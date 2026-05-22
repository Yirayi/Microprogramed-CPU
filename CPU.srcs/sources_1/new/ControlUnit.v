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
//   LOADI  09 -> 0x90
//   AND    0A -> 0x68
//   OR     0B -> 0x70
//   NOT    0C -> 0x78
//   SHIFTR 0D -> 0x80
//   SHIFTL 0E -> 0x88
//   OUT    0F -> 0xA0
//   IN     10 -> 0xA8
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
    output wire        halted,        // asserted when HALT microop active
    input  wire [1:0]  exec_mode,     // 00=run, 01=instr-step, 10=micro-step
    input  wire        step_pulse,    // single-cycle step trigger from BTNC
    output wire        can_step,      // step gate: tell CPU_top whether to execute
    // VGA history capture
    output reg         capture_pulse, // 1-cycle negedge pulse → push ring buffer
    output reg  [7:0]  snap_car       // CAR latched before advance (micro-step)
);

    // ---- Extract sequencing control bits ----
    wire C0  = micro_instr[0];   // CAR <= CAR+1
    wire C1  = micro_instr[1];   // CAR <= dispatch(mbr_high)
    wire C2  = micro_instr[2];   // CAR <= 0
    wire C21 = micro_instr[21];  // HALT
    localparam fetch1_micro_instr   = 32'h00000401;
    assign halted = C21;

    // ---- Single-step control ----
    // instr_running: set when step_pulse fires in instr-step mode,
    //               cleared when C2 fires (instruction boundary reached)
    reg instr_running;

    assign can_step =
        (exec_mode == 2'b00) ||                                // free-run
        (exec_mode == 2'b01 && (instr_running || step_pulse)) || // instr-step
        (exec_mode == 2'b10 && step_pulse);                    // micro-step

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
            8'h09:   dispatch = 8'h90;   // LOADI imm8
            8'h0F:   dispatch = 8'hA0;   // OUT [port]
            8'h10:   dispatch = 8'hA8;   // IN [port]
            default: dispatch = 8'h00;   // unknown -> restart fetch
        endcase
    endfunction
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            instr_running <= 1'b0;
        end else begin
      // instr_running state machine (only meaningful in mode 01)
                if (exec_mode == 2'b01) begin
                    if (C2 && instr_running)
                        instr_running <= step_pulse;
                    else if (!instr_running && step_pulse)
                        instr_running <= 1'b1;
                end else
                    instr_running <= 1'b0;
        end
    end
    // ---- CAR update logic (with single-step gating) ----
    // All state in one negedge block so NBA semantics work correctly:
    // can_step reads OLD instr_running, while instr_running is updated
    // simultaneously.  Splitting across posedge/negedge would clear
    // instr_running before the negedge could use it for the C2 transition.
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            car           <= 8'hFF;
            capture_pulse <= 1'b0;
            snap_car      <= 8'h00;
        end else begin
            capture_pulse <= 1'b0;
            // Post-reset: FF→00 (bypasses step gate so startup always occurs)
            if (car == 8'hFF) begin
                car <= 8'h00;
            end else begin
                // CAR sequencing, gated by can_step and HALT
                // can_step uses OLD instr_running via NBA semantics
                if (!C21 && can_step) begin
                    if      (C2) car <= 8'h00;
                    else if (C1) car <= dispatch(mbr_high);
                    else if (C0) car <= car + 8'h01;
                end
                // VGA capture (NBA: snap_car latches OLD car before advance)
                if (exec_mode == 2'b01 && C2 && instr_running) begin
                    capture_pulse <= 1'b1;
                end else if (exec_mode == 2'b10 && step_pulse && can_step) begin
                    capture_pulse <= 1'b1;
                    snap_car      <= car;
                end
            end
        end
    end


    // -------------------------------------------------------
    // Simulation-only decode strings
    // -------------------------------------------------------
    // synthesis translate_off

    reg [127:0] cu_command;   // 16-char micro-operation description
    reg [63:0]  cu_phase;     // 8-char micro-step name (fetch1, store2, …)
    always @(posedge clk) begin
        if (reset) begin cu_command = "RESET           "; cu_phase = "reset   "; end
        else
        begin
            case (car)
                8'h00: begin cu_command = "MAR<=PC         "; cu_phase = "fetch1  "; end
                8'h01: begin cu_command = "MBR<=IM[MAR]    "; cu_phase = "fetch2  "; end
                8'h02: begin cu_command = "IR,MAR,PC,DISP  "; cu_phase = "fetch3  "; end
                8'h10: begin cu_command = "MBR<=ACC        "; cu_phase = "store1  "; end
                8'h11: begin cu_command = "DM[MAR]<=MBR    "; cu_phase = "store2  "; end
                8'h20: begin cu_command = "MBR<=DM[MAR]    "; cu_phase = "load1   "; end
                8'h21: begin cu_command = "BR<=MBR         "; cu_phase = "load2   "; end
                8'h22: begin cu_command = "ACC<=BR         "; cu_phase = "load3   "; end
                8'h30: begin cu_command = "MBR<=DM[MAR]    "; cu_phase = "add1    "; end
                8'h31: begin cu_command = "BR<=MBR         "; cu_phase = "add2    "; end
                8'h32: begin cu_command = "ACC<=ACC+BR     "; cu_phase = "add3    "; end
                8'h38: begin cu_command = "MBR<=DM[MAR]    "; cu_phase = "sub1    "; end
                8'h39: begin cu_command = "BR<=MBR         "; cu_phase = "sub2    "; end
                8'h3A: begin cu_command = "ACC<=ACC-BR     "; cu_phase = "sub3    "; end
                8'h40: begin cu_command = "JMPGEZ:PC<=MAR  "; cu_phase = "jmpgez1 "; end
                8'h48: begin cu_command = "JMP:PC<=MAR     "; cu_phase = "jmp1    "; end
                8'h50: begin cu_command = "HALT            "; cu_phase = "halt1   "; end
                8'h58: begin cu_command = "MBR<=DM[MAR]    "; cu_phase = "mpy1    "; end
                8'h59: begin cu_command = "BR<=MBR         "; cu_phase = "mpy2    "; end
                8'h5A: begin cu_command = "{MR,ACC}<=MUL   "; cu_phase = "mpy3    "; end
                8'h68: begin cu_command = "MBR<=DM[MAR]    "; cu_phase = "and1    "; end
                8'h69: begin cu_command = "BR<=MBR         "; cu_phase = "and2    "; end
                8'h6A: begin cu_command = "ACC<=ACC&BR     "; cu_phase = "and3    "; end
                8'h70: begin cu_command = "MBR<=DM[MAR]    "; cu_phase = "or1     "; end
                8'h71: begin cu_command = "BR<=MBR         "; cu_phase = "or2     "; end
                8'h72: begin cu_command = "ACC<=ACC|BR     "; cu_phase = "or3     "; end
                8'h78: begin cu_command = "ACC<=~ACC       "; cu_phase = "not1    "; end
                8'h80: begin cu_command = "MBR<=DM[MAR]    "; cu_phase = "shiftr1 "; end
                8'h81: begin cu_command = "BR<=MBR         "; cu_phase = "shiftr2 "; end
                8'h82: begin cu_command = "ACC<=BR>>1      "; cu_phase = "shiftr3 "; end
                8'h88: begin cu_command = "MBR<=DM[MAR]    "; cu_phase = "shiftl1 "; end
                8'h89: begin cu_command = "BR<=MBR         "; cu_phase = "shiftl2 "; end
                8'h8A: begin cu_command = "ACC<=BR<<1      "; cu_phase = "shiftl3 "; end
                8'h90: begin cu_command = "ACC<=sext(MAR)  "; cu_phase = "loadi1  "; end
                8'hA0: begin cu_command = "port[MAR]<=ACC  "; cu_phase = "out1    "; end
                8'hA8: begin cu_command = "MBR<=port[MAR]  "; cu_phase = "in1     "; end
                8'hA9: begin cu_command = "BR<=MBR         "; cu_phase = "in2     "; end
                8'hAA: begin cu_command = "ACC<=BR         "; cu_phase = "in3     "; end
                default: begin cu_command = "???             "; cu_phase = "???     "; end
            endcase
         end
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
                8'h09: next_car_str = "->LOADI ";
                8'h0F: next_car_str = "->OUT   ";
                8'h10: next_car_str = "->IN    ";
                default: next_car_str = "->???   ";
            endcase
        else if (C0)
            next_car_str = "->CAR+1 ";
        else
            next_car_str = "->???   ";
    end
    // synthesis translate_on

endmodule
