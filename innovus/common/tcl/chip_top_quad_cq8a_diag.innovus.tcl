################################################################################
# CQ8a diagnostic: restore the CQ5/CQ6 routed signoff DB and REPORT the exact
# geometry (net, layer, floating status) at the five CQ6 DRC sites + the M7.S.4
# notch-floor weld line. Read-only: no edits, no save. Informs the ECO flow.
# usage (from innovus/common):
#   innovus -no_gui -batch -files tcl/chip_top_quad_cq8a_diag.innovus.tcl
################################################################################
set restore_db_file_check 0
setCheckMode -tapeOut false
restoreDesign dbs/chip_top_quad.signoff.innovus.dat chip_top_quad

proc boxof {p} {
    set b [dbGet $p.box]
    if {[llength $b]==1} { set b [lindex $b 0] }
    return $b
}
proc probe {name x0 y0 x1 y1} {
    puts "======== PROBE $name  win ($x0,$y0)-($x1,$y1) ========"
    set res {}
    catch { set res [dbQuery -area [list $x0 $y0 $x1 $y1] -objType {sWire wire via sViaInst viaInst}] }
    if {$res eq "" || $res eq "0x0"} {
        catch { set res [dbQuery -area [list $x0 $y0 $x1 $y1]] }
    }
    set nshown 0
    foreach p $res {
        if {$nshown > 40} { puts "   ...more..."; break }
        set ot "?"; catch { set ot [dbGet $p.objType] }
        set lay "?"; catch { set lay [dbGet $p.layer.name] }
        set net "?"; catch { set net [dbGet $p.net.name] }
        if {$net eq "0x0" || $net eq ""} { catch { set net [dbGet $p.sNet.name] } }
        set fl ""; catch { if {[dbGet $p.isFloating] eq "1"} { set fl " FLOATING" } }
        set bb [boxof $p]
        # only show routing-ish objs on metal/via layers
        if {[regexp {^(M[1-8]|VIA[1-7]|sWire|wire|via)} $ot$lay] || [string match "M*" $lay] || [string match "VIA*" $lay]} {
            puts "   $ot net=$net lay=$lay box=$bb$fl"
            incr nshown
        }
    }
    if {$nshown==0} { puts "   (nothing metal/via matched; raw count=[llength $res])" }
}

probe VIA7.W.1_s1  2162 1044 2167 1049
probe VIA7.W.1_s2  2162 1641 2167 1646
probe M7.S.3       352  1240 360  1262
probe M3.S.2_s1    1008 892  1017 899
probe M3.S.2_s2    1156 1028 1164 1035
probe M5.S.2       1009 932  1016 939
probe DM2.S.2_s1   933  1074 938  1080
probe DM2.S.2_s2   1033 1074 1038 1080
probe M7.S.4_weld  60   1062 630  1066

# Floating-stripe census in the center band + notch-floor bands (PG hygiene).
puts "======== FLOATING special-wire census ========"
foreach net {VDD VSS} {
    set netp [dbGet -p top.nets.name $net]
    set fcount 0
    catch {
        foreach w [dbGet $netp.sWires] {
            set isf 0; catch { set isf [dbGet $w.isFloating] }
            if {$isf eq "1"} { incr fcount }
        }
    }
    puts "   net $net floating sWires = $fcount"
}
puts "### CQ8a DIAG DONE ###"
exit
