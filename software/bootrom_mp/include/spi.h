// VestaRV: boot ROM SPI driver interface
// SPI0 only. SPIMODE0..3 encode the (CPOL, CPHA) pair.

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

// #include <MemoryMap.h>
#include <myshkin.h>



#define SPIMODE0	(0)
#define SPIMODE1	(SPICPHA)
#define SPIMODE2	(SPICPOL)
#define SPIMODE3	(SPICPOL | SPICPHA)



void spi_init(uint8_t spi_mode, uint8_t data_length);
void spi_setDataLength(uint8_t data_length);
uint32_t spi_transfer(uint32_t data);



#ifdef __cplusplus
}
#endif
