# See LICENSE for license details.

#*****************************************************************************
# shnpu.S  (M7d; M12 single-ROM boot rework)
#-----------------------------------------------------------------------------
# HART-GENERIC shared-NPU test — the M7d signature test, reworked for the
# M11 memory map (ALL peripherals are shared now; the private page is gone).
#
# M12: tiles are NO LONGER preloaded. Hart 0 stages this TCM image once and
# launches harts 1-3 into tile_entry through the bootrom loader (mp_boot.h);
# each tile then parks on the token. The token ring (0x10220) is unchanged.
#
# M7d moved the NPU's REGISTER bus onto the mp_arbiter; M11 put it back at
# its original address:
#     NPU = 0x4A00 (slot 10)   (NPUCR/IVSAR/WVSAR/OVSAR at +0/4/8/C)
# M11 also promoted the DATA PATH: the vectors live in the SHARED NPU
# staging RAM at 0xC000-0xFFFF (hart 0's retired private RAM1 — same
# addresses, now an arbiter slave). ANY hart can stage vectors, configure,
# start the accelerator and poll NPUCR.THINK for completion. hart 0 no
# longer sleeps during a THINK (the sleep protected its un-stallable
# private-RAM1 port; shared accesses have arbiter back-pressure) — the
# contract is: NEVER touch 0xC000-0xFFFF while a THINK may be active, poll
# NPUCR bit 16 first (the in-NPU port mux owns the RAM during the run).
#
# RTL FIXES THIS TEST GUARDS (see plan doc M7d):
#  * NPU.vhd's staging-RAM port mux switches on NPUTHINK REGISTERED on mclk
#    (NpuMuxSel) — a clean-cycle handover of the RAM port.
#  * The NPU's MMR read is COMBINATIONAL (collapses when CEN deasserts) and
#    its CEN was HARDWIRED asserted on the old gated bus — the bridge gives
#    it the real one-cycle strobe and registers the readback (I2C rule).
#
# Network under test: 1 input, 1 neuron, no bias, no activation (pure
# pass-through MAC) => OUT = X * W exactly.
#   Fixed-point formats (MCU generics): X = sfixed(0,-24), W/OUT = sfixed(7,-24)
#   X @0xC100 = 0x00800000 (0.5)     W @0xC104 = 0x02000000 (2.0)
#   OUT = 0x01000000 (1.0) -> written by the NPU to the staging RAM
# Run 1 (hart 1): OVSAR=0x42 -> 0xC108. Run 2 (hart 3, after hart 2
# retargets OVSAR=0x43): -> 0xC10C. Hart 0 verifies BOTH words afterward —
# the end-to-end proof that a tile-hart-started NPU really computed into the
# shared staging RAM, twice.
#
# Staging-RAM vector addresses (word index = (addr-0xC000)/4): clear of the
# bootrom's residual stack words at the very top of the staging RAM
# (0xFF00+, the unrebuilt M11 bootrom still stacks at 0xFFFC via the
# arbiter) and all image data.
#
# Shared words (>= 0x10220, clear of all earlier tests' words):
#     TOKEN    = 0x10220          whose turn (shram zero-init => hart 0)
#     DONE[h]  = 0x10230 + 4*h    0x4E900000+h after hart h's part
# Argus A3: TOKEN sits below the DONE base, so the NHARTS-sized DONE array
# (N=18: 0x10234..0x10274, < 0x10500) can't overrun it. NOTE (see report):
# harts 1/2/3 have DISTINCT roles and harts >= 4 fall into hart 1's role
# (reconfigure + npu_run to OUT1); N=18 semantics UNVERIFIED (and NPU is dropped
# in Argus anyway) — manual review. N=4 behaviour is unchanged.
# (TD scratch at 0x10260/64 -- 0x10240-0x1025C is the shlock band, ledger rule; next free 0x10268)
#
# IRQ LEG (digperiphs, 2026-07-22): NPU think-done = irq_router source 120
# (IRQB_NPU0_TD; npu_irq_spec.md). NPUSR @0x4A10 bit0 THINKDONE (sticky W1C,
# set once per THINK completion); NPUCR bit19 TDIE gates a registered level
# -> source 120 -> meip -> env MEIP_DISPATCHER -> IVT slot 120 -> plain-ret
# handler -> CLAIM/COMPLETE, exactly like wdma.S (119) / wrtc.S (114). Runs
# on hart 0 ONLY, after the existing polling proof above, before RVTEST_PASS
# — hart 1-3 behavior is unchanged. A THIRD output word (OV3, 0xC110) keeps
# this run's completion unambiguous from the OUT1/OUT2 proof already checked.
#     TD_FLAG = 0x10260   (ISR exactly-once counter)
#     TD_ISVC = 0x10264   (handler's masked INSVCX readback)
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_NPU     0x4A00
#define TOKEN      0x10220
#define DONE_BASE  0x10230
#define X_ADDR     0xC100
#define X_VAL      0x00800000   /* 0.5  in sfixed(0,-24)  */
#define W_VAL      0x02000000   /* 2.0  in sfixed(7,-24)  */
#define OUT_VAL    0x01000000   /* 1.0  in sfixed(7,-24)  */
#define IV_WORD    0x40         /* staging-RAM word of X   (0xC100) */
#define WV_WORD    0x41         /* staging-RAM word of W   (0xC104) */
#define OV1_WORD   0x42         /* staging-RAM word of OUT1 (0xC108) */
#define OV2_WORD   0x43         /* staging-RAM word of OUT2 (0xC10C) */
#define OV3_WORD   0x44         /* staging-RAM word of OUT3 (0xC110), IRQ leg */
#define CR_THINK   0x10000      /* THINK=1, NI=0 (1 input), NN=0 (1 neuron),
                                   BEN=0, AEN=0 (pass-through) */

/* ---- IRQ leg (source 120, IRQB_NPU0_TD; npu_irq_spec.md) ---------------- */
#define NPU_OVSAR_ADDR   0x4A0C      /* NPU +0xC: OVSAR (existing register) */
#define NPUSR_ADDR  0x4A10      /* NPU +0x10 (word offset 4): NEW, W1C bit0 */
#define TDIE        0x00080000 /* NPUCR bit19: think-done IRQ enable */
#define CR_THINK_TDIE (CR_THINK | TDIE)  /* THINK | TDIE | 1-input | 1-neuron */
#define IRTR_ENX    0x700C      /* HhENX, hart-0 row (sources 96-127) */
#define IRTR_PENDX  0x781C      /* RO pending, sources 96-127 */
#define IRTR_INSVCX 0x782C      /* RO in_service, sources 96-127 */
#define TD_SRC_BIT  0x01000000  /* bit24: source 120 (120-96) in ENX/PENDX/INSVCX */
#define TD_FLAG     0x10260     /* ISR exactly-once counter */
#define TD_ISVC     0x10264     /* handler's masked INSVCX readback */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher

    # M12 single-ROM boot: stage this TCM image once, then launch all three
    # tiles into tile_entry through the bootrom loader (mp_boot.h). They park
    # on the token just as the old preloaded tiles did.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined for tiles until now)
    .option pop

    li   sp, 0xBFF0             # private TCM top (IRQ_SV contract)

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
    # M11: 0x4A00 is the LIVE shared NPU register window. Reset proof:
    li   t0, 0x4A00
    lw   t1, 0(t0)              # NPUCR resets 0
    bnez t1, shnpu_fail
    lw   t1, 4(t0)              # IVSAR resets 0
    bnez t1, shnpu_fail

    li   t0, X_ADDR             # stage the vectors in the SHARED staging RAM
                                # (0xC000 page, via the arbiter — M11)
    li   t1, X_VAL
    sw   t1, 0(t0)              # X   @0xC100
    li   t1, W_VAL
    sw   t1, 4(t0)              # W   @0xC104
    sw   zero, 8(t0)            # OUT1 @0xC108 = 0 (must be overwritten)
    sw   zero, 12(t0)           # OUT2 @0xC10C = 0

    li   t0, 1
    sw   t0, 0(s3)              # TOKEN = 1: release the ring
                                # (M11: hart 0 no longer sleeps during NPU
                                # runs — it just polls the token like any
                                # other hart; runs are ~10 mclk anyway)
    li   t6, 100000             # M12: covers 3 serialized tile ROM-copies at launch
ring_wait:
    lw   t0, 0(s3)
    li   t1, NHARTS
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
    li   t0, NHARTS
    bne  t3, t0, done_check

    li   t0, X_ADDR             # THE END-TO-END PROOF: both outputs landed
    lw   t1, 8(t0)              # in the shared staging RAM: exact product
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

    # ================= IRQ leg: NPU think-done (vector 120) ================
    # NPUSR (0x4A10) bit0 THINKDONE, sticky W1C, set on THINK completion.
    # NPUCR bit19 TDIE gates a registered level -> irq_router source 120 ->
    # meip -> MEIP_DISPATCHER -> IVT slot 120 -> plain-ret handler ->
    # CLAIM/COMPLETE. Mirrors the wdma/wrtc Stage-E rider proof: PENDX read
    # with the route OFF (deterministic, no delivery race), then enable ENX,
    # INSVCX-in-handler rider, exactly-once, negctrl-lite, un-route. Hart 0
    # only; harts 1-3 stay parked in their own tile_verify loops throughout.
    li   t0, TD_FLAG
    sw   x0, 0(t0)               # exactly-once counter = 0
    li   t0, TD_ISVC
    sw   x0, 0(t0)

    # NPUSR.THINKDONE is STICKY (W1C) and the mainline proof above already
    # ran two THINKs (hart 1's and hart 3's npu_run, no TDIE) -- THINKDONE
    # may already be latched 1 from those, so this leg starts by clearing it
    # unconditionally (not asserting a "resets 0" precondition that doesn't
    # hold mid-test) and then proves the clear actually landed.
    li   t0, NPUSR_ADDR
    li   t1, 1
    sw   t1, 0(t0)               # W1C: clear any stale THINKDONE
    lw   t1, 0(t0)
    bnez t1, shnpu_fail          # must read 0 right after the clear

    li   t0, OV3_WORD
    li   t1, NPU_OVSAR_ADDR
    sw   t0, 0(t1)               # OVSAR -> OUT3 (0xC110): a fresh word so
    lw   t2, 0(t1)               # this run can't alias the OUT1/OUT2 proof
    bne  t2, t0, shnpu_fail

    # start the THINK with TDIE set but the router route OFF -> NPUSR sets,
    # the internal level asserts, but no meip is delivered yet
    li   t0, SH_NPU
    li   t1, CR_THINK_TDIE
    sw   t1, 0(t0)               # NPUCR = THINK | TDIE | 1-input | 1-neuron

    li   t6, 20000
td_wait_busy:
    li   t0, SH_NPU
    lw   t1, 0(t0)
    srli t1, t1, 16
    andi t1, t1, 1               # NPUCR bit16 = THINK (busy)
    beqz t1, td_wait_flag
    addi t6, t6, -1
    bnez t6, td_wait_busy
    j    shnpu_fail

td_wait_flag:
    li   t0, NPUSR_ADDR
    lw   t1, 0(t0)
    andi t1, t1, 1
    bnez t1, td_pendx
    addi t6, t6, -1
    bnez t6, td_wait_flag
    j    shnpu_fail

td_pendx:
    # RIDER: PENDX bit24 must be set (raw source pending; route still off ->
    # no delivery races this poll)
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    and  t1, t1, t2
    beqz t1, shnpu_fail

    # enable the route -> meip -> dispatcher -> claim 120 -> handler
    li   t0, IRTR_ENX
    li   t1, TD_SRC_BIT
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, shnpu_fail

    li   t6, 20000
td_wait_deliv:
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bge  t1, t2, td_deliv_ok
    addi t6, t6, -1
    bnez t6, td_wait_deliv
    j    shnpu_fail

td_deliv_ok:
    # exactly one delivery (in_service gateway)
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, shnpu_fail
    # RIDER: the handler recorded INSVCX bit24 while claimed
    li   t0, TD_ISVC
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    bne  t1, t2, shnpu_fail
    # handler W1C'd NPUSR bit0 -> level dropped -> NPUSR reads 0
    li   t0, NPUSR_ADDR
    lw   t1, 0(t0)
    bnez t1, shnpu_fail
    # PENDX bit24 clear now too (raw source level dropped)
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    and  t1, t1, t2
    bnez t1, shnpu_fail
    # end-to-end proof: the THINK that raised the IRQ really computed
    li   t0, X_ADDR
    lw   t1, 16(t0)              # OUT3 @ 0xC110
    li   t2, OUT_VAL
    bne  t1, t2, shnpu_fail

    # negative-control-lite: let any (erroneous) second delivery happen (no
    # new THINK started, route still on), then confirm counter stayed at 1
    li   t6, 2000
td_settle:
    addi t6, t6, -1
    bnez t6, td_settle
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, shnpu_fail

    li   t0, IRTR_ENX
    sw   x0, 0(t0)               # un-route (clean)
    li   t0, SH_NPU
    sw   x0, 0(t0)               # NPUCR back to reset default (TDIE off too)

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

    # ---- NPU think-done handler (vector 120; M19 plain-ret meip ABI).
    # ---- Reached via CLAIM=120 -> dispatcher jalr through IVT slot 120.
    # ---- Records the INSVCX in-handler proof, W1C-clears NPUSR bit0 (drops
    # ---- the level) BEFORE returning (dispatcher COMPLETEs after), bumps
    # ---- the exactly-once counter. t0-t2 dispatcher-saved scratch; ra
    # ---- survives (ret). s-regs/other GPRs untouched. ----------------------
    .section .text.init
npu0_td_isr:
    li   t0, IRTR_INSVCX
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    and  t1, t1, t2               # isolate bit24 (source 120 in service)
    li   t0, TD_ISVC
    sw   t1, 0(t0)                # mainline requires == TD_SRC_BIT
    li   t0, NPUSR_ADDR
    li   t1, 1
    sw   t1, 0(t0)                # W1C bit0 -> THINKDONE clears, level drops
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)
    ret

    # ---- env meip dispatcher (.isr_meip @0xB100) + IVT slot 85 ----------
    MEIP_DISPATCHER()
    IVT_ARM_MEIP()

    # ---- extend the IVT to slot 120 = NPU0_TD (DEFINE_IVT stops at 82,
    # ---- IVT_ARM_MEIP fills 83-85). Slot 120 @ .ivt+4*120 = 0x1E0. --------
    #
    # flash_prepend.sh boot-image gotcha (found this session): the SPI-flash
    # image builder splits the binary into loadSegmentToRAM regions on a run
    # of >= GAP_MIN(8) zero WORDS; a run of 7 or fewer is left INSIDE the
    # surrounding region instead. Slot 120 (0x81E0-0x81E3) is only 7 zero
    # words short of .text.init's fixed link.ld address (0x8200) -- one word
    # LESS than wdma.S's slot 119, whose 8-word gap DOES split (verified via
    # flash_prepend.sh's own region scan: wdma gets a dedicated 0x8200
    # segment, shnpu without this padding gets 0x81e0-0x85f4 MERGED into one
    # oversized segment). The merged form was proven to corrupt the boot
    # copy in simulation (hart 0 trapped on an illegal all-zero word fetched
    # at 0x8200 -- the flashed data at that address was verified correct via
    # the rcf itself, so the corruption is in the merged-segment copy, not
    # the image). FIX: explicitly park the remaining reserved slots 121-127
    # (never routed -- NUM_IRQ_SRCS=121, i.e. 120 is the last valid source)
    # at 0xBB00 like every other unused slot, which fills the gap solid all
    # the way to 0x8200 and removes the short zero-run entirely (matches the
    # DEFINE_IVT convention for slots 0-82; slots 86-119 stay an ordinary
    # zero gap exactly like wdma/wrtc, since that gap is provably >= 8 words
    # and always gets its own split segment).
    .section .ivt, "ax"
    .org 4*120
    jal  zero, npu0_td_isr        # slot 120 = IRQB_NPU0_TD
    jal  zero, 0x0BB00            # slot 121 - reserved -> parked
    jal  zero, 0x0BB00            # slot 122 - reserved -> parked
    jal  zero, 0x0BB00            # slot 123 - reserved -> parked
    jal  zero, 0x0BB00            # slot 124 - reserved -> parked
    jal  zero, 0x0BB00            # slot 125 - reserved -> parked
    jal  zero, 0x0BB00            # slot 126 - reserved -> parked
    jal  zero, 0x0BB00            # slot 127 - reserved -> parked
    .previous

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
