################################################################################
# CP5 probe 2 (READ-ONLY): the SPECIAL VIAS around the flagged VSS M4 stub.
# Probe 1 established the object is a real 0.46 x 6.285 um M4 riser
# (2354.67,1153.5)-(2355.13,1159.785) whose BOTTOM end is the IMPVFC-94
# dangling point; the source-GDS scan showed a via struct pad at y 1155.77-
# 1156.23 inside it, so the riser is connected and only its lower tail dangles.
# This dumps every special via on VSS/VDD in the neighbourhood so the trim
# point can be chosen from data instead of guessed.
################################################################################
source ../shared/constants.tcl

set DESIGN_NAME MCU_castalia_penta
set BASENAME    MCU_castalia_penta

restoreDesign $DATABASE_DIR/$BASENAME.signoff.innovus.dat $DESIGN_NAME
setCheckMode -tapeOut false

set X0 2345.0 ; set X1 2365.0 ; set Y0 1145.0 ; set Y1 1170.0

foreach net {VSS VDD} {
    set netp [dbGet -p top.nets.name $net]
    set n 0 ; set hit 0
    foreach v [dbGet $netp.sVias] {
        incr n
        set x "" ; set y ""
        catch { set x [dbGet $v.x] }
        catch { set y [dbGet $v.y] }
        if {$x eq "" || $y eq ""} { continue }
        if {$x < $X0 || $x > $X1 || $y < $Y0 || $y > $Y1} { continue }
        set def "?" ; set sts "?" ; set top "?" ; set bot "?"
        catch { set def [dbGet $v.viaDef.name] }
        catch { set sts [dbGet $v.status] }
        catch { set top [dbGet $v.viaDef.topLayer.name] }
        catch { set bot [dbGet $v.viaDef.botLayer.name] }
        puts [format "### PROBE2 ###  %s sVia (%.3f,%.3f) def %-28s %s->%s status %s" $net $x $y $def $bot $top $sts]
        incr hit
    }
    puts "### PROBE2 ### $net: $n special vias total, $hit in window x\[$X0,$X1\] y\[$Y0,$Y1\]"
}

# the TCM's own PG pins on its left edge (what the stub was reaching for)
set ip [dbGet -p top.insts.name mcu0/hart4/tile/ram0]
puts "### PROBE2 ### ram0 box [dbGet $ip.box]  orient [dbGet $ip.orient]"
set np 0
foreach pin [dbGet $ip.instTerms] {
    set nm "?"
    catch { set nm [dbGet $pin.name] }
    if {![string match "*VSS*" $nm] && ![string match "*VDD*" $nm]} { continue }
    incr np
    if {$np > 8} { continue }
    puts "### PROBE2 ###   PG instTerm $nm"
}
puts "### PROBE2 ### done"
exit
