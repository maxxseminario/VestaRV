# See LICENSE for license details.

#*****************************************************************************
# iretphan.S   (F-series fix pass, wave W4 -- DETECTOR for finding F9)
#-----------------------------------------------------------------------------
# F9 (SILICON): every `iret` issues a real bus READ at ALU_Result.
#
#   maindec.vhd:1079-1080   read_data_flag <= '1' when op = I_LOAD_OPCODE else
#                                             '1' when (op = CUSTOM_OPCODE and
#                                                       funct3 = "000" and
#                                                       funct7 = "0000000") else ...
#                             ^ the IRET encoding (constants.vhd:65/78/104:
#                               CUSTOM_OPCODE 0001011, IRET_FN3 000, IRET_FN7 0000000)
#   maindec.vhd:1088        mem_access_instr <= read_data_flag or write_data_flag;
#   vesta.vhd:2677/2806/2959/3067  the four EXECUTE dispatch shapes test
#                           `elsif mem_access_controller = '1'` BEFORE
#                           `elsif isr_ret = '1'` (:2721/:2833/:2996; shape D at
#                           :3067 has no isr_ret arm at all), so an `iret` takes
#                           the MEMORY arm: mem_access_instr <= '1',
#                           next_state <= MEMORY_WAIT.  The isr_ret arms in
#                           EXECUTE are DEAD (finding R1).
#   vesta.vhd:1821          data_addr <= ALU_Result when mem_access_instr = '1'
#   maindec.vhd:1107        alu_control <= "0000000" (ADD) when op = CUSTOM_OPCODE
#   maindec.vhd:997-1009    ALU_src falls through to '0' for CUSTOM_OPCODE
#                           => ALU_Result = reg[rs1] + reg[rs2]
#   maindec.vhd:1016-1033   WEN = "1111" for CUSTOM_OPCODE => the phantom is a READ
#   hart_tile.vhd:654-657   sh_sel is a PURE DECODE of data_addr
#   hart_tile.vhd:726       sh_req_int <= sh_sel and not sh_ack_ok and resetn
#
#   The canonical `iret` (riscv_test.h:21-23, `.insn r 0x0b,0,0,x0,x0,x0`) has
#   rs1 = rs2 = x0, so ALU_Result = 0 -- INSIDE THE SHARED BOOT ROM.  Every ISR
#   return on every hart therefore performs a real arbiter transaction.
#   vesta.vhd:2224-2235 (the P3 red-team F2/F3 comment) states the mechanism in
#   the RTL's own words; P3 removed iret from the PMP data check and left the
#   DATA PATH phantom in place.
#
# ---------------------------------------------------------------------------
# THE OBSERVABLE, AND WHY IT IS NOT A TIMING THRESHOLD
# ---------------------------------------------------------------------------
# ALU_Result = reg[rs1] + reg[rs2] is a DECODE of the instruction word, and the
# custom-opcode arm never inspects rs1/rs2 -- so `.insn r 0x0b,0,0,x0,<rs1>,x0`
# is the SAME instruction (isr_ret = '1', identical trajectory, identical
# architectural effect: the pop is addressed from stack_pointer in MEMORY_WAIT,
# vesta.vhd:1824) with the phantom read STEERED to reg[rs1].
#
# That turns F9 into a matched pair with NO calibration and NO threshold
# (R-W2-2): ONE `iret` instruction, at ONE PC, executed three times, differing
# only in the VALUE a register holds.
#
#   pass 1  rs1 = 0        -> phantom at 0x00000000  (shared boot ROM)
#   pass 2  rs1 = 0x9000   -> phantom in the PRIVATE TCM (0x8000-0xBFFF)
#   pass 3  rs1 = 0x600C   -> phantom at HW MUTEX 3
#
# LEG A (the direct bus watch, primary).  mutex_bank.vhd:99-110: a READ is an
# atomic return-old-and-claim attributed to the arbiter's granted master, so a
# later `lw` returns the PRE-EXISTING owner:
#       0 -> nobody ever read mutex 3.  No phantom.            (post-fix)
#       1 -> owner = hart 0 + 1: a read transaction DID occur
#            at ALU_Result, and the only candidate is the iret. (F9 FIRED)
# This is the scfailrd.S (W1/F2) instrument, re-aimed.  It is architectural,
# timing-free, and it asserts the ADDRESS as well as the existence of the read.
#
# LEG B (the canonical address-0 case, and the COST MEASUREMENT).  mcycle
# free-runs on clk (csr_unit.vhd:663 samples on rising_edge(clk)), so it SEES
# the stall that gates clk_cpu off (vesta.vhd:1116 `en_clk_cpu <= '0' when
# mem_ready = '0'`).  R-W1-1 rules that clk_cpu-counting metrics are
# STRUCTURALLY BLIND to this class; mcycle is the mclk-domain instrument that
# ruling names.  Bracket = {the ISR's last instruction before iret} ..
# {the first instruction after the resume}, so it spans exactly the iret and
# the closing csrr -- and the two brackets are byte-identical code at identical
# PCs.  d_ph - d_pr IS the measured per-ISR-return cost of F9.
#
# LEG C  pass 3's own delta, corroborating leg A in the timing domain.
#
# ---------------------------------------------------------------------------
# ANTI-VACUOUS GATES -- each one blocks a specific way of passing for the wrong
# reason.  All are enforced in the image, in BOTH polarities.
# ---------------------------------------------------------------------------
#   (1) MUTEX POSITIVE CONTROL.  Before the ISR work, hart 0 claim-reads
#       mutex 2 twice: the first must return 0 and the second must return 1.
#       Without this, "leg A reads 0" post-fix is indistinguishable from a dead
#       mutex bank.
#   (2) THE ISR MUST HAVE RUN EXACTLY THREE TIMES.
#   (3) ALL THREE PUSHED RETURN PCs MUST EQUAL &f9_landing -- the interrupt is
#       taken on the arming `sw` inside its own MEMORY_WAIT (vesta.vhd:3536),
#       so this is structurally determined, not calibrated, and it proves the
#       three brackets really are the same bracket.
#   (4) THE SHARED WINDOW MUST STILL BE SLOW.  An independent 8-load A/B
#       (private TCM vs the shared boot ROM) must show the shared burst costing
#       at least 8 more clk cycles.  THIS IS THE CRITERION A WRONG FIX CANNOT
#       SATISFY: post-fix the test demands d_ph == d_pr *while* the shared
#       window still costs +8 or more on a real load burst.  A "fix" that made
#       address 0 cheap, or that broke sh_sel, would equalise the iret deltas
#       and FAIL this gate.
#
# ---------------------------------------------------------------------------
# Verdict / a1 codes
# ---------------------------------------------------------------------------
#   a0=0xCAFEBABE                  PASS (post-fix expectation)
#   a0=0xDEADBEEF, a1=0xF9F90001   LEG A: the iret's phantom read CLAIMED the
#                                  mutex -- a real bus transaction at ALU_Result
#   a0=0xDEADBEEF, a1=0xF9F90002   LEG B: the address-0 iret cost more clk
#                                  cycles than the private-target iret
#   a0=0xDEADBEEF, a1=0xF9F90003   LEG C: the mutex-target iret cost more clk
#                                  cycles than the private-target iret
#   a0=0xDEADBEEF, a1=0x5E900001   mutex positive control: first claim-read of a
#                                  released mutex did not return 0
#   a0=0xDEADBEEF, a1=0x5E900002   mutex positive control: re-read did not
#                                  return hart0+1 -- the bank is not claiming
#   a0=0xDEADBEEF, a1=0x5E900003   the ISR did not run exactly 3 times
#   a0=0xDEADBEEF, a1=0x5E900004   a pushed return PC was not &f9_landing
#   a0=0xDEADBEEF, a1=0x5E900005   the shared load burst cost < 8 extra clk
#                                  cycles -- gate (4), the whole test is vacuous
#
# Registers live at the verdict (a probe harvests everything in one run):
#   s2 c_tcm   s3 c_sh    (8-load mcycle A/B: the shared window's real cost)
#   s5 d_ph    s6 d_pr    s7 d_mx   (the three iret-return mcycle deltas)
#   a2 mutex-3 pre-existing owner   a6 ISR entry count
#   a4 retpc[0]   a7 &f9_landing
#   s8 mutex-2 first claim-read (must be 0)  s9 second (must be 1)
#
# ---------------------------------------------------------------------------
# SHARED WORDS CLAIMED: NONE.
#   This detector needs no shared RAM scratch.  The hardware it touches outside
#   the private TCM is:
#     * HW MUTEX 2 @0x6008 (positive control) and MUTEX 3 @0x600C (leg A) --
#       hardware, not scratch; both are RELEASED on every exit path except the
#       deliberate F9-fired path, which leaves mutex 3 owned by hart 0 so the
#       DUT itself corroborates a0 (the scfailrd.S convention).
#     * the shared boot ROM at 0x200-0x21C -- READ-ONLY, 8 distinct words, used
#       only as the far side of the load-cost A/B.  Nothing is written there.
#     * CLINT msip[0] @0x5000 and IVT slot 83.
#   Nothing in 0x10000-0x107FF is touched, so this test cannot collide with
#   W1's band (0x10420-0x1043C), W3's (0x103E8-0x10404), or any committed test
#   at N=4 OR at N=18.
#
# Single hart.  Tiles 1-3 are never launched; they park in the boot ROM and the
# tb reports "tile hart(s) silent/parked", which is expected.
#
# Conventions: `.option arch, +zicsr` (rv32ua's -march has no zicsr);
#   `.option norvc`; RVTEST_CODE_END is `unimp` in this env, so every path ends
#   in an explicit RVTEST_PASS / RVTEST_FAIL spin.
#*****************************************************************************

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
