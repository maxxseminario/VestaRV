# See LICENSE for license details.

# VestaRV: red team, a PMP fetch fault on the upper half of a straddling instruction
# ON-ONLY, needing a trapCsr, umode and pmp build. privpmp is `.option norvc` throughout, so nothing else in the suite ever takes a fetch fault on the upper half of a split fetch, which is exactly the class where a new strobe keyed on EXECUTE plus a decode signal re-fires on compressed half-fetch cycles.
# THE GEOMETRY: with C enabled a 32-bit instruction may start at an odd halfword, so its two halves live in DIFFERENT words and are TWO separately checked fetch transactions. Only the upper word is fenced. B+0 c.nop, in the permitted word B+0; B+2 `addi s10, s10, 1`, 32-bit, occupying B+2 through B+5; B+4 THE FENCED WORD, NA4 with no permissions, holding the UPPER HALF; B+6 c.nop in that same fenced word, never fetched; B+8 c.nop in the permitted word B+8; B+10 `c.li s11, 7`, the RESUME point, a compressed instruction at an odd halfword.
# Three things are under test. (a) The fault fires at all on a half-fetch cycle, with cause 1. (b) The frozen rule for a straddling instruction: mepc is the LOWER half's address even when the UPPER half is the denied one, and mtval is the denied half's address. (c) THE RESIDUE. The half-fetch cycle asserted repeat_if_req, and every other trap out of a split fetch is dispatched from inside the repeat_if branch, which clears the flag first, but the instruction-access-fault arm is deliberately HOISTED to the top of EXECUTE and does not clear it. If repeat_if survives trap entry, the first compressed instruction the hart later executes at an odd halfword is decoded as the completion of a split fetch, with the PC advancing 4 instead of 2. Check 14 catches that by requiring `c.li s11, 7` at B+10 actually to set s11 to 7.
# CLASSIFICATION IF (c) BITES: instruction-stream corruption after a legitimate, recoverable PMP fetch fault, a mis-execution and PC-desync bug, and the natural handler action of MRETing back to mepc to re-run the instruction hits the same stale flag. Not an escape.
# Boundedness: the U fragment is straight-line into `ecall`, every landing slot inside it is a c.nop chain falling into the exit jump, and the handler bails to M after 8 traps, so a mis-decoded instruction that traps repeatedly cannot loop. Compressed encodings are raw `.half` words so the file can stay `.option norvc` and the layout is byte-exact: 0x0001 is c.nop and 0x4D9D is `c.li s11, 7`.
# REGISTER CONTRACT: s2 = B, the split base; s3 the trap counter; s4, s5 and s6 the FIRST fault's cause, mepc and mtval, captured once; s7 the handler resume PC; s9 the M continuation after ECALL; s10 the straddle-commit witness; s11 the c.li witness.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define RT6_TORTOP  0x00020000

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, rt6_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE) && defined(CORE_ENABLE_PMP)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0
    li   s4, 0
    li   s10, 0
    li   s11, 0

    li   t4, 1
    la   t0, rt6_handler
    csrw 0x305, t0
    csrr t1, 0x305
    bne  t1, t0, rt6_fail
    li   t4, 2
    csrw 0x7C0, x0
    csrr t1, 0x7C0
    bne  t1, x0, rt6_fail
    csrw 0x304, x0

    # ---- CHECK 3 : the map.  entry0 fences the word at B+4 ONLY ---------
    li   t4, 3
    la   s2, rt6_split_base
    addi t0, s2, 4
    srli t0, t0, 2
    csrw 0x3B0, t0
    csrw 0x3B1, x0
    li   t0, RT6_TORTOP
    srli t0, t0, 2
    csrw 0x3B2, t0
    li   t0, 0x000F0010             # cfg2=TOR RWX cfg1=OFF cfg0=NA4 no-perms
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt6_fail

    # ---- enter U at B, resuming (after the fault) at B+10 ---------------
    la   s9, rt6_m2
    addi s7, s2, 10
    csrw 0x341, s2
    csrw 0x300, x0                  # MPP=00 (U), MIE=0, MPRV=0
    mret                            # ---- U ----

rt6_m2:
    li   t4, 10
    li   t1, 1
    bne  s4, t1, rt6_fail           # cause 1 (instruction access fault)
    li   t4, 11
    addi t1, s2, 2
    bne  s5, t1, rt6_fail           # mepc  = the LOWER half's address
    li   t4, 12
    addi t1, s2, 4
    bne  s6, t1, rt6_fail           # mtval = the DENIED half's address
    li   t4, 13
    bne  s10, x0, rt6_fail          # the straddling addi committed nothing
    li   t4, 14
    li   t1, 7
    bne  s11, t1, rt6_fail          # THE RESIDUE CHECK: `c.li s11,7` at an
                                    # ODD halfword must execute as itself
    li   t4, 15
    li   t1, 2                      # exactly 1 access fault + 1 ECALL
    bne  s3, t1, rt6_fail

    li   t4, 16
    csrw 0x3A0, x0
    csrr t1, 0x3A0
    bne  t1, x0, rt6_fail
    li   t1, 0x00000001
    csrw 0x7C0, t1
    csrw 0x300, x0

    RVTEST_PASS

    # =====================================================================
    # THE U FRAGMENT.  Byte-exact; do not reorder or re-align.
    # =====================================================================
    .align 2
rt6_split_base:
    .half 0x0001                    # B+0   c.nop
rt6_lower:
    addi s10, s10, 1                # B+2 .. B+5  (STRADDLES the word edge)
    .half 0x0001                    # B+6   c.nop   (inside the fenced word)
    .half 0x0001                    # B+8   c.nop
rt6_resume:
    .half 0x4D9D                    # B+10  c.li s11, 7   <-- odd halfword
    .half 0x0001                    # B+12  c.nop
    .half 0x0001                    # B+14  c.nop
rt6_uexit:
    ecall                           # B+16  (word aligned)
    j    rt6_uexit

    .align 2
rt6_handler:
    csrr t0, 0x342
    addi s3, s3, 1
    li   t1, 8
    beq  t0, t1, rt6_hdl_ecall      # ECALL from U
    li   t1, 11
    beq  t0, t1, rt6_hdl_ecall      # ECALL from M
    bnez s4, rt6_hdl_nocap
    mv   s4, t0                     # capture the FIRST fault only
    csrr s5, 0x341
    csrr s6, 0x343
rt6_hdl_nocap:
    li   t1, 8
    blt  t1, s3, rt6_hdl_ecall      # BAIL to M after 8 traps (boundedness)
    csrw 0x341, s7
    mret
rt6_hdl_ecall:
    jr   s9

    .option pop

#else
    li   t4, 0
    j    rt6_fail
#endif

rt6_fail:
    RVTEST_FAIL

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
