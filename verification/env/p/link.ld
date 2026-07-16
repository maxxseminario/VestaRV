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



  /* NPU sections (M11 map).
   * .npu0_yhat is the TEST's expected-output copy: private TCM (0xB000).
   * .npu0_x / .npu0_w are the NPU's live vectors: the shared NPU staging
   * RAM at 0xC000-0xFFFF (was hart 0's private RAM1 -- same addresses; the
   * flash bootrom copy loop reaches them THROUGH the arbiter now). */

  . = 0xB000;  /* NPU 0 - Ideal Output Vector (TCM) */
  .npu0_yhat : {
    KEEP(*(.npu0_yhat))
    . = ALIGN(4);
  }

  . = 0xC000;  /* NPU 0 - Input Vector (shared NPU staging RAM) */
  .npu0_x : {
    KEEP(*(.npu0_x))
    . = ALIGN(4);
  }

  . = 0xE000;  /* NPU 0 - Weight Vector (shared NPU staging RAM) */
  .npu0_w : {
    KEEP(*(.npu0_w))
    . = ALIGN(4);
  }

  /* M11 ISR bank: every ISR lives INSIDE the private TCM (RAM1 is gone --
   * 0xC000-0xFFFF is the shared NPU staging RAM). 256 bytes per ISR,
   * 0xB200-0xBAFF; 0xBB00 is the unused-slot parking target (DEFINE_IVT).
   * The linker errors on overlap if an ISR outgrows its 256-byte slot. */

  /* M19: the meip (IVT slot 85) claim/complete dispatcher -- riscv_test.h
   * MEIP_DISPATCHER(). Empty unless the test invokes the macro. */
  . = 0x0B100;
  .isr_meip : {
    KEEP(*(.isr_meip))
    . = ALIGN(4);
  }

  . = 0x0B200;  /* IRQ 52 - UART1_RC */
  .isr_uart1_rc : {
    KEEP(*(.isr_uart1_rc))
    . = ALIGN(4);
  }

  . = 0x0B300;  /* IRQ 53 - UART1_TE */
  .isr_uart1_te : {
    KEEP(*(.isr_uart1_te))
    . = ALIGN(4);
  }

  . = 0x0B400;  /* IRQ 54 - UART1_TC */
  .isr_uart1_tc : {
    KEEP(*(.isr_uart1_tc))
    . = ALIGN(4);
  }

  . = 0x0B500;  /* IRQ 13 - UART0_RC */
  .isr_uart0_rc : {
    KEEP(*(.isr_uart0_rc))
    . = ALIGN(4);
  }

  . = 0x0B600;  /* IRQ 14 - UART0_TE */
  .isr_uart0_te : {
    KEEP(*(.isr_uart0_te))
    . = ALIGN(4);
  }

  . = 0x0B700;  /* IRQ 15 - UART0_TC */
  .isr_uart0_tc : {
    KEEP(*(.isr_uart0_tc))
    . = ALIGN(4);
  }

  . = 0x0B800;  /* IRQ 0 - SYSTEM WDT */
  .isr_sys_wdt : {
    KEEP(*(.isr_sys_wdt))
    . = ALIGN(4);
  }

  . = 0x0B900;  /* IRQ 9 - SPI0_TC */
  .isr_spi0_tc : {
    KEEP(*(.isr_spi0_tc))
    . = ALIGN(4);
  }

  . = 0x0BA00;  /* IRQ 10 - SPI0_TE */
  .isr_spi0_te : {
    KEEP(*(.isr_spi0_te))
    . = ALIGN(4);
  }

  /* CQ2b: the two ex-analog reserved sources (55/56) get real meip handler
   * slots ABOVE the 0xBB00 parking word (still inside the private TCM, inside
   * the uniform 4096-word tile stage/copy). Empty unless a test (shafe.S)
   * invokes the source-55/56 handlers; DEFINE_IVT points slots 55/56 here. */
  . = 0x0BC00;  /* IRQ 55 - AFE_SHARED (OR of the four AFE IF levels) */
  .isr_afe_shared : {
    KEEP(*(.isr_afe_shared))
    . = ALIGN(4);
  }

  . = 0x0BD00;  /* IRQ 56 - EIS engine level */
  .isr_eis : {
    KEEP(*(.isr_eis))
    . = ALIGN(4);
  }




  /* End marker */
  _end = .;
}