################################################################################
# CPR7 CLOSURE ECO -- Castalia-Penta 5-core (one bounded pass, COPY lineage).
#
# The CPR6 signoff DB / GDS are NEVER mutated in place; everything written here
# carries a cpr7 name:
#   dbs/MCU_castalia_penta.cpr7eco.innovus        the repaired cut of record
#   out/MCU_castalia_penta.cpr7.{gds2,sdf,xsim.v} from that cut
#
# THE DEFECT (CPR6 vG signoff: "Antenna 1"):
#   ANTENNA: Special Wire of Net VSS (M4), Bounds (2354.899,1153.500)(2354.900,
#   1153.500) -- the degenerate zero-area marker Innovus prints for the FREE
#   LOWER END of a hanging M4 riser.  MEASURED on this very DB by
#   tcl/MCU_castalia_penta_cpr7probe.tcl (log/MCU_castalia_penta_cpr7probe.log),
#   byte-for-byte the CP5/CP4b object:
#     riser      M4 VSS blockwire (2354.670,1153.500)-(2355.130,1159.785)
#     upper pad  M4 VSS blockwire (2354.670,1159.325)-(2355.530,1159.785)
#     crossing   M7 VSS blockwire (2318.000,1155.160)-(2355.550,1155.660)
#     macro      mcu0/hart0/tile/ram0 box starts at x=2355.3 (the riser sits in
#                the orchestrator TCM's west halo; hart0 = the orchestrator
#                after the CPR3 renumber -- CP5 called the same object hart4)
#   REPAIR (CP5's, unchanged): TRIM the free tail, do not delete the riser --
#   selection-scoped area-bounded delete of the riser shape, then add_shape the
#   same rectangle back with its bottom edge at y = 1155.160, the bottom edge of
#   the M7 VSS stripe that crosses here (floorplan-deterministic, measured).
#   NEVER a bare `editDelete` (CLAUDE.md: it wipes every wire and special wire
#   in the design).  Global count guards before/after, FATAL before saveDesign.
#
# TIMING: the CPR6 in-flow "SI On" table read setup WNS -0.023 / TNS -0.024 over
# 2 reg2cgate paths at mcu0/hart0/tile/adddec0/gen_flash_clk.cg_flash/CG1, while
# the saved cut's report_timing read MET +0.024.  cpr7probe adjudicated that
# split on the restored DB (both views).  This script re-measures setup+hold on
# the repaired cut and RECORDS them; it runs NO optimisation (the ECO must not
# touch the signal netlist -- the gate-smoke reuse argument depends on netlist
# identity with the CPR6 cut).
#
# Run (one heavy run at a time):
#   cd ~/vestarv/innovus/common/MCU_castalia_penta && source ~/vestarv/cdspaths.sh
#   innovus -no_gui -batch -log log/MCU_castalia_penta_cpr7eco -overwrite \
#           -files tcl/MCU_castalia_penta_cpr7eco.tcl
################################################################################

source ../shared/constants.tcl
source ../shared/procedures.tcl

set DESIGN_NAME MCU_castalia_penta
set BASENAME    MCU_castalia_penta
set SRCCUT      ${BASENAME}.cpr6.signoff
set ECOCUT      ${BASENAME}.cpr7eco
set CPR7        ${BASENAME}.cpr7

# the riser, as MEASURED by cpr7probe on this DB
set RIS_X0 2354.670 ; set RIS_X1 2355.130
set RIS_Y0 1153.500 ; set RIS_Y1 1159.785
# new bottom edge = bottom of the crossing M7 VSS stripe (2318.0,1155.16)-(2355.55,1155.66)
set NEW_Y0 1155.160
# delete window: fully contains the riser and NOTHING else (the upper M4 pad
# reaches x 2355.53; editDelete/-area is whole-shape-contained)
set DELWIN [list 2354.500 1153.300 2355.200 1159.900]
# census window (bigger, for the before/after shape list)
set WIN    [list 2348.000 1148.000 2362.000 1164.000]

# expected pre-ECO census, measured by cpr7probe on cpr6.signoff
set EXP_INSTS  597243
set EXP_SWIRES 22728
set EXP_WIRES  1454254
set EXP_VSSSW  20797
set EXP_VDDSW  1931

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
            set lay "?" ; catch { set lay [dbGet $w.layer.name] }
            lappend out [list $w $lay $b]
        }
    }
    return $out
}
# re-queried from the net every time -- never from a saved pointer
proc __riser_alive {} {
    global RIS_X0 RIS_Y0 RIS_Y1 WIN
    foreach e [__in_win VSS $WIN] {
        if {[lindex $e 1] ne "M4"} { continue }
        lassign [lindex $e 2] x1 y1 x2 y2
        if {abs($x1 - $RIS_X0) < 0.01 && abs($y1 - $RIS_Y0) < 0.01 && abs($y2 - $RIS_Y1) < 0.01} { return 1 }
    }
    return 0
}
# is the TRIMMED riser present?
proc __trimmed_alive {} {
    global RIS_X0 NEW_Y0 RIS_Y1 WIN
    foreach e [__in_win VSS $WIN] {
        if {[lindex $e 1] ne "M4"} { continue }
        lassign [lindex $e 2] x1 y1 x2 y2
        if {abs($x1 - $RIS_X0) < 0.01 && abs($y1 - $NEW_Y0) < 0.01 && abs($y2 - $RIS_Y1) < 0.01} { return 1 }
    }
    return 0
}
proc __report_list {tag lst} {
    puts "### CPR7ECO ### $tag : [llength $lst] shape(s)"
    foreach e $lst {
        puts "### CPR7ECO ###    [lindex $e 0]  [lindex $e 1]  [lindex $e 2]"
    }
}
proc __wns {tag mode} {
    global REPORT_DIR BASENAME
    set f $REPORT_DIR/$BASENAME.cpr7eco.$tag.$mode.rpt
    setAnalysisMode -checkType $mode -skew false
    if {[catch {report_timing -nworst 10 > $f} e]} {
        puts "### CPR7ECO ### WARN report_timing($tag,$mode) failed: $e"
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
    puts "### CPR7ECO ### WNS($tag,$mode) = $wns   (from $f)"
    return $wns
}

################################################################################
# 0. restore the CPR6 signoff cut (COPY lineage: nothing is written back to it)
################################################################################
if {![file isdirectory $DATABASE_DIR/${SRCCUT}.innovus.dat]} {
    puts "### CPR7ECO ### FATAL: no $DATABASE_DIR/${SRCCUT}.innovus.dat"
    exit 1
}
restoreDesign $DATABASE_DIR/${SRCCUT}.innovus.dat $DESIGN_NAME
setCheckMode -tapeOut false

set BASE_INSTS  [__cnt top.insts.name]
set BASE_SWIRES [__cnt top.nets.sWires]
set BASE_WIRES  [__cnt top.nets.wires]
set VSS_SW0     [llength [dbGet [dbGet -p top.nets.name VSS].sWires]]
set VDD_SW0     [llength [dbGet [dbGet -p top.nets.name VDD].sWires]]
puts "### CPR7ECO ### restored cut  = $SRCCUT"
puts "### CPR7ECO ### restored census: insts $BASE_INSTS  sWires $BASE_SWIRES  wires $BASE_WIRES"
puts "### CPR7ECO ### VSS sWires $VSS_SW0   VDD sWires $VDD_SW0"
set fatal 0
if {$BASE_INSTS  != $EXP_INSTS}  { puts "### CPR7ECO ### FATAL: insts $BASE_INSTS != probe-measured $EXP_INSTS"   ; incr fatal }
if {$BASE_SWIRES != $EXP_SWIRES} { puts "### CPR7ECO ### FATAL: sWires $BASE_SWIRES != probe-measured $EXP_SWIRES" ; incr fatal }
if {$BASE_WIRES  != $EXP_WIRES}  { puts "### CPR7ECO ### FATAL: wires $BASE_WIRES != probe-measured $EXP_WIRES"   ; incr fatal }
if {$VSS_SW0     != $EXP_VSSSW}  { puts "### CPR7ECO ### FATAL: VSS sWires $VSS_SW0 != probe-measured $EXP_VSSSW" ; incr fatal }
if {$VDD_SW0     != $EXP_VDDSW}  { puts "### CPR7ECO ### FATAL: VDD sWires $VDD_SW0 != probe-measured $EXP_VDDSW" ; incr fatal }
if {$fatal} { puts "### CPR7ECO ### ABORT: this is not the DB the probe measured." ; exit 1 }
puts "### CPR7ECO ### restored-census identity with the probe: PASS"

################################################################################
# 1. PROVE the riser is there, exactly as measured, before touching anything
################################################################################
__report_list "VSS special shapes in window $WIN (before)" [__in_win VSS $WIN]
if {![__riser_alive]} {
    puts "### CPR7ECO ### FATAL: the M4 VSS riser ($RIS_X0,$RIS_Y0)-($RIS_X1,$RIS_Y1) is NOT in this DB."
    exit 1
}
puts "### CPR7ECO ### riser confirmed present"

################################################################################
# 2. Trim it: delete (selection-scoped, area-bounded) + add back the upper part
################################################################################
deselectAll
if {[catch {editSelect -type Special -layer M4 -area $DELWIN -nets VSS} e]} {
    puts "### CPR7ECO ### editSelect(Special,M4) rc!=0: $e"
}
if {[catch {editDelete -selected} e]} {
    puts "### CPR7ECO ### editDelete -selected rc!=0: $e"
}
deselectAll
set killed [expr {![__riser_alive]}]
puts "### CPR7ECO ### after attempt 1 (editSelect + editDelete -selected): killed=$killed"
if {!$killed} {
    if {[catch {editDelete -type Special -net VSS -layer M4 -area $DELWIN} e]} {
        puts "### CPR7ECO ### editDelete(-type Special -area) rc!=0: $e"
    }
    set killed [expr {![__riser_alive]}]
    puts "### CPR7ECO ### after attempt 2 (editDelete -type Special -net -layer -area): killed=$killed"
}

set D_INSTS  [__cnt top.insts.name]
set D_SWIRES [__cnt top.nets.sWires]
set D_WIRES  [__cnt top.nets.wires]
set VSS_SW1  [llength [dbGet [dbGet -p top.nets.name VSS].sWires]]
set VDD_SW1  [llength [dbGet [dbGet -p top.nets.name VDD].sWires]]
puts "### CPR7ECO ### post-delete census: insts $D_INSTS (base $BASE_INSTS)  sWires $D_SWIRES (base $BASE_SWIRES)  wires $D_WIRES (base $BASE_WIRES)"
puts "### CPR7ECO ### VSS sWires $VSS_SW1 (base $VSS_SW0)   VDD sWires $VDD_SW1 (base $VDD_SW0)"

set fatal 0
if {!$killed}                               { puts "### CPR7ECO ### FATAL: the riser survived every scoped delete." ; incr fatal }
if {$D_INSTS != $BASE_INSTS}                { puts "### CPR7ECO ### FATAL: instance count changed by the delete." ; incr fatal }
if {$D_WIRES != $BASE_WIRES}                { puts "### CPR7ECO ### FATAL: signal-wire count changed by the delete." ; incr fatal }
if {$VDD_SW1 != $VDD_SW0}                   { puts "### CPR7ECO ### FATAL: VDD special wires changed by a VSS-scoped delete." ; incr fatal }
if {$VSS_SW1 != [expr {$VSS_SW0 - 1}]}      { puts "### CPR7ECO ### FATAL: expected exactly ONE VSS special wire deleted (got [expr {$VSS_SW0 - $VSS_SW1}])." ; incr fatal }
if {$D_SWIRES != [expr {$BASE_SWIRES - 1}]} { puts "### CPR7ECO ### FATAL: expected exactly ONE special wire deleted design-wide (got [expr {$BASE_SWIRES - $D_SWIRES}])." ; incr fatal }
if {$fatal} {
    puts "### CPR7ECO ### ABORT before any saveDesign -- $fatal guard(s) tripped."
    exit 1
}

add_shape -net VSS -layer M4 -rect [list $RIS_X0 $NEW_Y0 $RIS_X1 $RIS_Y1] -shape STRIPE -status ROUTED
puts "### CPR7ECO ### trimmed riser added: M4 VSS ($RIS_X0,$NEW_Y0)-($RIS_X1,$RIS_Y1)"

set A_INSTS  [__cnt top.insts.name]
set A_SWIRES [__cnt top.nets.sWires]
set A_WIRES  [__cnt top.nets.wires]
set VSS_SW2  [llength [dbGet [dbGet -p top.nets.name VSS].sWires]]
puts "### CPR7ECO ### post-add census: insts $A_INSTS  sWires $A_SWIRES (base $BASE_SWIRES)  wires $A_WIRES  VSS sWires $VSS_SW2 (base $VSS_SW0)"
__report_list "VSS special shapes in window $WIN (after)" [__in_win VSS $WIN]

set fatal 0
if {$A_INSTS  != $BASE_INSTS}  { puts "### CPR7ECO ### FATAL: instance count moved during the repair." ; incr fatal }
if {$A_WIRES  != $BASE_WIRES}  { puts "### CPR7ECO ### FATAL: signal-wire count moved during the repair." ; incr fatal }
if {$A_SWIRES != $BASE_SWIRES} { puts "### CPR7ECO ### FATAL: special-wire count is not back to baseline after delete+add." ; incr fatal }
if {$VSS_SW2  != $VSS_SW0}     { puts "### CPR7ECO ### FATAL: VSS special-wire count is not back to baseline." ; incr fatal }
if {[__riser_alive]}           { puts "### CPR7ECO ### FATAL: the untrimmed riser is somehow back." ; incr fatal }
if {![__trimmed_alive]}        { puts "### CPR7ECO ### FATAL: the TRIMMED riser is not in the DB." ; incr fatal }
if {$fatal} {
    puts "### CPR7ECO ### ABORT before any saveDesign -- $fatal guard(s) tripped."
    exit 1
}
puts "### CPR7ECO ### stub repair GUARDS PASS"

################################################################################
# 3. Signoff verification on the repaired cut
################################################################################
verifyConnectivity -error 100000 -connectPadSpecialPorts \
    -report $REPORT_DIR/$BASENAME.cpr7.verifyConnectivity.rpt
verifyGeometry -antenna \
    -report $REPORT_DIR/$BASENAME.cpr7.verifyGeometry.rpt

################################################################################
# 4. Timing on the repaired cut, BOTH views, no optimisation
################################################################################
setAnalysisMode -analysisType onChipVariation -cppr both
setDelayCalMode -SIAware false
set WNS_NOSI_SETUP [__wns noSI setup]
set WNS_NOSI_HOLD  [__wns noSI hold]
setDelayCalMode -SIAware true
set WNS_SI_SETUP   [__wns SI setup]
set WNS_SI_HOLD    [__wns SI hold]
setDelayCalMode -SIAware false
timeDesign -postRoute -outDir $REPORT_DIR/$BASENAME.timeDesign.cpr7
catch { report_power -outfile $REPORT_DIR/${BASENAME}_cpr7_full.power }
reportGateCount -level 2 -outfile $REPORT_DIR/$BASENAME.reportGateCount.cpr7.rpt
summaryReport -noHtml -outfile $REPORT_DIR/$BASENAME.summaryReport.cpr7.rpt

################################################################################
# 5. Save the cut of record + stream the products
################################################################################
set F_INSTS  [__cnt top.insts.name]
set F_SWIRES [__cnt top.nets.sWires]
set F_WIRES  [__cnt top.nets.wires]
puts "### CPR7ECO ### final census: insts $F_INSTS  sWires $F_SWIRES  wires $F_WIRES"
if {$F_INSTS != $BASE_INSTS || $F_SWIRES != $BASE_SWIRES || $F_WIRES != $BASE_WIRES} {
    puts "### CPR7ECO ### FATAL: final census moved off baseline -- refusing to stream/save."
    exit 1
}

saveDesign $DATABASE_DIR/$ECOCUT.innovus -def -netlist -rc -tcon
puts "### CPR7ECO ### saved -> $DATABASE_DIR/$ECOCUT.innovus"

streamOut \
    $OUTPUT_DIR/$CPR7.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -merge [list ../hart_tile/out/hart_tile.gds2 \
                 /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/gds/tphn65gpgv2od3_sl_210a/mt_2/8lm/tphn65gpgv2od3_sl.gds] \
    -mapFile ../shared/innovus2gds.map
puts "### CPR7ECO ### streamOut -> $OUTPUT_DIR/$CPR7.gds2"

write_sdf $OUTPUT_DIR/$CPR7.sdf
saveNetlist $OUTPUT_DIR/$CPR7.xsim.v -excludeCellInst ANTENNA2A10TH
puts "### CPR7ECO ### SDF + sim netlist written ($CPR7.sdf / $CPR7.xsim.v)"
puts "### CPR7ECO ### TIMING noSI setup $WNS_NOSI_SETUP hold $WNS_NOSI_HOLD ; SI setup $WNS_SI_SETUP hold $WNS_SI_HOLD"
puts "### CPR7ECO ### DONE -- cut of record $ECOCUT"
exit
