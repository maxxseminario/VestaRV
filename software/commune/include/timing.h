// VestaRV: millisecond and microsecond timebase interface
// timing_init() must run before micros(), millis() or delay(); it claims one TIMERx instance selected at compile time by TIMING_LIB_USE_TIMER_NUMBER.

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// #include <MemoryMap.h>
#include <myshkin.h>
#include <stdint.h>



void timing_init();
uint8_t get_timing_lib_is_initialized();
uint32_t micros();
uint32_t millis();
void delay(uint32_t ms);



#ifdef __cplusplus
}
#endif
