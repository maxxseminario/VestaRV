#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** Includes **/
#include <MemoryMap.h>
//#include <spi1.h>



/** Structs **/
typedef struct
{
	uint32_t SYNC_PxOUT_ADDR;
	uint32_t SYNC_BIT_MASK;
} DAC8162_SYNC_PIN_t;



/** External Function Declarations **/
void DAC8162_init(DAC8162_SYNC_PIN_t SYNC_PIN);
void DAC8162_setDacA(DAC8162_SYNC_PIN_t SYNC_PIN, uint16_t dacValue);
void DAC8162_setDacB(DAC8162_SYNC_PIN_t SYNC_PIN, uint16_t dacValue);
void DAC8162_setDacAB(DAC8162_SYNC_PIN_t SYNC_PIN, uint16_t dacValue);



#ifdef __cplusplus
}
#endif
