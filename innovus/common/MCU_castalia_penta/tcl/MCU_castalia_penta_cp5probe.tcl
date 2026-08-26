################################################################################
# CP5 probe (READ-ONLY -- no edits, no saveDesign): characterise the CP4b
# ANTENNA + IMPVFC-94 object at (2354.899, 1153.500) before any repair.
# The CP4b report called it a "degenerate zero-area VSS M4 sroute weld stub";
# the first ECO attempt proved there is NO zero-area shape in the DB, so this
# dumps every PG object around the point and its connectivity instead.
################################################################################
source ../shared/constants.tcl

set DESIGN_NAME MCU_castalia_penta
set BASENAME    MCU_castalia_penta
set WIN  {2340.0 1140.0 2375.0 1175.0}

proc __box {ptr} {
    set b {}
    catch { set b [dbGet $ptr.box] }
    if {[llength $b] == 1} { set b [lindex $b 0] }
    return $b
}

restoreDesign $DATABASE_DIR/$BASENAME.signoff.innovus.dat $DESIGN_NAME
setCheckMode -tapeOut false

lassign $WIN wx0 wy0 wx1 wy1
foreach net {VSS VDD} {
    set netp [dbGet -p top.nets.name $net]
    puts "### PROBE ### ---- net $net ----"
    set i 0
    foreach w [dbGet $netp.sWires] {
        set b [__box $w]
        if {[llength $b] != 4} { continue }
        lassign $b x1 y1 x2 y2
        if {!($x1 <= $wx1 && $wx0 <= $x2 && $y1 <= $wy1 && $wy0 <= $y2)} { continue }
        set lay "?" ; set sts "?" ; set via "-"
        catch { set lay [dbGet $w.layer.name] }
        catch { set sts [dbGet $w.status] }
        catch { set via [dbGet $w.viaDef.name -e] }
        puts [format "### PROBE ###   sWire %-14s layer %-5s status %-8s via %-18s box %s" $w $lay $sts $via $b]
        incr i
    }
    puts "### PROBE ### $net: $i special shapes in window"
}

# special vias (they are separate objects in some releases)
foreach coll {top.nets.sVias top.sVias} {
    if {![catch {set r [dbGet $coll -e]} e]} {
        if {$r ne "0x0" && $r ne ""} {
            puts "### PROBE ### collection $coll exists: [llength $r] objects (window filter below)"
            foreach v $r {
                set b [__box $v]
                if {[llength $b] != 4} { continue }
                lassign $b x1 y1 x2 y2
                if {!($x1 <= $wx1 && $wx0 <= $x2 && $y1 <= $wy1 && $wy0 <= $y2)} { continue }
                set nm "?" ; set nn "?"
                catch { set nm [dbGet $v.viaDef.name] }
                catch { set nn [dbGet $v.net.name] }
                puts [format "### PROBE ###   sVia %-14s def %-20s net %-8s box %s" $v $nm $nn $b]
            }
        }
    }
}

# regular routing + vias in the window, any net (dbQuery)
foreach ot {wire via inst} {
    if {[catch {set objs [dbQuery -area $WIN -objType $ot]} e]} {
        puts "### PROBE ### dbQuery -objType $ot failed: $e"
        continue
    }
    if {$objs eq "0x0" || $objs eq ""} { set objs {} }
    puts "### PROBE ### dbQuery $ot in window: [llength $objs]"
    set n 0
    foreach o $objs {
        set nn "?" ; set lay "?" ; set extra ""
        catch { set nn [dbGet $o.net.name -e] }
        catch { set lay [dbGet $o.layer.name -e] }
        if {$ot eq "via"} { catch { set extra [dbGet $o.via.cutLayer.name -e] } }
        if {$ot eq "inst"} { catch { set extra [dbGet $o.cell.name -e] ; set nn [dbGet $o.name] } }
        puts [format "### PROBE ###   %-5s %-14s net %-30s layer %-6s %s box %s" $ot $o $nn $lay $extra [__box $o]]
        incr n
        if {$n > 120} { puts "### PROBE ###   ... truncated" ; break }
    }
}

# what does connectivity say about the marker?
puts "### PROBE ### TCM box: [__box [dbGet -p top.insts.name mcu0/hart4/tile/ram0]]"
puts "### PROBE ### done"
exit
