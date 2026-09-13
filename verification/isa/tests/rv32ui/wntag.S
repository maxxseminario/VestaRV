# See LICENSE for license details.

# VestaRV: COTS NFC tag bring-up over I2C0
# It drives the I2C0 MASTER against an external NXP NTAG 5 model, an I2C SLAVE at the datasheet default 7-bit address 54h, hung off the shared open-drain SDA0/SCL0 pad planes P4.0 and P4.1. Single hart, with the tiles parked. It is the firmware side of "can the synthesized chip talk to a real COTS part", and is meant to run at gate level with SDF, where the bits really move through synthesized logic and pad models.
# TB CONTRACT: riscv_tb gives P4.0 and P4.1 a WEAK 'H' pull so the open-drain bus idles high and the tag model resolves its own strong lows onto the same nets, so no firmware pull-enable is needed. I2C0's serial core is SMCLK, SO SYS_CLK_CR MUST BE ZEROED FIRST, since the boot ROM parks SMCLK on LFXT at 32.768 kHz and a frame would then take about 10 ms. PAD ROUTING IS NOT AUTOMATIC: SDA0 and SCL0 are the AF0 home function of those pins, but a pin only drives its alternate function when GPIO3 PxSEL is 1, and PxSEL resets to 0, so without it the master reads back an undriven pad and loses arbitration mid-address.
# NTAG 5 FRAME SHAPES, from the data sheet: THERE IS NO FLAT BYTE ADDRESS, every access opens with a 16-bit BLOCK address, MSB first, and a block is 4 bytes. A memory write is S, slave address with W, the two block-address bytes, four data bytes, P, and writes exactly one block. A memory read is S, slave address with W, the two block-address bytes, P, then S, slave address with R, the data, a NACK and P. A register read, for blocks 10A0h to 10AFh, takes a THIRD address byte before the P.
# The legs: L1 reads user block 0000h and requires E1 40 80 09, the NFC Forum capability container the part ships with, WHICH THE CHIP CANNOT MANUFACTURE and can only come off the tag; L2 writes DE AD C0 DE into user block 0040h and then, with a fresh pointer set, reads the same block back, proving the tag took real state from the chip, since the part commits an EEPROM block write on the STOP; L3 reads STATUS0_REG and requires 02h, supply OK with no reader field in this bench, exercising the second, incompatible frame shape; L4 is a NEGATIVE leg addressing 7-bit 2Ah, the classic off-by-a-shift of the tag's own 54h, which must be NACKed, proving the model is address-selective rather than ACKing everything.
# I2C0 master registers at 0x4E00: CR has MDIV at [16:13] and MEN at [21]; FCR has the write-1 command bits MRB, MSP, MST and SC, of which MSP and MRB are ignored unless the master owns the bus, which it does here; SR has SPR, STR, MXC, MNR, MTXE, MARB, MSPS, MSTS, MCB and BS, with MXC, MNR and MSPS write-1-to-clear; MTX is the transmit byte, and a write with MEN set issues a master write, with the FIRST byte after a START being the address shifted up with the read/write bit; MRX is the receive byte.
# EVERY STOP IS POLLED, because of an I2C.vhd race: the master FSM asserts its clear strobe for one master-clock period inside the second stop state, so a START written into FCR during the stop cadence is silently swallowed. Each stop therefore clears MSPS, commands the stop, and polls MSPS back to 1 before the next frame may open.

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
