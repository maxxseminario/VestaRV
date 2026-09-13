# See LICENSE for license details.

# VestaRV: Zawrs wake on a foreign store killing the reservation
# Hart 0 takes an LR on a shared word and executes wrs.nto; hart 1, after a delay long enough that hart 0 is definitely stalled, STORES to that word, which kills the global reservation in resv_unit and must wake hart 0. THE RESERVATION KILL MUST WIN OVER THE SOFTWARE WATCHDOG.
# THE SOFTWARE WATCHDOG EXISTS SO A NEVER-WAKE BUG FAILS CLEANLY RATHER THAN HANGING, since wrs.nto has no timeout. After storing, hart 1 polls the wake flag with a bounded budget; if it expires, hart 1 raises BACKSTOP_FIRED and sends a backstop msip to hart 0, forcing it out of the stall through the interrupt-pending wake. Hart 0 distinguishes the paths by reading BACKSTOP_FIRED on wake: 0 means it woke on the reservation kill and passes, 1 means it only woke on the backstop and the kill was lost. That is exactly what the negative control exercises.
# Shared words, above the neighbouring band and below the loader rows at 0x10500, all bootrom-zeroed: SH_WORD = 0x104A0, the LR-reserved word; SH_A_WOKE = 0x104A4; SH_BACKSTOP = 0x104A8, set immediately before firing the backstop; SH_B_DONE = 0x104AC.
# BUILD-TIME DISPATCH on CORE_ENABLE_ZAWRS, never from an include: the default build leaves it undefined and degrades to a trivially passing single-hart variant so the suite stays green, and the ON arm is built by explicitly appending the define, with the exact command in extzawrs.S's header.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"
# CORE_ENABLE_ZAWRS comes from the build command (-DCORE_ENABLE_ZAWRS), never an include.

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
    .option push
    .option arch, +zicsr
    csrr s5, mcycle                 # timestamp BEFORE the stall
    .option pop
    WRS_NTO                         # stall until B's store kills the reservation
    # ---- woke ----
    .option push
    .option arch, +zicsr
    csrr s6, mcycle                 # timestamp AFTER the wake
    .option pop
    # A must have GENUINELY STALLED (B stores ~ms after A parks here): the mcycle
    # delta across the wrs must be large. A tiny delta = immediate-retire / a
    # degraded wake / a silently-OFF build masquerading — all FAIL here, so the
    # test cannot pass without actually exercising the wait.
    sub  s7, s6, s5
    li   s8, 1000
    bltu s7, s8, shwrs_fail         # did not stall -> the wait was never exercised
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
