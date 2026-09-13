# See LICENSE for license details.

# VestaRV: cross-hart amocas spinlock torture
# All harts run this image: hart 0 stages the TCM image once, launches the tiles through the boot ROM loader, then falls through and runs the same payload. Each hart performs ITERS critical sections behind a CAS SPINLOCK on one shared word: acquire is an amocas.w from 0 to hartid + 1, and release is an amocas.w from hartid + 1 back to 0, WHICH VERIFIES THAT WE HELD IT, since a release that does not see our ownership is a lost-mutual-exclusion failure. Inside the section the hart does a NON-atomic read-modify-write of the counter, protected only by the CAS lock, and re-reads the lock word to confirm exclusive ownership.
# Interleaved with the CAS traffic, every iteration also does an LR/SC atomic increment of a SEPARATE counter at a DIFFERENT address, which proves CAS grant-locking and LR/SC reservations coexist on the shared bus.
# Hart 0's assertions are exact: the CAS-protected counter must equal NHARTS*ITERS, since a lost update undercounts and a broken release or double entry overcounts, and the LR/SC counter must equal the same. Every acquire and store-conditional retry is BOUNDED with hartid-scaled backoff, because identical harts on the fair arbiter otherwise livelock, and a blown budget fails inside the 100 ms tb watchdog rather than hanging.
# ON-BUILD ONLY, since amocas.w traps illegal without Zacas. Shared words, all below 0x10500 and inside the bootrom zero range, with the control words after the NHARTS-sized array: DONE[h] = 0x10400 + 4*h for h = 1..NHARTS-1, LOCK = 0x10400 + 4*NHARTS, CTR = LOCK + 4 and LRSC_CTR = LOCK + 8.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define AMOCAS_W(rd,rs1,rs2)  .insn r 0x2f, 0x2, 0x14, rd, rs1, rs2
#define ITERS 16

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..NHARTS-1
    .option pop

#ifdef CORE_ENABLE_ZACAS
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher

    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined for tiles until now)
    .option pop
    li   sp, 0xBFF0

    li   s4, 0x10400                    # DONE base (DONE[h] = 0x10400 + 4*h)
    li   s7, (0x10400 + 4*NHARTS)       # LOCK   (control words AFTER the DONE
    li   s8, (0x10400 + 4*NHARTS + 4)   # CTR     array so N=18 can't overrun)
    li   s9, (0x10400 + 4*NHARTS + 8)   # LRSC_CTR
    addi s11, s10, 1            # my nonzero owner marker (myid+1)

    li   s6, ITERS             # committed critical sections per hart
iter_loop:
    # ---------- CAS spinlock acquire: LOCK 0(free) -> myid+1 ----------
    li   t6, 4096              # bounded acquire budget (broken lock -> FAIL)
cas_acquire:
    li   a2, 0                 # rd = compare value = 0 (expect free)
    AMOCAS_W(a2, s7, s11)      # if LOCK==0: LOCK<-myid+1, a2<-0(old); else a2<-holder
    beqz a2, cas_got          # old==0 -> we committed the 0->myid+1 transition
    addi t6, t6, -1
    beqz t6, shzc_fail
    slli t1, s10, 3           # backoff = hartid*8 + 8 spins (livelock rule)
    addi t1, t1, 8
1:  addi t1, t1, -1
    bnez t1, 1b
    j    cas_acquire
cas_got:
    # ---------- critical section: NON-atomic RMW of CTR ----------
    lw   t2, 0(s8)
    addi t2, t2, 1
    sw   t2, 0(s8)
    lw   t3, 0(s7)            # still owned by me? (direct mutual-exclusion check)
    bne  t3, s11, shzc_fail
    # ---------- CAS release: LOCK myid+1 -> 0, verify WE held it ----------
    mv   a2, s11             # rd = compare value = my owner marker
    li   t1, 0
    AMOCAS_W(a2, s7, t1)     # if LOCK==myid+1: LOCK<-0, a2<-myid+1; else a2<-other
    bne  a2, s11, shzc_fail  # release must have observed our ownership

    # ---------- interleaved LR/SC atomic increment (M7c interplay) ----------
    .option push
    .option arch, +a
    li   t6, 4096
lrsc_inc:
    lr.w t0, (s9)
    addi t0, t0, 1
    sc.w t5, t0, (s9)
    beqz t5, lrsc_ok         # SC success
    addi t6, t6, -1
    beqz t6, shzc_fail
    slli t1, s10, 3          # hartid-scaled backoff (LR/SC livelock rule)
    addi t1, t1, 8
2:  addi t1, t1, -1
    bnez t1, 2b
    j    lrsc_inc
lrsc_ok:
    .option pop

    addi s6, s6, -1
    bnez s6, iter_loop

    beqz s10, check_total

    # ---- harts 1..NHARTS-1: report DONE, inline PASS, park ----
    slli t0, s10, 2
    add  t1, s4, t0
    li   t2, 0xCA50000       # DONE marker base (nonzero)
    add  t2, t2, s10
    sw   t2, 0(t1)           # DONE[h]
    li   a0, 0xCAFEBABE      # inline PASS (tb latches a0_1/2/3)
quiet_spin:
    j    quiet_spin

    # ---- hart 0: wait for all DONEs (bounded), require EXACT counts ----
check_total:
    li   s6, 1
done_wait_loop:
    slli t0, s6, 2
    add  t1, s4, t0          # DONE[h]
    li   t2, 0xCA50000
    add  t2, t2, s6
    li   t6, 100000          # bounded wait (covers serialized tile ROM-copies)
done_wait:
    lw   t3, 0(t1)
    beq  t3, t2, done_ok
    addi t6, t6, -1
    bnez t6, done_wait
    j    shzc_fail
done_ok:
    addi s6, s6, 1
    li   t0, NHARTS
    bne  s6, t0, done_wait_loop

    lw   t3, 0(s8)           # CAS-protected counter
    li   t4, NHARTS*ITERS
    bne  t3, t4, shzc_fail   # lost/duplicated CAS critical section
    lw   t3, 0(s9)           # LR/SC counter
    bne  t3, t4, shzc_fail   # lost LR/SC update

    RVTEST_PASS              # a0 = 0xCAFEBABE

#else
    # OFF (default build): trivial single-hart pass — keeps the default suite
    # green (shzabha precedent). amocas.w is illegal on a zacas-OFF build; the
    # illegal-instruction trap is proven separately by extzacas/casill under
    # run_extoff.sh -> TRAP_OK.
    li   t0, 0x0ABC
    li   t1, 0x0ABC
    bne  t0, t1, shzc_fail
    RVTEST_PASS
#endif

shzc_fail:
    RVTEST_FAIL              # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
