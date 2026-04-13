// ============================================================
// CPU_top.v
// Microprogrammed CPU – Top-Level Module
// ============================================================
//
// Architecture overview:
//   Single-address, 16-bit instructions (opcode[15:8] | addr[7:0])
//   16-bit data words in RAM
//   Microprogrammed control: every machine instruction is
//   decomposed into a sequence of micro-operations driven by
//   32-bit microinstructions stored in Control Memory (CM).
//
// Internal registers:
//   MAR  [7:0]  – Memory Address Register
//   MBR  [15:0] – Memory Buffer Register
//   PC   [7:0]  – Program Counter
//   IR   [7:0]  – Instruction Register (holds current opcode)
//   BR   [15:0] – Buffer Register (operand staging for ALU)
//   ACC  [15:0] – Accumulator
//   MR   [15:0] – Multiply Result register (high word of MPY)
//
// Memory:
//   ControlMemory    – 32-bit x 256 ROM  (microcode, CMData.coe)
//   InstructionMemory– 16-bit x 256 ROM  (program,   IMData.coe)
//   DataMemory       – 16-bit x 256 RAM  (data,      DMData.coe)
//   All BRAMs have 1-cycle registered output latency.
//
// Microinstruction bit assignments (see CMData.coe for full list):
//   C0  [0]  CAR <= CAR+1
//   C1  [1]  CAR <= dispatch(MBR[15:8])
//   C2  [2]  CAR <= 0
//   C3  [3]  MBR <= IM[MAR]  (fetch phase) | MBR <= DM[MAR] (exec)
//   C4  [4]  IR  <= MBR[15:8]
//   C5  [5]  MAR <= MBR[7:0]
//   C6  [6]  PC  <= PC+1
//   C7  [7]  BR  <= MBR
//   C8  [8]  ACC <= 0
//   C9  [9]  ACC <= ACC+BR
//   C10 [10] MAR <= PC
//   C11 [11] MBR <= ACC
//   C12 [12] DM[MAR] <= MBR  (write enable)
//   C13 [13] ACC <= ACC-BR
//   C14 [14] ACC <= ACC AND BR
//   C15 [15] ACC <= ACC OR BR
//   C16 [16] ACC <= NOT ACC
//   C17 [17] ACC <= BR >> 1  (logical)
//   C18 [18] ACC <= BR << 1  (logical)
//   C19 [19] {MR,ACC} <= ACC * BR  (unsigned)
//   C20 [20] ACC <= BR
//   C21 [21] HALT
//   C22 [22] PC  <= MAR
//   C23 [23] if ACC[15]=0: PC <= MAR  (JMPGEZ)
//
// Memory phase select:
//   is_fetch = (car[7:4] == 4'h0)
//   When is_fetch=1 and C3 fires -> MBR captures InstructionMemory output
//   When is_fetch=0 and C3 fires -> MBR captures DataMemory output
//   Both memories are always addressed by MAR.
//   The registered BRAM output is valid one cycle after the address
//   is presented, which matches the micro-cycle sequencing.
//
// Fetch cycle timing (3 micro-cycles):
//   T1 (CAR=0x00): C10,C0  -> MAR <= PC;   CAR++
//   T2 (CAR=0x01): C3, C0  -> MBR <= IM[MAR];  CAR++
//                             (IM output is mem[PC] set at T1)
//   T3 (CAR=0x02): C4,C5,C6,C1
//                          -> IR  <= MBR[15:8]  (opcode)
//                          -> MAR <= MBR[7:0]   (operand addr)
//                          -> PC  <= PC+1
//                          -> CAR <= dispatch(MBR[15:8])
//
// Execute cycles: specific to each instruction (see CMData.coe)
// ============================================================

`timescale 1ns / 1ps

module CPU_top (
    input  wire clk,
    input  wire reset,
    output wire halted    // asserted when HALT instruction executes
);

    // -------------------------------------------------------
    // Internal registers
    // -------------------------------------------------------
    reg  [7:0]  MAR;
    reg  [15:0] MBR;
    reg  [7:0]  PC;
    reg  [7:0]  IR;
    reg  [15:0] BR;
    reg  [15:0] ACC;
    reg  [15:0] MR;

    // -------------------------------------------------------
    // rsta_busy guard: extend reset until both BRAMs are ready
    // Xilinx BRAM simulation model pulses rsta_busy HIGH at
    // power-on regardless of whether rsta is driven.  If this
    // pulse arrives after system reset is released the CPU would
    // read douta=0 (output register wiped) and stall.
    // Driving rsta=reset lets us monitor rsta_busy and hold the
    // CPU in reset until both CM and IM output registers are stable.
    // -------------------------------------------------------
    wire cm_rsta_busy;
    wire im_rsta_busy;
    wire internal_reset = reset | cm_rsta_busy | im_rsta_busy;

    // -------------------------------------------------------
    // Control Unit
    // -------------------------------------------------------
    wire [7:0]  car;
    wire [31:0] micro_instr;

    ControlUnit cu (
        .clk        (clk),
        .reset      (internal_reset),
        .micro_instr(micro_instr),
        .mbr_high   (MBR[15:8]),   // opcode used for dispatch (C1)
        .car        (car),
        .halted     (halted)
    );

    // -------------------------------------------------------
    // Control Memory (32-bit x 256 ROM, CMData.coe)
    // -------------------------------------------------------
    ControlMemory cm (
        .clka      (clk),
        .rsta      (reset),
        .addra     (car),
        .douta     (micro_instr),
        .rsta_busy (cm_rsta_busy)
    );

    // -------------------------------------------------------
    // Instruction Memory (16-bit x 256 ROM, IMData.coe)
    // -------------------------------------------------------
    wire [15:0] im_dout;

    InstructionMemory im (
        .clka      (clk),
        .rsta      (reset),
        .addra     (MAR),
        .douta     (im_dout),
        .rsta_busy (im_rsta_busy)
    );

    // -------------------------------------------------------
    // Data Memory (16-bit x 256 RAM, DMData.coe)
    // Port A = write, Port B = read (both addressed by MAR)
    // -------------------------------------------------------
    wire [15:0] dm_dout;
    wire        dm_we;

    assign dm_we = micro_instr[12];   // C12: DM[MAR] <= MBR

    DataMemory dm (
        // Write port A
        .clka (clk),
        .addra(MAR),
        .dina (MBR),
        .wea  (dm_we),
        // Read port B
        .clkb (clk),
        .addrb(MAR),
        .doutb(dm_dout)
    );

    // -------------------------------------------------------
    // Decode microinstruction control bits
    // -------------------------------------------------------
    wire C3  = micro_instr[3];    // MBR <= memory[MAR]
    wire C4  = micro_instr[4];    // IR  <= MBR[15:8]
    wire C5  = micro_instr[5];    // MAR <= MBR[7:0]
    wire C6  = micro_instr[6];    // PC  <= PC+1
    wire C7  = micro_instr[7];    // BR  <= MBR
    wire C8  = micro_instr[8];    // ACC <= 0
    wire C9  = micro_instr[9];    // ACC <= ACC+BR
    wire C10 = micro_instr[10];   // MAR <= PC
    wire C11 = micro_instr[11];   // MBR <= ACC
    wire C13 = micro_instr[13];   // ACC <= ACC-BR
    wire C14 = micro_instr[14];   // ACC <= ACC AND BR
    wire C15 = micro_instr[15];   // ACC <= ACC OR BR
    wire C16 = micro_instr[16];   // ACC <= NOT ACC
    wire C17 = micro_instr[17];   // ACC <= BR >> 1
    wire C18 = micro_instr[18];   // ACC <= BR << 1
    wire C19 = micro_instr[19];   // {MR,ACC} <= ACC * BR
    wire C20 = micro_instr[20];   // ACC <= BR
    wire C22 = micro_instr[22];   // PC  <= MAR
    wire C23 = micro_instr[23];   // if ACC[15]=0: PC <= MAR

    // Memory phase: CAR in range 0x00-0x0F means fetch cycle
    wire is_fetch = (car[7:4] == 4'h0);

    // -------------------------------------------------------
    // ALU
    // -------------------------------------------------------
    // ALU op encoding (matches ALU.v localparams)
    localparam ALU_ADD    = 4'h0;
    localparam ALU_SUB    = 4'h1;
    localparam ALU_AND    = 4'h2;
    localparam ALU_OR     = 4'h3;
    localparam ALU_NOT    = 4'h4;
    localparam ALU_SHR    = 4'h5;
    localparam ALU_SHL    = 4'h6;
    localparam ALU_MPY    = 4'h7;
    localparam ALU_PASS_B = 4'h8;

    reg  [3:0]  alu_op;
    wire [15:0] alu_result;
    wire [15:0] alu_mr;

    ALU alu (
        .a      (ACC),
        .b      (BR),
        .op     (alu_op),
        .result (alu_result),
        .mr_out (alu_mr)
    );

    // Select ALU operation from active control bits
    always @(*) begin
        if      (C9)  alu_op = ALU_ADD;
        else if (C13) alu_op = ALU_SUB;
        else if (C14) alu_op = ALU_AND;
        else if (C15) alu_op = ALU_OR;
        else if (C16) alu_op = ALU_NOT;
        else if (C17) alu_op = ALU_SHR;
        else if (C18) alu_op = ALU_SHL;
        else if (C19) alu_op = ALU_MPY;
        else if (C20) alu_op = ALU_PASS_B;
        else          alu_op = ALU_PASS_B;   // default (no ACC write)
    end

    // -------------------------------------------------------
    // Register update: all registers clocked on posedge
    // -------------------------------------------------------
    always @(posedge clk or posedge internal_reset) begin
        if (internal_reset) begin
            MAR <= 8'h00;
            MBR <= 16'h0000;
            PC  <= 8'h00;
            IR  <= 8'h00;
            BR  <= 16'h0000;
            ACC <= 16'h0000;
            MR  <= 16'h0000;
        end else begin

            // ---- MAR updates ----
            // C10 and C5 never assert in the same micro-cycle.
            if      (C10) MAR <= PC;
            else if (C5)  MAR <= MBR[7:0];

            // ---- MBR updates ----
            // C3 and C11 never assert in the same micro-cycle.
            if      (C3 && is_fetch) MBR <= im_dout;   // fetch: read IM
            else if (C3)             MBR <= dm_dout;   // execute: read DM
            else if (C11)            MBR <= ACC;       // STORE: capture ACC

            // ---- IR update ----
            if (C4) IR <= MBR[15:8];

            // ---- PC updates ----
            // C6 (PC+1) happens in fetch T3.
            // C22 (JMP) and C23 (JMPGEZ) happen in a single execute cycle.
            // C6 never combines with C22/C23 in the same micro-cycle.
            if      (C22)               PC <= MAR;
            else if (C23 && !ACC[15])   PC <= MAR;   // JMPGEZ: only if ACC>=0
            else if (C6)                PC <= PC + 8'h01;

            // ---- BR update ----
            if (C7) BR <= MBR;

            // ---- ACC updates ----
            // ACC reset (C8) is independent; arithmetic ops use ALU.
            if (C8) begin
                ACC <= 16'h0000;
            end else if (C9 | C13 | C14 | C15 | C16 | C17 | C18 | C19 | C20) begin
                ACC <= alu_result;
            end

            // ---- MR update (multiply high word) ----
            if (C19) MR <= alu_mr;

        end
    end

    // -------------------------------------------------------
    // Simulation-only decode strings
    // -------------------------------------------------------
    // synthesis translate_off
    reg [47:0] ir_str;          // 6-char IR opcode mnemonic
    always @(*) begin
        if (internal_reset) begin
            ir_str ="RESET ";
        end else
        begin
            case (IR)
                8'h01: ir_str = "STORE ";
                8'h02: ir_str = "LOAD  ";
                8'h03: ir_str = "ADD   ";
                8'h04: ir_str = "SUB   ";
                8'h05: ir_str = "JMPGEZ";
                8'h06: ir_str = "JMP   ";
                8'h07: ir_str = "HALT  ";
                8'h08: ir_str = "MPY   ";
                8'h0A: ir_str = "AND   ";
                8'h0B: ir_str = "OR    ";
                8'h0C: ir_str = "NOT   ";
                8'h0D: ir_str = "SHIFTR";
                8'h0E: ir_str = "SHIFTL";
                default: ir_str = "???   ";
            endcase
         end
    end

    reg [47:0] alu_op_str;      // 6-char ALU operation name
    always @(*) begin
       if (internal_reset) begin
            alu_op_str ="RESET ";
        end else
        begin
            case (alu_op)
                ALU_ADD:    alu_op_str = "ADD   ";
                ALU_SUB:    alu_op_str = "SUB   ";
                ALU_AND:    alu_op_str = "AND   ";
                ALU_OR:     alu_op_str = "OR    ";
                ALU_NOT:    alu_op_str = "NOT   ";
                ALU_SHR:    alu_op_str = "SHR   ";
                ALU_SHL:    alu_op_str = "SHL   ";
                ALU_MPY:    alu_op_str = "MPY   ";
                ALU_PASS_B: alu_op_str = "PASS_B";
                default:    alu_op_str = "???   ";
            endcase
         end
    end
    // synthesis translate_on

endmodule
