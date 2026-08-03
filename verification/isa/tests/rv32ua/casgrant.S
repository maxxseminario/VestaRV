# See LICENSE for license details.

#*****************************************************************************
# casgrant.S   (K4 session 3 — the K4-L4 / D-2026-08-03-2 DISCRIMINATOR)
#-----------------------------------------------------------------------------
# WHAT THIS TEST IS FOR. K4 row B8 (`zacas`) measured that an `amocas.w` whose
# compare FAILS emits a SECOND data-port READ record that the reference does
# not model (ledger K4-L4, divergence D-2026-08-03-2). Two readings were
# deliberately left unseparated:
#   (a) a REAL extra bus transaction on the failed-compare path, or
#   (b) a tracer artifact — a record emitted for a cycle in which no bus
#       transaction was driven.
# R-K4-2 (3) rules the named discriminator — DID THE ARBITER GRANT TWICE —
# into K4. This test is that discriminator.
#
# WHY THE B8 CELLS CANNOT SETTLE IT: their CAS target is `0x8410`, which is the
# hart's PRIVATE TCM. A private access never reaches `mp_arbiter`, so no
# bus-level instrument can see it. This test aims every measured access at the
# SHARED WINDOW instead.
#
# THE INSTRUMENT. `mhpmcounter4` with `mhpmevent4 = 2` counts "shared-bus
# grants (one per completed txn)" — csr_unit.vhd's `hpm_fires`, fed by
# `hpm_ev_stall <= not mem_ready`, and `mem_ready` can only rise after
# hart_tile's `sh_ack_ok`, which can only rise after the ARBITER's `done`.
# A counted grant is therefore an arbiter-COMPLETED shared transaction, not a
# core-side intent. Requires ENABLE_ZIHPM as well as ENABLE_ZACAS, which is why
# this row is CATALOG-tagged with BOTH knobs and appears only on a config that
# sets both (`config/castalia_zihpm_zacas.json`).
#
# THE MEASUREMENT IS NOT ASSERTED — READ IT OFF THE TRACE. The test asserts
# only (i) the three CONTROL deltas, whose values are structurally determined
# and hold under BOTH hypotheses, and (ii) the architectural results of both
# CAS forms. The two CAS deltas are left UNASSERTED on purpose: a test that
# asserts the disputed number is a hypothesis-confirming gate, not an
# instrument. Read `d_cas_ok` / `d_cas_fail` from the RTL trace — they are the
# `R` records of the two `sub` retires, and they are ALSO stored to the TCM
# result block at the end (visible as `M S` records) as a second readout.
#
#   d_null    (two adjacent csrr, nothing between)  expect 0   — the zero control
#   d_lw      (one shared-window `lw`)              expect 1   — known-NONZERO
#   d_sw      (one shared-window `sw`)              expect 1   — known-NONZERO
#   d_cas_ok  (shared `amocas.w`, compare SUCCEEDS) MEASURED
#   d_cas_fail(shared `amocas.w`, compare FAILS)    MEASURED  <-- THE ANSWER
#
#   d_cas_fail == d_lw   => ONE transaction  => reading (b), tracer artifact
#   d_cas_fail == d_cas_ok (two)             => reading (a), a real second
#                                               arbiter-completed transaction
#
# Method rule 4 (a method checked only against zero has not been checked) is
# what the `lw`/`sw` legs are for; method rule 7 (never calibrate — find the
# structurally determined edge) is why all five legs live in ONE run against
# ONE counter rather than being compared across runs.
#
# SHARED-WINDOW WORD CLAIMED: 0x100A0, one word. Free at N=4 (shmem_mp/shcount
# hammer tops out at 0x1009C; shboot's DONE array starts at 0x10120) and inside
# the bootrom's 0x10000-0x107FF zero range, so it is zero before the first read.
# This test is Castalia-only (N=4) by construction — its config sets no Argus
# shape — and it runs in isolation like every other, so the N=18 overlap the
# ledger rule warns about cannot occur here.
#
# gas 13.2 has no amocas mnemonic (see extzacas.S), so the CAS is an explicit
# `.insn` R-type. rv32ua's -march has no zicsr, hence the `.option arch` push.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define AMOCAS_W(rd,rs1,rs2)  .insn r 0x2f, 0x2, 0x14, rd, rs1, rs2

#define MHPMEVENT4     0x324
#define MHPMCOUNTER4   0xB04
#define MHPMCOUNTER4H  0xB84
#define SHARED_WORD    0x100A0        /* shared bulk RAM, zeroed by bootrom */

RVTEST_RV32U
RVTEST_CODE_BEGIN

.option arch, +zicsr

    # ---- base-ISA sanity (the extprobe convention) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cg_fail

    li   s0, SHARED_WORD           # every measured access targets THIS address
    li   t0, 2
    csrw MHPMEVENT4, t0            # counter 4 = shared-bus grants
    csrw MHPMCOUNTER4,  zero
    csrw MHPMCOUNTER4H, zero

    # ---- leg 0: the ZERO control — nothing between the two reads ----
    csrr s1, MHPMCOUNTER4
    csrr s2, MHPMCOUNTER4
    sub  s2, s2, s1                # d_null

    # ---- leg 1: one shared-window LOAD (known-NONZERO calibration) ----
    csrr s1, MHPMCOUNTER4
    lw   t0, 0(s0)
    csrr s3, MHPMCOUNTER4
    sub  s3, s3, s1                # d_lw

    # ---- leg 2: one shared-window STORE (the second known-NONZERO) ----
    li   t0, 0x0000CAFE
    csrr s1, MHPMCOUNTER4
    sw   t0, 0(s0)
    csrr s4, MHPMCOUNTER4
    sub  s4, s4, s1                # d_sw   (mem = 0x0000CAFE)

    # ---- leg 3: shared amocas.w, compare SUCCEEDS ----
    li   a2, 0x0000CAFE            # rd = compare value (== mem)
    li   a3, 0xF00DBABE            # rs2 = swap value
    csrr s1, MHPMCOUNTER4
    AMOCAS_W(a2, s0, a3)
    csrr s5, MHPMCOUNTER4
    sub  s5, s5, s1                # d_cas_ok   (MEASURED, not asserted)
    li   t1, 0x0000CAFE
    bne  a2, t1, cg_fail           # rd = old value
    lw   a4, 0(s0)
    li   t1, 0xF00DBABE
    bne  a4, t1, cg_fail           # mem swapped

    # ---- leg 4: shared amocas.w, compare FAILS  <-- THE DISCRIMINATOR ----
    li   a2, 0x12345678            # rd != mem  => compare fails
    li   a3, 0x5A5AA5A5            # rs2 — must NOT be written
    csrr s1, MHPMCOUNTER4
    AMOCAS_W(a2, s0, a3)
    csrr s6, MHPMCOUNTER4
    sub  s6, s6, s1                # d_cas_fail (MEASURED, not asserted)
    li   t1, 0xF00DBABE
    bne  a2, t1, cg_fail           # rd = old value
    lw   a4, 0(s0)
    bne  a4, t1, cg_fail           # mem UNCHANGED — the CAS did not write

    # ---- the CONTROLS are the only deltas this test asserts ----
    bnez s2, cg_fail               # d_null must be 0
    li   t1, 1
    bne  s3, t1, cg_fail           # d_lw must be 1
    bne  s4, t1, cg_fail           # d_sw must be 1

    # ---- second readout: the five deltas into the TCM result block ----
    # (TCM stores are private — they add no grants, and all five deltas are
    #  already computed, so this cannot perturb the measurement.)
    la   t2, cg_res
    sw   s2, 0(t2)                 # d_null
    sw   s3, 4(t2)                 # d_lw
    sw   s4, 8(t2)                 # d_sw
    sw   s5, 12(t2)                # d_cas_ok
    sw   s6, 16(t2)                # d_cas_fail

    RVTEST_PASS

cg_fail:
    RVTEST_FAIL                    # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 2
cg_res: .word 0
        .word 0
        .word 0
        .word 0
        .word 0
RVTEST_DATA_END
