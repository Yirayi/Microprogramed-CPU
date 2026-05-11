; ============================================================
; test_data.dm  –  Data Memory for all-instruction verification
; Generate with:  python dm_gen.py test_data.dm ../DMData.coe
; ============================================================
; Memory layout:
;   E0 (0xE0) = 0x000A = 10   input operand A
;   E1 (0xE1) = 0x0003 =  3   input operand B
;   E2 (0xE2) = 0xFFFF = -1   negative sentinel (for JMPGEZ not-taken test)
;   D0 (0xD0) = 0x0000         STORE result (written at runtime)
; ============================================================

; --- Inputs (read-only constants) ---
0xE0 : 0x000A   ; A = 10
0xE1 : 0x0003   ; B = 3
0xE2 : 0xFFFF   ; negative = -1

; --- Output scratch ---
0xD0 : 0x0000   ; written by STORE [D0] in program
