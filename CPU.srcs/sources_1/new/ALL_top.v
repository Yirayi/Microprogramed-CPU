`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/05/18 09:26:08
// Design Name: 
// Module Name: ALL_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ALL_top(
    input  wire clk,
    input  wire reset
    );
    wire CPU_halted;
    wire[15:0] segVal;
    CPU_top CPU(
    .clk(clk),
    .reset(reset),
    .halted(CPU_halted)    
    );
    
    wire [7:0] AN;
    wire [6:0] SEG;
    seven_seg_decimal sevenSegDisplay(
    .clk(clk),  
    .reset(reset),     
    .value(segVal),     
    .AN(AN),    
    .SEG(SEG)    
);
endmodule
