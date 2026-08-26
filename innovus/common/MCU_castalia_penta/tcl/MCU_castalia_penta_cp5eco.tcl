################################################################################
# CP5 CLOSURE ECO -- Castalia-Penta (one bounded pass).
#
# Lineage: COPY of the CP4b signoff DB. The CP4b DBs/GDS are NEVER mutated in
# place; everything this script writes carries a cp5 name:
#   dbs/MCU_castalia_penta.cp5eco_a.innovus   stage A = PG stub repair only
#   dbs/MCU_castalia_penta.cp5eco.innovus     stage B = stage A + setup ECO
#                                             (written ONLY if B is accepted)
#   out/MCU_castalia_penta.cp5.{gds2,sdf,xsim.v}   from the accepted cut
#
# ---------------------------------------------------------------------------
# RESIDUAL 1 -- the CP4b "degenerate zero-area VSS M4 sroute weld stub at
# (2354.899, 1153.500)".  MEASURED, not assumed (probe runs cp5probe /
# cp5probe2 + an SREF-aware scan of the SOURCE GDS):
#   * there is NO zero-area special wire anywhere in the DB (VDD or VSS);
#   * the real object is a 0.46 x 6.285 um M4 VSS riser
#         (2354.670, 1153.500) - (2355.130, 1159.785)
#     just west of the orchestrator TCM mcu0/hart4/tile/ram0 (box starts at
#     x = 2355.3), i.e. in the macro's halo, ABOVE it a second M4 pad
#         (2354.670, 1159.325) - (2355.530, 1159.785);
#   * the SOURCE GDS carries the same rectangle in the top struct (so it is
#     NOT a translation phantom -- PG4 discipline) PLUS the via struct
#     MCU_castalia_penta_VIA90, whose M4 landing pad is
#         (2354.670, 1155.770) - (2355.130, 1156.230),
#     i.e. INSIDE the riser: the riser is connected there and only its lower
#     TAIL (y 1153.500 .. 1155.770) hangs free. (2354.899, 1153.500) is the
#     marker Innovus prints for that free lower END -- both the single
#     verifyGeometry ANTENNA and the single IMPVFC-94 dangling wire.
#   => REPAIR = trim the tail, not delete the riser: delete the riser shape
#      (selection-scoped, area-bounded) and add_shape the same rectangle back
#      starting at y = 1155.16, the bottom edge of the M7 VSS stripe that
#      crosses here (floorplan-deterministic). The VIA90 pad keeps 0.61 um of
#      metal below it; nothing else in the window is touched.
#   NEVER a bare `editDelete` (CLAUDE.md: it wipes every wire and special wire
#   in the design). Global count guards before/after, FATAL before saveDesign.
#
# RESIDUAL 2 -- 3 clock-gating setup violations in mcu0/hart4 (WNS -0.021 ns,
#   TNS -0.044). ONE bounded incremental postRoute setup attempt (useful skew
#   on). Accept only if setup WNS >= 0 AND hold WNS >= 0; otherwise revert to
#   stage A and carry the -0.021 as a documented residual. No iteration, no
#   filler churn (deleteFiller/addFiller cycles are forbidden on a routed DB;
#   addFiller here is ADD-only, to close gaps the ECO placer opened).
#
# Run (one heavy run at a time):
#   cd ~/vestarv/innovus/common/MCU_castalia_penta && source ~/vestarv/cdspaths.sh
#   innovus -no_gui -batch -log log/MCU_castalia_penta_cp5eco -overwrite \
#           -files tcl/MCU_castalia_penta_cp5eco.tcl
################################################################################

source ../shared/constants.tcl
source ../shared/procedures.tcl

set DESIGN_NAME MCU_castalia_penta
set BASENAME    MCU_castalia_penta
set ECOA        ${BASENAME}.cp5eco_a
set ECOB        ${BASENAME}.cp5eco
set CP5         ${BASENAME}.cp5

# the riser, as measured
set RIS_X0 2354.670 ; set RIS_X1 2355.130
set RIS_Y0 1153.500 ; set RIS_Y1 1159.785
# new bottom edge = bottom of the M7 VSS stripe (2318.0,1155.16)-(2355.55,1155.66)
set NEW_Y0 1155.160
# delete window: fully contains the riser, and NOTHING else in this
# neighbourhood (the upper M4 pad reaches x 2355.53, the M7/M8/M5/M1 shapes all
# run far beyond -- editDelete/-area is whole-shape-contained).
set DELWIN [list 2354.500 1153.300 2355.200 1159.900]
# census window (bigger, for the before/after shape list)
set WIN    [list 2350.000 1150.000 2360.000 1162.000]

proc __cnt {path} {
    set r [dbGet $path -e]
    if {$r eq "0x0" || $r eq ""} { return 0 }
    return [llength $r]
}

proc __box {ptr} {
    set b {}
    catch { set b [dbGet $ptr.box] }
    if {[llength $b] == 1} { set b [lindex $b 0] }
    return $b
}

# special wires of $net whose box touches $win  -> {ptr layer box}
proc __in_win {net win} {
    lassign $win wx0 wy0 wx1 wy1
    set out {}
    set netp [dbGet -p top.nets.name $net]
    if {$netp eq "0x0" || $netp eq ""} { return {} }
    foreach w [dbGet $netp.sWires] {
        set b [__box $w]
        if {[llength $b] != 4} { continue }
        lassign $b x1 y1 x2 y2
        if {$x1 <= $wx1 && $wx0 <= $x2 && $y1 <= $wy1 && $wy0 <= $y2} {
            set lay "?"
            catch { set lay [dbGet $w.layer.name] }
            lappend out [list $w $lay $b]
        }
    }
    return $out
}

# is the untrimmed riser still present?  (re-queried from the net every time --
# never from a saved pointer: dbGet on a freed pointer can error, not return 0)
proc __riser_alive {} {
    global RIS_X0 RIS_Y0 RIS_Y1 WIN
    foreach e [__in_win VSS $WIN] {
        if {[lindex $e 1] ne "M4"} { continue }
        lassign [lindex $e 2] x1 y1 x2 y2
        if {abs($x1 - $RIS_X0) < 0.01 && abs($y1 - $RIS_Y0) < 0.01 && abs($y2 - $RIS_Y1) < 0.01} { return 1 }
    }
    return 0
}

proc __report_list {tag lst} {
    puts "### CP5ECO ### $tag : [llength $lst] shape(s)"
    foreach e $lst {
        puts "### CP5ECO ###    [lindex $e 0]  [lindex $e 1]  [lindex $e 2]"
    }
}

# setup / hold WNS by parsing a report_timing dump (numeric, install-agnostic)
proc __wns {tag mode} {
    global REPORT_DIR BASENAME
    set f $REPORT_DIR/$BASENAME.cp5eco.$tag.$mode.rpt
    setAnalysisMode -checkType $mode -skew false
    if {[catch {report_timing -nworst 10 > $f} e]} {
        puts "### CP5ECO ### WARN report_timing($tag,$mode) failed: $e"
        return 99.0
    }
    set wns 99.0
    set fh [open $f r]
    while {[gets $fh ln] >= 0} {
        if {[regexp {Slack Time\s+(-?[0-9]+\.[0-9]+)} $ln -> v]} {
            if {$v < $wns} { set wns $v }
        }
    }
    close $fh
    puts "### CP5ECO ### WNS($tag,$mode) = $wns   (from $f)"
    return $wns
}

################################################################################
# 0. restore the CP4b signoff cut (COPY lineage: nothing is written back to it)
################################################################################
restoreDesign $DATABASE_DIR/$BASENAME.signoff.innovus.dat $DESIGN_NAME
setCheckMode -tapeOut false

set BASE_INSTS  [__cnt top.insts.name]
set BASE_SWIRES [__cnt top.nets.sWires]
set BASE_WIRES  [__cnt top.nets.wires]
set VSS_SW0     [llength [dbGet [dbGet -p top.nets.name VSS].sWires]]
set VDD_SW0     [llength [dbGet [dbGet -p top.nets.name VDD].sWires]]
puts "### CP5ECO ### restored census: insts $BASE_INSTS  sWires $BASE_SWIRES  wires $BASE_WIRES"
puts "### CP5ECO ### VSS sWires $VSS_SW0   VDD sWires $VDD_SW0"
if {$BASE_INSTS == 0 || $BASE_SWIRES == 0 || $BASE_WIRES == 0} {
    puts "### CP5ECO ### FATAL: restored database is empty/gutted."
    exit 1
}

################################################################################
# 1. PROVE the riser is there, exactly as measured, before touching anything
################################################################################
__report_list "VSS special shapes in window $WIN (before)" [__in_win VSS $WIN]
if {![__riser_alive]} {
    puts "### CP5ECO ### FATAL: the M4 VSS riser ($RIS_X0,$RIS_Y0)-($RIS_X1,$RIS_Y1) is NOT in this DB."
    exit 1
}
puts "### CP5ECO ### riser confirmed present"

################################################################################
# 2. Trim it: delete (selection-scoped, area-bounded) + add back the upper part
################################################################################
deselectAll
if {[catch {editSelect -type Special -layer M4 -area $DELWIN -nets VSS} e]} {
    puts "### CP5ECO ### editSelect(Special,M4) rc!=0: $e"
}
if {[catch {editDelete -selected} e]} {
    puts "### CP5ECO ### editDelete -selected rc!=0: $e"
}
deselectAll
set killed [expr {![__riser_alive]}]
puts "### CP5ECO ### after attempt 1 (editSelect + editDelete -selected): killed=$killed"
if {!$killed} {
    if {[catch {editDelete -type Special -net VSS -layer M4 -area $DELWIN} e]} {
        puts "### CP5ECO ### editDelete(-type Special -area) rc!=0: $e"
    }
    set killed [expr {![__riser_alive]}]
    puts "### CP5ECO ### after attempt 2 (editDelete -type Special -net -layer -area): killed=$killed"
}

set D_INSTS  [__cnt top.insts.name]
set D_SWIRES [__cnt top.nets.sWires]
set D_WIRES  [__cnt top.nets.wires]
set VSS_SW1  [llength [dbGet [dbGet -p top.nets.name VSS].sWires]]
set VDD_SW1  [llength [dbGet [dbGet -p top.nets.name VDD].sWires]]
puts "### CP5ECO ### post-delete census: insts $D_INSTS (base $BASE_INSTS)  sWires $D_SWIRES (base $BASE_SWIRES)  wires $D_WIRES (base $BASE_WIRES)"
puts "### CP5ECO ### VSS sWires $VSS_SW1 (base $VSS_SW0)   VDD sWires $VDD_SW1 (base $VDD_SW0)"

set fatal 0
if {!$killed}                               { puts "### CP5ECO ### FATAL: the riser survived every scoped delete." ; incr fatal }
if {$D_INSTS != $BASE_INSTS}                { puts "### CP5ECO ### FATAL: instance count changed by the delete." ; incr fatal }
if {$D_WIRES != $BASE_WIRES}                { puts "### CP5ECO ### FATAL: signal-wire count changed by the delete." ; incr fatal }
if {$VDD_SW1 != $VDD_SW0}                   { puts "### CP5ECO ### FATAL: VDD special wires changed by a VSS-scoped delete." ; incr fatal }
if {$VSS_SW1 != [expr {$VSS_SW0 - 1}]}      { puts "### CP5ECO ### FATAL: expected exactly ONE VSS special wire deleted (got [expr {$VSS_SW0 - $VSS_SW1}])." ; incr fatal }
if {$D_SWIRES != [expr {$BASE_SWIRES - 1}]} { puts "### CP5ECO ### FATAL: expected exactly ONE special wire deleted design-wide (got [expr {$BASE_SWIRES - $D_SWIRES}])." ; incr fatal }
if {$fatal} {
    puts "### CP5ECO ### ABORT before any saveDesign -- $fatal guard(s) tripped."
    exit 1
}

add_shape -net VSS -layer M4 -rect [list $RIS_X0 $NEW_Y0 $RIS_X1 $RIS_Y1] -shape STRIPE -status ROUTED
puts "### CP5ECO ### trimmed riser added: M4 VSS ($RIS_X0,$NEW_Y0)-($RIS_X1,$RIS_Y1)"

set A_INSTS  [__cnt top.insts.name]
set A_SWIRES [__cnt top.nets.sWires]
set A_WIRES  [__cnt top.nets.wires]
set VSS_SW2  [llength [dbGet [dbGet -p top.nets.name VSS].sWires]]
puts "### CP5ECO ### post-add census: insts $A_INSTS  sWires $A_SWIRES (base $BASE_SWIRES)  wires $A_WIRES  VSS sWires $VSS_SW2 (base $VSS_SW0)"
__report_list "VSS special shapes in window $WIN (after)" [__in_win VSS $WIN]

set fatal 0
if {$A_INSTS  != $BASE_INSTS}  { puts "### CP5ECO ### FATAL: instance count moved during the repair." ; incr fatal }
if {$A_WIRES  != $BASE_WIRES}  { puts "### CP5ECO ### FATAL: signal-wire count moved during the repair." ; incr fatal }
if {$A_SWIRES != $BASE_SWIRES} { puts "### CP5ECO ### FATAL: special-wire count is not back to baseline after delete+add." ; incr fatal }
if {$VSS_SW2  != $VSS_SW0}     { puts "### CP5ECO ### FATAL: VSS special-wire count is not back to baseline." ; incr fatal }
if {[__riser_alive]}           { puts "### CP5ECO ### FATAL: the untrimmed riser is somehow back." ; incr fatal }
if {$fatal} {
    puts "### CP5ECO ### ABORT before any saveDesign -- $fatal guard(s) tripped."
    exit 1
}
puts "### CP5ECO ### stub repair GUARDS PASS"

# immediate proof that the repair did what it claims (and nothing else):
verifyConnectivity -error 100000 -connectPadSpecialPorts \
    -report $REPORT_DIR/$BASENAME.verifyConnectivity.cp5a.rpt
verifyGeometry -antenna \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.cp5a.rpt

saveDesign $DATABASE_DIR/$ECOA.innovus -def -netlist -rc -tcon
puts "### CP5ECO ### stage A saved -> $DATABASE_DIR/$ECOA.innovus"

################################################################################
# 3. ONE bounded setup-recovery attempt on the 3 hart4 clock-gating paths
################################################################################
setAnalysisMode -analysisType onChipVariation -cppr both
setDelayCalMode -SIAware false
set WNS_A_SETUP [__wns preA setup]
set WNS_A_HOLD  [__wns preA hold]
# MEASUREMENT SANITY (a clean number from a blind instrument is not evidence):
# stage A must still show the KNOWN CP4b violation (-0.021 ns, reg2cgate).
if {$WNS_A_SETUP > -0.010} {
    puts "### CP5ECO ### FATAL: stage-A setup WNS measured $WNS_A_SETUP, but the CP4b cut has a"
    puts "### CP5ECO ###        KNOWN -0.021 ns clock-gating violation -- the instrument is not"
    puts "### CP5ECO ###        seeing the violating path group; refusing to judge the ECO with it."
    exit 1
}

catch { setOptMode -usefulSkew true }
catch { setOptMode -usefulSkewPostRoute true }
if {[catch {optDesign -postRoute -setup -incr} e]} {
    puts "### CP5ECO ### optDesign -postRoute -setup -incr rc!=0: $e"
    puts "### CP5ECO ### retrying without -incr"
    if {[catch {optDesign -postRoute -setup} e2]} {
        puts "### CP5ECO ### optDesign -postRoute -setup rc!=0: $e2"
    }
}
setDelayCalMode -SIAware true
setOptMode -holdTargetSlack 0.01
if {[catch {optDesign -postRoute -hold -incr} e]} {
    puts "### CP5ECO ### optDesign -postRoute -hold -incr rc!=0: $e"
    catch {optDesign -postRoute -hold}
}
setOptMode -holdTargetSlack 0
setDelayCalMode -SIAware false
catch { addFiller }

set WNS_B_SETUP [__wns postB setup]
set WNS_B_HOLD  [__wns postB hold]
set B_INSTS  [__cnt top.insts.name]
set B_SWIRES [__cnt top.nets.sWires]
set B_WIRES  [__cnt top.nets.wires]
puts "### CP5ECO ### stage B census: insts $B_INSTS (A $A_INSTS)  sWires $B_SWIRES (A $A_SWIRES)  wires $B_WIRES (A $A_WIRES)"
puts "### CP5ECO ### stage A timing: setup $WNS_A_SETUP  hold $WNS_A_HOLD"
puts "### CP5ECO ### stage B timing: setup $WNS_B_SETUP  hold $WNS_B_HOLD"

if {$WNS_B_SETUP > 98.0 || $WNS_B_HOLD > 98.0} {
    puts "### CP5ECO ### FATAL: timing could not be measured after the ECO -- refusing to pick a cut blind."
    exit 1
}
set ACCEPT_B 0
if {$WNS_B_SETUP >= -0.0005 && $WNS_B_HOLD >= -0.0005 && $B_SWIRES >= [expr {$A_SWIRES - 1}]} { set ACCEPT_B 1 }

if {$ACCEPT_B} {
    puts "### CP5ECO ### DECISION: ACCEPT stage B (setup WNS $WNS_B_SETUP, hold WNS $WNS_B_HOLD)"
    set CUT $ECOB
} else {
    puts "### CP5ECO ### DECISION: REJECT stage B (setup WNS $WNS_B_SETUP, hold WNS $WNS_B_HOLD) -- reverting to stage A"
    restoreDesign $DATABASE_DIR/$ECOA.innovus.dat $DESIGN_NAME
    setCheckMode -tapeOut false
    setAnalysisMode -analysisType onChipVariation -cppr both
    setDelayCalMode -SIAware false
    set CUT $ECOA
}
puts "### CP5ECO ### CUT OF RECORD = $CUT"

################################################################################
# 4. Signoff checks + outputs on the cut of record
################################################################################
verifyConnectivity -error 100000 -connectPadSpecialPorts \
    -report $REPORT_DIR/$BASENAME.verifyConnectivity.cp5.rpt
verifyGeometry -antenna \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.cp5.rpt

set F_INSTS  [__cnt top.insts.name]
set F_SWIRES [__cnt top.nets.sWires]
set F_WIRES  [__cnt top.nets.wires]
puts "### CP5ECO ### final census: insts $F_INSTS  sWires $F_SWIRES  wires $F_WIRES"
if {$F_INSTS == 0 || $F_SWIRES < [expr {$BASE_SWIRES / 2}] || $F_WIRES == 0} {
    puts "### CP5ECO ### FATAL: final census collapsed -- refusing to stream/save."
    exit 1
}

set WNS_F_SETUP [__wns final setup]
set WNS_F_HOLD  [__wns final hold]
timeDesign -postRoute -outDir $REPORT_DIR/$BASENAME.timeDesign.cp5
catch { report_power -outfile $REPORT_DIR/${BASENAME}_cp5_full.power }
reportGateCount -level 2 -outfile $REPORT_DIR/$BASENAME.reportGateCount.cp5.rpt
summaryReport -noHtml -outfile $REPORT_DIR/$BASENAME.summaryReport.cp5.rpt

if {$CUT eq $ECOB} {
    saveDesign $DATABASE_DIR/$ECOB.innovus -def -netlist -rc -tcon
    puts "### CP5ECO ### stage B saved -> $DATABASE_DIR/$ECOB.innovus"
}

streamOut \
    $OUTPUT_DIR/$CP5.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -merge [list ../hart_tile/out/hart_tile.gds2 \
                 /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/gds/tphn65gpgv2od3_sl_210a/mt_2/8lm/tphn65gpgv2od3_sl.gds] \
    -mapFile ../shared/innovus2gds.map
puts "### CP5ECO ### streamOut -> $OUTPUT_DIR/$CP5.gds2"

write_sdf $OUTPUT_DIR/$CP5.sdf
saveNetlist $OUTPUT_DIR/$CP5.xsim.v -excludeCellInst ANTENNA2A10TH
puts "### CP5ECO ### SDF + sim netlist written ($CP5.sdf / $CP5.xsim.v)"
puts "### CP5ECO ### DONE -- cut of record $CUT ; setup WNS $WNS_F_SETUP ; hold WNS $WNS_F_HOLD"
exit
