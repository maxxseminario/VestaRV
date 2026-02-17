/* Default linker script, for normal executables */
/* Copyright (C) 2014-2019 Free Software Foundation, Inc.
	 Copying and distribution of this script, with or without modification,
	 are permitted in any medium without royalty provided the copyright
	 notice and this notice are preserved.  */
OUTPUT_FORMAT("elf32-littleriscv", "elf32-littleriscv", "elf32-littleriscv")
OUTPUT_ARCH(riscv)
ENTRY(__start_RAM_program__)

INCLUDE memory.x
INCLUDE periph.x

SECTIONS
{
	/* The interrupt vector table */
	.__interrupt_vector_table :
	{
		PROVIDE (_start = .);
		. = ALIGN(4);
		_interrupt_vector_table = .;
	} > vectors

	/* Each memory-mapped interrupt vector */
	.__interrupt_vector_0	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT0
	.__interrupt_vector_1	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT1
	.__interrupt_vector_2	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT2
	.__interrupt_vector_3	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT3
	.__interrupt_vector_4	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT4
	.__interrupt_vector_5	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT5
	.__interrupt_vector_6	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT6
	.__interrupt_vector_7	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT7
	.__interrupt_vector_8	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT8
	.__interrupt_vector_9	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT9
	.__interrupt_vector_10	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT10
	.__interrupt_vector_11	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT11
	.__interrupt_vector_12	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT12
	.__interrupt_vector_13	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT13
	.__interrupt_vector_14	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT14
	.__interrupt_vector_15	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT15
	.__interrupt_vector_16	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT16
	.__interrupt_vector_17	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT17
	.__interrupt_vector_18	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT18
	.__interrupt_vector_19	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT19
	.__interrupt_vector_20	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT20
	.__interrupt_vector_21	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT21
	.__interrupt_vector_22	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT22
	.__interrupt_vector_23	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT23
	.__interrupt_vector_24	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT24
	.__interrupt_vector_25	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT25
	.__interrupt_vector_26	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT26
	.__interrupt_vector_27	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT27
	.__interrupt_vector_28	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT28
	.__interrupt_vector_29	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT29
	.__interrupt_vector_30	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT30
	.__interrupt_vector_31	: { PROVIDE (_start = .); . = ALIGN(4); } > VECT31
	
	
	/* The text section, where the program is stored */
	.text :
	{
		/* This is the section for the start assembly function in start.S, the first thing that the bootloader calls once it finishes loading the program from the SPI flash. It is exactly 16 bytes long. */
		. = ALIGN(4);
		__program_start_start__ = .;
		*(.program_start*)
		__program_start_end__ = .;
		. = ALIGN(16);
		
		/* This is the master interrupt section, which must come exactly 16 bytes after the __start_RAM_program__ function. */
		*(.text.master_interrupt*)
		
		/* This is the rest of the .text section */
		*(.text.unlikely .text.*_unlikely .text.unlikely.*)
		*(.text.exit .text.exit.*)
		*(.text.startup .text.startup.*)
		*(.text.hot .text.hot.*)
		*(.text .stub .text.* .gnu.linkonce.t.*)
		/* .gnu.warning sections are handled specially by elf32.em.  */
		*(.gnu.warning)
	} > RAM	/* TODO: Change this if you want for smaller sized chips */
	
	
	
	/* Read-only sections, merged into text segment: */
	.interp         : { *(.interp) }
	.note.gnu.build-id  : { *(.note.gnu.build-id) }
	.hash           : { *(.hash) }
	.gnu.hash       : { *(.gnu.hash) }
	.dynsym         : { *(.dynsym) }
	.dynstr         : { *(.dynstr) }
	.gnu.version    : { *(.gnu.version) }
	.gnu.version_d  : { *(.gnu.version_d) }
	.gnu.version_r  : { *(.gnu.version_r) }
	.rela.init      : { *(.rela.init) }
	.rela.text      : { *(.rela.text .rela.text.* .rela.gnu.linkonce.t.*) }
	.rela.fini      : { *(.rela.fini) }
	.rela.rodata    : { *(.rela.rodata .rela.rodata.* .rela.gnu.linkonce.r.*) }
	.rela.data.rel.ro   : { *(.rela.data.rel.ro .rela.data.rel.ro.* .rela.gnu.linkonce.d.rel.ro.*) }
	.rela.data      : { *(.rela.data .rela.data.* .rela.gnu.linkonce.d.*) }
	.rela.tdata	  : { *(.rela.tdata .rela.tdata.* .rela.gnu.linkonce.td.*) }
	.rela.tbss	  : { *(.rela.tbss .rela.tbss.* .rela.gnu.linkonce.tb.*) }
	.rela.ctors     : { *(.rela.ctors) }
	.rela.dtors     : { *(.rela.dtors) }
	.rela.got       : { *(.rela.got) }
	.rela.sdata     : { *(.rela.sdata .rela.sdata.* .rela.gnu.linkonce.s.*) }
	.rela.sbss      : { *(.rela.sbss .rela.sbss.* .rela.gnu.linkonce.sb.*) }
	.rela.sdata2    : { *(.rela.sdata2 .rela.sdata2.* .rela.gnu.linkonce.s2.*) }
	.rela.sbss2     : { *(.rela.sbss2 .rela.sbss2.* .rela.gnu.linkonce.sb2.*) }
	.rela.bss       : { *(.rela.bss .rela.bss.* .rela.gnu.linkonce.b.*) }
	.rela.iplt      :
		{
			PROVIDE_HIDDEN (__rela_iplt_start = .);
			*(.rela.iplt)
			PROVIDE_HIDDEN (__rela_iplt_end = .);
		}
	.rela.plt       :
		{
			*(.rela.plt)
		}
	.init           :
	{
		KEEP (*(SORT_NONE(.init)))
	}
	.plt            : { *(.plt) }
	.iplt           : { *(.iplt) }
	
	/* TODO: Add extra memory sections */
	.NN0SRAM : { PROVIDE (_start = .); . = ALIGN(4); } > NPU0_RAM
	.AFE0_HISTOGRAM_RAM : { PROVIDE (_start = .); . = ALIGN(4); } > AFE0_HISTOGRAM_RAM
	.AFE1_HISTOGRAM_RAM : { PROVIDE (_start = .); . = ALIGN(4); } > AFE1_HISTOGRAM_RAM
	.AFE2_HISTOGRAM_RAM : { PROVIDE (_start = .); . = ALIGN(4); } > AFE2_HISTOGRAM_RAM
	.AFE3_HISTOGRAM_RAM : { PROVIDE (_start = .); . = ALIGN(4); } > AFE3_HISTOGRAM_RAM
	.AFE4_HISTOGRAM_RAM : { PROVIDE (_start = .); . = ALIGN(4); } > AFE4_HISTOGRAM_RAM
	.AFE5_HISTOGRAM_RAM : { PROVIDE (_start = .); . = ALIGN(4); } > AFE5_HISTOGRAM_RAM
	
	.fini           :
	{
		KEEP (*(SORT_NONE(.fini)))
	}
	PROVIDE (__etext = .);
	PROVIDE (_etext = .);
	PROVIDE (etext = .);
	.rodata         : { *(.rodata .rodata.* .gnu.linkonce.r.*) } > RAM	/* TODO: Change this if you want for smaller sized chips */
	.rodata1        : { *(.rodata1) }
	.sdata2         :
	{
		*(.sdata2 .sdata2.* .gnu.linkonce.s2.*)
	}
	.sbss2          : { *(.sbss2 .sbss2.* .gnu.linkonce.sb2.*) }
	.gcc_except_table   : ONLY_IF_RO { *(.gcc_except_table .gcc_except_table.*) }
	.gnu_extab   : ONLY_IF_RO { *(.gnu_extab*) }
	/* These sections are generated by the Sun/Oracle C++ compiler.  */
	.exception_ranges   : ONLY_IF_RO { *(.exception_ranges*) }
	/* Adjust the address for the data segment.  We want to adjust up to
		the same address within the page on the next page up.  */
	. = DATA_SEGMENT_ALIGN (CONSTANT (MAXPAGESIZE), CONSTANT (COMMONPAGESIZE));
	/* Exception handling  */
	.gnu_extab      : ONLY_IF_RW { *(.gnu_extab) }
	.gcc_except_table   : ONLY_IF_RW { *(.gcc_except_table .gcc_except_table.*) }
	.exception_ranges   : ONLY_IF_RW { *(.exception_ranges*) }
	/* Thread Local Storage sections  */
	.tdata	  :
	 {
		 PROVIDE_HIDDEN (__tdata_start = .);
		 *(.tdata .tdata.* .gnu.linkonce.td.*)
	 }
	.tbss		  : { *(.tbss .tbss.* .gnu.linkonce.tb.*) *(.tcommon) }
	.preinit_array    :
	{
		PROVIDE_HIDDEN (__preinit_array_start = .);
		KEEP (*(.preinit_array))
		PROVIDE_HIDDEN (__preinit_array_end = .);
	} > RAM	/* TODO: Change this if you want for smaller sized chips */
	.init_array    :
	{
		PROVIDE_HIDDEN (__init_array_start = .);
		KEEP (*(SORT_BY_INIT_PRIORITY(.init_array.*) SORT_BY_INIT_PRIORITY(.ctors.*)))
		KEEP (*(.init_array EXCLUDE_FILE (*crtbegin.o *crtbegin?.o *crtend.o *crtend?.o ) .ctors))
		PROVIDE_HIDDEN (__init_array_end = .);
	} > RAM	/* TODO: Change this if you want for smaller sized chips */
	.fini_array    :
	{
		PROVIDE_HIDDEN (__fini_array_start = .);
		KEEP (*(SORT_BY_INIT_PRIORITY(.fini_array.*) SORT_BY_INIT_PRIORITY(.dtors.*)))
		KEEP (*(.fini_array EXCLUDE_FILE (*crtbegin.o *crtbegin?.o *crtend.o *crtend?.o ) .dtors))
		PROVIDE_HIDDEN (__fini_array_end = .);
	} > RAM	/* TODO: Change this if you want for smaller sized chips */
	.ctors          :
	{
		/* gcc uses crtbegin.o to find the start of
			 the constructors, so we make sure it is
			 first.  Because this is a wildcard, it
			 doesn't matter if the user does not
			 actually link against crtbegin.o; the
			 linker won't look for a file to match a
			 wildcard.  The wildcard also means that it
			 doesn't matter which directory crtbegin.o
			 is in.  */
		KEEP (*crtbegin.o(.ctors))
		KEEP (*crtbegin?.o(.ctors))
		/* We don't want to include the .ctor section from
			 the crtend.o file until after the sorted ctors.
			 The .ctor section from the crtend file contains the
			 end of ctors marker and it must be last */
		KEEP (*(EXCLUDE_FILE (*crtend.o *crtend?.o ) .ctors))
		KEEP (*(SORT(.ctors.*)))
		KEEP (*(.ctors))
	} > RAM	/* TODO: Change this if you want for smaller sized chips */
	.dtors          :
	{
		KEEP (*crtbegin.o(.dtors))
		KEEP (*crtbegin?.o(.dtors))
		KEEP (*(EXCLUDE_FILE (*crtend.o *crtend?.o ) .dtors))
		KEEP (*(SORT(.dtors.*)))
		KEEP (*(.dtors))
	} > RAM	/* TODO: Change this if you want for smaller sized chips */
	.jcr            : { KEEP (*(.jcr)) }
	.data.rel.ro : { *(.data.rel.ro.local* .gnu.linkonce.d.rel.ro.local.*) *(.data.rel.ro .data.rel.ro.* .gnu.linkonce.d.rel.ro.*) }
	.dynamic        : { *(.dynamic) }
	. = DATA_SEGMENT_RELRO_END (0, .);
	.data           :
	{
		__DATA_BEGIN__ = .;
		*(.data .data.* .gnu.linkonce.d.*)
		SORT(CONSTRUCTORS)
	} > RAM	/* TODO: Change this if you want for smaller sized chips */
	.data1          : { *(.data1) }
	.got            : { *(.got.plt) *(.igot.plt) *(.got) *(.igot) }
	/* We want the small data sections together, so single-instruction offsets
		 can access them all, and initialized data all before uninitialized, so
		 we can shorten the on-disk segment size.  */
	.sdata          :
	{
		__SDATA_BEGIN__ = .;
		*(.srodata.cst16) *(.srodata.cst8) *(.srodata.cst4) *(.srodata.cst2) *(.srodata .srodata.*)
		*(.sdata .sdata.* .gnu.linkonce.s.*)
	} > RAM	/* TODO: Change this if you want for smaller sized chips */
	_edata = .; PROVIDE (edata = .);
	. = .;
	__bss_start = .;
	.sbss           :
	{
		*(.dynsbss)
		*(.sbss .sbss.* .gnu.linkonce.sb.*)
		*(.scommon)
	} > RAM	/* TODO: Change this if you want for smaller sized chips */
	.bss            :
	{
		*(.dynbss)
		*(.bss .bss.* .gnu.linkonce.b.*)
		*(COMMON)
		/* Align here to ensure that the .bss section occupies space up to
			_end.  Align after .bss to ensure correct alignment even if the
			.bss section disappears because there are no input sections.
			FIXME: Why do we need it? When there is no .bss section, we do not
			pad the .data section.  */
		. = ALIGN(. != 0 ? 32 / 8 : 1);
	} > RAM	/* TODO: Change this if you want for smaller sized chips */
	. = ALIGN(32 / 8);
	. = SEGMENT_START("ldata-segment", .);
	. = ALIGN(32 / 8);
	__BSS_END__ = .;
		__global_pointer$ = MIN(__SDATA_BEGIN__ + 0x800,
		            MAX(__DATA_BEGIN__ + 0x800, __BSS_END__ - 0x800));
	_end = .; PROVIDE (end = .);
	. = DATA_SEGMENT_END (.);
	/* Stabs debugging sections.  */
	.stab          0 : { *(.stab) }
	.stabstr       0 : { *(.stabstr) }
	.stab.excl     0 : { *(.stab.excl) }
	.stab.exclstr  0 : { *(.stab.exclstr) }
	.stab.index    0 : { *(.stab.index) }
	.stab.indexstr 0 : { *(.stab.indexstr) }
	
	.gnu.build.attributes : { *(.gnu.build.attributes .gnu.build.attributes.*) }
	/* DWARF debug sections.
		 Symbols in the DWARF debugging sections are relative to the beginning
		 of the section so we begin them at 0.  */
	/* DWARF 1 */
	.debug          0 : { *(.debug) }
	.line           0 : { *(.line) }
	/* GNU DWARF 1 extensions */
	.debug_srcinfo  0 : { *(.debug_srcinfo) }
	.debug_sfnames  0 : { *(.debug_sfnames) }
	/* DWARF 1.1 and DWARF 2 */
	.debug_aranges  0 : { *(.debug_aranges) }
	.debug_pubnames 0 : { *(.debug_pubnames) }
	/* DWARF 2 */
	.debug_info     0 : { *(.debug_info .gnu.linkonce.wi.*) }
	.debug_abbrev   0 : { *(.debug_abbrev) }
	.debug_line     0 : { *(.debug_line .debug_line.* .debug_line_end) }
	.debug_frame    0 : { *(.debug_frame) }
	.debug_str      0 : { *(.debug_str) }
	.debug_loc      0 : { *(.debug_loc) }
	.debug_macinfo  0 : { *(.debug_macinfo) }
	/* SGI/MIPS DWARF 2 extensions */
	.debug_weaknames 0 : { *(.debug_weaknames) }
	.debug_funcnames 0 : { *(.debug_funcnames) }
	.debug_typenames 0 : { *(.debug_typenames) }
	.debug_varnames  0 : { *(.debug_varnames) }
	/* DWARF 3 */
	.debug_pubtypes 0 : { *(.debug_pubtypes) }
	.debug_ranges   0 : { *(.debug_ranges) }
	/* DWARF Extension.  */
	.debug_macro    0 : { *(.debug_macro) }
	.debug_addr     0 : { *(.debug_addr) }
	.gnu.attributes 0 : { KEEP (*(.gnu.attributes)) }
	/DISCARD/ : { *(.note.GNU-stack) *(.gnu_debuglink) *(.gnu.lto_*) }
	
	
	
	/* Unused data */
	.comment       : { *(.comment) } > UNUSED
	.riscv.attributes	: { *(.riscv.attributes) } > UNUSED
	.eh_frame_hdr   : { *(.eh_frame_hdr) *(.eh_frame_entry .eh_frame_entry.*) } > UNUSED
	.eh_frame       : ONLY_IF_RO { KEEP (*(.eh_frame)) *(.eh_frame.*) } > UNUSED
	.eh_frame       : ONLY_IF_RW { KEEP (*(.eh_frame)) *(.eh_frame.*) } > UNUSED
}

/* Check if PROGRAM_START usage exceeds PROGRAM_START size */
ASSERT((__program_start_end__ - __program_start_start__) <= 16, "__start_RAM_program__ function in start.S is too large! Only 16 bytes are allowed in it.")
ASSERT((__program_start_end__ - __program_start_start__) > 0, "__start_RAM_program__ must be greater than 0 bytes long")
