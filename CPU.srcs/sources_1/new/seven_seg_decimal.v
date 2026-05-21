// ============================================================
// seven_seg_decimal.v
// Time-multiplexed 4-digit hex display driver
// Displays a 16-bit value as four hex digits on a common-anode
// 7-segment display (e.g. Nexys A7 rightmost 4 digits).
//
// Digit mapping:  AN[0]=digit0(LSB nibble) .. AN[3]=digit3(MSB nibble)
// Active-low anodes (AN) and active-low segments (SEG).
// Segment order: SEG[6:0] = {g,f,e,d,c,b,a}
// ============================================================
`timescale 1ns / 1ps

module seven_seg_decimal (
    input  wire        clk,
    input  wire        reset,
    input  wire [15:0] value,
    output reg  [7:0]  AN,
    output reg  [6:0]  SEG
);
    // ~1 ms digit period at 100 MHz: 17-bit counter, top 2 bits select digit
    reg [18:0] refresh_cnt;
    always @(posedge clk or posedge reset) begin
        if (reset) refresh_cnt <= '0;
        else       refresh_cnt <= refresh_cnt + 1'b1;
    end

    wire [1:0] sel = refresh_cnt[18:17];

    // Select active nibble
    reg [3:0] nibble;
    always @(*) begin
        case (sel)
            2'd0: nibble = value[3:0];
            2'd1: nibble = value[7:4];
            2'd2: nibble = value[11:8];
            2'd3: nibble = value[15:12];
        endcase
    end

    // Anode: only one digit active at a time (active-low, upper 4 off)
    always @(*) begin
        AN = 8'b1111_1111;
        AN[sel] = 1'b0;
    end

    // Hex segment decoder (active-low, segments gfedcba)
    always @(*) begin
        case (nibble)
            4'h0: SEG = 7'b100_0000;
            4'h1: SEG = 7'b111_1001;
            4'h2: SEG = 7'b010_0100;
            4'h3: SEG = 7'b011_0000;
            4'h4: SEG = 7'b001_1001;
            4'h5: SEG = 7'b001_0010;
            4'h6: SEG = 7'b000_0010;
            4'h7: SEG = 7'b111_1000;
            4'h8: SEG = 7'b000_0000;
            4'h9: SEG = 7'b001_0000;
            4'hA: SEG = 7'b000_1000;
            4'hB: SEG = 7'b000_0011;
            4'hC: SEG = 7'b100_0110;
            4'hD: SEG = 7'b010_0001;
            4'hE: SEG = 7'b000_0110;
            4'hF: SEG = 7'b000_1110;
        endcase
    end

endmodule
