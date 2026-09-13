// VestaRV: MCLK measurement and DCO0 tuning interface
// Both calls need two TIMERx instances: one gates a window on the reference clock, the other counts DCO0 edges inside it.

#pragma once



#include <clocks.h>



uint32_t measure_mclk_freq(TIMERx_t* TIMERA, TIMERx_t* TIMERB);
void set_DCO0_freq(uint32_t freq_hz, TIMERx_t* TIMERA, TIMERx_t* TIMERB);



