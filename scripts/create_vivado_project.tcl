# create_vivado_project.tcl - builds a Vivado project for the whole system in one step
#
# How to use (pick one):
#   In Vivado:  Tools > Run Tcl Script...  and choose this file
#   Or in a terminal:  vivado -mode batch -source scripts/create_vivado_project.tcl
#
# It creates the folder "vivado/" next to rtl/ and tb/, adds all the sources, sets soc_top as the
# design top and tb_soc as the simulation top. Then click Flow Navigator > Run Simulation >
# Run Behavioral Simulation. The simulation ends by itself when the testbench calls $finish.
#
# To run a different testbench: in the Sources window under Simulation Sources, right-click it
# (for example tb_pwm) and choose Set as Top, then run the simulation again.
#
# The chip is the one on the Nexys A7-100T (Artix-7 xc7a100tcsg324-1). No board is needed to simulate.
# Note: this script was written without access to Vivado. If a line fails, tell the author.

set script_dir [file dirname [file normalize [info script]]]
set root       [file normalize [file join $script_dir ..]]

create_project fpga_soc_sim [file join $root vivado] -part xc7a100tcsg324-1 -force

add_files -fileset sources_1 [glob [file join $root rtl *.v]]
add_files -fileset sim_1     [glob [file join $root tb *.v]]

set_property top soc_top [get_filesets sources_1]
set_property top tb_soc  [get_filesets sim_1]

# let the simulation run long enough for the whole test (the testbench stops it with $finish)
set_property -name {xsim.simulate.runtime} -value {500ms} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Project created. Next: Flow Navigator > Run Simulation > Run Behavioral Simulation."
