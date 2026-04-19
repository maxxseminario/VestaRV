/** Includes **/
#include <MemoryMap.h>



/** Function Declarations **/
uint32_t measure_mclk_freq(TIMERx_t* TIMERA, TIMERx_t* TIMERB);
void set_DCO0_freq(uint32_t freq_hz, TIMERx_t* TIMERA, TIMERx_t* TIMERB);



/** Function Defititions **/
uint32_t measure_mclk_freq(TIMERx_t* TIMERA, TIMERx_t* TIMERB)
{
	// Configure TIMERA to use DCO0
	TIMxCR_PTR(TIMERA) = 0
		| TIMDIV_1	// No clock division
		| TIMSSEL_MCLK
		;
	TIMxVAL_PTR(TIMERA) = 0;
	TIMxSR_PTR(TIMERA) = 0;

	// Configure TIMERB to use ClkLFXT (32.768 kHz)
	TIMxCR_PTR(TIMERB) = 0
		| TIMDIV_1	// No clock division
		| TIMSSEL_LFXT	// Select LFXT as the source clock for TIMER1
		;
	TIMxVAL_PTR(TIMERB) = 0;
	TIMxSR_PTR(TIMERB) = 0;

	register uint32_t t1_end = 4096;	// measurement time = 0.125 seconds

	// Start the low frequency measuring clock
	TIMxCR_PTR(TIMERB) |= TIMEN;

	// Wait for the low frequency measuring clock to have a positive clock edge. This ensures accurate and reproducable measurements
	while (TIMxVAL_PTR(TIMERB) == 1) {}

	// Start the measured clock's timer and reset the low frequency measuring clock
	TIMxCR_PTR(TIMERA) |= TIMEN;
	TIMxVAL_PTR(TIMERB) = 0;

	// Wait until TIMER1 reaches the desired value
	while (TIMxVAL_PTR(TIMERB) < t1_end) {}

	// The the measurement time is complete, stop TIMER0 and read its value, then calculate the frequency
	TIMxCR_PTR(TIMERA) = 0;
	TIMxCR_PTR(TIMERB) = 0;
	uint32_t frequency = TIMxVAL_PTR(TIMERA) << 3;	// multiply by 1 / measurement time

	// Send the frequency
	return frequency;
}

void set_DCO0_freq(uint32_t freq_hz, TIMERx_t* TIMERA, TIMERx_t* TIMERB)
{
	uint16_t dco0_value = 0;

	int8_t i;
	for (i = 11; i >= 0; i--)
	{
		dco0_value |= (1 << i);
		DCO0FREQ = dco0_value;

		volatile uint32_t j;
		for (j = 0; j < 10000; j++) {}

		uint32_t measured_freq = measure_mclk_freq(TIMERA, TIMERB);
		if (measured_freq > freq_hz)
		{
			dco0_value &= ~(1 << i);
		}
	}

	DCO0FREQ = dco0_value;
}



