/** Includes **/
#include <MemoryMap.h>
#include <uart_irq.h>
#include <irq.h>



/** Interrupt Service Routine Declaration Macros **/
RVISR(IRQ_UART0_VECTOR, ISR_UART0)



/** Defines **/
#define UART_RX_BUFFER_LENGTH	(64)
#define UART_TX_BUFFER_LENGTH	(64)



/** Private Variables **/
static volatile uint8_t uart_ready_to_transmit = 1;

static char uart_rx_buffer[UART_RX_BUFFER_LENGTH];
static volatile uint32_t uart_rx_buffer_head = 0;
static volatile uint32_t uart_rx_buffer_tail = 0;

static char uart_tx_buffer[UART_TX_BUFFER_LENGTH];
static volatile uint32_t uart_tx_buffer_head = 0;
static volatile uint32_t uart_tx_buffer_tail = 0;



/** Function Declarations **/
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



/** Function Definitions **/
void uart_init_default(uint16_t baud_register_value)
{
	// Initialize the UART peripheral
	P1SEL |= TX0_BIT | RX0_BIT;	// Set the TX and RX pins to peripheral mode

	UART0BR = baud_register_value;
	UART0CR = 0
		| UEN		// Enable UART
		// | UPEN	// Enable parity bit
		// | UPODD	// Set to odd parity
		| URCIE	// Enable receive complete interrupt
		| UTEIE	// Enable transmit register empty interrupt
		// | UTCIE	// Enable transmit complete interrupt
		;

	// Switch SMCLK to use the 32 kHz crystal in general,
	// use VFO for IRQs
	// TODO: Do the clocking!!!
	//CLK_CR = CLK_IRQ_VCFO | CLK_VFO | SMCLK_LFX;

	// Read the status register to clear UTEIF (transmit buffer empty) and UTCIF (transmission complete)
	UART0SR;

	// Read the receive buffer register to clear UOVF (receive overflow), URCIF (receive complete), UPEF (parity error), and UFEF (framing error)
	UART0RX;

	// Reset the RX and TX buffers
	uart_ready_to_transmit = 1;
	uart_rx_buffer_head = 0;
	uart_rx_buffer_tail = 0;
	uart_tx_buffer_head = 0;
	uart_tx_buffer_tail = 0;

	// Enable UART0 interrupts
	set_IRQ_disable_mask(get_IRQ_disable_mask() & ~(1 << IRQ_UART0_VECTOR));
}

void uart_putchar(char c)
{
	// Wait until the TX buffer is not full
	while (uart_bytes_in_tx_buffer() >= (UART_TX_BUFFER_LENGTH - 1)) {}

	// If the TX buffer has 0 bytes in it and the transmitter is not transmitting, send the byte (indicated by uart_ready_to_transmit)
	if (uart_ready_to_transmit)
	{
		uart_ready_to_transmit = 0;
		UART0TX = c;
	}
	else
	{
		// Push the new char to the TX buffer
		uart_tx_buffer[uart_tx_buffer_tail] = c;
		uart_tx_buffer_tail = (uart_tx_buffer_tail + 1) % UART_TX_BUFFER_LENGTH;
	}
	
	return;
}

char uart_getchar()
{
	// Wait for the UART to have at least one character in the RX buffer
	while (uart_rx_buffer_head == uart_rx_buffer_tail) { }
	
	// Return the next character in the RX buffer
	return uart_rx_buffer[uart_rx_buffer_head++];
}

void uart_read(char *str, uint32_t len)
{
	// Reads len bytes from the UART and puts them into str, putting a null terminator \0 at the end of str. Note that str must have at least len + 1 bytes allocated to it.
	uint32_t i;
	for (i = 0; i < len; i++)
	{
		str[i] = uart_getchar();
	}
	str[i] = '\0';
}

uint32_t uart_read_until(char *str, char terminator, uint32_t max_len)
{
	// Reads bytes from the UART into str until either the terminator char is found or max_len bytes are placed into str, putting a null terminator \0 at the end of str. Returns the number of chars placed into str. Note that str must have at least max_len + 1 bytes allocated to it.
	if (max_len == 0)
		return 0;
	
	uint32_t i = 0;
	char c;
	do
	{
		c = uart_getchar();
		str[i] = c;
		i++;
	}
	while ((c != terminator) && (i < max_len));
	str[i] = '\0';
	return i;
}

uint32_t uart_bytes_in_rx_buffer()
{
	if (uart_rx_buffer_head > uart_rx_buffer_tail)
	{
		return UART_RX_BUFFER_LENGTH + uart_rx_buffer_tail - uart_rx_buffer_head;
	}
	else
	{
		return uart_rx_buffer_tail - uart_rx_buffer_head;
	}
	
}

uint32_t uart_bytes_in_tx_buffer()
{
	if (uart_tx_buffer_head > uart_tx_buffer_tail)
	{
		return UART_TX_BUFFER_LENGTH + uart_tx_buffer_tail - uart_tx_buffer_head;
	}
	else
	{
		return uart_tx_buffer_tail - uart_tx_buffer_head;
	}
	
}

uint8_t uart_transmitting()
{
	return (uart_tx_buffer_head != uart_tx_buffer_tail);
}

uint8_t uart_available()
{
	return (UART0SR & URCIF) != 0;
}

void printString(char *s)
{
	uint32_t i = 0;
	char c = s[0];
	while (c != '\0')
	{
		uart_putchar(c);
		i++;
		c = s[i];
	}
	
	return;
}

void printNewline()
{
	uart_putchar('\n');
}

void printStringln(char *s)
{
	printString(s);
	printNewline();
}

void printNumberUInt32(uint32_t nu)
{
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
		uart_putchar(x[i]);
	} while (i > 0);

	uart_putchar(' ');
}

void printNumberInt32(int32_t n)
{
	uint32_t nu;

	if (n < 0) {
		uart_putchar('-');
		nu = -n;
	} else {
		nu = n;
	}

	printNumberUInt32(nu);
}

void printHex4(uint8_t n)
{
	n &= 0x0F;

	if (n > 9) {
		n += 7;
	}

	n += '0';
	uart_putchar(n);
}

void printHex8(uint8_t n)
{
	printHex4(n >> 4);
	printHex4(n);
}

void printHex16(uint16_t n)
{
	printHex8(n >> 8);
	printHex8(n);
}

void printHex32(uint32_t n)
{
	printHex16(n >> 16);
	printHex16(n);
}

uint8_t hex4ToNum(char hex4)
{
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



/** Interrupt Service Routines **/
void ISR_UART0()
{
	// Get the current value of the status register
	// Reading the status register clears UTEIF (transmit buffer empty flag) and UTCIF (transmit complete flag) in the status register
	uint8_t status_register = UART0SR;

	// Look for any new RX data
	if (status_register & URCIF)
	{
		// There is a new byte in the UARTxRX register. Put it in the RX buffer.
		// Reading the UARTxRX register clears UFEF (framing error flag), UPEF (parity error flag), UOVF (overflow flag), and URCIF (receive complete flag) in the status register
		uart_rx_buffer[uart_rx_buffer_tail] = UART0RX;
		uart_rx_buffer_tail = (uart_rx_buffer_tail + 1) % UART_RX_BUFFER_LENGTH;
	}
	
	// Look to see if the transmit buffer register is empty
	if (status_register & UTEIF)
	{
		// The transmit buffer register is empty and ready to accept a new byte
		// Does the TX buffer have another byte to push to the transmit register?
		if (uart_tx_buffer_head != uart_tx_buffer_tail)
		{
			// Transmit the next byte in the TX buffer
			UART0TX = uart_tx_buffer[uart_tx_buffer_head];
			uart_tx_buffer_head = (uart_tx_buffer_head + 1) % UART_TX_BUFFER_LENGTH;
		}
		else
		{
			// No more bytes to push to the transmit register
			uart_ready_to_transmit = 1;
		}
		
	}

	// All interruptable flags will have been cleared by this point
}
