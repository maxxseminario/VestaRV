################################################################################
# CP5 timing verification on the cut of record, IN THE SAME VIEW CP4b USED.
#
# WHY THIS EXISTS: the CP4b residual (-0.021 ns setup / +0.011 ns hold, 3
# violating clock-gating paths) came from optDesign's SI-AWARE summary
# ("Signoff Settings: SI On"). The CP5 ECO session ran with
# `setDelayCalMode -SIAware false`, and in THAT view the same database reports
# WNS +0.054 / TNS 0.000 / 0 violating paths BEFORE any optimisation -- so
# `optDesign -postRoute -setup` correctly found nothing to do, and the ECO is a
# no-op on logic. Comparing those two numbers as if they were the same check is
# exactly the "compare within one view, never across" trap.
#
# This script restores the cut of record and reports BOTH views on it:
#   rpt/<base>.timeDesign.cp5_noSI   SIAware false  (the ECO session's view)
#   rpt/<base>.timeDesign.cp5_SI     SIAware true   (the CP4b view)
# READ-ONLY: no edits, no saveDesign, no streamOut.
#
# Run: cd ~/vestarv/innovus/common/MCU_castalia_penta && source ~/vestarv/cdspaths.sh
#      innovus -no_gui -batch -log log/MCU_castalia_penta_cp5timing -overwrite \
#              -files tcl/MCU_castalia_penta_cp5timing.tcl
################################################################################
source ../shared/constants.tcl
source ../shared/procedures.tcl

set BASENAME MCU_castalia_penta

set CUTDB ""
foreach __c [list ${BASENAME}.cp5eco ${BASENAME}.cp5eco_a] {
    if {[file isdirectory "$DATABASE_DIR/${__c}.innovus.dat"]} { set CUTDB $__c ; break }
}
if {$CUTDB eq ""} { puts "CP5TIM: FATAL: no CP5 ECO DB in $DATABASE_DIR" ; exit 1 }
restoreDesign $DATABASE_DIR/${CUTDB}.innovus.dat $BASENAME
setCheckMode -tapeOut false
puts "### CP5TIM ### cut of record = $CUTDB"

setAnalysisMode -analysisType onChipVariation -cppr both

puts "### CP5TIM ### ---- view 1: SIAware FALSE (the CP5 ECO session's view) ----"
setDelayCalMode -SIAware false
timeDesign -postRoute -outDir $REPORT_DIR/$BASENAME.timeDesign.cp5_noSI

puts "### CP5TIM ### ---- view 2: SIAware TRUE (the CP4b view: 'SI On') ----"
setDelayCalMode -SIAware true
timeDesign -postRoute -si -outDir $REPORT_DIR/$BASENAME.timeDesign.cp5_SI

# the three CP4b endpoints, named explicitly, in the SI view
setAnalysisMode -checkType setup -skew true
catch { report_timing -nworst 5 > $REPORT_DIR/$BASENAME.cp5_SI.setup.rpt }
setAnalysisMode -checkType hold -skew true
catch { report_timing -nworst 5 > $REPORT_DIR/$BASENAME.cp5_SI.hold.rpt }
puts "### CP5TIM ### done (nothing saved)"
exit
