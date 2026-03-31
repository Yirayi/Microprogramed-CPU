`timescale 1ns / 1ps

module ROMReadTest;

    // ===== 信号声明 =====
    reg         clka;
    reg         rsta;
    reg  [7:0]  addra;
    wire [31:0] douta;
    wire        rsta_busy;

    // ===== 例化被测模块 =====
    ControlMemory CMinstance (
        .clka     (clka),
        .rsta     (rsta),
        .addra    (addra),
        .douta    (douta),
        .rsta_busy(rsta_busy)
    );

    // ===== 时钟生成 10ns周期 =====
    initial clka = 0;
    always #5 clka = ~clka;

    // ===== 测试逻辑 =====
    initial begin
        // 初始化信号
        rsta  = 0;
        addra = 8'd0;

        // ---- 复位 ----
        $display("=== Reset ===");
        rsta = 1;
        @(posedge clka); #1;
        @(posedge clka); #1;
        rsta = 0;

        // 等待 rsta_busy 拉低（复位完成）
        wait(rsta_busy == 0);
        $display("Reset done at time %0t", $time);


        @(posedge clka); #1;
        addra = 8'd0;
        @(posedge clka); #1;  // 等一个周期（有输出寄存器）


        addra = 8'd2;
        @(posedge clka); #1;
        
        addra = 8'd3;
        @(posedge clka); #1;
        
         addra = 8'd5;
        @(posedge clka); #1;
        
         addra = 8'd6;
        @(posedge clka); #1;
        
         addra = 8'd8;
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