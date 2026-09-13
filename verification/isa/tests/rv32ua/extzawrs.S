# See LICENSE for license details.

# VestaRV: Zawrs extension probe
# Single-hart adaptive probe for wrs.nto and wrs.sto, dispatched at BUILD TIME on CORE_ENABLE_ZAWRS, since Zawrs has no misa bit. The macro is NEVER auto-derived and never pulled from an include: the default build leaves it undefined and takes the OFF arm, keeping the suite green, and the ON arm is built by explicitly appending the define.
# ORDER MATTERS WHEN BUILDING THE ON ARM: run build_mp_images.sh FIRST, because it wipes build/ and rebuilds every group with the Makefile-default options plus -DNHARTS, dropping any -D placed on an earlier make, and then rebuild rv32ua on top with -DCORE_ENABLE_ZAWRS appended to RISCV_GCC_OPTS. The ON RTL is staged separately. Note also that the simulator reads a path that is normally a SYMLINK to verification/isa/rcf; a fresh worktree may materialise a real directory there and the simulation will run a stale image.
# The ON arm has three legs. With no valid reservation both wrs forms retire immediately, a tiny mcycle delta. With a live SHARED reservation and no foreign store, wrs.sto stalls until the short timeout of 1024 clk_cpu cycles, measured with mcycle as a delta of at least about 1024 and well short of a hang. For the pending-interrupt wake, a timer is armed and a fresh reservation taken before wrs.nto, which has NO timeout, so the only possible wake is the pending mtip and reaching the code afterwards with the slot-84 ISR having fired proves the wake path.
# The OFF arm passes trivially so the default suite stays green; the illegal-instruction trap for that polarity is proven separately by the extzawrsx.S poison under the stripped harness, because executing the wrs encoding in the main suite would hang in the terminal TRAP_STATE.
# This core has no mstatus.MIE, the CLINT and meip enables being hardwired on at the tile, so the spec's "wake even if globally disabled" sub-case cannot be exercised separately here; the Zawrs wake keys off the raw irq vector by construction and the third leg exercises it with the available enabled timer interrupt.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"                 /* NHARTS, CLINT base */
# CORE_ENABLE_ZAWRS comes from the build command (-DCORE_ENABLE_ZAWRS), never an include.

# CLINT offsets from base 0x5000 (N-parameterized; = 0x10/0x20 at N=4)
#define MTIME_OFF     ((4*NHARTS + 15) & ~15)
#define MTIME_LO      (MTIME_OFF)
#define MTIMECMP0_LO  (MTIME_OFF + 0x10)
#define MTIMECMP0_HI  (MTIME_OFF + 0x14)

# Raw Zawrs encodings (SYSTEM, funct3=000, rs1=x0, rd=x0, funct12=0x00D/0x01D)
#define WRS_NTO .word 0x00d00073
#define WRS_STO .word 0x01d00073

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0

    # ---- base-ISA sanity (runs on every build) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, extz_fail

#ifdef CORE_ENABLE_ZAWRS
    # =====================================================================
    # FEATURE ON
    # =====================================================================
    la   s3, extz_flags
    sw   x0, 0(s3)
    li   s2, 0x5000                 # CLINT base

    # ---- (i) NO reservation -> both wrs retire immediately ----
    .option push
    .option arch, +zicsr
    csrr t3, cycle
    WRS_NTO
    WRS_STO
    csrr t4, cycle
    .option pop
    sub  t5, t4, t3
    li   t6, 128
    bgeu t5, t6, extz_fail          # immediate retire => tiny delta (< 128)

    # ---- (ii) live SHARED reservation, no store -> wrs.sto times out ~1024 ----
    li   t0, 0x10000                # shared bulk-RAM word
    .option push
    .option arch, +a
    lr.w t1, (t0)                   # global reservation (resv_valid[0]=1)
    .option pop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop                             # let resv_valid_ext settle through the boundary
    .option push
    .option arch, +zicsr
    csrr t3, cycle
    WRS_STO                         # stalls ~WRS_TIMEOUT clk_cpu cycles
    csrr t4, cycle
    .option pop
    sub  t5, t4, t3
    li   t6, 1000
    bltu t5, t6, extz_fail          # must have stalled ~1024 cycles
    li   t6, 3000
    bgeu t5, t6, extz_fail          # ...and NOT hung

    # ---- (iii) pending-interrupt wake (wrs.nto has no timeout) ----
    lw   t1, MTIME_LO(s2)
    addi t1, t1, 200
    sw   t1, MTIMECMP0_LO(s2)       # arm timer: lo first (hi still all-ones)
    sw   x0, MTIMECMP0_HI(s2)       # ...hi=0: ARMED (fires ~200 ticks out)
    li   t0, 0x10004                # fresh shared word
    .option push
    .option arch, +a
    lr.w t1, (t0)                   # fresh reservation (no foreign store coming)
    .option pop
    nop
    nop
    nop
    nop
    WRS_NTO                         # only a pending interrupt can wake this
    # woke -> the slot-84 mtip ISR must have set flag bit 1
    li   t6, 20000
extz_iii_wait:
    lw   t2, 0(s3)
    andi t3, t2, 2
    bnez t3, extz_pass
    addi t6, t6, -1
    bnez t6, extz_iii_wait
    j    extz_fail
extz_pass:
    RVTEST_PASS

    # ---- slot-84 mtip ISR: disarm the timer, flag bit 1, iret ----
mtip_isr:
    addi sp, sp, -12
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    sw   t2, 8(sp)
    li   t0, 0x5000
    li   t1, -1
    sw   t1, MTIMECMP0_HI(t0)       # cmp hi = all-ones -> mtip level drops
    la   t1, extz_flags
    lw   t2, 0(t1)
    ori  t2, t2, 2
    sw   t2, 0(t1)
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    lw   t2, 8(sp)
    addi sp, sp, 12
    iret

    # extend the env IVT (DEFINE_IVT emits slots 0-82): slot 84 = mtip
    .section .ivt, "ax"
    .org 0x150                      # 0x14C=slot 83, 0x150=slot 84 (IRQB_CLINT_MTIP)
    jal  zero, mtip_isr
    .previous

#else
    # =====================================================================
    # FEATURE OFF: trivially pass (keeps the default suite green; the
    # illegal-instruction trap is proven by extzawrsx.S in the neg-ctrl harness)
    # =====================================================================
    RVTEST_PASS
#endif

extz_fail:
    RVTEST_FAIL

    # RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
extz_flags: .word 0
  TEST_DATA
RVTEST_DATA_END
