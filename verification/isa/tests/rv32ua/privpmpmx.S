# See LICENSE for license details.

# VestaRV: a PMP-denied access must issue no bus transaction
# ON-ONLY multi-hart test, needing a trapCsr, umode and pmp build. privpmp proves a denied access traps with the right cause, mtval and mepc; THIS file proves the STRICT PRE-ISSUE guarantee, that a denied access performs NO BUS TRANSACTION at all.
# WHY THAT MATTERS: the shared window holds two read-with-side-effect registers, the HW mutex bank, where a load is an atomic return-old-and-claim, and the irq_router CLAIM register, where a read drains the pending interrupt. A check that lands AFTER the arbiter grant is a silent lock leak or a stolen interrupt, which no cause or mtval check can see, because the trap looks perfect.
# THE PROOF, since a claim is only observable from ANOTHER hart: hart 0 runs in M-mode with mstatus.MPRV = 1 and MPP = U, so the DATA privilege is U while the instruction fetch stays M and no U-mode code region is needed; it executes `lw t3, 0(0x603C)` against MUTEX 15, which PMP entry 0 fences NA4 with R = W = X = 0, so the access must be denied with mcause 5, mtval 0x603C, mepc the load's own PC and rd untouched. Hart 0 then launches hart 1 through the boot ROM loader; hart 1 has its own empty PMP bank, performs the SAME load and publishes what it read. HART 1 MUST READ 0, meaning the mutex was free: had hart 0's denied load reached the arbiter it would have claimed the mutex and never released it, so hart 1 would read hart 0's marker.
# Mutex 15 is used by no other test and the suite runs one image per simulation, so the bank is provably all-free at reset for this run.
# Shared words, both N-agnostic scalars so they are correct at any NHARTS, taking the TOP TWO words of the reserved band 0x102A0-0x1037F, since that band grows from the bottom: 0x10378 PMPMX_MRD, what hart 1 read from mutex 15, and 0x1037C PMPMX_DONE1, hart 1's completion flag 0x40BE0001. The only loop is hart 0's DONE poll, bounded at 100000 iterations, which covers the serialised tile ROM copy at launch and fits inside the 100 ms tb watchdog.
# REGISTER CONTRACT, standard mode pushing nothing: s2 mutex 15's address, s3 the trap counter, s4, s5 and s6 cause, mepc and mtval, s7 the handler resume PC, s8 the expected mepc, s10 mhartid, t3 the denied load's rd, pre-seeded and required to survive, and t4 the CHECK ID.
# BUILD-TIME DISPATCH: assembled only with all three of -DCORE_ENABLE_TRAPCSR, -DCORE_ENABLE_UMODE and -DCORE_ENABLE_PMP; this file is deliberately not in the default runner array. THE NAME IS CONSTRAINED BY THE RUNNER: the rcf basename must be exactly 22 characters, so the spec's "privpmpmtx" would produce a 23-character rcf that xrun.sh rejects.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

.option norvc
.option norelax

#define PMPMX_MUTEX   0x0000603C        /* mutex bank 0x6000 + 4*15           */
#define PMPMX_MRD     0x00010378
#define PMPMX_DONE1   0x0001037C
#define PMPMX_TORTOP  0x00020000        /* TOR top: the whole shared window  */
#define PMPMX_SENT    0x22222222        /* "hart 1 never published" sentinel */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity ------------------------------------------------
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, pmx_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE) && defined(CORE_ENABLE_PMP)

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry            # M12: only hart 0 runs the launcher

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0                      # trap counter
    li   s2, PMPMX_MUTEX

    # =====================================================================
    # CHECK 1/2 — arm mtvec, then opt into STANDARD delivery (a PMP fault is
    # an EXCEPTION; in legacy mode it would dead-end in TRAP_STATE).
    # =====================================================================
    li   t4, 1
    la   t0, pmx_handler
    csrw 0x305, t0
    csrr t1, 0x305
    bne  t1, t0, pmx_fail

    li   t4, 2
    csrw 0x7C0, x0
    csrr t1, 0x7C0
    bne  t1, x0, pmx_fail

    # =====================================================================
    # CHECK 3/4 — the map. Entry 0 fences EXACTLY mutex 15 (NA4, no perms);
    # entry 2 grants U everything else in the shared window, so the ONLY
    # thing the U data view forbids is the mutex word itself. Addresses
    # first, cfg last.
    # =====================================================================
    li   t4, 3
    srli t0, s2, 2
    csrw 0x3B0, t0                  # pmpaddr0 = 0x603C >> 2
    csrr t1, 0x3B0
    bne  t1, t0, pmx_fail
    csrw 0x3B1, x0                  # pmpaddr1 = 0 : entry 2's TOR BASE
    li   t0, PMPMX_TORTOP
    srli t0, t0, 2
    csrw 0x3B2, t0                  # pmpaddr2 = TOR TOP

    li   t4, 4
    li   t0, 0x000F0010             # cfg2 = R|W|X|TOR, cfg1 = OFF, cfg0 = NA4
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, pmx_fail

    # =====================================================================
    # Publish the "hart 1 never ran" sentinel BEFORE anything else can write
    # it (the bootrom zeroes this range, so 0 would otherwise be ambiguous
    # with hart 1's legitimate "the mutex was free" result).
    # =====================================================================
    li   t0, PMPMX_MRD
    li   t1, PMPMX_SENT
    sw   t1, 0(t0)

    # =====================================================================
    # CHECK 10..14 — THE DENIED LOAD. M-mode, MPRV=1, MPP=U => the DATA
    # privilege is U (the fetch stays M, which is why no U code region is
    # needed). rd is pre-seeded so a phantom writeback is visible too.
    # =====================================================================
    li   t3, 0x33333333             # rd sentinel: must survive the fault
    li   t1, 0x00020000             # MPRV=1, MPP=00 (U)
    csrw 0x300, t1
    la   s7, pmx_denied_r
    la   s8, pmx_denied_a
    li   t2, 1                      # exactly one trap expected
pmx_denied_a:
    lw   t3, 0(s2)                  # <-- THE DENIED MUTEX CLAIM
pmx_denied_r:
    csrw 0x300, x0                  # clear MPRV before ANY other data access
                                    # (MRET back to M keeps MPRV but forces
                                    #  MPP=00, so the U view would persist)
    li   t4, 10
    bne  s3, t2, pmx_fail           # a trap was actually delivered
    li   t4, 11
    li   t1, 5
    bne  s4, t1, pmx_fail           # mcause = 5 (load access fault)
    li   t4, 12
    bne  s5, s8, pmx_fail           # mepc  = the load's own PC
    li   t4, 13
    bne  s6, s2, pmx_fail           # mtval = 0x603C, byte-precise
    li   t4, 14
    li   t1, 0x33333333
    bne  t3, t1, pmx_fail           # rd untouched: no phantom writeback

    # =====================================================================
    # Launch hart 1 through the M12 bootrom loader and let it claim the SAME
    # mutex. Everything from here runs in M with MPRV=0, so PMP grants it all
    # (unlocked entries never constrain M).
    # =====================================================================
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_HART(1, tile_entry, 4096)

    li   t4, 20                     # bounded DONE wait (shmutex budget)
    li   t0, PMPMX_DONE1
    li   t1, 0x40BE0001
    li   t2, 100000
pmx_wait:
    lw   t5, 0(t0)
    beq  t5, t1, pmx_got
    addi t2, t2, -1
    bnez t2, pmx_wait
    j    pmx_fail                   # hart 1 never reported

pmx_got:
    # =====================================================================
    # CHECK 40 — THE D5 VERDICT. Hart 1's claim-read of mutex 15 must have
    # returned 0 ("was free, you now own it"). A nonzero value is hart 0's
    # marker (hartid + 1 = 1) and means the DENIED load reached the arbiter
    # and claimed the mutex before trapping — exactly what the post-issue
    # negative-control seed (p3_postissue_seed.patch) manufactures.
    # =====================================================================
    li   t4, 40
    li   t0, PMPMX_MRD
    lw   t1, 0(t0)
    bne  t1, x0, pmx_fail

    # ---- restore: back to LEGACY delivery, PMP entries released ----------
    li   t4, 41
    csrw 0x3A0, x0
    csrr t1, 0x3A0
    bne  t1, x0, pmx_fail
    li   t1, 0x00000001
    csrw 0x7C0, t1
    csrw 0x300, x0

    RVTEST_PASS

    # =====================================================================
    # Hart 1's body. It enters here through the bootrom loader with ONLY sp
    # defined, in M-mode, in LEGACY delivery, with its OWN (all-zero) PMP
    # bank — so nothing constrains it and its claim is the honest observer.
    # =====================================================================
tile_entry:
    li   sp, 0xBFF0
    li   s2, PMPMX_MUTEX
    lw   t0, 0(s2)                  # atomic return-old-and-claim
    li   t1, PMPMX_MRD
    sw   t0, 0(t1)                  # publish what we read (0 = it was FREE)
    sw   x0, 0(s2)                  # release
    li   t1, PMPMX_DONE1
    li   t2, 0x40BE0001
    sw   t2, 0(t1)
    li   a0, 0xCAFEBABE             # inline PASS (tb latches a0_1)
tile_spin:
    j    tile_spin

    # =====================================================================
    # The mtvec handler (hart 0 only; placed after the PASS spin loop so it
    # can only be reached by a hardware trap).
    # =====================================================================
    .align 2
pmx_handler:
    csrr s4, 0x342                  # mcause
    csrr s5, 0x341                  # mepc
    csrr s6, 0x343                  # mtval
    addi s3, s3, 1
    csrw 0x341, s7                  # resume at s7 in the TRAPPED privilege
    mret

    .option pop

#else
    # OFF / trapCsr / trapCsr+umode build: the PMP CSRs are unknown addresses
    # and this core DEAD-ENDS an illegal instruction in the terminal
    # TRAP_STATE, so none of the above may be assembled.
    li   t4, 0
    j    pmx_fail
#endif

pmx_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF (t4 = failing check id)

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
