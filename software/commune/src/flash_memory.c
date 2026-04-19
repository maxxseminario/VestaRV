/** Includes **/
#include <MemoryMap.h>
#include <spi.h>
#include <flash_memory.h>



/** Defines **/
// SPI Flash Opcodes
#define SPI_FLASH_OPCODE_WAKE		(0xAB)
#define SPI_FLASH_OPCODE_UNPROTECT	(0x3D2A80A6)
#define SPI_FLASH_OPCODE_256B_PAGE	(0x3D2A7F9A)
#define SPI_FLASH_OPCODE_READ_HF	(0x0B)	// High frequency read mode
#define SPI_FLASH_OPCODE_READ_LF	(0x03)	// Low frequency read mode
#define SPI_FLASH_OPCODE_WRITE		(0x82)
#define SPI_FLASH_OPCODE_PAGE_ERASE	(0x81)
#define SPI_FLASH_OPCODE_STATUS_REGISTER_READ	(0xD7)



/** Function Declarations **/
void flash_memory_init();
void flash_memory_beginRead(uint32_t start_address);
void flash_memory_writePage(uint32_t page_address, uint8_t *data_256bytes);
void flash_memory_erasePage(uint32_t page_address);
uint8_t flash_memory_busy();
void assert_CS_FLASH();
void deassert_CS_FLASH();



/** Function Definitions **/
void flash_memory_init()
{
	// Initializes the SPI flash memory for reading and writing
	// Arguments: none
	// Returns: void

	// Set up SPI0
	spi_init(SPIMODE3, SPIDL_8);

	// Set up CS_FLASH pin
	CS_FLASH_PxSEL &= ~CS_FLASH_BIT;
	CS_FLASH_PxDIR |= CS_FLASH_BIT;
	deassert_CS_FLASH();

	// Wake the SPI flash from deep sleep
	assert_CS_FLASH();
	spi_transfer(SPI_FLASH_OPCODE_WAKE);
	deassert_CS_FLASH();

	// Wait for about 8 ms for the SPI flash to awake. Note: you cannot read the SPI flash status register to know when the device has awoken from deep power down, since the MISO line will be in a high-impedance state
	volatile uint32_t i;
	for (i = 40000; i > 0; i--) {}

	// Perform the global unprotect operation for all the memory on the SPI flash. This allows any page to be written to and/or erased (YE BE WARNED)
	spi_setDataLength(SPIDL_32);

	assert_CS_FLASH();
	spi_transfer(SPI_FLASH_OPCODE_UNPROTECT);
	deassert_CS_FLASH();

	// Wait for about 1 ms for the SPI flash to unprotect all its memory
	//for (i = 5000; i > 0; i--) {}
	while (flash_memory_busy()) {}

	// Configure the SPI flash to use 256-byte pages
	assert_CS_FLASH();
	spi_transfer(SPI_FLASH_OPCODE_256B_PAGE);
	deassert_CS_FLASH();
}

void flash_memory_beginRead(uint32_t start_address)
{
	// Sets up a read operation from the SPI flash memory
	// Note: this only sets up a read operation, and then hands off the actual SPI transmissions to read the data to the user. A typical application would call this function, then set the desired SPI data length, then call the spi_transfer function for however many times is desired, and finally call deassert_CS_FLASH
	// Note: You must change the SPI transfer data length after calling this function unless you want to use 32-bit transfers
	// Arguments:
	//	start_address: The address of the first SPI flash memory element to read
	// Returns: void

	// Wait for the SPI flash to be ready
	while (flash_memory_busy()) {}

	// Set up SPI0
	spi_init(SPIMODE3, SPIDL_8);
	assert_CS_FLASH();

	// Send the opcode to read from the SPI flash
	spi_transfer(SPI_FLASH_OPCODE_READ_HF);

	// Send the 24-bit start address and 8 dummy bits at the end
	spi_setDataLength(SPIDL_32);
	spi_transfer(start_address << 8);

	// Any further bytes transferred over SPI0 from the SPI flash will be the requested data. To end the transmission, simply deassert the CS_FLASH pin
	// Don't forget to change the data length after calling this function
}

void flash_memory_writePage(uint32_t page_address, uint8_t *data_256bytes)
{
	// Writes a page of data to the SPI flash
	// Note: You are technically required to wait an average of 10 ms and a maximum of 25 ms after this function call to allow the SPI flash to perform its internal write operation. This waiting period is up to the user to perform and is not enforced
	// Arguments:
	//	page_address: The address of the page to write to. Note that the LSB 8 bits are ignored because data must start on a 256-byte boundary (a page), and the MSB 8 bits are ignored because they are out of range of the size of the SPI flash
	//	data_256bytes: The data payload (as an array of bytes) to be written to the SPI flash. data_256bytes MUST be a 256 byte array. All 256 bytes of data in the array will be written to the SPI flash
	// Returns: void

	// Wait for SPI flash to be ready to write a page (i.e. it is not busy)
	while (flash_memory_busy()) {}

	// Set up SPI0
	spi_init(SPIMODE3, SPIDL_32);
	assert_CS_FLASH();

	// Send the write opcode, the start address, and a dummy byte to the SPI flash (note that we're sending the LSB byte of page_address: this is OK because it will simply be ignored)
	spi_transfer((((uint32_t)SPI_FLASH_OPCODE_WRITE) << 24) | page_address);

	// Send the payload
	spi_setDataLength(SPIDL_8);
	
	uint16_t i;
	for (i = 0; i < 256; i++)
	{
		spi_transfer(data_256bytes[i]);
	}

	// Finish transmission
	deassert_CS_FLASH();

	// Note that you are technically required to wait an average of 10 ms and a maximum of 25 ms after writing to allow the SPI flash to perform its internal write operation
}

void flash_memory_erasePage(uint32_t page_address)
{
	// Erases a page of data (sets all bytes in the page to 0xFF)
	// Note: You are technically required to wait an average of 6 ms and a maximum of 25 ms after this function call to allow the SPI flash to perform its internal erase operation. This waiting period is up to the user to perform and is not enforced
	// Arguments:
	//	page_address: The address of the page to erase. Note that the LSB 8 bits are ignored because data must start on a 256-byte boundary (a page), and the MSB 8 bits are ignored because they are out of range of the size of the SPI flash
	// Returns: void

	// Wait for SPI flash to be ready to erase a page (i.e. it is not busy)
	while (flash_memory_busy()) {}

	// Set up SPI0
	spi_init(SPIMODE3, SPIDL_32);
	assert_CS_FLASH();

	// Send the erase page opcode, the start address, and a dummy byte to the SPI flash (note that we're sending the LSB byte of page_address: this is OK because it will simply be ignored)
	spi_transfer((((uint32_t)SPI_FLASH_OPCODE_PAGE_ERASE) << 24) | page_address);

	// Finish transmission
	deassert_CS_FLASH();

	// Note that you are technically required to wait an average of 6 ms and a maximum of 25 ms after writing to allow the SPI flash to perform its internal write operation
}

uint8_t flash_memory_busy()
{
	// Set up SPI0
	spi_init(SPIMODE3, SPIDL_8);
	assert_CS_FLASH();

	// Send the status register read opcode
	spi_transfer(SPI_FLASH_OPCODE_STATUS_REGISTER_READ);

	// Get the first byte of the status register (the second byte is unnecessary)
	uint8_t status_reg_byte1 = spi_transfer(0);

	// Finish transmission
	deassert_CS_FLASH();

	// If the RDY/~BUSY bit is a 1, return false to indicate the SPI flash is not busy, otherwise return true to indicate it is still erasing/programming a page
	return ((status_reg_byte1 & BIT7) == 0);
}

void assert_CS_FLASH()
{
	CS_FLASH_PxOUT &= ~CS_FLASH_BIT;	// Assert CS
}

void deassert_CS_FLASH()
{
	CS_FLASH_PxOUT |= CS_FLASH_BIT;		// Deassert CS
}