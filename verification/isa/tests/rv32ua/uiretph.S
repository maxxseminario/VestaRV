# See LICENSE for license details.

#*****************************************************************************
# uiretph.S   (F-series fix pass, wave W4 -- the VERIFY-FIRST PROBE for F12)
#-----------------------------------------------------------------------------
# F12 AS FILED: `isr_ret` carries the U-mode qualifier (maindec.vhd:921,
# `and u_gate = '0'`) but `read_data_flag`'s iret arm (maindec.vhd:1080) does
# NOT.  R1 established that read_data_flag -- not isr_ret -- is what drives the
# EXECUTE trajectory.  So the filed hypothesis is that a U-mode `iret` becomes
# a PHANTOM LOAD THAT RETIRES INSTEAD OF TRAPPING.  Whether `trap` also rises
# was never established.  THIS FILE ESTABLISHES IT.  A refutation is a fine
# outcome and is what this probe is expected to produce.
#
# ON-ONLY.  Requires a trapCsr+umode staged build (both MemoryMap constants
# true) AND -DCORE_ENABLE_TRAPCSR -DCORE_ENABLE_UMODE on RISCV_GCC_OPTS.  The
# #else arm FAILs loudly; this test is NOT in the standing TEST_FILES array.
#
# ---------------------------------------------------------------------------
# WHAT IS MEASURED, AND HOW
# ---------------------------------------------------------------------------
# LEG 1 -- the CANONICAL U-mode iret (`.insn r 0x0b,0,0,x0,x0,x0`, the
#   riscv_test.h:21-23 macro word).  The instruction after it sets a witness
#   and then ECALLs, so BOTH outcomes come back to M with exactly one trap and
#   are distinguishable:
#       trap fires   -> mcause 2 (illegal instruction), mepc = the iret's OWN
#                       pc, witness still 0.                    F12 REFUTED
#       no trap      -> mcause 8 (ECALL from U), mepc = the ecall's pc,
#                       witness = 0x0BAD0001 -- the iret RETIRED.  F12 REAL
#
# LEG 2 -- the SAME instruction with the rs2/rs1 fields set so the phantom's
#   address is a HW MUTEX (mutex_bank.vhd:99-110: a read is an atomic
#   return-old-and-claim attributed to the arbiter's granted master).  This is
#   the direct bus watch -- it answers "what does the bus present?" without a
#   waveform:
#       mutex reads 0 -> NO transaction was issued at ALU_Result in U-mode
#       mutex reads 1 -> owner = hart 0 + 1: the U-mode phantom read FIRED
#   ALU_Result = reg[rs1] + reg[rs2] for CUSTOM_OPCODE (maindec.vhd:997-1009
#   ALU_src '0', :1107 alu_control ADD), and the custom-opcode decode never
#   inspects rs1/rs2 -- so this is the same instruction with a steered address,
#   exactly as iretphan.S (the F9 detector) uses it in M-mode.
#
# THE POSITIVE CONTROL IS A SEPARATE RUN, DELIBERATELY: `xrv32ua-p-iretphan`
#   is run on THIS SAME knobs-on build.  It must still report
#   a1 = 0xF9F90001 / a2 = 1, i.e. the M-mode phantom still claims its mutex on
#   this configuration.  Without that, "the U-mode mutex stayed free" would be
#   indistinguishable from "this build issues no phantoms at all".
#
# The mutex bank's own liveness is ALSO proven inside this file (mutex 2 is
# claim-read twice: 0 then 1), so a leg-2 zero can never be a dead-bank zero.
#
# ---------------------------------------------------------------------------
# Verdict / a1 codes.  a0 = 0xCAFEBABE means F12 is REFUTED.
# ---------------------------------------------------------------------------
#   a0=0xDEADBEEF, a1=0xF12F0001   LEG 1: the U-mode iret did NOT trap
#                                  (mcause was not 2)
#   a0=0xDEADBEEF, a1=0xF12F0002   LEG 1: mepc was not the iret's own pc
#   a0=0xDEADBEEF, a1=0xF12F0003   LEG 1: the witness after the iret executed
#                                  -- the instruction RETIRED
#   a0=0xDEADBEEF, a1=0xF12F0004   LEG 2: the steered U-mode iret did not trap
#   a0=0xDEADBEEF, a1=0xF12F0005   LEG 2: THE PHANTOM FIRED IN U-MODE -- the
#                                  mutex was claimed.  F12 IS REAL.
#   a0=0xDEADBEEF, a1=0x5E120001   mutex positive control broke (bank not live)
#   a0=0xDEADBEEF, a1=0x5E120002   wrong number of traps delivered
#   a0=0xDEADBEEF, a1=0x5E120003   a U-mode entry/CSR precondition failed
#   a0=0xDEADBEEF, a1=0x5E12BAD0   built on the wrong polarity (#else arm)
#
# Registers live at the verdict:
#   a3 leg1 mcause   a4 leg1 mepc    a5 leg1 mtval   s8  leg1 witness
#   a6 leg2 mcause   a7 leg2 mepc    s10 leg2 mtval  s11 leg2 witness
#   a2 mutex-4 pre-existing owner (leg 2's bus watch)
#   s3 trap count    s0 expected mepc for the leg under test
#
# SHARED WORDS CLAIMED: NONE.  HW MUTEX 2 @0x6008 (liveness control) and
#   MUTEX 4 @0x6010 (leg 2) only; both hardware, both released on exit except
#   the deliberate F12-REAL path.  Nothing in 0x10000-0x107FF is touched.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define MUTEX_LIVE  0x6008          /* mutex 2 -- bank liveness control */
#define MUTEX_U     0x6010          /* mutex 4 -- leg 2's phantom target */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity: prove the core runs before any privilege work ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, uf_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0                      # trap counter

    # =====================================================================
    # MUTEX BANK LIVENESS (so a leg-2 zero can never be a dead-bank zero)
    # =====================================================================
    li   t0, MUTEX_LIVE
    sw   x0, 0(t0)                  # release -> known free
    lw   t1, 0(t0)                  # claim-read #1 -> 0
    lw   t2, 0(t0)                  # claim-read #2 -> hart0 + 1
    sw   x0, 0(t0)                  # release
    li   a1, 0x5E120001
    bnez t1, uf_fail
    li   t3, 1
    bne  t2, t3, uf_fail

    li   s2, MUTEX_U
    sw   x0, 0(s2)                  # leg 2's mutex starts KNOWN-FREE

    # =====================================================================
    # arm mtvec, THEN opt into STANDARD delivery (privumode's frozen order --
    # MRET is only defined in standard mode)
    # =====================================================================
    li   a1, 0x5E120003
    la   t0, uf_handler
    csrw 0x305, t0
    csrr t1, 0x305
    bne  t1, t0, uf_fail
    csrw 0x7C0, x0                  # mtrapctl.LEGACY = 0 -> standard delivery
    csrr t1, 0x7C0
    bne  t1, x0, uf_fail

    # =====================================================================
    # LEG 1 -- the CANONICAL iret, executed in U-MODE
    # =====================================================================
    li   s1, 0
    la   s0, uf_uiret1              # expected mepc if it traps
    la   s9, uf_m1
    csrw 0x300, x0                  # MPP = 00 (U), MIE = 0, TW = 0
    la   t0, uf_uentry1
    csrw 0x341, t0
    mret                            # ---- now in U-MODE ----

uf_uentry1:
    nop
uf_uiret1:
    .insn r 0x0b, 0, 0, x0, x0, x0  # THE CANONICAL `iret`, IN U-MODE
    li   s1, 0x0BAD0001             # reached ONLY if it did not trap
    ecall                           # ...and this returns us to M either way

uf_m1:                              # ---- back in M (handler jr s9) ----
    mv   a3, s4                     # mcause
    mv   a4, s5                     # mepc
    mv   a5, s7                     # mtval
    mv   s8, s1                     # witness
    li   a1, 0x5E120002
    li   t3, 1
    bne  s3, t3, uf_fail

    # =====================================================================
    # LEG 2 -- the same instruction with the phantom STEERED at a HW MUTEX
    # =====================================================================
    li   s1, 0
    li   t3, MUTEX_U                # t3 = x28: ALU_Result = reg[t3] + x0
    la   s0, uf_uiret2
    la   s9, uf_m2
    csrw 0x300, x0                  # MPP = 00 (U)
    la   t0, uf_uentry2
    csrw 0x341, t0
    mret                            # ---- U-MODE again ----

uf_uentry2:
    nop
uf_uiret2:
    .insn r 0x0b, 0, 0, x0, t3, x0  # steered `iret`, IN U-MODE
    li   s1, 0x0BAD0002             # reached ONLY if it did not trap
    ecall

uf_m2:
    mv   a6, s4                     # mcause
    mv   a7, s5                     # mepc
    mv   s10, s7                    # mtval
    mv   s11, s1                    # witness
    li   a1, 0x5E120002
    li   t3, 2
    bne  s3, t3, uf_fail

    lw   a2, 0(s2)                  # THE BUS WATCH: pre-existing owner of the
                                    #   mutex.  0 = never read.  1 = hart 0
                                    #   claimed it = the U-mode phantom FIRED.

    # =====================================================================
    # THE VERDICT
    # =====================================================================
    li   t0, 2                      # 2 = illegal instruction
    li   a1, 0xF12F0001
    bne  a3, t0, uf_fail            # LEG 1: must have trapped, cause 2
    la   t1, uf_uiret1
    li   a1, 0xF12F0002
    bne  a4, t1, uf_fail            # LEG 1: mepc = the iret's OWN pc
    li   a1, 0xF12F0003
    bnez s8, uf_fail                # LEG 1: the iret must NOT have retired

    li   a1, 0xF12F0004
    bne  a6, t0, uf_fail            # LEG 2: must have trapped, cause 2
    la   t1, uf_uiret2
    bne  a7, t1, uf_fail            # LEG 2: mepc = the iret's OWN pc
    bnez s11, uf_fail               # LEG 2: must NOT have retired

    li   a1, 0xF12F0005
    bnez a2, uf_fail                # LEG 2: THE BUS WATCH.  A claimed mutex
                                    #   means a real read transaction issued at
                                    #   ALU_Result in U-mode.  F12 IS REAL.

    sw   x0, 0(s2)                  # release what our own probe read claimed
    RVTEST_PASS                     # a0 = 0xCAFEBABE  ==>  F12 REFUTED

    .align 2
uf_handler:
    csrr s4, 0x342                  # mcause
    csrr s5, 0x341                  # mepc
    csrr s6, 0x300                  # mstatus AS PUSHED
    csrr s7, 0x343                  # mtval
    addi s3, s3, 1
    jr   s9

    .option pop

#else
    li   a1, 0x5E12BAD0
    j    uf_fail
#endif

uf_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
