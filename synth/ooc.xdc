# HyperConv out-of-context constraints (for GUI project / manual runs;
# build.tcl generates the equivalent with the period scaled to its clk_ns arg)
# 200 MHz target on PYNQ-Z2 (xc7z020clg400-1)
create_clock -period 5.000 -name clk [get_ports clk]

# I/O delay budget for the OOC core so port paths are timed. Distinct max
# (setup, 25% of period) and min (hold, 10% of period) values describe a
# realistic data-valid window and satisfy the XDCH-2 methodology check.
set_input_delay -clock clk -max 1.250 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_input_delay -clock clk -min 0.500 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk -max 1.250 [all_outputs]
set_output_delay -clock clk -min 0.500 [all_outputs]

set_load 5.000 [all_outputs]
set_property LOAD 5 [get_ports frame_done]
set_property LOAD 5 [get_ports {out_data[0]}]
set_property LOAD 5 [get_ports {out_data[10]}]
set_property LOAD 5 [get_ports {out_data[11]}]
set_property LOAD 5 [get_ports {out_data[12]}]
set_property LOAD 5 [get_ports {out_data[13]}]
set_property LOAD 5 [get_ports {out_data[14]}]
set_property LOAD 5 [get_ports {out_data[15]}]
set_property LOAD 5 [get_ports {out_data[1]}]
set_property LOAD 5 [get_ports {out_data[2]}]
set_property LOAD 5 [get_ports {out_data[3]}]
set_property LOAD 5 [get_ports {out_data[4]}]
set_property LOAD 5 [get_ports {out_data[5]}]
set_property LOAD 5 [get_ports {out_data[6]}]
set_property LOAD 5 [get_ports {out_data[7]}]
set_property LOAD 5 [get_ports {out_data[8]}]
set_property LOAD 5 [get_ports {out_data[9]}]
set_property LOAD 5 [get_ports out_valid]
