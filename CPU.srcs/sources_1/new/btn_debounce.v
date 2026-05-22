`timescale 1ns / 1ps
// Button debounce + rising-edge pulse generator.
// Synchronizes async btn_in, waits ~10.5 ms stable, then emits
// a single-posedge-wide pulse on btn_pulse at each rising edge.
module btn_debounce (
    input  wire clk,
    input  wire reset,
    input  wire btn_in,    // raw asynchronous button input
    output reg  btn_out,   // debounced level
    output wire btn_pulse  // one-cycle rising-edge pulse
);
    // 2-stage synchronizer (metastability)
    (* ASYNC_REG = "TRUE" *) reg sync1, sync2;
    always @(posedge clk or posedge reset)
        if (reset) begin sync1 <= 0; sync2 <= 0; end
        else        begin sync1 <= btn_in; sync2 <= sync1; end

    // Counter-based debounce: capture sync2 only after it holds
    // stable for 2^20 cycles (~10.5 ms at 100 MHz)
    reg [19:0] cnt;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cnt     <= 0;
            btn_out <= 0;
        end else if (sync2 != btn_out) begin
            if (cnt == 20'hFFFFF) begin
                btn_out <= sync2;
                cnt     <= 0;
            end else
                cnt <= cnt + 1;
        end else
            cnt <= 0;
    end

    // Rising-edge detector → single-cycle pulse
    reg btn_prev;
    always @(posedge clk or posedge reset)
        if (reset) btn_prev <= 0;
        else       btn_prev <= btn_out;

    assign btn_pulse = btn_out & ~btn_prev;

endmodule
