## 这是一份修正后的 Nexys4 DDR Rev. C 约束文件

## Clock signal (板载 100MHz)
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports clk]

## Switches (复位按键，使用 SW0)
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports rst]

## USB HID (PS/2 键盘接口)
# 将原先的 USB_CLOCK/DATA 改为顶层模块对应的 PS2_CLOCK/DATA
# 建议开启内部上拉 PULLUP true 增加信号稳定性
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33 PULLUP true} [get_ports PS2_CLOCK]
set_property -dict {PACKAGE_PIN B2 IOSTANDARD LVCMOS33 PULLUP true} [get_ports PS2_DATA]

## USB-RS232 Interface (串口)
# 注释掉未使用的 RXD, CTS, RTS，只保留 TXD
# set_property -dict {PACKAGE_PIN C4 IOSTANDARD LVCMOS33} [get_ports RXD]
set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports TXD]
# set_property -dict {PACKAGE_PIN D3 IOSTANDARD LVCMOS33} [get_ports CTS]
# set_property -dict {PACKAGE_PIN E5 IOSTANDARD LVCMOS33} [get_ports RTS]