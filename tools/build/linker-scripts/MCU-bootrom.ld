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
	
	/* Uninitialised data that startup must NOT clear.
	   The Forth interpreter's arrays live here.
	   This used to be an ORPHAN section, which is exactly how 23,920 bytes of
	   it ran off the end of the TCM without anything noticing.  Naming it puts
	   it in the map file next to the region it has to fit in, and (NOLOAD)
	   pins it as NOBITS so it can never be emitted into the ROM image. */
	.noinit (NOLOAD) :
	{
		. = ALIGN(4);
		_snoinit = .;      /* define a global symbol at noinit start */
		*(.noinit)
		*(.noinit*)
		. = ALIGN(4);
		_enoinit = .;      /* define a global symbol at noinit end */
	} > RAM

	/* this is to define the start of the heap, and make sure we have a minimum size */
	.heap :
	{
		. = ALIGN(4);
		_heap_start = .;    /* define a global symbol at heap start */
	} > RAM
	
	/* The stack is not an output section: start.S loads sp directly with
	   SP_INIT_VAL, the top word of the private TCM.  Reserve the top of RAM for
	   it so that the ASSERT below can catch anything growing up into it. */
	_stack_size  = 1K;
	_stack_top   = ORIGIN(RAM) + LENGTH(RAM);
	_stack_limit = _stack_top - _stack_size;
	PROVIDE (__stack = _stack_top);
}

/* THE BOUND THAT WAS MISSING.
   RAM here is the per-hart private TCM, and it is the only private memory the
   tile has.  Anything the link places past the end of it does not fail and does
   not disappear: 0xA000-0xBFFF is the same 8 KiB array mirrored (the macro's
   top address bit is unconnected), and 0xC000 upwards is the shared NPU staging
   RAM behind the arbiter.  So an overflow here corrupts this hart's vectors and
   stack, and then other masters' memory, at run time only, silently.
   _stack_size is a reserve, not an allocation; measured worst case for this
   image is a 304 byte frame in execVM on a chain of about 500 bytes. */
ASSERT(_heap_start <= _stack_limit,
	"boot ROM RAM overflow: .data + .bss + .noinit have grown into the reserved stack area at the top of the private TCM. Shrink the rv4th arrays (see THE TCM BUDGET in rv4th.c), or lower _stack_size above and record why.")
