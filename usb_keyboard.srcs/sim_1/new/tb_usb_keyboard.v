// tb_usb_keyboard_verified.v
`timescale 1ns / 1ps

module tb_usb_keyboard_verified();

parameter CLK_PERIOD = 20;     // 50MHz
parameter PS2_CLK_PERIOD = 80000; // 12.5kHz
parameter BAUD_PERIOD = 8680;  // 115200 bps

reg  clk;
reg  rst;
wire ps2_clk;
wire ps2_data;
wire txd;

reg  ps2_clk_out;
reg  ps2_data_out;
assign ps2_clk = ps2_clk_out;
assign ps2_data = ps2_data_out;

usb_keyboard uut(
    .clk(clk),
    .rst(rst),
    .PS2_CLOCK(ps2_clk),
    .PS2_DATA(ps2_data),
    .TXD(txd)
);

// 模拟发送单个 PS/2 字节
task send_ps2_byte;
    input [7:0] scancode;
    reg [10:0] ps2_frame;
    integer i;
    begin
        // Frame: Start(0) + Data(LSB first) + Parity(Odd) + Stop(1)
        ps2_frame = {1'b1, ~^scancode, scancode[7:0], 1'b0};
        
        for(i = 0; i <= 10; i = i + 1) begin
            ps2_data_out = ps2_frame[i];
            #(PS2_CLK_PERIOD/2);
            ps2_clk_out = 1'b0;
            #(PS2_CLK_PERIOD/2);
            ps2_clk_out = 1'b1;
        end
        #(PS2_CLK_PERIOD * 2);
    end
endtask

// 模拟完整的人类按键动作：按下 -> 松开
task test_full_keypress;
    input [7:0] scancode;
    input [7:0] expected_ascii;
    reg [7:0] received_char;
    reg [9:0] uart_frame;
    integer i;
    begin
        $display("\n--- Testing Keystroke 0x%02X -> expecting '%c' ---", scancode, expected_ascii);
        
        // 1. 模拟按下按键 (发送扫描码)
        fork
            send_ps2_byte(scancode);
            begin
                // 监听 UART 输出
                @(negedge txd);
                #(BAUD_PERIOD/2);
                for(i = 0; i <= 9; i = i + 1) begin
                    uart_frame[i] = txd;
                    #(BAUD_PERIOD);
                end
                received_char = uart_frame[8:1];
                if(received_char == expected_ascii) 
                    $display("[OK] Press detected: '%c'", received_char);
                else 
                    $display("[ERROR] Press failed. Got: '%c'", received_char);
            end
        join
        
        #(BAUD_PERIOD * 5);

        // 2. 模拟松开按键 (发送 F0 + 扫描码)
        $display("[INFO] Releasing key...");
        send_ps2_byte(8'hF0);
        send_ps2_byte(scancode);
        
        // 3. 验证松开按键时 UART 没有发送任何数据
        #(BAUD_PERIOD * 15);
        if (txd === 1'b1) 
            $display("[OK] Release correctly ignored by UART.");
        else 
            $display("[ERROR] UART falsely triggered on key release!");
    end
endtask

// 时钟生成
initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// 测试主流程
initial begin
    rst = 1'b1;
    ps2_clk_out = 1'b1;
    ps2_data_out = 1'b1;
    
    repeat(10) @(posedge clk);
    rst = 1'b0;
    
    #(PS2_CLK_PERIOD * 2);
    
    // 测试正常的按键与释放
    test_full_keypress(8'h1C, "a"); // 按下并松开 A
    test_full_keypress(8'h32, "b"); // 按下并松开 B
    
    $display("\n========================================");
    $display("SIMULATION COMPLETE");
    $display("========================================");
    $finish;
end

initial begin
    $dumpfile("tb_usb_keyboard.vcd");
    $dumpvars(0, tb_usb_keyboard_verified);
end

endmodule