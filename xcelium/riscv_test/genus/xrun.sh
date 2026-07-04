#!/bin/bash

# Synthesizes the vhdl design

# Flag quick reference
#
# -messages         Prints summary messages for each handled file.
# -nocopyright      Prevents copyright boilerplate from being output.
# -v93              Enables use of VHDL 1993 standard.  This is fully supported.
# -v200x			Enables VHDL 200x revisions
# -work             Specifiy the work library logical name
# -controlrelax     Accept nonstandard coding methods.
#       nlstex      Allows nonstatic array aggregates. (others=>"0000")
# -linedebug        Allows simvision to set breakpoints line by line.
# -access rwc       Allows simvision to debug elaboration output.
# -gui              Debug simulation in simvision.
# -simvisionargs    Enables addition simvision arguments to be passed to xcellium
#       -waves      Open the wave window on simvision startup.
#       -timeunits  Change the defult unit of time in simvision.

CDS_PATH="."
LOG_PATH="log"
RESTORE_PATH="."
HDL_DIR="../../../hdl"
HDL_MCU_DIR="${HDL_DIR}/MCU"
INNOVUS_DIR="../../../innovus"
GENUS_DIR="../../../genus"
IP_DIR="../../../ip"
LIB_PATH="xcelium.d"

# Clean up the library directory.  This prevents different simulations from 
# corrupting one another.
[ -d $LIB_PATH ] && rm -r $LIB_PATH
#mkdir -p $LIB_PATH
mkdir -p $LOG_PATH

hdlFiles="$(< ./cell_list_genus.txt)"

# Run the uber command, which replaces the three-step legacy process.
xrun \
	-top riscv_tb \
	-sdf_cmd_file MCU.sdfcmd \
	-sdfstats $LOG_PATH/sdf_stats.log \
	-sdf_verbose \
	-v200x \
	-work work \
	-gui \
	-access +r \
	-controlrelax nlstex \
	-relax \
	-input $RESTORE_PATH/restore.tcl \
	-input ../../disable_x_warnings.tcl \
	$hdlFiles \
	$HDL_MCU_DIR/tb/riscv_tb.vhd

