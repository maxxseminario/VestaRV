# See LICENSE for license details.

#*****************************************************************************
# dbgtrpmp.S   (D-series, D4 -- the trampoline plant, observed IN BAND)
#-----------------------------------------------------------------------------
# BLIND-AUTHORED 2026-08-07 against d4_spec.md sections 1/3/6 (FROZEN
# 2026-08-07) by an agent that has not seen and will never see the D4
# implementation.  Committed polarity (R-K5-8): CORRECT RTL = PASS.
#
# NEEDS A HARNESS.  This image is one half of an instrument; the other half is
# a tcl debugger.  Run it as:
#     ./xrun_dbg_verify.sh verify_castaliadebug ../rcf/xxxxrv32ua-p-dbgtrpmp.rcf dbg_tramp.tcl
#   and likewise with dbg_trpact.tcl / dbg_trprep.tcl / dbg_trpheal.tcl /
#   dbg_trpsess.tcl.  Run WITHOUT a harness it fails on 0x0D260004 (nobody ever
#   released it), which is the correct answer: there was no debugger.
#
# WHAT IT CLAIMS, ARCHITECTURALLY, AND WHY THE CLAIM IS CONTENT-FREE
#   The harness can peek RAM cells; this image cannot, and that is the point.
#   Everything below is a hart executing loads and stores through mp_arbiter,
#   so a page that reads correct here reads correct to the machine.
#
#   The image POISONS the 40-word trampoline slot on command (0x5EAD0000 --
#   see below for why that value), and its final verdict is:
#
#       at release, NONE of the 40 words still holds the poison, and NONE of
#       them is zero, and the seven-word page TAIL (words 57..63) still holds
#       the mark this image wrote before any debugger existed.
#
#   That claim names no instruction.  It does not know, and must not know,
#   what the trampoline contains -- d4_spec 2 makes the built .words file the
#   single content oracle and gives it to a checker, and a test that hard-coded
#   one trampoline word would become a THIRD source of truth for the same 40
#   words.  What the claim does say is: something overwrote my poison at
#   0x10780-0x1081F with non-zero words, and it was not me, and it did not walk
#   past word 39.  On a chip whose Debug Module plants the trampoline that is
#   true; at 286921d, where nothing plants it, the poison is still sitting
#   there and this image FAILS with 0x0D260010.
#
# WHY 0x5EAD0000 AND NOT 0xDEADC0DE
#   A poisoned entry page is FETCHED by a halted hart.  0xDEADC0DE has
#   bits[1:0] = 10, a legal compressed opcode, so a poisoned page could decode
#   as real compressed instructions and let a debug-mode hart execute garbage
#   -- stores anywhere, jumps anywhere.  0x5EAD0000's low halfword is 0x0000,
#   the canonical illegal compressed encoding, so the very first halfword
#   fetched traps; the upper half is never reached.  It is also distinguishable
#   from an untouched (zero) word, which 0x00000000 would not be, and its bit
#   31 is clear so it can be published into a1-a3 on a FAIL path without
#   tripping the periph_tb_pkg img() overflow.
#
# VERDICT (a0 = 0xCAFEBABE pass / 0xDEADBEEF fail; a1 = diagnosis):
#   0x0D260001  the claimed shared band did not read back zero after clearing
#   0x0D260002  base-ISA sanity failed (the arithmetic below is wrong)
#   0x0D260003  the page TAIL mark did not read back after hart 0 wrote it
#               (a2 = tail word index) -- write-before-read on the CODE-ONLY
#               half of the entry page, discharged in band, not inherited
#   0x0D260004  the harness never released this image (SH_REL never arrived).
#               Run without a debugger, this is the expected answer.
#   0x0D260005  the victim tile never started (SH_RAN never advanced)
#   0x0D260006  the agent tile never started (SH_DIAG never armed)
#   0x0D260010  at release, N of the 40 entry-page words STILL HOLD THE POISON
#               (a2 = N).  THE HEADLINE FAILURE: nothing planted the page.
#   0x0D260011  at release, N of the 40 words are ZERO (a2 = N).  A page that
#               nobody ever wrote, or a plant that wrote zeros.
#   0x0D260012  the page TAIL was damaged (a2 = tail word index).  A plant
#               that walked past word 39.
#
# NEGATIVE CONTROL.  Build with -DDBGTRP_NC_NOPOISON and the image never
# poisons on command; the final scan then measures a page nobody has attacked.
# On a D4 chip it still passes (the plant fills it anyway); on 286921d it fails
# 0x0D260011 instead of 0x0D260010, which distinguishes "the poison persisted"
# from "the page was never written by anyone".  The two arms together are what
# make 0x0D260010 mean what it says: the poison really did land, and it really
# did survive.
#
# N-AGNOSTIC.  Two tiles are launched by number (1 and 2) and hart 3 is
# DELIBERATELY LEFT PARKED IN THE BOOT ROM -- dbg_trpsess.tcl halts it to prove
# the no-force session works against a ROM-parked tile as well as a running
# one (d4_spec 3, "both tile states").  No word is indexed by hartid, so the
# layout is identical at N=4 and N=18; at N=18 harts 3..17 are all parked.
#
# SHARED WORDS CLAIMED -- the D-series debug acceptance band 0x10050-0x1007C
#   (CLAUDE.md; 12 words), REUSED with this file's meanings.  Safe for the
#   shdma/wdma reason: one image per sim, and the D-series debug instruments
#   never coexist.  Claim and use are the same document (the F-ID2-1 lesson):
#     0x10050  PHASE   hart 0 progress
#     0x10054  READY   image -> harness: both tiles are demonstrably running
#     0x10058  CMD     harness -> image: 1 poison, 2 scan, 3 corrupt word ARG
#     0x1005C  ARG     harness -> image: the command argument
#     0x10060  SEQ     harness -> image: sequence number; a NEW value is the
#                      command edge.  An ordering, never a delay.
#     0x10064  ACK     image -> harness: echoes SEQ when the command is done
#     0x10068  CHK     image -> harness: rotate-xor hash of the 40 page words,
#                      computed by a RUNNING hart's own loads
#     0x1006C  W0      image -> harness: page word 0, as the hart read it
#     0x10070  W39     image -> harness: page word 39, as the hart read it
#     0x10074  RAN     the victim tile's liveness counter
#     0x10078  REL     harness -> image: release to the final verdict
#     0x1007C  DIAG    the agent tile's arming mark, then failure diagnosis
#
#   THE HARNESS MUST NOT FORCE ANY BAND WORD BEFORE READY.  hart 0 clears all
#   twelve and reads them back at entry; a word forced before that check reads
#   back non-zero and the image fails 0x0D260001 for a harness's reason.
#
# ALSO TOUCHED, and NOT a new claim: the debug program page 0x10680-0x1087F is
#   already claimed in CLAUDE.md.  This image writes only inside it: the 40
#   trampoline words 0x10780-0x1081F (poison/corrupt/scan) and the seven-word
#   tail 0x10864-0x1087C (the mark).  It never touches 0x10680-0x1077F (the DM's
#   data/progbuf/FLAGS words) or 0x10820-0x10860 (the DM's abstract area and
#   epilogue).  The tail is OUTSIDE the bootrom zero range, so hart 0 writes it
#   and reads it back before anything else may read it.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_PHASE   0x10050
#define SH_READY   0x10054
#define SH_CMD     0x10058
#define SH_ARG     0x1005C
#define SH_SEQ     0x10060
#define SH_ACK     0x10064
#define SH_CHK     0x10068
#define SH_W0      0x1006C
#define SH_W39     0x10070
#define SH_RAN     0x10074
#define SH_REL     0x10078
#define SH_DIAG    0x1007C

#define DBG_ENTRY   0x10780
#define TRAMP_WORDS 40
#define PAGE_TAIL   0x10864
#define TAIL_WORDS  7
#define POISON      0x5EAD0000
#define TAILMARK    0x5A170057
#define AGENT_MARK  0x0A6E7001

#define CMD_POISON  1
#define CMD_SCAN    2
#define CMD_CORRUPT 3

#define TILE_WORDS 1024
#define START_T    16
#define GLOBAL_BUDGET 20000
#define REL_BUDGET    40000

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry

    # ---- hart 0: clear the claimed band and prove it cleared ---------------
    li   a1, 0x0D260001
    li   t0, SH_PHASE
    li   t1, 12                     # 12 words: 0x10050 .. 0x1007C
tr_clr:
    sw   x0, 0(t0)
    lw   t2, 0(t0)
    bnez t2, tr_fail
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, tr_clr

    # ---- base-ISA sanity ---------------------------------------------------
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    li   a1, 0x0D260002
    bne  t2, t3, tr_fail

    # ---- mark the entry page's unused TAIL, and read it back ---------------
    # Words 57..63 sit ABOVE 0x10800, outside the bootrom zero range, so this
    # write discharges write-before-read for them in band rather than
    # inheriting it.  The read-back is the instrument-is-live proof: an
    # expected-zero needs independent evidence it was measured at all, and this
    # one is an expected-EQUAL for the same reason.
    li   t0, PAGE_TAIL
    li   t1, TAIL_WORDS
    li   t2, TAILMARK
tr_tailw:
    sw   t2, 0(t0)
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, tr_tailw

    li   t0, PAGE_TAIL
    li   t1, TAIL_WORDS
    li   t2, TAILMARK
    li   a2, 0
tr_tailr:
    lw   t3, 0(t0)
    li   a1, 0x0D260003
    bne  t3, t2, tr_fail
    addi a2, a2, 1
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, tr_tailr

    # ---- launch the two tiles ---------------------------------------------
    # hart 3 (and, at N=18, every hart above it) is deliberately NOT launched:
    # it stays parked in the boot ROM's WFI, which is the second tile state
    # d4_spec 3 asks the no-force session to cover.
    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)

    li   s11, GLOBAL_BUDGET

    # ---- wait for BOTH tiles to demonstrate execution ----------------------
    li   t4, START_T
tr_vwait:
    li   t0, SH_RAN
    lw   t1, 0(t0)
    bge  t1, t4, tr_vok
    addi s11, s11, -1
    bnez s11, tr_vwait
    li   a1, 0x0D260005
    j    tr_fail
tr_vok:
    li   t2, AGENT_MARK
tr_await:
    li   t0, SH_DIAG
    lw   t1, 0(t0)
    beq  t1, t2, tr_aok
    addi s11, s11, -1
    bnez s11, tr_await
    li   a1, 0x0D260006
    j    tr_fail
tr_aok:
    li   t0, SH_PHASE
    li   t1, 1
    sw   t1, 0(t0)
    li   t0, SH_READY
    li   t1, 1
    sw   t1, 0(t0)

    # ---- wait for the debugger to finish ----------------------------------
    # The image does NOT grade itself on its own schedule; the harness says
    # when its session is over.  Expiry is a verdict, never a fall-through.
    li   t4, REL_BUDGET
tr_relwait:
    li   t0, SH_REL
    lw   t1, 0(t0)
    bnez t1, tr_final
    addi t4, t4, -1
    bnez t4, tr_relwait
    li   a1, 0x0D260004
    j    tr_fail

    # ---- THE VERDICT -------------------------------------------------------
tr_final:
    li   t0, SH_PHASE
    li   t1, 2
    sw   t1, 0(t0)

    li   t5, DBG_ENTRY
    li   t6, TRAMP_WORDS
    li   a2, 0                      # poison survivors
    li   a3, 0                      # zero words
tr_scan:
    lw   t0, 0(t5)
    li   t1, POISON
    bne  t0, t1, 1f
    addi a2, a2, 1
1:
    bnez t0, 2f
    addi a3, a3, 1
2:
    addi t5, t5, 4
    addi t6, t6, -1
    bnez t6, tr_scan

    li   a1, 0x0D260010
    bnez a2, tr_fail
    mv   a2, a3
    li   a1, 0x0D260011
    bnez a3, tr_fail

    li   t5, PAGE_TAIL
    li   t6, TAIL_WORDS
    li   t2, TAILMARK
    li   a2, 0
tr_tailv:
    lw   t0, 0(t5)
    beq  t0, t2, 3f
    li   t1, SH_DIAG
    sw   t0, 0(t1)
    li   a1, 0x0D260012
    j    tr_fail
3:
    addi a2, a2, 1
    addi t5, t5, 4
    addi t6, t6, -1
    bnez t6, tr_tailv

    li   t0, SH_PHASE
    li   t1, 9
    sw   t1, 0(t0)
    # Clear the diagnosis registers on the PASS path.  Without this a1 keeps
    # whatever code the LAST unfired check armed -- measured 2026-08-07, the
    # liveness-control arm passed while reporting a1 = 0x0D260011, which reads
    # as a failure code on a passing run.  A wrong label is worse than none.
    li   a1, 0
    li   a2, 0
    li   a3, 0
    j    tr_pass

    # =======================================================================
    # the tiles
    # =======================================================================
tile_entry:
    li   sp, 0xBFF0
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    li   t4, 1
    beq  t3, t4, tile_victim
    li   t4, 2
    beq  t3, t4, tile_agent
tile_park:
    j    tile_park

    # The victim: a plain liveness counter, exactly the dbgdarkmp tile_loop
    # shape.  It is the hart the debugger halts in dbg_tramp/dbg_trpheal/
    # dbg_trpsess, and its counter is the only evidence a halted hart is not
    # retiring.
tile_victim:
    li   t5, SH_RAN
tile_vloop:
    lw   t0, 0(t5)
    addi t0, t0, 1
    sw   t0, 0(t5)
    j    tile_vloop

    # The agent: the in-band observation channel.  It never halts, so it can
    # read the entry page while NO hart is in debug mode -- which is the only
    # way to watch the dmactive-rise plant without the on-halt plant
    # confounding it.  It dispatches on a NEW value of SEQ (an edge, not a
    # delay) and echoes SEQ into ACK when it is done, so every harness step is
    # an ordering.
tile_agent:
    li   t0, SH_DIAG
    li   t1, AGENT_MARK
    sw   t1, 0(t0)
    li   s0, 0
tile_aloop:
    li   t0, SH_SEQ
    lw   s1, 0(t0)
    beq  s1, s0, tile_aloop

    li   t0, SH_CMD
    lw   t2, 0(t0)
    li   t0, SH_ARG
    lw   t3, 0(t0)

    li   t4, CMD_POISON
    beq  t2, t4, ta_poison
    li   t4, CMD_SCAN
    beq  t2, t4, ta_scan
    li   t4, CMD_CORRUPT
    beq  t2, t4, ta_corrupt
    j    ta_done

ta_poison:
#ifdef DBGTRP_NC_NOPOISON
    j    ta_done
#endif
    li   t5, DBG_ENTRY
    li   t6, TRAMP_WORDS
    li   a4, POISON
ta_ploop:
    sw   a4, 0(t5)
    addi t5, t5, 4
    addi t6, t6, -1
    bnez t6, ta_ploop
    j    ta_done

    # Corrupt ONE word, by index in ARG.  This is the "hart store" d4_spec 6
    # names for the re-plant and self-heal legs: a real store instruction, on
    # a real hart, through the real arbiter -- not a tcl poke, and not
    # something a forced word could even represent.
ta_corrupt:
    li   t5, DBG_ENTRY
    slli t6, t3, 2
    add  t5, t5, t6
    li   a4, POISON
    sw   a4, 0(t5)
    j    ta_done

    # The scan.  Rotate-left-1 then xor, so POSITION matters: the right 40
    # words in the wrong order hash differently.  The identical three lines
    # live in dbg_tramp_lib.tcl's d4_hash and nowhere else.
ta_scan:
    li   t5, DBG_ENTRY
    li   t6, TRAMP_WORDS
    li   a4, 0
ta_sloop:
    lw   a5, 0(t5)
    slli a6, a4, 1
    srli a7, a4, 31
    or   a4, a6, a7
    xor  a4, a4, a5
    addi t5, t5, 4
    addi t6, t6, -1
    bnez t6, ta_sloop
    li   t0, SH_CHK
    sw   a4, 0(t0)
    li   t0, DBG_ENTRY
    lw   a5, 0(t0)
    li   t1, SH_W0
    sw   a5, 0(t1)
    li   t0, (DBG_ENTRY + 4*(TRAMP_WORDS-1))
    lw   a5, 0(t0)
    li   t1, SH_W39
    sw   a5, 0(t1)
    j    ta_done

ta_done:
    li   t0, SH_ACK
    sw   s1, 0(t0)
    mv   s0, s1
    j    tile_aloop

tr_pass:
    RVTEST_PASS

tr_fail:
    RVTEST_FAIL

    # NOTE: RVTEST_CODE_END is `unimp` in this env (it traps) -- never fall
    # through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
