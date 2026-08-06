# =============================================================================
# dbg_dark.tcl -- the D2 DARK-HART harness: dmstatus.unavail against PWRCTRL,
# and halt-on-power-up under a held resethaltreq (d2_spec section 5).
#
#   ./xrun_dbg.sh rv32ua-p-dbgdarkmp dbg_dark.tcl
#
# THE ORDERING PROBLEM, AND WHY THERE IS NO CALIBRATION HERE
#   The obvious way to write this test is "wait until the tile is dark, then
#   set resethaltreq, then tell software to power it up" -- and every step of
#   that is a delay somebody has to tune.  Instead resethaltreq is armed
#   ONCE, BEFORE ANYTHING, and simply held: it is a level, it means "halt the
#   next time this hart comes out of reset", and a hart that is running when
#   it is armed is unaffected.  So the harness has no schedule at all; it
#   polls, and the image drives the power sequence.
#
# CHECKS (DMILOG; the runner greps for FAILED):
#   D1  hart 3 reads RUNNING before the gate
#   D2  while the image reports the tile at S_OFF, dmstatus for hart 3 reads
#       any- AND allunavail
#   D3  ...and NOT halted and NOT running.  This is the check that D0/P5's
#       "accidental unavail" trap is about: the tile's dbg_halted is clamped
#       to '0' when the domain is isolated, and '0' is indistinguishable from
#       "running" unless unavail is consulted FIRST.  A DM that derives its
#       state from dbg_halted alone reads a dark hart as RUNNING and fails
#       here and nowhere else.
#   D4  ...and NOT nonexistent: unavail and nonexistent are different answers
#       and a debugger acts differently on each
#   D5  THE DM IS STILL REACHABLE while a hart is dark -- dmstatus for hart 0
#       still reports version 3 and hart 0 still reads running.  The DM lives
#       on the always-on rail; if it went away with the tile, everything else
#       in this file would be unobservable rather than false.
#   D6  after the power-up, hart 3 reads HALTED: the held resethaltreq caught
#       it on the way out of reset
#   D7  ...INSIDE the entry page, and having retired nothing of its own.
#       Structural, read off the core's own pc exactly as D1's dbg_rst.tcl
#       does, because there is no in-band way to see a hart that never
#       executed anything.  An ORDERING, not a simultaneity (R-D2-5(1)), and
#       a page rather than a point because a halted hart is supposed to run
#       the trampoline planted at that address -- see the check's own note.
#   D8  resume puts it back to running
#
# The image supplies the half no harness can: that the tile really was gated
# (PWRSR nibble = S_OFF), that it really came back (S_ON), and -- the
# discriminator -- that a re-launch msip did NOT start it while it was
# halted but DID once it was resumed.  See dbgdarkmp.S's header for why that
# re-launch is the load-bearing part.
#
# AT UNIMPLEMENTED HEAD dmi_present prints INSTRUMENT_DEAD, the ACK and RACK
# words are still planted so the image completes its power sequence, and the
# image fails on 0x0D250006 -- the tile parked, took the msip and ran.
# =============================================================================
source ../../disable_x_warnings.tcl
# dbg_bfm.tcl lives beside this file in behavioral_mp/, but a harness is also
# run from the mutation scratch dir (d2mut/), whose CWD is one level across.
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }

set VICTIM 3
set SH_RAN  0x10054
set SH_CNT3 0x10058
set SH_ACK  0x1005C
set SH_DARK 0x10060
set SH_WOKE 0x10064
set SH_RACK 0x10068
set SH_ALIVE 0x10070
set SH_AACK  0x10074

set PRESENT [dmi_present]

dbg_plant_trampoline

# ---- 1. wait until the victim is alive ------------------------------------
# THE IMAGE SAYS SO; the harness no longer decides it (validation wave,
# 2026-08-06).  The old form watched SH_CNT3 ADVANCE across two 200 us
# samples -- and hart 0 CLEARS SH_CNT3 when it publishes DARK, so the two
# raced for the same word.  Measured: the harness lost, reported alive=0,
# and SKIPPED both D1 and the resethaltreq arm, after which every remaining
# leg failed for a reason with nothing to do with the DM.  hart 0 has
# already required CNT3 >= START_T before it publishes SH_ALIVE, so this is
# both race-free and a STRONGER liveness statement than the old one.
set alive 0
for {set i 0} {$i < 400} {incr i} {
    run 200 us
    if {[sh_get $SH_ALIVE] == 1} { set alive 1 ; break }
}
puts "DMILOG victim alive=$alive (image-published) after i=$i CNT3=[sh_get $SH_CNT3] RAN=[sh_get $SH_RAN]"
flush stdout

# ---- 1b. ARM resethaltreq, ON THE VICTIM'S OWN RAN==1 (R-D2-7(2)) ---------
# It used to be armed at t~0, "before anything", which read as the absence of
# a schedule and was in fact the worst possible one: t~0 lands INSIDE the
# victim's core reset, so the request was sampled at ITS release and halted
# the hart before it was ever launched -- the DEFINED behaviour, arriving at
# the wrong moment and making every later leg unreachable.  The arm is now
# ordered on the victim's demonstrated execution: the hart has retired at
# least START_T shared increments, so it is unambiguously past reset release,
# and the request can only be sampled at the NEXT one -- the power-up this
# test is about.  An ordering, not a duration.  (Validation wave: the
# ordering is now taken from hart 0's SH_ALIVE publication rather than from
# the harness's own race on SH_CNT3 -- see step 1 -- and the image HOLDS
# before gating until SH_AACK below, so the arm certainly lands inside the
# victim's running window.)
if {$PRESENT && $alive} {
    dm_select $VICTIM
    dm_setresethaltreq $VICTIM
    puts "DMILOG resethaltreq armed on hart $VICTIM AFTER its published liveness (ordered, not scheduled)"
    flush stdout
}

if {$PRESENT && $alive} {
    dm_select $VICTIM
    set s [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_allrunning $s] == 1 && [dms_allunavail $s] == 0}] \
        "D1: hart $VICTIM reads RUNNING (and not unavail) before the gate"
}

# Release the image into the gate.  Planted UNCONDITIONALLY -- exactly like
# SH_ACK below -- so a chip with no DM still completes its power sequence and
# fails on the ordering assertion that matters rather than on the handshake.
sh_force $SH_AACK 1

# ---- 2. wait for the IMAGE to report the tile dark, then look -------------
set dark 0
for {set i 0} {$i < 400} {incr i} {
    run 200 us
    if {[sh_get $SH_DARK] == 1} { set dark 1 ; break }
}
puts "DMILOG image reports DARK=$dark after i=$i"
flush stdout

if {$PRESENT && $dark} {
    dm_select $VICTIM
    set s [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_anyunavail $s] == 1 && [dms_allunavail $s] == 1}] \
        "D2: a power-gated hart reads any- AND allunavail (dmstatus [format 0x%08X $s])"
    d2_chk [expr {[dms_allhalted $s] == 0 && [dms_anyhalted $s] == 0 &&
                  [dms_allrunning $s] == 0 && [dms_anyrunning $s] == 0}] \
        "D3: ...and NOT halted and NOT running -- the clamped dbg_halted '0' must not read as either"
    d2_chk [expr {[dms_anynonexist $s] == 0}] \
        "D4: ...and NOT nonexistent: unavail and nonexistent are different answers"

    dm_select 0
    set s0 [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_version $s0] == 3 && [dms_allrunning $s0] == 1}] \
        "D5: the DM is STILL REACHABLE while a hart is dark, and hart 0 still reads running"
}

# tell the image to power the tile back up (a forced shared word -- the
# measured harness -> in-band channel).  Planted unconditionally so the image
# completes its sequence even when there is no DM to check anything.
sh_force $SH_ACK 1

# ---- 3. the power-up, under the held resethaltreq -------------------------
set woke 0
for {set i 0} {$i < 400} {incr i} {
    run 200 us
    if {[sh_get $SH_WOKE] == 1} { set woke 1 ; break }
}
puts "DMILOG image reports WOKE=$woke after i=$i"
flush stdout

if {$PRESENT && $woke} {
    dm_select $VICTIM
    set s [dm_poll_status $VICTIM dms_allhalted 400]
    d2_chk [expr {$s >= 0}] \
        "D6: after the power-up hart $VICTIM reads HALTED -- the held resethaltreq caught it out of reset"
    # D7 is structural, in the D1 dbg_rst.tcl idiom: there is no in-band way
    # to observe a hart that never retired anything.
    set pc -1
    catch {
        set b [string map {\" ""} [value ":dut:hart${VICTIM}:core:pc"]]
        if {[regexp {^[01]{32}$} $b]} { set pc [expr {"0b$b"}] }
    }
    # D7 is an ORDERING, not a simultaneity -- R-D2-5(1)'s ruling on I6's R2,
    # applied here at the validation wave for the same reason and one more.
    # The reason R-D2-5(1) gave: dbg_halted is on the free clock and the pc on
    # the gated one.  The additional reason, which only became visible once a
    # trampoline was actually planted (SS16.1 measured this leg with none): a
    # halted hart at DEBUG_ENTRY_ADDR is SUPPOSED to execute the trampoline
    # and park in its poll loop, so exact equality with the entry address
    # asserts that the trampoline did NOT run.  Measured pc here: 0x107D8,
    # 0x58 into the 64-word entry page.  The contract is that the hart is
    # halted INSIDE the entry page having retired nothing of its own.
    set inpage [expr {$pc >= $::DBG_ENTRY_ADDR && $pc < $::DBG_ENTRY_ADDR + 0x100}]
    d2_chk [expr {$inpage && [sh_get $SH_RAN] == 0}] \
        "D7: ...with pc INSIDE the entry page (read [format 0x%08X $pc], page [format 0x%08X $::DBG_ENTRY_ADDR]-[format 0x%08X [expr {$::DBG_ENTRY_ADDR + 0xFF}]]) and the victim having retired NOTHING of its own (RAN=[sh_get $SH_RAN])"
    puts "DMILOG   hart${VICTIM} state=[d2_state $VICTIM] RAN=[sh_get $SH_RAN]"

    # DIAGNOSTIC (validation wave): where will the dret land, and is the
    # tile's IVT slot 83 -- the bootrom's msip/loader hook -- armed yet?
    set dpc "?"
    catch {
        set b [string map {\" ""} [value ":dut:hart${VICTIM}:core:csr_unit_inst:dpc_r"]]
        if {[regexp {^[01]+$} $b]} { set dpc [format 0x%08X [expr {2*("0b$b")}]] }
    }
    set ivt83 "?"
    catch { set ivt83 [string map {\" ""} [value ":dut:hart${VICTIM}:ram0:RAM:mem([expr {(0x814C-0x8000)/4}])"]] }
    puts "DMILOG   pre-resume dpc=$dpc  tcm\[0x814C\](IVT slot 83)=$ivt83"
    flush stdout

    dm_resumereq $VICTIM
    set s [dm_poll_status $VICTIM dms_allrunning 400]
    d2_chk [expr {$s >= 0}] "D8: resume puts hart $VICTIM back to running"
    dm_clrresethaltreq $VICTIM
}

# Let the image see the resume -- and ONLY if there really was one.  The
# image's discriminator is the ORDER in which RAN and RACK arrive, so planting
# RACK unconditionally would hand a chip with no debug module a free pass.
if {$PRESENT && $woke} {
    sh_force $SH_RACK 1
    # DIAGNOSTIC, not a check: how long after the resume does the victim
    # actually execute?  The image's dk_ranwait draws on a budget, and a
    # budget that expires before the subject exists fails on correct RTL
    # (the SS9a class).  This names which of the two happened.
    # DIAGNOSTIC, not a check: the victim's post-resume execution is
    # PUBLISHED, not asserted -- see the D7/RAN note in dbgdarkmp.S.
    for {set i 0} {$i < 200} {incr i} {
        if {[sh_get $SH_RAN] == 1} { break }
        run 200 us
    }
    puts "DMILOG post-resume RAN=[sh_get $SH_RAN] RANP=[sh_get 0x10078] (published, not asserted)"
    flush stdout
} else {
    puts "DMILOG RACK withheld -- no resume was issued, so the image must see"
    puts "DMILOG   its victim run with nobody having resumed it."
    flush stdout
}

set verdict [d2_run_to_verdict 2400 "25 us"]
d2_report_verdict "dbgdarkmp" $verdict
puts "DMILOG PHASE=[sh_get 0x10050] RAN=[sh_get $SH_RAN] CNT3=[sh_get $SH_CNT3] DARK=[sh_get $SH_DARK] WOKE=[sh_get $SH_WOKE] SRSAW=[format 0x%08X [sh_get 0x1006C]]"
d2_summary "dbgdarkmp"
flush stdout
exit
