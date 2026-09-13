# See LICENSE for license details.

# VestaRV: the multi-hart boot protocol, end to end
# Nothing preloads the tile TCMs: harts 1..N-1 boot from THE shared ROM, park in WFI inside the boot ROM, and wake only through the ROM's msip loader, whose mailbox row is documented in mp_boot.h.
# Hart 0 is the only hart running this image at start, and for each tile in turn it first checks DONE[h] is 0, which proves the tile parked WITHOUT side effects and on silicon proves the ROM's mailbox zeroing; then stages this image into shared RAM once and launches the hart through the loader by writing the SRC, LEN and ENTRY row and setting CLINT msip[h]; then bounded-polls DONE[h]; then verifies msip[h] reads back 0, which proves the tile's ROM ISR cleared its own level through the arbiter.
# The tile payload is entered with sp set and the TCM freshly loaded by the ROM copy: it writes DONE[mhartid], sets a0 to PASS inline, then verifies DONE forever, so a post-PASS corruption still fails the run.
# Shared words: DONE[h] = 0x10120 + 4*h for h = 1..NHARTS-1, with no control words above the array and everything below 0x10500.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

# Copy volume per tile. The staggered proof copies SRC->TCM for each hart IN
# TURN, so the total copy cost is NHARTS-1 serialized transfers. The payload
# (.ivt 0x8000 + .text ending ~0x833A = ~207 words) is tiny; 512 words covers
# it with margin. At N=4 this still copies the whole payload (unchanged proof).
# At N=18, 17 serialized 16 KB copies overran the tb 100 ms watchdog (~300 ms of
# honest sim); the 512-word block keeps all 17 releases inside the watchdog
# without weakening the protocol (row/msip/ISR-clear/copy/ignite/report path is
# identical). (A3: verified passing at N=4 AND N=18.)
#define MP_SHBOOT_WORDS 512

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # Only hart 0 ever executes from _start in this image (tiles enter at
    # boot_payload via the loader), but keep the dispatch as a guard: a tile
    # that somehow lands here must not run the releaser.
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop

    li   s4, 0x10120            # DONE base
    beqz s10, releaser
    j    boot_payload           # guard: mis-dispatched tile becomes a payload

    # ---- tile payload: entered from the bootrom loader (msip ignite) ------
boot_payload:
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # entry ABI: only sp is defined — re-derive
    .option pop
    li   sp, 0xBFF0             # test convention (bootrom left 0xBFFC)
    li   s4, 0x10120
    slli t0, s10, 2
    add  s4, s4, t0             # my DONE word
    li   t3, 0xD00E0000
    add  t3, t3, s10
    sw   t3, 0(s4)              # report in
    li   a0, 0xCAFEBABE         # inline PASS (tb latches a0_1/2/3)
payload_verify:                 # forever: DONE must survive other traffic
    lw   t4, 0(s4)
    bne  t4, t3, shboot_fail
    j    payload_verify

    # ---- hart 0: staggered load + launch + wake check, hart 1 then 2 then 3
releaser:
    MP_STAGE_IMAGE(MP_SHBOOT_WORDS)  # stage the payload block once (0x18000)
    li   s6, 1
release_loop:
    slli t0, s6, 2
    add  s7, s4, t0             # DONE[h]
    lw   t2, 0(s7)
    bnez t2, shboot_fail        # must still be parked (and zeroed by the ROM)

    # launch hart s6 through the bootrom loader (register-indexed form of
    # mp_boot.h's MP_LAUNCH_HART): row FIRST, msip LAST
    slli t0, s6, 4
    li   t1, MP_BOOT_MB_BASE
    add  t0, t0, t1             # loader row for hart s6
    li   t1, MP_STAGE_BASE
    sw   t1, 0(t0)              # SRC = the staged image
    li   t1, MP_SHBOOT_WORDS
    sw   t1, 4(t0)              # LEN = payload block (covers .ivt + .text)
    la   t1, boot_payload
    sw   t1, 8(t0)              # ENTRY
    slli t0, s6, 2
    li   t1, MP_CLINT_MSIP
    add  t0, t0, t1
    li   t1, 1
    sw   t1, 0(t0)              # msip[s6] = 1 — ignite

    li   t5, 0xD00E0000
    add  t5, t5, s6             # expected DONE value
    li   t6, 100000             # bounded wake budget (broken release -> FAIL,
wake_wait:                      #  not a 100ms watchdog ride)
    lw   t2, 0(s7)
    beq  t2, t5, released
    addi t6, t6, -1
    bnez t6, wake_wait
    j    shboot_fail
released:
    # the tile's ROM ISR must have cleared its own msip level
    slli t0, s6, 2
    li   t1, MP_CLINT_MSIP
    add  t1, t1, t0
    lw   t2, 0(t1)
    bnez t2, shboot_fail
    addi s6, s6, 1
    li   t0, NHARTS
    bne  s6, t0, release_loop

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin

shboot_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF, spin

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
