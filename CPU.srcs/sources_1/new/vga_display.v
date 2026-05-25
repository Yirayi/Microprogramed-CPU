// ============================================================
// vga_display.v
// VGA 640x480@60Hz output – CPU register state + instruction history
//
// video_bus[128:0] packing (from CPU_top):
//   [7:0]    MAR   [23:8]   MBR   [31:24]  PC    [39:32]  IR
//   [55:40]  BR    [71:56]  ACC   [87:72]  MR    [95:88]  CAR
//   [96]     halted
//   [128:97] micro_instr (current 32-bit microinstruction)
//
// RIGHT panel (x=514..639, y=8..159): live registers + ports + micro_instr + mode (15 chars × 19 rows)
// LEFT  panel (x=0..559,   y=0..255): instruction history (70 chars × 32 rows)
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
    input  wire [208:0] video_bus,
    // single-step history control
    input  wire [1:0]  exec_mode,
    input  wire        capture_pulse,  // 1-cycle negedge pulse from ControlUnit
    input  wire [7:0]  snap_car,       // pre-advance CAR (micro-step)
    // Instruction scan bus (written once at startup, then static)
    input  wire        scan_done,
    input  wire        scan_wr_en,
    input  wire [7:0]  scan_wr_addr,
    input  wire [15:0] scan_wr_data,
    input  wire [7:0]  scan_count,
    // PS2 keyboard input (from ps2_decoder)
    input  wire        ps2_char_valid,
    input  wire [5:0]  ps2_char_data,
    input  wire        ps2_is_enter,
    input  wire        ps2_is_backspace,
    input  wire        ps2_is_tab,
    input  wire [7:0]  ps2_last_scan,
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
wire [31:0] v_MI     = video_bus[128:97];
wire [15:0] v_PI0    = video_bus[144:129];
wire [15:0] v_PO0    = video_bus[160:145];
wire [15:0] v_PO1    = video_bus[176:161];
wire [15:0] v_PO2    = video_bus[192:177];
wire [15:0] v_PO3    = video_bus[208:193];

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
    fnt[192]=8'h38; fnt[193]=8'h10; fnt[194]=8'h10; fnt[195]=8'h10;
    fnt[196]=8'h10; fnt[197]=8'h16; fnt[198]=8'h1C; fnt[199]=8'h00;
    // 'L' (idx 25)
    fnt[200]=8'h06; fnt[201]=8'h06; fnt[202]=8'h06; fnt[203]=8'h06;
    fnt[204]=8'h06; fnt[205]=8'h06; fnt[206]=8'h7E; fnt[207]=8'h00;
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
    // '[' (idx 33) – LSB-first: bar cols 1-3, body col 1
    fnt[264]=8'h0E; fnt[265]=8'h02; fnt[266]=8'h02; fnt[267]=8'h02;
    fnt[268]=8'h02; fnt[269]=8'h02; fnt[270]=8'h0E; fnt[271]=8'h00;
    // ']' (idx 34) – LSB-first: bar cols 4-6, body col 6
    fnt[272]=8'h70; fnt[273]=8'h40; fnt[274]=8'h40; fnt[275]=8'h40;
    fnt[276]=8'h40; fnt[277]=8'h40; fnt[278]=8'h70; fnt[279]=8'h00;
    // '<' (idx 35) – LSB-first: tip at col 1
    fnt[280]=8'h10; fnt[281]=8'h08; fnt[282]=8'h04; fnt[283]=8'h02;
    fnt[284]=8'h04; fnt[285]=8'h08; fnt[286]=8'h10; fnt[287]=8'h00;
    // '=' (idx 36)
    fnt[288]=8'h00; fnt[289]=8'h00; fnt[290]=8'h7E; fnt[291]=8'h00;
    fnt[292]=8'h7E; fnt[293]=8'h00; fnt[294]=8'h00; fnt[295]=8'h00;
    // '>' (idx 37) – LSB-first: tip at col 6
    fnt[296]=8'h08; fnt[297]=8'h10; fnt[298]=8'h20; fnt[299]=8'h40;
    fnt[300]=8'h20; fnt[301]=8'h10; fnt[302]=8'h08; fnt[303]=8'h00;
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
// RIGHT panel: x=[514,640), y=[8,160), 15 chars × 19 rows
//   Column layout: label(0-3) + ':'(4) + data(5-12) + space(13-14)
//     8-bit  values: '0','0',H,L  at cols 9-12
//     16-bit values: H3,H2,H1,H0  at cols 9-12
//     32-bit (MI) :  H7..H0       at cols 5-12
//   rows  0- 3: PC  MAR  IR  CAR   (8-bit registers)
//   rows  4- 7: MBR  BR  ACC  MR   (16-bit registers)
//   row   8:    blank separator
//   row   9:    MI (32-bit microinstruction, one row)
//   row  10:    blank separator
//   rows 11-12: MODE / HALT
//   row  13:    blank separator
//   rows 14-18: PI0  PO0  PO1  PO2  PO3  (I/O ports, 16-bit)
// ============================================================
wire in_panel = active && (hc >= 10'd514) && (vc >= 10'd8) && (vc < 10'd160);
wire [9:0] tx = hc - 10'd514;
wire [9:0] ty = vc - 10'd8;

wire [3:0] ccol = tx[6:3];   // char column 0..15
wire [4:0] crow = ty[7:3];   // char row    0..18
wire [2:0] fpx  = tx[2:0];
wire [2:0] frow = ty[2:0];

// Helper macro for 16-bit hex column decode (cols 9-12)
// Use inline case instead of macro for synthesis safety.

reg [5:0] cidx;
always @(*) begin
    cidx = `CSP;
    case (crow)
        // ---- row 0: PC  :    00HL   ----
        5'd0: case (ccol)
            4'd0: cidx = `CP;
            4'd1: cidx = `CC;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = `C0;
            4'd10: cidx = `C0;
            4'd11: cidx = {2'b0, v_PC[7:4]};
            4'd12: cidx = {2'b0, v_PC[3:0]};
            default: cidx = `CSP;
        endcase
        // ---- row 1: MAR :    00HL   ----
        5'd1: case (ccol)
            4'd0: cidx = `CM;
            4'd1: cidx = `CA;
            4'd2: cidx = `CR;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = `C0;
            4'd10: cidx = `C0;
            4'd11: cidx = {2'b0, v_MAR[7:4]};
            4'd12: cidx = {2'b0, v_MAR[3:0]};
            default: cidx = `CSP;
        endcase
        // ---- row 2: IR  :    00HL   ----
        5'd2: case (ccol)
            4'd0: cidx = `CI;
            4'd1: cidx = `CR;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = `C0;
            4'd10: cidx = `C0;
            4'd11: cidx = {2'b0, v_IR[7:4]};
            4'd12: cidx = {2'b0, v_IR[3:0]};
            default: cidx = `CSP;
        endcase
        // ---- row 3: CAR :    00HL   ----
        5'd3: case (ccol)
            4'd0: cidx = `CC;
            4'd1: cidx = `CA;
            4'd2: cidx = `CR;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = `C0;
            4'd10: cidx = `C0;
            4'd11: cidx = {2'b0, v_CAR[7:4]};
            4'd12: cidx = {2'b0, v_CAR[3:0]};
            default: cidx = `CSP;
        endcase
        // ---- row 4: MBR :    XXXX   ----
        5'd4: case (ccol)
            4'd0: cidx = `CM;
            4'd1: cidx = `CB;
            4'd2: cidx = `CR;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = {2'b0, v_MBR[15:12]};
            4'd10: cidx = {2'b0, v_MBR[11:8]};
            4'd11: cidx = {2'b0, v_MBR[7:4]};
            4'd12: cidx = {2'b0, v_MBR[3:0]};
            default: cidx = `CSP;
        endcase
        // ---- row 5: BR  :    XXXX   ----
        5'd5: case (ccol)
            4'd0: cidx = `CB;
            4'd1: cidx = `CR;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = {2'b0, v_BR[15:12]};
            4'd10: cidx = {2'b0, v_BR[11:8]};
            4'd11: cidx = {2'b0, v_BR[7:4]};
            4'd12: cidx = {2'b0, v_BR[3:0]};
            default: cidx = `CSP;
        endcase
        // ---- row 6: ACC :    XXXX   ----
        5'd6: case (ccol)
            4'd0: cidx = `CA;
            4'd1: cidx = `CC;
            4'd2: cidx = `CC;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = {2'b0, v_ACC[15:12]};
            4'd10: cidx = {2'b0, v_ACC[11:8]};
            4'd11: cidx = {2'b0, v_ACC[7:4]};
            4'd12: cidx = {2'b0, v_ACC[3:0]};
            default: cidx = `CSP;
        endcase
        // ---- row 7: MR  :    XXXX   ----
        5'd7: case (ccol)
            4'd0: cidx = `CM;
            4'd1: cidx = `CR;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = {2'b0, v_MR[15:12]};
            4'd10: cidx = {2'b0, v_MR[11:8]};
            4'd11: cidx = {2'b0, v_MR[7:4]};
            4'd12: cidx = {2'b0, v_MR[3:0]};
            default: cidx = `CSP;
        endcase
        // row 8: blank separator
        // ---- row 9: MI  :XXXXXXXX   (32-bit in one row) ----
        5'd9: case (ccol)
            4'd0: cidx = `CM;
            4'd1: cidx = `CI;
            4'd4: cidx = `CCOL;
            4'd5:  cidx = {2'b0, v_MI[31:28]};
            4'd6:  cidx = {2'b0, v_MI[27:24]};
            4'd7:  cidx = {2'b0, v_MI[23:20]};
            4'd8:  cidx = {2'b0, v_MI[19:16]};
            4'd9:  cidx = {2'b0, v_MI[15:12]};
            4'd10: cidx = {2'b0, v_MI[11:8]};
            4'd11: cidx = {2'b0, v_MI[7:4]};
            4'd12: cidx = {2'b0, v_MI[3:0]};
            default: cidx = `CSP;
        endcase
        // row 10: blank separator
        // ---- row 11: MODE:   XXXX   ----
        5'd11: case (ccol)
            4'd0: cidx = `CM;
            4'd1: cidx = `CO;
            4'd2: cidx = `CD;
            4'd3: cidx = `CE;
            4'd4: cidx = `CCOL;
            4'd8:  cidx = (exec_mode == 2'b00) ? `CR :
                          (exec_mode == 2'b01) ? `CI : `CU;
            4'd9:  cidx = (exec_mode == 2'b00) ? `CU : `CS;
            4'd10: cidx = (exec_mode == 2'b00) ? `CN : `CT;
            4'd11: cidx = (exec_mode == 2'b00) ? `CSP : `CP;
            default: cidx = `CSP;
        endcase
        // ---- row 12: HALT:      XXX ----
        5'd12: case (ccol)
            4'd0: cidx = `CH;
            4'd1: cidx = `CA;
            4'd2: cidx = `CL;
            4'd3: cidx = `CT;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = v_halted ? `CY : `CN;
            4'd10: cidx = v_halted ? `CE : `CO;
            4'd11: cidx = v_halted ? `CS : `CSP;
            default: cidx = `CSP;
        endcase
        // row 13: blank separator
        // ---- row 14: PI0 :    XXXX  (port_in[0]) ----
        5'd14: case (ccol)
            4'd0: cidx = `CP;
            4'd1: cidx = `CI;
            4'd2: cidx = `C0;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = {2'b0, v_PI0[15:12]};
            4'd10: cidx = {2'b0, v_PI0[11:8]};
            4'd11: cidx = {2'b0, v_PI0[7:4]};
            4'd12: cidx = {2'b0, v_PI0[3:0]};
            default: cidx = `CSP;
        endcase
        // ---- row 15: PO0 :    XXXX  (port_out[0]) ----
        5'd15: case (ccol)
            4'd0: cidx = `CP;
            4'd1: cidx = `CO;
            4'd2: cidx = `C0;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = {2'b0, v_PO0[15:12]};
            4'd10: cidx = {2'b0, v_PO0[11:8]};
            4'd11: cidx = {2'b0, v_PO0[7:4]};
            4'd12: cidx = {2'b0, v_PO0[3:0]};
            default: cidx = `CSP;
        endcase
        // ---- row 16: PO1 :    XXXX ----
        5'd16: case (ccol)
            4'd0: cidx = `CP;
            4'd1: cidx = `CO;
            4'd2: cidx = `C1;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = {2'b0, v_PO1[15:12]};
            4'd10: cidx = {2'b0, v_PO1[11:8]};
            4'd11: cidx = {2'b0, v_PO1[7:4]};
            4'd12: cidx = {2'b0, v_PO1[3:0]};
            default: cidx = `CSP;
        endcase
        // ---- row 17: PO2 :    XXXX ----
        5'd17: case (ccol)
            4'd0: cidx = `CP;
            4'd1: cidx = `CO;
            4'd2: cidx = `C2f;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = {2'b0, v_PO2[15:12]};
            4'd10: cidx = {2'b0, v_PO2[11:8]};
            4'd11: cidx = {2'b0, v_PO2[7:4]};
            4'd12: cidx = {2'b0, v_PO2[3:0]};
            default: cidx = `CSP;
        endcase
        // ---- row 18: PO3 :    XXXX ----
        5'd18: case (ccol)
            4'd0: cidx = `CP;
            4'd1: cidx = `CO;
            4'd2: cidx = `C3;
            4'd4: cidx = `CCOL;
            4'd9:  cidx = {2'b0, v_PO3[15:12]};
            4'd10: cidx = {2'b0, v_PO3[11:8]};
            4'd11: cidx = {2'b0, v_PO3[7:4]};
            4'd12: cidx = {2'b0, v_PO3[3:0]};
            default: cidx = `CSP;
        endcase
        default: cidx = `CSP;
    endcase
end

wire [7:0] fbyte = fnt[{cidx, frow}];
wire px = in_panel && fbyte[fpx];   // bit0=leftmost (LSB-first font convention)

// ============================================================
// LEFT panel: x=[0,560), y=[0,256), 70 chars × 32 rows
// History ring buffer: 32 entries
//   type=0: instr-step  {1'b0, v_IR[7:0], v_MAR[7:0]} = 17 bits
//   type=1: micro-step  {1'b1, snap_car[7:0], 8'h0}
// ============================================================

// Ring buffer storage
reg [16:0] hist [0:31];
reg  [4:0] hist_head;
integer    hist_init_i;
initial begin
    for (hist_init_i = 0; hist_init_i < 32; hist_init_i = hist_init_i+1)
        hist[hist_init_i] = 17'h0;
end

// ============================================================
// Bottom-left input panel state
// ============================================================
reg        area_sel;               // 0 = BL input area (Tab toggles)
reg [5:0]  input_buf  [0:31];      // current input line, up to 32 chars (font indices)
reg [5:0]  input_pos;              // cursor position 0..32
reg [5:0]  input_hist [0:15][0:31]; // history: 16 lines × 32 chars (font indices)
reg [3:0]  input_hist_head;        // next write row (mod-16 auto-wraps)
reg [4:0]  input_hist_count;       // valid history lines 0..16
reg [5:0]  blink_cnt;              // counts VGA frames for cursor blink
reg        blink_on;               // cursor visibility flag
integer    bl_i;

// Capture: negedge-generated capture_pulse, resync to posedge domain
reg  cap_d1;
always @(posedge clk or posedge reset) begin
    if (reset) begin
        cap_d1    <= 1'b0;
        hist_head <= 5'd0;
    end else begin
        cap_d1 <= capture_pulse;
        if (capture_pulse && !cap_d1) begin
            if (exec_mode == 2'b01)
                hist[hist_head] <= {1'b0, v_IR, v_MAR};
            else
                hist[hist_head] <= {1'b1, snap_car, 8'h0};
            hist_head <= hist_head + 1'd1;
        end
    end
end

// ============================================================
// BL panel: input buffer and history logic
// ============================================================
always @(posedge clk or posedge reset) begin
    if (reset) begin
        area_sel         <= 1'b0;
        input_pos        <= 6'd0;
        input_hist_head  <= 4'd0;
        input_hist_count <= 5'd0;
        blink_cnt        <= 6'd0;
        blink_on         <= 1'b1;
        for (bl_i = 0; bl_i < 32; bl_i = bl_i + 1)
            input_buf[bl_i] <= `CSP;
    end else begin
        // Cursor blink: increment at VGA vertical blanking start (once per frame ~60Hz)
        if (pclk_en && hc == 10'd0 && vc == V_ACT) begin
            if (blink_cnt == 6'd29) begin
                blink_cnt <= 6'd0;
                blink_on  <= ~blink_on;
            end else
                blink_cnt <= blink_cnt + 6'd1;
        end

        // Tab: cycle area selection
        if (ps2_is_tab) area_sel <= ~area_sel;

        // Accept keyboard input only in single-step mode (01) and area 0
        if (exec_mode == 2'b01 && area_sel == 1'b0) begin
            if (ps2_char_valid && input_pos < 6'd32) begin
                input_buf[input_pos] <= ps2_char_data;
                input_pos <= input_pos + 6'd1;
            end
            if (ps2_is_backspace && input_pos > 6'd0)
                input_pos <= input_pos - 6'd1;
            if (ps2_is_enter) begin
                // Save current line to history ring buffer
                for (bl_i = 0; bl_i < 32; bl_i = bl_i + 1) begin
                    if (bl_i < input_pos)
                        input_hist[input_hist_head][bl_i] <= input_buf[bl_i];
                    else
                        input_hist[input_hist_head][bl_i] <= `CSP;
                end
                input_hist_head  <= input_hist_head + 4'd1;
                if (input_hist_count < 5'd16)
                    input_hist_count <= input_hist_count + 5'd1;
                // Clear input buffer
                for (bl_i = 0; bl_i < 32; bl_i = bl_i + 1)
                    input_buf[bl_i] <= `CSP;
                input_pos <= 6'd0;
            end
        end
    end
end

// Rendering signals (left panel shrunk to 48 chars = 384px)
wire in_left  = active && (hc < 10'd384) && (vc < 10'd256);
wire [5:0] lcol  = hc[8:3];   // char column 0..47
wire [4:0] lrow  = vc[7:3];   // char row    0..31
wire [2:0] lfpx  = hc[2:0];   // pixel col within char
wire [2:0] lfrow = vc[2:0];   // pixel row within char

// Ring buffer read: oldest entry at row 0
wire [4:0] bidx = hist_head + lrow;
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
    input [6:0] pos;
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
    input [6:0] pos;
    // Micro-op name table: 62 chars starting at pos=8
    // car_desc[0..61] defined per CAR value
    reg [5:0] desc [0:61];
    integer k;
    begin
        for (k = 0; k < 62; k = k+1) desc[k] = `CSP;
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
            8'h02: begin // IR<=MBR[H] MAR<=MBR[L] PC<=PC+1 DISP
                desc[ 0]=`CI; desc[ 1]=`CR; desc[ 2]=`CLT; desc[ 3]=`CEQ;
                desc[ 4]=`CM; desc[ 5]=`CB; desc[ 6]=`CR;
                desc[ 7]=`CLBR; desc[ 8]=`CH; desc[ 9]=`CRBR; desc[10]=`CSP;
                desc[11]=`CM; desc[12]=`CA; desc[13]=`CR; desc[14]=`CLT; desc[15]=`CEQ;
                desc[16]=`CM; desc[17]=`CB; desc[18]=`CR;
                desc[19]=`CLBR; desc[20]=`CL; desc[21]=`CRBR; desc[22]=`CSP;
                desc[23]=`CP; desc[24]=`CC; desc[25]=`CLT; desc[26]=`CEQ;
                desc[27]=`CP; desc[28]=`CC; desc[29]=`CPLS; desc[30]=`C1; desc[31]=`CSP;
                desc[32]=`CD; desc[33]=`CI; desc[34]=`CS; desc[35]=`CP; end
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
            default: micro_char = (pos >= 7'd8 && pos <= 7'd69) ? desc[pos - 7'd8] : `CSP;
        endcase
    end
endfunction

// ---- Instr-step display character decode ----
function [5:0] instr_char;
    input [7:0] ir;
    input [7:0] operand;
    input [6:0] col;
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
        l_cidx = instr_char(cur_ir, cur_operand, {1'b0, lcol});
    else
        l_cidx = micro_char(cur_ir /* cur_ir holds snap_car for micro entries */, {1'b0, lcol});
end

wire [7:0] l_fbyte = fnt[{l_cidx, lfrow}];
wire l_px = in_left && l_fbyte[lfpx];

// ============================================================
// BOTTOM-LEFT panel: x=[0,384), y=[256,480) – 48 chars × 28 rows
//   rows  0-15: entered instruction history (oldest→newest)
//   row  16:    separator line (dashes)
//   rows 17-23: unused (blank)
//   row  24:    current input line  "> [text] |cursor"
//   row  25:    blank
//   row  26:    debug: last PS2 scan code at cols 40-43 "K:XX"
//   row  27:    blank
// ============================================================
wire in_bl    = active && (hc < 10'd384) && (vc >= 10'd256);
wire [5:0] bl_col  = hc[8:3];                   // 0..47
wire [9:0] bl_vc_off = vc - 10'd256;
wire [4:0] bl_row  = bl_vc_off[7:3];            // 0..27
wire [2:0] bl_fpx  = hc[2:0];
wire [2:0] bl_frow = vc[2:0];

// History ring buffer read index: show oldest entry at bl_row=0
wire [3:0] hist_disp_idx  = input_hist_head - input_hist_count[3:0] + bl_row[3:0];
wire       hist_row_valid  = (bl_row <= 5'd15) && ({1'b0, bl_row} < input_hist_count);

// BL character decode (combinational)
reg [5:0] bl_cidx;
always @(*) begin
    bl_cidx = `CSP;
    if (in_bl) begin
        if (bl_row <= 5'd15) begin
            // History rows
            if (hist_row_valid && bl_col < 6'd32)
                bl_cidx = input_hist[hist_disp_idx][bl_col[4:0]];
        end else if (bl_row == 5'd16) begin
            // Separator: draw '-' across first 32 cols
            bl_cidx = (bl_col < 6'd32) ? `CMIN : `CSP;
        end else if (bl_row == 5'd24) begin
            // Input line: "> text cursor"
            if (bl_col == 6'd0)
                bl_cidx = `CGT; // '>' prompt
            else if (bl_col >= 6'd1 && bl_col <= input_pos && bl_col <= 6'd32)
                bl_cidx = input_buf[bl_col - 6'd1];
            else if (bl_col == input_pos + 6'd1 && bl_col <= 6'd33)
                bl_cidx = blink_on ? `COR : `CSP; // blinking '|' cursor
        end else if (bl_row == 5'd26) begin
            // Debug: show "K:XX" (last PS2 scan code) right-aligned at cols 40-43
            case (bl_col)
                6'd40: bl_cidx = `CK;
                6'd41: bl_cidx = `CCOL;
                6'd42: bl_cidx = {2'b0, ps2_last_scan[7:4]};
                6'd43: bl_cidx = {2'b0, ps2_last_scan[3:0]};
                default: bl_cidx = `CSP;
            endcase
        end
    end
end

wire [7:0] bl_fbyte = fnt[{bl_cidx, bl_frow}];
wire bl_px = in_bl && bl_fbyte[bl_fpx];
// Separator row flag for color control
wire bl_sep_row = in_bl && (bl_row == 5'd16);
// Debug row flag for yellow text
wire bl_dbg_row = in_bl && (bl_row == 5'd26);

// ============================================================
// MIDDLE panel: x=[392,560), y=[0,480)  –  21 chars × 60 rows
// Static instruction listing from InstructionMemory scan.
// Format per row: > XX  MMMMMM [OO]
//   col  0:    '>' (highlighted) / ' '
//   col  1-2:  instruction address hex
//   col  3:    ' '
//   col  4-9:  mnemonic (6 chars)
//   col  10:   ' '
//   col  11:   '[' or ' '
//   col  12-13: operand hex or '  '
//   col  14:   ']' or ' '
//   col  15-20: unused (space)
// ============================================================

// Instruction ROM written by scan FSM
(* ram_style = "distributed" *) reg [15:0] instr_rom [0:255];
always @(posedge clk) begin
    if (scan_wr_en)
        instr_rom[scan_wr_addr] <= scan_wr_data;
end

// Middle panel coordinate signals
wire in_mid  = active && (hc >= 10'd392) && (hc < 10'd512);
wire [4:0] mcol  = hc[8:3] - 6'd49;   // char col 0..20  (392=49*8)
wire [5:0] mrow  = vc[8:3];            // char row 0..59  (full 480px height)
wire [2:0] mfpx  = hc[2:0];
wire [2:0] mfrow = vc[2:0];

// Highlight: which instruction PC to mark
wire [7:0] cur_exec_pc = (v_CAR[7:4] == 4'h0) ? v_PC :
                         (v_PC == 8'd0) ? 8'd0 : v_PC - 8'd1;
wire [7:0] highlighted_pc =
    (exec_mode == 2'b10) ? cur_exec_pc : v_PC;  // micro-step: executing; else: next fetch

// Scrolling: keep highlighted row ~10 lines from top, clamped to list bounds
wire [7:0] scroll_max = (scan_count > 8'd60) ? scan_count - 8'd60 : 8'd0;
wire [7:0] ideal_base = (highlighted_pc >= 8'd10) ? highlighted_pc - 8'd10 : 8'd0;
wire [7:0] mid_base   = (ideal_base > scroll_max) ? scroll_max : ideal_base;

// Row → instruction index
wire [7:0] mid_idx      = mid_base + {2'b0, mrow};
wire       mid_row_valid = scan_done && (mid_idx < scan_count);
wire [7:0] mid_ir  = instr_rom[mid_idx][15:8];
wire [7:0] mid_op  = instr_rom[mid_idx][7:0];

// Highlight flag (only in step modes)
wire mid_hl = mid_row_valid && (exec_mode != 2'b00) && (mid_idx == highlighted_pc);

// Character decode for middle panel
reg [5:0] m_cidx;
always @(*) begin
    m_cidx = `CSP;
    if (in_mid && mid_row_valid) begin
        case (mcol)
            5'd0:  m_cidx = mid_hl ? `CGT : `CSP;
            5'd1:  m_cidx = {2'b0, mid_idx[7:4]};
            5'd2:  m_cidx = {2'b0, mid_idx[3:0]};
            5'd3:  m_cidx = `CSP;
            5'd4:  m_cidx = mnemonic_char(mid_ir, 3'd0);
            5'd5:  m_cidx = mnemonic_char(mid_ir, 3'd1);
            5'd6:  m_cidx = mnemonic_char(mid_ir, 3'd2);
            5'd7:  m_cidx = mnemonic_char(mid_ir, 3'd3);
            5'd8:  m_cidx = mnemonic_char(mid_ir, 3'd4);
            5'd9:  m_cidx = mnemonic_char(mid_ir, 3'd5);
            5'd10: m_cidx = `CSP;
            5'd11: m_cidx = has_operand(mid_ir) ? `CLBR : `CSP;
            5'd12: m_cidx = has_operand(mid_ir) ? {2'b0, mid_op[7:4]} : `CSP;
            5'd13: m_cidx = has_operand(mid_ir) ? {2'b0, mid_op[3:0]} : `CSP;
            5'd14: m_cidx = has_operand(mid_ir) ? `CRBR : `CSP;
            default: m_cidx = `CSP;
        endcase
    end
end

wire [7:0] m_fbyte = fnt[{m_cidx, mfrow}];
wire m_px = in_mid && mid_row_valid && m_fbyte[mfpx];

// ============================================================
// Separators
// ============================================================
// Left panel right edge: x=384..385  (moved from 560)
wire sep_l = active && (hc >= 10'd384) && (hc < 10'd386);
// Right panel left edge: x=512..513  (moved left with right panel)
wire sep_r = active && (hc >= 10'd512) && (hc < 10'd514);

// ============================================================
// Color output
// ============================================================
wire [3:0] txt_r = v_halted ? 4'hF : 4'hF;
wire [3:0] txt_g = v_halted ? 4'h4 : 4'hF;
wire [3:0] txt_b = v_halted ? 4'h4 : 4'hF;

// Middle panel colors:
//   highlighted row text  : green  (0, F, 0)
//   highlighted row bg    : dark green (0, 2, 0)
//   normal row text       : white  (F, F, F)
//   normal row bg         : black  (0, 0, 0)
assign vga_r = !active        ? 4'h0 :
               l_px           ? txt_r :
               sep_l          ? 4'h5 :
               in_left        ? 4'h0 :
               bl_px&&bl_dbg_row ? 4'hF :   // BL debug row text: yellow (R=F)
               bl_px&&bl_sep_row ? 4'h3 :   // BL separator text: dim
               bl_px          ? 4'hF :      // BL text: white
               bl_sep_row     ? 4'h1 :      // BL separator bg: very dim
               in_bl          ? 4'h0 :      // BL bg: black
               m_px&&mid_hl   ? 4'h0 :      // highlight text: green (no red)
               m_px           ? 4'hF :      // normal text: white
               in_mid&&mid_hl ? 4'h0 :      // highlight bg: dark green (no red)
               in_mid         ? 4'h0 :      // normal bg: black
               px             ? txt_r :
               sep_r          ? 4'h5 :
               in_panel       ? 4'h0 : 4'h0;

assign vga_g = !active        ? 4'h0 :
               l_px           ? txt_g :
               sep_l          ? 4'h5 :
               in_left        ? 4'h0 :
               bl_px&&bl_dbg_row ? 4'hF :   // BL debug row text: yellow (G=F)
               bl_px&&bl_sep_row ? 4'h3 :   // BL separator text: dim
               bl_px          ? 4'hF :      // BL text: white
               bl_sep_row     ? 4'h1 :      // BL separator bg: very dim
               in_bl          ? 4'h0 :      // BL bg: black
               m_px&&mid_hl   ? 4'hF :      // highlight text: green (full)
               m_px           ? 4'hF :      // normal text: white
               in_mid&&mid_hl ? 4'h2 :      // highlight bg: dark green
               in_mid         ? 4'h0 :      // normal bg: black
               px             ? txt_g :
               sep_r          ? 4'h5 :
               in_panel       ? 4'h0 : 4'h0;

assign vga_b = !active        ? 4'h0 :
               l_px           ? txt_b :
               sep_l          ? 4'h5 :
               in_left        ? 4'h2 :
               bl_px&&bl_dbg_row ? 4'h0 :   // BL debug row text: yellow (B=0)
               bl_px&&bl_sep_row ? 4'h3 :   // BL separator text: dim
               bl_px          ? 4'hF :      // BL text: white
               bl_sep_row     ? 4'h1 :      // BL separator bg: very dim
               in_bl          ? 4'h0 :      // BL bg: black
               m_px&&mid_hl   ? 4'h0 :      // highlight text: green (no blue)
               m_px           ? 4'hF :      // normal text: white
               in_mid&&mid_hl ? 4'h0 :      // highlight bg: dark green (no blue)
               in_mid         ? 4'h0 :      // normal bg: black
               px             ? txt_b :
               sep_r          ? 4'h5 :
               in_panel       ? 4'h2 : 4'h0;

endmodule
