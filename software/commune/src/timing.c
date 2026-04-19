/** Includes **/
#include <MemoryMap.h>
#include <irq.h>



/** Defines **/
#ifndef TIMING_LIB_USE_TIMER_NUMBER
	#define TIMING_LIB_USE_TIMER_NUMBER	1
#endif	// #ifndef TIMING_USE_TIMER_NUMBER

#ifndef HFXT_FREQUENCY
	#define HFXT_FREQUENCY	(24000000UL)
#endif	// #ifndef HFXT_FREQUENCY

#if   (TIMING_LIB_USE_TIMER_NUMBER == 0)
	#define TIMING_TIMERx				TIMER0
	#define IRQ_TIMERx_TIMING_VECTOR	IRQ_TIMER0_VECTOR
#elif (TIMING_LIB_USE_TIMER_NUMBER == 1)
	#define TIMING_TIMERx				TIMER1
	#define IRQ_TIMERx_TIMING_VECTOR	IRQ_TIMER1_VECTOR
#elif (TIMING_LIB_USE_TIMER_NUMBER == 2)
	#define TIMING_TIMERx				TIMER2
	#define IRQ_TIMERx_TIMING_VECTOR	IRQ_TIMER2_VECTOR
#else	// #if (TIMING_LIB_USE_TIMER_NUMBER == 0)
	#error "Invalid value for TIMING_LIB_USE_TIMER_NUMBER"
#endif	// #if (TIMING_LIB_USE_TIMER_NUMBER == 0)



/** Static Variables **/
static volatile uint32_t micros_upper_byte = 0;	// Every 1 of this is exactly 16777216 us
static uint8_t timing_lib_is_initialized = 0;



/** Function Declarations **/
void timing_init();
uint8_t get_timing_lib_is_initialized();
uint32_t micros();
uint32_t millis();
void delay(uint32_t ms);



/** Interrupt Service Routine Declaration Macros **/
RVISR(IRQ_TIMERx_TIMING_VECTOR, ISR_TIMERx_TIMING)



/** Function Definitions **/
void timing_init()
{
	// Initializes the timer and ISR to enable the micros(), millis(), and delay() functions

	// Configure the timer to have a division of 1, use HFXT, and enable the CMP2 interrupt
	TIMxCR_PTR(TIMING_TIMERx) = 0
		| TIMDIV_1
		| TIMSSEL_HFXT
		| TIMCMP2IE
	;

	// Reset the timer value
	TIMxVAL_PTR(TIMING_TIMERx) = 0;
	TIMxSR_PTR(TIMING_TIMERx) = 0;
	micros_upper_byte = 0;

	// Set the timer to roll over after 16777216 us (16.777216 s)
	TIMxCMP2_PTR(TIMING_TIMERx) = ((HFXT_FREQUENCY / 1000000) * 16777216) - 1;

	// Enable the interrupt
	uint32_t mask = get_IRQ_disable_mask();
	mask &= ~(1 << IRQ_TIMERx_TIMING_VECTOR);
	set_IRQ_disable_mask(mask);

	// Start the timer
	TIMxCR_PTR(TIMING_TIMERx) |= TIMEN;

	// Set the initialized flag
	timing_lib_is_initialized = 1;
}

uint8_t get_timing_lib_is_initialized()
{
	if (timing_lib_is_initialized == 1)
	{
		return 1;
	}
	return 0;
}

uint32_t micros()
{
	// Returns the number of microseconds elapsed since timing_init() was last called
	uint32_t lower = TIMxVAL_PTR(TIMING_TIMERx);
	uint32_t upper = micros_upper_byte;
	return (upper << 24) | (lower / (HFXT_FREQUENCY / 1000000));
}

uint32_t millis()
{
	// Returns the number of milliseconds elapsed since timing_init() was last called
	uint32_t lower = TIMxVAL_PTR(TIMING_TIMERx);
	uint32_t upper = micros_upper_byte;
	uint64_t both = ((uint64_t)upper << 24) | (lower / (HFXT_FREQUENCY / 1000000));
	return both / 1000;
}

void delay(uint32_t ms)
{
	// Delays for ms milliseconds
	uint32_t start = micros();
	while (ms > 0)
	{
		while ((ms > 0) && ((micros() - start) >= 1000))
		{
			ms--;
			start += 1000;
		}
	}
}



/** ISRs **/
void ISR_TIMERx_TIMING()
{
	// The timer has overflowed at precisely 65,536 ms. Increment the upper half of the 32-bit milliseconds value
	micros_upper_byte++;
	
	// Clear the TIMCMP2IF interrupt flag
	TIMxSR_PTR(TIMING_TIMERx) = TIMCMP2IF;
}