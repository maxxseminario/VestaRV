# See LICENSE for license details.

# VestaRV: detector for the phantom bus read every `iret` issues
# THE DEFECT: maindec sets read_data_flag for the custom opcode with funct3 = 000 and funct7 = 0000000, which is the IRET encoding, and mem_access_instr follows it, so all four EXECUTE dispatch shapes test mem_access_controller BEFORE isr_ret and an `iret` takes the MEMORY arm; the isr_ret arms in EXECUTE are dead. data_addr then takes ALU_Result, the ALU does ADD with ALU_src low, so ALU_Result = reg[rs1] + reg[rs2], and WEN is all-ones so the phantom is a READ. The canonical `iret` has rs1 = rs2 = x0, so the address is 0, INSIDE THE SHARED BOOT ROM, and every ISR return on every hart performs a real arbiter transaction.
# THE OBSERVABLE IS NOT A TIMING THRESHOLD. ALU_Result is a decode of the instruction word and the custom-opcode arm never inspects rs1 or rs2, so `.insn r 0x0b,0,0,x0,<rs1>,x0` is the SAME instruction with the same trajectory and the same architectural effect, since the pop is addressed from stack_pointer in MEMORY_WAIT, but with the phantom read STEERED to reg[rs1]. That makes this a matched pair with no calibration: one `iret` at one PC executed three times, differing only in a register's value. Pass 1 uses rs1 = 0, putting the phantom in the shared boot ROM; pass 2 uses 0x9000, the private TCM; pass 3 uses 0x600C, HW mutex 3.
# LEG A is the direct bus watch and is primary: a mutex read is an atomic return-old-and-claim attributed to the granted master, so a later load returns the pre-existing owner. Reading 0 means nobody ever read mutex 3 and there was no phantom; reading hart 0 + 1 means a read transaction DID occur at ALU_Result and the only candidate is the iret. It is architectural, timing-free, and asserts the ADDRESS as well as the existence of the read. LEG B is the canonical address-0 case and the cost measurement: mcycle free-runs on clk and therefore SEES the stall that gates clk_cpu off, which clk_cpu-counting metrics are structurally blind to. Its bracket spans exactly the iret and the closing csrr, and the two brackets are byte-identical code at identical PCs, so d_ph - d_pr is the measured per-return cost. LEG C is pass 3's own delta, corroborating leg A in the timing domain.
# FOUR ANTI-VACUOUS GATES, each blocking a specific way of passing for the wrong reason, all enforced in both polarities. (1) A mutex positive control: before the ISR work hart 0 claim-reads mutex 2 twice, and the first must return 0 and the second hart 0 + 1, without which "leg A reads 0" is indistinguishable from a dead mutex bank. (2) The ISR must have run exactly three times. (3) All three pushed return PCs must equal the landing label; the interrupt is taken on the arming store inside its own MEMORY_WAIT, so this is structurally determined rather than calibrated, and it proves the three brackets really are the same bracket. (4) THE SHARED WINDOW MUST STILL BE SLOW: an independent 8-load A/B between private TCM and the shared boot ROM must show the shared burst costing at least 8 more clock cycles. THAT IS THE CRITERION A WRONG FIX CANNOT SATISFY, because a change that made address 0 cheap, or that broke sh_sel, would equalise the iret deltas and fail this gate.
# Verdicts: a0 = 0xCAFEBABE passes. a0 = 0xDEADBEEF with a1 = 0xF9F90001 leg A, the phantom read CLAIMED the mutex; 0xF9F90002 leg B, the address-0 iret cost more clock cycles than the private-target iret; 0xF9F90003 leg C, the mutex-target iret cost more; 0x5E900001 the first claim-read of a released mutex did not return 0; 0x5E900002 the re-read did not return hart 0 + 1, so the bank is not claiming; 0x5E900003 the ISR did not run exactly three times; 0x5E900004 a pushed return PC was wrong; 0x5E900005 the shared load burst cost fewer than 8 extra cycles, so the whole test is vacuous.
# Registers live at the verdict, so one probe run harvests everything: s2 and s3 the 8-load mcycle A/B giving the shared window's real cost; s5, s6 and s7 the three iret-return deltas; a2 mutex 3's pre-existing owner; a6 the ISR entry count; a4 the first return PC and a7 the landing address; s8 and s9 the two mutex-2 control reads.
# NO SHARED WORDS ARE CLAIMED. Outside the private TCM it touches HW mutex 2 and mutex 3, which are hardware rather than scratch and are RELEASED on every exit path except the deliberate fired path, which leaves mutex 3 owned by hart 0 so the DUT itself corroborates a0; the shared boot ROM at 0x200-0x21C, read-only, as the far side of the load-cost A/B; and CLINT msip[0] with IVT slot 83. Nothing in 0x10000-0x107FF is touched, so this test cannot collide with any other band at N=4 or N=18.
# Single hart: tiles 1-3 are never launched and park in the boot ROM, which the tb reports as silent or parked. `.option arch, +zicsr` is needed because rv32ua's -march has none, `.option norvc` throughout, and RVTEST_CODE_END is `unimp` here, so every path ends in an explicit PASS or FAIL spin.

#include "riscv_test.h"
#include "test_macros.h"

.option norelax
.option norvc

#define MCYCLE      0xB00
#define MSIP0       0x5000
#define MUTEX_PC    0x6008          /* mutex 2 -- the positive control       */
#define MUTEX_PH    0x600C          /* mutex 3 -- leg A's phantom target     */
#define TCM_PH      0x9000          /* inside the private TCM 0x8000-0xBFFF  */
#define ROM_BASE    0x00000200      /* 8 read-only shared boot-ROM words     */
#define TCM_BASE    0x00009000      /* 8 private TCM words for the A/B       */

RVTEST_RV32U
RVTEST_CODE_BEGIN

.option arch, +zicsr

    li   sp, 0xBFF0                 # sp MUST be valid before any IRQ

    # =====================================================================
    # GATE (1) -- MUTEX POSITIVE CONTROL.  Prove the claim mechanism is live
    # BEFORE relying on its silence as evidence.
    # =====================================================================
    li   s0, MUTEX_PC
    sw   x0, 0(s0)                  # release -> known free
    lw   s8, 0(s0)                  # claim-read #1: returns OLD owner = 0
    lw   s9, 0(s0)                  # claim-read #2: returns hart0+1 = 1
    sw   x0, 0(s0)                  # release again

    li   s1, MUTEX_PH
    sw   x0, 0(s1)                  # leg A's mutex starts KNOWN-FREE

    # =====================================================================
    # GATE (4) -- the shared window's real cost, measured independently of
    # any iret.  Eight DISTINCT words each side (hart_tile.vhd:717's
    # sh_acked_addr means eight loads of ONE address would be absorbed into a
    # single transaction and would measure nothing).
    # =====================================================================
    li   t2, TCM_BASE
    csrr s2, MCYCLE
    lw   t3,  0(t2)
    lw   t3,  4(t2)
    lw   t3,  8(t2)
    lw   t3, 12(t2)
    lw   t3, 16(t2)
    lw   t3, 20(t2)
    lw   t3, 24(t2)
    lw   t3, 28(t2)
    csrr t1, MCYCLE
    sub  s2, t1, s2                 # c_tcm

    li   t2, ROM_BASE
    csrr s3, MCYCLE
    lw   t3,  0(t2)
    lw   t3,  4(t2)
    lw   t3,  8(t2)
    lw   t3, 12(t2)
    lw   t3, 16(t2)
    lw   t3, 20(t2)
    lw   t3, 24(t2)
    lw   t3, 28(t2)
    csrr t1, MCYCLE
    sub  s3, t1, s3                 # c_sh

    # =====================================================================
    # THE THREE ISR PASSES.  One loop, one `iret`, one landing PC.  The ONLY
    # thing that differs between passes is the VALUE the ISR loads into t3,
    # which becomes the phantom read's address.
    # =====================================================================
    la   t0, f9_isrcnt
    sw   x0, 0(t0)
    li   s4, 0                      # pass index 0..2

f9_loop:
    la   t0, f9_target
    la   t1, f9_tbl
    slli t2, s4, 2
    add  t1, t1, t2
    lw   t2, 0(t1)
    sw   t2, 0(t0)                  # publish this pass's phantom target
    li   t2, MSIP0
    li   t1, 1
    sw   t1, 0(t2)                  # <- the interrupt is taken ON THIS STORE
f9_landing:
    csrr a5, MCYCLE                 # the resume lands HERE (store+4), EVERY pass
    sub  a5, a5, t6                 # d = mcycle(iret) + mcycle(this csrr)
    la   t0, f9_deltas
    slli t2, s4, 2
    add  t0, t0, t2
    sw   a5, 0(t0)
    addi s4, s4, 1
    li   t1, 3
    blt  s4, t1, f9_loop

    # =====================================================================
    # HARVEST
    # =====================================================================
    la   t0, f9_isrcnt
    lw   a6, 0(t0)                  # ISR entry count
    la   t0, f9_deltas
    lw   s5, 0(t0)                  # d_ph  pass 1, phantom -> 0x00000000 (ROM)
    lw   s6, 4(t0)                  # d_pr  pass 2, phantom -> 0x9000    (TCM)
    lw   s7, 8(t0)                  # d_mx  pass 3, phantom -> 0x600C  (MUTEX)
    la   t0, f9_retpcs
    lw   a4, 0(t0)
    lw   t4, 4(t0)
    lw   t5, 8(t0)
    la   a7, f9_landing

    lw   a2, 0(s1)                  # LEG A: this read is itself a claim, so it
                                    #   returns the PRE-EXISTING owner of mutex 3

    # =====================================================================
    # GATES -- setup first, so a broken run can never be read as a finding
    # =====================================================================
    bnez s8, f9_ctl1                # positive control: first read must be 0
    li   t0, 1
    bne  s9, t0, f9_ctl2            # positive control: re-read must be 1
    li   t0, 3
    bne  a6, t0, f9_ctl3            # the ISR must have run exactly 3 times
    bne  a4, a7, f9_ctl4            # all three resumes must be the SAME bracket
    bne  t4, a7, f9_ctl4
    bne  t5, a7, f9_ctl4
    addi t0, s2, 8
    bltu s3, t0, f9_ctl5            # the shared window must STILL be slow

    # =====================================================================
    # THE DISCRIMINATING CHECKS -- strongest (architectural) first
    # =====================================================================
    bnez a2, f9_legA                # LEG A: a real read happened at ALU_Result
    bne  s5, s6, f9_legB            # LEG B: the address-0 iret must cost the
                                    #   same as the private-target iret
    bne  s7, s6, f9_legC            # LEG C: so must the mutex-target one

    sw   x0, 0(s1)                  # release what our own probe read claimed
    RVTEST_PASS                     # a0 = 0xCAFEBABE

f9_legA:
    # DELIBERATELY does NOT release mutex 3: its owner must still read hart0+1
    # when the sim stops, so the hardware corroborates a0 (scfailrd convention).
    li   a1, 0xF9F90001
    j    f9_fail
f9_legB:    li a1, 0xF9F90002
            j  f9_fail
f9_legC:    li a1, 0xF9F90003
            j  f9_fail
f9_ctl1:    li a1, 0x5E900001
            j  f9_fail
f9_ctl2:    li a1, 0x5E900002
            j  f9_fail
f9_ctl3:    li a1, 0x5E900003
            j  f9_fail
f9_ctl4:    li a1, 0x5E900004
            j  f9_fail
f9_ctl5:    li a1, 0x5E900005
f9_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # =====================================================================
    # msip ISR (IVT slot 83, hardware-vectored).  Hart 0 is AWAKE, so no
    # `ignite` is needed.  ONE straight-line path -- no branches -- so every
    # pass executes the identical instruction sequence and leg B's two
    # brackets are structurally identical.  Uses t0/t3/t4/t5/t6 only; the main
    # flow re-derives t0/t1/t2 after every landing and keeps its state in
    # s0-s9/a*.
    #
    # `csrr t6, MCYCLE` MUST remain the instruction IMMEDIATELY before the
    # iret -- that adjacency is the bracket.
    # =====================================================================
f9_isr:
    la    t3, f9_isrcnt
    lw    t4, 0(t3)
    addi  t4, t4, 1
    sw    t4, 0(t3)                 # t4 = this pass's 1-based index
    lw    t5, 0(sp)                 # the return PC hardware pushed at sp-4
    la    t3, f9_retpcs
    slli  t0, t4, 2
    add   t3, t3, t0
    sw    t5, -4(t3)                # retpcs[index-1]
    li    t3, MSIP0
    sw    x0, 0(t3)                 # clear the msip LEVEL before returning
    la    t3, f9_target
    lw    t3, 0(t3)                 # t3 = THIS pass's phantom target
    csrr  t6, MCYCLE                # bracket open -- LAST instruction before iret
    .insn r 0x0b, 0, 0, x0, t3, x0  # iret, rs1 = t3  => ALU_Result = t3
                                    #   (funct3=0, funct7=0 => isr_ret AND
                                    #    read_data_flag, exactly as the canonical
                                    #    `iret` macro riscv_test.h:21-23, which is
                                    #    this same word with rs1 = x0)

    # ---- extend the env IVT: DEFINE_IVT emitted slots 0-82 ---------------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, f9_isr               # slot 83 = IRQB_CLINT_MSIP
    .previous

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
    .balign 4
f9_tbl:     .word 0x00000000        # pass 1: the CANONICAL iret's own address
            .word TCM_PH            # pass 2: private TCM  -- the control
            .word MUTEX_PH          # pass 3: HW mutex 3   -- leg A
f9_target:  .word 0
f9_isrcnt:  .word 0
f9_retpcs:  .word 0
            .word 0
            .word 0
f9_deltas:  .word 0
            .word 0
            .word 0
  TEST_DATA
RVTEST_DATA_END
