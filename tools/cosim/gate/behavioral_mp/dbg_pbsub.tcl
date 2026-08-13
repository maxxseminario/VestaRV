# =============================================================================
# dbg_pbsub.tcl -- the BLIND DETECTOR for F-D5-1 (R-DD8): the progbuf
# ebreak -> jal-to-epilogue substitution.
#
#   ./xrun_dbg_verify.sh verify_castaliadebug ../kba/xrv32ua-p-dbgtrpmp.rcf dbg_pbsub.tcl
#   ./xrun_dbg_verify.sh verify_argusdebug    ../kf0/xrv32ua-p-dbgtrpmp.rcf dbg_pbsub.tcl
#
# BLIND-AUTHORED 2026-08-10 by the D5 acceptance author, RESUMED under the
# R-D2-3(5) wall-both-ways pattern, against d5_spec.md section 1.5 as amended
# by R-DD8 (FROZEN) -- and against NOTHING ELSE.  The author is barred from,
# and has not opened, the implementer's fix, `dbg_pbebrk.tcl`, or the
# implementer's devlog section on this finding.  Committed polarity (R-K5-8):
# correct RTL = PASS.
#
# ---------------------------------------------------------------------------
# THE FINDING, from the frozen contract only
#   Stock OpenOCD terminates every short progbuf program -- i.e. EVERY memory
#   access -- with an EXPLICIT 32-bit ebreak (0x00100073) written into
#   progbuf0/1.  On the pre-fix tree that program ends in cmderr=3 (EXCEPTION).
#   The frozen fix: a DMI PROXY WRITE of exactly 0x00100073 into progbuf0 or
#   progbuf1 stores a POSITION-CORRECT `jal x0, (W_EPILOG - W_progbufN)*4`
#   instead.  Scope frozen: progbuf0/1 proxy writes ONLY; data0 untouched;
#   EXACT-encoding match only; readback returns the SUBSTITUTED word; and a
#   genuinely-trapping program still reports EXCEPTION.
#
# ---------------------------------------------------------------------------
# WHAT THIS FILE DELIBERATELY DOES NOT ASSERT, and it is the sharpest design
# decision in it.
#
#   1. IT NEVER READS FLAGS[h] OR ANY TOKEN VALUE.  Section 1.5's rule-12
#      rider was REWORDED on 2026-08-10 precisely because the general
#      "the entry publishes HALTED on any re-entry" mechanism is NOT
#      established -- only two per-leg token VALUES are measured, and they
#      disagree with each other unless some ordering/consumption effect
#      intervenes.  An exception detector keyed on the token would therefore
#      be asserting the one thing the rider leaves OPEN.  So the
#      exception-preservation leg (C1) grades `abstractcs.cmderr` -- the DM's
#      own architectural register, and the exact observable section 1.5 names
#      ("still reports EXCEPTION").  If the token mechanism is later settled,
#      nothing here needs to change.
#
#   2. IT NEVER ASSERTS A LITERAL SUBSTITUTED WORD.  The obvious readback
#      check is `progbuf1 == 0x1b80006f`, and it would be wrong twice over:
#      it encodes the implementer's exact offset arithmetic (which is theirs),
#      and it silently stops meaning anything if the epilogue ever moves.
#      Instead B1/B2 assert the STRUCTURE -- opcode 1101111 with rd = x0, i.e.
#      an unconditional jal that discards its link -- and B3 asserts
#      POSITION-CORRECTNESS the only way that word actually means anything:
#      **the substituted words at progbuf0 and progbuf1 must DECODE TO THE
#      SAME ABSOLUTE TARGET.**  Two different source positions resolving to
#      one destination IS position-correctness, expressed without knowing
#      where the destination is.  A fixed, position-BLIND offset -- the
#      natural wrong implementation -- passes B1 and B2 and fails B3, and
#      nothing else in this file would catch it.
#
# ---------------------------------------------------------------------------
# PREDICTIONS, written before the first run (method rule 3).  Recorded here so
# a miss is a miss.
#   A1 PASS at HEAD  the victim halts (precondition)
#   A2 FAIL at HEAD  the OpenOCD write shape ends cmderr=3 (EXCEPTION)
#   A3 **PASS at HEAD** -- and this is the subtle one.  progbuf0's `sw` runs
#      BEFORE progbuf1's ebreak traps, so THE DATA REALLY MOVES on the
#      pre-fix tree and only the verdict is wrong.  A detector that graded
#      "the memory word moved" ALONE would pass on the broken chip.  That is
#      why A2 and A3 are both graded and why neither is sufficient.
#   A4 FAIL at HEAD  the read shape likewise ends cmderr=3
#   A5 **PASS at HEAD** -- same reason: the `lw` lands in s1 before the trap.
#   B1 FAIL at HEAD  progbuf1 reads back the ebreak verbatim, not a jal
#   B2 FAIL at HEAD  progbuf0 likewise
#   B3 FAIL at HEAD  neither word is a jal, so there is no common target
#   C1 PASS at HEAD  a genuinely-trapping program already reports EXCEPTION
#   D1 PASS at HEAD  data0 stores the ebreak verbatim (the scope guard)
#   E1 PASS at HEAD  a non-ebreak progbuf word stores verbatim
#   F1 PASS at HEAD  a word ONE BIT away from the ebreak stores verbatim
#   => predicted 5 FAIL / 7 PASS of 12 at HEAD; 12/12 post-fix.
#
# SCORED against the measurement (86d0737), and the predictions are NOT edited
# above -- they stand as written:
#   THE FAILURE SET WAS EXACTLY RIGHT: A2, A4, B1, B2, B3 failed and nothing
#   else did.  A3 and A5 PASSED pre-fix as predicted -- the data really does
#   move and only the verdict is wrong.
#   ONE MISS, AND IT WAS MINE, NOT THE CHIP'S: the FIRST measurement showed A3
#   and A5 FAILING, which would have contradicted the prediction.  The cause
#   was the first draft's use of s0/s1 as operands (see THE REGISTER-CHOICE
#   NOTE) -- the abstract write reported success and never reached the
#   architectural register, so the program stored to address 0.  With a6/a7 the
#   predicted values reproduced exactly.  Recorded as a miss of the harness,
#   with the chip prediction upheld, rather than quietly rewritten as a hit.
#   A0 was ADDED after that first run and is therefore unpredicted; the run
#   count is 13, not 12.
#
# ---------------------------------------------------------------------------
# WHY E1 AND F1 EXIST (they pass in both worlds, on purpose).  Section 1.5
# says "EXACT-encoding match only".  Without E1/F1 an implementation that
# substituted a jal for EVERY progbuf proxy write -- destroying every real
# program OpenOCD ever loads -- would pass A, B, C and D.  F1 writes a word
# ONE BIT away from the ebreak (0x00100072) and requires it stored verbatim,
# which pins the match to the exact 32-bit value rather than to a mask or a
# funct3/opcode family.  Neither leg can fail at HEAD; both are stated as
# PASS-in-both-worlds rather than dressed up as evidence.
#
# ---------------------------------------------------------------------------
# THE REGISTER-CHOICE NOTE, and it is a MEASUREMENT, not a preference.
#
# Stock OpenOCD's memory idiom uses s0 (x8) as the address and s1 (x9) as the
# value.  The first draft of this file did the same and A0 caught it:
#
#     A0 OPERANDS: abstract write of s0 cmderr=0; s0 reads back 0x00000000
#                  (read-cmderr=0) want 0x0000BE00
#
# **The abstract write reported SUCCESS and did not take.**  That is not a
# harness bug and it is not F-D5-1: this DM serves abstract accesses to s0/s1
# out of the trampoline's dscratch copies (`debug_module.vhd`, the
# `if isgpr and n = R_S0 then` arm), so a written value lands in the saved
# copy rather than in the architectural register a progbuf program then reads.
# It is very probably the same object as the toolchain probe's `SimpleS1Test`,
# which fails on stock Spike AND here, in every configuration, and which that
# probe had already flagged as "x8/x9 are exactly the registers riscv-013 uses
# as program-buffer scratch".
#
# So this detector carries the address in **a6 (x16)** and the value in
# **a7 (x17)** -- the pair D4's own readback walk already proves round-trips.
# Everything F-D5-1 is about is unchanged: a lw/sw-class instruction in
# progbuf0, an EXPLICIT 32-bit ebreak in progbuf1, and the transfer+postexec
# command shape.  Only the register numbers differ, and they differ to REMOVE
# a confound that belongs to a different, still-open finding.  If the detector
# used s0/s1 it could fail for two independent reasons and name neither.
#
# The s0 behaviour is kept as a REPORTED, NEVER-GRADED control (S0-CTRL), so
# the day it changes, this file says so instead of quietly starting to pass
# for a new reason.
#
# WHY THE TRAPPING PROGRAM IS AN ILLEGAL INSTRUCTION AND NOT A BAD LOAD.
# There is no trapping-load class available to a progbuf program in the
# shipped debug configuration: a tile access >= 0x20000 reads ZEROS with no
# stall (the flash decode is enabled in every tile), and the default debug
# build has no PMP.  So `0x00000000` -- a defined illegal encoding -- is the
# only deterministic way to make a progbuf program genuinely trap.  Stated
# because the obvious alternative silently does not trap.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tramp_lib.tcl]} { source dbg_tramp_lib.tcl } else { source ../behavioral_mp/dbg_tramp_lib.tcl }

set VICTIM 1

# Encodings VALIDATED AGAINST THE TOOLCHAIN, not against my arithmetic
# (riscv-none-elf-as + objdump, this session):
#   sw a7,0(a6) = 0x01182023   lw a7,0(a6) = 0x00082883   ebreak = 0x00100073
#   (and, for the record, sw s1,0(s0) = 0x00942023 / lw s1,0(s0) = 0x00042483,
#    the literal OpenOCD pair -- see THE REGISTER-CHOICE NOTE in the header)
set ::PB_EBREAK   0x00100073
set ::PB_SW       0x01182023
set ::PB_LW       0x00082883
set ::PB_ILLEGAL  0x00000000     ;# a defined illegal encoding
set ::PB_NEARMISS 0x00100072     ;# the ebreak with bit 0 cleared -- ONE bit away
set ::PB_KNOWN    0xA5A5A5A5     ;# the method-validation known-nonzero
set ::R_A6 0x1010                ;# x16 -- the ADDRESS operand
set ::R_A7 0x1011                ;# x17 -- the VALUE operand
set ::R_S0 0x1008                ;# x8  -- probed as a control ONLY, never graded

# The memory target: a TCM word in the RETIRED 0xBE00-0xBEFF claim (CLAUDE.md
# -- the D1 instruments' old debug-entry band, given up when DEBUG_ENTRY_ADDR
# moved into the shared page).  Private to the tile, unreachable from the
# shared bus, well clear of the ISR bank (ends 0xBAFF) and below the stack top
# (0xBFF0).  The pre-value is READ and required to differ from the cookie, so
# nothing here depends on it being zero.
set ::PB_MEM   0x0000BE00
set ::PB_COOKIE 0xD5B7EA11

proc pb_tcm_word {h addr} {
    if {$addr < 0x8000 || $addr > 0xBFFC} { return "" }
    if {[catch {value ":dut:hart${h}:ram0:RAM:mem([expr {($addr - 0x8000) >> 2}])"} v]} { return "" }
    return [d2_int $v]
}

# ---------------------------------------------------------------------------
# jal decode.  RISC-V UJ-type: opcode[6:0]=1101111, rd[11:7],
# imm = {imm[20]=b31, imm[19:12]=b19:12, imm[11]=b20, imm[10:1]=b30:21, 0},
# sign-extended, added to the address OF THE JAL ITSELF.
# Returns {is_jal rd target_offset}.
# ---------------------------------------------------------------------------
proc pb_decode_jal {w} {
    set op [expr {$w & 0x7F}]
    set rd [expr {($w >> 7) & 0x1F}]
    if {$op != 0x6F} { return [list 0 $rd 0] }
    set i20 [expr {($w >> 31) & 0x1}]
    set i19_12 [expr {($w >> 12) & 0xFF}]
    set i11 [expr {($w >> 20) & 0x1}]
    set i10_1 [expr {($w >> 21) & 0x3FF}]
    set off [expr {($i20 << 20) | ($i19_12 << 12) | ($i11 << 11) | ($i10_1 << 1)}]
    if {$i20} { set off [expr {$off - (1 << 21)}] }
    return [list 1 $rd $off]
}

puts "DMILOG ================ dbg_pbsub: the F-D5-1 progbuf ebreak->jal detector ================"
puts "DMILOG   subject: a DMI proxy write of exactly 0x00100073 into progbuf0/1 stores a"
puts "DMILOG            POSITION-CORRECT jal x0,<epilogue> instead (d5_spec 1.5, R-DD8)."
puts "DMILOG   NHARTS=[expr {[info exists ::env(D2_NHARTS)] ? $::env(D2_NHARTS) : {?}}]"
puts "DMILOG   N-INDEPENDENCE: the subject is the DM's single progbuf proxy-write path."
puts "DMILOG            There is ONE dm0 and progbuf0/1 are not per-hart, so nothing in"
puts "DMILOG            this file is indexed by hartid.  N=18 is run to PROVE that rather"
puts "DMILOG            than to assume it."
flush stdout

if {![dmi_present]} { puts "DMILOG dbg_pbsub VERDICT=INSTRUMENT_DEAD" ; flush stdout ; exit }

d4_wait_ready

# ---- halt the victim: every abstract command needs a halted hart -----------
dm_select $VICTIM
dm_haltreq $VICTIM
set s [dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT]
d2_chk [expr {$s >= 0}] "A1: hart $VICTIM halted on haltreq (dmstatus [format 0x%08X $s]) -- the precondition for every abstract command below"
dm_clr_haltreq $VICTIM
d4_settle

# ---------------------------------------------------------------------------
# METHOD VALIDATION, before anything is graded (rule 4).  The progbuf proxy
# read/write path must be shown to round-trip a KNOWN NONZERO -- otherwise
# "progbuf1 read back 0x00100073" below would be uninterpretable: it could
# mean "stored verbatim" or it could mean the read path returns whatever was
# last written to the DMI bus.
# ---------------------------------------------------------------------------
dmi_write $::DM_PROGBUF0 $::PB_KNOWN
dmi_write $::DM_PROGBUF1 [expr {~$::PB_KNOWN & 0xFFFFFFFF}]
set k0 [dmi_read $::DM_PROGBUF0]
set k1 [dmi_read $::DM_PROGBUF1]
puts "DMILOG CONTROL progbuf0 round-trip: wrote [format 0x%08X $::PB_KNOWN] read [format 0x%08X $k0]"
puts "DMILOG CONTROL progbuf1 round-trip: wrote [format 0x%08X [expr {~$::PB_KNOWN & 0xFFFFFFFF}]] read [format 0x%08X $k1]"
set method_live [expr {$k0 == $::PB_KNOWN && $k1 == (~$::PB_KNOWN & 0xFFFFFFFF) && $k0 != $k1}]
if {!$method_live} {
    puts "DMILOG METHOD_NOT_VALIDATED -- the progbuf proxy path did not round-trip two"
    puts "DMILOG   DISTINCT known-nonzero words.  Until it does, every readback verdict"
    puts "DMILOG   below is uninterpretable.  Nothing is graded."
    puts "DMILOG dbg_pbsub VERDICT=INSTRUMENT_DEAD"
    flush stdout
    exit
}
puts "DMILOG METHOD_VALIDATED -- progbuf0 and progbuf1 round-trip two distinct nonzero words independently."

# S0-CTRL -- REPORTED, NEVER GRADED.  See THE REGISTER-CHOICE NOTE in the
# header.  s0/s1 are served from the trampoline's dscratch copies, so an
# abstract write of s0 reports SUCCESS and is not visible to a progbuf program
# in the same halt.  That is a different, still-open finding (the probable
# object of the vendored suite's SimpleS1Test) and this detector deliberately
# steers around it -- but it prints the measurement every run, so the day the
# behaviour changes this file says so rather than silently starting to pass
# for a new reason.
d4_settle
set s0w [d4_abs_write $::R_S0 0x5150C0DE]
d4_settle
set s0r [d4_abs_read $::R_S0]
puts "DMILOG S0-CTRL (never graded): abstract write of s0 cmderr=$s0w; s0 reads back [format 0x%08X [expr {[lindex $s0r 0] < 0 ? 0 : [lindex $s0r 0]}]] want 0x5150C0DE -- a MISMATCH here is the EXPECTED pre-existing s0/s1 dscratch behaviour, not an F-D5-1 symptom"
d4_settle
flush stdout

# ===========================================================================
# LEG A -- OpenOCD's EXACT memory-access byte shape.
#
# riscv-013's write_memory_progbuf, reproduced transaction for transaction:
#   abstract-write s0 = address
#   progbuf0 = sw s1,0(s0)
#   progbuf1 = EXPLICIT 32-bit ebreak            <-- the F-D5-1 trigger
#   command: regno=s1, write=1, transfer=1, postexec=1   (value rides in data0)
# ===========================================================================
set pre_mem [pb_tcm_word $VICTIM $::PB_MEM]
set wr_s0 [d4_abs_write $::R_A6 $::PB_MEM]
d4_settle
# A0 -- THE OPERANDS REALLY LOADED.  Added after the first run: A3 measured
# "the memory word did not move", and that verdict is worthless until it is
# separated from "the program never had an address to store to".  Reading s0
# back through the DM costs one abstract command and makes A3 attributable.
set rb_s0 [d4_abs_read $::R_A6]
puts "DMILOG A0 OPERANDS: abstract write of a6 cmderr=$wr_s0; a6 reads back [format 0x%08X [expr {[lindex $rb_s0 0] < 0 ? 0 : [lindex $rb_s0 0]}]] (read-cmderr=[lindex $rb_s0 1]) want [format 0x%08X $::PB_MEM]"
d2_chk [expr {$wr_s0 == 0 && [lindex $rb_s0 0] == $::PB_MEM}] \
    "A0: the address operand really loaded -- a6 holds [format 0x%08X $::PB_MEM] before the program runs.  Without this leg, A3's 'the word did not move' cannot be told apart from 'the program had nowhere to store'"
d4_settle
dmi_write $::DM_PROGBUF0 $::PB_SW
dmi_write $::DM_PROGBUF1 $::PB_EBREAK
dmi_write $::DM_DATA0    $::PB_COOKIE
dmi_write $::DM_COMMAND  [ac_cmd $::R_A7 1 1 1]
set acsA [d4_wait_notbusy]
set ceA  [expr {$acsA < 0 ? -1 : [acs_cmderr $acsA]}]
set post_mem [pb_tcm_word $VICTIM $::PB_MEM]
# Did the TRANSFER half of the command happen even though the program trapped?
# Separates "the value never reached a7" from "a7 held it and the store did
# not run".  Diagnostic, printed and never graded.
d4_settle
set diag_s1 [d4_abs_read $::R_A7]
set diag_s0 [d4_abs_read $::R_A6]
puts "DMILOG A DIAG after the write-shape: a7=[format 0x%08X [expr {[lindex $diag_s1 0] < 0 ? 0 : [lindex $diag_s1 0]}]] a6=[format 0x%08X [expr {[lindex $diag_s0 0] < 0 ? 0 : [lindex $diag_s0 0]}]] -- printed, never graded"
puts "DMILOG A WRITE-SHAPE: abstractcs=[format 0x%08X [expr {$acsA<0?0:$acsA}]] cmderr=$ceA ([d4_cmderr_name $ceA])"
puts "DMILOG A MEMORY \[[format 0x%08X $::PB_MEM]\]: before=[format 0x%08X [expr {$pre_mem eq {} ? -1 : $pre_mem}]] after=[format 0x%08X [expr {$post_mem eq {} ? -1 : $post_mem}]] cookie=[format 0x%08X $::PB_COOKIE]"
d2_chk [expr {$ceA == 0}] \
    "A2: OpenOCD's exact memory-WRITE shape (sw + explicit ebreak, transfer+write+postexec) completes cmderr=NONE -- got $ceA ([d4_cmderr_name $ceA]).  cmderr=3 here is F-D5-1: the ebreak OpenOCD writes into progbuf1 is executed as a real ebreak and the DM reports an exception on a program that did exactly what it was asked"
d2_chk [expr {$post_mem ne "" && $pre_mem ne "" && $pre_mem != $::PB_COOKIE && $post_mem == $::PB_COOKIE}] \
    "A3: ...and the memory word ACTUALLY MOVED -- [format 0x%08X [expr {$pre_mem eq {} ? -1 : $pre_mem}]] -> [format 0x%08X [expr {$post_mem eq {} ? -1 : $post_mem}]] (a VALUE check against an independent peek oracle, not an absence of error).  EXPECTED TO PASS PRE-FIX TOO: progbuf0's store executes before progbuf1's ebreak traps, so on the broken chip the data moves and only the verdict is wrong -- which is exactly why A2 and A3 are graded separately and neither alone is the detector"

d4_settle
# ---- the READ half of the same shape --------------------------------------
d4_abs_write $::R_A6 $::PB_MEM
d4_settle
dmi_write $::DM_PROGBUF0 $::PB_LW
dmi_write $::DM_PROGBUF1 $::PB_EBREAK
dmi_write $::DM_COMMAND  [ac_cmd $::R_A7 0 0 1]   ;# transfer=0, postexec=1
set acsB [d4_wait_notbusy]
set ceB  [expr {$acsB < 0 ? -1 : [acs_cmderr $acsB]}]
d4_settle
set rdb [d4_abs_read $::R_A7]
set rdv [lindex $rdb 0]
puts "DMILOG A READ-SHAPE: cmderr=$ceB ([d4_cmderr_name $ceB]) then a7=[format 0x%08X [expr {$rdv < 0 ? 0 : $rdv}]] (read-cmderr=[lindex $rdb 1])"
d2_chk [expr {$ceB == 0}] \
    "A4: OpenOCD's exact memory-READ shape (lw + explicit ebreak, postexec) completes cmderr=NONE -- got $ceB ([d4_cmderr_name $ceB])"
d2_chk [expr {$rdv == $::PB_COOKIE}] \
    "A5: ...and the value read back through the hart equals what was written ([format 0x%08X [expr {$rdv < 0 ? 0 : $rdv}]] vs [format 0x%08X $::PB_COOKIE]).  Also EXPECTED TO PASS PRE-FIX: the lw lands in a7 before the ebreak traps"

# ===========================================================================
# LEG B -- the substitution is VISIBLE and POSITION-CORRECT.
# ===========================================================================
d4_settle
dmi_write $::DM_PROGBUF0 $::PB_EBREAK
dmi_write $::DM_PROGBUF1 $::PB_EBREAK
set b0 [dmi_read $::DM_PROGBUF0]
set b1 [dmi_read $::DM_PROGBUF1]
set d0 [pb_decode_jal $b0]
set d1 [pb_decode_jal $b1]
puts "DMILOG B READBACK progbuf0 = [format 0x%08X $b0]  jal=[lindex $d0 0] rd=x[lindex $d0 1] off=[lindex $d0 2]"
puts "DMILOG B READBACK progbuf1 = [format 0x%08X $b1]  jal=[lindex $d1 0] rd=x[lindex $d1 1] off=[lindex $d1 2]"
d2_chk [expr {$b0 != $::PB_EBREAK && [lindex $d0 0] == 1 && [lindex $d0 1] == 0}] \
    "B1: a proxy write of the ebreak into progbuf0 reads back as something ELSE, and that something is jal-class (opcode 1101111) with rd=x0 -- got [format 0x%08X $b0] (jal=[lindex $d0 0] rd=x[lindex $d0 1]).  Structure, deliberately not a literal: the epilogue's address is the implementer's arithmetic, not this detector's"
d2_chk [expr {$b1 != $::PB_EBREAK && [lindex $d1 0] == 1 && [lindex $d1 1] == 0}] \
    "B2: ...and the same for progbuf1 -- got [format 0x%08X $b1] (jal=[lindex $d1 0] rd=x[lindex $d1 1])"

# POSITION-CORRECTNESS without knowing where the epilogue is: progbuf0 and
# progbuf1 sit one word apart (W_PROGBUF1 = W_PROGBUF0 + 1), so two
# position-correct jals must resolve to ONE common absolute target, i.e. their
# offsets must differ by exactly 4 with progbuf0's the larger.
set posok 0
set delta "n/a"
if {[lindex $d0 0] == 1 && [lindex $d1 0] == 1} {
    set delta [expr {[lindex $d0 2] - [lindex $d1 2]}]
    set posok [expr {$delta == 4}]
}
puts "DMILOG B POSITION: off(progbuf0)-off(progbuf1) = $delta (want exactly 4)"
d2_chk $posok \
    "B3: THE POSITION-CORRECTNESS CHECK -- progbuf0's and progbuf1's substituted jals resolve to the SAME absolute target (their offsets differ by exactly 4, the one word between them; measured $delta).  This is what 'position-correct' means, expressed without hard-coding where the epilogue is.  A FIXED, position-BLIND offset -- the natural wrong implementation -- passes B1 and B2 and fails ONLY here"

# ===========================================================================
# LEG C -- a genuinely-trapping program still reports EXCEPTION.
# Graded on the DM's own cmderr and NOT on any token/FLAGS word: section
# 1.5's rule-12 rider (as reworded 2026-08-10) leaves the general token
# mechanism OPEN, and a detector must not assert what is open.
# ===========================================================================
d4_settle
dmi_write $::DM_PROGBUF0 $::PB_ILLEGAL
dmi_write $::DM_PROGBUF1 $::PB_EBREAK
dmi_write $::DM_COMMAND  [ac_cmd $::R_A7 0 0 1]
set acsC [d4_wait_notbusy]
set ceC  [expr {$acsC < 0 ? -1 : [acs_cmderr $acsC]}]
puts "DMILOG C TRAPPING-PROGRAM: progbuf0=[format 0x%08X $::PB_ILLEGAL] (illegal) cmderr=$ceC ([d4_cmderr_name $ceC])"
d2_chk [expr {$ceC == $::CMDERR_EXCEPTION}] \
    "C1: a GENUINELY-trapping progbuf program still reports cmderr=EXCEPTION(3) -- got $ceC ([d4_cmderr_name $ceC]).  PASSES PRE-FIX TOO, declared in advance: this leg exists to prove the fix did not buy cmderr=0 by disabling exception reporting.  It grades the DM's own cmderr, never a token word -- the token mechanism is OPEN per the reworded 1.5 rider and a detector must not assert what is open"

# ===========================================================================
# LEG D -- data0 is OUT of scope and must stay verbatim.
# ===========================================================================
d4_settle
dmi_write $::DM_DATA0 $::PB_EBREAK
set dd [dmi_read $::DM_DATA0]
puts "DMILOG D DATA0: wrote [format 0x%08X $::PB_EBREAK] read [format 0x%08X $dd]"
d2_chk [expr {$dd == $::PB_EBREAK}] \
    "D1: a write of 0x00100073 to DATA0 is stored VERBATIM ([format 0x%08X $dd]) -- the substitution is scoped to progbuf0/1 proxy writes and must not leak to the data register.  Passes pre-fix; it is the scope guard, and it is the only check that would catch a substitution applied at the wrong place in the proxy path"

# ===========================================================================
# LEGS E/F -- EXACT-encoding match only.
# ===========================================================================
d4_settle
dmi_write $::DM_PROGBUF0 $::PB_LW
set e0 [dmi_read $::DM_PROGBUF0]
d2_chk [expr {$e0 == $::PB_LW}] \
    "E1: a NON-ebreak progbuf word is stored verbatim (wrote [format 0x%08X $::PB_LW], read [format 0x%08X $e0]).  Without this, an implementation that substituted a jal for EVERY progbuf write -- destroying every real program OpenOCD loads -- passes legs A, B, C and D"
dmi_write $::DM_PROGBUF1 $::PB_NEARMISS
set f1 [dmi_read $::DM_PROGBUF1]
d2_chk [expr {$f1 == $::PB_NEARMISS}] \
    "F1: a word ONE BIT away from the ebreak is stored verbatim (wrote [format 0x%08X $::PB_NEARMISS], read [format 0x%08X $f1]).  This pins 'exact-encoding match' to the exact 32-bit value rather than to a mask, an opcode family or a funct3 -- the three ways a match gets written too loosely"

ac_clear_cmderr
set verdict [d2_run_to_verdict 800 "25 us"]
d2_report_verdict "dbg_pbsub" $verdict
d2_summary "dbg_pbsub" 13
flush stdout
exit
