# =============================================================================
# dbg_trpsess.tcl -- THE D4 END-TO-END NO-FORCE SESSION.  d4_spec 6, bullet 5,
# and d4_spec 3's "both tile states".
#
#   ./xrun_dbg_verify.sh verify_castaliadebug ../rcf/xxxxrv32ua-p-dbgtrpmp.rcf dbg_trpsess.tcl
#
# BLIND-AUTHORED 2026-08-07 against d4_spec.md (FROZEN).  Committed polarity:
# CORRECT RTL = PASS.
#
# WHAT IT IS.  A whole debug session, from a normal boot, with ZERO
# dbg_plant_trampoline calls anywhere -- the thing D2 and D3 could never do,
# because every one of their planting harnesses had to force the page first.
# Attach (dmactive), halt a hart, read and write its GPRs and CSRs abstractly,
# move a word of memory through its own bus with a program-buffer lw/sw, and
# resume.  Then do it again on a hart that has never executed a single
# instruction of the test image -- one still parked in the boot ROM.
#
# THE TWO TILE STATES (d4_spec 3, "the no-force story is proven against BOTH a
# ROM-parked tile and a loader-launched running tile"):
#   * hart 1 is loader-launched and running the image's victim loop.
#   * hart 3 is DELIBERATELY NEVER LAUNCHED by dbgtrpmp.S, so it is sitting in
#     the boot ROM's WFI park exactly as it was at reset.  At N=18 harts 3..17
#     are all in that state and hart 3 is representative of every one of them.
#   Hart 0 (running, post-boot) is covered by d4_spec 3's own reading and is
#   not re-proven here.
#
# THE MEMORY ROUND-TRIP IS CLOSED AT BOTH ENDS THROUGH THE DM, on purpose.  The
# outbound half writes data0 (which the DM proxies to the shared word 0x10680)
# and moves it with a progbuf lw/sw into a band word; the return half moves it
# back and reads data0 again.  So the value crosses the hart's own load/store
# path twice and is observed only over DMI -- no peek is load-bearing.
#
# CHECKS (DMILOG; the runner greps for FAILED):
#   S0  the victim halts on haltreq
#   S1  the entry page reads back 40/40 through the DM (it is the planted code
#       that is executing, not something that happens to work)
#   S2  abstract GPR write + read round-trip on x18
#   S3  abstract CSR write + read round-trip on mscratch
#   S4  progbuf lw/sw moves a word OUT through the hart's bus...
#   S5  ...and back IN, observed at data0 over DMI
#   S6  the victim resumes and its counter moves again
#   S7  a ROM-PARKED hart is reported RUNNING (not unavail, not nonexistent)
#   S8  ...and halts on haltreq
#   S9  ...and its abstract GPR round-trip works -- the parked tile executes
#       the same planted page
#   S10 ...and it resumes
#
# AT 286921d (D4 UNIMPLEMENTED): S0 passes, S1 fails with the DM's own
#   cmderr = OTHER (7), and S2 onwards fail the same way -- every abstract
#   command needs the trampoline to publish TOK_HALTED and there is no
#   trampoline.  Each failure is a quoted cmderr, not a timeout.
#
# LIVENESS CONTROL (D4_CONTROL=1): the page is force-planted before the
# session; every check must pass.  That arm is also the ONLY thing in this set
# that proves S7-S10 are answerable at all -- whether a ROM-parked hart can be
# halted and driven is a CORE question, independent of D4, and the control arm
# answers it separately from the plant question.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tramp_lib.tcl]} { source dbg_tramp_lib.tcl } else { source ../behavioral_mp/dbg_tramp_lib.tcl }

set RUNNER 1                      ;# loader-launched, running the victim loop
set PARKED 3                      ;# never launched: still in the boot ROM WFI

set R_S2  0x1012                  ;# x18
set C_MSCRATCH 0x340
set GPR_MAGIC 0x0D26F00D
set CSR_MAGIC 0x0D26BEEF
set MEM_MAGIC 0x0D26D00D
set PB0 0x00082E03                ;# lw  t3, 0(a6)
set PB1 0x01C8A023                ;# sw  t3, 0(a7)
set R_A6 0x1010
set R_A7 0x1011
set MEM_TMP 0x1006C               ;# a band word this harness does not otherwise use

set PRESENT [dmi_present]
set WANT [d4_load_words]
if {[llength $WANT] == 0} {
    puts "DMILOG VERDICT=INSTRUMENT_DEAD (no content oracle)"
    d2_summary "dbgtrpmp/sess"
    flush stdout
    exit
}

set ready [d4_wait_ready]

proc sess_gpr_roundtrip {tag h magic} {
    d4_settle
    set e [d4_abs_write $::R_S2 $magic]
    set r [d4_abs_read $::R_S2]
    d2_chk [expr {$e == 0 && [lindex $r 1] == 0 && [lindex $r 0] == $magic}] \
        "$tag: abstract GPR write+read round-trip on x18 of hart $h (wrote [format 0x%08X $magic], read [format 0x%08X [lindex $r 0]], cmderr w=$e r=[lindex $r 1])"
    return [expr {[lindex $r 0] == $magic}]
}

if {$PRESENT && $ready} {
    d4_dmactive_on 0
    run 200 us
    d4_control_plant

    # =====================================================================
    # PART 1 -- the loader-launched, RUNNING tile
    # =====================================================================
    dm_select $RUNNER
    dm_haltreq $RUNNER
    set s [dm_poll_status $RUNNER dms_allhalted 400 $::HALTREQ_BIT]
    dm_clr_haltreq $RUNNER
    d2_chk [expr {$s >= 0}] "S0: the running tile halts on haltreq (dmstatus [format 0x%08X $s])"

    # S6's baseline is sampled AFTER the halt is confirmed, not before the
    # request -- same defect class as dbg_tramp.tcl T5, measured the same day.
    # Sampled before, it captures one legitimate pre-halt increment and S6's
    # message then reports "464 -> 465" on a run where the hart never resumed
    # at all: a true verdict carrying a false number.
    set ran0 [sh_get $::DBGTRP_RAN]

    if {$s >= 0} {
        set r [d4_dm_readback $WANT]
        d4_readback_report "S1" $r $WANT
        d2_chk [lindex $r 0] \
            "S1: the entry page reads back 40/40 through the DM -- the session is running the PLANTED code (read [lindex $r 1]/40)"

        sess_gpr_roundtrip "S2" $RUNNER $GPR_MAGIC

        d4_settle
        set e [d4_abs_write $C_MSCRATCH $CSR_MAGIC]
        set rc [d4_abs_read $C_MSCRATCH]
        d2_chk [expr {$e == 0 && [lindex $rc 1] == 0 && [lindex $rc 0] == $CSR_MAGIC}] \
            "S3: abstract CSR write+read round-trip on mscratch (read [format 0x%08X [lindex $rc 0]], cmderr w=$e r=[lindex $rc 1])"

        # ---- the memory round-trip, both ends over DMI -------------------
        # ORDER IS LOAD-BEARING, and the first draft got it wrong.  An abstract
        # GPR write transfers THROUGH data0, so writing a6 and a7 CLOBBERS the
        # data0 word -- which is this leg's source.  Measured 2026-08-07 by the
        # liveness-control arm: the destination came back holding 0x0001006C,
        # the address written into a7, and cmderr was 0, so the leg reported a
        # working progbuf moving the wrong word.  data0 is therefore seeded
        # AFTER both address registers.
        dmi_write $::DM_PROGBUF0 $PB0
        dmi_write $::DM_PROGBUF1 $PB1
        d4_abs_write $R_A6 $::DBG_DATA0_ADDR
        d4_abs_write $R_A7 $MEM_TMP
        dmi_write $::DM_DATA0 $MEM_MAGIC
        dmi_write $::DM_COMMAND [ac_cmd 0 0 0 1]
        set acs [d4_wait_notbusy]
        set moved [sh_get $MEM_TMP]
        d2_chk [expr {$acs >= 0 && [acs_cmderr $acs] == 0 && $moved == $MEM_MAGIC}] \
            "S4: a progbuf lw/sw moved a word OUT through the hart's own bus (0x[format %05X $MEM_TMP] reads [format 0x%08X $moved], cmderr=[expr {$acs < 0 ? -1 : [acs_cmderr $acs]}])"

        # The return leg needs data0 to hold something OTHER than MEM_MAGIC
        # before the postexec, or a stale value would fake the result.  It
        # does, and for free: the a7 write above left 0x00010680 there.  That
        # is the known-nonzero for S5, and it is quoted in the message.
        d4_abs_write $R_A6 $MEM_TMP
        d4_abs_write $R_A7 $::DBG_DATA0_ADDR
        set pre [dmi_read $::DM_DATA0]
        dmi_write $::DM_COMMAND [ac_cmd 0 0 0 1]
        set acs2 [d4_wait_notbusy]
        set back [dmi_read $::DM_DATA0]
        d2_chk [expr {$acs2 >= 0 && [acs_cmderr $acs2] == 0 && $back == $MEM_MAGIC &&
                      $pre != $MEM_MAGIC}] \
            "S5: ...and back IN, observed at data0 over DMI (was [format 0x%08X $pre], now [format 0x%08X $back], cmderr=[expr {$acs2 < 0 ? -1 : [acs_cmderr $acs2]}])"

        dm_resumereq $RUNNER
        set s6 [dm_poll_status $RUNNER dms_allrunning 400]
        run 500 us
        set ran1 [sh_get $::DBGTRP_RAN]
        d2_chk [expr {$s6 >= 0 && $ran1 > $ran0}] \
            "S6: the tile resumes and its counter moves again ($ran0 -> $ran1)"
    }

    # =====================================================================
    # PART 2 -- the ROM-PARKED tile.  Never launched, never executed a word
    # of the test image; it is exactly where the boot ROM left it.
    # =====================================================================
    dm_select $PARKED
    set sp [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {$sp >= 0 && [dms_allrunning $sp] == 1 && [dms_anyunavail $sp] == 0 &&
                  [dms_anynonexist $sp] == 0}] \
        "S7: the ROM-parked hart $PARKED reports RUNNING, not unavail, not nonexistent (dmstatus [format 0x%08X $sp])"

    dm_haltreq $PARKED
    set sp2 [dm_poll_status $PARKED dms_allhalted 400 $::HALTREQ_BIT]
    dm_clr_haltreq $PARKED
    d2_chk [expr {$sp2 >= 0}] \
        "S8: ...and it halts on haltreq (dmstatus [format 0x%08X $sp2])"

    if {$sp2 >= 0} {
        sess_gpr_roundtrip "S9" $PARKED 0x0D260BAD
        dm_resumereq $PARKED
        set sp3 [dm_poll_status $PARKED dms_allrunning 400]
        d2_chk [expr {$sp3 >= 0}] "S10: ...and it resumes"
    } else {
        d2_chk 0 "S9: (unreachable -- the parked hart never halted, see S8)"
        d2_chk 0 "S10: (unreachable -- see S8)"
    }
}

sh_force $::DBGTRP_REL 1
set verdict [d2_run_to_verdict 1600 "25 us"]
d2_report_verdict "dbgtrpmp/sess" $verdict
puts "DMILOG PHASE=[sh_get $::DBGTRP_PHASE] RAN=[sh_get $::DBGTRP_RAN]"
d2_summary "dbgtrpmp/sess" 11
flush stdout
exit
