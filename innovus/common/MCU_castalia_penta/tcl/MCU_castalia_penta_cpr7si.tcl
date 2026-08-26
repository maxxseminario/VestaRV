################################################################################
# CPR7 SI ADJUDICATION, PART 2 -- reproduce the in-flow coupled-RC state.
#
# PART 1 (tcl/MCU_castalia_penta_cpr7probe.tcl) showed that a plain restore of a
# saved cut gives an SI view that is MEANINGLESS:
#   log/MCU_castalia_penta_cpr7eco.log:
#     "#Finish writing rcdb with 772856 nodes, 685880 edges, and 0 xcaps"
#   log/MCU_castalia_penta_cpr7probe.log:
#     "WARN (IMPESI-2017): There is no coupling capacitance found in the design"
# i.e. `setExtractRCMode -coupled true` is NOT replayed by restoreDesign, so the
# first re-extraction in any post-hoc session writes a DECOUPLED rcdb and every
# subsequent `setDelayCalMode -SIAware true` number is computed with zero
# crosstalk.  The FLOW's own last extraction had 954,900 xcaps
# (log/MCU_castalia_penta.log:18569) -- that is the state in which the in-flow
# table read setup WNS -0.023 / TNS -0.024 over 2 reg2cgate paths at
# mcu0/hart0/tile/adddec0/gen_flash_clk.cg_flash/CG1.
#
# THIS SCRIPT rebuilds that state explicitly on the CPR7 cut of record:
#   setExtractRCMode -coupled true ; extractRC ; SIAware true ; timeDesign
# and reports the same numbers next to the decoupled view, so the CPR6 reading
# is either REPRODUCED or REFUTED with the instrument set the way the flow had
# it -- rather than declared a "phantom" by an instrument that cannot see it.
#
# READ-ONLY: no edits, no saveDesign, no streamOut.
#
# Run: cd ~/vestarv/innovus/common/MCU_castalia_penta && source ~/vestarv/cdspaths.sh
#      innovus -no_gui -batch -log log/MCU_castalia_penta_cpr7si -overwrite \
#              -files tcl/MCU_castalia_penta_cpr7si.tcl
################################################################################
source ../shared/constants.tcl
source ../shared/procedures.tcl

set BASENAME MCU_castalia_penta
set CUTDB    ${BASENAME}.cpr7eco

if {![file isdirectory $DATABASE_DIR/${CUTDB}.innovus.dat]} {
    puts "### CPR7SI ### FATAL: no $DATABASE_DIR/${CUTDB}.innovus.dat -- run the CPR7 ECO first"
    exit 1
}
setCheckMode -tapeOut false
restoreDesign $DATABASE_DIR/${CUTDB}.innovus.dat $BASENAME
setCheckMode -tapeOut false
puts "### CPR7SI ### restored cut = $CUTDB"

setAnalysisMode -analysisType onChipVariation -cppr both

################################################################################
# view A -- DECOUPLED extraction, SI off  (what a plain restore gives you)
################################################################################
puts "### CPR7SI ### ---- view A: extract DECOUPLED, SIAware false ----"
setExtractRCMode -engine postRoute -effortLevel medium -coupled false
extractRC
setDelayCalMode -SIAware false
timeDesign -postRoute -outDir $REPORT_DIR/$BASENAME.timeDesign.cpr7A_decoupled_noSI
setAnalysisMode -checkType setup -skew true
catch { report_timing -nworst 5 > $REPORT_DIR/$BASENAME.cpr7A.setup.rpt }
setAnalysisMode -checkType hold -skew true
catch { report_timing -nworst 5 > $REPORT_DIR/$BASENAME.cpr7A.hold.rpt }

################################################################################
# view B -- COUPLED extraction, SI ON  (the flow's own state, rebuilt)
################################################################################
# ORDER IS LOAD-BEARING: the extraction decides coupled-vs-decoupled from the
# delay-calc mode in force AT EXTRACTION TIME. Setting -coupled true but leaving
# SIAware false still writes an rcdb with 0 xcaps (that is exactly how the probe
# and the ECO sessions ended up with IMPESI-2017). SIAware FIRST, then extract.
puts "### CPR7SI ### ---- view B: SIAware true FIRST, then extract COUPLED ----"
setDelayCalMode -SIAware true
setExtractRCMode -engine postRoute -effortLevel medium -coupled true
extractRC
timeDesign -postRoute -si -outDir $REPORT_DIR/$BASENAME.timeDesign.cpr7B_coupled_SI
setAnalysisMode -checkType setup -skew true
catch { report_timing -nworst 8 > $REPORT_DIR/$BASENAME.cpr7B.setup.rpt }
setAnalysisMode -checkType hold -skew true
catch { report_timing -nworst 8 > $REPORT_DIR/$BASENAME.cpr7B.hold.rpt }
# the CPR6 in-flow endpoint, named explicitly
setAnalysisMode -checkType setup -skew true
catch { report_timing -through mcu0/hart0/tile/adddec0/gen_flash_clk.cg_flash/CG1/E \
        -nworst 4 > $REPORT_DIR/$BASENAME.cpr7B.cgflash.rpt }

puts "### CPR7SI ### DONE (nothing saved)"
exit
