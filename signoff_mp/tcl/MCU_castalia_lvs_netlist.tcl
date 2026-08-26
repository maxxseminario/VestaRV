# Wound-QUAD chip (staged 2026-07-27, NOTHING RUN YET): MCU_castalia
# LVS netlist WITH power/ground -- A7 FRESH-INIT + defIn pattern (never
# restoreDesign a tape-out-mode chip DB, never patch .mode: the standing G0/A7
# rule).
# init_verilog MUST be the cut's own post-route netlist
# (out/MCU_castalia.xsim.v) -- the flow INPUT verilog lacks the chip-level
# opt/CTS instances that are in the DEF.
#
# Cloned from tcl/chip_top_wound_lvs_netlist.tcl (Stage I), which is itself the
# G2 tcl/chip_top_dp_lvs_netlist.tcl. Deltas, all deliberate:
#   0. QUAD ORIENTATIONS. This is the FIRST consumer of __wnd_xform that
#      actually exercises all four cases: the Stage-I wound/DP tile row is
#      R0/R0/MY/MY, but the quad corner tiles are 2-axis mirrored
#      (hart0 R0, hart1 MY, hart2 MX, hart3 R180). The proc below ALREADY
#      implements R0/MX/MY/R180 -- it was written that way in the Stage-I
#      clone; nothing had to be ported from signoff_mp/gen_quad_lvslabels.py.
#      PROVEN AT STAGING (2026-07-27): the proc extracted verbatim into stock
#      tclsh and driven with gen_quad_lvslabels.py's own tile constants
#      reproduces pvs/chip_top_quad.lvslabels BYTE-FOR-BYTE (1884 labels =
#      471 pieces x 4 tiles, all four orientations).
#      FINDING while doing that control: gen_quad_lvslabels.py's HARDCODED
#      placements (20,1638 / 2009,1638 / 20,1 / 2009,1) are 1 um off the CQ3a
#      as-built DEF (20,1639 / 2010,1639 / 20,1 / 2010,1) -- 1413 of the 1884
#      CQ6 chip labels are 1 um adrift. This tcl reads the placements from the
#      run's OWN DB, so it does not inherit that error (the A6 lesson: never
#      trust tcl constants for placements, legalisation moves things).
#   1. chip_top_wound -> MCU_castalia; viewdefinition_chip_wound ->
#      _chip_wound_quad. LEF set is byte-identical to the wound/DP chips'
#      (verified against tcl/MCU_castalia.innovus.tcl: same 8 entries
#      incl. the same tphn65gpgv2od3_sl_8lm IO_PAD_LEF path).
#   2. saveNetlist target is the CHIP-ONLY netlist pvs/MCU_castalia.lvs.v.
#      The DP tcl on disk writes straight to pvs/chip_top_dp_full.lvs.v, but the
#      accepted pvs/chip_top_dp_full.lvs.v is chip + pad-patch + the FULL
#      pvs/hart_tile.lvs.v appended (4,315,911 + 3,165,009 = 7,480,920 bytes
#      exactly; `module hart_tile` is the last module in the file). Running the
#      DP tcl as it stands would clobber it with a tile-less, unpatched netlist.
#      Pad patch + concatenation live in gen_MCU_castalia_lvs_collateral.sh.
#   3. HARD sanity gate instead of the DP comment-only "should": distinct FE_OFN*
#      and CTS_* counts must equal out/MCU_castalia.xsim.v; on mismatch the
#      netlist is DELETED and the script exits 1.
#   4. Same-session pvs/MCU_castalia.lvslabels dump (G0). NO staged copy
#      of that file exists (deliberately -- a placeholder from another
#      floorplan would be actively wrong here, and lvs.sh's mtime gate cannot
#      catch a file that is NEWER than the netlist). It is created by this
#      script from the wound-quad cut's own placements, read from THIS DB
#      (mcu0 is a MODULE here, not a macro: the tile instances are named
#      mcu0/hart<h> and their boxes are already chip-absolute).
#      Binding is `lvs_cpoint VDD_SW_H<h> Xmcu0/Xhart<h>/VDD_SW` in
#      pvs/lvs_MCU_castalia_ctl -- keep names and cpoints in sync.
#      NB lvs.sh ALSO injects pvs/hart_tile_vddsw.lvslabels into the boxed
#      hart_tile struct for any cell matching chip_top* -- MCU_castalia
#      does.
#
# Run: cd ~/vestarv/innovus/common/MCU_castalia && innovus -no_gui -batch \
#        -log log/MCU_castalia_lvs_regen -files ../../../signoff_mp/tcl/MCU_castalia_lvs_netlist.tcl
# Normally invoked through ../../signoff_mp/gen_MCU_castalia_lvs_collateral.sh chip.

# 2026-07-28: the per-block reorg moved BOTH shared tcl files out of the block
# dirs; tcl/constants.tcl and $SCRIPT_DIR/procedures.tcl no longer resolve from
# a block CWD (the flow tcl was converted to ../shared/constants.tcl but this
# LVS chain was missed, so the wound-quad regen would fail identically today).
source ../shared/constants.tcl
source ../shared/procedures.tcl

set IO_PAD_LEF /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef

set PVS_DIR       /home/mseminario2/vestarv/signoff_mp/pvs
set XSIM_REF      "$OUTPUT_DIR/MCU_castalia.xsim.v"
set NETLIST_OUT   "$PVS_DIR/MCU_castalia.lvs.v"
set LABELS_OUT    "$PVS_DIR/MCU_castalia.lvslabels"
set TILE_LABELS   "$PVS_DIR/hart_tile.lvslabels"

proc __wnd_distinct {file pat} {
    if {![file exists $file]} { return -1 }
    set cmd [format {grep -oE '%s' "%s" | sort -u | wc -l} $pat $file]
    if {[catch {exec sh -c $cmd} out]} { return -1 }
    return [string trim $out]
}

set FE_PAT  {FE_OFN[A-Za-z0-9_]*}
set CTS_PAT {CTS_[A-Za-z0-9_]*}

if {![file exists $XSIM_REF]} {
    puts "WQCHIPREGEN: FATAL: reference netlist $XSIM_REF missing"
    exit 1
}

set init_verilog   $XSIM_REF
set init_top_cell  MCU_castalia
set init_pwr_net   VDD
set init_gnd_net   VSS
set init_mmmc_file "$SCRIPT_DIR/viewdefinition_MCU_castalia.tcl"
set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					../hart_tile/out/hart_tile.lef \
					$IO_PAD_LEF"
set init_design_uniquify 1
init_design
setDesignMode -process 65 -flowEffort standard -powerEffort low
setMultiCpuUsage -localCpu 4

defIn $DATABASE_DIR/MCU_castalia.signoff.innovus.dat/MCU_castalia.def.gz
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose
puts "WQCHIPREGEN: init+defIn+gnc done; instCount=[llength [dbGet top.insts.name]]"

# Physical cells KEPT (-phys): the tphn signal/supply pad-ring instances
# (PDUW16SDGZ_G / PDDW16SDGZ_G / PDB3A_G / PVDD*/PVSS*/PVDD2POC_G) -- subckt
# defs come from the tphn spice in lvs_include_chip. std-cell FILL family
# excluded (C0 list). NB the wound padring differs from DP ONLY in the CELL
# TYPE of PAD_P5_6/PAD_P5_7 (pull-DOWN PDDW16SDGZ_G, the DP-S3 contract);
# instance names are identical, so nothing here or in the pad patcher changes.
saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH" \
    $NETLIST_OUT
puts "WQCHIPREGEN: saveNetlist done -> $NETLIST_OUT"

# --- A7 SANITY GATE -------------------------------------------------------
set fe_ref [__wnd_distinct $XSIM_REF    $FE_PAT]
set fe_new [__wnd_distinct $NETLIST_OUT $FE_PAT]
set ct_ref [__wnd_distinct $XSIM_REF    $CTS_PAT]
set ct_new [__wnd_distinct $NETLIST_OUT $CTS_PAT]
puts "WQCHIPREGEN: distinct FE_OFN  ref=$fe_ref  new=$fe_new"
puts "WQCHIPREGEN: distinct CTS_    ref=$ct_ref  new=$ct_new"
if {$fe_ref <= 0 || $ct_ref <= 0} {
    file delete -force $NETLIST_OUT
    puts "WQCHIPREGEN: FATAL: could not count reference names in $XSIM_REF (ref=$fe_ref/$ct_ref)"
    exit 1
}
if {$fe_ref ne $fe_new || $ct_ref ne $ct_new} {
    file delete -force $NETLIST_OUT
    puts "WQCHIPREGEN: FATAL: FE_OFN/CTS_ counts differ from $XSIM_REF --"
    puts "WQCHIPREGEN:        the saved netlist is NOT this cut (A7 stale-netlist tell)."
    puts "WQCHIPREGEN:        $NETLIST_OUT deleted so nothing downstream can eat it."
    exit 1
}
puts "WQCHIPREGEN: A7 sanity gate PASS (FE_OFN + CTS_ exact)"

# --- VDD_SW chip labels, SAME SESSION (G0) --------------------------------
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
    puts "WQCHIPREGEN: FATAL: $TILE_LABELS missing -- dump it with tcl/hart_tile_lvs_netlist.tcl"
    exit 1
}
if {[file mtime $TILE_LABELS] < [file mtime ../hart_tile/out/hart_tile.gds2]} {
    puts "WQCHIPREGEN: FATAL: $TILE_LABELS is older than ../hart_tile/out/hart_tile.gds2 --"
    puts "WQCHIPREGEN:        re-dump the tile labels (tcl/hart_tile_lvs_netlist.tcl) first."
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
puts "WQCHIPREGEN: tile label pieces read: [llength $pts]"
puts "WQCHIPREGEN: tile short sentinels dropped (not aliased per hart): $nsent_skipped"

set fp [open $LABELS_OUT w]
set total 0
for {set h 0} {$h < 4} {incr h} {
    set ip [dbGet top.insts.name mcu0/hart$h -p]
    if {$ip == 0} {
        close $fp
        file delete -force $LABELS_OUT
        puts "WQCHIPREGEN: FATAL: no instance mcu0/hart$h in the chip DB"
        exit 1
    }
    set box [join [dbGet ${ip}.box]]
    set x1 [lindex $box 0]; set y1 [lindex $box 1]
    set x2 [lindex $box 2]; set y2 [lindex $box 3]
    set W  [expr {$x2 - $x1}]
    set H  [expr {$y2 - $y1}]
    set orient [dbGet ${ip}.orient]
    puts "WQCHIPREGEN: mcu0/hart$h  orient=$orient  box=($x1,$y1)-($x2,$y2)  W=$W H=$H"
    foreach pt $pts {
        set layer [lindex $pt 0]
        set lx    [lindex $pt 1]
        set ly    [lindex $pt 2]
        set text  [string trimright [lindex $pt 3] ":"]
        set g [__wnd_xform $orient $x1 $y1 $W $H $lx $ly]
        if {[llength $g] != 2} {
            close $fp
            file delete -force $LABELS_OUT
            puts "WQCHIPREGEN: FATAL: unsupported orient '$orient' on mcu0/hart$h"
            exit 1
        }
        puts $fp [format "%s %.3f %.3f %s_H%d:" $layer [lindex $g 0] [lindex $g 1] $text $h]
        incr total
    }
}
# Stage J sentinel texts (permanent): one VDD: and one VSS: TEXT on adjacent
# M1 followpin rails mid-die. WHY: Pegasus FIND_SHORTS only reports a merge
# between nets that carry CONFLICTING TEXTS. Neither the pad-pin texts nor the
# VDD_SW labels give the core VDD/VSS trees reliable text identity, so the
# Stage-J PDB3A guard-ring VDD-VSS short produced an EMPTY shorts file and
# surfaced only as an unexplained "layout VDD = missing net". With these two
# sentinels every future run is short-sensitive by construction: a merged
# power net now yields a named "SHORT n. VDD: - VSS:" path in lvs.rep.shorts.
# Coords are floorplan-deterministic center-band followpin rails (y=1113 VDD,
# y=1111 VSS, x mid-die) -- re-derive if the row grid ever changes.
puts $fp "131 1345.000 1113.000 VDD:"
puts $fp "131 1345.000 1111.000 VSS:"
incr total 2
close $fp
puts "WQCHIPREGEN: wrote $total labels (incl. 2 VDD/VSS short-sentinel texts) -> $LABELS_OUT"
puts "WQCHIPREGEN: DONE (netlist + same-cut labels).  Now run gen_MCU_castalia_lvs_collateral.sh"
puts "WQCHIPREGEN:      for patch_chip_pads_wound.py + the tile-netlist concatenation."
exit
