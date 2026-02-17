#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** Includes **/
#include <MemoryMap.h>



/** Defines **/
#define I2C_GOOD					(0)
#define I2C_BUS_BUSY				(-1)
#define I2C_START_CONDITION_TIMEOUT	(-2)
#define I2C_START_CONDITION_FAILED	(-3)
#define I2C_MASTER_TX_TIMEOUT		(-4)
#define I2C_ARBITRATION_LOSS		(-5)
#define I2C_MASTER_NACK_RECEIVED	(-6)
#define I2C_STOP_CONDITION_TIMEOUT	(-7)
#define I2C_STOP_CONDITION_FAILED	(-8)
#define I2C_MASTER_RX_TIMEOUT		(-9)



/** External Generic Function Declarations **/
int8_t i2cx_master_tx_start(I2Cx_t* I2Cx, uint8_t slave_address);
int8_t i2cx_master_rx_start(I2Cx_t* I2Cx, uint8_t slave_address);
int8_t i2cx_master_tx_byte(I2Cx_t* I2Cx, uint8_t tx_data);
int8_t i2cx_master_tx_bytes(I2Cx_t* I2Cx, uint8_t* tx_data_array, uint32_t length);
int8_t i2cx_master_rx_byte(I2Cx_t* I2Cx, uint8_t* rx_data_out);
uint8_t i2cx_master_rx_byte_no_timeout(I2Cx_t* I2Cx);
int8_t i2cx_master_rx_bytes(I2Cx_t* I2Cx, uint8_t* rx_data_array_out, uint32_t length);
int8_t i2cx_master_stop(I2Cx_t* I2Cx);



/** External Function Declarations **/
int8_t i2c_master_tx_start(uint8_t slave_address);
int8_t i2c_master_rx_start(uint8_t slave_address);
int8_t i2c_master_tx_byte(uint8_t tx_data);
int8_t i2c_master_tx_bytes(uint8_t* tx_data_array, uint32_t length);
int8_t i2c_master_rx_byte(uint8_t* rx_data_out);
uint8_t i2c_master_rx_byte_no_timeout();
int8_t i2c_master_rx_bytes(uint8_t* rx_data_array_out, uint32_t length);
int8_t i2c_master_stop();



#ifdef __cplusplus
}
#endif
