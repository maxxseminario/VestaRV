# See LICENSE for license details.

#*****************************************************************************
# wntag.S  (COTS NFC tag bring-up -- NXP NTAG 5 on the I2C0 pads)
#-----------------------------------------------------------------------------
# Drives the I2C0 MASTER against an external NXP NTAG 5 tag model
# (hdl/common/tb/ntag5_model.vhd, an I2C SLAVE at the datasheet default 7-bit
# address 54h) hung off the shared open-drain SDA0/SCL0 pad planes P4.0/P4.1
# (LQFP-100 pins 37/38). Single-hart directed (hart 0; tiles park).
#
# This is the FIRMWARE side of the "can the synthesized chip talk to a real
# COTS part" question -- it is meant to run at gate level with SDF, where the
# bits really move through synthesized logic and pad models.
#
# TB CONTRACT (same as wi2ct.S): riscv_tb gives P4.0/P4.1 a WEAK 'H' pull so
# the open-drain bus idles high; the tag model resolves its own strong lows
# onto the same nets. No firmware REN is needed. I2C0's serial core is SMCLK,
# so SYSCLK_CR_ADDR = 0 first (the bootrom parks SMCLK on LFXT = 32.768 kHz and a
# frame would then take ~10 ms). PAD ROUTING: SDA0/SCL0 are the AF0 (home)
# function of P4.0/P4.1 but a pin only drives its alt-function when GPIO3
# PxSEL = 1 (reset is PxSEL = 0 = plain GPIO) -- without it the master reads
# back an undriven pad and loses arbitration mid-address.
#
# NTAG 5 FRAME SHAPES ([L] NTP53x2 data sheet Rev. 3.2, 8.3.1.4). There is NO
# flat byte address: every access opens with a 16-bit BLOCK address, MSB
# first, and a block is 4 bytes.
#   MEMORY write : S SL_AD+W BL_AD1 BL_AD0 D0 D1 D2 D3 P     (exactly 1 block)
#   MEMORY read  : S SL_AD+W BL_AD1 BL_AD0 P, S SL_AD+R D... NACK P
#   REGISTER (blocks 10A0h-10AFh) reads take a THIRD address byte REGA:
#                  S SL_AD+W BL_AD1 BL_AD0 REGA P, S SL_AD+R REGDAT NACK P
#
# WHAT IS CHECKED
#   L1  MEMORY READ of user block 0000h == E1 40 80 09 -- the NFC Forum
#       capability container the part ships with ([L] Tab. 7). The chip cannot
#       manufacture these bytes; they can only come off the tag.
#   L2  MEMORY WRITE of DE AD C0 DE into user block 0040h, then a fresh
#       pointer-set + read-back of the same block. Proves the tag took real
#       state from the chip (NTAG 5 commits an EEPROM block write on the STOP).
#   L3  REGISTER READ of STATUS0_REG (block 10A0h, REGA 0) == 02h:
#       VCC_SUPPLY_OK = 1, NFC_FIELD_OK = 0 (no reader field in this bench).
#       Exercises the second, incompatible frame shape.
#   L4  NEGATIVE: addressing 7-bit 2Ah (address byte 54h -- note that 54h is
#       the tag's 7-bit address, a classic off-by-a-shift) must be NACKed.
#       Proves the model is address-selective rather than ACKing everything.
#
# I2C0 master (I2C.vhd AS-BUILT; base 0x4E00):
#   CR  0x4E00 : ... MDIV[16:13] ... MEN[21]
#   FCR 0x4E04 : MRB[0] MSP[1] MST[2] SC[3]      (write-1 command bits;
#                MSP/MRB are ignored unless MCB -- this master owns the bus)
#   SR  0x4E08 : SPR[0] STR[1] MXC[2] MNR[3] MTXE[4] MARB[5] MSPS[6] MSTS[7]
#                ... MCB[14] BS[15]              (MXC/MNR/MSPS are W1C)
#   MTX 0x4E0C : master transmit byte (a write with MEN=1 issues MasterWrite);
#                the FIRST byte after a START is {SAD<<1 | RnW}
#   MRX 0x4E10 : master receive byte
#
# WHY EVERY STOP IS POLLED (I2C.vhd race, found writing this test): the master
# FSM asserts ClearI2CMST for one ClkMaster period inside MasterStateStop2, so
# a START written into FCR during the stop cadence is silently swallowed. Each
# I2STOP therefore W1C-clears MSPS, commands the stop, and polls MSPS back to
# 1 (set in MasterStateStop3) before the next frame may open.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define SYSCLK_CR_ADDR   0x4900
#define I2C0_CR      0x4E00
#define I2C0_FCR     0x4E04
#define I2C0_SR      0x4E08
#define I2C0_MTX     0x4E0C
#define I2C0_MRX     0x4E10
#define GPIO3_SEL    0x4D24            /* GPIO3 PxSEL: SDA0/SCL0 alt-func on P4.0/1 */

#define I2C0_CR_VAL  0x00202000        /* MEN(21) | MDIV=1 (SCL ~ smclk/32) */

/* I2C0 SR bits */
#define MSR_MXC      0x004
#define MSR_MNR      0x008
#define MSR_MSPS     0x040
#define MSR_CLR3     0x04C             /* W1C MXC | MNR | MSPS */

/* I2C0 FCR command bits */
#define FCR_MRB      0x1
#define FCR_MSP      0x2
#define FCR_MST      0x4

/* address bytes {SAD<<1 | RnW} */
#define NTAG_W       0xA8              /* write to 7-bit 54h (NTAG 5 default) */
#define NTAG_R       0xA9              /* read  from 7-bit 54h                */
#define BAD_W        0x54              /* write to 7-bit 2Ah -- nobody home   */

# ---- bounded poll of (I2C0 SR & mask) != 0; s3 = countdown ----------------
.macro PSR mask, failt
    li   s3, 20000
.Lpsr_lp\@:
    li   a0, I2C0_SR
    lw   t0, 0(a0)
    andi t0, t0, \mask
    bnez t0, .Lpsr_done\@
    addi s3, s3, -1
    bnez s3, .Lpsr_lp\@
    j    \failt
.Lpsr_done\@:
.endm

# ---- START (clear stale MXC/MNR/MSPS first) -------------------------------
.macro I2START
    li   a0, I2C0_SR
    li   t1, MSR_CLR3
    sw   t1, 0(a0)
    li   a0, I2C0_FCR
    li   t1, FCR_MST
    sw   t1, 0(a0)
.endm

# ---- transmit one byte; the addressed device MUST ACK ---------------------
.macro I2WR val, failt
    li   a0, I2C0_MTX
    li   t1, \val
    sw   t1, 0(a0)
    PSR  MSR_MXC, \failt
    li   a0, I2C0_SR
    lw   t0, 0(a0)
    andi t0, t0, MSR_MNR
    bnez t0, \failt
    li   a0, I2C0_SR
    li   t1, MSR_MXC
    sw   t1, 0(a0)
.endm

# ---- transmit one byte; the bus MUST answer with a NACK -------------------
.macro I2WRN val, failt
    li   a0, I2C0_MTX
    li   t1, \val
    sw   t1, 0(a0)
    PSR  MSR_MXC, \failt
    li   a0, I2C0_SR
    lw   t0, 0(a0)
    andi t0, t0, MSR_MNR
    beqz t0, \failt
    li   a0, I2C0_SR
    li   t1, MSR_MXC
    sw   t1, 0(a0)
.endm

# ---- receive one byte into \dst and ACK it (\dst != a0/t0/t1/s3) ----------
.macro I2RD dst, failt
    li   a0, I2C0_FCR
    li   t1, FCR_MRB
    sw   t1, 0(a0)
    PSR  MSR_MXC, \failt
    li   a0, I2C0_MRX
    lw   \dst, 0(a0)
    li   a0, I2C0_SR
    li   t1, MSR_MXC
    sw   t1, 0(a0)
.endm

# ---- STOP (NACKs a pending read byte) and wait for it to leave the wire ---
.macro I2STOP failt
    li   a0, I2C0_SR
    li   t1, MSR_MSPS
    sw   t1, 0(a0)
    li   a0, I2C0_FCR
    li   t1, FCR_MSP
    sw   t1, 0(a0)
    PSR  MSR_MSPS, \failt
.endm

# ---- compare the last received byte in s5 against an expected value -------
.macro EXPB val, failt
    li   t3, \val
    bne  s5, t3, \failt
.endm

# ---- crude bounded delay --------------------------------------------------
.macro DELAYN n
    li   s4, \n
.Ldly_lp\@:
    addi s4, s4, -1
    bnez s4, .Ldly_lp\@
.endm

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0                   # valid stack (no IRQs here, but cheap)

    # ================= L0: clocks + pad routing + master ==============
    li   a0, SYSCLK_CR_ADDR
    sw   x0, 0(a0)                    # SMCLK -> HFXT (I2C0 core is smclk)

    li   a0, GPIO3_SEL
    li   t1, 0x3
    sw   t1, 0(a0)                    # P4.0/P4.1 -> SDA0/SCL0 (AF0)

    li   a0, I2C0_CR
    li   t1, I2C0_CR_VAL
    sw   t1, 0(a0)                    # MEN | MDIV=1

    # ================= L1: read the capability container ==============
    # point the tag at user block 0000h
    I2START
    I2WR NTAG_W, wntag_fail
    I2WR 0x00,   wntag_fail           # BL_AD1
    I2WR 0x00,   wntag_fail           # BL_AD0
    I2STOP wntag_fail

    # read 4 bytes; the 4th is NACKed by the STOP
    I2START
    I2WR NTAG_R, wntag_fail
    I2RD s5, wntag_fail
    EXPB 0xE1, wntag_fail
    I2RD s5, wntag_fail
    EXPB 0x40, wntag_fail
    I2RD s5, wntag_fail
    EXPB 0x80, wntag_fail
    I2RD s5, wntag_fail
    EXPB 0x09, wntag_fail
    I2STOP wntag_fail

    # ================= L2: write a user block, read it back ===========
    I2START
    I2WR NTAG_W, wntag_fail
    I2WR 0x00,   wntag_fail           # BL_AD1
    I2WR 0x40,   wntag_fail           # BL_AD0 -> user block 0040h
    I2WR 0xDE,   wntag_fail
    I2WR 0xAD,   wntag_fail
    I2WR 0xC0,   wntag_fail
    I2WR 0xDE,   wntag_fail           # 4th data byte decides writability
    I2STOP wntag_fail                 # STOP commits the EEPROM block

    DELAYN 64                         # let the EEPROM programming cycle end

    I2START
    I2WR NTAG_W, wntag_fail
    I2WR 0x00,   wntag_fail
    I2WR 0x40,   wntag_fail
    I2STOP wntag_fail

    I2START
    I2WR NTAG_R, wntag_fail
    I2RD s5, wntag_fail
    EXPB 0xDE, wntag_fail
    I2RD s5, wntag_fail
    EXPB 0xAD, wntag_fail
    I2RD s5, wntag_fail
    EXPB 0xC0, wntag_fail
    I2RD s5, wntag_fail
    EXPB 0xDE, wntag_fail
    I2STOP wntag_fail

    # ================= L3: REGISTER read of STATUS0_REG ===============
    # block 10A0h, REGA 0 -> the register frame shape (third address byte)
    I2START
    I2WR NTAG_W, wntag_fail
    I2WR 0x10,   wntag_fail           # BL_AD1
    I2WR 0xA0,   wntag_fail           # BL_AD0 -> session register block
    I2WR 0x00,   wntag_fail           # REGA = 0 (STATUS0_REG)
    I2STOP wntag_fail

    I2START
    I2WR NTAG_R, wntag_fail
    I2RD s5, wntag_fail
    EXPB 0x02, wntag_fail             # VCC_SUPPLY_OK=1, NFC_FIELD_OK=0
    I2STOP wntag_fail

    # ================= L4: NEGATIVE -- wrong slave address ============
    I2START
    I2WRN BAD_W, wntag_fail           # 7-bit 2Ah: must NACK
    I2STOP wntag_fail

    RVTEST_PASS                       # a0 = 0xCAFEBABE

wntag_fail:
    RVTEST_FAIL                       # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) -- the pass/fail
    # spins above must come from RVTEST_PASS/RVTEST_FAIL, never fall-through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
