# See LICENSE for license details.

#*****************************************************************************
# privrt1.S   (P2 RED TEAM — the TRAP-ENTRY SIDE-EFFECT class)
#-----------------------------------------------------------------------------
# ON-ONLY DIRECTED TEST (needs a trapCsr+umode build).
#
# THE BUG CLASS THIS FILE OWNS: "a decode output that bypasses valid_funct and
# commits a side effect for an instruction that TRAPPED".  Two members of the
# class were real, working U-mode escapes found while building P2 (see
# verification/isa/negctrl/p2_umode_seeds.repro.txt (d)), and BOTH needed two
# fixes, because `read_data` doubles as the instruction during decode: the
# faulting encoding is STILL presented to maindec through MTRAP_SV/MTRAP_JUMP,
# by which time `priv` has already flipped to M and maindec's u_gate has
# dropped.  The closing block is vesta.vhd's `trap_entry_seq`, which gates
# csr_valid, isr_ret and the free-running `sleep_cpu` flop across both entry
# cycles.
#
# privucsr already proves that all four privileged encodings TRAP, and proves
# the csr_valid half of the fix at ONE CSR (mscratch).  This file adds the
# three witnesses privucsr does NOT carry:
#
#   1. THE sleep_cpu WITNESS.  A U-mode `extinguish` traps -- but did it leave
#      `sleep_cpu` alone?  sleep_cpu has EXACTLY ONE architectural observation
#      point in the whole core: the legacy IRQ_REST arm
#      (vesta.vhd IRQ_REST: `elsif sleep_cpu = '1' then next_state <= SLEEPING`).
#      So the witness is an `iret` executed in STANDARD mode -- P1 accepted
#      deviation (b), "unspecified-but-bounded": isr_ret still routes
#      EXECUTE -> IRQ_REST, which pops a return PC from mem[sp] and resumes.
#      If sleep_cpu were set the hart would enter SLEEPING instead.
#
#      BOUNDEDNESS BY CONSTRUCTION.  Before every `iret` the test arms
#      mtimecmp[0] = mtime + 0x8000 with mie.MTIE and mstatus.MIE=1, so mtip is
#      NOT yet pending when the iret issues (std_irq_take is '0' at the
#      IRQ_REST check point) but WILL pend ~1.4 ms later.  The correct path
#      resumes at mem[sp] and disarms the timer within a handful of
#      instructions; the buggy path parks in SLEEPING and is dragged out by
#      that timer into the handler, which FAILs at CHECK 90 on the phase
#      marker s10.  Neither path can hang, and both are far inside the 100 ms
#      tb watchdog.
#
#      PHASE 1 runs the SAME vehicle once BEFORE any U-mode work, while
#      sleep_cpu is provably '0' (reset value; no extinguish has executed).
#      That is the control: if the vehicle itself were broken, PHASE 1 fails
#      at CHECK 10 and the PHASE 3 result means nothing.
#
#   2. csr_valid AT TWO MORE CSRs.  privucsr's sentinel is mscratch (pure
#      storage).  Here the U-mode poisons are `csrs mie, 0x888` and
#      `csrw mcounteren, -1` -- both are LIVE control state (mie gates
#      delivery; mcounteren gates U's own counter access), and both read back
#      in M.  Deliberately NOT mtvec/mepc/mtrapctl: a committed write to any
#      of those would derail the trap path itself into an unbounded hang
#      instead of a bounded miscompare.
#
#   3. THE DOCUMENTED-GAP WITNESS (CHECK 25/33).  p0_specs.md 3: "U-mode
#      memory access is UNRESTRICTED until P3".  P2 is a PRIVILEGE boundary,
#      not a MEMORY boundary: mtvec and every M-mode handler live in the
#      private TCM, which U-mode can store to.  CHECK 33 PINS that documented
#      behaviour (a U-mode `sw` into the ISR bank at 0xB704 lands) so P3's PMP
#      cannot change it silently -- when PMP arrives this check MUST be
#      revisited, not deleted.
#
# REGISTER CONTRACT (standard mode pushes NOTHING; M and U share the regfile):
#   s0   the poison's own address -- published by the U code, checked as mepc
#   s3   poison-trap counter (handler increments)
#   s6   CLINT mtimecmp[0] lo (0x5020);  s7  CLINT mtime lo (0x5010)
#   s9   M-mode continuation address (handler `jr s9` on a U ECALL)
#   s10  IRET-VEHICLE PHASE MARKER: 0 = iret in flight, expect a resume;
#        1 = resumed.  The timer handler FAILs iff it fires with s10 = 0.
#   s11  the U code's EXPECTED trap count
#   ra   subroutine link (pv1_arm_timer / pv1_disarm) -- never touched by the
#        handler, so a trap cannot corrupt it
#   t4   CHECK ID at every comparison
#
# BUILD-TIME DISPATCH: ON iff BOTH -DCORE_ENABLE_TRAPCSR and -DCORE_ENABLE_UMODE
# are appended to RISCV_GCC_OPTS on a staged trapCsr+umode build.  privrt1 is
# deliberately NOT in the default behavioral_mp runner array, so the #else arm
# must never execute.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity: prove the core runs before any privilege work ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, pv1_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s0, 0
    li   s3, 0
    li   s10, 1                     # no iret in flight yet
    li   s11, 0
    li   s6, 0x00005020             # CLINT mtimecmp[0] lo
    li   s7, 0x00005010             # CLINT mtime lo

    # =====================================================================
    # M SETUP — CHECK 1..3
    # =====================================================================
    li   t4, 1                      # arm mtvec BEFORE opting into standard mode
    la   s2, pv1_handler
    csrw 0x305, s2
    csrr t2, 0x305
    bne  t2, s2, pv1_fail

    li   t4, 2                      # STANDARD delivery (mtrapctl.LEGACY = 0)
    csrw 0x7C0, x0
    csrr t2, 0x7C0
    bne  t2, x0, pv1_fail

    li   t4, 3                      # quiet machine state
    csrw 0x300, x0
    csrw 0x304, x0
    csrw 0x306, x0
    csrr t2, 0x300
    bne  t2, x0, pv1_fail
    csrr t2, 0x306
    bne  t2, x0, pv1_fail

    # =====================================================================
    # PHASE 1 — CONTROL RUN of the iret/IRQ_REST observation vehicle, while
    # sleep_cpu is provably '0' (reset value; nothing has executed
    # extinguish).  If this leg fails, the vehicle is broken and PHASE 3
    # proves nothing — which is exactly why it is here.
    # =====================================================================
    li   t4, 10
    jal  ra, pv1_arm_timer
    li   s10, 0                     # iret in flight: a timer trap now = FAIL
    li   sp, 0x0000BF00
    la   t0, pv1_ret1
    sw   t0, 0(sp)
    iret                            # -> IRQ_REST -> PC <- mem[sp]
    j    pv1_fail                   # iret must NOT fall through

pv1_ret1:
    li   s10, 1                     # resumed: the vehicle works
    csrw 0x300, x0                  # mstatus.MIE off
    csrw 0x304, x0                  # mie off
    jal  ra, pv1_disarm
    li   sp, 0xBFF0
    li   t4, 11
    li   t3, 0
    bne  s3, t3, pv1_fail           # the control leg must have trapped ZERO times

    # =====================================================================
    # PHASE 2 — U-mode poisons whose SIDE EFFECTS bypass valid_funct.
    # CHECK ids 21..25 are set IN U, one per poison.
    # =====================================================================
    li   t4, 20
    la   s9, pv1_m2
    la   t0, pv1_u1
    csrw 0x341, t0                  # mepc
    csrw 0x300, x0                  # mstatus = 0 : MPP=00, MIE=0, MPIE=0, TW=0
    mret                            # ---- U-MODE ----

pv1_u1:
    # ORDER IS LOAD-BEARING — READ BEFORE EDITING.  `ignite` (wake_rq) CLEARS
    # sleep_cpu and `extinguish` (sleep_rq) SETS it, and both drive the SAME
    # free-running flop.  With extinguish FIRST and ignite second the seeded
    # escape sets the flop and then immediately clears it again: the witness in
    # PHASE 3 sees a clean 0 and the negative control does NOT bite.  (That is
    # exactly the X3 `jvtmask` failure mode — a control that cannot be observed
    # is not a control.  The first draft of this file had it that way and the
    # p2rt_sleepentry seed PASSED.)  extinguish must be the LAST custom-opcode
    # poison before the witness.
    li   t4, 21                     # POISON 1: ignite  (drives wake_rq -> the
    addi s11, s11, 1                #   clearing direction of sleep_cpu)
    la   s0, pv1_p1
pv1_p1:
    ignite
    bne  s3, s11, pv1_fail

    li   t4, 22                     # POISON 2: extinguish  (drives sleep_rq ->
    addi s11, s11, 1                #   the SETTING direction; the one PHASE 3
    la   s0, pv1_p2                 #   observes)
pv1_p2:
    extinguish
    bne  s3, s11, pv1_fail

    li   t4, 23                     # POISON 3: csrs mie, 0x888 — a WRITE to
    li   t0, 0x888                  #   live delivery state.  Must trap AND
    addi s11, s11, 1                #   commit nothing (CHECK 31 reads it back).
    la   s0, pv1_p3
pv1_p3:
    csrs 0x304, t0
    bne  s3, s11, pv1_fail

    li   t4, 24                     # POISON 4: csrw mcounteren, -1 — a U-mode
    li   t0, -1                     #   write that would UNLOCK U's own counter
    addi s11, s11, 1                #   access (CHECK 32 reads it back).
    la   s0, pv1_p4
pv1_p4:
    csrw 0x306, t0
    bne  s3, s11, pv1_fail

    li   t4, 25                     # DOCUMENTED-GAP WITNESS: U-mode store into
    li   t0, 0x0000B704             #   the M-mode ISR bank.  p0_specs.md 3 —
    li   t1, 0x5EC0DE01             #   "U-mode memory access is UNRESTRICTED
    sw   t1, 0(t0)                  #   until P3".  This MUST land today.

    ecall                           # -> M (mcause 8): the handler does `jr s9`
    j    pv1_fail

    # =====================================================================
    # PHASE 2 verdicts (M) — CHECK 30..33
    # =====================================================================
pv1_m2:
    li   t4, 30                     # exactly four poisons trapped
    li   t3, 4
    bne  s3, t3, pv1_fail

    li   t4, 31                     # mie must STILL read 0 — the U-mode
    csrr t2, 0x304                  #   `csrs mie` trapped and committed nothing
    bne  t2, x0, pv1_fail

    li   t4, 32                     # mcounteren must STILL read 0
    csrr t2, 0x306
    bne  t2, x0, pv1_fail

    li   t4, 33                     # the U-mode store into the M-mode ISR bank
    li   t0, 0x0000B704             #   DID land.  PINS the documented P2 gap —
    lw   t1, 0(t0)                  #   revisit (do not delete) at P3/PMP.
    li   t2, 0x5EC0DE01
    bne  t1, t2, pv1_fail
    sw   x0, 0(t0)

    # =====================================================================
    # PHASE 3 — THE sleep_cpu WITNESS.  POISON 1's U-mode `extinguish` and
    # POISON 2's `ignite` both trapped; they must ALSO have left sleep_cpu
    # untouched.  Re-run the PHASE-1 vehicle: if sleep_cpu is set, IRQ_REST
    # parks in SLEEPING and the armed timer FAILs us at CHECK 90.
    # =====================================================================
    li   t4, 40
    jal  ra, pv1_arm_timer
    li   s10, 0
    li   sp, 0x0000BF00
    la   t0, pv1_ret2
    sw   t0, 0(sp)
    iret
    j    pv1_fail

pv1_ret2:
    li   s10, 1
    csrw 0x300, x0
    csrw 0x304, x0
    jal  ra, pv1_disarm
    li   sp, 0xBFF0

    li   t4, 41                     # no extra traps were taken along the way
    li   t3, 4
    bne  s3, t3, pv1_fail

    # =====================================================================
    # PHASE 4 — restore and finish.  Clear every source and mask BEFORE
    # returning to LEGACY delivery (re-arming the legacy irq_handler with a
    # level still high would vector through an IVT slot a plain rv32ua image
    # does not populate).
    # =====================================================================
    li   t4, 50
    csrw 0x300, x0
    csrw 0x304, x0
    csrw 0x306, x0
    li   t1, 0x00000001
    csrw 0x7C0, t1                  # back to LEGACY delivery
    csrr t2, 0x7C0
    bne  t2, t1, pv1_fail

    RVTEST_PASS

    # =====================================================================
    # Subroutines and the mtvec handler.  Placed AFTER the RVTEST_PASS spin
    # loop, so they can only be reached by an explicit jal or by hardware.
    # =====================================================================

    # Arm mtimecmp[0] = mtime + 0x8000 (~1.4 ms at mclk=24 MHz), then unmask
    # mie.MTIE and mstatus.MIE.  The hi word is parked all-ones across the lo
    # write so the level can never glitch high mid-update.
    .align 2
pv1_arm_timer:
    li   t1, -1
    sw   t1, 4(s6)                  # mtimecmp hi = all-ones (quiet)
    lw   t0, 0(s7)                  # mtime lo
    li   t1, 0x8000
    add  t0, t0, t1
    sw   t0, 0(s6)                  # mtimecmp lo = mtime + K
    sw   x0, 4(s6)                  # mtimecmp hi = 0 -> level arms at mtime+K
    li   t0, 0x00000080
    csrw 0x304, t0                  # mie.MTIE
    li   t0, 0x00000008
    csrw 0x300, t0                  # mstatus.MIE = 1 (MPP=00, MPIE=0, TW=0)
    ret

    # Park mtimecmp back at all-ones and wait, BOUNDED, for mip.MTIP to fall.
    .align 2
pv1_disarm:
    li   t0, -1
    sw   t0, 4(s6)
    li   t1, 4096
pv1_dis_w:
    csrr t0, 0x344
    andi t0, t0, 0x80
    beqz t0, pv1_dis_q
    addi t1, t1, -1
    bnez t1, pv1_dis_w
    li   t4, 94                     # mtip never fell
    j    pv1_fail
pv1_dis_q:
    ret

    # The mtvec handler.  U-mode cannot read mcause/mepc, so every poison is
    # verified here, in M.  A mismatch jumps straight into RVTEST_FAIL.
    .align 2
pv1_handler:
    csrr t5, 0x342                  # mcause
    csrr t6, 0x341                  # mepc
    li   t3, 0x80000007
    beq  t5, t3, pv1_h_timer        # machine TIMER interrupt
    li   t3, 8
    beq  t5, t3, pv1_h_tom          # ECALL from U = "give me M-mode back"
    li   t3, 2                      # every poison must be illegal-instruction
    bne  t5, t3, pv1_h_bad
    bne  t6, s0, pv1_h_pc           # ... taken at the poison's OWN pc
    addi s3, s3, 1
    addi t6, t6, 4                  # skip the 4-byte poison
    csrw 0x341, t6
    mret                            # back to U (MPP was pushed 00)

pv1_h_tom:
    jr   s9

pv1_h_bad:
    li   t4, 96                     # unexpected mcause
    j    pv1_fail
pv1_h_pc:
    li   t4, 97                     # right cause, wrong mepc
    j    pv1_fail

pv1_h_timer:
    li   t3, -1                     # disarm at the source FIRST
    sw   t3, 4(s6)
    li   t3, 4096
pv1_h_tw:
    csrr t0, 0x344
    andi t0, t0, 0x80
    beqz t0, pv1_h_tq
    addi t3, t3, -1
    bnez t3, pv1_h_tw
    li   t4, 95                     # mtip never fell inside the handler
    j    pv1_fail
pv1_h_tq:
    bnez s10, pv1_h_tok             # s10 = 1: a benign leftover timer
    li   t4, 90                     # s10 = 0: THE ESCAPE.  The iret went to
    j    pv1_fail                   #   SLEEPING, so a U-mode extinguish/ignite
                                    #   that TRAPPED still moved sleep_cpu.
pv1_h_tok:
    mret

    .option pop

#else
    # OFF / trapCsr-only build: U-mode does not exist, so none of the above may
    # be assembled.  Reaching here means the ON/OFF staging discipline was
    # violated.
    li   t4, 0
    j    pv1_fail
#endif

pv1_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF (t4 = failing check id)

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
