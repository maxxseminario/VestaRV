/** Includes **/
#include <MemoryMap.h>



/** Defines **/



/** Global Variables **/



/** Interrupt Service Routine Declaration Macros **/
//RVISR(IRQ_name_VECTOR, ISR_name)



/** Function Declarations **/



/** Main Function **/
// C++ includes name mangling, so any function that it is necessary to preserve the name in a global scope must have a prefix of extern "C" to prevent name mangling, including the main function
extern "C" int main()
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
