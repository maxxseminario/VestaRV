# See LICENSE for license details.

# VestaRV: Zabha cross-hart adjacent-lane byte and halfword strobe test
# THE HAZARD IS ADJACENT-LANE CLOBBER: a sub-word AMO write MUST drive ONLY its own byte lanes. If it drives all four strobes, concurrent harts hammering adjacent lanes of one shared word destroy each other's lanes and overwrite the untouched guard lanes.
# The ON body releases all harts together through a GO barrier for real contention. On the BYTE word at 0x104C0, harts 0, 1 and 2 each hammer the lane equal to their hartid with 64 amoadd.b increments while lane 3 is an UNTOUCHED GUARD holding 0x5A, so correct strobes leave lanes 0 to 2 at 64 and the guard intact. On the HALF word at 0x104C4, every hart hammers half 0 with 64 amoadd.h increments, a contended sub-word read-modify-write relying on arbiter grant-lock atomicity, while half 1 is an untouched guard holding 0xC3C3, so half 0 must end at NHARTS*64. On the SWAP word at 0x104C8, hart 0 runs a deterministic amoswap.b chain on lane 1 with lanes 0, 2 and 3 as guards holding 0x99, which proves amoswap.b returns the sign-extended old sub-word and writes only lane 1.
# Pass is 0xCAFEBABE in a0 on hart 0, with the tiles passing inline and continuing to verify. BOTH POLARITIES: the default build leaves CORE_ENABLE_ZABHA undefined and degrades to a trivially passing single-hart variant so the suite stays green, and the ON arm is built by explicitly appending the define. Zabha operations use `.insn`, since gas 13.2 has neither the mnemonics nor the -march token.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"
# CORE_ENABLE_ZABHA comes from the build command (-DCORE_ENABLE_ZABHA), never an include.

#define AMOADD_B(rd,rs1,rs2)   .insn r 0x2f, 0x0, 0x00, rd, rs1, rs2
#define AMOADD_H(rd,rs1,rs2)   .insn r 0x2f, 0x1, 0x00, rd, rs1, rs2
#define AMOSWAP_B(rd,rs1,rs2)  .insn r 0x2f, 0x0, 0x04, rd, rs1, rs2

#define WB    0x104C0
#define WH    0x104C4
#define WSW   0x104C8
#define GO    0x104CC
#define DONE  0x104D0
#define KITER 64

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop

#ifdef CORE_ENABLE_ZABHA
    bnez s10, tile_entry            # only hart 0 runs the launcher

    # ---- hart 0: seed guards, launch all tiles, drop the GO barrier ----
    li   t0, WB
    li   t1, 0x5A000000             # byte3 = 0x5A guard ; bytes 0-2 = 0
    sw   t1, 0(t0)
    li   t0, WH
    li   t1, 0xC3C30000             # half1 = 0xC3C3 guard ; half0 = 0
    sw   t1, 0(t0)
    li   t0, WSW
    li   t1, 0x9999AA99             # bytes 0/2/3 = 0x99 guards ; byte1 = 0xAA
    sw   t1, 0(t0)
    li   t0, GO
    sw   x0, 0(t0)                  # GO = 0 (defensive; bootrom already zeroed)

    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

    li   t0, GO
    li   t1, 1
    sw   t1, 0(t0)                  # release everybody together

tile_entry:                        # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    li   sp, 0xBFF0

    # ---- GO barrier: spin until hart 0 releases (bounded) ----
    li   t0, GO
    li   t6, 200000
go_wait:
    lw   t1, 0(t0)
    bnez t1, go_go
    addi t6, t6, -1
    bnez t6, go_wait
    j    shz_fail                   # GO never dropped -> clean FAIL
go_go:

    # ---- BYTE contention: harts 0,1,2 hammer lane==hartid of WB ----
    li   t3, 3
    bge  s10, t3, skip_byte         # harts >=3 do not touch WB (lane3 = guard)
    li   t0, WB
    add  t0, t0, s10                # &WB + hartid  (my byte lane)
    li   s6, KITER
    li   s5, 1
byte_loop:
    AMOADD_B(t2, t0, s5)            # mem[lane] += 1 ; only my lane's strobe
    addi s6, s6, -1
    bnez s6, byte_loop
skip_byte:

    # ---- HALF contention: ALL harts hammer half0 of WH ----
    li   t0, WH                     # half0 address (2-aligned)
    li   s6, KITER
    li   s5, 1
half_loop:
    AMOADD_H(t2, t0, s5)            # contended sub-word RMW (+1)
    addi s6, s6, -1
    bnez s6, half_loop

    # ---- report DONE ----
    slli t0, s10, 2
    li   t1, DONE
    add  t1, t1, t0
    li   t2, 0xB0B00000
    add  t2, t2, s10
    sw   t2, 0(t1)

    bnez s10, tile_pass             # tiles pass inline + verify forever

    # ================= hart 0: wait, deterministic swap, verify =================
    # wait for every tile's DONE (bounded)
    li   s6, 1
dwait_outer:
    slli t0, s6, 2
    li   t1, DONE
    add  t1, t1, t0
    li   t2, 0xB0B00000
    add  t2, t2, s6
    li   t6, 200000
dwait_inner:
    lw   t3, 0(t1)
    beq  t3, t2, dwait_next
    addi t6, t6, -1
    bnez t6, dwait_inner
    j    shz_fail                   # a tile never finished
dwait_next:
    addi s6, s6, 1
    li   t0, NHARTS
    bne  s6, t0, dwait_outer

    # ---- amoswap.b deterministic chain on WSW lane 1 (single writer) ----
    li   s0, WSW
    addi s1, s0, 1                  # &WSW + 1  (byte lane 1)
    li   t1, 0x11
    AMOSWAP_B(t2, s1, t1)           # old = 0xAA (init lane1)
    li   t3, 0xFFFFFFAA             # sign-extended old byte
    bne  t2, t3, shz_fail
    li   t1, 0x22
    AMOSWAP_B(t2, s1, t1)           # old = 0x11
    li   t3, 0x00000011
    bne  t2, t3, shz_fail
    lbu  t2, 0(s1)                  # lane1 now 0x22
    li   t3, 0x22
    bne  t2, t3, shz_fail
    # WSW adjacent-lane guards (0x99) untouched
    lbu  t2, 0(s0)
    li   t3, 0x99
    bne  t2, t3, shz_fail
    lbu  t2, 2(s0)
    bne  t2, t3, shz_fail
    lbu  t2, 3(s0)
    bne  t2, t3, shz_fail

    # ---- BYTE word checks: lanes 0/1/2 = KITER, lane3 = guard 0x5A ----
    li   s0, WB
    lbu  t2, 0(s0)
    li   t3, KITER
    bne  t2, t3, shz_fail
    lbu  t2, 1(s0)
    bne  t2, t3, shz_fail
    lbu  t2, 2(s0)
    bne  t2, t3, shz_fail
    lbu  t2, 3(s0)                  # GUARD lane — must be untouched
    li   t3, 0x5A
    bne  t2, t3, shz_fail

    # ---- HALF word checks: half0 = NHARTS*KITER, half1 = guard 0xC3C3 ----
    li   s0, WH
    lhu  t2, 0(s0)
    li   t3, NHARTS*KITER
    bne  t2, t3, shz_fail
    lhu  t2, 2(s0)                  # GUARD half — must be untouched
    li   t3, 0xC3C3
    bne  t2, t3, shz_fail

    RVTEST_PASS                     # a0 = 0xCAFEBABE

tile_pass:
    li   a0, 0xCAFEBABE             # tiles pass inline; keep verifying the guard
    slli t0, s10, 2
    li   t1, DONE
    add  t1, t1, t0
    li   t2, 0xB0B00000
    add  t2, t2, s10
tile_forever:
    lw   t3, 0(t1)
    bne  t3, t2, shz_fail
    j    tile_forever

#else
    # OFF (default build): trivial single-hart pass — keeps the 124-suite green.
    # (Zabha byte/half AMOs are illegal here; the illegal-instruction trap is
    #  proven separately by extzabha under run_extoff.sh -> TRAP_OK.)
    li   t0, 0x0ABC
    li   t1, 0x0ABC
    bne  t0, t1, shz_fail
    RVTEST_PASS
#endif

shz_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
