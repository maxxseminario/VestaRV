/*
 *  rv4th
 *
 *  forth-like interpreter for the msp430
 *
 *  Source originally from Mark Bauer, beginning life in the z80 and earlier.
 *  Nathan Schemm used and modified for use in his series of msp430-compatible
 *  processors.
 *
 *  This version by Dan White (2013).  Cleaned-up, expanded, and given
 *  capabilities to allow live re-configuration and directly calling user C
 *  functions.
 *
 *  * Used in Dan's "atoi" chip loaded from flash into RAM.
 *  * Fabbed in ROM as part of the Gharzai/Schmitz "piranha" imager chip.
 *  * Fabbed in ROM as part of the Schmitz/Gharzai "cheetah" chip.
 *  * Fabbed in ROM as part of the Schmitz/Murray "War Bonnet" chip.
 *
 *  If cpp symbol "MSP430" is not defined, it compiles to a version for testing
 *  on PC as a console program via the setup and main() in "test430.c".
 *
 * TODO ideas:
 *  - use enum/symbols for VM opcodes (?builtins tagged as negative numbers?)
 *
 */


/** Includes **/
// #include <MemoryMap.h>
#include <myshkin.h>
#include <rv4th.h>
#include <uart.h>
#include <spi.h>
#include <flash_memory.h>



/** Defines **/
#define MATH_STACK_SIZE 512	// * 4 bytes
#define ADDR_STACK_SIZE 512	// * 4 bytes

//total length of all user programs in opcodes
#define USER_PROG_SIZE 4096	// * 2 bytes

//max number of user-defined words
#define USER_OPCODE_MAPPING_SIZE 128	// * 2 bytes

//total string length of all word names (+ 1x<space> each)
#define USER_CMD_LIST_SIZE 2048	// * 1 byte

//maximum input line length
#define LINE_BUFFER_SIZE 1024	// * 1 byte

//maximum word character width
#define WORD_BUFFER_SIZE 64	// * 1 byte

// our "special" pointer, direct word access to all absolute address space
#define dirMemory ((int32_t *) 0)



/** Global Variables **/

/****************************************************************************
 *
 * Module-level global variables (in RAM)
 *
 ***************************************************************************/
__attribute__ ((section(".noinit"))) int16_t xit;  // set to 1 to kill program
__attribute__ ((section(".noinit"))) int16_t echo; // boolean: false -> no interactive echo/prompt

__attribute__ ((section(".noinit"))) uint16_t progCounter;  // value determines builtin/user and opcode to execute

__attribute__ ((section(".noinit"))) int16_t lineBufferIdx; // input line buffer index
__attribute__ ((section(".noinit"))) int16_t progIdx;       // next open space for user opcodes
__attribute__ ((section(".noinit"))) int16_t cmdListIdx;    // next open space for user word strings

/*
 * The ".noinit" section should be placed so these vectors are the last part
 * of allocated RAM.  All space beyond, up until 0xff00, is empty or unused.
 * This keeps all the rv4th global variables in RAM in one continuous block.
 */
__attribute__ ((section(".noinit"))) int32_t mathStackArray[MATH_STACK_SIZE];
__attribute__ ((section(".noinit"))) int32_t addrStackArray[ADDR_STACK_SIZE];
__attribute__ ((section(".noinit"))) int32_t progArray[USER_PROG_SIZE];	// NOTE: changed from int16_t to int32_t to fix a bug that would create undefined upper 16 bits in numeric text values defined within a user-defined function.
__attribute__ ((section(".noinit"))) int16_t progOpcodesArray[USER_OPCODE_MAPPING_SIZE];
__attribute__ ((section(".noinit"))) char cmdListArray[USER_CMD_LIST_SIZE];
__attribute__ ((section(".noinit"))) char lineBufferArray[LINE_BUFFER_SIZE];
__attribute__ ((section(".noinit"))) char wordBufferArray[WORD_BUFFER_SIZE];

/* The following allow re-configuring the location/size of all configurable
 * arrays.  Then the stack sizes and user program space sizes can be
 * (re-)specified by changing the table and calling rv4th_init() again.  See
 * test430.c for a configuration example.
 *
 * THE ONLY BOUNDARY CHECKS ARE:
 *  - math stack underflow
 *  - line buffer overflow
 *  - word buffer overflow
 *
 * The user is therefore responsible for:
 *  - keeping stack depths in range
 *  - not underflowing the address stack
 *  - allocating sufficient space in prog[], progOpcodes[], cmdList[]
 */
__attribute__ ((section(".noinit"))) int32_t *mathStackPtr;
__attribute__ ((section(".noinit"))) int32_t *addrStackPtr;

__attribute__ ((section(".noinit"))) int32_t *mathStackStart;	// original locations for calculating stack depth
__attribute__ ((section(".noinit"))) int32_t *addrStackStart;

__attribute__ ((section(".noinit"))) int32_t *prog;	// user programs (opcodes) are placed here	NOTE: changed from int16_t to int32_t to fix a bug that would create undefined upper 16 bits in numeric text values defined within a user-defined function.

__attribute__ ((section(".noinit"))) int16_t *progOpcodes;	// mapping between cmdList word index and program. opcodes start index into prog[]

__attribute__ ((section(".noinit"))) char *cmdList;	// string containing user-defined words
__attribute__ ((section(".noinit"))) char *lineBuffer;	// where interactive inputs are buffered
__attribute__ ((section(".noinit"))) char *wordBuffer;	// the currently-parsed word


__attribute__ ((section(".noinit"))) uint8_t flash_is_initialized;	// A boolean value if the SPI flash has been initialized or not




/****************************************************************************
 *
 * Module-level global constants (in ROM)
 *
 ***************************************************************************/

// The order matches the execVM function and determines the opcode value.
// NOTE: must end in a space !!!!
const char cmdListBi[] = {
	"bye + - * /% "						// 1 -> 5
	". dup drop swap < "				// 6 -> 10
	"> == hb. gw dfn "					// 11 -> 15
	"abs , p@ p! not "					// 16 -> 20
	"list if then else begin "			// 21 -> 25
	"until depth h. ] num "				// 26 -> 30
	"push0 goto exec lu pushn "			// 31 -> 35
	"over push1 pwrd emit ; "			// 36 -> 40
	"@ ! h@ do loop "					// 41 -> 45
	"+loop i j k ~ "					// 46 -> 50
	"^ & | */ key "						// 51 -> 55
	"cr *2 /2 call0 call1 "				// 56 -> 60
	"call2 call3 call4 ndrop swpb "		// 61 -> 65
	"+! roll pick tuck max "			// 66 -> 70
	"min s. sh. neg echo "				// 71 -> 75
	"init o2w o2p rst clk "				// 76 -> 80
	"fr fw fe fem sbi "					// 81 -> 85
	"cbi mask and or swphw "			// 86 -> 90
	"sll srl mr mw ms "					// 91 -> 95
};
#define LAST_PREDEFINED 94	// update this when we add commands to the built in list

#define BUILTIN_OPCODE_OFFSET 20000
#define BUILTIN_INTERP_OFFSET 10000

// these commands are interps
const char cmdListBi2[] = {"[ : var "};

// these values point to where in progBi[] these routines start
const int16_t cmdList2N[] = {0,10000,10032,10135};  // need an extra zero at the front


// to flag the initial built in functions from the rest, save the negative of them in the program space (prog).

const int16_t progBi[] = { // address actually start at 10000

   // this is the monitor in compiled forth code (by hand)

   20025,        //   0 begin
   20014,        //   1 gw      get word
   20030,        //   2 num     test if number
   20022,10008,  //   3 if

   20031,        //   5 push0    push a zero on math stack
   20032,10030,  //   6 goto     jump to until function

   20008,        //   8 drop
   20034,        //   9 lu       look up word
   20022,10026,  //  10 if       did we find the word in the dictionary

   20035,']',    //  12 pushn    next value on math stack  look for ]

   20036,        //  14 over
   20012,        //  15 equal    test if function was a ']'
   20022,10022,  //  16 if

   20008,        //  18 drop     it was the ']' exit function
   20037,        //  19 push1    put a true on the math stack
   20032,10030,  //  20 goto     jump to until func

   20033,        //  22 exec     execute the function on the math stack (it is a call so we return to here)
   20031,        //  23 push0
   20032,10030,  //  24 goto     jump to until func

   // undefined string

   20035,'?',    //  26 pushn    put the '?' on math stack
   20039,        //  28 emit     output the ? to the terminal
   20031,        //  29 push0

   20026,        //  30 until
   20040,        //  31 return function



   // this is the ':' function hand compiled

   20035,0x5555, //  32 just push a known value on the stack, will test at the end
   20014,        //  34 get a word from the input

   20015,        //  35 define it
   20025,        //  36 begin

   20014,        //  37 get a word
   20030,        //  38 see if number
   20022,10047,  //  39 if

   // it is a number

   20035,20035,  //  41 put the push next number opcode on stack
   20017,        //  43 put that opcode in the def
   20017,        //  44 put the actual value next	NOTE: This is where the bug that makes any number typed within a user-defined (interpreted) function to have undefined upper 16 bits occurs. The number, which during definition has already been parsed and pushed to the math stack, is now popped off the math stack and placed into the compiled prog array. The bug is two-fold: if the prog array is only 16 bits, or the pushn function only allows 16-bit numbers, the number will fail to be placed in the compiled prog array correctly.
   20031,        //  45 push 0
   20026,        //  46 until     // we can have many untils for one begin

   // wasn't a number, we need to test for many other things

   20008,        //  47 drop
   20034,        //  48 look in dictionary
   20020,        //  49 not


   20022,10058,  //  50 if        not found .... let them know and just ignore
   20035,'?',    //  52 push a '?' on the stack
   20039,        //  54 emit
   20038,        //  55 tell them what we couldn't find
   20031,        //  56 push0
   20026,        //  57 until

   // we found it in the dictionary

   20035,20022,  //  58 pushn     see if it is an if function
   20036,        //  60 over
   20012,        //  61 equal
   20022,10070,  //  62 if

   // it is an if function

   20017,        //  64 append the if statement to the stack (it was still on the stack
   20043,        //  65 h@ get location of next free word
   20007,        //  66 dup    ( leave a copy on the math stack for the "then" statement
   20017,        //  67 append it to memory
   20031,        //  68 push0
   20026,        //  69 until

   // **********************

   20035,20024,  //  70 pushn     see if it is an "else" function
   20036,        //  72 over
   20012,        //  73 equal
   20022,10088,  //  74 if

	//  it is an "else" statement

   20035,20032,  //  76 push a goto command on the math stack
   20017,        //  78 append it to the program
   20043,        //  79 h@ get location of next free word
   20009,        //  80 swap
   20017,        //  81 append
   20009,        //  82 swap
   20043,        //  83 h@
   20009,        //  84 swap
   20019,        //  85 !    this will be in prog space
   20031,        //  86 push0
   20026,        //  87 until

   // *******************************

   20035,20023,  //  88 pushn    see if it is a "then" function

   20036,        //  90 over
   20012,        //  91 equal    test if function was a 'then'
   20022,10100,  //  92 if

	  // it is a "then"

   20008,        //  94 drop
   20043,        //  95 h@
   20009,        //  96 swap
   20019,        //  97 !
   20031,        //  98 push0
   20026,        //  99 until

   // *********************************

   20035,10001,  // 100 pushn    see if it is a "[" function

   20036,        // 102 over
   20012,        // 103 equal
   20022,10109,  // 104 if

	  // it is a "["

   10001,        // 106 recurse into the monitor
   20031,        // 107 push0
   20026,        // 108 until

   // ********************************************

   20035,20040,  // 109 pushn    next value on math stack  look for built in func ';'

   20036,        // 111 over
   20012,        // 112 equal    test if function was a ';'
   20020,        // 113 not
   20022,10119,  // 114 if

		 // this must be just an ordinary function ..... just push it in the prog

   20017,        // 116 append
   20031,        // 117 push0
   20026,        // 118 until

   //  must be the ';'

   20017,        // 119 append return function to prog

   20035,0x5555, // 120 just push a known value on the stack, will test at the end
   20012,        // 122 equal
   20020,        // 123 not
   20022,10132,  // 124 if

   20035,'?',    // 126 push a '?' on the stack
   20039,        // 128 emit
   20035,'s',    // 129 push a 's' on the stack
   20039,        // 131 emit

   20037,        // 132 push1
   20026,        // 133 until
   20040,        // 134 return


   // ***********************************************
   // var    create a variable

   20043,        // 135 get address of variable
   20031,        // 136 push0
   20017,        // 137 append  ","

   20014,        // 138 get a word from the input
   20015,        // 139 define it
   20035,20035,  // 140 put the push next number opcode on stack
   20017,        // 142 append the pushn instruction
   20017,        // 143 append the address we want to push
   20035,20040,  // 144 put a return instruction on stack
   20017,        // 146 put the return instruction in prog
   20040,        // 147 return

   };



/****************************************************************************
 *
 * Local function prototypes
 *
 * xFunc() are closely related to opcodes
 *
 * Note: push/pop and such may be candidates for making non-static (public)
 ***************************************************************************/
/****************************************************************************
 * Stack implementation
 ***************************************************************************/
static void pushMathStack(int32_t n);
static int32_t popMathStack();
static void ndrop(int32_t n);

static void pushAddrStack(int32_t n);
static int32_t popAddrStack();
static void ndropAddr(int32_t n);

/****************************************************************************
 * Line input handling
 ***************************************************************************/
static char getKeyB(void);
static void getLine(void);
static char nextPrintableChar(void);
static char skipStackComment(void);

/****************************************************************************
 * Word buffer usage
 ***************************************************************************/
static int16_t lookupToken(char *x, char *l);
static void dfnFunc(void);
static void getWordFunc(void);
static void luFunc(void);
static void numFunc(void);

/****************************************************************************
 * Terminal output effects
 ***************************************************************************/
static void listFunc(void);
static void opcode2wordFunc(void);

/****************************************************************************
 * Other helpers
 ***************************************************************************/
static void execFunc(void);
static void ifFunc(int16_t x);
static void loopFunc(int16_t n);
static void opcode2progFunc(void);
static void pushnFunc(void);
static void rollFunc(int16_t n);

static void flashReadFunc(uint32_t start_address, uint32_t length, int32_t bin_payload);
static void flashWritePageFunc(uint32_t page_address, int32_t bin_payload);
static uint8_t flashErasePageFunc(uint32_t page_address, int32_t confirmation_key);
static uint8_t flashEraseMultiplePagesFunc(uint32_t start_page_address, uint32_t length, int32_t confirmation_key);
static uint32_t clkMeasureFunc(uint8_t clock_select, uint8_t measurement_time_select);
static void memoryReadFunc(uint32_t start_address, uint32_t length, int32_t mode);
static void memoryWriteFunc(uint32_t start_address, uint32_t length, uint32_t bin_payload);
static void memorySetFunc(uint32_t start_address, uint32_t length, uint8_t set_byte);

/****************************************************************************
 * VM opcode execution
 ***************************************************************************/
static void execVM(int16_t opcode);

/****************************************************************************
 * Stack implementation
 ***************************************************************************/
#define TOS (*mathStackPtr)
#define NOS (*(mathStackPtr + 1))
#define STACK(n) (*(mathStackPtr + n))

void pushMathStack(int32_t n)
{
	mathStackPtr--;
	*mathStackPtr = n;
}


int32_t popMathStack()
{
	int32_t i;

	i = *mathStackPtr;

	/* prevent stack under-flow
	 * *** this is the ONLY stack checking in rv4th and is only here
	 * to avoid crashing things when a human pops/prints too much.  Words
	 * are expected to properly handle the stack.
	 * */
	if (mathStackPtr < mathStackStart) {
		mathStackPtr++;
	}

	return(i);
}


void ndrop(int32_t n)
{
	mathStackPtr += n;

	if (mathStackPtr > mathStackStart) {
		mathStackPtr = mathStackStart;
	}
}


#define ATOS (*addrStackPtr)
#define ANOS (*(addrStackPtr + 1))
#define ASTACK(n) (*(addrStackPtr + n))

void pushAddrStack(int32_t n)
{
	addrStackPtr--;
	*addrStackPtr = n;
}


int32_t popAddrStack(void)
{
	int32_t i;
	i = *addrStackPtr;
	addrStackPtr++;
	return(i);
}


void ndropAddr(int32_t n)
{
	addrStackPtr += n;
}


/****************************************************************************
 * Line input handling
 ***************************************************************************/
char getKeyB(void)
{
	char c;

	c = lineBuffer[lineBufferIdx++];
	if (c == 0) {
		getLine();
		c = lineBuffer[lineBufferIdx++];
	}

	return (c);
}


void getLine(void)
{
	int16_t waiting;
	char c;

	lineBufferIdx = 0;

	if (echo) {
		//uart_putchar('\r');
		uart_putchar('\n');
		uart_putchar('>');   // this is our prompt
	}

	waiting = 1;
	while (waiting) {  // just hang in loop until we get CR
		c = uart_getchar();

		if (echo && (c == '\b') && (lineBufferIdx > 0)) {
			uart_putchar('\b');
			uart_putchar(' ');
			uart_putchar('\b');
			lineBufferIdx--;
		} else {
			if (echo) {
				uart_putchar(c);

				if (c == '\r') {
					uart_putchar('\n');
				}
			}

			if ( (c == '\r') ||
				 (c == '\n') ||
				 (lineBufferIdx >= (LINE_BUFFER_SIZE - 1))) { // prevent overflow of line buffer

				waiting = 0;
			}

			lineBuffer[lineBufferIdx++] = c;
			lineBuffer[lineBufferIdx] = 0;
		}
	}

	lineBufferIdx = 0;
}


char nextPrintableChar(void)
{
	char c;

	do {
		c = getKeyB();
	} while (c <= ' ');

	return (c);
}


char skipStackComment(void)
{
	char c;

	do {
		c = getKeyB();
	} while (c != ')');

	c = nextPrintableChar();

	return (c);
}


/****************************************************************************
 * Word buffer usage
 ***************************************************************************/
int16_t lookupToken(char *word, char *list)
{
	// looking for word in list
	// Matches FIRST OCCURENCE of word in list

	int16_t i;
	int16_t j;
	int16_t k;
	int16_t n;

	i = 0;
	j = 0;
	k = 0;
	n = 1;

	while (list[i] != 0) {
		if ((word[j] != 0) && (list[i] == word[j])) {
			// keep matching
			j++;
		} else if ((word[j] == 0) && (list[i] == ' ')){
			// end of word, match iff it's the end of the list item
			k = n;
			//just break the while early
			break;
		} else {
			j = 0;
			n++;
			while (list[i] > ' ') {
				i++;
			}
		}

		i++;
	}

	return(k);
}


void dfnFunc(void)
{
	// this function adds a new def to the list and creates a new opcode

	uint16_t i;

	i = 0;

	while (wordBuffer[i]) {
		cmdList[cmdListIdx++] = wordBuffer[i];
		i = i + 1;
	}

	cmdList[cmdListIdx++] = ' ';
	cmdList[cmdListIdx] = 0;
	i = lookupToken(wordBuffer, cmdList);
	progOpcodes[i] = progIdx;
}


void getWordFunc(void)
{
	int16_t k;
	uint8_t c;

	k = 0;
	c = nextPrintableChar();

	// ignore comments
	while ((c == '(') || (c == 92)) {
		switch (c) {
			case '(': // '(' + anything + ')'
				c = skipStackComment();
				break;

			case 92: // '\' backslash -- to end of line
				getLine();
				c = nextPrintableChar();
				break;

			default:
				break;
		}
	}

	do {
		wordBuffer[k++] = c;
		wordBuffer[k] = 0;
		c = getKeyB();
	} while ((c > ' ') && (k < WORD_BUFFER_SIZE));
}


void luFunc(void)
{
	int16_t opcode;

	opcode = lookupToken(wordBuffer, (char *)cmdListBi);

	if (opcode) {
		opcode += BUILTIN_OPCODE_OFFSET;
		pushMathStack(opcode);
		pushMathStack(1);
	} else {
		// need to test internal interp commands
		opcode = lookupToken(wordBuffer, (char *)cmdListBi2);
		if (opcode) {
			opcode += BUILTIN_INTERP_OFFSET;
			pushMathStack(opcode);
			pushMathStack(1);
		} else {
			opcode = lookupToken(wordBuffer, cmdList);
			if (opcode) {
				pushMathStack(opcode);
				pushMathStack(1);
			} else {
				pushMathStack(0);
			}
		}
	}
}


void numFunc(void)
{
	// the word to test is in wordBuffer

	uint16_t i;
	int16_t isnum;
	int32_t n;

	i = 0;
	isnum = 0;
	n = 0;

	// first check for neg sign
	if (wordBuffer[i] == '-') {
		i = i + 1;
	}

	if ((wordBuffer[i] >= '0') && (wordBuffer[i] <= '9')) {
		// it is a number
		isnum = 1;
		// check if hex
		if (wordBuffer[0] == '0' && wordBuffer[1] == 'x') {
			// base 16 number ... just assume all characters are good
			i = 2;
			n = 0;
			while (wordBuffer[i]) {
				//n = n << 4;
				//n = n + wordBuffer[i] - '0';
				//if (wordBuffer[i] > '9') {
				//	n = n - 7;

				//	// compensate for lowercase digits
				//	if (wordBuffer[i] >= 'a') {
				//		n -= 0x20;
				//	}
				//}
				n = (n << 4) | hex4_to_uint(wordBuffer[i]);
				i = i + 1;
			}
		} else {
			// base 10 number
			n = 0;
			while (wordBuffer[i]) {
				n = n * 10;
				n = n + wordBuffer[i] - '0';
				i = i + 1;
			}
			if (wordBuffer[0] == '-') {
				n = -n;
			}
		}
	}

	pushMathStack(n);
	pushMathStack(isnum);
}


/****************************************************************************
 * Terminal output effects
 ***************************************************************************/

void listFunc(void)
{
	printStringln((char *)cmdListBi);
	printStringln((char *)cmdListBi2);
	printStringln(cmdList);
}


void opcode2wordFunc(void)
{
	// given an opcode, print corresponding ASCII word name

	int16_t n;
	int16_t opcode;
	char *list;

	n = 1; // opcode indices are 1-based
	opcode = popMathStack();

	// where is the opcode defined?
	// remove offset
	if (opcode >= BUILTIN_OPCODE_OFFSET) {
		list = (char *)cmdListBi;
		opcode -= BUILTIN_OPCODE_OFFSET;
	} else if (opcode >= BUILTIN_INTERP_OFFSET) {
		list = (char *)cmdListBi2;
		opcode -= BUILTIN_INTERP_OFFSET;
	} else {
		list = cmdList;
	}

	// walk list to get word
	// skip to start of the expected location
	while (n < opcode) {
		while (*list > ' ') {
			list++;
		}
		list++;
		n++;
	}

	if (*list != 0) {
		// not end of list, print next word
		while (*list > ' ') {
			uart_putchar(*list++);
		}
	} else {
		uart_putchar('?');
	}

	uart_putchar(' ');
}


/****************************************************************************
 * Other helpers
 ***************************************************************************/
void execFunc(void) {
	int16_t opcode;

	opcode = popMathStack();

	if (opcode >= BUILTIN_OPCODE_OFFSET) {
		// this is a built in opcode
		execVM(opcode - BUILTIN_OPCODE_OFFSET);
	} else if (opcode >= BUILTIN_INTERP_OFFSET) {
		// built in interp
		pushAddrStack(progCounter);
		progCounter = cmdList2N[opcode - BUILTIN_INTERP_OFFSET];
	} else {
		pushAddrStack(progCounter);
		progCounter = progOpcodes[opcode];
	}
}


void ifFunc(int16_t x){
	// used as goto if x == 1

	uint16_t addr;
	uint16_t tmp;
	int32_t i;

	if(progCounter >= BUILTIN_INTERP_OFFSET){
		tmp = progCounter - BUILTIN_INTERP_OFFSET;
		addr = progBi[tmp];
	} else {
		addr = prog[progCounter];
	}

	progCounter++;

	if (x == 1) {
		// this is a goto
		progCounter = addr;
	} else {
		// this is the "if" processing
		i = popMathStack();
		if(i == 0){
			progCounter = addr;
		}
	}
}


void loopFunc(int16_t n)
{
#define j ATOS      // loop address
#define k ANOS      // count
#define m ASTACK(2) // limit

	k += n;     // inc/dec the count

	if (((n > 0) && (k < m)) || ((n < 0) && (k > m))) {
		// loop
		progCounter = j;
	} else {
		// done, cleanup
		ndropAddr(3);
	}
#undef j
#undef k
#undef m
}


void opcode2progFunc(void)
{
	// given an opcode, get the start index of prog of it's definition

	if (TOS >= BUILTIN_INTERP_OFFSET) {
		// catches both OPCODE and INTERP_OFFSET
		TOS = 0;
	} else {
		TOS = progOpcodes[TOS];
	}
}


void pushnFunc(void)
{
	int32_t i;	// NOTE: this needs to be 32 bits in order to fix the bug where written numbers in user-defined functions have undefined upper 16 bits

	if (progCounter >= BUILTIN_INTERP_OFFSET) {
		i = progBi[progCounter - BUILTIN_INTERP_OFFSET];
	} else {
		i = prog[progCounter];
	}

	progCounter = progCounter + 1;
	pushMathStack(i);
}


void rollFunc(int16_t n)
{
	int32_t *addr;
	int32_t tmp;

	tmp = STACK(n);
	addr = (mathStackPtr + n);

	while (addr > mathStackPtr) {
		*addr = *(addr - 1);
		addr--;
	}

	TOS = tmp;
}


void flashReadFunc(uint32_t start_address, uint32_t length, int32_t bin_payload)
{
	// Reads the SPI flash memory starting at start_address and reading length number of bytes
	// Print format: If bin_payload == 0, prints the first element as a MSB-first two-char hexadecimal string, followed by the second element, and so on. If bin_payload == 1, prints the first element as a MSB-first binary byte, followed by the second element, and so on.

	// Initialize the SPI flash if it hasn't been already
	if (flash_is_initialized == 0)
	{
		flash_memory_init();
		flash_is_initialized = 1;
	}
	
	// Send the start address
	flash_memory_beginRead(start_address);
	spi_setDataLength(SPIDL_8);

	//uint8_t crc8 = 0;
	uint8_t received_data;
	while (length > 0)
	{
		received_data = spi_transfer(0);
		if (bin_payload)
			uart_putchar(received_data);
		else
			printHex8(received_data);
		length--;
	}

	deassert_CS_FLASH();
}


void flashWritePageFunc(uint32_t page_address, int32_t bin_payload)
{
	// Reads in data from UART0 and writes the data to the SPI flash memory
	// Protocol: Once the flash write command has been issued, the forth interpreter will issue a '$' char to indicate it is ready to receive the payload. Write 256 payload bytes in order of increasing addresses to UART0. Once they have been received by the forth interpreter, it will calculate the CRC16_CDMA2000 value of the payload and send it back over UART0 as a 4 character hex string. You must then write a 'Y' character to UART0 to make the forth interpreter write the payload to the flash memory; any other character will cause it to abort the SPI flash write process.
	// If bin_payload == 0: Expects the payload to be a HEX string with exactly 512 characters that represent a 256-byte page. Each group of two characters will be treated as one MSB-first byte in HEX. The bytes must be ordered such that the first byte will be stored at the location "page_address", the second at "page_address + 1", and so on.
	// If bin_payload == 1: Expects the payload to be a raw binary array containing exactly 256 bytes to form a page. Each byte must be MSB-first. The bytes must be ordered such that the first byte will be stored at the location "page_address", the second at "page_address + 1", and so on.
	
	// Initialize the SPI flash if it hasn't been already
	if (flash_is_initialized == 0)
	{
		flash_memory_init();
		flash_is_initialized = 1;
	}
	
	// Indicate that the MCU is ready to receive the page data with the ready character
	uart_putchar('$');
	
	// Read the data to be written to the SPI flash from the UART and place it into a 256-byte buffer (a page of data)
	// Concurrently, compute the CRC16_CDMA2000 value of the page (polynomial = 0xC857, initial CRC value = 0xFFFF, no final XOR (= 0x0000), no data reflection, no output reflection)
	uint8_t flash_write_buffer[256];
	uint16_t i;
	CRCSTATE = 0xFFFF;
	for (i = 0; i < 256; i++)
	{
		
		uint8_t element;
		if (bin_payload)
		{
			// Read a single byte from the UART as a raw binary value
			element = uart_getchar();
		}
		else
		{
			// Read two ASCII bytes from the UART and convert them into one 8-bit element
			element = hex4_to_uint(uart_getchar()) << 4;
			element |= hex4_to_uint(uart_getchar());
		}

		// Put the element in the buffer
		flash_write_buffer[i] = element;
		
		// Continue computing the CRC
		CRCDATA = element;
	}

	// Print the CRC16 value (always 4 chars long)
	printHex16(CRCSTATE);

	// Read a single char from the UART
	char good = uart_getchar();
	
	// If the affirmative char was received, program the buffer to the SPI flash
	if (good == 'Y')
		flash_memory_writePage(page_address, flash_write_buffer);
}

uint8_t flashErasePageFunc(uint32_t page_address, int32_t confirmation_key)
{
	// Erases the page of the SPI flash memory located at page_address if and only if confirmation_key == 123
	if (confirmation_key == 123)
	{
		// Initialize the SPI flash if it hasn't been already
		if (flash_is_initialized == 0)
		{
			flash_memory_init();
			flash_is_initialized = 1;
		}
		
		// Erase the page
		flash_memory_erasePage(page_address);
		return 1;	// Successfully erased the page
	}

	return 0;	// Failed to erase the page
}


uint8_t flashEraseMultiplePagesFunc(uint32_t start_page_address, uint32_t length, int32_t confirmation_key)
{	
	// Erases the page of the SPI flash memory located at page_address if and only if confirmation_key == 123
	if ((confirmation_key == 123) && ((start_page_address & 0xFFFFFF00) == start_page_address) && ((length & 0xFFFFFF00) == length) && (length > 0))
	{
		// Initialize the SPI flash if it hasn't been already
		if (flash_is_initialized == 0)
		{
			flash_memory_init();
			flash_is_initialized = 1;
		}

		length += start_page_address;

		while (start_page_address < length)
		{
			// Erase the page
			flash_memory_erasePage(start_page_address);
			start_page_address += 256;
		}
		
		return 1;	// Successfully erased the page
	}

	return 0;	// Failed to erase the page
}


uint32_t clkMeasureFunc(uint8_t clock_select, uint8_t measurement_time_select)
{
	// Calculates the clock frequency of the desired clock and transmits the frequency over UART
	// Uses TIMER0 to count up clock cycles on the desired clock
	// Uses TIMER1 to count up clock cycles on LFXT, which must be 32.768 kHz
	// Arguments:
	//	clock_select: 0 <= SMCLK; 1 <= MCLK; 2 <= LFXT; 3 <= HFXT
	//	measurement_time_select: 0 <= 1 second; 1 <= 0.5 seconds; 2 <= 0.25 seconds; 3 <= 0.125 seconds

	// Configure TIMER0 to use the desired clock
	TIM0CR = 0
		| TIMDIV_1	// No clock division
		| ((((uint32_t)clock_select) & 0b11) << 8)	// Select the desired source clock
		;
	TIM0VAL = 0;
	TIM0SR = 0xFF;

	// Configure TIMER1 to use ClkLFXT (32.768 kHz)
	TIM1CR = 0
		| TIMDIV_1	// No clock division
		| TIMSSEL_LFXT	// Select LFXT as the source clock for TIMER1
		;
	TIM1VAL = 0;
	TIM1SR = 0xFF;
	register uint32_t t1_end;
	switch (measurement_time_select)
	{
		case 0:
			t1_end = 32768;	// 1 second
			break;
		case 1:
			t1_end = 16384;	// 0.5 seconds
			break;
		case 2:
			t1_end = 8192;	// 0.25 seconds
			break;
		default:
			t1_end = 4096;	// 0.125 seconds
			measurement_time_select = 3;
			break;
	}

	// Start the low frequency measuring clock
	TIM1CR |= TIMEN;

	// Wait for the low frequency measuring clock to have a positive clock edge. This ensures accurate and reproducable measurements
	while (TIM1VAL == 0) {}

	// Start the measured clock's timer and reset the low frequency measuring clock
	TIM0CR |= TIMEN;
	TIM1VAL = 0;

	// Wait until TIMER1 reaches the desired value
	while (TIM1VAL < t1_end) {}

	// The the measurement time is complete, stop TIMER0 and read its value, then calculate the frequency
	TIM0CR = 0;
	TIM1CR = 0;
	uint32_t frequency = TIM0VAL << measurement_time_select;

	// Send the frequency
	return frequency;
}

void memoryReadFunc(uint32_t start_address, uint32_t length, int32_t mode)
{
	// Reads a block of memory and prints it to the serial port. Note that the printed data is in order of memory address. For example, if you are reading a 4-byte data block with the intention of parsing it into a 32-bit unsigned integer, you will need to reverse the order of every 4 bytes.
	// Arguments:
	//	start_address: The memory location of the first byte to read
	//	length:	The number of bytes to read, including the first byte
	//	mode: If mode == 0, sends an ASCII hex string of the data. If mode == 1, sends a raw binary payload of the data.

	// Set up the CRC16_CDMA2000 value of the data (polynomial = 0xC857, initial CRC value = 0xFFFF, no final XOR (= 0x0000), no data reflection, no output reflection)
	uint8_t *data = (uint8_t *)start_address;
	CRCSTATE = 0xFFFF;
	uint32_t i;
	
	// Send the payload
	for (i = 0; i < length; i++)
	{
		if (mode)
			uart_putchar(data[i]);
		else
			printHex8(data[i]);
		CRCDATA = data[i];
	}

	// Send the CRC data
	if (mode)
	{
		// Send binary CRC data in two bytes, LSbyte first
		uart_putchar(CRCSTATE);			// LSbyte
		uart_putchar(CRCSTATE >> 8);	// MSbyte
	}
	else
	{
		// Send CRC data as a 4-char hex string
		printHex16(CRCSTATE);
	}

	return;
}

void memoryWriteFunc(uint32_t start_address, uint32_t length, uint32_t bin_payload)
{
	// Reads in data from UART0 and writes the data to RAM
	// Protocol: Once the memory write command has been issued, the forth interpreter will issue a '$' char to indicate it is ready to receive the payload. Write length payload bytes in order of increasing addresses to UART0. Once they have been received by the forth interpreter, it will calculate the CRC16_CDMA2000 value of the payload and send it back over UART0 as a 4 character hex string.
	// If bin_payload == 0: Expects the payload to be a HEX string with exactly 2*length characters. Each group of two characters will be treated as one MSB-first byte in HEX. The bytes must be ordered such that the first byte will be stored at the location "page_address", the second at "page_address + 1", and so on.
	// If bin_payload == 1: Expects the payload to be a raw binary array containing exactly length bytes. Each byte must be MSB-first. The bytes must be ordered such that the first byte will be stored at the location "page_address", the second at "page_address + 1", and so on.
	
	// Indicate that the MCU is ready to receive the page data with the ready character
	uart_putchar('$');
	
	// Read the data to be written to ram from the UART
	// Concurrently, compute the CRC16_CDMA2000 value of the data (polynomial = 0xC857, initial CRC value = 0xFFFF, no final XOR (= 0x0000), no data reflection, no output reflection)
	length += start_address;
	CRCSTATE = 0xFFFF;
	while (start_address < length)
	{
		
		uint8_t element;
		if (bin_payload)
		{
			// Read a single byte from the UART as a raw binary value
			element = uart_getchar();
		}
		else
		{
			// Read two ASCII bytes from the UART and convert them into one 8-bit element
			element = hex4_to_uint(uart_getchar()) << 4;
			element |= hex4_to_uint(uart_getchar());
		}

		// Put the element in RAM at the appropriate location
		(*((volatile uint8_t *)start_address)) = element;
		
		// Continue computing the CRC
		CRCDATA = element;

		start_address++;
	}

	// Print the CRC16 value (always 4 chars long)
	printHex16(CRCSTATE);
}

void memorySetFunc(uint32_t start_address, uint32_t length, uint8_t set_byte)
{
	// Sets all bytes to set_byte, beginning at start_address and continuing for length bytes
	// Arguments:
	//	start_address: The first address
	//	length:	The number of bytes to set
	length += start_address;
	while (start_address < length)
	{
		(*((uint8_t *)start_address)) = set_byte;
		start_address += 1;
	}

	return;
}


/****************************************************************************
 *
 * VM opcode execution
 *
 ***************************************************************************/
void execVM(int16_t opcode)
{
	int32_t i,j,k,m,n;
	int64_t x;

	switch(opcode){
		case  0: // unused
			break;

		case  1: // bye
			xit = 1;
			break;

		case  2: // +  ( a b -- a+b )
			NOS += TOS;
			popMathStack();
			break;

		case  3: // -  ( a b -- a-b )
			NOS += -TOS;
			popMathStack();
			break;

		case  4: // *  ( a b -- reshi reslo )
			x = TOS * NOS;
			NOS = (int32_t)((x >> 32) & 0xffffffff);
			TOS = (int32_t)(x & 0xffffffff);
			break;

		case  5: // /%  ( a b -- a/b a%b )
			i = NOS;
			j = TOS;
			NOS = i / j;
			TOS = i % j;
			break;

		case  6: // .  ( a -- )
			printNumberInt32(popMathStack());
			break;

		case  7: // dup  ( a -- a a )
			pushMathStack(TOS);
			break;

		case  8: // drop  ( a -- )
			i = popMathStack();
			break;

		case  9: // swap  ( a b -- b a )
			i = TOS;
			TOS = NOS;
			NOS = i;
			break;

		case 10: // <  ( a b -- a<b )
			i = popMathStack();
			if (TOS < i) {
				TOS = 1;
			} else {
				TOS = 0;
			}
			break;

		case 11: // >  ( a b -- a>b )
			i = popMathStack();
			if (TOS > i) {
				TOS = 1;
			} else {
				TOS = 0;
			}
			break;

		case 12: // ==  ( a b -- a==b )
			i = popMathStack();
			if (i == TOS) {
				TOS = 1;
			} else {
				TOS = 0;
			}
			break;

		case 13: // hb.  ( a -- )
			printHex8(popMathStack());
			uart_putchar(' ');
			break;

		case 14: // gw  ( -- ) \ get word from input
			getWordFunc();
			break;

		case 15: // dfn  ( -- ) \ create opcode and store word to cmdList
			dfnFunc();
			break;

		case 16: // abs  ( a -- |a| ) \ -32768 is unchanged
			if (TOS < 0) {
				TOS = -TOS;
			}
			break;

		case 17: // ,  ( opcode -- ) \ push opcode to prog space
			prog[progIdx++] = popMathStack();
			break;

		case 18: // p@  ( opaddr -- opcode ) \ retrieve opcode from prog address
			i = TOS;
			TOS = prog[i];
			break;

		case 19: // p!  ( opcode opaddr -- )
			i = popMathStack();
			j = popMathStack();
			prog[i] = j;
			break;

		case 20: // not  ( a -- !a ) \ logical not
			if (TOS) {
				TOS = 0;
			} else {
				TOS = 1;
			}
			break;

		case 21: // list  ( -- ) \ show defined words
			listFunc();
			break;

		case 22: // if  ( flag -- )
			ifFunc(0);
			break;

		case 23: // then      ( trapped in ':')
			break;

		case 24: // else      ( trapped in ':')
			break;

		case 25: // begin  ( -- ) ( -a- pcnt )
			pushAddrStack(progCounter);
			break;

		case 26: // until  ( flag -- ) ( addr -a- )
			i = popAddrStack();
			j = popMathStack();

			if (j == 0) {
				addrStackPtr--;  // number is still there ... just fix the pointer
				progCounter = i;
			}
			break;

		case 27: // depth  ( -- n ) \ math stack depth
			pushMathStack(mathStackStart - mathStackPtr);
			break;

		case 28: // h.  ( a -- )
			printHex32(popMathStack());
			uart_putchar(' ');
			break;

		case 29: // ] ( trapped in interp )
			break;

		case 30: // num  ( -- n flag ) \ is word in buffer a number?
			numFunc();
			break;

		case 31: // push0  ( -- 0 )
			pushMathStack(0);
			break;

		case 32: // goto   ( for internal use only )
			ifFunc(1);
			break;

		case 33: // exec  ( opcode -- )
			execFunc();
			break;

		case 34: // lu  ( -- opcode 1 | 0 )
			luFunc();
			break;

		case 35: // pushn   ( -- a ) \ put next prog code to math stack
			pushnFunc();
			break;

		case 36: // over  ( a b -- a b a )
			pushMathStack(NOS);
			break;

		case 37: // push1  ( -- 1 )
			pushMathStack(1);
			break;

		case 38: // pwrd  ( -- ) \ print word buffer
			printStringln(wordBuffer);
			break;

		case 39: // emit  ( c -- )
			uart_putchar(popMathStack());
			break;

		case 40: // ;  ( pcnt -a- ) \ return from inner word
			i = progCounter;
			progCounter = popAddrStack();
			break;

		case 41: // @  ( addr -- val ) \ read directly from memory address
			i = TOS >> 2;
			TOS = dirMemory[(uint32_t)i];
			break;

		case 42: // !  ( val addr -- ) \ write directly to memory address words only!
			i = popMathStack();  //  address to write to
			i = i >> 2;
			j = popMathStack();  //  value to write
			dirMemory[(uint32_t)i] = j;
			break;

		case 43: // h@  ( -- prog ) \ get end of program code space
			pushMathStack(progIdx);
			break;

		//////////////////////////////////////////////////////////////////////////
		//////// end of words used in progBi[] ///////////////////////////////////
		//////////////////////////////////////////////////////////////////////////

		case 44: // do  ( limit cnt -- ) ( -a- limit cnt pcnt )
			i = popMathStack();  // start of count
			j = popMathStack();  // end count
			k = progCounter;

			pushAddrStack(j);  // limit on count
			pushAddrStack(i);  // count  (I)
			pushAddrStack(k);  // address to remember for looping
			break;

		case 45: // loop  ( -- ) ( limit cnt pcnt -a- | limit cnt+1 pcnt )
			loopFunc(1);
			break;

		case 46: // +loop  ( n -- ) ( limit cnt pcnt -a- | limit cnt+n pcnt ) \ decrement loop if n<0
			loopFunc(popMathStack());
			break;

		case 47: // i  ( -- cnt ) \ loop counter value
			i = ANOS;
			pushMathStack(i);
			break;

		case 48: // j  ( -- cnt ) \ next outer loop counter value
			i = ASTACK(4);
			pushMathStack(i);
			break;

		case 49: // k  ( -- cnt ) \ next next outer loop counter value
			i = ASTACK(7);
			pushMathStack(i);
			break;

		case 50: // ~  ( a -- ~a ) \ bitwise complement
			TOS = ~TOS;
			break;

		case 51: // ^  ( a b -- a^b ) \ bitwise xor
			NOS ^= TOS;
			popMathStack();
			break;

		case 52: // &  ( a b -- a&b ) \ bitwise and
			NOS &= TOS;
			popMathStack();
			break;

		case 53: // |  ( a b -- a|b ) \bitwise or
			NOS |= TOS;
			popMathStack();
			break;

		case 54: // */  ( a b c -- (a*b)/c ) \ 32b intermediate
			i = popMathStack();
			j = TOS;
			k = NOS;
			x = j * k;
			x = ((int32_t)x) / i;	// TODO: x should NOT be cast as an int32_t (it should be an int64_t), but so far I haven't found a way to link the __divdi3 function. For now, the only way to link successfully is to use 32-bit division
			popMathStack();
			TOS = (int32_t)(x & 0xffffffff);
			break;

		case 55: // key  ( -- c ) \ get a key from input .... (wait for it)
			pushMathStack(uart_getchar());
			break;

		case 56: // cr  ( -- )
			//uart_putchar('\r');
			uart_putchar('\n');
			break;

		case 57: // *2  ( a -- a<<1 )
			TOS <<= 1;
			break;

		case 58: // /2  ( a -- a>>1 )
			TOS >>= 1;
			break;

		case 59: // call0  ( &func -- *func() )
			i = TOS;
GCC_DIAG_OFF(int-to-pointer-cast);
			TOS = (*(int32_t(*)(void)) i) ();
GCC_DIAG_ON(int-to-pointer-cast);
			break;

		case 60: // call1  ( a &func -- *func(a) )
			i = TOS;
			j = NOS;
GCC_DIAG_OFF(int-to-pointer-cast);
			NOS = (*(int32_t(*)(int32_t)) i) (j);
GCC_DIAG_ON(int-to-pointer-cast);
			popMathStack();
			break;

		case 61: // call2  ( a b &func -- *func(a,b) )
			i = TOS;
			j = NOS;
			k = STACK(2);
GCC_DIAG_OFF(int-to-pointer-cast);
			STACK(2) = (*(int32_t(*)(int32_t, int32_t)) i) (k, j);
GCC_DIAG_ON(int-to-pointer-cast);
			ndrop(2);
			break;

		case 62: // call3  ( a b c &func -- *func(a,b,c) )
			i = TOS;
			j = NOS;
			k = STACK(2);
			m = STACK(3);
GCC_DIAG_OFF(int-to-pointer-cast);
			STACK(3) = (*(int32_t(*)(int32_t, int32_t, int32_t)) i) (m, k, j);
GCC_DIAG_ON(int-to-pointer-cast);
			ndrop(3);
			break;

		case 63: // call4  ( a b c d &func -- *func(a,b,c,d) )
			i = TOS;
			j = NOS;
			k = STACK(2);
			m = STACK(3);
			n = STACK(4);
GCC_DIAG_OFF(int-to-pointer-cast);
			STACK(4) = (*(int32_t(*)(int32_t, int32_t, int32_t, int32_t)) i) (n, m, k, j);
GCC_DIAG_ON(int-to-pointer-cast);
			ndrop(4);
			break;

		case 64: // ndrop  ( (x)*n n -- ) \ drop n math stack cells
			ndrop(popMathStack());
			break;

		case 65: // swpb  ( n -- n ) \ byteswap TOS
			TOS = ((TOS >> 8) & 0x00ff) | ((TOS << 8) & 0xff00);
			break;

		case 66: // +!  ( n addr -- ) \ *addr += n
			i = popMathStack();
			j = popMathStack();
			dirMemory[(uint32_t)i] += j;
			break;

		case 67: // roll  ( n -- ) \ nth stack removed and placed on top
			rollFunc(popMathStack());
			break;

		case 68: // pick  ( n -- ) \ nth stack copied to top
			i = popMathStack();
			pushMathStack(STACK(i));
			break;

		case 69: // tuck  ( a b -- b a b ) \ insert copy TOS to after NOS
			i = NOS;
			pushMathStack(TOS);
			STACK(2) = TOS;
			NOS = i;
			break;

		case 70: // max  ( a b -- c ) \ c = a ? a>b : b
			i = popMathStack();
			if (i > TOS) {
				TOS = i;
			}
			break;

		case 71: // min  ( a b -- c ) \ c = a ? a<b : b
			i = popMathStack();
			if (i < TOS) {
				TOS = i;
			}
			break;

		case 72: // s.  ( -- ) \ print stack contents, TOS on right
			{ // addr is strictly local to this block
					int32_t *addr;
					addr = mathStackStart;
					while (addr >= mathStackPtr) {
							printNumberInt32(*addr);
							addr--;
					}
			}
			break;

		case 73: // sh.  ( -- ) \ print stack contents in hex, TOS on right
			{ // addr is strictly local to this block
					int32_t *addr;
					addr = mathStackStart;
					while (addr >= mathStackPtr) {
							printHex32(*addr);
							uart_putchar(' ');
							addr--;
					}
			}
			break;

		case 74: // neg  ( a -- -a ) \ twos complement
			TOS *= -1;
			break;

		case 75: // echo  ( bool -- ) \ ?echo prompts and terminal input?
			echo = popMathStack();
			break;

		case 76: // init  ( -- ) \ clears buffers and calls rv4th_init
			*lineBuffer = 0; // if location is same, the call is recursive otherwise
			rv4th_init();
			break;

		case 77: // o2w  ( opcode -- ) \ prints name of opcode
			opcode2wordFunc();
			break;

		case 78: // o2p  ( opcode -- progIdx ) \ lookup opcode definition, 0 if builtin
			opcode2progFunc();
			break;
		
		case 79: // rst ( -- ) \ Performs a soft reset of the MCU
			MEMPWRCR = 0;	// Power on all memory
			asm volatile ("j 0");
			break;
		
		case 80: // clk ( measurement_time_select clock_select -- ) \ Measures clock frequency
			i = popMathStack();	// clock_select
			j = popMathStack();	// measurement_time_select
			TOS = clkMeasureFunc(i, j);
			break;
		
		case 81: // fr  ( bin_payload length start_address -- ) \ SPI flash read
			i = popMathStack();	// start_address, the address to begin reading from
			j = popMathStack();	// length, the number of bytes to read
			k = popMathStack();	// bin_payload, if true (nonzero), transmits binary data, otherwise it transmits an ASCII hex string
			flashReadFunc(i, j, k);
			break;
		
		case 82: // fw  ( bin_payload page_address -- ) \ SPI flash write page
			i = popMathStack();	// page_address, the address of the page to write to
			j = popMathStack();	// bin_payload, if true (nonzero), expects the transmission of binary data, otherwise it expects an ASCII hex string
			flashWritePageFunc(i, j);
			break;
		
		case 83: // fe ( confirmation_key page_address -- erase_successful ) \ SPI flash erase page
			i = popMathStack(); // page_address, the address of the page to erase
			j = TOS; // confirmation_key, which must be equal to 123 in order to erase the page
			TOS = flashErasePageFunc(i, j);	// Pushes erase_successful to TOS, which is 1 if the erase was successful and 0 if not
			break;
		
		case 84: // fem ( confirmation_key length start_page_address -- erase_successful ) \ SPI flash erase multiple page
			i = popMathStack(); // start_page_address, the address of the page to erase
			j = popMathStack();	// length, the number of bytes to erase. Must be a multiple of 256
			k = TOS; // confirmation_key, which must be equal to 123 in order to erase the page
			TOS = flashEraseMultiplePagesFunc(i, j, k);	// Pushes erase_successful to TOS, which is 1 if the erase was successful and 0 if not
			break;
		
		case 85: // sbi ( bitnum addr -- ) \ set bit by writing directly to memory address (words only!)
			i = popMathStack();	// address to write to
			i = i >> 2;
			j = popMathStack();	// bit number to set
			dirMemory[(uint32_t)i] |= (1 << j);
			break;
		
		case 86: // cbi ( bitnum addr -- ) \ clear bit by writing directly to memory address (words only!)
			i = popMathStack();	// address to write to
			i = i >> 2;
			j = popMathStack();	// bit number to clear
			dirMemory[(uint32_t)i] &= ~(1 << j);
			break;
		
		case 87: // mask ( posbitmask val addr -- ) \ write only masked bits by writing directly to memory address (words only!)
			i = popMathStack();	// address to write to
			i = i >> 2;
			j = popMathStack();	// value to write within mask
			k = popMathStack();	// positive bit mask (only write to bits with 1's)
			dirMemory[(uint32_t)i] = (dirMemory[(uint32_t)i] & (~k)) | (j & k);
			break;
		
		case 88: // and ( a b -- a&&b ) \ Logical and (if a and b are nonzero, return 1)
			i = popMathStack();	// b
			TOS = TOS && i;
			break;
		
		case 89: // or ( a b -- a||b ) \ Logical or (if a or b are nonzero, return 1)
			i = popMathStack();	// b
			TOS = TOS || i;
			break;
		
		case 90: // swphw  ( n -- n ) \ Swap upper and lower 16 bits of TOS
			TOS = ((TOS >> 16) & 0x0000ffff) | ((TOS << 16) & 0xffff0000);
			break;
		
		case 91: // sll  ( val bits -- ret ) \ Shift left logical (also arithmetic)
			i = popMathStack();	// bits
			TOS = ((uint32_t)TOS) << i;
			break;
		
		case 92: // srl  ( val bits -- ret ) \ Shift right logical
			i = popMathStack();	// bits
			TOS = ((uint32_t)TOS) >> i;
			break;
		
		case 93: // mr  ( mode length start_address -- ) \ Memory read
			i = popMathStack();	// start_address, the address to begin reading from
			j = popMathStack();	// length, the number of bytes to read
			k = popMathStack();	// mode, if true (nonzero), transmits binary data, if equal to 2, transmits compressed data, otherwise it transmits an ASCII hex string
			memoryReadFunc(i, j, k);
			break;
		
		case 94: // mw  ( bin_payload length start_address -- ) \ Memory write
			i = popMathStack();	// start_address, the address to begin writing to
			j = popMathStack();	// length, the number of bytes to write
			k = popMathStack();	// bin_payload, if true (nonzero), receives binary data. If false, it receives an ASCII hex string
			memoryWriteFunc(i, j, k);
			break;
		
		case 95: // ms ( set_byte length start_address -- ) \ Memory erase
			i = popMathStack();	// start_address, the address to begin erasing from
			j = popMathStack();	// length, the number of bytes to erase
			k = popMathStack();	// set_byte, the value that all bytes will be set as
			memorySetFunc(i, j, k);
			break;
		
		default:
			break;
	}
}



/****************************************************************************
 *
 * Public functions
 *
 ***************************************************************************/
void rv4th_init()
{
	// Initialize the pointers to the buffers
	mathStackPtr = &mathStackArray[MATH_STACK_SIZE - 1];
	addrStackPtr = &addrStackArray[ADDR_STACK_SIZE - 1];
	mathStackStart = &mathStackArray[MATH_STACK_SIZE - 1];
	addrStackStart = &addrStackArray[ADDR_STACK_SIZE - 1];
	prog = &progArray[0];
	progOpcodes = &progOpcodesArray[0];
	cmdList = &cmdListArray[0];
	lineBuffer =  &lineBufferArray[0];
	wordBuffer = &wordBufferArray[0];

	// Initialize the top of the math stack to zero
	mathStackArray[MATH_STACK_SIZE - 1] = 0;

	// Terminate the buffers
	lineBufferArray[0] = '\0';
	cmdListArray[0] = '\0';

	// Initialize the other variables
	xit = 0;
	echo = 1;
	progCounter = BUILTIN_INTERP_OFFSET;
	progIdx = 1;	// this will be the first opcode
	cmdListIdx = 0;

	lineBufferIdx = 0;
	printStringln((char *) (ASIC_NAME " rv4th-rom!"));

	//// A note on how to execute a line of words on initialization
	//uint8_t *str = (uint8_t *)"1 2 3 4 5 s.\n";
	//for (i=0; i < 14; i++) {
	//	lineBufferArray[i] = str[i];
	//	lineBufferArray[i+1] = 0;
	//}
}


int16_t rv4th_processLoop(void) // this processes the forth opcodes.
{
	uint16_t opcode;
	uint16_t tmp;

	flash_is_initialized = 0;

	while (xit == 0)
	{
		if (progCounter >= BUILTIN_INTERP_OFFSET)
		{
			tmp = progCounter - BUILTIN_INTERP_OFFSET;
			opcode = progBi[tmp];
		}
		else
		{
			opcode = prog[progCounter];
		}

		progCounter = progCounter + 1;

		if (opcode >= BUILTIN_OPCODE_OFFSET)
		{
			// this is a built in opcode
			execVM(opcode - BUILTIN_OPCODE_OFFSET);
		}
		else
		{
			pushAddrStack(progCounter);
			progCounter = progOpcodes[opcode];
		}
	}

	return(TOS);
}

