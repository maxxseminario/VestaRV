#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** Includes **/
// #include <MemoryMap.h>
#include <myshkin.h>
#include <stdint.h>



/** Defines **/
#define UART_CALC_BR(__clockfreq, __baudrate)	((__clockfreq / (16 * __baudrate)) - 1)
#define UART_CALC_BAUDRATE(__clockfreq, __baud_control_reg)	(__clockfreq / (16 * (__baud_control_reg + 1)))

// Function aliases (for backwards compatibility)
#define uart_putchar		uart_putc
#define uart_getchar		uart_getc
#define printString			uart_puts
#define printNewline		uart_putln
#define printStringln		uart_putsln
#define printHex4			uart_puth4
#define printHex8			uart_puth8
#define printHex16			uart_puth16
#define printHex32			uart_puth32



/** Helper Function Declarations **/
uint8_t uint32_to_str(char* buf, uint32_t nu);
uint8_t	hex4_to_uint(char hex4);
uint8_t double_to_str(char* buf, double val, uint8_t num_decimal_digits);



/** Generic Function Declarations **/
void	uartx_init_default(UARTx_t* UARTx, uint16_t baud_register_value);
void	uartx_init_8N1(UARTx_t* UARTx, uint32_t smclk_freq, uint32_t baud);
uint8_t	uartx_transmitting(UARTx_t* UARTx);
uint8_t	uartx_available(UARTx_t* UARTx);
char	uartx_getc(UARTx_t* UARTx);
char	uartx_getc_immediate(UARTx_t* UARTx);
uint8_t	uartx_getb(UARTx_t* UARTx);
uint8_t	uartx_getb_immediate(UARTx_t* UARTx);
uint8_t	uartx_gets_until(UARTx_t* UARTx, char* buf, uint32_t len, char terminator);
uint8_t	uartx_getsln(UARTx_t* UARTx, char* buf, uint32_t len);
void	uartx_getbytes(UARTx_t* UARTx, void* buf, uint32_t len);
uint8_t	uartx_getbytes_until(UARTx_t* UARTx, void* buf, uint32_t len, uint8_t terminator);
void	uartx_putc(UARTx_t* UARTx, char c);
void	uartx_putb(UARTx_t* UARTx, uint8_t byte);
void	uartx_puts(UARTx_t* UARTx, const void* str);
void	uartx_putln(UARTx_t* UARTx);
void	uartx_putsln(UARTx_t* UARTx, const void* str);
void	uartx_putui(UARTx_t* UARTx, uint32_t nu);
void	uartx_puti(UARTx_t* UARTx, int32_t n);
void	uartx_puth4(UARTx_t* UARTx, uint8_t n);
void	uartx_puth8(UARTx_t* UARTx, uint8_t n);
void	uartx_puth16(UARTx_t* UARTx, uint16_t n);
void	uartx_puth32(UARTx_t* UARTx, uint32_t n);
void	uartx_putuib8(UARTx_t* UARTx, uint8_t nu);
void	uartx_putuib16(UARTx_t* UARTx, uint16_t nu);
void	uartx_putuib32(UARTx_t* UARTx, uint32_t nu);
void	uartx_putf(UARTx_t* UARTx, double val, uint8_t num_decimal_digits);
void	uartx_pute(UARTx_t* UARTx, double val, uint8_t num_decimal_digits);




/** Function Declarations for UART0 **/
void	uart_init_default(uint16_t baud_register_value);
void	uart_init_8N1(uint32_t smclk_freq, uint32_t baud);
uint8_t	uart_transmitting();
uint8_t	uart_available();
char	uart_getc();
char	uart_getc_immediate();
uint8_t	uart_getb();
uint8_t	uart_getb_immediate();
uint8_t	uart_gets_until(char* buf, uint32_t len, char terminator);
uint8_t	uart_getsln(char* buf, uint32_t len);
void	uart_getbytes(void* buf, uint32_t len);
uint8_t	uart_getbytes_until(void* buf, uint32_t len, uint8_t terminator);
void	uart_putc(char c);
void	uart_putb(uint8_t byte);
void	uart_puts(const void* str);
void	uart_putln();
void	uart_putsln(const void* str);
void	uart_putui(uint32_t nu);
void	uart_puti(int32_t n);
void	uart_puth4(uint8_t n);
void	uart_puth8(uint8_t n);
void	uart_puth16(uint16_t n);
void	uart_puth32(uint32_t n);
void	uart_putuib8(uint8_t nu);
void	uart_putuib16(uint16_t nu);
void	uart_putuib32(uint32_t nu);
void	uart_putf(double val, uint8_t num_decimal_digits);
void	uart_pute(double val, uint8_t num_decimal_digits);

void	printNumberUInt32(uint32_t nu);
void	printNumberInt32(int32_t n);



#ifdef UART1_BASE
/** Function Declarations for UART1 **/
void	uart1_init_default(uint16_t baud_register_value);
void	uart1_init_8N1(uint32_t smclk_freq, uint32_t baud);
uint8_t	uart1_transmitting();
uint8_t	uart1_available();
char	uart1_getc();
char	uart1_getc_immediate();
uint8_t	uart1_getb();
uint8_t	uart1_getb_immediate();
uint8_t	uart1_gets_until(char* buf, uint32_t len, char terminator);
uint8_t	uart1_getsln(char* buf, uint32_t len);
void	uart1_getbytes(void* buf, uint32_t len);
uint8_t	uart1_getbytes_until(void* buf, uint32_t len, uint8_t terminator);
void	uart1_putc(char c);
void	uart1_putb(uint8_t byte);
void	uart1_puts(const void* str);
void	uart1_putln();
void	uart1_putsln(const void* str);
void	uart1_putui(uint32_t nu);
void	uart1_puti(int32_t n);
void	uart1_puth4(uint8_t n);
void	uart1_puth8(uint8_t n);
void	uart1_puth16(uint16_t n);
void	uart1_puth32(uint32_t n);
void	uart1_putuib8(uint8_t nu);
void	uart1_putuib16(uint16_t nu);
void	uart1_putuib32(uint32_t nu);
void	uart1_putf(double val, uint8_t num_decimal_digits);
void	uart1_pute(double val, uint8_t num_decimal_digits);
#endif	// #ifdef UART1_BASE



#ifdef __cplusplus
}
#endif
