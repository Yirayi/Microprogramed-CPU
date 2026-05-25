// ============================================================
// keyboard_ctrl.v
// PS/2 keyboard command processor for microprogrammed CPU
//
// Receives PS/2 scan codes (Set 2), converts to font indices,
// maintains a command-line buffer, validates instructions on
// Enter, and generates an injection trigger so the CPU executes
// the typed instruction in single-step mode.
//
// Input format:  MNEMONIC [XX]   (XX = 2 hex digits)
//                HALT | NOT      (no operand)
//
// Font index encoding (shared with vga_display):
//   0-9  = '0'-'9'     10='A' 11='B' 12='C' 13='D' 14='E' 15='F'
//   16=' ' 17=':'      18='P' 19='I' 20='R' 21='M'
//   22='G' 23='H'      24='J' 25='L' 26='N' 27='O'
//   28='S' 29='T'      30='U' 31='Y' 32='Z'
//   33='[' 34=']'      38='+' 39='-' 40='X' 41='W' 42='K'
//   43='V' 44='Q'      45='&' 46='|'
//   37='>'  36='='
//
// Special internal font-index values (>46):
//   61 = Enter
//   62 = Backspace
//   63 = unknown / ignore
//
// Display bus (to vga_display):
//   kb_buf_pack [89:0]  : 15 × 6-bit font indices for input line
//   kb_buf_len  [3:0]   : actual number of chars in buffer (0..15)
//   kb_cursor   [0]     : cursor blink (slow counter bit)
//   kb_status   [3:0]   : 0=idle 1=ok 2=err_unknown 3=err_format 4=err_mode
//   kb_msg_pack [89:0]  : 15 × 6-bit font indices for status line
// ============================================================
`timescale 1ns / 1ps

module keyboard_ctrl (
    input  wire        clk,
    input  wire        reset,

    // PS/2 raw decoded bytes (from PS2_receiver)
    input  wire [7:0]  ps2_data,
    input  wire        ps2_valid,

    // CPU execution mode (01 = instr-step required)
    input  wire [1:0]  exec_mode,

    // Instruction injection outputs (to CPU_top via ALL_top)
    output reg         inj_valid,      // 1-cycle pulse: inject instruction
    output reg  [15:0] inj_word,       // {opcode[7:0], operand[7:0]}

    // Synthetic step pulse (to ControlUnit / ALL_top)
    output reg         kb_step_pulse,  // 1-cycle pulse, triggers CPU step

    // Display outputs (to vga_display)
    output wire [89:0] kb_buf_pack,    // 15 × 6-bit font indices
    output wire [3:0]  kb_buf_len,
    output wire        kb_cursor,
    output wire [3:0]  kb_status,
    output wire [89:0] kb_msg_pack
);

// ============================================================
// Font index letter constants
// ============================================================
localparam FI_A=6'd10, FI_B=6'd11, FI_C=6'd12, FI_D=6'd13, FI_E=6'd14;
localparam FI_F=6'd15, FI_G=6'd22, FI_H=6'd23, FI_I=6'd19, FI_J=6'd24;
localparam FI_K=6'd42, FI_L=6'd25, FI_M=6'd21, FI_N=6'd26, FI_O=6'd27;
localparam FI_P=6'd18, FI_Q=6'd44, FI_R=6'd20, FI_S=6'd28, FI_T=6'd29;
localparam FI_U=6'd30, FI_V=6'd43, FI_W=6'd41, FI_X=6'd40, FI_Y=6'd31;
localparam FI_Z=6'd32;
localparam FI_SP=6'd16, FI_LBRACE=6'd33, FI_RBRACE=6'd34;
localparam FI_COL=6'd17, FI_EQ=6'd36, FI_GT=6'd37, FI_MIN=6'd39;
localparam FI_BAR=6'd46;  // '|' used as cursor

// Special action codes
localparam AC_ENTER = 6'd61, AC_BKSP = 6'd62, AC_IGN = 6'd63;

// ============================================================
// PS/2 break-code filter
// State: NORM → AFTER_F0 → NORM  (release code ignored)
//                → AFTER_E0 → NORM  (extended key ignored)
//             AFTER_E0 → AFTER_E0_F0 → NORM
// ============================================================
reg after_f0, after_e0, after_e0f0;
reg key_make;
reg [7:0] key_code;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        after_f0 <= 0; after_e0 <= 0; after_e0f0 <= 0;
        key_make <= 0; key_code <= 0;
    end else begin
        key_make <= 0;
        if (ps2_valid) begin
            if (after_f0) begin
                after_f0 <= 0; // released key byte – discard
            end else if (after_e0f0) begin
                after_e0f0 <= 0; // extended released key – discard
            end else if (after_e0) begin
                if (ps2_data == 8'hF0) begin
                    after_e0 <= 0; after_e0f0 <= 1;
                end else begin
                    after_e0 <= 0; // extended make code – ignore (no ext keys needed)
                end
            end else if (ps2_data == 8'hF0) begin
                after_f0 <= 1;
            end else if (ps2_data == 8'hE0) begin
                after_e0 <= 1;
            end else begin
                key_make <= 1;
                key_code <= ps2_data;
            end
        end
    end
end

// ============================================================
// PS/2 Set-2 make-code → font index (or special code)
// ============================================================
function [5:0] ps2_to_fidx;
    input [7:0] code;
    case (code)
        // Letters (A-Z)
        8'h1C: ps2_to_fidx = FI_A;
        8'h32: ps2_to_fidx = FI_B;
        8'h21: ps2_to_fidx = FI_C;
        8'h23: ps2_to_fidx = FI_D;
        8'h24: ps2_to_fidx = FI_E;
        8'h2B: ps2_to_fidx = FI_F;
        8'h34: ps2_to_fidx = FI_G;
        8'h33: ps2_to_fidx = FI_H;
        8'h43: ps2_to_fidx = FI_I;
        8'h3B: ps2_to_fidx = FI_J;
        8'h42: ps2_to_fidx = FI_K;
        8'h4B: ps2_to_fidx = FI_L;
        8'h3A: ps2_to_fidx = FI_M;
        8'h31: ps2_to_fidx = FI_N;
        8'h44: ps2_to_fidx = FI_O;
        8'h4D: ps2_to_fidx = FI_P;
        8'h15: ps2_to_fidx = FI_Q;
        8'h2D: ps2_to_fidx = FI_R;
        8'h1B: ps2_to_fidx = FI_S;
        8'h2C: ps2_to_fidx = FI_T;
        8'h3C: ps2_to_fidx = FI_U;
        8'h2A: ps2_to_fidx = FI_V;
        8'h1D: ps2_to_fidx = FI_W;
        8'h22: ps2_to_fidx = FI_X;
        8'h35: ps2_to_fidx = FI_Y;
        8'h1A: ps2_to_fidx = FI_Z;
        // Digits 0-9
        8'h45: ps2_to_fidx = 6'd0;
        8'h16: ps2_to_fidx = 6'd1;
        8'h1E: ps2_to_fidx = 6'd2;
        8'h26: ps2_to_fidx = 6'd3;
        8'h25: ps2_to_fidx = 6'd4;
        8'h2E: ps2_to_fidx = 6'd5;
        8'h36: ps2_to_fidx = 6'd6;
        8'h3D: ps2_to_fidx = 6'd7;
        8'h3E: ps2_to_fidx = 6'd8;
        8'h46: ps2_to_fidx = 6'd9;
        // Punctuation
        8'h29: ps2_to_fidx = FI_SP;      // Space
        8'h54: ps2_to_fidx = FI_LBRACE;  // [
        8'h5B: ps2_to_fidx = FI_RBRACE;  // ]
        // Control
        8'h5A: ps2_to_fidx = AC_ENTER;
        8'h66: ps2_to_fidx = AC_BKSP;
        default: ps2_to_fidx = AC_IGN;
    endcase
endfunction

// ============================================================
// Command buffer
// ============================================================
reg [5:0] kbuf [0:14]; // 15-char font-index buffer
reg [3:0] klen;

// Cursor blink: toggle every 2^25 cycles (~0.33 s at 100 MHz)
reg [25:0] blink_cnt;
always @(posedge clk or posedge reset)
    if (reset) blink_cnt <= 0; else blink_cnt <= blink_cnt + 1;
wire cursor_on = blink_cnt[25];

// ============================================================
// Instruction validator (combinational)
// Inputs: kbuf[0..14], klen
// Outputs: parse_valid, parse_opcode, parse_operand, parse_err
//   parse_err: 0=none 1=unknown_mnem 2=format_error 3=mode_error
// ============================================================
reg        parse_valid;
reg [7:0]  parse_opcode;
reg [7:0]  parse_operand;
reg [1:0]  parse_err;

// Helper wires for readability
wire [5:0] b0=kbuf[0], b1=kbuf[1], b2=kbuf[2], b3=kbuf[3],
           b4=kbuf[4], b5=kbuf[5], b6=kbuf[6], b7=kbuf[7],
           b8=kbuf[8], b9=kbuf[9], b10=kbuf[10];

// Check operand suffix " [HH]" starting at position p (p, p+1, p+2, p+3, p+4)
// For mlen=2: p=2; mlen=3: p=3; mlen=4: p=4; mlen=5: p=5; mlen=6: p=6

// Shared operand fields for each mnemonic length
wire op_sfx2_ok = (b2==FI_SP) && (b3==FI_LBRACE) && (b4<=6'd15) && (b5<=6'd15) && (b6==FI_RBRACE);
wire op_sfx3_ok = (b3==FI_SP) && (b4==FI_LBRACE) && (b5<=6'd15) && (b6<=6'd15) && (b7==FI_RBRACE);
wire op_sfx4_ok = (b4==FI_SP) && (b5==FI_LBRACE) && (b6<=6'd15) && (b7<=6'd15) && (b8==FI_RBRACE);
wire op_sfx5_ok = (b5==FI_SP) && (b6==FI_LBRACE) && (b7<=6'd15) && (b8<=6'd15) && (b9==FI_RBRACE);
wire op_sfx6_ok = (b6==FI_SP) && (b7==FI_LBRACE) && (b8<=6'd15) && (b9<=6'd15) && (b10==FI_RBRACE);

wire [7:0] op2 = {b4[3:0], b5[3:0]};  // operand for 2-char mnemonic (len=7)
wire [7:0] op3 = {b5[3:0], b6[3:0]};  // operand for 3-char mnemonic (len=8)
wire [7:0] op4 = {b6[3:0], b7[3:0]};  // operand for 4-char mnemonic (len=9)
wire [7:0] op5 = {b7[3:0], b8[3:0]};  // operand for 5-char mnemonic (len=10)
wire [7:0] op6 = {b8[3:0], b9[3:0]};  // operand for 6-char mnemonic (len=11)

always @(*) begin
    parse_valid   = 1'b0;
    parse_opcode  = 8'h00;
    parse_operand = 8'h00;
    parse_err     = 2'd1;   // default: unknown mnemonic

    case (klen)
        // ---- No-operand instructions ----
        4'd3: begin  // NOT
            if (b0==FI_N && b1==FI_O && b2==FI_T) begin
                parse_valid = 1; parse_opcode = 8'h0C; parse_err = 0;
            end
        end
        4'd4: begin  // HALT
            if (b0==FI_H && b1==FI_A && b2==FI_L && b3==FI_T) begin
                parse_valid = 1; parse_opcode = 8'h07; parse_err = 0;
            end
        end

        // ---- 2-char mnemonic + " [XX]" = 7 chars total ----
        4'd7: begin
            if (op_sfx2_ok) begin
                if (b0==FI_O && b1==FI_R) begin
                    parse_valid=1; parse_opcode=8'h0B; parse_operand=op2; parse_err=0;
                end else if (b0==FI_I && b1==FI_N) begin
                    parse_valid=1; parse_opcode=8'h10; parse_operand=op2; parse_err=0;
                end
                // else: correct format, unknown mnemonic → parse_err stays 1
            end else begin
                parse_err = 2'd2; // format error
            end
        end

        // ---- 3-char mnemonic + " [XX]" = 8 chars total ----
        4'd8: begin
            if (op_sfx3_ok) begin
                if      (b0==FI_A && b1==FI_D && b2==FI_D) begin parse_valid=1; parse_opcode=8'h03; parse_operand=op3; parse_err=0; end
                else if (b0==FI_S && b1==FI_U && b2==FI_B) begin parse_valid=1; parse_opcode=8'h04; parse_operand=op3; parse_err=0; end
                else if (b0==FI_M && b1==FI_P && b2==FI_Y) begin parse_valid=1; parse_opcode=8'h08; parse_operand=op3; parse_err=0; end
                else if (b0==FI_A && b1==FI_N && b2==FI_D) begin parse_valid=1; parse_opcode=8'h0A; parse_operand=op3; parse_err=0; end
                else if (b0==FI_O && b1==FI_U && b2==FI_T) begin parse_valid=1; parse_opcode=8'h0F; parse_operand=op3; parse_err=0; end
                else if (b0==FI_J && b1==FI_M && b2==FI_P) begin parse_valid=1; parse_opcode=8'h06; parse_operand=op3; parse_err=0; end
                // else: correct format, unknown mnemonic
            end else begin
                parse_err = 2'd2;
            end
        end

        // ---- 4-char mnemonic + " [XX]" = 9 chars total ----
        4'd9: begin
            if (op_sfx4_ok) begin
                if (b0==FI_L && b1==FI_O && b2==FI_A && b3==FI_D) begin
                    parse_valid=1; parse_opcode=8'h02; parse_operand=op4; parse_err=0;
                end
                // else: unknown
            end else begin
                parse_err = 2'd2;
            end
        end

        // ---- 5-char mnemonic + " [XX]" = 10 chars total ----
        4'd10: begin
            if (op_sfx5_ok) begin
                if      (b0==FI_L && b1==FI_O && b2==FI_A && b3==FI_D && b4==FI_I) begin
                    parse_valid=1; parse_opcode=8'h09; parse_operand=op5; parse_err=0;
                end else if (b0==FI_S && b1==FI_T && b2==FI_O && b3==FI_R && b4==FI_E) begin
                    parse_valid=1; parse_opcode=8'h01; parse_operand=op5; parse_err=0;
                end
            end else begin
                parse_err = 2'd2;
            end
        end

        // ---- 6-char mnemonic + " [XX]" = 11 chars total ----
        4'd11: begin
            if (op_sfx6_ok) begin
                if      (b0==FI_S && b1==FI_H && b2==FI_I && b3==FI_F && b4==FI_T && b5==FI_R) begin
                    parse_valid=1; parse_opcode=8'h0D; parse_operand=op6; parse_err=0;
                end else if (b0==FI_S && b1==FI_H && b2==FI_I && b3==FI_F && b4==FI_T && b5==FI_L) begin
                    parse_valid=1; parse_opcode=8'h0E; parse_operand=op6; parse_err=0;
                end else if (b0==FI_J && b1==FI_M && b2==FI_P && b3==FI_G && b4==FI_E && b5==FI_Z) begin
                    parse_valid=1; parse_opcode=8'h05; parse_operand=op6; parse_err=0;
                end
                // else: unknown mnemonic
            end else begin
                parse_err = 2'd2;
            end
        end

        default: begin
            // Length doesn't match any valid instruction – format error
            parse_err = 2'd2;
        end
    endcase
end

// ============================================================
// Status register (latched on Enter press)
// ============================================================
// 0=idle, 1=ok, 2=err_unknown, 3=err_format, 4=err_mode
reg [3:0] status_r;

// Status message buffer (15 font indices)
reg [5:0] msg_buf [0:14];

// Message presets – 15 font-idx chars each (pad with FI_SP)
task set_msg_ok;
    // "OK EXECUTING    " – 15 chars
    begin
        msg_buf[ 0]=FI_O;  msg_buf[ 1]=FI_K;  msg_buf[ 2]=FI_SP;
        msg_buf[ 3]=FI_E;  msg_buf[ 4]=FI_X;  msg_buf[ 5]=FI_E;
        msg_buf[ 6]=FI_C;  msg_buf[ 7]=FI_U;  msg_buf[ 8]=FI_T;
        msg_buf[ 9]=FI_I;  msg_buf[10]=FI_N;  msg_buf[11]=FI_G;
        msg_buf[12]=FI_SP; msg_buf[13]=FI_SP; msg_buf[14]=FI_SP;
    end
endtask

task set_msg_unknown;
    // "ERR UNKNOWN     "
    begin
        msg_buf[ 0]=FI_E;  msg_buf[ 1]=FI_R;  msg_buf[ 2]=FI_R;
        msg_buf[ 3]=FI_SP; msg_buf[ 4]=FI_U;  msg_buf[ 5]=FI_N;
        msg_buf[ 6]=FI_K;  msg_buf[ 7]=FI_N;  msg_buf[ 8]=FI_O;
        msg_buf[ 9]=FI_W;  msg_buf[10]=FI_N;  msg_buf[11]=FI_SP;
        msg_buf[12]=FI_SP; msg_buf[13]=FI_SP; msg_buf[14]=FI_SP;
    end
endtask

task set_msg_format;
    // "ERR FORMAT      "
    begin
        msg_buf[ 0]=FI_E;  msg_buf[ 1]=FI_R;  msg_buf[ 2]=FI_R;
        msg_buf[ 3]=FI_SP; msg_buf[ 4]=FI_F;  msg_buf[ 5]=FI_O;
        msg_buf[ 6]=FI_R;  msg_buf[ 7]=FI_M;  msg_buf[ 8]=FI_A;
        msg_buf[ 9]=FI_T;  msg_buf[10]=FI_SP; msg_buf[11]=FI_SP;
        msg_buf[12]=FI_SP; msg_buf[13]=FI_SP; msg_buf[14]=FI_SP;
    end
endtask

task set_msg_mode;
    // "ERR STEP MODE   "
    begin
        msg_buf[ 0]=FI_E;  msg_buf[ 1]=FI_R;  msg_buf[ 2]=FI_R;
        msg_buf[ 3]=FI_SP; msg_buf[ 4]=FI_S;  msg_buf[ 5]=FI_T;
        msg_buf[ 6]=FI_E;  msg_buf[ 7]=FI_P;  msg_buf[ 8]=FI_SP;
        msg_buf[ 9]=FI_M;  msg_buf[10]=FI_O;  msg_buf[11]=FI_D;
        msg_buf[12]=FI_E;  msg_buf[13]=FI_SP; msg_buf[14]=FI_SP;
    end
endtask

task clear_msg;
    integer mi;
    begin
        for (mi = 0; mi < 15; mi = mi+1) msg_buf[mi] = FI_SP;
    end
endtask

// ============================================================
// Main state machine: buffer management + Enter handling
// ============================================================
integer i;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        for (i = 0; i < 15; i = i+1) kbuf[i] <= FI_SP;
        klen          <= 4'd0;
        status_r      <= 4'd0;
        inj_valid     <= 1'b0;
        inj_word      <= 16'h0;
        kb_step_pulse <= 1'b0;
        clear_msg;
    end else begin
        inj_valid     <= 1'b0;
        kb_step_pulse <= 1'b0;

        if (key_make) begin
            // ps2_to_fidx is a pure function; inlining avoids 'automatic' keyword
            if (ps2_to_fidx(key_code) == AC_BKSP) begin
                // Backspace: remove last character
                if (klen > 0) begin
                    klen <= klen - 1;
                    kbuf[klen - 1] <= FI_SP;
                end
                status_r <= 4'd0;
                clear_msg;

            end else if (ps2_to_fidx(key_code) == AC_ENTER) begin
                // Enter: validate and (optionally) execute
                if (exec_mode != 2'b01) begin
                    // Wrong mode
                    status_r <= 4'd4;
                    set_msg_mode;
                end else if (parse_valid) begin
                    // Valid instruction – inject into CPU
                    inj_valid     <= 1'b1;
                    inj_word      <= {parse_opcode, parse_operand};
                    kb_step_pulse <= 1'b1;
                    status_r      <= 4'd1;
                    set_msg_ok;
                    // Clear buffer after successful execution
                    for (i = 0; i < 15; i = i+1) kbuf[i] <= FI_SP;
                    klen <= 4'd0;
                end else begin
                    // Invalid – show error, keep buffer
                    if (parse_err == 2'd1) begin
                        status_r <= 4'd2; set_msg_unknown;
                    end else begin
                        status_r <= 4'd3; set_msg_format;
                    end
                end

            end else if (ps2_to_fidx(key_code) != AC_IGN) begin
                // Normal printable character
                if (klen < 4'd15) begin
                    kbuf[klen] <= ps2_to_fidx(key_code);
                    klen       <= klen + 1;
                end
                status_r <= 4'd0;
                clear_msg;
            end
        end
    end
end

// ============================================================
// Pack output buses
// ============================================================
genvar gi;
generate
    for (gi = 0; gi < 15; gi = gi+1) begin : pack_gen
        assign kb_buf_pack[gi*6 +: 6] = kbuf[gi];
        assign kb_msg_pack[gi*6 +: 6] = msg_buf[gi];
    end
endgenerate

assign kb_buf_len = klen;
assign kb_cursor  = cursor_on;
assign kb_status  = status_r;

endmodule
