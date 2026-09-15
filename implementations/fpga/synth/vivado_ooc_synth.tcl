# VestaRV: out-of-context Vivado synthesis of the fpga_default bring-up cut.
#
# No board, no pin assignment and no bitstream: the point is to put the RTL
# through a real synthesizer and read back the clock-resource report, which is
# the one number hdl/fpga/'s stand-in cells exist to control. GHDL says the file
# set binds; this says Vivado can build it and how many of the 32 BUFGCTRL sites
# it wants.
#
# Run from the REPO ROOT, after the file list is built:
#
#   tools/bin/bazel build //opensource_sim/fpga_default:fpga_default_vivado_files
#   vivado -mode batch -nojournal -nolog \
#       -source implementations/fpga/synth/vivado_ooc_synth.tcl
#
# Every path in the manifest is exec-root relative, which is workspace-root
# relative once bazel-out resolves, so the working directory has to be the repo
# root and nowhere else.
#
# Knobs, all overridable with -tclargs name=value:
#   part     the device. Default is the Artix-7 the clock budget is written
#            against: 32 BUFGCTRL, 6 clock regions.
#   files    the manifest produced by //opensource_sim/fpga_default:fpga_default_vivado_files.
#   xdc      the constraints. fpga_default_ooc.xdc is the template in this directory.
#   outdir   where the reports and the post-synthesis checkpoint land.
#   romimage the boot ROM image. MCU has NO generics, and Vivado's -generic
#            reaches the top entity only, so the image cannot be passed down to
#            rom2k_hvt_pg from here: this script copies it to rom.rcf in the
#            working directory, which is that generic's default.

set part     "xc7a100tcsg324-1"
set files    "bazel-bin/opensource_sim/fpga_default/fpga_default_vivado_files.f"
set xdc      "implementations/fpga/synth/fpga_default_ooc.xdc"
set outdir   "build/fpga_default_ooc"
set romimage "software/bootrom_mp/bin/rom.rcf"

foreach arg $argv {
	if {[regexp {^([a-z]+)=(.*)$} $arg -> key value]} {
		if {[info exists $key]} {
			set $key $value
		} else {
			puts "vivado_ooc_synth.tcl: unknown knob '$key'"
			exit 1
		}
	}
}

if {![file exists $files]} {
	puts "vivado_ooc_synth.tcl: no file list at $files."
	puts "  tools/bin/bazel build //opensource_sim/fpga_default:fpga_default_vivado_files"
	exit 1
}

file mkdir $outdir

# The manifest is the analysis order and it is load bearing: `entity work.x`
# binds at analysis, hdl/common/sim/ and hdl/fpga/ declare the same entities,
# and a tool handed both binds whichever architecture it read last. Do not sort
# this list, do not glob for it, and do not add hdl/common/sim/ to it.
set fh [open $files r]
set srcs [split [string trim [read $fh]] "\n"]
close $fh

set missing {}
foreach f $srcs {
	if {![file exists $f]} {
		lappend missing $f
	}
}
if {[llength $missing] > 0} {
	puts "vivado_ooc_synth.tcl: [llength $missing] file(s) in the manifest do not exist relative to [pwd]:"
	foreach f $missing { puts "  $f" }
	puts "  Run from the repo root, with bazel-out resolved."
	exit 1
}

puts "vivado_ooc_synth.tcl: [llength $srcs] VHDL files, part $part, top MCU"

# The tree is --std=08 throughout. Vivado's VHDL-2008 support is a subset; a
# failure here is a Vivado gap and not an RTL defect, and the GHDL gate
# //opensource_sim/fpga_default:fpga_default_elaborate is what says so.
read_vhdl -vhdl2008 -library work $srcs

if {[file exists $xdc]} {
	read_xdc -mode out_of_context $xdc
} else {
	puts "vivado_ooc_synth.tcl: no constraints at $xdc, synthesizing unconstrained"
}

# The boot ROM image, under the name hdl/fpga/ARM_IP_ROM.vhd's InitFile generic
# defaults to. Without it the array is all zeros and synthesis warns rather than
# failing, which is what a core that fetches nothing but zeros looks like on a
# board.
if {[file exists $romimage]} {
	file copy -force $romimage "rom.rcf"
} else {
	puts "vivado_ooc_synth.tcl: no boot ROM image at $romimage, the ROM will synthesize as all zeros"
}

# -mode out_of_context: no I/O buffers are inserted, so the design needs no pin
# assignment and no board. The clock buffers hdl/fpga/ instantiates ARE still
# built, which is the whole reason for the run.
synth_design -top MCU -part $part -mode out_of_context

write_checkpoint -force $outdir/post_synth.dcp

report_utilization          -file $outdir/utilization.rpt
report_clock_utilization    -file $outdir/clock_utilization.rpt
report_clock_networks       -file $outdir/clock_networks.rpt
report_clock_interaction    -file $outdir/clock_interaction.rpt
report_high_fanout_nets     -file $outdir/high_fanout.rpt
report_drc -ruledecks {default} -file $outdir/drc.rpt

# The census this run exists to produce: how many global clock buffers the
# design asked for, against the 32 BUFGCTRL sites on the default part.
set bufg [llength [get_cells -hierarchical -quiet -filter {REF_NAME =~ BUFG*}]]
set mmcm [llength [get_cells -hierarchical -quiet -filter {REF_NAME =~ MMCM*}]]
puts "vivado_ooc_synth.tcl: BUFG-class primitives = $bufg, MMCM = $mmcm"
puts "vivado_ooc_synth.tcl: reports under $outdir"
