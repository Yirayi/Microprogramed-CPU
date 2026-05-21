// ============================================================
// sim_LaunchCPU.v
// Testbench: launch ALL_top in free-run mode (SW[15:14]=00)
//
// Drives:
//   clk       – 100 MHz (10 ns period)
//   reset_btn – LOW for 200 ns (→ reset=HIGH active), then HIGH
//   sw        – 16'h0000 (exec_mode=00: free-run, IN[0]=0)
//   btn_step  – 0 (not pressed)
//
// Simulation stops automatically when halted is asserted.
// ============================================================
`timescale 1ns / 1ps

module sim_LaunchCPU;

    // ---- stimulus signals ----
    reg        clk;
    reg        reset_btn;  // CPU_RESETN: 0=reset active, 1=running
    reg [15:0] sw;
    reg        btn_step;

    // ---- DUT outputs (observed in waveform) ----
    wire [7:0] AN;
    wire [6:0] SEG;
    wire       vga_hs, vga_vs;
    wire [3:0] vga_r, vga_g, vga_b;

    // ---- DUT ----
    ALL_top dut (
        .clk      (clk),
        .reset_btn(reset_btn),
        .sw       (sw),
        .btn_step (btn_step),
        .AN       (AN),
        .SEG      (SEG),
        .vga_hs   (vga_hs),
        .vga_vs   (vga_vs),
        .vga_r    (vga_r),
        .vga_g    (vga_g),
        .vga_b    (vga_b)
    );

    // ---- 100 MHz clock ----
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- reset then release ----
    initial begin
        reset_btn = 1'b0;  // assert reset (reset = ~reset_btn = 1)
        sw        = 16'h0000;  // free-run, IN[0]=0
        btn_step  = 1'b0;

        #200;
        reset_btn = 1'b1;  // release reset, CPU starts
    end

    // ---- stop when CPU halts ----
    wire halted = dut.halted;
    always @(posedge halted) begin
        #100;  // let the last few signals settle
        $finish;
    end

    // ---- safety timeout: 10 ms ----
    initial #10_000_000 $finish;

endmodule
