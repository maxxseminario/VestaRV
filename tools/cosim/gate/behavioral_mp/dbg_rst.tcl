# =============================================================================
# dbg_rst.tcl -- the D1 HALT-ON-RESET instrument.  Structural, graded by grep,
# and it needs NO test software of its own.
#
#   ./xrun_dbg.sh xxxxxxrv32ui-p-add dbg_rst.tcl
#
# WHY IT CARRIES NO IMAGE.  d1_spec.md 2 makes dbg_resethaltreq an entry cause
# sampled at reset release, "before the first instruction retires".  At reset
# there is nothing sensible at DEBUG_ENTRY_ADDR to execute -- at D1 it was the
# UNINITIALISED private TCM, and since the R-D2-1(3) migration it is a shared
# word the bootrom has not zeroed yet.  A debug ROM is D4's.  Halt-on-reset is
# therefore only checkable STRUCTURALLY: did dbg_halted rise, did it rise
# before the hart retired anything, and at what pc?  None of that needs a
# program, so this harness rides whatever test is running on hart 0 and
# observes hart 1.
#
# MIGRATED 2026-08-05 (R-D2-1(3)) and RE-SHAPED 2026-08-06: R2 accepts EITHER
# entry address -- 0x10780 (the shared page) or the 0xBE00 VHDL generic
# default the tree still carries -- and REPORTS which it observed.  It used to
# demand 0x10780 and therefore re-reported the entry-address migration gap as
# a second finding; one known item counted twice is a wrong record.
#
# WHAT IT CHECKS
#   R1  dbg_resethaltreq held across reset release raises dbg_halted on hart 1
#   R2  ORDERING, not simultaneity (RE-SHAPED 2026-08-06, R-D2-5(1)):
#       after dbg_halted rises, hart 1's pc REACHES DEBUG_ENTRY_ADDR, and it
#       does so before any retire.  The old check read pc AT THE INSTANT
#       dbg_halted rose and required equality -- a simultaneity that was
#       structurally determined only while the entry lived in the TCM.  With
#       a shared-window entry `dbg_halted` (free clk) legitimately LEADS the
#       pc update (gated clk, stalled by the entry's own shared fetch), so
#       the old form was a calibration in the method-rule-7 sense and would
#       have failed correct RTL.  The architectural contract is the ORDER.
#   R3  hart 1 never left PC_RST_VAL for the boot ROM first -- i.e. it halted
#       BEFORE running any instruction.  Measured as: hart 1's pc is never
#       observed inside the boot ROM's post-reset stretch (0x4..0x1FF) on any
#       sample before dbg_halted rises.  Sampled every 500 ns from time 0,
#       which is ~12 mclk at 24 MHz -- fine enough to see a hart that boots.
#   R4  hart 0 is UNAFFECTED: its own test still reaches its verdict, so a
#       halt-on-reset on one tile is not a chip-wide event.
#   R5  NEW (F-D2-2, R-D2-6(3)) -- THE OTHER HALF OF "SAMPLED AT RESET
#       RELEASE".  d1_spec's frozen interface says dbg_resethaltreq is
#       sampled AT RESET RELEASE.  R1 checks that a request held ACROSS the
#       release halts the hart; R5 checks the complement, which nothing in
#       the D-series has ever checked: a request asserted LATER, on a hart
#       that is already RUNNING, must NOT halt it.  A build whose arming
#       window is wider than the release edge -- armed by reset and cleared
#       only by some later event -- passes R1 and fails R5, and that is a
#       violation of the frozen interface rather than a matter of taste.
#       hart 2 is the subject: it is never given a request at reset, is
#       OBSERVED out of reset and not halted (pc past the reset value with
#       dbg_halted low for a run of samples -- an ordering, not a delay), and
#       only then is the request raised.  See the note at the check for why
#       the precondition is NOT "pc is advancing".
#       Authored blind under method rule 2: no fix exists and none has been
#       seen.
#
# Grade by grep: PASS iff RSTLOG VERDICT=PASS.  At unimplemented HEAD it prints
# RSTLOG PORT_ABSENT and VERDICT=INSTRUMENT_DEAD -- the part-1 seen-to-FAIL leg.
# =============================================================================
source ../../disable_x_warnings.tcl

set RRQ ":dut:hart1:dbg_resethaltreq"
set HLT ":dut:hart1:dbg_halted"
set PC  ":dut:hart1:core:pc"
# R5's subject: a hart that gets NO request at reset.
set RRQ2 ":dut:hart2:dbg_resethaltreq"
set HLT2 ":dut:hart2:dbg_halted"
set PC2  ":dut:hart2:core:pc"
# R-D2-1(3) migrated DEBUG_ENTRY_ADDR to the shared page, but the VHDL generic
# default is still 0xBE00 until the generator's debug-ON emission lands, so
# BOTH are accepted and the log REPORTS which was observed (the dbg_irq.tcl
# `in_stub` idiom).  R2 is about the ORDERING (R-D2-5(1)); making it also
# re-report the entry-address migration gap would count one known item twice.
set DBG_ENTRY 0x10780
proc is_entry {p} {
    if {$p == 0x10780} { return 2 }
    if {$p == 0xBE00}  { return 1 }
    return 0
}

proc hex32 {bits} {
    set b [string map {\" ""} $bits]
    if {![regexp {^[01]{32}$} $b]} { return $bits }
    return [format "0x%08X" [expr {"0b$b"}]]
}
proc pcv {p} {
    if {[catch {value $p} v]} { return -1 }
    set b [string map {\" ""} $v]
    if {![regexp {^[01]{32}$} $b]} { return -1 }
    return [expr {"0b$b"}]
}

set fails 0
if {[catch {value $HLT} e]} {
    puts "RSTLOG PORT_ABSENT path=$HLT err=$e"
    puts "RSTLOG VERDICT=INSTRUMENT_DEAD (no D1 debug interface in this build)"
    flush stdout
    exit
}
if {[catch {force $RRQ '1'} e]} {
    puts "RSTLOG FORCE_REFUSED path=$RRQ err=$e"
    puts "RSTLOG VERDICT=INSTRUMENT_DEAD"
    flush stdout
    exit
}
puts "RSTLOG resethaltreq forced high from time 0"

# ---- R1/R3: watch hart 1 from time 0 ---------------------------------------
set halted 0
set ranrom 0
set pcat -1
for {set i 0} {$i < 400} {incr i} {
    run 500 ns
    set p [pcv $PC]
    if {$p > 0 && $p < 0x200} { set ranrom 1 }
    set v [value $HLT]
    if {[string match {*1*} $v]} { set halted 1; set pcat $p; break }
}
puts [format "RSTLOG R1 halted=%d after %d x 500ns  pc_at_halt=0x%08X  ran_bootrom_first=%d" \
      $halted $i [expr {$pcat < 0 ? 0 : $pcat}] $ranrom]
if {!$halted} { puts "RSTLOG CHECK FAILED R1: dbg_halted never rose"; incr fails }
if {$ranrom} { puts "RSTLOG CHECK FAILED R3: hart 1 executed boot ROM before halting"; incr fails }

# ---- R2: the ORDERING.  pc must REACH DEBUG_ENTRY_ADDR after the halt, and
# still without any retire.  `dbg_halted` may lead the pc update by design
# (spec 4, added R-D2-5(1)); what may not happen is the pc never arriving, or
# the hart retiring something on the way.
set reached 0
set ranrom2 $ranrom
if {$halted} {
    if {[is_entry $pcat]} { set reached [is_entry $pcat] }
    for {set j 0} {$j < 400 && !$reached} {incr j} {
        run 500 ns
        set p [pcv $PC]
        if {$p > 0 && $p < 0x200} { set ranrom2 1 }
        if {[is_entry $p]} { set reached [is_entry $p] }
    }
    set where [expr {$reached == 2 ? "0x10780 (the shared entry page)" : ($reached == 1 ? "0xBE00 (the VHDL generic default)" : "nowhere")}]
    puts [format "RSTLOG R2 pc reached DEBUG_ENTRY_ADDR at %s after %d further samples (pc=0x%08X) ran_bootrom=%d" \
          $where $j [expr {[pcv $PC] < 0 ? 0 : [pcv $PC]}] $ranrom2]
}
if {$halted && !$reached} {
    puts "RSTLOG CHECK FAILED R2: pc never reached DEBUG_ENTRY_ADDR after the halt"
    incr fails
}
if {$halted && $reached && $ranrom2} {
    puts "RSTLOG CHECK FAILED R2: hart 1 retired boot ROM code on the way to DEBUG_ENTRY_ADDR"
    incr fails
}
catch {release $RRQ}
flush stdout

# ---- R5 (F-D2-2): a resethaltreq raised on a RUNNING hart must NOT halt it -
# hart 2 was given no request at reset.  A hart that halts here has an arming
# window wider than the reset-release edge d1_spec froze.
# The precondition is OUT OF RESET AND NOT HALTED, observed rather than waited
# for: pc past the reset value and dbg_halted low for a run of consecutive
# samples.  It is deliberately NOT "pc is advancing" -- MEASURED on this leg's
# first run, a tile on an ordinary single-hart image parks in the bootrom WFI
# (pc stuck at 0x2B4), so a pc-advancing criterion is never satisfied and the
# check reported UNCHECKED, which would have quietly retired the leg.  A parked
# hart is the case that matters anyway: three of four harts sit parked in the
# normal idle state, and a resethaltreq raised then is exactly what d1_spec's
# "sampled at reset release" forbids from halting them.
set running 0
set streak 0
set p0 -1
for {set i 0} {$i < 4000 && !$running} {incr i} {
    run 500 ns
    set p0 [pcv $PC2]
    set hv [expr {[catch {value $HLT2} vv] ? 1 : ([string match {*1*} $vv] ? 1 : 0)}]
    if {$p0 > 0x200 && !$hv} { incr streak } else { set streak 0 }
    if {$streak >= 20} { set running 1 }
}
set pre_halt [expr {[catch {value $HLT2} v2] ? -1 : ([string match {*1*} $v2] ? 1 : 0)}]
puts [format "RSTLOG R5 hart2 out-of-reset-not-halted=%d after %d x 500ns (pc=0x%08X) halted_before_request=%d" \
      $running $i [expr {$p0 < 0 ? 0 : $p0}] $pre_halt]
if {!$running} {
    puts "RSTLOG R5 UNCHECKED -- hart 2 never met the precondition, so raising the"
    puts "RSTLOG   request would have proved nothing.  Not counted either way."
} elseif {$pre_halt == 1} {
    puts "RSTLOG R5 UNCHECKED -- hart 2 was ALREADY halted before the request."
} else {
    if {[catch {force $RRQ2 '1'} e]} {
        puts "RSTLOG R5 FORCE_REFUSED path=$RRQ2 err=$e"
    } else {
        set h2 0
        for {set i 0} {$i < 800} {incr i} {
            run 500 ns
            if {[string match {*1*} [value $HLT2]]} { set h2 1; break }
        }
        puts [format "RSTLOG R5 halted_after_request=%d after %d x 500ns pc=0x%08X" \
              $h2 $i [expr {[pcv $PC2] < 0 ? 0 : [pcv $PC2]}]]
        if {$h2} {
            puts "RSTLOG CHECK FAILED R5: dbg_resethaltreq raised on a RUNNING hart HALTED it."
            puts "RSTLOG   d1_spec's frozen interface says it is sampled AT RESET RELEASE;"
            puts "RSTLOG   an arming window wider than that edge is the F-D2-2 violation."
            incr fails
        }
        catch {release $RRQ2}
    }
}
flush stdout

# ---- R4: hart 0's own test must still reach its verdict --------------------
set dead_q "\"11011110101011011011111011101111\""
set cafe_q "\"11001010111111101011101010111110\""
set verdict TIMEOUT
for {set i 0} {$i < 2400} {incr i} {
    run 25 us
    set av [value :a0]
    if {$av eq $dead_q} { set verdict FAILED; break }
    if {$av eq $cafe_q} { set verdict PASSED; break }
}
puts "RSTLOG R4 hart0 verdict=$verdict"
if {$verdict ne "PASSED"} { puts "RSTLOG CHECK FAILED R4: hart 0 disturbed"; incr fails }

if {$fails == 0} { puts "RSTLOG VERDICT=PASS" } else { puts "RSTLOG VERDICT=FAIL ($fails checks)" }
flush stdout
exit
