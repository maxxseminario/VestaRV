# CPR7: ERA static rail analysis on the CPR7 cut-of-record DB (Castalia-Penta).
# READ-ONLY (restores, analyses, saves NOTHING).
#
# Adapted from ../chip_top_quad/tcl/cq5_era.tcl (the license-free era_static
# recipe). DELTAS:
#   * design/DB: the CPR7 ECO cut (dbs/MCU_castalia_penta.cpr7eco{,_a}.innovus.dat),
#     selected the same way the LVS collateral selects it;
#   * cq5's HARDCODED 4-element hart list is extended to the orchestrator's
#     region: after the CPR3 RENUMBER the SOFT hart is mcu0/hart0 (CP5 called
#     the same object hart4) and the four HARDENED tiles are mcu0/hart1..hart4.
#     mcu0/hart0 covers the orchestrator's whole subtree -- its std cells in the
#     right-band flank AND its 16 KiB TCM mcu0/hart0/tile/ram0, which is why
#     ram0 is NOT listed separately: report_power -instances on the parent
#     already contains it, and listing both would double-count the current;
#   * setCheckMode -tapeOut false BEFORE restoreDesign (3 analog macros have no
#     .lib timing -- a tape-out-mode restore FATALs);
#   * voltage sources come from the net's OWN wide M8 band stripes (never
#     *vsrc_diearea), unchanged from cq5.
#
# Run: cd ~/vestarv/innovus/common/MCU_castalia_penta && source ~/vestarv/cdspaths.sh
#      innovus -no_gui -batch -log log/cpr7_era -overwrite -files tcl/cpr7_era.tcl
source ../shared/constants.tcl
source ../shared/procedures.tcl

set BASENAME MCU_castalia_penta
set OUT rpt/${BASENAME}_cpr7_era
file mkdir $OUT
setCheckMode -tapeOut false

set CUTDB ""
foreach __c [list ${BASENAME}.cpr7eco] {
    if {[file isdirectory "$DATABASE_DIR/${__c}.innovus.dat"]} { set CUTDB $__c ; break }
}
if {$CUTDB eq ""} { puts "CPR7ERA: FATAL: no CPR7 ECO DB in $DATABASE_DIR" ; exit 1 }
restoreDesign $DATABASE_DIR/${CUTDB}.innovus.dat $BASENAME
puts "CPR7ERA: restore done (cut = $CUTDB)"
setCheckMode -tapeOut false

# --- per-instance power -> current file (I = P[mW]*1e-3 / 0.9V) ---
set insts {mcu0/hart0 mcu0/hart1 mcu0/hart2 mcu0/hart3 mcu0/hart4
           mcu0/shbank0 mcu0/shbank1 mcu0/shbank2 mcu0/shbank3
           mcu0/npuram0 mcu0/rom0}
catch {report_power -instances $insts -outfile $OUT/inst_power.rpt}
catch {report_power -outfile $OUT/power_all.rpt}
array set want {}
foreach i $insts { set want($i) 1 }
set fin  [open $OUT/inst_power.rpt r]
set fout [open $OUT/vdd_current.txt w]
set ncur 0 ; set totI 0.0
while {[gets $fin ln] >= 0} {
    set f [regexp -all -inline {\S+} $ln]
    if {[llength $f] < 8} { continue }
    set nm [lindex $f 0]
    if {![info exists want($nm)]} { continue }
    set ptot [lindex $f 6]
    if {![string is double -strict $ptot]} { continue }
    set i [expr {$ptot * 1e-3 / 0.9}]
    puts $fout "$nm $i VDD"
    puts "CPR7ERA: inst_power  $nm  P=$ptot mW  I=[format %.4g $i] A"
    incr ncur ; set totI [expr {$totI + $i}]
}
close $fin ; close $fout
puts "CPR7ERA: current file $ncur instances, total [format %.3f [expr {$totI*1e3}]] mA"
if {$ncur == 0} {
    puts "CPR7ERA: FATAL: no instance rows parsed -- the rail run would be meaningless."
    exit 1
}

proc write_srcs {net fname} {
    set netp [dbGet -p top.nets.name $net]
    set pts {}
    foreach w [dbGet $netp.sWires] {
        set l "?"; catch { set l [dbGet $w.layer.name] }
        if {$l ne "M8"} { continue }
        set b {}; catch { set b [dbGet $w.box] }
        if {[llength $b] == 1} { set b [lindex $b 0] }
        if {[llength $b] != 4} { continue }
        lassign $b x0 y0 x1 y1
        if {[expr {$x1-$x0}] < 400} { continue }
        set yc [format %.1f [expr {($y0+$y1)/2.0}]]
        foreach fx {0.02 0.5 0.98} {
            lappend pts [list [format %.1f [expr {$x0 + $fx*($x1-$x0)}]] $yc]
        }
    }
    set fh [open $fname w]
    puts $fh "* XY power pad location file -- net $net (M8 stripe taps)"
    puts $fh "* vsrc_name X(um) Y(um) LEF_layer"
    set k 0
    foreach p $pts { puts $fh "${net}P$k [lindex $p 0] [lindex $p 1] M8" ; incr k }
    close $fh
    return [llength $pts]
}
set nv [write_srcs VDD $OUT/vdd_pads.txt]
set ns [write_srcs VSS $OUT/vss_pads.txt]
puts "CPR7ERA: voltage-source files written (VDD $nv pts, VSS $ns pts, M8 stripe centers)"
if {$nv == 0 || $ns == 0} {
    puts "CPR7ERA: FATAL: no wide M8 band stripes found for a net -- sources would be empty."
    exit 1
}

setMultiCpuUsage -localCpu 4
catch {set_rail_analysis_mode -method era_static -accuracy hd}
catch {set_pg_nets -net VDD -voltage 0.9 -threshold 0.873}
catch {set_pg_nets -net VSS -voltage 0.0 -threshold 0.027}
catch {set_power_data -reset}
set rc [catch {set_power_data -format ascii_current -scale 1.0 $OUT/vdd_current.txt} msg]
puts "CPR7ERA: power_data rc=$rc msg=[string range $msg 0 80]"
catch {set_power_pads -net VDD -format xy -file $OUT/vdd_pads.txt}
catch {set_power_pads -net VSS -format xy -file $OUT/vss_pads.txt}

set rc [catch {analyze_rail -type net -output $OUT/rail_out VDD} msg]
puts "CPR7ERA: analyze_rail VDD rc=$rc msg=[string range $msg 0 200]"
set rc [catch {analyze_rail -type net -output $OUT/rail_out VSS} msg]
puts "CPR7ERA: analyze_rail VSS rc=$rc msg=[string range $msg 0 200]"

foreach t {hart0 hart1 hart2 hart3 hart4} {
    set ip [dbGet -p top.insts.name mcu0/$t -e]
    if {$ip eq "0x0" || $ip eq ""} {
        # hart0 is a MODULE (soft), not a placed instance -- report its TCM box
        set ip [dbGet -p top.insts.name mcu0/$t/tile/ram0 -e]
        if {$ip eq "0x0" || $ip eq ""} { puts "CPR7ERA: $t : no placed instance (soft module)" ; continue }
        set bb [dbGet $ip.box]
        if {[llength $bb]==1} { set bb [lindex $bb 0] }
        puts "CPR7ERA: $t (soft) TCM bbox=$bb"
        continue
    }
    set bb [dbGet $ip.box]
    if {[llength $bb]==1} { set bb [lindex $bb 0] }
    puts "CPR7ERA: tile $t bbox=$bb"
}
catch { report_rail -type worst -net VDD > $OUT/rail_worst_VDD.rpt ; puts "CPR7ERA: rail_worst_VDD written" }
catch { report_rail -type worst -net VSS > $OUT/rail_worst_VSS.rpt ; puts "CPR7ERA: rail_worst_VSS written" }
puts "CPR7ERA: done (NOTHING SAVED)"
exit
