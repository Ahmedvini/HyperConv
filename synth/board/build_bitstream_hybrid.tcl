# ----------------------------------------------------------------------------
# HyperConv hybrid - build_bitstream_hybrid.tcl
# Full synth -> impl -> bitstream for the 2-px/cycle hybrid self-test demo.
# Same pins as the baseline flow (synth/board/board.xdc is reused verbatim).
#
#   vivado -mode batch -source synth/board/build_bitstream_hybrid.tcl \
#          -tclargs <part> [<testcase>]
#
#   <part>      e.g. xc7z020clg400-1 (PYNQ-Z2)
#   <testcase>  which sim/tests/<case> to bake into ROM (default: sobel_x)
#
# LED mapping identical to the baseline bitstream:
#   led[0]=pass / led[1]=fail / led[2]=done / led[3]=heartbeat.
# ----------------------------------------------------------------------------
if {[info exists argv] && (![info exists argc] || $argc == 0)} { set argc [llength $argv] }
if {$argc < 1} { error "usage: -tclargs <part> \[<testcase>\]  (or: set argv {<part> \[<testcase>\]} before sourcing)" }
set part [lindex $argv 0]
set tc   [expr {$argc > 1 ? [lindex $argv 1] : "sobel_x"}]

set root  [file normalize [file join [file dirname [info script]] ../..]]
set bdir  [file normalize [file dirname [info script]]]
set tdir  $root/sim/tests/$tc
set out   $bdir/build_hybrid
file mkdir $out

# $readmemh resolves relative to the run directory, so stage the chosen
# vectors as img/kernel/expected.hex right where synthesis runs.
foreach f {img kernel expected} {
    file copy -force $tdir/$f.hex $out/$f.hex
}
cd $out

create_project -in_memory -part $part

read_verilog [glob $root/rtl/*.v]
read_verilog $root/rtl/selftest/selftest_top_hybrid.v
read_verilog $bdir/board_top_hybrid.v
read_xdc     $bdir/board.xdc

synth_design -top board_top_hybrid -part $part
opt_design
place_design
phys_opt_design
route_design

# PL-only Zynq bitstream: the PS7 hard block is deliberately unused.
set_property SEVERITY Advisory [get_drc_checks ZPS7-1]

report_utilization    -file $out/util.rpt
report_timing_summary -file $out/timing.rpt
report_drc            -file $out/drc.rpt

write_bitstream -force $out/hyperconv_hybrid_selftest.bit
puts "BITSTREAM: wrote $out/hyperconv_hybrid_selftest.bit  (testcase=$tc part=$part)"
