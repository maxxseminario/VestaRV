# See LICENSE for license details.

#*****************************************************************************
# shi2c.S  (M7c.2; M12 single-ROM boot rework; Argus A3 claim-based rework)
#-----------------------------------------------------------------------------
# HART-GENERIC shared I2C0/I2C1 test.
#
# M12: tiles are NO LONGER preloaded. Hart 0 stages this TCM image once and
# launches all tiles 1..NHARTS-1 into tile_entry through the bootrom loader
# (mp_boot.h); each tile then parks on the GO gate.
#
# M7c.2 moved both I2Cs onto the mp_arbiter; M11 put them back at their legacy
# addresses: I2C0 = 0x4E00, I2C1 = 0x4F00 (offsets CR/FCR/SR/MTX/MRX/STX/SRX/
# AR/AMR at +0/4/8/C/10/14/18/1C/20); the windows are LIVE for all harts.
#
# THE AUDIT FINDING THIS TEST GUARDS: I2C.vhd's register read is COMBINATIONAL
# (rdata collapses to CR when enable deasserts), so the MCU-side bridge REGISTERS
# it at the LATCH->DATA edge (i2c_rdata_bridge). The AR reset readbacks
# (I2C0=0x79, I2C1=0x23 — nonzero, per-instance distinct, != CR reset 0) fail
# loudly if that bridge register is ever lost. Each role's dance runs the AR
# check for its OWN instance, so both bridge paths are covered.
#
# ARGUS A3 CLAIM-BASED OWNERSHIP (user decision 2026-07-10): the two I2Cs are a
# POOL of claimable roles. Any hart may atomically CLAIM a free I2C through the
# HW mutex bank (0x6000, 1-insn acquire); the winner owns it EXCLUSIVELY (mutex
# never released) and runs the FULL self-contained dance once (AR bridge proof +
# AMR/STX/CR write-readback + CR restore), then records ROLEDONE[i]. Harts that
# find both taken just park. With NHARTS >= NROLES claimers the mutex bank
# guarantees BOTH I2Cs are exercised EXACTLY once. Verified at N=4 AND N=18.
#
#   Role 0 = I2C0 dance (SAD 0x79)   Role 1 = I2C1 dance (SAD 0x23)
#
# No SMCLK dependence (nothing is enabled; the register file is on the free-
# running arbiter clock). The dance never sets SEN/MEN/SCS; only IE (12:0) and
# MDIV (16:13). Register-level test (the tb has no I2C bus devices).
#
# Shared words (>= 0x10200, clear of earlier tests' words, all < 0x10500):
#     GO            = 0x10200            0x12C60000 after hart 0 opens the gate
#     DONE[h]       = 0x10204 + 4*h      0x12C00000+h after hart h finishes
#     ROLEDONE[i]   = 0x10204 + 4*NHARTS + 4*i   0x12CD0000+i after role i runs
#   (mutex bank 0x6000+4*i provides the atomic claim; nothing in shared RAM)
# ROLEDONE sits at DONE_BASE + 4*NHARTS so the DONE array can't overrun it
# (N=18: DONE 0x10204..0x10248, ROLEDONE 0x1024C..0x10250).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_I2C0    0x4E00
#define SH_I2C1    0x4F00
#define MUTEX_BASE 0x6000              /* HW mutex bank: mutex i guards role i */
#define NROLES     2
#define GO            0x10200
#define DONE_BASE     0x10204
#define ROLEDONE_BASE (DONE_BASE + 4*NHARTS)
#define GO_MAGIC      0x12C60000
#define DONE_MAGIC    0x12C00000
#define ROLE_MAGIC    0x12CD0000
#define CR_TESTVAL 0x1E01F      /* IE bits 4:0 + 12:8, MDIV=0xF; SEN/MEN=0 */
#define I2C0_SAD   0x79
#define I2C1_SAD   0x23

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher

    # M12 single-ROM boot: stage this TCM image once, launch all tiles into
    # tile_entry through the bootrom loader (mp_boot.h). They park on GO.
    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined for tiles until now)
    .option pop

    li   sp, 0xBFF0             # private TCM top (IRQ_SV contract)

    li   s3, GO
    li   s4, DONE_BASE

    beqz s10, hart0

    # ---- tiles: wait for GO, then claim-and-run one role -------------------
tile_go_wait:
    lw   t0, 0(s3)
    li   t1, GO_MAGIC
    bne  t0, t1, tile_go_wait
    jal  ra, claim_and_run
    j    report

    # ---- hart 0: open GO (no clock/reset setup needed), claim + judge ------
hart0:
    li   t0, GO_MAGIC
    sw   t0, 0(s3)             # open GO: every hart may claim from here
    jal  ra, claim_and_run    # hart 0 also competes for an I2C

    # adjudicate: wait every tile's DONE, then verify both ROLEDONE ----------
    li   s6, 1
done_gather:
    li   t6, 100000
1:  slli t0, s6, 2
    add  t0, t0, s4
    lw   t1, 0(t0)            # DONE[s6]
    li   t2, DONE_MAGIC
    add  t2, t2, s6
    beq  t1, t2, 2f
    addi t6, t6, -1
    bnez t6, 1b
    j    shi2c_fail
2:  addi s6, s6, 1
    li   t0, NHARTS
    bltu s6, t0, done_gather

    li   s6, 0                # verify each I2C was exercised EXACTLY once
role_check:
    li   t0, ROLEDONE_BASE
    slli t1, s6, 2
    add  t0, t0, t1
    lw   t1, 0(t0)
    li   t2, ROLE_MAGIC
    add  t2, t2, s6
    bne  t1, t2, shi2c_fail
    addi s6, s6, 1
    li   t0, NROLES
    bltu s6, t0, role_check

    RVTEST_PASS               # a0 = 0xCAFEBABE, spin

    # ---- every hart ends here: record DONE, PASS, verify DONE forever ------
report:
    slli t0, s10, 2
    add  t0, t0, s4
    li   t1, DONE_MAGIC
    add  t1, t1, s10
    sw   t1, 0(t0)            # DONE[h]
    li   a0, 0xCAFEBABE       # inline PASS (tb latches a0_1..a0_(N-1))
tile_verify:                  # forever: DONE must survive other traffic
    lw   t2, 0(t0)
    bne  t2, t1, shi2c_fail
    j    tile_verify

shi2c_fail:
    RVTEST_FAIL               # a0 = 0xDEADBEEF, spin

    # ---- claim_and_run: atomically claim the first FREE I2C via the mutex
    # ---- bank, run its dance once, mark ROLEDONE[i]. Returns without claiming
    # ---- if both are taken. Saves ra in s0, role in s1; i2c_dance uses s2/s5
    # ---- + t0/t1 and preserves s0/s1/s3/s4/s10. ----------------------------
claim_and_run:
    mv   s0, ra               # save return (i2c_dance clobbers nothing saved)
    li   s1, 0                # role index
cr_try:
    li   t0, MUTEX_BASE
    slli t1, s1, 2
    add  t0, t0, t1
    lw   t2, 0(t0)           # 1-insn atomic claim: 0 = I now own role s1
    beqz t2, cr_won
    addi s1, s1, 1
    li   t3, NROLES
    bltu s1, t3, cr_try
    mv   ra, s0              # both taken — no role for me
    jalr zero, 0(ra)
cr_won:
    bnez s1, cr_i2c1         # role 0 = I2C0; role 1 = I2C1
    li   s2, SH_I2C0
    li   s5, I2C0_SAD
    j    cr_run
cr_i2c1:
    li   s2, SH_I2C1
    li   s5, I2C1_SAD
cr_run:
    jal  ra, i2c_dance
    li   t0, ROLEDONE_BASE
    slli t1, s1, 2
    add  t0, t0, t1
    li   t2, ROLE_MAGIC
    add  t2, t2, s1
    sw   t2, 0(t0)           # ROLEDONE[i] = magic+i (exactly one writer)
    mv   ra, s0
    jalr zero, 0(ra)

    # ---- i2c_dance: self-contained register-level exercise of the I2C at s2
    # ---- (expected AR reset SAD in s5). AR bridge proof, AMR/STX write-back,
    # ---- CR write-readback, then CR restored to 0 (exclusive owner cleans up).
    # ---- Never sets SEN/MEN/SCS. Clobbers t0/t1.
    # ---- CR+0 FCR+4 SR+8 MTX+C MRX+10 STX+14 SRX+18 AR+1C AMR+20 -----------
i2c_dance:
    lw   t0, 0(s2)           # CR resets 0
    bnez t0, shi2c_fail
    lw   t0, 28(s2)          # AR resets to this instance's SAD — the
    bne  t0, s5, shi2c_fail  # combinational-read-bridge check (!= CR!)
    lw   t0, 8(s2)           # SR: no flags at reset
    bnez t0, shi2c_fail
    lw   t0, 16(s2)          # MRX resets 0
    bnez t0, shi2c_fail
    li   t0, 0x51
    sw   t0, 32(s2)          # AMR write/readback (7 bits)
    lw   t1, 32(s2)
    bne  t1, t0, shi2c_fail
    sw   zero, 32(s2)        # restore AMR = 0
    lw   t1, 32(s2)
    bnez t1, shi2c_fail
    li   t0, 0xA7
    sw   t0, 20(s2)          # STX write/readback (8 bits)
    lw   t1, 20(s2)
    bne  t1, t0, shi2c_fail
    li   t0, CR_TESTVAL
    sw   t0, 0(s2)           # CR write (IE+MDIV only)...
    lw   t1, 0(s2)
    bne  t1, t0, shi2c_fail  # ...and readback
    sw   zero, 0(s2)         # restore CR = 0 (exclusive owner cleans up)
    lw   t1, 0(s2)
    bnez t1, shi2c_fail
    jalr zero, 0(ra)

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
