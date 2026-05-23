// usb_keyboard.v
module usb_keyboard(
    input             clk,
    input             rst,
    inout             PS2_CLOCK,
    inout             PS2_DATA,
    output reg        TXD
);

wire ps2_clk_in  = PS2_CLOCK;
wire ps2_data_in = PS2_DATA;
assign PS2_CLOCK = 1'bz;
assign PS2_DATA  = 1'bz;

wire [7:0] key_scancode;
wire       key_valid;
wire       parity_err;

ps2_receiver ps2_receiver_inst(
    .clk(clk),
    .rst(rst),
    .ps2_clk(ps2_clk_in),
    .ps2_data(ps2_data_in),
    .key_data(key_scancode),
    .key_valid(key_valid),
    .parity_error(parity_err)
);

// ASCII 查表函数保持原样
function [7:0] scancode_to_ascii(input [7:0] scancode);
    begin
        case(scancode)
            8'h1C: scancode_to_ascii = "a";
            8'h32: scancode_to_ascii = "b";
            // ... (保留你原来的所有键值映射, 篇幅原因省略部分)
            8'h1A: scancode_to_ascii = "z";
            8'h29: scancode_to_ascii = " ";
            8'h5A: scancode_to_ascii = 8'h0D;
            default: scancode_to_ascii = 8'h00;
        endcase
    end
endfunction

reg [15:0] baud_counter;
reg [9:0]  tx_buffer;
reg [3:0]  tx_bit_count;
reg        sending;

// 新增：按键释放标志位
reg        is_break; 

always @(posedge clk or posedge rst) begin
    if(rst) begin
        baud_counter <= 16'd0;
        tx_buffer <= 10'b1111111111;
        tx_bit_count <= 4'd0;
        sending <= 1'b0;
        TXD <= 1'b1;
        is_break <= 1'b0;
    end else begin
        // UART 发送逻辑
        if (sending) begin
            if (baud_counter < 16'd867) begin // 100M/115200 - 1
                baud_counter <= baud_counter + 16'd1;
            end else begin
                baud_counter <= 16'd0;
                if (tx_bit_count < 4'd10) begin
                    TXD <= tx_buffer[0];
                    tx_buffer <= {1'b1, tx_buffer[9:1]};
                    tx_bit_count <= tx_bit_count + 4'd1;
                end else begin
                    sending <= 1'b0;
                    TXD <= 1'b1;
                end
            end
        end
        
        // 键盘协议解析逻辑
        if (key_valid && !parity_err) begin
            if (key_scancode == 8'hF0) begin
                is_break <= 1'b1; // 收到断码标志，说明下一个码是松开的键
            end else if (key_scancode == 8'hE0) begin
                // 扩展码标志（此处暂时忽略，不影响字母输入）
            end else begin
                if (is_break) begin
                    is_break <= 1'b0; // 这是按键松开的扫描码，清除标志，但不触发发送
                end else begin
                    // 这是真正的按键按下，触发 UART 发送
                    if (~sending && (scancode_to_ascii(key_scancode) != 8'h00)) begin
                        tx_buffer <= {1'b1, scancode_to_ascii(key_scancode), 1'b0};
                        tx_bit_count <= 4'd0;
                        sending <= 1'b1;
                        baud_counter <= 16'd0;
                    end
                end
            end
        end
    end
end

endmodule