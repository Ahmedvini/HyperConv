# ----------------------------------------------------------------------------
# HyperConv - board.xdc  (TEMPLATE - fill in for your board before building)
#
# Replace every <...> placeholder with the values from your board's master
# XDC / schematic, then run synth/board/build_bitstream.tcl.
#
# You need exactly three things: a clock, a reset button, and 4 LEDs.
# ----------------------------------------------------------------------------

# ---- clock -----------------------------------------------------------------
# Set the pin and the I/O standard for your board's clock, and the REAL period
# (ns) of that clock. Example below assumes a 100 MHz single-ended clock.
set_property -dict { PACKAGE_PIN <CLK_PIN>  IOSTANDARD <CLK_IOSTD> } [get_ports clk_pin]
create_clock -period <CLK_PERIOD_NS> -name sys_clk [get_ports clk_pin]
#   100 MHz -> 10.000    125 MHz -> 8.000    50 MHz -> 20.000

# ---- reset button ----------------------------------------------------------
set_property -dict { PACKAGE_PIN <RST_PIN>  IOSTANDARD <RST_IOSTD> } [get_ports rst_pin]

# ---- status LEDs -----------------------------------------------------------
# led[0]=pass  led[1]=fail  led[2]=done  led[3]=heartbeat
set_property -dict { PACKAGE_PIN <LED0_PIN>  IOSTANDARD <LED_IOSTD> } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN <LED1_PIN>  IOSTANDARD <LED_IOSTD> } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN <LED2_PIN>  IOSTANDARD <LED_IOSTD> } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN <LED3_PIN>  IOSTANDARD <LED_IOSTD> } [get_ports {led[3]}]

# Typical I/O standards: LVCMOS33 (most 7-series boards, 3.3 V banks),
# LVCMOS18 (many UltraScale+ HP/HD banks). Match your board's bank voltage.
