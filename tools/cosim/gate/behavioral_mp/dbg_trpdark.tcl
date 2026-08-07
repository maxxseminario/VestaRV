# =============================================================================
# dbg_trpdark.tcl -- THE D4 HALT-ON-RESET IN-BAND LEG.  d4_spec 3, in full.
# THE BACKBONE: neither I6 nor J6 has ever graded a halt into an UNPLANTED
# page (d4_probe P6), and neither has ever proved that the hart which halts at
# reset release goes on to execute REAL entry code.
#
#   N=4:   ./xrun_dbg_verify.sh verify_castaliadebug ../rcf/rv32ua-p-dbgdarkmp.rcf dbg_trpdark.tcl
#   N=18:  ./xrun_dbg_verify.sh verify_argusdebug   ../k??/rv32ua-p-dbgdarkmp.rcf dbg_trpdark.tcl
#
# BLIND-AUTHORED 2026-08-07 against d4_spec.md (FROZEN).  Committed polarity:
# CORRECT RTL = PASS.
#
# IT IS dbg_dark.tcl's SEQUENCE WITH THE FORCE REMOVED AND THE VERDICT MOVED.
# The image (dbgdarkmp.S) is unchanged and unregistered-by-me: it already
# drives the whole PWRCTRL power-cycle in band and already publishes the
# orderings this leg needs.  What changes is that the trampoline is NOT
# planted -- dmactive is raised first and the DM is expected to plant it -- and
# that the grading no longer stops at "the hart is halted somewhere in the
# entry page".  d4_spec 3 asks for three things and this file checks all three
# plus the two it depends on:
#
#   (a) the victim halts with ZERO retires                     -> N1, N2
#   (b) pc reaches DEBUG_ENTRY_ADDR before any retire           -> N2
#   (c) it executes the REAL DM-planted entry code             -> N3, N4, N5
#
# ON (b) AND WHY IT IS NOT A pc EQUALITY (R-D2-5(1), method rule 7/17).
#   dbg_halted is on the free-running clock and the pc is on the gated one,
#   stalled by the entry fetch's own shared access, so an instantaneous pc
#   equality at the halt edge is microarchitecture, not contract.  Worse, once
#   a trampoline really is planted the hart is SUPPOSED to run it and park in
#   its poll loop, so exact equality with the entry address would assert that
#   the trampoline did NOT run.  The contract asserted here is the ordering:
#   the pc is INSIDE the 64-word entry page and the victim's own liveness word
#   is still zero -- it reached the page having retired nothing of its own.
#
# ON (c), WHICH IS THE PART THAT IS NEW.  "The victim is halted in the entry
#   page" is satisfied by a hart spinning on illegal-instruction re-entry in a
#   page of zeros; that is precisely what 286921d does and J6 grades it green.
#   The discriminator is that the DM must have OBSERVED the hart's TOK_HALTED,
#   which only the real trampoline publishes -- and the only way to observe
#   THAT from outside is to ask the DM to do something that waits for it.  N3
#   is an abstract GPR round-trip; it cannot complete unless the planted code
#   ran.  N4 then reads the whole page back through that same channel, and N5
#   resumes the hart, which is `dret` executed by the trampoline itself.
#
# CHECKS (DMILOG; the runner greps for FAILED):
#   E1  the victim reads RUNNING before the gate (environment)
#   E2  a power-gated hart reads any+all unavail, and NOT halted/running
#   E3  the DM is still reachable while a hart is dark
#   N1  after the power-up the victim reads HALTED
#   N2  ...with pc INSIDE the entry page and its liveness word still zero --
#       it reached the page before retiring anything of its own
#   N3  THE DISCRIMINATOR: an abstract GPR round-trip succeeds, so the DM
#       observed the trampoline's own TOK_HALTED -- the halted hart executed
#       REAL planted code, not a page of zeros
#   N4  ...and all 40 entry-page words read back through the DM equal the
#       built deliverable
#   N5  ...and the resume works, which is the planted `dret`
#
# AT 286921d (D4 UNIMPLEMENTED): E1-E3 and N1-N2 PASS -- and that is the whole
#   point of the leg.  A halt-on-reset instrument that stops at N2 is green on
#   a chip where debug is unusable.  N3 fails with the DM's own cmderr = OTHER
#   (7) after its 65535-mclk FLAGS wait, N4 the same, N5 silently drops (the
#   resume path's bound sets no cmderr at all -- resumeack simply stays 0 and
#   the hart stays halted), and the image then fails 0x0D250009 because its
#   victim never ran again.  Every one of those is a named, quoted answer.
#
# LIVENESS CONTROL (D4_CONTROL=1): the page is force-planted at the top, which
# is where the dmactive plant would have put it; N1-N5 must all pass.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tramp_lib.tcl]} { source dbg_tramp_lib.tcl } else { source ../behavioral_mp/dbg_tramp_lib.tcl }

# dbgdarkmp.S's band, quoted from its own header table (dbgdarkmp.S:110-127).
set VICTIM 3
set SH_PHASE 0x10050
set SH_RAN   0x10054
set SH_CNT3  0x10058
set SH_ACK   0x1005C
set SH_DARK  0x10060
set SH_WOKE  0x10064
set SH_RACK  0x10068
set SH_ALIVE 0x10070
set SH_AACK  0x10074

set R_S2 0x1012
set GPR_MAGIC 0x0D26CAFE

set PRESENT [dmi_present]
set WANT [d4_load_words]
if {[llength $WANT] == 0} {
    puts "DMILOG VERDICT=INSTRUMENT_DEAD (no content oracle)"
    d2_summary "dbgdarkmp/trpdark"
    flush stdout
    exit
}
set NH 4
if {[info exists ::env(D2_NHARTS)]} { set NH $::env(D2_NHARTS) }
puts "DMILOG D4 halt-on-reset in-band leg: NHARTS=$NH victim=$VICTIM (no plant, no tile-port force)"
flush stdout

# THE PLANT TRIGGER, and it is the first thing that happens: dmactive rises
# long before the victim is power-cycled, so on a D4 chip the page is populated
# before any hart can possibly halt.  Nothing else in this file writes the page.
if {$PRESENT} {
    d4_dmactive_on 0
    run 200 us
}
d4_control_plant

# ---- 1. the victim publishes its own liveness ----------------------------
set alive 0
for {set i 0} {$i < 400} {incr i} {
    run 200 us
    if {[sh_get $SH_ALIVE] == 1} { set alive 1 ; break }
}
puts "DMILOG victim alive=$alive (image-published) after i=$i CNT3=[sh_get $SH_CNT3] RAN=[sh_get $SH_RAN]"
flush stdout

if {$PRESENT && $alive} {
    dm_select $VICTIM
    dm_setresethaltreq $VICTIM
    puts "DMILOG resethaltreq armed on hart $VICTIM AFTER its published liveness (ordered, not scheduled)"
    flush stdout

    set s [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_allrunning $s] == 1 && [dms_allunavail $s] == 0}] \
        "E1: hart $VICTIM reads RUNNING before the gate"
}

sh_force $SH_AACK 1

# ---- 2. the image gates the tile -----------------------------------------
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
    d2_chk [expr {[dms_anyunavail $s] == 1 && [dms_allunavail $s] == 1 &&
                  [dms_allhalted $s] == 0 && [dms_anyrunning $s] == 0}] \
        "E2: a power-gated hart reads any+all unavail and NOT halted/running (dmstatus [format 0x%08X $s])"
    dm_select 0
    set s0 [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_version $s0] == 3 && [dms_allrunning $s0] == 1}] \
        "E3: the DM is still reachable while a hart is dark"
}

sh_force $SH_ACK 1

# ---- 3. the power-up, under the held resethaltreq ------------------------
set woke 0
for {set i 0} {$i < 400} {incr i} {
    run 200 us
    if {[sh_get $SH_WOKE] == 1} { set woke 1 ; break }
}
puts "DMILOG image reports WOKE=$woke after i=$i"
flush stdout

set resumed 0
if {$PRESENT && $woke} {
    dm_select $VICTIM
    set s [dm_poll_status $VICTIM dms_allhalted 400]
    d2_chk [expr {$s >= 0}] \
        "N1: after the power-up hart $VICTIM reads HALTED -- the held resethaltreq caught it out of reset"

    set pc -1
    catch {
        set b [string map {\" ""} [value ":dut:hart${VICTIM}:core:pc"]]
        if {[regexp {^[01]{32}$} $b]} { set pc [expr {"0b$b"}] }
    }
    set inpage [expr {$pc >= $::DBG_ENTRY_ADDR && $pc < $::DBG_ENTRY_ADDR + 0x100}]
    d2_chk [expr {$inpage && [sh_get $SH_RAN] == 0}] \
        "N2: ...with pc INSIDE the entry page (read [format 0x%08X $pc]) and the victim having retired NOTHING of its own (RAN=[sh_get $SH_RAN]) -- an ORDERING, not a simultaneity"
    puts "DMILOG   hart${VICTIM} state=[d2_state $VICTIM]"
    flush stdout

    if {$s >= 0} {
        ac_clear_cmderr
        set e [d4_abs_write $R_S2 $GPR_MAGIC]
        set r [d4_abs_read $R_S2]
        d2_chk [expr {$e == 0 && [lindex $r 1] == 0 && [lindex $r 0] == $GPR_MAGIC}] \
            "N3: THE DISCRIMINATOR -- an abstract GPR round-trip completes on the halted-at-reset hart (wrote [format 0x%08X $GPR_MAGIC], read [format 0x%08X [lindex $r 0]], cmderr w=$e r=[lindex $r 1]).  It cannot complete unless the DM observed the trampoline's own TOK_HALTED, so the hart executed REAL planted code."

        set rb [d4_dm_readback $WANT]
        d4_readback_report "N4" $rb $WANT
        d2_chk [lindex $rb 0] \
            "N4: ...and all 40 entry-page words read back through the DM equal the built deliverable (read [lindex $rb 1]/40)"

        dm_resumereq $VICTIM
        set s3 [dm_poll_status $VICTIM dms_allrunning 400]
        set resumed [expr {$s3 >= 0}]
        d2_chk $resumed "N5: ...and the resume works -- which is the planted `dret` executing"
        dm_clrresethaltreq $VICTIM
    }
}

# The image's own discriminator is the ORDER in which RAN and RACK arrive, so
# RACK is planted ONLY if a resume really happened (the dbg_dark.tcl rule).
if {$PRESENT && $woke && $resumed} {
    sh_force $SH_RACK 1
} else {
    puts "DMILOG RACK withheld -- no successful resume, so the image must see its"
    puts "DMILOG   victim run with nobody having resumed it (or not run at all)."
    flush stdout
}

set verdict [d2_run_to_verdict 2000 "25 us"]
d2_report_verdict "dbgdarkmp/trpdark" $verdict
puts "DMILOG PHASE=[sh_get $SH_PHASE] RAN=[sh_get $SH_RAN] CNT3=[sh_get $SH_CNT3] DARK=[sh_get $SH_DARK] WOKE=[sh_get $SH_WOKE]"
d2_summary "dbgdarkmp/trpdark" 8
flush stdout
exit
