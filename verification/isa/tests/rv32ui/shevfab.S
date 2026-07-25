# See LICENSE for license details.

#*****************************************************************************
# shevfab.S  (digperiphs EVFAB Stage 5 -- THE FLAGSHIP EVENT-FABRIC SMOKE)
#-----------------------------------------------------------------------------
# The whole point of EVFAB0 in one test: a peripheral chain that runs to
# completion WITH THE CPU ASLEEP.
#
#     TIMER0 compare0  --EV4-->  EVFAB0 CH0  --T0-->  DMA0 CH0 GO
#         --> DMA0 masters one word 0x104E0 -> UART0 TX through the arbiter
#         --> DMA0 CH0 DONE --(vector 118)--> irq_router --> meip
#         --> MEIP_DISPATCHER --> IVT slot 118 --> plain-ret handler
#         --> WAKE=1 + ignite --> hart 0 resumes.
#
# Between "TIMER0 enable" and "hart 0 wakes" the CPU executes NOTHING: it sits
# in `extinguish` (clk_cpu gated OFF). No polling of the DMA, no polling of the
# fabric -- the ONLY thing that can restart the core is the DMA-done interrupt
# at the end of the chain. Every link is therefore load-bearing: kill the
# channel enable, the EVSEL, the task, the DMA arm or the route and hart 0
# never comes back (or a bounded pre-sleep readback trips first).
#
# Hart 0 only; harts 1-3 stay parked in the bootrom (no MP_STAGE / MP_LAUNCH,
# like shdma.S / wdma.S -- the tb reports "tile hart(s) silent/parked",
# expected). Gated by the `eventFabric` + `dma` tags in verify_stage.py, so it
# joins ONLY configurations that instantiate BOTH blocks
# (config/castalia_evfab.json today); TIMER0 and UART0 are unconditional.
#
# ---- EVFAB0 register file (event_fabric_spec.md sec.4; base 0x6B00, slot n
# ---- @ +4n; EVFAB.vhd SLOT_* constants) ------------------------------------
#   0 EVFCR      rw  EN[0] global kill (reset 0)
#   1 EVFSR      ro  FIREDIF[0] = OR(FIRED), OVRIF[1] = OR(OVR)
#   2 EVFIE      reserved, reads 0 (vectorless v1, D20)
#   3 EVFCAP     ro  N_CH[7:0] N_EV[15:8] N_TASK[23:16] VER[31:24]
#                    = 8 / 16 / 10 / 1 -> 0x010A1008
#   4 EVFCHEN    rw  channel enables (reset 0)   5 CHENSET w1s   6 CHENCLR w1c
#   8 EVFFIRED   W1C sticky "channel n fired"    9 EVFOVR   W1C sticky overrun
#  10 EVFEVSTAT  W1C sticky RAW-event record, UNGATED by EN/CHEN
#  16+n EVFCHnCFG rw EVSEL[4:0] TASKSEL[11:8] ENR[31] (RO mirror of CHEN(n))
# EVSEL 4 = TIMER0 compare0 (T-mode toggle export, timer_clock domain -- the
# fabric owns the 2-FF + XOR CDC). TASKSEL 0 = DMA0 CH0 GO (one-mclk pulse
# consumed at the SAME arm site as the register GO, DMAEN re-applied at the
# tap). EVSEL/TASKSEL are written only while CHEN(0)=0 (spec sec.4).
# The fabric rides FREE-RUNNING mclk in the always-on domain -- that is why the
# chain keeps firing with the core's clock gated off.
#
# ---- DMA0 (dma_spec.md / DMA.vhd; base 0x6800) -----------------------------
#   CR 0x6800 : DMAEN[0] CHnGO[4:1] DONEIE[12] ERRIE[13]
#   SR 0x6804 : BUSY[0] CHnDONE[4:1] CHnERR[8:5]   (DONE/ERR W1C)
#   C0SRC +08  C0DST +0C  C0LEN +10  C0CFG +14 (SINC[0] DINC[1] TRIG[5:2])
# CH0 is armed with DMAEN|DONEIE and CH0GO left CLEAR: the ONLY launch is the
# fabric task pulse. CFG = 0 -> mem2mem, no SINC (re-read the same word), no
# DINC (fixed peripheral destination), no CRC. LEN = 1 word, deliberately: a
# single-word burst has no UART TX pacing hazard (the DMA would happily
# overrun a 320-mclk frame with a longer LEN -- pacing is a v2 TRIG feature).
#
# ---- vector 118 route (irq_router row layout, M19) -------------------------
# Source 118 -> enable word 118/32 = 3 (ENX) bit 118 mod 32 = 22. Hart-0 row:
# H0ENX @ 0x7000 + 0xC = 0x700C, value 1<<22 = 0x00400000 (wdma/shdma
# precedent). IVT slot 118 @ .ivt + 4*118 = 0x1D8.
#
# ---- SMCLK gotcha ----------------------------------------------------------
# UART0's serial core is smclk-domain and the ROM bootrom parks SMCLK on LFXT
# (32.768 kHz -> ~10 ms/frame). SYS_CLK_CR = 0 (SMCLK <- HFXT) is the FIRST
# thing this test does (shuart.S / periph UART.S precedent). It also releases
# TIMER0's ClockMuxGlitchFree, which defaults to the smclk slice and needs 3
# smclk edges to hand over -- hence the poll-until-counting after TIMER0 enable
# (shtimer.S rule: never sample VAL back-to-back right after enable).
#
# ---- LEDGER (CLAUDE.md shared-window rule; free at N=4 AND N=18) -----------
#     SRC   = 0x104E0   the word the DMA moves (payload byte in bits 7:0)
#     WAKE  = 0x104E4   set to 1 by the vector-118 handler; the ONLY wake proof
# Below: shafe's band tops at TURN = 0x10484 + 4*NHARTS + 4 (N=4: 0x10498;
# N=18: 0x104D0) -- both < 0x104E0. Above: the bootrom loader rows start at
# 0x10500. Both words are < 0x10500 and inside the bootrom zero range
# (< 0x10800), so the write-before-read contract holds (the test writes both
# before reading either anyway).
#
# ---- Budgets ---------------------------------------------------------------
# Every poll is bounded at 20000 iterations (~275 ms at 65536, so 20000 trips
# well inside the 100 ms tb watchdog -- shirq/shperiph/shdma precedent). The
# compare fires at 0x300 = 768 mclk ticks (32 us at 24 MHz) after TIMER0 is
# enabled, so the whole chain completes microseconds into the sleep.
#
# NOTE: RVTEST_CODE_END is `unimp` (traps) in this env -- every path ends in a
# spin; the test never falls through.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

# ---- EVFAB0 ---------------------------------------------------------------
#define EVF_BASE      0x6B00
#define O_EVFCR       0x00
#define O_EVFSR       0x04
#define O_EVFIE       0x08
#define O_EVFCAP      0x0C
#define O_EVFCHEN     0x10
#define O_EVFCHENSET  0x14
#define O_EVFFIRED    0x20
#define O_EVFOVR      0x24
#define O_EVFEVSTAT   0x28
#define O_EVFCH0CFG   0x40                  /* slot 16 */

#define EVF_CAP_EXP   0x010A1008            /* VER 1 | N_TASK 10 | N_EV 16 | N_CH 8 */
#define EVF_EN        0x00000001
#define CH0_BIT       0x00000001
#define EV_TIM0_CMP0  4                     /* EVSEL 4 */
#define TASK_DMA0_GO  0                     /* TASKSEL 0 */
#define CH0CFG_VAL    ((TASK_DMA0_GO << 8) | EV_TIM0_CMP0)   /* 0x00000004 */
#define CH0CFG_ENR    0x80000004            /* same + ENR mirror once enabled */
#define EVSTAT_EV4    (1 << EV_TIM0_CMP0)   /* 0x10 */
#define EVFSR_FIREDIF 0x1
#define EVFSR_OVRIF   0x2

# ---- DMA0 -----------------------------------------------------------------
#define DMA_BASE      0x6800
#define O_CR          0x00
#define O_SR          0x04
#define O_C0SRC       0x08
#define O_C0DST       0x0C
#define O_C0LEN       0x10
#define O_C0CFG       0x14
#define DMAEN         (1 << 0)
#define DONEIE        (1 << 12)
#define ARM_NO_GO     (DMAEN | DONEIE)      /* 0x1001 -- CH0GO stays CLEAR */
#define CH0DONE       (1 << 1)
#define CHERR_ALL     0x000001E0            /* CHnERR = SR bits 8:5 */

# ---- UART0 (shared console UART) ------------------------------------------
#define UART0_BASE    0x4400
#define O_UCR         0x00
#define O_USR         0x04
#define O_UBR         0x08
#define O_UTX         0x10
#define UART0_TX_ADDR 0x4410                /* the DMA destination */
#define UART_BR_VAL   1                     /* baud = smclk/32 -> 320 mclk/frame */
#define UART_CR_EN    0x20
#define UTCIF         0x1                   /* SR bit0: transmission complete */

# ---- TIMER0 ---------------------------------------------------------------
#define TIMER0_BASE   0x4600
#define O_TCR         0x00
#define O_TSR         0x04
#define O_TVAL        0x08
#define O_TCMP0       0x0C
#define TIM_CMP0_VAL  0x300                 /* 768 mclk ticks ~= 32 us */
#define TIM_CR_EN_MCLK 0x140                /* enable[6] + clock source 01 = mclk */

# ---- irq_router -----------------------------------------------------------
#define IRTR_H0ENX    0x700C
#define SRC118_BIT    0x00400000            /* bit 22 = source 118 (DMA0_DONE) */

# ---- shared-word ledger ---------------------------------------------------
#define SRC_WORD      0x104E0
#define WAKE          0x104E4
#define PAYLOAD       0x0000005A            /* 'Z' -- the byte the DMA transmits */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0                  # valid stack before any IRQ (IRQ_SV pushes PC)
    li   s0, DMA_BASE
    li   s1, EVF_BASE
    li   s2, UART0_BASE
    li   s3, TIMER0_BASE
    li   s4, SRC_WORD
    li   s5, WAKE

    # ---- SMCLK <- HFXT (UART0 core clock; also releases the TIMER mux) -----
    li   t0, 0x4900                  # SYSTEM0: SYS_CLK_CR at +0
    sw   zero, 0(t0)

    # ================= L0: EVFAB0 reset proofs through the arbiter =========
    lw   t0, O_EVFCR(s1)
    bnez t0, shevfab_fail            # CR resets 0 (global kill asserted, D21)
    lw   t0, O_EVFIE(s1)
    bnez t0, shevfab_fail            # IE reserved, reads 0 (vectorless v1)
    lw   t0, O_EVFCHEN(s1)
    bnez t0, shevfab_fail            # CHEN resets 0
    lw   t0, O_EVFFIRED(s1)
    bnez t0, shevfab_fail
    lw   t0, O_EVFOVR(s1)
    bnez t0, shevfab_fail
    lw   t0, O_EVFEVSTAT(s1)
    andi t0, t0, EVSTAT_EV4
    bnez t0, shevfab_fail            # no TIMER0 compare recorded yet
    lw   t0, O_EVFCAP(s1)
    li   t1, EVF_CAP_EXP
    bne  t0, t1, shevfab_fail        # CAP = the LIVE line counts

    # ================= L1: payload + wake flag ============================
    li   t0, PAYLOAD
    sw   t0, 0(s4)
    sw   x0, 0(s5)                   # WAKE = 0 (write-before-read)

    # ================= L2: UART0 TX config ================================
    li   t0, UART_BR_VAL
    sw   t0, O_UBR(s2)
    lw   t1, O_UBR(s2)
    bne  t1, t0, shevfab_fail
    li   t0, UART_CR_EN
    sw   t0, O_UCR(s2)               # enable, no IRQ enables
    lw   t1, O_UCR(s2)
    bne  t1, t0, shevfab_fail
    lw   t1, O_USR(s2)
    andi t1, t1, UTCIF
    bnez t1, shevfab_fail            # nothing transmitted yet

    # ================= L3: DMA0 CH0 armed but NOT launched ================
    sw   s4, O_C0SRC(s0)             # SRC = the shared payload word
    li   t0, UART0_TX_ADDR
    sw   t0, O_C0DST(s0)             # DST = UART0 TX (fixed, DINC=0)
    li   t0, 1
    sw   t0, O_C0LEN(s0)             # LEN = 1 word (no TX pacing hazard)
    sw   x0, O_C0CFG(s0)             # mem2mem, no SINC/DINC/CRC
    li   t0, ARM_NO_GO
    sw   t0, O_CR(s0)                # DMAEN | DONEIE -- CH0GO CLEAR
    lw   t1, O_SR(s0)
    bnez t1, shevfab_fail            # nothing busy, nothing flagged

    # ================= L4: route DMA0_DONE (118) to hart 0 ================
    li   t0, IRTR_H0ENX
    li   t1, SRC118_BIT
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, shevfab_fail        # H0ENX bit22 readback

    # ================= L5: EVFAB0 CH0 = EV4 -> T0 =========================
    li   t0, CH0CFG_VAL
    sw   t0, O_EVFCH0CFG(s1)         # written while CHEN(0)=0 (spec sec.4)
    lw   t1, O_EVFCH0CFG(s1)
    bne  t1, t0, shevfab_fail        # ENR (bit31) still 0 -- channel disabled
    li   t0, CH0_BIT
    sw   t0, O_EVFCHENSET(s1)        # w1s (no RMW race with other harts)
    lw   t1, O_EVFCHEN(s1)
    li   t2, CH0_BIT
    bne  t1, t2, shevfab_fail        # CHEN(0) latched
    lw   t1, O_EVFCH0CFG(s1)
    li   t2, CH0CFG_ENR
    bne  t1, t2, shevfab_fail        # ENR now mirrors CHEN(0)
    li   t0, EVF_EN
    sw   t0, O_EVFCR(s1)             # release the global kill
    lw   t1, O_EVFCR(s1)
    bne  t1, t0, shevfab_fail

    # ================= L6: start TIMER0, then GO TO SLEEP =================
    li   t0, TIM_CMP0_VAL
    sw   t0, O_TCMP0(s3)             # compare0 = 768 ticks out
    lw   t1, O_TCMP0(s3)
    bne  t1, t0, shevfab_fail
    li   t0, TIM_CR_EN_MCLK
    sw   t0, O_TCR(s3)               # enable, source = mclk, div = 1
    lw   t2, O_TVAL(s3)              # first VAL sample (glitch-free mux may
    li   t6, 20000                   # still be handing over -- never compare
tim_count_wait:                      # two back-to-back samples, shtimer rule)
    lw   t3, O_TVAL(s3)
    bne  t3, t2, tim_counting        # it is really counting
    addi t6, t6, -1
    bnez t6, tim_count_wait
    j    shevfab_fail
tim_counting:

    # ---- From here the CPU does NOTHING. The compare is still hundreds of
    # ---- ticks away (this poll exits within a few tens of mclk), so
    # ---- `extinguish` always wins the race to sleep -- same guarantee as
    # ---- shdma.S's L2 and shirq.S's sleep-before-IRQ note. The wake can only
    # ---- come from the far end of the chain.
wfi_loop:
    extinguish                       # clk_cpu OFF -- fabric/DMA/UART run on
    lw   t0, 0(s5)                   # free-running mclk without us
    li   t1, 1
    bne  t0, t1, wfi_loop            # any other meip -> back to sleep

    # ================= P1: the fabric fired, exactly channel 0 ============
    lw   t0, O_EVFSR(s1)
    andi t1, t0, EVFSR_FIREDIF
    beqz t1, shevfab_fail            # SR reduction agrees with FIRED
    andi t1, t0, EVFSR_OVRIF
    bnez t1, shevfab_fail            # no overrun (DMA was idle at firing)
    lw   t0, O_EVFFIRED(s1)
    li   t1, CH0_BIT
    bne  t0, t1, shevfab_fail        # ONLY channel 0
    lw   t0, O_EVFOVR(s1)
    bnez t0, shevfab_fail
    li   t0, CH0_BIT
    sw   t0, O_EVFFIRED(s1)          # W1C (action path: ~3 clk, D5)
    li   t6, 20000
1:  lw   t1, O_EVFFIRED(s1)
    beqz t1, 2f
    addi t6, t6, -1
    bnez t6, 1b
    j    shevfab_fail
2:  lw   t0, O_EVFSR(s1)
    andi t0, t0, EVFSR_FIREDIF
    bnez t0, shevfab_fail            # FIREDIF follows FIRED down

    # ================= P2: EVSTAT recorded the RAW event ==================
    lw   t0, O_EVFEVSTAT(s1)
    andi t1, t0, EVSTAT_EV4
    beqz t1, shevfab_fail            # bit 4 = TIMER0 compare0
    li   t0, EVSTAT_EV4
    sw   t0, O_EVFEVSTAT(s1)         # W1C bit 4 only
    li   t6, 20000
3:  lw   t1, O_EVFEVSTAT(s1)
    andi t1, t1, EVSTAT_EV4
    beqz t1, 4f
    addi t6, t6, -1
    bnez t6, 3b
    j    shevfab_fail
4:

    # ================= P3: UART0 really transmitted the byte ==============
    # The DMA pushed it through the arbiter while the core was gated off; the
    # smclk frame (320 mclk) may still be in flight when we wake.
    li   t6, 20000
5:  lw   t1, O_USR(s2)
    andi t1, t1, UTCIF
    bnez t1, 6f
    addi t6, t6, -1
    bnez t6, 5b
    j    shevfab_fail
6:  li   t1, UTCIF
    sw   t1, O_USR(s2)               # SR write-1 -> clr_UTCIF pulse
    li   t6, 20000
7:  lw   t1, O_USR(s2)
    andi t1, t1, UTCIF
    beqz t1, 8f
    addi t6, t6, -1
    bnez t6, 7b
    j    shevfab_fail
8:

    # ================= P4: DMA0 clean ====================================
    lw   t1, O_SR(s0)
    andi t2, t1, CH0DONE
    bnez t2, shevfab_fail            # the handler W1C'd it
    li   t2, CHERR_ALL
    and  t2, t1, t2
    bnez t2, shevfab_fail            # no channel errored anywhere
    li   t0, IRTR_H0ENX
    sw   x0, 0(t0)                   # un-route (clean)

    RVTEST_PASS                      # a0 = 0xCAFEBABE, spin

shevfab_fail:
    RVTEST_FAIL                      # a0 = 0xDEADBEEF, spin

    # ---- DMA0_DONE handler (vector 118; M19 plain-ret meip ABI). Reached via
    # ---- CLAIM=118 -> dispatcher jalr through IVT slot 118. Clears the LEVEL
    # ---- (W1C CH0DONE) BEFORE returning (the dispatcher COMPLETEs after),
    # ---- raises WAKE, and IGNITES -- hart 0 is asleep, so without it the
    # ---- dispatcher's iret would drop straight back into sleep. t0-t2 are
    # ---- dispatcher-saved scratch; ra survives (ret). s0-s5 untouched. -----
    .section .text.init
dma0_done_isr:
    li   t0, DMA_BASE
    li   t1, CH0DONE
    sw   t1, O_SR(t0)                # W1C CH0DONE -> irq_done level drops
    li   t0, WAKE
    li   t1, 1
    sw   t1, 0(t0)                   # WAKE = 1 (the mainline's only wake proof)
    ignite                           # clear sleep_cpu: iret resumes MAINLINE
    ret

    # ---- env meip dispatcher (.isr_meip @0xB100) + IVT slot 85 ------------
    MEIP_DISPATCHER()
    IVT_ARM_MEIP()

    # ---- extend the IVT to slot 118 = DMA0_DONE (DEFINE_IVT stops at 82,
    # ---- IVT_ARM_MEIP fills 83-85). Slot 118 @ .ivt + 4*118 = 0x1D8. ------
    .section .ivt, "ax"
    .org 4*118
    jal  zero, dma0_done_isr         # slot 118 = IRQB_DMA0_DONE
    .previous

    RVTEST_CODE_END                  # unimp (traps) -- never reached

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
