// ============================================================
// vga_display.v
// VGA 640x480@60Hz output – shows CPU register state
//
// video_bus[96:0] packing (from CPU_top):
//   [7:0]   MAR   [23:8]  MBR   [31:24] PC   [39:32] IR
//   [55:40] BR    [71:56] ACC   [87:72] MR   [95:88] CAR
//   [96]    halted
//
// Display: 9-char × 8-row text panel in top-right corner
//   x: 568..639  y: 8..71  (each char 8×8 px)
//   Layout per row:  AAA:XXXX
//     col0-2 = register name, col3 = ':', col4-7 = hex value
//
// Font indices: 0-15 = hex '0'-'F'
//               16=' '  17=':'  18='P'  19='I'  20='R'  21='M'
// ============================================================
`timescale 1ns / 1ps

module vga_display (
    input  wire        clk,
    input  wire        reset,
    input  wire [96:0] video_bus,
    output wire        vga_hs,
    output wire        vga_vs,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b
);

// --- Unpack video_bus ---
wire [7:0]  v_MAR    = video_bus[7:0];
wire [15:0] v_MBR    = video_bus[23:8];
wire [7:0]  v_PC     = video_bus[31:24];
wire [7:0]  v_IR     = video_bus[39:32];
wire [15:0] v_BR     = video_bus[55:40];
wire [15:0] v_ACC    = video_bus[71:56];
wire [15:0] v_MR     = video_bus[87:72];
wire [7:0]  v_CAR    = video_bus[95:88];
wire        v_halted = video_bus[96];

// --- Pixel clock enable: 25 MHz effective rate (100 MHz ÷ 4) ---
// Uses clock-enable on the 100 MHz master clock to avoid Vivado
// derived-clock DRC errors that occur with 'posedge pclk'.
reg [1:0] cdiv;
always @(posedge clk or posedge reset)
    if (reset) cdiv <= 0; else cdiv <= cdiv + 1;
wire pclk_en = (cdiv == 2'd3); // one-cycle pulse every 4 clk cycles

// --- VGA 640×480@60Hz counters (100 MHz clock, advance on pclk_en) ---
localparam H_ACT=640, H_TOT=800;
localparam H_SS=656,  H_SE=752;   // hsync active window
localparam V_ACT=480, V_TOT=525;
localparam V_SS=490,  V_SE=492;   // vsync active window

reg [9:0] hc, vc;
always @(posedge clk or posedge reset) begin
    if (reset) begin hc <= 0; vc <= 0; end
    else if (pclk_en) begin
        if (hc == H_TOT-1) begin
            hc <= 0;
            vc <= (vc == V_TOT-1) ? 10'd0 : vc + 1;
        end else hc <= hc + 1;
    end
end

assign vga_hs = ~(hc >= H_SS && hc < H_SE);
assign vga_vs = ~(vc >= V_SS && vc < V_SE);
wire active = (hc < H_ACT) && (vc < V_ACT);

// --- Font ROM: 22 chars × 8 rows, addressed as {char_idx[4:0], row[2:0]} ---
(* rom_style = "distributed" *) reg [7:0] fnt [0:255];
initial begin
    // '0'
    fnt[  0]=8'h3C; fnt[  1]=8'h66; fnt[  2]=8'h6E; fnt[  3]=8'h76;
    fnt[  4]=8'h66; fnt[  5]=8'h66; fnt[  6]=8'h3C; fnt[  7]=8'h00;
    // '1'
    fnt[  8]=8'h18; fnt[  9]=8'h1C; fnt[ 10]=8'h18; fnt[ 11]=8'h18;
    fnt[ 12]=8'h18; fnt[ 13]=8'h18; fnt[ 14]=8'h7E; fnt[ 15]=8'h00;
    // '2'
    fnt[ 16]=8'h3C; fnt[ 17]=8'h66; fnt[ 18]=8'h60; fnt[ 19]=8'h38;
    fnt[ 20]=8'h0C; fnt[ 21]=8'h66; fnt[ 22]=8'h7E; fnt[ 23]=8'h00;
    // '3'
    fnt[ 24]=8'h3C; fnt[ 25]=8'h66; fnt[ 26]=8'h60; fnt[ 27]=8'h38;
    fnt[ 28]=8'h60; fnt[ 29]=8'h66; fnt[ 30]=8'h3C; fnt[ 31]=8'h00;
    // '4'
    fnt[ 32]=8'h30; fnt[ 33]=8'h38; fnt[ 34]=8'h3C; fnt[ 35]=8'h36;
    fnt[ 36]=8'h7E; fnt[ 37]=8'h30; fnt[ 38]=8'h30; fnt[ 39]=8'h00;
    // '5'
    fnt[ 40]=8'h7E; fnt[ 41]=8'h06; fnt[ 42]=8'h3E; fnt[ 43]=8'h60;
    fnt[ 44]=8'h60; fnt[ 45]=8'h66; fnt[ 46]=8'h3C; fnt[ 47]=8'h00;
    // '6'
    fnt[ 48]=8'h38; fnt[ 49]=8'h0C; fnt[ 50]=8'h06; fnt[ 51]=8'h3E;
    fnt[ 52]=8'h66; fnt[ 53]=8'h66; fnt[ 54]=8'h3C; fnt[ 55]=8'h00;
    // '7'
    fnt[ 56]=8'h7E; fnt[ 57]=8'h66; fnt[ 58]=8'h30; fnt[ 59]=8'h18;
    fnt[ 60]=8'h0C; fnt[ 61]=8'h0C; fnt[ 62]=8'h0C; fnt[ 63]=8'h00;
    // '8'
    fnt[ 64]=8'h3C; fnt[ 65]=8'h66; fnt[ 66]=8'h66; fnt[ 67]=8'h3C;
    fnt[ 68]=8'h66; fnt[ 69]=8'h66; fnt[ 70]=8'h3C; fnt[ 71]=8'h00;
    // '9'
    fnt[ 72]=8'h3C; fnt[ 73]=8'h66; fnt[ 74]=8'h66; fnt[ 75]=8'h7C;
    fnt[ 76]=8'h60; fnt[ 77]=8'h30; fnt[ 78]=8'h1E; fnt[ 79]=8'h00;
    // 'A' (idx 10)
    fnt[ 80]=8'h18; fnt[ 81]=8'h3C; fnt[ 82]=8'h66; fnt[ 83]=8'h7E;
    fnt[ 84]=8'h66; fnt[ 85]=8'h66; fnt[ 86]=8'h66; fnt[ 87]=8'h00;
    // 'B' (idx 11)
    fnt[ 88]=8'h3E; fnt[ 89]=8'h66; fnt[ 90]=8'h66; fnt[ 91]=8'h3E;
    fnt[ 92]=8'h66; fnt[ 93]=8'h66; fnt[ 94]=8'h3E; fnt[ 95]=8'h00;
    // 'C' (idx 12)
    fnt[ 96]=8'h3C; fnt[ 97]=8'h66; fnt[ 98]=8'h06; fnt[ 99]=8'h06;
    fnt[100]=8'h06; fnt[101]=8'h66; fnt[102]=8'h3C; fnt[103]=8'h00;
    // 'D' (idx 13)
    fnt[104]=8'h1E; fnt[105]=8'h36; fnt[106]=8'h66; fnt[107]=8'h66;
    fnt[108]=8'h66; fnt[109]=8'h36; fnt[110]=8'h1E; fnt[111]=8'h00;
    // 'E' (idx 14)
    fnt[112]=8'h7E; fnt[113]=8'h06; fnt[114]=8'h06; fnt[115]=8'h3E;
    fnt[116]=8'h06; fnt[117]=8'h06; fnt[118]=8'h7E; fnt[119]=8'h00;
    // 'F' (idx 15)
    fnt[120]=8'h7E; fnt[121]=8'h06; fnt[122]=8'h06; fnt[123]=8'h3E;
    fnt[124]=8'h06; fnt[125]=8'h06; fnt[126]=8'h06; fnt[127]=8'h00;
    // ' ' (idx 16)
    fnt[128]=8'h00; fnt[129]=8'h00; fnt[130]=8'h00; fnt[131]=8'h00;
    fnt[132]=8'h00; fnt[133]=8'h00; fnt[134]=8'h00; fnt[135]=8'h00;
    // ':' (idx 17)
    fnt[136]=8'h00; fnt[137]=8'h18; fnt[138]=8'h18; fnt[139]=8'h00;
    fnt[140]=8'h18; fnt[141]=8'h18; fnt[142]=8'h00; fnt[143]=8'h00;
    // 'P' (idx 18)
    fnt[144]=8'h3E; fnt[145]=8'h66; fnt[146]=8'h66; fnt[147]=8'h3E;
    fnt[148]=8'h06; fnt[149]=8'h06; fnt[150]=8'h06; fnt[151]=8'h00;
    // 'I' (idx 19)
    fnt[152]=8'h3C; fnt[153]=8'h18; fnt[154]=8'h18; fnt[155]=8'h18;
    fnt[156]=8'h18; fnt[157]=8'h18; fnt[158]=8'h3C; fnt[159]=8'h00;
    // 'R' (idx 20)
    fnt[160]=8'h3E; fnt[161]=8'h66; fnt[162]=8'h66; fnt[163]=8'h3E;
    fnt[164]=8'h1E; fnt[165]=8'h36; fnt[166]=8'h66; fnt[167]=8'h00;
    // 'M' (idx 21)
    fnt[168]=8'h63; fnt[169]=8'h77; fnt[170]=8'h7F; fnt[171]=8'h6B;
    fnt[172]=8'h63; fnt[173]=8'h63; fnt[174]=8'h63; fnt[175]=8'h00;
end

// --- Text panel: x=[568,640), y=[8,72), 9 chars × 8 rows ---
wire in_panel = active && (hc >= 10'd568) && (vc >= 10'd8) && (vc < 10'd72);
wire [9:0] tx = hc - 10'd568;   // 0..71
wire [9:0] ty = vc - 10'd8;     // 0..63

wire [3:0] ccol = tx[6:3];  // char column 0..8  (tx/8, needs 4 bits for col 8)
wire [2:0] crow = ty[5:3];  // char row    0..7
wire [2:0] fpx  = tx[2:0];  // pixel column within char
wire [2:0] frow = ty[2:0];  // pixel row within char

// --- Character lookup ---
reg [4:0] cidx;
always @(*) begin
    cidx = 5'd16; // default: space
    case (crow)
        // Row 0: PC  :00XX  (8-bit, show as 00HH)
        3'd0: case (ccol)
            4'd0: cidx = 5'd18;                   // P
            4'd1: cidx = 5'd12;                   // C
            4'd2: cidx = 5'd16;                   // space
            4'd3: cidx = 5'd17;                   // :
            4'd4: cidx = 5'd0;                    // 0
            4'd5: cidx = 5'd0;                    // 0
            4'd6: cidx = {1'b0, v_PC[7:4]};
            4'd7: cidx = {1'b0, v_PC[3:0]};
            default: cidx = 5'd16;
        endcase
        // Row 1: MAR :00XX
        3'd1: case (ccol)
            4'd0: cidx = 5'd21;                   // M
            4'd1: cidx = 5'd10;                   // A
            4'd2: cidx = 5'd20;                   // R
            4'd3: cidx = 5'd17;                   // :
            4'd4: cidx = 5'd0;
            4'd5: cidx = 5'd0;
            4'd6: cidx = {1'b0, v_MAR[7:4]};
            4'd7: cidx = {1'b0, v_MAR[3:0]};
            default: cidx = 5'd16;
        endcase
        // Row 2: IR  :00XX
        3'd2: case (ccol)
            4'd0: cidx = 5'd19;                   // I
            4'd1: cidx = 5'd20;                   // R
            4'd2: cidx = 5'd16;
            4'd3: cidx = 5'd17;
            4'd4: cidx = 5'd0;
            4'd5: cidx = 5'd0;
            4'd6: cidx = {1'b0, v_IR[7:4]};
            4'd7: cidx = {1'b0, v_IR[3:0]};
            default: cidx = 5'd16;
        endcase
        // Row 3: CAR :00XX
        3'd3: case (ccol)
            4'd0: cidx = 5'd12;                   // C
            4'd1: cidx = 5'd10;                   // A
            4'd2: cidx = 5'd20;                   // R
            4'd3: cidx = 5'd17;
            4'd4: cidx = 5'd0;
            4'd5: cidx = 5'd0;
            4'd6: cidx = {1'b0, v_CAR[7:4]};
            4'd7: cidx = {1'b0, v_CAR[3:0]};
            default: cidx = 5'd16;
        endcase
        // Row 4: MBR :XXXX  (16-bit)
        3'd4: case (ccol)
            4'd0: cidx = 5'd21;                   // M
            4'd1: cidx = 5'd11;                   // B
            4'd2: cidx = 5'd20;                   // R
            4'd3: cidx = 5'd17;
            4'd4: cidx = {1'b0, v_MBR[15:12]};
            4'd5: cidx = {1'b0, v_MBR[11:8]};
            4'd6: cidx = {1'b0, v_MBR[7:4]};
            4'd7: cidx = {1'b0, v_MBR[3:0]};
            default: cidx = 5'd16;
        endcase
        // Row 5: BR  :XXXX
        3'd5: case (ccol)
            4'd0: cidx = 5'd11;                   // B
            4'd1: cidx = 5'd20;                   // R
            4'd2: cidx = 5'd16;
            4'd3: cidx = 5'd17;
            4'd4: cidx = {1'b0, v_BR[15:12]};
            4'd5: cidx = {1'b0, v_BR[11:8]};
            4'd6: cidx = {1'b0, v_BR[7:4]};
            4'd7: cidx = {1'b0, v_BR[3:0]};
            default: cidx = 5'd16;
        endcase
        // Row 6: ACC :XXXX
        3'd6: case (ccol)
            4'd0: cidx = 5'd10;                   // A
            4'd1: cidx = 5'd12;                   // C
            4'd2: cidx = 5'd12;                   // C
            4'd3: cidx = 5'd17;
            4'd4: cidx = {1'b0, v_ACC[15:12]};
            4'd5: cidx = {1'b0, v_ACC[11:8]};
            4'd6: cidx = {1'b0, v_ACC[7:4]};
            4'd7: cidx = {1'b0, v_ACC[3:0]};
            default: cidx = 5'd16;
        endcase
        // Row 7: MR  :XXXX
        3'd7: case (ccol)
            4'd0: cidx = 5'd21;                   // M
            4'd1: cidx = 5'd20;                   // R
            4'd2: cidx = 5'd16;
            4'd3: cidx = 5'd17;
            4'd4: cidx = {1'b0, v_MR[15:12]};
            4'd5: cidx = {1'b0, v_MR[11:8]};
            4'd6: cidx = {1'b0, v_MR[7:4]};
            4'd7: cidx = {1'b0, v_MR[3:0]};
            default: cidx = 5'd16;
        endcase
        default: cidx = 5'd16;
    endcase
end

// --- Font pixel ---
wire [7:0] fbyte = fnt[{cidx, frow}];          // {5-bit char, 3-bit row} = 8-bit addr
wire px = in_panel && fbyte[fpx];

// --- Separator: 2px vertical gray line at x=566..567 ---
wire sep = active && (hc >= 10'd566) && (hc < 10'd568);

// --- Color output ---
// Panel bg: dark navy; text: white; halted: tint red; separator: gray
wire [3:0] txt_r = v_halted ? 4'hF : 4'hF;
wire [3:0] txt_g = v_halted ? 4'h4 : 4'hF;
wire [3:0] txt_b = v_halted ? 4'h4 : 4'hF;

assign vga_r = !active ? 4'h0 : px ? txt_r : sep ? 4'h5 : in_panel ? 4'h0 : 4'h0;
assign vga_g = !active ? 4'h0 : px ? txt_g : sep ? 4'h5 : in_panel ? 4'h0 : 4'h0;
assign vga_b = !active ? 4'h0 : px ? txt_b : sep ? 4'h5 : in_panel ? 4'h2 : 4'h0;

endmodule
