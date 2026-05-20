// ============================================================
// AllInstr_tb.v
// Verifies every instruction executes correctly.
//
// Instructions under test:
//   LOAD  [E0]          → ACC = 10
//   STORE [D0]          → DM[D0] = 10
//   ADD   [E1]          → ACC = 13
//   SUB   [E1]          → ACC = 7
//   AND   [E1]          → ACC = 2
//   OR    [E1]          → ACC = 11
//   NOT                 → ACC = 0xFFF5
//   SHIFTR [E0]         → ACC = 5   (DM[E0]>>1)
//   SHIFTL [E1]         → ACC = 6   (DM[E1]<<1)
//   MPY   [E1]          → ACC = 0x001E, MR = 0x0000  (10×3=30)
//   JMP   [0x12]        → skips dead HALT at 0x11
//   JMPGEZ [0x14]       → taken  (ACC=30≥0); skips dead HALT at 0x13
//   LOAD  [E2]          → ACC = 0xFFFF  (−1)
//   JMPGEZ [0x1C]       → NOT taken (ACC[15]=1); falls through
//   LOAD  [E0]          → ACC = 10  (proves not-taken path ran)
//   LOADI 42            → ACC = 0x002A
//   OUT   [0]           → port_out[0] = 0x002A
//   LOADI 255           → ACC = 0xFFFF  (sign-extend 0xFF)
//   OUT   [1]           → port_out[1] = 0xFFFF
//   IN    [0]           → ACC = port_in[0] = 0xABCD
//   HALT                → freezes at CAR=0x50
//
// Expected final state (after HALT at PC=0x1C):
//   halted     = 1
//   CAR        = 0x50
//   PC         = 0x1D   (0x1C+1; proves JMP and JMPGEZ-taken worked)
//   IR         = 0x07
//   ACC        = 0xABCD (proves IN[0] was reached and JMPGEZ-not-taken worked)
//   MR         = 0x0000
//   port_out[0] = 0x002A (proves LOADI 42 + OUT [0])
//   port_out[1] = 0xFFFF (proves LOADI 255 + OUT [1])
// ============================================================

`timescale 1ns / 1ps

module AllInstr_tb;

    reg  clk, reset;
    wire halted;

    reg  [63:0] port_in;
    wire [63:0] port_out;

    CPU_top dut (
        .clk     (clk),
        .reset   (reset),
        .halted  (halted),
        .port_out(port_out),
        .port_in (port_in)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    wire [7:0]  tb_CAR = dut.car;
    wire [7:0]  tb_PC  = dut.PC;
    wire [7:0]  tb_IR  = dut.IR;
    wire [15:0] tb_ACC = dut.ACC;
    wire [15:0] tb_MR  = dut.MR;

    integer cycle, errors;

    initial begin
        errors   = 0;
        port_in         = 64'h0;
        port_in[15:0]   = 16'hABCD;   // port 0
        reset     = 1'b1;
        $display("=== All-Instructions Testbench ===");
        repeat (5) @(posedge clk);
        #1; reset = 1'b0;

        cycle = 0;
        while (!halted && cycle < 1000) begin
            @(posedge clk); #1;
            cycle = cycle + 1;
        end

        if (!halted) begin
            $display("[FAIL] HALT not reached within 1000 cycles (PC=0x%02h)", tb_PC);
            errors = errors + 1;
        end else begin
            $display("[%0t] HALT after %0d post-reset cycles.", $time, cycle);
            repeat (3) @(posedge clk); #1;

            check_8 ("CAR",       tb_CAR,    8'h50);
            check_8 ("PC",        tb_PC,     8'h1D);
            check_8 ("IR",        tb_IR,     8'h07);
            check_16("ACC",       tb_ACC,    16'hABCD);
            check_16("MR",        tb_MR,     16'h0000);
            check_16("port_out[0]",port_out[15:0], 16'h002A);
            check_16("port_out[1]",port_out[31:16],16'hFFFF);
        end

        $display("===================================");
        if (errors == 0) $display("  ALL PASSED (%0d checks)", 7);
        else             $display("  %0d FAILED", errors);
        $display("===================================");
        $finish;
    end

    task check_8;
        input [127:0] name; input [7:0] actual, expected;
        begin
            if (actual === expected)
                $display("  PASS: %-10s = 0x%02h", name, actual);
            else begin
                $display("  FAIL: %-10s expected 0x%02h, got 0x%02h", name, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task check_16;
        input [127:0] name; input [15:0] actual, expected;
        begin
            if (actual === expected)
                $display("  PASS: %-10s = 0x%04h", name, actual);
            else begin
                $display("  FAIL: %-10s expected 0x%04h, got 0x%04h", name, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

endmodule
