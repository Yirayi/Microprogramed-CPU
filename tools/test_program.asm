; ============================================================
; test_program.asm  –  All-instruction verification
; Generate with:  python im_asm.py test_program.asm ../IMData.coe
; ============================================================
;
; Exercises every instruction once and checks the final CPU state.
;
; Data memory (see test_data.dm):
;   E0 = 0xE0  value 10 = 0x000A
;   E1 = 0xE1  value  3 = 0x0003
;   E2 = 0xE2  value -1 = 0xFFFF  (negative sentinel)
;   D0 = 0xD0  STORE target
;
; Expected encoding:
;   PC 00: 02E0  PC 01: 01D0  PC 02: 02E0  PC 03: 03E1
;   PC 04: 02E0  PC 05: 04E1  PC 06: 02E0  PC 07: 0AE1
;   PC 08: 02E0  PC 09: 0BE1  PC 0A: 02E0  PC 0B: 0C00
;   PC 0C: 0DE0  PC 0D: 0EE1  PC 0E: 02E0  PC 0F: 08E1
;   PC 10: 0612  PC 11: 0700  PC 12: 0514  PC 13: 0700
;   PC 14: 02E2  PC 15: 0517  PC 16: 02E0  PC 17: 0700
;
; Expected final state after HALT at PC=0x17:
;   PC  = 0x18  (HALT at 0x17, PC incremented during fetch T3)
;   CAR = 0x50  (frozen at HALT microcode entry)
;   IR  = 0x07  (HALT opcode)
;   ACC = 0x000A  (LOAD[E0] at 0x16: JMPGEZ-not-taken path executed)
;   MR  = 0x0000  (MPY 10*3=30 fits in 16-bit ACC)
;
; PC=0x18 implicitly verifies:
;   JMP    at 0x10 jumped correctly  (dead HALT at 0x11 was skipped)
;   JMPGEZ at 0x12 taken correctly   (dead HALT at 0x13 was skipped)
; ACC=0x000A verifies JMPGEZ at 0x15 was NOT taken (negative operand)
; ============================================================

; ── Address symbol definitions ─────────────────────────────
E0 = 0xE0   ; 10
E1 = 0xE1   ; 3
E2 = 0xE2   ; -1 (negative sentinel)
D0 = 0xD0   ; STORE scratch

; ── LOAD / STORE ───────────────────────────────────────────
        LOAD   [E0]         ; PC=00  02E0  ACC = 10
        STORE  [D0]         ; PC=01  01D0  DM[D0] = 10

; ── ADD ────────────────────────────────────────────────────
        LOAD   [E0]         ; PC=02  02E0  ACC = 10
        ADD    [E1]         ; PC=03  03E1  ACC = 13

; ── SUB ────────────────────────────────────────────────────
        LOAD   [E0]         ; PC=04  02E0  ACC = 10
        SUB    [E1]         ; PC=05  04E1  ACC = 7

; ── AND ────────────────────────────────────────────────────
        LOAD   [E0]         ; PC=06  02E0  ACC = 10 = 0b1010
        AND    [E1]         ; PC=07  0AE1  ACC =  2 = 0b0010

; ── OR ─────────────────────────────────────────────────────
        LOAD   [E0]         ; PC=08  02E0  ACC = 10 = 0b1010
        OR     [E1]         ; PC=09  0BE1  ACC = 11 = 0b1011

; ── NOT ────────────────────────────────────────────────────
        LOAD   [E0]         ; PC=0A  02E0  ACC = 10 = 0x000A
        NOT                 ; PC=0B  0C00  ACC = 0xFFF5 = ~0x000A

; ── SHIFTR ─────────────────────────────────────────────────
        SHIFTR [E0]         ; PC=0C  0DE0  ACC = DM[E0]>>1 = 5

; ── SHIFTL ─────────────────────────────────────────────────
        SHIFTL [E1]         ; PC=0D  0EE1  ACC = DM[E1]<<1 = 6

; ── MPY ────────────────────────────────────────────────────
        LOAD   [E0]         ; PC=0E  02E0  ACC = 10
        MPY    [E1]         ; PC=0F  08E1  {MR,ACC} = 10*3 = 30; ACC=0x001E MR=0

; ── JMP: must skip dead HALT at 0x11 ───────────────────────
        JMP    [jmpok]      ; PC=10  0612
        HALT                ; PC=11  0700  dead – skipped if JMP works

; ── JMPGEZ taken: ACC=0x001E (positive), must jump ─────────
jmpok:  JMPGEZ [gezok]      ; PC=12  0514
        HALT                ; PC=13  0700  dead – skipped if JMPGEZ-taken works

; ── JMPGEZ not-taken: ACC=0xFFFF (negative), must fall through
gezok:  LOAD   [E2]         ; PC=14  02E2  ACC = 0xFFFF
        JMPGEZ [done]       ; PC=15  0517  NOT taken (ACC[15]=1) → fall through
        LOAD   [E0]         ; PC=16  02E0  ACC = 10  ← proves not-taken path ran

done:   HALT                ; PC=17  0700  ACC=0x000A if correct, 0xFFFF if JMPGEZ wrongly taken
