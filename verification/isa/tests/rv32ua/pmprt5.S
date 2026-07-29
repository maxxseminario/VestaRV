# See LICENSE for license details.

#*****************************************************************************
# pmprt5.S   (P3 RED TEAM — the STORE-side D5 leak, the TRAP-ENTRY
#             RE-PRESENTATION window, and CROSS-HART BANK ISOLATION)
#-----------------------------------------------------------------------------
# ON-ONLY DIRECTED MP TEST (needs a trapCsr+umode+pmp build).  privpmpmx
# proves the LOAD side of D5 (a denied mutex claim-read never issues).  This
# file covers the two things it does not:
#
# PART 1 (CHECK 10..17) — THE STORE SIDE, AND THE TRAP-ENTRY WINDOW.
#   The HW mutex bank's `sw 0` is an owner-unqualified RELEASE (CLAUDE.md).
#   So: hart 0 CLAIMS mutex 14 in M, then attempts a PMP-DENIED `sw x0` to the
#   same word under the U data view.  If the denied store issued — either in
#   its own EXECUTE cycle, or when the faulting encoding is RE-PRESENTED to
#   the decoder during MTRAP_SV/MTRAP_JUMP (`read_data` doubles as the
#   instruction during decode; this is the exact shape of the P2 U-mode CSR
#   escape, closed there by `trap_entry_seq`, vesta.vhd:1742-1758) — the mutex
#   would have been RELEASED.  hart 0 then re-reads it: still-owned reads back
#   as hartid+1 = 1, released reads back as 0.  ONE HART sees the whole story,
#   so this is a much cheaper D5 witness than the two-hart claim test.
#
#   This is also the vehicle for red-team item 2 (MTRAP_SV presents
#   `pc_next_reg` on the bus for ALL causes; only cause 1 is parked,
#   vesta.vhd:1841-1846).  A cause-7 entry from a store aimed at a mutex word
#   is precisely the case where a re-presented address would be
#   side-effecting.
#
# PART 2 (CHECK 20..27) — CROSS-HART BANK ISOLATION.
#   Every hart_tile instantiates its OWN csr_unit, so the pmpcfg/pmpaddr bank
#   is per-hart.  hart 0 fences a shared word with an entry that has no
#   permissions; hart 1 is launched through the M12 bootrom loader with an
#   untouched (all-zero) bank and must be able to WRITE that same word.  Then
#   hart 0 proves BOTH halves at once: its own U view still faults on the
#   word, and its M view reads back exactly what hart 1 wrote.  A bank that
#   bled across harts fails the first half (hart 1 blocked, no marker) or the
#   second (hart 0's fence gone).
#
# SHARED-WORD LEDGER (CLAUDE.md: everything < 0x10500, inside the bootrom zero
# range).  Two N-agnostic scalars from the course-reserved band
# 0x102A0-0x1037F, just below privpmpmx's pair:
#     0x10368  PMPRT5_W      the fenced shared word (hart 1 writes it)
#     0x1036C  PMPRT5_DONE1  hart 1's completion flag (0x50BE0001)
#
# BOUNDEDNESS: the only loop is hart 0's DONE poll with an explicit 100000
# iteration budget (the shmutex figure).
#
# REGISTER CONTRACT:
#   s2 the fenced address    s3 trap counter   s4/s5/s6 cause/mepc/mtval
#   s7 handler resume PC     s10 mhartid       t4 CHECK ID
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

.option norvc
.option norelax

#define PMPRT5_MUTEX  0x00006038        /* mutex bank 0x6000 + 4*14  */
#define PMPRT5_W      0x00010368
#define PMPRT5_DONE1  0x0001036C
#define PMPRT5_TORTOP 0x00020000
#define PMPRT5_MARK   0x5A5AC0DE

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, rt5_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE) && defined(CORE_ENABLE_PMP)

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, rt5_tile_entry

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0

    li   t4, 1
    la   t0, rt5_handler
    csrw 0x305, t0
    csrr t1, 0x305
    bne  t1, t0, rt5_fail
    li   t4, 2
    csrw 0x7C0, x0
    csrr t1, 0x7C0
    bne  t1, x0, rt5_fail
    csrw 0x300, x0
    csrw 0x304, x0

    # =====================================================================
    # PART 1 — the STORE side of D5.
    # =====================================================================
    li   s2, PMPRT5_MUTEX

    li   t4, 10                     # CLAIM mutex 14 in M (must have been free)
    lw   t0, 0(s2)
    bne  t0, x0, rt5_fail

    li   t4, 11                     # the map: entry0 fences EXACTLY that word
    srli t0, s2, 2
    csrw 0x3B0, t0
    csrw 0x3B1, x0
    li   t0, PMPRT5_TORTOP
    srli t0, t0, 2
    csrw 0x3B2, t0
    li   t0, 0x000F0010             # cfg2=TOR RWX cfg1=OFF cfg0=NA4 no-perms
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt5_fail

    li   t4, 12                     # THE DENIED RELEASE
    mv   t6, s3
    la   s7, rt5_p1_flt
    li   t1, 0x00020000             # MPRV=1, MPP=U
    csrw 0x300, t1
rt5_p1_a:
    sw   x0, 0(s2)                  # <-- must NOT reach the mutex bank
    csrw 0x300, x0
    j    rt5_fail                   # it was granted: the fence is wrong

rt5_p1_flt:
    csrw 0x300, x0
    li   t4, 13
    addi t1, t6, 1
    bne  s3, t1, rt5_fail
    li   t4, 14
    li   t1, 7
    bne  s4, t1, rt5_fail           # cause 7 (store/AMO access fault)
    li   t4, 15
    la   t1, rt5_p1_a
    bne  s5, t1, rt5_fail           # mepc = the store's own PC
    li   t4, 16
    bne  s6, s2, rt5_fail           # mtval = 0x6038, byte-precise

    # ---- THE VERDICT.  M is unconstrained by an unlocked entry, so this
    # claim-read is legal.  It must return hart 0's own marker (hartid+1 = 1),
    # proving the mutex was NEVER released — i.e. neither the EXECUTE cycle
    # nor the MTRAP_SV/MTRAP_JUMP re-presentation put the store on the bus.
    li   t4, 17
    lw   t0, 0(s2)
    li   t1, 1
    bne  t0, t1, rt5_fail
    sw   x0, 0(s2)                  # release it for good hygiene

    # =====================================================================
    # PART 2 — cross-hart bank isolation.
    # =====================================================================
    li   s2, PMPRT5_W
    li   t4, 20                     # re-aim entry 0 at the shared word
    srli t0, s2, 2
    csrw 0x3B0, t0
    csrr t1, 0x3B0
    bne  t1, t0, rt5_fail

    li   t4, 21                     # hart 0's own U view must be fenced
    mv   t6, s3
    la   s7, rt5_p2_flt1
    li   t1, 0x00020000
    csrw 0x300, t1
    lw   t0, 0(s2)
    csrw 0x300, x0
    j    rt5_fail                   # granted: the fence is wrong
rt5_p2_flt1:
    csrw 0x300, x0
    li   t4, 22
    li   t1, 5
    bne  s4, t1, rt5_fail

    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_HART(1, rt5_tile_entry, 4096)

    li   t4, 23                     # bounded DONE wait (shmutex budget)
    li   t0, PMPRT5_DONE1
    li   t1, 0x50BE0001
    li   t2, 100000
rt5_wait:
    lw   t5, 0(t0)
    beq  t5, t1, rt5_got
    addi t2, t2, -1
    bnez t2, rt5_wait
    j    rt5_fail                   # hart 1 never reported

rt5_got:
    li   t4, 24                     # NO BANK BLEED: hart 1's write landed
    lw   t0, 0(s2)                  # (M view — an unlocked entry never
    li   t1, PMPRT5_MARK            #  constrains M, so this read is legal)
    bne  t0, t1, rt5_fail

    li   t4, 25                     # and hart 0's OWN fence still stands
    mv   t6, s3
    la   s7, rt5_p2_flt2
    li   t1, 0x00020000
    csrw 0x300, t1
    lw   t0, 0(s2)
    csrw 0x300, x0
    j    rt5_fail
rt5_p2_flt2:
    csrw 0x300, x0
    li   t4, 26
    addi t1, t6, 1
    bne  s3, t1, rt5_fail
    li   t4, 27
    bne  s6, s2, rt5_fail

    # ---- restore -------------------------------------------------------
    li   t4, 28
    csrw 0x3A0, x0
    csrr t1, 0x3A0
    bne  t1, x0, rt5_fail
    li   t1, 0x00000001
    csrw 0x7C0, t1
    csrw 0x300, x0

    RVTEST_PASS

    # =====================================================================
    # hart 1: entered through the bootrom loader with only sp defined, in M,
    # LEGACY delivery, with its OWN all-zero PMP bank.
    # =====================================================================
rt5_tile_entry:
    li   sp, 0xBFF0
    li   t0, PMPRT5_W
    li   t1, PMPRT5_MARK
    sw   t1, 0(t0)                  # must NOT be blocked by hart 0's bank
    lw   t2, 0(t0)
    bne  t2, t1, rt5_tile_spin      # readback failed: publish nothing
    li   t0, PMPRT5_DONE1
    li   t1, 0x50BE0001
    sw   t1, 0(t0)
    li   a0, 0xCAFEBABE             # inline PASS (tb latches a0_1)
rt5_tile_spin:
    j    rt5_tile_spin

    .align 2
rt5_handler:
    csrr t0, 0x342
    addi s3, s3, 1
    mv   s4, t0
    csrr s5, 0x341
    csrr s6, 0x343
    csrw 0x341, s7
    mret

    .option pop

#else
    li   t4, 0
    j    rt5_fail
#endif

rt5_fail:
    RVTEST_FAIL

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
