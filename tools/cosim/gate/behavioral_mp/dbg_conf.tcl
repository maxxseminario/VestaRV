# =============================================================================
# dbg_conf.tcl -- the DM REGISTER-MAP CONFORMANCE checks of d2_spec section 3,
# run over the PROVEN riscv_tb flow.
#
#   ./xrun_dbg.sh xxxxxxrv32ui-p-add dbg_conf.tcl
#
# WHY THIS EXISTS BESIDE hdl/common/tb/dbg_dmi_tb.vhd, and the honest reason
# ---------------------------------------------------------------------------
# The VHDL bench (instrument J1) is the file that NAMES the frozen d2_spec-2
# DMI port in VHDL, so a missing or renamed port is an ELABORATION ERROR
# there -- that is its unique and irreplaceable job, and it was demonstrated
# doing it (8 x *E,FMLUNK, one per formal, and nothing else).  But that bench
# builds its own reduced MCU environment, and MEASURED at authoring time it
# does NOT free-run: simulation time freezes around 0.7 ms with xmsim at 100 %
# CPU -- CLAUDE.md's combinational-loop signature -- and it does so with the
# stimulus process idle, so it is the environment and not the checks.  Root
# cause was NOT found inside the D2 acceptance wave and is reported to Fable.
#
# riscv_tb, by contrast, is the environment the whole 142-test suite runs in
# every day.  So the same conformance list is ALSO expressed here, over the
# tcl DMI BFM (dbg_bfm.tcl), on that environment.  Neither file makes the
# other redundant: J1 catches an absent port at compile time, this one grades
# the register map on a chip that is known to run.  Whichever the implementer
# fixes first, the other still has to pass.
#
# THE CHECK LIST is d2_spec section 8's first bullet, one for one with the
# VHDL bench's C-numbers so the two logs can be diffed against each other:
#   K1  dmstatus.version = 3      K2  authenticated = 1
#   K3  hasresethaltreq = 1       K4  impebreak = 1
#   K5  hartinfo.dataaddr = 0x10680, dataaccess = 1, datasize = 1
#   K6  abstractcs progbufsize = 2, datacount = 1, busy = 0, cmderr = 0
#   K7  hartsel WARL width; hartselhi, ndmreset, hartreset, hasel read zero
#   K8  out-of-range hartsel -> NONEXISTENT, NOT Spike's clamp; and hartsel
#       = N-1 is existent (the pair -- either half alone is forgeable)
#   K9  haltsum0 (0x40) = 0, op success   K10 haltsum1 (0x13) = 0, op SUCCESS
#   K11 an unimplemented DMI address returns FAILED (K10's counterpart)
#   K12 data0 proxy round trip, TWICE, and the shared word 0x10680 agrees
#   K13 cmderr is W1C in BOTH directions (write 0 must NOT clear)
#   K14 abstractauto reads zero        K15 dmcs2 group WARL to 8 groups
#   K16 hart 1 reads RUNNING, then haltreq halts it, then it STAYS halted
#   K17 haltsum0 now reads exactly bit 1 -- which is what makes K9 evidence
#       instead of a hardwired zero (method rule 5)
#   K18 hart 2 is still running: the halt was per-hart
#   K19 cmdtype 2 (access memory) on the HALTED hart -> NOT_SUPPORTED, which
#       IS DD5's memory answer
#   K20 aarsize = 3 on the HALTED hart -> NOT_SUPPORTED
#   K21 R5's CORNER (added 2026-08-06, R-D2-8(5)): a `command` written while
#       cmderr is NONZERO must be IGNORED -- cmderr keeps its old value and
#       busy never rises -- and the SAME command must run once cmderr is
#       cleared W1C.  Two checks, and they are a pair: K21a alone is
#       satisfied by a DM that has stopped accepting commands at all, and
#       K21b is what excludes that.
#
# It rides whatever image is on hart 0 and asserts nothing about it, so the
# cheapest invocation is a plain rv32ui test.  The halted hart is hart 1,
# which is parked in the bootrom's WFI and has no work to lose.
#
# AT UNIMPLEMENTED HEAD dmi_present prints PORT_ABSENT / INSTRUMENT_DEAD and
# every check is skipped -- the part-1 seen-to-FAIL leg.
# =============================================================================
source ../../disable_x_warnings.tcl
# dbg_bfm.tcl lives beside this file in behavioral_mp/, but a harness is also
# run from the mutation scratch dir (d2mut/), whose CWD is one level across.
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }

set NHARTS 4
if {[info exists ::env(D2_NHARTS)]} { set NHARTS $::env(D2_NHARTS) }
proc hartsel_w {n} { set w 0 ; set p 1 ; while {$p < $n} { set p [expr {$p*2}] ; incr w } ; if {$w == 0} { set w 1 } ; return $w }
set W [hartsel_w $NHARTS]
set HS_MAX [expr {(1 << $W) - 1}]   ;# retained for reference only -- R-D2-4(1)
                                    ;# retired the masked-readback contract

set PRESENT [dmi_present]

# Let the tiles finish the ROM boot and park.  A LOWER BOUND, and K16 asserts
# the precondition (hart 1 running) rather than assuming it.
run 2 ms

# THE TRAMPOLINE, added at the validation wave (2026-08-06) with K21b.
# For K0-K20 this harness needed none: every command it issues is REFUSED
# before execution (K13a HALT_RESUME, K19/K20 NOT_SUPPORTED), so no halted
# hart ever had to run anything, and the header's "resuming it needs the
# trampoline, and that belongs to the in-band instruments" was true.
# K21b broke that: it is the FIRST check here that issues a VALID abstract
# command, and a valid command on a progbuf-first DM is executed BY THE HART
# at DEBUG_ENTRY_ADDR.  With nothing planted there the halted hart cannot
# publish TOK_HALTED, the DM waits out its own POLL_LIMIT (65535 mclk,
# ~2.7 ms), and dm_wait_notbusy's 400 x 2 us budget expires first and returns
# -1 -- so K21b FAILED at the baseline on a DM that was behaving correctly.
# That is the SS9a class (a check that fails on correct RTL) in the author's
# own set, and this is its fix: plant the trampoline the way all ten sibling
# harnesses do, BEFORE any hart is halted.
dbg_plant_trampoline

if {$PRESENT} {
    dm_select 0
    set s [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {$::DMI_ROP == 0}] "K0: dmstatus read returns op = success"
    d2_chk [expr {[dms_version $s] == 3}] \
        "K1: dmstatus.version = 3 (got [dms_version $s]; Spike's 2 is the deviation, not the reference)"
    d2_chk [expr {[dms_authenticated $s] == 1}] "K2: dmstatus.authenticated = 1"
    d2_chk [expr {[dms_hasresethaltreq $s] == 1}] \
        "K3: dmstatus.hasresethaltreq = 1 (D1 shipped the wire; Spike reads 0 and is not the reference)"
    d2_chk [expr {[dms_impebreak $s] == 1}] "K4: dmstatus.impebreak = 1"

    set hi [dmi_read $::DM_HARTINFO]
    d2_chk [expr {[d2_fld $hi 11 0] == 0x680 && [d2_fld $hi 16 16] == 1 && [d2_fld $hi 15 12] == 1}] \
        "K5: hartinfo dataaddr=0x680 dataaccess=1 datasize=1 (got [format 0x%08X $hi])"

    set acs [dmi_read $::DM_ABSTRACTCS]
    d2_chk [expr {[acs_progbufsize $acs] == 2 && [acs_datacount $acs] == 1 &&
                  [acs_busy $acs] == 0 && [acs_cmderr $acs] == 0}] \
        "K6: abstractcs progbufsize=2 datacount=1 busy=0 cmderr=0 (got [format 0x%08X $acs])"

    # hartsello[25:16] AND hartselhi[15:6] all ones, dmactive set, bits 1-5
    # left clear (set+clr resethaltreq together is ambiguous, not stronger)
    dmi_write $::DM_DMCONTROL 0x03FFFFC1
    set dc [dmi_read $::DM_DMCONTROL]
    d2_chk [expr {[d2_fld $dc 25 16] == 0x3FF}] \
        "K7a: hartsello stores ALL TEN bits at both N (read [format 0x%03X [d2_fld $dc 25 16]], want 0x3FF) -- R-D2-4(1): no mask, no clamp"
    d2_chk [expr {[d2_fld $dc 15 6] == 0}] "K7b: hartselhi reads zero"
    d2_chk [expr {[d2_fld $dc 1 1] == 0}]  "K7c: ndmreset reads zero (WARL, D3 residue)"
    d2_chk [expr {[d2_fld $dc 29 29] == 0}] "K7d: hartreset reads zero (WARL, D3 residue)"
    d2_chk [expr {[d2_fld $dc 26 26] == 0}] "K7e: hasel reads zero (dropped at D2)"

    # K8 now probes with the SMALLEST out-of-range value rather than 0x3FF.
    # NHARTS+1 is the value a bit-masking implementation would silently fold
    # onto a REAL hart (5 -> hart 1 at N=4), which is precisely the failure
    # class the anti-clamp rationale condemns and the reason R-D2-4(1) made
    # hartsello wide.  0x3FF cannot catch it; this can.
    dmi_write $::DM_DMCONTROL [expr {(($NHARTS + 1) << 16) | 1}]
    set dc [dmi_read $::DM_DMCONTROL]
    set s [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_anynonexist $s] == 1 && [dms_allnonexist $s] == 1 &&
                  [d2_fld $dc 25 16] == ($NHARTS + 1)}] \
        "K8a: hartsel = NHARTS+1 reads back UNMASKED and reports BOTH nonexistent bits"
    d2_chk [expr {[dms_allhalted $s] == 0 && [dms_anyhalted $s] == 0 &&
                  [dms_allrunning $s] == 0 && [dms_anyrunning $s] == 0}] \
        "K8b: ...and it did NOT clamp onto a real hart the way Spike does"
    dm_select [expr {$NHARTS - 1}]
    set s [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_anynonexist $s] == 0}] \
        "K8c: hartsel = NHARTS-1 is EXISTENT (the pair that stops a hardwired nonexistent from passing K8a)"

    dm_select 0
    set hs [dmi_read $::DM_HALTSUM0]
    d2_chk [expr {$::DMI_ROP == 0 && $hs == 0}] "K9: haltsum0 = 0, op success, nothing halted"
    set h1 [dmi_read $::DM_HALTSUM1]
    d2_chk [expr {$::DMI_ROP == 0 && $h1 == 0}] \
        "K10: haltsum1 reads ZERO with op SUCCESS (d2_spec 2 carves it out of the failed-address rule by name)"
    dmi_read 0x1A
    d2_chk [expr {$::DMI_ROP == $::DMI_RSP_FAILED}] \
        "K11: an unimplemented DMI address DOES return failed (got op $::DMI_ROP)"

    dmi_write $::DM_DATA0 0x5EED0D2A
    set v [dmi_read $::DM_DATA0]
    d2_chk [expr {$v == 0x5EED0D2A}] "K12a: data0 proxy round-trips a written value"
    dmi_write $::DM_DATA0 0xA5A5F00D
    set v [dmi_read $::DM_DATA0]
    d2_chk [expr {$v == 0xA5A5F00D}] "K12b: ...and a SECOND value, so K12a is not a reset constant"
    set w [sh_get $::DBG_DATA0_ADDR]
    d2_chk [expr {$w == 0xA5A5F00D}] \
        "K12c: ...and shared [format 0x%05X $::DBG_DATA0_ADDR] AGREES (read [format 0x%08X $w]) -- data0 really is a proxy for hartinfo.dataaddr"

    # cmderr W1C, both directions.  The error is provoked with a LEGAL command
    # aimed at a RUNNING hart, whose answer (HALT_RESUME) is unambiguous --
    # an illegal-command probe would leave NOT_SUPPORTED-vs-HALT_RESUME
    # ordering undefined and the check would be testing the spec's silence.
    dm_select 1
    dmi_write $::DM_COMMAND [ac_cmd 0x1008 0 1 0]
    set acs [dm_wait_notbusy]
    d2_chk [expr {$acs >= 0 && [acs_cmderr $acs] == $::CMDERR_HALTRESUME}] \
        "K13a: a command aimed at a RUNNING hart sets cmderr = HALT_RESUME (got [expr {$acs<0?-1:[acs_cmderr $acs]}])"
    dmi_write $::DM_ABSTRACTCS 0
    set acs [dmi_read $::DM_ABSTRACTCS]
    d2_chk [expr {[acs_cmderr $acs] == $::CMDERR_HALTRESUME}] \
        "K13b: writing ZERO to cmderr leaves it SET -- W1C, not read/write"
    ac_clear_cmderr
    set acs [dmi_read $::DM_ABSTRACTCS]
    d2_chk [expr {[acs_cmderr $acs] == 0}] "K13c: writing ONES clears it"

    set aa [dmi_read $::DM_ABSTRACTAUTO]
    d2_chk [expr {$aa == 0}] "K14: abstractauto reads zero"

    set c2 [dmi_read $::DM_DMCS2]
    d2_chk [expr {[d2_fld $c2 6 2] == 0}] "K15a: dmcs2.group resets to 0 (no group)"
    dmi_write $::DM_DMCS2 0x0000007E
    set c2 [dmi_read $::DM_DMCS2]
    d2_chk [expr {[d2_fld $c2 6 2] == 7}] \
        "K15b: dmcs2.group is WARL to 8 groups (all-ones reads back [d2_fld $c2 6 2], want 7)"
    dmi_write $::DM_DMCS2 0x00000002

    # ---- the liveness half ------------------------------------------------
    dm_select 1
    set s [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_allrunning $s] == 1 && [dms_anyrunning $s] == 1}] \
        "K16a: hart 1 reads all- AND anyrunning before the halt request"
    dm_haltreq 1
    set s [dm_poll_status 1 dms_allhalted 400 $::HALTREQ_BIT]
    d2_chk [expr {$s >= 0}] "K16b: dmcontrol.haltreq halted hart 1"
    if {$s >= 0} {
        d2_chk [expr {[dms_anyhalted $s] == 1}] "K16c: anyhalted is driven too"
        d2_chk [expr {[dms_allrunning $s] == 0}] "K16d: running went low"
    }
    dm_clr_haltreq 1
    set s [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_allhalted $s] == 1}] \
        "K16e: hart 1 STAYS halted after haltreq is dropped (halt is a state)"

    set hs [dmi_read $::DM_HALTSUM0]
    d2_chk [expr {$hs == 2}] \
        "K17: haltsum0 = 0x2 exactly (got [format 0x%08X $hs]) -- nonzero and in the right place"

    dm_select 2
    set s [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_allhalted $s] == 0 && [dms_allrunning $s] == 1}] \
        "K18: hart 2 is still RUNNING -- halting hart 1 halted only hart 1"

    dm_select 1
    dmi_write $::DM_COMMAND 0x02201000
    set acs [dm_wait_notbusy]
    d2_chk [expr {$acs >= 0 && [acs_cmderr $acs] == $::CMDERR_NOTSUP}] \
        "K19: cmdtype 2 (access memory) on a HALTED hart -> NOT_SUPPORTED (that IS DD5's memory answer)"
    ac_clear_cmderr
    dmi_write $::DM_COMMAND [ac_cmd 0x1008 0 1 0 3]
    set acs [dm_wait_notbusy]
    d2_chk [expr {$acs >= 0 && [acs_cmderr $acs] == $::CMDERR_NOTSUP}] \
        "K20: aarsize = 3 on a HALTED hart -> NOT_SUPPORTED"
    # ---- K21: R5's CORNER (R-D2-8(5)) ---------------------------------
    # The debug spec starts no abstract command while `cmderr` is nonzero:
    # the debugger must clear it W1C first.  A DM that starts anyway loses
    # the previous error AND runs something the debugger did not think it
    # had authorised -- and the loss is silent, because the new outcome
    # overwrites the old code.
    # cmderr is deliberately NOT cleared after K20, so it arrives here as
    # NOT_SUPPORTED (2).  The discriminator is that a VALID command aimed at
    # the HALTED hart 1 -- one that would certainly succeed and set cmderr to
    # 0 -- must leave cmderr at its OLD value and must never raise busy.
    set acs [dmi_read $::DM_ABSTRACTCS]
    set pre [acs_cmderr $acs]
    dmi_write $::DM_COMMAND [ac_cmd 0x1008 0 1 0]
    set acs [dm_wait_notbusy]
    d2_chk [expr {$acs >= 0 && [acs_cmderr $acs] == $pre && $pre != 0}] \
        "K21a: a command written while cmderr is nonzero is IGNORED -- cmderr still [expr {$acs<0?-1:[acs_cmderr $acs]}] (was $pre), not overwritten by the new command's outcome"
    ac_clear_cmderr
    dmi_write $::DM_COMMAND [ac_cmd 0x1008 0 1 0]
    set acs [dm_wait_notbusy]
    d2_chk [expr {$acs >= 0 && [acs_cmderr $acs] == 0}] \
        "K21b: ...and the SAME command runs once cmderr is cleared W1C (cmderr [expr {$acs<0?-1:[acs_cmderr $acs]}]) -- so K21a is a refusal, not a dead DM"
    ac_clear_cmderr

    # hart 1 is left HALTED on purpose: resuming it needs the trampoline, and
    # that belongs to the in-band instruments.  hart 0 is untouched throughout.
}

set verdict [d2_run_to_verdict 2400 "25 us"]
d2_report_verdict "dbg_conf(rider)" $verdict
d2_summary "dbg_conf"
flush stdout
exit
