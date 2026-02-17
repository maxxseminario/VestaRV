#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** Includes **/
#include <stdint.h>
#include <MemoryMap.h>
#include <custom_ops.S>



/** Define Macros **/
#define cpu_sleep()	asm volatile(MACRO_TO_STRING(picorv32_sleep_insn()) "\n")
#define cpu_wake()	asm volatile(MACRO_TO_STRING(picorv32_wake_insn()) "\n")
#define halt_cpu_until_interrupt() asm volatile(MACRO_TO_STRING(picorv32_waitirq_insn()) "\n")



/** External Function Declarations **/
void enable_all_interrupts();
void disable_all_interrupts();
#ifdef ENABLE_COUNTERS
uint32_t set_cpu_timer_asm(uint32_t new_timer_value);
#endif	// #ifdef ENABLE_COUNTERS



#ifdef __cplusplus
}
#endif
