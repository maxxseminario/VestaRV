# See LICENSE for license details.

#*****************************************************************************
# packalias.S   (K-series, K5 -- the BLIND DETECTOR for finding F-BV1)
#-----------------------------------------------------------------------------
# F-BV1 (rulings.md R-K3-2): the RTL's Zbb ZEXT.H decode row is qualified on
# funct7 and funct3 ONLY, never on rs2.  The Zbkb `pack` encoding space shares
# that funct7/funct3 pair, so on a build with Zbkb OFF -- which is every shipped
# config -- a `pack` with rs2 != x0 is admitted by the ZEXT.H row and RETIRES
# instead of raising an illegal-instruction exception.  Same class as the
# pre-F10 `unimp` silent alias: a reserved encoding executing as something else.
#
# WHAT THE ISA SAYS (verified against the toolchain, not quoted from a doc).
#   RV32 Zbb `zext.h rd, rs1` and RV32 Zbkb `pack rd, rs1, rs2` share
#   opcode 0110011 / funct3 100 / funct7 0000100.  zext.h IS the rs2 = x0 point
#   of that space -- `riscv-none-elf-as -march=...+zbb` assembles `zext.h t3,t4`
#   to 0x080ece33, which is bit-for-bit `.insn r 0x33,0x4,0x04,x28,x29,x0`.
#   Therefore, on a build with Zbb ON and Zbkb OFF:
#       rs2 == x0   ->  zext.h        LEGAL, rd = zext16(rs1)
#       rs2 != x0   ->  pack          NOT IMPLEMENTED -> illegal-instruction
#   and on a build with Zbkb ON, every rs2 is legal and computes
#   rd = (rs2[15:0] << 16) | rs1[15:0]  (which for rs2 = x0 degenerates to
#   exactly zext.h -- the two are the same instruction, not two instructions).
#   `packh` (funct3 111) is Zbkb-only in both polarities: it is not a Zbb
#   encoding, so it must trap on every build without Zbkb.
#
# WHERE THE RTL LOSES IT (re-grepped at c480170; every line number rots)
#   maindec.vhd:288-297   is_zbb_r_instr, whose last term is, in full,
#                         "(funct7 = ZEXT_FN7 and funct3 = \"100\")".  No rs2
#                         term appears anywhere in the row.
#   constants.vhd:218/259 ZEXT_FN7 = PACK_FN7 = "0000100"; PACK_FN3 = "100" is
#                         the same funct3 the ZEXT.H row matches.  The two
#                         constants are the same seven bits under two names.
#   maindec.vhd:749-750   the R_OPCODE arm: "elsif is_zbb_r_instr = '1' then
#                         valid_funct <= '1';" -- and this arm is reached BEFORE
#                         the Zbkb arm at :761, so with ENABLE_ZBKB false the
#                         whole pack space still lands here.
#   maindec.vhd:1244      alu_control gets "0101001" (ZEXT.H) for the same
#                         unqualified funct7/funct3 pair.
#   alu.vhd:615-618       ZEXT.H computes (others => '0') & a(15 downto 0) --
#                         operand b (rs2) is not read at all, which is why the
#                         retired results are <= 0xFFFF and why two encodings
#                         differing only in rs2 give the SAME answer.
#   maindec.vhd:761-762   is_zbkb_new_r_instr is ENABLE_ZBKB-gated, so it is a
#                         constant '0' here and cannot be the arm that fires.
#   maindec.vhd:782-783   packh (funct3 111) matches no arm and reaches
#                         "else valid_funct <= '0'" -- which is why hart 3 below
#                         is a CONTROL and not a victim.
#   This file asserts BEHAVIOUR, not any of the above; the citations are here so
#   a reader can check that the two encodings really do collide.
#
# ---------------------------------------------------------------------------
# THE POLARITY TRAP, AND WHY THIS FILE HAS THE SHAPE IT HAS
#   Pre-fix a `pack` with rs2 != x0 retires, so a single-hart test runs past it
#   and reports whatever it likes.  Post-fix it TRAPS -- and on a default build
#   (CORE_ENABLE_TRAPCSR false) an illegal instruction lands in the TERMINAL
#   TRAP_STATE: self-loop, no handler, no exit.  A hart that enters it never
#   writes a0 again.  A naive detector is therefore FAIL-then-HANG: it never
#   renders a clean post-fix verdict, and a hang is not a pass.
#   No trapCsr variant of this file is needed or wanted, for a reason that is
#   itself measurable: the encodings under test are decode-legality encodings,
#   identical in every build, and the DEFAULT build is the one the finding is
#   about.  The rocsrwmp.S (F10, wave W5) construction covers exactly this and
#   is reused verbatim in shape: the offending encodings run on TILE harts, and
#   HART 0 -- which never executes one -- keeps the ordinary a0 contract and
#   observes the tiles through a PROGRESS-word protocol.
#       PROGRESS = 1   the victim reached its encoding and is wedged in it
#                      => it TRAPPED          (post-fix: the PASS condition)
#       PROGRESS = 2   the victim executed straight through the encoding
#                      => it RETIRED          (pre-fix: THE FINDING)
#   Both polarities end at a0.  Nothing here depends on a trapCsr build.
#
# THE THREE TILE HARTS
#   hart 1  VICTIM   0x081ece33   pack x28, x29, x1    rs2 field = 00001
#   hart 2  VICTIM   0x09fece33   pack x28, x29, x31   rs2 field = 11111
#           Both victims use the SAME rs1 = 0x12345678 and DIFFERENT rs2 values
#           (0x9ABCDEF0 and 0x0F0F0F0F).  The two extremes of the rs2 field are
#           covered, and because true `pack` would return 0xDEF05678 and
#           0x0F0F5678 while the ZEXT.H row returns 0x00005678 for both, the
#           stored results discriminate "aliased onto zext.h" from any other
#           way of retiring.  That identical-results signature is the K3 blind
#           validation's own evidence, reproduced directed.
#   hart 3  CONTROL  0x09fefe33   packh x28, x29, x31
#           packh must trap on this build TODAY and after any fix.  It is here
#           to prove the observation path is LIVE PRE-FIX: without it, "PROGRESS
#           stays at 1" is a state this test would never have been seen to
#           produce, and an instrument whose pass-side has never fired is not an
#           instrument.  It is also the over-reach guard on the default build:
#           a fix that legalises packh shows up here as 0xBADA0003.
#   The victims wedge in TCM (TRAP_STATE fetches pc_next_trad_reg, a TCM address
#   here), so they raise no arbiter traffic that could disturb hart 0.  The
#   instruction placed immediately after every encoding is an `addi`, never a
#   store, so F8 (TRAP_STATE committing the word at pc+4 when it decodes as a
#   store) cannot fire.
#
# THE POSITIVE HALF runs on HART 0, before any launch, in BOTH polarities, and
#   must pass today AND forever.  Five legal encodings plus a base-ISA sanity
#   check; its proof is twofold -- the VALUES are asserted, and on a default
#   build a wrongly-trapped instruction wedges hart 0 terminally, so hart 0
#   reaching any verdict at all is proof none of them trapped (LIVENESS).
#   POSPROG counts the legs so a wedged run can be located exactly.
#       P0  base ISA add
#       P1  pack x28, x29, x0   rs1 = 0x12345678  ->  0x00005678
#       P2  pack x28, x29, x0   rs1 = 0xFFFFFFFF  ->  0x0000FFFF
#       P3  pack x28, x29, x0   rs1 = 0x0000ABCD  ->  0x0000ABCD
#       P4  pack x28, x0,  x0                     ->  0x00000000
#       P5  zext.h x28, x29     the MNEMONIC, via .option arch +zbb, so gas
#                               chooses the encoding -- proof that the canonical
#                               zext.h is the rs2 = x0 form and that it is legal
#   Every one of these has rs2 = x0.  Hart 0 NEVER executes an rs2 != x0
#   encoding, in either polarity: that is what keeps hart 0 alive post-fix.
#
# THE ZBKB-ON ARM (#ifdef CORE_ENABLE_ZBKB) is the guard against an OVER-WIDE
#   fix.  On a Zbkb build every one of these must keep working; a fix that made
#   the whole pack space illegal, or that broke zext.h, fails here.  It is
#   single-hart -- nothing traps on that build, so no observer is needed.
#       O1  pack x28, x29, x30  0x12345678 / 0x9ABCDEF0  ->  0xDEF05678
#       O2  pack x28, x29, x30  0x12345678 / 0x0000FFFF  ->  0xFFFF5678
#       O3  pack x28, x29, x30  0x12345678 / 0x00010000  ->  0x00005678
#           (deliberate: a nonzero rs2 whose low half is 0 returns the SAME
#            value zext.h would.  Value alone cannot separate the two rows --
#            the difference is legality, and only legality.)
#       O4  packh x28, x29, x30 0x12345678 / 0x9ABCDEF0  ->  0x0000F078
#
# THE PASS-POLARITY CONTROL (-DPACKALIAS_PASS_CONTROL, default build only).
#   A detector that has never been seen to PASS is as untrustworthy as one that
#   has never been seen to FAIL: it might be structurally incapable of passing.
#   Building with -DPACKALIAS_PASS_CONTROL replaces BOTH victims' encodings with
#   packh -- which traps on this build today -- so all three tiles wedge, hart 0
#   observes PROGRESS = 1 from all three, and the a0 = 0xCAFEBABE path is
#   exercised END TO END on the UNFIXED tree.  It is a control, not a detector:
#   it makes no claim about F-BV1.  It is also the closest available rehearsal
#   of the post-fix run, and it costs no RTL change to obtain.
#
# BUILD POLARITY.  The OFF arm is the default:  never auto-derive
#   CORE_ENABLE_ZBKB from a generated header.  To build the ON arm, pass
#   -DCORE_ENABLE_ZBKB explicitly in RISCV_GCC_OPTS (the extprobe_template.S
#   convention) and run it on a Zbkb-ON staged build.
#   REQUIRES ENABLE_BITMANIP (Zbb) TRUE in both arms -- zext.h itself is a Zbb
#   encoding, so this test is not valid on a castalia_nobitmanip build.
#
# ---------------------------------------------------------------------------
# VERDICT.  a0 = 0xCAFEBABE => F-BV1 is fixed (or, on the ON arm, Zbkb still
# works).  a0 = 0xDEADBEEF with:
#   a1 = 0xBADA0010   BOTH victims retired, BOTH returning 0x00005678: rs2 is
#                     ignored and the encodings aliased onto zext.h  <-- F-BV1
#                     (a2 = victim 1's rd, a3 = victim 2's rd)
#   a1 = 0xBADA0011   both retired, victim 1's rd is NOT the zext.h value
#   a1 = 0xBADA0012   both retired, victim 2's rd is NOT the zext.h value
#   a1 = 0xBADA0001   only victim 1 (rs2 = x1) retired
#   a1 = 0xBADA0002   only victim 2 (rs2 = x31) retired
#   a1 = 0xBADA0003   hart 3 retired: packh became legal without Zbkb -- NOT
#                     F-BV1, an over-wide fix (checked first, it is a different
#                     class)
#   a1 = 0x5E1A0001   a positive-half zext.h leg returned the wrong value
#   a1 = 0x5E1A0002   a victim never armed: it did not reach its encoding
#   a1 = 0x5E1A0003   a progress word did not read back: shared-RAM setup break
#   a1 = 0x5E1A0004   base-ISA sanity failed
#   a1 = 0x5E1A0005   POSPROG did not count every positive leg
# NO a0 AT ALL (tb watchdog) is itself a result: hart 0 wedged inside its own
#   positive half, i.e. THE FIX OVER-REACHES and made a legal zext.h illegal.
#   Probe POSPROG (0x104D4) and :dut:hart0:core:pc to name the leg.
#
# NOT IN ANY STANDING LIST.  Post-fix all three tiles are parked in TRAP_STATE
#   forever and never write a0_1/a0_2/a0_3; riscv_tb reports "tile hart(s)
#   silent/parked", a NOTE, not a failure.  Invoke explicitly with
#   ./xrun_batch.sh rv32ua-p-packalias.
#   The image name carries NO x padding: the 22-character basename contract
#   counts the ".rcf" suffix, and "rv32ua-p-packalias.rcf" is already 22, so
#   TEST_FILE is "../rcf/rv32ua-p-packalias.rcf" -- 29 characters exactly.
#
# SHARED WORDS CLAIMED (all < 0x10500 and inside the bootrom zero range)
#     0x104D4  POSPROG  hart 0's positive-half leg counter
#     0x104D8  VAL1     victim 1's rd after its encoding
#     0x104DC  VAL2     victim 2's rd after its encoding
#     0x104F4  PROG1    victim 1's progress
#     0x104F8  PROG2    victim 2's progress
#     0x104FC  PROG3    hart 3 control's progress
#   Both bands are free at N=4 AND at N=18.  0x104D4-0x104DC sits between
#   shafe's N=18 TURN (0x104D0) and shevfab's SRC (0x104E0); 0x104F4-0x104FC
#   sits between rocsrwmp's NEGPROG (0x104F0) and the bootrom loader rows
#   (0x10500).
#*****************************************************************************

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
