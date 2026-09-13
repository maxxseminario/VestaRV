# See LICENSE for license details.

# VestaRV: compressed execute-from-shared proof
# The compressed twin of shexec.S, whose payload is `.option norvc` so every fetch is a full word. The hazard here is a 32-bit instruction whose two halves live in DIFFERENT shared words: that fetch re-arbitrates mid-instruction and exercises sh_acked_addr (the master-side ack is qualified by word address, so the second half must win the arbiter again), sh_rdata_cpu (the clk_cpu consumption stage that stops an in-flight completion rewriting the instruction a frozen core is executing), and the half-fetch decode class.
# Payload at 0x103C0, four words: +0x00 c.nop pushes the body off word alignment; rvc_loop at +0x02 `lw t2, 0(s0)` STRADDLES the +0x04 boundary; +0x06 c.add, +0x08 c.addi, +0x0A c.bnez back to rvc_loop (a backward branch to a target 2 mod 4), +0x0C c.jr, +0x0E c.nop padding. Every iteration re-enters at +0x02, so both the straddling fetch and the misaligned target run iters times per hart.
# `lw` is forced to 32 bits by addressing t2 (x7), outside the c.lw rd' set x8-x15. VERIFY WITH objdump AFTER ANY EDIT: the test is worthless if the assembler quietly compresses that load. The accumulator a4 is inside the compressed set, which is what lets `add` shrink to c.add.
# Per-hart iteration counts differ (4 + hartid): a4 must equal iters * 0x00010001, and CHK holds 0x00010001.
# Shared words, reused from shexec.S verbatim because the two images never coexist in one simulation: CODE 0x103C0..0x103CC (one word shorter than shexec's, and 0x103D0 is left ZERO so shamo's probe constraint 0x22222222 stays safe), CHK 0x103D4, TOKEN 0x103D8, DONE[h] 0x103D8 + 4*h = 0xE0CC0000 + h. N=18 DONE tops at 0x1041C, below the loader rows at 0x10500.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_CODE   0x103C0
#define SH_CHK    0x103D4
#define SH_TOKEN  0x103D8
#define CHK_VAL   0x00010001
#define DONE_MAG  0xE0CC0000

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher

    # M12 single-ROM boot: stage this TCM image once, launch all three tiles
    # into tile_entry (mp_boot.h). They park on TOKEN just as shexec's tiles
    # do; hart 0 falls through to the orchestrator.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined for tiles until now)
    .option pop
    li   sp, 0xBFF0             # convention (loader left 0xBFFC)

    li   s2, SH_CODE            # payload entry
    li   s3, SH_TOKEN           # turn word (DONE base: TOKEN + 4*h)
    li   s4, SH_CHK

    beqz s10, orchestrator

    # ---- harts 1-3: park on TOKEN (reads only), then take our turn -------
park_loop:
    lw   t1, 0(s3)
    bne  t1, s10, park_loop

    li   a1, 4
    add  a1, a1, s10            # iters = 4 + hartid
    slli t5, a1, 16
    add  t5, t5, a1             # expected a4 = iters * 0x00010001
    mv   s0, s4                 # payload reads CHK through s0
    li   a4, 0                  # accumulator (compressed reg set)
    jalr ra, s2, 0              # EXECUTE RVC FROM SHARED (returns via ra)
    bne  a4, t5, shexecc_fail

    slli t0, s10, 2
    add  s5, s3, t0             # my DONE word
    li   t3, DONE_MAG
    add  t3, t3, s10
    sw   t3, 0(s5)              # report in
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
payload_verify:                 # forever: DONE must survive other traffic
    lw   t4, 0(s5)
    bne  t4, t3, shexecc_fail
    j    payload_verify

    # ---- hart 0: copy payload out, prove it runs, then release tiles ------
orchestrator:
    # copy the 4 payload words into shared RAM, read-back verified
    la   t0, payload_src
    mv   t2, s2
    li   t3, 4
copy_loop:
    lw   t4, 0(t0)
    sw   t4, 0(t2)
    lw   t6, 0(t2)              # read-back (shared write really landed)
    bne  t6, t4, shexecc_fail
    addi t0, t0, 4
    addi t2, t2, 4
    addi t3, t3, -1
    bnez t3, copy_loop
    li   t4, CHK_VAL
    sw   t4, 0(s4)              # CHK constant

    # tiles must still be parked: DONE[1..3] all zero (reads-only proof)
    li   t0, 1
parked_chk:
    slli t1, t0, 2
    add  t1, s3, t1
    lw   t2, 0(t1)
    bnez t2, shexecc_fail
    addi t0, t0, 1
    li   t1, NHARTS
    bne  t0, t1, parked_chk

    # the gate hart executes RVC from shared FIRST (fail fast, easy triage)
    li   a1, 4                  # iters = 4
    slli t5, a1, 16
    add  t5, t5, a1             # expected 0x00040004
    mv   s0, s4
    li   a4, 0
    jalr ra, s2, 0              # EXECUTE RVC FROM SHARED
    bne  a4, t5, shexecc_fail

    # release tiles one at a time; bounded wake budget each (shboot pattern)
    li   s6, 1
release_loop:
    sw   s6, 0(s3)              # TOKEN = h: hart h's turn
    slli t0, s6, 2
    add  s7, s3, t0             # DONE[h]
    li   t5, DONE_MAG
    add  t5, t5, s6
    li   t6, 100000             # bounded: broken tile -> FAIL, not watchdog
wake_wait:
    lw   t2, 0(s7)
    beq  t2, t5, released
    addi t6, t6, -1
    bnez t6, wake_wait
    j    shexecc_fail
released:
    addi s6, s6, 1
    li   t0, NHARTS
    bne  s6, t0, release_loop

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shexecc_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- payload source image (copied to SH_CODE; never executed here) ----
    # Position-independent by construction: the branch is PC-relative, data
    # goes through s0, the return through ra. RVC is forced ON for this block;
    # the ONLY 32-bit instruction is the lw, which cannot compress because t2
    # (x7) is outside the c.lw register set — that is what puts a word-boundary
    # straddle at +0x02 on every loop iteration.
    .align 2
    .option push
    .option rvc
payload_src:
    nop                         # +0x00 c.nop   — offsets the body by 2
rvc_loop:
    lw   t2, 0(s0)              # +0x02 32-bit  ** STRADDLE **
    add  a4, a4, t2             # +0x06 c.add
    addi a1, a1, -1             # +0x08 c.addi
    bnez a1, rvc_loop           # +0x0A c.bnez  ** target is 2 mod 4 **
    jr   ra                     # +0x0C c.jr
    nop                         # +0x0E c.nop   — pad to exactly 4 words
    .option pop

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
