# See LICENSE for license details.

#*****************************************************************************
# extzimop.S   (ISA extension program, X1 Zimop+Zcmop, 2026-07-17)
#-----------------------------------------------------------------------------
# Build-time-dispatched probe for Zimop (mop.r.N / mop.rr.N) and Zcmop
# (c.mop.N). These extensions have NO misa bit, so — like the extprobe_template
# it derives from — this file dispatches at COMPILE time on the generator's
# CORE_ENABLE_ZIMOP #define (emitted into the make-chip product
# platform/common/out/software/include/MemoryMap.h only when isa.zimop=true;
# the rv32ua compile line was extended with -I.../platform/common/out/software/include
# so that header wins over the frozen Myshkin MemoryMap.h).
#
#   feature ON  (#ifdef CORE_ENABLE_ZIMOP):  execute the encodings, CHECK that
#       mop.r/mop.rr write rd<-0 (a real x0-safe zero write) and that c.mop.N is
#       a pure nop (no register/memory change, sequential PC) -> PASS.
#   feature OFF (#else):  the same encodings are decode HOLES and MUST take the
#       illegal-instruction trap (observed as trap_flag by the stripped-build
#       harness behavioral_mp_stripped/run_extoff.sh + trap_watch.tcl; surviving
#       past them -> explicit FAIL).
#
# Authoritative encodings (source: riscv/riscv-opcodes rv_zimop + rv_zcmop;
# the installed gcc 13.2.0 gas does not know zimop/zcmop, so raw .word/.2byte
# are used). Skeleton cross-checks against the well-known reference words
# mop.r.0 x0,x0 = 0x81C04073 and mop.rr.0 x0,x0,x0 = 0x82004073. rd=a2, rs1=a5,
# rs2=a1 are chosen to AVOID a0/x10 (the testbench's pass/fail monitor register)
# as any mop operand:
#   mop.r.0   a2,a5     = 0x81C7C673   (SYSTEM f3=100, bit31=1, bits25..22=0111)
#   mop.r.31  a2,a5     = 0xCDF7C673   (index bits {30,27,26,21,20} all set)
#   mop.rr.0  a2,a5,a1  = 0x82B7C673   (SYSTEM f3=100, bit31=1, bit25=1, rs2=a1)
#   mop.rr.7  a2,a5,a1  = 0xCEB7C673   (index bits {30,27,26} all set)
#   c.mop.1             = 0x6081       (C1 15..13=011,12=0,11..7=N odd,6..2=0,1..0=01)
#   c.mop.15            = 0x6781
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

# CORE_ENABLE_* build-time feature defines. The verification/isa Makefile
# extracts these from the current platform/common make-chip output into a tiny
# dependency-free build/core_features.h (-I$(build_dir)); it is empty (all
# features OFF) when no ON make-chip product is present, so the default build
# takes the #else (OFF) arm.
#include "core_features.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, extt_fail

#ifdef CORE_ENABLE_ZIMOP
    # =====================================================================
    # FEATURE ON: mop.r.N / mop.rr.N write rd<-0; c.mop.N is a pure nop.
    # rs1 (a5) is preloaded NONZERO and rd (a2) with a nonzero poison, so a
    # missing write OR an rd<-rs1 passthrough (the negative-control seed) both
    # leave a2 != 0 and are caught by the bnez checks below. a0/x10 is the tb
    # monitor register and is deliberately NOT used as a mop operand.
    # =====================================================================
    li   a5, 0x0BADF00D          # rs1 = nonzero (poison for the rd<-rs1 seed)

    # mop.r.0 a2,a5  -> a2 = 0
    li   a2, 0x5A5A5A5A
    .word 0x81C7C673
    bnez a2, extt_fail

    # mop.r.31 a2,a5 -> a2 = 0
    li   a2, 0x5A5A5A5A
    .word 0xCDF7C673
    bnez a2, extt_fail

    li   a1, 0x12345678          # rs2 = nonzero
    # mop.rr.0 a2,a5,a1 -> a2 = 0
    li   a2, 0x5A5A5A5A
    .word 0x82B7C673
    bnez a2, extt_fail

    # mop.rr.7 a2,a5,a1 -> a2 = 0
    li   a2, 0x5A5A5A5A
    .word 0xCEB7C673
    bnez a2, extt_fail

#ifdef CORE_ENABLE_COMPRESSED
    # ---- Zcmop: c.mop.N is a pure nop (no reg/mem change, PC+2) ----
    # Two 16-bit c.mop words keep the stream 4-byte aligned. If either trapped
    # (bad gating) or altered architectural state, we would not reach PASS with
    # the sentinels intact.
    li   a3, 0xC0FFEE11          # sentinel that must survive c.mop
    li   a4, 0xC0FFEE11
    .2byte 0x6081                # c.mop.1
    .2byte 0x6781                # c.mop.15
    bne  a3, a4, extt_fail       # c.mop must not touch any GPR
#endif

    RVTEST_PASS

#else
    # =====================================================================
    # FEATURE OFF: the mop encoding is a decode hole and MUST trap illegal.
    # (The stripped-build harness watches trap_flag via trap_watch.tcl and
    #  reports TRAP_OK when the trap fires here; reaching extt_fail = FAIL.)
    # NB: do NOT preload a0 here — trap_watch.tcl reads a0 for the 0xDEADBEEF
    # FAIL sentinel, so any a0 poison would be a false SURVIVED. The trap fires
    # on the encoding regardless of operand registers.
    # =====================================================================
    .word 0x81C7C673             # mop.r.0 a2,a5 — must be illegal-instruction here
    j    extt_fail               # reached only if the encoding did NOT trap

#endif

extt_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
extt_scratch: .word 0
RVTEST_DATA_END
