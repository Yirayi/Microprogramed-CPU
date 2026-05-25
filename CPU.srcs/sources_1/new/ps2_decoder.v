`timescale 1ns / 1ps
// ps2_decoder.v
// Converts PS/2 Set-2 raw scan codes into font-index char events.
// Handles break codes (F0 prefix) and extended codes (E0 prefix).
module ps2_decoder (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  key_data,     // from PS2_receiver.key_data
    input  wire        key_valid,    // 1-cycle pulse from PS2_receiver
    output reg         char_valid,   // 1-cycle pulse: printable char received
    output reg  [5:0]  char_data,    // font ROM index (matches vga_display font table)
    output reg         is_enter,     // 1-cycle: Enter key
    output reg         is_backspace, // 1-cycle: Backspace key
    output reg         is_tab,       // 1-cycle: Tab key
    output reg  [7:0]  last_scan     // last raw scan code (for debug display)
);

localparam IDLE      = 2'd0;
localparam GOT_E0    = 2'd1;  // received extended-key prefix
localparam GOT_F0    = 2'd2;  // received break-code prefix
localparam GOT_E0_F0 = 2'd3;  // received extended break prefix

reg [1:0] state;

// Map PS/2 Set-2 make code → vga_display font index.
// Returns 6'h3F for unmapped keys (used as "invalid" sentinel).
function [5:0] scan_to_font;
    input [7:0] sc;
    begin
        case (sc)
            // Letters A-Z
            8'h1C: scan_to_font = 6'd10; // A
            8'h32: scan_to_font = 6'd11; // B
            8'h21: scan_to_font = 6'd12; // C
            8'h23: scan_to_font = 6'd13; // D
            8'h24: scan_to_font = 6'd14; // E
            8'h2B: scan_to_font = 6'd15; // F
            8'h34: scan_to_font = 6'd22; // G
            8'h33: scan_to_font = 6'd23; // H
            8'h43: scan_to_font = 6'd19; // I
            8'h3B: scan_to_font = 6'd24; // J
            8'h42: scan_to_font = 6'd42; // K
            8'h4B: scan_to_font = 6'd25; // L
            8'h3A: scan_to_font = 6'd21; // M
            8'h31: scan_to_font = 6'd26; // N
            8'h44: scan_to_font = 6'd27; // O
            8'h4D: scan_to_font = 6'd18; // P
            8'h15: scan_to_font = 6'd44; // Q
            8'h2D: scan_to_font = 6'd20; // R
            8'h1B: scan_to_font = 6'd28; // S
            8'h2C: scan_to_font = 6'd29; // T
            8'h3C: scan_to_font = 6'd30; // U
            8'h2A: scan_to_font = 6'd43; // V
            8'h1D: scan_to_font = 6'd41; // W
            8'h22: scan_to_font = 6'd40; // X
            8'h35: scan_to_font = 6'd31; // Y
            8'h1A: scan_to_font = 6'd32; // Z
            // Digits 0-9
            8'h45: scan_to_font = 6'd0;  // 0
            8'h16: scan_to_font = 6'd1;  // 1
            8'h1E: scan_to_font = 6'd2;  // 2
            8'h26: scan_to_font = 6'd3;  // 3
            8'h25: scan_to_font = 6'd4;  // 4
            8'h2E: scan_to_font = 6'd5;  // 5
            8'h36: scan_to_font = 6'd6;  // 6
            8'h3D: scan_to_font = 6'd7;  // 7
            8'h3E: scan_to_font = 6'd8;  // 8
            8'h46: scan_to_font = 6'd9;  // 9
            // Space
            8'h29: scan_to_font = 6'd16; // space
            default: scan_to_font = 6'h3F; // unmapped
        endcase
    end
endfunction

wire [5:0] decoded_font = scan_to_font(key_data);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state        <= IDLE;
        char_valid   <= 1'b0;
        char_data    <= 6'd0;
        is_enter     <= 1'b0;
        is_backspace <= 1'b0;
        is_tab       <= 1'b0;
        last_scan    <= 8'h00;
    end else begin
        char_valid   <= 1'b0;
        is_enter     <= 1'b0;
        is_backspace <= 1'b0;
        is_tab       <= 1'b0;
        if (key_valid) begin
            last_scan <= key_data;
            case (state)
                IDLE: begin
                    if (key_data == 8'hF0)
                        state <= GOT_F0;
                    else if (key_data == 8'hE0)
                        state <= GOT_E0;
                    else if (key_data == 8'h5A)
                        is_enter <= 1'b1;
                    else if (key_data == 8'h66)
                        is_backspace <= 1'b1;
                    else if (key_data == 8'h0D)
                        is_tab <= 1'b1;
                    else if (decoded_font != 6'h3F) begin
                        char_valid <= 1'b1;
                        char_data  <= decoded_font;
                    end
                end
                GOT_E0:    state <= (key_data == 8'hF0) ? GOT_E0_F0 : IDLE;
                GOT_F0:    state <= IDLE; // key release: discard
                GOT_E0_F0: state <= IDLE; // extended key release: discard
                default:   state <= IDLE;
            endcase
        end
    end
end

endmodule
