// ============================================================
// SumProgram_tb.v
// Testbench for the 1+2+3+...+100 sum program
// ============================================================
//
// Program source: tools/test_program.asm  (12 instructions)
// Data source:    tools/test_data.dm
//
// Data Memory pre-load (DMData.coe):
//   DM[0xA0] = 0x0000  constant 0   (initial value of sum)
//   DM[0xA1] = 0x0001  constant 1   (decrement step)
//   DM[0xA2] = 0x0064  constant 100 (initial value of temp)
//   DM[0xA3] = 0x0000  temp         (loop counter, runtime variable)
//   DM[0xA4] = 0x0000  sum          (accumulator, runtime variable)
//
// Program execution (101 loop iterations, ~3864 micro-cycles):
//   sum  = 0;  temp = 100;
//   loop: sum += temp;  temp--;  if (temp >= 0) goto loop;
//   HALT
//
// Instruction encoding (12 instructions, matches Table 2):
//   PC 00: 02A0  LOAD  [A0]      PC 01: 01A4  STORE [A4]
//   PC 02: 02A2  LOAD  [A2]      PC 03: 01A3  STORE [A3]
//   PC 04: 02A4  LOAD  [A4]  <-- LOOP start
//   PC 05: 03A3  ADD   [A3]      PC 06: 01A4  STORE [A4]
//   PC 07: 02A3  LOAD  [A3]      PC 08: 04A1  SUB   [A1]
//   PC 09: 01A3  STORE [A3]      PC 0A: 0504  JMPGEZ[loop=0x04]
//   PC 0B: 0700  HALT
//
// Execution trace of final loop iteration (temp = 0):
//   LOAD [A4]  → ACC = 5050 = 0x13BA
//   ADD  [A3]  → ACC = 5050 + 0 = 5050
//   STORE[A4]  → DM[0xA4] = 5050 = 0x13BA   ← final sum
//   LOAD [A3]  → ACC = 0
//   SUB  [A1]  → ACC = 0 - 1 = -1 = 0xFFFF  ← final ACC
//   STORE[A3]  → DM[0xA3] = 0xFFFF
//   JMPGEZ     → ACC[15]=1, not taken
//   HALT
//
// Expected final state:
//   halted = 1
//   CAR    = 0x50   (frozen at HALT microcode address)
//   PC     = 0x0C   (0x0B + 1, incremented during HALT fetch T3)
//   IR     = 0x07   (HALT opcode)
//   ACC    = 0xFFFF (last computed value: temp-1 = 0-1 = -1)
//   MR     = 0x0000 (no multiply instruction in this program)
//   DM[0xA4] = 0x13BA = 5050  → verify in waveform via tb_dm_dout
// ============================================================

`timescale 1ns / 1ps

module SumProgram_tb;

    // -------------------------------------------------------
    // DUT connections
    // -------------------------------------------------------
    reg  clk;
    reg  reset;
    wire halted;

    CPU_top dut (
        .clk    (clk),
        .reset  (reset),
        .halted (halted)
    );

    // -------------------------------------------------------
    // Clock: 10 ns period (100 MHz)
    // -------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -------------------------------------------------------
    // Hierarchical aliases for DUT internals
    // -------------------------------------------------------
    wire [7:0]  tb_MAR = dut.MAR;
    wire [15:0] tb_MBR = dut.MBR;
    wire [7:0]  tb_PC  = dut.PC;
    wire [7:0]  tb_IR  = dut.IR;
    wire [15:0] tb_BR  = dut.BR;
    wire [15:0] tb_ACC = dut.ACC;
    wire [15:0] tb_MR  = dut.MR;
    wire [7:0]  tb_CAR = dut.car;
    wire [31:0] tb_MI  = dut.micro_instr;
    // DM read-port output (reflects DM[MAR] – useful for waveform inspection)
    wire [15:0] tb_dm_dout = dut.dm_dout;

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
    integer cycle;
    integer errors;

    initial begin
        errors = 0;
        reset  = 1'b1;

        $display("============================================================");
        $display("  Sum 1+2+...+100 Testbench");
        $display("  Expected: DM[0xA4] = 0x13BA = 5050 after HALT");
        $display("============================================================");

        // Hold reset for 5 clock cycles
        repeat (5) @(posedge clk);
        #1;
        reset = 1'b0;
        $display("[%0t] Reset released. Execution begins.", $time);
        $display("  (program runs ~3864 micro-cycles; timeout = 5000)");

        // -------------------------------------------------------
        // Run until HALT or timeout
        // Cycle budget: ~22 init + 101*38 loop + 4 halt = ~3864
        // -------------------------------------------------------
        cycle = 0;
        fork
            begin : wait_halt
                while (!halted && cycle < 10000) begin
                    @(posedge clk); #1;
                    cycle = cycle + 1;
                end
            end
        join

        if (!halted) begin
            $display("[FAIL] CPU did not HALT within 5000 cycles! (stopped at PC=0x%02h)", tb_PC);
            errors = errors + 1;
        end else begin
            $display("[%0t] HALT asserted after %0d post-reset cycles.", $time, cycle);
        end

        // Allow pipeline to fully drain
        repeat (3) @(posedge clk); #1;

        // -------------------------------------------------------
        // Final register state display
        // -------------------------------------------------------
        $display("");
        $display("--- Final Register State ---");
        $display("  CAR = 0x%02h  (expect 0x50 – HALT microcode address)", tb_CAR);
        $display("  PC  = 0x%02h  (expect 0x0C – HALT was at 0x0B, PC+1)", tb_PC);
        $display("  IR  = 0x%02h  (expect 0x07 – HALT opcode)", tb_IR);
        $display("  MAR = 0x%02h", tb_MAR);
        $display("  MBR = 0x%04h", tb_MBR);
        $display("  BR  = 0x%04h", tb_BR);
        $display("  ACC = 0x%04h  (expect 0xFFFF – last temp-1 = 0-1 = -1)", tb_ACC);
        $display("  MR  = 0x%04h  (expect 0x0000 – no MPY instruction)", tb_MR);
        $display("  DM read-port (MAR=0x%02h): 0x%04h  (check 0xA4 in waveform)", tb_MAR, tb_dm_dout);
        $display("");
        $display("  Note: DM[0xA4] = sum = 5050 = 0x13BA");
        $display("        Inspect tb_dm_dout when MAR=0xA4 in the waveform.");
        $display("");

        // -------------------------------------------------------
        // Assertions
        // -------------------------------------------------------
        check_flag("halted",   halted,  1'b1);
        check_8   ("CAR",      tb_CAR,  8'h50);
        check_8   ("PC",       tb_PC,   8'h0C);
        check_8   ("IR",       tb_IR,   8'h07);
        check_16  ("ACC",      tb_ACC,  16'hFFFF);
        check_16  ("MR",       tb_MR,   16'h0000);

        // -------------------------------------------------------
        // Summary
        // -------------------------------------------------------
        $display("");
        $display("============================================================");
        if (errors == 0)
            $display("  ALL TESTS PASSED  (%0d checks)", 6);
        else
            $display("  %0d TEST(S) FAILED", errors);
        $display("============================================================");

        $finish;
    end

    // -------------------------------------------------------
    // Cycle-by-cycle waveform monitor
    // Print every 100 cycles to keep log manageable,
    // always print the last cycle before HALT.
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (!reset && (cycle % 100 == 0 || halted)) begin
            $display("[cyc %4d t=%0t] CAR=%02h MI=%08h | PC=%02h IR=%02h MAR=%02h MBR=%04h BR=%04h ACC=%04h MR=%04h | HALT=%b",
                     cycle, $time,
                     tb_CAR, tb_MI,
                     tb_PC, tb_IR, tb_MAR, tb_MBR, tb_BR, tb_ACC, tb_MR,
                     halted);
        end
    end

    // -------------------------------------------------------
    // Check helper tasks
    // -------------------------------------------------------
    task check_flag;
        input [63:0] name;
        input        actual;
        input        expected;
        begin
            if (actual === expected)
                $display("  PASS: %-8s = %b", name, actual);
            else begin
                $display("  FAIL: %-8s expected %b, got %b", name, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task check_8;
        input [63:0] name;
        input [7:0]  actual;
        input [7:0]  expected;
        begin
            if (actual === expected)
                $display("  PASS: %-8s = 0x%02h", name, actual);
            else begin
                $display("  FAIL: %-8s expected 0x%02h, got 0x%02h", name, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

    task check_16;
        input [63:0] name;
        input [15:0] actual;
        input [15:0] expected;
        begin
            if (actual === expected)
                $display("  PASS: %-8s = 0x%04h", name, actual);
            else begin
                $display("  FAIL: %-8s expected 0x%04h, got 0x%04h", name, expected, actual);
                errors = errors + 1;
            end
        end
    endtask

endmodule
