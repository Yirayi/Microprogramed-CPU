`timescale 1ns / 1ps

module ROMReadTest;

    // ===== 信号声明 =====
    reg         clka;
    reg  [7:0]  addra;
    wire [31:0] douta;

    // ===== 例化被测模块 =====
    ControlMemory CMinstance (
        .clka     (clka),
        .addra    (addra),
        .douta    (douta)
    );

    // ===== 时钟生成 10ns周期 =====
    initial clka = 0;
    always #5 clka = ~clka;

    // ===== 测试逻辑 =====
    initial begin
        addra = 8'h01;
        @(posedge clka); #1;
        
        addra = 8'h02;
        @(posedge clka); #1;
        
         addra = 8'h10;
        @(posedge clka); #1;
        
         addra = 8'h11;
        @(posedge clka); #1;
        
         addra = 8'h20;
        @(posedge clka); #1;
        
        repeat(5) @(posedge clka);
 
        $display("=== Test Done ===");
        $finish;
    end

    // ===== 波形输出 =====
    initial begin
        $dumpfile("ROMReadTest.vcd");
        $dumpvars(0, ROMReadTest);
    end

endmodule