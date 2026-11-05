/* Reference image map. Spike reserves [0x0,0x2000); the body sits at the same
 * address as the DUT image, so a trap value that leaks an address cannot differ
 * between the two. Tests too large for the DUT's RAM still link here: the
 * reference memory region is sized by the plugin. */
OUTPUT_ARCH( "riscv" )
ENTRY(rvtest_entry_point)

SECTIONS
{
  . = 0x10900;
  .text.init : { *(.text.init) }
  .text : { *(.text) }
  . = ALIGN(16);
  .tohost : { *(.tohost) }
  . = ALIGN(16);
  .data : { *(.data) *(.data.string) }
  .bss : { *(.bss) }
  _end = .;
}
