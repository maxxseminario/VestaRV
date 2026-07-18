/*
 * afetest - Minimal AFE bring-up test
 * ------------------------------------------------------------------
 * Goal: prove the AFE peripheral is alive on a freshly fabricated
 * chip with a passive resistor "dummy cell" connected (RE-R-WE,
 * CE-R-WE or similar). Performs a single DSADC conversion at a
 * known excitation and stores the 12-bit result in a global so it
 * can be inspected via JTAG/GDB.
 *
 * It also routes useful internal signals onto the four AFE digital
 * test ports (DTP0..DTP3) so that even without a debugger you can
 * see the FSM running on a scope:
 *   DTP0 = adc_clk        (idx 4)
 *   DTP1 = adc_active     (idx 0)  -> ADCACTIVE
 *   DTP2 = adc_done       (idx 3)
 *   DTP3 = adc_start      (idx 8)
 *
 * If the conversion completes (DATARDYIF asserts) the program
 * blinks the on-board LED on P3.0 slowly via direct GPIO writes.
 * If it times out (FSM stuck) it blinks rapidly. This gives a
 * chip-only pass/fail signal even before UART/JTAG is wired up.
 *
 * Register map: platform/myshkin/gcc/lib/include/MemoryMap.h
 * Behaviour:    hdl/myshkin/periph/AFE.vhd
 * Procedure:    platform/myshkin/latex/PeripheralIntroductions/AFE-intro-myshkin-2025-11.tex
 */

#include <stdint.h>
#include "MemoryMap.h"

/* ----- Direct address access (avoids any *_PTR macro / struct issues) ----- */
#define REG32(addr) (*(volatile uint32_t *)(addr))
#define REG16(addr) (*(volatile uint16_t *)(addr))
#define REG8(addr)  (*(volatile uint8_t  *)(addr))

#define AFE_CR_R          REG32(AFE_CR_ADDRESS)
#define AFE_TPR_R         REG32(AFE_TPR_ADDRESS)
#define AFE_SR_R          REG8 (AFE_SR_ADDRESS)
#define AFE_ADC_VAL_R     REG16(AFE_ADC_VAL_ADDRESS)
#define BIAS_CR_R         REG8 (BIAS_CR_ADDRESS)
#define BIAS_TIA_G_POT_R  REG32(BIAS_TIA_G_POT_ADDRESS)
#define BIAS_DSADC_VCM_R  REG16(BIAS_DSADC_VCM_ADDRESS)
#define BIAS_REV_POT_R    REG16(BIAS_REV_POT_ADDRESS)

/* ----- Globals visible to the debugger -------------------------------------*/
volatile uint32_t afe_result    = 0xDEADBEEF; /* last 12-bit ADC code        */
volatile uint32_t afe_n_done    = 0;          /* successful conversion count */
volatile uint32_t afe_n_timeout = 0;          /* timeout count               */
volatile uint32_t afe_status_snapshot = 0;    /* last AFE_SR read            */

/* ----- Tunables ------------------------------------------------------------*/
#define RAMPNUM          0xFFF   /* full-scale 12-bit integration window     */
#define DAC_MIDSCALE     8192    /* 14-bit midscale = VDD/2                   */
#define DAC_EXCITATION   9192    /* ~+1000 LSB above midscale -> small +Δv    */
#define TIA_GAIN_MIN     0x1FFFF /* lowest gain (widest input current range)  */
#define POLL_TIMEOUT     100000u /* loop iterations to wait for DATARDYIF     */

/* ----- Tiny delay (pure software, calibration-free) ------------------------*/
static void busy_delay(volatile uint32_t n) {
    while (n--) { __asm__ volatile ("nop"); }
}

/* ----- Single DSADC conversion. Returns 12-bit code or 0xFFFF on timeout. --*/
static uint32_t afe_single_conversion(void) {
    /* Clear all status flags (write 1 to clear) */
    AFE_SR_R = 0x0F;

    /* Trigger: write any value to AFE_ADC_VAL */
    AFE_ADC_VAL_R = 0;

    /* Poll DATARDYIF (bit 1 of AFE_SR) */
    for (uint32_t i = 0; i < POLL_TIMEOUT; i++) {
        uint8_t sr = AFE_SR_R;
        if (sr & AFE_DATARDYIF_BIT) {
            afe_status_snapshot = sr;
            uint32_t v = AFE_ADC_VAL_R & AFE_ADCVAL_MASK;
            AFE_SR_R = AFE_DATARDYIF_BIT;   /* clear flag */
            return v;
        }
    }
    afe_status_snapshot = AFE_SR_R;
    return 0xFFFFu; /* timeout sentinel */
}

/* ----- Bring up the AFE for a basic measurement ----------------------------*/
static void afe_init(void) {
    /* 1. Bias generation: enable internal bias + buffers, internal gen mode */
    BIAS_CR_R = BUFEN_BIT | EN_BIT;   /* USEDAC=0 -> on-chip generator       */

    /* 2. Reference voltages (DACs):
     *    - VCM at VDD/2 (centre TIA output / DSADC input)
     *    - REV (excitation) slightly above VCM so cell sees a known Δv      */
    BIAS_DSADC_VCM_R = DAC_MIDSCALE;
    BIAS_REV_POT_R   = DAC_EXCITATION;

    /* 3. TIA gain: start at minimum gain (max current range) so we don't
     *    rail the amplifier on an unknown dummy resistor.                   */
    BIAS_TIA_G_POT_R = TIA_GAIN_MIN;

    /* (All other trim registers BIAS_TC_POT/LC_POT/TC_DSADC/LC_DSADC/
     *  RIN_DSADC/RFB_DSADC/ADJ keep their HDL reset values -- that's the
     *  whole point of "most basic": rely on factory defaults first.)       */

    /* 4. Route useful FSM signals to DTP0..DTP3 for scope visibility.
     *    AFE_TPR layout: [19:15]=DTP3SEL [14:10]=DTP2SEL
     *                    [9:5]  =DTP1SEL [4:0]  =DTP0SEL                   */
    AFE_TPR_R = ( 4u << AFE_DTP0SEL_LSB)   /* DTP0 = adc_clk    */
              | ( 0u << AFE_DTP1SEL_LSB)   /* DTP1 = ADCACTIVE  */
              | ( 3u << AFE_DTP2SEL_LSB)   /* DTP2 = adc_done   */
              | ( 8u << AFE_DTP3SEL_LSB);  /* DTP3 = adc_start  */

    /* 5. Control register: RAMPNUM | ADCEXTIN=1 | DACEN=1 | EN=1 | ADCEN=1
     *    CONTMEAS=0 (single shot), DATARDYIE=0 (poll mode).                */
    AFE_CR_R = ((uint32_t)RAMPNUM << AFE_RAMPNUM_LSB)
             | AFE_ADCEXTIN_BIT
             | AFE_DACEN_BIT
             | AFE_EN_BIT
             | AFE_ADCEN_BIT;

    /* 6. Allow analog blocks to settle before first conversion.            */
    busy_delay(50000);
}

/* ----- Optional pass/fail visual indicator on P3.0 -------------------------*/
/* GPIO2 base = 0x4800 (P3.x). Slot 8. Direct register pokes only.           */
#define P3_BASE   0x4800u
#define P3_SEL    REG32(P3_BASE + 0x00)
#define P3_DIR    REG32(P3_BASE + 0x04)
#define P3_OUT    REG32(P3_BASE + 0x08)

static void led_init(void) {
    P3_SEL = 0x00;   /* P3.0 = software GPIO (not peripheral)               */
    P3_DIR = 0x01;   /* P3.0 = output                                       */
    P3_OUT = 0x00;
}
static void led_blink(uint32_t period_ticks, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        P3_OUT = 0x01; busy_delay(period_ticks);
        P3_OUT = 0x00; busy_delay(period_ticks);
    }
}

/* ===========================================================================
 *                                MAIN
 * =========================================================================*/
int main(void) {
    led_init();
    afe_init();

    /* Run a handful of conversions so transients average out. The result
     * of the *last* conversion is left in afe_result for inspection.       */
    for (int i = 0; i < 8; i++) {
        uint32_t v = afe_single_conversion();
        if (v == 0xFFFFu) {
            afe_n_timeout++;
        } else {
            afe_result = v;
            afe_n_done++;
        }
    }

    /* Visual indication:
     *   - All conversions completed -> 4 slow blinks
     *   - Any timeouts              -> 8 fast blinks
     *   then idle.                                                         */
    if (afe_n_timeout == 0) {
        led_blink(400000, 4);
    } else {
        led_blink(80000, 8);
    }

    while (1) { __asm__ volatile ("wfi"); }
    return 0;
}
