# See LICENSE for license details.

#*****************************************************************************
# shi2c.S  (M7c.2)
#-----------------------------------------------------------------------------
# HART-GENERIC shared I2C0/I2C1 test.
#
# M7c.2 moved both I2Cs onto the mp_arbiter at their mirror slots:
#     I2C0 0x4E00 -> 0x13E00 (slot 14)     I2C1 0x4F00 -> 0x13F00 (slot 15)
# Register offsets unchanged (CR/FCR/SR/MTX/MRX/STX/SRX/AR/AMR at
# +0/4/8/C/10/14/18/1C/20); old windows read zeros.
#
# THE AUDIT FINDING THIS TEST GUARDS: I2C.vhd's register read is
# COMBINATIONAL (every other moved peripheral registers its own read) — its
# rdata collapses to register 0 (CR) the moment the enable deasserts, which
# would make the arbiter's end-of-DATA capture return CR for EVERY address.
# The MCU-side bridge therefore REGISTERS the I2C rdata at the LATCH->DATA
# edge (i2c_rdata_bridge). The AR-reset readbacks below (I2C0=0x79,
# I2C1=0x23 — nonzero, distinct per instance, and DIFFERENT from CR's reset
# value 0) fail loudly if that bridge register is ever lost.
#
# The tb has no I2C bus devices (SCL/SDA pads sit behind GPIO3's PxSEL,
# which resets to GPIO mode), so this is a REGISTER-LEVEL test: master/slave
# enables (CR bits 21:20) and clock-stretch select (18) are never set; only
# IE bits (12:0) and MDIV (16:13) are written. Sequence per hart:
#   hart 0: old 0x4E00/0x4F00 windows dead; I2C0 dance; token=1
#   hart 1: I2C0 CR must still read hart 0's value (cross-hart visibility),
#           then restore CR=0 and verify; token=2
#   hart 2: I2C1 dance; token=3
#   hart 3: I2C1 CR visibility + restore + AR readback again; token=4
# Dance = CR reads 0 at reset; CR write/readback (0x1E01F: IE bits + MDIV);
# AR reads its reset SAD; AMR write/readback + restore; STX write/readback;
# SR reads 0 (no flags at reset); MRX reads 0.
#
# No SMCLK dependence (nothing is enabled; the register file is on the
# free-running arbiter clock) — no SYS_CLK_CR write needed. All parking is
# read-only on the token.
#
# Shared words (>= 0x10200, clear of all earlier tests' words):
#     TOKEN    = 0x10200          whose turn (shram zero-init => hart 0)
#     DONE[h]  = 0x10210 + 4*h    0x12C00000+h after hart h's dance
# (next free shared word: 0x10220)
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define SH_I2C0    0x13E00
#define SH_I2C1    0x13F00
#define TOKEN      0x10200
#define DONE_BASE  0x10210
#define CR_TESTVAL 0x1E01F      /* IE bits 4:0 + 12:8, MDIV=0xF; SEN/MEN=0 */
#define I2C0_SAD   0x79
#define I2C1_SAD   0x23

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop

    li   sp, 0xFFF0             # private RAM1 top (IRQ_SV contract)

    li   s3, TOKEN
    li   s4, DONE_BASE
    li   s6, 0x12C00000         # DONE magic base

    beqz s10, hart0

    # ---- harts 1-3: park on the token (reads only), then one dance --------
token_wait:
    lw   t0, 0(s3)
    bne  t0, s10, token_wait

    li   t0, 2
    beq  s10, t0, hart2
    li   t0, 3
    beq  s10, t0, hart3

    # ---- hart 1: I2C0 cross-hart visibility + restore ----------------------
    li   s2, SH_I2C0
    lw   t0, 0(s2)              # CR: hart 0's test value must be visible
    li   t1, CR_TESTVAL
    bne  t0, t1, shi2c_fail
    sw   zero, 0(s2)            # restore CR = 0...
    lw   t0, 0(s2)
    bnez t0, shi2c_fail         # ...and verify
    j    report

    # ---- hart 2: full I2C1 dance --------------------------------------------
hart2:
    li   s2, SH_I2C1
    li   s5, I2C1_SAD
    jal  ra, i2c_dance
    j    report

    # ---- hart 3: I2C1 visibility + restore + AR again -----------------------
hart3:
    li   s2, SH_I2C1
    lw   t0, 0(s2)              # CR: hart 2's test value must be visible
    li   t1, CR_TESTVAL
    bne  t0, t1, shi2c_fail
    sw   zero, 0(s2)            # restore CR = 0
    lw   t0, 0(s2)
    bnez t0, shi2c_fail
    lw   t0, 28(s2)             # AR still reads the reset SAD (0x23)
    li   t1, I2C1_SAD
    bne  t0, t1, shi2c_fail

report:
    slli t0, s10, 2
    add  t0, t0, s4
    add  t1, s6, s10
    sw   t1, 0(t0)              # DONE[h]
    addi t0, s10, 1
    sw   t0, 0(s3)              # pass the token on
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
    slli t0, s10, 2
    add  t0, t0, s4
    add  t1, s6, s10
tile_verify:                    # forever: DONE must survive other traffic
    lw   t2, 0(t0)
    bne  t2, t1, shi2c_fail
    j    tile_verify

    # ---- hart 0 -------------------------------------------------------------
hart0:
    li   t0, 0x4E00             # OLD private I2C0 window: dead, reads 0
    lw   t1, 0(t0)
    bnez t1, shi2c_fail
    lw   t1, 28(t0)             # (was AR = 0x79 — must be gone)
    bnez t1, shi2c_fail
    li   t0, 0x4F00             # OLD I2C1 window
    lw   t1, 28(t0)
    bnez t1, shi2c_fail

    li   s2, SH_I2C0
    li   s5, I2C0_SAD
    jal  ra, i2c_dance          # leaves CR = CR_TESTVAL for hart 1 to see

    li   t0, 1
    sw   t0, 0(s3)              # TOKEN = 1: release the ring

    li   t6, 20000              # bounded-wait for the ring to come home
ring_wait:
    lw   t0, 0(s3)
    li   t1, 4
    beq  t0, t1, ring_home
    addi t6, t6, -1
    bnez t6, ring_wait
    j    shi2c_fail
ring_home:
    li   t3, 1                  # verify DONE[1..3]
done_check:
    slli t0, t3, 2
    add  t0, t0, s4
    lw   t1, 0(t0)
    add  t2, s6, t3
    bne  t1, t2, shi2c_fail
    addi t3, t3, 1
    li   t0, 4
    bne  t3, t0, done_check

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shi2c_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # ---- i2c_dance: register-level exercise of the I2C at s2 (expected AR
    # ---- reset SAD in s5). Leaves CR = CR_TESTVAL (next hart verifies +
    # ---- restores). Never sets SEN/MEN/SCS. Clobbers t0/t1. ----------------
    # ---- CR+0 FCR+4 SR+8 MTX+C MRX+10 STX+14 SRX+18 AR+1C AMR+20 ----------
i2c_dance:
    lw   t0, 0(s2)              # CR resets 0
    bnez t0, shi2c_fail
    lw   t0, 28(s2)             # AR resets to this instance's SAD — the
    bne  t0, s5, shi2c_fail     # combinational-read-bridge check (≠ CR!)
    lw   t0, 8(s2)              # SR: no flags at reset
    bnez t0, shi2c_fail
    lw   t0, 16(s2)             # MRX resets 0
    bnez t0, shi2c_fail
    li   t0, 0x51
    sw   t0, 32(s2)             # AMR write/readback (7 bits)
    lw   t1, 32(s2)
    bne  t1, t0, shi2c_fail
    sw   zero, 32(s2)           # restore AMR = 0
    lw   t1, 32(s2)
    bnez t1, shi2c_fail
    li   t0, 0xA7
    sw   t0, 20(s2)             # STX write/readback (8 bits)
    lw   t1, 20(s2)
    bne  t1, t0, shi2c_fail
    li   t0, CR_TESTVAL
    sw   t0, 0(s2)              # CR write (IE+MDIV only)...
    lw   t1, 0(s2)
    bne  t1, t0, shi2c_fail     # ...and readback; left set for the next hart
    jalr zero, 0(ra)

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
