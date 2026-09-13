/* VestaRV: link script for the riscv-tests/debug harness programs on Castalia.
 * Local file, not vendored upstream; see ../../VENDORED.md.
 * THE LOAD ADDRESS 0x14000 IS NOT A FREE CHOICE. The harness downloads each program over
 * the debug transport and runs it, so it must land where the Debug Module can write it
 * through the program buffer and every hart can fetch it. A tile's TCM is private to one
 * hart and holds the session image, so the only candidate is the shared bulk RAM, and
 * inside it 0x14000-0x17FFF is the one 16 KB window claimed by nothing at either hart
 * count: below it lie the test scratch and debug bands, the boot ROM loader rows, the
 * debug program page and shlock's journal and counts, and above it the tile image
 * staging area.
 * IT MUST MATCH `ram` AND `ram_size` IN vesta_castalia.py, because the harness computes
 * bad_address and the download target from the Python declaration and links here.
 * Programs linked here EXECUTE FROM THE SHARED WINDOW through mp_arbiter. That path is
 * proven for uncompressed code only, and the harness compiles with compressed enabled
 * whenever misa reports C, so a harness failure that looks like a debugger problem may
 * be that gap.
 */

OUTPUT_ARCH( "riscv" )

SECTIONS
{
  . = 0x00014000;

  .text :
  {
    *(.text.entry)
    *(.text)
    *(.text.*)
  }

  .rodata : { *(.rodata .rodata.*) }

  .data : { *(.data .data.*) }

  .sdata : {
    __global_pointer$ = . + 0x800;
    *(.srodata.cst16) *(.srodata.cst8) *(.srodata.cst4) *(.srodata.cst2)
    *(.srodata*)
    *(.sdata .sdata.* .gnu.linkonce.s.*)
  }

  __bss_start = .;
  .sbss : {
    *(.sbss .sbss.* .gnu.linkonce.sb.*)
    *(.scommon)
  }
  .bss : { *(.bss .bss.*) }
  __bss_end = .;

  __malloc_start = .;
  . = . + 512;

  _end = .;

  /* The window is 16 KB and its upper neighbour (0x18000) is the tile image
   * staging area, so an overrun would corrupt a DIFFERENT subsystem silently.
   * Fail at link time instead. */
  ASSERT(_end <= 0x00018000,
         "VestaRV: the harness program overran the 0x14000-0x17FFF shared window")
}
