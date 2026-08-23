OUTPUT_ARCH( "riscv" )
ENTRY(_start)

/* RAM is the testbench window: 0x14000 bytes based at 0x8000, matching the
 * padded image the .rcf carries. _start is pinned at 0x8200 because that is
 * the core's PC_RST_VAL in this harness. */
SECTIONS
{
  . = 0x00008000;
  .ivt : { KEEP(*(.ivt)) }

  .text.init 0x00008200 : SUBALIGN(4) { KEEP(*(.text.init)) }

  . = ALIGN(4);
  .text   : { *(.text .text.*) }

  . = ALIGN(4);
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) }

  . = ALIGN(8);
  __global_pointer$ = . + 0x800;
  .data   : { *(.data .data.*) *(.sdata .sdata.*) }

  . = ALIGN(4);
  .bss    : {
    __bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  }

  _end = .;

  /* Stack grows down from the top of the RAM window. */
  _stack_top = 0x0001BFF0;
}
