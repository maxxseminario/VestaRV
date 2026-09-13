# See LICENSE for license details.

# VestaRV: the Zbkb `pack` space must not alias onto the Zbb ZEXT.H decode row
# THE DEFECT: the ZEXT.H decode row is qualified on funct7 and funct3 ONLY, never on rs2, and the Zbkb `pack` encoding space shares that funct7 and funct3 pair, so on a build with Zbkb off, which is every shipped configuration, a `pack` with rs2 other than x0 is admitted by the ZEXT.H row and RETIRES instead of raising illegal-instruction. That is the same class as a reserved encoding executing as something else.
# WHAT THE ISA SAYS, verified against the toolchain: RV32 `zext.h rd, rs1` and RV32 `pack rd, rs1, rs2` share opcode 0110011, funct3 100 and funct7 0000100, and zext.h IS the rs2 = x0 point of that space, since the assembler renders `zext.h t3,t4` as the same word as `.insn r 0x33,0x4,0x04,x28,x29,x0`. So with Zbb on and Zbkb off, rs2 = x0 is a legal zext.h and any other rs2 is an unimplemented pack and must raise illegal-instruction; with Zbkb on, every rs2 is legal and computes (rs2[15:0] << 16) | rs1[15:0], which for rs2 = x0 degenerates to exactly zext.h, so the two are ONE instruction and not two. `packh`, funct3 111, is Zbkb-only in both polarities and must trap on every build without it. The alias is visible in the result as well as in the legality, because the ZEXT.H datapath never reads operand b, so two encodings differing only in rs2 give the SAME answer, at most 0xFFFF.
# THE POLARITY TRAP THAT SETS THIS FILE'S SHAPE: with the defect a pack retires and a single-hart test runs past it, while with it fixed the pack TRAPS, and on a default build an illegal instruction lands in the TERMINAL TRAP_STATE with no handler and no exit, so the hart never writes a0 again. A naive detector is therefore fail-then-hang and never renders a clean verdict. NO trapCsr VARIANT IS NEEDED OR WANTED, because these are decode-legality encodings, identical in every build, and the default build is the one the finding is about. So the offending encodings run on TILE harts and hart 0, which never executes one, keeps the a0 contract and observes the tiles through a PROGRESS word: 1 means the victim reached its encoding and is wedged in it, so it trapped, and 2 means it executed straight through, so it retired. Both polarities end at a0.
# The three tile harts. Hart 1 and hart 2 are VICTIMS running `pack x28, x29, x1` and `pack x28, x29, x31`, the two extremes of the rs2 field, with the SAME rs1 and DIFFERENT rs2 values; a true pack would return two different results while the ZEXT.H row returns the same value for both, so THE STORED RESULTS DISCRIMINATE "aliased onto zext.h" FROM ANY OTHER WAY OF RETIRING. Hart 3 is the CONTROL running `packh x28, x29, x31`, which must trap on this build today and after any fix; it is there to prove the observation path is LIVE before the fix, since otherwise "PROGRESS stays at 1" is a state this test would never have been seen to produce, and it doubles as the over-reach guard. The victims wedge in TCM, so they raise no arbiter traffic that could disturb hart 0, and the instruction after every encoding is an `addi`, never a store, so the TRAP_STATE store-leak cannot fire.
# THE POSITIVE HALF RUNS ON HART 0, before any launch, in both polarities, and must pass today and forever. It is a base-ISA add plus five legal encodings, all with rs2 = x0: three packs with different rs1 values, a pack with both sources x0, and `zext.h` written as the MNEMONIC through `.option arch, +zbb` so gas chooses the encoding, which proves the canonical zext.h is the rs2 = x0 form and is legal. HART 0 NEVER EXECUTES AN rs2 /= x0 ENCODING IN EITHER POLARITY, which is what keeps it alive after the fix, and its proof is twofold: the values are asserted, and a wrongly trapped instruction would wedge it terminally, so reaching any verdict at all proves none of them trapped. POSPROG counts the legs so a wedged run can be located.
# THE ZBKB-ON ARM guards against an OVER-WIDE fix: on a Zbkb build every pack must keep working, and one of its cases is a nonzero rs2 whose low half is 0, which returns the SAME value zext.h would, DELIBERATELY, because value alone cannot separate the two rows and the difference is legality and only legality. It is single-hart, since nothing traps on that build.
# THE PASS-POLARITY CONTROL -DPACKALIAS_PASS_CONTROL replaces BOTH victims' encodings with packh, which traps on this build today, so all three tiles wedge, hart 0 observes PROGRESS = 1 from all three and the passing path is exercised end to end on the unfixed tree. A detector never seen to pass is as untrustworthy as one never seen to fail. It is a control and makes no claim about the finding.
# BUILD POLARITY: the OFF arm is the default and CORE_ENABLE_ZBKB is NEVER auto-derived from a generated header; the ON arm needs the define passed explicitly and a Zbkb-ON staged build. ENABLE_BITMANIP MUST BE TRUE IN BOTH ARMS, since zext.h is itself a Zbb encoding, so this test is not valid on a no-bitmanip build.
# Verdicts: a0 = 0xCAFEBABE means the alias is gone, or on the ON arm that Zbkb still works. a1 = 0xBADA0010 both victims retired returning the same zext.h value, so rs2 is ignored and the encodings aliased, the finding, with a2 and a3 the two results; 0xBADA0011 and 0xBADA0012 both retired but one result is not the zext.h value; 0xBADA0001 and 0xBADA0002 only one victim retired; 0xBADA0003 hart 3 retired, so packh became legal without Zbkb, which is an over-wide fix and a different class, checked first; 0x5E1A0001 a positive-half leg returned the wrong value; 0x5E1A0002 a victim never armed; 0x5E1A0003 a progress word did not read back; 0x5E1A0004 base-ISA sanity failed; 0x5E1A0005 POSPROG did not count every leg. NO a0 AT ALL is itself a result: hart 0 wedged inside its own positive half, so the fix over-reached and made a legal zext.h illegal; probe POSPROG at 0x104D4 to name the leg.
# NOT IN ANY STANDING LIST: after the fix all three tiles are parked in TRAP_STATE forever and never write their a0, which riscv_tb reports as a NOTE. Invoke it explicitly with ./xrun_batch.sh rv32ua-p-packalias. THE IMAGE NAME CARRIES NO x PADDING, because the 22-character basename contract counts the ".rcf" suffix and this name is already 22.
# Shared words, all below 0x10500 and inside the bootrom zero range, in two bands free at N=4 and at N=18: 0x104D4 POSPROG, 0x104D8 VAL1 and 0x104DC VAL2; 0x104F4 PROG1, 0x104F8 PROG2 and 0x104FC PROG3.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_POSPROG  0x104D4
#define SH_VAL1     0x104D8
#define SH_VAL2     0x104DC
#define SH_PROG1    0x104F4
#define SH_PROG2    0x104F8
#define SH_PROG3    0x104FC

#define TILE_WORDS  1024        /* covers 0x8000-0x8FFF */
#define ARM_BUDGET  12000
#define WATCH_ITERS 4000

#define ZEXT_OF_RS1 0x00005678  /* zext16(0x12345678) -- the alias signature */

/* gas 13.2 has no zbk* mnemonics; .insn is the house convention (extzbkb.S) */
#define PACK(rd,rs1,rs2)   .insn r 0x33, 0x4, 0x04, rd, rs1, rs2
#define PACKH(rd,rs1,rs2)  .insn r 0x33, 0x7, 0x04, rd, rs1, rs2

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry            # only hart 0 orchestrates

    # ==================================================================
    # THE POSITIVE HALF -- both polarities, must pass today and forever.
    # Every leg has rs2 = x0.  Hart 0 executes no other kind.
    # ==================================================================
    li   s4, SH_POSPROG
    sw   x0, 0(s4)
    li   s5, 0

    .macro PK_OK
    addi s5, s5, 1
    sw   s5, 0(s4)
    .endm

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    PK_OK
    li   a1, 0x5E1A0004
    bne  t2, t3, pk_fail

    li   x29, 0x12345678
    li   x28, 0
    PACK(x28, x29, x0)              # P1: zext.h form
    PK_OK
    li   t1, 0x00005678
    li   a1, 0x5E1A0001
    bne  x28, t1, pk_fail

    li   x29, 0xFFFFFFFF
    li   x28, 0
    PACK(x28, x29, x0)              # P2
    PK_OK
    li   t1, 0x0000FFFF
    li   a1, 0x5E1A0001
    bne  x28, t1, pk_fail

    li   x29, 0x0000ABCD
    li   x28, 0
    PACK(x28, x29, x0)              # P3
    PK_OK
    li   t1, 0x0000ABCD
    li   a1, 0x5E1A0001
    bne  x28, t1, pk_fail

    li   x28, 0x5A5A5A5A
    PACK(x28, x0, x0)               # P4: rs1 = x0 too
    PK_OK
    li   a1, 0x5E1A0001
    bnez x28, pk_fail

    li   x29, 0x12345678
    li   x28, 0
    .option push
    .option arch, +zbb
    zext.h x28, x29                 # P5: the MNEMONIC -- gas picks the encoding
    .option pop
    PK_OK
    li   t1, 0x00005678
    li   a1, 0x5E1A0001
    bne  x28, t1, pk_fail

#ifdef CORE_ENABLE_ZBKB
    # ==================================================================
    # ZBKB-ON ARM.  Single hart; nothing traps on this build.  This is the
    # guard against an over-wide fix: pack/packh must keep working here.
    # ==================================================================
    li   x29, 0x12345678
    li   x30, 0x9ABCDEF0
    li   x28, 0
    PACK(x28, x29, x30)             # O1
    PK_OK
    li   t1, 0xDEF05678
    li   a1, 0x5E1A0001
    bne  x28, t1, pk_fail

    li   x30, 0x0000FFFF
    li   x28, 0
    PACK(x28, x29, x30)             # O2
    PK_OK
    li   t1, 0xFFFF5678
    li   a1, 0x5E1A0001
    bne  x28, t1, pk_fail

    li   x30, 0x00010000
    li   x28, 0
    PACK(x28, x29, x30)             # O3: nonzero rs2, zext.h-lookalike value
    PK_OK
    li   t1, 0x00005678
    li   a1, 0x5E1A0001
    bne  x28, t1, pk_fail

    li   x30, 0x9ABCDEF0
    li   x28, 0
    PACKH(x28, x29, x30)            # O4
    PK_OK
    li   t1, 0x0000F078
    li   a1, 0x5E1A0001
    bne  x28, t1, pk_fail

    lw   t1, 0(s4)
    li   t2, 10
    li   a1, 0x5E1A0005
    bne  t1, t2, pk_fail            # six positive legs + four ON legs
    j    pk_pass

#else
    # ==================================================================
    # DEFAULT (ZBKB-OFF) ARM.  The observer construction.
    # ==================================================================
    lw   t1, 0(s4)
    li   t2, 6
    li   a1, 0x5E1A0005
    bne  t1, t2, pk_fail            # six positive legs, all survived, all counted

    li   s2, SH_PROG1
    li   s3, SH_PROG2
    li   s9, SH_PROG3

    li   t0, SH_VAL1
    sw   x0, 0(t0)
    li   t0, SH_VAL2
    sw   x0, 0(t0)
    sw   x0, 0(s2)
    sw   x0, 0(s3)
    sw   x0, 0(s9)

    li   a1, 0x5E1A0003
    lw   t1, 0(s2)
    bnez t1, pk_fail
    lw   t1, 0(s3)
    bnez t1, pk_fail
    lw   t1, 0(s9)
    bnez t1, pk_fail

    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(2, tile_entry, TILE_WORDS)
    MP_LAUNCH_HART(3, tile_entry, TILE_WORDS)

    # ---- bounded wait: all three must say they REACHED their encoding ----
    li   t6, ARM_BUDGET
    li   t5, 1
pk_arm_wait:
    lw   t2, 0(s2)
    blt  t2, t5, pk_arm_next
    lw   t3, 0(s3)
    blt  t3, t5, pk_arm_next
    lw   t4, 0(s9)
    bge  t4, t5, pk_armed
pk_arm_next:
    addi t6, t6, -1
    bnez t6, pk_arm_wait
    li   a1, 0x5E1A0002             # a victim never reached its encoding
    j    pk_fail

pk_armed:
    # ---- observe: no hart may ever advance past its encoding ----
    li   s7, 0
    li   t6, WATCH_ITERS
    li   t5, 2
pk_watch:
    lw   t2, 0(s2)
    bne  t2, t5, 1f
    ori  s7, s7, 1
1:  lw   t3, 0(s3)
    bne  t3, t5, 2f
    ori  s7, s7, 2
2:  lw   t4, 0(s9)
    bne  t4, t5, 3f
    ori  s7, s7, 4
3:  addi t6, t6, -1
    bnez t6, pk_watch

    beqz s7, pk_pass                # nothing retired: every encoding trapped

    # ---- classify ----
    li   t0, SH_VAL1
    lw   a2, 0(t0)
    li   t0, SH_VAL2
    lw   a3, 0(t0)
    li   t2, ZEXT_OF_RS1

    andi t0, s7, 4
    li   a1, 0xBADA0003
    bnez t0, pk_fail                # packh retired -- a different class

    andi t0, s7, 1
    li   a1, 0xBADA0002
    beqz t0, pk_fail                # only victim 2 retired
    andi t0, s7, 2
    li   a1, 0xBADA0001
    beqz t0, pk_fail                # only victim 1 retired

    li   a1, 0xBADA0011
    bne  a2, t2, pk_fail
    li   a1, 0xBADA0012
    bne  a3, t2, pk_fail
    li   a1, 0xBADA0010             # both retired, both = zext16(rs1): rs2 IGNORED
    j    pk_fail
#endif

pk_pass:
    RVTEST_PASS                     # a0 = 0xCAFEBABE
pk_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

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
    li   t4, 3
    beq  t3, t4, tile_h3
tile_park:
    j    tile_park

tile_h1:
    li   t0, SH_PROG1
    li   t1, 1
    sw   t1, 0(t0)                  # armed: about to execute the encoding
    li   x29, 0x12345678
    li   x1,  0x9ABCDEF0
    li   x28, 0
#ifdef PACKALIAS_PASS_CONTROL
    PACKH(x28, x29, x1)             # PASS-POLARITY CONTROL: see the note below
#else
    PACK(x28, x29, x1)              # rs2 = x1 -- MUST TRAP without Zbkb
#endif
    addi t1, x0, 2                  # never a store: F8 cannot fire here
    li   t2, SH_VAL1
    sw   x28, 0(t2)                 # reached ONLY if it did NOT trap
    sw   t1, 0(t0)
tile_h1_park:
    j    tile_h1_park

tile_h2:
    li   t0, SH_PROG2
    li   t1, 1
    sw   t1, 0(t0)                  # armed
    li   x29, 0x12345678
    li   x31, 0x0F0F0F0F
    li   x28, 0
#ifdef PACKALIAS_PASS_CONTROL
    PACKH(x28, x29, x31)            # PASS-POLARITY CONTROL: see the note below
#else
    PACK(x28, x29, x31)             # rs2 = x31 -- MUST TRAP without Zbkb
#endif
    addi t1, x0, 2                  # never a store: F8 cannot fire here
    li   t2, SH_VAL2
    sw   x28, 0(t2)                 # reached ONLY if it did NOT trap
    sw   t1, 0(t0)
tile_h2_park:
    j    tile_h2_park

tile_h3:
    li   t0, SH_PROG3
    li   t1, 1
    sw   t1, 0(t0)                  # armed
    li   x29, 0x12345678
    li   x31, 0x0F0F0F0F
    li   x28, 0
    PACKH(x28, x29, x31)            # packh -- MUST TRAP without Zbkb, always
    addi t1, x0, 2                  # never a store: F8 cannot fire here
    sw   t1, 0(t0)                  # reached ONLY if it did NOT trap
tile_h3_park:
    j    tile_h3_park

    # NOTE: RVTEST_CODE_END is 'unimp' in this env -- never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
