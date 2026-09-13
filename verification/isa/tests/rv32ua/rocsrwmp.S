# See LICENSE for license details.

# VestaRV: read-only-CSR write form must trap, on the default build
# The same subject as rocsrw.S, which documents the mechanism: maindec sets valid_funct from csr_addr_valid, a pure ADDRESS map with no reference to csr_op or the rs1 and uimm fields, while csr_unit already decodes the write form correctly and uses it only as a store strobe. THE TRAP APPLIES IN EVERY BUILD, and rocsrw.S can only test one where the trap is recoverable, so THIS file covers the DEFAULT build, which has no trap handler at all.
# THAT NEEDS THREE HARTS, because on a default build an illegal instruction lands in the TERMINAL TRAP_STATE and a hart that enters it never writes a0 again. The victims are tile harts 1 and 2 and the observer is hart 0, which keeps the ordinary pass/fail contract. Each victim writes a PROGRESS word before its illegal encoding and again after it, so the two states are unambiguous: PROGRESS = 1 means the victim reached the encoding and is wedged in it, so the write trapped; PROGRESS = 2 means it executed straight through, so the write was a silent nop. HART 0 REFUSES TO RENDER A VERDICT UNTIL IT HAS SEEN PROGRESS = 1 FROM BOTH VICTIMS, so a tile that never launched fails rather than vacuously passing.
# THE VICTIMS WEDGE IN TCM, NOT IN THE SHARED WINDOW, because TRAP_STATE's fetch address is the latched next-fetch address, which is a TCM address here, so the wedged harts generate no arbiter traffic and cannot disturb hart 0's observation. The instruction immediately after each illegal encoding is an `addi`, never a store, so the TRAP_STATE store-leak cannot fire either. Hart 1's encoding is `csrw mhartid, t0`, a CSRRW at 0xF14; hart 2's is `unimp` itself, csrrw x0, cycle, x0 at 0xC00, which has always been claimed to trap in this environment while today it is a silent nop, made testable in the very build the claim is about.
# THE NEGATIVE HALF RUNS ON HART 0 ITSELF, before any launch, and its proof is LIVENESS: on a default build a wrongly trapped instruction wedges hart 0 terminally, so hart 0 reaching its verdict at all means none of the eight negative encodings trapped. Each bumps a shared counter first, so a wedged run can be located precisely. The eight are a read of mhartid, csrrsi on cycle with uimm field 0, csrrci on mhartid with uimm field 0, and csrw to mhpmevent3, mcountinhibit, mhpmcounter3, mhpmcounter5 and misa. mip AT 0x344 IS DELIBERATELY ABSENT, because without CORE_ENABLE_TRAPCSR it is an unknown CSR and would trap for an unrelated reason. Three of the eight are verbatim from the Zihpm probe's default path, so hart 0 surviving them is the proof that a correctly scoped fix cannot move the suite floor.
# Verdicts: a0 = 0xCAFEBABE means the behaviour is correct in the default build and correctly scoped. a0 = 0xDEADBEEF with a1 = 0xF10A0001 means hart 1 executed past its write and 0xF10A0002 that hart 2 executed past `unimp`, both the finding; 0x5E1A0001 a negative-half read returned the wrong value; 0x5E1A0002 a victim never armed; 0x5E1A0003 the counter did not read back, a shared-RAM setup break. NO a0 AT ALL is itself a result: hart 0 wedged inside its own negative half, meaning the fix over-reaches; probe NEGPROG at 0x104F0 to name the leg.
# NOT IN THE STANDING SUITE: both victims end parked in TRAP_STATE forever and never write their a0, which riscv_tb reports as a NOTE rather than a failure. Invoke it explicitly with ./xrun_batch.sh xxxxrv32ua-p-rocsrwmp. Shared words, all below 0x10500 and inside the bootrom zero range: 0x104E8 PROG1, 0x104EC PROG2, 0x104F0 NEGPROG. The band 0x104E8-0x104F4 is free at N=4 and at N=18, and unlike the neighbouring bands it does not even overlap at N=18.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_PROG1    0x104E8
#define SH_PROG2    0x104EC
#define SH_NEGPROG  0x104F0

#define TILE_WORDS  1024        /* covers 0x8000-0x8FFF */
#define ARM_BUDGET  12000
#define WATCH_ITERS 4000

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr -- enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry            # belt-and-braces: only hart 0 orchestrates

    li   s2, SH_PROG1
    li   s3, SH_PROG2
    li   s4, SH_NEGPROG
    li   s6, 0x5A5A5A5A             # a distinctive write source, never 0

    sw   x0, 0(s4)                  # NEGPROG starts clear
    li   s5, 0                      # ...and its register shadow

    .option push
    .option arch, +zicsr

    # ==================================================================
    # THE NEGATIVE HALF.  Proof is LIVENESS: on this build a wrongly
    # trapped instruction wedges hart 0 terminally and no a0 is ever
    # written.  NEGPROG makes a wedged run locatable.
    # ==================================================================
    .macro ROCA_OK enc
    .word \enc
    addi s5, s5, 1
    sw   s5, 0(s4)
    .endm

    mv   t0, s6
    ROCA_OK 0xF14022F3                  # csrr t0, mhartid
    li   a1, 0x5E1A0001
    bnez t0, rocmp_fail                 # hart 0 -> mhartid must read 0

    ROCA_OK 0xC0006373                  # csrrsi t1, cycle, 0
    li   a1, 0x5E1A0001
    beqz t1, rocmp_fail                 # cycle must be counting

    mv   t2, s6
    ROCA_OK 0xF14073F3                  # csrrci t2, mhartid, 0
    li   a1, 0x5E1A0001
    bnez t2, rocmp_fail

    mv   t0, s6
    ROCA_OK 0x32329073                  # csrw mhpmevent3, t0     (extzihpm)
    mv   t0, s6
    ROCA_OK 0x32029073                  # csrw mcountinhibit, t0
    ROCA_OK 0xB0301073                  # csrw mhpmcounter3, x0   (extzihpm)
    ROCA_OK 0xB0501073                  # csrw mhpmcounter5, x0   (extzihpm)
    mv   t0, s6
    ROCA_OK 0x30129073                  # csrw misa, t0

    .option pop

    li   a1, 0x5E1A0003
    lw   t1, 0(s4)
    li   t2, 8
    bne  t1, t2, rocmp_fail             # eight legs, all survived, all recorded

    # ==================================================================
    # arm the victims' progress words, then launch tiles 1 and 2
    # ==================================================================
    sw   x0, 0(s2)
    lw   t1, 0(s2)
    li   a1, 0x5E1A0003
    bnez t1, rocmp_fail
    sw   x0, 0(s3)
    lw   t1, 0(s3)
    bnez t1, rocmp_fail

    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)

    # ==================================================================
    # wait (bounded) for BOTH victims to say they reached the encoding
    # ==================================================================
    li   t6, ARM_BUDGET
    li   t5, 1
arm_wait:
    lw   t2, 0(s2)
    blt  t2, t5, arm_next
    lw   t3, 0(s3)
    bge  t3, t5, armed
arm_next:
    addi t6, t6, -1
    bnez t6, arm_wait
    li   a1, 0x5E1A0002                 # a victim never reached the encoding
    j    rocmp_fail

armed:
    # ==================================================================
    # observe: neither victim may ever advance to 2
    # ==================================================================
    li   t6, WATCH_ITERS
    li   t5, 2
watch_loop:
    lw   t2, 0(s2)
    beq  t2, t5, rocmp_h1_ran
    lw   t3, 0(s3)
    beq  t3, t5, rocmp_h2_ran
    addi t6, t6, -1
    bnez t6, watch_loop

    RVTEST_PASS                         # a0 = 0xCAFEBABE

rocmp_h1_ran:
    li   a1, 0xF10A0001                 # csrw mhartid, t0 did not trap
    j    rocmp_fail
rocmp_h2_ran:
    li   a1, 0xF10A0002                 # unimp did not trap
rocmp_fail:
    RVTEST_FAIL                         # a0 = 0xDEADBEEF

    # ---- tile harts enter here (loader ABI: only sp is defined) -------------
tile_entry:
    li   sp, 0xBFF0
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    li   t4, 1
    beq  t3, t4, tile_h1
    li   t4, 2
    beq  t3, t4, tile_h2
tile_park:
    j    tile_park

tile_h1:
    li   t0, SH_PROG1
    li   t1, 1
    sw   t1, 0(t0)                      # armed: about to execute the encoding
    .word 0xF1429073                    # csrw mhartid, t0  -- MUST TRAP
    addi t1, x0, 2                      # never a store: F8 cannot fire here
    sw   t1, 0(t0)                      # reached ONLY if it did NOT trap
tile_h1_park:
    j    tile_h1_park

tile_h2:
    li   t0, SH_PROG2
    li   t1, 1
    sw   t1, 0(t0)                      # armed
    .word 0xC0001073                    # unimp = csrrw x0,cycle,x0 -- MUST TRAP
    addi t1, x0, 2                      # never a store: F8 cannot fire here
    sw   t1, 0(t0)                      # reached ONLY if it did NOT trap
tile_h2_park:
    j    tile_h2_park

    # NOTE: RVTEST_CODE_END is 'unimp' in this env -- never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
