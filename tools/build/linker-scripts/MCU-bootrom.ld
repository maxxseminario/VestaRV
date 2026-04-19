OUTPUT_FORMAT("elf32-littleriscv", "elf32-littleriscv", "elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(_start)

INCLUDE memory.x
INCLUDE periph.x

SECTIONS
{
	__interrupt_vector_1	: { KEEP (*(__interrupt_vector_1 )) } > VECT1
	__interrupt_vector_2	: { KEEP (*(__interrupt_vector_2 )) } > VECT2
	__interrupt_vector_3	: { KEEP (*(__interrupt_vector_3 )) } > VECT3
	__interrupt_vector_4	: { KEEP (*(__interrupt_vector_4 )) } > VECT4
	__interrupt_vector_5	: { KEEP (*(__interrupt_vector_5 )) } > VECT5
	__interrupt_vector_6	: { KEEP (*(__interrupt_vector_6 )) } > VECT6
	__interrupt_vector_7	: { KEEP (*(__interrupt_vector_7 )) } > VECT7
	__interrupt_vector_8	: { KEEP (*(__interrupt_vector_8 )) } > VECT8
	__interrupt_vector_9	: { KEEP (*(__interrupt_vector_9 )) } > VECT9
	__interrupt_vector_10	: { KEEP (*(__interrupt_vector_10)) } > VECT10
	__interrupt_vector_11	: { KEEP (*(__interrupt_vector_11)) } > VECT11
	__interrupt_vector_12	: { KEEP (*(__interrupt_vector_12)) } > VECT12
	__interrupt_vector_13	: { KEEP (*(__interrupt_vector_13)) } > VECT13
	__interrupt_vector_14	: { KEEP (*(__interrupt_vector_14)) } > VECT14
	__interrupt_vector_15	: { KEEP (*(__interrupt_vector_15)) } > VECT15
	__interrupt_vector_16	: { KEEP (*(__interrupt_vector_16)) } > VECT16
	__interrupt_vector_17	: { KEEP (*(__interrupt_vector_17)) } > VECT17
	__interrupt_vector_18	: { KEEP (*(__interrupt_vector_18)) } > VECT18
	__interrupt_vector_19	: { KEEP (*(__interrupt_vector_19)) } > VECT19
	__interrupt_vector_20	: { KEEP (*(__interrupt_vector_20)) } > VECT20
	__interrupt_vector_21	: { KEEP (*(__interrupt_vector_21)) } > VECT21
	__interrupt_vector_22	: { KEEP (*(__interrupt_vector_22)) } > VECT22
	__interrupt_vector_23	: { KEEP (*(__interrupt_vector_23)) } > VECT23
	__interrupt_vector_24	: { KEEP (*(__interrupt_vector_24)) } > VECT24
	__interrupt_vector_25	: { KEEP (*(__interrupt_vector_25)) } > VECT25
	__interrupt_vector_26	: { KEEP (*(__interrupt_vector_26)) } > VECT26
	__interrupt_vector_27	: { KEEP (*(__interrupt_vector_27)) } > VECT27
	__interrupt_vector_28	: { KEEP (*(__interrupt_vector_28)) } > VECT28
	__interrupt_vector_29	: { KEEP (*(__interrupt_vector_29)) } > VECT29
	__interrupt_vector_30	: { KEEP (*(__interrupt_vector_30)) } > VECT30
	__interrupt_vector_31	: { KEEP (*(__interrupt_vector_31)) } > VECT31
	
	/* The program code and other data goes into RAM */
	.text :
	{
		PROVIDE (_start = .);
		. = ALIGN(4);
		*(.text)			/* .text sections (code) */
		*(.text*)			/* .text* sections (code) */
		*(.rodata)			/* .rodata sections (constants, strings, etc.) */
		*(.rodata*)			/* .rodata* sections (constants, strings, etc.) */
		*(.srodata)			/* .rodata sections (constants, strings, etc.) */
		*(.srodata*)		/* .rodata* sections (constants, strings, etc.) */
		. = ALIGN(4);
		_etext = .;			/* define a global symbol at end of code */
		_sidata = _etext;	/* This is used by the startup in order to initialize the .data secion */
	} > ROM
	
	
	/* This is the initialized data section
	The program executes knowing that the data is in the RAM
	but the loader puts the initial values in the FLASH (inidata).
	It is one task of the startup to copy the initial values from FLASH to RAM. */
	.data : AT ( _sidata )
	{
		. = ALIGN(4);
		_sdata = .;        /* create a global symbol at data start; used by startup code in order to initialise the .data section in RAM */
		_ram_start = .;    /* create a global symbol at ram start for garbage collector */
		. = ALIGN(4);
		*(.data)           /* .data sections */
		*(.data*)          /* .data* sections */
		*(.sdata)           /* .sdata sections */
		*(.sdata*)          /* .sdata* sections */
		. = ALIGN(4);
		_edata = .;        /* define a global symbol at data end; used by startup code in order to initialize the .data section in RAM */
	} > RAM
	
	/* Uninitialized data section */
	.bss :
	{
		. = ALIGN(4);
		_sbss = .;         /* define a global symbol at bss start; used by startup code */
		*(.bss)
		*(.bss*)
		*(.sbss)
		*(.sbss*)
		*(COMMON)
	
		. = ALIGN(4);
		_ebss = .;         /* define a global symbol at bss end; used by startup code */
	} > RAM
	
	/* this is to define the start of the heap, and make sure we have a minimum size */
	.heap :
	{
		. = ALIGN(4);
		_heap_start = .;    /* define a global symbol at heap start */
	} > RAM
	
	/*
	.stack (ORIGIN (RAM) + LENGTH(RAM))
	{
		PROVIDE (__stack = .);
		*(.stack)
	}
	*/
}
