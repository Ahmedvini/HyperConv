# HyperConv out-of-context constraints (for manual/GUI runs; build.tcl
# generates the equivalent with the period scaled to its clk_ns argument)
# 300 MHz target on ZCU106 (xczu7ev-ffvc1156-2-e)
create_clock -period 3.333 -name clk [get_ports clk]

# I/O delay budget for the OOC core (25% of the period each side) so port
# paths are timed and TIMING-18 methodology checks are satisfied
set_input_delay  -clock clk 0.833 [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_output_delay -clock clk 0.833 [all_outputs]
