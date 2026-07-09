# HyperConv out-of-context constraints (for GUI project / manual runs;
# build.tcl generates the equivalent with the period scaled to its clk_ns arg)
# 300 MHz target on ZCU106 (xczu7ev-ffvc1156-2-e)
create_clock -period 3.333 -name clk [get_ports clk]

# I/O delay budget for the OOC core so port paths are timed. Distinct max
# (setup, 25% of period) and min (hold, 10% of period) values describe a
# realistic data-valid window and satisfy the XDCH-2 methodology check.
set inputs [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_input_delay  -clock clk -max 0.833 $inputs
set_input_delay  -clock clk -min 0.333 $inputs
set_output_delay -clock clk -max 0.833 [all_outputs]
set_output_delay -clock clk -min 0.333 [all_outputs]
