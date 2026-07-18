# See LICENSE for license details.

#*****************************************************************************
# shcaslr.S  (X2 red-team — CAS-vs-LR/SC same-address interplay)
#-----------------------------------------------------------------------------
# Pins the SYSTEM-LEVEL contract of the Zacas wen-gated conditional write against
# the global LR/SC reservation unit (resv_unit.vhd): a COMMITTED amocas write
# kills a foreign reservation on the same word; a FAILED amocas (no committed
# write — wen "1111", all lanes suppressed) must NOT.
#
#   hart 0 = RESERVER + gate. hart 1 = CAS-doer. harts >=2 = uninvolved (park).
#
#   LEG 1 (CAS SUCCESS kills the reservation):
#     hart 0 : lr.w W (W=0) ; FLAG_A=1 ; spin FLAG_B ; sc.w W  -> MUST FAIL
#     hart 1 : spin FLAG_A ; amocas.w W cmp=0 swap=0xA1 (SUCCESS, commits) ; FLAG_B=1
#     A committed CAS write to W lands between hart 0's LR and SC, so the global
#     resv_unit kills hart 0's reservation and its SC MUST fail (sc rd != 0).
#
#   LEG 2 (CAS FAIL must NOT kill the reservation):
#     hart 0 : lr.w W (W=0xA1) ; FLAG_A2=1 ; spin FLAG_B2 ; sc.w W -> MUST SUCCEED
#     hart 1 : spin FLAG_A2 ; amocas.w W cmp=0xDEAD swap=0x99 (FAIL, no write) ; FLAG_B2=1
#     The failed CAS commits NO write (all lanes suppressed), so hart 0's
#     reservation survives and its SC MUST succeed (sc rd == 0).
#
# Deterministic handshake (no contention) via level flags, so no backoff is
# needed; every spin is BOUNDED and FAILs inside the 100 ms tb watchdog. The
# reserving hart's stores to the FLAG words (different addresses from W) and its
# spin-loads do NOT clear its reservation (vesta local flop clears only on
# SC/IRQ; the global table kills only a match on the reserved word) — that is
# precisely what leg 2 relies on.
#
# NEGATIVE CONTROL: x2_zacas_uncond_write.patch (removes the CAS-fail wen
# suppression) makes leg 2's "failing" CAS commit its swap -> kills hart 0's
# reservation -> leg 2 SC FAILS -> this test FAILS (the fail-leg is caught).
#
# ON-BUILD ONLY: amocas.w traps illegal without Zacas (OFF arm = trivial pass,
# shzabha/shzacas precedent).
#
# Shared-window map (all < 0x10500, inside the bootrom zero range; tests run in
# isolation so overlap with other tests' bands is benign):
#     W       = 0x10400   (contended reserved word)
#     FLAG_A  = 0x10404   (leg 1: hart 0 reserved -> hart 1 go)
#     FLAG_B  = 0x10408   (leg 1: hart 1 CAS committed -> hart 0)
#     FLAG_A2 = 0x1040C   (leg 2: hart 0 reserved -> hart 1 go)
#     FLAG_B2 = 0x10410   (leg 2: hart 1 CAS done (no write) -> hart 0)
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define AMOCAS_W(rd,rs1,rs2)  .insn r 0x2f, 0x2, 0x14, rd, rs1, rs2

#define W_ADDR   0x10400
#define FLAG_A   0x10404
#define FLAG_B   0x10408
#define FLAG_A2  0x1040C
#define FLAG_B2  0x10410

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # 0..NHARTS-1
    .option pop

#ifdef CORE_ENABLE_ZACAS
    bnez s10, tile_entry        # M12: only hart 0 runs the launcher

    MP_STAGE_IMAGE(4096)
    MP_LAUNCH_ALL(tile_entry, 4096)

    li   sp, 0xBFF0             # hart 0 falls through to the reserver
    j    reserver

tile_entry:                     # tiles enter here (loader ABI: only sp defined)
    .option push
    .option arch, +zicsr
    csrr s10, mhartid           # re-derive (undefined for tiles until now)
    .option pop
    li   sp, 0xBFF0
    li   t0, 1
    beq  s10, t0, cas_doer      # hart 1 = the CAS-doer
    # harts >= 2: not part of the choreography — inline pass and park
    li   a0, 0xCAFEBABE
uninvolved_park:
    j    uninvolved_park

    # ===================== hart 1: the CAS-doer =====================
cas_doer:
    li   s1, FLAG_A
    li   s2, FLAG_B
    li   s3, FLAG_A2
    li   s4, FLAG_B2
    li   s5, W_ADDR

    .option push
    .option arch, +a
    # ---- leg 1: wait for hart 0's reservation, then a SUCCESS CAS ----
    li   t6, 200000
1:  lw   t0, 0(s1)              # spin FLAG_A
    bnez t0, 1f
    addi t6, t6, -1
    bnez t6, 1b
    j    cas_fail_h1            # bounded: hart 0 never armed
1:
    li   a2, 0                  # compare = 0 (matches W's zero-init)
    li   t1, 0xA1              # swap value
    AMOCAS_W(a2, s5, t1)       # W: 0 -> 0xA1 (SUCCESS, commits a write)
    bnez a2, cas_fail_h1       # old value must be the zero-init
    li   t2, 1
    sw   t2, 0(s2)            # FLAG_B = 1 (leg 1 CAS committed)

    # ---- leg 2: wait for hart 0's fresh reservation, then a FAIL CAS ----
    li   t6, 200000
2:  lw   t0, 0(s3)             # spin FLAG_A2
    bnez t0, 2f
    addi t6, t6, -1
    bnez t6, 2b
    j    cas_fail_h1
2:
    li   a2, 0xDEAD           # compare != W (0xA1) -> CAS MUST FAIL, no write
    li   t1, 0x99
    AMOCAS_W(a2, s5, t1)
    li   t3, 0xA1
    bne  a2, t3, cas_fail_h1  # old value returned must be W unchanged (0xA1)
    li   t2, 1
    sw   t2, 0(s4)           # FLAG_B2 = 1 (leg 2 CAS done — no committed write)
    .option pop

    li   a0, 0xCAFEBABE       # hart 1 inline PASS (monitored as a0_1)
h1_park:
    j    h1_park

cas_fail_h1:
    li   a0, 0xDEADBEEF       # hart 1 self-check FAIL (fails the run via a0_1)
h1_fail_park:
    j    h1_fail_park

    # ===================== hart 0: the RESERVER (gate) =====================
reserver:
    li   s1, FLAG_A
    li   s2, FLAG_B
    li   s3, FLAG_A2
    li   s4, FLAG_B2
    li   s5, W_ADDR

    .option push
    .option arch, +a
    # ---- leg 1: LR, let hart 1 commit a SUCCESS CAS, SC MUST FAIL ----
    lr.w t0, (s5)            # reserve W (reads 0)
    li   t1, 1
    sw   t1, 0(s1)          # FLAG_A = 1 (stores to FLAG_A do NOT clear the resv)
    li   t6, 200000
3:  lw   t2, 0(s2)          # spin FLAG_B (loads do NOT clear the resv)
    bnez t2, 3f
    addi t6, t6, -1
    bnez t6, 3b
    j    caslr_fail
3:
    li   t3, 0xBAD1
    sc.w t4, t3, (s5)       # reservation was killed by hart 1's CAS -> MUST FAIL
    beqz t4, caslr_fail     # sc rd == 0 would mean SUCCESS (contract broken)
    lw   t5, 0(s5)          # and W must hold the CAS's swap (0xA1), not our SC data
    li   t3, 0xA1
    bne  t5, t3, caslr_fail

    # ---- leg 2: fresh LR, hart 1 does a FAIL CAS (no write), SC MUST SUCCEED ----
    lr.w t0, (s5)           # reserve W (reads 0xA1)
    li   t1, 1
    sw   t1, 0(s3)         # FLAG_A2 = 1
    li   t6, 200000
4:  lw   t2, 0(s4)         # spin FLAG_B2
    bnez t2, 4f
    addi t6, t6, -1
    bnez t6, 4b
    j    caslr_fail
4:
    li   t3, 0xC0DE
    sc.w t4, t3, (s5)      # reservation SURVIVED the failed CAS -> MUST SUCCEED
    bnez t4, caslr_fail    # sc rd != 0 would mean FAIL (contract broken)
    lw   t5, 0(s5)         # our SC data must be in memory
    li   t3, 0xC0DE
    bne  t5, t3, caslr_fail
    .option pop

    RVTEST_PASS             # a0 = 0xCAFEBABE

caslr_fail:
    RVTEST_FAIL             # a0 = 0xDEADBEEF

#else
    # OFF (default build): trivial single-hart pass — keeps the default suite
    # green (shzabha/shzacas precedent). amocas.w is illegal on a zacas-OFF build.
    li   t0, 0x0ABC
    li   t1, 0x0ABC
    bne  t0, t1, caslr_fail_off
    RVTEST_PASS
caslr_fail_off:
    RVTEST_FAIL
#endif

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
