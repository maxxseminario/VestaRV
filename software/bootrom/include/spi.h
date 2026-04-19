#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** Includes **/
// #include <MemoryMap.h>
#include <myshkin.h>



/** Defines **/
#define SPIMODE0	(0)
#define SPIMODE1	(SPICPHA)
#define SPIMODE2	(SPICPOL)
#define SPIMODE3	(SPICPOL | SPICPHA)



/** External Function Declarations **/
void spi_init(uint8_t spi_mode, uint8_t data_length);
void spi_setDataLength(uint8_t data_length);
uint32_t spi_transfer(uint32_t data);



#ifdef __cplusplus
}
#endif
