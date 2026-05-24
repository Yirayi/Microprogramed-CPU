// ============================================================
// sim_LaunchCPU.v
// Testbench: PS/2 keyboard input verification + single-step mode
//
// 主要用途（本版）：验证 PS/2 → ps2_decoder → vga_display 输入链路
//
// PS/2 协议（手册 §8.1/§8.2）:
//   · PIC24 开漏驱动，空闲时钟/数据均为 HIGH
//   · 11 位帧: start(0), D0..D7(LSB 先), odd_parity, stop(1)
//   · 数据在 ps2_clk 高电平期间设置，HOST 在下降沿采样
//   · 断码: 先发 0xF0，再发对应 make 码
//
// 观察波形（Vivado Simulation → 运行后在 Scope 面板添加信号）:
//   Layer 1 – PS/2 物理信号
//     ps2_clk_tb                           ← 模拟的时钟
//     ps2_data_tb                          ← 模拟的数据
//   Layer 2 – PS2_receiver 内部
//     dut/u_ps2_rx/bit_count               ← 应依次 0→10 再复位
//     dut/u_ps2_rx/key_data   [hex]        ← 每帧结束后更新的扫描码
//     dut/u_ps2_rx/key_valid               ← 1 周期脉冲，表示帧接收完毕
//     dut/u_ps2_rx/parity_error            ← 应始终为 0
//   Layer 3 – ps2_decoder 输出
//     dut/u_ps2_dec/last_scan [hex]        ← 最近收到的原始扫描码
//     dut/u_ps2_dec/char_valid             ← 可打印字符脉冲
//     dut/u_ps2_dec/char_data  [unsigned]  ← 字体索引 (A=10, D=13…)
//     dut/u_ps2_dec/is_enter               ← 回车脉冲
//     dut/u_ps2_dec/is_backspace           ← 退格脉冲
//   Layer 4 – vga_display 输入缓冲
//     dut/vga/input_pos        [unsigned]  ← 光标位置，字符输入时递增
//     dut/vga/input_hist_count [unsigned]  ← 历史行数，回车时递增
//
// $display 输出也会打印每个事件时间戳，无需手动看波形即可核查。
// ============================================================
`timescale 1ns / 1ps

module sim_LaunchCPU;

// ── stimulus registers ─────────────────────────────────────────────────────
reg        clk;
reg        reset_btn;
reg [15:0] sw;
reg        btn_step;
reg        ps2_clk_tb;   // PS/2 clock (idle = 1)
reg        ps2_data_tb;  // PS/2 data  (idle = 1)

// ── DUT outputs ────────────────────────────────────────────────────────────
wire [7:0] AN;
wire [6:0] SEG;
wire       vga_hs, vga_vs;
wire [3:0] vga_r, vga_g, vga_b;

// ── DUT ───────────────────────────────────────────────────────────────────
ALL_top dut (
    .clk      (clk),
    .reset_btn(reset_btn),
    .sw       (sw),
    .btn_step (btn_step),
    .ps2_clk  (ps2_clk_tb),
    .ps2_data (ps2_data_tb),
    .AN       (AN),
    .SEG      (SEG),
    .vga_hs   (vga_hs),
    .vga_vs   (vga_vs),
    .vga_r    (vga_r),
    .vga_g    (vga_g),
    .vga_b    (vga_b)
);

// ── 100 MHz system clock ───────────────────────────────────────────────────
initial clk = 0;
always  #5 clk = ~clk;

// ── convenience aliases ────────────────────────────────────────────────────
wire halted        = dut.halted;
wire instr_running = dut.cpu.cu.instr_running;

// ============================================================
// PS/2 发送任务
//
// 时序参数：半位周期 PS2_HALF = 2000 ns = 2 µs
//   · 每位耗时 ≈ 4.25 µs，11 位帧 ≈ 47 µs/字节
//   · PS2_receiver 超时阈值 500 µs >> 4.25 µs，不会误复位
//   · 两级同步器延迟 2 周期(20 ns) << 2000 ns，保证采样正确
// ============================================================
localparam PS2_HALF = 2_000; // ns

// 发送单字节：11 位 PS/2 帧
// 帧顺序（bit 0 先发）: start=0, D0..D7, parity(odd), stop=1
task ps2_send_byte;
    input [7:0] b;
    integer     i;
    reg [10:0]  frame;
    begin
        frame[0]   = 1'b0;    // start bit
        frame[8:1] = b;       // D0(LSB)…D7(MSB)
        frame[9]   = ~(^b);   // 奇校验位：若 data 中 1 的个数为偶数则补 1
        frame[10]  = 1'b1;    // stop bit

        for (i = 0; i < 11; i = i + 1) begin
            // 数据在时钟高电平期间设置（setup time = PS2_HALF）
            ps2_data_tb = frame[i];
            #(PS2_HALF);
            // 时钟下降沿 → HOST(FPGA) 在此采样
            ps2_clk_tb  = 1'b0;
            #(PS2_HALF);
            // 时钟上升沿
            ps2_clk_tb  = 1'b1;
            #(PS2_HALF / 4); // 短暂高电平，再进入下一位
        end
        ps2_data_tb = 1'b1;       // 数据回到空闲高电平
        #(PS2_HALF * 6);          // 字节间间隔
    end
endtask

// 按下并释放一个键（make 码 + 0xF0 断码前缀 + make 码）
task ps2_key;
    input [7:0] make_code;
    begin
        $display("[%8.3f us] KEY PRESS   scan=0x%02X",
                 $realtime / 1000.0, make_code);
        ps2_send_byte(make_code); // make：键按下
        #(PS2_HALF * 15);         // 模拟按键保持时间
        ps2_send_byte(8'hF0);     // 断码前缀
        ps2_send_byte(make_code); // make 码（断码）
    end
endtask

// ── 事件监视器（打印时间戳，无需手动看波形）─────────────────────────────
always @(posedge dut.u_ps2_rx.key_valid)
    $display("[%8.3f us] PS2_receiver  key_data=0x%02X  parity_err=%b",
             $realtime / 1000.0,
             dut.u_ps2_rx.key_data, dut.u_ps2_rx.parity_error);

always @(posedge dut.u_ps2_dec.char_valid)
    $display("[%8.3f us] ps2_decoder   char font_idx=%-2d  input_pos=%0d → %0d",
             $realtime / 1000.0,
             dut.u_ps2_dec.char_data,
             dut.vga.input_pos,
             dut.vga.input_pos + 1);

always @(posedge dut.u_ps2_dec.is_enter)
    $display("[%8.3f us] ps2_decoder   ENTER  hist_count: %0d → %0d",
             $realtime / 1000.0,
             dut.vga.input_hist_count,
             dut.vga.input_hist_count + 1);

always @(posedge dut.u_ps2_dec.is_backspace)
    $display("[%8.3f us] ps2_decoder   BACKSPACE  input_pos: %0d → %0d",
             $realtime / 1000.0,
             dut.vga.input_pos,
             dut.vga.input_pos - 1);

// ── 单步辅助任务（保留，CPU 调试用）──────────────────────────────────────
task step_one_instr;
    begin
        @(posedge clk); #1;
        force dut.step_pulse = 1'b1;
        @(posedge clk); #1;
        force dut.step_pulse = 1'b0;
        release dut.step_pulse;
        repeat(15) @(posedge clk);
    end
endtask

// ── 主激励 ────────────────────────────────────────────────────────────────
initial begin
    reset_btn   = 1'b0;
    // SW[15:14]=01 → exec_mode=01（单指令步进模式，键盘输入生效）
    // SW[11:0]=10  → port IN[0] 测试数据
    sw          = 16'h400A;
    btn_step    = 1'b0;
    ps2_clk_tb  = 1'b1;  // PS/2 空闲：高电平
    ps2_data_tb = 1'b1;

    #200;
    reset_btn = 1'b1;    // 释放复位

    // 等待 BRAM 初始化完成
    @(negedge dut.cpu.internal_reset);
    repeat(20) @(posedge clk);

    $display("");
    $display("=== PS/2 仿真开始：exec_mode=01，键盘输入已激活 ===");
    $display("=== 预期：每次字符按键 input_pos+1，Enter 后 hist_count+1 ===");
    $display("");

    // ── 输入第一行: "ADD 03" + Enter ─────────────────────────────────────
    // 期望 input_pos: 0→1→2→3→4→5→6, 然后 Enter 复位到 0, hist_count→1
    ps2_key(8'h1C);  // A   font_idx=10
    ps2_key(8'h23);  // D   font_idx=13
    ps2_key(8'h23);  // D   font_idx=13
    ps2_key(8'h29);  // 空格 font_idx=16
    ps2_key(8'h26);  // 3   font_idx=3
    ps2_key(8'h5A);  // Enter → is_enter=1

    #50_000;

    // ── 输入第二行: "SUB 05" + Enter ─────────────────────────────────────
    ps2_key(8'h1B);  // S   font_idx=28
    ps2_key(8'h30);  // B   ← 注意: B 的 Set2 码是 0x32, 此处故意写错
                     //     decoder 会把 0x30 视为 unknown (char_valid 不触发)
                     //     → 可观察到 input_pos 不变
    ps2_key(8'h32);  // B   font_idx=11 (正确扫描码)
    ps2_key(8'h29);  // 空格
    ps2_key(8'h2E);  // 5   font_idx=5
    ps2_key(8'h66);  // Backspace → 删除 '5'
    ps2_key(8'h16);  // 1   font_idx=1
    ps2_key(8'h5A);  // Enter

    #50_000;

    $display("");
    $display("=== 仿真结束 ===");
    $display("    input_pos      = %0d  (期望: 0，Enter 后已清零)",
             dut.vga.input_pos);
    $display("    input_hist_count = %0d  (期望: 2，两行历史)",
             dut.vga.input_hist_count);
    $display("    last_scan      = 0x%02X", dut.u_ps2_dec.last_scan);
    $display("");
    $finish;
end

// ── 安全超时：5 ms ──────────────────────────────────────────────────────
initial begin
    #5_000_000;
    $display("=== Timeout (5 ms)：仿真未正常结束 ===");
    $finish;
end

endmodule
