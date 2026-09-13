# See LICENSE for license details.

# VestaRV: misaligned fetch with compressed disabled, the SHAPE_Q EXECUTE arm
# SHAPE_Q is the EXECUTE arm below the hoisted PMP one, taken when ENABLE_COMPRESSED is false and pc(1) is set, routing to MTRAP_SV in standard mode and to TRAP_STATE in legacy. Its predicate is statically false wherever ENABLE_COMPRESSED is true, which is every shipped configuration, so nothing executed it until a norvc configuration existed. This file is the stimulus.
# CLAIM 1, ARCHITECTURE: a halfword-aligned PC with C disabled is instruction-address-misaligned, giving cause 0, mtval equal to the misaligned PC, and mepc EQUAL TO THE SAME VALUE WITH BIT 1 CLEARED. THE ASYMMETRY IS THE RTL BEING RIGHT: the FSM sources both from pc and they diverge one stage later in csr_unit's trap-entry writeback, which copies trap_pc(31 downto 2) and then takes bit 1 from trap_pc only when ENABLE_COMPRESSED, otherwise forcing it to 0. That is the RISC-V IALIGN WARL rule, hence the `andi t2, s0, -4` in both checks. A CONSEQUENCE FOR ANY CAUSE-0 HANDLER: mepc points at the word BELOW the faulting address, so an mret straight back to it resumes at an address that was never an instruction boundary. THE TEST MUST CLEAR mtrapctl FIRST, because mtrapctl.LEGACY resets to 1 and the legacy path is the terminal TRAP_STATE, which would make this a watchdog hang rather than a failure.
# CLAIM 2, COMMIT SUPPRESSION: the arm must drive reg_write_dp low and wen all-ones, because an earlier version drove pc_en only and let both fall through to the LIVE DECODE, so the misaligned-fetch trap could commit the faulting encoding's rd and its store lanes on the cycle it trapped. The fetch at an odd halfword reads the WORD that contains it, so the live decode sees a word this file chooses, and each block carries its own known-nonzero control, because a suppression checked only against zero has not been checked. Block A uses word 0x00000093, `addi ra, x0, 0`, whose control executes it at an ALIGNED pc and proves it does write ra, after which the odd-halfword jump must leave ra holding its sentinel. Block B uses word 0x012C2023, `sw s2, 0(s8)`, whose control proves the store lands, after which the odd-halfword jump must leave the scratch word holding its sentinel.
# WHAT THIS FILE DOES NOT PROVE, stated so nobody upgrades it later: that NO transaction was issued. Unchanged ra and unchanged scratch are architectural outcomes, and the bus-level claim belongs to a clocked property. This file proves the arm is entered, that the architectural result is right, and that the two commit paths are suppressed.
# IT IS BOTH-POLARITY BY misa, in the ext* family's idiom, because the catalog tag vocabulary is positive-only and "needs compressed OFF" is unexpressible. On a C-ON build it takes an arm that jumps to an odd halfword holding a real compressed instruction and requires it to EXECUTE, which is the positive control for the same jump machinery on the polarity where the arm must not fire. It is ON-only on trapCsr, since the trap has to be recoverable. Compressed encodings are raw `.half` words so the file stays `.option norvc` and the layout is byte-exact: 0x0001 is c.nop and 0x4485 is `c.li s1, 1`.
# BEWARE: a comment line whose first word after the hash is a preprocessor keyword IS a directive in this tree, which is why RTL quotations here are indented with a leading dot.
# Verdict codes in a1: 0x51000001 the odd-halfword target is not 4n+2, so the layout moved; 0x51000002 an mtvec or mtrapctl precondition failed; 0x51000003 control A did not write ra, so block A's word is not what we think; 0x51000004 control B did not store; 0x5100010n block A, with n = 1 no trap, 2 wrong cause, 3 wrong mepc, 4 wrong mtval, 5 ra WAS COMMITTED; 0x5100020n block B with the same n and 5 meaning the store was committed; 0x51000005 wrong total trap count; 0x510000C1 the C-ON arm's compressed instruction did not execute, so the jump machinery itself is broken; 0x510000C2 the C-ON arm took a trap where none may fire; 0x5E10BAD0 built on the wrong polarity. No shared words are claimed: single hart, TCM and CSRs only.

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
    bne  t2, t3, shq_fail

#if defined(CORE_ENABLE_TRAPCSR)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0                      # trap counter
    li   s10, 0                     # C-ON witness

    # ------------------------------------------------------------------
    # arm mtvec, then opt into STANDARD delivery (the rocsrw/privumode
    # order).  Without the mtrapctl clear every trap below is the TERMINAL
    # TRAP_STATE and this file is a watchdog hang, not a test.
    # ------------------------------------------------------------------
    li   a1, 0x51000002
    la   t0, shq_handler
    csrw 0x305, t0
    csrr t1, 0x305
    bne  t1, t0, shq_fail
    csrw 0x7C0, x0                  # mtrapctl.LEGACY = 0 -> standard delivery
    csrr t1, 0x7C0
    bnez t1, shq_fail

    # ------------------------------------------------------------------
    # POLARITY DISPATCH on misa.C (bit 2).  Runtime, not build time: the
    # tag vocabulary cannot express "compressed OFF".
    # ------------------------------------------------------------------
    csrr t0, 0x301                  # misa
    andi t1, t0, 4
    bnez t1, shq_c_on

    # ==================================================================
    # C IS OFF -- THE SHAPE_Q ARM IS LIVE.
    # ==================================================================

    # ---- CONTROL A : the same word, at an ALIGNED pc, MUST write ra ----
    li   a1, 0x51000003
    li   ra, 0xA5A5A5A5
    .word 0x00000093                # addi ra, x0, 0   -- executed normally
    bnez ra, shq_fail               # it committed: the encoding is what we think

    # ---- CONTROL B : the same word, at an ALIGNED pc, MUST store -------
    li   a1, 0x51000004
    la   s8, shq_scratch
    li   s2, 0xDEADDEAD
    li   t0, 0x5EED5EED
    sw   t0, 0(s8)
    .word 0x012C2023                # sw s2, 0(s8)     -- executed normally
    lw   t1, 0(s8)
    bne  t1, s2, shq_fail           # it committed: the encoding is what we think

    # ---- TEST A : jump to the ODD halfword of block A ------------------
    li   ra, 0xA5A5A5A5             # the sentinel a fall-through would zero
    la   s0, shq_oddA
    li   a1, 0x51000001
    andi t1, s0, 3
    li   t2, 2
    bne  t1, t2, shq_fail           # STRUCTURAL: the target really is 4n+2
    la   s6, shq_resumeA            # where the handler puts us back
    mv   s1, s3
    jalr zero, 0(s0)                # ---- SHAPE_Q ----
shq_resumeA:
    li   a1, 0x51000101
    beq  s3, s1, shq_fail           # it did NOT trap
    addi a1, a1, 1
    bnez s4, shq_fail               # mcause must be 0 (instr addr misaligned)
    addi a1, a1, 1
    andi t2, s0, -4                 # IALIGN mask -- see the header note
    bne  s5, t2, shq_fail           # mepc  = the misaligned PC with bit1 WARL-0
    addi a1, a1, 1
    bne  s7, s0, shq_fail           # mtval = the misaligned PC, UNMASKED
    addi a1, a1, 1
    li   t2, 0xA5A5A5A5
    bne  ra, t2, shq_fail           # THE N2 CHECK: rd was NOT committed

    # ---- TEST B : jump to the ODD halfword of block B ------------------
    li   t0, 0x5EED5EED
    sw   t0, 0(s8)                  # re-arm the scratch sentinel
    la   s0, shq_oddB
    li   a1, 0x51000001
    andi t1, s0, 3
    li   t2, 2
    bne  t1, t2, shq_fail
    la   s6, shq_resumeB
    mv   s1, s3
    jalr zero, 0(s0)                # ---- SHAPE_Q ----
shq_resumeB:
    li   a1, 0x51000201
    beq  s3, s1, shq_fail
    addi a1, a1, 1
    bnez s4, shq_fail               # mcause must be 0
    addi a1, a1, 1
    andi t2, s0, -4                 # IALIGN mask -- see the header note
    bne  s5, t2, shq_fail           # mepc  = the misaligned PC with bit1 WARL-0
    addi a1, a1, 1
    bne  s7, s0, shq_fail           # mtval = the misaligned PC, UNMASKED
    addi a1, a1, 1
    lw   t1, 0(s8)
    li   t2, 0x5EED5EED
    bne  t1, t2, shq_fail           # THE N2 CHECK: the store lanes were dead

    # ---- exactly two traps, nothing else fired ------------------------
    li   a1, 0x51000005
    li   t3, 2
    bne  s3, t3, shq_fail
    j    shq_done

    # ==================================================================
    # C IS ON -- SHAPE_Q is statically dead.  Positive control on the SAME
    # jump machinery: an odd-halfword target holding a real compressed
    # instruction must EXECUTE, and nothing may trap.
    # ==================================================================
shq_c_on:
    la   s0, shq_c_odd
    li   a1, 0x51000001
    andi t1, s0, 3
    li   t2, 2
    bne  t1, t2, shq_fail
    li   s1, 0
    jalr zero, 0(s0)
shq_c_back:
    li   a1, 0x510000C1
    li   t2, 1
    bne  s1, t2, shq_fail           # `c.li s1, 1` at 4n+2 really executed
    li   a1, 0x510000C2
    bnez s3, shq_fail               # and nothing trapped

shq_done:
    RVTEST_PASS                     # a0 = 0xCAFEBABE

    # ==================================================================
    # THE BLOCKS.  Byte-exact; do not reorder, re-align or "tidy".
    # ==================================================================
    .align 2
shq_blkA:
    .half 0x0093                    # word = 0x00000093 = addi ra, x0, 0
shq_oddA:
    .half 0x0000                    # <-- 4n+2, the SHAPE_Q target

    .align 2
shq_blkB:
    .half 0x2023                    # word = 0x012C2023 = sw s2, 0(s8)
shq_oddB:
    .half 0x012C                    # <-- 4n+2, the SHAPE_Q target

    .align 2
shq_c_blk:
    .half 0x0001                    # c.nop, never executed (alignment only)
shq_c_odd:
    .half 0x4485                    # <-- 4n+2: c.li s1, 1   (C-ON arm)
    j    shq_c_back                 # back at 4n, a plain 32-bit jump

    .align 2
shq_scratch:
    .word 0

    .align 2
shq_handler:
    csrr s4, 0x342                  # mcause
    csrr s5, 0x341                  # mepc
    csrr s7, 0x343                  # mtval
    addi s3, s3, 1
    csrw 0x341, s6                  # resume where the caller told us to
    mret

    .option pop

#else
    li   a1, 0x5E10BAD0
    j    shq_fail
#endif

shq_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env -- never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
