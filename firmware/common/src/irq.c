/** Includes **/
#include <MemoryMap.h>



/** Public Function Declarations **/
void enable_all_interrupts();
void disable_all_interrupts();
#ifdef ENABLE_COUNTERS
uint32_t set_cpu_timer(uint32_t new_timer_value);
#endif	// #ifdef ENABLE_COUNTERS



/** Private Function Declarations **/
#ifndef ENABLE_IRQ_FAST_CONTEXT_SWITCHING
void IRQ_master_handler_C(uint32_t IRQ_flags);
#endif	// #ifndef ENABLE_IRQ_FAST_CONTEXT_SWITCHING



/** External Assembly Function Declarations **/
extern uint32_t halt_cpu_until_interrupt_asm();
#ifdef ENABLE_COUNTERS
extern uint32_t set_cpu_timer_asm(uint32_t new_timer_value);
#endif	// #ifdef ENABLE_COUNTERS



/** Public Function Definitions **/
void enable_all_interrupts()
{
	IRQEN = 0xFFFFFFFF;
}

void disable_all_interrupts()
{
	IRQEN = 0;
}

#ifdef ENABLE_COUNTERS
uint32_t set_cpu_timer(uint32_t new_timer_value)
{
	// Sets the 32- or 64-bit CPU timer (which is a countdown timer) to new_timer_value
	// Note: Setting the timer to 0 disables the timer
	// Note: The CPU timer generates an interrupt (IVT element 0) when the timer transitions from 1 to 0
	return set_cpu_timer_asm(new_timer_value);
}
#endif	// #ifdef ENABLE_COUNTERS




/** Private Function Definitions **/
#ifndef ENABLE_IRQ_FAST_CONTEXT_SWITCHING
void IRQ_master_handler_C(uint32_t IRQ_flags)
{
	// Check the interrupts in order of priority
	uint32_t v;
	for (v = 0; v <= LAST_POPULATED_IRQ_VECTOR; v++)	// WARNING: This must remain as-is because v is used later to shift in the IRQ flags
	{
		if ((IRQ_flags >> v) & 0x1)
		{
			// This interrupt is triggered, so call the appropriate function pointed to by the appropriate interrupt vector table element
			((void (*)(void))(*((uint32_t *)(INTERRUPT_VECTOR_TABLE_START + (v << 2)))))();
		}
	}
}
#endif	// #ifndef ENABLE_IRQ_FAST_CONTEXT_SWITCHING
