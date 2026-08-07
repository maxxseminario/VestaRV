# =============================================================================
# dbg_tapconf.tcl -- D3 instrument T2: TAP GRAPH, IR AND DR CONFORMANCE.
# Everything in d3_spec section 1 that can be observed from the four pins,
# checked WITHOUT any DMI transaction.
#
#   ./xrun_dbg.sh xxxxxxrv32ui-p-add dbg_tapconf.tcl
#   D2_NHARTS=18 <the argus_debug staged runner> dbg_tapconf.tcl
#
# BLIND-AUTHORED 2026-08-06 against d3_spec.md 1 (FROZEN).
#
# THE METHOD, AND WHY NOTHING HERE READS AN INTERNAL SIGNAL
#   A TAP's state register is internal.  A harness that probed it would be
#   grading an implementation it has not seen and would break on any legal
#   re-encoding.  Every check below is therefore made through the ONLY
#   observable a debugger has: what a subsequent scan returns on TDO.  The
#   recurring device is that TEST-LOGIC-RESET SETS IR = IDCODE (d3_spec 1), so
#   "did we reach TLR?" becomes "does a 32-bit DR scan now return the IDCODE?"
#   -- a question with a USER-decided, chip-specific, hard-to-forge answer
#   (0x1CA57EEF / 0x1A265EEF, R-DD4(1)).
#
# THE DR/IR LENGTH CHECKS ARE MEASUREMENTS, NOT INFERENCES.  A chain length is
# measured by flushing the register with ones and then counting how many shifts
# a zero takes to appear on TDO.  That is the standard boundary-scan chain
# measurement and it needs no cooperation from the DUT beyond being a shift
# register.  It is strictly stronger than "the value looked right": a 41-bit
# spec implemented as 40 bits still returns a plausible-looking dtmcs.
#
# SAFETY: every length measurement finishes by shifting in a known ALL-ZERO
# word before it leaves Shift-*, so the unavoidable Update-DR at the end of the
# scan commits a NOP (op=00) and never a garbage DMI write.  Getting this wrong
# would let a conformance harness write dmcontrol with random bits -- including
# dmactive=0 -- and then report on a DM it had just reset.
#
# CHECK LIST (G-numbers; the runner greps for "CHECK FAILED"):
#   G0  the five JTAG pins exist                (else INSTRUMENT_DEAD, all skipped)
#   G1  after TLR a 32-bit DR scan returns this chip's IDCODE, with NO IR load
#   G2  IDCODE bit 0 = 1 (mandatory in 1149.1; also the fail-safe default's
#       only set bit, so G1+G4 together exclude the default)
#   G3  IDCODE version [31:28] = 1
#   G4  IDCODE partnum [27:12] = 0xCA57 (N=4) / 0xA265 (N=18)
#   G5  IDCODE manufid [11:1] = 0x777
#   G6  the IDCODE DR has ZERO STORAGE: shifting a different pattern in and
#       re-capturing still yields the IDCODE (d3_spec 1 "constant, loaded at
#       Capture-DR -- zero storage")
#   G7  IR chain length is exactly 5
#   G8  IDCODE DR length is exactly 32
#   G9  dtmcs DR length is exactly 32
#   G10 dmi DR length is exactly 41
#   G11 BYPASS DR length is exactly 1
#   G12 an UNSUPPORTED IR selects BYPASS -- length exactly 1 (the named
#       deviation from Spike, whose dr/dr_length go stale instead)
#   G13 BYPASS really delays by one: a pattern shifted through comes back
#       shifted by exactly one bit with a leading zero
#   G14 IR persists across DR scans (it is not re-captured or self-clearing)
#   G15 TMS high x5 reaches TLR FROM EVERY ONE OF THE 16 STATES (16 checks,
#       graded individually so a single broken edge is named, not averaged)
#   G16 TRSTn is ASYNCHRONOUS: asserted with TCK PARKED it still reaches TLR
#   G17 TRSTn asserted while parked in Shift-DR also restores IR = IDCODE
#   G18 dtmcs version = 1 and abits = 7 (the 0x71 base, d3_cdc_spec 4)
#
# AT UNIMPLEMENTED HEAD tap_present prints TAP_PORT_ABSENT / INSTRUMENT_DEAD
# and every check is skipped -- the part-1 seen-to-FAIL leg.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tap.tcl]} { source dbg_tap.tcl } else { source ../behavioral_mp/dbg_tap.tcl }

set NHARTS 4
if {[info exists ::env(D2_NHARTS)]} { set NHARTS $::env(D2_NHARTS) }
if {$NHARTS == 18} {
    set EXP_IDCODE $::TAP_IDCODE_ARGUS
    set EXP_PARTNUM 0xA265
    set CHIPNAME "Argus"
} else {
    set EXP_IDCODE $::TAP_IDCODE_CASTALIA
    set EXP_PARTNUM 0xCA57
    set CHIPNAME "Castalia"
}

set PRESENT [tap_present]

# Let the chip boot.  The TAP is NOT reset by system resetn (d3_cdc_spec 3), so
# strictly none of this needs the chip to be out of reset -- but riscv_tb holds
# resetn low at time 0 and a harness that starts scanning into a chip still in
# reset is testing a condition no other check here shares.  G16/G17 exercise
# the reset independence deliberately; the rest run on a booted chip.
run 200 us

# tap_measure_len lives in dbg_tap.tcl (shared with the live control, and
# fixed there once): it flushes the selected register with ones, VERIFIES TDO
# actually went high, then counts how many shifts a zero takes to appear.  It
# returns -2 for a TDO that never went high -- a stuck-low TDO otherwise
# measures as a plausible 1-bit BYPASS, which is how a broken instrument
# reports "ok" on its two easiest checks.

if {$PRESENT} {
    tap_init

    # ---- G1..G6: IDCODE, straight out of Test-Logic-Reset ------------------
    # tap_init ends in TLR and does NOT load IR.  So this scan reads whatever
    # DR the RESET VALUE of IR selects, which d3_spec 1 says is IDCODE.  If IR
    # reset to anything else this returns the wrong length/value and G1 fails,
    # which is exactly what "IR reset = IDCODE" means from outside.
    set id [tap_shift_dr 0 $::DRLEN_IDCODE]
    d2_chk [expr {$id == $EXP_IDCODE}] \
        "G1: IDCODE out of TLR with no IR load = [format 0x%08X $id], want [format 0x%08X $EXP_IDCODE] ($CHIPNAME, R-DD4(1))"
    d2_chk [expr {($id & 1) == 1}] \
        "G2: IDCODE bit 0 = 1 (1149.1 mandatory)"
    d2_chk [expr {[d2_fld $id 31 28] == 1}] \
        "G3: IDCODE version [d2_fld $id 31 28] = 1"
    d2_chk [expr {[d2_fld $id 27 12] == $EXP_PARTNUM}] \
        "G4: IDCODE partnum [format 0x%04X [d2_fld $id 27 12]] = [format 0x%04X $EXP_PARTNUM] -- the CHIP DISCRIMINATOR"
    d2_chk [expr {[d2_fld $id 11 1] == 0x777}] \
        "G5: IDCODE manufid [format 0x%03X [d2_fld $id 11 1]] = 0x777"

    # G6: zero storage.  Shift a value that is NOT the idcode all the way in;
    # the next Capture-DR must reload the constant.  A DTM that implemented
    # IDCODE as a writable 32-bit shift register passes G1 and fails this.
    tap_shift_dr 0xFFFFFFFF $::DRLEN_IDCODE
    set id2 [tap_shift_dr 0 $::DRLEN_IDCODE]
    d2_chk [expr {$id2 == $EXP_IDCODE}] \
        "G6: IDCODE DR has ZERO STORAGE -- re-captured [format 0x%08X $id2] after shifting 0xFFFFFFFF through it"

    # ---- G7..G12: measured chain lengths -----------------------------------
    tap_reset
    set irl [tap_measure_len SHIFT_IR 64]
    d2_chk [expr {$irl == $::IR_LEN}] "G7: IR chain length measured $irl, want $::IR_LEN"

    tap_ir $::IR_IDCODE
    set l [tap_measure_len SHIFT_DR 128]
    d2_chk [expr {$l == $::DRLEN_IDCODE}] "G8: IDCODE DR length measured $l, want $::DRLEN_IDCODE"

    tap_ir $::IR_DTMCS
    set l [tap_measure_len SHIFT_DR 128]
    d2_chk [expr {$l == $::DRLEN_DTMCS}] "G9: dtmcs DR length measured $l, want $::DRLEN_DTMCS"

    tap_ir $::IR_DMI
    set l [tap_measure_len SHIFT_DR 128]
    d2_chk [expr {$l == $::DRLEN_DMI}] \
        "G10: dmi DR length measured $l, want $::DRLEN_DMI (= abits 7 + 34, the frozen port's arithmetic)"

    tap_ir $::IR_BYPASS
    set l [tap_measure_len SHIFT_DR 64]
    d2_chk [expr {$l == $::DRLEN_BYPASS}] "G11: BYPASS DR length measured $l, want 1"

    # G12: THE NAMED DEVIATION.  0x05 is not IDCODE(0x01), DTMCS(0x10),
    # DMI(0x11) or BYPASS(0x1F).  d3_spec 1 requires it to select BYPASS.
    # Spike instead leaves dr/dr_length stale from the previous capture, so a
    # Spike-faithful copy would measure 1 here ONLY by accident of what ran
    # before -- which is why the check is preceded by a DMI selection, making
    # "stale" mean 41 and "BYPASS" mean 1.  The two answers cannot be confused.
    tap_ir $::IR_DMI
    tap_shift_dr 0 8
    tap_shift_ir 0x05
    set l [tap_measure_len SHIFT_DR 64]
    d2_chk [expr {$l == $::DRLEN_BYPASS}] \
        "G12: an UNSUPPORTED IR (0x05) selects BYPASS -- length measured $l, want 1 (stale-DR would measure $::DRLEN_DMI)"

    # ---- G13: BYPASS really is a one-bit delay -----------------------------
    # Capture-DR of BYPASS loads 0, so the pattern comes back with a leading
    # zero and everything else shifted up by one.  This checks the SHIFT
    # DIRECTION and the sampling edges at the same time: an MSB-first shifter
    # or a TDO updated on the rising edge produces a different word here.
    tap_ir $::IR_BYPASS
    set pat 0x6A5   ;# 12 bits, no run longer than 2, so an off-by-one shows
    set nb 12
    tap_goto SHIFT_DR
    set got 0
    for {set k 0} {$k < $nb} {incr k} {
        if {[tap_tdo]} { set got [expr {$got | (1 << $k)}] }
        tap_step [expr {$k == $nb-1}] [expr {($pat >> $k) & 1}]
    }
    tap_goto UPDATE_DR
    tap_goto RUN_TEST_IDLE
    set want [expr {($pat << 1) & ((1 << $nb) - 1)}]
    d2_chk [expr {$got == $want}] \
        "G13: BYPASS delays by exactly one bit -- shifted in [format 0x%03X $pat], got [format 0x%03X $got], want [format 0x%03X $want]"

    # ---- G14: IR persists ---------------------------------------------------
    tap_shift_ir $::IR_DTMCS
    set a [tap_shift_dr 0 $::DRLEN_DTMCS]
    set b [tap_shift_dr 0 $::DRLEN_DTMCS]
    d2_chk [expr {[dtmcs_version $a] == [dtmcs_version $b] &&
                  [dtmcs_abits $a] == [dtmcs_abits $b] &&
                  [dtmcs_version $a] != 0}] \
        "G14: IR persists across DR scans -- two consecutive dtmcs reads agree ([format 0x%08X $a] / [format 0x%08X $b])"

    # ---- G18: the dtmcs base value -----------------------------------------
    d2_chk [expr {[dtmcs_version $a] == 1}] "G18a: dtmcs.version = [dtmcs_version $a], want 1"
    d2_chk [expr {[dtmcs_abits $a] == 7}] \
        "G18b: dtmcs.abits = [dtmcs_abits $a], want 7 (base 0x71, matching Spike's constant and the frozen port)"

    # ---- G15: TMS high x5 from EVERY state ---------------------------------
    # Each sub-check: select BYPASS (so every Update the walk passes through is
    # harmless), navigate to the state, apply TMS=1 five times, then read a
    # 32-bit DR WITHOUT loading IR.  Reaching TLR is the only way that returns
    # the IDCODE, because TLR is the only thing that sets IR = IDCODE.
    #
    # The walk to UPDATE_IR necessarily commits whatever Capture-IR loaded; the
    # walk to UPDATE_DR commits the BYPASS capture.  Both are harmless BY THE
    # CHOICE OF BYPASS, and that choice is the reason this loop can visit all
    # sixteen states without disturbing the DM.
    foreach sname $::TAP_NAMES {
        tap_reset
        tap_shift_ir $::IR_BYPASS
        tap_goto $sname
        for {set i 0} {$i < 5} {incr i} { tap_step 1 0 }
        set ::TAP_STATE 0
        set ::TAP_IR $::IR_IDCODE
        set v [tap_shift_dr 0 $::DRLEN_IDCODE]
        d2_chk [expr {$v == $EXP_IDCODE}] \
            "G15/$sname: TMS high x5 from $sname reaches TLR (IDCODE reads [format 0x%08X $v])"
    }

    # ---- G16/G17: TRSTn is asynchronous ------------------------------------
    # Park in SHIFT_DR with BYPASS selected, stop TCK entirely, and pulse
    # trstn.  A design that reset the TAP on a TCK edge cannot pass this: no
    # edge occurs while trstn is low.
    tap_reset
    tap_shift_ir $::IR_BYPASS
    tap_goto SHIFT_DR
    tap_trst_pulse 4
    set v [tap_shift_dr 0 $::DRLEN_IDCODE]
    d2_chk [expr {$v == $EXP_IDCODE}] \
        "G16: TRSTn asserted with TCK PARKED reaches TLR from SHIFT_DR (IDCODE reads [format 0x%08X $v])"
    d2_chk [expr {$v == $EXP_IDCODE}] \
        "G17: ...and it restored IR = IDCODE, which is the only reason that scan could return an IDCODE at all"

    # Diagnostic, NOT a check: 1149.1 mandates the two LSBs of the Capture-IR
    # value be "01".  d3_spec is SILENT on Capture-IR content, so this harness
    # reports it and grades nothing -- see the clause-coverage diff's
    # named-uncovered row.  A future spec sentence turns this line into a check.
    tap_reset
    set cir [tap_shift_ir $::IR_BYPASS]
    puts "DMILOG TAPNOTE Capture-IR value = [format 0x%02X $cir] (1149.1 wants bits\[1:0\] = 01; d3_spec is silent -- ungraded)"
    flush stdout
}

tap_cost "dbg_tapconf"
set verdict [d2_run_to_verdict 2400 "25 us"]
d2_report_verdict "dbg_tapconf(rider)" $verdict
# 34, not 40: the file has 19 static d2_chk sites, one of which (G15) is a
# 16-iteration foreach, so 18 + 16 = 34 checks EXECUTE.  The original 40 was a
# guess written before the G15 loop was expanded, and it made this harness
# report UNDER_RAN on correct RTL at both N -- instrument defect I-1, found by
# the D3 implementation wave and fixed here under author ownership.  The
# min-check floor is a real guard (it is what stops a half-run harness reading
# as a pass); the number just has to be the truth.
tap_summary "dbg_tapconf" $PRESENT 34
flush stdout
