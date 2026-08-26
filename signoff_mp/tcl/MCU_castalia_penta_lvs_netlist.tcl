# CASTALIA-PENTA chip (CPR7, 2026-08-15): MCU_castalia_penta LVS netlist WITH
# power/ground -- A7 FRESH-INIT + defIn pattern (never restoreDesign a
# tape-out-mode chip DB, never patch .mode: the standing G0/A7 rule).
#
# CLONE of tcl/MCU_castalia_lvs_netlist.tcl (the 4-hart wound-quad chip).
# DELTAS, all deliberate:
#   1. design/cell/lib names -> MCU_castalia_penta; mmmc ->
#      tcl/viewdefinition_MCU_castalia_penta.tcl (block-local, hart_tile ETM +
#      sram/rom libs; hart4 is SOFT so no extra library entry exists).
#   2. THE CUT. Any re-P&R (and any post-P&R ECO) invalidates saved LVS
#      netlists -- CPR7 RETARGET (2026-08-15): this file reads the CPR7 CUT OF
#      RECORD (the CPR6 5-core re-cut + its closure ECO):
#        dbs/MCU_castalia_penta.cpr7eco.innovus.dat
#      and the netlist it is checked against is that cut's own
#      out/MCU_castalia_penta.cpr7.xsim.v. The CPR6 *.signoff DB and every
#      CP-era (*.cp5.*, *.signoff) product are NOT the cut of record and are
#      deliberately not readable from here.
#   3. LABELS: 4 corner tiles only -- and after the CPR3 RENUMBER those are
#      mcu0/hart1..hart4. mcu0/hart0 is the SOFT orchestrator: no switched rail,
#      no VDD_SW piece set, no cpoint. Label texts are VDD_SW_H1..VDD_SW_H4 and
#      pvs/lvs_MCU_castalia_penta_ctl carries exactly those four cpoints --
#      keep the two files in sync (a name/index skew here silently produces a
#      phantom VDD_SW MISMATCH; the A6 same-name lesson in another costume).
#   3b. THE 8 KiB TCM (2026-08-18). Two things this file was missing, both
#      fixed below and both flagged in log/MCU_castalia_penta_lvs_regen.log:
#      (a) sram1p8k_hvt_pg.vclef was not in init_lef_file --
#          "**ERROR: (IMPREPO-102): Instance mcu0/hart0/tile/ram0 of the cell
#           sram1p8k_hvt_pg has no physical library"; and
#      (b) the split-rail globalNetConnect rules were not re-declared after
#          clearGlobalNets -- IMPVL-520 on VSSE/VDDPE/VDDCE of that instance.
#      Together they made saveNetlist emit the orchestrator's TCM with no power
#      pins at all, so LVS could not have checked the very binding it was run
#      for. The P&R DB is not affected: MCU_castalia_penta.innovus.tcl has both.
#   4. The two Stage-J VDD:/VSS: short-sentinel texts are re-VERIFIED against
#      this DB before they are written (the reference tcl hard-codes them):
#      an M1 VDD and an M1 VSS follow-pin rail must actually cover the two
#      points, or the run FATALs. Sentinels are what make FIND_SHORTS
#      short-sensitive at all (Stage J: a real PDB3A VDD-VSS short produced an
#      EMPTY shorts file without them).
#
# Run: cd ~/vestarv/innovus/common/MCU_castalia_penta && innovus -no_gui -batch \
#        -log log/MCU_castalia_penta_lvs_regen \
#        -files ../../../signoff_mp/tcl/MCU_castalia_penta_lvs_netlist.tcl
# Normally invoked through ../../signoff_mp/gen_MCU_castalia_penta_lvs_collateral.sh.

source ../shared/constants.tcl
source ../shared/procedures.tcl

set IO_PAD_LEF /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef

set BASE          MCU_castalia_penta
set PVS_DIR       /home/mseminario2/vestarv/signoff_mp/pvs
# Retargeted 2026-08-17 to the cpr6 signoff cut -- see the long note in
# gen_MCU_castalia_penta_lvs_collateral.sh. Overridable via the environment
# so a future closure-ECO cut can be selected without editing this file.
set CUTSEL  [expr {[info exists ::env(CUTSEL)]  ? $::env(CUTSEL)  : "cpr6.signoff"}]
set XSIMSEL [expr {[info exists ::env(XSIMSEL)] ? $::env(XSIMSEL) : "cpr6"}]
set XSIM_REF      "$OUTPUT_DIR/${BASE}.${XSIMSEL}.xsim.v"
set NETLIST_OUT   "$PVS_DIR/${BASE}.lvs.v"
set LABELS_OUT    "$PVS_DIR/${BASE}.lvslabels"
set TILE_LABELS   "$PVS_DIR/hart_tile.lvslabels"

# ---- CPR7 cut of record -----------------------------------------------------
set CUTDB ""
foreach __c [list ${BASE}.${CUTSEL}] {
    if {[file isdirectory "$DATABASE_DIR/${__c}.innovus.dat"]} { set CUTDB $__c ; break }
}
if {$CUTDB eq ""} {
    puts "PENTAREGEN: FATAL: no CPR7 ECO database in $DATABASE_DIR"
    puts "PENTAREGEN:        expected ${BASE}.${CUTSEL}.innovus.dat"
    exit 1
}
set CUT_DEF "$DATABASE_DIR/${CUTDB}.innovus.dat/${BASE}.def.gz"
if {![file exists $CUT_DEF]} {
    puts "PENTAREGEN: FATAL: $CUT_DEF missing (the cut's DB has no DEF -- saveDesign -def?)"
    exit 1
}
puts "PENTAREGEN: cut of record = $CUTDB"
puts "PENTAREGEN: DEF           = $CUT_DEF"

proc __wnd_distinct {file pat} {
    if {![file exists $file]} { return -1 }
    set cmd [format {grep -oE '%s' "%s" | sort -u | wc -l} $pat $file]
    if {[catch {exec sh -c $cmd} out]} { return -1 }
    return [string trim $out]
}

set FE_PAT  {FE_OFN[A-Za-z0-9_]*}
set CTS_PAT {CTS_[A-Za-z0-9_]*}

if {![file exists $XSIM_REF]} {
    puts "PENTAREGEN: FATAL: reference netlist $XSIM_REF missing (the CPR7 ECO writes it)"
    exit 1
}

set init_verilog   $XSIM_REF
set init_top_cell  MCU_castalia_penta
set init_pwr_net   VDD
set init_gnd_net   VSS
set init_mmmc_file "$SCRIPT_DIR/viewdefinition_MCU_castalia_penta.tcl"
set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					../hart_tile/out/hart_tile.lef \
					$IO_PAD_LEF"
set init_design_uniquify 1
init_design
setDesignMode -process 65 -flowEffort standard -powerEffort low
setMultiCpuUsage -localCpu 4

defIn $CUT_DEF
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose
# THE 8 KiB TCM'S SPLIT RAILS (2026-08-18). This is a FRESH-INIT + defIn
# session, so the DB's own globalNetConnect rules are NOT inherited -- whatever
# is declared here is the whole of what saveNetlist -includePowerGround can
# emit. Before this block existed, the orchestrator's own TCM instance
# mcu0/hart0/tile/ram0 (sram1p8k_hvt_pg: split rails VDDPE/VDDCE/VSSE, not the
# 16 KiB macro's plain VDD/VSS) came out of saveNetlist with NO power pins at
# all, and the regen log said so:
#   **WARN: (IMPVL-520): P/G pin 'VSSE' of instance 'mcu0/hart0/tile/ram0' is
#            not connected to a power or ground net.      (also VDDPE, VDDCE)
# The P&R DB itself is fine (MCU_castalia_penta.innovus.tcl declares exactly
# these three rules and its log has zero IMPVL-520) -- the loss was in THIS
# file, and its effect was to hand LVS a source netlist in which the fifth
# TCM's power was invisible, i.e. the one thing LVS was being run to check
# would have gone unchecked (the PG2-F1 shape). Keep these three lines in sync
# with MCU_castalia_penta.innovus.tcl.
globalNetConnect VDD -type pgpin -pin VDDPE -inst * -module {} -autoTie -verbose
globalNetConnect VDD -type pgpin -pin VDDCE -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSSE  -inst * -module {} -autoTie -verbose
puts "PENTAREGEN: init+defIn+gnc done; instCount=[llength [dbGet top.insts.name]]"

# Physical cells KEPT (-phys): the tphn signal/supply pad-ring instances; the
# std-cell FILL family is excluded (C0 list). Identical to the 4-hart chip:
# the penta padring is the same 72-pad pre-D3 LQFP-100 ring.
saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH" \
    $NETLIST_OUT
puts "PENTAREGEN: saveNetlist done -> $NETLIST_OUT"

# --- A7 SANITY GATE -------------------------------------------------------
set fe_ref [__wnd_distinct $XSIM_REF    $FE_PAT]
set fe_new [__wnd_distinct $NETLIST_OUT $FE_PAT]
set ct_ref [__wnd_distinct $XSIM_REF    $CTS_PAT]
set ct_new [__wnd_distinct $NETLIST_OUT $CTS_PAT]
puts "PENTAREGEN: distinct FE_OFN  ref=$fe_ref  new=$fe_new"
puts "PENTAREGEN: distinct CTS_    ref=$ct_ref  new=$ct_new"
if {$fe_ref <= 0 || $ct_ref <= 0} {
    file delete -force $NETLIST_OUT
    puts "PENTAREGEN: FATAL: could not count reference names in $XSIM_REF (ref=$fe_ref/$ct_ref)"
    exit 1
}
if {$fe_ref ne $fe_new || $ct_ref ne $ct_new} {
    file delete -force $NETLIST_OUT
    puts "PENTAREGEN: FATAL: FE_OFN/CTS_ counts differ from $XSIM_REF --"
    puts "PENTAREGEN:        the saved netlist is NOT this cut (A7 stale-netlist tell)."
    puts "PENTAREGEN:        $NETLIST_OUT deleted so nothing downstream can eat it."
    exit 1
}
puts "PENTAREGEN: A7 sanity gate PASS (FE_OFN + CTS_ exact)"

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
    puts "PENTAREGEN: FATAL: $TILE_LABELS missing -- dump it with tcl/hart_tile_lvs_netlist.tcl"
    exit 1
}
if {[file mtime $TILE_LABELS] < [file mtime ../hart_tile/out/hart_tile.gds2]} {
    puts "PENTAREGEN: FATAL: $TILE_LABELS is older than ../hart_tile/out/hart_tile.gds2 --"
    puts "PENTAREGEN:        re-dump the tile labels (tcl/hart_tile_lvs_netlist.tcl) first."
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
puts "PENTAREGEN: tile label pieces read: [llength $pts]"
puts "PENTAREGEN: tile short sentinels dropped (not aliased per hart): $nsent_skipped"

# CPR7 RENUMBER ASSERTION: mcu0/hart0 must NOT be a placed macro instance (it is
# the soft orchestrator). If it ever is, this file is being run against a CP-era
# cut and the labels below would land on the wrong four tiles.
set __h0 [dbGet top.insts.name mcu0/hart0 -p -e]
if {$__h0 ne "0x0" && $__h0 ne ""} {
    puts "PENTAREGEN: FATAL: mcu0/hart0 IS a placed instance -- this is a pre-CPR3"
    puts "PENTAREGEN:        (CP-era) cut where hart0..hart3 are the hardened tiles."
    exit 1
}
puts "PENTAREGEN: hart0 is soft (no placed macro) -- CPR3 renumber confirmed"

# CPR3 RENUMBER: the four HARDENED corner tiles are mcu0/hart1..hart4
# (mcu0/hart0 is the soft orchestrator -- no switched rail, no labels).
set fp [open $LABELS_OUT w]
set total 0
for {set h 1} {$h <= 4} {incr h} {
    set ip [dbGet top.insts.name mcu0/hart$h -p]
    if {$ip == 0} {
        close $fp
        file delete -force $LABELS_OUT
        puts "PENTAREGEN: FATAL: no instance mcu0/hart$h in the chip DB"
        exit 1
    }
    set box [join [dbGet ${ip}.box]]
    set x1 [lindex $box 0]; set y1 [lindex $box 1]
    set x2 [lindex $box 2]; set y2 [lindex $box 3]
    set W  [expr {$x2 - $x1}]
    set H  [expr {$y2 - $y1}]
    set orient [dbGet ${ip}.orient]
    puts "PENTAREGEN: mcu0/hart$h  orient=$orient  box=($x1,$y1)-($x2,$y2)  W=$W H=$H"
    foreach pt $pts {
        set layer [lindex $pt 0]
        set lx    [lindex $pt 1]
        set ly    [lindex $pt 2]
        set text  [string trimright [lindex $pt 3] ":"]
        set g [__wnd_xform $orient $x1 $y1 $W $H $lx $ly]
        if {[llength $g] != 2} {
            close $fp
            file delete -force $LABELS_OUT
            puts "PENTAREGEN: FATAL: unsupported orient '$orient' on mcu0/hart$h"
            exit 1
        }
        puts $fp [format "%s %.3f %.3f %s_H%d:" $layer [lindex $g 0] [lindex $g 1] $text $h]
        incr total
    }
}

# --- Stage-J short sentinels, VERIFIED against THIS DB ---------------------
# (the reference tcl hard-codes the two points; here they are proven to sit on
#  an M1 VDD / M1 VSS follow-pin rail before being written)
proc __covered {net px py} {
    set netp [dbGet -p top.nets.name $net]
    if {$netp eq "0x0" || $netp eq ""} { return 0 }
    foreach w [dbGet $netp.sWires] {
        set lay ""
        catch { set lay [dbGet $w.layer.name] }
        if {$lay ne "M1"} { continue }
        set b {}
        catch { set b [dbGet $w.box] }
        if {[llength $b] == 1} { set b [lindex $b 0] }
        if {[llength $b] != 4} { continue }
        lassign $b x1 y1 x2 y2
        if {$px >= $x1 && $px <= $x2 && $py >= $y1 && $py <= $y2} { return 1 }
    }
    return 0
}
set SENT_X 1345.000
set SENT_VDD_Y 1113.000
set SENT_VSS_Y 1111.000
set okv [__covered VDD $SENT_X $SENT_VDD_Y]
set okg [__covered VSS $SENT_X $SENT_VSS_Y]
puts "PENTAREGEN: sentinel check -- VDD@($SENT_X,$SENT_VDD_Y) on M1 rail: $okv ; VSS@($SENT_X,$SENT_VSS_Y): $okg"
if {!$okv || !$okg} {
    close $fp
    file delete -force $LABELS_OUT
    puts "PENTAREGEN: FATAL: a short-sentinel point is NOT on an M1 follow-pin rail of its net."
    puts "PENTAREGEN:        Re-derive the two coordinates from this floorplan's row grid;"
    puts "PENTAREGEN:        writing them blind would leave FIND_SHORTS text-blind (Stage J)."
    exit 1
}
puts $fp [format "131 %.3f %.3f VDD:" $SENT_X $SENT_VDD_Y]
puts $fp [format "131 %.3f %.3f VSS:" $SENT_X $SENT_VSS_Y]
incr total 2
close $fp
puts "PENTAREGEN: wrote $total labels (incl. 2 VDD/VSS short-sentinel texts) -> $LABELS_OUT"
puts "PENTAREGEN: DONE (netlist + same-cut labels).  Now run gen_MCU_castalia_penta_lvs_collateral.sh"
puts "PENTAREGEN:      for patch_chip_pads_wound.py + the tile-netlist concatenation."
exit
