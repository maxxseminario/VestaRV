# See LICENSE for license details.

#*****************************************************************************
# shmixw.S  (X2 red-team — mixed-width same-word cross-hart torture)
#-----------------------------------------------------------------------------
# Four harts concurrently hammer the SAME shared word W with DIFFERENT widths,
# released together by a GO barrier for real LOCKED-exit contention:
#
#     hart 0 : amoadd.b  on byte 0 (W+0) , +1 x N0   (N0 = 0x11)
#     hart 1 : amoadd.b  on byte 2 (W+2) , +1 x N2   (N2 = 0x13)
#     hart 2 : amoadd.h  on half 1 (W+2) , +1 x Nh   (Nh = 0x17)   [overlaps byte 2!]
#     hart 3 : amoadd.w  on word   (W+0) , +0x01000000 x Nw (Nw = 0x1D) [byte 3]
#     harts >= 4 : uninvolved (inline pass, park — never touch W)
#
# This goes BEYOND shzabha's adjacent-lane pattern: byte 2 is hammered by BOTH
# a byte AMO (hart 1) AND a half AMO (hart 2), and byte 3 (the high byte of
# half 1) is hammered by the word AMO (hart 3) — so the half AMO's read-modify-
# write of {byte3,byte2} races the word AMO's write of byte3. M8 grant-locking
# makes each AMO's read+write pair indivisible, so no contribution is ever lost.
#
# EXACT-SUM design (lane-carry-free — every per-lane total < 0x100, so sub-word
# truncation never drops a carry and the word add's +0x01000000 lands purely in
# byte 3):
#     byte 0 = N0                 = 0x11
#     byte 1 = 0                  = 0x00
#     byte 2 = N2 + Nh = 0x13+0x17 = 0x2A
#     byte 3 = Nw                 = 0x1D
#     W_final = 0x1D2A0011   (exactly computable, order-independent)
#
# If atomicity breaks (e.g. the ghost-txn / lock-drop seed), a half AMO can
# rewrite a stale byte 3 over a word AMO's update — byte 3 < Nw -> W != expected
# -> FAIL. So shmixw also catches lost mixed-width updates.
#
# Pass = 0xCAFEBABE in a0 (hart 0 gate; tiles PASS inline). Bounded barrier /
# DONE polls FAIL inside the 100 ms tb watchdog. Needs harts 0-3 (Castalia N=4).
#
# ON-BUILD ONLY (amoadd.b/.h trap without Zabha; OFF arm = trivial pass).
#
# Shared-window map (all < 0x10500, inside the bootrom zero range; isolation
# makes overlap with other tests' bands benign):
#     W       = 0x10420
#     GO      = 0x10424
#     DONE[h] = 0x10424 + 4*h   (h = 1..3)   -> 0x10428 / 0x1042C / 0x10430
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"
# CORE_ENABLE_ZABHA comes from the build command (-DCORE_ENABLE_ZABHA), never an include.

#define AMOADD_B(rd,rs1,rs2)   .insn r 0x2f, 0x0, 0x00, rd, rs1, rs2
#define AMOADD_H(rd,rs1,rs2)   .insn r 0x2f, 0x1, 0x00, rd, rs1, rs2

#define W_ADDR   0x10420
#define GO_ADDR  0x10424
#define DONE_BASE 0x10424

#define N0   0x11
#define N2   0x13
#define NH   0x17
#define NW   0x1D
#define W_EXPECT 0x1D2A0011

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop

#ifdef CORE_ENABLE_ZABHA
    bnez s10, tile_entry            # only hart 0 runs the launcher

    # ---- hart 0: clear W + GO, launch all tiles, drop the GO barrier ----
    li   t0, W_ADDR
    sw   x0, 0(t0)                  # W = 0 (defensive; bootrom already zeroed)
    li   t0, GO_ADDR
    sw   x0, 0(t0)

    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

    li   t0, GO_ADDR
    li   t1, 1
    sw   t1, 0(t0)                  # release everybody together

    # ---- hart 0's contribution: byte 0, +1 x N0 ----
    li   s0, W_ADDR                 # byte 0 address = W+0
    li   t3, 1
    li   s6, N0
h0_loop:
    AMOADD_B(t2, s0, t3)
    addi s6, s6, -1
    bnez s6, h0_loop
    j    hart0_verify

tile_entry:                        # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    li   sp, 0xBFF0

    # ---- GO barrier: spin until hart 0 releases (bounded) ----
    li   t0, GO_ADDR
    li   t6, 200000
go_wait:
    lw   t1, 0(t0)
    bnez t1, go_go
    addi t6, t6, -1
    bnez t6, go_wait
    j    mixw_fail_tile
go_go:
    # ---- dispatch by hartid ----
    li   t0, 1
    beq  s10, t0, do_byte2
    li   t0, 2
    beq  s10, t0, do_half1
    li   t0, 3
    beq  s10, t0, do_word
    # harts >= 4: uninvolved — inline pass, never touch W
    li   a0, 0xCAFEBABE
    j    tile_park

do_byte2:                          # hart 1: amoadd.b on byte 2 (W+2)
    li   s0, W_ADDR + 2
    li   t3, 1
    li   s6, N2
1:  AMOADD_B(t2, s0, t3)
    addi s6, s6, -1
    bnez s6, 1b
    j    tile_report

do_half1:                          # hart 2: amoadd.h on half 1 (W+2)
    li   s0, W_ADDR + 2
    li   t3, 1
    li   s6, NH
1:  AMOADD_H(t2, s0, t3)
    addi s6, s6, -1
    bnez s6, 1b
    j    tile_report

do_word:                           # hart 3: amoadd.w on the whole word (byte 3)
    li   s0, W_ADDR
    li   t3, 0x01000000
    li   s6, NW
    .option push
    .option arch, +a
1:  amoadd.w t2, t3, (s0)
    addi s6, s6, -1
    bnez s6, 1b
    .option pop
    j    tile_report

tile_report:                       # DONE[h] = 1, inline PASS, park
    slli t0, s10, 2
    li   t1, DONE_BASE
    add  t1, t1, t0
    li   t2, 1
    sw   t2, 0(t1)
    li   a0, 0xCAFEBABE
tile_park:
    j    tile_park
mixw_fail_tile:
    li   a0, 0xDEADBEEF
    j    tile_park

    # ---- hart 0: wait for the three contributors, require the exact sum ----
hart0_verify:
    li   s6, 1
dwait_loop:
    slli t0, s6, 2
    li   t1, DONE_BASE
    add  t1, t1, t0                # DONE[h]
    li   t6, 200000
dwait:
    lw   t2, 0(t1)
    bnez t2, dwait_ok
    addi t6, t6, -1
    bnez t6, dwait
    j    mixw_fail
dwait_ok:
    addi s6, s6, 1
    li   t0, 4
    blt  s6, t0, dwait_loop        # h = 1,2,3

    li   s0, W_ADDR
    lw   t2, 0(s0)
    li   t3, W_EXPECT
    bne  t2, t3, mixw_fail         # exact mixed-width sum

    RVTEST_PASS                    # a0 = 0xCAFEBABE

mixw_fail:
    RVTEST_FAIL                    # a0 = 0xDEADBEEF

#else
    # OFF (default build): trivial single-hart pass — keeps the default suite
    # green (shzabha precedent). amoadd.b/.h are illegal on a zabha-OFF build.
    li   t0, 0x0ABC
    li   t1, 0x0ABC
    bne  t0, t1, mixw_fail_off
    RVTEST_PASS
mixw_fail_off:
    RVTEST_FAIL
#endif

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
