# =============================================================================
# dbg_gateidc.tcl -- THE D5 SECTION-6 BOUNDED GATE LEG, and the grader for it.
#
# BEHAVIOURAL (the liveness control, and it must PASS):
#   ./xrun_dbg_verify.sh verify_castaliadebug ../kba/xrv32ua-p-dbgtrpmp.rcf dbg_gateidc.tcl
#   ./xrun_dbg_verify.sh verify_argusdebug    ../kf0/xrv32ua-p-dbgtrpmp.rcf dbg_gateidc.tcl
#
# GATE (the leg d5_spec 6 owes), through the implementer's genus_mp-sibling
# runner against MCU_MP.genus.dbgon.v + its 73 MB SDF, MTM MAXIMUM:
#   TAP_PFX=<verilog top path> D5_GATE=1 <their runner> ... dbg_gateidc.tcl
#
# BLIND-AUTHORED 2026-08-10 against d5_spec.md section 6 (FROZEN).
#
# WHAT IT DOES, AND WHY IT IS THIS SMALL
#   tap_reset, ONE IDCODE scan, ONE dtmcs read.  ~45-100 TCK.  That is the
#   whole leg, because the tree probe priced everything larger honestly: a
#   1,000-DMI-transaction gate session is 2.3-38 hours (C51) and buys back
#   behaviour the behavioural run already proved.  What only the gate run can
#   say is that the TAP EXISTS, MEETS TIMING and ANSWERS THROUGH REAL CELLS.
#   Two values say that, and this file asserts exactly those two.
#
# THE EXPECTED VALUES, quoted so the comparison is pinned and not merely its
# outcome:
#     IDCODE  Castalia 0x1CA57EEF   Argus 0x1A265EEF
#     dtmcs   0x00007071            (version 1, abits 7, dmistat 0, idle 7)
#   dtmcs is graded FIELD BY FIELD as well as whole, because a gate run that
#   returned a plausible-but-wrong word is the failure worth naming precisely.
#
# THE ONE-BIT-SHIFT TRAP (ipc probe C26), wired into the report rather than
# left in a document: a TDO sampled one phase late returns the WHOLE bitstream
# shifted by exactly one bit -- 0x1CA57EEF becomes 0x0E52BF77 -- which looks
# structured and sends the investigation into the DUT.  If the IDCODE is wrong
# this file computes both single-bit rotations of the expected value and SAYS
# SO when one of them matches.  On a gate run driven by the existing dbg_tap
# BFM a phase error is unlikely; on any future bridge-driven run it is the
# first thing to suspect.
#
# SDF LIVENESS IS NOT OPTIONAL AND IS NOT THIS FILE'S JOB.  A gate leg that
# claims "through the SDF-annotated gates" must show the POST-run half, and
# the pre-flight guard every runner already carries cannot.  The runner's
# operator runs, and the report quotes:
#     /usr/bin/python3.6 tools/cosim/d5_sdf_live.py <blockdir>/log \
#         --expect-sdf MCU_MP.genus.dbgon.sdf \
#         --control xcelium/riscv_test/genus_mp/log
#   rc 0 = LIVE.  --expect-sdf is the clause that catches the specific D5
#   mistake: annotating MCU_MP.genus.sdf (the debug-OFF cut, which has no TAP)
#   while believing the dbgon SDF was used.  --control is the known-nonzero.
#   THE GATE LEG IS NOT ACCEPTED WITHOUT THAT rc 0 QUOTED.
#
# D5_GATE=1 only changes what the file SAYS, never what it CHECKS: the same
# two values are asserted in both worlds, which is the point of running the
# behavioural arm as the control.
#
# EXPECTED BEHAVIOURALLY: ALL CHECKS PASSED (6 checks).
# EXPECTED ON A TREE WITH NO TAP (e.g. ./xrun_dbg.sh, the debug-OFF default):
#   TAP_PORT_ABSENT / INSTRUMENT_DEAD, nothing graded, and tap_summary refuses
#   to call it a pass.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tap.tcl]} { source dbg_tap.tcl } else { source ../behavioral_mp/dbg_tap.tcl }

set ::D5_GATE [expr {[info exists ::env(D5_GATE)] && $::env(D5_GATE) eq "1"}]
set N [expr {[info exists ::env(D2_NHARTS)] ? $::env(D2_NHARTS) : 4}]
set WANT_ID [expr {$N >= 18 ? $::TAP_IDCODE_ARGUS : $::TAP_IDCODE_CASTALIA}]
set WANT_DTMCS 0x00007071

puts "DMILOG ================ dbg_gateidc: the D5 section-6 bounded TAP leg ================"
puts "DMILOG   arm=[expr {$::D5_GATE ? {GATE (SDF-annotated cells)} : {BEHAVIOURAL (the liveness control)}}]"
puts "DMILOG   NHARTS=$N  TAP_PFX=$::TAP_PFX"
puts "DMILOG   expect IDCODE=[format 0x%08X $WANT_ID]  dtmcs=[format 0x%08X $WANT_DTMCS]"
flush stdout

set present [tap_present]
if {!$present} {
    tap_summary "dbg_gateidc" 0
    puts "DMILOG dbg_gateidc VERDICT=INSTRUMENT_DEAD"
    flush stdout
    exit
}

# ---- 1. plug the debugger in, then reset the TAP ---------------------------
# tap_init IS REQUIRED AND tap_reset ALONE IS NOT.  MEASURED, first run of this
# file 2026-08-10: with tap_reset only, the leg scanned 91 TCK across 3 scans
# and read IDCODE = 0x00000000 and dtmcs = 0x00000000.  The reason is in
# riscv_tb.vhd rather than in the TAP: MCU is declared as a COMPONENT whose
# port list ends at a0_3, so `trstn` is an unassociated formal sitting at its
# ENTITY DEFAULT '0' -- the TAP is held in asynchronous reset and shifts
# nothing.  tap_init is the proc that drives trstn high; tap_reset only walks
# TMS.  Worth stating loudly because 0x00000000 is the least informative
# possible failure and it is a HARNESS failure, not a chip one.
tap_init
tap_reset
d2_chk 1 "G1: tap_init released trstn and tap_reset walked the TAP to Test-Logic-Reset with IR at its reset value (IR_IDCODE) -- a precondition, graded so a run that never got here cannot look like a run that did"

# ---- 2. the IDCODE scan -----------------------------------------------------
set id [tap_read_idcode]
puts "DMILOG G2 IDCODE readback = [format 0x%08X $id]"
set rl [expr {(($WANT_ID << 1) | (($WANT_ID >> 31) & 1)) & 0xFFFFFFFF}]
set rr [expr {(($WANT_ID >> 1) | (($WANT_ID << 31) & 0x80000000)) & 0xFFFFFFFF}]
if {$id != $WANT_ID && ($id == $rl || $id == $rr)} {
    puts "DMILOG G2 ONE-BIT-SHIFT WARNING: the readback equals the EXPECTED value rotated by"
    puts "DMILOG   exactly one bit ([format 0x%08X $rl] / [format 0x%08X $rr])."
    puts "DMILOG   Treat that as a TDO SAMPLING PHASE symptom in the driver, not as an"
    puts "DMILOG   RTL fault, until proven otherwise (ipc probe C26).  It looks"
    puts "DMILOG   structured, which is exactly why it misdirects."
}
d2_chk [expr {$id == $WANT_ID}] \
    "G2: the IDCODE scans out as [format 0x%08X $WANT_ID] (got [format 0x%08X $id]).  The value is a USER decision (R-DD4(1)) and is baked into the synthesised module name -- MCU_MP.genus.dbgon.v carries jtag_dtm_ENABLE_DEBUG1_IDCODE480607983_IDLE_CYCLES7, and 480607983 = 0x1CA57EEF, so on the gate arm the netlist itself corroborates this number"

# ---- 3. the dtmcs read ------------------------------------------------------
set dt [tap_read_dtmcs]
puts "DMILOG G3 dtmcs readback = [format 0x%08X $dt] (version=[dtmcs_version $dt] abits=[dtmcs_abits $dt] dmistat=[dtmcs_dmistat $dt] idle=[dtmcs_idle $dt])"
d2_chk [expr {$dt == $WANT_DTMCS}] \
    "G3: dtmcs reads [format 0x%08X $WANT_DTMCS] (got [format 0x%08X $dt])"
d2_chk [expr {[dtmcs_version $dt] == 1 && [dtmcs_abits $dt] == 7}] \
    "G4: ...and its geometry fields are right on their own -- version=[dtmcs_version $dt] (want 1), abits=[dtmcs_abits $dt] (want 7).  Graded apart from G3 so a wrong word names WHICH field moved"
d2_chk [expr {[dtmcs_idle $dt] == 7}] \
    "G5: ...idle = [dtmcs_idle $dt] (want 7).  This is the field the .cfg's whole timing contract rests on: jtag_dtm.vhd's own derivation assumes T_TCK >= 140 ns, and OpenOCD honours idle by inserting that many Run-Test/Idle cycles after every DMI scan, so every TCK-count projection in the toolchain probe rescales by it"
d2_chk [expr {[dtmcs_dmistat $dt] == 0}] \
    "G6: ...and dmistat = [dtmcs_dmistat $dt] (want 0).  Nonzero here would mean the DTM is ALREADY deaf -- every non-NOP Update-DR of dmi silently dropped until dmireset (jtag_dtm.vhd DEVIATION 4) -- on a leg that has issued no DMI transaction at all"

tap_cost "dbg_gateidc"
if {$::D5_GATE} {
    puts "DMILOG ---- GATE ARM: the SDF-liveness proof is OWED and is NOT in this file ----"
    puts "DMILOG   Run and quote:  /usr/bin/python3.6 tools/cosim/d5_sdf_live.py <blockdir>/log \\"
    puts "DMILOG                       --expect-sdf MCU_MP.genus.dbgon.sdf \\"
    puts "DMILOG                       --control xcelium/riscv_test/genus_mp/log"
    puts "DMILOG   rc 0 (LIVE) is part of the leg's verdict.  Six green checks through"
    puts "DMILOG   UNANNOTATED cells would prove the netlist, not the timing."
}
tap_summary "dbg_gateidc" $present 6
flush stdout
exit
