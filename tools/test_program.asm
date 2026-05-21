; ============================================================
; test_program.asm  –  All-instruction verification (extended)
; Generate with:  python im_asm.py test_program.asm ../IMData.coe
; ============================================================
;
; Data memory (see test_data.dm):
;   E0=0xE0  value 10=0x000A    E1=0xE1  value 3=0x0003
;   E2=0xE2  value -1=0xFFFF    D0=0xD0  STORE target
;
; Expected encoding:
;   PC 00: 02E0  PC 01: 01D0  PC 02: 02E0  PC 03: 03E1
;   PC 04: 02E0  PC 05: 04E1  PC 06: 02E0  PC 07: 0AE1
;   PC 08: 02E0  PC 09: 0BE1  PC 0A: 02E0  PC 0B: 0C00
;   PC 0C: 0DE0  PC 0D: 0EE1  PC 0E: 02E0  PC 0F: 08E1
;   PC 10: 0612  PC 11: 0700  PC 12: 0514  PC 13: 0700
;   PC 14: 02E2  PC 15: 051C  PC 16: 02E0
;   PC 17: 092A  PC 18: 0F00  PC 19: 09FF  PC 1A: 0F01
;   PC 1B: 1000  PC 1C: 0700
;
; Expected final state after HALT at PC=0x1C:
;   PC        = 0x1D   (0x1C+1)
;   CAR       = 0x50
;   IR        = 0x07
;   ACC       = port_in[0]           (verified in testbench)
;   MR        = 0x0000               (MPY 10x3=30 fits in 16-bit)
;   port_out[0] = 0x002A = 42        (from LOADI 42 + OUT [0])
;   port_out[1] = 0xFFFF             (from LOADI 255 + OUT [1])
;
; PC=0x1D proves JMP (skip 0x11) and JMPGEZ-taken (skip 0x13)
; ACC=port_in[0] proves JMPGEZ-not-taken (IN[0] at 0x1B was reached)
; ============================================================

; ── Address symbol definitions ─────────────────────────────
E0 = 0xE0   ; 10 = 0x000A
E1 = 0xE1   ; 3  = 0x0003
E2 = 0xE2   ; -1 = 0xFFFF  (negative sentinel)
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
        LOAD   [E0]         ; PC=08  02E0  ACC = 10
        OR     [E1]         ; PC=09  0BE1  ACC = 11

; ── NOT ────────────────────────────────────────────────────
        LOAD   [E0]         ; PC=0A  02E0  ACC = 10
        NOT                 ; PC=0B  0C00  ACC = 0xFFF5

; ── SHIFTR ─────────────────────────────────────────────────
        SHIFTR [E0]         ; PC=0C  0DE0  ACC = DM[E0]>>1 = 5

; ── SHIFTL ─────────────────────────────────────────────────
        SHIFTL [E1]         ; PC=0D  0EE1  ACC = DM[E1]<<1 = 6

; ── MPY ────────────────────────────────────────────────────
        LOAD   [E0]         ; PC=0E  02E0  ACC = 10
        MPY    [E1]         ; PC=0F  08E1  {MR,ACC}=30; ACC=0x001E MR=0

; ── JMP: skip dead HALT at 0x11 ────────────────────────────
        JMP    [jmpok]      ; PC=10  0612
        HALT                ; PC=11  0700  dead

; ── JMPGEZ taken: ACC=0x001E, must jump ────────────────────
jmpok:  JMPGEZ [gezok]      ; PC=12  0514
        HALT                ; PC=13  0700  dead

; ── JMPGEZ not-taken: ACC=0xFFFF (negative), fall through ──
gezok:  LOAD   [E2]         ; PC=14  02E2  ACC = 0xFFFF
        JMPGEZ [done]       ; PC=15  051C  NOT taken → fall through
        LOAD   [E0]         ; PC=16  02E0  ACC = 10

; ── LOADI: load immediate (sign-extended) ──────────────────
        LOADI  42           ; PC=17  092A  ACC = 0x002A = 42

; ── OUT: ACC to peripheral port ────────────────────────────
        OUT    [0]          ; PC=18  0F00  port_out[0] = 0x002A

; ── LOADI negative (sign extension test) ───────────────────
        LOADI  255          ; PC=19  09FF  ACC = 0xFFFF (sext 0xFF)

; ── OUT port 1 ─────────────────────────────────────────────
        OUT    [1]          ; PC=1A  0F01  port_out[1] = 0xFFFF

; ── IN: peripheral port to ACC ─────────────────────────────
        IN     [0]          ; PC=1B  1000  ACC = port_in[0]

done:   HALT                ; PC=1C  0700
