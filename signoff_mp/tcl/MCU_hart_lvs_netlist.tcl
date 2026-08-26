# MCU_hart (2026-08-24): the MCU_hart LVS netlist WITH power/ground, plus the
# same-session virtual-connect labels and the short sentinels.
#
# A7 FRESH-INIT + defIn pattern.  Never restoreDesign a signoff DB and never
# patch its .mode: that is the standing G0/A7 rule, and it has a second reason
# here.  The .dat databases EMBED THEIR OWN LEF COPIES, so a restoreDesign
# carries stale macro views; rom2k_hvt_pg is a brand-new macro, and a stale
# view of it would be invisible and wrong.  Fresh init reads today's LEF.
#
# CLONE of tcl/MCU_castalia_penta_lvs_netlist.tcl.  DELTAS, all deliberate:
#   1. Design/cell/lib names -> MCU_hart / topcell MCU; mmmc ->
#      ../innovus/common/MCU_hart/tcl/viewdefinition_MCU_hart.tcl.
#   2. NO pad LEF and no pad instances: this is a BLOCK assembly.
#   3. ONE hardened tile, instance `hart0`, at the TOP level (not under an mcu0
#      chip wrapper).  So the label text is VDD_SW_H0 and the matching cpoint in
#      pvs/lvs_MCU_hart_ctl is `Xhart0/VDD_SW`.  Keep the two in sync: a
#      name/index skew silently produces a phantom VDD_SW MISMATCH.
#   4. rom2k_hvt_pg joins the LEF list.  Its LVS consequence lives in
#      signoff_mp/lvs_include_hart, not here.
#   5. THE SENTINELS ARE DERIVED, NOT HARD CODED.  The penta file hard-codes two
#      coordinates and then verifies them.  MCU_hart's floorplan is derived at
#      P&R time from the staged config's macro inventory, so there are no
#      coordinates to hard-code -- this file SEARCHES the DB for an adjacent
#      M1 VDD / M1 VSS follow-pin rail pair and writes a text on each.  It
#      FATALs if it cannot find one.  Sentinels are what make FIND_SHORTS
#      short-sensitive at all: in Stage J a REAL PDB3A VDD-VSS ring short
#      produced an EMPTY shorts file without them, and an empty shorts file
#      with no conflicting texts proves exactly nothing.
#
# Run: cd ~/vestarv/innovus/common/MCU_hart && innovus -no_gui -batch \
#        -log log/MCU_hart_lvs_regen \
#        -files ../../../signoff_mp/tcl/MCU_hart_lvs_netlist.tcl
# Normally invoked through signoff_mp/gen_MCU_hart_lvs_collateral.sh.

source ../shared/constants.tcl
source ../shared/procedures.tcl

set BASE          MCU_hart
set DESIGN_NAME   MCU
set PVS_DIR       /home/mseminario2/vestarv/signoff_mp/pvs
set CUTSEL  [expr {[info exists ::env(CUTSEL)]  ? $::env(CUTSEL)  : "signoff"}]
set XSIMSEL [expr {[info exists ::env(XSIMSEL)] ? $::env(XSIMSEL) : ""}]
if {$XSIMSEL eq ""} {
	set XSIM_REF "$OUTPUT_DIR/${BASE}.xsim.v"
} else {
	set XSIM_REF "$OUTPUT_DIR/${BASE}.${XSIMSEL}.xsim.v"
}
set NETLIST_OUT   "$PVS_DIR/${BASE}.lvs.v"
set LABELS_OUT    "$PVS_DIR/${BASE}.lvslabels"
set TILE_LABELS   "$PVS_DIR/hart_tile.lvslabels"
set TILE_INST     hart0

# ---- cut of record ----------------------------------------------------------
set CUTDB "${BASE}.${CUTSEL}"
if {![file isdirectory "$DATABASE_DIR/${CUTDB}.innovus.dat"]} {
	puts "HARTREGEN: FATAL: no $DATABASE_DIR/${CUTDB}.innovus.dat -- re-run P&R (or set CUTSEL)"
	exit 1
}
set CUT_DEF "$DATABASE_DIR/${CUTDB}.innovus.dat/${DESIGN_NAME}.def.gz"
if {![file exists $CUT_DEF]} {
	# saveDesign names the DEF after the DESIGN, which here is MCU, not MCU_hart.
	# Fall back to whatever single .def.gz the DB holds rather than guessing.
	set __cands [glob -nocomplain "$DATABASE_DIR/${CUTDB}.innovus.dat/*.def.gz"]
	if {[llength $__cands] == 1} {
		set CUT_DEF [lindex $__cands 0]
	} else {
		puts "HARTREGEN: FATAL: cannot identify the DEF in $DATABASE_DIR/${CUTDB}.innovus.dat"
		puts "HARTREGEN:        candidates: $__cands"
		exit 1
	}
}
puts "HARTREGEN: cut of record = $CUTDB"
puts "HARTREGEN: DEF           = $CUT_DEF"

proc __wnd_distinct {file pat} {
	if {![file exists $file]} { return -1 }
	set cmd [format {grep -oE '%s' "%s" | sort -u | wc -l} $pat $file]
	if {[catch {exec sh -c $cmd} out]} { return -1 }
	return [string trim $out]
}
set FE_PAT  {FE_OFN[A-Za-z0-9_]*}
set CTS_PAT {CTS_[A-Za-z0-9_]*}

if {![file exists $XSIM_REF]} {
	puts "HARTREGEN: FATAL: reference netlist $XSIM_REF missing (the P&R run writes it)"
	exit 1
}

set init_verilog   $XSIM_REF
set init_top_cell  $DESIGN_NAME
set init_pwr_net   VDD
set init_gnd_net   VSS
set init_mmmc_file "$SCRIPT_DIR/viewdefinition_MCU_hart.tcl"
set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom2k_hvt_pg/rom2k_hvt_pg.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					../hart_tile/out/hart_tile.lef"
set init_design_uniquify 1
init_design
setDesignMode -process 65 -flowEffort standard -powerEffort low
setMultiCpuUsage -localCpu 4

defIn $CUT_DEF
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose
# THE SPLIT RAILS.  This is a FRESH-INIT + defIn session, so the DB's own
# globalNetConnect rules are NOT inherited: whatever is declared here is the
# whole of what saveNetlist -includePowerGround can emit.  Omitting these three
# on the penta flow made an 8 KiB TCM come out of saveNetlist with NO power pins
# at all (IMPVL-520 on VDDPE/VDDCE/VSSE), i.e. LVS was handed a source netlist
# in which the very thing it was run to check was invisible.  Keep in sync with
# ../innovus/common/MCU_hart/tcl/MCU_hart.innovus.tcl.
globalNetConnect VDD -type pgpin -pin VDDPE -inst * -module {} -autoTie -verbose
globalNetConnect VDD -type pgpin -pin VDDCE -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSSE  -inst * -module {} -autoTie -verbose
puts "HARTREGEN: init+defIn+gnc done; instCount=[llength [dbGet top.insts.name]]"

# Block assembly: no pad instances, so -phys keeps nothing but would be
# harmless.  It is DROPPED here on purpose so the netlist contains exactly the
# logical instances plus the PG, and any physical-only cell that shows up is a
# surprise worth seeing rather than one that quietly rides along.
saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH" \
    $NETLIST_OUT
puts "HARTREGEN: saveNetlist done -> $NETLIST_OUT"

# --- A7 SANITY GATE ----------------------------------------------------------
set fe_ref [__wnd_distinct $XSIM_REF    $FE_PAT]
set fe_new [__wnd_distinct $NETLIST_OUT $FE_PAT]
set ct_ref [__wnd_distinct $XSIM_REF    $CTS_PAT]
set ct_new [__wnd_distinct $NETLIST_OUT $CTS_PAT]
puts "HARTREGEN: distinct FE_OFN  ref=$fe_ref  new=$fe_new"
puts "HARTREGEN: distinct CTS_    ref=$ct_ref  new=$ct_new"
if {$fe_ref <= 0 || $ct_ref <= 0} {
	file delete -force $NETLIST_OUT
	puts "HARTREGEN: FATAL: could not count reference names in $XSIM_REF (ref=$fe_ref/$ct_ref)"
	exit 1
}
if {$fe_ref ne $fe_new || $ct_ref ne $ct_new} {
	file delete -force $NETLIST_OUT
	puts "HARTREGEN: FATAL: FE_OFN/CTS_ counts differ from $XSIM_REF --"
	puts "HARTREGEN:        the saved netlist is NOT this cut (the A7 stale-netlist tell)."
	puts "HARTREGEN:        $NETLIST_OUT deleted so nothing downstream can eat it."
	exit 1
}
puts "HARTREGEN: A7 sanity gate PASS (FE_OFN + CTS_ exact)"

# --- VDD_SW labels for the one hardened tile, SAME SESSION (G0) -------------
proc __wnd_xform {orient x1 y1 W H x y} {
	switch -- $orient {
		R0   { return [list [expr {$x1 + $x}]       [expr {$y1 + $y}]] }
		MX   { return [list [expr {$x1 + $x}]       [expr {$y1 + ($H - $y)}]] }
		MY   { return [list [expr {$x1 + ($W - $x)}] [expr {$y1 + $y}]] }
		R180 { return [list [expr {$x1 + ($W - $x)}] [expr {$y1 + ($H - $y)}]] }
	}
	return {}
}

if {![file exists $TILE_LABELS]} {
	puts "HARTREGEN: FATAL: $TILE_LABELS missing -- dump it with tcl/hart_tile_lvs_netlist.tcl"
	exit 1
}
if {[file mtime $TILE_LABELS] < [file mtime ../hart_tile/out/hart_tile.gds2]} {
	puts "HARTREGEN: FATAL: $TILE_LABELS is older than ../hart_tile/out/hart_tile.gds2 --"
	puts "HARTREGEN:        re-dump the tile labels (tcl/hart_tile_lvs_netlist.tcl) first."
	exit 1
}

set nsent_skipped 0
set pts {}
set fh [open $TILE_LABELS r]
while {[gets $fh ln] >= 0} {
	set p [split [string trim $ln]]
	set p [lsearch -all -inline -not -exact $p {}]
	if {[llength $p] >= 4} {
		set __txt [string trimright [lindex $p 3] ":"]
		if {$__txt eq "VDD" || $__txt eq "VSS"} {
			# 2026-08-25 SENTINEL CARRY.  The TILE label dump grew its own VDD:/VSS:
			# short-sentinel texts on 2026-08-24 (tcl/hart_tile_lvs_netlist.tcl).
			# Those two are the tile's OWN conflicting-text pair and must not be
			# aliased per hart here.  A "VSS_H1:" text sitting on real VSS geometry
			# is a spurious VSS_H1-vs-VSS short, one per sentinel per hart -- eight
			# of them on the penta.  This dump writes its own top-level sentinels
			# further down, so the tile's are dropped rather than carried.
			incr nsent_skipped
			continue
		}
		lappend pts [list [lindex $p 0] [lindex $p 1] [lindex $p 2] [lindex $p 3]]
	}
}
close $fh
puts "HARTREGEN: tile label pieces read: [llength $pts]"
puts "HARTREGEN: tile short sentinels dropped (not aliased per hart): $nsent_skipped"
if {[llength $pts] == 0} {
	puts "HARTREGEN: FATAL: $TILE_LABELS has no usable label lines"
	exit 1
}

set ip [dbGet top.insts.name $TILE_INST -p -e]
if {$ip eq "" || $ip eq "0x0"} {
	puts "HARTREGEN: FATAL: no instance $TILE_INST in the MCU_hart DB"
	exit 1
}
set box [join [dbGet ${ip}.box]]
set x1 [lindex $box 0]; set y1 [lindex $box 1]
set x2 [lindex $box 2]; set y2 [lindex $box 3]
set W  [expr {$x2 - $x1}]
set H  [expr {$y2 - $y1}]
set orient [dbGet ${ip}.orient]
puts "HARTREGEN: $TILE_INST  orient=$orient  box=($x1,$y1)-($x2,$y2)  W=$W H=$H"

# THE PIECE TEXTS ARE FORCED ONTO metal1_text, NOT COPIED FROM THE TILE FILE.
# The layer the tile dump chooses is the tile's business and it has moved once
# already: on 2026-08-25 at 18:04 the tile label file went from GDS layer 131 to
# GDS layer 231 (sidecar pvs/hart_tile.lvslabels.pre_nettext).
# GDS layer 231 has NO LAYER_MAP in /opt/design_kits/TSMC65-PDK/kit/PVS/LVS/pvs.lvs,
# so a text on it attaches to nothing and the piece names never exist.
# At tile level that is harmless and it is what took the tile to MATCH, because
# the tile's own VDD_SW extracts as one net with no help from the labels.
# At MCU_hart level it is not harmless, and the difference was MEASURED on this
# cut with the same netlist, the same GDS and only the layer changed:
#     texts on GDS 231 (unmapped)   unmatched nets   406 : 0
#     texts on GDS 131 (metal1_text) unmatched nets    1 : 0
# The 406 are the switched rail's own pieces, which is exactly the class
# signoff_mp/gds_add_labels.py was written for -- VDD_SW is many layout pieces
# joined only through the header switches, and one text per piece is what
# unifies them under VIRTUAL_CONNECT -COLON YES.
# The pieces are M1 follow-pin rail segments, so metal1_text is the layer that
# describes them, and pinning it here means a future tile-side layer change
# cannot silently fragment the parent again.
set VDDSW_TEXT_LAYER 131
set relayered 0

set fp [open $LABELS_OUT w]
set total 0
foreach pt $pts {
	set layer [lindex $pt 0]
	set lx    [lindex $pt 1]
	set ly    [lindex $pt 2]
	set text  [string trimright [lindex $pt 3] ":"]
	if {$layer ne $VDDSW_TEXT_LAYER} { incr relayered }
	set g [__wnd_xform $orient $x1 $y1 $W $H $lx $ly]
	if {[llength $g] != 2} {
		close $fp
		file delete -force $LABELS_OUT
		puts "HARTREGEN: FATAL: unsupported orient '$orient' on $TILE_INST"
		exit 1
	}
	puts $fp [format "%s %.3f %.3f %s_H0:" $VDDSW_TEXT_LAYER [lindex $g 0] [lindex $g 1] $text]
	incr total
}
puts "HARTREGEN: piece texts written on GDS layer $VDDSW_TEXT_LAYER (metal1_text); $relayered of $total came off another layer"

# --- SHORT SENTINELS, DERIVED FROM THIS DB ---------------------------------
# Find an M1 VDD follow-pin rail and an M1 VSS follow-pin rail that overlap in
# x, and put one text on each.  Adjacent rails are ~2 um apart, so if VDD and
# VSS are ever merged into one layout net the two conflicting texts land on the
# same net and FIND_SHORTS reports it.  Without them the shorts file is empty
# whether or not a short exists (Stage J: a real PDB3A ring short, invisible to
# Innovus, to the PG wrapper and to Calibre DRC, produced an empty shorts file).
proc __m1_rails {net} {
	set out {}
	set netp [dbGet -p top.nets.name $net]
	if {$netp eq "0x0" || $netp eq ""} { return {} }
	foreach w [dbGet $netp.sWires] {
		set lay ""
		catch { set lay [dbGet $w.layer.name] }
		if {$lay ne "M1"} { continue }
		set b {}
		catch { set b [dbGet $w.box] }
		if {[llength $b] == 1} { set b [lindex $b 0] }
		if {[llength $b] != 4} { continue }
		lassign $b bx1 by1 bx2 by2
		# Follow-pin rails are long and thin; skip anything that is not.
		if {($bx2 - $bx1) < 20.0} { continue }
		lappend out [list $bx1 $by1 $bx2 $by2]
	}
	return $out
}

set VDD_RAILS [__m1_rails VDD]
set VSS_RAILS [__m1_rails VSS]
puts "HARTREGEN: M1 follow-pin rail candidates -- VDD [llength $VDD_RAILS] , VSS [llength $VSS_RAILS]"

set SENT_VDD {}
set SENT_VSS {}
set BEST_DY  1e9
foreach v $VDD_RAILS {
	lassign $v vx1 vy1 vx2 vy2
	set vyc [expr {($vy1 + $vy2) / 2.0}]
	foreach g $VSS_RAILS {
		lassign $g gx1 gy1 gx2 gy2
		set ox1 [expr {$vx1 > $gx1 ? $vx1 : $gx1}]
		set ox2 [expr {$vx2 < $gx2 ? $vx2 : $gx2}]
		if {($ox2 - $ox1) < 10.0} { continue }
		set gyc [expr {($gy1 + $gy2) / 2.0}]
		set dy [expr {abs($gyc - $vyc)}]
		if {$dy < 0.5} { continue }
		if {$dy < $BEST_DY} {
			set BEST_DY $dy
			set xc [expr {($ox1 + $ox2) / 2.0}]
			set SENT_VDD [list $xc $vyc]
			set SENT_VSS [list $xc $gyc]
		}
	}
}
if {[llength $SENT_VDD] != 2 || [llength $SENT_VSS] != 2} {
	close $fp
	file delete -force $LABELS_OUT
	puts "HARTREGEN: FATAL: could not find an adjacent M1 VDD / M1 VSS follow-pin rail pair."
	puts "HARTREGEN:        Writing no sentinels would leave FIND_SHORTS TEXT-BLIND, and an"
	puts "HARTREGEN:        empty shorts file would then prove nothing at all (Stage J)."
	puts "HARTREGEN:        Check that addFiller / the follow-pin rails actually exist in this cut."
	exit 1
}
lassign $SENT_VDD SVX SVY
lassign $SENT_VSS SGX SGY
puts "HARTREGEN: sentinels -- VDD@([format %.3f $SVX],[format %.3f $SVY]) VSS@([format %.3f $SGX],[format %.3f $SGY]) dy=[format %.3f $BEST_DY]"
puts $fp [format "131 %.3f %.3f VDD:" $SVX $SVY]
puts $fp [format "131 %.3f %.3f VSS:" $SGX $SGY]
incr total 2
close $fp
puts "HARTREGEN: wrote $total labels (incl. 2 VDD/VSS short-sentinel texts) -> $LABELS_OUT"
puts "HARTREGEN: DONE (netlist + same-cut labels).  Now run gen_MCU_hart_lvs_collateral.sh"
puts "HARTREGEN:      for the tile-netlist concatenation."
exit
