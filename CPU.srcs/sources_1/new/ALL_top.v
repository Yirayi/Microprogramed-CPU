// ============================================================
// ALL_top.v
// System Top-Level: CPU + peripherals
//
// I/O:
//   clk        – 100 MHz board clock
//   reset_btn  – CPU_RESETN (C12, active-low push-button)
//   sw[15:0]   – slide switches
//     sw[11:0] : port IN[0] data (sign-extended 12-bit)
//     sw[15:14]: exec_mode  00=run 01=instr-step 10=micro-step
//   btn_step   – BTNC (N17), single-step advance in step modes
//   AN[7:0]    – 7-segment anode,  active-low
//   SEG[6:0]   – 7-segment cathode, active-low {a,b,c,d,e,f,g}
//   vga_*      – VGA output
// ============================================================
`timescale 1ns / 1ps

module ALL_top (
    input  wire        clk,
    input  wire        reset_btn,
    input  wire [15:0] sw,
    input  wire        btn_step,
    output wire [7:0]  AN,
    output wire [6:0]  SEG,
    // PS2 keyboard
    input  wire        ps2_clk,
    input  wire        ps2_data,
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
    wire [208:0] video_bus;
    wire        capture_pulse;
    wire [7:0]  snap_car;
    wire        scan_done, scan_wr_en;
    wire [7:0]  scan_wr_addr, scan_count;
    wire [15:0] scan_wr_data;

    // PS2 keyboard decoder wires
    wire [7:0]  ps2_key_data;
    wire        ps2_key_valid;
    wire        ps2_char_valid;
    wire [5:0]  ps2_char_data;
    wire        ps2_is_enter;
    wire        ps2_is_backspace;
    wire        ps2_is_tab;
    wire [7:0]  ps2_last_scan;

    // ---- SW 2-stage synchronizer (metastability) ----
    (* ASYNC_REG = "TRUE" *) reg [15:0] sw_s1, sw_s2;
    always @(posedge clk or posedge reset) begin
        if (reset) begin sw_s1 <= 0; sw_s2 <= 0; end
        else        begin sw_s1 <= sw;   sw_s2 <= sw_s1; end
    end

    wire [1:0]  exec_mode = sw_s2[15:14];
    // port_in[0]: SW[11:0] sign-extended to 16 bits (12-bit signed input)
    wire [15:0] sw_port0 = {{4{sw_s2[11]}}, sw_s2[11:0]};

    // ---- BTNC debounce + edge detect ----
    wire step_pulse;
    btn_debounce u_step_db (
        .clk      (clk),
        .reset    (reset),
        .btn_in   (btn_step),
        .btn_out  (),
        .btn_pulse(step_pulse)
    );

    // ---- port_in wiring ----
    wire [3:0][15:0] port_in;
    assign port_in[0] = sw_port0;  // SW[11:0], 12-bit signed, sign-extended to 16
    assign port_in[1] = 16'h0;
    assign port_in[2] = 16'h0;
    assign port_in[3] = 16'h0;

    CPU_top cpu (
        .clk          (clk),
        .reset        (reset),
        .halted       (halted),
        .port_out     (port_out),
        .port_in      (port_in),
        .video_bus    (video_bus),
        .exec_mode    (exec_mode),
        .step_pulse   (step_pulse),
        .capture_pulse(capture_pulse),
        .snap_car     (snap_car),
        .scan_done    (scan_done),
        .scan_wr_en   (scan_wr_en),
        .scan_wr_addr (scan_wr_addr),
        .scan_wr_data (scan_wr_data),
        .scan_count   (scan_count)
    );

    PS2_receiver u_ps2_rx (
        .clk      (clk),
        .rst      (reset),
        .ps2_clk  (ps2_clk),
        .ps2_data (ps2_data),
        .key_data (ps2_key_data),
        .key_valid(ps2_key_valid),
        .parity_error()
    );

    ps2_decoder u_ps2_dec (
        .clk         (clk),
        .rst         (reset),
        .key_data    (ps2_key_data),
        .key_valid   (ps2_key_valid),
        .char_valid  (ps2_char_valid),
        .char_data   (ps2_char_data),
        .is_enter    (ps2_is_enter),
        .is_backspace(ps2_is_backspace),
        .is_tab      (ps2_is_tab),
        .last_scan   (ps2_last_scan)
    );

    seven_seg_decimal seg_disp (
        .clk  (clk),
        .reset(reset),
        .value(port_out[0]),
        .AN   (AN),
        .SEG  (SEG)
    );

    vga_display vga (
        .clk             (clk),
        .reset           (reset),
        .video_bus       (video_bus),
        .exec_mode       (exec_mode),
        .capture_pulse   (capture_pulse),
        .snap_car        (snap_car),
        .scan_done       (scan_done),
        .scan_wr_en      (scan_wr_en),
        .scan_wr_addr    (scan_wr_addr),
        .scan_wr_data    (scan_wr_data),
        .scan_count      (scan_count),
        .ps2_char_valid  (ps2_char_valid),
        .ps2_char_data   (ps2_char_data),
        .ps2_is_enter    (ps2_is_enter),
        .ps2_is_backspace(ps2_is_backspace),
        .ps2_is_tab      (ps2_is_tab),
        .ps2_last_scan   (ps2_last_scan),
        .vga_hs          (vga_hs),
        .vga_vs          (vga_vs),
        .vga_r           (vga_r),
        .vga_g           (vga_g),
        .vga_b           (vga_b)
    );

endmodule
