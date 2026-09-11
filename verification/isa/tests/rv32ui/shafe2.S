# See LICENSE for license details.

#*****************************************************************************
# shafe2.S  -- MCU-level test of the four AFE2 analog front-end sites
#-----------------------------------------------------------------------------
# THE END-TO-END AFE2 TEST. hdl/common/tb/AFE2_tb.vhd covers the block as a
# unit; nothing had ever written or read an AFE2 register THROUGH THE MCU BUS,
# at RTL or at gate (F20 finding 4). This file does, on the tape-out
# configuration (penta_wound + peripherals.afe2), and it is the successor to
# shafe.S, which addresses the RETIRED afe_stub bank at 0x4C00.
#
# HART 0 ONLY. Every site's ownership gate admits its owner tile hart OR the
# management hart, and MGMT_HART is 0 on every configuration (mcu_vhd.py's
# emitAfe2Instance keeps the entity default), so hart 0 reaches all four sites
# without the launcher. The tiles stay parked; the tb reports them silent, which
# is the single-hart note, not a failure. The gate itself is proved per site in
# AFE2_tb (hart 2 denied, hart 1 and hart 0 allowed).
#
# MAP (generated: MemoryMap.h AFE0_BASE..AFE3_BASE, MemoryMap.vhd IRQB_AFE):
#   site h at 0x6C00 + 0x100*h; CR +0 SR +4 DATA +8 TIA +12 DACVP +16
#   DACVCM +20 BIAS +24 MUX +28 SWAP +32. Reset: CR = 0x700 (SAMPLESTEP 7),
#   MUX = 0xF0 (ATP_SEL 0xF parks the site off the shared test pads, F13), rest 0.
#   Vector 124 = IRQB_AFE, the OR of the four sites, IVT slot at 0x81F0. It is
#   routed per hart through the irq_router row word 3 (HhENX = irq_en[127:96],
#   0x7000 + 0x10*h + 0xC) because NUM_IRQ_SRCS = 125 makes NUM_EN_WORDS 4.
#
# THE CONVERTER is hdl/common/sim/sar_macro_model.vhd, instantiated per site by
# the generated riscv_tb.vhd. Site h returns code 0x155 + h, so a DATA readback
# is an exact word: DATA = VALID(15) | phase(14) | SARADC_SEL(13:10) | code(9:0).
# With SARADC_SEL = 14 the model returns the 10-bit window of the 50 ctl pins
# that ATP_SEL selects instead (5 windows cover all 50 bits), which is how phase
# 9 proves the control word written to TIA/DACVP/DACVCM/BIAS/MUX reaches the
# pins -- those bits leave the MCU for the analog macro and have no other route
# back to software.
#
# PHASES (TESTNUM carries the phase, so a FAIL names where):
#   2 reset values on all four sites
#   3 implemented-bit width per register (write all ones, read the mask back)
#   4 per-site patterns, read back exactly, and each site re-read after the next
#     is written -- no aliasing between the four 256 B sub-slots
#   5 one single conversion on site 0: DATA = 0x8155, read is side-effect free,
#     write-1 to SR.DRDY pops
#   6 simultaneous trigger: sites 0-3 armed with CR.SYNCEN, one CR.SYNC write on
#     site 0 starts all four, all four codes read back, all four popped by write-1
#   7 continuous mode until SR.OVF, FIFO holds its 4 entries, OVF cleared by
#     write-1, the four queued codes drained
#   8 vector 124 delivered to hart 0: route it in H0ENX, arm CR.DRDYIE, take the
#     interrupt through the env meip dispatcher (CLAIM -> IVT slot 124 ->
#     .isr_afe_shared), handler reads DATA and pops to drop the level
#   9 the ctl pins, through the model's echo
#
# No smclk peripheral is touched (AFE2 is on mclk), so no SYS_CLK_CR write. All
# polls are bounded 20000 and trip well inside the 100 ms tb watchdog; one
# conversion is 23 trigger ticks = 1.92 us at the 12 MHz f_sar a 24 MHz mclk
# gives at CLKDIV = 0.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define AFE0        0x6C00
#define AFE_STRIDE  0x100
#define SH_IRTR     0x7000
#define H0ENX_OFF   0x0C            /* row 0 word 3 = irq_en[127:96] */
#define AFE_ENX_BIT 0x10000000      /* source 124 -> bit 124-96 = 28 */

#define R_CR        0
#define R_SR        4
#define R_DATA      8
#define R_TIA       12
#define R_DACVP     16
#define R_DACVCM    20
#define R_BIAS      24
#define R_MUX       28
#define R_SWAP      32

#define CR_RST      0x00000700      /* SAMPLESTEP = 7 */
#define MUX_RST     0x000000F0      /* ATP_SEL = 0xF */
#define CR_EN       0x00000701
#define CR_START    0x00000705
#define CR_ENCONT   0x00000703
#define CR_CONTGO   0x00000707
#define CR_ENSYNC   0x00000711      /* EN + SYNCEN */
#define CR_SYNCGO   0x00000719      /* EN + SYNCEN + SYNC pulse */
#define CR_ENIE     0x00000721      /* EN + DRDYIE */
#define CR_IEGO     0x00000725
#define SR_REL      0x00000008
#define SR_POP      0x00000002
#define SR_CLROVF   0x00000004
#define POLL_MAX    20000

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # RVTEST_CODE_BEGIN's INIT_XREG zeroes EVERY x register, sp included, so a
    # test that takes an interrupt MUST re-establish a stack before it does:
    # the core's IRQ_SV pushes the PC at sp-4 and the meip dispatcher pushes 20
    # more bytes. With sp = 0 that lands outside the private array and the hart
    # never returns from the vector -- measured here as a 100 ms watchdog death
    # in phase 8 with source 124 stuck in_service. 0x9FF0 is the top of hart 0's
    # 8 KiB private TCM (0x8000-0x9FFF); shirq.S and shafe.S write the aliasing
    # 0xBFF0 for the same reason.
    li   sp, 0x9FF0

    # =====================================================================
    # 2. Reset values, all four sites.
    # =====================================================================
    li   TESTNUM, 2
    li   s2, 0
p2_site:
    jal  ra, site_base              # s1 = AFE0 + 0x100*s2

    lw   t0, R_CR(s1)
    li   t1, CR_RST
    bne  t0, t1, shafe2_fail
    lw   t0, R_MUX(s1)
    li   t1, MUX_RST
    bne  t0, t1, shafe2_fail
    lw   t0, R_SR(s1)
    bnez t0, shafe2_fail
    lw   t0, R_DATA(s1)
    bnez t0, shafe2_fail
    lw   t0, R_TIA(s1)
    bnez t0, shafe2_fail
    lw   t0, R_DACVP(s1)
    bnez t0, shafe2_fail
    lw   t0, R_DACVCM(s1)
    bnez t0, shafe2_fail
    lw   t0, R_BIAS(s1)
    bnez t0, shafe2_fail
    lw   t0, R_SWAP(s1)
    bnez t0, shafe2_fail
    # words 9-63 of the sub-slot hold no flop and read 0
    lw   t0, 36(s1)
    bnez t0, shafe2_fail
    lw   t0, 252(s1)
    bnez t0, shafe2_fail

    addi s2, s2, 1
    li   t0, 4
    bltu s2, t0, p2_site

    # =====================================================================
    # 3. Implemented-bit width: write all ones, read the mask back.
    #    Done per site and CR restored immediately, so the 128-mclk release
    #    counter never reaches REL and the pulse bits stay inert.
    # =====================================================================
    li   TESTNUM, 3
    li   s2, 0
p3_site:
    jal  ra, site_base
    li   t3, -1                     # 0xFFFFFFFF

    sw   t3, R_CR(s1)
    lw   t0, R_CR(s1)
    li   t1, 0x0000FFF3             # START (2) and SYNC (3) are pulses, not flops
    bne  t0, t1, shafe2_fail
    sw   x0, R_CR(s1)               # back to idle before anything can release

    sw   t3, R_TIA(s1)
    lw   t0, R_TIA(s1)
    li   t1, 0x000003FF
    bne  t0, t1, shafe2_fail

    sw   t3, R_DACVP(s1)
    lw   t0, R_DACVP(s1)
    li   t1, 0x00001FFF
    bne  t0, t1, shafe2_fail

    sw   t3, R_DACVCM(s1)
    lw   t0, R_DACVCM(s1)
    li   t1, 0x00001FFF
    bne  t0, t1, shafe2_fail

    sw   t3, R_BIAS(s1)
    lw   t0, R_BIAS(s1)
    li   t1, 0x0000003F
    bne  t0, t1, shafe2_fail

    sw   t3, R_MUX(s1)
    lw   t0, R_MUX(s1)
    li   t1, 0x000000FF
    bne  t0, t1, shafe2_fail

    sw   t3, R_SWAP(s1)
    lw   t0, R_SWAP(s1)
    li   t1, 0xFFFF0FFF
    bne  t0, t1, shafe2_fail

    # SR and DATA hold no writable flop: a write must not stick.
    sw   t3, R_DATA(s1)
    lw   t0, R_DATA(s1)
    bnez t0, shafe2_fail

    addi s2, s2, 1
    li   t0, 4
    bltu s2, t0, p3_site

    # =====================================================================
    # 4. Per-site patterns. Every site gets a value no other site has, then
    #    every site is re-read after all four were written: a decode that
    #    aliased two sub-slots would show up as the wrong site's pattern.
    # =====================================================================
    li   TESTNUM, 4
    li   s2, 0
p4_write:
    jal  ra, site_base
    jal  ra, site_pattern           # t4 = TIA, t5 = DACVP, t6 = DACVCM, s3 = BIAS|MUX|SWAP set
    sw   t4, R_TIA(s1)
    sw   t5, R_DACVP(s1)
    sw   t6, R_DACVCM(s1)
    li   t0, 0x15
    add  t0, t0, s2
    sw   t0, R_BIAS(s1)
    li   t0, 0x50
    add  t0, t0, s2
    sw   t0, R_MUX(s1)
    li   t0, 0x00070300
    add  t0, t0, s2
    sw   t0, R_SWAP(s1)
    addi s2, s2, 1
    li   t0, 4
    bltu s2, t0, p4_write

    li   s2, 0
p4_read:
    jal  ra, site_base
    jal  ra, site_pattern
    lw   t0, R_TIA(s1)
    bne  t0, t4, shafe2_fail
    lw   t0, R_DACVP(s1)
    bne  t0, t5, shafe2_fail
    lw   t0, R_DACVCM(s1)
    bne  t0, t6, shafe2_fail
    li   t1, 0x15
    add  t1, t1, s2
    lw   t0, R_BIAS(s1)
    bne  t0, t1, shafe2_fail
    li   t1, 0x50
    add  t1, t1, s2
    lw   t0, R_MUX(s1)
    bne  t0, t1, shafe2_fail
    li   t1, 0x00070300
    add  t1, t1, s2
    lw   t0, R_SWAP(s1)
    bne  t0, t1, shafe2_fail
    addi s2, s2, 1
    li   t0, 4
    bltu s2, t0, p4_read

    # Clear the patterns: the phases below assume a quiet control word.
    li   s2, 0
p4_clear:
    jal  ra, site_base
    sw   x0, R_TIA(s1)
    sw   x0, R_DACVP(s1)
    sw   x0, R_DACVCM(s1)
    sw   x0, R_BIAS(s1)
    sw   x0, R_MUX(s1)
    sw   x0, R_SWAP(s1)
    addi s2, s2, 1
    li   t0, 4
    bltu s2, t0, p4_clear

    # =====================================================================
    # 5. One conversion on site 0. MUX = 0, so the DATA tag is 0 and the word
    #    is exactly VALID | code.
    # =====================================================================
    li   TESTNUM, 5
    li   s1, AFE0
    li   t0, CR_EN
    sw   t0, R_CR(s1)               # EN: SARADC_rst releases, quiet counter starts
    jal  ra, wait_rel
    li   t0, CR_START
    sw   t0, R_CR(s1)               # START pulse
    jal  ra, wait_drdy              # SR & 3 == 2 (DRDY set, BUSY clear)

    lw   t0, R_DATA(s1)
    li   t1, 0x8155                 # VALID | sel 0 | phase 0 | 0x155
    bne  t0, t1, shafe2_fail
    lw   t0, R_DATA(s1)             # a read must not pop or otherwise mutate
    bne  t0, t1, shafe2_fail
    lw   t0, R_SR(s1)
    li   t2, 0x0F00                 # CNT (the immediate does not fit andi)
    and  t1, t0, t2
    li   t2, 0x0100
    bne  t1, t2, shafe2_fail

    li   t0, SR_POP
    sw   t0, R_SR(s1)               # write-1 to SR.DRDY = pop
    lw   t0, R_SR(s1)
    li   t2, 0x0F02                 # CNT and DRDY
    and  t1, t0, t2
    bnez t1, shafe2_fail
    lw   t0, R_DATA(s1)             # empty FIFO reads 0, VALID clear
    bnez t0, shafe2_fail
    sw   x0, R_CR(s1)

    # =====================================================================
    # 6. Simultaneous trigger. All four sites arm with CR.SYNCEN; one CR.SYNC
    #    write on site 0 pulses trig_out, MCU.vhd ORs it into every site's
    #    trig_in, and every armed site starts on the same mclk edge.
    # =====================================================================
    li   TESTNUM, 6
    li   s2, 0
p6_arm:
    jal  ra, site_base
    li   t0, CR_ENSYNC
    sw   t0, R_CR(s1)
    jal  ra, wait_rel
    addi s2, s2, 1
    li   t0, 4
    bltu s2, t0, p6_arm

    li   s1, AFE0
    li   t0, CR_SYNCGO
    sw   t0, R_CR(s1)               # broadcast

    li   s2, 0
p6_read:
    jal  ra, site_base
    jal  ra, wait_drdy
    lw   t0, R_DATA(s1)
    li   t1, 0x8155
    add  t1, t1, s2                 # site h returns 0x155 + h
    bne  t0, t1, shafe2_fail
    li   t0, SR_POP
    sw   t0, R_SR(s1)
    lw   t0, R_SR(s1)
    li   t2, 0x0F02                 # CNT and DRDY both cleared by the write-1
    and  t1, t0, t2
    bnez t1, shafe2_fail
    andi t1, t0, 0x0014             # OVF and TO never set on a clean round
    bnez t1, shafe2_fail
    sw   x0, R_CR(s1)
    addi s2, s2, 1
    li   t0, 4
    bltu s2, t0, p6_read

    # =====================================================================
    # 7. Continuous mode to FIFO overflow. Four entries fit; the fifth
    #    capture sets OVF and is dropped.
    # =====================================================================
    li   TESTNUM, 7
    li   s1, AFE0
    li   t0, CR_ENCONT
    sw   t0, R_CR(s1)
    jal  ra, wait_rel
    li   t0, CR_CONTGO
    sw   t0, R_CR(s1)

    li   t3, POLL_MAX
p7_ovf:
    lw   t0, R_SR(s1)
    andi t1, t0, 0x04
    bnez t1, p7_full
    addi t3, t3, -1
    bnez t3, p7_ovf
    j    shafe2_fail
p7_full:
    sw   x0, R_CR(s1)               # EN = 0 stops the sequencer; the FIFO keeps its entries
    lw   t0, R_SR(s1)
    li   t2, 0x0F00
    and  t1, t0, t2
    li   t2, 0x0400                 # CNT = 4, the FIFO depth
    bne  t1, t2, shafe2_fail
    li   t0, SR_CLROVF
    sw   t0, R_SR(s1)               # write-1 clears OVF
    lw   t0, R_SR(s1)
    andi t1, t0, 0x04
    bnez t1, shafe2_fail
    li   t2, 0x0F00
    and  t1, t0, t2
    li   t2, 0x0400
    bne  t1, t2, shafe2_fail        # ...and does not disturb the queue

    li   s3, 4
p7_drain:
    lw   t0, R_DATA(s1)
    li   t1, 0x8155
    bne  t0, t1, shafe2_fail
    li   t0, SR_POP
    sw   t0, R_SR(s1)
    addi s3, s3, -1
    bnez s3, p7_drain
    lw   t0, R_SR(s1)
    li   t2, 0x0F02
    and  t1, t0, t2
    bnez t1, shafe2_fail

    # =====================================================================
    # 8. Vector 124 to hart 0. Route it in hart 0's own row, arm CR.DRDYIE,
    #    and let one conversion deliver meip -> CLAIM -> IVT slot 124.
    # =====================================================================
    li   TESTNUM, 8
    li   t0, SH_IRTR
    li   t1, AFE_ENX_BIT
    sw   t1, H0ENX_OFF(t0)          # H0ENX = irq_en[127:96], bit 28 = source 124
    lw   t2, H0ENX_OFF(t0)
    bne  t2, t1, shafe2_fail

    la   t0, afe_irq_flag
    sw   x0, 0(t0)
    la   t0, afe_irq_data
    sw   x0, 0(t0)

    li   s1, AFE0
    li   t0, CR_ENIE
    sw   t0, R_CR(s1)
    jal  ra, wait_rel
    li   t0, CR_IEGO
    sw   t0, R_CR(s1)

    li   t3, POLL_MAX
p8_wait:
    la   t0, afe_irq_flag
    lw   t1, 0(t0)
    bnez t1, p8_took
    addi t3, t3, -1
    bnez t3, p8_wait
    j    shafe2_fail
p8_took:
    la   t0, afe_irq_data
    lw   t1, 0(t0)
    li   t2, 0x8155
    bne  t1, t2, shafe2_fail        # the handler saw the real conversion
    lw   t0, R_SR(s1)
    li   t2, 0x0F02
    and  t1, t0, t2
    bnez t1, shafe2_fail            # the handler popped, so the level is down
    sw   x0, R_CR(s1)
    li   t0, SH_IRTR
    sw   x0, H0ENX_OFF(t0)          # un-route before the next phase runs conversions

    # =====================================================================
    # 9. The 50 ctl pins. Program the control word, then read it back one
    #    10-bit window at a time through the model's echo: SARADC_SEL = 14
    #    makes the returned code the window ATP_SEL selects, so every ctl bit
    #    is compared against what the registers were told to hold.
    #      ctl = 0x2A95A39E3E5E0 | ATP_SEL, and the DATA word carries the
    #      SARADC_SEL tag 14, hence the 0xB8xx expectations in afe_ctl_exp.
    # =====================================================================
    li   TESTNUM, 9
    li   s1, AFE0
    li   t0, 0x26A
    sw   t0, R_TIA(s1)              # ResEn = 0x2A, ThEn = 0x9
    li   t0, 0x15A3
    sw   t0, R_DACVP(s1)            # A_Dac_Vp = 0x5A3, En_Dac_Vp = 1
    li   t0, 0x13C7
    sw   t0, R_DACVCM(s1)           # A_Dac_Vcm = 0x3C7, En_Dac_Vcm = 1
    li   t0, 0x25
    sw   t0, R_BIAS(s1)             # Bias_Adj = 0x25
    li   t0, CR_EN
    sw   t0, R_CR(s1)
    jal  ra, wait_rel

    li   s2, 0
    la   s3, afe_ctl_exp
p9_win:
    slli t0, s2, 4                  # MUX [7:4] = ATP_SEL = the window index...
    ori  t0, t0, 0x0E               # ...and MUX [3:0] = SARADC_SEL = 14, the echo code
    sw   t0, R_MUX(s1)
    li   t0, CR_START
    sw   t0, R_CR(s1)
    jal  ra, wait_drdy
    lw   t0, R_DATA(s1)
    lw   t1, 0(s3)
    bne  t0, t1, shafe2_fail
    li   t0, SR_POP
    sw   t0, R_SR(s1)
    addi s3, s3, 4
    addi s2, s2, 1
    li   t0, 5
    bltu s2, t0, p9_win

    sw   x0, R_CR(s1)
    li   t0, MUX_RST
    sw   t0, R_MUX(s1)              # leave the site parked off the test pads

    RVTEST_PASS                     # a0 = 0xCAFEBABE, spin

shafe2_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF, spin

    # ---- site_base: s1 = AFE0 + 0x100*s2, without the M extension (the tile
    # ---- ISA gate rejects mul in rv32ui images). Clobbers t0-t2. ----------
site_base:
    li   t0, AFE_STRIDE
    mv   t1, s2
    li   t2, 0
sb_loop:
    beqz t1, sb_done
    add  t2, t2, t0
    addi t1, t1, -1
    j    sb_loop
sb_done:
    li   s1, AFE0
    add  s1, s1, t2
    ret

    # ---- site_pattern: the three wide per-site values. Clobbers t4-t6. ----
site_pattern:
    li   t4, 0x2AA
    add  t4, t4, s2                 # TIA   (10 bits)
    li   t5, 0x1234
    add  t5, t5, s2                 # DACVP (13 bits)
    li   t6, 0x0ABC
    add  t6, t6, s2                 # DACVCM(13 bits)
    ret

    # ---- wait_rel: SR.REL, i.e. SARADC_rst released and the QUIET_CYCLES
    # ---- window elapsed. Bounded. Clobbers t0-t3. -------------------------
wait_rel:
    li   t3, POLL_MAX
wr_loop:
    lw   t0, R_SR(s1)
    andi t1, t0, SR_REL
    bnez t1, wr_done
    addi t3, t3, -1
    bnez t3, wr_loop
    j    shafe2_fail
wr_done:
    ret

    # ---- wait_drdy: a result queued and the sequencer idle again
    # ---- (SR & 3 == 2). Bounded. Clobbers t0-t3. --------------------------
wait_drdy:
    li   t3, POLL_MAX
wd_loop:
    lw   t0, R_SR(s1)
    andi t1, t0, 0x03
    li   t2, 0x02
    beq  t1, t2, wd_done
    addi t3, t3, -1
    bnez t3, wd_loop
    j    shafe2_fail
wd_done:
    ret

    # ---- vector-124 handler (M19 plain-ret ABI, reached via CLAIM = 124 ->
    # ---- the dispatcher's jalr through IVT slot 124 -> 0xBC00). Records the
    # ---- DATA word, then POPS, which drops the DRDY level BEFORE the
    # ---- dispatcher COMPLETEs -- a level still high at complete re-pends.
    # ---- t0/t1/t2 are dispatcher-saved scratch; ra must survive. ----------
    .section .isr_afe_shared, "ax"
afe_irq_isr:
    li   t0, AFE0
    lw   t1, R_DATA(t0)
    la   t2, afe_irq_data
    sw   t1, 0(t2)
    li   t1, SR_POP
    sw   t1, R_SR(t0)               # pop: FIFO empty -> irq drops
    la   t2, afe_irq_flag
    li   t1, 1
    sw   t1, 0(t2)
    ret
    .previous

    # ---- env meip dispatcher (.isr_meip @0xB100) --------------------------
    MEIP_DISPATCHER()

    # ---- IVT: slots 83/84 parked, 85 -> the dispatcher, 124 -> the AFE
    # ---- handler. IRQB_AFE = 124, so its slot is at 4*124 = 0x1F0, inside
    # ---- the 0x8000-0x81FF vector area (link.ld puts .text.init at 0x8200).
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, 0x0BB00              # slot 83 = IRQB_CLINT_MSIP: parked
    jal  zero, 0x0BB00              # slot 84 = IRQB_CLINT_MTIP: parked
    jal  zero, 0x0B100              # slot 85 = IRQB_EXT_MEIP -> dispatcher
    .org 0x1F0
    jal  zero, 0x0BC00              # slot 124 = IRQB_AFE -> .isr_afe_shared
    .previous

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) -- never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
afe_irq_flag: .word 0
afe_irq_data: .word 0
    # DATA words for phase 9: VALID | tag 14 | the 10-bit ctl window, windows
    # 0..4 of ctl = 0x2A95A39E3E5E0 | ATP_SEL.
afe_ctl_exp:  .word 0xB9E0, 0xB8F9, 0xBB9E, 0xB968, 0xBAA9
  TEST_DATA
RVTEST_DATA_END
