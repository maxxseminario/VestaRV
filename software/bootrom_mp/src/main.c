// VestaRV: boot ROM C entry point
// Clocks MCLK and SMCLK from HFXT, powers on all memory, brings up UART0 at 115200 baud, then runs the rv4th Forth monitor forever.
// The hard-coded UART0BR assumes HFXT is exactly 24 MHz. Other common oscillator frequencies still land on standard rates with the same setting: 16 MHz gives 76800, and 62.5 kHz through 96 MHz in the 1/1.5/2/3 family all divide cleanly.

// #include <MemoryMap.h>
#include <myshkin.h>
#include <rv4th.h>
#include <uart.h>
#include <flash_memory.h>




#define HFXT_FREQUENCY 24000000UL	// the clock going into the UART
#define BAUDRATE 115200UL

const char chip_id[] = {
	ASIC_NAME
	":\n"
	"- Seminario\n"
};



int main()
{
	// Both MCLK and SMCLK run from HFXT, so the UART has a known baud rate on boot.
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
	
	uart_init_default(UART_CALC_BR(HFXT_FREQUENCY, BAUDRATE));

	// rv4th_processLoop() returns on the "exit" word, on EOT (0x04) and on 0xff in the input.
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
