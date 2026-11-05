OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x8200;
  .text : { *(.text.init) }
  . = 0x10000;
  .flash : { *(.flash) }
}
