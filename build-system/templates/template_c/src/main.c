/** Includes **/
#include <MemoryMap.h>



/** Defines **/



/** Global Variables **/



/** Interrupt Service Routine Declaration Macros **/
//RVISR(IRQ_name_VECTOR, ISR_name)



/** Function Declarations **/



/** Main Function **/
int main()
{
	// Power down the ROM
	MEMPWRCR |= ROMOFF;
	
	// Put your code here

	return 0;
}



/** Function Definitions **/



/** Interrupt Service Routines **/
/*
void ISR_name()
{

}
*/
