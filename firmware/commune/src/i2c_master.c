/** Includes **/
#include <MemoryMap.h>
#include <i2c_master.h>


/** Defines **/
#define I2C_TIMEOUT		(10000)



/** Generic Function Declarations **/
int8_t i2cx_master_tx_start(I2Cx_t* I2Cx, uint8_t slave_address);
int8_t i2cx_master_rx_start(I2Cx_t* I2Cx, uint8_t slave_address);
int8_t i2cx_master_tx_byte(I2Cx_t* I2Cx, uint8_t tx_data);
int8_t i2cx_master_tx_bytes(I2Cx_t* I2Cx, uint8_t* tx_data_array, uint32_t length);
int8_t i2cx_master_rx_byte(I2Cx_t* I2Cx, uint8_t* rx_data_out);
uint8_t i2cx_master_rx_byte_no_timeout(I2Cx_t* I2Cx);
int8_t i2cx_master_rx_bytes(I2Cx_t* I2Cx, uint8_t* rx_data_array_out, uint32_t length);
int8_t i2cx_master_stop(I2Cx_t* I2Cx);



/** Function Declarations **/
int8_t i2c_master_tx_start(uint8_t slave_address);
int8_t i2c_master_rx_start(uint8_t slave_address);
int8_t i2c_master_tx_byte(uint8_t tx_data);
int8_t i2c_master_tx_bytes(uint8_t* tx_data_array, uint32_t length);
int8_t i2c_master_rx_byte(uint8_t* rx_data_out);
uint8_t i2c_master_rx_byte_no_timeout();
int8_t i2c_master_rx_bytes(uint8_t* rx_data_array_out, uint32_t length);
int8_t i2c_master_stop();



/** Private Function Declarations **/
int8_t i2cx_master_send_start(I2Cx_t* I2Cx);



/** Generic Function Definitions **/
int8_t i2cx_master_tx_start(I2Cx_t* I2Cx, uint8_t slave_address)
{
	// Send a start condition
	int8_t ret = i2cx_master_send_start(I2Cx);
	if (ret != I2C_GOOD)
	{
		return ret;
	}

	// Send the slave address followd by a write bit (0b0)
	return i2cx_master_tx_byte(I2Cx, (slave_address << 1) | 0b0);
}

int8_t i2cx_master_rx_start(I2Cx_t* I2Cx, uint8_t slave_address)
{
	// Send a start condition
	int8_t ret = i2cx_master_send_start(I2Cx);
	if (ret != I2C_GOOD)
	{
		return ret;
	}

	// Send the slave address followd by a read bit (0b1)
	return i2cx_master_tx_byte(I2Cx, (slave_address << 1) | 0b1);
}

int8_t i2cx_master_tx_byte(I2Cx_t* I2Cx, uint8_t tx_data)
{
	// Clear the status register
	I2CxSR_PTR(I2Cx) = 0;

	// Send the data
	I2CxMTX_PTR(I2Cx) = tx_data;

	// Wait for the transmission to complete, or for a loss of arbitration
	volatile uint32_t timeout = I2C_TIMEOUT;
	while (!(I2CxSR_PTR(I2Cx) & (I2CMXC | I2CMARB)))
	{
		if (timeout == 0)
		{
			// Send a stop condition and release control of the bus
			I2CxFCR_PTR(I2Cx) = I2CMSP;
			I2CxCR_PTR(I2Cx) &= ~I2CMEN;
			return I2C_MASTER_TX_TIMEOUT;
		}

		timeout--;
	}

	if (I2CxSR_PTR(I2Cx) & I2CMARB)
	{
		return I2C_ARBITRATION_LOSS;
	}

	// Did we receive an ACK or a NACK?
	if (I2CxSR_PTR(I2Cx) & I2CMNR)
	{
		return I2C_MASTER_NACK_RECEIVED;
	}

	return I2C_GOOD;
}

int8_t i2cx_master_tx_bytes(I2Cx_t* I2Cx, uint8_t* tx_data_array, uint32_t length)
{
	uint32_t i;
	volatile uint32_t timeout;

	for (i = 0; i < length; i++)
	{
		// Clear the status register
		I2CxSR_PTR(I2Cx) = 0;

		// Send the data
		I2CxMTX_PTR(I2Cx) = tx_data_array[i];

		// Wait for the TX register to be empty, or for a loss of arbitration
		timeout = I2C_TIMEOUT;
		while (!(I2CxSR_PTR(I2Cx) & (I2CMTXE | I2CMARB)))
		{
			if (timeout == 0)
			{
				// Send a stop condition and release control of the bus
				I2CxFCR_PTR(I2Cx) = I2CMSP;
				I2CxCR_PTR(I2Cx) &= ~I2CMEN;
				return I2C_MASTER_TX_TIMEOUT;
			}

			timeout--;
		}

		if (I2CxSR_PTR(I2Cx) & I2CMARB)
		{
			return I2C_ARBITRATION_LOSS;
		}

		// Did we receive an ACK or a NACK?
		if (I2CxSR_PTR(I2Cx) & I2CMNR)
		{
			return I2C_MASTER_NACK_RECEIVED;
		}
	}

	// Wait for the final transmission to be complete
	timeout = I2C_TIMEOUT;
	while (!(I2CxSR_PTR(I2Cx) & (I2CMXC | I2CMARB)))
	{
		if (timeout == 0)
		{
			// Send a stop condition and release control of the bus
			I2CxFCR_PTR(I2Cx) = I2CMSP;
			I2CxCR_PTR(I2Cx) &= ~I2CMEN;
			return I2C_MASTER_TX_TIMEOUT;
		}

		timeout--;
	}

	if (I2CxSR_PTR(I2Cx) & I2CMARB)
	{
		return I2C_ARBITRATION_LOSS;
	}

	// Did we receive an ACK or a NACK?
	if (I2CxSR_PTR(I2Cx) & I2CMNR)
	{
		return I2C_MASTER_NACK_RECEIVED;
	}

	return I2C_GOOD;
}

int8_t i2cx_master_rx_byte(I2Cx_t* I2Cx, uint8_t* rx_data_out)
{
	// Clear the status register
	I2CxSR_PTR(I2Cx) = 0;
	
	// Receive a byte of data from the slave by sending it clock pulses
	I2CxFCR_PTR(I2Cx) = I2CMRB;
	
	// Wait for the transmission to complete
	volatile uint32_t timeout = I2C_TIMEOUT;
	while (!(I2CxSR_PTR(I2Cx) & (I2CMXC | I2CMARB)))
	{
		if (timeout == 0)
		{
			// Send a stop condition and release control of the bus
			I2CxFCR_PTR(I2Cx) = I2CMSP;
			I2CxCR_PTR(I2Cx) &= ~I2CMEN;
			return I2C_MASTER_RX_TIMEOUT;
		}

		timeout--;
	}
	
	// Clear the status register
	I2CxSR_PTR(I2Cx) = 0;
	
	// No need to send an ACK or NACK here, the peripheral will handlie it itself
	
	// Return the data
	*rx_data_out = I2C0MRX;

	return 0;
}

uint8_t i2cx_master_rx_byte_no_timeout(I2Cx_t* I2Cx)
{
	// Clear the status register
	I2CxSR_PTR(I2Cx) = 0;
	
	// Receive a byte of data from the slave by sending it clock pulses
	I2CxFCR_PTR(I2Cx) = I2CMRB;
	
	// Wait for the transmission to complete
	while (!(I2CxSR_PTR(I2Cx) & (I2CMXC | I2CMARB))) {}
	
	// Clear the status register
	I2CxSR_PTR(I2Cx) = 0;
	
	// No need to send an ACK or NACK here, the peripheral will handlie it itself
	
	// Return the data
	return I2C0MRX;
}

int8_t i2cx_master_rx_bytes(I2Cx_t* I2Cx, uint8_t* rx_data_array_out, uint32_t length)
{
	uint32_t i;
	for (i = 0; i < length; i++)
	{
		int8_t ret = i2cx_master_rx_byte(I2Cx, &rx_data_array_out[i]);
		if (ret != I2C_GOOD)
		{
			return ret;
		}
	}

	return I2C_GOOD;
}

int8_t i2cx_master_stop(I2Cx_t* I2Cx)
{
	// Clear the status register
	I2CxSR_PTR(I2Cx) = 0;

	// Send the stop condition
	I2CxFCR_PTR(I2Cx) = I2CMSP;

	// Wait for the stop condition to be sent
	volatile uint32_t timeout = I2C_TIMEOUT;
	while (!(I2CxSR_PTR(I2Cx) & I2CMSPS))
	{
		if (timeout == 0)
		{
			return I2C_STOP_CONDITION_TIMEOUT;	
		}

		timeout--;
	}
	
	// Did the stop condition get sent successfully?
	if (!(I2CxSR_PTR(I2Cx) & I2CSPR))
	{
		return I2C_STOP_CONDITION_FAILED;
	}

	// Clear the status register
	I2CxSR_PTR(I2Cx) = 0;

	return I2C_GOOD;
}




/** Function Definitions **/
int8_t i2c_master_tx_start(uint8_t slave_address)
{
	return i2cx_master_tx_start(I2C0, slave_address);
}

int8_t i2c_master_rx_start(uint8_t slave_address)
{
	return i2cx_master_rx_start(I2C0, slave_address);
}

int8_t i2c_master_tx_byte(uint8_t tx_data)
{
	return i2cx_master_tx_byte(I2C0, tx_data);
}

int8_t i2c_master_tx_bytes(uint8_t* tx_data_array, uint32_t length)
{
	return i2cx_master_tx_bytes(I2C0, tx_data_array, length);
}

int8_t i2c_master_rx_byte(uint8_t* rx_data_out)
{
	return i2cx_master_rx_byte(I2C0, rx_data_out);
}

uint8_t i2c_master_rx_byte_no_timeout()
{
	return i2cx_master_rx_byte_no_timeout(I2C0);
}

int8_t i2c_master_rx_bytes(uint8_t* rx_data_array_out, uint32_t length)
{
	return i2cx_master_rx_bytes(I2C0, rx_data_array_out, length);
}

int8_t i2c_master_stop()
{
	return i2cx_master_stop(I2C0);
}



/** Private Function Definitions **/
int8_t i2cx_master_send_start(I2Cx_t* I2Cx)
{
	// Check if master mode is enabled
	if (I2CxCR_PTR(I2Cx) & I2CMEN)
	{
		// Master mode is enabled. Check to see if the bus is being controlled by some other master (the bus is busy, but this master does not have control of it)
		if ((I2CxSR_PTR(I2Cx) & (I2CBS | I2CMCB)) == (I2CMCB))
		{
			return I2C_BUS_BUSY;
		}
	}

	// Check if slave mode is enabled
	if (I2CxCR_PTR(I2Cx) & I2CSEN)
	{
		// Slave mode is enabled. Check to see if the bus is idle or not
		if (I2CxSR_PTR(I2Cx) & I2CBS)
		{
			return I2C_BUS_BUSY;
		}
	}

	// Clear the status register
	I2CxSR_PTR(I2Cx) = 0;

	// Disable all I2C master mode interrupts
	I2CxCR_PTR(I2Cx) &= ~(I2CMSTSIE | I2CMSPSIE | I2CMARBIE | I2CMTXEIE | I2CMNRIE | I2CMXCIE | I2CSTRIE | I2CSPRIE);

	// Set up the I2C peripheral to enable master mode, disable slave mode, and set the I2C clock divider to divide by 16 (this should result in a 400 kHz SCL when f_MCU = 24 MHz)
	I2CxCR_PTR(I2Cx) = (I2CxCR_PTR(I2Cx) & ~(I2CMEN | I2CSEN | I2CMDIV_MASK)) | (I2CMEN | I2CMDIV_16);

	// Send a start condition
	I2CxFCR_PTR(I2Cx) = I2CMST;

	// Wait for the start condition to be sent
	volatile uint32_t timeout = I2C_TIMEOUT;
	while (!(I2CxSR_PTR(I2Cx) & I2CMSTS))
	{
		if (timeout == 0)
		{
			return I2C_START_CONDITION_TIMEOUT;	
		}

		timeout--;
	}

	// Did the start condition get sent successfully?
	if (!(I2CxSR_PTR(I2Cx) & I2CSTR))
	{
		return I2C_START_CONDITION_FAILED;
	}

	// Clear the status register
	I2CxSR_PTR(I2Cx) = 0;

	return I2C_GOOD;
}
