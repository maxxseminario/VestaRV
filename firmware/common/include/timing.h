#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** Includes **/
// #include <MemoryMap.h>
#include <myshkin.h>
#include <stdint.h>



/** Function Declarations **/
void timing_init();
uint8_t get_timing_lib_is_initialized();
uint32_t micros();
uint32_t millis();
void delay(uint32_t ms);



#ifdef __cplusplus
}
#endif
