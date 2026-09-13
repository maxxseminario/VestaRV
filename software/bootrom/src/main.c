// VestaRV: single-hart boot ROM entry point, reached from start.S when the BOOT pin selects the monitor.
// MCLK and SMCLK are both sourced from HFXT so UART0's baud is known at reset; the hard-coded
// UART0BR assumes HFXT is 24 MHz for 115200 baud. Other HFXT frequencies still yield standard
// bauds (16 MHz gives 76800, 48 MHz gives 230400), so a board change moves the console rate
// rather than breaking it. main() never returns: it re-enters rv4th_init/processLoop forever,
// and the monitor returns only when the `bye` word is executed.

#include <myshkin.h>
#include <rv4th.h>
#include <uart.h>
#include <flash_memory.h>


#define HFXT_FREQUENCY 24000000UL	// HFXT is the clock going into the UART
#define BAUDRATE 115200UL

const char chip_id[] = {
	ASIC_NAME
	":\n"
	"- Seminario\n"
};



int main()
{
	// Both clocks come from HFXT, which is what makes the boot baud rate known.
	SYSCLKCR = 0
		| SMCLKSEL_HFXT	// SMCLK is sourced from HFXT
		| MCLKSEL_HFXT	// MCLK is sourced from HFXT
	;
	CLKDIVCR = 0
		| SMCLKDIV_1	// No division for SMCLK
		| MCLKDIV_1		// No division for MCLK
	;

	// Power on all of the memory
	MEMPWRCR = 0;
	
	// 115200 at HFXT = 24 MHz. The UART0BR value is fixed, so the console rate tracks HFXT:
	// 62.5 kHz, 125 kHz, 250 kHz, 375 kHz, 500 kHz, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48
	// and 96 MHz all still give a standard baud.
	uart_init_default(UART_CALC_BR(HFXT_FREQUENCY, BAUDRATE));

	// The monitor is restarted whenever it returns. rv4th_processLoop returns the top of the
	// math stack, so typing `42 bye` at the console prints the chip identification string.
	int16_t x;

	while (1)
	{
		rv4th_init();
		x = rv4th_processLoop();

		if (x == 42)
		{
			printStringln((char *)chip_id);
		}
	}

	return 0;
}
