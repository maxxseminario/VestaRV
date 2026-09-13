# See LICENSE for license details.

# VestaRV: decode proof for the wound configuration's three new peripherals
# Hart 0 only, tiles parked. It proves QSPI0 at 0x4C00, I3C0 at 0x6100 and NFC0 at 0x6200 decode in gates, with one inert write and readback plus two known-nonzero reset-value reads. IT IS NOT A DRIVER: no engine is ever launched, no CMD or trigger register is touched, and no interrupts are used, so the wound-configuration vectors are deliberately left unarmed.
# QSPI0ADR at 0x4C08 is a plain 32-bit address-holding register and a write there never launches a transaction, so it takes an inert 0xA5 write and readback. I3C0CR at 0x6100 has SDAPP bit 2 set at reset and is read masked to that bit, never written, since a known-nonzero reset field already proves the decode. NFC0CR at 0x6200 has AUTOREAD bit 12 set at reset and is read masked to that bit, never written.

#include "riscv_test.h"
#include "test_macros.h"

#define QSPI0ADR        0x4C08
#define I3C0CR          0x6100
#define NFC0CR          0x6200

#define QSPI_PATTERN    0x000000A5
#define I3C_SDAPP_MASK  0x00000004
#define NFC_AUTORD_MASK 0x00001000

RVTEST_RV32U
RVTEST_CODE_BEGIN

# -------------------------------------------------------------------------
# 1. QSPI0: QSPI0ADR write/readback (inert -- ADR write never launches;
#    only a QSPI0CMD write does)
# -------------------------------------------------------------------------
    addi gp, gp, 1
    li   a0, QSPI0ADR
    li   s0, QSPI_PATTERN
    sw   s0, 0(a0)
    lw   s4, 0(a0)
    bne  s0, s4, fail

# -------------------------------------------------------------------------
# 2. I3C0: I3C0CR reset-value read (SDAPP bit 2 = 1 @ reset), read-only
# -------------------------------------------------------------------------
    addi gp, gp, 1
    li   a0, I3C0CR
    lw   s4, 0(a0)
    li   s3, I3C_SDAPP_MASK
    and  s4, s4, s3
    bne  s4, s3, fail

# -------------------------------------------------------------------------
# 3. NFC0: NFC0CR reset-value read (AUTOREAD bit 12 = 1 @ reset), read-only
# -------------------------------------------------------------------------
    addi gp, gp, 1
    li   a0, NFC0CR
    lw   s4, 0(a0)
    li   s3, NFC_AUTORD_MASK
    and  s4, s4, s3
    bne  s4, s3, fail

    jal zero, pass

    TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
