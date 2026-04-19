#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** Includes **/
#include <MemoryMap.h>



/** Defines **/
#define I2C_SLAVE_GOOD					(0)
#define I2C_SLAVE_RECEIVER				(0)
#define I2C_SLAVE_TRANSMITTER			(1)
#define I2C_SLAVE_NEW_BYTE_AVAILABLE	(1)

#define I2C_SLAVE_BUS_BUSY				(-1)
#define I2C_SLAVE_CONNECTION_ENDED		(-2)



/** External Generic Function Declarations **/
int8_t i2cx_slave_init(I2Cx_t* I2Cx, uint8_t this_slave_address);
uint8_t i2cx_has_slave_been_addressed(I2Cx_t* I2Cx);
uint8_t i2cc_slave_get_mode(I2Cx_t* I2Cx);
uint8_t i2cx_slave_wait_until_addressed(I2Cx_t* I2Cx);
int8_t i2cx_slave_available(I2Cx_t* I2Cx);
int8_t i2cx_slave_rx_byte(I2Cx_t* I2Cx, uint8_t* rx_data_out, uint8_t send_nack);
void i2cx_slave_tx_queue_byte(I2Cx_t* I2Cx, uint8_t tx_data);
int8_t i2cx_slave_tx_byte(I2Cx_t* I2Cx, uint8_t tx_data);



/** External Function Declarations **/
int8_t i2c_slave_init(uint8_t this_slave_address);
uint8_t i2c_has_slave_been_addressed();
uint8_t i2c_slave_get_mode();
uint8_t i2c_slave_wait_until_addressed();
int8_t i2c_slave_available();
int8_t i2c_slave_rx_byte(uint8_t* rx_data_out, uint8_t send_nack);
void i2c_slave_tx_queue_byte( uint8_t tx_data);
int8_t i2c_slave_tx_byte(uint8_t tx_data);



#ifdef __cplusplus
}
#endif
