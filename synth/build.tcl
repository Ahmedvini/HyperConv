# ----------------------------------------------------------------------------
# HyperConv - build.tcl
# Out-of-context synthesis + implementation of conv_top, producing the
# utilization / timing / power reports required by the competition.
#
#   vivado -mode batch -source synth/build.tcl [-tclargs <part> [<clk_ns>] [<tag>] [lutmult]]
#   Multipliers use DSP blocks by default; 4th arg "lutmult" forces LUT
#   multipliers (NO_DSP_MULT) for resource-tradeoff comparison.
#
# Default part: ZCU106 (Zynq UltraScale+ XCZU7EV). OOC mode is used because
# the accelerator is a core, not a full board design; pin constraints are
# out of scope and stated as an assumption in the report.
# ----------------------------------------------------------------------------
set part   xczu7ev-ffvc1156-2-e
set clk_ns 3.333
set tag    ""
set defines {}
if {$argc > 0} { set part   [lindex $argv 0] }
if {$argc > 1} { set clk_ns [lindex $argv 1] }
if {$argc > 2} { set tag    _[lindex $argv 2] }
if {$argc > 3 && [lindex $argv 3] eq "lutmult"} { set defines {NO_DSP_MULT=1} }

set root    [file normalize [file join [file dirname [info script]] ..]]
set reports $root/synth/reports$tag
file mkdir $reports

create_project -in_memory -part $part

read_verilog [glob $root/rtl/*.v]
set xdc $reports/ooc_gen.xdc
set fh [open $xdc w]
puts $fh "create_clock -period $clk_ns -name clk \[get_ports clk\]"
# I/O delay budget for the OOC core (25% of the period each side) so timing
# analysis covers port paths and TIMING-18 methodology checks are satisfied
set tio [format %.3f [expr {$clk_ns * 0.25}]]
puts $fh "set_input_delay  -clock clk $tio \[get_ports -filter {DIRECTION == IN && NAME != clk}\]"
puts $fh "set_output_delay -clock clk $tio \[all_outputs\]"
close $fh
read_xdc -mode out_of_context $xdc

# defaults: N=3, 32x32, 4 kernel sets, u8 in / s8 coeff / s16 out
if {[llength $defines]} {
    synth_design -top conv_top -part $part -mode out_of_context -verilog_define $defines
} else {
    synth_design -top conv_top -part $part -mode out_of_context
}
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

write_checkpoint -force $root/synth/conv_top_routed$tag.dcp

# one-line summary for the log
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "HYPERCONV_RESULT part=$part wns=$wns"
