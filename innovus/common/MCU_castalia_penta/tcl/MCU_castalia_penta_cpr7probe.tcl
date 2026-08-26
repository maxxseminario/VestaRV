################################################################################
# CPR7 PROBE + SI ADJUDICATION -- READ-ONLY on the CPR6 cut of record.
#
# Two jobs, one restore:
#  (a) MEASURE the object behind vG "ANTENNA: Special Wire of Net VSS (M4)
#      Bounds (2354.899,1153.500)(2354.900,1153.500)" -- the CP5 forensics say
#      it is a 0.46 x 6.285 um M4 VSS riser (2354.670,1153.500)-(2355.130,
#      1159.785) whose lower TAIL hangs free below the VIA landing pad; the
#      repair trims the tail back to the crossing M7 VSS stripe.  NOTHING is
#      assumed here: the window is dumped shape-by-shape (M4 + M7 + vias) so
#      the CPR7 ECO can be written against MEASURED coordinates.
#  (b) ADJUDICATE the CPR6 SI-view split: the in-flow "Signoff Settings: SI On"
#      table read setup WNS -0.023 / TNS -0.024 / 2 reg2cgate paths at
#      mcu0/hart0/tile/adddec0/gen_flash_clk.cg_flash/CG1, while the saved
#      cut's report_timing read MET +0.024.  Report BOTH views on the RESTORED
#      database (CP5 method: compare within one view, never across).
#
# READ-ONLY: no edits, no saveDesign, no streamOut.
#
# Run: cd ~/vestarv/innovus/common/MCU_castalia_penta && source ~/vestarv/cdspaths.sh
#      innovus -no_gui -batch -log log/MCU_castalia_penta_cpr7probe -overwrite \
#              -files tcl/MCU_castalia_penta_cpr7probe.tcl
################################################################################
source ../shared/constants.tcl
source ../shared/procedures.tcl

set DESIGN_NAME MCU_castalia_penta
set BASENAME    MCU_castalia_penta
set CUTDB       ${BASENAME}.cpr6.signoff

if {![file isdirectory $DATABASE_DIR/${CUTDB}.innovus.dat]} {
    puts "### CPR7P ### FATAL: no $DATABASE_DIR/${CUTDB}.innovus.dat"
    exit 1
}
restoreDesign $DATABASE_DIR/${CUTDB}.innovus.dat $DESIGN_NAME
setCheckMode -tapeOut false
puts "### CPR7P ### restored cut = $CUTDB"

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

set BASE_INSTS  [__cnt top.insts.name]
set BASE_SWIRES [__cnt top.nets.sWires]
set BASE_WIRES  [__cnt top.nets.wires]
set VSS_SW0     [llength [dbGet [dbGet -p top.nets.name VSS].sWires]]
set VDD_SW0     [llength [dbGet [dbGet -p top.nets.name VDD].sWires]]
puts "### CPR7P ### census: insts $BASE_INSTS  sWires $BASE_SWIRES  wires $BASE_WIRES"
puts "### CPR7P ### VSS sWires $VSS_SW0   VDD sWires $VDD_SW0"

################################################################################
# (a) the antenna window
################################################################################
set WIN [list 2348.000 1148.000 2362.000 1164.000]
lassign $WIN wx0 wy0 wx1 wy1

foreach net {VSS VDD} {
    set netp [dbGet -p top.nets.name $net]
    if {$netp eq "0x0" || $netp eq ""} { continue }
    set n 0
    foreach w [dbGet $netp.sWires] {
        set b [__box $w]
        if {[llength $b] != 4} { continue }
        lassign $b x1 y1 x2 y2
        if {$x1 <= $wx1 && $wx0 <= $x2 && $y1 <= $wy1 && $wy0 <= $y2} {
            set lay "?" ; catch { set lay [dbGet $w.layer.name] }
            set sh  "?" ; catch { set sh  [dbGet $w.shape] }
            set st  "?" ; catch { set st  [dbGet $w.status] }
            puts [format "### CPR7P ### SW %s %-4s %-10s %-8s (%.3f,%.3f)-(%.3f,%.3f)  w=%.3f h=%.3f  ptr=%s" \
                  $net $lay $sh $st $x1 $y1 $x2 $y2 [expr {$x2-$x1}] [expr {$y2-$y1}] $w]
            incr n
        }
    }
    puts "### CPR7P ### $net special shapes in window: $n"
}

# special vias in the window (the VIA structs that land on the riser)
set nv 0
foreach net {VSS VDD} {
    set netp [dbGet -p top.nets.name $net]
    if {$netp eq "0x0" || $netp eq ""} { continue }
    foreach v [dbGet $netp.sVias -e] {
        if {$v eq "0x0"} { continue }
        set xx 0 ; set yy 0
        catch { set xx [dbGet $v.x] }
        catch { set yy [dbGet $v.y] }
        if {$xx >= $wx0 && $xx <= $wx1 && $yy >= $wy0 && $yy <= $wy1} {
            set vn "?" ; catch { set vn [dbGet $v.via.name] }
            puts [format "### CPR7P ### SVIA %s %s at (%.3f,%.3f)" $net $vn $xx $yy]
            incr nv
        }
    }
}
puts "### CPR7P ### special vias in window: $nv"

# what does the macro/inst neighbourhood look like (the orch TCM SW corner)?
foreach ip [dbGet -p top.insts.name mcu0/hart0/tile/ram0* -e] {
    if {$ip eq "0x0" || $ip eq ""} { continue }
    puts "### CPR7P ### inst [dbGet $ip.name] box [join [dbGet $ip.box]] orient [dbGet $ip.orient]"
}

################################################################################
# (b) SI adjudication -- both views on THIS restored database
################################################################################
setAnalysisMode -analysisType onChipVariation -cppr both

puts "### CPR7P ### ---- view 1: SIAware FALSE ----"
setDelayCalMode -SIAware false
setAnalysisMode -checkType setup -skew true
catch { report_timing -nworst 8 > $REPORT_DIR/$BASENAME.cpr7_noSI.setup.rpt }
setAnalysisMode -checkType hold -skew true
catch { report_timing -nworst 8 > $REPORT_DIR/$BASENAME.cpr7_noSI.hold.rpt }
timeDesign -postRoute -outDir $REPORT_DIR/$BASENAME.timeDesign.cpr7_noSI

puts "### CPR7P ### ---- view 2: SIAware TRUE (the in-flow 'SI On' view) ----"
setDelayCalMode -SIAware true
setAnalysisMode -checkType setup -skew true
catch { report_timing -nworst 8 > $REPORT_DIR/$BASENAME.cpr7_SI.setup.rpt }
setAnalysisMode -checkType hold -skew true
catch { report_timing -nworst 8 > $REPORT_DIR/$BASENAME.cpr7_SI.hold.rpt }
timeDesign -postRoute -si -outDir $REPORT_DIR/$BASENAME.timeDesign.cpr7_SI

# name the CPR6 in-flow endpoint explicitly, in the SI view
setAnalysisMode -checkType setup -skew true
catch { report_timing -through mcu0/hart0/tile/adddec0/gen_flash_clk.cg_flash/CG1/E \
        -nworst 4 > $REPORT_DIR/$BASENAME.cpr7_SI.cgflash.rpt }

puts "### CPR7P ### DONE (nothing saved)"
exit
