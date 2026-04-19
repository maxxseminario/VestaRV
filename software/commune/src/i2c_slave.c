/** Includes **/
#include <MemoryMap.h>
#include <i2c_slave.h>


/** Defines **/
#define I2C_TIMEOUT		(10000)



/** Generic Function Declarations **/
int8_t i2cx_slave_init(I2Cx_t* I2Cx, uint8_t this_slave_address);
uint8_t i2cx_has_slave_been_addressed(I2Cx_t* I2Cx);
uint8_t i2cc_slave_get_mode(I2Cx_t* I2Cx);
uint8_t i2cx_slave_wait_until_addressed(I2Cx_t* I2Cx);
int8_t i2cx_slave_available(I2Cx_t* I2Cx);
int8_t i2cx_slave_rx_byte(I2Cx_t* I2Cx, uint8_t* rx_data_out, uint8_t send_nack);
void i2cx_slave_tx_queue_byte(I2Cx_t* I2Cx, uint8_t tx_data);
int8_t i2cx_slave_tx_byte(I2Cx_t* I2Cx, uint8_t tx_data);




/** Function Declarations **/
int8_t i2c_slave_init(uint8_t this_slave_address);
uint8_t i2c_has_slave_been_addressed();
uint8_t i2c_slave_get_mode();
uint8_t i2c_slave_wait_until_addressed();
int8_t i2c_slave_available();
int8_t i2c_slave_rx_byte(uint8_t* rx_data_out, uint8_t send_nack);
void i2c_slave_tx_queue_byte( uint8_t tx_data);
int8_t i2c_slave_tx_byte(uint8_t tx_data);




/** Private Function Declarations **/




/** Generic Function Definitions **/
int8_t i2cx_slave_init(I2Cx_t* I2Cx, uint8_t this_slave_address)
{
	// Check if master mode is enabled
	if (I2CxCR_PTR(I2Cx) & I2CMEN)
	{
		// Master mode is enabled. Check to see if the bus is being controlled by some other master (the bus is busy, but this master does not have control of it)
		if ((I2CxSR_PTR(I2Cx) & (I2CBS | I2CMCB)) == (I2CMCB))
		{
			return I2C_SLAVE_BUS_BUSY;
		}
	}

	// Check if slave mode is enabled
	if (I2CxCR_PTR(I2Cx) & I2CSEN)
	{
		// Slave mode is enabled. Check to see if the bus is idle or not
		if (I2CxSR_PTR(I2Cx) & I2CBS)
		{
			return I2C_SLAVE_BUS_BUSY;
		}
	}

	// Set the slave address
	I2CxAR_PTR(I2Cx) = this_slave_address;

	// Clear the status register
	I2CxSR_PTR(I2Cx) = 0;

	// Disable all I2C slave mode interrupts
	I2CxCR_PTR(I2Cx) &= ~(I2CSAIE | I2CSTXEIE | I2CSOVFIE | I2CSNRIE | I2CSXCIE);

	// Set up the I2C peripheral to enable slave mode, enable clock stretching, disable the general call address (0x00), and prevent the slave from NACKing the first received byte
	I2CxCR_PTR(I2Cx) = (I2CxCR_PTR(I2Cx) & ~(I2CMEN | I2CSEN | I2CSCS | I2CSN | I2CGCE)) | (I2CSEN | I2CSCS);

	return I2C_SLAVE_GOOD;
}

uint8_t i2cx_has_slave_been_addressed(I2Cx_t* I2Cx)
{
	// Return 1 if the slave has been addressed, return 0 if it has not
	return (I2CxSR_PTR(I2Cx) & I2CSA) != 0;
}

uint8_t i2cx_slave_get_mode(I2Cx_t* I2Cx)
{
	// Clear the status register (this does not clear I2CSTM)
	I2CxSR_PTR(I2Cx) = 0;

	// Return 1 if in slave transmitter mode, return 0 if in slave receiver mode
	if (I2CxSR_PTR(I2Cx) & I2CSTM)
	{
		// Enter slave transmitter mode
		// Do NOT send the ACK/NACK yet
		return I2C_SLAVE_TRANSMITTER;
	}
	else
	{
		// Enter slave receiver mode
		// Send an ACK and continue with transmission
		I2CxFCR_PTR(I2Cx) = I2CSC;
		return I2C_SLAVE_RECEIVER;
	}
}

uint8_t i2cx_slave_wait_until_addressed(I2Cx_t* I2Cx)
{
	// Send an ACK when addressed
	I2CxCR_PTR(I2Cx) &= ~I2CSN;
	
	// Block until this slave has been addressed
	while (!(i2cx_has_slave_been_addressed(I2Cx))) {}

	return i2cx_slave_get_mode(I2Cx);
}

int8_t i2cx_slave_available(I2Cx_t* I2Cx)
{
	// Check for a stop condition or a restart condition
	uint8_t start_or_stop_received = (I2CxSR_PTR(I2Cx) & (I2CSTR | I2CSPR)) != 0;
	
	// Return 1 if a new byte has been received by the slave transmitter, return 0 otherwise
	uint8_t has_new_byte = (I2CxSR_PTR(I2Cx) & I2CSXC) != 0;

	// Clear the status register
	I2CxSR_PTR(I2Cx) = 0;

	if (start_or_stop_received)
		return I2C_SLAVE_CONNECTION_ENDED;
	if (has_new_byte)
		return I2C_SLAVE_NEW_BYTE_AVAILABLE;
	return 0;
}

int8_t i2cx_slave_rx_byte(I2Cx_t* I2Cx, uint8_t* rx_data_out, uint8_t send_nack)
{
	// Wait for a new byte to be received
	int8_t ret = 0;
	while (ret == 0)
	{
		ret = i2cx_slave_available(I2Cx);
	}

	if (ret < 0)
		return ret;

	// Clear the status register
	I2CxSR_PTR(I2Cx) = 0;

	// Read the new byte
	*rx_data_out = I2CxSRX_PTR(I2Cx);

	// Send ACK or NACK
	if (send_nack)
	{
		I2CxCR_PTR(I2Cx) |= I2CSN;
	}
	else
	{
		I2CxCR_PTR(I2Cx) &= ~I2CSN;
	}

	// Release the I2C port (allow SCK to be deasserted) to allow the master to continue sending SCK pulses
	I2CxFCR_PTR(I2Cx) = I2CSC;

	return I2C_SLAVE_GOOD;
}

void i2cx_slave_tx_queue_byte(I2Cx_t* I2Cx, uint8_t tx_data)
{
	// Queue the byte to be transmitted
	I2CxSTX_PTR(I2Cx) = tx_data;

	// Release the I2C port (allow SCK to be deasserted) to allow the master to continue sending SCK pulses
	I2CxFCR_PTR(I2Cx) = I2CSC;

	return;
}

int8_t i2cx_slave_tx_byte(I2Cx_t* I2Cx, uint8_t tx_data)
{
	// Queue the next byte for transfer
	i2cx_slave_tx_queue_byte(I2Cx, tx_data);

	// Wait for the end of the transmission
	int8_t ret = 0;
	while (ret == 0)
	{
		ret = i2cx_slave_available(I2Cx);
	}

	if (ret < 0)
		return ret;
	
	return I2C_SLAVE_GOOD;
}





/** Function Definitions **/
int8_t i2c_slave_init(uint8_t this_slave_address)
{
	return i2cx_slave_init(I2C0, this_slave_address);
}

uint8_t i2c_has_slave_been_addressed()
{
	return i2cx_has_slave_been_addressed(I2C0);
}

uint8_t i2c_slave_get_mode()
{
	return i2cx_slave_get_mode(I2C0);
}

uint8_t i2c_slave_wait_until_addressed()
{
	return i2cx_slave_wait_until_addressed(I2C0);
}

int8_t i2c_slave_available()
{
	return i2cx_slave_available(I2C0);
}

int8_t i2c_slave_rx_byte(uint8_t* rx_data_out, uint8_t send_nack)
{
	return i2cx_slave_rx_byte(I2C0, rx_data_out, send_nack);
}

void i2c_slave_tx_queue_byte(uint8_t tx_data)
{
	return i2cx_slave_tx_queue_byte(I2C0, tx_data);
}

int8_t i2c_slave_tx_byte(uint8_t tx_data)
{
	return i2cx_slave_tx_byte(I2C0, tx_data);
}




/** Private Function Definitions **/

