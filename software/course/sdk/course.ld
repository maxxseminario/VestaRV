/* course.ld -- VestaRV course SDK linker script.
 *
 * Single-hart course program laid out for the shared-ROM boot contract:
 *   - IVT window   0x8000 - 0x81FF   (.ivt, from crt0.S; 512 bytes)
 *   - entry _start 0x8200            (.text.init; the bootrom jumps here)
 *   - code/data    follow in the private TCM (0x8000-0xBFFF)
 *   - stack top    0xBFF0            (grows down; set by crt0.S)
 *
 * Modeled on verification/env/p/link.ld (the proven ISA-test layout) but
 * trimmed to what a course lab needs (no ISR bank, no NPU sections).
 */

OUTPUT_ARCH( "riscv" )
ENTRY(_start)

__stack_top = 0x0000BFF0;

SECTIONS
{
  /* Interrupt vector table, fixed at 0x8000 (crt0.S fills 512 bytes). */
  . = 0x00008000;
  .ivt : { KEEP(*(.ivt)) }

  /* Runtime + program entry. SUBALIGN(4) pins _start at 0x8200 exactly
     (the address the bootrom jumps to), regardless of section alignment. */
  . = 0x00008200;
  .text.init 0x00008200 : SUBALIGN(4) { KEEP(*(.text.init)) }

  .text : {
    *(.text.unlikely .text.unlikely.*)
    *(.text .text.*)
  }

  . = ALIGN(4);
  .rodata : {
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
  }

  . = ALIGN(8);
  __global_pointer$ = . + 0x400;
  .data : {
    *(.data .data.*)
    *(.sdata .sdata.*)
  }

  . = ALIGN(4);
  __bss_start = .;
  .bss (NOLOAD) : {
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
  }
  . = ALIGN(4);
  __bss_end = .;
  _end = .;

  /DISCARD/ : {
    *(.comment)
    *(.note .note.*)
    *(.riscv.attributes)
    *(.eh_frame .eh_frame_hdr)
  }
}
