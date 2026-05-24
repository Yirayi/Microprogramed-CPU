# 时钟
set_property PACKAGE_PIN E3 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.0 [get_ports clk]

# 复位（CPU RESET按钮，按下为低）
set_property PACKAGE_PIN C12 [get_ports reset_btn]
set_property IOSTANDARD LVCMOS33 [get_ports reset_btn]

# 数码管阳极
set_property PACKAGE_PIN U13 [get_ports {AN[7]}]
set_property PACKAGE_PIN K2  [get_ports {AN[6]}]
set_property PACKAGE_PIN T14 [get_ports {AN[5]}]
set_property PACKAGE_PIN P14 [get_ports {AN[4]}]
set_property PACKAGE_PIN J14 [get_ports {AN[3]}]
set_property PACKAGE_PIN T9  [get_ports {AN[2]}]
set_property PACKAGE_PIN J18 [get_ports {AN[1]}]
set_property PACKAGE_PIN J17 [get_ports {AN[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {AN[*]}]

# 数码管阴极
set_property PACKAGE_PIN T10 [get_ports {SEG[6]}]
set_property PACKAGE_PIN R10 [get_ports {SEG[5]}]
set_property PACKAGE_PIN K16 [get_ports {SEG[4]}]
set_property PACKAGE_PIN K13 [get_ports {SEG[3]}]
set_property PACKAGE_PIN P15 [get_ports {SEG[2]}]
set_property PACKAGE_PIN T11 [get_ports {SEG[1]}]
set_property PACKAGE_PIN L18 [get_ports {SEG[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {SEG[*]}]

# VGA接口 (Nexys 4 DDR 手册 Figure 11)
# 红色通道 RED[0..3] → vga_r[0..3]
set_property PACKAGE_PIN A3  [get_ports {vga_r[0]}]
set_property PACKAGE_PIN B4  [get_ports {vga_r[1]}]
set_property PACKAGE_PIN C5  [get_ports {vga_r[2]}]
set_property PACKAGE_PIN A4  [get_ports {vga_r[3]}]
# 绿色通道 GRN[0..3] → vga_g[0..3]
set_property PACKAGE_PIN C6  [get_ports {vga_g[0]}]
set_property PACKAGE_PIN A5  [get_ports {vga_g[1]}]
set_property PACKAGE_PIN B6  [get_ports {vga_g[2]}]
set_property PACKAGE_PIN A6  [get_ports {vga_g[3]}]
# 蓝色通道 BLU[0..3] → vga_b[0..3]
set_property PACKAGE_PIN B7  [get_ports {vga_b[0]}]
set_property PACKAGE_PIN C7  [get_ports {vga_b[1]}]
set_property PACKAGE_PIN D7  [get_ports {vga_b[2]}]
set_property PACKAGE_PIN D8  [get_ports {vga_b[3]}]
# 同步信号
set_property PACKAGE_PIN B11 [get_ports vga_hs]
set_property PACKAGE_PIN B12 [get_ports vga_vs]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports vga_hs]
set_property IOSTANDARD LVCMOS33 [get_ports vga_vs]

# 拨码开关 SW[15:0]
# sw[14]=exec_mode[0], sw[15]=exec_mode[1]; sw[7:0]=IN[0]数据
set_property PACKAGE_PIN J15 [get_ports {sw[0]}]
set_property PACKAGE_PIN L16 [get_ports {sw[1]}]
set_property PACKAGE_PIN M13 [get_ports {sw[2]}]
set_property PACKAGE_PIN R15 [get_ports {sw[3]}]
set_property PACKAGE_PIN R17 [get_ports {sw[4]}]
set_property PACKAGE_PIN T18 [get_ports {sw[5]}]
set_property PACKAGE_PIN U18 [get_ports {sw[6]}]
set_property PACKAGE_PIN R13 [get_ports {sw[7]}]
set_property PACKAGE_PIN T8  [get_ports {sw[8]}]
set_property PACKAGE_PIN U8  [get_ports {sw[9]}]
set_property PACKAGE_PIN R16 [get_ports {sw[10]}]
set_property PACKAGE_PIN T13 [get_ports {sw[11]}]
set_property PACKAGE_PIN H6  [get_ports {sw[12]}]
set_property PACKAGE_PIN U12 [get_ports {sw[13]}]
set_property PACKAGE_PIN U11 [get_ports {sw[14]}]
set_property PACKAGE_PIN V10 [get_ports {sw[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

# 按钮（均高电平有效）
# btn_step = BTNC (N17): 单步触发
set_property PACKAGE_PIN N17 [get_ports btn_step]
set_property IOSTANDARD LVCMOS33 [get_ports btn_step]

# PS/2 键盘接口 (Nexys 4 DDR, PIC24 HID Controller)
# 手册要求: open-drain 驱动, FPGA 必须开启内部上拉 (PULLUP true)
# 否则空闲时 ps2_clk/ps2_data 悬空读为 0, 无法检测边沿
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33 PULLUP true} [get_ports ps2_clk]
set_property -dict {PACKAGE_PIN B2 IOSTANDARD LVCMOS33 PULLUP true} [get_ports ps2_data]