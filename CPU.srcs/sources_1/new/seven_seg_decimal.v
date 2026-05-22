// ============================================================
// seven_seg_decimal.v
// Time-multiplexed 5-digit decimal display driver
//
// Displays a 16-bit unsigned value (0-65535) as five decimal
// digits on the rightmost 5 digits of a common-anode
// 8-digit 7-segment display (Nexys A7).
//
// Pin mapping (must match XDC constraints):
//   AN[0]  = rightmost digit  (ones)
//   AN[1]                     (tens)
//   AN[2]                     (hundreds)
//   AN[3]                     (thousands)
//   AN[4]  = fifth digit      (ten-thousands)
//   AN[5..7] = always off
//
//   SEG[6:0] = {CG,CF,CE,CD,CC,CB,CA} = {g,f,e,d,c,b,a}
//   Active-low: 0 = segment ON, 1 = segment OFF
//   Common anode: AN active-low (0 = digit enabled)
// ============================================================
`timescale 1ns / 1ps

module seven_seg_decimal (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] value,
    output reg  [7:0]  AN,
    output reg  [6:0]  SEG
);

    // BCD decomposition via constant division (synthesizable)
    wire [3:0] d0 = value % 10;           // ones
    wire [3:0] d1 = (value / 10)  % 10;  // tens
    wire [3:0] d2 = (value / 100) % 10;  // hundreds
    wire [3:0] d3 = (value / 1000) % 10; // thousands
    wire [3:0] d4 = value / 10000;        // ten-thousands (0..6)

    // Refresh counter
    // bits[18:16] → 8 states; states 0-4 drive digits, 5-7 blank (short dead time)
    // Each digit period = 2^16 / 100 MHz ≈ 655 µs
    // Full 5-digit refresh ≈ 2^19 / 100 MHz ≈ 5.2 ms (~191 Hz, flicker-free)
    reg [18:0] refresh_cnt;
    always @(posedge clk or posedge reset)
        if (reset) refresh_cnt <= '0;
        else       refresh_cnt <= refresh_cnt + 1;

    wire [2:0] sel = refresh_cnt[18:16]; // 0..7

    // Digit mux and anode control
    reg [3:0] digit;
    always @(*) begin
        AN    = 8'b1111_1111; // all off by default (active-low)
        digit = 4'd0;
        case (sel)
            3'd0: begin AN[0] = 1'b0; digit = d0; end
            3'd1: begin AN[1] = 1'b0; digit = d1; end
            3'd2: begin AN[2] = 1'b0; digit = d2; end
            3'd3: begin AN[3] = 1'b0; digit = d3; end
            3'd4: begin AN[4] = 1'b0; digit = d4; end
            default: ; // states 5-7: all anodes stay off
        endcase
    end

    // Segment decoder
    // XDC pin mapping: SEG[6]=CA(a), SEG[5]=CB(b), SEG[4]=CC(c),
    //                  SEG[3]=CD(d), SEG[2]=CE(e), SEG[1]=CF(f), SEG[0]=CG(g)
    // So SEG[6:0] = {a, b, c, d, e, f, g}  (active-low: 0 = ON)
    //
    //  Digit  Segments ON     {a b c d e f g}
    //    0    a b c d e f      0 0 0 0 0 0 1  = 7'b000_0001
    //    1        b c          1 0 0 1 1 1 1  = 7'b100_1111
    //    2    a b   d e   g    0 0 1 0 0 1 0  = 7'b001_0010
    //    3    a b c d     g    0 0 0 0 1 1 0  = 7'b000_0110
    //    4        b c   f g    1 0 0 1 1 0 0  = 7'b100_1100
    //    5    a   c d   f g    0 1 0 0 1 0 0  = 7'b010_0100
    //    6    a   c d e f g    0 1 0 0 0 0 0  = 7'b010_0000
    //    7    a b c            0 0 0 1 1 1 1  = 7'b000_1111
    //    8    a b c d e f g    0 0 0 0 0 0 0  = 7'b000_0000
    //    9    a b c d   f g    0 0 0 0 1 0 0  = 7'b000_0100
    always @(*) begin
        case (digit)
            4'd0: SEG = 7'b000_0001;
            4'd1: SEG = 7'b100_1111;
            4'd2: SEG = 7'b001_0010;
            4'd3: SEG = 7'b000_0110;
            4'd4: SEG = 7'b100_1100;
            4'd5: SEG = 7'b010_0100;
            4'd6: SEG = 7'b010_0000;
            4'd7: SEG = 7'b000_1111;
            4'd8: SEG = 7'b000_0000;
            4'd9: SEG = 7'b000_0100;
            default: SEG = 7'b111_1111; // all segments off
        endcase
    end

endmodule
