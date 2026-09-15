# ----------------------------------------------------------------------------
# OOC synthesis of the DMP probe: does the packed multiply infer ONE DSP48E1?
# vivado -mode batch -source experiments/dmp_probe/synth_dmp_probe.tcl
# ----------------------------------------------------------------------------
set part xc7z020clg400-1
set root [file normalize [file join [file dirname [info script]] ../..]]

create_project -in_memory -part $part
read_verilog $root/experiments/dmp_probe/dmp_probe.v

set xdc $root/experiments/dmp_probe/ooc.xdc
set fh [open $xdc w]
puts $fh "create_clock -period 5.0 -name clk \[get_ports clk\]"
close $fh
read_xdc -mode out_of_context $xdc

synth_design -top dmp_probe -part $part -mode out_of_context
report_utilization -file $root/experiments/dmp_probe/util_synth.rpt

# DSP detail
puts "HYBRID_DMP_PROBE: DSP48 primitives used:"
foreach c [get_cells -hier -filter {REF_NAME =~ DSP48*}] { puts "  [get_property NAME $c]" }
puts "HYBRID_DMP_PROBE: total DSP = [llength [get_cells -hier -filter {REF_NAME =~ DSP48*}]]"

# also push it through implementation for a timing number
opt_design
place_design
phys_opt_design
route_design
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "HYBRID_DMP_PROBE: WNS = $wns (target 200 MHz)"
report_timing_summary -file $root/experiments/dmp_probe/timing_impl.rpt
