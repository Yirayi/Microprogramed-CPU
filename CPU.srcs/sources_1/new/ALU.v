// ============================================================
// ALU.v
// Microprogrammed CPU – Arithmetic Logic Unit
// ============================================================
// Combinational ALU driven by a 4-bit operation code.
// Inputs a, b are 16-bit operands.
// result is 16-bit (low word); mr_out carries the high 16 bits
// of the multiply result (zero for all other operations).
//
// Operations (op):
//   ALU_ADD    4'h0  result = a + b
//   ALU_SUB    4'h1  result = a - b
//   ALU_AND    4'h2  result = a & b
//   ALU_OR     4'h3  result = a | b
//   ALU_NOT    4'h4  result = ~a       (b unused)
//   ALU_SHR    4'h5  result = b >> 1   (logical, uses b directly)
//   ALU_SHL    4'h6  result = b << 1   (logical, uses b directly)
//   ALU_MPY    4'h7  {mr_out,result} = a * b  (unsigned 32-bit)
//   ALU_PASS_B 4'h8  result = b        (used for ACC <= BR load)
// ============================================================

`timescale 1ns / 1ps

module ALU (
    input  wire [15:0] a,        // first operand (typically ACC)
    input  wire [15:0] b,        // second operand (typically BR)
    input  wire [3:0]  op,       // operation select
    output reg  [15:0] result,   // 16-bit ALU output
    output reg  [15:0] mr_out    // high word of multiply (zero otherwise)
);

    // Operation encoding
    localparam ALU_ADD    = 4'h0;
    localparam ALU_SUB    = 4'h1;
    localparam ALU_AND    = 4'h2;
    localparam ALU_OR     = 4'h3;
    localparam ALU_NOT    = 4'h4;
    localparam ALU_SHR    = 4'h5;
    localparam ALU_SHL    = 4'h6;
    localparam ALU_MPY    = 4'h7;
    localparam ALU_PASS_B = 4'h8;

    wire [31:0] mult_result = {16'b0, a} * {16'b0, b};  // unsigned 32-bit

    always @(*) begin
        mr_out = 16'h0000;
        case (op)
            ALU_ADD:    result = a + b;
            ALU_SUB:    result = a - b;
            ALU_AND:    result = a & b;
            ALU_OR:     result = a | b;
            ALU_NOT:    result = ~a;
            ALU_SHR:    result = {1'b0, b[15:1]};   // logical shift right
            ALU_SHL:    result = {b[14:0], 1'b0};   // logical shift left
            ALU_MPY:    begin
                            result = mult_result[15:0];
                            mr_out = mult_result[31:16];
                        end
            ALU_PASS_B: result = b;
            default:    result = 16'h0000;
        endcase
    end

endmodule
