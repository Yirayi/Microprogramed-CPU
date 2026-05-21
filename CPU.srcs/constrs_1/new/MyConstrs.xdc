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