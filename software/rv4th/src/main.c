// VestaRV: rv4th monitor application entry point
// Clocks MCLK and SMCLK from HFXT, powers on all memory, brings up UART0 at 115200 baud, then runs the rv4th Forth interpreter forever.
// The baud constant assumes HFXT is exactly 24 MHz.

#include <MemoryMap.h>
#include <rv4th.h>
#include <uart.h>
#include <flash_memory.h>

#define SMCLK_FREQUENCY 24000000UL
#define BAUDRATE 115200UL

const char chip_id[] = {
	ASIC_NAME
	":\n"
	"- Balkir\n"
	"- Gharzai\n"
	"- Hoffman\n"
	"- Murray\n"
	"- Schemm\n"
	"- Schmitz\n"
	"- White\n"
};

int main()
{
	// Init clocks
	SYSCLKCR = 0
		// | CLKOSSEL_CPU	// The CLKO pin outputs the CPU clock
		| SMCLKSEL_HFXT	// SMCLK is sourced from HFXT
		| MCLKSEL_HFXT	// MCLK is sourced from HFXT
	;
	CLKDIVCR = 0
		| SMCLKDIV_1	// No division for SMCLK
		| MCLKDIV_1		// No division for MCLK
	;

	// Power on all of the memory
	MEMPWRCR = 0;
	
	// Init UART
	uart_init_default(UART_CALC_BR(SMCLK_FREQUENCY, BAUDRATE));

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
