; ============================================================
; test_data.dm  –  Data Memory for the 1+2+3+...+100 sum program
; Generate with:  python dm_gen.py test_data.dm ../DMData.coe
; ============================================================
; Memory layout (addresses 0xA0-0xA4):
;   A0 (0xA0) = 0      constant zero  (used to init sum)
;   A1 (0xA1) = 1      constant one   (used for temp--)
;   A2 (0xA2) = 100    constant limit (used to init temp)
;   A3 (0xA3) = 0      variable: temp (loop counter, overwritten at runtime)
;   A4 (0xA4) = 0      variable: sum  (accumulator,  overwritten at runtime)
;
; Expected result after HALT:  DM[0xA4] = 5050 = 0x13BA
; ============================================================

; --- Constants ---
0xA0 : 0x0000   ; A0: constant 0   (initial value of sum)
0xA1 : 0x0001   ; A1: constant 1   (decrement step for temp)
0xA2 : 0x0064   ; A2: constant 100 (0x64 = 100 decimal, initial value of temp)

; --- Variables (initial values, overwritten by program) ---
0xA3 : 0x0000   ; A3: temp  (will be set to 100, then decremented each loop)
0xA4 : 0x0000   ; A4: sum   (will accumulate 1+2+...+100 = 5050 = 0x13BA)
