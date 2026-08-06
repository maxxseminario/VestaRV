# =============================================================================
# dbg_abs.tcl -- the D2 ABSTRACT-COMMAND harness (the DMI face of dbgabsmp.S).
#
#   ./xrun_dbg.sh rv32ua-p-dbgabsmp dbg_abs.tcl
#
# It is the debugger: DMI only, no tile-port force.  The image checks the
# ARCHITECTURAL face; this file checks the DMI face.  See dbgabsmp.S's header
# for why neither half can forge the other.
#
# CHECKS (DMILOG CHECK lines; the runner greps for FAILED):
#   A1  the victim halts on haltreq (precondition for everything below)
#   A2  abstract GPR read of x9 returns the victim's GPR_MAGIC
#   A3  abstract GPR write of x18 reports cmderr = 0
#   A4  abstract CSR read of mscratch returns CSR_MAGIC
#   A5  abstract CSR write of mscratch reports cmderr = 0
#   A6  progbuf0/progbuf1 round-trip their written values over DMI
#   A7  a POSTEXEC command with transfer=0 runs the program buffer and
#       reports cmderr = 0 -- and the shared word MEM_DST, read through the
#       RAM model, now holds MEM_MAGIC.  That is DD5's memory answer, moved
#       through the hart's own bus.
#   A8  an abstract read of an UNIMPLEMENTED CSR sets cmderr = EXCEPTION (3)
#   A9  ...and the hart is STILL HALTED afterwards -- not wedged, not resumed
#   A10 ...and cmderr clears W1C and the NEXT abstract command still works,
#       which is the requirement that actually matters
#   A11 data0 mirrors the shared word 0x10680 (hartinfo.dataaddr) -- the
#       proxy semantics of d2_spec 3, checked through the RAM model, which a
#       VHDL bench cannot see
#   A12 the resume works after all of it
#
# AT UNIMPLEMENTED HEAD dmi_present reports INSTRUMENT_DEAD, every check is
# skipped and the image is still run to its own verdict (a1 = 0x0D220003).
# =============================================================================
source ../../disable_x_warnings.tcl
# dbg_bfm.tcl lives beside this file in behavioral_mp/, but a harness is also
# run from the mutation scratch dir (d2mut/), whose CWD is one level across.
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }

set VICTIM 1
set SH_READY   0x10050
set SH_REL     0x10054
set SH_MEM_SRC 0x10064
set SH_MEM_DST 0x10068

set GPR_MAGIC    0x0AB50001
set CSR_MAGIC    0x0AB50002
set MEM_MAGIC    0x0AB50003
set ABS_WR_MAGIC 0x0AB5FEED
set CSR_WR_MAGIC 0x0AB5BEEF

# regno encodings (d2_spec 3: GPRs 0x1000+n, CSRs 0x000-0xFFF)
set R_S1  0x1009      ;# x9
set R_S2  0x1012      ;# x18
set R_A6  0x1010      ;# x16
set R_A7  0x1011      ;# x17
set C_MSCRATCH 0x340
# 0x5A5 is unallocated in EVERY build's csr_addr_valid, including debug mode
# (0x7B0-0x7B3 are LEGAL while the abstract sequence executes, so they are the
# wrong choice for an exception probe -- that is the trap this line avoids).
set C_BAD 0x5A5

# progbuf payload: lw t3,0(a6) then sw t3,0(a7).  Hand-encoded and spelled out
# so a reader can check the arithmetic instead of trusting it:
#   lw  rd=28 rs1=16 imm=0 f3=010 op=0000011 -> 0x00082E03
#   sw  rs2=28 rs1=17 imm=0 f3=010 op=0100011 -> 0x01C8A023
set PB0 0x00082E03
set PB1 0x01C8A023

set PRESENT [dmi_present]

# ---- 1. wait for the victim to publish READY -------------------------------
set ready 0
for {set i 0} {$i < 300} {incr i} {
    run 200 us
    if {[sh_get $SH_READY] == 1} { set ready 1 ; break }
}
puts "DMILOG victim READY=$ready after i=$i"
flush stdout
if {!$ready} {
    puts "DMILOG VICTIM_NEVER_READY -- a test-side finding, not a DM finding."
}

dbg_plant_trampoline

if {$PRESENT} {
    # ---- 2. halt the victim -------------------------------------------
    dm_haltreq $VICTIM
    set s [dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT]
    d2_chk [expr {$s >= 0}] "A1: the victim halted on haltreq"
    dm_clr_haltreq $VICTIM

    if {$s >= 0} {
        # ---- 3. abstract GPR read -------------------------------------
        set v [ac_read_reg $R_S1]
        d2_chk [expr {$v == $GPR_MAGIC}] \
            "A2: abstract GPR read of x9 = [format 0x%08X $v] (want [format 0x%08X $GPR_MAGIC])"

        # ---- 4. abstract GPR write ------------------------------------
        d2_chk [ac_write_reg $R_S2 $ABS_WR_MAGIC] \
            "A3: abstract GPR write of x18 reported cmderr = 0"

        # ---- 5. abstract CSR read + write -----------------------------
        set v [ac_read_reg $C_MSCRATCH]
        d2_chk [expr {$v == $CSR_MAGIC}] \
            "A4: abstract CSR read of mscratch = [format 0x%08X $v]"
        d2_chk [ac_write_reg $C_MSCRATCH $CSR_WR_MAGIC] \
            "A5: abstract CSR write of mscratch reported cmderr = 0"

        # ---- 6. the program buffer ------------------------------------
        dmi_write $::DM_PROGBUF0 $PB0
        dmi_write $::DM_PROGBUF1 $PB1
        set r0 [dmi_read $::DM_PROGBUF0]
        set r1 [dmi_read $::DM_PROGBUF1]
        d2_chk [expr {$r0 == $PB0 && $r1 == $PB1}] \
            "A6: progbuf0/1 round-trip their written values"

        ac_write_reg $R_A6 $SH_MEM_SRC
        ac_write_reg $R_A7 $SH_MEM_DST
        # transfer = 0, postexec = 1: run the program buffer and nothing else.
        # progbufsize is 2 and this sequence needs three words to return, so
        # a PASS here is also impebreak working.
        dmi_write $::DM_COMMAND [ac_cmd 0 0 0 1]
        set acs [dm_wait_notbusy]
        d2_chk [expr {$acs >= 0 && [acs_cmderr $acs] == 0}] \
            "A7a: POSTEXEC ran the program buffer with cmderr = 0"
        set dst [sh_get $SH_MEM_DST]
        d2_chk [expr {$dst == $MEM_MAGIC}] \
            "A7b: the progbuf lw/sw moved the word -- MEM_DST = [format 0x%08X $dst] (DD5's memory answer, through the hart's own bus)"

        # ---- 7. the EXCEPTION cmderr ----------------------------------
        dmi_write $::DM_COMMAND [ac_cmd $C_BAD 0 1 0]
        set acs [dm_wait_notbusy]
        d2_chk [expr {$acs >= 0 && [acs_cmderr $acs] == $::CMDERR_EXCEPTION}] \
            "A8: an abstract read of an unimplemented CSR sets cmderr = EXCEPTION (got [expr {$acs < 0 ? -1 : [acs_cmderr $acs]}])"
        set s2 [dmi_read $::DM_DMSTATUS]
        d2_chk [expr {[dms_allhalted $s2] == 1}] \
            "A9: ...and the hart is STILL HALTED -- an exception in debug mode is not a wedge and not a resume"
        ac_clear_cmderr
        set v [ac_read_reg $R_S1]
        d2_chk [expr {$v == $GPR_MAGIC}] \
            "A10: ...and the NEXT abstract command still works after the exception"

        # ---- 8. the data0 proxy, seen from the RAM model --------------
        dmi_write $::DM_DATA0 0x0D2ADD00
        set w [sh_get $::DBG_DATA0_ADDR]
        d2_chk [expr {$w == 0x0D2ADD00}] \
            "A11: data0 is a PROXY for shared [format 0x%05X $::DBG_DATA0_ADDR] -- the word itself reads [format 0x%08X $w] (a VHDL bench cannot see this half)"

        # ---- 9. resume -------------------------------------------------
        dm_resumereq $VICTIM
        set s3 [dm_poll_status $VICTIM dms_allrunning 400]
        d2_chk [expr {$s3 >= 0}] "A12: the victim resumed after all of it"
    }
}

# ---- 10. release the victim's park and let the image grade itself ---------
# A forced shared word is the harness -> in-band channel; it is the measured
# mechanism (dbg_bfm.tcl header) and it is never used for a word the design
# writes.
sh_force $SH_REL 1
set verdict [d2_run_to_verdict 2400 "25 us"]
d2_report_verdict "dbgabsmp" $verdict
puts "DMILOG OBS_S2=[format 0x%08X [sh_get 0x1005C]] OBS_MSCR=[format 0x%08X [sh_get 0x10060]] OBS_S1=[format 0x%08X [sh_get 0x1006C]]"
puts "DMILOG MEM_SRC=[format 0x%08X [sh_get 0x10064]] MEM_DST=[format 0x%08X [sh_get 0x10068]] PROG=[sh_get 0x10070]"
d2_summary "dbgabsmp"
flush stdout
exit
