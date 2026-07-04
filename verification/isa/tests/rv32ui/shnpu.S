# See LICENSE for license details.

#*****************************************************************************
# shnpu.S  (M7d)
#-----------------------------------------------------------------------------
# HART-GENERIC shared-NPU test — the M7d signature test (and the LAST
# peripheral move: SARADC/AFE stay hart-0-private by decision, with the
# never-shared SYSTEM0/SPI0/GPIO0).
#
# M7d moved the NPU's REGISTER bus onto the mp_arbiter at its mirror slot:
#     NPU 0x4A00 -> 0x13A00 (slot 10)   (NPUCR/IVSAR/WVSAR/OVSAR at +0/4/8/C)
# The DATA PATH is unchanged: the NPU crunches vectors in HART 0's PRIVATE
# RAM1 through the in-NPU SRAM-port mux, and npu0_active sleeps hart 0 for
# the duration. So "shared" means shared CONTROL: any hart may configure and
# start the accelerator and poll NPUCR.THINK for completion; the DATA is
# staged in hart 0's RAM1 (by hart 0, or via shared-RAM handoff — software's
# job, this test has hart 0 stage it).
#
# TWO RTL FIXES THIS TEST GUARDS (see plan doc M7d):
#  * NPU.vhd's RAM1-port mux now switches on NPUTHINK REGISTERED on mclk
#    (NpuMuxSel), and NpuActive = raw-OR-delayed — hart 0 is asleep one full
#    cycle BEFORE the port switches and wakes one full cycle AFTER it
#    returns. With the raw bit, a CROSS-HART THINK write could flip the port
#    while hart 0 had a RAM1 access in flight (corrupted load/dropped store);
#    with hart-0-only control that race was unreachable, which is why it
#    never bit before.
#  * The NPU's MMR read is COMBINATIONAL (collapses when CEN deasserts) and
#    its CEN was HARDWIRED asserted on the old gated bus — the bridge gives
#    it the real one-cycle strobe and registers the readback (I2C rule).
#
# Network under test: 1 input, 1 neuron, no bias, no activation (pure
# pass-through MAC) => OUT = X * W exactly.
#   Fixed-point formats (MCU generics): X = sfixed(0,-24), W/OUT = sfixed(7,-24)
#   X @0xC100 = 0x00800000 (0.5)     W @0xC104 = 0x02000000 (2.0)
#   OUT = 0x01000000 (1.0) -> written by the NPU to hart 0's RAM1
# Run 1 (hart 1): OVSAR=0x42 -> 0xC108. Run 2 (hart 3, after hart 2
# retargets OVSAR=0x43): -> 0xC10C. Hart 0 verifies BOTH words afterward —
# the end-to-end proof that a tile-hart-started NPU really computed into
# hart 0's private RAM1, twice, with hart 0 sleeping through each run.
# (Hart 0's token/poll loops freeze while it sleeps — iterations don't burn.)
#
# RAM1 vector addresses (word index = (addr-0xC000)/4): clear of the stack
# top (0xFFF0), the .isr_* linker sections (0xED00+), and all image data.
#
# Shared words (>= 0x10220, clear of all earlier tests' words):
#     TOKEN    = 0x10220          whose turn (shram zero-init => hart 0)
#     DONE[h]  = 0x10230 + 4*h    0x4E900000+h after hart h's part
# (next free shared word: 0x10240)
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define SH_NPU     0x13A00
#define TOKEN      0x10220
#define DONE_BASE  0x10230
#define X_ADDR     0xC100
#define X_VAL      0x00800000   /* 0.5  in sfixed(0,-24)  */
#define W_VAL      0x02000000   /* 2.0  in sfixed(7,-24)  */
#define OUT_VAL    0x01000000   /* 1.0  in sfixed(7,-24)  */
#define IV_WORD    0x40         /* RAM1 word of X   (0xC100) */
#define WV_WORD    0x41         /* RAM1 word of W   (0xC104) */
#define OV1_WORD   0x42         /* RAM1 word of OUT1 (0xC108) */
#define OV2_WORD   0x43         /* RAM1 word of OUT2 (0xC10C) */
#define CR_THINK   0x10000      /* THINK=1, NI=0 (1 input), NN=0 (1 neuron),
                                   BEN=0, AEN=0 (pass-through) */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop

    li   sp, 0xFFF0             # private RAM1 top (IRQ_SV contract)

    li   s2, SH_NPU             # +0 CR, +4 IVSAR, +8 WVSAR, +12 OVSAR
    li   s3, TOKEN
    li   s4, DONE_BASE
    li   s6, 0x4E900000         # DONE magic base

    beqz s10, hart0

    # ---- harts 1-3: park on the token (reads only), then one part ----------
token_wait:
    lw   t0, 0(s3)
    bne  t0, s10, token_wait

    li   t0, 2
    beq  s10, t0, hart2
    li   t0, 3
    beq  s10, t0, hart3

    # ---- hart 1: configure the NPU through the arbiter + RUN 1 -------------
    lw   t0, 0(s2)              # NPUCR resets 0 (think included)
    bnez t0, shnpu_fail
    li   t0, IV_WORD
    sw   t0, 4(s2)              # IVSAR write...
    lw   t1, 4(s2)
    bne  t1, t0, shnpu_fail     # ...and readback (combinational-read bridge)
    li   t0, WV_WORD
    sw   t0, 8(s2)              # WVSAR
    lw   t1, 8(s2)
    bne  t1, t0, shnpu_fail
    li   t0, OV1_WORD
    sw   t0, 12(s2)             # OVSAR -> OUT1
    lw   t1, 12(s2)
    bne  t1, t0, shnpu_fail
    jal  ra, npu_run            # >>> a TILE hart starts the accelerator <<<
    j    report

    # ---- hart 2: cross-hart config visibility + retarget the output --------
hart2:
    lw   t0, 4(s2)              # hart 1's IVSAR/WVSAR must be visible
    li   t1, IV_WORD
    bne  t0, t1, shnpu_fail
    lw   t0, 8(s2)
    li   t1, WV_WORD
    bne  t0, t1, shnpu_fail
    li   t0, OV2_WORD
    sw   t0, 12(s2)             # OVSAR -> OUT2 for run 2
    lw   t1, 12(s2)
    bne  t1, t0, shnpu_fail
    j    report

    # ---- hart 3: RUN 2 (same X/W, new output word) --------------------------
hart3:
    jal  ra, npu_run

report:
    slli t0, s10, 2
    add  t0, t0, s4
    add  t1, s6, s10
    sw   t1, 0(t0)              # DONE[h]
    addi t0, s10, 1
    sw   t0, 0(s3)              # pass the token on
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
    slli t0, s10, 2
    add  t0, t0, s4
    add  t1, s6, s10
tile_verify:                    # forever: DONE must survive other traffic
    lw   t2, 0(t0)
    bne  t2, t1, shnpu_fail
    j    tile_verify

    # ---- hart 0 -------------------------------------------------------------
hart0:
    li   t0, 0x4A00             # OLD private NPU window: dead, reads 0
    lw   t1, 0(t0)
    bnez t1, shnpu_fail
    lw   t1, 4(t0)
    bnez t1, shnpu_fail

    li   t0, X_ADDR             # stage the vectors in MY private RAM1
    li   t1, X_VAL
    sw   t1, 0(t0)              # X   @0xC100
    li   t1, W_VAL
    sw   t1, 4(t0)              # W   @0xC104
    sw   zero, 8(t0)            # OUT1 @0xC108 = 0 (must be overwritten)
    sw   zero, 12(t0)           # OUT2 @0xC10C = 0

    li   t0, 1
    sw   t0, 0(s3)              # TOKEN = 1: release the ring
                                # (hart 0 now SLEEPS through each NPU run —
                                # the poll below freezes with it, so the
                                # budget only burns while awake)
    li   t6, 20000
ring_wait:
    lw   t0, 0(s3)
    li   t1, 4
    beq  t0, t1, ring_home
    addi t6, t6, -1
    bnez t6, ring_wait
    j    shnpu_fail
ring_home:
    li   t3, 1                  # verify DONE[1..3]
done_check:
    slli t0, t3, 2
    add  t0, t0, s4
    lw   t1, 0(t0)
    add  t2, s6, t3
    bne  t1, t2, shnpu_fail
    addi t3, t3, 1
    li   t0, 4
    bne  t3, t0, done_check

    li   t0, X_ADDR             # THE END-TO-END PROOF: both outputs landed
    lw   t1, 8(t0)              # in MY private RAM1 with the exact product
    li   t2, OUT_VAL
    bne  t1, t2, shnpu_fail     # OUT1 = 0.5 * 2.0 = 1.0
    lw   t1, 12(t0)
    bne  t1, t2, shnpu_fail     # OUT2 likewise (run 2, different hart)
    lw   t1, 0(t0)              # and the operands survived both runs
    li   t2, X_VAL
    bne  t1, t2, shnpu_fail
    lw   t1, 4(t0)
    li   t2, W_VAL
    bne  t1, t2, shnpu_fail

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shnpu_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- npu_run: start THINK and poll it back to 0 (clobbers t0/t6).
    # ---- The run itself is ~10 mclk cycles; the first poll usually already
    # ---- sees 0. NPUCR readback re-inserts THINK at bit 16 (the M-series
    # ---- NPUTHINK-readback fix — completion IS observable). ----------------
npu_run:
    li   t0, CR_THINK
    sw   t0, 0(s2)              # NPUCR = THINK | 1-input | 1-neuron
    li   t6, 20000
think_wait:
    lw   t0, 0(s2)
    srli t0, t0, 16
    andi t0, t0, 1              # NPUCR bit 16 = THINK (busy)
    beqz t0, think_done
    addi t6, t6, -1
    bnez t6, think_wait
    j    shnpu_fail
think_done:
    jalr zero, 0(ra)

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
