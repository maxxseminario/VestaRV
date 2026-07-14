// See LICENSE for license details.

#ifndef _ENV_PHYSICAL_SINGLE_CORE_H
#define _ENV_PHYSICAL_SINGLE_CORE_H

#include "../encoding.h"
#include "../../isa/macros/scalar/myshkin_s.h"


// Custom Instruction Definitions
#ifdef __ASSEMBLER__  // Only include if being processed by assembler

// .insn r OPCODE, FUNCT3, FUNCT7, RD, RS1, RS2
// 0x0b - custom opcode
// funct3=0 - iret
// funct3=1 - sleep / wake instruction
// funct7=0 - sleep, funct7=1 - wake


// IRET - Interrupt Return
.macro iret
    .insn r 0x0b, 0, 0, x0, x0, x0
.endm

// Puts Vesta to sleep
.macro extinguish
    .insn r 0x0b, 1, 0, x0, x0, x0
.endm

// Wakes Vesta up from sleep
.macro ignite
    .insn r 0x0b, 1, 1, x0, x0, x0
.endm

#endif // __ASSEMBLER__



//-----------------------------------------------------------------------
// Begin Macro
//-----------------------------------------------------------------------

#define RVTEST_RV64U                                                    \
  .macro init;                                                          \
  .endm

#define RVTEST_RV64UF                                                   \
  .macro init;                                                          \
  RVTEST_FP_ENABLE;                                                     \
  .endm

#define RVTEST_RV64UV                                                   \
  .macro init;                                                          \
  RVTEST_VECTOR_ENABLE;                                                 \
  .endm

#define RVTEST_RV64UVX                                                  \
  .macro init;                                                          \
  RVTEST_ZVE32X_ENABLE;                                                 \
  .endm

#define RVTEST_RV32U                                                    \
  .macro init;                                                          \
  .endm

#define RVTEST_RV32UF                                                   \
  .macro init;                                                          \
  RVTEST_FP_ENABLE;                                                     \
  .endm

#define RVTEST_RV32UV                                                   \
  .macro init;                                                          \
  RVTEST_VECTOR_ENABLE;                                                 \
  .endm

#define RVTEST_RV32UVX                                                  \
  .macro init;                                                          \
  RVTEST_ZVE32X_ENABLE;                                                 \
  .endm

#define RVTEST_RV64M                                                    \
  .macro init;                                                          \
  RVTEST_ENABLE_MACHINE;                                                \
  .endm

#define RVTEST_RV64S                                                    \
  .macro init;                                                          \
  RVTEST_ENABLE_SUPERVISOR;                                             \
  .endm

#define RVTEST_RV32M                                                    \
  .macro init;                                                          \
  RVTEST_ENABLE_MACHINE;                                                \
  .endm

#define RVTEST_RV32S                                                    \
  .macro init;                                                          \
  RVTEST_ENABLE_SUPERVISOR;                                             \
  .endm

#if __riscv_xlen == 64
# define CHECK_XLEN li a0, 1; slli a0, a0, 31; bgez a0, 1f; RVTEST_PASS; 1:
#else
# define CHECK_XLEN li a0, 1; slli a0, a0, 31; bltz a0, 1f; RVTEST_PASS; 1:
#endif



// Macro to define the complete IVT section
#define DEFINE_IVT()                                                           \
.section .ivt, "ax";                                                          \ 
  /* M11 memory-map rework: every ISR target lives INSIDE the private TCM   */ \
  /* (0x8000-0xBFFF). Slots with a real linker section point at the ISR     */ \
  /* bank 0xB200-0xBAFF (256 B each, env/p/link.ld); every UNUSED slot      */ \
  /* parks at 0xBB00 (dead TCM word) -- a spuriously taken IRQ can no       */ \
  /* longer execute from the shared window or masquerade as a restart.     */ \
  jal zero, 0x0B800;   /* IRQ 0  - SYS_WDT     - ISR bank 0x0B800 (.isr_sys_wdt) */ \
  jal zero, 0x0BB00;   /* IRQ 1  - GPIO0_B0    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 2  - GPIO0_B1    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 3  - GPIO0_B2    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 4  - GPIO0_B3    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 5  - GPIO0_B4    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 6  - GPIO0_B5    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 7  - GPIO0_B6    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 8  - GPIO0_B7    - unused -> TCM parking */ \
  jal zero, 0x0B900;   /* IRQ 9  - SPI0_TC     - ISR bank 0x0B900 (.isr_spi0_tc) */ \
  jal zero, 0x0BA00;   /* IRQ 10 - SPI0_TE     - ISR bank 0x0BA00 (.isr_spi0_te) */ \
  jal zero, 0x0BB00;   /* IRQ 11 - SPI1_TC     - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 12 - SPI1_TE     - unused -> TCM parking */ \
  jal zero, 0x0B500;   /* IRQ 13 - UART0_RC    - ISR bank 0x0B500 (.isr_uart0_rc) */ \
  jal zero, 0x0B600;   /* IRQ 14 - UART0_TE    - ISR bank 0x0B600 (.isr_uart0_te) */ \
  jal zero, 0x0B700;   /* IRQ 15 - UART0_TC    - ISR bank 0x0B700 (.isr_uart0_tc) */ \
  jal zero, 0x0BB00;   /* IRQ 16 - TIM0_CAP0   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 17 - TIM0_CAP1   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 18 - TIM0_OVF    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 19 - TIM0_CMP0   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 20 - TIM0_CMP1   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 21 - TIM0_CMP2   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 22 - TIM1_CAP0   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 23 - TIM1_CAP1   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 24 - TIM1_OVF    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 25 - TIM1_CMP0   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 26 - TIM1_CMP1   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 27 - TIM1_CMP2   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 28 - GPIO1_B0    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 29 - GPIO1_B1    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 30 - GPIO1_B2    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 31 - GPIO1_B3    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 32 - GPIO1_B4    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 33 - GPIO1_B5    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 34 - GPIO1_B6    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 35 - GPIO1_B7    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 36 - GPIO2_B0    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 37 - GPIO2_B1    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 38 - GPIO2_B2    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 39 - GPIO2_B3    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 40 - GPIO2_B4    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 41 - GPIO2_B5    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 42 - GPIO2_B6    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 43 - GPIO2_B7    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 44 - GPIO3_B0    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 45 - GPIO3_B1    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 46 - GPIO3_B2    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 47 - GPIO3_B3    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 48 - GPIO3_B4    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 49 - GPIO3_B5    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 50 - GPIO3_B6    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 51 - GPIO3_B7    - unused -> TCM parking */ \
  jal zero, 0x0B200;   /* IRQ 52 - UART1_RC    - ISR bank 0x0B200 (.isr_uart1_rc) */ \
  jal zero, 0x0B300;   /* IRQ 53 - UART1_TE    - ISR bank 0x0B300 (.isr_uart1_te) */ \
  jal zero, 0x0B400;   /* IRQ 54 - UART1_TC    - ISR bank 0x0B400 (.isr_uart1_tc) */ \
  jal zero, 0x0BB00;   /* IRQ 55 - AFE0_RC     - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 56 - SAR0_RC     - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 57 - I2C0_STR    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 58 - I2C0_SPR    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 59 - I2C0_MSTS   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 60 - I2C0_MSPS   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 61 - I2C0_MARB   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 62 - I2C0_MTXE   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 63 - I2C0_MNR    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 64 - I2C0_MXC    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 65 - I2C0_SA     - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 66 - I2C0_STXE   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 67 - I2C0_SOVF   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 68 - I2C0_SNR    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 69 - I2C0_SXC    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 70 - I2C1_STR    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 71 - I2C1_SPR    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 72 - I2C1_MSTS   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 73 - I2C1_MSPS   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 74 - I2C1_MARB   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 75 - I2C1_MTXE   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 76 - I2C1_MNR    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 77 - I2C1_MXC    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 78 - I2C1_SA     - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 79 - I2C1_STXE   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 80 - I2C1_SOVF   - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 81 - I2C1_SNR    - unused -> TCM parking */ \
  jal zero, 0x0BB00;   /* IRQ 82 - I2C1_SXC    - unused -> TCM parking */

/* ===========================================================================
 * M19 CLAIM/COMPLETE DELIVERY (PLIC-lite irq_router rework)
 * ===========================================================================
 * Peripheral IRQs are no longer hardware-vectored to their per-source IVT
 * slots: every hart takes ONE external interrupt (meip, IVT slot 85 =
 * IRQB_EXT_MEIP), raised by the irq_router whenever some source is pending,
 * enabled in THAT hart's routing row (0x7000 + 0x10*h), and not already
 * under service. The slot-85 dispatcher below reads CLAIM (0x7800) to
 * atomically discover+claim the source, dispatches THROUGH THE EXISTING IVT
 * (jalr into slot id: the slot's `jal zero, isr` preserves ra, so the
 * per-source .isr_* sections double as the dispatch table for free), then
 * writes the id back to CLAIM (complete) and irets. A parked slot (0xBB00)
 * reached via claim never returns -> tb watchdog = loud FAIL.
 *
 * HANDLER ABI (per-source .isr_* sections, meip-delivered sources ONLY —
 * CLINT slots 83/84 keep the classic hardware-vectored iret ISRs):
 *   - plain function: END WITH ret (the dispatcher completes + irets)
 *   - t0/t1/t2 are dispatcher-saved scratch: free to clobber
 *   - ra must survive (or be saved/restored); anything else: save/restore
 *   - clear the source LEVEL at the peripheral BEFORE returning (complete
 *     happens after return; a still-high level re-pends = new event)
 *   - a handler on a slept hart still does its own `ignite`
 * The CLINT slots (83/84) are hardwire-enabled on EVERY hart since M19 (no
 * SYSTEM/router setup needed); all peripheral routing = the router rows.
 * ======================================================================== */

#define IRQR_BASE_ADDR   0x7000
#define IRQR_CLAIM_ADDR  0x7800
#define IRQB_EXT_MEIP_N  85

/* The slot-85 dispatcher, in its own 256 B TCM section (link.ld: 0xB100).
 * The claimed id is stashed ON THE STACK across the handler call — handlers
 * are allowed to clobber t0/t1/t2, so nothing live may stay in them (the
 * first cut kept id in t1 and COMPLETEd garbage; the out-of-range write was
 * ignored and the source stayed under service forever — shirq round 2). */
#define MEIP_DISPATCHER()                                                      \
  .section .isr_meip, "ax";                                                    \
meip_dispatch:                                                                 \
  addi sp, sp, -20;                                                            \
  sw   ra, 0(sp);                                                              \
  sw   t0, 4(sp);                                                              \
  sw   t1, 8(sp);                                                              \
  sw   t2, 12(sp);                                                             \
  li   t2, IRQR_CLAIM_ADDR;                                                    \
  lw   t1, 0(t2);              /* CLAIM (atomic read-and-claim) */             \
  li   t0, -1;                                                                 \
  beq  t1, t0, 99f;            /* sentinel: spurious -> just iret */           \
  sw   t1, 16(sp);             /* stash id (handlers may clobber t0-t2) */     \
  slli t0, t1, 2;                                                              \
  li   ra, 0x8000;                                                             \
  add  t0, t0, ra;             /* &IVT[id] */                                  \
  jalr ra, 0(t0);              /* slot jal preserves ra; handler rets here */  \
  lw   t1, 16(sp);             /* reload id + claim address */                 \
  li   t2, IRQR_CLAIM_ADDR;                                                    \
  sw   t1, 0(t2);              /* COMPLETE(id) */                              \
99:;                                                                           \
  lw   ra, 0(sp);                                                              \
  lw   t0, 4(sp);                                                              \
  lw   t1, 8(sp);                                                              \
  lw   t2, 12(sp);                                                             \
  addi sp, sp, 20;                                                             \
  iret;                                                                        \
  .previous;

/* Arm IVT slot 85 -> the dispatcher, for tests that did NOT emit their own
 * slots 83/84 (parks them; gap-free .org from the DEFINE_IVT end). Tests
 * with their own CLINT ISRs at .org 0x14C instead add a third jal:
 *     jal zero, 0x0B100    # slot 85 = meip -> dispatcher            */
#define IVT_ARM_MEIP()                                                         \
  .section .ivt, "ax";                                                         \
  .org 0x14C;                                                                  \
  jal zero, 0x0BB00;           /* 83 msip: parked (test uses none) */          \
  jal zero, 0x0BB00;           /* 84 mtip: parked */                           \
  jal zero, 0x0B100;           /* 85 meip -> dispatcher (.isr_meip) */         \
  .previous;

#define INIT_XREG                                                       \
  li x1, 0;                                                             \
  li x2, 0;                                                             \
  li x3, 0;                                                             \
  li x4, 0;                                                             \
  li x5, 0;                                                             \
  li x6, 0;                                                             \
  li x7, 0;                                                             \
  li x8, 0;                                                             \
  li x9, 0;                                                             \
  li x10, 0;                                                            \
  li x11, 0;                                                            \
  li x12, 0;                                                            \
  li x13, 0;                                                            \
  li x14, 0;                                                            \
  li x15, 0;                                                            \
  li x16, 0;                                                            \
  li x17, 0;                                                            \
  li x18, 0;                                                            \
  li x19, 0;                                                            \
  li x20, 0;                                                            \
  li x21, 0;                                                            \
  li x22, 0;                                                            \
  li x23, 0;                                                            \
  li x24, 0;                                                            \
  li x25, 0;                                                            \
  li x26, 0;                                                            \
  li x27, 0;                                                            \
  li x28, 0;                                                            \
  li x29, 0;                                                            \
  li x30, 0;                                                            \
  li x31, 0;

#define INIT_PMP                                                        \
  la t0, 1f;                                                            \
  csrw mtvec, t0;                                                       \
  /* Set up a PMP to permit all accesses */                             \
  li t0, (1 << (31 + (__riscv_xlen / 64) * (53 - 31))) - 1;             \
  csrw pmpaddr0, t0;                                                    \
  li t0, PMP_NAPOT | PMP_R | PMP_W | PMP_X;                             \
  csrw pmpcfg0, t0;                                                     \
  .align 2;                                                             \
1:

#define INIT_RNMI                                                       \
  la t0, 1f;                                                            \
  csrw mtvec, t0;                                                       \
  csrwi CSR_MNSTATUS, MNSTATUS_NMIE;                                    \
  .align 2;                                                             \
1:

#define INIT_SATP                                                      \
  la t0, 1f;                                                            \
  csrw mtvec, t0;                                                       \
  csrwi satp, 0;                                                       \
  .align 2;                                                             \
1:

#define DELEGATE_NO_TRAPS                                               \
  csrwi mie, 0;                                                         \
  la t0, 1f;                                                            \
  csrw mtvec, t0;                                                       \
  csrwi medeleg, 0;                                                     \
  csrwi mideleg, 0;                                                     \
  .align 2;                                                             \
1:

#define RVTEST_ENABLE_SUPERVISOR                                        \
  li a0, MSTATUS_MPP & (MSTATUS_MPP >> 1);                              \
  csrs mstatus, a0;                                                     \
  li a0, SIP_SSIP | SIP_STIP;                                           \
  csrs mideleg, a0;                                                     \

#define RVTEST_ENABLE_MACHINE                                           \
  li a0, MSTATUS_MPP;                                                   \
  csrs mstatus, a0;                                                     \

#define RVTEST_FP_ENABLE                                                \
  li a0, MSTATUS_FS & (MSTATUS_FS >> 1);                                \
  csrs mstatus, a0;                                                     \
  csrwi fcsr, 0

#define RVTEST_VECTOR_ENABLE                                            \
  li a0, (MSTATUS_VS & (MSTATUS_VS >> 1)) |                             \
         (MSTATUS_FS & (MSTATUS_FS >> 1));                              \
  csrs mstatus, a0;                                                     \
  csrwi fcsr, 0;                                                        \
  csrwi vcsr, 0;

#define RVTEST_ZVE32X_ENABLE                                            \
  li a0, (MSTATUS_VS & (MSTATUS_VS >> 1));                              \
  csrs mstatus, a0;                                                     \
  csrwi vcsr, 0;

#define RISCV_MULTICORE_DISABLE                                         \
  csrr a0, mhartid;                                                     \
  1: bnez a0, 1b

#define EXTRA_TVEC_USER
#define EXTRA_TVEC_MACHINE
#define EXTRA_INIT
#define EXTRA_INIT_TIMER
#define FILTER_TRAP
#define FILTER_PAGE_FAULT

#define INTERRUPT_HANDLER j other_exception /* No interrupts should occur */


// Added By Maxx Seminario 04/28/2025
#define RVTEST_CODE_BEGIN                                               \
        DEFINE_IVT();                                                      \
        .section .text.init;                                            \
        .align  2;                                                      \
        .globl _start;                                                  \
_start:                                                                 \
        /* reset vector */                                              \
        j reset_vector;                                                 \
        .align 2;                                                       \
reset_vector:                                                           \
        INIT_XREG;                                                      \
        li TESTNUM, 0;                                                  \
        /* Jump to test code (no mret/CSRs) */                          \
        la t0, test_entry;              /* Define test_entry in test */ \
        jr t0;                                                          \
        /* No exception handling */                                     \
test_entry:                             /* Label for test code */        \
        /* Your test code starts here */




 
#define RVTEST_CODE_END                                                 \
         j RVTEST_PASS                   /* Loop forever on pass */

// #define RVTEST_CODE_BEGIN                                               \
//         .section .text.init;                                            \
//         .align  6;                                                      \
//         .weak stvec_handler;                                            \
//         .weak mtvec_handler;                                            \
//         .globl _start;                                                  \
// _start:                                                                 \
//         /* reset vector */                                              \
//         j reset_vector;                                                 \
//         .align 2;                                                       \
// trap_vector:                                                            \
//         /* test whether the test came from pass/fail */                 \
//         csrr t5, mcause;                                                \
//         li t6, CAUSE_USER_ECALL;                                        \
//         beq t5, t6, write_tohost;                                       \
//         li t6, CAUSE_SUPERVISOR_ECALL;                                  \
//         beq t5, t6, write_tohost;                                       \
//         li t6, CAUSE_MACHINE_ECALL;                                     \
//         beq t5, t6, write_tohost;                                       \
//         /* if an mtvec_handler is defined, jump to it */                \
//         la t5, mtvec_handler;                                           \
//         beqz t5, 1f;                                                    \
//         jr t5;                                                          \
//         /* was it an interrupt or an exception? */                      \
//   1:    csrr t5, mcause;                                                \
//         bgez t5, handle_exception;                                      \
//         INTERRUPT_HANDLER;                                              \
// handle_exception:                                                       \
//         /* we don't know how to handle whatever the exception was */    \
//   other_exception:                                                      \
//         /* some unhandlable exception occurred */                       \
//   1:    ori TESTNUM, TESTNUM, 1337;                                     \
//   write_tohost:                                                         \
//         sw TESTNUM, tohost, t5;                                         \
//         sw zero, tohost + 4, t5;                                        \
//         j write_tohost;                                                 \
// reset_vector:                                                           \
//         INIT_XREG;                                                      \
//         RISCV_MULTICORE_DISABLE;                                        \
//         INIT_RNMI;                                                      \
//         INIT_SATP;                                                      \
//         INIT_PMP;                                                       \
//         DELEGATE_NO_TRAPS;                                              \
//         li TESTNUM, 0;                                                  \
//         la t0, trap_vector;                                             \
//         csrw mtvec, t0;                                                 \
//         CHECK_XLEN;                                                     \
//         /* if an stvec_handler is defined, delegate exceptions to it */ \
//         la t0, stvec_handler;                                           \
//         beqz t0, 1f;                                                    \
//         csrw stvec, t0;                                                 \
//         li t0, (1 << CAUSE_LOAD_PAGE_FAULT) |                           \
//                (1 << CAUSE_STORE_PAGE_FAULT) |                          \
//                (1 << CAUSE_FETCH_PAGE_FAULT) |                          \
//                (1 << CAUSE_MISALIGNED_FETCH) |                          \
//                (1 << CAUSE_USER_ECALL) |                                \
//                (1 << CAUSE_BREAKPOINT);                                 \
//         csrw medeleg, t0;                                               \
// 1:      csrwi mstatus, 0;                                               \
//         init;                                                           \
//         EXTRA_INIT;                                                     \
//         EXTRA_INIT_TIMER;                                               \
//         la t0, 1f;                                                      \
//         csrw mepc, t0;                                                  \
//         csrr a0, mhartid;                                               \
//         mret;                                                           \
// 1:

//-----------------------------------------------------------------------
// End Macro
//-----------------------------------------------------------------------

#define RVTEST_CODE_END                                                 \
        unimp

//-----------------------------------------------------------------------
// Pass/Fail Macro
// Added by Maxx Seminario 04/29/2025
// Pass and Fail go into infinate loop. Test number of failed test is stored in global pointer (gp)
//-----------------------------------------------------------------------

#define RVTEST_PASS         \
    li a0, 0xCAFEBABE;     \
    j _pass_label;          \
_pass_label:                \
    j _pass_label

  #define RVTEST_FAIL         \
    li a0, 0xDEADBEEF;      \ 
    j _fail_label;          \
_fail_label:                \
    j _fail_label          

#define TESTNUM gp
// #define RVTEST_FAIL         \
//     sll TESTNUM, TESTNUM, 1;\
//     or TESTNUM, TESTNUM, 1; \
//     j _fail_label;          \
// _fail_label:                \
//     j _fail_label



// #define RVTEST_PASS                                                     \
//         fence;                                                          \
//         li TESTNUM, 1;                                                  \
//         li a7, 93;                                                      \
//         li a0, 0;                                                       \
//         ecall

// #define TESTNUM gp
// #define RVTEST_FAIL                                                     \
//         fence;                                                          \
// 1:      beqz TESTNUM, 1b;                                               \
//         sll TESTNUM, TESTNUM, 1;                                        \
//         or TESTNUM, TESTNUM, 1;                                         \
//         li a7, 93;                                                      \
//         addi a0, TESTNUM, 0;                                            \
//         ecall

//-----------------------------------------------------------------------
// Data Section Macro
//-----------------------------------------------------------------------

#define EXTRA_DATA

#define RVTEST_DATA_BEGIN                                               \
        EXTRA_DATA                                                      \
        .pushsection .tohost,"aw",@progbits;                            \
        .align 6; .global tohost; tohost: .dword 0; .size tohost, 8;    \
        .align 6; .global fromhost; fromhost: .dword 0; .size fromhost, 8;\
        .popsection;                                                    \
        .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
