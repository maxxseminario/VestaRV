OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x8200;
  .text : { *(.text.init) *(.text*) }
  . = 0x9100;
  .ldata : { LONG(0x11223344) LONG(0x55667788) }
}
