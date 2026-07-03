# See LICENSE for license details.

#*****************************************************************************
# shboot.S  (M5a)
#-----------------------------------------------------------------------------
# HART-GENERIC boot/release test — the soft-CLINT IPI flow.
#
# Mailboxes live in the shared window at 0x10100+ (clear of shmem.S 0x10000-8,
# shlrsc 0x1000C/0x10010, shmem_mp hammer words 0x10040+4*h, counter 0x10080):
#     GO[h]    = 0x10100 + 4*h   release magic (0x600DB007) written by hart 0
#     ENTRY[h] = 0x10110 + 4*h   entry PC written by hart 0 before GO
#     DONE[h]  = 0x10120 + 4*h   0xD00E0000+h written by hart h after waking
#
# Harts 1-3 (preloaded, start at t=0): PARK — poll their GO word (reads only,
# no shared writes while parked), then jump to the ENTRY PC, write DONE, set
# a0 = PASS inline, and verify their DONE word forever.
#
# Hart 0 (SPI boot, arrives late): for each hart 1..3 IN TURN (staggered):
# check DONE[h]==0 (proves it really parked without side effects), write
# ENTRY[h] then GO[h], and poll DONE[h] with a BOUNDED budget until the hart
# reports in. All three released and reporting -> RVTEST_PASS.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..3
    .option pop

    li   s2, 0x10100            # GO base
    li   s3, 0x10110            # ENTRY base
    li   s4, 0x10120            # DONE base
    li   s5, 0x600DB007         # GO release magic

    beqz s10, releaser

    # ---- harts 1-3: park (poll GO — reads only), then jump to ENTRY ----
    slli t0, s10, 2
    add  s2, s2, t0             # my GO word
    add  s3, s3, t0             # my ENTRY word
park_loop:
    lw   t1, 0(s2)
    bne  t1, s5, park_loop
    lw   t2, 0(s3)              # entry PC (hart 0 wrote it before GO)
    jalr x0, t2, 0

    # entry target — same link address in every hart's private RAM image
boot_payload:
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

    # ---- hart 0: staggered release + wake check, hart 1 then 2 then 3 ----
releaser:
    li   s6, 1
release_loop:
    slli t0, s6, 2
    add  s7, s4, t0             # DONE[h]
    lw   t2, 0(s7)
    bnez t2, shboot_fail        # must still be parked (no early shared writes)
    la   t3, boot_payload
    add  t4, s3, t0             # ENTRY[h] first...
    sw   t3, 0(t4)
    add  t4, s2, t0             # ...then GO[h]
    sw   s5, 0(t4)
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
    addi s6, s6, 1
    li   t0, 4
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
