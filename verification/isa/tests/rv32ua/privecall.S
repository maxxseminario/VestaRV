# See LICENSE for license details.

#*****************************************************************************
# privecall.S   (P1 standard M-mode trap DELIVERY — exceptions + MRET)
#-----------------------------------------------------------------------------
# ON-ONLY DIRECTED TEST. privcsr proves the CSR FILE; this file proves the
# DELIVERY hardware in vesta's FSM (states MTRAP_SV -> MTRAP_JUMP, and the MRET
# arm MTRAP_RET) against the frozen cause table in
# ~/work/chip_docs/castalia/priv_arch/p0_specs.md 2.2:
#
#   ECALL from M          -> mcause 11, mtval 0, mepc = the ECALL's OWN pc
#   EBREAK                -> mcause  3, mtval 0, mepc = its own pc
#   illegal instruction   -> mcause  2, mtval = the faulting 32-bit encoding
#   MRET                  -> pc <- mepc, MIE <- MPIE, MPIE <- 1
#   trap entry            -> MPIE <- MIE, MIE <- 0   (the mstatus stack push)
#
# Sequence: arm mtvec FIRST, then opt into standard delivery (mtrapctl.LEGACY=0
# — the D1 coexistence bit, which RESETS to 1 so an ON chip still runs the whole
# legacy suite untouched). Two full ECALL round trips run back to back: the
# second one is the proof that the MPIE/MIE stack RE-ARMS (a MRET that forgets
# to restore MIE from MPIE leaves MIE=0, so the second entry pushes MPIE=0 and
# the post-MRET mstatus never returns to 0x1888 — that is negative control (a),
# verification/isa/negctrl/p1_mpierestore_seed.patch).
#
# Every failure path is a compare-and-branch into RVTEST_FAIL, never a watchdog
# hang: the bounded checks are value comparisons, and the trap counter s3 makes
# "no trap was delivered at all" a bounded FAIL too.
#
# REGISTER CONTRACT (this file's handler does NOT save/restore — standard mode
# pushes NOTHING, by design: a U-mode sp is untrusted, software uses mscratch):
#   s0  expected mepc for the trap under test
#   s1  resume witness (written by the instruction at mepc+4)
#   s2  handler address
#   s3  trap counter (handler increments; the main flow checks it)
#   s4  mcause captured in the handler
#   s5  mepc   captured in the handler
#   s6  mstatus captured INSIDE the trap (the pushed state)
#   s7  mtval  captured in the handler
#   t5  handler scratch (never live across a trap in the main flow)
#   t4  CHECK ID at every comparison — a FAIL is localisable from a0/t4 alone
#
# BUILD-TIME DISPATCH (privcsr / extjvt idiom): ON iff -DCORE_ENABLE_TRAPCSR is
# appended to RISCV_GCC_OPTS on a staged trapCsr build. The #else arm FAILs
# immediately and loudly — privecall is deliberately NOT in the default
# behavioral_mp runner array, so that arm must never execute.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

# P2 COMPATIBILITY (2026-07-28): mstatus.MPP is WARL {11} on a trapCsr-only
# build (any write stores 11) but WARL {00,11} once U-mode exists — where a
# written 00 stays 00 AND **MRET forces MPP<-00**. P_MPP0 is the MPP field as
# it reads after writing 0 to mstatus and, identically, after an MRET, so this
# file is a valid gate on BOTH ON flavours. The value captured INSIDE a trap is
# unaffected (trap entry sets MPP<-priv, and this test only ever traps from M).
#ifdef CORE_ENABLE_UMODE
#define P_MPP0  0x00000000
#else
#define P_MPP0  0x00001800
#endif

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity: prove the core runs before any trap work ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, pecl_fail

#ifdef CORE_ENABLE_TRAPCSR

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0                 # valid sp (standard mode never pushes; set
                                    # anyway so the file matches suite convention)
    li   s3, 0                      # trap counter

    # =====================================================================
    # CHECK 1 — arm mtvec BEFORE opting into standard delivery. Order is the
    # contract: a trap taken with mtvec still 0 would vector to address 0.
    # =====================================================================
    li   t4, 1
    la   s2, pecl_handler
    csrw 0x305, s2
    csrr t2, 0x305
    bne  t2, s2, pecl_fail          # handler is .align 2 -> MODE WARL 00 is a no-op

    # ---- CHECK 2: mstatus.MIE = 1, mie = 0 (no source can possibly fire) ----
    li   t4, 2
    li   t1, 0x00000008
    csrw 0x300, t1
    csrw 0x304, x0
    csrr t2, 0x300
    li   t3, (P_MPP0|0x00000008)    # MPP field | MIE
    bne  t2, t3, pecl_fail

    # ---- CHECK 3: opt into STANDARD delivery (mtrapctl.LEGACY = 0) ----
    li   t4, 3
    csrw 0x7C0, x0
    csrr t2, 0x7C0
    bne  t2, x0, pecl_fail

    # =====================================================================
    # ECALL ROUND TRIP 1 — CHECK 4..10
    # =====================================================================
    la   s0, pecl_ecall1
    li   s1, 0
pecl_ecall1:
    ecall
    li   s1, 0x000000A5             # resume MUST land exactly here (mepc+4)

    li   t4, 4                      # a trap was actually delivered
    li   t3, 1
    bne  s3, t3, pecl_fail

    li   t4, 5                      # mcause == 11 (ecall from M)
    li   t3, 11
    bne  s4, t3, pecl_fail

    li   t4, 6                      # mepc == the ECALL's OWN pc
    bne  s5, s0, pecl_fail

    li   t4, 7                      # inside the trap: MPIE<=MIE(1), MIE<=0
    li   t3, 0x00001880
    bne  s6, t3, pecl_fail

    li   t4, 8                      # mtval == 0 for an ECALL
    bne  s7, x0, pecl_fail

    li   t4, 9                      # execution resumed at ECALL+4
    li   t3, 0x000000A5
    bne  s1, t3, pecl_fail

    li   t4, 10                     # MRET popped: MIE<=MPIE(1), MPIE<=1
    csrr t2, 0x300                  # (U-mode build: MRET also forces MPP<-00)
    li   t3, (P_MPP0|0x00000088)
    bne  t2, t3, pecl_fail

    # =====================================================================
    # ECALL ROUND TRIP 2 — CHECK 11..15. THE STACK RE-ARM PROOF.
    # =====================================================================
    la   s0, pecl_ecall2
    li   s1, 0
pecl_ecall2:
    ecall
    li   s1, 0x0000005A

    li   t4, 11
    li   t3, 2
    bne  s3, t3, pecl_fail

    li   t4, 12
    li   t3, 11
    bne  s4, t3, pecl_fail

    li   t4, 13
    bne  s5, s0, pecl_fail

    li   t4, 14                     # MIE was 1 again on entry => MPIE pushed 1
    li   t3, 0x00001880
    bne  s6, t3, pecl_fail

    li   t4, 15
    csrr t2, 0x300
    li   t3, (P_MPP0|0x00000088)
    bne  t2, t3, pecl_fail

    li   t4, 16
    li   t3, 0x0000005A
    bne  s1, t3, pecl_fail

    # =====================================================================
    # EBREAK — CHECK 17..20. mcause 3, mtval 0 (p0_specs.md 2.2 chose 0).
    # =====================================================================
    la   s0, pecl_ebreak1
    li   s1, 0
pecl_ebreak1:
    ebreak
    li   s1, 0x000000E7

    li   t4, 17
    li   t3, 3
    bne  s3, t3, pecl_fail

    li   t4, 18
    li   t3, 3
    bne  s4, t3, pecl_fail

    li   t4, 19
    bne  s5, s0, pecl_fail

    li   t4, 20
    bne  s7, x0, pecl_fail          # mtval == 0

    li   t4, 21
    li   t3, 0x000000E7
    bne  s1, t3, pecl_fail

    # =====================================================================
    # ILLEGAL INSTRUCTION — CHECK 22..25. mcause 2, mtval = the ENCODING.
    # 0x0000007F is opcode "1111111", which is in no valid_opcode arm, so it
    # is an illegal instruction on EVERY build of this core. Its low two bits
    # are "11", so it is fetched and decoded as a full 32-bit word.
    # =====================================================================
    la   s0, pecl_illegal1
    li   s1, 0
pecl_illegal1:
    .word 0x0000007F
    li   s1, 0x0000001E

    li   t4, 22
    li   t3, 4
    bne  s3, t3, pecl_fail

    li   t4, 23
    li   t3, 2
    bne  s4, t3, pecl_fail

    li   t4, 24
    bne  s5, s0, pecl_fail

    li   t4, 25                     # mtval == the faulting 32-bit encoding
    li   t3, 0x0000007F
    bne  s7, t3, pecl_fail

    li   t4, 26
    li   t3, 0x0000001E
    bne  s1, t3, pecl_fail

    # =====================================================================
    # RESTORE: back to LEGACY delivery and a quiet mstatus/mie, so an ON
    # build running the rest of the suite is provably unaffected.
    # =====================================================================
    li   t4, 27
    li   t1, 0x00000001
    csrw 0x7C0, t1
    csrw 0x300, x0
    csrw 0x304, x0
    csrr t2, 0x7C0
    li   t3, 0x00000001
    bne  t2, t3, pecl_fail
    csrr t2, 0x304
    bne  t2, x0, pecl_fail

    RVTEST_PASS

    # =====================================================================
    # The mtvec handler. Placed AFTER the RVTEST_PASS spin loop, so it can
    # only ever be reached by a hardware trap — never by fall-through.
    # Every trap this test takes is a 4-byte EXCEPTION, so the handler
    # advances mepc by 4 before MRET (the standard "return past the faulting
    # instruction" idiom). privirq's handler deliberately does NOT.
    # =====================================================================
    .align 2
pecl_handler:
    csrr s4, 0x342                  # mcause
    csrr s5, 0x341                  # mepc
    csrr s6, 0x300                  # mstatus AS PUSHED (MPIE<=old MIE, MIE=0)
    csrr s7, 0x343                  # mtval
    addi s3, s3, 1
    addi t5, s5, 4
    csrw 0x341, t5
    mret

    .option pop

#else
    # OFF build: ECALL/EBREAK/MRET are illegal instructions and the ten P1 CSR
    # addresses are unknown CSRs — this core DEAD-ENDS an illegal instruction in
    # the terminal TRAP_STATE, so none of the above may be assembled. Reaching
    # here means the ON/OFF staging discipline was violated.
    li   t4, 0
    j    pecl_fail
#endif

pecl_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF (t4 = failing check id)

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
