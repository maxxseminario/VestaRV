# =============================================================================
# dbg_irq.tcl -- the F-D2-1 harness: a hart in debug mode takes NO interrupt,
# in BOTH delivery polarities.
#
#   ./xrun_dbg.sh rv32ua-p-dbgirqmp dbg_irq.tcl
#
# The D1 mechanism again: no Debug Module exists and none is needed -- this
# harness forces the tiles' `dbg_haltreq` ports.  The INTERRUPT half is
# entirely in band (hart 0 owns the CLINT), so this file's job is to put the
# victims into debug mode and then assert the two structural properties the
# image cannot see:
#
#   Y1  `dbg_halted` stays ASSERTED for the whole pending-interrupt window.
#       If it dropped, the hart left debug mode and "no interrupt was taken
#       in debug mode" would be true for the wrong reason.
#   Y2  the victim stays INSIDE its debug-entry stub for the whole window.
#       Read as a containment on `pc`: the stub is 32 words at whichever
#       DEBUG_ENTRY_ADDR the build carries (0xBE00 today, shared 0x10780 once
#       the generator's emission lands -- the harness accepts either and says
#       which it saw).  A hart that wandered off to an ISR and came back
#       could satisfy Y1 and the counter checks only if the ISR were
#       invisible; Y2 is what closes that.
#
# The WINDOW is bounded by EVENTS at both ends, not by a delay: it opens when
# the image publishes IN_DEBUG and closes when the image publishes GO
# (method rule 17).  The harness samples inside it and never decides its
# length.
#
# AT UNIMPLEMENTED HEAD F-D2-1 is a LIVE defect, so this harness is expected
# to report findings alongside the image's a1.  That is the seen-to-FAIL leg.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }

set VICTIMS {1 2}
set BLK(1) 0x10880
set BLK(2) 0x108C0
set O_ENTRIES  0
set O_ISR_CNT  4
set O_CTRL     8
set O_WINDOW   12
set O_DBGISR   16
set O_IN_DEBUG 20
set O_GO       24
set O_READY    36
set O_MSIP_SEEN 44

proc port {h n} { return ":dut:hart${h}:${n}" }
proc bit1 {p} {
    if {[catch {value $p} v]} { return -1 }
    if {[string match {*1*} $v]} { return 1 }
    return 0
}
proc pcv {h} {
    if {[catch {value ":dut:hart${h}:core:pc"} v]} { return -1 }
    set b [string map {\" ""} $v]
    if {![regexp {^[01]{32}$} $b]} { return -1 }
    return [expr {"0b$b"}]
}
# The stub occupies 32 words from DEBUG_ENTRY_ADDR.  Both candidate addresses
# are accepted because the tree's generic is 0xBE00 today and shared 0x10780
# after the generator's debug-ON emission; the harness REPORTS which it saw
# rather than assuming, so a silent move cannot pass unnoticed.
proc in_stub {pc} {
    if {$pc >= 0xBE00 && $pc < 0xBE80} { return 1 }
    if {$pc >= 0x10780 && $pc < 0x10800} { return 2 }
    return 0
}

set PORTS 1
foreach h $VICTIMS {
    if {[catch {value [port $h dbg_halted]} e]} {
        puts "IRQLOG PORT_ABSENT hart=$h path=[port $h dbg_halted] err=$e"
        puts "IRQLOG VERDICT=INSTRUMENT_DEAD (no D1 debug interface in this build)"
        flush stdout
        set PORTS 0
        break
    }
}

# ---- 1. wait for both victims to be ARMED and parked -----------------------
set ready 0
for {set i 0} {$i < 400} {incr i} {
    run 200 us
    if {[sh_get [expr {$BLK(1)+$O_READY}]] == 1 && [sh_get [expr {$BLK(2)+$O_READY}]] == 1} {
        set ready 1 ; break
    }
}
puts "IRQLOG victims READY=$ready after i=$i  CTRL=[sh_get [expr {$BLK(1)+$O_CTRL}]]/[sh_get [expr {$BLK(2)+$O_CTRL}]]"
flush stdout

# ---- 2. wait for the image's KNOWN-NONZERO control to land ----------------
# hart 0 sends each victim an msip while it is plainly NOT in debug mode.  The
# harness must not halt anybody until BOTH ISRs have run, or the control would
# be measuring a halted hart -- which is the very thing under test.
set ctrl 0
for {set i 0} {$i < 400} {incr i} {
    run 200 us
    if {[sh_get [expr {$BLK(1)+$O_CTRL}]] == 1 && [sh_get [expr {$BLK(2)+$O_CTRL}]] == 1} {
        set ctrl 1 ; break
    }
}
puts "IRQLOG known-nonzero control landed=$ctrl  ISR_CNT=[sh_get [expr {$BLK(1)+$O_ISR_CNT}]]/[sh_get [expr {$BLK(2)+$O_ISR_CNT}]]"
flush stdout
if {!$ctrl} {
    puts "IRQLOG CONTROL_NEVER_FIRED -- the interrupt was not taken even OUTSIDE"
    puts "IRQLOG   debug mode, so nothing this run reports about debug mode means"
    puts "IRQLOG   anything.  Test/config finding, not an RTL one."
}

# ---- 3. halt both victims --------------------------------------------------
array set halted {1 0 2 0}
if {$PORTS && $ctrl} {
    foreach h $VICTIMS {
        if {[catch {force [port $h dbg_haltreq] '1'} e]} {
            puts "IRQLOG FORCE_REFUSED hart=$h err=$e"
        }
    }
    puts "IRQLOG haltreq forced on harts $VICTIMS"
    flush stdout
}

# ---- 4. the window: from IN_DEBUG to GO, per victim, sampled --------------
array set y1 {1 1 2 1}
array set y2 {1 1 2 1}
array set seen_at {1 0 2 0}
array set sampled {1 0 2 0}
for {set i 0} {$i < 20000} {incr i} {
    run 500 ns
    set alldone 1
    foreach h $VICTIMS {
        if {$PORTS && !$halted($h) && [bit1 [port $h dbg_halted]] == 1} {
            set halted($h) 1
            catch {release [port $h dbg_haltreq]}
            puts "IRQLOG halted hart=$h at sample $i -- request released"
            flush stdout
        }
        # inside this victim's window?  opens on IN_DEBUG, closes on GO.
        if {[sh_get [expr {$BLK($h)+$O_IN_DEBUG}]] == 1 && [sh_get [expr {$BLK($h)+$O_GO}]] == 0} {
            set alldone 0
            incr sampled($h)
            if {$PORTS && [bit1 [port $h dbg_halted]] != 1} { set y1($h) 0 }
            set p [pcv $h]
            set w [in_stub $p]
            if {$w == 0} { set y2($h) 0 } else { set seen_at($h) $w }
        } elseif {[sh_get [expr {$BLK($h)+$O_GO}]] == 0} {
            set alldone 0
        }
    }
    if {$alldone} { break }
}
puts "IRQLOG window sweep i=$i  samples=[list $sampled(1) $sampled(2)]"
foreach h $VICTIMS {
    if {$sampled($h) == 0} {
        puts "IRQLOG Y-UNCHECKED hart=$h -- the window never opened (IN_DEBUG stayed 0)."
        puts "IRQLOG   An unsampled window is NOT a clean one; read the image's a1."
    } else {
        d2_chk [expr {$y1($h)}] \
            "Y1.$h: dbg_halted stayed ASSERTED for the whole pending-interrupt window ($sampled($h) samples)"
        set where [expr {$seen_at($h) == 1 ? "0xBE00 (the VHDL generic default)" : ($seen_at($h) == 2 ? "0x10780 (the shared entry page)" : "nowhere")}]
        d2_chk [expr {$y2($h)}] \
            "Y2.$h: hart $h stayed INSIDE its debug-entry stub throughout -- observed at $where"
    }
    puts "IRQLOG   hart$h state=[d2_state $h] pc=[format 0x%08X [pcv $h]] ENTRIES=[sh_get [expr {$BLK($h)+$O_ENTRIES}]] ISR_CNT=[sh_get [expr {$BLK($h)+$O_ISR_CNT}]] DBGISR=[format 0x%08X [sh_get [expr {$BLK($h)+$O_DBGISR}]]] MSIP_SEEN=[sh_get [expr {$BLK($h)+$O_MSIP_SEEN}]]"
}
flush stdout

set verdict [d2_run_to_verdict 2400 "25 us"]
d2_report_verdict "dbgirqmp" $verdict
foreach h $VICTIMS {
    set b $BLK($h)
    puts "IRQLOG hart$h final ISR_CNT=[sh_get [expr {$b+$O_ISR_CNT}]] CTRL=[sh_get [expr {$b+$O_CTRL}]] DBGISR=[format 0x%08X [sh_get [expr {$b+$O_DBGISR}]]] WIN_SNAP=[sh_get [expr {$b+28}]] POST=[format 0x%08X [sh_get [expr {$b+40}]]]"
}
puts "IRQLOG bystander CNT=[sh_get 0x10920]"
d2_summary "dbgirqmp"
flush stdout
exit
