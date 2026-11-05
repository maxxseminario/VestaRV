/* Micro-kernel images: IVT + kernels in the private TCM (0x8000-0x9FFF), shared-fetch kernels at the
 * bottom of the shared bulk RAM (0x10900, above the bootrom mailbox and Debug Module pages). */
OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS
{
  . = 0x00008000;
  .ivt : { KEEP(*(.ivt)) }
  .text.init 0x00008200 : { *(.text.init) }
  ASSERT(. <= 0x9F00, "kernels overran the TCM scratch word")
  .text_sh 0x00010900 : { *(.text_sh) }
}
