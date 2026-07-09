# See LICENSE for license details.

#*****************************************************************************
# afsel.S  (GPIO multi-AF: PxAFS alternate-function select)
#-----------------------------------------------------------------------------
# System-level proof of the multi-alternate-function GPIO fabric: every pin
# is GPIO + up to 8 alternate functions (AF0..AF7). PxSEL still picks GPIO vs
# alternate mode; the NEW PxAFS register (slot 11, one nibble per pin, low 3
# bits used) picks WHICH alternate function drives the pad. PxAFS resets to 0
# = AF0 = the legacy function, so all pre-multi-AF software is unaffected.
#
# Hart 0 only (tiles stay parked in the ROM). Phases:
#   gp=2..5   PxAFS register semantics: full write/readback, reserved nibble
#             bit 3 reads 0, byte-lane (sb) write masking
#   gp=6      TIMER0 PWM setup (CMP0 toggle @0x20, CMP2RST period 0x60, MCLK)
#             + bounded poll-until-counting (clock-mux handoff)
#   gp=7      NEGATIVE CONTROL: P2.0 (RTL) in alt mode at AF0 drives the GPIO
#             OUT register value (0) — the timer waveform must NOT leak in
#   gp=8,9    P2AFS field0=1 -> AF1=T0CMP0: P2IN(0) must reach 1, then 0
#             (the PWM is really on the pad — plane-1 OUTPUT mux + wiring)
#   gp=10     NEGATIVE CONTROL: edges on P4.0 (RTL) with P4AFS=0 must not
#             capture (T0CAP0 still observes its driven-low home pad P3.2)
#   gp=11     P4AFS field0=1 -> T0CAP0 observes P4.0: a software rising edge
#             on the pad sets CAP0IF (relocated INPUT mux; input routing is
#             keyed on PxAFS alone, so the pin can stay in GPIO output mode —
#             the software-loopback self-test pattern from the TRM)
#
# Port bases are RTL numbering: GPIO1=P2 @0x4100, GPIO2=P3 @0x4800,
# GPIO3=P4 @0x4D00. All accesses go through the shared window / arbiter.
# Bounded polls only (4096 max — inside the 100ms tb watchdog).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define GPIO1_BASE   0x4100
#define GPIO2_BASE   0x4800
#define GPIO3_BASE   0x4D00
#define TIMER0_BASE  0x4600
#define SYSTEM0_BASE 0x4900

#define GPIO_IN   0
#define GPIO_OUT  4
#define GPIO_DIR  20
#define GPIO_SEL  36
#define GPIO_AFS  44

#define TIM_CR    0
#define TIM_SR    4
#define TIM_VAL   8
#define TIM_CMP0  12
#define TIM_CMP2  20

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, park              # single-hart test: tiles must never get here

    li   sp, 0xBFF0             # private TCM top; IRQ_SV pushes PC at sp-4

    # SMCLK -> HFXT right away (bootrom parks it on LFXT; the TIMER clock
    # mux needs 3 smclk edges to release its default smclk slice)
    li   s0, SYSTEM0_BASE
    sw   zero, 0(s0)            # SYS_CLK_CR = 0

    li   s1, GPIO1_BASE         # RTL P2
    li   s2, GPIO2_BASE         # RTL P3
    li   s3, GPIO3_BASE         # RTL P4
    li   s4, TIMER0_BASE

    #------------------------------------------------------------------
    # PxAFS register semantics
    #------------------------------------------------------------------
    li   gp, 2                  # full-width write/readback (all fields <= 7)
    li   t0, 0x76543210
    sw   t0, GPIO_AFS(s1)
    lw   t1, GPIO_AFS(s1)
    bne  t1, t0, fail

    li   gp, 3                  # nibble bit 3 is reserved: reads back 0
    li   t0, 0x88888888
    sw   t0, GPIO_AFS(s1)
    lw   t1, GPIO_AFS(s1)
    bnez t1, fail

    li   gp, 4
    li   t0, 0xFFFFFFFF
    sw   t0, GPIO_AFS(s3)
    lw   t1, GPIO_AFS(s3)
    li   t2, 0x77777777
    bne  t1, t2, fail

    li   gp, 5                  # byte-lane masking: sb writes ONE lane
    sb   zero, (GPIO_AFS + 2)(s3)
    lw   t1, GPIO_AFS(s3)
    li   t2, 0x77007777
    bne  t1, t2, fail

    sw   zero, GPIO_AFS(s1)     # restore reset state
    sw   zero, GPIO_AFS(s3)

    #------------------------------------------------------------------
    # T0CMP0 PWM relocated to P2.0 (RTL) via AF1  [output plane mux]
    #------------------------------------------------------------------
    li   gp, 6                  # timer: toggle @CMP0=0x20, period CMP2=0x60
    sw   zero, TIM_CR(s4)
    li   t0, 0x20
    sw   t0, TIM_CMP0(s4)
    li   t0, 0x60
    sw   t0, TIM_CMP2(s4)
    li   t0, 0x1C0              # TEN | CMP2RST | SSEL_MCLK, DIV 1
    sw   t0, TIM_CR(s4)

    li   t3, 4096               # bounded poll until VAL is really counting
1:  lw   t0, TIM_VAL(s4)
    lw   t1, TIM_VAL(s4)
    bne  t0, t1, 2f
    addi t3, t3, -1
    bnez t3, 1b
    j    fail
2:

    li   gp, 7                  # NEGATIVE CONTROL: alt mode at AF0 (the CS1
    li   t0, 1                  # plane maps the GPIO OUT/DIR regs) driving 0
    sw   t0, GPIO_DIR(s1)       # P2.0 output...
    sw   zero, GPIO_OUT(s1)     # ...low
    lw   t5, GPIO_SEL(s1)       # RMW: keep the UART0 SEL bits (P2.4/5)
    ori  t5, t5, 1
    sw   t5, GPIO_SEL(s1)       # P2.0 alt mode, P2AFS field0 = 0 (AF0)
    li   t3, 512                # ~36 PWM periods of samples
1:  lw   t0, GPIO_IN(s1)
    andi t0, t0, 1
    bnez t0, fail               # timer waveform leaked into plane 0
    addi t3, t3, -1
    bnez t3, 1b

    li   gp, 8                  # engage AF1: the pad now carries the PWM
    li   t0, 1                  # P2AFS field0 = 1
    sw   t0, GPIO_AFS(s1)
    li   t3, 4096
1:  lw   t0, GPIO_IN(s1)        # must reach 1...
    andi t0, t0, 1
    bnez t0, 2f
    addi t3, t3, -1
    bnez t3, 1b
    j    fail
2:
    li   gp, 9
    li   t3, 4096
1:  lw   t0, GPIO_IN(s1)        # ...and fall back to 0 (really toggling)
    andi t0, t0, 1
    beqz t0, 2f
    addi t3, t3, -1
    bnez t3, 1b
    j    fail
2:
    sw   zero, GPIO_AFS(s1)     # restore
    lw   t5, GPIO_SEL(s1)
    andi t5, t5, -2
    sw   t5, GPIO_SEL(s1)

    #------------------------------------------------------------------
    # T0CAP0 capture input relocated to P4.0 (RTL)  [relocated input mux]
    #------------------------------------------------------------------
    li   gp, 10
    li   t0, 4                  # home pad P3.2: GPIO output-low so the
    sw   t0, GPIO_DIR(s2)       # un-relocated capture input is a driven 0
    sw   zero, GPIO_OUT(s2)     # (never a floating X)
    sw   zero, GPIO_SEL(s2)

    li   t0, 1                  # alternate pad P4.0: GPIO output-low (input
    sw   t0, GPIO_DIR(s3)       # routing keys on PxAFS alone, SEL stays 0 —
    sw   zero, GPIO_OUT(s3)     # the software-loopback pattern)
    sw   zero, GPIO_SEL(s3)

    lw   t0, TIM_CR(s4)         # + CAP0EN, rising edge (CAP0FE=0)
    li   t1, 0x400
    or   t0, t0, t1
    sw   t0, TIM_CR(s4)
    li   t0, 0x3F
    sw   t0, TIM_SR(s4)         # W1C any stale flags

    li   t2, 1                  # NEGATIVE CONTROL: edges on P4.0 with
    sw   t2, GPIO_OUT(s3)       # P4AFS=0 must not capture (T0CAP0 is still
    sw   zero, GPIO_OUT(s3)     # watching its quiet home pad P3.2)
    sw   t2, GPIO_OUT(s3)
    sw   zero, GPIO_OUT(s3)
    lw   t0, TIM_SR(s4)
    andi t0, t0, 0x10           # CAP0IF
    bnez t0, fail

    li   gp, 11                 # engage the relocation
    li   t0, 1                  # P4AFS field0 = 1 -> T0CAP0 observes P4.0
    sw   t0, GPIO_AFS(s3)
    sw   t2, GPIO_OUT(s3)       # rising edge on the pad
    li   t3, 4096
1:  lw   t0, TIM_SR(s4)
    andi t0, t0, 0x10
    bnez t0, 2f
    addi t3, t3, -1
    bnez t3, 1b
    j    fail
2:
    sw   zero, GPIO_AFS(s3)     # tidy up
    sw   zero, GPIO_OUT(s3)
    sw   zero, TIM_CR(s4)

    RVTEST_PASS

park:
    j    park

fail:
    RVTEST_FAIL

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every path above ends in a spin.
RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
