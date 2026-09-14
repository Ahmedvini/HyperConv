# HyperConv out-of-context constraints (for GUI project / manual runs;
# build.tcl generates the equivalent with the period scaled to its clk_ns arg)
# 200 MHz target on PYNQ-Z2 (xc7z020clg400-1)
create_clock -period 5.0 -name clk [get_ports clk]

# I/O delay budget for the OOC core so port paths are timed. Distinct max
# (setup, 25% of period) and min (hold, 10% of period) values describe a
# realistic data-valid window and satisfy the XDCH-2 methodology check.
set inputs [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_input_delay  -clock clk -max 1.250 $inputs
set_input_delay  -clock clk -min 0.500 $inputs
set_output_delay -clock clk -max 1.250 [all_outputs]
set_output_delay -clock clk -min 0.500 [all_outputs]
