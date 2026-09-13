# See LICENSE for license details.

# VestaRV: Zfinx extension probe
# BUILD-TIME DISPATCH, not runtime misa dispatch, because Zfinx SETS NO misa BIT, misa.F staying 0 by spec, and because this core DEAD-ENDS an illegal instruction in TRAP_STATE with the PC frozen and no software trap recovery, so a try-and-recover runtime probe is impossible. With -DCORE_ENABLE_ZFINX a representative slice of the Zfinx operation set executes, the fcsr, fflags and frm CSRs are read, and the results are checked; without it the file does base-ISA sanity and passes, because the pass/fail runner cannot observe a dead-end trap as a pass and the default Zfinx-off suite must stay green. The genuine "Zfinx off means illegal-instruction trap" behaviour is proven separately by the extzfinx poison family under run_extoff.sh, ONE POISON PER FP ENCODING CLASS, because a dead-end trap only ever proves one at a time.
# THE MACRO IS PASSED DIRECTLY, NEVER THROUGH #include "MemoryMap.h": on the default rv32ua compile line that name resolves to the frozen Myshkin header, which fails to preprocess. So the OFF build is the plain compile line and the ON build adds only -DCORE_ENABLE_ZFINX, with the shared Makefile unmodified.
# The ON arm's FP mnemonics are wrapped in `.option arch, +zfinx` so the file assembles under the suite base -march, which gas 13.2 accepts for every single-precision mnemonic on x-registers, and the fflags, frm and fcsr reads need +zicsr, added in the same push.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, extzf_fail

#ifdef CORE_ENABLE_ZFINX
    # =====================================================================
    # FEATURE ON: execute a representative Zfinx slice and CHECK -> PASS.
    # =====================================================================
    .option push
    .option arch, +zfinx
    .option arch, +zicsr

    # -- fadd.s : 1.5 + 2.5 = 4.0 --
    li   a1, 0x3fc00000            # 1.5f
    li   a2, 0x40200000            # 2.5f
    fadd.s a0, a1, a2
    li   a3, 0x40800000           # 4.0f
    bne  a0, a3, extzf_fail

    # -- fmul.s : 2.0 * 3.0 = 6.0 --
    li   a1, 0x40000000           # 2.0f
    li   a2, 0x40400000           # 3.0f
    fmul.s a0, a1, a2
    li   a3, 0x40c00000           # 6.0f
    bne  a0, a3, extzf_fail

    # -- fsub.s : 4.0 - 1.5 = 2.5 --
    li   a1, 0x40800000
    li   a2, 0x3fc00000
    fsub.s a0, a1, a2
    li   a3, 0x40200000
    bne  a0, a3, extzf_fail

    # -- fdiv.s : 6.0 / 2.0 = 3.0 --
    li   a1, 0x40c00000
    li   a2, 0x40000000
    fdiv.s a0, a1, a2
    li   a3, 0x40400000
    bne  a0, a3, extzf_fail

    # -- fsqrt.s : sqrt(4.0) = 2.0 --
    li   a1, 0x40800000
    fsqrt.s a0, a1
    li   a3, 0x40000000
    bne  a0, a3, extzf_fail

    # -- fmadd.s : 2.0*3.0 + 1.5 = 7.5 --
    li   a1, 0x40000000           # 2.0
    li   a2, 0x40400000           # 3.0
    li   a4, 0x3fc00000           # 1.5
    fmadd.s a0, a1, a2, a4
    li   a3, 0x40f00000           # 7.5f
    bne  a0, a3, extzf_fail

    # -- fcvt.s.w / fcvt.w.s round-trip : 5 -> 5.0 -> 5 --
    li   a1, 5
    fcvt.s.w a0, a1
    li   a3, 0x40a00000           # 5.0f
    bne  a0, a3, extzf_fail
    fcvt.w.s a2, a0
    li   a3, 5
    bne  a2, a3, extzf_fail

    # -- fsgnj.s : |3.5| with sign of -1 -> -3.5 --
    li   a1, 0x40600000           # 3.5f
    li   a2, 0xbf800000           # -1.0f
    fsgnj.s a0, a1, a2
    li   a3, 0xc0600000           # -3.5f
    bne  a0, a3, extzf_fail

    # -- feq.s : 3.5 == 3.5 -> 1 --
    li   a1, 0x40600000
    fsgnj.s a2, a1, a1            # a2 = 3.5
    feq.s a0, a1, a2
    li   a3, 1
    bne  a0, a3, extzf_fail

    # -- fmin.s : min(3.5, -1.0) = -1.0 --
    li   a1, 0x40600000
    li   a2, 0xbf800000
    fmin.s a0, a1, a2
    li   a3, 0xbf800000
    bne  a0, a3, extzf_fail

    # -- fclass.s : classify -1.0 -> bit 1 (negative normal) --
    li   a1, 0xbf800000
    fclass.s a0, a1
    li   a3, 0x00000002
    bne  a0, a3, extzf_fail

    # -- fflags accumulation + rd=x0 still sets flags --
    csrrw x0, fflags, x0          # clear
    li   a1, 0x3f800000           # 1.0
    li   a2, 0x30000000           # ~2^-30
    fadd.s x0, a1, a2             # rd=x0, inexact -> NX must still set
    csrr a0, fflags
    li   a3, 0x01                 # NX
    bne  a0, a3, extzf_fail

    # -- frm write/read-back through the fcsr CSRs --
    csrrw x0, fflags, x0          # clear fflags first: the prior rd=x0 fadd left
                                  # NX(0x01) set, so fcsr would read 0x81 not 0x80
    li   a1, 0x00000004           # RMM
    csrw frm, a1
    csrr a0, frm
    li   a3, 0x00000004
    bne  a0, a3, extzf_fail
    csrr a0, fcsr                 # fcsr[7:5] must reflect frm
    li   a3, 0x00000080
    bne  a0, a3, extzf_fail
    csrw fflags, x0               # tidy up
    csrw frm, x0

    .option pop
#endif // CORE_ENABLE_ZFINX

    RVTEST_PASS

extzf_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
