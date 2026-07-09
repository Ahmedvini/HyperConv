# ----------------------------------------------------------------------------
# HyperConv - create_project.tcl
# Creates a persistent, GUI-friendly Vivado PROJECT for conv_top so that
# synthesis/implementation runs are saved to disk and can be driven from the
# Flow Navigator (unlike synth/build.tcl, which is an in-memory script flow).
#
# Run once from the Vivado Tcl Console (works in the GUI, same window):
#   cd /home/ahmedelsheikh/Documents/GitHub/HyperConv/synth
#   source create_project.tcl
#
# Then in the Flow Navigator click "Run Synthesis", then "Run Implementation".
# Reports/checkpoints persist under vivado_ooc/conv_top_ooc.runs/.
#
# Synthesis is out-of-context (the accelerator is a core with no board pins),
# so no I/O placement / package-pin constraints are needed. The clock and I/O
# delay budget come from synth/ooc.xdc.
# ----------------------------------------------------------------------------
set root     [file normalize [file join [file dirname [info script]] ..]]
set proj_dir $root/vivado_ooc

# close whatever is currently open in this window (sim project, checkpoint, ...)
catch { close_sim -force -quiet }
catch { close_project -quiet }

create_project conv_top_ooc $proj_dir -part xczu7ev-ffvc1156-2-e -force

add_files -norecurse [glob $root/rtl/*.v]
add_files -fileset constrs_1 -norecurse $root/synth/ooc.xdc

set_property top conv_top [current_fileset]
update_compile_order -fileset sources_1

# out-of-context synthesis: build the core with no top-level I/O buffers
# (whole-design OOC is passed to synth_design via the run's extra options)
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} \
             -value {-mode out_of_context} -objects [get_runs synth_1]

puts "----------------------------------------------------------------"
puts "Project 'conv_top_ooc' ready (part xczu7ev-ffvc1156-2-e, OOC)."
puts "Flow Navigator -> Run Synthesis, then Run Implementation."
puts "To reproduce the report numbers non-interactively, use build.tcl."
puts "----------------------------------------------------------------"
