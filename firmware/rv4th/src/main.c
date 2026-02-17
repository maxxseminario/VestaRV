/** Includes **/
#include <MemoryMap.h>
#include <rv4th.h>
#include <uart.h>
#include <flash_memory.h>



/** Defines **/

// Baud rate generation defines
#define SMCLK_FREQUENCY 24000000UL	// The clock going into the UART
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




/*
 * Re-define the startup/reset behavior to this.  GCC normally uses this
 * opportunity to initialize all variables (bss) to zero.
 *
 * By doing this, we take all initialization into our own hands.
 *
 *      YE BE WARNED
 */
//void __attribute__ ((naked)) _reset_vector__(void) {
//  __asm__ __volatile__("mov #0xff00,r1"::);
//  __asm__ __volatile__("br #main"::);
//}



/** Main Function **/
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
