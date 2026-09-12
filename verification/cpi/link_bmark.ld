OUTPUT_ARCH( "riscv" )
ENTRY(_start)

/* RAM is the testbench window: 0x14000 bytes based at 0x8000, matching the
 * padded image the .rcf carries. _start is pinned at 0x8200 because that is
 * the core's PC_RST_VAL in this harness.
 *
 * THE WORKING SET IS BASED AT 0x10000, NOT LEFT TO RUN ON FROM .text
 * (2026-09-12). The window this harness models is flat, but the chip it models
 * is not: 0x8000-0x9FFF is the 8 KiB private TCM and 0xA000-0xBFFF is that
 * array's own upper mirror (hdl/common/hart_tile.vhd). A benchmark whose
 * arrays ran on from .text therefore addressed the mirror -- spmv's .rodata by
 * 35,744 bytes past the TCM, qsort's and rsort's .data by 16,384, dhrystone's
 * NOBITS .bss by 6,584 -- and //tools/build:verification_image_map_test read
 * exactly that back off the section headers.
 *
 * 0x10000 is the shared bulk RAM window on the part and plain flat RAM here,
 * so nothing about the measurement moves: .rodata, .data and .bss keep their
 * order, their alignment and their distance from __global_pointer$, which is
 * what fixes the instruction selection, and this harness's memory answers in
 * one cycle at every address. Only the absolute immediates change.
 *
 * .text stays in the TCM window. The largest benchmark text is spmv's, ending
 * 0x930B, so every image still fetches out of the private array. */
SECTIONS
{
  . = 0x00008000;
  .ivt : { KEEP(*(.ivt)) }

  .text.init 0x00008200 : SUBALIGN(4) { KEEP(*(.text.init)) }

  . = ALIGN(4);
  .text   : { *(.text .text.*) }

  /* The working set, based at the shared-RAM window. Keep .rodata, .data and
   * .bss adjacent and in this order: __global_pointer$ sits between .rodata
   * and .data, so their relative layout is what decides which symbols the
   * linker reaches gp-relative. */
  . = 0x00010000;
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
