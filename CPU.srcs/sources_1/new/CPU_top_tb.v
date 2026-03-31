// ============================================================
// CPU_top_tb.v
// Testbench for Microprogrammed CPU
// ============================================================
// Verifies the test program stored in IMData.coe against
// pre-loaded data memory values (DMData.coe):
//   DM[0xF0] = 0x0005 (operand A = 5)
//   DM[0xF1] = 0x0003 (operand B = 3)
//
// Test program execution trace:
//   PC 0x00  LOAD   0xF0  -> ACC = 5
//   PC 0x01  ADD    0xF1  -> ACC = 5+3 = 8
//   PC 0x02  STORE  0xF2  -> DM[0xF2] = 8
//   PC 0x03  SUB    0xF0  -> ACC = 8-5 = 3
//   PC 0x04  AND    0xF0  -> ACC = 3 & 5 = 1   (011 & 101 = 001)
//   PC 0x05  OR     0xF1  -> ACC = 1 | 3 = 3   (001 | 011 = 011)
//   PC 0x06  NOT          -> ACC = ~3 = 0xFFFC
//   PC 0x07  SHIFTR 0xF0  -> ACC = DM[0xF0]>>1 = 5>>1 = 2
//   PC 0x08  SHIFTL 0xF0  -> ACC = DM[0xF0]<<1 = 5<<1 = 10 (0x000A)
//   PC 0x09  MPY    0xF1  -> {MR,ACC} = 10*3 = 30 (0x001E), MR=0
//   PC 0x0A  JMPGEZ 0x0C  -> ACC=30>=0, jump taken -> PC=0x0C
//   PC 0x0B  HALT         -> skipped
//   PC 0x0C  JMP    0x0E  -> PC = 0x0E
//   PC 0x0D  HALT         -> skipped (dead code)
//   PC 0x0E  HALT         -> CPU stops
//
// Expected final state:
//   ACC = 0x001E  (30)
//   MR  = 0x0000  (high word of MPY, fits in 16 bits)
//   PC  = 0x0F    (incremented during HALT instruction fetch T3)
//   IR  = 0x07    (HALT opcode)
//   halted = 1
// ============================================================

`timescale 1ns / 1ps

module CPU_top_tb;

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
    // Convenience aliases to DUT internals (hierarchical ref)
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

    // -------------------------------------------------------
    // VCD dump (optional – comment out for pure simulation)
    // -------------------------------------------------------
    initial begin
        $dumpfile("cpu_sim.vcd");
        $dumpvars(0, CPU_top_tb);
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
        $display("  Microprogrammed CPU Testbench");
        $display("============================================================");

        // Hold reset for 5 clock cycles to ensure clean initialisation
        repeat (5) @(posedge clk);
        #1;   // tiny offset so we sample after flip-flop settling
        reset = 1'b0;
        $display("[%0t] Reset released. Execution begins.", $time);

        // -------------------------------------------------------
        // Run until HALT or timeout (300 cycles)
        // -------------------------------------------------------
        cycle = 0;
        fork
            // Branch 1: count cycles and wait for halted
            begin : wait_halt
                while (!halted && cycle < 300) begin
                    @(posedge clk); #1;
                    cycle = cycle + 1;
                end
            end
        join

        if (!halted) begin
            $display("[FAIL] CPU did not HALT within 300 cycles! (stopped at PC=0x%02h)", tb_PC);
            errors = errors + 1;
        end else begin
            $display("[%0t] HALT asserted after ~%0d post-reset cycles.", $time, cycle);
        end

        // Allow pipeline to fully drain
        repeat (3) @(posedge clk); #1;

        // -------------------------------------------------------
        // Final register checks
        // -------------------------------------------------------
        $display("");
        $display("--- Final Register State ---");
        $display("  CAR = 0x%02h  (expect 0x50 – HALT address)", tb_CAR);
        $display("  PC  = 0x%02h  (expect 0x0F)", tb_PC);
        $display("  IR  = 0x%02h  (expect 0x07 – HALT opcode)", tb_IR);
        $display("  MAR = 0x%02h", tb_MAR);
        $display("  MBR = 0x%04h", tb_MBR);
        $display("  BR  = 0x%04h", tb_BR);
        $display("  ACC = 0x%04h  (expect 0x001E = 30)", tb_ACC);
        $display("  MR  = 0x%04h  (expect 0x0000)", tb_MR);
        $display("");

        // ---- halted ----
        check_flag("halted",   halted,  1'b1);

        // ---- CAR must be frozen at HALT address ----
        check_8   ("CAR",      tb_CAR,  8'h50);

        // ---- PC: incremented in HALT fetch T3 (was 0x0E, PC+1 = 0x0F) ----
        check_8   ("PC",       tb_PC,   8'h0F);

        // ---- IR: HALT opcode ----
        check_8   ("IR",       tb_IR,   8'h07);

        // ---- ACC: MPY result low word (10 * 3 = 30 = 0x001E) ----
        check_16  ("ACC",      tb_ACC,  16'h001E);

        // ---- MR: MPY result high word (30 < 0x10000 so MR = 0) ----
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
    // Waveform monitor: print key state each clock cycle
    // -------------------------------------------------------
    always @(posedge clk) begin
        if (!reset) begin
            $display("[cyc %3d t=%0t] CAR=%02h MI=%08h | PC=%02h IR=%02h MAR=%02h MBR=%04h BR=%04h ACC=%04h MR=%04h | HALT=%b",
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
