// VestaRV: TI DAC8162 SPI DAC driver interface
// The SYNC (chip-select) pin is passed as a port output-register address plus a bit mask, so one driver serves any GPIO pin.

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#include <MemoryMap.h>
//#include <spi1.h>



/** Structs **/
typedef struct
{
	uint32_t SYNC_PxOUT_ADDR;
	uint32_t SYNC_BIT_MASK;
} DAC8162_SYNC_PIN_t;



void DAC8162_init(DAC8162_SYNC_PIN_t SYNC_PIN);
void DAC8162_setDacA(DAC8162_SYNC_PIN_t SYNC_PIN, uint16_t dacValue);
void DAC8162_setDacB(DAC8162_SYNC_PIN_t SYNC_PIN, uint16_t dacValue);
void DAC8162_setDacAB(DAC8162_SYNC_PIN_t SYNC_PIN, uint16_t dacValue);



#ifdef __cplusplus
}
#endif
