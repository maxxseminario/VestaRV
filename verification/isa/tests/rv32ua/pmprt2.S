# See LICENSE for license details.

#*****************************************************************************
# pmprt2.S   (P3 RED TEAM — `iret` carries a PHANTOM PMP DATA CHECK at
#             ALU_Result = 0x00000000)
#-----------------------------------------------------------------------------
# ON-ONLY DIRECTED TEST (needs a trapCsr+umode+pmp build).
#
# THE HYPOTHESIS (kickoff red-team item 3, confirmed by RTL reading).
#   maindec.vhd:1073-1082
#       read_data_flag <= '1' when op = I_LOAD_OPCODE else
#                         '1' when (op = CUSTOM_OPCODE and funct3 = "000"
#                                   and funct7 = "0000000") else ...
#       mem_access_instr <= read_data_flag or write_data_flag;
#   i.e. `iret` (CUSTOM_OPCODE f3=000 f7=0000000) is a MEMORY READ to the
#   decoder.  vesta's EXECUTE dispatch therefore takes the generic memory arm
#   (vesta.vhd:2201-2205, ABOVE the `isr_ret` arm at 2247) and issues a real
#   bus read at `ALU_Result`.  For the canonical encoding
#   (`.insn r 0x0b,0,0,x0,x0,x0`, riscv_test.h:21-23) alu_control is ADD and
#   ALU_src is '0' (maindec.vhd:1101 / 1008), so ALU_Result = x0 + x0 = 0 —
#   the read lands on address 0x00000000, THE SHARED BOOT ROM.
#
#   P3 then hangs its data-side check on exactly that decode
#   (vesta.vhd:1789-1793: `mem_access_controller='1' and wen_controller="1111"`
#   => pmp_d_rd), so a PMP map that denies address 0 makes a LEGAL M-mode
#   `iret` take a spurious LOAD ACCESS FAULT (cause 5, mtval 0).
#
# CLASSIFICATION IF IT BITES: DoS on M-mode (a legal, privileged instruction
# is denied), NOT an escape.  It also mis-attributes: mtval reports 0, an
# address the instruction never names.
#
# TWO INDEPENDENT ARMS, both non-fatal so BOTH are always observed:
#   ARM A  MPRV=1 / MPP=U with an unlocked NA4 fence on address 0.  The
#          effective DATA privilege is U, the fetch stays M.
#   ARM B  a LOCKED NA4 fence on address 0, executed in plain M with MPRV=0
#          (locked entries enforce on M — p0_specs.md §4).  This is the pure
#          M-mode denial-of-service, with no MPRV involved at all.
# ARM B is LAST because a lock releases only at reset.
#
# The verdict is a composite: t4 = 100 + s0 where s0 bit0 = ARM A faulted,
# bit1 = ARM B faulted.  t4 = 100 (s0 = 0) is the spec-correct outcome and
# the test PASSes; 101 / 102 / 103 name which arm(s) bit.
#
# POSITIVE CONTROL (CHECK 6): the same `iret` with an EMPTY map must retire
# through IRQ_REST and resume at mem[sp].  Without it a "no fault" result
# would be indistinguishable from a broken vehicle.
#
# BOUNDEDNESS: no loop anywhere.  Every `iret` either resumes at the word
# planted at mem[sp] or lands in the handler, which resumes at s7.
#
# REGISTER CONTRACT:
#   s0 verdict accumulator   s3 trap counter   s4/s5/s6 cause/mepc/mtval
#   s7 handler resume PC     s11 trap count snapshot        t4 CHECK ID
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

#define RT2_TORTOP   0x00020000
#define RT2_STK      0x0000BF00

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, rt2_fail

#if defined(CORE_ENABLE_TRAPCSR) && defined(CORE_ENABLE_UMODE) && defined(CORE_ENABLE_PMP)

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0
    li   s0, 0

    li   t4, 1
    la   t0, rt2_handler
    csrw 0x305, t0
    csrr t1, 0x305
    bne  t1, t0, rt2_fail

    li   t4, 2
    csrw 0x7C0, x0
    csrr t1, 0x7C0
    bne  t1, x0, rt2_fail

    csrw 0x300, x0
    csrw 0x304, x0                  # mie off: nothing may be delivered

    # =====================================================================
    # CHECK 6 — POSITIVE CONTROL.  Empty PMP map, plain M, MPRV=0.  The
    # `iret` must retire (EXECUTE -> MEMORY_WAIT -> IRQ_REST) and load the
    # PC from mem[sp].
    # =====================================================================
    li   t4, 6
    li   sp, RT2_STK
    la   t0, rt2_ctl_ok
    sw   t0, 0(sp)
    mv   s11, s3
    la   s7, rt2_ctl_bad
    iret
    j    rt2_fail                   # iret must NOT fall through

rt2_ctl_bad:                        # the control faulted: the vehicle is broken
    li   t4, 7
    j    rt2_fail

rt2_ctl_ok:
    li   sp, 0xBFF0
    li   t4, 8
    bne  s3, s11, rt2_fail          # the control leg must trap ZERO times

    # =====================================================================
    # CHECK 9/10 — THE MAP.  entry0 fences address 0 (NA4, no permissions);
    # entry1 is OFF and carries entry2's TOR base; entry2 grants everything
    # everything else in 0x0..0x1FFFF, so the stack pop and all ordinary work survive.
    # =====================================================================
    li   t4, 9
    csrw 0x3B0, x0                  # pmpaddr0 = 0        (NA4 at address 0)
    csrw 0x3B1, x0                  # pmpaddr1 = 0        (entry2's TOR base)
    li   t0, RT2_TORTOP
    srli t0, t0, 2
    csrw 0x3B2, t0
    li   t4, 10
    li   t0, 0x000F0010             # cfg2=R|W|X|TOR cfg1=OFF cfg0=NA4 no-perms
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt2_fail

    # ---- CHECK 11 : the fence is real (a U-view LOAD from 0 must fault) --
    # POSITIVE CONTROL for the map itself.
    li   t4, 11
    mv   s11, s3
    la   s7, rt2_probe_flt
    li   t1, 0x00020000             # MPRV=1, MPP=U
    csrw 0x300, t1
    lw   t2, 0(x0)                  # must be DENIED
    csrw 0x300, x0
    j    rt2_fail                   # it was granted: the map is wrong
rt2_probe_flt:
    csrw 0x300, x0
    li   t4, 12
    addi t1, s11, 1
    bne  s3, t1, rt2_fail
    li   t4, 13
    li   t1, 5
    bne  s4, t1, rt2_fail
    li   t4, 14
    bne  s6, x0, rt2_fail           # mtval = 0x00000000

    # =====================================================================
    # ARM A — `iret` under the U DATA view (MPRV=1, MPP=U).  Spec: `iret`
    # names no memory, so it must retire.  If the phantom ALU_Result read is
    # checked, it faults with cause 5 / mtval 0.
    # =====================================================================
    li   sp, RT2_STK
    la   t0, rt2_a_ok
    sw   t0, 0(sp)
    mv   s11, s3
    la   s7, rt2_a_flt
    li   t1, 0x00020000             # MPRV=1, MPP=U
    csrw 0x300, t1
    iret
    j    rt2_fail                   # must not fall through

rt2_a_flt:                          # <-- the hypothesis fired
    csrw 0x300, x0
    li   sp, 0xBFF0
    ori  s0, s0, 1
    j    rt2_armb

rt2_a_ok:
    csrw 0x300, x0
    li   sp, 0xBFF0

    # =====================================================================
    # ARM B — the pure M-mode form.  LOCK the address-0 fence (L=1) and run
    # `iret` in plain M with MPRV=0.  A locked entry enforces on M, so if the
    # phantom read is checked this is an unconditional M-mode denial of a
    # legal privileged instruction.  LAST: locks release only at reset.
    # =====================================================================
rt2_armb:
    li   t4, 20
    li   t0, 0x000F0090             # cfg2 kept, cfg0 = L | NA4, R=W=X=0
    csrw 0x3A0, t0
    csrr t1, 0x3A0
    bne  t1, t0, rt2_fail           # cfg1/cfg2 unchanged, cfg0 now locked

    li   sp, RT2_STK
    la   t0, rt2_b_ok
    sw   t0, 0(sp)
    mv   s11, s3
    la   s7, rt2_b_flt
    csrw 0x300, x0                  # MPRV=0: plain M
    iret
    j    rt2_fail

rt2_b_flt:                          # <-- the M-mode DoS
    li   sp, 0xBFF0
    ori  s0, s0, 2
    j    rt2_verdict

rt2_b_ok:
    li   sp, 0xBFF0

    # =====================================================================
    # THE VERDICT.  t4 = 100 + s0.  100 = spec-correct (no phantom check).
    # =====================================================================
rt2_verdict:
    addi t4, s0, 100
    bne  s0, x0, rt2_fail

    li   t1, 0x00000001
    csrw 0x7C0, t1                  # back to LEGACY delivery
    csrw 0x300, x0

    RVTEST_PASS

    .align 2
rt2_handler:
    csrr t0, 0x342
    addi s3, s3, 1
    mv   s4, t0
    csrr s5, 0x341
    csrr s6, 0x343
    csrw 0x341, s7
    mret

    .option pop

#else
    li   t4, 0
    j    rt2_fail
#endif

rt2_fail:
    RVTEST_FAIL

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
