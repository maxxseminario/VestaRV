# See LICENSE for license details.

#*****************************************************************************
# extzihpm.S   (X1 Zihpm ext-probe, 2026-07-17)
#-----------------------------------------------------------------------------
# Adaptive probe for the Zihpm hardware performance counters (ENABLE_ZIHPM) AND
# a companion for the UNCONDITIONAL csr_valid base repair (Deliverable A). One
# image, BOTH polarities: the arm is chosen at RUN TIME by whether counter 3
# actually moves, so the SAME rcf proves the OFF behavior in the default suite
# and the ON behavior under the ENABLE_ZIHPM build (no include-path surgery, no
# per-polarity rebuild of THIS file — see the report for the rationale vs the
# compile-time #ifdef template).
#
#   ON  (ENABLE_ZIHPM true):  program event 1 (arbiter-stall) on counter 3 and
#       event 2 (shared-bus grants) on counter 4, hammer the shared bus, and
#       require  stall_cycles(c3) > grant_count(c4)  (each grant costs several
#       stall cycles) — this is the exact assertion the negative-control event
#       1<->2 swap violates. Then: counter 3 nonzero+monotone across two reads;
#       mhpmevent3=0 freezes it; counter 5 reads zero and swallows writes.
#   OFF (ENABLE_ZIHPM false): counters 3/4/5 read zero, writes ignored, event
#       selector reads zero, and NONE of these legal CSRs trap.
#
# Every CSR touched here is in the csr_valid map, so this probe NEVER traps in
# either polarity (the trap side of Deliverable A is the extbadcsr.S poison).
#
# Whole file is `.option norvc/norelax` so the image is fixed-width base + the
# explicit CSR ops; `.option arch, +zicsr` admits the CSR encodings (rv32ua's
# -march has no zicsr).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

# CSR addresses (numeric so no zicsr-name table is needed)
#define MHPMEVENT3     0x323
#define MHPMEVENT4     0x324
#define MCOUNTINHIBIT  0x320
#define MHPMCOUNTER3   0xB03
#define MHPMCOUNTER3H  0xB83
#define MHPMCOUNTER4   0xB04
#define MHPMCOUNTER4H  0xB84
#define MHPMCOUNTER5   0xB05
#define SHARED_SCRATCH 0x10000        /* shared bulk RAM, zeroed by bootrom */
#define HAMMER_N       64

RVTEST_RV32U
RVTEST_CODE_BEGIN

.option arch, +zicsr

    # ---- base-ISA sanity (runs on every build) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, zih_fail

    li   s0, SHARED_SCRATCH        # bus-hammer address (loads only; non-destructive)

    # ---- program the events + clear counters 3/4 ----
    li   t0, 1
    csrw MHPMEVENT3, t0            # counter 3 = arbiter-stall cycles
    li   t0, 2
    csrw MHPMEVENT4, t0            # counter 4 = shared-bus grants
    csrw MHPMCOUNTER3,  zero
    csrw MHPMCOUNTER3H, zero
    csrw MHPMCOUNTER4,  zero
    csrw MHPMCOUNTER4H, zero

    # ---- hammer window 1 ----
    li   t1, HAMMER_N
1:  lw   x0, 0(s0)
    addi t1, t1, -1
    bnez t1, 1b

    csrr s2, MHPMCOUNTER3          # c3a = stall cycles (0 iff ENABLE_ZIHPM off)
    csrr s3, MHPMCOUNTER4          # c4a = grant count

    beqz s2, zih_off              # counter never moved -> OFF polarity

    # =====================================================================
    # ENABLE_ZIHPM ON
    # =====================================================================
    # Event-mux discriminator: stall cycles MUST exceed the grant count.
    # A swapped 1<->2 mux makes counter3=grants, counter4=stalls => this fails.
    bgeu s3, s2, zih_fail         # grants >= stalls -> mux wrong -> FAIL
    beqz s3, zih_fail             # no grants observed -> bus not hammered -> FAIL

    # nonzero + monotone: a second window must strictly grow counter 3
    li   t1, HAMMER_N
2:  lw   x0, 0(s0)
    addi t1, t1, -1
    bnez t1, 2b
    csrr s4, MHPMCOUNTER3          # c3b
    bgeu s2, s4, zih_fail         # require c3b > c3a

    # freeze: event 0 stops the counter
    csrw MHPMEVENT3, zero
    csrr s5, MHPMCOUNTER3
    li   t1, HAMMER_N
3:  lw   x0, 0(s0)
    addi t1, t1, -1
    bnez t1, 3b
    csrr s6, MHPMCOUNTER3
    bne  s5, s6, zih_fail         # counter must be frozen

    # counter 5 is hardwired zero: reads 0 and swallows writes
    csrr t0, MHPMCOUNTER5
    bnez t0, zih_fail
    li   t0, 0xFFFFFFFF
    csrw MHPMCOUNTER5, t0
    csrr t0, MHPMCOUNTER5
    bnez t0, zih_fail

    j    zih_pass

    # =====================================================================
    # ENABLE_ZIHPM OFF  (counters 3-31 hardwired zero, no trap)
    # =====================================================================
zih_off:
    li   t0, 0xFFFFFFFF
    csrw MHPMCOUNTER3, t0          # write ignored
    csrr t0, MHPMCOUNTER3
    bnez t0, zih_fail             # still zero
    csrr t0, MHPMCOUNTER4
    bnez t0, zih_fail             # counter 4 zero
    li   t0, 5
    csrw MHPMEVENT3, t0           # event write ignored
    csrr t0, MHPMEVENT3
    bnez t0, zih_fail             # event reads zero
    csrr t0, MHPMCOUNTER5
    bnez t0, zih_fail             # counter 5 zero
    li   t0, 0xFFFFFFFF
    csrw MHPMCOUNTER5, t0
    csrr t0, MHPMCOUNTER5
    bnez t0, zih_fail             # swallowed
    # reaching here means every hpm CSR was legal (no illegal-instr trap)
    j    zih_pass

zih_pass:
    RVTEST_PASS

zih_fail:
    RVTEST_FAIL                   # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
zih_scratch: .word 0
RVTEST_DATA_END
