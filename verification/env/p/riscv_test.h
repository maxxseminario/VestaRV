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
  jal zero, 0x05A00;   /* IRQ 0  - SYS_WDT     - IVT: 0xA000 -> ISR: 0x05A00 */ \
  jal zero, 0x05C00;   /* IRQ 1  - GPIO0_B0    - IVT: 0xA004 -> ISR: 0x05C00 */ \
  jal zero, 0x05E00;   /* IRQ 2  - GPIO0_B1    - IVT: 0xA008 -> ISR: 0x05E00 */ \
  jal zero, 0x06000;   /* IRQ 3  - GPIO0_B2    - IVT: 0xA00C -> ISR: 0x06000 */ \
  jal zero, 0x06200;   /* IRQ 4  - GPIO0_B3    - IVT: 0xA010 -> ISR: 0x06200 */ \
  jal zero, 0x06400;   /* IRQ 5  - GPIO0_B4    - IVT: 0xA014 -> ISR: 0x06400 */ \
  jal zero, 0x06600;   /* IRQ 6  - GPIO0_B5    - IVT: 0xA018 -> ISR: 0x06600 */ \
  jal zero, 0x06800;   /* IRQ 7  - GPIO0_B6    - IVT: 0xA01C -> ISR: 0x06800 */ \
  jal zero, 0x06A00;   /* IRQ 8  - GPIO0_B7    - IVT: 0xA020 -> ISR: 0x06A00 */ \
  jal zero, 0x0FC00;   /* IRQ 9  - SPI0_TC     - IVT: 0xA024 -> ISR: 0x06C00 changed */ \
  jal zero, 0x0FE00;   /* IRQ 10 - SPI0_TE     - ivt: 0xA028 -> ISR: 0x06E00 changed */ \
  jal zero, 0x07000;   /* IRQ 11 - SPI1_TC     - IVT: 0xA02C -> ISR: 0x07000 */ \
  jal zero, 0x07200;   /* IRQ 12 - SPI1_TE     - IVT: 0xA030 -> ISR: 0x07200 */ \
  jal zero, 0x0F400;   /* IRQ 13 - UART0_RC    - IVT: 0xA034 -> ISR: 0x07400  changed*/ \
  jal zero, 0x0F600;   /* IRQ 14 - UART0_TE    - IVT: 0xA038 -> ISR: 0x07600 changed */ \
  jal zero, 0x0F800;   /* IRQ 15 - UART0_TC    - IVT: 0xA03C -> ISR: 0x07800 changed*/ \
  jal zero, 0x07A00;   /* IRQ 16 - TIM0_CAP0   - IVT: 0xA040 -> ISR: 0x07A00 */ \
  jal zero, 0x07C00;   /* IRQ 17 - TIM0_CAP1   - IVT: 0xA044 -> ISR: 0x07C00 */ \
  jal zero, 0x07E00;   /* IRQ 18 - TIM0_OVF    - IVT: 0xA048 -> ISR: 0x07E00 */ \
  jal zero, 0x08000;   /* IRQ 19 - TIM0_CMP0   - IVT: 0xA04C -> ISR: 0x08000 */ \
  jal zero, 0x08200;   /* IRQ 20 - TIM0_CMP1   - IVT: 0xA050 -> ISR: 0x08200 */ \
  jal zero, 0x08400;   /* IRQ 21 - TIM0_CMP2   - IVT: 0xA054 -> ISR: 0x08400 */ \
  jal zero, 0x08600;   /* IRQ 22 - TIM1_CAP0   - IVT: 0xA058 -> ISR: 0x08600 */ \
  jal zero, 0x08800;   /* IRQ 23 - TIM1_CAP1   - IVT: 0xA05C -> ISR: 0x08800 */ \
  jal zero, 0x08A00;   /* IRQ 24 - TIM1_OVF    - IVT: 0xA060 -> ISR: 0x08A00 */ \
  jal zero, 0x08C00;   /* IRQ 25 - TIM1_CMP0   - IVT: 0xA064 -> ISR: 0x08C00 */ \
  jal zero, 0x08E00;   /* IRQ 26 - TIM1_CMP1   - IVT: 0xA068 -> ISR: 0x08E00 */ \
  jal zero, 0x09000;   /* IRQ 27 - TIM1_CMP2   - IVT: 0xA06C -> ISR: 0x09000 */ \
  jal zero, 0x09200;   /* IRQ 28 - GPIO1_B0    - IVT: 0xA070 -> ISR: 0x09200 */ \
  jal zero, 0x09400;   /* IRQ 29 - GPIO1_B1    - IVT: 0xA074 -> ISR: 0x09400 */ \
  jal zero, 0x09600;   /* IRQ 30 - GPIO1_B2    - IVT: 0xA078 -> ISR: 0x09600 */ \
  jal zero, 0x09800;   /* IRQ 31 - GPIO1_B3    - IVT: 0xA07C -> ISR: 0x09800 */ \
  jal zero, 0x09A00;   /* IRQ 32 - GPIO1_B4    - IVT: 0xA080 -> ISR: 0x09A00 */ \
  jal zero, 0x09C00;   /* IRQ 33 - GPIO1_B5    - IVT: 0xA084 -> ISR: 0x09C00 */ \
  jal zero, 0x09E00;   /* IRQ 34 - GPIO1_B6    - IVT: 0xA088 -> ISR: 0x09E00 */ \
  jal zero, 0x0A000;   /* IRQ 35 - GPIO1_B7    - IVT: 0xA08C -> ISR: 0x0A000 */ \
  jal zero, 0x0A200;   /* IRQ 36 - GPIO2_B0    - IVT: 0xA090 -> ISR: 0x0A200 */ \
  jal zero, 0x0A400;   /* IRQ 37 - GPIO2_B1    - IVT: 0xA094 -> ISR: 0x0A400 */ \
  jal zero, 0x0A600;   /* IRQ 38 - GPIO2_B2    - IVT: 0xA098 -> ISR: 0x0A600 */ \
  jal zero, 0x0A800;   /* IRQ 39 - GPIO2_B3    - IVT: 0xA09C -> ISR: 0x0A800 */ \
  jal zero, 0x0AA00;   /* IRQ 40 - GPIO2_B4    - IVT: 0xA0A0 -> ISR: 0x0AA00 */ \
  jal zero, 0x0AC00;   /* IRQ 41 - GPIO2_B5    - IVT: 0xA0A4 -> ISR: 0x0AC00 */ \
  jal zero, 0x0AE00;   /* IRQ 42 - GPIO2_B6    - IVT: 0xA0A8 -> ISR: 0x0AE00 */ \
  jal zero, 0x0B000;   /* IRQ 43 - GPIO2_B7    - IVT: 0xA0AC -> ISR: 0x0B000 */ \
  jal zero, 0x0B200;   /* IRQ 44 - GPIO3_B0    - IVT: 0xA0B0 -> ISR: 0x0B200 */ \
  jal zero, 0x0B400;   /* IRQ 45 - GPIO3_B1    - IVT: 0xA0B4 -> ISR: 0x0B400 */ \
  jal zero, 0x0B600;   /* IRQ 46 - GPIO3_B2    - IVT: 0xA0B8 -> ISR: 0x0B600 */ \
  jal zero, 0x0B800;   /* IRQ 47 - GPIO3_B3    - IVT: 0xA0BC -> ISR: 0x0B800 */ \
  jal zero, 0x0BA00;   /* IRQ 48 - GPIO3_B4    - IVT: 0xA0C0 -> ISR: 0x0BA00 */ \
  jal zero, 0x0BC00;   /* IRQ 49 - GPIO3_B5    - IVT: 0xA0C4 -> ISR: 0x0BC00 */ \
  jal zero, 0x0BE00;   /* IRQ 50 - GPIO3_B6    - IVT: 0xA0C8 -> ISR: 0x0BE00 */ \
  jal zero, 0x0C000;   /* IRQ 51 - GPIO3_B7    - IVT: 0xA0CC -> ISR: 0x0C000 */ \
  jal zero, 0x0ED00;   /* IRQ 52 - UART1_RC    - IVT: 0xA0D0 -> ISR: 0x0C200 changed*/ \
  jal zero, 0x0F000;   /* IRQ 53 - UART1_TE    - IVT: 0xA0D4 -> ISR: 0x0C400 changed*/ \
  jal zero, 0x0F200;   /* IRQ 54 - UART1_TC    - IVT: 0xA0D8 -> ISR: 0x0C600 changed*/ \
  jal zero, 0x0C800;   /* IRQ 55 - AFE0_RC     - IVT: 0xA0DC -> ISR: 0x0C800 */ \
  jal zero, 0x0CA00;   /* IRQ 56 - SAR0_RC     - IVT: 0xA0E0 -> ISR: 0x0CA00 */ \
  jal zero, 0x0CC00;   /* IRQ 57 - I2C0_STR    - IVT: 0xA0E4 -> ISR: 0x0CC00 */ \
  jal zero, 0x0CE00;   /* IRQ 58 - I2C0_SPR    - IVT: 0xA0E8 -> ISR: 0x0CE00 */ \
  jal zero, 0x0D000;   /* IRQ 59 - I2C0_MSTS   - IVT: 0xA0EC -> ISR: 0x0D000 */ \
  jal zero, 0x0D200;   /* IRQ 60 - I2C0_MSPS   - IVT: 0xA0F0 -> ISR: 0x0D200 */ \
  jal zero, 0x0D400;   /* IRQ 61 - I2C0_MARB   - IVT: 0xA0F4 -> ISR: 0x0D400 */ \
  jal zero, 0x0D600;   /* IRQ 62 - I2C0_MTXE   - IVT: 0xA0F8 -> ISR: 0x0D600 */ \
  jal zero, 0x0D800;   /* IRQ 63 - I2C0_MNR    - IVT: 0xA0FC -> ISR: 0x0D800 */ \
  jal zero, 0x0DA00;   /* IRQ 64 - I2C0_MXC    - IVT: 0xA100 -> ISR: 0x0DA00 */ \
  jal zero, 0x0DC00;   /* IRQ 65 - I2C0_SA     - IVT: 0xA104 -> ISR: 0x0DC00 */ \
  jal zero, 0x0DE00;   /* IRQ 66 - I2C0_STXE   - IVT: 0xA108 -> ISR: 0x0DE00 */ \
  jal zero, 0x0E000;   /* IRQ 67 - I2C0_SOVF   - IVT: 0xA10C -> ISR: 0x0E000 */ \
  jal zero, 0x0E200;   /* IRQ 68 - I2C0_SNR    - IVT: 0xA110 -> ISR: 0x0E200 */ \
  jal zero, 0x0E400;   /* IRQ 69 - I2C0_SXC    - IVT: 0xA114 -> ISR: 0x0E400 */ \
  jal zero, 0x0E600;   /* IRQ 70 - I2C1_STR    - IVT: 0xA118 -> ISR: 0x0E600 */ \
  jal zero, 0x0E800;   /* IRQ 71 - I2C1_SPR    - IVT: 0xA11C -> ISR: 0x0E800 */ \
  jal zero, 0x0EA00;   /* IRQ 72 - I2C1_MSTS   - IVT: 0xA120 -> ISR: 0x0EA00 */ \
  jal zero, 0x0EC00;   /* IRQ 73 - I2C1_MSPS   - IVT: 0xA124 -> ISR: 0x0EC00 */ \
  jal zero, 0x0EE00;   /* IRQ 74 - I2C1_MARB   - IVT: 0xA128 -> ISR: 0x0EE00 */ \
  jal zero, 0x0F000;   /* IRQ 75 - I2C1_MTXE   - IVT: 0xA12C -> ISR: 0x0F000 */ \
  jal zero, 0x0F200;   /* IRQ 76 - I2C1_MNR    - IVT: 0xA130 -> ISR: 0x0F200 */ \
  jal zero, 0x0F400;   /* IRQ 77 - I2C1_MXC    - IVT: 0xA134 -> ISR: 0x0F400 */ \
  jal zero, 0x0F600;   /* IRQ 78 - I2C1_SA     - IVT: 0xA138 -> ISR: 0x0F600 */ \
  jal zero, 0x0F800;   /* IRQ 79 - I2C1_STXE   - IVT: 0xA13C -> ISR: 0x0F800 */ \
  jal zero, 0x0FA00;   /* IRQ 80 - I2C1_SOVF   - IVT: 0xA140 -> ISR: 0x0FA00 */ \
  jal zero, 0x0FC00;   /* IRQ 81 - I2C1_SNR    - IVT: 0xA144 -> ISR: 0x0FC00 */ \
  jal zero, 0x0FE00;   /* IRQ 82 - I2C1_SXC    - IVT: 0xA148 -> ISR: 0x0FE00 */
  
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
