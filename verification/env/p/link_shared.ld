/* link_shared.ld -- EXECUTE-FROM-SHARED variant of link.ld (2026-08-16).
 *
 * FOR IMAGES THAT DO NOT FIT THE PRIVATE TCM. With the 8 KiB TCM the private
 * array is 0x8000-0x9FFF, and rv32uc-p-rvc's .text.init alone is 11,642 bytes:
 * linked at 0x8200 it runs past the array's top, and because the tile drops the
 * unused top address bit it WRAPS ONTO ITSELF and overwrites its own opening
 * instructions. (Measured: an alias-collision scan over all 243 built ELFs
 * flags exactly one, rvc, colliding .text.init<->.text.init.)
 *
 * THE FIX IS NOT A SMALLER TEST, IT IS A DIFFERENT MEMORY. The shared bulk RAM
 * at 0x10000-0x1FFFF is 64 KiB behind the arbiter, and executing from it is
 * proven silicon, not a hope: M10 made instruction fetch through the arbiter
 * work (addr-qualified ack + the clk_cpu-staged sh_rdata_cpu) and shexec.S is
 * its standing test. The M12 boot itself fetches through the same path.
 *
 * WHAT MOVES, and what deliberately does not:
 *   .ivt        STAYS at 0x8000. The vector table must be in the TCM -- it is
 *               what the core's IRQ hardware reads.
 *   .boot_entry NEW, at BOOT_ENTRY_VEC = 0x10640. One word holding _start's
 *               address, which the bootrom reads (start.S: lw t0, 0(t0); jr t0)
 *               instead of hardcoding its jump to 0x8200. Emitted by the LINKER
 *               (LONG), so there is no assembly stub and the test source is
 *               untouched. NOT 0x81FC -- that looked free and is not, the NPU
 *               images hold a real JAL there; see the body comment.
 *   .text.init  MOVES to 0x10900 -- above the bootrom's mailbox zero range
 *               (0x10000-0x107FF), its loader rows (0x10500-0x1061F) AND the
 *               Debug Module program page (0x10680-0x1087F, live since
 *               debug.enable became a shipped default), and well below
 *               MP_STAGE_BASE 0x18000.
 *   ISR/NPU     STAY at their TCM/staging addresses. They are fixed hardware
 *               contracts, and they are empty in an image that needs this file.
 *
 * The 0x8200-0x10800 hole costs nothing: flash_prepend.sh scans for non-zero
 * regions and emits one 0x10adbeef segment per region (GAP_MIN=8), so the hole
 * is simply never loaded.
 *
 * Do not use this as the default link script: an image that FITS the TCM should
 * stay in it, where fetch is private and single-cycle rather than arbitrated.
 */
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
  /* The published entry address, read by the bootrom instead of its hardcoded
   * jump to 0x8200. See BOOT_ENTRY_VEC in myshkin_s.h for why it is HERE and
   * not in the TCM: 0x81FC looked free and is not (the NPU images hold a real
   * JAL there). 0x10640 is the gap between the loader mailbox rows, which end
   * at 0x1061F for N=18, and the Debug Module program page at 0x10680 -- and it
   * is inside the bootrom's 0x10000-0x107FF zero range, so it reads 0 for every
   * image that does not publish one. */
  . = 0x00010640;
  .boot_entry : { LONG(_start); }

  /* .text.init in the SHARED BULK RAM, not the TCM.
   * 0x10900 CLEARS THE DEBUG MODULE PROGRAM PAGE (0x10680-0x1087F), which is
   * live on this chip since debug.enable became a shipped default -- an earlier
   * draft put this at 0x10800, inside that page. Also clear of the mailbox zero
   * range below and of MP_STAGE_BASE 0x18000 above, leaving ~29 KiB.
   * SUBALIGN(4) is kept for the reason link.ld gives: rvc.S has an internal
   * `.align 12` for its cross-page fetch test which would otherwise propagate
   * to the whole section and move _start. */
  . = 0x00010900;
  .text.init 0x00010900 : SUBALIGN(4) { *(.text.init) }

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