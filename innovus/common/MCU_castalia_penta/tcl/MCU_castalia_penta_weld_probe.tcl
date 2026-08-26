################################################################################
# WELD PROBE -- READ-ONLY on the 2026-08-17 CPR6 signoff cut.
#
# QUESTION: the WQ-DELTA 15 M7 weld patch
#     add_shape -net VSS -layer M7 -rect {1318.9 503.8 1326.1 509.2}
# now dangles at BOTH ends (verifyConnectivity: dangling Wire at 1318.900,506.5
# and 1326.100,506.5; 2 ANTENNA markers).  The patch's literal coordinates were
# derived from the PRE-JTAG pad ring; the five D3 JTAG pads re-centred the SOUTH
# row by -50 um.  This probe MEASURES, it does not assume:
#
#   (1) where PAD_VSS_1 actually is, and where its padPin-sroute strap /
#       M2 riser / via stack actually lands (top layer + x + y),
#   (2) the actual x-span AND y-extent of every VSS M7 vertical stripe near it,
#   (3) the nearest opposite-net (VDD) M7 geometry, for the wide-metal
#       clearance the fix must respect,
#   (4) the weld patch itself, and what verifyConnectivity says about it.
#
# READ-ONLY: no saveDesign, no streamOut, no add_shape, no editDelete.
#
# Run: cd ~/vestarv/innovus/common/MCU_castalia_penta && source ~/vestarv/cdspaths.sh
#      innovus -no_gui -batch -log log/MCU_castalia_penta_weld_probe -overwrite \
#              -files tcl/MCU_castalia_penta_weld_probe.tcl
################################################################################
source ../shared/constants.tcl

set DESIGN_NAME MCU_castalia_penta
set BASENAME    MCU_castalia_penta
set CUTDB       ${BASENAME}.cpr6.signoff
set REPORT_DIR  rpt

proc __box {ptr} {
    set b {}
    catch { set b [dbGet $ptr.box] }
    if {[llength $b] == 1} { set b [lindex $b 0] }
    return $b
}
proc P {args} { puts "### WELD ### [join $args { }]" }

if {![file isdirectory $DATABASE_DIR/${CUTDB}.innovus.dat]} {
    P "FATAL: no $DATABASE_DIR/${CUTDB}.innovus.dat"
    exit 1
}
restoreDesign $DATABASE_DIR/${CUTDB}.innovus.dat $DESIGN_NAME
setCheckMode -tapeOut false
P "restored cut = $CUTDB"

################################################################################
# (1) THE PADS.  Boxes of the south-row supply pads + their PG instTerm shapes.
################################################################################
P "---- (1) PAD INSTANCES ----"
foreach pn {PAD_VSS_1 PAD_VDD_1 PAD_VSS_0 PAD_VSSPST_1 PAD_TMS PAD_P2_0} {
    set ip ""
    catch { set ip [dbGet -p top.insts.name $pn -e] }
    if {$ip eq "" || $ip eq "0x0"} { P "  pad $pn NOT FOUND" ; continue }
    P [format "  %-14s cell %-14s orient %-5s box %s" \
        $pn [dbGet $ip.cell.name -e] [dbGet $ip.orient -e] [__box $ip]]
    foreach it [dbGet $ip.instTerms -e] {
        set tn "?" ; set nn "-"
        catch { set tn [dbGet $it.cellTerm.name -e] }
        catch { set nn [dbGet $it.net.name -e] }
        if {$nn ne "VSS" && $nn ne "VDD"} { continue }
        P [format "      instTerm %-10s net %-6s" $tn $nn]
        foreach acc {allShapes.shapes pins.allShapes.shapes pin.allShapes.shapes} {
            set r ""
            if {![catch { set r [dbGet $it.$acc -e] }] && $r ne "" && $r ne "0x0"} {
                foreach s $r {
                    set sl "?" ; set sb ""
                    catch { set sl [dbGet $s.layer.name -e] }
                    catch { set sb [dbGet $s.rect -e] }
                    if {$sb eq ""} { catch { set sb [__box $s] } }
                    P "        shape ($acc) layer $sl box $sb"
                }
                break
            }
        }
    }
}

################################################################################
# (2) EVERY PG sWire in a tall window over the PAD_VSS_1 column.
#     x 1230..1400 covers the pad (25 um wide) and the two VSS / two VDD M7
#     stripe columns either side of it; y -170..760 covers pad -> mesh bottom.
################################################################################
set WIN {1230.0 -170.0 1400.0 760.0}
lassign $WIN wx0 wy0 wx1 wy1
P "---- (2) ALL VSS/VDD sWires in window $WIN ----"
foreach net {VSS VDD} {
    set netp [dbGet -p top.nets.name $net -e]
    if {$netp eq "" || $netp eq "0x0"} { P "  net $net NOT FOUND" ; continue }
    set i 0
    foreach w [dbGet $netp.sWires -e] {
        set b [__box $w]
        if {[llength $b] != 4} { continue }
        lassign $b x1 y1 x2 y2
        if {!($x1 <= $wx1 && $wx0 <= $x2 && $y1 <= $wy1 && $wy0 <= $y2)} { continue }
        set lay "?" ; set sts "?" ; set via "-"
        catch { set lay [dbGet $w.layer.name -e] }
        catch { set sts [dbGet $w.status -e] }
        catch { set via [dbGet $w.viaDef.name -e] }
        P [format "  %-4s %-5s status %-9s via %-18s box %s" $net $lay $sts $via $b]
        incr i
        if {$i > 400} { P "  ... truncated at 400 for $net" ; break }
    }
    P "  net $net : $i sWires in window"
}

P "---- (2b) dbQuery sWire/sVia/wire/via in window (any net) ----"
foreach ot {sWire sVia wire via} {
    set objs {}
    if {[catch { set objs [dbQuery -area $WIN -objType $ot] } e]} {
        P "  dbQuery -objType $ot failed: $e" ; continue
    }
    if {$objs eq "0x0" || $objs eq ""} { set objs {} }
    P "  dbQuery $ot in window: [llength $objs]"
    set n 0
    foreach o $objs {
        set nn "?" ; set lay "?" ; set vd "-"
        catch { set nn  [dbGet $o.net.name -e] }
        catch { set lay [dbGet $o.layer.name -e] }
        catch { set vd  [dbGet $o.viaDef.name -e] }
        if {$nn ne "VSS" && $nn ne "VDD"} { continue }
        P [format "    %-5s net %-5s layer %-6s via %-18s box %s" $ot $nn $lay $vd [__box $o]]
        incr n
        if {$n > 300} { P "    ... truncated" ; break }
    }
}

################################################################################
# (3) THE VSS / VDD M7 VERTICAL STRIPES: full x-span AND y-extent, for every
#     M7 sWire whose box is inside x 1150..1450.  This is the number the
#     WQ-DELTA 15 comment got wrong -- it quoted an x-span and never a y.
################################################################################
P "---- (3) M7 stripes, x in 1150..1450, FULL y extent ----"
foreach net {VSS VDD} {
    set netp [dbGet -p top.nets.name $net -e]
    foreach w [dbGet $netp.sWires -e] {
        set lay "?"
        catch { set lay [dbGet $w.layer.name -e] }
        if {$lay ne "M7"} { continue }
        set b [__box $w]
        if {[llength $b] != 4} { continue }
        lassign $b x1 y1 x2 y2
        if {$x2 < 1150.0 || $x1 > 1450.0} { continue }
        P [format "  %-4s M7 x\[%9.3f,%9.3f\] y\[%9.3f,%9.3f\] w=%7.3f h=%9.3f status %s" \
            $net $x1 $x2 $y1 $y2 [expr {$x2-$x1}] [expr {$y2-$y1}] [dbGet $w.status -e]]
    }
}

################################################################################
# (4) LOWEST PG METAL ANYWHERE: what is the true bottom of the PG fabric, and
#     is there ANY pad-supply strap geometry south of the core?
################################################################################
P "---- (4) lowest PG sWire per layer (whole design) ----"
foreach net {VSS VDD} {
    set netp [dbGet -p top.nets.name $net -e]
    array unset LOW
    array unset LOWB
    foreach w [dbGet $netp.sWires -e] {
        set lay "?"
        catch { set lay [dbGet $w.layer.name -e] }
        set b [__box $w]
        if {[llength $b] != 4} { continue }
        set y1 [lindex $b 1]
        if {![info exists LOW($lay)] || $y1 < $LOW($lay)} { set LOW($lay) $y1 ; set LOWB($lay) $b }
    }
    foreach lay [lsort [array names LOW]] {
        P [format "  %-4s %-6s lowest y1 = %10.3f  box %s" $net $lay $LOW($lay) $LOWB($lay)]
    }
}

################################################################################
# (5) CONNECTIVITY: reproduce the dangling report so the fix has a before-shot.
################################################################################
P "---- (5) verifyConnectivity (PG only) ----"
verifyConnectivity -type special -error 200 -warning 200 \
    -report $REPORT_DIR/$BASENAME.verifyConnectivity.weld_probe.rpt
P "probe complete -- $REPORT_DIR/$BASENAME.verifyConnectivity.weld_probe.rpt"
exit
