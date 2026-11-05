/* VestaRV RISCOF image map.
 *
 * .vesta_stub  hart 0 launcher at 0x8200, the bootrom's default entry.
 * .vesta_cfg   one word, the target hart, patched per image by mk_rcf.py.
 * .vesta_tcm_text  the arch-test trap handlers, in TCM on every hart: a tile gets
 *              a copy through the bootrom loader, from the shadow mk_rcf.py writes
 *              at 0x1E000. See sim/patch_arch_test.py for why they cannot stay in
 *              shared RAM.
 * .text.init   test body in shared bulk RAM above the mailbox rows and the
 *              Debug Module program page, 0x10900, so every hart can fetch it.
 * .data        signature and test data, directly after the body.
 *
 * An image that does not fit shared RAM below the shadow fails here at link time.
 */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  . = 0x8200;
  .vesta_stub : { *(.vesta_stub) }
  . = 0x8800;
  .vesta_cfg : { *(.vesta_cfg) }
  . = 0x8840;
  .vesta_tcm_text : { *(.vesta_tcm_text) }
  . = ALIGN(4);
  vesta_tcm_end = .;
  ASSERT(vesta_tcm_end <= 0x9FF0, "TCM image exceeds the 8 KiB array")

  . = 0x10900;
  .text.init : { *(.text.init) }
  .text : { *(.text) }
  . = ALIGN(16);
  .data : { *(.data) *(.data.string) }
  .bss : { *(.bss) }
  _end = .;
  ASSERT(_end <= 0x1E000, "image exceeds shared bulk RAM below the TCM shadow")
}
