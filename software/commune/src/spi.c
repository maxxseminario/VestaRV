/** Includes **/
// #include <MemoryMap.h>
#include <myshkin.h>



/** Generic Function Declarations **/
void spix_init(SPIx_t* SPIx, uint8_t setupAsSlave, uint8_t spi_mode, uint8_t data_length);
void spix_setDataLength(SPIx_t* SPIx, uint8_t data_length);
uint32_t spix_transfer(SPIx_t* SPIx, uint32_t data);



/** Function Declarations **/
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



/** Generic Function Definitions **/
void spix_init(SPIx_t* SPIx, uint8_t setupAsSlave, uint8_t spi_mode, uint8_t data_length)
{
	// Initializes the SPI0 peripheral
	// Arguments:
	//	spi_mode: The SPI mode. Can be 0 - 3, or SPIMODEx with x being 0 - 3
	// Returns: void

	// Set up the SPI control register
#ifdef SPISM
	#define __IF_SPI_HAS_SLAVE_CAPABILITY__ (setupAsSlave ? SPISM : 0)
#else
	#define __IF_SPI_HAS_SLAVE_CAPABILITY__ (0)
#endif

	SPIxCR_PTR(SPIx) = 0
		| __IF_SPI_HAS_SLAVE_CAPABILITY__
		| SPIEN			// Enables SPI
		| SPIMSB		// Sends the MSB bit first
		// | SPITCIE	// Enables the transmit complete interrupt
		// | SPITEIE	// Enables the transmit register empty interrupt
		// | SPIDL_8	// 8-bit transfers
		| (spi_mode & (SPICPOL | SPICPHA))
	;
	spix_setDataLength(SPIx, data_length);

	// Clear the SPI status register
	SPIxSR_PTR(SPIx) = SPITCIF | SPITEIF;

	return;
}

void spix_setDataLength(SPIx_t* SPIx, uint8_t data_length)
{
	// Sets the SPI transmission length
	// Arguments:
	//	data_length: The data length of a SPI transfer. May be SPIDL_8 for 8-bit transfers, SPIDL_16 for 16-bit transfers, or SPIDL_32 for 32-bit transfers
	// Returns: void
	SPIxCR_PTR(SPIx) = (SPIxCR_PTR(SPIx) & (~(SPIDL_MASK))) | (data_length & SPIDL_MASK);
}

uint32_t spix_transfer(SPIx_t* SPIx, uint32_t data)
{
	// Transfers data over the SPI0 peripheral. The length of the transfer is determined by the previously set data length
	// Arguments:
	//	data: The data to be transferred. If the data length is set to 8-bit, only the LSB 8 bits are transmitted. If the data length is set to 16-bit, only the LSB 16 bits are transmitted.
	// Returns: Received data. If the data length is set to 8-bit, only the LSB 8 bits are valid. If the data length is set to 16-bit, only the LSB 16 bits are valid.

	// Load the data into the SPI transmit register to begin the transfer
	SPIxTX_PTR(SPIx) = data;

	// Wait for the transfer to finish
	while (SPIxSR_PTR(SPIx) & SPIBUSY) {}

	// Return the value of the SPI receive register
	return SPIxRX_PTR(SPIx);
}



/** Function Definitions **/
void spi_init(uint8_t spi_mode, uint8_t data_length)
{
	// Initialize SPI
	spix_init(SPI0, 0, spi_mode, data_length);

	// Set the SPI pin select register
	MISO0_PxSEL |= MISO0_BIT | MOSI0_BIT | SCK0_BIT;

	return;
}

void spi_setDataLength(uint8_t data_length)
{
	spix_setDataLength(SPI0, data_length);
}

uint32_t spi_transfer(uint32_t data)
{
	return spix_transfer(SPI0, data);
}



#ifdef SPI1
#ifdef SPISM
void spi1_init(uint8_t setupAsSlave, uint8_t spi_mode, uint8_t data_length)
#else	// #ifdef SPISM
void spi1_init(uint8_t spi_mode, uint8_t data_length)
#endif	// #ifdef SPISM
{
	// Initialize SPI
#ifdef SPISM
	spix_init(SPI1, setupAsSlave, spi_mode, data_length);
#else
	spix_init(SPI1, 0, spi_mode, data_length);
#endif

	// Set the SPI pin select register
	MISO0_PxSEL |= MISO0_BIT | MOSI0_BIT | SCK0_BIT;

	return;
}

void spi1_setDataLength(uint8_t data_length)
{
	spix_setDataLength(SPI1, data_length);
}

uint32_t spi1_transfer(uint32_t data)
{
	return spix_transfer(SPI1, data);
}
#endif // #ifdef SPI1
