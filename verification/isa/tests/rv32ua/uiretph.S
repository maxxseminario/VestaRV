# See LICENSE for license details.

# VestaRV: verify-first probe for a U-mode `iret` phantom load
# THE HYPOTHESIS AS FILED: isr_ret carries the U-mode qualifier but read_data_flag's iret arm does not, and read_data_flag rather than isr_ret is what drives the EXECUTE trajectory, so a U-mode `iret` becomes a phantom load that RETIRES instead of trapping. Whether `trap` also rises was never established, and this file establishes it. A REFUTATION IS A FINE OUTCOME and is what this probe is expected to produce.
# ON-ONLY: it needs a staged trapCsr and umode build with both MemoryMap constants true AND -DCORE_ENABLE_TRAPCSR -DCORE_ENABLE_UMODE on the compile options. The #else arm fails loudly and this test is not in the standing runner array.
# LEG 1 uses the CANONICAL U-mode iret. The instruction after it sets a witness and then ECALLs, so both outcomes return to M with exactly one trap and are distinguishable: a trap gives mcause 2 with mepc at the iret's own PC and the witness still 0, refuting the hypothesis; no trap gives mcause 8 with mepc at the ecall and the witness set, meaning the iret retired.
# LEG 2 uses the SAME instruction with the register fields set so the phantom's address is a HW MUTEX, where a read is an atomic return-old-and-claim attributed to the granted master. That is the direct bus watch and answers what the bus presents without a waveform: the mutex reading 0 means no transaction was issued at ALU_Result in U-mode, and reading hart 0 + 1 means the phantom fired. ALU_Result is reg[rs1] + reg[rs2] for the custom opcode and the decode never inspects those fields, so this is the same instruction with a steered address.
# THE POSITIVE CONTROL IS A SEPARATE RUN, DELIBERATELY: the M-mode sibling probe is run on this same knobs-on build and must still report its phantom claiming the mutex. Without that, "the U-mode mutex stayed free" would be indistinguishable from "this build issues no phantoms at all". The bank's own liveness is also proven inside this file, by claim-reading another mutex twice and requiring 0 then hart 0 + 1, so a leg-2 zero can never be a dead-bank zero.
# Verdicts: a0 = 0xCAFEBABE means the hypothesis is refuted. a0 = 0xDEADBEEF with a1 = 0xF12F0001 leg 1 did not trap; 0xF12F0002 leg 1's mepc was not the iret's own PC; 0xF12F0003 the witness after the iret executed, so the instruction retired; 0xF12F0004 leg 2's steered iret did not trap; 0xF12F0005 THE PHANTOM FIRED IN U-MODE and the mutex was claimed; 0x5E120001 the mutex positive control broke, so the bank is not live; 0x5E120002 the wrong number of traps was delivered; 0x5E120003 a U-mode entry or CSR precondition failed; 0x5E12BAD0 built on the wrong polarity.
# Registers live at the verdict: a3, a4 and a5 leg 1's mcause, mepc and mtval with s8 its witness; a6, a7 and s10 leg 2's mcause, mepc and mtval with s11 its witness; a2 the pre-existing owner of leg 2's mutex; s3 the trap count and s0 the expected mepc for the leg under test.
# NO SHARED WORDS ARE CLAIMED: only HW mutex 2 as the liveness control and mutex 4 for leg 2, both hardware and both released on exit except on the deliberate fired path. Nothing in 0x10000-0x107FF is touched.

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
