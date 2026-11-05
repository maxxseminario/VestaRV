/* Interrupt-latency images: same placement as mpcpi.ld plus the ISR pinned at 0x9100, the address perf_mon watches. */
OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS
{
  . = 0x00008000;
  .ivt : { KEEP(*(.ivt)) }
  .text.init 0x00008200 : { *(.text.init) }
  ASSERT(. <= 0x9100, "image overran the ISR slot")
  .isr 0x00009100 : { KEEP(*(.isr)) }
  .text_sh 0x00010900 : { *(.text_sh) }
}
