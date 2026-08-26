################################################################################
# CP5 closure ECO -- STAGE B (setup recovery), restarted from stage A.
#
# WHY A SEPARATE SCRIPT: the first pass (tcl/MCU_castalia_penta_cp5eco.tcl) got
# through the stub repair (stage A saved) and through
# `optDesign -postRoute -setup -incr`, which CLOSED the 3 clock-gating
# violations (WNS +0.054, TNS 0.000, 0 violating paths, DRVs 0, density
# 9.397%), and then the innovus process exited rc=1 with no error, no crash
# signature and no further .cmd entry -- i.e. it died at the end of that
# optDesign, before the hold pass. Nothing was lost (stage A is on disk) and
# nothing was corrupted (the exit happened between commands).
#
# This script therefore replays ONLY the timing half, from the stage-A DB, and
# SAVES EARLY: DB first, then hold work, then outputs -- so a repeat of the
# same exit cannot cost the recovered setup slack.
#
#   dbs/MCU_castalia_penta.cp5eco.innovus          stage B DB
#   out/MCU_castalia_penta.cp5.{gds2,sdf,xsim.v}   cut-of-record products
#
# ACCEPTANCE (unchanged): setup WNS >= 0 AND hold clean AND DRVs 0, measured in
# ONE view in ONE session (the flow's `timeDesign -si -signoff` Quantus is
# broken install-wide -- never compare across views/cuts).
#
# Run: cd ~/vestarv/innovus/common/MCU_castalia_penta && source ~/vestarv/cdspaths.sh
#      innovus -no_gui -batch -log log/MCU_castalia_penta_cp5ecoB -overwrite \
#              -files tcl/MCU_castalia_penta_cp5ecoB.tcl
################################################################################

source ../shared/constants.tcl
source ../shared/procedures.tcl

set DESIGN_NAME MCU_castalia_penta
set BASENAME    MCU_castalia_penta
set ECOA        ${BASENAME}.cp5eco_a
set ECOB        ${BASENAME}.cp5eco
set CP5         ${BASENAME}.cp5

proc __cnt {path} {
    set r [dbGet $path -e]
    if {$r eq "0x0" || $r eq ""} { return 0 }
    return [llength $r]
}

proc __wns {tag mode} {
    global REPORT_DIR BASENAME
    set f $REPORT_DIR/$BASENAME.cp5ecoB.$tag.$mode.rpt
    setAnalysisMode -checkType $mode -skew false
    if {[catch {report_timing -nworst 10 > $f} e]} {
        puts "### CP5ECOB ### WARN report_timing($tag,$mode) failed: $e"
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
    puts "### CP5ECOB ### WNS($tag,$mode) = $wns   (from $f)"
    return $wns
}

restoreDesign $DATABASE_DIR/$ECOA.innovus.dat $DESIGN_NAME
setCheckMode -tapeOut false
setAnalysisMode -analysisType onChipVariation -cppr both
setDelayCalMode -SIAware false

set A_INSTS  [__cnt top.insts.name]
set A_SWIRES [__cnt top.nets.sWires]
set A_WIRES  [__cnt top.nets.wires]
puts "### CP5ECOB ### stage A census: insts $A_INSTS  sWires $A_SWIRES  wires $A_WIRES"
if {$A_INSTS == 0 || $A_SWIRES == 0 || $A_WIRES == 0} {
    puts "### CP5ECOB ### FATAL: stage-A database is empty/gutted."
    exit 1
}

# A-side reference numbers, same instrument, same session
set WNS_A_SETUP [__wns A setup]
set WNS_A_HOLD  [__wns A hold]
if {$WNS_A_SETUP > -0.010} {
    puts "### CP5ECOB ### FATAL: stage-A setup WNS $WNS_A_SETUP does not show the known"
    puts "### CP5ECOB ###        CP4b clock-gating violation -- instrument not sensitive; stopping."
    exit 1
}
timeDesign -postRoute -outDir $REPORT_DIR/$BASENAME.timeDesign.cp5A

################################################################################
# the one bounded attempt
################################################################################
catch { setOptMode -usefulSkew true }
catch { setOptMode -usefulSkewPostRoute true }
if {[catch {optDesign -postRoute -setup -incr} e]} {
    puts "### CP5ECOB ### optDesign -postRoute -setup -incr rc!=0: $e"
}
set B_INSTS  [__cnt top.insts.name]
set B_SWIRES [__cnt top.nets.sWires]
set B_WIRES  [__cnt top.nets.wires]
puts "### CP5ECOB ### post-opt census: insts $B_INSTS (A $A_INSTS)  sWires $B_SWIRES (A $A_SWIRES)  wires $B_WIRES (A $A_WIRES)"
if {$B_INSTS == 0 || $B_SWIRES < [expr {$A_SWIRES / 2}] || $B_WIRES == 0} {
    puts "### CP5ECOB ### FATAL: census collapsed after optDesign -- refusing to save."
    exit 1
}
set WNS_B_SETUP [__wns B setup]
set WNS_B_HOLD  [__wns B hold]

# SAVE EARLY (the first pass died right about here)
saveDesign $DATABASE_DIR/$ECOB.innovus -def -netlist -rc -tcon
puts "### CP5ECOB ### stage B DB saved -> $DATABASE_DIR/$ECOB.innovus"

# hold repair only if this view says hold degraded below stage A
if {$WNS_B_HOLD < 0.0 && $WNS_B_HOLD < $WNS_A_HOLD} {
    puts "### CP5ECOB ### hold degraded vs stage A -- running one hold pass"
    setDelayCalMode -SIAware true
    setOptMode -holdTargetSlack 0.01
    if {[catch {optDesign -postRoute -hold -incr} e]} {
        puts "### CP5ECOB ### optDesign -postRoute -hold -incr rc!=0: $e"
    }
    setOptMode -holdTargetSlack 0
    setDelayCalMode -SIAware false
    set WNS_B_SETUP [__wns B2 setup]
    set WNS_B_HOLD  [__wns B2 hold]
    saveDesign $DATABASE_DIR/$ECOB.innovus -def -netlist -rc -tcon
    puts "### CP5ECOB ### stage B DB re-saved after the hold pass"
} else {
    puts "### CP5ECOB ### hold not degraded vs stage A ($WNS_B_HOLD vs $WNS_A_HOLD) -- no hold pass"
}

timeDesign -postRoute -outDir $REPORT_DIR/$BASENAME.timeDesign.cp5B
puts "### CP5ECOB ### A: setup $WNS_A_SETUP hold $WNS_A_HOLD   B: setup $WNS_B_SETUP hold $WNS_B_HOLD"

################################################################################
# signoff checks + cut-of-record outputs
################################################################################
verifyConnectivity -error 100000 -connectPadSpecialPorts \
    -report $REPORT_DIR/$BASENAME.verifyConnectivity.cp5.rpt
verifyGeometry -antenna \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.cp5.rpt
catch { report_power -outfile $REPORT_DIR/${BASENAME}_cp5_full.power }
reportGateCount -level 2 -outfile $REPORT_DIR/$BASENAME.reportGateCount.cp5.rpt
summaryReport -noHtml -outfile $REPORT_DIR/$BASENAME.summaryReport.cp5.rpt

set F_INSTS  [__cnt top.insts.name]
set F_SWIRES [__cnt top.nets.sWires]
set F_WIRES  [__cnt top.nets.wires]
puts "### CP5ECOB ### final census: insts $F_INSTS  sWires $F_SWIRES  wires $F_WIRES"
if {$F_INSTS == 0 || $F_SWIRES < [expr {$A_SWIRES / 2}] || $F_WIRES == 0} {
    puts "### CP5ECOB ### FATAL: final census collapsed -- refusing to stream."
    exit 1
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
puts "### CP5ECOB ### streamOut -> $OUTPUT_DIR/$CP5.gds2"

write_sdf $OUTPUT_DIR/$CP5.sdf
saveNetlist $OUTPUT_DIR/$CP5.xsim.v -excludeCellInst ANTENNA2A10TH
puts "### CP5ECOB ### SDF + sim netlist written"
puts "### CP5ECOB ### DONE"
exit
