# A7 Stage 3: ERA static rail analysis on the ROUTED chip_top_argus signoff.
# FIRST-EVER ERA rail pass on Argus. Adapted from tcl/cq5_era.tcl (CQ5) /
# ~/vesta_docs/pg4_artifacts/pg4_era.tcl (license-free era_static). READ-ONLY;
# writes nothing back to any Innovus DB.
# Run from ~/vestarv/innovus/common (ONE innovus job at a time):
#   source ~/vestarv/cdspaths.sh && innovus -no_gui -batch -log log/a7_era \
#       -files tcl/a7_era.tcl
#
# WHY FRESH-INIT + defIn (not restoreDesign): the signoff .dat carries
# `setCheckMode -tapeOut true`, which promotes the 13 timing-less cells (3 analog
# abstracts + 10 tphn pad cells) to a riCheckTimingLibrary FATAL DURING restore
# (eco4/eco5 war story: an in-session setCheckMode is too late). A FRESH
# init_design session NEVER runs that check (eco4's own finding), so we re-init
# from the SAME LEF/netlist/mmmc the flow used and defIn the routed DEF. No DB
# surgery, no checksum bypass, signoff DB untouched.
#
# CAVEAT (a7_architecture.md invariant 12): STATIC / LEAKAGE-driven estimate
# (era_static, avg). No switching VCD; per-instance current = report_power
# int+sw+leak / 0.9V. Signoff corner SS 0.9V. Voltage sources on the net's own
# WIDE M8 stripe centers (guaranteed on-metal), NOT *vsrc_diearea (which projects
# to the die perimeter and misses interior rings). set_power_pads -format xy rows
# = "name X Y LEF_layer"; set_power_data -format ascii_current = 3-column.
#
# Argus macros: 18 hardened tiles (mcu0/hart0..17, LEF leaves = ONE .iv row
# each), 8 shared-RAM banks (shbank0..7), 1 boot ROM (rom0). NO NPU (digital).
source ../shared/constants.tcl
source ../shared/procedures.tcl
set OUT rpt/a7_era
file mkdir $OUT

# ---- fresh init from the flow's exact inputs (byte-identical vars) ----
set init_verilog   "$INPUT_DIR/chip_top_argus.v ../MCU_ARGUS/in/MCU_ARGUS_hier.pnr.v"
set init_top_cell  chip_top
set init_pwr_net   VDD
set init_gnd_net   VSS
set init_mmmc_file "$SCRIPT_DIR/viewdefinition_chip_argus.tcl"
set IO_PAD_LEF "/opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef"
set init_lef_file "$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
                   $STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
                   $IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
                   $IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
                   $IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
                   $IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
                   $IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
                   ../hart_tile_argus/out/hart_tile_argus.lef \
                   $IO_PAD_LEF"
set init_design_uniquify 1
setCheckMode -tapeOut false
init_design
setDesignMode -process 65 -flowEffort standard -powerEffort low
setMultiCpuUsage -localCpu 4
setAnalysisMode -analysisType onChipVariation -cppr both
# routed physical from the signoff DEF (placement + signal + PG special routing)
defIn $DATABASE_DIR/chip_top_argus.signoff.innovus.dat/chip_top.def.gz
clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie
puts "A7ERA: init+defIn done"

# =====================================================================
# Stage-1 cross-check (this same session):
#   (a) 18/18 tile placement at frozen coords
#   (b) per-tile PG strap count = special-net M7 stripes crossing each tile
#       (all-R0 rows => uniform per column; CQ lesson: a placement change can
#        starve tiles of straps -- this is the ERA strap-count audit input).
# =====================================================================
proc _boxes_m7 {net} {
    set out {}
    set netp [dbGet -p top.nets.name $net]
    if {$netp eq "0x0" || $netp eq ""} { return $out }
    foreach w [dbGet $netp.sWires] {
        set l "?"; catch { set l [dbGet $w.layer.name] }
        if {$l ne "M7"} { continue }
        set b {}; catch { set b [dbGet $w.box] }
        if {[llength $b] == 1} { set b [lindex $b 0] }
        if {[llength $b] != 4} { continue }
        lappend out $b
    }
    return $out
}
set VDD_M7 [_boxes_m7 VDD]
set VSS_M7 [_boxes_m7 VSS]
puts "A7ERA: harvested M7 sWires VDD=[llength $VDD_M7] VSS=[llength $VSS_M7]"
proc _count_over {boxes bx0 by0 bx1 by1} {
    set n 0
    foreach b $boxes {
        lassign $b x0 y0 x1 y1
        if {$x0 < $bx1 && $x1 > $bx0 && $y0 < $by1 && $y1 > $by0} { incr n }
    }
    return $n
}
set fa [open $OUT/tile_placement_pg_audit.txt w]
puts $fa "# hart  x_llx  y_lly  orient  vddM7  vssM7  totalM7  (frozen x in {30 475 920 1365 1810 2255}, y in {565.085 1268.085 1971.085}, R0)"
for {set h 0} {$h < 18} {incr h} {
    set ip [dbGet -p top.insts.name mcu0/hart$h]
    set bb [dbGet $ip.box]
    if {[llength $bb]==1} { set bb [lindex $bb 0] }
    lassign $bb bx0 by0 bx1 by1
    set orient [dbGet $ip.orient]
    set nv [_count_over $VDD_M7 $bx0 $by0 $bx1 $by1]
    set ns [_count_over $VSS_M7 $bx0 $by0 $bx1 $by1]
    puts $fa [format "hart%-2d %9.3f %9.3f %-5s %5d %5d %5d" $h $bx0 $by0 $orient $nv $ns [expr {$nv+$ns}]]
}
close $fa
puts "A7ERA: tile placement + PG strap audit -> $OUT/tile_placement_pg_audit.txt"

# ---- per-instance power -> ascii_current file (I = P[mW]*1e-3 / 0.9V) ----
set insts {}
for {set h 0} {$h < 18} {incr h} { lappend insts mcu0/hart$h }
for {set b 0} {$b < 8}  {incr b} { lappend insts mcu0/shbank$b }
lappend insts mcu0/rom0
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
puts "A7ERA: current file $ncur instances, total [format %.3f [expr {$totI*1e3}]] mA"

# ---- voltage sources from the net's OWN wide M8 stripe centers ----
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
puts "A7ERA: voltage-source files written (VDD $nv pts, VSS $ns pts, M8 stripe centers)"

catch {set_rail_analysis_mode -method era_static -accuracy hd}
catch {set_pg_nets -net VDD -voltage 0.9 -threshold 0.873}
catch {set_pg_nets -net VSS -voltage 0.0 -threshold 0.027}
catch {set_power_data -reset}
set rc [catch {set_power_data -format ascii_current -scale 1.0 $OUT/vdd_current.txt} msg]
puts "A7ERA: power_data rc=$rc msg=[string range $msg 0 80]"
catch {set_power_pads -net VDD -format xy -file $OUT/vdd_pads.txt}
catch {set_power_pads -net VSS -format xy -file $OUT/vss_pads.txt}

set rc [catch {analyze_rail -type net -output $OUT/rail_out VDD} msg]
puts "A7ERA: analyze_rail VDD rc=$rc msg=[string range $msg 0 200]"
set rc [catch {analyze_rail -type net -output $OUT/rail_out VSS} msg]
puts "A7ERA: analyze_rail VSS rc=$rc msg=[string range $msg 0 200]"

catch { report_rail -type worst -net VDD > $OUT/rail_worst_VDD.rpt ; puts "A7ERA: rail_worst_VDD written" }
catch { report_rail -type worst -net VSS > $OUT/rail_worst_VSS.rpt ; puts "A7ERA: rail_worst_VSS written" }
puts "A7ERA: done (NOTHING SAVED)"
exit
