// ============================================================
// ControlUnit.v
// Microprogrammed CPU – Control Unit
// ============================================================
// Responsibilities:
//   - Maintain the Control Address Register (CAR)
//   - Read the 32-bit microinstruction from Control Memory
//   - Implement CAR sequencing: C0 (increment), C1 (dispatch),
//     C2 (reset to fetch)
//   - Drive the HALT output when C21 is active
//
// CAR update priority:  C2  >  C1  >  C0
//   C2  : CAR <= 0          (return to fetch after last microop)
//   C1  : CAR <= dispatch   (jump to instruction's microcode start)
//   C0  : CAR <= CAR + 1    (advance within an instruction's routine)
//   none: CAR unchanged     (HALT – freezes execution)
//
// Dispatch table (opcode byte from MBR[15:8] -> CAR start address):
//   STORE  01 -> 0x10
//   LOAD   02 -> 0x20
//   ADD    03 -> 0x30
//   SUB    04 -> 0x38
//   JMPGEZ 05 -> 0x40
//   JMP    06 -> 0x48
//   HALT   07 -> 0x50
//   MPY    08 -> 0x58
//   AND    0A -> 0x68
//   OR     0B -> 0x70
//   NOT    0C -> 0x78
//   SHIFTR 0D -> 0x80
//   SHIFTL 0E -> 0x88
//
// Note: C1 reads mbr_high (MBR[15:8]) combinationally.
//   Both C4 (IR <= MBR[15:8]) and C1 fire in the same clock
//   cycle (fetch T3). Using MBR[15:8] directly avoids the
//   one-cycle IR latency.
// ============================================================

`timescale 1ns / 1ps

module ControlUnit (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] micro_instr,   // current microinstruction from CM
    input  wire [7:0]  mbr_high,      // MBR[15:8] – opcode for dispatch
    output reg  [7:0]  car,           // Control Address Register
    output wire        halted         // asserted when HALT microop active
);

    // ---- Extract sequencing control bits ----
    wire C0  = micro_instr[0];   // CAR <= CAR+1
    wire C1  = micro_instr[1];   // CAR <= dispatch(mbr_high)
    wire C2  = micro_instr[2];   // CAR <= 0
    wire C21 = micro_instr[21];  // HALT

    assign halted = C21;

    // ---- Dispatch function: opcode -> CAR start address ----
    function [7:0] dispatch;
        input [7:0] opcode;
        case (opcode)
            8'h01:   dispatch = 8'h10;   // STORE X
            8'h02:   dispatch = 8'h20;   // LOAD X
            8'h03:   dispatch = 8'h30;   // ADD X
            8'h04:   dispatch = 8'h38;   // SUB X
            8'h05:   dispatch = 8'h40;   // JMPGEZ X
            8'h06:   dispatch = 8'h48;   // JMP X
            8'h07:   dispatch = 8'h50;   // HALT
            8'h08:   dispatch = 8'h58;   // MPY X
            8'h0A:   dispatch = 8'h68;   // AND X
            8'h0B:   dispatch = 8'h70;   // OR X
            8'h0C:   dispatch = 8'h78;   // NOT
            8'h0D:   dispatch = 8'h80;   // SHIFTR X
            8'h0E:   dispatch = 8'h88;   // SHIFTL X
            default: dispatch = 8'h00;   // unknown -> restart fetch
        endcase
    endfunction

    // ---- CAR update logic ----
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            car <= 8'h00;
        end else if (!C21) begin
            // Priority: C2 > C1 > C0
            if (C2)
                car <= 8'h00;
            else if (C1)
                car <= dispatch(mbr_high);
            else if (C0)
                car <= car + 8'h01;
            // else: no sequencing bits -> stay (should not happen except HALT)
        end
        // C21 asserted: CAR freezes (CPU halted)
    end

    // -------------------------------------------------------
    // Simulation-only decode strings
    // -------------------------------------------------------
    // synthesis translate_off
    reg [127:0] uop_str;        // 16-char micro-operation description
    always @(*) begin
        case (car)
            8'h00: uop_str = "MAR<=PC         ";
            8'h01: uop_str = "MBR<=IM[MAR]    ";
            8'h02: uop_str = "IR,MAR,PC,DISP  ";
            8'h10: uop_str = "MBR<=ACC        ";
            8'h11: uop_str = "DM[MAR]<=MBR    ";
            8'h20: uop_str = "MBR<=DM[MAR]    ";
            8'h21: uop_str = "BR<=MBR         ";
            8'h22: uop_str = "ACC<=BR         ";
            8'h30: uop_str = "MBR<=DM[MAR]    ";
            8'h31: uop_str = "BR<=MBR         ";
            8'h32: uop_str = "ACC<=ACC+BR     ";
            8'h38: uop_str = "MBR<=DM[MAR]    ";
            8'h39: uop_str = "BR<=MBR         ";
            8'h3A: uop_str = "ACC<=ACC-BR     ";
            8'h40: uop_str = "JMPGEZ:PC<=MAR  ";
            8'h48: uop_str = "JMP:PC<=MAR     ";
            8'h50: uop_str = "HALT            ";
            8'h58: uop_str = "MBR<=DM[MAR]    ";
            8'h59: uop_str = "BR<=MBR         ";
            8'h5A: uop_str = "{MR,ACC}<=MUL   ";
            8'h68: uop_str = "MBR<=DM[MAR]    ";
            8'h69: uop_str = "BR<=MBR         ";
            8'h6A: uop_str = "ACC<=ACC&BR     ";
            8'h70: uop_str = "MBR<=DM[MAR]    ";
            8'h71: uop_str = "BR<=MBR         ";
            8'h72: uop_str = "ACC<=ACC|BR     ";
            8'h78: uop_str = "ACC<=~ACC       ";
            8'h80: uop_str = "MBR<=DM[MAR]    ";
            8'h81: uop_str = "BR<=MBR         ";
            8'h82: uop_str = "ACC<=BR>>1      ";
            8'h88: uop_str = "MBR<=DM[MAR]    ";
            8'h89: uop_str = "BR<=MBR         ";
            8'h8A: uop_str = "ACC<=BR<<1      ";
            default: uop_str = "???             ";
        endcase
    end

    reg [63:0] next_car_str;    // 8-char next-CAR destination label
    always @(*) begin
        if (C21)
            next_car_str = "FROZEN  ";
        else if (C2)
            next_car_str = "->FETCH ";
        else if (C1)
            case (mbr_high)
                8'h01: next_car_str = "->STORE ";
                8'h02: next_car_str = "->LOAD  ";
                8'h03: next_car_str = "->ADD   ";
                8'h04: next_car_str = "->SUB   ";
                8'h05: next_car_str = "->JMPGEZ";
                8'h06: next_car_str = "->JMP   ";
                8'h07: next_car_str = "->HALT  ";
                8'h08: next_car_str = "->MPY   ";
                8'h0A: next_car_str = "->AND   ";
                8'h0B: next_car_str = "->OR    ";
                8'h0C: next_car_str = "->NOT   ";
                8'h0D: next_car_str = "->SHIFTR";
                8'h0E: next_car_str = "->SHIFTL";
                default: next_car_str = "->???   ";
            endcase
        else if (C0)
            next_car_str = "->CAR+1 ";
        else
            next_car_str = "->???   ";
    end
    // synthesis translate_on

endmodule
