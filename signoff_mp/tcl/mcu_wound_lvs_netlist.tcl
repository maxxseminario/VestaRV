# Stage H / wound respin (staged 2026-07-26, NOTHING RUN YET): regenerate the
# MCU_WOUND (wound-patch SoC assembly, top cell "MCU") LVS netlist WITH
# power/ground from the wound cut, per the A7 re-P&R-invalidates-netlists rule,
# AND dump pvs/MCU_WOUND.lvslabels in the SAME SESSION (the G0 rule: the
# labels/netlist/GDS triple must come from ONE cut -- lvs.sh enforces it by mtime).
#
# Cloned from tcl/mcu_dp_lvs_netlist.tcl (Stage F2a). A7 FRESH-INIT pattern
# (a7/regen_lvs_netlist2.tcl), NOT the older mcu recipe's restoreDesign + .mode
# patch: init from the cut's OWN post-route netlist (out/MCU_WOUND.xsim.v, same
# save as the DEF) + the flow's exact LEF set, then defIn the signoff DEF -- no
# DB touched, no tapeOut-mode interaction at all (the assembly DB restoreDesign
# FATALs on the 3 timing-less analog macros).
#
# Deltas vs the DP original, all deliberate:
#   1. MCU_DP -> MCU_WOUND everywhere; viewdefinition_top_dp -> _top_wound.
#   2. The saveNetlist target is the ASSEMBLY-ONLY netlist pvs/MCU_WOUND.lvs.v.
#      The DP tcl on disk writes straight to pvs/MCU_DP_full.lvs.v, but that is
#      NOT how the accepted pvs/MCU_DP_full.lvs.v was actually made: the F2a
#      devlog (attempt 4) and the byte arithmetic both say _full = assembly
#      netlist + the FULL pvs/hart_tile.lvs.v appended (module hart_tile is the
#      last module in the file; a boxed tile stub aborts the compare at the 1M-net
#      matcher threshold). Running the DP tcl as it stands today would CLOBBER
#      pvs/MCU_DP_full.lvs.v with a tile-less netlist. The concatenation for the
#      wound blocks lives in gen_wound_lvs_collateral.sh (accept_chip.sh stage-2
#      pattern) -- keep the split.
#   3. HARD sanity gate (the A7 stale-netlist tell was a comment-only "should"
#      in the DP script): distinct FE_OFN* and CTS_* name counts in the saved
#      netlist must EQUAL those in out/MCU_WOUND.xsim.v. Mismatch => the netlist
#      is not this cut; the file is DELETED and the script exits 1 (a surviving
#      stale netlist that lvs.sh happily eats is the failure mode being closed).
#   4. Same-session lvslabels dump (new; the DP block relies on the shared
#      pvs/MCU.lvslabels, which is the CASTALIA/DP assembly's label set -- the
#      A6 cell-name trap. mcu_wound_LABELS is EXPLICIT in the signoff Makefile).
#      Placements are read from THIS DB, never from tcl constants (the A6 lesson
#      baked into gen_argus_lvslabels.py: legalization moves rows and hardcoded
#      coords mis-place every label).
#
# Run: cd ~/vestarv/innovus/common/MCU_WOUND && innovus -no_gui -batch \
#        -log log/mcu_wound_lvs_regen -files ../../../signoff_mp/tcl/mcu_wound_lvs_netlist.tcl
# (run dir = the BLOCK dir since the 2026-07-27 reorg, so dbs/ out/ log/ and
#  ../shared/constants.tcl resolve as in the flow)
# Normally invoked through ../../signoff_mp/gen_wound_lvs_collateral.sh block.

source ../shared/constants.tcl
source ../shared/procedures.tcl

set PVS_DIR       /home/mseminario2/vestarv/signoff_mp/pvs
set XSIM_REF      "$OUTPUT_DIR/MCU_WOUND.xsim.v"
set NETLIST_OUT   "$PVS_DIR/MCU_WOUND.lvs.v"
set LABELS_OUT    "$PVS_DIR/MCU_WOUND.lvslabels"
set TILE_LABELS   "$PVS_DIR/hart_tile.lvslabels"

# --------------------------------------------------------------------------
# helper: count DISTINCT tokens matching a regex in a file (A7 sanity gate).
# One `sh -c` child, so Tcl only sees sh's status (= wc's, always 0) even when
# grep finds nothing.  The pattern lives in braces so Tcl never substitutes the
# bracket expression.
# --------------------------------------------------------------------------
proc __wnd_distinct {file pat} {
    if {![file exists $file]} { return -1 }
    set cmd [format {grep -oE '%s' "%s" | sort -u | wc -l} $pat $file]
    if {[catch {exec sh -c $cmd} out]} { return -1 }
    return [string trim $out]
}

set FE_PAT  {FE_OFN[A-Za-z0-9_]*}
set CTS_PAT {CTS_[A-Za-z0-9_]*}

if {![file exists $XSIM_REF]} {
    puts "WOUNDREGEN: FATAL: reference netlist $XSIM_REF missing"
    exit 1
}

set init_verilog   $XSIM_REF
set init_top_cell  MCU
set init_pwr_net   VDD
set init_gnd_net   VSS
set init_mmmc_file "$SCRIPT_DIR/viewdefinition_top_wound.tcl"
set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					$OUTPUT_DIR/hart_tile.lef"
set init_design_uniquify 1
init_design
setDesignMode -process 65 -flowEffort standard -powerEffort low
setMultiCpuUsage -localCpu 4

defIn $DATABASE_DIR/MCU_WOUND.signoff.innovus.dat/MCU.def.gz
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose
puts "WOUNDREGEN: init+defIn+gnc done; instCount=[llength [dbGet top.insts.name]]"

# saveNetlist options per hart_tile_lvs_netlist.tcl rationale + the mcu
# recipe's FILLTIE additions (assembly-level fill set).
saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH" \
    $NETLIST_OUT
puts "WOUNDREGEN: saveNetlist done -> $NETLIST_OUT"

# --- A7 SANITY GATE: this netlist must be THIS cut ------------------------
set fe_ref [__wnd_distinct $XSIM_REF    $FE_PAT]
set fe_new [__wnd_distinct $NETLIST_OUT $FE_PAT]
set ct_ref [__wnd_distinct $XSIM_REF    $CTS_PAT]
set ct_new [__wnd_distinct $NETLIST_OUT $CTS_PAT]
puts "WOUNDREGEN: distinct FE_OFN  ref=$fe_ref  new=$fe_new"
puts "WOUNDREGEN: distinct CTS_    ref=$ct_ref  new=$ct_new"
if {$fe_ref <= 0 || $ct_ref <= 0} {
    file delete -force $NETLIST_OUT
    puts "WOUNDREGEN: FATAL: could not count reference names in $XSIM_REF (ref=$fe_ref/$ct_ref)"
    exit 1
}
if {$fe_ref ne $fe_new || $ct_ref ne $ct_new} {
    file delete -force $NETLIST_OUT
    puts "WOUNDREGEN: FATAL: FE_OFN/CTS_ counts differ from $XSIM_REF --"
    puts "WOUNDREGEN:        the saved netlist is NOT this cut (A7 stale-netlist tell)."
    puts "WOUNDREGEN:        $NETLIST_OUT deleted so nothing downstream can eat it."
    exit 1
}
puts "WOUNDREGEN: A7 sanity gate PASS (FE_OFN + CTS_ exact)"

# --- VDD_SW assembly labels, SAME SESSION (G0) ----------------------------
# VDD_SW is tile-INTERNAL (no LEF pin, absent from MCU_WOUND.lvs.v), so after
# Pegasus flattening each tile's switched rail is a SEPARATE schematic net ->
# each tile gets a DISTINCT text VDD_SW_H<h>; the binding is the
# `lvs_cpoint VDD_SW_H<h> Xhart<h>/VDD_SW` rules in pvs/lvs_mcu_ctl (keep the
# label names and the cpoint rules in sync).  Tile-local piece centres come
# from pvs/hart_tile.lvslabels (tile fPlan box is 0-based: x 40-620, y 5-1049).
# Placements come from THIS DB, not from tcl constants (A6 lesson).
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
    puts "WOUNDREGEN: FATAL: $TILE_LABELS missing -- dump it with tcl/hart_tile_lvs_netlist.tcl"
    exit 1
}
# G0/A7: the tile labels must belong to the SAME tile cut this assembly merged.
if {[file mtime $TILE_LABELS] < [file mtime $OUTPUT_DIR/hart_tile.gds2]} {
    puts "WOUNDREGEN: FATAL: $TILE_LABELS is older than $OUTPUT_DIR/hart_tile.gds2 --"
    puts "WOUNDREGEN:        re-dump the tile labels (tcl/hart_tile_lvs_netlist.tcl) first."
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
puts "WOUNDREGEN: tile label pieces read: [llength $pts]"
puts "WOUNDREGEN: tile short sentinels dropped (not aliased per hart): $nsent_skipped"

set fp [open $LABELS_OUT w]
set total 0
for {set h 0} {$h < 4} {incr h} {
    set ip [dbGet top.insts.name hart$h -p]
    if {$ip == 0} {
        close $fp
        file delete -force $LABELS_OUT
        puts "WOUNDREGEN: FATAL: no instance hart$h in the assembly DB"
        exit 1
    }
    set box [join [dbGet ${ip}.box]]
    set x1 [lindex $box 0]; set y1 [lindex $box 1]
    set x2 [lindex $box 2]; set y2 [lindex $box 3]
    set W  [expr {$x2 - $x1}]
    set H  [expr {$y2 - $y1}]
    set orient [dbGet ${ip}.orient]
    puts "WOUNDREGEN: hart$h  orient=$orient  box=($x1,$y1)-($x2,$y2)  W=$W H=$H"
    foreach pt $pts {
        set layer [lindex $pt 0]
        set lx    [lindex $pt 1]
        set ly    [lindex $pt 2]
        set text  [string trimright [lindex $pt 3] ":"]
        set g [__wnd_xform $orient $x1 $y1 $W $H $lx $ly]
        if {[llength $g] != 2} {
            close $fp
            file delete -force $LABELS_OUT
            puts "WOUNDREGEN: FATAL: unsupported orient '$orient' on hart$h"
            exit 1
        }
        puts $fp [format "%s %.3f %.3f %s_H%d:" $layer [lindex $g 0] [lindex $g 1] $text $h]
        incr total
    }
}
close $fp
puts "WOUNDREGEN: wrote $total labels ([llength $pts] per tile x 4) -> $LABELS_OUT"
puts "WOUNDREGEN: DONE (netlist + same-cut labels).  Now run gen_wound_lvs_collateral.sh"
puts "WOUNDREGEN:      to append pvs/hart_tile.lvs.v -> pvs/MCU_WOUND_full.lvs.v"
exit
