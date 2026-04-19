/** Includes **/
#include <MemoryMap.h>
#include <uart.h>

#include <math.h>
#include <string.h>



/** Helper Function Declarations **/
uint8_t	uint32_to_str(char* buf, uint32_t nu);
uint8_t	hex4_to_uint(char hex4);
uint8_t	double_to_str_exp(char* buf, double val, uint8_t num_decimal_digits);
uint8_t	double_to_str(char* buf, double val, uint8_t num_decimal_digits);



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



/** Helper Function Definitions **/
uint8_t uint32_to_str(char* buf, uint32_t nu)
{
	// Converts a uint32 to a string
	// Arguments:
	//	buf: pointer to the string that the number will be written to. buf must be an array of at least size 12, including the null terminator (length 11)
	//	nu: The uint32 to convert to a string
	// Returns: the length of buf (not including null terminator)
	int32_t i;
	int32_t rem;
	char x[12];

	i = 0;
	do
	{
		rem = nu % 10;
		x[i] = (uint8_t)rem + (uint8_t)'0';
		nu = nu / 10;
		i = i + 1;
	} while ((nu != 0) && (i < 12));

	int32_t j = 0;
	do
	{
		i = i - 1;
		buf[j] = x[i];
		j++;
	} while (i > 0);
	buf[j] = '\0';
	return j;
}

uint8_t hex4_to_uint(char hex4)
{
	// Converts hex character to a uint8
	// Arguments:
	//	hex4: the char to convert
	// Returns: the converted number

	uint8_t n = hex4 - '0';
	
	// Check if digit is A-F
	if (hex4 > '9')
	{
		// It's A-F (but could still be a-f)
		n -= 7;

		// Check if a-f
		if (hex4 >= 'a')
			n -= 0x20;
	}

	return n;
}

uint8_t double_to_str_exp(char* buf, double val, uint8_t num_decimal_digits)
{
	// Converts a double to a string using exponential formatting
	// Arguments:
	//	buf: pointer to the string that the number will be written to. buf must be an array of at least size 10 + num_decimal_digits, including the null terminator (maximum size of 27)
	//	val: The double to convert to a string
	//	num_decimal_digits: The number of digits after the decimal point. Maximum is 17, minimum is 0
	// Returns: the length of buf (not including null terminator)
	uint8_t i = 0;
	int classification = fpclassify(val);
	if (classification == FP_ZERO)
	{
		strcpy(buf, "0.0");
		return 3;
	}
	
	if (isnan(val))
	{
		strcpy(buf, "nan");
		return 3;
	}

	// Add a negative sign if the number is negative
	if (val < 0)
	{
		val = -val;
		buf[0] = '-';
		i++;
	}

	if (classification == FP_INFINITE)
	{
		strcpy(&buf[i], "inf");
		return 3 + i;
	}

	if (num_decimal_digits > 17)
	{
		num_decimal_digits = 17;
	}

	
	// Calculate the exponent
	int16_t exponent10 = 0;
	while (val < 1.0)
	{
		val *= 10;
		exponent10--;
	}
	while (val >= 10.0)
	{
		val *= 0.1;
		exponent10++;
	}

	// Calculate the rounding factor and round the value
	double rounding_addend = 0.5;
	uint8_t j;
	for (j = 0; j < num_decimal_digits; j++)
	{
		rounding_addend *= 0.1;
	}
	val += rounding_addend;
	if (val >= 10.0)
	{
		val *= 0.1;
		exponent10++;
	}

	// Calculate the "ones" digit and put it in the string
	uint8_t ones_digit = (uint8_t)val;
	buf[i] = (char)ones_digit + '0';
	i++;
	
	// Add the decimal point
	if (num_decimal_digits > 0)
	{
		buf[i] = '.';
		i++;
	}
	
	// Put the decimal digits in the string
	for (j = 0; j < num_decimal_digits; j++)
	{
		val = (val - (double)ones_digit) * 10;
		ones_digit = (uint8_t)val;
		buf[i] = ones_digit + '0';
		i++;
	}

	// Put the 'e' and exponent sign in the string
	buf[i] = 'e';
	i++;
	if (exponent10 < 0)
	{
		exponent10 = -exponent10;
		buf[i] = '-';
	}
	else
	{
		buf[i] = '+';
	}
	i++;

    // Put the exponent in the string
	i += uint32_to_str(&buf[i], exponent10);	// This automatically adds a null terminator

	return i;
}

uint8_t double_to_str(char* buf, double val, uint8_t num_decimal_digits)
{
	// Converts a double to a string using normal formatting
	// Arguments:
	//	buf: pointer to the string that the number will be written to. buf must be an array of at least size 12 + num_decimal_digits, including the null terminator (maximum size of 29)
	//	val: The double to convert to a string
	//	num_decimal_digits: The number of digits after the decimal point. Maximum is 17, minimum is 0
	// Returns: the length of buf (not including null terminator)
	if (fpclassify(val) != FP_NORMAL)
	{
		// Any infinite, zero, or NaN values will be handled by double_to_str_exp()
		return double_to_str_exp(buf, val, num_decimal_digits);
	}
	
	if (num_decimal_digits > 17)
	{
		num_decimal_digits = 17;
	}
	
	uint8_t i = 0;

	// Add a negative sign if the number is negative
	if (val < 0)
	{
		val = -val;
		buf[0] = '-';
		i++;
	}

	if (val >= 1000000000)
	{
		i += double_to_str_exp(&buf[i], val, num_decimal_digits);
		return i;
	}

	// Calculate the rounding factor and round the value
	double rounding_addend = 0.5;
	uint8_t j;
	for (j = 0; j < num_decimal_digits; j++)
	{
		rounding_addend *= 0.1;
	}
	val += rounding_addend;

	// Add the integer part
	uint32_t integer_part = val;
	i += uint32_to_str(&buf[i], integer_part);

	if (num_decimal_digits == 0)
	{
		return i;
	}

	// Add the decimal point
	buf[i] = '.';
	i++;

	// Add the fractional part
	for (j = 0; j < num_decimal_digits; j++)
	{
		val = (val - (double)integer_part) * 10;
		integer_part = (uint32_t)val;
		buf[i] = integer_part + '0';
		i++;
	}

	buf[i] = '\0';
	return i;
}



/** Generic Function Definitions **/
void uartx_init_default(UARTx_t* UARTx, uint16_t baud_register_value)
{
	// Initializes the UARTx peripheral for 8N1 transmissions (but does not enable the appropriate pins)
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	baud_register_value: The desired value of the baud register (you must calculate it yourself)
	// Returns: nothing

	// Set baud rate
	UARTxBR_PTR(UARTx) = baud_register_value;

	// Set up control register
	UARTxCR_PTR(UARTx) = 0
		| UEN		// Enable UART
		// | UPEN	// Enable parity bit
		// | UPODD	// Set to odd parity
		// | URCIE	// Enable receive complete interrupt
		// | UTEIE	// Enable transmit register empty interrupt
		// | UTCIE	// Enable transmit complete interrupt
	;

	// Clear the interrupt flags UTEIF (transmit buffer empty) and UTCIF (transmission complete)
	UARTxSR_PTR(UARTx) = UTEIF | UTCIF;
	UARTxRX_PTR(UARTx);	// read RX register to clear other bits

	// Read the receive buffer register to clear UOVF (receive overflow), URCIF (receive complete), UPEF (parity error), and UFEF (framing error)
	UARTxRX_PTR(UARTx);
}

void uartx_init_8N1(UARTx_t* UARTx, uint32_t smclk_freq, uint32_t baud)
{
	// Initializes the UARTx peripheral for 8N1 transmissions (but does not enable the appropriate pins)
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	smclk_freq: The frequency of SMCLK in Hz (used for calculating the baud register)
	//	baud: The desired baud (used for calculating the baud register)
	// Returns: nothing
	
	// UARTxBR = (smclk_freq / (16 * baud)) - 1
	baud <<= 4;	// baud *= 16
	uint32_t uartxbr = ((smclk_freq + (baud >> 1)) / baud) - 1;	// with rounding
	uartx_init_default(UARTx, uartxbr);
}

void uartx_putc(UARTx_t* UARTx, char c)
{
	// Sends a single character over the UART
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	c: the character to send
	// Returns: nothing

	// Wait for the transmitter to finish any previous transmissions
	while (UARTxSR_PTR(UARTx) & UTBF) { }
	//while (UARTx->SR.TBF) {}
	
	// Send the new data byte
	UARTxTX_PTR(UARTx) = c;
	
	return;
}

char uartx_getc(UARTx_t* UARTx)
{
	// Waits for a single new character to be available in the UART RX register, and then reads it and returns it. If an unread character is in the UART RX register before this function is called, then it will be read and immediately returned. If more than one new characters are received before this function is called, only the most recent one will be returned, and the others will be lost.
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	// Returns: the character that was read from the UART RX register

	// Wait for the UART to receive a new character
	while ((UARTxSR_PTR(UARTx) & URCIF) == 0) { }
	
	// Return the new character that is in the receive buffer register
	return UARTxRX_PTR(UARTx);
}

char uartx_getc_immediate(UARTx_t* UARTx)
{
	// Returns the character currently in the UART RX register, regardless of if it has been read before or not.
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	// Returns: the character that was read from the UART RX register
	
	return UARTxRX_PTR(UARTx);
}

void uartx_putb(UARTx_t* UARTx, uint8_t byte)
{
	// Sends a single byte over the UART
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	byte: the byte to send
	// Returns: nothing

	uartx_putc(UARTx, (char)byte);
}

uint8_t uartx_getb(UARTx_t* UARTx)
{
	// Returns the byte currently in the UART RX register, regardless of if it has been read before or not.
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	// Returns: the byte that was read from the UART RX register

	return (uint8_t)uartx_getc(UARTx);
}

uint8_t uartx_getb_immediate(UARTx_t* UARTx)
{
	// Returns the byte currently in the UART RX register, regardless of if it has been read before or not.
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	// Returns: the byte that was read from the UART RX register

	return (uint8_t)uartx_getc_immediate(UARTx);
}

uint8_t uartx_transmitting(UARTx_t* UARTx)
{
	// Indicates if the UART is currently transmitting a byte or not
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	// Returns: 1 if the UART is currently transmitting a byte; 0 if not

	return (UARTxSR_PTR(UARTx) & UTBF) != 0;
}

uint8_t uartx_available(UARTx_t* UARTx)
{
	// Indicates if there is a new, unread character has been received and is available in the UART RX register or not
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	// Returns: 1 if a new, unread character is available in the UART RX register; 0 if not

	return (UARTxSR_PTR(UARTx) & URCIF) != 0;
}

void uartx_puts(UARTx_t* UARTx, const void* str)
{
	// Sends a string over the UART (stopping at the first null terminator \0 in str, without sending the null terminator)
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	str: A pointer to the string to send. Must be properly null terminated.
	// Returns: nothing
	
	uint32_t i = 0;
	char c = ((char*)str)[0];
	while (c != '\0')
	{
		uartx_putc(UARTx, c);
		i++;
		c = ((char*)str)[i];
	}
	
	return;
}

void uartx_putln(UARTx_t* UARTx)
{
	// Sends a newline string ("\n") over the UART
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	// Returns: nothing

	uartx_putc(UARTx, '\n');
}

void uartx_putsln(UARTx_t* UARTx, const void* str)
{
	// Sends a string over the UART followed by a newline
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	str: A pointer to the string to send. Must be properly null terminated.
	// Returns: nothing

	uartx_puts(UARTx, str);
	uartx_putln(UARTx);
}

void uartx_putui(UARTx_t* UARTx, uint32_t nu)
{
	// Converts an unsigned 32-bit integer to a string and sends the string over the UART
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	nu: the unsigned 32-bit integer to send
	// Returns: nothing
	
	int32_t i;
	int32_t rem;
	char x[12];

	i = 0;
	do
	{
		rem = nu % 10;
		x[i] = (uint8_t)rem + (uint8_t)'0';
		nu = nu / 10;
		i = i + 1;
	} while ((nu != 0) && (i < 12));

	do
	{
		i = i - 1;
		uartx_putc(UARTx, x[i]);
	} while (i > 0);
}

void uartx_puti(UARTx_t* UARTx, int32_t n)
{
	// Converts a signed 32-bit integer to a string and sends the string over the UART
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	n: the signed 32-bit integer to send
	// Returns: nothing

	uint32_t nu;

	if (n < 0) {
		uartx_putc(UARTx, '-');
		nu = -n;
	} else {
		nu = n;
	}

	uartx_putui(UARTx, nu);
}

void uartx_puth4(UARTx_t* UARTx, uint8_t n)
{
	// Converts an unsigned integer to a 4-bit (1-digit) hexadecimal string and sends the string over the UART. If the number is outside the bounds of a 4-bit unsigned integer, it is truncated.
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	n: the unsigned integer to send as a hexadecimal number
	// Returns: nothing

	n &= 0x0F;

	if (n > 9) {
		n += 7;
	}

	n += '0';
	uartx_putc(UARTx, n);
}

void uartx_puth8(UARTx_t* UARTx, uint8_t n)
{
	// Converts an unsigned integer to a 8-bit (2-digit) hexadecimal string and sends the string over the UART. If the number is outside the bounds of a 8-bit unsigned integer, it is truncated.
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	n: the unsigned integer to send as a hexadecimal number
	// Returns: nothing

	uartx_puth4(UARTx, n >> 4);
	uartx_puth4(UARTx, n);
}

void uartx_puth16(UARTx_t* UARTx, uint16_t n)
{
	// Converts an unsigned integer to a 16-bit (4-digit) hexadecimal string and sends the string over the UART. If the number is outside the bounds of a 16-bit unsigned integer, it is truncated.
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	n: the unsigned integer to send as a hexadecimal number
	// Returns: nothing

	uartx_puth8(UARTx, n >> 8);
	uartx_puth8(UARTx, n);
}

void uartx_puth32(UARTx_t* UARTx, uint32_t n)
{
	// Converts an unsigned integer to a 32-bit (8-digit) hexadecimal string and sends the string over the UART. If the number is outside the bounds of a 32-bit unsigned integer, it is truncated.
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	n: the unsigned integer to send as a hexadecimal number
	// Returns: nothing

	uartx_puth16(UARTx, n >> 16);
	uartx_puth16(UARTx, n);
}

void uartx_putuib8(UARTx_t* UARTx, uint8_t nu)
{
	// Converts an unsigned integer to a 8-bit (8-digit) binary string and sends the string over the UART. If the number is outside the bounds of a 8-bit unsigned integer, it is truncated.
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	n: the unsigned integer to send as a binary number
	// Returns: nothing

	int32_t i;
	for (i = 7; i > 0; i--)
	{
		if (nu >> i)
		{
			uartx_putc(UARTx, '1');
		}
		else
		{
			uartx_putc(UARTx, '0');
		}
	}
}

void uartx_putuib16(UARTx_t* UARTx, uint16_t nu)
{
	// Converts an unsigned integer to a 16-bit (16-digit) binary string and sends the string over the UART. If the number is outside the bounds of a 16-bit unsigned integer, it is truncated.
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	n: the unsigned integer to send as a binary number
	// Returns: nothing

	uartx_putuib8(UARTx, nu >> 8);
	uartx_putuib8(UARTx, nu);
}

void uartx_putuib32(UARTx_t* UARTx, uint32_t nu)
{
	// Converts an unsigned integer to a 32-bit (32-digit) binary string and sends the string over the UART. If the number is outside the bounds of a 32-bit unsigned integer, it is truncated.
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	n: the unsigned integer to send as a binary number
	// Returns: nothing
	
	uartx_putuib16(UARTx, nu >> 16);
	uartx_putuib16(UARTx, nu);
}

void uartx_putf(UARTx_t* UARTx, double val, uint8_t num_decimal_digits)
{
	// Converts a double to a string and sends the string over the UART, with num_decimal_digits digits after the decimal point.
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	val: the double to send as a string
	//	num_decimal_digits: The number of digits after the decimal point to send. If num_decimal_digits is less than the number of actual digits in the number, then the number will be rounded
	// Returns: nothing

	char buf[30];
	double_to_str(buf, val, num_decimal_digits);
	uartx_puts(UARTx, buf);
}

void uartx_pute(UARTx_t* UARTx, double val, uint8_t num_decimal_digits)
{
	// Converts a double to a string in scientific/exponential notation (e.g. "1.79e+3") and sends the string over the UART, with num_decimal_digits digits after the decimal point.
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	val: the double to send as a string
	//	num_decimal_digits: The number of digits after the decimal point to send. If num_decimal_digits is less than the number of actual digits in the number, then the number will be rounded
	// Returns: nothing

	char buf[30];
	double_to_str_exp(buf, val, num_decimal_digits);
	uartx_puts(UARTx, buf);
}

void uartx_getbytes(UARTx_t* UARTx, void* buf, uint32_t len)
{
	// Receives an array byte-by-byte over the UART until len bytes have been received, placing each received byte into buf
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	buf: The array to store the received bytes into. Size must be at least len.
	//	len: The number of bytes to receive
	// Returns: nothing

	uint32_t i;
	for (i = 0; i < len; i++)
	{
		((uint8_t*)buf)[i] = (uint8_t)uartx_getc(UARTx);
	}
	return;
}

uint8_t uartx_getbytes_until(UARTx_t* UARTx, void* buf, uint32_t len, uint8_t terminator)
{
	// Receives an array byte-by-byte over the UART until len bytes have been received or the terminator byte was received, placing each received byte into buf
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	buf: The array to store the received bytes into. Size must be at least len.
	//	len: The maximum number of bytes to receive
	//	terminator: When this byte is received, this function will stop receiving new bytes, even if len bytes have not been received. The terminator byte is placed in buf.
	// Returns: 1 if no terminator byte was found; 0 if a terminator byte was found

	uint32_t i;
	for (i = 0; i < len; i++)
	{
		uint8_t c = (uint8_t)uartx_getc(UARTx);
		((uint8_t*)buf)[i] = c;
		if (c == terminator)
		{
			return 0;
		}
	}
	return 1;
}

uint8_t uartx_gets_until(UARTx_t* UARTx, char* buf, uint32_t len, char terminator)
{
	// Receives a string character-by-character over the UART until len characters have been received or the terminator character (or a null terminator) was received, placing each received character into buf
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	buf: The string to store the received characters into. Size must be at least len + 1 (including null terminator).
	//	len: The maximum number of characters to receive (not including null terminator)
	//	terminator: When this character is received, this function will stop receiving new characters, even if len characters have not been received. The terminator character is not placed in buf.
	// Returns: 1 if no terminator character was found; 0 if a terminator character was found

	uint32_t i;
	for (i = 0; i < len; i++)
	{
		char c = uartx_getc(UARTx);
		if ((c == '\0') || (c == terminator))
		{
			buf[i] = '\0';
			return 0;
		}
		buf[i] = c;
	}
	buf[i] = '\0';
	return 1;
}

uint8_t uartx_getsln(UARTx_t* UARTx, char* buf, uint32_t len)
{
	// Receives a string character-by-character over the UART until len characters have been received or a newline character ('\n') or a null terminator was received, placing each received character into buf. Carriage return characters ('\r') are ignored and not placed in the string
	// Arguments:
	//	UARTx: a pointer to the desired UART peripheral base address (e.g. UART0, UART1, etc.)
	//	buf: The string to store the received characters into. Size must be at least len + 1 (including null terminator).
	//	len: The maximum number of characters to receive (not including null terminator)
	// Returns: 1 if no newline was found; 0 if a newline was found

	uint32_t i;
	for (i = 0; i < len; i++)
	{
		char c = uartx_getc(UARTx);
		if (c == '\r')
		{
			continue;
		}
		if ((c == '\0') || (c == '\n'))
		{
			buf[i] = '\0';
			return 0;
		}
		buf[i] = c;
	}
	buf[i] = '\0';
	return 1;
}

void printNumberUInt32(uint32_t nu)
{
	uart_putui(nu);
	uart_putc(' ');
}

void printNumberInt32(int32_t n)
{
	uart_puti(n);
	uart_putc(' ');
}



/** Function Definitions for UART0 **/
void uart_init_default(uint16_t baud_register_value)
{
	// Initialize the UART peripheral
	TX0_PxSEL |= TX0_BIT;
	RX0_PxSEL |= RX0_BIT;

	uartx_init_default(UART0, baud_register_value);
}

void uart_init_8N1(uint32_t smclk_freq, uint32_t baud)
{
	// Initialize the UART peripheral
	P1SEL |= TX0_BIT | RX0_BIT;	// Set the TX and RX pins to peripheral mode

	uartx_init_8N1(UART0, smclk_freq, baud);
}

void uart_putc(char c)
{
	uartx_putc(UART0, c);
}

char uart_getc()
{
	return uartx_getc(UART0);
}

char uart_getc_immediate()
{
	return uartx_getc_immediate(UART0);
}

void uart_putb(uint8_t byte)
{
	uartx_putb(UART0, byte);
}

uint8_t uart_getb()
{
	return uartx_getb(UART0);
}

uint8_t uart_getb_immediate()
{
	return uartx_getb_immediate(UART0);
}

uint8_t uart_transmitting()
{
	return uartx_transmitting(UART0);
}

uint8_t uart_available()
{
	return uartx_available(UART0);
}

void uart_puts(const void* str)
{
	uartx_puts(UART0, str);
}

void uart_putln()
{
	uartx_putln(UART0);
}

void uart_putsln(const void* str)
{
	uartx_putsln(UART0, str);
}

void uart_putui(uint32_t nu)
{
	uartx_putui(UART0, nu);
}

void uart_puti(int32_t n)
{
	uartx_puti(UART0, n);
}

void uart_puth4(uint8_t n)
{
	uartx_puth4(UART0, n);
}

void uart_puth8(uint8_t n)
{
	uartx_puth8(UART0, n);
}

void uart_puth16(uint16_t n)
{
	uartx_puth16(UART0, n);
}

void uart_puth32(uint32_t n)
{
	uartx_puth32(UART0, n);
}

void uart_putuib8(uint8_t nu)
{
	uartx_putuib8(UART0, nu);
}

void uart_putuib16(uint16_t nu)
{
	uartx_putuib16(UART0, nu);
}

void uart_putuib32(uint32_t nu)
{
	uartx_putuib32(UART0, nu);
}

void uart_putf(double val, uint8_t num_decimal_digits)
{
	uartx_putf(UART0, val, num_decimal_digits);
}

void uart_pute(double val, uint8_t num_decimal_digits)
{
	uartx_pute(UART0, val, num_decimal_digits);
}

void uart_getbytes(void* buf, uint32_t len)
{
	uartx_getbytes(UART0, buf, len);
}

uint8_t uart_getbytes_until(void* buf, uint32_t len, uint8_t terminator)
{
	return uartx_getbytes_until(UART0, buf, len, terminator);
}

uint8_t uart_gets_until(char* buf, uint32_t len, char terminator)
{
	return uartx_gets_until(UART0, buf, len, terminator);
}

uint8_t uart_getsln(char* buf, uint32_t len)
{
	return uartx_getsln(UART0, buf, len);
}



#ifdef UART1_BASE
/** Function Definitions for UART0 **/
void uart1_init_default(uint16_t baud_register_value)
{
	// Initialize the UART peripheral
	TX1_PxSEL |= TX1_BIT;
	RX1_PxSEL |= RX1_BIT;

	uartx_init_default(UART1, baud_register_value);
}

void uart1_init_8N1(uint32_t smclk_freq, uint32_t baud)
{
	// Initialize the UART peripheral
	P1SEL |= TX0_BIT | RX0_BIT;	// Set the TX and RX pins to peripheral mode

	uartx_init_8N1(UART1, smclk_freq, baud);
}

void uart1_putc(char c)
{
	uartx_putc(UART1, c);
}

char uart1_getc()
{
	return uartx_getc(UART1);
}

char uart1_getc_immediate()
{
	return uartx_getb_immediate(UART1);
}

void uart1_putb(uint8_t byte)
{
	uartx_putb(UART1, byte);
}

uint8_t uart1_getb()
{
	return uartx_getb(UART1);
}

uint8_t uart1_getb_immediate()
{
	return uartx_getb_immediate(UART1);
}

uint8_t uart1_transmitting()
{
	return uartx_transmitting(UART1);
}

uint8_t uart1_available()
{
	return uartx_available(UART1);
}

void uart1_puts(const void* str)
{
	uartx_puts(UART1, str);
}

void uart1_putln()
{
	uartx_putln(UART1);
}

void uart1_putsln(const void* str)
{
	uartx_putsln(UART1, str);
}

void uart1_putui(uint32_t nu)
{
	uartx_putui(UART1, nu);
}

void uart1_puti(int32_t n)
{
	uartx_puti(UART1, n);
}

void uart1_puth4(uint8_t n)
{
	uartx_puth4(UART1, n);
}

void uart1_puth8(uint8_t n)
{
	uartx_puth8(UART1, n);
}

void uart1_puth16(uint16_t n)
{
	uartx_puth16(UART1, n);
}

void uart1_puth32(uint32_t n)
{
	uartx_puth32(UART1, n);
}

void uart1_putuib8(uint8_t nu)
{
	uartx_putuib8(UART1, nu);
}

void uart1_putuib16(uint16_t nu)
{
	uartx_putuib16(UART1, nu);
}

void uart1_putuib32(uint32_t nu)
{
	uartx_putuib32(UART1, nu);
}

void uart1_putf(double val, uint8_t num_decimal_digits)
{
	uartx_putf(UART1, val, num_decimal_digits);
}

void uart1_pute(double val, uint8_t num_decimal_digits)
{
	uartx_pute(UART1, val, num_decimal_digits);
}

void uart1_getbytes(void* buf, uint32_t len)
{
	uartx_getbytes(UART1, buf, len);
}

uint8_t uart1_getbytes_until(void* buf, uint32_t len, uint8_t terminator)
{
	return uartx_getbytes_until(UART1, buf, len, terminator);
}

uint8_t uart1_gets_until(char* buf, uint32_t len, char terminator)
{
	return uartx_gets_until(UART1, buf, len, terminator);
}

uint8_t uart1_getsln(char* buf, uint32_t len)
{
	return uartx_getsln(UART1, buf, len);
}
#endif	// #ifdef UART1_BASE
