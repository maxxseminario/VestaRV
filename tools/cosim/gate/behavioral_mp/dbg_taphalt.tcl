# =============================================================================
# dbg_taphalt.tcl -- D3 instrument T5: THE END-TO-END PROOF.
# Halt a RUNNING hart, read one of its registers, and resume it -- all of it
# through the JTAG pins, on a chip whose other harts are doing real work.
# This is the D2 headline (dbg_dmi.tcl) driven from the pads instead of from a
# forced port, and it is the sentence D3 exists to be able to say.
#
#   ./xrun_dbg.sh xrv32ua-p-dbgdmimp dbg_taphalt.tcl
#   (N=18: the argus_debug staged runner, ../kf0/xrv32ua-p-dbgdmimp.rcf)
#
# BLIND-AUTHORED 2026-08-06 against d3_spec.md 6 (FROZEN).
#
# WHY IT RIDES dbgdmimp AND NOT A PLAIN rv32ui IMAGE
#   dmstatus cannot tell you whether a hart is making PROGRESS -- `running` is
#   a state, and a wedged hart reads running too.  dbgdmimp launches three
#   victim harts that increment three shared counters (0x10054/58/5C, already
#   ledgered as part of the D-series acceptance band 0x10050-0x1007C; this file
#   only READS them and claims nothing new).  Those counters are what turn
#   "the status bit changed" into "execution stopped and started again".
#   Every claim below about halting and resuming is made TWICE: once from
#   dmstatus, once from the counters.  Either alone is forgeable.
#
# THE mhartid LEG IS THE SHARPEST CHECK IN THE D3 SET.  An abstract read of CSR
# 0xF14 through the DM must return the number of the hart the DM says it
# selected.  A DM that executes the abstract sequence on the wrong hart, or a
# DTM that corrupts the 10-bit hartsel field on its way across the crossing,
# passes every status check in this file and fails this one -- and the answer
# it returns names the hart it actually reached.
#
# CHECK LIST (E-numbers; the runner greps for "CHECK FAILED"):
#   E0  the five JTAG pins exist                (else INSTRUMENT_DEAD)
#   E1  precondition: all three victim counters are ADVANCING before anything
#       is halted (exits early on the event, never on a schedule)
#   E2  the victim reads RUNNING through the TAP, both pair bits driven
#   E3  haltreq written over JTAG halts it: all- AND anyhalted
#   E4  haltsum0 reads EXACTLY the victim's bit -- the right hart, from a
#       different register
#   E5  the other two victims still read RUNNING
#   E6  ...and their counters are still ADVANCING (dmstatus cannot say this)
#   E7  ...while the halted hart's counter is FROZEN.  E6 without E7 is
#       satisfied by a chip where nothing halted at all
#   E8  an abstract read of a GPR through the TAP returns cmderr = NONE
#   E9  an abstract read of CSR 0xF14 (mhartid) returns THE VICTIM'S OWN ID --
#       the sequence really executed on the selected hart
#   E10 resumereq over JTAG resumes it: running again, resumeack set
#   E11 ...and its counter ADVANCES again -- resume means execution, not a bit
#   E12 haltsum0 is back to zero
#   E13 the image's own verdict (a0), which measures forward progress in band
#
# AT UNIMPLEMENTED HEAD tap_present prints TAP_PORT_ABSENT / INSTRUMENT_DEAD,
# every check is skipped, and the run continues so the IMAGE is also seen to
# fail its own way -- both halves of the two-part FAIL leg in one run.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tap.tcl]} { source dbg_tap.tcl } else { source ../behavioral_mp/dbg_tap.tcl }

set NHARTS 4
if {[info exists ::env(D2_NHARTS)]} { set NHARTS $::env(D2_NHARTS) }

# dbgdmimp's three victims and their counters (dbg_dmi.tcl:56-59, the D2
# headline harness -- the same words, deliberately, so the two instruments are
# asking one question over two transports).
set VICTIM 2
set CNT(1) 0x10054
set CNT(2) 0x10058
set CNT(3) 0x1005C

set PRESENT [tap_present]

proc cnts {} {
    global CNT
    set out {}
    foreach h {1 2 3} { lappend out [sh_get $CNT($h)] }
    return $out
}
proc advanced {a b i} { expr {[lindex $b $i] > [lindex $a $i]} }

# ---- E1: wait for real forward progress, bounded, exiting on the EVENT -----
set p [cnts]
set started 0
for {set i 0} {$i < 200} {incr i} {
    run 200 us
    set q [cnts]
    if {[advanced $p $q 0] && [advanced $p $q 1] && [advanced $p $q 2]} {
        set started 1 ; break
    }
}
d2_chk $started \
    "E1: all three victims are counting before anything is halted (counters [cnts])"

if {$PRESENT && $started} {
    # THE TRAMPOLINE, and its absence was instrument defect I-3.
    # E8-E13 (abstract GPR read, mhartid, resume, the counter restarting,
    # haltsum0, the image's own a0) ALL depend on code being present at
    # DEBUG_ENTRY_ADDR: a valid abstract command on a progbuf-first DM is
    # EXECUTED BY THE HALTED HART there.  With nothing planted, the hart
    # cannot publish its token, the DM waits out its own POLL_LIMIT, and six
    # checks fail ON CORRECT RTL -- the SS9a class, in my own set, with
    # dbg_conf.tcl's header documenting the exact trap and dbg_dmi.tcl
    # planting one.  Measured by the implementation wave: identical file plus
    # this one line gives 17/17 at N=4 AND N=18.
    dbg_plant_trampoline

    tap_init
    tap_calibrate_idle 8

    # ---- E2: the victim is running ---------------------------------------
    dmi_write_tap $::DM_DMCONTROL [expr {($VICTIM << 16) | 1}]
    set s [dmi_read_tap $::DM_DMSTATUS]
    d2_chk [expr {[dms_allrunning $s] == 1 && [dms_anyrunning $s] == 1}] \
        "E2: hart $VICTIM reads all- AND anyrunning through the TAP before the request"

    # ---- E3: halt it ------------------------------------------------------
    # haltreq is HELD across the poll (the dm_poll_status `hold` lesson): each
    # poll round rewrites dmcontrol, and rewriting it without the bit would
    # take the request away invisibly.
    set held [expr {1 << 31}]
    set s -1
    for {set i 0} {$i < 400} {incr i} {
        dmi_write_tap $::DM_DMCONTROL [expr {($VICTIM << 16) | $held | 1}]
        set v [dmi_read_tap $::DM_DMSTATUS]
        if {$v >= 0 && [dms_allhalted $v]} { set s $v ; break }
        run 2 us
    }
    d2_chk [expr {$s >= 0}] "E3a: haltreq written over JTAG halted hart $VICTIM"
    if {$s >= 0} {
        d2_chk [expr {[dms_anyhalted $s] == 1}] "E3b: anyhalted is driven too"
        d2_chk [expr {[dms_allrunning $s] == 0}] "E3c: running went low"
    }
    dmi_write_tap $::DM_DMCONTROL [expr {($VICTIM << 16) | 1}]

    # ---- E4: haltsum0 names the right hart --------------------------------
    set hs [dmi_read_tap $::DM_HALTSUM0]
    d2_chk [expr {$hs == (1 << $VICTIM)}] \
        "E4: haltsum0 = [format 0x%08X $hs], want [format 0x%08X [expr {1 << $VICTIM}]] -- the right hart, read from a different register"

    # ---- E5/E6/E7: who is still working -----------------------------------
    foreach h {1 3} {
        dmi_write_tap $::DM_DMCONTROL [expr {($h << 16) | 1}]
        set v [dmi_read_tap $::DM_DMSTATUS]
        d2_chk [expr {[dms_allrunning $v] == 1}] \
            "E5/$h: hart $h still reads RUNNING while hart $VICTIM is halted"
    }
    set a [cnts]
    run 400 us
    set b [cnts]
    d2_chk [expr {[advanced $a $b 0] && [advanced $a $b 2]}] \
        "E6: the other two victims' counters ADVANCED while hart $VICTIM was halted ([lindex $a 0]->[lindex $b 0], [lindex $a 2]->[lindex $b 2])"
    d2_chk [expr {[lindex $a 1] == [lindex $b 1]}] \
        "E7: ...and hart $VICTIM's counter is FROZEN at [lindex $b 1] -- it really stopped executing"

    # ---- E8/E9: abstract access through the TAP ---------------------------
    dmi_write_tap $::DM_DMCONTROL [expr {($VICTIM << 16) | 1}]
    ac_clear_cmderr_tap
    dmi_write_tap $::DM_COMMAND [ac_cmd 0x1008 0 1 0]     ;# GPR x8
    set acs -1
    for {set i 0} {$i < 400} {incr i} {
        set acs [dmi_read_tap $::DM_ABSTRACTCS]
        if {$acs >= 0 && [acs_busy $acs] == 0} { break }
        run 2 us
    }
    d2_chk [expr {$acs >= 0 && [acs_cmderr $acs] == 0}] \
        "E8: an abstract GPR read over JTAG completed with cmderr = [expr {$acs<0?-1:[acs_cmderr $acs]}], want 0"

    ac_clear_cmderr_tap
    dmi_write_tap $::DM_COMMAND [ac_cmd 0x0F14 0 1 0]     ;# CSR mhartid
    set acs -1
    for {set i 0} {$i < 400} {incr i} {
        set acs [dmi_read_tap $::DM_ABSTRACTCS]
        if {$acs >= 0 && [acs_busy $acs] == 0} { break }
        run 2 us
    }
    set hid [dmi_read_tap $::DM_DATA0]
    d2_chk [expr {$acs >= 0 && [acs_cmderr $acs] == 0 && $hid == $VICTIM}] \
        "E9: abstract read of mhartid (CSR 0xF14) over JTAG returned $hid, want $VICTIM -- the sequence executed ON THE SELECTED HART, and the 10-bit hartsel survived the crossing"

    # ---- E10/E11: resume ---------------------------------------------------
    set s -1
    for {set i 0} {$i < 400} {incr i} {
        dmi_write_tap $::DM_DMCONTROL [expr {($VICTIM << 16) | (1 << 30) | 1}]
        set v [dmi_read_tap $::DM_DMSTATUS]
        if {$v >= 0 && [dms_allrunning $v]} { set s $v ; break }
        run 2 us
    }
    d2_chk [expr {$s >= 0}] "E10a: resumereq written over JTAG resumed hart $VICTIM"
    if {$s >= 0} {
        d2_chk [expr {[dms_allresumeack $s] == 1 || [dms_anyresumeack $s] == 1}] \
            "E10b: resumeack is set"
    }
    set a [cnts]
    run 400 us
    set b [cnts]
    d2_chk [expr {[advanced $a $b 1]}] \
        "E11: hart $VICTIM's counter ADVANCES again ([lindex $a 1]->[lindex $b 1]) -- resume means execution, not a status bit"

    set hs [dmi_read_tap $::DM_HALTSUM0]
    d2_chk [expr {$hs == 0}] "E12: haltsum0 is back to [format 0x%08X $hs], want 0"
}

tap_cost "dbg_taphalt"
set verdict [d2_run_to_verdict 2400 "25 us"]
d2_report_verdict "dbg_taphalt" $verdict
d2_chk [expr {$verdict eq "PASSED"}] \
    "E13: the image's own in-band verdict is $verdict -- forward progress measured by the harts themselves"
tap_summary "dbg_taphalt" $PRESENT 14
flush stdout
