# G2 chip patch pass 1 (2026-07-23): chip_top_dp core-metal onesies.
# chipdrc core residual (fresh interior cut — the G1 assembly fixes do NOT
# propagate): G.4:M2i x4 @ (798.55, 484.61-484.79) = the assembly's 1049
# jog pattern shifted; M2.S.1 @ (1013.805,482.465-482.5) = the assembly's
# exact pair-gap site recreated; M2.S.1 x3 @ y 486.50-486.525 (x 1049.5 /
# 1056.7 / 1063.8) = collinear stub gaps. ALL additive same-net merges (no
# rips, no ecoRoute -> timing/netlist/SDF untouched). Nets resolved at
# runtime; __mrg FATALs on any foreign-net blocker (then this pass iterates).
# NO saveDesign; streamOut trial out/chip_top_dp.g2p1.gds2.
#
# Run: cd ~/vestarv/innovus/common/chip_top_dp && innovus -no_gui -batch \
#        -log log/chip_top_dp_g2p1 -files ../../../signoff_mp/tcl/chip_top_dp_g2_patch1.tcl

source ../shared/constants.tcl
source ../shared/procedures.tcl

set IO_PAD_LEF /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef
set init_verilog   "$OUTPUT_DIR/chip_top_dp.xsim.v"
set init_top_cell  chip_top_dp
set init_pwr_net   VDD
set init_gnd_net   VSS
set init_mmmc_file "$SCRIPT_DIR/viewdefinition_chip_dp.tcl"
set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					$OUTPUT_DIR/hart_tile.lef \
					$IO_PAD_LEF"
set init_design_uniquify 1
init_design
setDesignMode -process 65 -flowEffort standard -powerEffort low
setMultiCpuUsage -localCpu 4

defIn $DATABASE_DIR/chip_top_dp.signoff.innovus.dat/chip_top_dp.def.gz
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose

proc __counts {} {
	set ni [llength [dbGet -e top.insts]]
	set ns [llength [dbGet -e top.nets.sWires]]
	set nw [llength [dbGet -e top.nets.wires]]
	return [list $ni $ns $nw]
}
proc __fatal {msg} { puts "G2P1 FATAL: $msg"; exit 1 }
foreach {__ni0 __ns0 __nw0} [__counts] {}
puts "G2P1 COUNTS baseline: insts=$__ni0 sWires=$__ns0 wires=$__nw0"
set __fatals 0

proc __mrg {tag net lay rect} {
	global __fatals
	foreach {x0 y0 x1 y1} $rect {}
	set chk [list [expr {$x0-0.16}] [expr {$y0-0.16}] [expr {$x1+0.16}] [expr {$y1+0.16}]]
	foreach o [concat [dbQuery -area $chk -objType wire] [dbQuery -area $chk -objType sWire]] {
		if {[dbGet -e $o.layer.name] ne $lay} { continue }
		if {[lindex [dbGet -e $o.net.name] 0] eq $net} { continue }
		set ob [lindex [dbGet $o.box] 0]
		foreach {ox0 oy0 ox1 oy1} $ob {}
		set dx [expr {max($x0-$ox1, $ox0-$x1)}]
		set dy [expr {max($y0-$oy1, $oy0-$y1)}]
		if {$dx < 0.0999 && $dy < 0.0999} {
			puts "G2P1 FATAL: $tag foreign $lay net=[dbGet -e $o.net.name] at $ob blocks rect $rect"
			incr __fatals
			return
		}
	}
	add_shape -net $net -layer $lay -rect $rect -shape STRIPE -status ROUTED
	puts "G2P1: $tag merged rect $rect on $net/$lay"
}
# net at window: wires, then via pads (PG4 landing-pad lesson)
proc __netat2 {lay win} {
	foreach o [concat [dbQuery -area $win -objType wire] [dbQuery -area $win -objType sWire]] {
		if {[dbGet -e $o.layer.name] ne $lay} { continue }
		set n [lindex [dbGet -e $o.net.name] 0]
		if {$n ne "" && $n ne "VDD" && $n ne "VSS"} { return $n }
	}
	foreach o [dbQuery -area $win -objType via] {
		if {[dbGet -e $o.via.botLayer.name] ne $lay && [dbGet -e $o.via.topLayer.name] ne $lay} { continue }
		set n [lindex [dbGet -e $o.net.name] 0]
		if {$n ne "" && $n ne "VDD" && $n ne "VSS"} { return $n }
	}
	return ""
}
proc __site {tag win rect} {
	global __fatals
	# dump first (forensics if the merge fatals)
	foreach kind {wire sWire via} {
		foreach o [dbQuery -area $win -objType $kind] {
			if {$kind eq "via"} {
				puts "G2P1 DUMP $tag via [dbGet -e $o.via.botLayer.name]->[dbGet -e $o.via.topLayer.name] net=[dbGet -e $o.net.name]"
			} else {
				puts "G2P1 DUMP $tag $kind lay=[dbGet -e $o.layer.name] net=[dbGet -e $o.net.name] box=[dbGet -e $o.box]"
			}
		}
	}
	set n [__netat2 M2 $win]
	if {$n eq ""} { __fatal "$tag: no M2 signal net in $win" }
	__mrg $tag $n M2 $rect
}

__site "G.4@798"      {798.3 484.3 799.0 485.1}   {798.45 484.5 798.635 484.79}
__site "M2.S.1@1013"  {1013.6 482.2 1014.1 482.8} {1013.805 482.36 1013.905 482.6}
__site "M2.S.1@1049b" {1049.3 486.2 1049.9 486.9} {1049.535 486.4 1049.635 486.63}
__site "M2.S.1@1056"  {1056.4 486.2 1057.0 486.9} {1056.65 486.4 1056.77 486.63}
__site "M2.S.1@1063"  {1063.6 486.2 1064.1 486.9} {1063.805 486.4 1063.905 486.63}

if {$__fatals > 0} { __fatal "$__fatals merge fatals — NO streamOut" }
foreach {__ni1 __ns1 __nw1} [__counts] {}
puts "G2P1 COUNTS post-patch: insts=$__ni1 sWires=$__ns1 wires=$__nw1"
if {$__ni1 != $__ni0} { __fatal "inst count changed" }
if {$__nw1 != $__nw0} { __fatal "regular wire count changed (additive-only pass)" }
if {[expr {$__ns1 - $__ns0}] > 10} { __fatal "sWire growth implausible" }

streamOut \
	$OUTPUT_DIR/chip_top_dp.g2p1.gds2 \
	-libName WorkLib \
	-structureName chip_top_dp \
	-stripes 1 \
	-units 1000 \
	-mode ALL \
	-merge [list $OUTPUT_DIR/hart_tile.gds2 /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/gds/tphn65gpgv2od3_sl_210a/mt_2/8lm/tphn65gpgv2od3_sl.gds] \
	-mapFile ../shared/innovus2gds.map
puts "G2P1: COMPLETE (trial GDS out/chip_top_dp.g2p1.gds2, no saveDesign)"
exit
