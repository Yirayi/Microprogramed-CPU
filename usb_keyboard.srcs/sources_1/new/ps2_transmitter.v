// ps2_receiver.v
module ps2_receiver(
    input            clk,
    input            rst,
    input            ps2_clk,
    input            ps2_data,
    output reg [7:0] key_data,
    output reg       key_valid,
    output reg       parity_error
);

// 跨时钟域两级同步 (打拍抗亚稳态)
reg [1:0] ps2_clk_r;
reg [1:0] ps2_data_r;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        ps2_clk_r <= 2'b11;
        ps2_data_r <= 2'b11;
    end else begin
        ps2_clk_r <= {ps2_clk_r[0], ps2_clk};
        ps2_data_r <= {ps2_data_r[0], ps2_data};
    end
end

wire ps2_clk_negedge = (ps2_clk_r == 2'b10);
wire ps2_data_sync   = ps2_data_r[1];

reg [3:0] bit_count;
reg [9:0] shift_reg;    // 存储 Start(1) + Data(8) + Parity(1)
reg [15:0] timeout_cnt; // 超时计数器

always @(posedge clk or posedge rst) begin
    if(rst) begin
        key_data <= 8'h00;
        key_valid <= 1'b0;
        parity_error <= 1'b0;
        bit_count <= 4'd0;
        timeout_cnt <= 16'd0;
    end else begin
        key_valid <= 1'b0; // 默认拉低脉冲
        
        if (ps2_clk_negedge) begin
            timeout_cnt <= 16'd0; // 只要有时钟边沿就清零超时
            
            // 第11位是停止位，直接在这里判断，前10位存入shift_reg
            if (bit_count == 4'd10) begin
                bit_count <= 4'd0;
                // 校验：起始位为0，停止位为1
                if (shift_reg[0] == 1'b0 && ps2_data_sync == 1'b1) begin
                    key_data <= shift_reg[8:1];
                    // PS/2 是奇校验: 数据位+校验位的 1 的总数为奇数
                    parity_error <= ~(^shift_reg[9:1]); 
                    key_valid <= 1'b1;
                end
            end else begin
                shift_reg[bit_count] <= ps2_data_sync;
                bit_count <= bit_count + 4'd1;
            end
        end else begin
            // 超时恢复机制 (50MHz下16'd50000约为1ms。如果1ms没有新边沿，强制重置状态)
            if (timeout_cnt < 16'd50000) begin
                timeout_cnt <= timeout_cnt + 16'd1;
            end else begin
                bit_count <= 4'd0; 
            end
        end
    end
end

endmodule