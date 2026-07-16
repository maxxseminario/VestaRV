# CQ5 ERA probe: restore routed DB, characterize the VDD/VSS ring sWires (to
# place voltage sources) and the per-instance power report format. Diagnostic
# only, nothing saved.
source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl
setCheckMode -tapeOut false
restoreDesign $DATABASE_DIR/chip_top_quad.signoff.innovus.dat chip_top_quad
set OUT rpt/cq5_era
file mkdir $OUT

# --- VDD ring sWire geometry: layer + box for the widest/edge wires ---
foreach net {VDD VSS} {
    set netp [dbGet -p top.nets.name $net]
    set fh [open $OUT/${net}_swires.txt w]
    set nn 0
    foreach w [dbGet $netp.sWires] {
        set l "?"; catch { set l [dbGet $w.layer.name] }
        set b {}; catch { set b [dbGet $w.box] }
        if {[llength $b] == 1} { set b [lindex $b 0] }
        if {[llength $b] != 4} { continue }
        lassign $b x0 y0 x1 y1
        puts $fh "$l $x0 $y0 $x1 $y1"
        incr nn
    }
    close $fh
    puts "### PROBE ### $net sWires=$nn -> $OUT/${net}_swires.txt"
}

# --- per-instance power for the top-level macros/blocks ---
set insts {mcu0/hart0 mcu0/hart1 mcu0/hart2 mcu0/hart3 mcu0/shbank0 mcu0/shbank1 mcu0/shbank2 mcu0/shbank3 mcu0/npuram0 mcu0/rom0}
set rc [catch {report_power -instances $insts -outfile $OUT/inst_power.rpt} msg]
puts "### PROBE ### report_power -instances rc=$rc msg=[string range $msg 0 80]"
exit
