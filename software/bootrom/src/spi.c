/** Includes **/
// #include <MemoryMap.h>
#include <myshkin.h>



/** Function Declarations **/
void spi_init(uint8_t spi_mode, uint8_t data_length);
void spi_setDataLength(uint8_t data_length);
uint32_t spi_transfer(uint32_t data);



/** Function Definitions **/
void spi_init(uint8_t spi_mode, uint8_t data_length)
{
	// Initializes the SPI0 peripheral
	// Arguments:
	//	spi_mode: The SPI mode. Can be 0 - 3, or SPIMODEx with x being 0 - 3
	// Returns: void

	// Set up the SPI control register
	SPI0CR = 0
		| SPIEN			// Enables SPI
		| SPIMSB		// Sends the MSB bit first
		// | SPITCIE	// Enables the transmit complete interrupt
		// | SPITEIE	// Enables the transmit register empty interrupt
		// | SPIDL_8	// 8-bit transfers
		| spi_mode
	;
	spi_setDataLength(data_length);

	// Clear the SPI status register
	SPI0SR = SPITCIF | SPITEIF;

	// Set the SPI pin select register
	MISO0_PxSEL |= MISO0_BIT | MOSI0_BIT | SCK0_BIT;

	return;
}

void spi_setDataLength(uint8_t data_length)
{
	// Sets the SPI transmission length
	// Arguments:
	//	data_length: The data length of a SPI transfer. May be SPIDL_8 for 8-bit transfers, SPIDL_16 for 16-bit transfers, or SPIDL_32 for 32-bit transfers
	// Returns: void
	SPI0CR = (SPI0CR & (~(SPIDL_MASK))) | data_length;
}

uint32_t spi_transfer(uint32_t data)
{
	// Transfers data over the SPI0 peripheral. The length of the transfer is determined by the previously set data length
	// Arguments:
	//	data: The data to be transferred. If the data length is set to 8-bit, only the LSB 8 bits are transmitted. If the data length is set to 16-bit, only the LSB 16 bits are transmitted.
	// Returns: Received data. If the data length is set to 8-bit, only the LSB 8 bits are valid. If the data length is set to 16-bit, only the LSB 16 bits are valid.

	// Load the data into the SPI transmit register to begin the transfer
	SPI0TX = data;

	// Wait for the transfer to finish
	while (SPI0SR & SPIBUSY) {}

	// Return the value of the SPI receive register
	return SPI0RX;
}
