# See LICENSE for license details.

# VestaRV: in-band debug-deny detector, no DMI port needed
# Covers the four debug obligations that are software-visible with no debug module, no halt request and no testbench surgery: the 0x7Bx CSR block must trap from M-mode in BOTH knob polarities, `dret` outside debug mode must be illegal, `ebreak` with dcsr.ebreakm = 0 must NOT enter debug mode, and NOTHING may reach DEBUG_ENTRY_ADDR unless a debugger asked. Because nothing here forces a signal, this is the only such instrument that can join the standing lists. Invoke it explicitly with `./xrun_batch.sh rv32ua-p-dbgdenymp`; the three tiles end parked in TRAP_STATE and never write a0_1/a0_2/a0_3, which riscv_tb reports as a NOTE.
# A BOTH-POLARITY TEST MUST BE SHOWN TO BE LIVE, since passing before and after the change proves nothing. Two devices do that. First, the write-form control on an address legal today: hart 0 executes `csrw misa, t0`, and 0x301 is the first term of maindec's csr_addr_valid with no ENABLE_ qualifier, sits in the writable quadrant so csr_ro_denied cannot reach it, and has a WARL-ignore arm, so it must retire on every matrix row; if a decode change spills outside 0x7Bx this catches it, and a hart-0 wedge is unmissable because a default build's TRAP_STATE is terminal. Second, the three victims are observed rather than assumed: each publishes a stepped progress word and hart 0 asserts it stops at its expected value and stays there, so a victim that never armed is a distinct verdict from one that advanced too far.
# THE DEBUG-ENTRY TRIPWIRE is the real detector. Hart 0 plants a 7-word stub at DEBUG_ENTRY_ADDR = 0x10780 in the SHARED window before it launches anybody; the stub writes a hart-identifying magic into DBGMARK and spins. On a correct build it is dead code, since no halt request exists here and dcsr.ebreakm resets to 0, so DBGMARK going nonzero means exactly one thing: a hart entered debug mode with nobody asking. It catches `ebreak` routed to debug entry regardless of dcsr.ebreakm, a 0x7Bx access from M-mode routed there instead of trapping, and `dret` outside debug implemented as a jump there, and the magic names the hart. THE STUB IS PLANTED BY COPYING, NOT BY A LINKER SECTION, because a new section in verification/env/p/link.ld changes build/.imgset and wipes the whole build tree for every suite; it therefore contains no PC-relative reference outside itself and its one internal branch is a relocation-invariant self-loop. Execution from the shared window carries `.option norvc`, which this file sets, because compressed or misaligned execution from shared is untested. IF DEBUG_ENTRY_ADDR MOVES, four sites change: here, dbghaltmp.S, dbgstepmp.S and `set DBG_ENTRY` in dbg_rst.tcl, the last of which is easy to miss.
# A MUST-TRAP ENCODING CONSUMES A VICTIM, because a trap lands in the terminal TRAP_STATE, and hart 0 can take none of them. Six encodings are wanted and three victims exist, so each gets one primary with the rest chained behind it: hart 1 takes `csrr dcsr` (0x7B0) then 0x7B1, 0x7B2, 0x7B3 and a write form at 0x7B0; hart 2 takes `dret` then 0x7B4, the over-wide-HIGH guard; hart 3 takes `ebreak` then 0x7AF, the over-wide-LOW guard. The chained assertions are live only in an already-broken world but still CLASSIFY the breakage. RESIDUAL: with three victims, a fix that admits exactly one of 0x7B1, 0x7B2 or 0x7B3 and not 0x7B0 is invisible here.
# `dret` IS ONLY PARTLY OBSERVABLE. Hart 2 asserts that the instruction after the dret is not reached, which catches a dret admitted by the decoder and executed as a NOP, the half-finished FSM arm. It does NOT catch a dret that executes and jumps to dpc, because dpc resets to something this test cannot set and the hart lands somewhere it cannot report from, leaving PROG at 1 exactly as a trap does. The tripwire covers the sub-case where dpc happens to be DEBUG_ENTRY_ADDR. Full dret semantics belong to dbgstepmp.S.
# Verdicts: a0 = 0xCAFEBABE means all three encodings still trap, no hart reached DEBUG_ENTRY_ADDR and the legal-today control still retires. a1 = 0x0DB60001 a victim never armed; 0x0DB60002 a shared word did not read back; 0x0DB60003 base-ISA sanity failed; 0x0DB60004 a positive-half leg returned the wrong value; 0x0DB60005 POSPROG did not count every positive leg; 0x0D7B0000 hart 1 advanced past PROG 1, so 0x7B0 was admitted for read, with a2 naming how far; 0x0D7B00D6 hart 2 advanced past PROG 1, so `dret` did not trap; 0x0D7B00EB hart 3 advanced past PROG 1, so `ebreak` did not trap; 0x0DB6DEB6 DBGMARK is nonzero, so a hart entered debug mode unasked, with a2 naming which. NO a0 AT ALL is itself a result: hart 0 wedged in its own positive half, meaning a decode change made a legal M-mode CSR access illegal; probe POSPROG at 0x1005C to name the leg.
# THREE NEGATIVE CONTROLS, since a both-polarity detector cannot be seen to fail on an unimplemented tree. -DDBGDENY_NC_7B0 turns hart 1's `csrr dcsr` into a nop, expecting a1 = 0x0D7B0000 with a2 = 2; -DDBGDENY_NC_DRET turns hart 2's `dret` into a nop, which is literally the implementation this instrument exists to catch, expecting a1 = 0x0D7B00D6 with a2 = 2; -DDBGDENY_NC_MARK makes hart 3 jump to DEBUG_ENTRY_ADDR instead of executing `ebreak`, expecting a1 = 0x0DB6DEB6 with a2 = 0xD0B00003. Build them OUT OF TREE, because the .imgset wipe is shared state: `./tools/build_one_rcf.sh tests/rv32ua/dbgdenymp.S rv32ua-p-ddnc7b0 -DDBGDENY_NC_7B0`. They are controls and make no claim about the RTL.
# Knob-independent by construction, which an untagged catalog row has to be: everything hart 0 executes is legal on every matrix row, nothing reads a counter, an FP CSR or a trap CSR, and each victim's primary traps in every polarity. N-agnostic: exactly three victims at any NHARTS and no shared word indexed by hartid. Shared words, inside the 12-word D-series debug band 0x10050-0x1007C and reused with this file's meanings under the one-image-per-sim rule: 0x10050 SUBJPROG, 0x10054 WPROG, 0x10058 GPROG, 0x1005C POSPROG, 0x10060 DBGMARK, which must stay 0; plus the shared debug entry page at 0x10780-0x1087F.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_SUBJPROG  0x10050
#define SH_WPROG     0x10054
#define SH_GPROG     0x10058
#define SH_POSPROG   0x1005C
#define SH_DBGMARK   0x10060

/* R-D2-1(3): the debug entry page in the SHARED window.  See the header for
   why it moved off the TCM and what else changes if the ruling moves again.
   The 7-word tripwire stub fits inside the 64-word entry page
   0x10780-0x1087F (R-D2-2(3)) many times over.                                      */
#define DBG_ENTRY    0x10780

/* 1024 words = 0x8000-0x8FFF, which covers the IVT and the whole image (the
   linked size is ~0x87D0).  The debug stub does NOT ride the staged copy at
   all any more: since the migration it lives in the SHARED window and hart 0
   plants it once.  A full-TCM 4096-word stage would add ~7 ms of serialized
   arbiter traffic for nothing.                                             */
#define TILE_WORDS   1024
#define ARM_BUDGET   12000
#define WATCH_ITERS  4000

/* Every encoding under test is a raw .word so gas cannot rewrite it and so the
   file does not depend on gas's CSR name table.  All eight were verified with
   riscv-none-elf-as + objdump before the first build.                       */
#define CSRR_S0_7B0   0x7B002473    /* csrrs s0, 0x7B0, x0   dcsr       */
#define CSRR_S1_7B1   0x7B1024F3    /* csrrs s1, 0x7B1, x0   dpc        */
#define CSRR_S2_7B2   0x7B202973    /* csrrs s2, 0x7B2, x0   dscratch0  */
#define CSRR_S3_7B3   0x7B3029F3    /* csrrs s3, 0x7B3, x0   dscratch1  */
#define CSRR_S4_7B4   0x7B402A73    /* csrrs s4, 0x7B4, x0   unallocated ABOVE */
#define CSRR_S5_7AF   0x7AF02AF3    /* csrrs s5, 0x7AF, x0   unallocated BELOW */
#define CSRW_7B0_T0   0x7B029073    /* csrrw x0,  0x7B0, t0   write form */
#define DRET_INSN     0x7B200073    /* dret                             */
#define EBREAK_INSN   0x00100073    /* ebreak                           */
#define CSRW_MISA_T0  0x30129073    /* csrrw x0,  0x301, t0   LEGAL TODAY */
#define CSRR_T1_MISA  0x30102373    /* csrrs t1,  0x301, x0   LEGAL TODAY */
#define CSRR_T0_F14   0xF14022F3    /* csrrs t0,  0xF14, x0   mhartid    */

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry            # only hart 0 orchestrates

    li   s2, SH_SUBJPROG
    li   s3, SH_WPROG
    li   s4, SH_GPROG
    li   s5, SH_POSPROG
    li   s6, SH_DBGMARK

    # ==================================================================
    # clear every claimed word and prove it read back
    # ==================================================================
    li   a1, 0x0DB60002
    sw   x0, 0(s2)
    lw   t1, 0(s2)
    bnez t1, dd_fail
    sw   x0, 0(s3)
    lw   t1, 0(s3)
    bnez t1, dd_fail
    sw   x0, 0(s4)
    lw   t1, 0(s4)
    bnez t1, dd_fail
    sw   x0, 0(s5)
    lw   t1, 0(s5)
    bnez t1, dd_fail
    sw   x0, 0(s6)
    lw   t1, 0(s6)
    bnez t1, dd_fail

    # THE PLANT.  Since the migration to the shared window the entry page is
    # GLOBAL: hart 0 plants it once, here, before anything else and long
    # before any victim exists.  It covers the orchestrator too -- if hart 0
    # itself enters debug mode the verdict path is running in debug mode, and
    # that has to be visible.
    jal  ra, dd_plant

    li   s7, 0                      # POSPROG register shadow

    # ==================================================================
    # THE POSITIVE HALF.  Four legs, every one unconditionally legal on
    # every matrix row.  Proof is LIVENESS (a wrongly-trapped instruction
    # wedges hart 0 terminally) plus the asserted values.
    # ==================================================================
    .macro DD_OK
    addi s7, s7, 1
    sw   s7, 0(s5)
    .endm

    li   t0, 1234                   # P0: base ISA sanity
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    DD_OK
    li   a1, 0x0DB60003
    bne  t2, t3, dd_fail

    li   t0, 0x5A5A5A5A             # P1: csrr t0, mhartid -- must read 0
    .word CSRR_T0_F14
    DD_OK
    li   a1, 0x0DB60004
    bnez t0, dd_fail

    li   t0, 0x5A5A5A5A             # P2: THE WRITE-FORM CONTROL.
    .word CSRW_MISA_T0              #     csrw misa, t0 -- writable quadrant,
    DD_OK                           #     WARL-ignore, must RETIRE forever
    li   a1, 0x0DB60004
    li   t1, 0
    .word CSRR_T1_MISA              # P3: csrr t1, misa -- must retire nonzero
    DD_OK
    beqz t1, dd_fail                #     (and prove P2 left no damage)

    lw   t1, 0(s5)
    li   t2, 4
    li   a1, 0x0DB60005
    bne  t1, t2, dd_fail            # four legs, all survived, all recorded

    # ==================================================================
    # launch the three victims
    # ==================================================================
    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(3, tile_entry, TILE_WORDS)

    # ==================================================================
    # bounded wait for every victim to reach its EXPECTED terminal state.
    # All three expect PROG = 1: each victim's PRIMARY encoding is its
    # first, and it must trap.
    # ==================================================================
    li   s8, 1
    li   t6, ARM_BUDGET
dd_wait:
    lw   t2, 0(s2)
    blt  t2, s8, dd_wait_next
    lw   t3, 0(s3)
    blt  t3, s8, dd_wait_next
    lw   t4, 0(s4)
    bge  t4, s8, dd_armed
dd_wait_next:
    addi t6, t6, -1
    bnez t6, dd_wait

    lw   a2, 0(s2)
    lw   t3, 0(s3)
    lw   t4, 0(s4)
    slli a3, t3, 4
    add  a3, a3, t4
    li   a1, 0x0DB60001
    j    dd_fail

dd_armed:
    # ==================================================================
    # observe: no victim may advance past PROG = 1, ever
    # ==================================================================
    li   t6, WATCH_ITERS
dd_watch:
    lw   t2, 0(s2)
    bne  t2, s8, dd_subj_over
    lw   t3, 0(s3)
    bne  t3, s8, dd_wctl_over
    lw   t4, 0(s4)
    bne  t4, s8, dd_guard_over
    lw   t5, 0(s6)
    bnez t5, dd_mark_set            # THE TRIPWIRE, sampled every round
    addi t6, t6, -1
    bnez t6, dd_watch

    # ==================================================================
    # final tripwire read, and the verdict
    # ==================================================================
    lw   t5, 0(s6)
    bnez t5, dd_mark_set

    RVTEST_PASS                     # a0 = 0xCAFEBABE

dd_subj_over:
    mv   a2, t2
    li   a1, 0x0D7B0000             # 0x7B0 admitted for read (a2 says how far)
    j    dd_fail
dd_wctl_over:
    mv   a2, t3
    li   a1, 0x0D7B00D6             # dret did not trap outside debug mode
    j    dd_fail
dd_guard_over:
    mv   a2, t4
    li   a1, 0x0D7B00EB             # ebreak did not trap with ebreakm = 0
    j    dd_fail
dd_mark_set:
    mv   a2, t5
    li   a1, 0x0DB6DEB6             # a hart entered debug mode unasked
dd_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # =====================================================================
    # dd_plant -- copy the tripwire stub to DEBUG_ENTRY_ADDR in the SHARED
    # window.  No arguments: the stub identifies its own hart by reading
    # mhartid, so ONE copy serves all four.  Clobbers t0-t3.
    # MIGRATION NOTE (2026-08-05): the entry page is now global, so this is
    # called ONCE, by hart 0, BEFORE any victim is launched.  The victims no
    # longer plant -- there is nothing per-hart left to plant -- and the
    # tripwire is in place strictly earlier than it used to be.
    # =====================================================================
dd_plant:
    la   t0, dd_stub_start
    la   t1, dd_stub_end
    li   t2, DBG_ENTRY
1:  lw   t3, 0(t0)
    sw   t3, 0(t2)
    addi t0, t0, 4
    addi t2, t2, 4
    blt  t0, t1, 1b
    ret

    # ---- THE TRIPWIRE STUB.  Copied verbatim to DEBUG_ENTRY_ADDR. --------
    # RELOCATION RULES obeyed here: no `la`, no `auipc`, no branch or jump
    # whose target lies outside this block.  The one branch is a self-loop,
    # whose offset is the same wherever the block lands.  `li` of an absolute
    # constant and `csrr` of an absolute CSR number are both position-free.
    # It reads mhartid so ONE copy serves all four harts.  NO .align here:
    # `.balign`/`.align` are silent no-ops inside a `.option norvc` region
    # (CLAUDE.md), and every instruction in this file is 4 bytes anyway, so
    # the block is word-aligned by construction.
dd_stub_start:
    .option push
    .option arch, +zicsr
    csrr a4, mhartid
    .option pop
    li   a3, 0xD0B00000
    add  a4, a4, a3                 # 0xD0B0000h -- names the hart
    li   a3, SH_DBGMARK
    sw   a4, 0(a3)
2:  j    2b
dd_stub_end:

    # ---- tile harts enter here (loader ABI: only sp is defined) ----------
tile_entry:
    li   sp, 0xBFF0
    # No plant here since the migration: the entry page is SHARED and hart 0
    # planted it before this hart was launched.  (Planting again would be
    # harmless -- identical bytes -- but it would suggest the page were
    # per-hart, which is exactly the misreading the migration exists to end.)
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    li   t4, 1
    beq  t3, t4, tile_h1
    li   t4, 2
    beq  t3, t4, tile_h2
    li   t4, 3
    beq  t3, t4, tile_h3
tile_park:
    j    tile_park

    # ---- hart 1: THE 0x7Bx READ BLOCK -----------------------------------
    # The instruction immediately after every encoding under test is an
    # `addi`, never a store, so F8 (TRAP_STATE decoding and committing the
    # word at pc_next_trad_reg) cannot fire on any of them.
tile_h1:
    li   t0, SH_SUBJPROG
    li   t1, 1
    sw   t1, 0(t0)                  # PROG=1: about to read dcsr -- TERMINAL
#ifdef DBGDENY_NC_7B0
    nop                             # NEGATIVE CONTROL: the primary is removed
#else
    .word CSRR_S0_7B0               # 0x7B0 -- MUST TRAP from M-mode
#endif
    addi t1, x0, 2
    sw   t1, 0(t0)                  # PROG=2: reached only if 0x7B0 admitted
    .word CSRR_S1_7B1               # 0x7B1 -- chained
    addi t1, x0, 3
    sw   t1, 0(t0)
    .word CSRR_S2_7B2               # 0x7B2 -- chained
    addi t1, x0, 4
    sw   t1, 0(t0)
    .word CSRR_S3_7B3               # 0x7B3 -- chained
    addi t1, x0, 5
    sw   t1, 0(t0)                  # PROG=5: the whole block admitted for read
    .word CSRW_7B0_T0               # a WRITE FORM at 0x7B0 -- chained
    addi t1, x0, 6
    sw   t1, 0(t0)                  # PROG=6: the write form retired too
tile_h1_park:
    j    tile_h1_park

    # ---- hart 2: `dret` OUTSIDE DEBUG MODE ------------------------------
tile_h2:
    li   t0, SH_WPROG
    li   t1, 1
    sw   t1, 0(t0)                  # PROG=1: about to execute dret -- TERMINAL
#ifdef DBGDENY_NC_DRET
    nop                             # NEGATIVE CONTROL: the primary is removed
#else
    .word DRET_INSN                 # MUST be illegal-instruction outside debug
#endif
    addi t1, x0, 2
    sw   t1, 0(t0)                  # PROG=2: the dret RETIRED (or NOP'd)
    .word CSRR_S4_7B4               # 0x7B4 -- over-wide-HIGH guard, chained
    addi t1, x0, 3
    sw   t1, 0(t0)                  # PROG=3: 0x7B4 admitted too
tile_h2_park:
    j    tile_h2_park

    # ---- hart 3: `ebreak` WITH dcsr.ebreakm = 0 -------------------------
    # d1_spec.md section 1: dcsr.ebreakm is a debug-mode-only field and RESETS
    # TO 0, so no M-mode software can ever set it.  `ebreak` must therefore
    # take an ordinary breakpoint exception (cause 3) -- terminal TRAP_STATE on
    # the shipped default -- and must NOT reach DEBUG_ENTRY_ADDR.  On the
    # trapCsr-OFF row `ebreak` is an illegal instruction instead: the same
    # observable, which is what keeps this leg row-independent.
tile_h3:
    li   t0, SH_GPROG
    li   t1, 1
    sw   t1, 0(t0)                  # PROG=1: about to ebreak -- TERMINAL
#ifdef DBGDENY_NC_MARK
    li   t2, DBG_ENTRY              # NEGATIVE CONTROL: jump to the debug entry
    jalr x0, t2, 0                  # vector as a spontaneous debug entry would
#else
    .word EBREAK_INSN               # MUST NOT enter debug mode
#endif
    addi t1, x0, 2
    sw   t1, 0(t0)                  # PROG=2: the ebreak did not trap at all
    .word CSRR_S5_7AF               # 0x7AF -- over-wide-LOW guard, chained
    addi t1, x0, 3
    sw   t1, 0(t0)                  # PROG=3: 0x7AF admitted too
tile_h3_park:
    j    tile_h3_park

    # NOTE: RVTEST_CODE_END is `unimp` in this env (it traps) -- never fall
    # through; every hart-0 path above ends in a spin and every tile path ends
    # in an unconditional jump.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
