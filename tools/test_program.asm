; ============================================================
; test_program.asm  –  Sum 1+2+3+...+100
; Generate with:  python im_asm.py test_program.asm ../IMData.coe
; ============================================================
;
; C equivalent:
;   sum = 0;
;   temp = 100;
;   do { sum = sum + temp; temp = temp - 1; } while (temp >= 0);
;   // result: sum = 1+2+...+100 = 5050 = 0x13BA
;
; Data memory layout (see test_data.dm):
;   A0=0xA0  constant 0    A1=0xA1  constant 1
;   A2=0xA2  constant 100  A3=0xA3  temp       A4=0xA4  sum
;
; Expected encoding (matches Table 2 in specification):
;   PC 00: 02A0   PC 01: 01A4   PC 02: 02A2   PC 03: 01A3
;   PC 04: 02A4   PC 05: 03A3   PC 06: 01A4   PC 07: 02A3
;   PC 08: 04A1   PC 09: 01A3   PC 0A: 0504   PC 0B: 0700
; ============================================================

; ── Address symbol definitions ─────────────────────────────
A0 = 0xA0   ; constant 0   (initial value of sum)
A1 = 0xA1   ; constant 1   (decrement step)
A2 = 0xA2   ; constant 100 (initial value of temp)
A3 = 0xA3   ; temp         (loop counter)
A4 = 0xA4   ; sum          (accumulator)

; ── Code ───────────────────────────────────────────────────
; sum = 0
        LOAD   [A0]         ; PC=00  02A0  ACC = 0
        STORE  [A4]         ; PC=01  01A4  DM[A4] (sum) = 0

; temp = 100
        LOAD   [A2]         ; PC=02  02A2  ACC = 100
        STORE  [A3]         ; PC=03  01A3  DM[A3] (temp) = 100

; loop: sum = sum + temp
loop:   LOAD   [A4]         ; PC=04  02A4  ACC = sum
        ADD    [A3]         ; PC=05  03A3  ACC = sum + temp
        STORE  [A4]         ; PC=06  01A4  DM[A4] (sum) = sum + temp

; temp = temp - 1
        LOAD   [A3]         ; PC=07  02A3  ACC = temp
        SUB    [A1]         ; PC=08  04A1  ACC = temp - 1
        STORE  [A3]         ; PC=09  01A3  DM[A3] (temp) = temp - 1

; if temp >= 0 goto loop
        JMPGEZ [loop]       ; PC=0A  0504  ACC[15]=0 → jump to PC=0x04

; end
        HALT                ; PC=0B  0700  sum = 5050 = 0x13BA in DM[A4]
