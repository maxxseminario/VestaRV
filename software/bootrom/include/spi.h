// VestaRV: SPI0 driver interface for the boot ROM.
// SPIMODE0..3 are the usual CPOL/CPHA pairs; spi_init takes one of them plus a SPIDL_* length.

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

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
