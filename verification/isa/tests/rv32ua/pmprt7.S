# See LICENSE for license details.

# VestaRV: a PMP-denied fetch address in the same cycle as a permitted load
# ON-ONLY, needing a trapCsr, umode and pmp build. Sibling of pmprt6, which fences the upper half of a straddling 32-bit instruction reached from a compressed ALU operation; this file reaches the SAME fenced halfword from a compressed LOAD, which puts the fetch check and a data access in one cycle.
# WHY THAT CYCLE IS DIFFERENT: the core checks the address it would put on the bus as an instruction fetch, and a denial raises pmp_if_park, which parks data_addr on PC_RST_VAL. In the dispatch cycle of a load the bus is carrying the LOAD's address, not a fetch, and the load's own PMP verdict is a separate, permitted one. So this cycle asks data_addr to serve a permitted data access while the fetch side of the same cycle is denied. THE PARK ARM OF THE data_addr MUX SITS BELOW EVERY DATA-ACCESS ARM precisely so the data access wins, and check 17 makes that ordering a measured fact rather than a reading of the source.
# THE GEOMETRY is pmprt6's except for the instruction at B+0, and only the word at B+4 is fenced: B+0 `c.lw s1, 0(s0)`, a compressed load at a permitted address; B+2 `addi s10, s10, 1`, 32-bit, occupying B+2 through B+5; B+4 THE FENCED WORD, NA4 with no permissions, holding the upper half; B+6 c.nop in the same fenced word, never fetched; B+8 c.nop in the permitted word; B+10 `c.li s11, 7`, the resume point at an odd halfword. The load's address is a word well outside the fenced one, holding a sentinel written in M before the drop to U, and the load retires normally, because its rd commit happens at the memory edge one edge before the fetch denial is consumed, so the sentinel reaches M in s1.
# What each check owns: 10 to 12 that the fault still fires with cause 1 and that mepc names the LOWER half while mtval names the denied half; 13 that the straddling addi committed nothing; 14 that no split-fetch flag survived trap entry to mis-decode the compressed instruction at the odd halfword; and 17, the new one, that the load read the sentinel, so the denied fetch address did not displace the permitted data address, which a park that won over the data arm would replace with PC_RST_VAL.
# Boundedness: the U fragment is straight-line into `ecall`, every landing slot is a c.nop chain falling into the exit jump, and the handler bails to M after 8 traps, so a mis-decoded instruction that traps cannot loop. Compressed encodings are raw `.half` words so the file stays `.option norvc` and the layout is byte-exact: 0x0001 is c.nop, 0x4D9D is `c.li s11, 7` and 0x4004 is `c.lw s1, 0(s0)`.
# REGISTER CONTRACT: s0 the load base, s1 the loaded sentinel, s2 = B the split base, s3 the trap counter, s4, s5 and s6 the FIRST fault's cause, mepc and mtval captured once, s7 the handler resume PC, s9 the M continuation after ECALL, s10 the straddle-commit witness and s11 the c.li witness.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define RT7_TORTOP   0x00020000
#define RT7_SENTINEL 0x5A5AA5A5

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, rt7_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE) && defined(CORE_ENABLE_PMP)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0
    li   s4, 0
    li   s10, 0
    li   s11, 0
    li   s1, 0

    li   t4, 1
    la   t0, rt7_handler
    csrw 0x305, t0
    csrr t1, 0x305
    bne  t1, t0, rt7_fail
    li   t4, 2
    csrw 0x7C0, x0
    csrr t1, 0x7C0
    bne  t1, x0, rt7_fail
    csrw 0x304, x0

    # ---- the load's target: a permitted word holding a known sentinel ----
    li   t4, 3
    la   s0, rt7_data
    li   t0, RT7_SENTINEL
    sw   t0, 0(s0)
    lw   t1, 0(s0)
    bne  t1, t0, rt7_fail

    # ---- CHECK 4 : the map.  entry0 fences the word at B+4 ONLY ---------
    li   t4, 4
    la   s2, rt7_split_base
    addi t0, s2, 4
    srli t0, t0, 2
    csrw 0x3B0, t0
    csrw 0x3B1, x0
    li   t0, RT7_TORTOP
    srli t0, t0, 2
    csrw 0x3B2, t0
    li   t0, 0x000F0010             # cfg2=TOR RWX cfg1=OFF cfg0=NA4 no-perms
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt7_fail

    # ---- enter U at B, resuming (after the fault) at B+10 ---------------
    la   s9, rt7_m2
    addi s7, s2, 10
    csrw 0x341, s2
    csrw 0x300, x0                  # MPP=00 (U), MIE=0, MPRV=0
    mret                            # ---- U ----

rt7_m2:
    li   t4, 10
    li   t1, 1
    bne  s4, t1, rt7_fail           # cause 1 (instruction access fault)
    li   t4, 11
    addi t1, s2, 2
    bne  s5, t1, rt7_fail           # mepc  = the LOWER half's address
    li   t4, 12
    addi t1, s2, 4
    bne  s6, t1, rt7_fail           # mtval = the DENIED half's address
    li   t4, 13
    bne  s10, x0, rt7_fail          # the straddling addi committed nothing
    li   t4, 14
    li   t1, 7
    bne  s11, t1, rt7_fail          # THE RESIDUE CHECK: `c.li s11,7` at an
                                    # ODD halfword must execute as itself
    li   t4, 15
    li   t1, 2                      # exactly 1 access fault + 1 ECALL
    bne  s3, t1, rt7_fail

    li   t4, 17                     # THE DATA-ADDRESS CHECK: the compressed
    li   t1, RT7_SENTINEL           # load in the denied-fetch cycle read its
    bne  s1, t1, rt7_fail           # OWN address, not the park address

    li   t4, 18
    csrw 0x3A0, x0
    csrr t1, 0x3A0
    bne  t1, x0, rt7_fail
    li   t1, 0x00000001
    csrw 0x7C0, t1
    csrw 0x300, x0

    RVTEST_PASS

    # =====================================================================
    # THE U FRAGMENT.  Byte-exact; do not reorder or re-align.
    # =====================================================================
    .align 2
rt7_split_base:
    .half 0x4004                    # B+0   c.lw s1, 0(s0)
rt7_lower:
    addi s10, s10, 1                # B+2 .. B+5  (STRADDLES the word edge)
    .half 0x0001                    # B+6   c.nop   (inside the fenced word)
    .half 0x0001                    # B+8   c.nop
rt7_resume:
    .half 0x4D9D                    # B+10  c.li s11, 7   <-- odd halfword
    .half 0x0001                    # B+12  c.nop
    .half 0x0001                    # B+14  c.nop
rt7_uexit:
    ecall                           # B+16  (word aligned)
    j    rt7_uexit

    .align 2
rt7_data:
    .word 0

    .align 2
rt7_handler:
    csrr t0, 0x342
    addi s3, s3, 1
    li   t1, 8
    beq  t0, t1, rt7_hdl_ecall      # ECALL from U
    li   t1, 11
    beq  t0, t1, rt7_hdl_ecall      # ECALL from M
    bnez s4, rt7_hdl_nocap
    mv   s4, t0                     # capture the FIRST fault only
    csrr s5, 0x341
    csrr s6, 0x343
rt7_hdl_nocap:
    li   t1, 8
    blt  t1, s3, rt7_hdl_ecall      # BAIL to M after 8 traps (boundedness)
    csrw 0x341, s7
    mret
rt7_hdl_ecall:
    jr   s9

    .option pop

#else
    li   t4, 0
    j    rt7_fail
#endif

rt7_fail:
    RVTEST_FAIL

RVTEST_CODE_END

    .data
RVTEST_DATA_BEGIN
    TEST_DATA
RVTEST_DATA_END
