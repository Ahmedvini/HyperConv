# ----------------------------------------------------------------------------
# HyperConv - wave_setup.tcl
# Source this INSIDE the xsim GUI Tcl Console (after the simulation loads) to
# get a clean, report-ready wave window: only the key ports, with sensible
# radixes and named dividers.
#
#   source /home/ahmedelsheikh/Documents/GitHub/HyperConv/sim/wave_setup.tcl
#
# Then: run all   (or 'restart ; run all' if already run), then Zoom Fit.
#
# Finds the testbench scope dynamically so it works for any KSEL (Vivado
# specializes the top name to '\tb_conv_top(KSEL=n)' for non-default KSEL).
# ----------------------------------------------------------------------------
set top ""
foreach s [get_scopes /*] { if {[string match "*tb_conv_top*" $s]} { set top $s } }
if {$top eq ""} { error "wave_setup: could not find tb_conv_top scope" }

catch { remove_wave -of [get_wave_config] } ;# clear any existing waves

# clock / reset (testbench level)
current_scope $top
add_wave_divider "clock / reset"
add_wave -radix bin clk
add_wave -radix bin rst_n

# pixel stream in / result stream out (DUT ports)
current_scope $top/dut
add_wave_divider "pixel stream in"
add_wave -radix bin      px_valid
add_wave -radix unsigned px_data
add_wave_divider "result stream out"
add_wave -radix bin      out_valid
add_wave -radix dec      out_data      ;# signed 16-bit result
add_wave -radix bin      frame_done

current_scope $top
puts "wave_setup: signals added on scope $top. Now: run all, then Zoom Fit."
