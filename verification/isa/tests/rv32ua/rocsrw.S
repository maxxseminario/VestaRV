# See LICENSE for license details.

#*****************************************************************************
# rocsrw.S   (F-series fix pass, wave W5 -- the ARCHITECTURAL DETECTOR for F10)
#-----------------------------------------------------------------------------
# F10: a WRITE FORM aimed at a READ-ONLY CSR is accepted and silently dropped.
#
# THE RULE (RISC-V unprivileged spec, CSR address map):
#     csr_addr[11:10] == "11"  =>  the CSR is READ-ONLY.  Any instruction that
#     ATTEMPTS to write it raises an illegal-instruction exception, regardless
#     of whether the CSR exists or of what the write value would be.
# Everything BELOW that quadrant is writable; a WARL implementation that
# ignores the written bits there is LEGAL and must NOT trap.
#
# WHERE THE RTL LOSES IT (re-grepped at 703d42a; every doc line number is stale)
#     maindec.vhd:381-419  csr_addr_valid -- a pure ADDRESS-KNOWN map.  It
#                          admits CSR_MHARTID (0xF14), CSR_CYCLE/TIME/INSTRET
#                          (0xC00/01/02) and the whole hpmcounter user range
#                          (0xC03-0xC1F, 0xC83-0xC9F) -- all of them read-only
#                          quadrant -- with NO reference to csr_op or to the
#                          rs1/uimm field.
#     maindec.vhd:790-795  the SYSTEM/is_csr_instr arm reads, in full:
#                          "if u_csr_denied = '1' then valid_funct <= '0';" and
#                          otherwise "valid_funct <= csr_addr_valid;".
#                          So for a KNOWN read-only address valid_funct is '1'
#                          and trap stays '0' -- the write form never trips it.
#     maindec.vhd:501      csr_valid <= is_csr_instr and csr_addr_valid and
#                                       (not u_csr_denied)      -- also blind
#                                       to the write form.
#     csr_unit.vhd:456     csr_write_en <= csr_valid when
#                              (csr_op(1 downto 0) = "01" or csr_rs1_zero = '0')
#                          THE WRITE FORM IS ALREADY DECODED HERE, EXACTLY per
#                          spec -- and it is used only as a store strobe.
#     csr_unit.vhd:381-408 csr_addr_stores() -- 0xF14/0xC00/0xC01/... are not
#                          in it, so csr_commit_we (:1195) stays low.
#     NET EFFECT: write form + read-only address = a silent NOP.
#
# THE POLARITY TRAP THIS FILE IS BUILT AROUND
#     Pre-fix the illegal write is a NOP, so a test runs straight past it.
#     Post-fix it TRAPS -- and on a DEFAULT build a trap lands in the TERMINAL
#     TRAP_STATE (self-loop, no handler, no exit), so the hart wedges, never
#     writes a0, and the run dies on the tb watchdog.  A naive detector is
#     therefore GREEN pre-fix and HUNG post-fix: backwards and useless.
#     THIS file dodges that by running on a KNOBS-ON build where the trap is
#     RECOVERABLE, so both polarities report a0 and the real architectural
#     claim (mcause/mepc/mtval) can be asserted.  Its sibling rocsrwmp.S
#     covers the DEFAULT build with an observer hart.
#
# ON-ONLY.  Requires a trapCsr staged build (CORE_ENABLE_TRAPCSR true in the
#     flow's MemoryMap copy -- xcelium/riscv_test/behavioral_mp_umode) AND
#     -DCORE_ENABLE_TRAPCSR on RISCV_GCC_OPTS.  The other arm FAILs loudly.
#     NOT in the standing TEST_FILES array; do not add it.
#
# ---------------------------------------------------------------------------
# STRUCTURE.  Every leg is a raw .word so gas cannot rewrite it; each encoding
# was cross-checked against riscv-none-elf-as (all 14 matched hand assembly).
# The handler is RESUMING (mepc+4, mret), so a leg that traps and a leg that
# retires both continue at the very next instruction and are told apart ONLY
# by the trap COUNTER -- no witness register can be fooled by the resume.
#
#   C0  POSITIVE CONTROL, both polarities: .word 0x0000007F, an opcode absent
#       from maindec's valid_opcode list on every build.  It proves the mtvec
#       handler, the counter, the mepc+4 resume AND the mcause/mepc/mtval
#       plumbing are live BEFORE any F10 claim is made.  A pre-fix run that
#       reaches the negatives has therefore validated its own instrument.
#
#   N1-N9  THE NEGATIVE HALF -- nine encodings that must NOT trap, ever.
#       N1  f14022f3  csrr t0, mhartid        read of a READ-ONLY CSR
#       N2  c0006373  csrrsi t1, cycle, 0     uimm FIELD 0 => not a write
#       N3  f14073f3  csrrci t2, mhartid, 0   uimm FIELD 0 => not a write
#       N4  32329073  csrw mhpmevent3, t0     0x323, WRITABLE quadrant
#       N5  34429073  csrw mip, t0            0x344, WRITABLE quadrant, and its
#                                             csr_unit write arm is `null`, so
#                                             it drops exactly like a read-only
#                                             CSR does.  THE OVER-REACH GATE.
#       N6  32029073  csrw mcountinhibit, t0  0x320, WARL-ignore (ZIHPM off)
#       N7  b0301073  csrw mhpmcounter3, x0   0xB03, WRITABLE quadrant
#       N8  b0501073  csrw mhpmcounter5, x0   0xB05, dropped in BOTH ZIHPM
#                                             polarities -- still not F10
#       N9  30129073  csrw misa, t0           0x301, WARL-ignore
#       N4/N7/N8 are VERBATIM three of the nine writes rv32ua-p-extzihpm
#       executes on its default path.  Their passing IS the proof that the
#       correctly-scoped F10 cannot move the 136/136 suite floor.
#
#   L1-L5  THE POSITIVE HALF -- five write forms at read-only addresses.
#       L1  f1429073  csrw mhartid, t0        CSRRW, rs1 = t0
#       L2  c002a373  csrrs t1, cycle, t0     CSRRS with rs1 FIELD nonzero
#       L3  c0105073  csrwi time, 0           CSRRWI with uimm = 0: CSRRW*
#                                             ALWAYS writes.  A fix that keys
#                                             only on "rs1 field nonzero"
#                                             MISSES THIS ONE.
#       L4  c000f073  csrci cycle, 1          CSRRCI, uimm field nonzero
#       L5  c0001073  `unimp` itself = csrrw x0, cycle, x0.  CLAUDE.md has
#                                             always claimed unimp traps; today
#                                             it is a silent NOP.  This leg is
#                                             that claim, made testable.
#
#   L6  NO SIDE EFFECT: mhartid re-read after L1 must still be 0.
#   TOTAL TRAP COUNT must be exactly 6 (C0 + L1-L5).  An over-reaching fix
#   cannot satisfy that even if it somehow passed every negative leg.
#
# ---------------------------------------------------------------------------
# VERDICT CODES.  a0 = 0xCAFEBABE  =>  F10 is FIXED and correctly scoped.
# ---------------------------------------------------------------------------
#   a1 = 0xF10F0n00   leg Ln did NOT trap  <-- THE FINDING, pre-fix value
#   a1 = 0xF10F0n01   leg Ln trapped with mcause /= 2
#   a1 = 0xF10F0n02   leg Ln trapped with mepc /= the faulting pc
#   a1 = 0xF10F0n03   leg Ln trapped with mtval /= the faulting instruction
#   a1 = 0xF10F0600   L1 COMMITTED: mhartid changed -- a trap left a side effect
#   a1 = 0x0BAD0n01   negative leg Nn TRAPPED -- THE FIX OVER-REACHES
#   a1 = 0x0BAD0n02   negative leg Nn returned the wrong value
#   a1 = 0x5E100001   C0 positive control did not trap: the harness is dead,
#                     nothing else in this file means anything
#   a1 = 0x5E100002   wrong total trap count
#   a1 = 0x5E100003   an mtvec / mtrapctl precondition failed
#   a1 = 0x5E10BAD0   built on the wrong polarity
#
# Registers live at the verdict: s3 trap count, s4/s5/s7 last mcause/mepc/mtval.
#
# SHARED WORDS CLAIMED: NONE.  Single hart, TCM and CSRs only.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # base-ISA sanity: prove the core runs before any privilege work
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, roc_fail

#if defined(CORE_ENABLE_TRAPCSR)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0                      # trap counter
    li   s6, 0x5A5A5A5A             # a distinctive write source, never 0

    # ------------------------------------------------------------------
    # arm mtvec, then opt into STANDARD delivery (privumode's frozen order)
    # ------------------------------------------------------------------
    li   a1, 0x5E100003
    la   t0, roc_handler
    csrw 0x305, t0
    csrr t1, 0x305
    bne  t1, t0, roc_fail
    csrw 0x7C0, x0                  # mtrapctl.LEGACY = 0 -> standard delivery
    csrr t1, 0x7C0
    bnez t1, roc_fail

    # ==================================================================
    # A leg that MUST trap: cause 2, mepc = its own pc, mtval = its own word.
    # ==================================================================
    .macro ROC_TRAPS enc, code
    mv   s1, s3                     # trap count before the leg
    la   s0, 8f                     # the leg's own pc
8:  .word \enc
    li   a1, \code
    beq  s3, s1, roc_fail           # it did NOT trap
    li   t3, 2
    addi a1, a1, 1
    bne  s4, t3, roc_fail           # mcause must be 2 (illegal instruction)
    addi a1, a1, 1
    bne  s5, s0, roc_fail           # mepc must be the faulting pc
    addi a1, a1, 1
    lw   t4, 0(s0)                  # the faulting word, read back from TCM
    bne  s7, t4, roc_fail           # mtval must be the faulting instruction
    .endm

    # ==================================================================
    # A leg that MUST NOT trap.
    # ==================================================================
    .macro ROC_OK enc, code
    mv   s1, s3
    .word \enc
    li   a1, \code
    bne  s3, s1, roc_fail           # it TRAPPED -- the fix over-reaches
    .endm

    # ==================================================================
    # C0 -- POSITIVE CONTROL.  Validates the instrument on BOTH polarities.
    # ==================================================================
    ROC_TRAPS 0x0000007F, 0x5E100001

    # ==================================================================
    # THE NEGATIVE HALF.  All nine must be silent on both polarities.
    # ==================================================================
    mv   t0, s6
    ROC_OK  0xF14022F3, 0x0BAD0101      # N1  csrr t0, mhartid
    li   a1, 0x0BAD0102
    bnez t0, roc_fail                   #     hart 0 -> mhartid must read 0

    ROC_OK  0xC0006373, 0x0BAD0201      # N2  csrrsi t1, cycle, 0
    li   a1, 0x0BAD0202
    beqz t1, roc_fail                   #     cycle must be counting

    mv   t2, s6
    ROC_OK  0xF14073F3, 0x0BAD0301      # N3  csrrci t2, mhartid, 0
    li   a1, 0x0BAD0302
    bnez t2, roc_fail

    mv   t0, s6
    ROC_OK  0x32329073, 0x0BAD0401      # N4  csrw mhpmevent3, t0   (extzihpm)
    mv   t0, s6
    ROC_OK  0x34429073, 0x0BAD0501      # N5  csrw mip, t0   OVER-REACH GATE
    mv   t0, s6
    ROC_OK  0x32029073, 0x0BAD0601      # N6  csrw mcountinhibit, t0
    ROC_OK  0xB0301073, 0x0BAD0701      # N7  csrw mhpmcounter3, x0 (extzihpm)
    ROC_OK  0xB0501073, 0x0BAD0801      # N8  csrw mhpmcounter5, x0 (extzihpm)
    mv   t0, s6
    ROC_OK  0x30129073, 0x0BAD0901      # N9  csrw misa, t0

    # ==================================================================
    # THE POSITIVE HALF.  Every one of these is a write form at [11:10]="11".
    # ==================================================================
    mv   t0, s6
    ROC_TRAPS 0xF1429073, 0xF10F0100    # L1  csrw mhartid, t0
    mv   t0, s6
    ROC_TRAPS 0xC002A373, 0xF10F0200    # L2  csrrs t1, cycle, t0
    ROC_TRAPS 0xC0105073, 0xF10F0300    # L3  csrwi time, 0      (uimm = 0!)
    ROC_TRAPS 0xC000F073, 0xF10F0400    # L4  csrci cycle, 1
    ROC_TRAPS 0xC0001073, 0xF10F0500    # L5  unimp

    # ==================================================================
    # L6 -- a trapping instruction must leave NO architectural side effect.
    # ==================================================================
    li   a1, 0xF10F0600
    csrr t0, 0xF14
    bnez t0, roc_fail

    # ==================================================================
    # THE COUNT.  Exactly six traps: C0 + L1..L5.  Nothing else may fire.
    # ==================================================================
    li   a1, 0x5E100002
    li   t3, 6
    bne  s3, t3, roc_fail

    RVTEST_PASS                     # a0 = 0xCAFEBABE

    .align 2
roc_handler:
    csrr s4, 0x342                  # mcause
    csrr s5, 0x341                  # mepc
    csrr s7, 0x343                  # mtval
    addi s3, s3, 1
    addi t6, s5, 4                  # RESUME past the faulting word (norvc)
    csrw 0x341, t6
    mret

    .option pop

#else
    li   a1, 0x5E10BAD0
    j    roc_fail
#endif

roc_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' in this env -- never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
