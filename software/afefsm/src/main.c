/*
 * afefsm - Absolute-minimum AFE FSM kicker
 * ------------------------------------------------------------------
 * Goal: do the LEAST amount of work needed to get the AFE_FSM cycling
 * so we can look at internal signals on the four AFE digital test
 * ports (DTP0..DTP3) with a scope.
 *
 * Strategy:
 *   - Enable the bias generator (bare minimum so the analog blocks
 *     have current).
 *   - Route four useful FSM signals onto DTP0..DTP3 via AFE_TPR.
 *   - Put the AFE in CONTINUOUS-MEASUREMENT mode (CONTMEAS=1) so the
 *     FSM re-triggers itself forever without any CPU help.
 *   - Kick it off by writing AFE_ADC_VAL once.
 *   - Spin forever. No polling, no globals, no LED, no UART.
 *
 * After this runs you should see:
 *   DTP0 = adc_clk      (free-running ADC clock)
 *   DTP1 = ADCACTIVE    (high while a conversion is in progress)
 *   DTP2 = adc_done     (one-shot pulse at end of each conversion)
 *   DTP3 = adc_start    (one-shot pulse at start of each conversion)
 *
 * Register map: platform/gcc/lib/include/MemoryMap.h
 * Behaviour:    hdl/MCU/periph/AFE.vhd
 */

#include <stdint.h>
#include "MemoryMap.h"

/* Direct address access (no struct/PTR macros, just raw pokes). */
#define REG32(addr) (*(volatile uint32_t *)(addr))
#define REG16(addr) (*(volatile uint16_t *)(addr))
#define REG8(addr)  (*(volatile uint8_t  *)(addr))

#define AFE_CR_R          REG32(AFE_CR_ADDRESS)
#define AFE_TPR_R         REG32(AFE_TPR_ADDRESS)
#define AFE_SR_R          REG8 (AFE_SR_ADDRESS)
#define AFE_ADC_VAL_R     REG16(AFE_ADC_VAL_ADDRESS)
#define BIAS_CR_R         REG8 (BIAS_CR_ADDRESS)

/* DTP signal-select indices (see AFE.vhd test-port mux).            */
#define DTP_ADC_CLK       4u
#define DTP_ADC_ACTIVE    0u
#define DTP_ADC_DONE      3u
#define DTP_ADC_START     8u

/* RAMPNUM = full-scale 12-bit integration window. Larger -> longer
 * conversion -> easier to see edges on a slow scope.                */
#define RAMPNUM           0xFFFu

static void busy_delay(volatile uint32_t n) {
    while (n--) { __asm__ volatile ("nop"); }
}

int main(void) {
    /* 1. Bias generator on (internal mode, buffers enabled).        */
    BIAS_CR_R = BUFEN_BIT | EN_BIT;

    /* Let the bias settle before we start switching analog stuff.   */
    busy_delay(20000);

    /* 2. Route FSM signals to DTP0..DTP3.
     *    AFE_TPR layout:
     *      [19:15] = DTP3SEL
     *      [14:10] = DTP2SEL
     *      [ 9: 5] = DTP1SEL
     *      [ 4: 0] = DTP0SEL                                         */
    AFE_TPR_R = ((uint32_t)DTP_ADC_CLK    << AFE_DTP0SEL_LSB)
              | ((uint32_t)DTP_ADC_ACTIVE << AFE_DTP1SEL_LSB)
              | ((uint32_t)DTP_ADC_DONE   << AFE_DTP2SEL_LSB)
              | ((uint32_t)DTP_ADC_START  << AFE_DTP3SEL_LSB);

    /* 3. Clear any latched status bits (write-1-to-clear).          */
    AFE_SR_R = 0x0F;

    /* 4. Enable the AFE FSM in continuous-measurement mode:
     *      RAMPNUM | CONTMEAS=1 | DACEN=1 | EN=1 | ADCEN=1
     *    DATARDYIE=0 (no interrupts), ADCEXTIN=0 (use internal DSADC
     *    front-end -- we just want the FSM to run, we don't care
     *    about the value yet).                                      */
    AFE_CR_R = ((uint32_t)RAMPNUM << AFE_RAMPNUM_LSB)
             | AFE_CONTMEAS_BIT
             | AFE_DACEN_BIT
             | AFE_EN_BIT
             | AFE_ADCEN_BIT;

    /* 5. Kick off the first conversion. In CONTMEAS mode the FSM
     *    will re-trigger itself from then on.                       */
    AFE_ADC_VAL_R = 0;

    /* 6. Done. Sleep forever; the FSM runs on its own.              */
    for (;;) { __asm__ volatile ("wfi"); }
    return 0;
}
