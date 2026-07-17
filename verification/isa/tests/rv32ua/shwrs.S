# See LICENSE for license details.

#*****************************************************************************
# shwrs.S   (X1 Zawrs directed multi-core wake test)
#-----------------------------------------------------------------------------
# The Zawrs lock-wakeup story. Hart A (hart 0, the gate) takes an LR on a shared
# word and executes wrs.nto; hart B (hart 1) — after a deliberate delay long
# enough that A is definitely stalled — STORES to that word, which kills A's
# global reservation in resv_unit and must wake A. reservation-kill must WIN
# over the software watchdog.
#
# SOFTWARE WATCHDOG (so a never-wake bug FAILs cleanly inside the 1-minute sim,
# never hangs): after storing, hart B polls A_WOKE with a bounded budget. If A
# acknowledges the wake, B is done (no backstop). If the budget expires (A is
# stuck — wrs.nto has no timeout), B raises BACKSTOP_FIRED and fires a backstop
# msip at hart 0, forcing A out of the stall via the interrupt-pending wake so
# the verdict is a clean FAIL. A distinguishes the paths: it reads BACKSTOP_FIRED
# on wake — 0 => it woke on the reservation kill (PASS); 1 => it only woke on the
# backstop (reservation-kill lost => FAIL). This is exactly what the negative
# control (seed "never wake on invalidation") exercises: it drives the backstop
# path and a clean watchdog FAIL.
#
# Shared-window words (< 0x10500 loader rows, > shafe 0x10498, bootrom-zeroed):
#     SH_WORD     = 0x104A0   the LR-reserved shared word
#     SH_A_WOKE   = 0x104A4   A sets = 1 once wrs.nto wakes
#     SH_BACKSTOP = 0x104A8   B sets = 1 immediately before firing the backstop
#     SH_B_DONE   = 0x104AC   B progress marker
#
# Build-time #ifdef: the OFF (Zawrs-disabled) image degrades to a trivially
# passing single-hart variant so the DEFAULT suite stays green.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"
#include "core_features.h"          /* CORE_ENABLE_ZAWRS (assembly-safe companion) */

#define WRS_NTO      .word 0x00d00073

#define SH_WORD      0x104A0
#define SH_A_WOKE    0x104A4
#define SH_BACKSTOP  0x104A8
#define SH_B_DONE    0x104AC
#define STORE_VAL    0xB0B0B0B0

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop

#ifdef CORE_ENABLE_ZAWRS
    # hart 0 = A (falls through); the loader launches hart 1 into hart_b_entry.
    bnez s10, hart_b_entry          # (defensive; the loader ENTRY already routes B)

    # ===== hart 0 = A: launcher + waiter + gate =====
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_HART(1, hart_b_entry, 4096)   # launch ONLY hart 1

    li   s2, SH_WORD
    .option push
    .option arch, +a
    lr.w t0, (s2)                   # take the global reservation
    .option pop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop                             # let resv_valid_ext settle through the boundary
    WRS_NTO                         # stall until B's store kills the reservation
    # ---- woke ----
    li   t1, 1
    li   s3, SH_A_WOKE
    sw   t1, 0(s3)                  # tell B we woke (so B skips its backstop)
    li   s4, SH_BACKSTOP
    lw   t2, 0(s4)                  # which path woke us?
    bnez t2, shwrs_fail             # backstop fired first => reservation-kill lost
    lw   t3, 0(s2)                  # the store must have landed (kill => it did)
    li   t4, STORE_VAL
    bne  t3, t4, shwrs_fail
    RVTEST_PASS                     # a0 = 0xCAFEBABE (hart-0 gate PASS)

    # ===== hart 1 = B: storer + software watchdog =====
hart_b_entry:
    li   sp, 0xBFF0
    li   s2, SH_WORD
    li   s3, SH_A_WOKE
    li   s4, SH_BACKSTOP
    li   t6, 6000                   # delay so A is definitely parked in wrs.nto
1:  addi t6, t6, -1
    bnez t6, 1b
    li   t0, STORE_VAL
    sw   t0, 0(s2)                  # STORE -> kills A's reservation -> A must wake
    li   t6, 20000                  # bounded watchdog (fits the 100ms tb watchdog)
2:  lw   t1, 0(s3)
    bnez t1, b_done                 # A acknowledged the wake -> good, no backstop
    addi t6, t6, -1
    bnez t6, 2b
    # A never woke -> raise the backstop and msip hart 0 (clean FAIL, not a hang)
    li   t1, 1
    sw   t1, 0(s4)                  # BACKSTOP_FIRED = 1 (A reads this and FAILs)
    li   t0, 0x5000
    li   t1, 1
    sw   t1, 0(t0)                  # MSIP[0] = 1 -> forces A out of the nto-stall
b_done:
    li   a0, 0xCAFEBABE             # tile inline PASS (tb latches a0_1)
    li   t0, SH_B_DONE
    li   t1, 1
    sw   t1, 0(t0)
b_spin:
    j    b_spin

    # hart 0 slot-83 msip ISR (fires only in the backstop/broken case): clear
    # the level and return; BACKSTOP_FIRED already told A it lost.
msip_isr:
    addi sp, sp, -8
    sw   t0, 0(sp)
    sw   t1, 4(sp)
    li   t0, 0x5000
    sw   x0, 0(t0)                  # clear MSIP[0]
    lw   t0, 0(sp)
    lw   t1, 4(sp)
    addi sp, sp, 8
    iret

    .section .ivt, "ax"
    .org 0x14C
    jal  zero, msip_isr             # slot 83 = IRQB_CLINT_MSIP
    .previous

#else
    # ===== ZAWRS off: trivially-passing single-hart variant (suite green) =====
    RVTEST_PASS
#endif

shwrs_fail:
    RVTEST_FAIL

    # RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
