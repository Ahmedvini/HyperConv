# ----------------------------------------------------------------------------
# HyperConv hybrid - build_hybrid.tcl
# Out-of-context synthesis + implementation of conv_top_hybrid, same
# methodology as the baseline synth/build.tcl.
#
#   vivado -mode batch -source synth/build_hybrid.tcl \
#       [-tclargs <part> [<clk_ns>] [<tag>]]
# ----------------------------------------------------------------------------
set part   xc7z020clg400-1
set clk_ns 5.0
set tag    ""
if {$argc > 0} { set part   [lindex $argv 0] }
if {$argc > 1} { set clk_ns [lindex $argv 1] }
if {$argc > 2} { set tag    _[lindex $argv 2] }

set root    [file normalize [file join [file dirname [info script]] ..]]
set reports $root/synth/reports_hybrid$tag
file mkdir $reports

create_project -in_memory -part $part

read_verilog [glob $root/rtl/*.v]
set xdc $reports/ooc_gen.xdc
set fh [open $xdc w]
puts $fh "create_clock -period $clk_ns -name clk \[get_ports clk\]"
set tmax [format %.3f [expr {$clk_ns * 0.25}]]
set tmin [format %.3f [expr {$clk_ns * 0.10}]]
puts $fh "set inputs \[get_ports -filter {DIRECTION == IN && NAME != clk}\]"
puts $fh "set_input_delay  -clock clk -max $tmax \$inputs"
puts $fh "set_input_delay  -clock clk -min $tmin \$inputs"
puts $fh "set_output_delay -clock clk -max $tmax \[all_outputs\]"
puts $fh "set_output_delay -clock clk -min $tmin \[all_outputs\]"
close $fh
read_xdc -mode out_of_context $xdc

# defaults: N=3, 32x32, 4 kernel sets, u8 in / s8 coeff / s16 out
synth_design -top conv_top_hybrid -part $part -mode out_of_context
report_utilization      -file $reports/util_synth.rpt

opt_design
place_design
phys_opt_design
route_design

report_utilization      -file $reports/util_impl.rpt
report_timing_summary   -file $reports/timing_impl.rpt -delay_type min_max \
                        -report_unconstrained -max_paths 10
report_power            -file $reports/power_impl.rpt
report_design_analysis  -file $reports/design_analysis.rpt
report_methodology      -file $reports/methodology.rpt

write_checkpoint -force $root/synth/conv_top_hybrid_routed$tag.dcp

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "HYBRID_RESULT part=$part wns=$wns"
