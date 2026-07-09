# ----------------------------------------------------------------------------
# HyperConv - create_project.tcl
# Creates ONE persistent, GUI-friendly Vivado project that does everything:
#   * Run Simulation      (behavioral, testbench tb_conv_top, sobel_x vectors)
#   * Run Synthesis       (out-of-context)
#   * Run Implementation  (place & route, reports)
# so it is all driven from the Flow Navigator in a single window, and runs
# persist on disk.
#
# Run once from the Vivado Tcl Console (works in the GUI, same window):
#   cd /home/ahmedelsheikh/Documents/GitHub/HyperConv/synth
#   source create_project.tcl
#
# Synthesis is out-of-context (the accelerator is a core with no board pins),
# so no I/O placement / package-pin constraints are needed. The clock and I/O
# delay budget come from synth/ooc.xdc.
# ----------------------------------------------------------------------------

# xsim's bundled gcc can't find the system C runtime (crt1.o) on Ubuntu unless
# LIBRARY_PATH points at the multiarch dir -- without this 'Run Simulation'
# fails with 'XSIM 43-3238 Failed to link the design'. Set it for this session.
set ::env(LIBRARY_PATH) "/usr/lib/x86_64-linux-gnu"

set root     [file normalize [file join [file dirname [info script]] ..]]
set proj_dir $root/vivado_ooc

# close whatever is currently open in this window (sim project, checkpoint, ...)
catch { close_sim -force -quiet }
catch { close_project -quiet }

create_project conv_top_ooc $proj_dir -part xczu7ev-ffvc1156-2-e -force

# ---- design sources + constraints ----
add_files -norecurse [glob $root/rtl/*.v]
add_files -fileset constrs_1 -norecurse $root/synth/ooc.xdc
set_property top conv_top [current_fileset]
update_compile_order -fileset sources_1

# out-of-context synthesis: build the core with no top-level I/O buffers
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} \
             -value {-mode out_of_context} -objects [get_runs synth_1]

# ---- simulation: testbench + default stimulus (sobel_x edge-detection) ----
add_files -fileset sim_1 -norecurse $root/tb/tb_conv_top.v
set_property top tb_conv_top [get_filesets sim_1]
set_property generic {N=3 IMG_W=32 IMG_H=32 KSEL=3} [get_filesets sim_1]
set T $root/sim/tests/sobel_x
set_property -name {xsim.simulate.xsim.more_options} \
    -value "-testplusarg IMG=$T/img.hex -testplusarg KER=$T/kernel.hex -testplusarg EXP=$T/expected.hex" \
    -objects [get_filesets sim_1]
# pause at time 0 so signals can be added before running
set_property -name {xsim.simulate.runtime} -value {0ns} -objects [get_filesets sim_1]
update_compile_order -fileset sim_1

puts "----------------------------------------------------------------"
puts "Project 'conv_top_ooc' ready (part xczu7ev-ffvc1156-2-e, OOC)."
puts "  Flow Navigator -> Run Simulation      (waveforms; sobel_x by default)"
puts "  Flow Navigator -> Run Synthesis, then Run Implementation (reports)"
puts "In the sim wave window:  source ../sim/wave_setup.tcl ; run all"
puts "----------------------------------------------------------------"
