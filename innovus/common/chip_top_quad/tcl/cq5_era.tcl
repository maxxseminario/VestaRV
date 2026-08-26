# CQ5: ERA static rail analysis on the ROUTED chip_top_quad signoff DB.
# Adapted from ~/vesta_docs/pg4_artifacts/pg4_era.tcl (license-free era_static).
# READ-ONLY. Run from ~/vestarv/innovus/common:
#   source cdspaths.sh && innovus -no_gui -batch -log log/cq5_era -files tcl/cq5_era.tcl
#
# Signoff corner is SS 0.9V -> set_pg_nets uses 0.9V (PG4 precedent). Voltage
# sources are placed on the actual VDD/VSS M7 core-ring legs (the ring lives in
# the tile-free CENTER BAND y~[1094,1599]; left/right legs only, top+bottom are
# skipped for the analog windows). Per-instance power comes from
# report_power -instances (the SRAMs dominate, leakage-heavy; the tiles enter as
# their macro current at the tile location). hart3 (R180, 5 VDD straps) IR drop
# is reported next to the other three tiles' from the analyze_rail results.
source ../shared/constants.tcl
source ../shared/procedures.tcl
set OUT rpt/cq5_era
file mkdir $OUT
setCheckMode -tapeOut false
restoreDesign $DATABASE_DIR/chip_top_quad.signoff.innovus.dat chip_top_quad
puts "CQ5ERA: restore done"

# --- per-instance power -> current file (I = P[mW]*1e-3 / 0.9V) ---
# Row format (report_power -instances): name f1 f2 int sw leak TOTAL pct cell.
set insts {mcu0/hart0 mcu0/hart1 mcu0/hart2 mcu0/hart3 mcu0/shbank0 mcu0/shbank1 mcu0/shbank2 mcu0/shbank3 mcu0/npuram0 mcu0/rom0}
catch {report_power -instances $insts -outfile $OUT/inst_power.rpt}
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
    incr ncur ; set totI [expr {$totI + $i}]
}
close $fin ; close $fout
puts "CQ5ERA: current file $ncur instances, total [format %.3f [expr {$totI*1e3}]] mA"

# --- voltage sources derived from the net's OWN M8 stripe centers (guaranteed
# on-metal; no *vsrc_diearea perimeter projection, which fails for this
# interior center-band ring). Emit the center point of the widest M8 sWires. ---
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
        if {[expr {$x1-$x0}] < 400} { continue } ;# only the wide band stripes
        # sample 3 points along each wide stripe (left / center / right)
        set yc [format %.1f [expr {($y0+$y1)/2.0}]]
        foreach fx {0.02 0.5 0.98} {
            lappend pts [list [format %.1f [expr {$x0 + $fx*($x1-$x0)}]] $yc]
        }
    }
    # WORKING PG4 format: "<name> <X> <Y> <LEF_layer>" (NOT *vsrc_diearea).
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
puts "CQ5ERA: voltage-source files written (VDD $nv pts, VSS $ns pts, M8 stripe centers)"

setMultiCpuUsage -localCpu 4
catch {set_rail_analysis_mode -method era_static -accuracy hd}
catch {set_pg_nets -net VDD -voltage 0.9 -threshold 0.873}
catch {set_pg_nets -net VSS -voltage 0.0 -threshold 0.027}
catch {set_power_data -reset}
set rc [catch {set_power_data -format ascii_current -scale 1.0 $OUT/vdd_current.txt} msg]
puts "CQ5ERA: power_data rc=$rc msg=[string range $msg 0 80]"
catch {set_power_pads -net VDD -format xy -file $OUT/vdd_pads.txt}
catch {set_power_pads -net VSS -format xy -file $OUT/vss_pads.txt}

set rc [catch {analyze_rail -type net -output $OUT/rail_out VDD} msg]
puts "CQ5ERA: analyze_rail VDD rc=$rc msg=[string range $msg 0 200]"
set rc [catch {analyze_rail -type net -output $OUT/rail_out VSS} msg]
puts "CQ5ERA: analyze_rail VSS rc=$rc msg=[string range $msg 0 200]"

# --- per-tile worst IR drop from the effective-voltage node map ---
# The ERA results are in $OUT/rail_out/<NET>_25C_avg_*/. We also print each
# tile bbox so a per-tile bin can be computed from the node map. Try the
# built-in region report first (wrapped in catch), then dump summaries.
foreach t {hart0 hart1 hart2 hart3} {
    set ip [dbGet -p top.insts.name mcu0/$t]
    set bb [dbGet $ip.box]
    if {[llength $bb]==1} { set bb [lindex $bb 0] }
    puts "CQ5ERA: tile $t bbox=$bb"
}
catch { report_rail -type worst -net VDD > $OUT/rail_worst_VDD.rpt ; puts "CQ5ERA: rail_worst_VDD written" }
catch { report_rail -type worst -net VSS > $OUT/rail_worst_VSS.rpt ; puts "CQ5ERA: rail_worst_VSS written" }
puts "CQ5ERA: done (NOTHING SAVED)"
exit
