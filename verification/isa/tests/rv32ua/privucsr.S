# See LICENSE for license details.

#*****************************************************************************
# privucsr.S   (P2 U-mode — the PRIVILEGED-ACCESS POISON SWEEP)
#-----------------------------------------------------------------------------
# ON-ONLY DIRECTED TEST (needs a trapCsr+umode build). privumode proves the
# privilege ROUND TRIP; this file proves the U-mode DECODE GATE in maindec —
# every privileged thing a U-mode program can reach must take the
# illegal-instruction trap (mcause 2) at its OWN pc, per
# ~/vesta_docs/priv_arch/p0_specs.md §3 / §3.1:
#
#   csr_addr(9:8) /= "00"   ONE comparator covering every machine (0x3xx/0xBxx/
#                           0xFxx) and custom (0x7C0 mtrapctl) CSR — reads AND
#                           writes.                    [negctrl (b) p2_privgate]
#   MRET                    M-mode only
#   iret / extinguish / ignite   the three CUSTOM Vesta insns are PRIVILEGED
#                           (they drive the legacy irq_handler handshake and the
#                           sleep state directly) — the whole custom opcode traps
#   WFI with mstatus.TW=1   the trap-on-wait rule, a DECODE illegal
#                                                      [negctrl (c) p2_twignore]
#   mcounteren gating       cycle/time/instret/hpmcounter3-4 trap in U unless the
#                           matching enable bit is set; with the bit set the read
#                           SUCCEEDS
#
# THE PROTOCOL. U-mode cannot read mcause/mepc (that is the point), so the
# M-mode handler does the verifying: it requires mcause 2 and mepc == s0 (the
# poison's own address, published by the U code just before executing it),
# increments the trap counter s3, then skips the 4-byte poison (mepc+4) and
# MRETs back into U. The U code carries its OWN expected count in s11 and
# compares s3 against it after every poison, so a poison that FAILS TO TRAP is
# caught IMMEDIATELY, in U, by a bounded compare-and-branch — never by a hang.
# A U-mode ECALL (mcause 8) is the "give me M-mode back" request: the handler
# leaves the trap with `jr s9` into the M-mode flow instead of MRETing.
#
# BOUNDEDNESS OF THE WFI POISON. Before the TW phase the test arms mie.MSIE and
# raises CLINT msip[0], so (mip and mie) /= 0 holds. If TW were IGNORED (the
# p2_twignore seed) the WFI would be legal, enter SLEEPING, and wake IMMEDIATELY
# on that pending source (mstatus.MIE stays 0, so nothing is delivered) — it
# resumes at WFI+4, lands on the count check, and FAILs. It can never hang.
#
# REGISTER CONTRACT (standard mode pushes NOTHING; M and U share the regfile):
#   s0   the poison's own address — published by the U code, checked as mepc
#   s3   poison-trap counter (handler increments; U and M both read it)
#   s5   rdcycle      result from the ENABLED-counter phase
#   s6   hpmcounter3  result from the ENABLED-counter phase
#   s7   trap-count snapshot around the must-NOT-trap counter reads
#   s8   CLINT msip[hart 0] address
#   s9   M-mode continuation address (handler `jr s9` on a U ECALL)
#   s11  the U code's EXPECTED trap count
#   t3/t5/t6  handler scratch;  t4  CHECK ID at every comparison
#
# BUILD-TIME DISPATCH: ON iff BOTH -DCORE_ENABLE_TRAPCSR and -DCORE_ENABLE_UMODE
# are appended to RISCV_GCC_OPTS on a staged trapCsr+umode build. privucsr is
# deliberately NOT in the default behavioral_mp runner array, so the #else arm
# must never execute.
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
    bne  t2, t3, pucs_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0                      # poison-trap counter
    li   s11, 0                     # the U code's expected count
    li   s8, 0x00005000             # CLINT msip[hart 0]

    # =====================================================================
    # M SETUP — CHECK 1..4
    # =====================================================================
    li   t4, 1                      # mcounteren RESETS to 0 (P2 makes it real)
    csrr t2, 0x306
    bne  t2, x0, pucs_fail

    li   t4, 2                      # arm mtvec BEFORE opting into standard mode
    la   t0, pucs_handler
    csrw 0x305, t0
    csrr t2, 0x305
    bne  t2, t0, pucs_fail

    li   t4, 3                      # STANDARD delivery (mtrapctl.LEGACY = 0)
    csrw 0x7C0, x0
    csrr t2, 0x7C0
    bne  t2, x0, pucs_fail

    li   t4, 4                      # quiet machine state: MIE=0, MPP=00, TW=0
    csrw 0x300, x0
    csrw 0x304, x0
    csrr t2, 0x300
    bne  t2, x0, pucs_fail

    li   t4, 5                      # mscratch SENTINEL. POISON 3 below is a
    li   t1, 0x5A5A5A5A             #   U-mode `csrw mscratch, x0`: it must trap
    csrw 0x340, t1                  #   AND commit NOTHING. csr_valid is
    csrr t2, 0x340                  #   csr_unit's write enable, so a bare
    bne  t2, t1, pucs_fail          #   is_csr_instr there lets the trapping
                                    #   write through — a full escape (the same
                                    #   hole would let U rewrite mtvec/mtrapctl).
                                    #   CHECK 27 reads the sentinel back.

#ifdef CORE_ENABLE_PMP
    # =====================================================================
    # P3 PMP PROLOGUE (2026-07-29). With PMP implemented, a U-mode access
    # matching NO entry FAULTS (spec + frozen §4 no-match rule) — on a pmp
    # build the very first U-mode instruction fetch below would take an
    # instruction access fault (cause 1) into the handler and derail every
    # check. Grant U R|W|X over 0x0-0xFFFF (TOR entry 1, base = pmpaddr0 = 0;
    # entries 2-15 left free, nothing locked) BEFORE entering U. On the
    # trapCsr+umode polarity this block is not assembled and the file
    # behaves exactly as it did at P2.
    # =====================================================================
    csrw 0x3B0, x0                  # pmpaddr0 = 0 : entry 1's TOR base
    li   t0, 0x00010000
    srli t0, t0, 2                  # word address of the TOR top
    csrw 0x3B1, t0                  # pmpaddr1 = 0x10000 >> 2
    li   t0, 0x00000F00             # cfg1 = TOR|X|W|R, cfg0 = OFF
    csrw 0x3A0, t0
#endif

    # =====================================================================
    # PHASE 1 — enter U with TW=0 and mcounteren all-zero, and run the nine
    # poisons. CHECK ids 10..18 are set IN U, one per poison.
    # =====================================================================
    la   s9, pucs_m1
    la   t0, pucs_u1
    csrw 0x341, t0
    mret                            # ---- U-MODE ----

pucs_u1:
    li   t4, 10                     # POISON 1: read a MACHINE CSR (mstatus)
    addi s11, s11, 1
    la   s0, pucs_p1
pucs_p1:
    csrr t0, 0x300
    bne  s3, s11, pucs_fail

    li   t4, 11                     # POISON 2: read the CUSTOM CSR (mtrapctl)
    addi s11, s11, 1
    la   s0, pucs_p2
pucs_p2:
    csrr t0, 0x7C0
    bne  s3, s11, pucs_fail

    li   t4, 12                     # POISON 3: WRITE a machine CSR (mscratch)
    addi s11, s11, 1
    la   s0, pucs_p3
pucs_p3:
    csrw 0x340, x0
    bne  s3, s11, pucs_fail

    li   t4, 13                     # POISON 4: MRET in U (0x30200073)
    addi s11, s11, 1
    la   s0, pucs_p4
pucs_p4:
    .word 0x30200073
    bne  s3, s11, pucs_fail

    li   t4, 14                     # POISON 5: iret (custom opcode 0x0B)
    addi s11, s11, 1
    la   s0, pucs_p5
pucs_p5:
    iret
    bne  s3, s11, pucs_fail

    li   t4, 15                     # POISON 6: extinguish
    addi s11, s11, 1
    la   s0, pucs_p6
pucs_p6:
    extinguish
    bne  s3, s11, pucs_fail

    li   t4, 16                     # POISON 7: ignite
    addi s11, s11, 1
    la   s0, pucs_p7
pucs_p7:
    ignite
    bne  s3, s11, pucs_fail

    li   t4, 17                     # POISON 8: rdcycle with mcounteren.CY = 0
    addi s11, s11, 1
    la   s0, pucs_p8
pucs_p8:
    csrr t0, 0xC00
    bne  s3, s11, pucs_fail

    li   t4, 18                     # POISON 9: hpmcounter3 with HPM3 = 0
    addi s11, s11, 1
    la   s0, pucs_p9
pucs_p9:
    csrr t0, 0xC03
    bne  s3, s11, pucs_fail

    ecall                           # -> M (mcause 8): the handler does `jr s9`

    # =====================================================================
    # PHASE 2 (M) — CHECK 20..26. Count the poisons, prove mcounteren's WARL
    # shape, enable CY + HPM3, and arm the pending source that keeps the WFI
    # poison bounded.
    # =====================================================================
pucs_m1:
    li   t4, 20                     # exactly nine poisons trapped
    li   t3, 9
    bne  s3, t3, pucs_fail

    li   t4, 27                     # THE SIDE-EFFECT PROOF: the U-mode
    csrr t2, 0x340                  #   `csrw mscratch, x0` of POISON 3 trapped
    li   t3, 0x5A5A5A5A             #   AND left mscratch untouched. A trapping
    bne  t2, t3, pucs_fail          #   instruction must commit nothing.

    li   t4, 21                     # mcounteren WARL: only bits 4:0 have storage
    li   t1, 0xFFFFFFFF
    csrw 0x306, t1
    csrr t2, 0x306
    li   t3, 0x0000001F
    bne  t2, t3, pucs_fail

    li   t4, 22
    csrw 0x306, x0
    csrr t2, 0x306
    bne  t2, x0, pucs_fail

    li   t4, 23                     # enable CY(0) and HPM3(3) ONLY — TM stays 0
    li   t1, 0x00000009
    csrw 0x306, t1
    csrr t2, 0x306
    bne  t2, t1, pucs_fail

    li   t4, 24                     # arm mie.MSIE and raise CLINT msip[0]
    li   t1, 0x00000008
    csrw 0x304, t1
    li   t1, 1
    sw   t1, 0(s8)
    li   t2, 4096                   # bounded (~1 ms class) — the level crosses
pucs_wait_mip:                      #   the registered tile boundary
    csrr t0, 0x344
    andi t0, t0, 0x8
    bnez t0, pucs_armed
    addi t2, t2, -1
    bnez t2, pucs_wait_mip
    j    pucs_fail                  # mip never mirrored msip
pucs_armed:

    li   t4, 25                     # mstatus.TW = 1 (and MPP=00, MIE=0)
    li   t1, 0x00200000
    csrw 0x300, t1
    csrr t2, 0x300
    li   t3, 0x00200000
    bne  t2, t3, pucs_fail

    # =====================================================================
    # PHASE 3 — back to U with CY|HPM3 enabled and TW=1.
    # =====================================================================
    li   t4, 26
    la   s9, pucs_m2
    la   t0, pucs_u2
    csrw 0x341, t0
    mret                            # ---- U-MODE, TW=1 ----

pucs_u2:
    li   t4, 30                     # the ENABLED counters must NOT trap
    mv   s7, s3
    csrr s5, 0xC00                  # rdcycle    (mcounteren.CY  = 1)
    csrr s6, 0xC03                  # hpmcounter3 (mcounteren.HPM3 = 1)
    bne  s3, s7, pucs_fail          # any trap here => the enable was ignored

    li   t4, 31                     # and rdcycle really returned a live counter
    beqz s5, pucs_fail

    li   t4, 32                     # POISON 10: time, with TM still 0
    addi s11, s11, 1
    la   s0, pucs_p10
pucs_p10:
    csrr t0, 0xC01
    bne  s3, s11, pucs_fail

    li   t4, 33                     # POISON 11: WFI with mstatus.TW = 1
    addi s11, s11, 1
    la   s0, pucs_p11
pucs_p11:
    .word 0x10500073
    bne  s3, s11, pucs_fail         # TW ignored => WFI woke on the armed msip
                                    #   and fell through here with s3 unchanged

    ecall                           # -> M

    # =====================================================================
    # PHASE 4 (M) — CHECK 40..43. Count, then RESTORE: clear the source
    # FIRST, then mie/TW/mcounteren, and only THEN go back to LEGACY delivery
    # (re-enabling the legacy irq_handler with msip still high would vector
    # through IVT slot 83, which a plain rv32ua image does not populate).
    # =====================================================================
pucs_m2:
    li   t4, 40
    li   t3, 11
    bne  s3, t3, pucs_fail

    li   t4, 41
    sw   x0, 0(s8)
    li   t2, 4096
pucs_wait_clr:
    csrr t0, 0x344
    andi t0, t0, 0x8
    beqz t0, pucs_quiet
    addi t2, t2, -1
    bnez t2, pucs_wait_clr
    j    pucs_fail                  # msip never cleared
pucs_quiet:
    csrw 0x304, x0                  # mie = 0
    csrw 0x300, x0                  # mstatus = 0 (clears TW)
    csrw 0x306, x0                  # mcounteren = 0
    li   t1, 0x00000001
    csrw 0x7C0, t1                  # back to LEGACY delivery

    li   t4, 42
    csrr t2, 0x7C0
    li   t3, 0x00000001
    bne  t2, t3, pucs_fail
    csrr t2, 0x304
    bne  t2, x0, pucs_fail

    li   t4, 43
    csrr t2, 0x306
    bne  t2, x0, pucs_fail

    RVTEST_PASS

    # =====================================================================
    # The mtvec handler. Placed AFTER the RVTEST_PASS spin loop, so it can
    # only ever be reached by a hardware trap. It is the VERIFIER: U-mode
    # cannot read mcause/mepc, so every poison's cause and pc are checked
    # here, in M. A mismatch jumps straight into RVTEST_FAIL (bounded).
    # =====================================================================
    .align 2
pucs_handler:
    csrr t5, 0x342                  # mcause
    csrr t6, 0x341                  # mepc
    li   t3, 8
    beq  t5, t3, pucs_to_m          # ECALL from U = "give me M-mode back"
    li   t3, 2                      # every poison must be illegal-instruction
    bne  t5, t3, pucs_fail
    bne  t6, s0, pucs_fail          # ... taken at the poison's OWN pc
    addi s3, s3, 1
    addi t6, t6, 4                  # skip the 4-byte poison
    csrw 0x341, t6
    mret                            # back to U (MPP was pushed 00)
pucs_to_m:
    jr   s9

    .option pop

#else
    # OFF / trapCsr-only build: U-mode does not exist, so none of the above may
    # be assembled. Reaching here means the ON/OFF staging discipline was
    # violated.
    li   t4, 0
    j    pucs_fail
#endif

pucs_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF (t4 = failing check id)

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
