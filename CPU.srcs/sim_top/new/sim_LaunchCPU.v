// ============================================================
// sim_LaunchCPU.v
// Testbench: single-instruction step mode (SW[15:14]=01)
//
// exec_mode=2'b01: CPU pauses at each instruction boundary and
// waits for a step_pulse before executing the next instruction.
//
// In simulation the btn_debounce timer (~10.5 ms) is bypassed:
// force/release directly drives dut.step_pulse for one 100 MHz
// clock cycle, which is what the hardware button would produce
// after debounce.
//
// Signal hierarchy used:
//   dut.step_pulse          – ALL_top internal wire (forced here)
//   dut.cpu.cu.instr_running – ControlUnit reg: 1 while executing
//   dut.cpu.internal_reset  – CPU_top wire: BRAM init guard
//   dut.halted              – CPU_top output
// ============================================================
`timescale 1ns / 1ps

module sim_LaunchCPU;

    // ---- stimulus ----
    reg        clk;
    reg        reset_btn;
    reg [15:0] sw;
    reg        btn_step;

    // ---- DUT outputs ----
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

    // ---- convenience aliases ----
    wire halted        = dut.halted;
    wire instr_running = dut.cpu.cu.instr_running;

    // ---- task: execute exactly one instruction ----
    // Injects a single-cycle step_pulse (bypassing btn_debounce),
    // then waits until the instruction boundary is reached again.
    // Handles HALT by also watching posedge halted.
    task step_one_instr;
        begin
            // Force step_pulse high for one 100 MHz cycle.
            // The ControlUnit samples it on the next negedge clk.
            @(posedge clk); #1;
            force dut.step_pulse = 1'b1;
            @(posedge clk); #1;
            force dut.step_pulse = 1'b0;
            release dut.step_pulse;

            repeat(10) @(posedge clk);
        end
    endtask

    // ---- main stimulus ----
    initial begin
        reset_btn = 1'b0;     // assert reset  (reset = ~reset_btn = 1)
        sw        = 16'h4000; // exec_mode = 2'b01 (single-instr step)
                              // sw[15]=0, sw[14]=1 → exec_mode[1:0]=01
        btn_step  = 1'b0;

        #200;
        reset_btn = 1'b1;     // release reset

        // Wait until BRAM init guard clears
        @(negedge dut.cpu.internal_reset);
        repeat(6) @(posedge clk);

        // Step through the program one instruction at a time
        while (!halted)
            step_one_instr();

        #100;
        $display("=== CPU halted after single-step run. ===");
        $finish;
    end

    // ---- safety timeout: 1 ms ----
    initial begin
        #1_000_000;
        $display("=== Timeout: simulation did not halt. ===");
        $finish;
    end

endmodule
