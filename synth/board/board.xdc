# ----------------------------------------------------------------------------
# HyperConv - board.xdc  (PYNQ-Z2, Zynq-7020 XC7Z020-1)
#
# Pins from the PYNQ-Z2 master XDC / schematic:
#   100 MHz oscillator on H16, buttons active-high with board pull-downs,
#   LEDs LD3-LD0 on M14/N16/P14/R14.
# ----------------------------------------------------------------------------

# ---- clock -----------------------------------------------------------------
# 100 MHz single-ended oscillator
set_property IOSTANDARD LVCMOS33 [get_ports clk_pin]
create_clock -period 10.000 -name sys_clk [get_ports clk_pin]

# ---- reset button ----------------------------------------------------------
# BTN0 (active-high on PYNQ-Z2; board_top.v inverts it)
set_property IOSTANDARD LVCMOS33 [get_ports rst_pin]

# ---- status LEDs -----------------------------------------------------------
# led[0]=pass  led[1]=fail  led[2]=done  led[3]=heartbeat
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

# ---- quasi-static I/O -------------------------------------------------------
# The reset button and the status LEDs change at human speed; they are not
# timed paths. False-path them so check_timing reports no unconstrained I/O.
set_false_path -from [get_ports rst_pin]
set_false_path -to [get_ports {led[*]}]

