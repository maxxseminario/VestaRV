# =============================================================================
# dbg_dmi.tcl -- THE HEADLINE D2 harness: halt ONE hart through the Debug
# Module while the others keep running, then resume it.
#
#   ./xrun_dbg.sh rv32ua-p-dbgdmimp dbg_dmi.tcl
#
# THIS HARNESS IS THE DEBUGGER.  It drives the MCU's frozen d2_spec-2 DMI port
# and nothing else.  It NEVER forces a tile dbg_* port -- that was D1's
# mechanism and it is exactly what D2 replaces: here the DM does the halting,
# and if the DM does not, the instrument says so.
#
# WHAT IT CHECKS ITSELF (DMILOG CHECK lines; the runner greps for FAILED):
#   H1  hart 2 reads RUNNING before the request (both pair bits driven)
#   H2  dmcontrol.haltreq halts it: all- AND anyhalted, within budget
#   H3  haltsum0 reads EXACTLY bit 2 -- the right hart, from the other
#       register, so a dmstatus that mirrors hartsel blindly cannot pass both
#   H4  harts 1 and 3 still read RUNNING while 2 is halted
#   H5  hart 2 STAYS halted after haltreq is dropped (halt is a state)
#   H6  dmcontrol.resumereq resumes it: running again, and resumeack set
#   H7  resumeack is STICKY-until-next-resumereq, not a pulse the poll caught
#       by luck: it still reads 1 on a second dmstatus read
#   R1-R4  THE RE-ARMED WIRE (added 2026-08-06 under R-D2-2(5)).  d2_spec 4
#       as amended DEFINES `resumereq` written while `dmcontrol.haltreq` is
#       still held: the hart resumes (resumeack sets) and then RE-HALTS with
#       no further DMI write.  The D1 core will not do that on its own -- its
#       wait-for-release flop collapses a held request to exactly ONE entry --
#       so the re-halt can only come from the DM re-arming the wire, and this
#       ordering is the ONLY DMI-visible signature it has.  The four checks
#       are an ORDERING and contain no duration:
#         R1 haltreq (HELD, never cleared) halts hart 2 again
#         R2 resumereq written WITH haltreq still set sets resumeack
#         R3 ...and then halted reads 1 AGAIN, with NOTHING written between
#            R2's read and this one.  R3 IS the re-arm.
#         R4 clearing both bits finally lets it run
#       R2 must PASS for R3 to mean anything: a DM that simply ignored the
#       resumereq would leave the hart halted throughout and satisfy R3 by
#       accident, so R2 and R3 are a pair and are graded as one.
#
# WHAT THE IMAGE CHECKS, and why the split (see dbgdmimp.S's header): dmstatus
# cannot say whether the OTHER harts made forward progress -- `running` is a
# state, and a wedged hart reads running too.  The image measures that with
# three shared counters, in band.  The verdict of this instrument is BOTH:
# the test's a0 AND the absence of DMILOG CHECK FAILED.
#
# AT UNIMPLEMENTED HEAD there is no dmi_* port at all: dmi_present reports
# PORT_ABSENT / INSTRUMENT_DEAD, every check is skipped, and the run continues
# so the IMAGE is also seen to fail its own way (a1 = 0x0D210004, no hart ever
# stopped).  Both halves of the D1 two-part FAIL leg, in one run.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
# dbg_bfm.tcl lives beside this file in behavioral_mp/, but a harness is also
# run from the mutation scratch dir (d2mut/), whose CWD is one level across.
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }

set VICTIM  2
set CNT1 0x10054
set CNT2 0x10058
set CNT3 0x1005C

set PRESENT [dmi_present]

# ---- 1. let the chip boot and all three victims start counting -------------
# Bounded, and it EXITS EARLY on the event rather than running a schedule:
# what matters is that the counters are moving before anything is halted.
set started 0
set p1 [sh_get $CNT1] ; set p2 [sh_get $CNT2] ; set p3 [sh_get $CNT3]
for {set i 0} {$i < 200} {incr i} {
    run 200 us
    set n1 [sh_get $CNT1] ; set n2 [sh_get $CNT2] ; set n3 [sh_get $CNT3]
    if {$n1 > $p1 && $n2 > $p2 && $n3 > $p3} { set started 1 ; break }
    set p1 $n1 ; set p2 $n2 ; set p3 $n3
}
puts "DMILOG boot i=$i started=$started CNT=[format {%d %d %d} [sh_get $CNT1] [sh_get $CNT2] [sh_get $CNT3]]"
flush stdout
if {!$started} {
    puts "DMILOG COUNTERS_NEVER_STARTED -- the IMAGE never got its victims"
    puts "DMILOG   running.  That is a test-side finding, not a DM finding."
}

# ---- 2. the D4-ROM stand-in --------------------------------------------
dbg_plant_trampoline

# ---- 3. halt the victim through DMI ----------------------------------------
if {$PRESENT} {
    dm_select $VICTIM
    set s [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_allrunning $s] == 1 && [dms_anyrunning $s] == 1}] \
        "H1: hart $VICTIM reads all- AND anyrunning before the halt request"

    dm_haltreq $VICTIM
    set s [dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT]
    d2_chk [expr {$s >= 0}] "H2a: dmcontrol.haltreq halted hart $VICTIM (allhalted)"
    if {$s >= 0} {
        d2_chk [expr {[dms_anyhalted $s] == 1}] "H2b: ...anyhalted is driven too"
        d2_chk [expr {[dms_allrunning $s] == 0}] "H2c: ...and running went low"
    }

    set hs [dmi_read $::DM_HALTSUM0]
    d2_chk [expr {$hs == (1 << $VICTIM)}] \
        "H3: haltsum0 = [format 0x%X [expr {1 << $VICTIM}]] -- exactly the "
    puts "DMILOG   (haltsum0 read back [format 0x%08X $hs]; H3 is the SECOND "
    puts "DMILOG   register to name the hart, so a dmstatus that merely echoes"
    puts "DMILOG   hartsel cannot satisfy H2 and H3 together)"

    foreach h [list 1 3] {
        dm_select $h
        set s [dmi_read $::DM_DMSTATUS]
        d2_chk [expr {[dms_allhalted $s] == 0 && [dms_allrunning $s] == 1}] \
            "H4.$h: hart $h still reads RUNNING while hart $VICTIM is halted"
    }

    dm_clr_haltreq $VICTIM
    dm_select $VICTIM
    set s [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_allhalted $s] == 1}] \
        "H5: hart $VICTIM STAYS halted after haltreq is dropped"

    # ---- 4. hold the halt long enough for the IMAGE to see it -------------
    # hart 0's snapshot interval is ~250 us; three of them is a lower bound,
    # and a longer hold gives the same verdict.  Nothing is tuned onto an
    # instruction here.
    run 1500 us

    # ---- 5. resume ---------------------------------------------------------
    dm_resumereq $VICTIM
    set s [dm_poll_status $VICTIM dms_allrunning 400]
    d2_chk [expr {$s >= 0}] "H6a: dmcontrol.resumereq resumed hart $VICTIM"
    if {$s >= 0} {
        d2_chk [expr {[dms_allresumeack $s] == 1 && [dms_anyresumeack $s] == 1}] \
            "H6b: ...and both resumeack bits are set"
        set s2 [dmi_read $::DM_DMSTATUS]
        d2_chk [expr {[dms_allresumeack $s2] == 1}] \
            "H7: resumeack is STICKY until the next resumereq -- it is not a"
        puts "DMILOG   one-cycle pulse the poll happened to catch"
    }
    set hs [dmi_read $::DM_HALTSUM0]
    d2_chk [expr {$hs == 0}] "H8: haltsum0 back to 0 after the resume"

    # ---- 6. THE RE-ARMED WIRE (R-D2-2(5)) --------------------------------
    # haltreq goes up and is NEVER cleared until R4.  Everything between is
    # one held level and one resumereq.
    dm_haltreq $VICTIM
    set s [dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT]
    d2_chk [expr {$s >= 0}] "R1: haltreq (HELD from here) halted hart $VICTIM again"

    if {$s >= 0} {
        dm_resume_under_held_halt $VICTIM
        set s [dm_poll_status_ro dms_allresumeack 400]
        d2_chk [expr {$s >= 0}]             "R2: resumereq written WITH haltreq still held set resumeack -- the hart really did resume"
        if {$s >= 0} {
            # NOTHING is written to the DM between R2 and R3: BOTH polls are
            # dm_poll_status_ro, which writes nothing at all.  That matters --
            # the ordinary dm_poll_status re-writes dmcontrol every round to
            # keep hartsel right, and any write here would let a reader argue
            # the re-halt was manufactured by a fresh haltreq edge.
            set s [dm_poll_status_ro dms_allhalted 400]
            d2_chk [expr {$s >= 0}]                 "R3: ...and hart $VICTIM RE-HALTED with no further DMI write -- THE re-armed-wire signature (d2_spec 4 as amended)"
        }
        # R4, RE-SHAPED (R-D2-6(5)(iii)).  The first draft cleared haltreq and
        # then required the hart to RUN -- i.e. it demanded resume-on-
        # haltreq-clear, which contradicts spec 4 (resume is `resumereq` and
        # nothing else) AND contradicts this very file's own C18/H5, which
        # assert that a halted hart STAYS halted when haltreq is dropped.  An
        # instrument cannot require both.  R4 now asserts the defined
        # contract, in two ordered halves in one check:
        #   (a) clearing haltreq alone leaves it HALTED, then
        #   (b) `resumereq` releases it.
        dmi_write $::DM_DMCONTROL [dm_dmcontrol $VICTIM]
        set sh [dmi_read $::DM_DMSTATUS]
        set still [expr {$sh >= 0 && [dms_allhalted $sh] == 1}]
        dm_resumereq $VICTIM
        set s [dm_poll_status $VICTIM dms_allrunning 400]
        d2_chk [expr {$still && $s >= 0}] \
            "R4: clearing haltreq alone left hart $VICTIM HALTED (still=$still), and resumereq then released it -- resume is resumereq and nothing else"
    }
}

# ---- 6. the image's own verdict --------------------------------------------
set verdict [d2_run_to_verdict 2400 "25 us"]
d2_report_verdict "dbgdmimp" $verdict
puts "DMILOG final CNT=[format {%d %d %d} [sh_get $CNT1] [sh_get $CNT2] [sh_get $CNT3]]"
puts "DMILOG STOPPED_H=[format 0x%08X [sh_get 0x10060]] RESUMED_H=[format 0x%08X [sh_get 0x10064]] STALLMAP=[format 0x%08X [sh_get 0x10070]]"
puts "DMILOG ADV1=[sh_get 0x10068] ADV3=[sh_get 0x1006C] PHASE=[sh_get 0x10050] REARM=[sh_get 0x10074]"
foreach h [list 1 2 3] { puts "DMILOG   hart$h state=[d2_state $h]" }
d2_summary "dbgdmimp"
flush stdout
exit
