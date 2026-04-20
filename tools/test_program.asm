; ============================================================
; test_program.asm  –  Test program exercising all 13 instructions
; Generate with:  python im_asm.py test_program.asm ../IMData.coe
; ============================================================
; Assumes data memory is pre-loaded (see test_data.dm):
;   DM[A]       = 5
;   DM[B]       = 3
;   DM[scratch] = 0  (will be written by STORE)
;
; Expected final state after HALT:
;   ACC = 0x001E (30)   MR = 0x0000   PC = 0x0F
; ============================================================

; ── Address symbol definitions ─────────────────────────────
; Format:  SYMBOL = address   (hex or decimal)

A       = 0xF0   ; operand A in data memory
B       = 0xF1   ; operand B in data memory
scratch = 0xF2   ; scratch location in data memory

; ── Code ───────────────────────────────────────────────────
; Instructions begin at PC = 0x00.
; Labels are written as  name:  and resolve to the current PC.
; All memory operands must be enclosed in [].

        LOAD   [A]          ; ACC = DM[A] = 5
        ADD    [B]          ; ACC = 5 + 3 = 8
        STORE  [scratch]    ; DM[scratch] = 8
        SUB    [A]          ; ACC = 8 - 5 = 3
        AND    [A]          ; ACC = 3 & 5 = 1  (011 & 101)
        OR     [B]          ; ACC = 1 | 3 = 3  (001 | 011)
        NOT                 ; ACC = ~3 = 0xFFFC
        SHIFTR [A]          ; ACC = DM[A] >> 1 = 5 >> 1 = 2
        SHIFTL [A]          ; ACC = DM[A] << 1 = 5 << 1 = 10
        MPY    [B]          ; {MR,ACC} = 10 * 3 = 30 (0x001E), MR=0
        JMPGEZ [end_ok]     ; ACC = 30 >= 0  →  jump taken to end_ok
        HALT                ; (skipped because JMPGEZ was taken)
end_ok: JMP    [end]        ; unconditional jump to end
dead:   HALT                ; (dead code – never reached)
end:    HALT                ; normal program end
