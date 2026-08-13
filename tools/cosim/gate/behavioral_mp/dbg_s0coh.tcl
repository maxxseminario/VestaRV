# =============================================================================
# dbg_s0coh.tcl -- the BLIND DETECTOR for F-D5-2 (R-DD9): the coherent-dscratch
# contract.  During a halt, dscratch0/1 is the SINGLE home of the debuggee's
# s0/s1.
#
#   ./xrun_dbg_verify.sh verify_castaliadebug ../kba/xrv32ua-p-dbgtrpmp.rcf dbg_s0coh.tcl
#   ./xrun_dbg_verify.sh verify_argusdebug    ../kf0/xrv32ua-p-dbgtrpmp.rcf dbg_s0coh.tcl
#
# BLIND-AUTHORED 2026-08-11 by the D5 acceptance author, resumed under the
# R-D2-3(5) wall-both-ways pattern, against d5_spec.md section 1.6 as FROZEN by
# R-DD9 -- and against NOTHING else.  The author is barred from, and has not
# opened, the implementer's `dbg_s0rd.tcl`, `dbg_pbebrk.tcl`, their devlog
# sections on F-D5-2, or their report.  Committed polarity (R-K5-8).
#
# I INSTRUMENT THE CONTRACT, NOT THE MECHANISM.  Section 1.6 grants explicit
# mechanism latitude -- "the code home, trampoline epilogue vs DM synthesized
# body, is the implementer's design".  So there is not one check in this file
# on WHERE the value lives, on the trampoline's shape, on dscratch as a CSR, or
# on any sequence table.  Every leg is one of the six OBSERVABLE clauses (a)-(f),
# graded through the DMI port and an independent peek oracle.  A detector that
# reached for the mechanism would have to be rewritten by whichever design won,
# and would be testing the fix rather than the finding.
#
# ---------------------------------------------------------------------------
# THE FINDING, from the frozen contract only
#   Stock OpenOCD uses s0/s1 as scratch ACROSS abstract-command boundaries for
#   every memory access.  On the pre-fix tree the value is lost at that
#   boundary, so gdb memory reads return SILENT WRONG ANSWERS WITH cmderr=0 --
#   the worst failure shape available, because nothing reports it.
#
# ---------------------------------------------------------------------------
# THE INDEPENDENT ORACLE, and why every value leg has one.
#   The confounded quantity here IS the abstract s0/s1 readback -- it is the
#   thing under test.  So no leg may prove a memory access worked by reading it
#   back through the same path that is broken.  Every value clause below is
#   checked against a DIRECT SIMULATOR PEEK: the TCM cell for memory
#   (`:dut:hartN:ram0:RAM:mem(i)`) and the regfile cell for registers
#   (`:dut:hartN:core:datapath_inst:rf:registers(i)`).  Those are outside the
#   DM entirely.  Where a leg must plant a value first, it plants it through
#   the a6/a7 path -- the (d)-class control, proven working -- and CONFIRMS the
#   plant with the peek before using it as an oracle.
#
# ---------------------------------------------------------------------------
# PREDICTIONS at 899a321, written before the first run (method rule 3):
#   D1  (d) a6-class round-trip ................. PASS  (the control)
#   C1  (c) abstract-write s0 then abstract-read s0 . FAIL -- measured
#           already in dbg_pbsub's S0-CTRL: wrote 0x5150C0DE, read 0x00000000
#   C2  (c) progbuf modification of s0 visible ...... FAIL
#   A1  (a) the two-command READ idiom returns the TRUE memory value . FAIL,
#           and this is THE finding: cmderr=0 with a wrong value
#   B1  (b) the two-command WRITE idiom lands the value ............. FAIL
#           (s0 holds the wrong address when the store executes)
#   E0  (e) setup: magic installed via resume ....... PASS (the value reaches
#           the architectural register on RESUME; it is lost at the COMMAND
#           boundary, which is a different boundary)
#           **MISSED -- see the E-setup note in the body.  MEASURED: the
#           abstract write is lost OUTRIGHT pre-fix, so nothing reaches the
#           debuggee on resume either and s0/s1 stayed 0x00000000.  The
#           prediction is left as written; the setup was redesigned to plant
#           the magic from the testbench side, which is install-path
#           independent.  The chip prediction that mattered (E1 passes at HEAD)
#           is unaffected -- only my assumption about how to arm it was wrong.**
#   E1  (e) plain halt+resume preserves the debuggee's s0/s1 ....... PASS,
#           **AND IT MUST KEEP PASSING** -- see below
#   F1  (f) a genuinely-trapping progbuf program still reports EXCEPTION . PASS
#   E2  (e) witness-strength gate ....... NOT PREDICTED -- this leg did not
#           exist when the predictions were written.  It was ADDED after the
#           measurement refuted my own zero-witness-still-discriminates
#           argument (see E2 in the body).  It FAILS at HEAD.
#   => predicted 4 FAIL / 4 PASS of 8 graded legs at HEAD; measured 5 FAIL of
#      11 once E2 joined, with the predicted failure SET {C1,C2,A1,B1} exactly
#      right and E2 the honest addition.
#
# ---------------------------------------------------------------------------
# WHY (e) IS THE MOST IMPORTANT LEG IN THIS FILE EVEN THOUGH IT PASSES TODAY.
#
#   The natural wrong implementation of F-D5-2 is to stop serving s0/s1 from
#   dscratch and serve the ARCHITECTURAL registers directly.  That makes
#   OpenOCD work perfectly: (a), (b) and (c) all go green, the memory idioms
#   land, gdb is happy.  And it silently destroys the debuggee, because during
#   a halt the architectural s0/s1 belong to the trampoline, which is using
#   them as its own scratch -- so the debuggee's real s0/s1 would be whatever
#   the entry code last left there, and a resume would hand the program
#   corrupted registers.
#
#   A test suite built only from "does the debugger work?" CANNOT SEE THAT.
#   (e) is the leg that can -- BUT ONLY IF THE WITNESS IS NONZERO, and that
#   turned out to be the whole difficulty.  See E2 in the body: at HEAD the
#   debuggee's s0/s1 are structurally pinned to zero, so E1 passes with a ZERO
#   witness and does NOT by itself discriminate the (e)-killer.  E2 is the gate
#   that fixes this, and clause (e) is cleared by **E1 AND E2 together**, never
#   by E1 alone.  A validation wave that sees (a)-(c) go green while E1 goes
#   red has found the wrong fix; one that sees E1 green and E2 red has found a
#   fix that has not actually given the debuggee its registers back.
#
# ---------------------------------------------------------------------------
# N-INDEPENDENCE: the subject is the single dm0's abstract-command service path
# for two register numbers.  Nothing here is indexed by hartid; one victim is
# used at either N.  N=18 is RUN to prove that rather than to assume it.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tramp_lib.tcl]} { source dbg_tramp_lib.tcl } else { source ../behavioral_mp/dbg_tramp_lib.tcl }

set VICTIM 1

# Encodings VALIDATED AGAINST THE TOOLCHAIN (riscv-none-elf-as + objdump):
set ::I_LW_S0_S0   0x00042403   ;# lw   s0, 0(s0)   -- OpenOCD's read idiom
set ::I_SW_S1_S0   0x00942023   ;# sw   s1, 0(s0)   -- OpenOCD's write idiom
set ::I_ADDI_S0_4  0x00440413   ;# addi s0, s0, 4
set ::I_LW_A7_A6   0x00082883   ;# lw   a7, 0(a6)   -- the (d)-class planting path
set ::I_LW_S0_A6   0x00082403   ;# lw   s0, 0(a6)   -- the E-PROBE pair (core loads its own s0/s1)
set ::I_LW_S1_A6   0x00482483   ;# lw   s1, 4(a6)
set ::I_SW_A7_A6   0x01182023   ;# sw   a7, 0(a6)
set ::I_EBREAK     0x00100073
set ::I_ILLEGAL    0x00000000

set ::R_S0 0x1008 ; set ::R_S1 0x1009
set ::R_A6 0x1010 ; set ::R_A7 0x1011
set ::X_S0 8      ; set ::X_S1 9        ;# regfile indices, for the peek oracle

# Two TCM words in the RETIRED 0xBE00-0xBEFF claim: private to the tile,
# outside every shared-window ledger row, clear of the ISR bank (ends 0xBAFF)
# and below the stack top (0xBFF0).
set ::MEM_R 0x0000BE10        ;# the READ leg's source word
set ::MEM_W 0x0000BE14        ;# the WRITE leg's destination word

set ::VAL_TRUE   0xC0FFEE01   ;# planted at MEM_R; what (a) must return
set ::VAL_STORE  0x5AFE0002   ;# what (b) must land at MEM_W
set ::VAL_S0     0x0D5C0FF0   ;# (c) round-trip probe
set ::VAL_A6     0xA6A6A6A6   ;# (d) control
set ::MAGIC_S0   0xDEB0DEB0   ;# (e) the debuggee's magic
set ::MAGIC_S1   0xDEB1DEB1

proc coh_tcm {h addr} {
    if {$addr < 0x8000 || $addr > 0xBFFC} { return "" }
    if {[catch {value ":dut:hart${h}:ram0:RAM:mem([expr {($addr - 0x8000) >> 2}])"} v]} { return "" }
    return [d2_int $v]
}
proc coh_gpr {h i} {
    if {[catch {value ":dut:hart${h}:core:datapath_inst:rf:registers($i)"} v]} { return "" }
    return [d2_int $v]
}
# One postexec-only command: run whatever is in progbuf, transfer nothing.
proc coh_postexec {} {
    dmi_write $::DM_COMMAND [ac_cmd $::R_S1 0 0 1]
    set acs [d4_wait_notbusy]
    return [expr {$acs < 0 ? -1 : [acs_cmderr $acs]}]
}
proc coh_prog {w0 w1} {
    dmi_write $::DM_PROGBUF0 $w0
    dmi_write $::DM_PROGBUF1 $w1
}

puts "DMILOG ================ dbg_s0coh: the F-D5-2 coherent-dscratch detector ================"
puts "DMILOG   contract: d5_spec 1.6 (a)-(f).  MECHANISM LATITUDE IS RESPECTED --"
puts "DMILOG            no leg here inspects where the value lives, only what is observable."
puts "DMILOG   NHARTS=[expr {[info exists ::env(D2_NHARTS)] ? $::env(D2_NHARTS) : {?}}]  victim=hart $VICTIM"
flush stdout

if {![dmi_present]} { puts "DMILOG dbg_s0coh VERDICT=INSTRUMENT_DEAD" ; flush stdout ; exit }
d4_wait_ready

# ---- halt the victim --------------------------------------------------------
dm_select $VICTIM
dm_haltreq $VICTIM
set s [dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT]
d2_chk [expr {$s >= 0}] "P1: hart $VICTIM halted on haltreq (dmstatus [format 0x%08X $s]) -- the precondition for every abstract command below"
dm_clr_haltreq $VICTIM
d4_settle

# ===========================================================================
# (d) THE a6-CLASS CONTROL, FIRST.  It is also this file's method validation
# (rule 4): if an ordinary GPR does not round-trip, then "s0 did not round-trip"
# below would say nothing about s0.
# ===========================================================================
set wa [d4_abs_write $::R_A6 $::VAL_A6]
d4_settle
set ra [d4_abs_read $::R_A6]
puts "DMILOG D (d)-CONTROL a6: write cmderr=$wa, read back [format 0x%08X [expr {[lindex $ra 0] < 0 ? 0 : [lindex $ra 0]}]] want [format 0x%08X $::VAL_A6]"
set d_ok [expr {$wa == 0 && [lindex $ra 0] == $::VAL_A6}]
d2_chk $d_ok \
    "D1: (d) an ORDINARY GPR round-trips across the abstract-command boundary -- a6 wrote and read back [format 0x%08X $::VAL_A6].  This is the control that makes every s0/s1 verdict below mean something, and it must pass in BOTH worlds: the fix is about s0/s1 and must not disturb the ordinary path"
if {!$d_ok} {
    puts "DMILOG METHOD_NOT_VALIDATED -- the ordinary-GPR control did not round-trip."
    puts "DMILOG   Every s0/s1 result below would be uninterpretable.  Nothing further is graded."
    puts "DMILOG dbg_s0coh VERDICT=INSTRUMENT_DEAD"
    d2_summary "dbg_s0coh" 99
    flush stdout
    exit
}
puts "DMILOG METHOD_VALIDATED -- the ordinary abstract-GPR path works, so s0/s1 failures below are about s0/s1."
flush stdout

# ===========================================================================
# (c) THE ROUND-TRIP ACROSS A COMMAND BOUNDARY.  Graded before (a)/(b) because
# it is the simplest statement of the same contract and localises the rest.
# ===========================================================================
d4_settle
set ws [d4_abs_write $::R_S0 $::VAL_S0]
d4_settle
set rs [d4_abs_read $::R_S0]
puts "DMILOG C (c)-ROUNDTRIP s0: write cmderr=$ws, read back [format 0x%08X [expr {[lindex $rs 0] < 0 ? 0 : [lindex $rs 0]}]] want [format 0x%08X $::VAL_S0]"
d2_chk [expr {$ws == 0 && [lindex $rs 0] == $::VAL_S0}] \
    "C1: (c) a value written to s0 by one abstract command is read back by the NEXT one ([format 0x%08X [expr {[lindex $rs 0] < 0 ? 0 : [lindex $rs 0]}]] vs [format 0x%08X $::VAL_S0]).  Pre-fix this reads the debuggee's saved value instead -- the write reports cmderr=0 and is simply lost, which is the whole shape of F-D5-2"

# ...and a progbuf modification of s0 must be visible to the next abstract read.
d4_settle
d4_abs_write $::R_S0 $::VAL_S0
d4_settle
coh_prog $::I_ADDI_S0_4 $::I_EBREAK
set ce_c2 [coh_postexec]
d4_settle
set rs2 [d4_abs_read $::R_S0]
puts "DMILOG C (c)-PROGBUF-VISIBLE: after `addi s0,s0,4` cmderr=$ce_c2, s0 reads [format 0x%08X [expr {[lindex $rs2 0] < 0 ? 0 : [lindex $rs2 0]}]] want [format 0x%08X [expr {$::VAL_S0 + 4}]]"
d2_chk [expr {[lindex $rs2 0] == $::VAL_S0 + 4}] \
    "C2: (c) a progbuf program's modification of s0 is visible to the following abstract read ([format 0x%08X [expr {[lindex $rs2 0] < 0 ? 0 : [lindex $rs2 0]}]] vs [format 0x%08X [expr {$::VAL_S0 + 4}]]).  Both directions of the boundary, not just the one OpenOCD happens to exercise first"

# ===========================================================================
# (a) OpenOCD's EXACT two-command memory-READ idiom.
#     Plant the truth through the (d)-class a6/a7 path and CONFIRM it with the
#     peek oracle, so the value (a) must return is established independently of
#     everything under test.
# ===========================================================================
d4_settle
d4_abs_write $::R_A6 $::MEM_R
d4_settle
dmi_write $::DM_DATA0 $::VAL_TRUE
dmi_write $::DM_PROGBUF0 $::I_SW_A7_A6
dmi_write $::DM_PROGBUF1 $::I_EBREAK
dmi_write $::DM_COMMAND [ac_cmd $::R_A7 1 1 1]
d4_wait_notbusy
d4_settle
set planted [coh_tcm $VICTIM $::MEM_R]
puts "DMILOG A PLANT: \[[format 0x%08X $::MEM_R]\] peeks as [format 0x%08X [expr {$planted eq {} ? -1 : $planted}]] want [format 0x%08X $::VAL_TRUE]"
set plant_ok [expr {$planted == $::VAL_TRUE}]
d2_chk $plant_ok \
    "A0: the oracle word really holds the planted truth ([format 0x%08X [expr {$planted eq {} ? -1 : $planted}]]), confirmed by a DIRECT SIMULATOR PEEK and not by reading it back through the path under test.  Without this, (a) below would be comparing two unknowns"

# The idiom, transaction for transaction:
#   abstract-write s0 = addr ; postexec `lw s0,0(s0)` ; abstract-read s0
d4_settle
d4_abs_write $::R_S0 $::MEM_R
d4_settle
coh_prog $::I_LW_S0_S0 $::I_EBREAK
set ce_a [coh_postexec]
d4_settle
set ra1 [d4_abs_read $::R_S0]
set got_a [lindex $ra1 0]
puts "DMILOG A (a)-READ-IDIOM: postexec cmderr=$ce_a ([d4_cmderr_name $ce_a]); abstract s0 = [format 0x%08X [expr {$got_a < 0 ? 0 : $got_a}]] want [format 0x%08X $::VAL_TRUE]"
d2_chk [expr {$ce_a == 0 && $got_a == $::VAL_TRUE}] \
    "A1: (a) OpenOCD's exact two-command memory-READ idiom returns the TRUE memory value -- got [format 0x%08X [expr {$got_a < 0 ? 0 : $got_a}]], the word really holds [format 0x%08X $::VAL_TRUE] (peek oracle).  THE FAILURE SHAPE IS THE POINT: pre-fix this completes with cmderr=0 and hands gdb a WRONG ANSWER, so nothing anywhere reports an error"

# ===========================================================================
# (b) OpenOCD's EXACT two-command memory-WRITE idiom.
#     s0 = address and s1 = value are set by SEPARATE abstract commands and
#     must both survive to the postexec.  The oracle is the peek, again.
# ===========================================================================
d4_settle
set pre_w [coh_tcm $VICTIM $::MEM_W]
d4_abs_write $::R_S0 $::MEM_W
d4_settle
d4_abs_write $::R_S1 $::VAL_STORE
d4_settle
coh_prog $::I_SW_S1_S0 $::I_EBREAK
set ce_b [coh_postexec]
d4_settle
set post_w [coh_tcm $VICTIM $::MEM_W]
puts "DMILOG B (b)-WRITE-IDIOM: postexec cmderr=$ce_b ([d4_cmderr_name $ce_b]); \[[format 0x%08X $::MEM_W]\] [format 0x%08X [expr {$pre_w eq {} ? -1 : $pre_w}]] -> [format 0x%08X [expr {$post_w eq {} ? -1 : $post_w}]] want [format 0x%08X $::VAL_STORE]"
d2_chk [expr {$ce_b == 0 && $pre_w ne "" && $pre_w != $::VAL_STORE && $post_w == $::VAL_STORE}] \
    "B1: (b) OpenOCD's exact two-command memory-WRITE idiom lands the value at the intended word ([format 0x%08X [expr {$pre_w eq {} ? -1 : $pre_w}]] -> [format 0x%08X [expr {$post_w eq {} ? -1 : $post_w}]], peek oracle; the absent-before half is what stops a stale word passing).  Pre-fix s0 holds the wrong address when the store executes, so the write lands somewhere else entirely -- also silently"

# ===========================================================================
# (e) DEBUGGEE PRESERVATION -- passes at HEAD and MUST KEEP PASSING.
#     See the header: this is the leg that catches serve-architectural-directly,
#     the wrong fix that makes (a),(b),(c) green while corrupting the program.
#     NOTE the boundary being tested is HALT+RESUME, and no debugger register
#     write happens inside it.  The magic is installed BEFORE, through a resume
#     -- a different boundary, and one that works in both worlds.
# ===========================================================================
#     WHAT THE WITNESS IS, AND WHY IT IS THE DEBUGGEE'S OWN VALUE.
#     Two setup routes were tried and BOTH are recorded because both taught
#     something:
#       (1) install the magic through the DEBUGGER.  MEASURED, first run
#           2026-08-11: an abstract write of s0 on the pre-fix tree is lost
#           OUTRIGHT -- it reaches neither the architectural register nor
#           dscratch, so nothing is restored on resume and s0/s1 stayed
#           0x00000000.  **That is a sharper statement of F-D5-2 than the spec
#           makes: pre-fix there is NO debugger-visible way to set the
#           debuggee's s0/s1 at all.**  So a debugger-installed magic cannot
#           arm a leg that must PASS at HEAD.
#       (2) plant it from the TESTBENCH by forcing the regfile cell and
#           releasing.  ALSO WRONG, and for a simulator reason worth writing
#           down: `registers` is a DRIVEN VHDL signal, so on `release` it
#           reverts to its driver's last value -- the old one.  The force+
#           release idiom that works for the shared-RAM model (a memory) does
#           NOT transfer to a register file.  Measured: s0 still read
#           0x00000000 after release.
#     So the witness is THE DEBUGGEE'S OWN s0/s1, whatever the program left
#     there, established by two agreeing samples.  That is also the most
#     faithful reading of clause (e): it says "the debuggee's s0/s1", not
#     "a value the debugger put there".
#
#     ON WITNESS STRENGTH, stated rather than glossed (method rule 4): if the
#     program's natural s0/s1 are ZERO, this is a zero witness and a zero
#     witness is normally weak.  Here it still DISCRIMINATES, and the reason is
#     specific: under the natural wrong fix -- serve the architectural
#     registers directly, never restoring -- a resumed hart gets whatever the
#     TRAMPOLINE last left in s0/s1, which is its own working scratch and is
#     not the debuggee's value.  The leg reports the during-halt architectural
#     values precisely so the size of that gap is visible in the log.
#     E-PROBE: try to give the debuggee a NONZERO witness, through the one
#     path that is not under test.  a6 works (D1), so a progbuf pair
#     `lw s0,0(a6)` / `lw s1,4(a6)` makes the CORE ITSELF load magic into its
#     own s0/s1 -- no abstract s0/s1 write anywhere.  Whether that survives the
#     resume is a MEASUREMENT, printed either way, and the witness strength
#     reported below follows it rather than an assumption.
d4_settle
d4_abs_write $::R_A6 $::MEM_R
d4_settle
dmi_write $::DM_DATA0 $::MAGIC_S0
dmi_write $::DM_PROGBUF0 $::I_SW_A7_A6
dmi_write $::DM_PROGBUF1 $::I_EBREAK
dmi_write $::DM_COMMAND [ac_cmd $::R_A7 1 1 1]
d4_wait_notbusy
d4_settle
d4_abs_write $::R_A6 [expr {$::MEM_R + 4}]
d4_settle
dmi_write $::DM_DATA0 $::MAGIC_S1
dmi_write $::DM_PROGBUF0 $::I_SW_A7_A6
dmi_write $::DM_PROGBUF1 $::I_EBREAK
dmi_write $::DM_COMMAND [ac_cmd $::R_A7 1 1 1]
d4_wait_notbusy
d4_settle
d4_abs_write $::R_A6 $::MEM_R
d4_settle
coh_prog $::I_LW_S0_A6 $::I_LW_S1_A6
set ce_probe [coh_postexec]
set probe_s0 [coh_gpr $VICTIM $::X_S0]
set probe_s1 [coh_gpr $VICTIM $::X_S1]
puts "DMILOG E-PROBE (never graded): the CORE loaded its own s0/s1 from memory via a6; cmderr=$ce_probe; while STILL HALTED the architectural s0=[format 0x%08X [expr {$probe_s0 eq {} ? -1 : $probe_s0}]] s1=[format 0x%08X [expr {$probe_s1 eq {} ? -1 : $probe_s1}]] want [format 0x%08X $::MAGIC_S0]/[format 0x%08X $::MAGIC_S1]"

d4_settle
dm_resumereq $VICTIM
dm_poll_status $VICTIM dms_allrunning 400
run 200 us
set live_s0 [coh_gpr $VICTIM $::X_S0]
set live_s1 [coh_gpr $VICTIM $::X_S1]
run 200 us
set live_s0b [coh_gpr $VICTIM $::X_S0]
set live_s1b [coh_gpr $VICTIM $::X_S1]
puts "DMILOG E SETUP: the debuggee's own running s0=[format 0x%08X [expr {$live_s0 eq {} ? -1 : $live_s0}]] s1=[format 0x%08X [expr {$live_s1 eq {} ? -1 : $live_s1}]] (resampled [format 0x%08X [expr {$live_s0b eq {} ? -1 : $live_s0b}]]/[format 0x%08X [expr {$live_s1b eq {} ? -1 : $live_s1b}]])"
set e_setup [expr {$live_s0 ne "" && $live_s1 ne "" &&
                   $live_s0 == $live_s0b && $live_s1 == $live_s1b}]
set e_strong [expr {$live_s0 != 0 || $live_s1 != 0}]
puts "DMILOG E WITNESS STRENGTH: [expr {$e_strong ? {NONZERO -- E1 is a STRONG pass} : {ZERO -- E1 is a WEAK pass, see E2}}]"

# E2 -- THE WITNESS-STRENGTH GATE, and it exists because the first runs proved
# my own header wrong.  I had argued a zero witness still discriminates the
# (e)-killer, on the grounds that a chip serving the architectural registers
# would hand back TRAMPOLINE SCRATCH, which would be nonzero.  MEASURED at
# 899a321: the during-halt architectural s0/s1 are THEMSELVES 0x00000000, and
# the E-PROBE shows the core can execute `lw s0,0(a6)` with cmderr=0 and STILL
# read 0x00000000 back while halted.  So pre-fix the debuggee's s0/s1 are
# structurally pinned to their dscratch values and NOTHING -- debugger or
# progbuf -- can give them a nonzero value.  **A zero witness therefore does
# NOT discriminate the (e)-killer, and the claim is withdrawn rather than
# defended.**
#
# E2 is what replaces it: it requires the debuggee to be ABLE to hold a nonzero
# s0/s1 across a halt.  It fails at HEAD for the same root cause as C1/C2/A1/B1,
# and post-fix it must pass -- at which point E1 automatically becomes the
# strong leg the spec intends, because the witness is nonzero.  E1 alone is
# NOT sufficient evidence for clause (e); E1 AND E2 together are.
set probe_took [expr {$probe_s0 == $::MAGIC_S0 && $probe_s1 == $::MAGIC_S1}]
d2_chk [expr {$probe_took && $e_strong}] \
    "E2: (e) THE WITNESS-STRENGTH GATE -- the debuggee can actually HOLD a nonzero s0/s1: the core loaded [format 0x%08X $::MAGIC_S0]/[format 0x%08X $::MAGIC_S1] into its own s0/s1 through progbuf (probe_took=$probe_took) and still had them while running (strong=$e_strong).  Pre-fix this FAILS -- s0/s1 are pinned to dscratch and cannot be changed by any means -- which is why E1's pass at HEAD is a ZERO-WITNESS pass and must not be read as clearing clause (e) on its own"
d2_chk $e_setup \
    "E0: (e) precondition -- the debuggee's OWN s0/s1 are stable across two samples ([format 0x%08X [expr {$live_s0 eq {} ? -1 : $live_s0}]]/[format 0x%08X [expr {$live_s1 eq {} ? -1 : $live_s1}]]), so there is a defined value for the halt to preserve.  Without this E1 would be comparing an unknown to itself"

if {!$e_setup} {
    puts "DMILOG E1 NOT-GRADED -- the debuggee's s0/s1 were not stable across two samples,"
    puts "DMILOG   so 'the magic survived' would be comparing an unknown to itself."
    puts "DMILOG   NOT-GRADED is NOT a pass: E1 is the leg that catches the natural"
    puts "DMILOG   wrong fix, and a run that could not evaluate it has not cleared it."
    incr ::D2_CHECKS
    incr ::D2_FAILS
    flush stdout
} else {
    # THE LEG: a plain halt+resume with NO debugger register writes at all.
    dm_haltreq $VICTIM
    dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT
    dm_clr_haltreq $VICTIM
    set held_s0 [coh_gpr $VICTIM $::X_S0]
    set held_s1 [coh_gpr $VICTIM $::X_S1]
    dm_resumereq $VICTIM
    dm_poll_status $VICTIM dms_allrunning 400
    run 200 us
    set after_s0 [coh_gpr $VICTIM $::X_S0]
    set after_s1 [coh_gpr $VICTIM $::X_S1]
    puts "DMILOG E DURING-HALT (never graded): architectural s0=[format 0x%08X [expr {$held_s0 eq {} ? -1 : $held_s0}]] s1=[format 0x%08X [expr {$held_s1 eq {} ? -1 : $held_s1}]] -- the trampoline owns these while halted; the debuggee's copies live elsewhere and that is the whole design"
    puts "DMILOG E AFTER-RESUME: s0=[format 0x%08X [expr {$after_s0 eq {} ? -1 : $after_s0}]] s1=[format 0x%08X [expr {$after_s1 eq {} ? -1 : $after_s1}]] want [format 0x%08X $live_s0]/[format 0x%08X $live_s1] (the debuggee's own pre-halt values)"
    d2_chk [expr {$after_s0 == $live_s0 && $after_s1 == $live_s1}] \
        "E1: (e) A PLAIN HALT+RESUME WITH NO DEBUGGER REGISTER WRITES LEAVES THE DEBUGGEE'S s0/s1 INTACT ([format 0x%08X [expr {$after_s0 eq {} ? -1 : $after_s0}]]/[format 0x%08X [expr {$after_s1 eq {} ? -1 : $after_s1}]], unchanged from its pre-halt [format 0x%08X $live_s0]/[format 0x%08X $live_s1]).  PASSES AT HEAD AND MUST KEEP PASSING -- it is the ONLY leg that fails on the natural wrong fix (serve the architectural registers directly), which turns (a),(b),(c) green while handing the resumed program corrupted registers.  A wave that sees a-c go green and E1 go red has found the wrong fix, not a flaky test"
}

# ===========================================================================
# (f) EXCEPTION PRESERVATION.  Graded on the DM's own cmderr and never on a
#     token word -- section 1.5's rider leaves the token mechanism OPEN.
# ===========================================================================
d4_settle
dm_haltreq $VICTIM
dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT
dm_clr_haltreq $VICTIM
d4_settle
coh_prog $::I_ILLEGAL $::I_EBREAK
set ce_f [coh_postexec]
puts "DMILOG F (f)-EXCEPTION: progbuf0=[format 0x%08X $::I_ILLEGAL] (illegal) cmderr=$ce_f ([d4_cmderr_name $ce_f])"
d2_chk [expr {$ce_f == $::CMDERR_EXCEPTION}] \
    "F1: (f) a genuinely-trapping progbuf program still reports cmderr=EXCEPTION(3) -- got $ce_f ([d4_cmderr_name $ce_f]).  Passes in both worlds, declared: it exists so a fix cannot buy clean memory access by weakening exception reporting.  Graded on the DM's own cmderr, never on a token -- the token mechanism is OPEN per the reworded 1.5 rider"

ac_clear_cmderr
set verdict [d2_run_to_verdict 800 "25 us"]
d2_report_verdict "dbg_s0coh" $verdict
d2_summary "dbg_s0coh" 9
flush stdout
exit
