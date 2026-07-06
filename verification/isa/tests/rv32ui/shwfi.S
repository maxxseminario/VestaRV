# See LICENSE for license details.

#*****************************************************************************
# shwfi.S  (M5b; M12 single-ROM boot rework)
#-----------------------------------------------------------------------------
# HART-GENERIC real-CLINT IPI + sleep/wake test — the M5b signature test.
#
# M12: tiles are NO LONGER preloaded. Hart 0 stages this TCM image once and
# launches each tile into tile_entry through the bootrom loader — the FIRST
# msip[h] is consumed by the ROM loader (the launch). The tile then advertises
# READY and extinguishes; hart 0's SECOND msip[h] is the real test IPI, taken
# by the tile's OWN msip ISR (slot 83, copied into its TCM). So the launch and
# the wake are two successive msips per tile.
#
# Supersedes nothing: shboot.S (soft-CLINT poll-parking) stays. THIS test
# parks harts 1-3 with the vesta SLEEP instruction (extinguish: clk_cpu gated
# OFF) and wakes them with a REAL hardware IPI — hart 0 writes CLINT msip[h];
# the level IRQ enters the tile's irq_vector at slot IRQB_CLINT_MSIP (83, the
# only enabled slot besides mtip), the mclk-domain irq_handler un-gates the
# sleeping core, the ISR clears the msip level, ignites (clears sleep_cpu so
# iret resumes MAINLINE instead of falling back to sleep), and the woken hart
# reports DONE.
#
# CLINT (shared window, all harts reach it through the arbiter):
#     MSIP[h]     = 0x5000 + 4*h    (bit 0; level IRQ to hart h)
# Shared words (>= 0x10150, clear of all earlier tests' words):
#     READY[h]    = 0x10150 + 4*h    0x4EAD0000+h just before hart h sleeps
#     DONE[h]     = 0x10160 + 4*h    0xD00E0000+h after hart h wakes
#
# RACE NOTE (why sleep-after-READY is safe): the arbiter SERIALIZES the
# window. Hart 0 can only observe READY[h] after hart h's store completed,
# and the IPI needs at least one MORE full shared transaction after that
# observation; hart h executes extinguish (private, unstallable) on the very
# next instruction after its store releases. So msip[h] can never arrive
# before hart h is asleep.
#
# Hart 0 (SPI boot) per hart 1..3 IN TURN: LAUNCH the tile (loader row + first
# msip), bounded-wait READY[h], verify DONE[h]==0 (really parked, asleep),
# write msip[h]=1 (the test IPI), bounded-wait DONE[h], verify msip[h]==0 (the
# tile's ISR ran and cleared it). All three -> RVTEST_PASS.
#
# IVT: the env's DEFINE_IVT (inside RVTEST_CODE_BEGIN) emits slots 0-82; we
# extend the SAME .ivt section with slots 83 (msip -> ISR) and 84 (mtip ->
# FAIL: mtimecmp resets all-ones, it must never fire here).
#
# ISR contract in this core: hardware pushes ONLY the return PC (at sp-4,
# IRQ_SV) — registers are the ISR's job, and sp MUST be valid before any IRQ
# can fire (set to top of the private TCM at entry, before the first IPI).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3 (ISR reads it too — do not clobber)
    .option pop
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher/waker

    # hart 0: set up and go to the waker (the staged launch is done there)
    li   sp, 0xBFF0             # private TCM top; IRQ_SV pushes PC at sp-4
    li   s2, 0x10150            # READY base
    li   s3, 0x10160            # DONE base
    li   s4, 0x5000            # CLINT MSIP base
    li   s5, 0x4EAD0000         # READY magic base
    li   s6, 0xD00E0000         # DONE magic base
    j    waker

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (ISR reads it too — do not clobber)
    .option pop
    li   sp, 0xBFF0             # private TCM top; IRQ_SV pushes PC at sp-4
    li   s2, 0x10150            # READY base
    li   s3, 0x10160            # DONE base
    li   s4, 0x5000            # CLINT MSIP base
    li   s5, 0x4EAD0000         # READY magic base
    li   s6, 0xD00E0000         # DONE magic base

    # ---- harts 1-3: advertise READY, then sleep on the NEXT instruction ----
    slli t0, s10, 2
    add  s2, s2, t0             # my READY word
    add  s3, s3, t0             # my DONE word
    add  s5, s5, s10            # my READY magic
    add  s6, s6, s10            # my DONE magic
    sw   s5, 0(s2)              # READY...
    extinguish                  # ...and clk_cpu OFF (see race note above)

    # ---- here only after the msip ISR ignited + iret'd -------------------
    sw   s6, 0(s3)              # report DONE (real wake proof)
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
wfi_verify:                     # forever: DONE must survive other traffic
    lw   t4, 0(s3)
    bne  t4, s6, shwfi_fail
    j    wfi_verify

    # ---- hart 0: staggered — LAUNCH, park proof, REAL IPI, wake proof -----
waker:
    MP_STAGE_IMAGE(4096)        # stage the full TCM image once (0x18000)
    li   s7, 1
waker_loop:
    # M12 LAUNCH: write hart s7's loader row, then its FIRST msip. The bootrom
    # loader consumes it (copies the image, enters tile_entry). The tile's
    # own READY/extinguish follows; the SECOND msip (is_ready below) is the
    # test IPI, taken by the tile's copied slot-83 ISR.
    slli t0, s7, 4
    li   t1, MP_BOOT_MB_BASE
    add  t0, t0, t1             # loader row for hart s7
    li   t1, MP_STAGE_BASE
    sw   t1, 0(t0)              # SRC = the staged image
    li   t1, 4096
    sw   t1, 4(t0)              # LEN = full TCM
    la   t1, tile_entry
    sw   t1, 8(t0)              # ENTRY
    slli t0, s7, 2
    li   t1, MP_CLINT_MSIP
    add  t0, t0, t1
    li   t1, 1
    sw   t1, 0(t0)              # msip[s7] = 1 — ignite the loader (the LAUNCH)

    slli t0, s7, 2
    add  t1, s2, t0             # READY[h]
    add  s8, s5, s7             # expected READY value
    li   t6, 100000             # M12: this first wait covers the tile's ROM
                                # copy after launch (fits the 100ms watchdog)
ready_wait:
    lw   t2, 0(t1)
    beq  t2, s8, is_ready
    addi t6, t6, -1
    bnez t6, ready_wait
    j    shwfi_fail
is_ready:
    add  t1, s3, t0             # DONE[h]: must still be 0 — hart is asleep
    lw   t2, 0(t1)
    bnez t2, shwfi_fail
    add  t3, s4, t0             # MSIP[h]
    li   t2, 1
    sw   t2, 0(t3)              # >>> the real hardware IPI <<<
    add  s9, s6, s7             # expected DONE value
    li   t6, 20000
wake_wait:
    lw   t2, 0(t1)
    beq  t2, s9, woke
    addi t6, t6, -1
    bnez t6, wake_wait
    j    shwfi_fail
woke:
    lw   t2, 0(t3)              # its ISR must have cleared the msip level
    bnez t2, shwfi_fail
    addi s7, s7, 1
    li   t0, 4
    bne  s7, t0, waker_loop

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shwfi_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- msip ISR (runs on the woken hart; only t0/t1 used, stack-saved) --
msip_isr:
    addi sp, sp, -8
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    slli t0, s10, 2
    li   t1, 0x5000
    add  t1, t1, t0
    sw   x0, 0(t1)              # clear MY msip level (or the IRQ re-fires)
    ignite                      # clear sleep_cpu: iret must resume MAINLINE
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    addi sp, sp, 8
    iret

    # ---- extend the env IVT: DEFINE_IVT emitted slots 0-82 ----------------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, msip_isr         # slot 83 = IRQB_CLINT_MSIP
    jal  zero, shwfi_fail       # slot 84 = IRQB_CLINT_MTIP — must never fire
    .previous

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
