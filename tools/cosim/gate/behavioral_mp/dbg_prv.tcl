# =============================================================================
# dbg_prv.tcl -- the D2 dcsr.prv harness (carryover 3, R-D1-3(2)).
#
#   ./xrun_dbg.sh rv32ua-p-dbgprvmp dbg_prv.tcl
#
# IT NEEDS debug.enable AND priv.umode IN THE SAME BUILD.  Since R-D2-2(2)
# that row exists: config/castalia_debug.json (the 29th) carries
# "priv": {"trapCsr": true, "umode": true} explicitly.  See dbgprvmp.S's
# header for the history and for why there is no 31st row.
#
# WHAT IT CHECKS (DMILOG):
#   P1  the U-mode victim halts on haltreq
#   P2  an abstract read of dcsr (0x7B0) returns prv = 0 (U).  THIS is
#       carryover 3.  It is worth exactly nothing unless the victim really
#       was in U-mode, which is why the image brackets the visit with two
#       ecalls and grades their mcause -- see dbgprvmp.S.
#   P3  the same dcsr read reports xdebugver = 4 and cause = 3 (haltreq), so
#       a dcsr that returns a plausible-looking constant is caught: a
#       constant that satisfies prv = 0 AND xdebugver = 4 AND cause = 3 is no
#       longer a constant anyone writes by accident, and P4 below moves it.
#   P4  dcsr.prv is WRITABLE (WARL) in debug mode: write prv = 3, read it
#       back as 3, write it back to 0.  A HARDWIRED-ZERO prv passes P2 and
#       fails here -- and hardwired zero is exactly what an implementer who
#       has only ever tested M-mode victims would ship, because on every D1
#       victim prv = 3 was the right answer and on every one of these it is 0.
#       *** If P4 passes with prv left at 3 the victim would resume in
#       M-mode, so it is written back to 0 before the resume, and the image's
#       SECOND ecall (cause 8, from U) is the independent confirmation that
#       the write-back took.  ***
#   P5  resume works
#
# AT UNIMPLEMENTED HEAD dmi_present prints INSTRUMENT_DEAD and the image is
# still run to its own verdict (a1 = 0x0D240003, the victim never released).
# =============================================================================
source ../../disable_x_warnings.tcl
# dbg_bfm.tcl lives beside this file in behavioral_mp/, but a harness is also
# run from the mutation scratch dir (d2mut/), whose CWD is one level across.
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }

set VICTIM 1
set SH_READY 0x10050
set SH_REL   0x10054
set C_DCSR   0x7B0

set PRESENT [dmi_present]

# ---- 1. wait for the victim to reach U-mode and park ----------------------
set ready 0
for {set i 0} {$i < 300} {incr i} {
    run 200 us
    if {[sh_get $SH_READY] == 1} { set ready 1 ; break }
}
puts "DMILOG victim READY=$ready after i=$i  CAUSE1=[format 0x%08X [sh_get 0x1005C]] PROG=[sh_get 0x10068]"
flush stdout
if {!$ready} {
    puts "DMILOG VICTIM_NEVER_REACHED_UMODE -- a test-side or config-side finding."
    puts "DMILOG   This test REQUIRES debug.enable AND priv.umode in one build:"
    puts "DMILOG   config/castalia_debug.json as amended by R-D2-2(2)."
}

dbg_plant_trampoline

if {$PRESENT && $ready} {
    dm_haltreq $VICTIM
    set s [dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT]
    d2_chk [expr {$s >= 0}] "P1: the U-mode victim halted on haltreq"
    dm_clr_haltreq $VICTIM

    if {$s >= 0} {
        set dcsr [ac_read_reg $C_DCSR]
        d2_chk [expr {$dcsr >= 0 && [d2_fld $dcsr 1 0] == 0}] \
            "P2: dcsr.prv = 0 (U) on a U-mode victim -- carryover 3 (dcsr = [format 0x%08X $dcsr])"
        d2_chk [expr {$dcsr >= 0 && [d2_fld $dcsr 31 28] == 4 && [d2_fld $dcsr 8 6] == 3}] \
            "P3: ...and the same dcsr reports xdebugver = 4 and cause = 3 (haltreq)"

        # P4: prv must be WARL-writable, or a hardwired zero passes P2
        set wr [expr {($dcsr & ~3) | 3}]
        ac_write_reg $C_DCSR $wr
        set d2v [ac_read_reg $C_DCSR]
        d2_chk [expr {$d2v >= 0 && [d2_fld $d2v 1 0] == 3}] \
            "P4a: dcsr.prv is WRITABLE in debug mode (wrote 3, read [expr {$d2v<0?-1:[d2_fld $d2v 1 0]}]) -- a hardwired zero passes P2 and fails here"
        set back [expr {($d2v & ~3)}]
        ac_write_reg $C_DCSR $back
        set d3v [ac_read_reg $C_DCSR]
        d2_chk [expr {$d3v >= 0 && [d2_fld $d3v 1 0] == 0}] \
            "P4b: ...and written back to 0, so the victim resumes in U (the image's SECOND ecall is the independent confirmation)"

        dm_resumereq $VICTIM
        set r [dm_poll_status $VICTIM dms_allrunning 400]
        d2_chk [expr {$r >= 0}] "P5: the victim resumed"
    }
}

sh_force $SH_REL 1
set verdict [d2_run_to_verdict 2400 "25 us"]
d2_report_verdict "dbgprvmp" $verdict
puts "DMILOG CAUSE1=[format 0x%08X [sh_get 0x1005C]] CAUSE2=[format 0x%08X [sh_get 0x10060]] UCNT=[sh_get 0x10064] PROG=[sh_get 0x10068]"
d2_summary "dbgprvmp"
flush stdout
exit
