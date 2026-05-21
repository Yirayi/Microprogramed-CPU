// ============================================================
// ALL_top.v
// System Top-Level: CPU + peripherals
//
// Peripherals:
//   seven_seg_decimal – displays port_out[0] as 4 hex digits
//
// I/O:
//   clk   – board clock (e.g. 100 MHz)
//   reset – active-high synchronous reset (e.g. BTNC)
//   AN    – 7-segment anode  [7:0], active-low
//   SEG   – 7-segment cathode[6:0], active-low, segments {g,f,e,d,c,b,a}
// ============================================================
`timescale 1ns / 1ps

module ALL_top (
    input  wire       clk,
    input  wire       reset_btn,
    output wire [7:0] AN,
    output wire [6:0] SEG
);
    wire reset = ~reset_btn;  // 取反，按下按钮才触发高电平复位
    wire halted;
    wire [3:0][15:0] port_out;

    CPU_top cpu (
        .clk     (clk),
        .reset   (reset),
        .halted  (halted),
        .port_out(port_out),
        .port_in ('0)
    );

    seven_seg_decimal seg_disp (
        .clk  (clk),
        .reset(reset),
        .value(port_out[0]),
        .AN   (AN),
        .SEG  (SEG)
    );

endmodule
