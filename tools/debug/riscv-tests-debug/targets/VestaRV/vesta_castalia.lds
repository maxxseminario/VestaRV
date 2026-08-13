/* VestaRV "Castalia" link script for the riscv-tests/debug harness programs.
 *
 * LOCAL FILE (not vendored upstream) -- see ../../VENDORED.md.
 *
 * WHERE 0x14000 COMES FROM, AND WHY IT IS NOT A FREE CHOICE.
 *   The harness downloads each test program over the debug transport and runs
 *   it, so it must land in memory that (a) the Debug Module can write through
 *   the program buffer and (b) every hart can fetch from.  A tile's TCM
 *   (0x8000-0xBFFF) is PRIVATE to one hart and holds the session image, so it
 *   is neither.  That leaves the shared bulk RAM, 0x10000-0x1FFFF, and inside
 *   it exactly one unclaimed 16 KB window:
 *
 *     0x10000-0x104FF  test scratch + the D-series debug acceptance band
 *     0x10500-0x1061F  the bootrom loader rows (N=18 block)
 *     0x10680-0x1087F  the debug program page (DATA0/FLAGS/trampoline/progbuf)
 *     0x11000, 0x11800 shlock's JOURNAL and COUNTS
 *     0x14000-0x17FFF  <-- THIS WINDOW, claimed by nothing at either NHARTS
 *     0x18000-0x1BFFF  MP_STAGE_BASE, the tile image staging area
 *
 *   It is also what `vesta_castalia.py` declares as `ram`/`ram_size`, and the
 *   two must agree: the harness computes its own addresses (bad_address, the
 *   download target) from the Python declaration, and links here.  Change one,
 *   change both.
 *
 * WHAT THIS ADDRESS MAKES THE HARNESS EXERCISE, STATED IN ADVANCE.
 *   Programs linked here EXECUTE FROM THE SHARED WINDOW, through mp_arbiter.
 *   That path is proven (shexec.S, M10) for uncompressed code -- but the
 *   harness compiles with -march=rv32imac_zicsr whenever misa reports C, and
 *   CLAUDE.md records compressed/misaligned execution from shared as UNTESTED
 *   (shexec's payload is `.option norvc`).  So a harness failure that looks
 *   like a debugger problem may be that gap; it is named here so it is
 *   recognised rather than rediscovered.
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
