#pragma once



/** Includes **/
#include <clocks.h>



/** External Function Declarations **/
uint32_t measure_mclk_freq(TIMERx_t* TIMERA, TIMERx_t* TIMERB);
void set_DCO0_freq(uint32_t freq_hz, TIMERx_t* TIMERA, TIMERx_t* TIMERB);



