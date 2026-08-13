# =============================================================================
# dbg_dmreg.tcl -- the D5 section-1 RTL DETECTOR: the two zero-flop
# debug_module.vhd edits R-DD6(1) approved, graded on the RAW DMI PORT.
#
#   ./xrun_dbg_verify.sh verify_castaliadebug ../kba/xrv32ua-p-dbgtrpmp.rcf dbg_dmreg.tcl
#   ./xrun_dbg_verify.sh verify_argusdebug    ../kf0/xrv32ua-p-dbgtrpmp.rcf dbg_dmreg.tcl
#
# BLIND-AUTHORED 2026-08-10 against d5_spec.md section 1 (FROZEN) by an agent
# that has not seen and will never see the D5 implementation.  Committed
# polarity (R-K5-8): CORRECT RTL = PASS.
#
# WHY THE RAW DMI PORT AND NOT THE TAP
#   The two edits are DM read arms.  Driving them through the TAP would put
#   the DTM's uniform nonzero-dmistat gate (jtag_dtm.vhd:477-495) between the
#   instrument and the subject: at HEAD leg L1 provokes a FAILED, the DTM
#   latches sticky FAILED, and EVERY subsequent non-NOP Update-DR is silently
#   DROPPED until dmireset -- so a TAP-driven detector would report one real
#   failure followed by a cascade of transport artefacts and could not tell
#   them apart.  VERIFIED IN THE RTL RATHER THAN ASSUMED (the orchestrator's
#   reading was offered for independent confirmation and is confirmed):
#   `grep -n sticky hdl/common/debug_module.vhd` returns NOTHING -- the sticky
#   machine exists only in jtag_dtm.vhd, and the eight dmi_* ports this file
#   drives reach debug_module.vhd's request process directly.  So on this path
#   a FAILED response has NO successor state at all, and L1b below MEASURES
#   that rather than trusting it.
#
# THE TRAP THIS FILE IS BUILT AROUND, AND IT WOULD HAVE MADE A FALSE PASS
#   debug_module.vhd's unimplemented-address arm is
#       rsp_op_r <= OP_FAIL;  rsp_data_r <= (others => '0');
#   -- op FAILED *and data 0x00000000*.  The post-fix answer for sbcs is
#   op SUCCESS *and data 0x00000000*.  THE DATA IS THE SAME IN BOTH WORLDS.
#   A detector that graded `data == 0` would have passed at HEAD, on a chip
#   where gdb cannot attach at all.  Every sbcs check here grades the RESPONSE
#   OP first and names it in its own text.
#
# EXPECTED AT TODAY'S HEAD (97813d6) -- the FAIL leg, and what each says:
#   L1  FAILED : sbcs (0x38) read answers op=FAILED(2) data=0x00000000
#   L1b PASS   : ...and the very next raw read of dmstatus still SUCCEEDS
#                (no sticky on this path; the L1 failure is LOCAL)
#   L2  FAILED : hartinfo (0x12) reads 0x00011680
#   L3a FAILED : hartinfo dataaccess = 1 (want 0)
#   L3b FAILED : hartinfo datasize   = 1 (want 0)
#   L3c FAILED : hartinfo dataaddr   = 0x680 (want 0)
#   L3d PASS   : hartinfo nscratch   = 0 (already 0 -- a PASS at HEAD, on
#                purpose: the null claim is four fields and only three move)
#   L4  FAILED : a write to sbcs answers op=FAILED (want SUCCESS-ignored)
#   L5  FAILED : ...and the ignored-write invariants cannot even be evaluated
#   L6  PASS   : the 14 OTHER unimplemented addresses answer FAILED, and the
#                two implemented controls answer SUCCESS -- the map-invariance
#                baseline.  ITS FAIL LEG IS SEALED (a mutant), not HEAD.
#
# EXPECTED ON CORRECT POST-FIX RTL: ALL CHECKS PASSED (10 checks).
# MEASURED AT HEAD 97813d6: 7 of 10 FAILED (L1 L2 L3a L3b L3c L4 L5); the
# three PASSes are L1b, L3d and L6 and each is a PASS on purpose.
#
# LIVENESS: L6's own controls are the rule-4 known-nonzero for the whole file.
# 0x11 (dmstatus) must answer SUCCESS with a NONZERO word and 0x13 (haltsum1)
# must answer SUCCESS with ZERO -- so the same proc that reports "FAILED" for
# 0x38 is demonstrated, in the same run, to report SUCCESS for two addresses
# and to distinguish zero data from nonzero data.  If those controls do not
# hold, the file says INSTRUMENT_DEAD and grades nothing.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }

set ::DM_SBCS 0x38

# The addresses debug_module.vhd:303-315 does NOT implement, EXCLUDING 0x38
# (which section 1.1 moves into the implemented set).  Every one of these must
# still answer FAILED after the edit: the clause "a new A_SBCS constant joins
# the implemented list" is a statement about ONE address, and a diff that
# widened the decode instead would be caught here and nowhere else.
set ::D5_UNIMPL {0x14 0x15 0x19 0x1a 0x1b 0x1c 0x1d 0x30 0x39 0x3a 0x3b 0x3c 0x3d 0x3f}

proc d5_opname {op} {
    switch -- $op {
        0 { return "SUCCESS(0)" }
        2 { return "FAILED(2)" }
        3 { return "BUSY(3)" }
        default { return "op=$op" }
    }
}

# One graded raw read -> {ok op data}.  Never retried, never widened.
proc d5_read {addr} {
    set d [dmi_read $addr]
    return [list $::DMI_OK $::DMI_ROP $d]
}

puts "DMILOG ================ dbg_dmreg: the D5 section-1 RTL detector ================"
puts "DMILOG   subject: sbcs (0x38) read-zero-SUCCESS + ignored-SUCCESS writes;"
puts "DMILOG            hartinfo (0x12) the null claim (all four fields 0)."
puts "DMILOG   NHARTS=[expr {[info exists ::env(D2_NHARTS)] ? $::env(D2_NHARTS) : "?"}]"
flush stdout

if {![dmi_present]} {
    puts "DMILOG dbg_dmreg VERDICT=INSTRUMENT_DEAD"
    flush stdout
    exit
}

# ---------------------------------------------------------------------------
# 0. THE KNOWN-NONZERO VALIDATION OF THE METHOD, before anything is graded.
#    Two controls, chosen so one is SUCCESS-with-nonzero-data and the other is
#    SUCCESS-with-zero-data.  A method validated only against zero has not been
#    validated (method rule 4).
# ---------------------------------------------------------------------------
set c_stat [d5_read $::DM_DMSTATUS]
set c_hs1  [d5_read $::DM_HALTSUM1]
puts "DMILOG CONTROL dmstatus(0x11)  ok=[lindex $c_stat 0] [d5_opname [lindex $c_stat 1]] data=[format 0x%08X [lindex $c_stat 2]]"
puts "DMILOG CONTROL haltsum1(0x13)  ok=[lindex $c_hs1 0] [d5_opname [lindex $c_hs1 1]] data=[format 0x%08X [lindex $c_hs1 2]]"
set method_live [expr {[lindex $c_stat 0] && [lindex $c_stat 1] == 0 && [lindex $c_stat 2] != 0 &&
                       [lindex $c_hs1  0] && [lindex $c_hs1  1] == 0 && [lindex $c_hs1  2] == 0}]
if {!$method_live} {
    puts "DMILOG METHOD_NOT_VALIDATED -- the two controls did not both behave."
    puts "DMILOG   0x11 must answer SUCCESS with a NONZERO word and 0x13 must answer"
    puts "DMILOG   SUCCESS with ZERO.  Until both hold, a 'FAILED' or a '0' reported"
    puts "DMILOG   below would be uninterpretable.  Nothing is graded."
    puts "DMILOG dbg_dmreg VERDICT=INSTRUMENT_DEAD"
    flush stdout
    exit
}
puts "DMILOG METHOD_VALIDATED -- the reader distinguishes SUCCESS from FAILED and zero from nonzero."
flush stdout

# ---------------------------------------------------------------------------
# 1. sbcs (0x38): read-zero-SUCCESS.
# ---------------------------------------------------------------------------
set r [d5_read $::DM_SBCS]
set r_ok [lindex $r 0] ; set r_op [lindex $r 1] ; set r_d [lindex $r 2]
puts "DMILOG L1 RAW sbcs(0x38) read: handshake=$r_ok op=[d5_opname $r_op] data=[format 0x%08X $r_d]"
d2_chk [expr {$r_ok && $r_op == $::DMI_RSP_SUCCESS && $r_d == 0}] \
    "L1: sbcs (0x38) READ answers op=SUCCESS with data=0x00000000 -- got op=[d5_opname $r_op] data=[format 0x%08X $r_d].  THE OP IS THE DISCRIMINATOR: the HEAD unimplemented arm also returns data 0x00000000, so a data-only check would pass on a chip gdb cannot attach to (riscv-013.c:1653-1654 aborts examine on a FAILED sbcs read)"

# L1b -- the sticky-independence measurement.  Issued IMMEDIATELY after L1, on
# purpose: if a FAILED on this path had a successor state, this read would be
# the one it killed.
set r2 [d5_read $::DM_DMSTATUS]
d2_chk [expr {[lindex $r2 0] && [lindex $r2 1] == 0 && [lindex $r2 2] != 0}] \
    "L1b: the DMI transaction IMMEDIATELY after the sbcs read still succeeds (dmstatus [d5_opname [lindex $r2 1]] [format 0x%08X [lindex $r2 2]]) -- the raw dmi_* path carries NO sticky state, so L1's verdict is about ONE address and not about a deafened transport"

# ---------------------------------------------------------------------------
# 2. hartinfo (0x12): the null claim, whole and then field by field.
#    The whole-word check is what a debugger sees; the four field checks are
#    what a FAIL REPORT has to say to be useful (which field, and what it held).
# ---------------------------------------------------------------------------
set h [d5_read $::DM_HARTINFO]
set h_ok [lindex $h 0] ; set h_op [lindex $h 1] ; set h_d [lindex $h 2]
set hi_dataaddr   [d2_fld $h_d 11 0]
set hi_datasize   [d2_fld $h_d 15 12]
set hi_dataaccess [d2_fld $h_d 16 16]
set hi_nscratch   [d2_fld $h_d 23 20]
puts "DMILOG L2 RAW hartinfo(0x12) read: op=[d5_opname $h_op] data=[format 0x%08X $h_d]"
puts "DMILOG    fields: dataaddr=[format 0x%03X $hi_dataaddr] datasize=$hi_datasize dataaccess=$hi_dataaccess nscratch=$hi_nscratch"
d2_chk [expr {$h_ok && $h_op == $::DMI_RSP_SUCCESS && $h_d == 0}] \
    "L2: hartinfo (0x12) reads 0x00000000 SUCCESS -- got [format 0x%08X $h_d] (HEAD drives 0x00011680: dataaddr 0x680, which sign-extends to an address inside the READ-ONLY shared boot ROM)"
d2_chk [expr {$hi_dataaccess == 0}] \
    "L3a: hartinfo.dataaccess = 0 (got $hi_dataaccess) -- riscv-013.c:1147 reads dataaddr ONLY under dataaccess==1, so this ONE bit is what closes R-D2-8 R6 by emission rather than by tolerance"
d2_chk [expr {$hi_datasize == 0}] \
    "L3b: hartinfo.datasize = 0 (got $hi_datasize) -- the null claim is all four fields, not just the one OpenOCD gates on"
d2_chk [expr {$hi_dataaddr == 0}] \
    "L3c: hartinfo.dataaddr = 0x000 (got [format 0x%03X $hi_dataaddr])"
d2_chk [expr {$hi_nscratch == 0}] \
    "L3d: hartinfo.nscratch = 0 (got $hi_nscratch) -- ALREADY TRUE AT HEAD and graded anyway: an edit that set nscratch while zeroing the rest would steer OpenOCD to GPR scratch it does not have, and no other check in this file would notice"

# ---------------------------------------------------------------------------
# 3. sbcs writes are IGNORED-SUCCESS.  Three things must hold and they are
#    graded separately because they fail for different reasons:
#      L4 the write itself answers SUCCESS
#      L5 the write changed NOTHING -- sbcs still reads zero, and a witness
#         register that shares the write path (abstractcs, whose cmderr is
#         W1C and would be the natural casualty of a mis-decoded write) is
#         unchanged.
#    A "write-side-effect" mutant is exactly what L5 exists for.
# ---------------------------------------------------------------------------
set acs_before [d5_read $::DM_ABSTRACTCS]
set w [dmi_write $::DM_SBCS 0xFFFFFFFF]
set w_op $::DMI_ROP
set w_ok $::DMI_OK
puts "DMILOG L4 RAW sbcs(0x38) write 0xFFFFFFFF: handshake=$w_ok op=[d5_opname $w_op]"
d2_chk [expr {$w_ok && $w_op == $::DMI_RSP_SUCCESS}] \
    "L4: a WRITE of 0xFFFFFFFF to sbcs completes op=SUCCESS -- got [d5_opname $w_op] (d5_spec 1.1: writes are ignored-SUCCESS, not FAILED and not accepted)"

set r3 [d5_read $::DM_SBCS]
set acs_after [d5_read $::DM_ABSTRACTCS]
set sb_still_zero [expr {[lindex $r3 0] && [lindex $r3 1] == 0 && [lindex $r3 2] == 0}]
set acs_same [expr {[lindex $acs_before 0] && [lindex $acs_after 0] &&
                    [lindex $acs_before 2] == [lindex $acs_after 2]}]
puts "DMILOG L5 after the write: sbcs=[d5_opname [lindex $r3 1]] [format 0x%08X [lindex $r3 2]]  abstractcs [format 0x%08X [lindex $acs_before 2]] -> [format 0x%08X [lindex $acs_after 2]]"
d2_chk [expr {$sb_still_zero && $acs_same}] \
    "L5: the write had NO EFFECT -- sbcs still reads zero-SUCCESS (still_zero=$sb_still_zero) and abstractcs is unchanged (same=$acs_same).  'Ignored' is a measurement here, not a promise: a decode that let the write land somewhere is caught by the witness"

# ---------------------------------------------------------------------------
# 4. MAP INVARIANCE.  Exactly ONE address joined the implemented set.
#    This check PASSES at HEAD by construction -- it is the baseline, and its
#    FAIL leg is a sealed mutant, not this tree.  It is graded anyway because
#    a widened decode is the natural wrong implementation of clause 1.1 and
#    nothing else in the D5 instrument set would see it.
# ---------------------------------------------------------------------------
set widened {}
foreach a $::D5_UNIMPL {
    set q [d5_read $a]
    if {![lindex $q 0]} { lappend widened "[format 0x%02X $a]:NOHANDSHAKE" ; continue }
    if {[lindex $q 1] != $::DMI_RSP_FAILED} {
        lappend widened "[format 0x%02X $a]:[d5_opname [lindex $q 1]]=[format 0x%08X [lindex $q 2]]"
    }
}
puts "DMILOG L6 unimplemented sweep over [llength $::D5_UNIMPL] addresses: deviations={$widened}"
d2_chk [expr {[llength $widened] == 0}] \
    "L6: every OTHER unimplemented DMI address still answers FAILED -- exactly one address joined the implemented set (deviations: [llength $widened])"

# ---------------------------------------------------------------------------
# 5. the image's own verdict -- the run is also a chip run.
# ---------------------------------------------------------------------------
set verdict [d2_run_to_verdict 2400 "25 us"]
d2_report_verdict "dbg_dmreg" $verdict
# The floor is the file's OWN check count, counted off the file and then
# MEASURED: L1 L1b L2 L3a L3b L3c L3d L4 L5 L6 = 10.  The first draft said 12
# -- an arithmetic slip by the author, caught by the first FAIL-leg run, which
# reported NO_CHECKS on a run that had graded everything it owns.  Recorded as
# a miss rather than quietly widened; a floor that rejects a correct run is a
# wrong floor (the D4 8.2 lesson).
d2_summary "dbg_dmreg" 10
flush stdout
exit
