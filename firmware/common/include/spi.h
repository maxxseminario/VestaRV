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



/** External Generic Function Declarations **/
void spix_init(SPIx_t* SPIx, uint8_t setupAsSlave, uint8_t spi_mode, uint8_t data_length);
void spix_setDataLength(SPIx_t* SPIx, uint8_t data_length);
uint32_t spix_transfer(SPIx_t* SPIx, uint32_t data);



/** External Function Declarations **/
void spi_init(uint8_t spi_mode, uint8_t data_length);
void spi_setDataLength(uint8_t data_length);
uint32_t spi_transfer(uint32_t data);

#ifdef SPI1
#ifdef SPISM
void spi1_init(uint8_t setupAsSlave, uint8_t spi_mode, uint8_t data_length);
#else	// #ifdef SPISM
void spi1_init(uint8_t spi_mode, uint8_t data_length);
#endif	// #ifdef SPISM
void spi1_setDataLength(uint8_t data_length);
uint32_t spi1_transfer(uint32_t data);
#endif	// #ifdef SPI1



#ifdef __cplusplus
}
#endif
