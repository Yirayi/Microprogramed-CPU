# Microprogrammed CPU — Nexys A7 FPGA Implementation

A 16-bit, single-address, microprogrammed CPU implemented in Verilog for the Digilent Nexys A7-100T (Artix-7 xc7a100t), featuring a 640×480 VGA debug display, PS/2 keyboard instruction injection, and single-step debugging at both instruction and micro-operation granularity.

---

## Features

- 16-bit single-address ISA with 16 instructions (arithmetic, logic, shift, jump, I/O, immediate)
- Microprogrammed control unit: 32-bit microinstructions stored in 256-entry BRAM ROM
- Three execution modes: free-run, instruction-step, micro-step (selected by slide switches)
- 640×480 VGA debug display with four panels: live register state, static instruction listing, step history, and interactive keyboard input
- PS/2 keyboard: type and inject arbitrary instructions at runtime in instruction-step mode without disturbing the program counter
- 5-digit 7-segment decimal display driven by CPU output port 0
- 12-bit signed switch input routed to CPU input port 0
- Separate 256-word instruction memory, data memory, and microcode control memory (all Xilinx BRAM)
- Startup scan: instruction memory auto-populated to VGA listing panel before first execution

---

## Architecture Overview

### Module Hierarchy

```
ALL_top
 ├── CPU_top
 │    ├── ControlUnit      CAR sequencer, opcode dispatch, single-step gating, injection
 │    ├── ALU              Combinational 16-bit: ADD/SUB/AND/OR/NOT/SHL/SHR/MPY
 │    ├── ControlMemory    256×32 BRAM ROM — microcode
 │    ├── InstrMemory      256×16 BRAM ROM — program
 │    └── DataMemory       256×16 BRAM dual-port RAM — data
 ├── vga_display           640×480 driver, font ROM, 4 panels, keyboard parser, injector
 ├── PS2_receiver          Raw PS/2 frame decoder (start+data+parity+stop)
 ├── ps2_decoder           Set-2 scancode → font index; F0/E0 prefix handling
 ├── seven_seg_decimal     5-digit time-multiplexed 7-segment driver
 └── btn_debounce          2-stage synchronizer + edge detector for BTNC
```

### Signal Flow

Register writes occur on **posedge clk**; the Control Address Register (CAR) advances on **negedge clk**. This split-edge arrangement pipelines CAR sequencing so the new microinstruction address is stable before the next posedge register update.

A 209-bit `video_bus` carries all internal CPU registers (PC, MAR, MBR, IR, BR, ACC, MR, CAR, halted, exec_mode, port_out, port_in, micro_instr) to `vga_display` for live readout. Separately, `scan_wr_*` signals from `CPU_top` populate the VGA instruction listing during the startup scan phase.

---

## Instruction Set Architecture

### Instruction Encoding

```
Bits [15:8] — opcode    (8-bit)
Bits  [7:0] — operand   (DM address / branch target / immediate / port number)
```

### Instructions

| Opcode | Mnemonic  | Operand     | Operation                                  | Micro-start |
|--------|-----------|-------------|--------------------------------------------|-------------|
| 0x01   | STORE X   | DM address  | DM[X] ← ACC                               | 0x10        |
| 0x02   | LOAD X    | DM address  | ACC ← DM[X]                               | 0x20        |
| 0x03   | ADD X     | DM address  | ACC ← ACC + DM[X]                         | 0x30        |
| 0x04   | SUB X     | DM address  | ACC ← ACC − DM[X]                         | 0x38        |
| 0x05   | JMPGEZ X  | target addr | if ACC[15]=0 then PC ← X                 | 0x40        |
| 0x06   | JMP X     | target addr | PC ← X                                    | 0x48        |
| 0x07   | HALT      | —           | Freeze CPU (CAR locked)                   | 0x50        |
| 0x08   | MPY X     | DM address  | {MR, ACC} ← ACC × DM[X] (unsigned 32-bit)| 0x58        |
| 0x09   | LOADI imm | imm8        | ACC ← sign\_extend(imm8)                  | 0x90        |
| 0x0A   | AND X     | DM address  | ACC ← ACC & DM[X]                         | 0x68        |
| 0x0B   | OR X      | DM address  | ACC ← ACC \| DM[X]                        | 0x70        |
| 0x0C   | NOT       | —           | ACC ← ~ACC                                | 0x78        |
| 0x0D   | SHIFTR X  | DM address  | ACC ← DM[X] >> 1 (logical)               | 0x80        |
| 0x0E   | SHIFTL X  | DM address  | ACC ← DM[X] << 1 (logical)               | 0x88        |
| 0x0F   | OUT port  | port# 0–3   | port\_out[port] ← ACC                     | 0xA0        |
| 0x10   | IN port   | port# 0–3   | ACC ← port\_in[port]                      | 0xA8        |

**Notes:**
- JMPGEZ tests ACC[15] (sign bit); jump is taken when ACC ≥ 0 (bit 15 = 0)
- MPY is unsigned: ACC × DM[X] produces a 32-bit result; low 16 bits → ACC, high 16 bits → MR
- LOADI sign-extends the 8-bit operand field: range −128..+127 (encoded as 0x00..0xFF)
- OUT/IN use only operand bits [1:0] as the port selector

---

## Microarchitecture

### Microinstruction Format (32 bits)

Each entry in the 256-word control memory is a 32-bit word where individual bits directly gate register operations. Multiple bits may be set in one microinstruction to perform parallel transfers.

| Bit | Name | Micro-operation |
|-----|------|-----------------|
|  0  | C0   | CAR ← CAR + 1 |
|  1  | C1   | CAR ← dispatch(MBR[15:8]) |
|  2  | C2   | CAR ← 0x00 (return to fetch) |
|  3  | C3   | MBR ← IM[MAR] (during fetch) or DM[MAR] (during execute) |
|  4  | C4   | IR ← MBR[15:8] |
|  5  | C5   | MAR ← MBR[7:0] |
|  6  | C6   | PC ← PC + 1 |
|  7  | C7   | BR ← MBR |
|  8  | C8   | ACC ← 0x0000 |
|  9  | C9   | ACC ← ACC + BR |
| 10  | C10  | MAR ← PC |
| 11  | C11  | MBR ← ACC |
| 12  | C12  | DM[MAR] ← MBR |
| 13  | C13  | ACC ← ACC − BR |
| 14  | C14  | ACC ← ACC & BR |
| 15  | C15  | ACC ← ACC \| BR |
| 16  | C16  | ACC ← ~ACC |
| 17  | C17  | ACC ← BR >> 1 (logical) |
| 18  | C18  | ACC ← BR << 1 (logical) |
| 19  | C19  | {MR, ACC} ← ACC × BR (unsigned 32-bit) |
| 20  | C20  | ACC ← BR |
| 21  | C21  | HALT — freeze CAR; no further advance |
| 22  | C22  | PC ← MAR |
| 23  | C23  | if ACC[15]=0: PC ← MAR |
| 24  | C24  | ACC ← sign\_extend(MAR[7:0]) |
| 25  | C25  | port\_out[MAR[1:0]] ← ACC |
| 26  | C26  | MBR ← port\_in[MAR[1:0]] |
| 27–31 | — | Reserved (must be 0) |

CAR update priority: **C2 > C1 > C0 > no change** (HALT).

### Fetch-Execute Cycle

Every instruction begins with the same 3-microinstruction fetch sequence:

```
CAR=0x00  C10, C0         MAR ← PC;                        CAR ← CAR+1
CAR=0x01  C3,  C0         MBR ← IM[MAR];                   CAR ← CAR+1
CAR=0x02  C4, C5, C6, C1  IR←MBR[15:8]; MAR←MBR[7:0]; PC←PC+1; CAR←dispatch(IR)
```

After fetch T3, CAR jumps to the instruction-specific execute sequence. Example — LOAD X (3 execute cycles):

```
CAR=0x20  C3,  C0    MBR ← DM[MAR];   CAR ← CAR+1
CAR=0x21  C7,  C0    BR  ← MBR;       CAR ← CAR+1
CAR=0x22  C20, C2    ACC ← BR;         CAR ← 0x00 (return to fetch)
```

### Opcode Dispatch Table

| Opcode | Mnemonic | CAR start |   | Opcode | Mnemonic | CAR start |
|--------|----------|-----------|---|--------|----------|-----------|
| 0x01   | STORE    | 0x10      |   | 0x09   | LOADI    | 0x90      |
| 0x02   | LOAD     | 0x20      |   | 0x0A   | AND      | 0x68      |
| 0x03   | ADD      | 0x30      |   | 0x0B   | OR       | 0x70      |
| 0x04   | SUB      | 0x38      |   | 0x0C   | NOT      | 0x78      |
| 0x05   | JMPGEZ   | 0x40      |   | 0x0D   | SHIFTR   | 0x80      |
| 0x06   | JMP      | 0x48      |   | 0x0E   | SHIFTL   | 0x88      |
| 0x07   | HALT     | 0x50      |   | 0x0F   | OUT      | 0xA0      |
| 0x08   | MPY      | 0x58      |   | 0x10   | IN       | 0xA8      |

### Timing

| Event | Clock edge |
|-------|------------|
| Register writes (PC, MAR, MBR, IR, BR, ACC, MR, port_out) | posedge clk |
| CAR advance | negedge clk |
| BRAM output register | posedge \~clk (= negedge clk) |

All three BRAMs (CM, IM, DM) use `clks = ~clk` so their registered outputs are stable at the next posedge clk, aligning with register capture. The fetch cycle's 3-step structure accounts for the 1-cycle BRAM output latency: the address presented at T1 yields valid data captured at T2.

---

## Register File

| Register | Width  | Description |
|----------|--------|-------------|
| PC       | 8-bit  | Program counter; incremented at fetch T3 (C6); loaded by JMP (C22) or JMPGEZ (C23) |
| MAR      | 8-bit  | Memory address register; loaded from PC (C10) at fetch T1 or from MBR[7:0] (C5) at fetch T3 |
| MBR      | 16-bit | Memory buffer; captures IM[MAR] at fetch T2, DM[MAR] during execute, or ACC (C11) / port (C26) |
| IR       | 8-bit  | Instruction register; holds opcode = MBR[15:8], loaded by C4 |
| BR       | 16-bit | Buffer register; ALU second operand; loaded from MBR by C7 |
| ACC      | 16-bit | Accumulator; result of all ALU and data-move operations; source for OUT |
| MR       | 16-bit | Multiply result high word; written only by MPY (C19); readable via VGA debug bus |
| CAR      | 8-bit  | Control address register; indexes the microcode ROM |

---

## Memory System

| Memory       | Size       | Type               | Init file    | Clock  |
|--------------|------------|--------------------|--------------|--------|
| Control (CM) | 256 × 32 b | BRAM ROM           | CMData.coe   | clk    |
| Instruction (IM) | 256 × 16 b | BRAM ROM       | IMData.coe   | ~clk   |
| Data (DM)    | 256 × 16 b | BRAM dual-port RAM | DMData.coe   | ~clk   |

- DM write port (A) is gated by C12; read port (B) is always active
- IM address is multiplexed: `scan_addr` during the startup scan, `MAR` during normal execution
- **Startup scan**: `CPU_top` holds the CPU in reset and reads IM sequentially into the VGA instruction-listing buffer; scan terminates at the first HALT opcode (0x07) or address 0xFF

---

## ALU

Nine operations, each selected by one or more C-bits in the active microinstruction:

| C-bit | Operation   | Expression             | Notes |
|-------|-------------|------------------------|-------|
| C9    | ADD         | ACC + BR               | |
| C13   | SUB         | ACC − BR               | |
| C14   | AND         | ACC & BR               | |
| C15   | OR          | ACC \| BR              | |
| C16   | NOT         | ~ACC                   | Single-operand |
| C17   | SHIFTR      | BR >> 1                | Logical; zero-fills MSB |
| C18   | SHIFTL      | BR << 1                | Logical; zero-fills LSB |
| C19   | MPY         | ACC × BR (unsigned)    | 32-bit result → {MR, ACC} |
| C20   | PASS\_B     | BR                     | Used for ACC ← BR loads |

There is no flag register. The only condition tested externally is ACC[15] (sign bit), which JMPGEZ uses via C23.

---

## Execution Modes & Debugging

### Mode Selection (SW[15:14])

| SW[15:14] | Mode         | Behavior |
|-----------|--------------|----------|
| `00`      | Free-run     | CPU executes continuously at full 100 MHz speed |
| `01`      | Instr-step   | CPU pauses after completing each instruction; press BTNC to advance one instruction |
| `10`      | Micro-step   | CPU pauses after each microinstruction; press BTNC to advance one CAR step |

### Step History (Left VGA Panel)

- **Instr-step**: Each BTNC press captures IR[7:0] and MAR[7:0] at the instruction boundary, displayed as the decoded mnemonic and operand.
- **Micro-step**: Each BTNC press captures the pre-advance CAR value, displayed as a hex address and a descriptive label (e.g., `MAR<=PC`, `MBR<=IM[MAR]`, `ACC<=ACC+BR`).
- Both modes use a 32-entry ring buffer; entries display oldest-first (row 0 = oldest).

---

## VGA Display (640×480 @ 60 Hz)

### Screen Layout

```
 x=0        x=384  x=392  x=512 x=514    x=640
  ┌──────────┬──────┬───────────┬─────────┐  y=0
  │          │      │           │         │
  │  Left    │      │  Middle   │  Right  │
  │  Panel   │ sep  │  Panel    │  Panel  │
  │  Step    │      │  Static   │  Regs   │
  │  History │      │  Instr    │  +Ports │
  │  32 rows │      │  Listing  │         │  y=255
  ├──────────┤      │           ├─────────┤
  │          │      │           │         │
  │  Bottom- │      │  (inst    │         │
  │  Left    │      │  listing  │ (blank) │
  │  Panel   │      │ continues)│         │
  │  KB input│      │           │         │
  │  +history│      │           │         │
  └──────────┴──────┴───────────┴─────────┘  y=479
```

### Panel Details

**Left panel** (x=0–383, y=0–255, 48 chars × 32 rows)
Step history ring buffer. In instr-step mode: mnemonic + operand per instruction executed. In micro-step mode: CAR hex + micro-op label per step. Text turns red when CPU is halted.

**Middle panel** (x=392–511, y=0–479)
Static instruction memory listing populated at startup. Format per row:
```
> AA MMMMMM [OO]
```
`AA` = address (hex), `MMMMMM` = mnemonic (6 chars), `OO` = operand (hex). The row corresponding to the current PC is highlighted in green; the panel scrolls to keep it visible.

**Right panel** (x=514–639, y=8–159, 15 chars × 19 rows)
Live register display, updated every frame:
- PC, MAR, IR, CAR — 2-digit hex (8-bit)
- MBR, BR, ACC, MR — 4-digit hex (16-bit)
- MI (current microinstruction) — 8-digit hex (32-bit)
- exec\_mode, HALT status
- PO0–PO3 (port\_out[0..3]), PI0 (port\_in[0]) — 4-digit hex

**Bottom-left panel** (x=0–383, y=256–479)
Interactive keyboard input area:
- Top 16 rows: command history (typed instructions and error messages)
- Separator line of dashes
- Input prompt with blinking cursor (up to 32 characters)
- Debug row showing last raw PS/2 scan code received

### Display Parameters

| Parameter | Value |
|-----------|-------|
| Resolution | 640×480 |
| Refresh rate | 60 Hz |
| Pixel clock | 25 MHz (100 MHz ÷ 4) |
| H timing | ACT=640, FP=16, SYNC=96, BP=48 |
| V timing | ACT=480, FP=10, SYNC=2, BP=33 |
| Color depth | 12-bit (4-bit per channel) |
| Sync polarity | Active-low |
| Font | 47 characters, 8×8 px, LSB-first, distributed ROM |

---

## PS/2 Keyboard & Instruction Injection

### Supported Characters

| Category | Characters |
|----------|------------|
| Letters | A–Z (26) |
| Digits | 0–9 (10) |
| Symbols | Space, `[`, `]` |
| Special | Enter (confirm/execute), Backspace (delete), Tab (switch focus) |

### Instruction Syntax

Instructions are entered in plain text and parsed on Enter:

| Format       | Example        | Applicable instructions |
|--------------|----------------|-------------------------|
| `MNE [N]`    | `LOAD [34]`    | STORE, LOAD, ADD, SUB, JMPGEZ, JMP, MPY, AND, OR, SHIFTR, SHIFTL (N = 0–255) |
| `MNE [N]`    | `OUT [0]`      | OUT, IN (N = 0–3) |
| `LOADI N`    | `LOADI 42`     | LOADI (N = 0–255, sign-extended by CPU) |
| `MNE`        | `HALT`         | HALT, NOT |

Validation errors are written to the command history panel:

| Error message  | Cause |
|----------------|-------|
| `ERR UNKNOWN`  | Mnemonic not recognized |
| `ERR FORMAT`   | Wrong syntax (missing space, brackets, or digits) |
| `ERR RANGE`    | Operand out of valid range (e.g., port > 3) |

### Injection Mechanism

Injection is available **only in instruction-step mode** (`SW[15:14]=01`) when the CPU is not halted. It runs one complete fetch-execute cycle for the typed instruction without advancing the program counter.

**Cycle trace:**

```
Cycle N:     inj_req asserts → inject_trigger fires (1-shot rising-edge detect)
             can_step=1; CAR: 0x00→0x01; instr_running=1, injecting=1
Cycle N+1:   CAR=0x01, C3 fires: MBR ← inject_instr  (overrides IM[MAR])
Cycle N+2:   CAR=0x02, C4/C5/C1 fire: IR←opcode, MAR←operand, CAR→dispatch(IR)
             C6 (PC+1) is SUPPRESSED while injecting=1 → PC unchanged
Cycle N+k:   Execute micro-cycles proceed normally (DM reads, ALU, register writes)
Cycle N+k+1: C2 fires → inject_done pulses; injecting=0; CAR→0x00
Cycle N+k+2: vga_display sees inject_done, clears inj_req; CPU pauses at CAR=0x00
```

PC is preserved because C6 is gated by `!injecting_w` in `CPU_top`. After injection completes, the next BTNC press resumes the original program from the same PC.

**Signal path:** `vga_display` → (`inj_req`, `inj_instr[15:0]`) → `CPU_top` → `ControlUnit`; `inject_done` returns on the same path.

---

## I/O Ports & Peripherals

### CPU I/O Ports

| Port | Direction | Source / Destination |
|------|-----------|----------------------|
| port\_in[0] | Input | SW[11:0] sign-extended to 16 bits |
| port\_in[1..3] | Input | Tied to 0x0000 |
| port\_out[0] | Output | 7-segment decimal display |
| port\_out[1..3] | Output | Available on VGA right panel only |

### 7-Segment Display

- Shows `port_out[0]` as unsigned decimal (0–65535), 5 digits
- Common-anode display, active-low; AN[5..7] permanently blanked
- Multiplexing refresh: ~191 Hz; per-digit period: ~655 µs

### Slide Switches as Input

SW[11:0] is treated as a 12-bit signed integer and sign-extended to 16 bits before being presented to the CPU as `port_in[0]`. An IN instruction with operand 0 reads this value into ACC.

---

## Board & Pin Assignments

**Target device:** Digilent Nexys A7-100T — `xc7a100tcsg324-1`  
**Toolchain:** Vivado 2023.2

### Clock & Reset

| Signal | Pin | Description |
|--------|-----|-------------|
| `clk` | E3 | 100 MHz board oscillator |
| `reset_btn` | C12 | CPU\_RESETN — active-low push-button |

### Push Button

| Signal | Pin | Description |
|--------|-----|-------------|
| `btn_step` | N17 | BTNC — active-high single-step trigger |

### Slide Switches

| Signal | Pin | Signal | Pin |
|--------|-----|--------|-----|
| sw[0]  | J15 | sw[8]  | T8  |
| sw[1]  | L16 | sw[9]  | U8  |
| sw[2]  | M13 | sw[10] | R16 |
| sw[3]  | R15 | sw[11] | T13 |
| sw[4]  | R17 | sw[12] | H6  |
| sw[5]  | T18 | sw[13] | U12 |
| sw[6]  | U18 | sw[14] | U11 |
| sw[7]  | R13 | sw[15] | V10 |

sw[15:14] = exec\_mode; sw[11:0] = port\_in[0] data.

### 7-Segment Display

| Signal | Pins (AN[7]→AN[0]) |
|--------|--------------------|
| AN[7:0] | U13, K2, T14, P14, J14, T9, J18, J17 |

| Signal | Pins (SEG[6]→SEG[0]) — {a,b,c,d,e,f,g} |
|--------|------------------------------------------|
| SEG[6:0] | T10, R10, K16, K13, P15, T11, L18 |

### VGA

| Signal | Pins |
|--------|------|
| `vga_hs` | B11 |
| `vga_vs` | B12 |
| `vga_r[3:0]` | A4, C5, B4, A3 |
| `vga_g[3:0]` | A6, B6, A5, C6 |
| `vga_b[3:0]` | D8, D7, C7, B7 |

### PS/2 Keyboard

| Signal | Pin | Notes |
|--------|-----|-------|
| `ps2_clk` | F4 | Open-drain; PULLUP enabled |
| `ps2_data` | B2 | Open-drain; PULLUP enabled |

Internal FPGA pull-ups are required. Without them, idle-state detection fails (lines float low).

---

## Source Files

### Verilog Modules

| File | Description |
|------|-------------|
| `ALL_top.v` | Top-level: instantiates all modules; 2-stage switch synchronizer; injection wire routing |
| `CPU_top.v` | CPU datapath: register file, BRAM instantiations, microinstruction decode, port I/O, startup scan FSM, injection MBR mux and PC suppression |
| `ControlUnit.v` | CAR sequencer: dispatch table, C0/C1/C2 priority, single-step gating (`can_step`), injection edge-detect, `inject_done` pulse |
| `ALU.v` | Combinational 16-bit ALU; 9 operations; unsigned 32-bit multiply |
| `vga_display.v` | 640×480 VGA driver; 8×8 font ROM (47 chars); 4 display panels; PS/2 keyboard buffer; instruction parser; injection state machine |
| `PS2_receiver.v` | PS/2 frame receiver: 11-bit shift register, odd-parity check, 1 ms timeout recovery |
| `ps2_decoder.v` | PS/2 Set-2 → 6-bit font index; handles F0 (break) and E0 (extended) prefixes |
| `seven_seg_decimal.v` | 5-digit decimal multiplexer; ~191 Hz refresh; AN[5..7] blanked |
| `btn_debounce.v` | 2-stage synchronizer + ~10.5 ms stable-time counter; outputs single-cycle rising-edge pulse |

### Memory Initialization Files (COE format)

| File | Contents |
|------|----------|
| `CMData.coe` | 256 × 32-bit microcode ROM (microinstruction for each CAR address) |
| `IMData.coe` | 256 × 16-bit instruction program (default demo) |
| `DMData.coe` | 256 × 16-bit initial data memory |

### Alternative Programs (`Memory/`)

| Directory | Program |
|-----------|---------|
| `Memory/1sumto100/` | Sum integers 1..100; result left in ACC |
| `Memory/1sumtoX/`   | Sum integers 1..X where X is read from port\_in[0] (SW[11:0]) |
| `Memory/InstTest/`  | Instruction test suite covering all 16 opcodes |

To use an alternative program, copy its `IMData.coe` (and `DMData.coe` if present) over the root-level files before synthesizing, or update the BRAM IP core `.coe` paths in Vivado and regenerate.

---

## Getting Started

### Requirements

- Vivado 2023.2 (or a compatible version that supports Artix-7)
- Digilent Nexys A7-100T board
- PS/2 keyboard (optional — required only for instruction injection)
- VGA monitor (optional — required only for debug display)

### Build & Program

1. Open `CPU.xpr` in Vivado.
2. *(Optional)* To load a different program, replace `IMData.coe` / `DMData.coe` with files from `Memory/<program>/`.
3. Run **Flow → Generate Bitstream** (synthesis + implementation are run automatically).
4. Connect the board, open **Hardware Manager**, and program the device.

### Operating the Board

| Control | Setting | Effect |
|---------|---------|--------|
| SW[15:14] | `00` | Free-run: CPU executes continuously after RESETN |
| SW[15:14] | `01` | Instruction-step: BTNC advances one instruction |
| SW[15:14] | `10` | Micro-step: BTNC advances one microinstruction |
| SW[11:0] | any | Sets the value returned by `IN [0]` (12-bit signed) |
| RESETN (C12) | press | Resets CPU and all peripherals; re-runs startup scan |
| BTNC (N17) | press | Single-step trigger (debounced; one pulse per press) |

### Keyboard Instruction Injection (Instruction-Step Mode Only)

1. Set SW[15:14] = `01`.
2. Press RESETN; wait for the VGA instruction listing to appear (startup scan complete).
3. Step through the program with BTNC as needed.
4. Type an instruction on the PS/2 keyboard (e.g., `LOADI 42`) and press Enter.
   - If valid: the instruction executes once; ACC (or the target register) updates; PC is unchanged.
   - If invalid: an error message appears in the command history panel.
5. Continue stepping with BTNC; the CPU resumes from the original PC.

**Examples:**

```
LOADI 42          Load immediate 0x2A into ACC
LOAD [224]        Load DM[0xE0] (decimal 10) into ACC
ADD [225]         ACC = ACC + DM[0xE1]
STORE [208]       Write ACC to DM[0xD0]
OUT [0]           Display ACC on 7-segment display
HALT              Freeze the CPU
```
