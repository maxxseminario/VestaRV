#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** Includes **/
// #include <MemoryMap.h>
#include <myshkin.h>
#include <spi.h>



/** External Function Declarations **/
void flash_memory_init();
void flash_memory_beginRead(uint32_t start_address);
void flash_memory_writePage(uint32_t page_address, uint8_t *data_256bytes);
void flash_memory_erasePage(uint32_t page_address);
uint8_t flash_memory_busy();
void assert_CS_FLASH();
void deassert_CS_FLASH();



#ifdef __cplusplus
}
#endif
