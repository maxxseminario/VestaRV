OUTPUT_ARCH( "riscv" )
ENTRY(_start)

SECTIONS
{
  /* IVT section at fixed address 0xa000 */
  . = 0x0000a000;
  .ivt : { 
    KEEP(*(.ivt))
    . = ALIGN(4);
  }

  /* Text init section starts at 0xa100 */
  . = 0x0000a100;
  .text.init : { *(.text.init) }

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

  . = 0xC000;  /* NPU 0 - Ideal Output Vector */
  .npu0_yhat : {
    KEEP(*(.npu0_yhat))
    . = ALIGN(4);
  }

  . = 0x10000;  /* NPU 0 - Input Vector */
  .npu0_x : {
    KEEP(*(.npu0_x))
    . = ALIGN(4);
  }

  . = 0x12000;  /* NPU 0 - Weight Vector */
  .npu0_w : {
    KEEP(*(.npu0_w))
    . = ALIGN(4);
  }


  

/* ISR sections at their specific addresses */
  /* Each ISR gets 512 bytes (0x200) of space */

  . = 0x0C800;  /* IRQ 0 - SYSTEM WDT */        
  .isr_sys_wdt : {
    KEEP(*(.isr_sys_wdt))
    . = ALIGN(4);
  }

  . = 0x0CA00;  /* IRQ 1 - GPIO0_B0 */
  .isr_gpio0_b0 : {
    KEEP(*(.isr_gpio0_b0))
    . = ALIGN(4);
  }

  . = 0x0CC00;  /* IRQ 2 - GPIO0_B1 */
  .isr_gpio0_b1 : {
    KEEP(*(.isr_gpio0_b1))
    . = ALIGN(4);
  }

  . = 0x0CE00;  /* IRQ 3 - GPIO0_B2 */
  .isr_gpio0_b2 : {
    KEEP(*(.isr_gpio0_b2))
    . = ALIGN(4);
  }

  . = 0x0D000;  /* IRQ 4 - GPIO0_B3 */
  .isr_gpio0_b3 : {
    KEEP(*(.isr_gpio0_b3))
    . = ALIGN(4);
  }

  . = 0x0D200;  /* IRQ 5 - GPIO0_B4 */
  .isr_gpio0_b4 : {
    KEEP(*(.isr_gpio0_b4))
    . = ALIGN(4);
  }

  . = 0x0D400;  /* IRQ 6 - GPIO0_B5 */
  .isr_gpio0_b5 : {
    KEEP(*(.isr_gpio0_b5))
    . = ALIGN(4);
  }

  . = 0x0D600;  /* IRQ 7 - GPIO0_B6 */
  .isr_gpio0_b6 : {
    KEEP(*(.isr_gpio0_b6))
    . = ALIGN(4);
  }

  . = 0x0D800;  /* IRQ 8 - GPIO0_B7 */
  .isr_gpio0_b7 : {
    KEEP(*(.isr_gpio0_b7))
    . = ALIGN(4);
  }

  . = 0x0DA00;  /* IRQ 9 - SPI0_TC */
  .isr_spi0_tc : {
    KEEP(*(.isr_spi0_tc))
    . = ALIGN(4);
  }

  . = 0x0DC00;  /* IRQ 10 - SPI0_TE */
  .isr_spi0_te : {
    KEEP(*(.isr_spi0_te))
    . = ALIGN(4);
  }

  . = 0x0DE00;  /* IRQ 11 - SPI1_TC */
  .isr_spi1_tc : {
    KEEP(*(.isr_spi1_tc))
    . = ALIGN(4);
  }

  . = 0x0E000;  /* IRQ 12 - SPI1_TE */
  .isr_spi1_te : {
    KEEP(*(.isr_spi1_te))
    . = ALIGN(4);
  }

  . = 0x0E200;  /* IRQ 13 - UART0_RC */
  .isr_uart0_rc : {
    KEEP(*(.isr_uart0_rc))
    . = ALIGN(4);
  }

  . = 0x0E400;  /* IRQ 14 - UART0_TE */
  .isr_uart0_te : {
    KEEP(*(.isr_uart0_te))
    . = ALIGN(4);
  }

  . = 0x0E600;  /* IRQ 15 - UART0_TC */
  .isr_uart0_tc : {
    KEEP(*(.isr_uart0_tc))
    . = ALIGN(4);
  }

  . = 0x0E800;  /* IRQ 16 - TIM0_CAP0 */
  .isr_tim0_cap0 : {
    KEEP(*(.isr_tim0_cap0))
    . = ALIGN(4);
  }

  . = 0x0EA00;  /* IRQ 17 - TIM0_CAP1 */
  .isr_tim0_cap1 : {
    KEEP(*(.isr_tim0_cap1))
    . = ALIGN(4);
  }

  . = 0x0EC00;  /* IRQ 18 - TIM0_OVF */
  .isr_tim0_ovf : {
    KEEP(*(.isr_tim0_ovf))
    . = ALIGN(4);
  }

  . = 0x0EE00;  /* IRQ 19 - TIM0_CMP0 */
  .isr_tim0_cmp0 : {
    KEEP(*(.isr_tim0_cmp0))
    . = ALIGN(4);
  }

  . = 0x0F000;  /* IRQ 20 - TIM0_CMP1 */
  .isr_tim0_cmp1 : {
    KEEP(*(.isr_tim0_cmp1))
    . = ALIGN(4);
  }

  . = 0x0F200;  /* IRQ 21 - TIM0_CMP2 */
  .isr_tim0_cmp2 : {
    KEEP(*(.isr_tim0_cmp2))
    . = ALIGN(4);
  }

  . = 0x0F400;  /* IRQ 22 - TIM1_CAP0 */
  .isr_tim1_cap0 : {
    KEEP(*(.isr_tim1_cap0))
    . = ALIGN(4);
  }

  . = 0x0F600;  /* IRQ 23 - TIM1_CAP1 */
  .isr_tim1_cap1 : {
    KEEP(*(.isr_tim1_cap1))
    . = ALIGN(4);
  }

  . = 0x0F800;  /* IRQ 24 - TIM1_OVF */
  .isr_tim1_ovf : {
    KEEP(*(.isr_tim1_ovf))
    . = ALIGN(4);
  }

  . = 0x0FA00;  /* IRQ 25 - TIM1_CMP0 */
  .isr_tim1_cmp0 : {
    KEEP(*(.isr_tim1_cmp0))
    . = ALIGN(4);
  }

  . = 0x0FC00;  /* IRQ 26 - TIM1_CMP1 */
  .isr_tim1_cmp1 : {
    KEEP(*(.isr_tim1_cmp1))
    . = ALIGN(4);
  }

  . = 0x0FE00;  /* IRQ 27 - TIM1_CMP2 */
  .isr_tim1_cmp2 : {
    KEEP(*(.isr_tim1_cmp2))
    . = ALIGN(4);
  }

  . = 0x10000;  /* IRQ 28 - GPIO1_B0 */
  .isr_gpio1_b0 : {
    KEEP(*(.isr_gpio1_b0))
    . = ALIGN(4);
  }

  . = 0x10200;  /* IRQ 29 - GPIO1_B1 */
  .isr_gpio1_b1 : {
    KEEP(*(.isr_gpio1_b1))
    . = ALIGN(4);
  }

  . = 0x10400;  /* IRQ 30 - GPIO1_B2 */
  .isr_gpio1_b2 : {
    KEEP(*(.isr_gpio1_b2))
    . = ALIGN(4);
  }

  . = 0x10600;  /* IRQ 31 - GPIO1_B3 */
  .isr_gpio1_b3 : {
    KEEP(*(.isr_gpio1_b3))
    . = ALIGN(4);
  }

  . = 0x10800;  /* IRQ 32 - GPIO1_B4 */
  .isr_gpio1_b4 : {
    KEEP(*(.isr_gpio1_b4))
    . = ALIGN(4);
  }

  . = 0x10A00;  /* IRQ 33 - GPIO1_B5 */
  .isr_gpio1_b5 : {
    KEEP(*(.isr_gpio1_b5))
    . = ALIGN(4);
  }

  . = 0x10C00;  /* IRQ 34 - GPIO1_B6 */
  .isr_gpio1_b6 : {
    KEEP(*(.isr_gpio1_b6))
    . = ALIGN(4);
  }

  . = 0x10E00;  /* IRQ 35 - GPIO1_B7 */
  .isr_gpio1_b7 : {
    KEEP(*(.isr_gpio1_b7))
    . = ALIGN(4);
  }

  . = 0x11000;  /* IRQ 36 - GPIO2_B0 */
  .isr_gpio2_b0 : {
    KEEP(*(.isr_gpio2_b0))
    . = ALIGN(4);
  }

  . = 0x11200;  /* IRQ 37 - GPIO2_B1 */
  .isr_gpio2_b1 : {
    KEEP(*(.isr_gpio2_b1))
    . = ALIGN(4);
  }

  . = 0x11400;  /* IRQ 38 - GPIO2_B2 */
  .isr_gpio2_b2 : {
    KEEP(*(.isr_gpio2_b2))
    . = ALIGN(4);
  }

  . = 0x11600;  /* IRQ 39 - GPIO2_B3 */
  .isr_gpio2_b3 : {
    KEEP(*(.isr_gpio2_b3))
    . = ALIGN(4);
  }

  . = 0x11800;  /* IRQ 40 - GPIO2_B4 */
  .isr_gpio2_b4 : {
    KEEP(*(.isr_gpio2_b4))
    . = ALIGN(4);
  }

  . = 0x11A00;  /* IRQ 41 - GPIO2_B5 */
  .isr_gpio2_b5 : {
    KEEP(*(.isr_gpio2_b5))
    . = ALIGN(4);
  }

  . = 0x11C00;  /* IRQ 42 - GPIO2_B6 */
  .isr_gpio2_b6 : {
    KEEP(*(.isr_gpio2_b6))
    . = ALIGN(4);
  }

  . = 0x11E00;  /* IRQ 43 - GPIO2_B7 */
  .isr_gpio2_b7 : {
    KEEP(*(.isr_gpio2_b7))
    . = ALIGN(4);
  }

  . = 0x12000;  /* IRQ 44 - GPIO3_B0 */
  .isr_gpio3_b0 : {
    KEEP(*(.isr_gpio3_b0))
    . = ALIGN(4);
  }

  . = 0x12200;  /* IRQ 45 - GPIO3_B1 */
  .isr_gpio3_b1 : {
    KEEP(*(.isr_gpio3_b1))
    . = ALIGN(4);
  }

  . = 0x12400;  /* IRQ 46 - GPIO3_B2 */
  .isr_gpio3_b2 : {
    KEEP(*(.isr_gpio3_b2))
    . = ALIGN(4);
  }

  . = 0x12600;  /* IRQ 47 - GPIO3_B3 */
  .isr_gpio3_b3 : {
    KEEP(*(.isr_gpio3_b3))
    . = ALIGN(4);
  }

  . = 0x12800;  /* IRQ 48 - GPIO3_B4 */
  .isr_gpio3_b4 : {
    KEEP(*(.isr_gpio3_b4))
    . = ALIGN(4);
  }

  . = 0x12A00;  /* IRQ 49 - GPIO3_B5 */
  .isr_gpio3_b5 : {
    KEEP(*(.isr_gpio3_b5))
    . = ALIGN(4);
  }

  . = 0x12C00;  /* IRQ 50 - GPIO3_B6 */
  .isr_gpio3_b6 : {
    KEEP(*(.isr_gpio3_b6))
    . = ALIGN(4);
  }

  . = 0x12E00;  /* IRQ 51 - GPIO3_B7 */
  .isr_gpio3_b7 : {
    KEEP(*(.isr_gpio3_b7))
    . = ALIGN(4);
  }

  . = 0x13000;  /* IRQ 52 - UART1_RC */
  .isr_uart1_rc : {
    KEEP(*(.isr_uart1_rc))
    . = ALIGN(4);
  }

  . = 0x13200;  /* IRQ 53 - UART1_TE */
  .isr_uart1_te : {
    KEEP(*(.isr_uart1_te))
    . = ALIGN(4);
  }

  . = 0x13400;  /* IRQ 54 - UART1_TC */
  .isr_uart1_tc : {
    KEEP(*(.isr_uart1_tc))
    . = ALIGN(4);
  }

  . = 0x13600;  /* IRQ 55 - AFE0_RC */
  .isr_afe0_rc : {
    KEEP(*(.isr_afe0_rc))
    . = ALIGN(4);
  }

  . = 0x13800;  /* IRQ 56 - AFE0_OVF */
  .isr_afe0_ovf : {
    KEEP(*(.isr_afe0_ovf))
    . = ALIGN(4);
  }

  . = 0x13A00;  /* IRQ 57 - AFE0_ERR */
  .isr_afe0_err : {
    KEEP(*(.isr_afe0_err))
    . = ALIGN(4);
  }

  . = 0x13C00;  /* IRQ 58 - SAR0_RC */
  .isr_sar0_rc : {
    KEEP(*(.isr_sar0_rc))
    . = ALIGN(4);
  }

  . = 0x13E00;  /* IRQ 59 - SAR0_OVF */
  .isr_sar0_ovf : {
    KEEP(*(.isr_sar0_ovf))
    . = ALIGN(4);
  }

  /* End marker */
  _end = .;
}