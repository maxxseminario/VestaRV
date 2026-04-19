/** Includes **/
#include <MemoryMap.h>
#include <spi1.h>
#include <DAC8162.h>



/** Defines **/
// Commands (bits 21 downto 19)
#define SHIFT_CMD				19

#define CMD_WRITE_REG			(0b000 << SHIFT_CMD)	// Write to input register n (Table 13)
#define CMD_LDAC_UPDATE			(0b001 << SHIFT_CMD)	// Software LDAC, update DAC register n (Table 13)
#define CMD_WRITE_UPDATE_ALL	(0b010 << SHIFT_CMD)	// Write to input register n (Table 13) and update all DAC registers
#define CMD_WRITE_UPDATE		(0b011 << SHIFT_CMD)	// Write to input register n and update DAC register n (Table 13)
#define CMD_SET_POWER			(0b100 << SHIFT_CMD)	// Set DAC power up or down mode
#define CMD_RESET				(0b101 << SHIFT_CMD)	// Software reset
#define CMD_SET_LDAC			(0b110 << SHIFT_CMD)	// Set LDAC registers
#define CMD_REF					(0b111 << SHIFT_CMD)	// Enable or disable the internal reference

// Register Addresses (bits 18 downto 16)
#define SHIFT_ADDR				16

#define ADDR_DACA				(0b000 << SHIFT_ADDR)
#define ADDR_DACB				(0b001 << SHIFT_ADDR)
#define ADDR_GAIN				(0b010 << SHIFT_ADDR)	// Only use with command CMD_WRITE_REG
#define ADDR_DACAB				(0b111 << SHIFT_ADDR)	// DAC A and DAC B



/** Function Declarations **/
void DAC8162_init(DAC8162_SYNC_PIN_t SYNC_PIN);
void DAC8162_setDacA(DAC8162_SYNC_PIN_t SYNC_PIN, uint16_t dacValue);
void DAC8162_setDacB(DAC8162_SYNC_PIN_t SYNC_PIN, uint16_t dacValue);
void DAC8162_setDacAB(DAC8162_SYNC_PIN_t SYNC_PIN, uint16_t dacValue);
void DAC8162_transmit(DAC8162_SYNC_PIN_t SYNC_PIN, uint32_t data24b);



/** Function Definitions **/
void DAC8162_init(DAC8162_SYNC_PIN_t SYNC_PIN)
{
	// Reset all registers in the DAC
	DAC8162_transmit(SYNC_PIN, CMD_RESET | 0b1);

	// Enable internal 2.5 V reference and reset DAC A and DAC B (also sets DAC gain to 2, which is undesirable but ultimately acceptable, it just needs to be changed to 1 later)
	DAC8162_transmit(SYNC_PIN, CMD_REF | 0b1);

	// Set gain to 1 for DAC A and DAC B (this makes the full-scale range 2.5 V)
	DAC8162_transmit(SYNC_PIN, CMD_WRITE_REG | ADDR_GAIN | 0b11);

	// Disable LDAC pin for DAC A and DAC B
	DAC8162_transmit(SYNC_PIN, CMD_SET_LDAC | 0b11);

	// Power up DAC A and DAC B
	DAC8162_transmit(SYNC_PIN, CMD_SET_POWER | 0b11);
}

void DAC8162_setDacA(DAC8162_SYNC_PIN_t SYNC_PIN, uint16_t dacValue)
{
	DAC8162_transmit(SYNC_PIN, CMD_WRITE_UPDATE | ADDR_DACA | (dacValue << 2));
}

void DAC8162_setDacB(DAC8162_SYNC_PIN_t SYNC_PIN, uint16_t dacValue)
{
	DAC8162_transmit(SYNC_PIN, CMD_WRITE_UPDATE | ADDR_DACB | (dacValue << 2));
}

void DAC8162_setDacAB(DAC8162_SYNC_PIN_t SYNC_PIN, uint16_t dacValue)
{
	DAC8162_transmit(SYNC_PIN, CMD_WRITE_UPDATE | ADDR_DACAB | (dacValue << 2));
}

void DAC8162_transmit(DAC8162_SYNC_PIN_t SYNC_PIN, uint32_t data24b)
{
	// Set up the SPI peripheral
	spi1_init(SPIMODE2, SPIDL_8);	// SCK idles high, data is latched on the leading edge of SCK, 8-bit transfers

	// Assert SYNC pin (bring low)
	(*((volatile uint32_t *) SYNC_PIN.SYNC_PxOUT_ADDR)) &= ~(SYNC_PIN.SYNC_BIT_MASK);

	// Send the 24-bit data MSB first
	spi1_transfer(data24b >> 16);
	spi1_transfer(data24b >> 8);
	spi1_transfer(data24b);

	// Deassert SYNC pin (bring high)
	(*((volatile uint32_t *) SYNC_PIN.SYNC_PxOUT_ADDR)) |= SYNC_PIN.SYNC_BIT_MASK;

	return;
}
