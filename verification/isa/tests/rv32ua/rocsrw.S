# See LICENSE for license details.

# VestaRV: a write form aimed at a read-only CSR must trap
# THE RULE: csr_addr[11:10] == "11" means the CSR is READ-ONLY, and any instruction that ATTEMPTS to write it raises illegal-instruction, regardless of whether the CSR exists or of what the value would be. Everything below that quadrant is writable, and a WARL implementation that ignores the written bits there is legal and must NOT trap.
# WHERE THE RTL LOSES IT: maindec's csr_addr_valid is a pure ADDRESS-KNOWN map with no reference to csr_op or the rs1/uimm field, and it admits mhartid, cycle, time, instret and the whole user hpmcounter range, all read-only quadrant; the SYSTEM arm then sets valid_funct from csr_addr_valid, so the write form never trips it, and csr_valid is equally blind. csr_unit ALREADY DECODES THE WRITE FORM EXACTLY PER SPEC and uses it only as a store strobe, and the read-only addresses are absent from csr_addr_stores, so the net effect is a silent nop.
# THE POLARITY TRAP THIS FILE IS BUILT AROUND: with the defect the illegal write is a nop and a test runs straight past it, while with it fixed the write TRAPS, and on a default build a trap lands in the TERMINAL TRAP_STATE, so the hart wedges, never writes a0, and the run dies on the watchdog. A naive detector is therefore green before and hung after: backwards and useless. THIS FILE RUNS ON A KNOBS-ON BUILD WHERE THE TRAP IS RECOVERABLE, so both polarities report a0 and the architectural claim can be asserted; the sibling rocsrwmp.S covers the default build with an observer hart.
# ON-ONLY: it needs a staged trapCsr build AND -DCORE_ENABLE_TRAPCSR on the compile options; the other arm fails loudly. NOT IN THE STANDING RUNNER ARRAY; do not add it.
# STRUCTURE: every leg is a raw .word so gas cannot rewrite it, and each encoding was cross-checked against the assembler. The handler RESUMES at mepc+4, so a leg that traps and a leg that retires both continue at the very next instruction and are told apart ONLY by the trap counter, which no witness register can fool. C0 is the positive control in both polarities, `.word 0x0000007F`, an opcode absent from valid_opcode on every build, which proves the handler, the counter, the resume and the mcause, mepc and mtval plumbing are live before any claim is made.
# THE NEGATIVE HALF is nine encodings that must NOT trap, ever: a read of mhartid; csrrsi on cycle with uimm field 0 and csrrci on mhartid with uimm field 0, neither of which is a write; csrw to mhpmevent3, mcountinhibit, mhpmcounter3, mhpmcounter5 and misa, all in the writable quadrant or WARL-ignore; and csrw to mip, whose csr_unit write arm is `null` so it drops exactly as a read-only CSR does, WHICH IS THE OVER-REACH GATE. Three of them are verbatim from the writes the Zihpm probe executes on its default path, so their passing is the proof that a correctly scoped fix cannot move the suite floor.
# THE POSITIVE HALF is five write forms at read-only addresses: `csrw mhartid, t0`; `csrrs t1, cycle, t0` with a nonzero rs1 field; `csrwi time, 0`, WHICH A FIX KEYED ONLY ON "rs1 FIELD NONZERO" MISSES, because CSRRW and CSRRWI always write; `csrci cycle, 1` with a nonzero uimm field; and `unimp` itself, which is csrrw x0, cycle, x0 and has always been claimed to trap while today it is a silent nop. A sixth leg re-reads mhartid after the first and requires it unchanged, and THE TOTAL TRAP COUNT MUST BE EXACTLY SIX, which an over-reaching fix cannot satisfy even if it passed every negative leg.
# Verdicts: a0 = 0xCAFEBABE means the behaviour is correct and correctly scoped. a1 = 0xF10F0n00 leg Ln did not trap, the finding; 0xF10F0n01 it trapped with the wrong mcause; 0xF10F0n02 with the wrong mepc; 0xF10F0n03 with the wrong mtval; 0xF10F0600 the first write COMMITTED, so a trap left a side effect; 0x0BAD0n01 negative leg Nn trapped, so the fix over-reaches; 0x0BAD0n02 negative leg Nn returned the wrong value; 0x5E100001 the positive control did not trap, so the harness is dead and nothing else in this file means anything; 0x5E100002 the wrong total trap count; 0x5E100003 an mtvec or mtrapctl precondition failed; 0x5E10BAD0 built on the wrong polarity. Registers live at the verdict: s3 the trap count and s4, s5 and s7 the last mcause, mepc and mtval. No shared words are claimed: single hart, TCM and CSRs only.

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
