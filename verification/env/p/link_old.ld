OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  /* IVT section at fixed address 0x8000 */
  . = 0x00008000;
  .ivt : { 
    KEEP(*(.ivt))
    . = ALIGN(4);
  }
  
  /* Text init section starts at 0x8050 */
  . = 0x00008050;
  .text.init : { *(.text.init) }
  . = ALIGN(0x1000);
  .tohost : { *(.tohost) }
  . = ALIGN(0x1000);
  .text : { *(.text) }
  . = ALIGN(0x1000);
  .data : { *(.data) }
  .bss : { *(.bss) }
  _end = .;
}