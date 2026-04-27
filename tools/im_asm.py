#!/usr/bin/env python3
"""
im_asm.py  –  Two-pass assembler: mnemonic source → IMData.coe.

Input file format  (.asm):
    ; Full-line comment  (# also accepted)

    ; ── Address symbol definitions (top of file, before any instruction) ──
    SYMBOL = 0xADDR   ; comment      ← binds a name to a fixed address
    SYMBOL = DECIMAL  ; comment

    ; ── Code (starts at PC = 0x00) ──
    [LABEL:]  MNEMONIC  [OPERAND]   ; comment
    [LABEL:]                         ; label-only line

Rules:
  • Operands MUST be written as  [NAME]  or  [0xNN]  or  [N]
    (square brackets signal indirect / memory addressing).
  • Instructions with no architectural operand (HALT, NOT) must have none.
  • A code label  name:  implicitly defines the symbol to the current PC.
  • Symbol definitions at the top and code labels share one namespace;
    a later definition silently shadows an earlier one.

Supported mnemonics:
    LOAD  STORE  ADD  SUB  AND  OR  NOT  SHIFTR  SHIFTL  MPY  JMP  JMPGEZ  HALT

Usage:
    python im_asm.py <source.asm> [output.coe]

    Default output filename: IMData.coe
"""

import sys
import re
import os

# ── Opcode table ──────────────────────────────────────────────────────────────
OPCODES = {
    'STORE':  0x01,
    'LOAD':   0x02,
    'ADD':    0x03,
    'SUB':    0x04,
    'JMPGEZ': 0x05,
    'JMP':    0x06,
    'HALT':   0x07,
    'MPY':    0x08,
    'AND':    0x0A,
    'OR':     0x0B,
    'NOT':    0x0C,
    'SHIFTR': 0x0D,
    'SHIFTL': 0x0E,
}
NO_OPERAND = {'HALT', 'NOT'}

# ── Helpers ───────────────────────────────────────────────────────────────────

def parse_int(s: str) -> int:
    s = s.strip()
    if re.fullmatch(r'0[xX][0-9A-Fa-f]+', s):
        return int(s, 16)
    return int(s, 10)


# ── Parser ────────────────────────────────────────────────────────────────────

def parse_source(path: str):
    """
    Parse the source file into:
        symbols  : dict  name -> int
        raw      : list of (lineno, label|None, mnemonic|None, operand_str|None, comment|None)
    """
    symbols = {}
    raw     = []
    in_code = False

    with open(path, encoding='utf-8') as f:
        src_lines = f.readlines()

    for lineno, line_raw in enumerate(src_lines, 1):
        line = line_raw.rstrip('\n').strip()
        if not line or line[0] in (';', '#'):
            continue

        # Peel off inline comment
        comment = None
        if ';' in line:
            ci      = line.index(';')
            comment = line[ci + 1:].strip() or None
            line    = line[:ci].strip()
        if not line:
            continue

        # ── Symbol definition?  NAME = value  (only before first code line) ──
        m = re.fullmatch(r'([A-Za-z_]\w*)\s*=\s*(.+)', line)
        if m and not in_code:
            name, val_s = m.group(1), m.group(2).strip()
            try:
                symbols[name] = parse_int(val_s)
            except ValueError:
                sys.exit(f'[ERROR] {path}:{lineno}: bad symbol value "{val_s}"')
            continue

        # ── Code line ──────────────────────────────────────────────────────
        in_code = True

        # Optional leading label   name:
        label = None
        m = re.match(r'^([A-Za-z_]\w*)\s*:(.*)', line)
        if m:
            label = m.group(1)
            line  = m.group(2).strip()

        if not line:
            # Label-only line – valid
            raw.append((lineno, label, None, None, comment))
            continue

        # Mnemonic [operand]
        parts    = line.split(None, 1)
        mnemonic = parts[0].upper()
        if mnemonic not in OPCODES:
            sys.exit(f'[ERROR] {path}:{lineno}: unknown mnemonic "{mnemonic}"')

        operand_s = None
        if len(parts) > 1:
            rest = parts[1].strip()
            m = re.fullmatch(r'\[([^\]]+)\]', rest)
            if not m:
                sys.exit(f'[ERROR] {path}:{lineno}: operand must be in [brackets], got "{rest}"')
            operand_s = m.group(1).strip()

        if mnemonic not in NO_OPERAND and operand_s is None:
            sys.exit(f'[ERROR] {path}:{lineno}: {mnemonic} requires an operand [addr]')
        if mnemonic in NO_OPERAND and operand_s is not None:
            print(f'[WARN]  {path}:{lineno}: {mnemonic} does not use an operand – ignored')
            operand_s = None

        raw.append((lineno, label, mnemonic, operand_s, comment))

    return symbols, raw


# ── Two-pass assembly ─────────────────────────────────────────────────────────

def assemble(path: str):
    symbols, raw = parse_source(path)

    # ── Pass 1: walk code lines and assign PC addresses to labels ───────────
    pc = 0
    for _lineno, label, mnemonic, _op, _cmt in raw:
        if label is not None:
            if label in symbols:
                print(f'[WARN]  label "{label}" at PC=0x{pc:02X} '
                      f'shadows existing symbol 0x{symbols[label]:02X}')
            symbols[label] = pc
        if mnemonic is not None:
            pc += 1

    total = pc
    if total > 256:
        sys.exit(f'[ERROR] program too large ({total} instructions, max 256)')
    if total == 0:
        print('[WARN]  empty program – generating 256 NOP (0000) entries')

    # ── Pass 2: encode instructions ─────────────────────────────────────────
    instrs   = []   # list of 16-bit ints
    comments = []   # parallel comment strings (or None)
    labels_at = {}  # pc -> list[str]

    cur_pc = 0
    for lineno, label, mnemonic, operand_s, comment in raw:
        if label is not None:
            labels_at.setdefault(cur_pc, []).append(label)
        if mnemonic is None:
            continue

        opcode  = OPCODES[mnemonic]
        operand = 0

        if operand_s is not None:
            if re.fullmatch(r'[A-Za-z_]\w*', operand_s):
                if operand_s not in symbols:
                    sys.exit(f'[ERROR] {path}:{lineno}: undefined symbol "{operand_s}"')
                operand = symbols[operand_s]
            else:
                try:
                    operand = parse_int(operand_s)
                except ValueError:
                    sys.exit(f'[ERROR] {path}:{lineno}: bad operand "{operand_s}"')

        if not 0 <= operand <= 255:
            sys.exit(f'[ERROR] {path}:{lineno}: operand {operand:#04x} out of 0-0xFF range')

        instrs.append((opcode << 8) | operand)
        comments.append(comment)
        cur_pc += 1

    return instrs, comments, labels_at, symbols


# ── COE generation ────────────────────────────────────────────────────────────

def generate_coe(instrs, comments, labels_at, symbols, src_name: str) -> list:
    total = len(instrs)
    out   = [
        '; Instruction Memory initialization  (auto-generated by im_asm.py)',
        f'; Source: {src_name}',
        ';',
        'memory_initialization_radix=16;',
        'memory_initialization_vector=',
    ]

    # ── Emit assembled instructions ──────────────────────────────────────────
    for pc in range(total):
        if pc in labels_at:
            out.append(f'; [{", ".join(labels_at[pc])}]')
        cmt = comments[pc]
        if cmt:
            out.append(f'; PC=0x{pc:02X}: {cmt}')
        # separator: "," unless this is the absolute last of all 256 entries
        sep = ';' if pc == 255 else ','
        out.append(f'{instrs[pc]:04X}{sep}')

    # ── Zero-pad to 256 entries ───────────────────────────────────────────────
    if total < 256:
        padding = 256 - total
        lbl     = f'0x{total:02X}' if padding == 1 else f'0x{total:02X}-0xFF'
        out.append(f'; {lbl}: unused')
        for k in range(0, padding, 8):
            chunk_size = min(8, padding - k)
            is_last    = (k + chunk_size >= padding)
            out.append(', '.join(['0000'] * chunk_size) + (';' if is_last else ','))

    return out


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        sys.exit(f'Usage: {sys.argv[0]} <source.asm> [output.coe]')

    src  = sys.argv[1]
    dest = sys.argv[2] if len(sys.argv) > 2 else 'IMData.coe'

    instrs, comments, labels_at, symbols = assemble(src)
    total = len(instrs)
    lines = generate_coe(instrs, comments, labels_at, symbols, os.path.basename(src))

    with open(dest, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')

    # Print symbol table
    sym_info = ', '.join(f'{k}=0x{v:02X}' for k, v in sorted(symbols.items(), key=lambda x: x[1]))
    print(f'[OK] {dest}  ({total} instructions, {256 - total} padding zeros)')
    print(f'     symbols: {sym_info}')


if __name__ == '__main__':
    main()
