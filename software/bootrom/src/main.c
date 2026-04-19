/** Includes **/
// #include <MemoryMap.h>
#include <myshkin.h>
#include <rv4th.h>
#include <uart.h>
#include <flash_memory.h>



/** Defines **/

// Baud rate generation defines
//#define LFXT_FREQUENCY	32768UL	// The frequency of LFXT
#define HFXT_FREQUENCY 24000000UL	// The frequency of HFXT, the clock going into the UART
#define BAUDRATE 115200UL	// TODO: NOTE: changed from previous version!

const char chip_id[] = {
	ASIC_NAME
	":\n"
	"- Seminario\n"
};



/** Main Function **/
int main()
{
	// Init clocks (MCLK uses the high frequency external clock, while SMCLK uses the low frequency 32.768 kHz external clock. This allows the UART to have a known baud rate on boot)
	SYSCLKCR = 0
		//| CLKOSSEL_CPU	// The CLKO pin outputs the CPU clock
		//| SMCLKSEL_LFXT	// SMCLK is sourced from LFXT
		| SMCLKSEL_HFXT	// SMCLK is sourced from HFXT (TODO: NOTE: changed from previous version!)
		| MCLKSEL_HFXT	// MCLK is sourced from HFXT
	;
	CLKDIVCR = 0
		| SMCLKDIV_1	// No division for SMCLK
		| MCLKDIV_1		// No division for MCLK
	;

	// Power on all of the memory
	MEMPWRCR = 0;
	
	// Init UART
	// TODO: NOTE: WARNING: This was changed from the previous versions! It used to be that SMCLK would be sourced by LFXT (at 32.768 kHz) to give a baud of 2048. However, to ensure compatibility with all Linux/Windows/macOS serial port drivers, this has been changed to a standard baudrate of 115200. This will prevent a lot of issues down the road with driver support. However, the main drawback is that it assumes HFXT will be exactly 24 MHz to produce the correct baud. Fortunately, if you do use a different frequency for HFXT, most off-the-shelf oscillators give a frequency that will still produce a standard baud using this same hard-coded setting for UART0BR. For example, if HFXT is 16 MHz, the baud would become 76800, a standard baud. A non-exhaustive list of valid HFXT frequencies: 62.5 kHz, 125 kHz, 250 kHz, 375 kHz, 500 kHz, 1 MHz, 1.5 MHz, 2 MHz, 3 MHz, 4 MHz, 6 MHz, 8 MHz, 12 MHz, 16 MHz, 24 MHz, 32 MHz, 48 MHz, 96 MHz.
	uart_init_default(UART_CALC_BR(HFXT_FREQUENCY, BAUDRATE));

	/*
	 * Startup and run rv4th interp.
	 *
	 * See config_default_rv4th() and "test4th.c" for examples of
	 * re-configuring the program vector sizes and providing I/O functions.
	 *
	 * The following make processLoop() return:
	 *  - executing the "exit" word
	 *  - any EOT character in the input ('^D', control-D, 0x04)
	 *  - any 0xff character in the input
	 */
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
