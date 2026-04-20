; ============================================================
; test_data.dm  –  Data Memory source for the test program
; Generate with:  python dm_gen.py test_data.dm ../DMData.coe
; ============================================================
; Format:  address : value   ; optional comment
; Address and value may be hex (0x..) or decimal.
; Only the entries listed here are written; all other
; addresses are initialised to 0x0000.
; ============================================================

; --- Operands ---
0xF0 : 0x0005   ; A = 5  (used by LOAD, SUB, AND, SHIFTR, SHIFTL)
0xF1 : 0x0003   ; B = 3  (used by ADD, OR, MPY)

; --- Scratch area ---
0xF2 : 0x0000   ; scratch  (written by STORE, unused initial value)
