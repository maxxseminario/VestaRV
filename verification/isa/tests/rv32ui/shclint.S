# See LICENSE for license details.

#*****************************************************************************
# shclint.S  (M5b)
#-----------------------------------------------------------------------------
# Hart-0 directed test of the real CLINT registers + hart-0 IRQ delivery,
# run against the default shmem_mp contention tiles (harts 1-3 hammer the
# shared window throughout — every CLINT access below rides the arbiter
# under real 4-way contention).
#
# CLINT map (shared window, 0x5000) — N-parameterized layout (Argus A3):
#     MSIP[h]        = 0x5000 + 4*h                     (bit 0, level IRQ)
#     MTIME_OFF      = roundup16(4*NHARTS)  (= 0x10 @N=4, 0x50 @N=18)
#     MTIME  lo/hi   = 0x5000+MTIME_OFF / +4            (free-running, writable)
#     MTIMECMP[0]    = 0x5000 + MTIME_OFF + 0x10        (resets ALL-ONES -> quiet)
# At N=4 the formula reproduces the historic 0x5010/0x5020 layout exactly; at
# N=18 the wider msip array pushes mtime to 0x5050 and mtimecmp[0] to 0x5060.
#
# Checks:
#   1. mtime ticks: two reads (separate arbiter txns) strictly increase.
#   2. mtime is writable: set lo=0x40000000/hi=0, read back within a small
#      delta (it keeps counting underneath).
#   3. hart 0 unmask via SYSTEM: SYS_IRQ_ENU packing QUIRK — the write path
#      maps EN bits 84:80 to write_data(28:24) (NOT the read-back packing!),
#      so bit 83 (msip) = wd bit 27, bit 84 (mtip) = wd bit 28 -> 0x18000000.
#      SYS_IRQ_CR bit 0 = global irq_gen.
#   4. msip self-IPI: MSIP[0]=1 -> ISR (slot 83) clears it + sets flag bit 0.
#   5. mtip: MTIMECMP[0] = mtime+64 (lo FIRST while hi is still all-ones —
#      no spurious window — THEN hi=0 arms it) -> ISR (slot 84) disarms by
#      setting cmp hi back to all-ones + sets flag bit 1.
#
# ISR contract: hardware pushes only the return PC at sp-4 (sp set first);
# ISRs save/restore what they touch; the level MUST be cleared before iret
# or the irq_handler immediately re-triggers. Hart 0 is never asleep here,
# so no ignite. isr_flags lives in PRIVATE RAM (.data) — no shared traffic.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"                 /* NHARTS (default 4; Argus build -DNHARTS=18) */

# CLINT register offsets from base 0x5000, derived by the RTL's layout formula
# (mtime after the NHARTS-sized msip array, 16-byte aligned).
#define MTIME_OFF     ((4*NHARTS + 15) & ~15)
#define MTIME_LO      (MTIME_OFF)
#define MTIME_HI      (MTIME_OFF + 4)
#define MTIMECMP0_LO  (MTIME_OFF + 0x10)
#define MTIMECMP0_HI  (MTIME_OFF + 0x14)

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0             # private TCM top; IRQ_SV pushes PC at sp-4
    li   s2, 0x5000            # CLINT base
    la   s3, isr_flags
    sw   x0, 0(s3)

    # ---- 1. mtime ticks --------------------------------------------------
    lw   t0, MTIME_LO(s2)           # MTIME lo
    lw   t1, MTIME_LO(s2)
    bgeu t0, t1, shclint_fail   # second read must be STRICTLY greater

    # ---- 2. mtime writable -----------------------------------------------
    li   t2, 0x40000000
    sw   t2, MTIME_LO(s2)           # MTIME lo = 0x40000000
    sw   x0, MTIME_HI(s2)           # MTIME hi = 0
    lw   t0, MTIME_LO(s2)
    sub  t0, t0, t2             # ticks since the write
    li   t1, 0x1000
    bgeu t0, t1, shclint_fail   # must read back close to the written value

    # ---- 3. unmask CLINT IRQs on hart 0 (SYSTEM regs) ----------------------
    li   s4, 0x4900             # SYSTEM base
    li   t0, 0x18000000         # ENU write packing: bit27=msip(83), bit28=mtip(84)
    sw   t0, 0x1C(s4)           # SYS_IRQ_ENU
    li   t0, 1
    sw   t0, 0x2C(s4)           # SYS_IRQ_CR: irq_gen (global enable)

    # ---- 4. msip self-IPI --------------------------------------------------
    li   t1, 1
    sw   t1, 0x00(s2)           # MSIP[0] = 1
    li   t6, 20000              # bounded: must trip inside the 100ms watchdog
msip_wait:
    lw   t2, 0(s3)
    andi t3, t2, 1
    bnez t3, msip_ok
    addi t6, t6, -1
    bnez t6, msip_wait
    j    shclint_fail
msip_ok:
    lw   t2, 0x00(s2)           # ISR cleared the level
    bnez t2, shclint_fail

    # ---- 5. mtip: arm mtimecmp[0] a little in the future --------------------
    lw   t1, MTIME_LO(s2)           # MTIME lo (hi is 0 from step 2; +64 can't carry)
    addi t1, t1, 64
    sw   t1, MTIMECMP0_LO(s2)           # MTIMECMP[0] lo first (hi still all-ones: quiet)
    sw   x0, MTIMECMP0_HI(s2)           # ...then hi = 0: ARMED
    li   t6, 20000
mtip_wait:
    lw   t2, 0(s3)
    andi t3, t2, 2
    bnez t3, mtip_ok
    addi t6, t6, -1
    bnez t6, mtip_wait
    j    shclint_fail
mtip_ok:
    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shclint_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- ISRs (hart 0; clear the LEVEL before iret) -------------------------
msip_isr:
    addi sp, sp, -12
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    sw   t2, 8(sp)
    li   t0, 0x5000
    sw   x0, 0(t0)              # clear MSIP[0]
    la   t1, isr_flags
    lw   t2, 0(t1)
    ori  t2, t2, 1
    sw   t2, 0(t1)
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    lw   t2, 8(sp)
    addi sp, sp, 12
    iret

mtip_isr:
    addi sp, sp, -12
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    sw   t2, 8(sp)
    li   t0, 0x5000
    li   t1, -1
    sw   t1, MTIMECMP0_HI(t0)           # MTIMECMP[0] hi = all-ones: level drops
    la   t1, isr_flags
    lw   t2, 0(t1)
    ori  t2, t2, 2
    sw   t2, 0(t1)
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    lw   t2, 8(sp)
    addi sp, sp, 12
    iret

    # ---- extend the env IVT: DEFINE_IVT emitted slots 0-82 ------------------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, msip_isr         # slot 83 = IRQB_CLINT_MSIP
    jal  zero, mtip_isr         # slot 84 = IRQB_CLINT_MTIP
    .previous

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
isr_flags: .word 0
  TEST_DATA
RVTEST_DATA_END
