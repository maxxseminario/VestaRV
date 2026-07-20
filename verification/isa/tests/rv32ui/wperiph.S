# See LICENSE for license details.

#*****************************************************************************
# wperiph.S
#-----------------------------------------------------------------------------
# DECODE-PROOF for the wound config's three new peripheral instances: QSPI0
# @0x4C00 (page-0 slot 12), I3C0 @0x6100 (mutex-page sub-slot 1), NFC0
# @0x6200 (mutex-page sub-slot 2). Single-hart directed test (hart 0 only;
# tiles stay parked -- no MP_LAUNCH, no mp_boot.h). Proves the three new
# shared-window slots decode in gates: one inert write/readback (QSPI0) plus
# two known-nonzero-reset-value reads (I3C0, NFC0). NOT a firmware driver --
# no engine is ever launched (the CMD/trigger registers are never touched)
# and no IRQs are used (env DEFINE_IVT only reaches slot 82 / the meip
# dispatcher is not armed here; the wound-config vectors 55/56/86-97 are
# left unarmed on purpose).
#
# Register picks (see ~/vesta_docs/digperiphs -- qspi_spec.md / i3c_spec.md /
# nfc_spec.md "Driver note" tables):
#   QSPI0ADR (0x4C08) -- plain 32-bit address-holding register; a write here
#     never launches a transaction (only a QSPI0CMD write does, per the
#     qspi_spec.md launch sequence) -- inert write/readback, pattern 0xA5.
#   I3C0CR   (0x6100) -- SDAPP[2] = 1 @ reset (i3c_spec.md register table) --
#     read-only reset-value check, masked to bit 2. Never written (CR bit 0
#     is I3CEN; a write is avoidable here since a known-nonzero reset field
#     already proves the decode).
#   NFC0CR   (0x6200) -- AUTOREAD[12] = 1 @ reset (nfc_spec.md register
#     table) -- read-only reset-value check, masked to bit 12. Never written.
#*****************************************************************************

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
