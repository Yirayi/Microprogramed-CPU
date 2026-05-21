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
    input  wire        clk,
    input  wire        reset_btn,
    output wire [7:0]  AN,
    output wire [6:0]  SEG,
    // VGA outputs
    output wire        vga_hs,
    output wire        vga_vs,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b
);
    wire reset = ~reset_btn;
    wire halted;
    wire [3:0][15:0] port_out;
    wire [96:0] video_bus;

    CPU_top cpu (
        .clk      (clk),
        .reset    (reset),
        .halted   (halted),
        .port_out (port_out),
        .port_in  ('0),
        .video_bus(video_bus)
    );

    seven_seg_decimal seg_disp (
        .clk  (clk),
        .reset(reset),
        .value(port_out[0]),
        .AN   (AN),
        .SEG  (SEG)
    );

    vga_display vga (
        .clk      (clk),
        .reset    (reset),
        .video_bus(video_bus),
        .vga_hs   (vga_hs),
        .vga_vs   (vga_vs),
        .vga_r    (vga_r),
        .vga_g    (vga_g),
        .vga_b    (vga_b)
    );

endmodule
