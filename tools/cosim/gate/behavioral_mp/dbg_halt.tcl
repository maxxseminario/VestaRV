# =============================================================================
# dbg_halt.tcl -- the D1 halt harness for rv32ua-p-dbghaltmp.
#
#   ./xrun_dbg.sh rv32ua-p-dbghaltmp dbg_halt.tcl
#
# WHAT IT DOES, AND WHY IT WAITS ON STATE RATHER THAN ON A CLOCK
# ---------------------------------------------------------------------------
# At D1 no debug module exists, so hdl/common/MCU.vhd leaves every tile's
# dbg_haltreq / dbg_resethaltreq / dbg_halted unconnected.  This harness is
# the debugger: it forces the request lines and reads the halted lines.  The
# force path was validated against a known-nonzero effect before any of this
# was written -- see dbg_forcecheck.tcl.
#
# It fires only after each victim has REACHED ITS ABSORBING STATE, and it
# learns that by reading the victims' own cpu_state (SLEEPING for the parked
# hart, TRAP_STATE for the wedged one), not by counting microseconds.  Both
# states are absorbing: once entered they are never left without an external
# event, so an early poll simply loops again and a late one is still correct.
# That is deliberate -- a calibrated delay passes on the machine it was tuned
# on and silently stops covering anything afterwards (method rule 7).
# Hart 3 needs no wait at all: it spins on a shared flag until the harness's
# own visit releases it.
#
# THE HALT HANDSHAKE, AND WHAT R-D1-2(1b) CHANGED ABOUT IT.
# dbg_haltreq is a LEVEL (d1_spec.md 1).  This harness raises it, watches
# dbg_halted, and drops it -- which is what a real debugger does.
#
# CORRECTED 2026-08-05 (method rule 12: a wrong rationale is worse than none,
# and this one was mine).  The header used to say that a held request would
# make the hart "re-enter debug the instant its dret retired, forever", and
# that "a build that never raises dbg_halted hangs this harness".  BOTH ARE
# NOW FALSE, and the second was never quite true:
#   * The implemented core carries WAIT-FOR-RELEASE on dbg_haltreq (the
#     mp_arbiter `need_release` idiom, ratified as a D1 design by R-D1-2(1b)):
#     one entry per ASSERTION, the mask cleared only when the request is
#     OBSERVED low, release winning over set.  So a continuously held request
#     yields exactly ONE entry.  Dropping it is good hygiene and re-arms the
#     next halt; it is no longer required for correctness.
#   * This harness has never been able to hang: every loop in it is bounded
#     and the test's own a0/a1 is the verdict.  The old sentence promised a
#     hang as evidence, and evidence that cannot occur is not evidence.
#
# CONSEQUENCE FOR THE POLLING RATE, and this is the real defect the ruling
# exposed.  With wait-for-release the whole halt -> stub -> dret round trip
# completes in a couple of microseconds, well INSIDE a 25 us polling chunk, so
# a coarse poll can step straight over the halted interval and see dbg_halted
# low on both sides of it.  The old harness then printed NO_HALTED on a run
# whose test PASSED -- a spurious diagnostic, and exactly the kind of
# decorative negative that gets quoted as a finding.  The watch loop below now
# samples every 500 ns (about 12 mclk), and a non-observation is classified,
# not asserted:
#
# DIAGNOSTICS, all reported and none silent:
#   HALTLOG PORT_ABSENT     the debug ports do not exist -- the part-1
#                           seen-to-FAIL demonstration
#   HALTLOG HALT_NOT_SAMPLED  no dbg_halted sample caught a '1' AND the test
#                           PASSED.  BENIGN: the entry completed between
#                           samples.  Not a failure, and never counted as one.
#   HALTLOG NO_HALTED       no dbg_halted sample caught a '1' AND the test
#                           FAILED.  THAT is the finding.
#   HALTLOG STATE_TIMEOUT   a victim never reached its absorbing state (the
#                           test image is wrong, not the RTL)
# The a0 verdict remains the instrument; the harness log explains it.
# =============================================================================
source ../../disable_x_warnings.tcl

set HARTS {1 2 3}
set REQ  {}
set HLT  {}
foreach h $HARTS {
    dict set REQ $h ":dut:hart${h}:dbg_haltreq"
    dict set HLT $h ":dut:hart${h}:dbg_halted"
}

# ---- 0. do the ports exist at all? -----------------------------------------
foreach h $HARTS {
    if {[catch {value [dict get $HLT $h]} e]} {
        puts "HALTLOG PORT_ABSENT hart=$h path=[dict get $HLT $h] err=$e"
        puts "HALTLOG VERDICT=INSTRUMENT_DEAD (no D1 debug interface in this build)"
        flush stdout
        # Run on anyway: the test must be SEEN to fail its own way too.
        set PORTS 0
        break
    }
    set PORTS 1
}
if {![info exists PORTS]} { set PORTS 1 }

proc st {h} {
    if {[catch {value ":dut:hart${h}:core:current_state"} v]} { return "ERR" }
    return [string map {\" ""} $v]
}

set dead_q "\"11011110101011011011111011101111\""
set cafe_q "\"11001010111111101011101010111110\""

# ---- 1. let the image boot and the victims reach their absorbing states -----
# 60 x 25 us = 1.5 ms is nowhere near enough on its own: the SPI boot copy is
# ~9.6 ms.  The loop below runs up to 1200 chunks = 30 ms, and EXITS EARLY the
# moment both states are seen -- the bound is a safety net, not a schedule.
set armed 0
for {set i 0} {$i < 1200} {incr i} {
    run 25 us
    if {[st 1] eq "SLEEPING" && [st 2] eq "TRAP_STATE"} { set armed 1; break }
}
puts "HALTLOG arm i=$i armed=$armed h1=[st 1] h2=[st 2] h3=[st 3]"
flush stdout
if {!$armed} {
    puts "HALTLOG STATE_TIMEOUT -- a victim never parked; the image, not the RTL"
}

# ---- 2. raise every halt request -------------------------------------------
set forced 0
if {$PORTS} {
    foreach h $HARTS {
        if {[catch {force [dict get $REQ $h] '1'} e]} {
            puts "HALTLOG FORCE_REFUSED hart=$h err=$e"
        } else {
            incr forced
        }
    }
    puts "HALTLOG forced=$forced of 3"
    flush stdout
}

# ---- 3. watch dbg_halted; drop each request as soon as its hart is halted ---
# 500 ns per sample (~12 mclk), 4000 samples = 2 ms.  Fine enough to land
# inside a halt window that wait-for-release makes only a few microseconds
# long, and long enough to cover all three victims' serialized stub traffic.
set seen [dict create 1 0 2 0 3 0]
for {set i 0} {$i < 4000} {incr i} {
    run 500 ns
    if {$PORTS} {
        foreach h $HARTS {
            if {[dict get $seen $h]} continue
            if {[catch {value [dict get $HLT $h]} v]} { continue }
            if {[string match {*1*} $v]} {
                dict set seen $h 1
                catch {release [dict get $REQ $h]}
                puts "HALTLOG halted hart=$h at chunk $i -- request released"
                flush stdout
            }
        }
    }
    if {[dict get $seen 1] && [dict get $seen 2] && [dict get $seen 3]} { break }
}
set any_halted [expr {[dict get $seen 1] || [dict get $seen 2] || [dict get $seen 3]}]
# The classification of a non-observation is DEFERRED to after the verdict --
# it depends on whether the test passed.  See below.

# ---- 4. run to the test's own verdict --------------------------------------
proc hex32 {bits} {
    set b [string map {\" ""} $bits]
    if {![regexp {^[01]{32}$} $b]} { return $bits }
    return [format "0x%08X" [expr {"0b$b"}]]
}
set verdict TIMEOUT
for {set i 0} {$i < 2400} {incr i} {
    run 25 us
    set av [value :a0]
    if {$av eq $dead_q} { set verdict FAILED; break }
    if {$av eq $cafe_q} { set verdict PASSED; break }
}
set out "HALTLOG VERDICT=$verdict"
foreach {tag idx} {a0 10 a1 11 a2 12 a3 13} {
    if {[catch {value :dut:hart0:core:datapath_inst:rf:registers($idx)} v]} {
        set v ERR
    } else { set v [hex32 $v] }
    append out " $tag=$v"
}
puts $out
if {$PORTS && !$any_halted} {
    if {$verdict eq "PASSED"} {
        puts "HALTLOG HALT_NOT_SAMPLED -- no sample caught dbg_halted high, but the"
        puts "HALTLOG   test PASSED, so every victim did enter and leave debug mode."
        puts "HALTLOG   BENIGN: wait-for-release makes the halt window shorter than"
        puts "HALTLOG   the sampling interval.  dbg_halted's own coverage is I2's."
    } else {
        puts "HALTLOG NO_HALTED -- requests raised, dbg_halted never sampled high,"
        puts "HALTLOG   and the test FAILED.  This is the finding."
    }
}
foreach h $HARTS {
    set hv "n/a"
    catch {set hv [value [dict get $HLT $h]]}
    puts "HALTLOG   hart$h state=[st $h] halted=$hv"
}
flush stdout
exit
