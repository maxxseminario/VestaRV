#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** Includes **/
#include <stdint.h>



/** Defines **/
#define UART_CALC_BR(__clockfreq, __baudrate)	((__clockfreq / (16 * __baudrate)) - 1)
#define UART_CALC_BAUDRATE(__clockfreq, __baud_control_reg)	(__clockfreq / (16 * (__baud_control_reg + 1)))



/** External Function Declarations **/
void uart_init_default(uint16_t baud_register_value);
void uart_putchar(char c);
char uart_getchar();
void uart_read(char *str, uint32_t len);
uint32_t uart_read_until(char *str, char terminator, uint32_t max_len);
uint32_t uart_bytes_in_rx_buffer();
uint32_t uart_bytes_in_tx_buffer();
uint8_t uart_transmitting();
uint8_t uart_available();
void printString(char *s);
void printNewline();
void printStringln(char *s);
void printNumberUInt32(uint32_t nu);
void printNumberInt32(int32_t n);
void printHex4(uint8_t n);
void printHex8(uint8_t n);
void printHex16(uint16_t n);
void printHex32(uint32_t n);
uint8_t hex4ToNum(char hex4);



#ifdef __cplusplus
}
#endif
