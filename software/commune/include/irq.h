// VestaRV: interrupt control and CPU sleep intrinsics
// cpu_sleep, cpu_wake and halt_cpu_until_interrupt emit the custom SYSTEM encodings defined in custom_ops.S; they are not standard RISC-V instructions.

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <MemoryMap.h>
#include <custom_ops.S>



/** Define Macros **/
#define cpu_sleep()	asm volatile(MACRO_TO_STRING(picorv32_sleep_insn()) "\n")
#define cpu_wake()	asm volatile(MACRO_TO_STRING(picorv32_wake_insn()) "\n")
#define halt_cpu_until_interrupt() asm volatile(MACRO_TO_STRING(picorv32_waitirq_insn()) "\n")



void enable_all_interrupts();
void disable_all_interrupts();
#ifdef ENABLE_COUNTERS
uint32_t set_cpu_timer_asm(uint32_t new_timer_value);
#endif	// #ifdef ENABLE_COUNTERS



#ifdef __cplusplus
}
#endif
