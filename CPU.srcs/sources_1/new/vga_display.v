// ============================================================
// vga_display.v
// VGA 640x480@60Hz output – CPU register state + instruction history
//
// video_bus[96:0] packing (from CPU_top):
//   [7:0]   MAR   [23:8]  MBR   [31:24] PC   [39:32] IR
//   [55:40] BR    [71:56] ACC   [87:72] MR   [95:88] CAR
//   [96]    halted
//
// RIGHT panel (x=568..639, y=8..71): live register values (9 chars × 8 rows)
// LEFT  panel (x=0..383,   y=0..127): instruction history (48 chars × 16 rows)
//
// Font index table (6-bit cidx, 512-entry array):
//   0-9  = '0'-'9'    10='A' 11='B' 12='C' 13='D' 14='E' 15='F'
//   16=' ' 17=':'     18='P' 19='I' 20='R' 21='M'
//   22='G' 23='H'     24='J' 25='L' 26='N' 27='O'
//   28='S' 29='T'     30='U' 31='Y' 32='Z'
//   33='[' 34=']'     35='<' 36='=' 37='>'
//   38='+' 39='-'     40='X' 41='W' 42='K' 43='V' 44='Q'
//   45='&' 46='|'
// ============================================================
`timescale 1ns / 1ps

// ---- Character index constants ----
`define C0   6'd0
`define C1   6'd1
`define C2f  6'd2
`define C3   6'd3
`define C4   6'd4
`define C5   6'd5
`define C6   6'd6
`define C7   6'd7
`define C8   6'd8
`define C9   6'd9
`define CA   6'd10
`define CB   6'd11
`define CC   6'd12
`define CD   6'd13
`define CE   6'd14
`define CF   6'd15
`define CSP  6'd16  // space
`define CCOL 6'd17  // ':'
`define CP   6'd18
`define CI   6'd19
`define CR   6'd20
`define CM   6'd21
`define CG   6'd22
`define CH   6'd23
`define CJ   6'd24
`define CL   6'd25
`define CN   6'd26
`define CO   6'd27
`define CS   6'd28
`define CT   6'd29
`define CU   6'd30
`define CY   6'd31
`define CZ   6'd32
`define CLBR 6'd33  // '['
`define CRBR 6'd34  // ']'
`define CLT  6'd35  // '<'
`define CEQ  6'd36  // '='
`define CGT  6'd37  // '>'
`define CPLS 6'd38  // '+'
`define CMIN 6'd39  // '-'
`define CX   6'd40
`define CW   6'd41
`define CK   6'd42
`define CV   6'd43
`define CQ   6'd44
`define CAND 6'd45  // '&'
`define COR  6'd46  // '|'

module vga_display (
    input  wire        clk,
    input  wire        reset,
    input  wire [96:0] video_bus,
    // single-step history control
    input  wire [1:0]  exec_mode,
    input  wire        capture_pulse,  // 1-cycle negedge pulse from ControlUnit
    input  wire [7:0]  snap_car,       // pre-advance CAR (micro-step)
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
reg [1:0] cdiv;
always @(posedge clk or posedge reset)
    if (reset) cdiv <= 0; else cdiv <= cdiv + 1;
wire pclk_en = (cdiv == 2'd3);

// --- VGA 640×480@60Hz counters ---
localparam H_ACT=640, H_TOT=800;
localparam H_SS=656,  H_SE=752;
localparam V_ACT=480, V_TOT=525;
localparam V_SS=490,  V_SE=492;

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

// ============================================================
// Font ROM: 47 chars × 8 rows = 376 entries, array size 512
// Address: {cidx[5:0], row[2:0]} = 9-bit
// ============================================================
(* rom_style = "distributed" *) reg [7:0] fnt [0:511];
initial begin
    // '0' (idx 0)
    fnt[  0]=8'h3C; fnt[  1]=8'h66; fnt[  2]=8'h6E; fnt[  3]=8'h76;
    fnt[  4]=8'h66; fnt[  5]=8'h66; fnt[  6]=8'h3C; fnt[  7]=8'h00;
    // '1' (idx 1)
    fnt[  8]=8'h18; fnt[  9]=8'h1C; fnt[ 10]=8'h18; fnt[ 11]=8'h18;
    fnt[ 12]=8'h18; fnt[ 13]=8'h18; fnt[ 14]=8'h7E; fnt[ 15]=8'h00;
    // '2' (idx 2)
    fnt[ 16]=8'h3C; fnt[ 17]=8'h66; fnt[ 18]=8'h60; fnt[ 19]=8'h38;
    fnt[ 20]=8'h0C; fnt[ 21]=8'h66; fnt[ 22]=8'h7E; fnt[ 23]=8'h00;
    // '3' (idx 3)
    fnt[ 24]=8'h3C; fnt[ 25]=8'h66; fnt[ 26]=8'h60; fnt[ 27]=8'h38;
    fnt[ 28]=8'h60; fnt[ 29]=8'h66; fnt[ 30]=8'h3C; fnt[ 31]=8'h00;
    // '4' (idx 4)
    fnt[ 32]=8'h30; fnt[ 33]=8'h38; fnt[ 34]=8'h3C; fnt[ 35]=8'h36;
    fnt[ 36]=8'h7E; fnt[ 37]=8'h30; fnt[ 38]=8'h30; fnt[ 39]=8'h00;
    // '5' (idx 5)
    fnt[ 40]=8'h7E; fnt[ 41]=8'h06; fnt[ 42]=8'h3E; fnt[ 43]=8'h60;
    fnt[ 44]=8'h60; fnt[ 45]=8'h66; fnt[ 46]=8'h3C; fnt[ 47]=8'h00;
    // '6' (idx 6)
    fnt[ 48]=8'h38; fnt[ 49]=8'h0C; fnt[ 50]=8'h06; fnt[ 51]=8'h3E;
    fnt[ 52]=8'h66; fnt[ 53]=8'h66; fnt[ 54]=8'h3C; fnt[ 55]=8'h00;
    // '7' (idx 7)
    fnt[ 56]=8'h7E; fnt[ 57]=8'h66; fnt[ 58]=8'h30; fnt[ 59]=8'h18;
    fnt[ 60]=8'h0C; fnt[ 61]=8'h0C; fnt[ 62]=8'h0C; fnt[ 63]=8'h00;
    // '8' (idx 8)
    fnt[ 64]=8'h3C; fnt[ 65]=8'h66; fnt[ 66]=8'h66; fnt[ 67]=8'h3C;
    fnt[ 68]=8'h66; fnt[ 69]=8'h66; fnt[ 70]=8'h3C; fnt[ 71]=8'h00;
    // '9' (idx 9)
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
    // 'G' (idx 22)
    fnt[176]=8'h3C; fnt[177]=8'h66; fnt[178]=8'h06; fnt[179]=8'h36;
    fnt[180]=8'h66; fnt[181]=8'h66; fnt[182]=8'h3C; fnt[183]=8'h00;
    // 'H' (idx 23)
    fnt[184]=8'h66; fnt[185]=8'h66; fnt[186]=8'h66; fnt[187]=8'h7E;
    fnt[188]=8'h66; fnt[189]=8'h66; fnt[190]=8'h66; fnt[191]=8'h00;
    // 'J' (idx 24)
    fnt[192]=8'h1C; fnt[193]=8'h08; fnt[194]=8'h08; fnt[195]=8'h08;
    fnt[196]=8'h08; fnt[197]=8'h68; fnt[198]=8'h38; fnt[199]=8'h00;
    // 'L' (idx 25)
    fnt[200]=8'h60; fnt[201]=8'h60; fnt[202]=8'h60; fnt[203]=8'h60;
    fnt[204]=8'h60; fnt[205]=8'h60; fnt[206]=8'h7E; fnt[207]=8'h00;
    // 'N' (idx 26)
    fnt[208]=8'h66; fnt[209]=8'h76; fnt[210]=8'h7E; fnt[211]=8'h6E;
    fnt[212]=8'h66; fnt[213]=8'h66; fnt[214]=8'h66; fnt[215]=8'h00;
    // 'O' (idx 27)
    fnt[216]=8'h3C; fnt[217]=8'h66; fnt[218]=8'h66; fnt[219]=8'h66;
    fnt[220]=8'h66; fnt[221]=8'h66; fnt[222]=8'h3C; fnt[223]=8'h00;
    // 'S' (idx 28)
    fnt[224]=8'h3C; fnt[225]=8'h66; fnt[226]=8'h06; fnt[227]=8'h3C;
    fnt[228]=8'h60; fnt[229]=8'h66; fnt[230]=8'h3C; fnt[231]=8'h00;
    // 'T' (idx 29)
    fnt[232]=8'h7E; fnt[233]=8'h18; fnt[234]=8'h18; fnt[235]=8'h18;
    fnt[236]=8'h18; fnt[237]=8'h18; fnt[238]=8'h18; fnt[239]=8'h00;
    // 'U' (idx 30)
    fnt[240]=8'h66; fnt[241]=8'h66; fnt[242]=8'h66; fnt[243]=8'h66;
    fnt[244]=8'h66; fnt[245]=8'h66; fnt[246]=8'h3C; fnt[247]=8'h00;
    // 'Y' (idx 31)
    fnt[248]=8'h66; fnt[249]=8'h66; fnt[250]=8'h66; fnt[251]=8'h3C;
    fnt[252]=8'h18; fnt[253]=8'h18; fnt[254]=8'h18; fnt[255]=8'h00;
    // 'Z' (idx 32)
    fnt[256]=8'h7E; fnt[257]=8'h60; fnt[258]=8'h30; fnt[259]=8'h18;
    fnt[260]=8'h0C; fnt[261]=8'h06; fnt[262]=8'h7E; fnt[263]=8'h00;
    // '[' (idx 33)
    fnt[264]=8'h38; fnt[265]=8'h20; fnt[266]=8'h20; fnt[267]=8'h20;
    fnt[268]=8'h20; fnt[269]=8'h20; fnt[270]=8'h38; fnt[271]=8'h00;
    // ']' (idx 34)
    fnt[272]=8'h1C; fnt[273]=8'h04; fnt[274]=8'h04; fnt[275]=8'h04;
    fnt[276]=8'h04; fnt[277]=8'h04; fnt[278]=8'h1C; fnt[279]=8'h00;
    // '<' (idx 35)
    fnt[280]=8'h08; fnt[281]=8'h10; fnt[282]=8'h20; fnt[283]=8'h40;
    fnt[284]=8'h20; fnt[285]=8'h10; fnt[286]=8'h08; fnt[287]=8'h00;
    // '=' (idx 36)
    fnt[288]=8'h00; fnt[289]=8'h00; fnt[290]=8'h7E; fnt[291]=8'h00;
    fnt[292]=8'h7E; fnt[293]=8'h00; fnt[294]=8'h00; fnt[295]=8'h00;
    // '>' (idx 37)
    fnt[296]=8'h10; fnt[297]=8'h08; fnt[298]=8'h04; fnt[299]=8'h02;
    fnt[300]=8'h04; fnt[301]=8'h08; fnt[302]=8'h10; fnt[303]=8'h00;
    // '+' (idx 38)
    fnt[304]=8'h00; fnt[305]=8'h18; fnt[306]=8'h18; fnt[307]=8'h7E;
    fnt[308]=8'h18; fnt[309]=8'h18; fnt[310]=8'h00; fnt[311]=8'h00;
    // '-' (idx 39)
    fnt[312]=8'h00; fnt[313]=8'h00; fnt[314]=8'h00; fnt[315]=8'h7E;
    fnt[316]=8'h00; fnt[317]=8'h00; fnt[318]=8'h00; fnt[319]=8'h00;
    // 'X' (idx 40)
    fnt[320]=8'h66; fnt[321]=8'h66; fnt[322]=8'h3C; fnt[323]=8'h18;
    fnt[324]=8'h3C; fnt[325]=8'h66; fnt[326]=8'h66; fnt[327]=8'h00;
    // 'W' (idx 41)
    fnt[328]=8'h63; fnt[329]=8'h63; fnt[330]=8'h63; fnt[331]=8'h6B;
    fnt[332]=8'h7F; fnt[333]=8'h77; fnt[334]=8'h63; fnt[335]=8'h00;
    // 'K' (idx 42)
    fnt[336]=8'h66; fnt[337]=8'h6C; fnt[338]=8'h78; fnt[339]=8'h70;
    fnt[340]=8'h78; fnt[341]=8'h6C; fnt[342]=8'h66; fnt[343]=8'h00;
    // 'V' (idx 43)
    fnt[344]=8'h66; fnt[345]=8'h66; fnt[346]=8'h66; fnt[347]=8'h66;
    fnt[348]=8'h3C; fnt[349]=8'h3C; fnt[350]=8'h18; fnt[351]=8'h00;
    // 'Q' (idx 44)
    fnt[352]=8'h3C; fnt[353]=8'h66; fnt[354]=8'h66; fnt[355]=8'h66;
    fnt[356]=8'h76; fnt[357]=8'h6C; fnt[358]=8'h78; fnt[359]=8'h00;
    // '&' (idx 45)
    fnt[360]=8'h1C; fnt[361]=8'h36; fnt[362]=8'h36; fnt[363]=8'h1C;
    fnt[364]=8'h6E; fnt[365]=8'h66; fnt[366]=8'h7C; fnt[367]=8'h00;
    // '|' (idx 46)
    fnt[368]=8'h18; fnt[369]=8'h18; fnt[370]=8'h18; fnt[371]=8'h18;
    fnt[372]=8'h18; fnt[373]=8'h18; fnt[374]=8'h18; fnt[375]=8'h00;
end

// ============================================================
// RIGHT panel: x=[568,640), y=[8,72), 9 chars × 8 rows
// ============================================================
wire in_panel = active && (hc >= 10'd568) && (vc >= 10'd8) && (vc < 10'd72);
wire [9:0] tx = hc - 10'd568;
wire [9:0] ty = vc - 10'd8;

wire [3:0] ccol = tx[6:3];
wire [2:0] crow = ty[5:3];
wire [2:0] fpx  = tx[2:0];
wire [2:0] frow = ty[2:0];

reg [5:0] cidx;
always @(*) begin
    cidx = `CSP;
    case (crow)
        3'd0: case (ccol)   // PC  :00XX
            4'd0: cidx = `CP;
            4'd1: cidx = `CC;
            4'd2: cidx = `CSP;
            4'd3: cidx = `CCOL;
            4'd4: cidx = `C0;
            4'd5: cidx = `C0;
            4'd6: cidx = {2'b0, v_PC[7:4]};
            4'd7: cidx = {2'b0, v_PC[3:0]};
            default: cidx = `CSP;
        endcase
        3'd1: case (ccol)   // MAR :00XX
            4'd0: cidx = `CM;
            4'd1: cidx = `CA;
            4'd2: cidx = `CR;
            4'd3: cidx = `CCOL;
            4'd4: cidx = `C0;
            4'd5: cidx = `C0;
            4'd6: cidx = {2'b0, v_MAR[7:4]};
            4'd7: cidx = {2'b0, v_MAR[3:0]};
            default: cidx = `CSP;
        endcase
        3'd2: case (ccol)   // IR  :00XX
            4'd0: cidx = `CI;
            4'd1: cidx = `CR;
            4'd2: cidx = `CSP;
            4'd3: cidx = `CCOL;
            4'd4: cidx = `C0;
            4'd5: cidx = `C0;
            4'd6: cidx = {2'b0, v_IR[7:4]};
            4'd7: cidx = {2'b0, v_IR[3:0]};
            default: cidx = `CSP;
        endcase
        3'd3: case (ccol)   // CAR :00XX
            4'd0: cidx = `CC;
            4'd1: cidx = `CA;
            4'd2: cidx = `CR;
            4'd3: cidx = `CCOL;
            4'd4: cidx = `C0;
            4'd5: cidx = `C0;
            4'd6: cidx = {2'b0, v_CAR[7:4]};
            4'd7: cidx = {2'b0, v_CAR[3:0]};
            default: cidx = `CSP;
        endcase
        3'd4: case (ccol)   // MBR :XXXX
            4'd0: cidx = `CM;
            4'd1: cidx = `CB;
            4'd2: cidx = `CR;
            4'd3: cidx = `CCOL;
            4'd4: cidx = {2'b0, v_MBR[15:12]};
            4'd5: cidx = {2'b0, v_MBR[11:8]};
            4'd6: cidx = {2'b0, v_MBR[7:4]};
            4'd7: cidx = {2'b0, v_MBR[3:0]};
            default: cidx = `CSP;
        endcase
        3'd5: case (ccol)   // BR  :XXXX
            4'd0: cidx = `CB;
            4'd1: cidx = `CR;
            4'd2: cidx = `CSP;
            4'd3: cidx = `CCOL;
            4'd4: cidx = {2'b0, v_BR[15:12]};
            4'd5: cidx = {2'b0, v_BR[11:8]};
            4'd6: cidx = {2'b0, v_BR[7:4]};
            4'd7: cidx = {2'b0, v_BR[3:0]};
            default: cidx = `CSP;
        endcase
        3'd6: case (ccol)   // ACC :XXXX
            4'd0: cidx = `CA;
            4'd1: cidx = `CC;
            4'd2: cidx = `CC;
            4'd3: cidx = `CCOL;
            4'd4: cidx = {2'b0, v_ACC[15:12]};
            4'd5: cidx = {2'b0, v_ACC[11:8]};
            4'd6: cidx = {2'b0, v_ACC[7:4]};
            4'd7: cidx = {2'b0, v_ACC[3:0]};
            default: cidx = `CSP;
        endcase
        3'd7: case (ccol)   // MR  :XXXX
            4'd0: cidx = `CM;
            4'd1: cidx = `CR;
            4'd2: cidx = `CSP;
            4'd3: cidx = `CCOL;
            4'd4: cidx = {2'b0, v_MR[15:12]};
            4'd5: cidx = {2'b0, v_MR[11:8]};
            4'd6: cidx = {2'b0, v_MR[7:4]};
            4'd7: cidx = {2'b0, v_MR[3:0]};
            default: cidx = `CSP;
        endcase
        default: cidx = `CSP;
    endcase
end

wire [7:0] fbyte = fnt[{cidx, frow}];
wire px = in_panel && fbyte[7 - fpx];

// ============================================================
// LEFT panel: x=[0,384), y=[0,128), 48 chars × 16 rows
// History ring buffer: 16 entries
//   type=0: instr-step  {1'b0, v_IR[7:0], v_MAR[7:0]} = 17 bits
//   type=1: micro-step  {1'b1, snap_car[7:0], 8'h0}
// ============================================================

// Ring buffer storage (power-on init to all spaces / type=0 / empty)
reg [16:0] hist [0:15];
reg  [3:0] hist_head;
integer    hist_init_i;
initial begin
    for (hist_init_i = 0; hist_init_i < 16; hist_init_i = hist_init_i+1)
        hist[hist_init_i] = 17'h0;
end

// Capture: negedge-generated capture_pulse, resync to posedge domain
reg  cap_d1;
always @(posedge clk or posedge reset) begin
    if (reset) begin
        cap_d1    <= 1'b0;
        hist_head <= 4'd0;
    end else begin
        cap_d1 <= capture_pulse;
        // Rising edge of capture_pulse (negedge→posedge transfer, 1-cycle pulse)
        if (capture_pulse && !cap_d1) begin
            if (exec_mode == 2'b01)
                hist[hist_head] <= {1'b0, v_IR, v_MAR};
            else
                hist[hist_head] <= {1'b1, snap_car, 8'h0};
            hist_head <= hist_head + 1'd1;
        end
    end
end

// Rendering signals
wire in_left  = active && (hc < 10'd384) && (vc < 10'd128);
wire [8:0] ltx = hc[8:0];          // 0..383
wire [8:0] lty = vc[8:0];          // 0..127

wire [5:0] lcol = ltx[8:3];        // char column 0..47
wire [3:0] lrow = lty[6:3];        // char row    0..15
wire [2:0] lfpx = ltx[2:0];        // pixel col within char
wire [2:0] lfrow= lty[2:0];        // pixel row within char

// Which ring buffer entry corresponds to display row lrow?
// hist_head points to next-write; oldest = hist_head, newest = hist_head-1
wire [3:0] bidx = hist_head + {lrow};
wire [16:0] cur_entry   = hist[bidx];
wire        cur_type    = cur_entry[16];
wire [7:0]  cur_ir      = cur_entry[15:8];
wire [7:0]  cur_operand = cur_entry[7:0];

// ---- Helper: hex nibble -> font index ----
function [5:0] nibble_idx;
    input [3:0] n;
    nibble_idx = {2'b0, n};   // 0..15 map directly
endfunction

// ---- Instruction mnemonic: 6 chars (col 0..5) ----
function [5:0] mnemonic_char;
    input [7:0] ir;
    input [2:0] pos;   // 0..5
    reg [5:0] m [0:5];
    integer j;
    begin
        // default: spaces
        for (j = 0; j < 6; j = j+1) m[j] = `CSP;
        case (ir)
            8'h01: begin m[0]=`CS; m[1]=`CT; m[2]=`CO; m[3]=`CR; m[4]=`CE; end            // STORE
            8'h02: begin m[0]=`CL; m[1]=`CO; m[2]=`CA; m[3]=`CD; end                      // LOAD
            8'h03: begin m[0]=`CA; m[1]=`CD; m[2]=`CD; end                                 // ADD
            8'h04: begin m[0]=`CS; m[1]=`CU; m[2]=`CB; end                                 // SUB
            8'h05: begin m[0]=`CJ; m[1]=`CM; m[2]=`CP; m[3]=`CG; m[4]=`CE; m[5]=`CZ; end // JMPGEZ
            8'h06: begin m[0]=`CJ; m[1]=`CM; m[2]=`CP; end                                 // JMP
            8'h07: begin m[0]=`CH; m[1]=`CA; m[2]=`CL; m[3]=`CT; end                      // HALT
            8'h08: begin m[0]=`CM; m[1]=`CP; m[2]=`CY; end                                 // MPY
            8'h09: begin m[0]=`CL; m[1]=`CO; m[2]=`CA; m[3]=`CD; m[4]=`CI; end            // LOADI
            8'h0A: begin m[0]=`CA; m[1]=`CN; m[2]=`CD; end                                 // AND
            8'h0B: begin m[0]=`CO; m[1]=`CR; end                                            // OR
            8'h0C: begin m[0]=`CN; m[1]=`CO; m[2]=`CT; end                                 // NOT
            8'h0D: begin m[0]=`CS; m[1]=`CH; m[2]=`CI; m[3]=`CF; m[4]=`CT; m[5]=`CR; end // SHIFTR
            8'h0E: begin m[0]=`CS; m[1]=`CH; m[2]=`CI; m[3]=`CF; m[4]=`CT; m[5]=`CL; end // SHIFTL
            8'h0F: begin m[0]=`CO; m[1]=`CU; m[2]=`CT; end                                 // OUT
            8'h10: begin m[0]=`CI; m[1]=`CN; end                                            // IN
            default: begin m[0]=`C9; m[1]=`C9; m[2]=`C9; end                               // ???
        endcase
        mnemonic_char = m[pos];
    end
endfunction

// ---- Has operand flag ----
function has_operand;
    input [7:0] ir;
    case (ir)
        8'h07: has_operand = 1'b0;   // HALT
        8'h0C: has_operand = 1'b0;   // NOT
        default: has_operand = 1'b1;
    endcase
endfunction

// ---- Micro-op sequence: 34 chars (col 14..47 → uop col 0..33) ----
// Returns font index for position pos (0..33) of instruction ir's uop sequence
function [5:0] uop_char;
    input [7:0] ir;
    input [5:0] pos;
    // MBR<=DM[MAR] = M B R < = D M [ M A R ]   (12 chars)
    //                0 1 2 3 4 5 6 7 8 9 10 11
    // BR<=MBR      = B R < = M B R             (7 chars, start col 13)
    //                13 14 15 16 17 18 19
    // ACC<=BR      = A C C < = B R             (7 chars, start col 20)
    //                20 21 22 23 24 25 26
    begin
        uop_char = `CSP;
        case (ir)
            8'h01: // STORE: MBR<=ACC DM[MAR]<=MBR
                case (pos)
                    6'd0:  uop_char = `CM;
                    6'd1:  uop_char = `CB;
                    6'd2:  uop_char = `CR;
                    6'd3:  uop_char = `CLT;
                    6'd4:  uop_char = `CEQ;
                    6'd5:  uop_char = `CA;
                    6'd6:  uop_char = `CC;
                    6'd7:  uop_char = `CC;
                    6'd8:  uop_char = `CSP;
                    6'd9:  uop_char = `CD;
                    6'd10: uop_char = `CM;
                    6'd11: uop_char = `CLBR;
                    6'd12: uop_char = `CM;
                    6'd13: uop_char = `CA;
                    6'd14: uop_char = `CR;
                    6'd15: uop_char = `CRBR;
                    6'd16: uop_char = `CLT;
                    6'd17: uop_char = `CEQ;
                    6'd18: uop_char = `CM;
                    6'd19: uop_char = `CB;
                    6'd20: uop_char = `CR;
                    default: uop_char = `CSP;
                endcase
            8'h02: // LOAD: MBR<=DM[MAR] BR<=MBR ACC<=BR
                case (pos)
                    6'd0:  uop_char = `CM;
                    6'd1:  uop_char = `CB;
                    6'd2:  uop_char = `CR;
                    6'd3:  uop_char = `CLT;
                    6'd4:  uop_char = `CEQ;
                    6'd5:  uop_char = `CD;
                    6'd6:  uop_char = `CM;
                    6'd7:  uop_char = `CLBR;
                    6'd8:  uop_char = `CM;
                    6'd9:  uop_char = `CA;
                    6'd10: uop_char = `CR;
                    6'd11: uop_char = `CRBR;
                    6'd12: uop_char = `CSP;
                    6'd13: uop_char = `CB;
                    6'd14: uop_char = `CR;
                    6'd15: uop_char = `CLT;
                    6'd16: uop_char = `CEQ;
                    6'd17: uop_char = `CM;
                    6'd18: uop_char = `CB;
                    6'd19: uop_char = `CR;
                    6'd20: uop_char = `CSP;
                    6'd21: uop_char = `CA;
                    6'd22: uop_char = `CC;
                    6'd23: uop_char = `CC;
                    6'd24: uop_char = `CLT;
                    6'd25: uop_char = `CEQ;
                    6'd26: uop_char = `CB;
                    6'd27: uop_char = `CR;
                    default: uop_char = `CSP;
                endcase
            8'h03: // ADD: MBR<=DM[MAR] BR<=MBR ACC<=ACC+BR
                case (pos)
                    6'd0:  uop_char = `CM;
                    6'd1:  uop_char = `CB;
                    6'd2:  uop_char = `CR;
                    6'd3:  uop_char = `CLT;
                    6'd4:  uop_char = `CEQ;
                    6'd5:  uop_char = `CD;
                    6'd6:  uop_char = `CM;
                    6'd7:  uop_char = `CLBR;
                    6'd8:  uop_char = `CM;
                    6'd9:  uop_char = `CA;
                    6'd10: uop_char = `CR;
                    6'd11: uop_char = `CRBR;
                    6'd12: uop_char = `CSP;
                    6'd13: uop_char = `CB;
                    6'd14: uop_char = `CR;
                    6'd15: uop_char = `CLT;
                    6'd16: uop_char = `CEQ;
                    6'd17: uop_char = `CM;
                    6'd18: uop_char = `CB;
                    6'd19: uop_char = `CR;
                    6'd20: uop_char = `CSP;
                    6'd21: uop_char = `CA;
                    6'd22: uop_char = `CC;
                    6'd23: uop_char = `CC;
                    6'd24: uop_char = `CLT;
                    6'd25: uop_char = `CEQ;
                    6'd26: uop_char = `CA;
                    6'd27: uop_char = `CC;
                    6'd28: uop_char = `CC;
                    6'd29: uop_char = `CPLS;
                    6'd30: uop_char = `CB;
                    6'd31: uop_char = `CR;
                    default: uop_char = `CSP;
                endcase
            8'h04: // SUB: MBR<=DM[MAR] BR<=MBR ACC<=ACC-BR
                case (pos)
                    6'd0:  uop_char = `CM;
                    6'd1:  uop_char = `CB;
                    6'd2:  uop_char = `CR;
                    6'd3:  uop_char = `CLT;
                    6'd4:  uop_char = `CEQ;
                    6'd5:  uop_char = `CD;
                    6'd6:  uop_char = `CM;
                    6'd7:  uop_char = `CLBR;
                    6'd8:  uop_char = `CM;
                    6'd9:  uop_char = `CA;
                    6'd10: uop_char = `CR;
                    6'd11: uop_char = `CRBR;
                    6'd12: uop_char = `CSP;
                    6'd13: uop_char = `CB;
                    6'd14: uop_char = `CR;
                    6'd15: uop_char = `CLT;
                    6'd16: uop_char = `CEQ;
                    6'd17: uop_char = `CM;
                    6'd18: uop_char = `CB;
                    6'd19: uop_char = `CR;
                    6'd20: uop_char = `CSP;
                    6'd21: uop_char = `CA;
                    6'd22: uop_char = `CC;
                    6'd23: uop_char = `CC;
                    6'd24: uop_char = `CLT;
                    6'd25: uop_char = `CEQ;
                    6'd26: uop_char = `CA;
                    6'd27: uop_char = `CC;
                    6'd28: uop_char = `CC;
                    6'd29: uop_char = `CMIN;
                    6'd30: uop_char = `CB;
                    6'd31: uop_char = `CR;
                    default: uop_char = `CSP;
                endcase
            8'h05: // JMPGEZ: IF ACC>=0 PC<=MAR
                case (pos)
                    6'd0:  uop_char = `CI;
                    6'd1:  uop_char = `CF;
                    6'd2:  uop_char = `CSP;
                    6'd3:  uop_char = `CA;
                    6'd4:  uop_char = `CC;
                    6'd5:  uop_char = `CC;
                    6'd6:  uop_char = `CGT;
                    6'd7:  uop_char = `CEQ;
                    6'd8:  uop_char = `C0;
                    6'd9:  uop_char = `CCOL;
                    6'd10: uop_char = `CSP;
                    6'd11: uop_char = `CP;
                    6'd12: uop_char = `CC;
                    6'd13: uop_char = `CLT;
                    6'd14: uop_char = `CEQ;
                    6'd15: uop_char = `CM;
                    6'd16: uop_char = `CA;
                    6'd17: uop_char = `CR;
                    default: uop_char = `CSP;
                endcase
            8'h06: // JMP: PC<=MAR
                case (pos)
                    6'd0:  uop_char = `CP;
                    6'd1:  uop_char = `CC;
                    6'd2:  uop_char = `CLT;
                    6'd3:  uop_char = `CEQ;
                    6'd4:  uop_char = `CM;
                    6'd5:  uop_char = `CA;
                    6'd6:  uop_char = `CR;
                    default: uop_char = `CSP;
                endcase
            8'h07: // HALT
                case (pos)
                    6'd0:  uop_char = `CH;
                    6'd1:  uop_char = `CA;
                    6'd2:  uop_char = `CL;
                    6'd3:  uop_char = `CT;
                    default: uop_char = `CSP;
                endcase
            8'h08: // MPY: MBR<=DM[MAR] BR<=MBR MRACC=MUL
                case (pos)
                    6'd0:  uop_char = `CM;
                    6'd1:  uop_char = `CB;
                    6'd2:  uop_char = `CR;
                    6'd3:  uop_char = `CLT;
                    6'd4:  uop_char = `CEQ;
                    6'd5:  uop_char = `CD;
                    6'd6:  uop_char = `CM;
                    6'd7:  uop_char = `CLBR;
                    6'd8:  uop_char = `CM;
                    6'd9:  uop_char = `CA;
                    6'd10: uop_char = `CR;
                    6'd11: uop_char = `CRBR;
                    6'd12: uop_char = `CSP;
                    6'd13: uop_char = `CB;
                    6'd14: uop_char = `CR;
                    6'd15: uop_char = `CLT;
                    6'd16: uop_char = `CEQ;
                    6'd17: uop_char = `CM;
                    6'd18: uop_char = `CB;
                    6'd19: uop_char = `CR;
                    6'd20: uop_char = `CSP;
                    6'd21: uop_char = `CM;
                    6'd22: uop_char = `CR;
                    6'd23: uop_char = `CA;
                    6'd24: uop_char = `CC;
                    6'd25: uop_char = `CC;
                    6'd26: uop_char = `CLT;
                    6'd27: uop_char = `CEQ;
                    6'd28: uop_char = `CM;
                    6'd29: uop_char = `CU;
                    6'd30: uop_char = `CL;
                    default: uop_char = `CSP;
                endcase
            8'h09: // LOADI: ACC<=SEXT OPERAND
                case (pos)
                    6'd0:  uop_char = `CA;
                    6'd1:  uop_char = `CC;
                    6'd2:  uop_char = `CC;
                    6'd3:  uop_char = `CLT;
                    6'd4:  uop_char = `CEQ;
                    6'd5:  uop_char = `CS;
                    6'd6:  uop_char = `CE;
                    6'd7:  uop_char = `CX;
                    6'd8:  uop_char = `CT;
                    6'd9:  uop_char = `CSP;
                    6'd10: uop_char = `CO;
                    6'd11: uop_char = `CP;
                    6'd12: uop_char = `CE;
                    6'd13: uop_char = `CR;
                    6'd14: uop_char = `CA;
                    6'd15: uop_char = `CN;
                    6'd16: uop_char = `CD;
                    default: uop_char = `CSP;
                endcase
            8'h0A: // AND: MBR<=DM[MAR] BR<=MBR ACC<=ACC&BR
                case (pos)
                    6'd0:  uop_char = `CM;
                    6'd1:  uop_char = `CB;
                    6'd2:  uop_char = `CR;
                    6'd3:  uop_char = `CLT;
                    6'd4:  uop_char = `CEQ;
                    6'd5:  uop_char = `CD;
                    6'd6:  uop_char = `CM;
                    6'd7:  uop_char = `CLBR;
                    6'd8:  uop_char = `CM;
                    6'd9:  uop_char = `CA;
                    6'd10: uop_char = `CR;
                    6'd11: uop_char = `CRBR;
                    6'd12: uop_char = `CSP;
                    6'd13: uop_char = `CB;
                    6'd14: uop_char = `CR;
                    6'd15: uop_char = `CLT;
                    6'd16: uop_char = `CEQ;
                    6'd17: uop_char = `CM;
                    6'd18: uop_char = `CB;
                    6'd19: uop_char = `CR;
                    6'd20: uop_char = `CSP;
                    6'd21: uop_char = `CA;
                    6'd22: uop_char = `CC;
                    6'd23: uop_char = `CC;
                    6'd24: uop_char = `CLT;
                    6'd25: uop_char = `CEQ;
                    6'd26: uop_char = `CA;
                    6'd27: uop_char = `CC;
                    6'd28: uop_char = `CC;
                    6'd29: uop_char = `CAND;
                    6'd30: uop_char = `CB;
                    6'd31: uop_char = `CR;
                    default: uop_char = `CSP;
                endcase
            8'h0B: // OR: MBR<=DM[MAR] BR<=MBR ACC<=ACC|BR
                case (pos)
                    6'd0:  uop_char = `CM;
                    6'd1:  uop_char = `CB;
                    6'd2:  uop_char = `CR;
                    6'd3:  uop_char = `CLT;
                    6'd4:  uop_char = `CEQ;
                    6'd5:  uop_char = `CD;
                    6'd6:  uop_char = `CM;
                    6'd7:  uop_char = `CLBR;
                    6'd8:  uop_char = `CM;
                    6'd9:  uop_char = `CA;
                    6'd10: uop_char = `CR;
                    6'd11: uop_char = `CRBR;
                    6'd12: uop_char = `CSP;
                    6'd13: uop_char = `CB;
                    6'd14: uop_char = `CR;
                    6'd15: uop_char = `CLT;
                    6'd16: uop_char = `CEQ;
                    6'd17: uop_char = `CM;
                    6'd18: uop_char = `CB;
                    6'd19: uop_char = `CR;
                    6'd20: uop_char = `CSP;
                    6'd21: uop_char = `CA;
                    6'd22: uop_char = `CC;
                    6'd23: uop_char = `CC;
                    6'd24: uop_char = `CLT;
                    6'd25: uop_char = `CEQ;
                    6'd26: uop_char = `CA;
                    6'd27: uop_char = `CC;
                    6'd28: uop_char = `CC;
                    6'd29: uop_char = `COR;
                    6'd30: uop_char = `CB;
                    6'd31: uop_char = `CR;
                    default: uop_char = `CSP;
                endcase
            8'h0C: // NOT: ACC<=NOT ACC
                case (pos)
                    6'd0:  uop_char = `CA;
                    6'd1:  uop_char = `CC;
                    6'd2:  uop_char = `CC;
                    6'd3:  uop_char = `CLT;
                    6'd4:  uop_char = `CEQ;
                    6'd5:  uop_char = `CN;
                    6'd6:  uop_char = `CO;
                    6'd7:  uop_char = `CT;
                    6'd8:  uop_char = `CSP;
                    6'd9:  uop_char = `CA;
                    6'd10: uop_char = `CC;
                    6'd11: uop_char = `CC;
                    default: uop_char = `CSP;
                endcase
            8'h0D: // SHIFTR: MBR<=DM[MAR] BR<=MBR ACC=BR>>1
                case (pos)
                    6'd0:  uop_char = `CM;
                    6'd1:  uop_char = `CB;
                    6'd2:  uop_char = `CR;
                    6'd3:  uop_char = `CLT;
                    6'd4:  uop_char = `CEQ;
                    6'd5:  uop_char = `CD;
                    6'd6:  uop_char = `CM;
                    6'd7:  uop_char = `CLBR;
                    6'd8:  uop_char = `CM;
                    6'd9:  uop_char = `CA;
                    6'd10: uop_char = `CR;
                    6'd11: uop_char = `CRBR;
                    6'd12: uop_char = `CSP;
                    6'd13: uop_char = `CB;
                    6'd14: uop_char = `CR;
                    6'd15: uop_char = `CLT;
                    6'd16: uop_char = `CEQ;
                    6'd17: uop_char = `CM;
                    6'd18: uop_char = `CB;
                    6'd19: uop_char = `CR;
                    6'd20: uop_char = `CSP;
                    6'd21: uop_char = `CA;
                    6'd22: uop_char = `CC;
                    6'd23: uop_char = `CC;
                    6'd24: uop_char = `CLT;
                    6'd25: uop_char = `CEQ;
                    6'd26: uop_char = `CB;
                    6'd27: uop_char = `CR;
                    6'd28: uop_char = `CGT;
                    6'd29: uop_char = `CGT;
                    6'd30: uop_char = `C1;
                    default: uop_char = `CSP;
                endcase
            8'h0E: // SHIFTL: MBR<=DM[MAR] BR<=MBR ACC=BR<<1
                case (pos)
                    6'd0:  uop_char = `CM;
                    6'd1:  uop_char = `CB;
                    6'd2:  uop_char = `CR;
                    6'd3:  uop_char = `CLT;
                    6'd4:  uop_char = `CEQ;
                    6'd5:  uop_char = `CD;
                    6'd6:  uop_char = `CM;
                    6'd7:  uop_char = `CLBR;
                    6'd8:  uop_char = `CM;
                    6'd9:  uop_char = `CA;
                    6'd10: uop_char = `CR;
                    6'd11: uop_char = `CRBR;
                    6'd12: uop_char = `CSP;
                    6'd13: uop_char = `CB;
                    6'd14: uop_char = `CR;
                    6'd15: uop_char = `CLT;
                    6'd16: uop_char = `CEQ;
                    6'd17: uop_char = `CM;
                    6'd18: uop_char = `CB;
                    6'd19: uop_char = `CR;
                    6'd20: uop_char = `CSP;
                    6'd21: uop_char = `CA;
                    6'd22: uop_char = `CC;
                    6'd23: uop_char = `CC;
                    6'd24: uop_char = `CLT;
                    6'd25: uop_char = `CEQ;
                    6'd26: uop_char = `CB;
                    6'd27: uop_char = `CR;
                    6'd28: uop_char = `CLT;
                    6'd29: uop_char = `CLT;
                    6'd30: uop_char = `C1;
                    default: uop_char = `CSP;
                endcase
            8'h0F: // OUT: PORT[XX]<=ACC (XX=operand)
                case (pos)
                    6'd0:  uop_char = `CP;
                    6'd1:  uop_char = `CO;
                    6'd2:  uop_char = `CR;
                    6'd3:  uop_char = `CT;
                    6'd4:  uop_char = `CLBR;
                    6'd5:  uop_char = `CX;
                    6'd6:  uop_char = `CX;
                    6'd7:  uop_char = `CRBR;
                    6'd8:  uop_char = `CLT;
                    6'd9:  uop_char = `CEQ;
                    6'd10: uop_char = `CA;
                    6'd11: uop_char = `CC;
                    6'd12: uop_char = `CC;
                    default: uop_char = `CSP;
                endcase
            8'h10: // IN: MBR=PORT[XX] BR<=MBR ACC<=BR
                case (pos)
                    6'd0:  uop_char = `CM;
                    6'd1:  uop_char = `CB;
                    6'd2:  uop_char = `CR;
                    6'd3:  uop_char = `CLT;
                    6'd4:  uop_char = `CEQ;
                    6'd5:  uop_char = `CP;
                    6'd6:  uop_char = `CO;
                    6'd7:  uop_char = `CR;
                    6'd8:  uop_char = `CT;
                    6'd9:  uop_char = `CLBR;
                    6'd10: uop_char = `CX;
                    6'd11: uop_char = `CX;
                    6'd12: uop_char = `CRBR;
                    6'd13: uop_char = `CSP;
                    6'd14: uop_char = `CB;
                    6'd15: uop_char = `CR;
                    6'd16: uop_char = `CLT;
                    6'd17: uop_char = `CEQ;
                    6'd18: uop_char = `CM;
                    6'd19: uop_char = `CB;
                    6'd20: uop_char = `CR;
                    6'd21: uop_char = `CSP;
                    6'd22: uop_char = `CA;
                    6'd23: uop_char = `CC;
                    6'd24: uop_char = `CC;
                    6'd25: uop_char = `CLT;
                    6'd26: uop_char = `CEQ;
                    6'd27: uop_char = `CB;
                    6'd28: uop_char = `CR;
                    default: uop_char = `CSP;
                endcase
            default: uop_char = `CSP;
        endcase
    end
endfunction

// ---- Micro-step display: CAR=XX : <description> (48 chars) ----
// Returns char index for column pos (0..47)
function [5:0] micro_char;
    input [7:0] car;
    input [5:0] pos;
    // Micro-op name table: 32 chars starting at pos=9
    // car_desc[0..31] defined per CAR value
    reg [5:0] desc [0:31];
    integer k;
    begin
        for (k = 0; k < 32; k = k+1) desc[k] = `CSP;
        case (car)
            8'h00: begin // MAR<=PC
                desc[ 0]=`CM; desc[ 1]=`CA; desc[ 2]=`CR;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CP; desc[ 6]=`CC; end
            8'h01: begin // MBR<=IM[MAR]
                desc[ 0]=`CM; desc[ 1]=`CB; desc[ 2]=`CR;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CI; desc[ 6]=`CM;
                desc[ 7]=`CLBR; desc[ 8]=`CM; desc[ 9]=`CA; desc[10]=`CR; desc[11]=`CRBR; end
            8'h02: begin // IR,MAR,PC,DISP
                desc[ 0]=`CI; desc[ 1]=`CR; desc[ 2]=`CSP;
                desc[ 3]=`CM; desc[ 4]=`CA; desc[ 5]=`CR; desc[ 6]=`CSP;
                desc[ 7]=`CP; desc[ 8]=`CC; desc[ 9]=`CSP;
                desc[10]=`CD; desc[11]=`CI; desc[12]=`CS; desc[13]=`CP; end
            8'h10: begin // MBR<=ACC
                desc[ 0]=`CM; desc[ 1]=`CB; desc[ 2]=`CR;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CA; desc[ 6]=`CC; desc[ 7]=`CC; end
            8'h11: begin // DM[MAR]<=MBR
                desc[ 0]=`CD; desc[ 1]=`CM;
                desc[ 2]=`CLBR; desc[ 3]=`CM; desc[ 4]=`CA; desc[ 5]=`CR; desc[ 6]=`CRBR;
                desc[ 7]=`CLT; desc[ 8]=`CEQ;
                desc[ 9]=`CM; desc[10]=`CB; desc[11]=`CR; end
            8'h20, 8'h30, 8'h38, 8'h58, 8'h68, 8'h70, 8'h80, 8'h88: begin // MBR<=DM[MAR]
                desc[ 0]=`CM; desc[ 1]=`CB; desc[ 2]=`CR;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CD; desc[ 6]=`CM;
                desc[ 7]=`CLBR; desc[ 8]=`CM; desc[ 9]=`CA; desc[10]=`CR; desc[11]=`CRBR; end
            8'h21, 8'h31, 8'h39, 8'h59, 8'h69, 8'h71, 8'h81, 8'h89: begin // BR<=MBR
                desc[ 0]=`CB; desc[ 1]=`CR;
                desc[ 2]=`CLT; desc[ 3]=`CEQ;
                desc[ 4]=`CM; desc[ 5]=`CB; desc[ 6]=`CR; end
            8'h22: begin // ACC<=BR
                desc[ 0]=`CA; desc[ 1]=`CC; desc[ 2]=`CC;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CB; desc[ 6]=`CR; end
            8'h32: begin // ACC<=ACC+BR
                desc[ 0]=`CA; desc[ 1]=`CC; desc[ 2]=`CC;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CA; desc[ 6]=`CC; desc[ 7]=`CC;
                desc[ 8]=`CPLS; desc[ 9]=`CB; desc[10]=`CR; end
            8'h3A: begin // ACC<=ACC-BR
                desc[ 0]=`CA; desc[ 1]=`CC; desc[ 2]=`CC;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CA; desc[ 6]=`CC; desc[ 7]=`CC;
                desc[ 8]=`CMIN; desc[ 9]=`CB; desc[10]=`CR; end
            8'h40: begin // JMPGEZ:PC<=MAR
                desc[ 0]=`CJ; desc[ 1]=`CM; desc[ 2]=`CP; desc[ 3]=`CG; desc[ 4]=`CE; desc[ 5]=`CZ;
                desc[ 6]=`CCOL; desc[ 7]=`CP; desc[ 8]=`CC;
                desc[ 9]=`CLT; desc[10]=`CEQ; desc[11]=`CM; desc[12]=`CA; desc[13]=`CR; end
            8'h48: begin // JMP:PC<=MAR
                desc[ 0]=`CJ; desc[ 1]=`CM; desc[ 2]=`CP; desc[ 3]=`CCOL;
                desc[ 4]=`CP; desc[ 5]=`CC;
                desc[ 6]=`CLT; desc[ 7]=`CEQ; desc[ 8]=`CM; desc[ 9]=`CA; desc[10]=`CR; end
            8'h50: begin // HALT
                desc[ 0]=`CH; desc[ 1]=`CA; desc[ 2]=`CL; desc[ 3]=`CT; end
            8'h5A: begin // MRACC<=MUL
                desc[ 0]=`CM; desc[ 1]=`CR; desc[ 2]=`CA; desc[ 3]=`CC; desc[ 4]=`CC;
                desc[ 5]=`CLT; desc[ 6]=`CEQ;
                desc[ 7]=`CM; desc[ 8]=`CU; desc[ 9]=`CL; end
            8'h6A: begin // ACC<=ACC&BR
                desc[ 0]=`CA; desc[ 1]=`CC; desc[ 2]=`CC;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CA; desc[ 6]=`CC; desc[ 7]=`CC;
                desc[ 8]=`CAND; desc[ 9]=`CB; desc[10]=`CR; end
            8'h72: begin // ACC<=ACC|BR
                desc[ 0]=`CA; desc[ 1]=`CC; desc[ 2]=`CC;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CA; desc[ 6]=`CC; desc[ 7]=`CC;
                desc[ 8]=`COR; desc[ 9]=`CB; desc[10]=`CR; end
            8'h78: begin // ACC<=NOT ACC
                desc[ 0]=`CA; desc[ 1]=`CC; desc[ 2]=`CC;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CN; desc[ 6]=`CO; desc[ 7]=`CT; desc[ 8]=`CSP;
                desc[ 9]=`CA; desc[10]=`CC; desc[11]=`CC; end
            8'h82: begin // ACC<=BR>>1
                desc[ 0]=`CA; desc[ 1]=`CC; desc[ 2]=`CC;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CB; desc[ 6]=`CR;
                desc[ 7]=`CGT; desc[ 8]=`CGT; desc[ 9]=`C1; end
            8'h8A: begin // ACC<=BR<<1
                desc[ 0]=`CA; desc[ 1]=`CC; desc[ 2]=`CC;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CB; desc[ 6]=`CR;
                desc[ 7]=`CLT; desc[ 8]=`CLT; desc[ 9]=`C1; end
            8'h90: begin // ACC<=SEXT OPERAND
                desc[ 0]=`CA; desc[ 1]=`CC; desc[ 2]=`CC;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CS; desc[ 6]=`CE; desc[ 7]=`CX; desc[ 8]=`CT; desc[ 9]=`CSP;
                desc[10]=`CO; desc[11]=`CP; desc[12]=`CE; desc[13]=`CR; desc[14]=`CA; desc[15]=`CN; desc[16]=`CD; end
            8'hA0: begin // PORT[MAR]<=ACC
                desc[ 0]=`CP; desc[ 1]=`CO; desc[ 2]=`CR; desc[ 3]=`CT;
                desc[ 4]=`CLBR; desc[ 5]=`CM; desc[ 6]=`CA; desc[ 7]=`CR; desc[ 8]=`CRBR;
                desc[ 9]=`CLT; desc[10]=`CEQ;
                desc[11]=`CA; desc[12]=`CC; desc[13]=`CC; end
            8'hA8: begin // MBR<=PORT[MAR]
                desc[ 0]=`CM; desc[ 1]=`CB; desc[ 2]=`CR;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CP; desc[ 6]=`CO; desc[ 7]=`CR; desc[ 8]=`CT;
                desc[ 9]=`CLBR; desc[10]=`CM; desc[11]=`CA; desc[12]=`CR; desc[13]=`CRBR; end
            8'hA9: begin // BR<=MBR (IN step2)
                desc[ 0]=`CB; desc[ 1]=`CR;
                desc[ 2]=`CLT; desc[ 3]=`CEQ;
                desc[ 4]=`CM; desc[ 5]=`CB; desc[ 6]=`CR; end
            8'hAA: begin // ACC<=BR (IN step3)
                desc[ 0]=`CA; desc[ 1]=`CC; desc[ 2]=`CC;
                desc[ 3]=`CLT; desc[ 4]=`CEQ;
                desc[ 5]=`CB; desc[ 6]=`CR; end
            default: begin
                desc[ 0]=6'd0; desc[ 1]=6'd0; desc[ 2]=6'd0; end  // 000
        endcase
        // Map pos to output
        // pos 0..2: 'C' 'A' 'R'
        // pos 3..4: car high/low nibble hex
        // pos 5: space, pos 6: ':', pos 7: space
        // pos 8..47: desc[0..39] (but desc only 32 deep)
        case (pos)
            6'd0:  micro_char = `CC;
            6'd1:  micro_char = `CA;
            6'd2:  micro_char = `CR;
            6'd3:  micro_char = {2'b0, car[7:4]};
            6'd4:  micro_char = {2'b0, car[3:0]};
            6'd5:  micro_char = `CSP;
            6'd6:  micro_char = `CCOL;
            6'd7:  micro_char = `CSP;
            default: micro_char = (pos >= 6'd8 && pos <= 6'd39) ? desc[pos - 6'd8] : `CSP;
        endcase
    end
endfunction

// ---- Instr-step display character decode ----
function [5:0] instr_char;
    input [7:0] ir;
    input [7:0] operand;
    input [5:0] col;
    begin
        instr_char = `CSP;
        if (col <= 6'd5) begin
            instr_char = mnemonic_char(ir, col[2:0]);
        end else if (col == 6'd6) begin
            instr_char = `CSP;
        end else if (col == 6'd7) begin
            instr_char = has_operand(ir) ? `CLBR : `CSP;
        end else if (col == 6'd8) begin
            instr_char = has_operand(ir) ? {2'b0, operand[7:4]} : `CSP;
        end else if (col == 6'd9) begin
            instr_char = has_operand(ir) ? {2'b0, operand[3:0]} : `CSP;
        end else if (col == 6'd10) begin
            instr_char = has_operand(ir) ? `CRBR : `CSP;
        end else if (col == 6'd11) begin
            instr_char = `CSP;
        end else if (col == 6'd12) begin
            instr_char = `CCOL;
        end else if (col == 6'd13) begin
            instr_char = `CSP;
        end else begin
            instr_char = uop_char(ir, col - 6'd14);
        end
    end
endfunction

// ---- Left panel character index lookup ----
reg [5:0] l_cidx;
always @(*) begin
    if (!in_left)
        l_cidx = `CSP;
    else if (cur_type == 1'b0)
        l_cidx = instr_char(cur_ir, cur_operand, lcol);
    else
        l_cidx = micro_char(cur_ir /* cur_ir holds snap_car for micro entries */, lcol);
end

wire [7:0] l_fbyte = fnt[{l_cidx, lfrow}];
wire l_px = in_left && l_fbyte[7 - lfpx];

// ============================================================
// Separators
// ============================================================
// Left panel right edge: x=384..385
wire sep_l = active && (hc >= 10'd384) && (hc < 10'd386);
// Right panel left edge: x=566..567
wire sep_r = active && (hc >= 10'd566) && (hc < 10'd568);

// ============================================================
// Color output
// ============================================================
wire [3:0] txt_r = v_halted ? 4'hF : 4'hF;
wire [3:0] txt_g = v_halted ? 4'h4 : 4'hF;
wire [3:0] txt_b = v_halted ? 4'h4 : 4'hF;

assign vga_r = !active ? 4'h0 :
               l_px    ? txt_r :
               sep_l   ? 4'h5 :
               in_left ? 4'h0 :
               px      ? txt_r :
               sep_r   ? 4'h5 :
               in_panel? 4'h0 : 4'h0;

assign vga_g = !active ? 4'h0 :
               l_px    ? txt_g :
               sep_l   ? 4'h5 :
               in_left ? 4'h0 :
               px      ? txt_g :
               sep_r   ? 4'h5 :
               in_panel? 4'h0 : 4'h0;

assign vga_b = !active ? 4'h0 :
               l_px    ? txt_b :
               sep_l   ? 4'h5 :
               in_left ? 4'h2 :
               px      ? txt_b :
               sep_r   ? 4'h5 :
               in_panel? 4'h2 : 4'h0;

endmodule
