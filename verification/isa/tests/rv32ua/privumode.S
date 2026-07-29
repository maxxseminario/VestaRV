# See LICENSE for license details.

#*****************************************************************************
# privumode.S   (P2 U-mode — privilege round trip, MPP WARL, ECALL-from-U)
#-----------------------------------------------------------------------------
# ON-ONLY DIRECTED TEST (needs a trapCsr+umode build). privcsr proves the P1 CSR
# file and privecall proves P1 delivery; THIS file proves the P2 privilege
# machinery in csr_unit + the ECALL cause mux in vesta, against
# ~/vesta_docs/priv_arch/p0_specs.md §3 / §3.1:
#
#   misa.U (bit 20)        set iff ENABLE_UMODE — the program's ONE misa change
#   mstatus.MPP WARL       {00,11}: a written 00 STAYS 00; the two UNSUPPORTED
#                          encodings 01/10 map to 11 (M) — the FROZEN
#                          conservative direction
#   MRET                   priv <- MPP, THEN MPP <- 00.  The "THEN MPP <- 00"
#                          half is negative control (a),
#                          verification/isa/negctrl/p2_mppstuck_seed.patch, and
#                          CHECK 8 is its catcher: an MRET taken from M with
#                          MPP=11 must leave MPP reading 00.
#   trap entry             MPP <- priv (the INTERRUPTED privilege), priv <- M
#   ECALL from U           mcause 8 (ECALL from M is 11 — privecall's job)
#
# Every failure path is a compare-and-branch into RVTEST_FAIL, never a watchdog
# hang: the trap counter s3 makes "no trap was delivered at all" bounded too,
# and the instruction after each U-mode ECALL is an explicit `j pvum_fail` (a
# resume THERE means the U->M transition never happened).
#
# REGISTER CONTRACT (standard mode pushes NOTHING — a U-mode sp is untrusted):
#   s0  expected mepc for the trap under test  (set in M before entering U)
#   s1  U-mode witness (written by the U code)
#   s2  handler address
#   s3  trap counter (handler increments)
#   s4  mcause captured in the handler
#   s5  mepc   captured in the handler
#   s6  mstatus captured INSIDE the trap (the PUSHED state — MPP = trapped priv)
#   s9  M-mode continuation address; the handler leaves the trap with `jr s9`
#       rather than MRET, so the pushed mstatus stays inspectable from M
#   t4  CHECK ID at every comparison — a FAIL is localisable from a0/t4 alone
#
# BUILD-TIME DISPATCH (privcsr / privecall / extjvt idiom): ON iff BOTH
# -DCORE_ENABLE_TRAPCSR and -DCORE_ENABLE_UMODE are appended to RISCV_GCC_OPTS
# on a staged trapCsr+umode build. The #else arm FAILs immediately and loudly —
# privumode is deliberately NOT in the default behavioral_mp runner array, so
# that arm must never execute.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity: prove the core runs before any privilege work ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, pvum_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0                 # valid sp (standard mode never pushes; set
                                    # anyway so the file matches suite convention)
    li   s3, 0                      # trap counter

    # =====================================================================
    # CHECK 1 — misa.U (bit 20). The ONE misa change of the whole P-series
    # program (p0_specs.md §3.1/§6): set iff ENABLE_UMODE, so an OFF or
    # trapCsr-only build's misa is bit-identical to a pre-P0 chip.
    # =====================================================================
    li   t4, 1
    csrr t2, 0x301
    li   t3, 0x00100000
    and  t2, t2, t3
    bne  t2, t3, pvum_fail

    # =====================================================================
    # CHECK 2..5 — mstatus.MPP WARL widening {11} -> {00,11}.
    # =====================================================================
    li   t4, 2                      # a written 00 STAYS 00 (this is the widening)
    csrw 0x300, x0
    csrr t2, 0x300
    bne  t2, x0, pvum_fail

    li   t4, 3                      # a written 11 stores 11
    li   t1, 0x00001800
    csrw 0x300, t1
    csrr t2, 0x300
    li   t3, 0x00001800
    bne  t2, t3, pvum_fail

    li   t4, 4                      # UNSUPPORTED 10 -> 11 (conservative direction)
    li   t1, 0x00001000
    csrw 0x300, t1
    csrr t2, 0x300
    li   t3, 0x00001800
    bne  t2, t3, pvum_fail

    li   t4, 5                      # UNSUPPORTED 01 -> 11
    li   t1, 0x00000800
    csrw 0x300, t1
    csrr t2, 0x300
    li   t3, 0x00001800
    bne  t2, t3, pvum_fail

    # =====================================================================
    # CHECK 6/7 — arm mtvec FIRST, then opt into STANDARD delivery. Order is
    # the contract; and MRET is only defined in standard mode (in legacy mode
    # it lands in the terminal TRAP_STATE), so nothing below may run until
    # mtrapctl.LEGACY is 0.
    # =====================================================================
    li   t4, 6
    la   s2, pvum_handler
    csrw 0x305, s2
    csrr t2, 0x305
    bne  t2, s2, pvum_fail

    li   t4, 7
    csrw 0x7C0, x0
    csrr t2, 0x7C0
    bne  t2, x0, pvum_fail

    # =====================================================================
    # CHECK 8 — THE MPP-CLEAR PROOF (negative control (a) p2_mppstuck).
    # An MRET taken from M with MPP=11 returns to M (priv <- MPP) and MUST
    # then leave MPP reading 00. Entry state 0x1800 (MPP=11, MPIE=0, MIE=0)
    # -> after MRET: MIE<=MPIE(0), MPIE<=1, priv<=M, MPP<=00 => 0x0080.
    # With `MPP <= "00"` dropped it reads 0x1880 and this bounded bne fires.
    # =====================================================================
    li   t4, 8
    li   t1, 0x00001800
    csrw 0x300, t1
    la   t0, pvum_mret1_ret
    csrw 0x341, t0
    mret                            # returns to M (MPP was 11)
pvum_mret1_ret:
    csrr t2, 0x300
    li   t3, 0x00000080             # MPIE only: MPP MUST have been cleared
    bne  t2, t3, pvum_fail

#ifdef CORE_ENABLE_PMP
    # =====================================================================
    # P3 PMP PROLOGUE (2026-07-29). With PMP implemented, a U-mode access
    # matching NO entry FAULTS (spec + frozen §4 no-match rule) — on a pmp
    # build the first U-mode fetch of ROUND TRIP 1 would take cause 1 and
    # derail the ECALL protocol. Grant U R|W|X over 0x0-0xFFFF (TOR entry 1,
    # base = pmpaddr0 = 0; entries 2-15 free, nothing locked) BEFORE the
    # first U entry. Not assembled on the trapCsr+umode polarity.
    # =====================================================================
    csrw 0x3B0, x0                  # pmpaddr0 = 0 : entry 1's TOR base
    li   t0, 0x00010000
    srli t0, t0, 2                  # word address of the TOR top
    csrw 0x3B1, t0                  # pmpaddr1 = 0x10000 >> 2
    li   t0, 0x00000F00             # cfg1 = TOR|X|W|R, cfg0 = OFF
    csrw 0x3A0, t0
#endif

    # =====================================================================
    # U-MODE ROUND TRIP 1 — CHECK 9..15.
    # MPP=00 + MRET enters U; the U code's ECALL comes back to M with cause 8.
    # =====================================================================
    li   t4, 9
    li   s1, 0
    csrw 0x300, x0                  # MPP=00 (U), MIE=0, TW=0
    la   s0, pvum_uecall1           # expected mepc
    la   s9, pvum_m1                # where the handler resumes the M flow
    la   t0, pvum_uentry1
    csrw 0x341, t0
    mret                            # ---- now in U-MODE ----

pvum_uentry1:
    li   s1, 0x000000C1             # U-mode witness
pvum_uecall1:
    ecall                           # -> M, mcause 8
    j    pvum_fail                  # resuming HERE means U->M never happened

pvum_m1:                            # ---- back in M (handler jr s9) ----
    li   t4, 10                     # a trap was actually delivered
    li   t3, 1
    bne  s3, t3, pvum_fail

    li   t4, 11                     # mcause == 8 (ECALL from U, NOT 11)
    li   t3, 8
    bne  s4, t3, pvum_fail

    li   t4, 12                     # mepc == the U ECALL's OWN pc
    bne  s5, s0, pvum_fail

    li   t4, 13                     # the U-mode code really executed
    li   t3, 0x000000C1
    bne  s1, t3, pvum_fail

    li   t4, 14                     # mstatus AS PUSHED: MPP <- trapped priv = 00,
    bne  s6, x0, pvum_fail          #   MPIE <- MIE(0), MIE <- 0  => 0x00000000

    li   t4, 15                     # we really are back in M: a machine CSR read
    csrr t2, 0x7C0                  #   would be an illegal instruction in U
    bne  t2, x0, pvum_fail          #   (and standard delivery is still selected)

    # =====================================================================
    # U-MODE ROUND TRIP 2 — CHECK 16..21. The SECOND MPP=00 MRET proves the
    # privilege stack RE-ARMS (MPP was forced to 00 by round 1's entry MRET,
    # and trap entry then overwrote it with the trapped priv).
    # =====================================================================
    li   t4, 16
    li   s1, 0
    csrw 0x300, x0
    la   s0, pvum_uecall2
    la   s9, pvum_m2
    la   t0, pvum_uentry2
    csrw 0x341, t0
    mret                            # ---- U-MODE again ----

pvum_uentry2:
    li   s1, 0x000000C2
pvum_uecall2:
    ecall
    j    pvum_fail

pvum_m2:
    li   t4, 17
    li   t3, 2
    bne  s3, t3, pvum_fail

    li   t4, 18
    li   t3, 8
    bne  s4, t3, pvum_fail

    li   t4, 19
    bne  s5, s0, pvum_fail

    li   t4, 20
    li   t3, 0x000000C2
    bne  s1, t3, pvum_fail

    li   t4, 21
    bne  s6, x0, pvum_fail

    # =====================================================================
    # U-MODE ROUND TRIP 3 — CHECK 22..25 (P3-entry, kickoff §3 item 1):
    # an MRET that returns BELOW M must CLEAR mstatus.MPRV (priv-spec rule;
    # without it M-privileged data-access semantics ride into U — an escape
    # vector the moment PMP consumes data_priv_m). Negative control
    # p3e_mprvmret drops exactly that clear; CHECK 25 is its catcher.
    # =====================================================================
    li   t4, 22
    li   t1, 0x00020000             # MPRV=1, MPP=00 (U)
    csrw 0x300, t1
    csrr t2, 0x300                  # pre-condition: MPRV really stored
    li   t3, 0x00020000
    bne  t2, t3, pvum_fail

    li   t4, 23
    li   s1, 0
    la   s0, pvum_uecall3
    la   s9, pvum_m3
    la   t0, pvum_uentry3
    csrw 0x341, t0
    mret                            # ---- U-MODE; this MRET must clear MPRV ----

pvum_uentry3:
    li   s1, 0x000000C3
pvum_uecall3:
    ecall
    j    pvum_fail

pvum_m3:
    li   t4, 24                     # trap 3 delivered: from U, cause 8, right pc
    li   t3, 3
    bne  s3, t3, pvum_fail
    li   t3, 8
    bne  s4, t3, pvum_fail
    bne  s5, s0, pvum_fail

    li   t4, 25                     # THE POINT: MPRV reads 0 back in M — the
    csrr t2, 0x300                  # entry MRET cleared it and nothing set it
    li   t3, 0x00020000             # since (trap entry does not touch MPRV).
    and  t2, t2, t3
    bne  t2, x0, pvum_fail

    # =====================================================================
    # RESTORE — back to LEGACY delivery and a quiet mstatus/mie, so an ON
    # build running the rest of the suite is provably unaffected.
    # =====================================================================
    li   t4, 26
    li   t1, 0x00000001
    csrw 0x7C0, t1
    csrw 0x300, x0
    csrw 0x304, x0
    csrr t2, 0x7C0
    li   t3, 0x00000001
    bne  t2, t3, pvum_fail
    csrr t2, 0x304
    bne  t2, x0, pvum_fail

    RVTEST_PASS

    # =====================================================================
    # The mtvec handler. Placed AFTER the RVTEST_PASS spin loop, so it can
    # only ever be reached by a hardware trap — never by fall-through.
    # It deliberately does NOT MRET: it leaves the trap with `jr s9` into the
    # M-mode flow, which keeps the PUSHED mstatus (MPP = the trapped
    # privilege) inspectable — an MRET would immediately force MPP to 00 and
    # destroy the very evidence CHECK 14/21 wants.
    # =====================================================================
    .align 2
pvum_handler:
    csrr s4, 0x342                  # mcause
    csrr s5, 0x341                  # mepc
    csrr s6, 0x300                  # mstatus AS PUSHED
    addi s3, s3, 1
    jr   s9

    .option pop

#else
    # OFF / trapCsr-only build: U-mode does not exist (misa.U clear, MPP WARL
    # {11}, no privilege register) and on a plain OFF build MRET/ECALL and the
    # ten P1 CSR addresses are illegal instructions that DEAD-END in the
    # terminal TRAP_STATE — so none of the above may be assembled. Reaching
    # here means the ON/OFF staging discipline was violated.
    li   t4, 0
    j    pvum_fail
#endif

pvum_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF (t4 = failing check id)

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
