; ============================================================
; collatz.asm  -  Collatz Sequence Step Counter
; Generate with:  python im_asm.py collatz.asm ../IMData.coe
;
; Task:
;   Read N from port_in[0].
;   Count Collatz steps until N reaches 1:
;     - if N is even : N = N / 2
;     - if N is odd  : N = 3*N + 1
;   Output the result to port_out[0] (7-segment display).
;
; Output encoding:
;   bits[15:1] = step count  (display >> 1)
;   bit  0     = 1 if N was even, 0 if N was odd
;   e.g. input 6  -> 8 steps, 6 is even  -> display = 8*2 | 1 = 17 (0x0011)
;        input 5  -> 5 steps, 5 is odd   -> display = 5*2 | 0 = 10 (0x000A)
;        input 27 ->111 steps,27 is odd  -> display =111*2| 0 =222 (0x00DE)
;
; Recommended input range: 1..100
; (Larger N may produce 3N+1 > 0xFFFF and lose the high bits.)
;
; DM layout (all initialized at runtime via LOADI+STORE):
;   D0 = N      current Collatz value (mutated each iteration)
;   D1 = COUNT  step counter (starts 0)
;   D2 = ONE    constant 1
;   D3 = THREE  constant 3
;   D4 = TWO    constant 2
;   D5 = PAR    temporary / even_flag
;   D6 = ORIG   original parity of N  (= N & 1, saved before loop)
;   D7 = TEMP   scratch word for SHIFTL
;
; Instructions covered:
;   IN STORE LOADI LOAD AND JMPGEZ JMP SUB SHIFTR MPY ADD NOT SHIFTL OR OUT HALT
; ============================================================

; DM address symbols
N     = 0xD0
COUNT = 0xD1
ONE   = 0xD2
THREE = 0xD3
TWO   = 0xD4
PAR   = 0xD5
ORIG  = 0xD6
TEMP  = 0xD7

; ── Read input ─────────────────────────────────────────────
        IN    [0]           ; PC=00  1000  N = port_in[0]
        STORE [N]           ; PC=01  01D0  DM[D0] = N

; ── Initialize constants (no pre-loaded DM data required) ──
        LOADI 1             ; PC=02  0901
        STORE [ONE]         ; PC=03  01D2  DM[D2] = 1

        LOADI 3             ; PC=04  0903
        STORE [THREE]       ; PC=05  01D3  DM[D3] = 3

        LOADI 2             ; PC=06  0902
        STORE [TWO]         ; PC=07  01D4  DM[D4] = 2

        LOADI 0             ; PC=08  0900
        STORE [COUNT]       ; PC=09  01D1  step counter = 0

; ── Save original parity of N (for display encoding) ───────
        LOAD  [N]           ; PC=0A  02D0  ACC = N
        AND   [ONE]         ; PC=0B  0AD2  ACC = N & 1  (0=even, 1=odd)
        STORE [ORIG]        ; PC=0C  01D6  DM[D6] = original parity

; ── Main loop: execute while N > 1 (i.e. N >= 2) ───────────
loop:
        LOAD  [N]           ; PC=0D  02D0
        SUB   [TWO]         ; PC=0E  04D4  ACC = N - 2
        JMPGEZ [body]       ; PC=0F  0511  N >= 2 -> run loop body
        JMP   [done]        ; PC=10  0621  N < 2 -> exit loop

; ── Loop body: one Collatz step ─────────────────────────────
body:
        LOAD  [N]           ; PC=11  02D0
        AND   [ONE]         ; PC=12  0AD2  ACC = N & 1  (parity test)
        STORE [PAR]         ; PC=13  01D5  save parity
        SUB   [ONE]         ; PC=14  04D2  ACC = parity - 1
        JMPGEZ [is_odd]     ; PC=15  0519  parity was 1 -> 1-1=0 >= 0 -> odd

; ── Even branch: N = N >> 1 (divide by 2) ──────────────────
        SHIFTR [N]          ; PC=16  0DD0  ACC = DM[N] >> 1 = N/2
        STORE  [N]          ; PC=17  01D0  N = N/2
        JMP    [count_step] ; PC=18  061D

; ── Odd branch: N = 3*N + 1 ─────────────────────────────────
is_odd:
        LOAD  [N]           ; PC=19  02D0
        MPY   [THREE]       ; PC=1A  08D3  ACC = N * 3  (low 16 bits)
        ADD   [ONE]         ; PC=1B  03D2  ACC = 3*N + 1
        STORE [N]           ; PC=1C  01D0  N = 3*N+1

; ── Increment step counter and loop back ───────────────────
count_step:
        LOAD  [COUNT]       ; PC=1D  02D1
        ADD   [ONE]         ; PC=1E  03D2  count++
        STORE [COUNT]       ; PC=1F  01D1
        JMP   [loop]        ; PC=20  060D

; ── Format result and output to 7-segment display ──────────
done:
        ; Compute even_flag = NOT(original_parity) & 1
        ;   original_parity=0 (was even) -> NOT gives 0xFFFF -> & 1 = 1
        ;   original_parity=1 (was odd)  -> NOT gives 0xFFFE -> & 1 = 0
        LOAD  [ORIG]        ; PC=21  02D6  ACC = original parity (0 or 1)
        NOT                 ; PC=22  0C00  ACC = bitwise complement
        AND   [ONE]         ; PC=23  0AD2  ACC = even_flag (1=even, 0=odd)
        STORE [PAR]         ; PC=24  01D5  DM[D5] = even_flag

        ; Compose display = (count << 1) | even_flag
        LOAD  [COUNT]       ; PC=25  02D1
        STORE [TEMP]        ; PC=26  01D7  TEMP = count
        SHIFTL [TEMP]       ; PC=27  0ED7  ACC = DM[D7] << 1 = count * 2
        OR    [PAR]         ; PC=28  0BD5  ACC = (count*2) | even_flag
        OUT   [0]           ; PC=29  0F00  -> port_out[0] (7-segment display)
        HALT                ; PC=2A  0700
