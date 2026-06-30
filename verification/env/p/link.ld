OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  /* IVT section at fixed address 0x8000 */
  . = 0x00008000;
  .ivt : { 
    KEEP(*(.ivt))
    . = ALIGN(4);
  }

  /* Text init section starts at 0x8200, where the boot ROM / IVT jumps to
   * _start. SUBALIGN(4) pins the section (and _start) at 0x8200 even when a
   * test forces a large section alignment: rv32uc's rvc.S has an internal
   * `.align 12` (its cross-page fetch test) that otherwise propagates 4 KB
   * alignment to .text.init, bumping the whole section — and _start — to the
   * next 4 KB boundary (0x9000) and breaking the hardcoded jump to _start at
   * 0x8200. The internal `.align 12` is still honored by the linker's
   * R_RISCV_ALIGN handling, so the cross-page test data stays 4 KB-aligned. */
  . = 0x00008200;
  .text.init 0x00008200 : SUBALIGN(4) { *(.text.init) }

  /* Remove the ALIGN(0x1000) that was causing the issue */
  .tohost : { *(.tohost) }
  . = ALIGN(4);  /* Use smaller alignment */
  .text : { *(.text) }

  /* Place .data and .bss sections immediately after .text */
  . = ALIGN(4);
  .data : { *(.data) }
  .bss : { *(.bss) }



  /* NPU sections at their specific addresses */
  /* NPU weights may only be stored in ram2, offset = 0x10000, 16KB */

  . = 0xB000;  /* NPU 0 - Ideal Output Vector */
  .npu0_yhat : {
    KEEP(*(.npu0_yhat))
    . = ALIGN(4);
  }

  . = 0xC000;  /* NPU 0 - Input Vector */
  .npu0_x : {
    KEEP(*(.npu0_x))
    . = ALIGN(4);
  }

  . = 0xE000;  /* NPU 0 - Weight Vector */
  .npu0_w : {
    KEEP(*(.npu0_w))
    . = ALIGN(4);
  }




    /* ISR sections at their specific addresses */
  /* Each ISR gets 512 bytes (0x200) of space */

  /* ISR sections at their specific addresses */
  /* Each ISR gets 512 bytes (0x200) of space */


  . = 0x0ED00;  /* IRQ 52 - UART1_RC */
  .isr_uart1_rc : {
    KEEP(*(.isr_uart1_rc))
    . = ALIGN(4);
  }

  . = 0x0F000;  /* IRQ 53 - UART1_TE */
  .isr_uart1_te : {
    KEEP(*(.isr_uart1_te))
    . = ALIGN(4);
  }

  . = 0x0F200;  /* IRQ 54 - UART1_TC */
  .isr_uart1_tc : {
    KEEP(*(.isr_uart1_tc))
    . = ALIGN(4);
  }



  . = 0x0F400;  /* IRQ 13 - UART0_RC */
  .isr_uart0_rc : {
    KEEP(*(.isr_uart0_rc))
    . = ALIGN(4);
  }

  . = 0x0F600;  /* IRQ 14 - UART0_TE */
  .isr_uart0_te : {
    KEEP(*(.isr_uart0_te))
    . = ALIGN(4);
  }

  . = 0x0F800;  /* IRQ 15 - UART0_TC */
  .isr_uart0_tc : {
    KEEP(*(.isr_uart0_tc))
    . = ALIGN(4);
  }

  . = 0x0FA00;  /* IRQ 0 - SYSTEM WDT */        
  .isr_sys_wdt : {
    KEEP(*(.isr_sys_wdt))
    . = ALIGN(4);
  }

  . = 0x0FC00;  /* IRQ 9 - SPI0_TC */
  .isr_spi0_tc : {
    KEEP(*(.isr_spi0_tc))
    . = ALIGN(4);
  }

  . = 0x0FE00;  /* IRQ 10 - SPI0_TE */
  .isr_spi0_te : {
    KEEP(*(.isr_spi0_te))
    . = ALIGN(4);
  }



 
  /* End marker */
  _end = .;
}