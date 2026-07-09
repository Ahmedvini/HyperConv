# ----------------------------------------------------------------------------
# HyperConv - build_bitstream.tcl
# Full synth -> impl -> bitstream for the standalone self-test demo.
# Only run this AFTER filling in synth/board/board.xdc for your board and
# passing the board's part number.
#
#   vivado -mode batch -source synth/board/build_bitstream.tcl \
#          -tclargs <part> [<testcase>]
#
#   <part>      e.g. xc7a35tcpg236-1 (Basys3), xc7z020clg400-1 (PYNQ-Z2), ...
#   <testcase>  which sim/tests/<case> to bake into ROM (default: sobel_x)
#
# The self-test streams the baked-in image through conv_top, compares on-chip
# to the golden result, and lights led[0]=pass / led[1]=fail / led[2]=done /
# led[3]=heartbeat. Program the resulting .bit onto the board.
# ----------------------------------------------------------------------------
if {$argc < 1} { error "usage: -tclargs <part> \[<testcase>\]" }
set part [lindex $argv 0]
set tc   [expr {$argc > 1 ? [lindex $argv 1] : "sobel_x"}]

set root  [file normalize [file join [file dirname [info script]] ../..]]
set bdir  [file dirname [info script]]
set tdir  $root/sim/tests/$tc
set out   $bdir/build
file mkdir $out

# $readmemh resolves relative to the run directory, so stage the chosen
# vectors as img/kernel/expected.hex right where synthesis runs.
foreach f {img kernel expected} {
    file copy -force $tdir/$f.hex $out/$f.hex
}
cd $out

create_project -in_memory -part $part

read_verilog [glob $root/rtl/*.v]
read_verilog $root/rtl/selftest/selftest_top.v
read_verilog $bdir/board_top.v
read_xdc     $bdir/board.xdc

synth_design -top board_top -part $part
opt_design
place_design
phys_opt_design
route_design

report_utilization    -file $out/util.rpt
report_timing_summary -file $out/timing.rpt
report_drc            -file $out/drc.rpt

write_bitstream -force $out/hyperconv_selftest.bit
puts "BITSTREAM: wrote $out/hyperconv_selftest.bit  (testcase=$tc part=$part)"
