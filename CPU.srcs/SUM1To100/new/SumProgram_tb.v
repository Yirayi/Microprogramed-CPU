// ============================================================
// SumProgram_tb.v
// Testbench for the 1+2+3+...+100 sum program
// ============================================================
//
// Program source: Memory/1sumto100/IMData.coe  (14 instructions)
// Data source:    Memory/1sumto100/DMData.coe
//
// Data Memory pre-load:
//   DM[0xA0] = 0x0000  constant 0   (initial value of sum)
//   DM[0xA1] = 0x0001  constant 1   (decrement step)
//   DM[0xA2] = 0x0064  constant 100 (initial value of temp)
//   DM[0xA3] = 0x0000  temp         (loop counter, runtime variable)
//   DM[0xA4] = 0x0000  sum          (accumulator, runtime variable)
//
// Program execution (101 loop iterations):
//   sum = 0;  temp = 100;
//   loop: sum += temp;  temp--;  if (temp >= 0) goto loop;
//   ACC = sum;  port_out[0] = sum;  HALT
//
// Instruction encoding:
//   PC 00: 02A0  LOAD  [A0]      PC 01: 01A4  STORE [A4]
//   PC 02: 02A2  LOAD  [A2]      PC 03: 01A3  STORE [A3]
//   PC 04: 02A4  LOAD  [A4]  <-- LOOP start
//   PC 05: 03A3  ADD   [A3]      PC 06: 01A4  STORE [A4]
//   PC 07: 02A3  LOAD  [A3]      PC 08: 04A1  SUB   [A1]
//   PC 09: 01A3  STORE [A3]      PC 0A: 0504  JMPGEZ[loop=0x04]
//   PC 0B: 02A4  LOAD  [A4]      PC 0C: 0F00  OUT   [0]
//   PC 0D: 0700  HALT
//
// Execution trace of final loop iteration (temp = 0):
//   LOAD [A4]  → ACC = 5050 = 0x13BA
//   ADD  [A3]  → ACC = 5050 + 0 = 5050
//   STORE[A4]  → DM[0xA4] = 5050 = 0x13BA   ← final sum written
//   LOAD [A3]  → ACC = 0
//   SUB  [A1]  → ACC = 0 - 1 = -1 = 0xFFFF
//   STORE[A3]  → DM[0xA3] = 0xFFFF
//   JMPGEZ     → ACC[15]=1, not taken, fall through
//   LOAD [A4]  → ACC = 0x13BA
//   OUT  [0]   → port_out[0] = 0x13BA
//   HALT
//
// Expected final state:
//   halted      = 1
//   CAR         = 0x50    (frozen at HALT microcode address)
//   PC          = 0x0E    (0x0D + 1, incremented in fetch T3)
//   IR          = 0x07    (HALT opcode)
//   ACC         = 0x13BA  (loaded from DM[A4] just before HALT)
//   MR          = 0x0000  (no MPY instruction in this program)
//   port_out[0] = 0x13BA  (= 5050, drives 7-segment display)
// ============================================================

`timescale 1ns / 1ps

module SumProgram_tb;

    // -------------------------------------------------------
    // Clock
    // -------------------------------------------------------
    reg clk, reset;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -------------------------------------------------------
    // CPU_top
    // -------------------------------------------------------
    wire          halted;
    wire [3:0][15:0] port_out;

    CPU_top dut (
        .clk     (clk),
        .reset   (reset),
        .halted  (halted),
        .port_out(port_out),
        .port_in ('0)
    );

    // -------------------------------------------------------
    // seven_seg_decimal (separate instance for waveform debug)
    // -------------------------------------------------------
    wire [7:0] tb_AN;
    wire [6:0] tb_SEG;

    seven_seg_decimal seg_disp (
        .clk  (clk),
        .reset(reset),
        .value(port_out[0]),
        .AN   (tb_AN),
        .SEG  (tb_SEG)
    );

    // -------------------------------------------------------
    // Hierarchical aliases for DUT internals
    // -------------------------------------------------------
    wire [7:0]  tb_MAR      = dut.MAR;
    wire [15:0] tb_MBR      = dut.MBR;
    wire [7:0]  tb_PC       = dut.PC;
    wire [7:0]  tb_IR       = dut.IR;
    wire [15:0] tb_BR       = dut.BR;
    wire [15:0] tb_ACC      = dut.ACC;
    wire [15:0] tb_MR       = dut.MR;
    wire [7:0]  tb_CAR      = dut.car;
    wire [31:0] tb_MI       = dut.micro_instr;
    wire [15:0] tb_dm_dout  = dut.dm_dout;
    wire [15:0] tb_port_out0 = port_out[0];

    // -------------------------------------------------------
    // VCD dump
    // -------------------------------------------------------
    initial begin
        $dumpfile("sum_sim.vcd");
        $dumpvars(0, SumProgram_tb);
    end

    // -------------------------------------------------------
    // Test flow
    // -------------------------------------------------------
    integer cycle, errors;

    initial begin
        errors = 0;
        reset  = 1'b1;

        $display("============================================================");
        $display("  Sum 1+2+...+100 Testbench");
        $display("  Expected: port_out[0] = 0x13BA = 5050 after HALT");
        $display("============================================================");

        repeat (5) @(posedge clk);
        #1;
        reset = 1'b0;
        $display("[%0t] Reset released.", $time);

        // ~101*38 + overhead micro-cycles, budget 10000
        cycle = 0;
        while (!halted && cycle < 10000) begin
            @(posedge clk); #1;
            cycle = cycle + 1;
        end

        if (!halted) begin
            $display("[FAIL] CPU did not HALT within 10000 cycles (PC=0x%02h)", tb_PC);
            errors = errors + 1;
        end else begin
            $display("[%0t] HALT after %0d post-reset cycles.", $time, cycle);
        end

        repeat (3) @(posedge clk); #1;

        // -------------------------------------------------------
        // Final state display
        // -------------------------------------------------------
        $display("");
        $display("--- Final Register State ---");
        $display("  CAR        = 0x%02h  (expect 0x50)", tb_CAR);
        $display("  PC         = 0x%02h  (expect 0x0E)", tb_PC);
        $display("  IR         = 0x%02h  (expect 0x07)", tb_IR);
        $display("  ACC        = 0x%04h  (expect 0x13BA)", tb_ACC);
        $display("  MR         = 0x%04h  (expect 0x0000)", tb_MR);
        $display("  port_out[0]= 0x%04h  (expect 0x13BA = 5050)", tb_port_out0);
        $display("  MAR=%02h  MBR=%04h  BR=%04h", tb_MAR, tb_MBR, tb_BR);
        $display("  DM read-port (MAR=0x%02h) = 0x%04h", tb_MAR, tb_dm_dout);
        $display("");

        // -------------------------------------------------------
        // Assertions
        // -------------------------------------------------------
        check_flag("halted",     halted,       1'b1);
        check_8   ("CAR",        tb_CAR,       8'h50);
        check_8   ("PC",         tb_PC,        8'h0E);
        check_8   ("IR",         tb_IR,        8'h07);
        check_16  ("ACC",        tb_ACC,       16'h13BA);
        check_16  ("MR",         tb_MR,        16'h0000);
        check_16  ("port_out[0]",tb_port_out0, 16'h13BA);

        $display("");
        $display("============================================================");
        if (errors == 0)
            $display("  ALL TESTS PASSED  (%0d checks)", 7);
        else
            $display("  %0d TEST(S) FAILED", errors);
        $display("============================================================");
        $finish;
    end

    // -------------------------------------------------------
    // Cycle-by-cycle waveform monitor (every 200 cycles)
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (!reset && (cycle % 200 == 0 || halted))
            $display("[cyc %4d] CAR=%02h PC=%02h IR=%02h ACC=%04h port_out[0]=%04h HALT=%b",
                     cycle, tb_CAR, tb_PC, tb_IR, tb_ACC, tb_port_out0, halted);
    end

    // -------------------------------------------------------
    // Check tasks
    // -------------------------------------------------------
    task check_flag;
        input [63:0] name; input actual, expected;
        begin
            if (actual === expected)
                $display("  PASS: %-12s = %b", name, actual);
            else begin
                $display("  FAIL: %-12s expected %b, got %b", name, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task check_8;
        input [63:0] name; input [7:0] actual, expected;
        begin
            if (actual === expected)
                $display("  PASS: %-12s = 0x%02h", name, actual);
            else begin
                $display("  FAIL: %-12s expected 0x%02h, got 0x%02h", name, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task check_16;
        input [63:0] name; input [15:0] actual, expected;
        begin
            if (actual === expected)
                $display("  PASS: %-12s = 0x%04h", name, actual);
            else begin
                $display("  FAIL: %-12s expected 0x%04h, got 0x%04h", name, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

endmodule
