/* VestaRV: chip registers. One base address and one typed pointer per instance.
   Generated from hdl/common/regs/rdl/ by platform/common/python/rdl_cheader_regs.py.
   Do not edit; regenerate with `bazel run //platform/common/python:rdl_regs_headers`. */

#ifndef CASTALIA_REGS_H
#define CASTALIA_REGS_H

#include <stdint.h>

#include "afe2_regs.h"
#include "biasg_regs.h"
#include "clint_regs.h"
#include "dma_regs.h"
#include "evfab_regs.h"
#include "gpio_regs.h"
#include "i2c_regs.h"
#include "i2ctarget_regs.h"
#include "i3c_regs.h"
#include "irq_router_regs.h"
#include "mutex_bank_regs.h"
#include "nfc_regs.h"
#include "npu_regs.h"
#include "onewire_regs.h"
#include "pwm_regs.h"
#include "pwr_ctrl_regs.h"
#include "qspi_regs.h"
#include "rtc_regs.h"
#include "spi_regs.h"
#include "system_regs.h"
#include "timer_regs.h"
#include "trng_regs.h"
#include "uart_regs.h"

/* Peripheral base addresses. These are the CPU byte addresses of the shared
   peripheral window, the same numbers MemoryMap.h publishes as <INST>_BASE;
   the name differs so the two headers can be included together and
   //platform/common:regs_headers_vs_memorymap_test can compare them. */
#define GPIO0_BASE_ADDR        0x4000u
#define GPIO1_BASE_ADDR        0x4100u
#define SPI0_BASE_ADDR         0x4200u
#define SPI1_BASE_ADDR         0x4300u
#define UART0_BASE_ADDR        0x4400u
#define UART1_BASE_ADDR        0x4500u
#define TIMER0_BASE_ADDR       0x4600u
#define TIMER1_BASE_ADDR       0x4700u
#define GPIO2_BASE_ADDR        0x4800u
#define SYSTEM_BASE_ADDR       0x4900u
#define NPU_BASE_ADDR          0x4A00u
#define PWRCTRL_BASE_ADDR      0x4B00u
#define QSPI0_BASE_ADDR        0x4C00u
#define GPIO3_BASE_ADDR        0x4D00u
#define I2C0_BASE_ADDR         0x4E00u
#define I2C1_BASE_ADDR         0x4F00u
#define CLINT_BASE_ADDR        0x5000u
#define MUTEX_BASE_ADDR        0x6000u
#define I3C0_BASE_ADDR         0x6100u
#define NFC0_BASE_ADDR         0x6200u
#define GPIO4_BASE_ADDR        0x6300u
#define GPIO5_BASE_ADDR        0x6400u
#define RTC0_BASE_ADDR         0x6500u
#define PWM0_BASE_ADDR         0x6600u
#define OW0_BASE_ADDR          0x6700u
#define DMA0_BASE_ADDR         0x6800u
#define TRNG0_BASE_ADDR        0x6900u
#define I2CT0_BASE_ADDR        0x6A00u
#define EVFAB_BASE_ADDR        0x6B00u
#define AFE0_BASE_ADDR         0x6C00u
#define AFE1_BASE_ADDR         0x6D00u
#define AFE2_BASE_ADDR         0x6E00u
#define AFE3_BASE_ADDR         0x6F00u
#define IRQROUTER_BASE_ADDR    0x7000u

/* One typed pointer per instance. `AFE0_REGS->AFExCR = v;` writes site 0's
   control register; the struct is the block's, so the member names carry the
   template spelling (AFExCR, not AFE0CR) and the instance is in the pointer. */
#define GPIO0_REGS             ((volatile gpio_t *) GPIO0_BASE_ADDR)
#define GPIO1_REGS             ((volatile gpio_t *) GPIO1_BASE_ADDR)
#define SPI0_REGS              ((volatile spi_t *) SPI0_BASE_ADDR)
#define SPI1_REGS              ((volatile spi_t *) SPI1_BASE_ADDR)
#define UART0_REGS             ((volatile uart_t *) UART0_BASE_ADDR)
#define UART1_REGS             ((volatile uart_t *) UART1_BASE_ADDR)
#define TIMER0_REGS            ((volatile timer_t *) TIMER0_BASE_ADDR)
#define TIMER1_REGS            ((volatile timer_t *) TIMER1_BASE_ADDR)
#define GPIO2_REGS             ((volatile gpio_t *) GPIO2_BASE_ADDR)
#define SYSTEM_REGS            ((volatile system_t *) SYSTEM_BASE_ADDR)
#define NPU_REGS               ((volatile npu_t *) NPU_BASE_ADDR)
#define PWRCTRL_REGS           ((volatile pwr_ctrl_t *) PWRCTRL_BASE_ADDR)
#define QSPI0_REGS             ((volatile qspi_t *) QSPI0_BASE_ADDR)
#define GPIO3_REGS             ((volatile gpio_t *) GPIO3_BASE_ADDR)
#define I2C0_REGS              ((volatile i2c_t *) I2C0_BASE_ADDR)
#define I2C1_REGS              ((volatile i2c_t *) I2C1_BASE_ADDR)
#define CLINT_REGS             ((volatile clint_t *) CLINT_BASE_ADDR)
#define MUTEX_REGS             ((volatile mutex_bank_t *) MUTEX_BASE_ADDR)
#define I3C0_REGS              ((volatile i3c_t *) I3C0_BASE_ADDR)
#define NFC0_REGS              ((volatile nfc_t *) NFC0_BASE_ADDR)
#define GPIO4_REGS             ((volatile gpio_t *) GPIO4_BASE_ADDR)
#define GPIO5_REGS             ((volatile gpio_t *) GPIO5_BASE_ADDR)
#define RTC0_REGS              ((volatile rtc_t *) RTC0_BASE_ADDR)
#define PWM0_REGS              ((volatile pwm_t *) PWM0_BASE_ADDR)
#define OW0_REGS               ((volatile onewire_t *) OW0_BASE_ADDR)
#define DMA0_REGS              ((volatile dma_t *) DMA0_BASE_ADDR)
#define TRNG0_REGS             ((volatile trng_t *) TRNG0_BASE_ADDR)
#define I2CT0_REGS             ((volatile i2ctarget_t *) I2CT0_BASE_ADDR)
#define EVFAB_REGS             ((volatile evfab_t *) EVFAB_BASE_ADDR)
#define AFE0_REGS              ((volatile afe2_site_t *) AFE0_BASE_ADDR)
#define AFE1_REGS              ((volatile afe2_site_t *) AFE1_BASE_ADDR)
#define AFE2_REGS              ((volatile afe2_site_t *) AFE2_BASE_ADDR)
#define AFE3_REGS              ((volatile afe2_site_t *) AFE3_BASE_ADDR)
#define IRQROUTER_REGS         ((volatile irq_router_t *) IRQROUTER_BASE_ADDR)

/* OVERLAY BLOCKS: real registers that the top addrmap cannot carry, because
   SystemRDL has no way to say two addrmaps share one address range. Each one
   sits inside a host peripheral's sub-slot at its own word offsets, so its
   struct is based at the HOST's base address. */
#define AFE0BIASG_BASE_ADDR    0x6C00u   /* overlaid on AFE0 */
#define AFE0BIASG_REGS         ((volatile biasg_t *) AFE0BIASG_BASE_ADDR)

/* The interrupt vector each instance owns, from the top addrmap. A block with
   no vector (PWRCTRL, MUTEX, EVFAB, IRQROUTER) has no define here. The four
   AFE sites SHARE vector 124 and demultiplex it through their own SR. */
#define GPIO0_IRQ_VECTOR       1
#define GPIO1_IRQ_VECTOR       28
#define SPI0_IRQ_VECTOR        9
#define SPI1_IRQ_VECTOR        11
#define UART0_IRQ_VECTOR       13
#define UART1_IRQ_VECTOR       52
#define TIMER0_IRQ_VECTOR      16
#define TIMER1_IRQ_VECTOR      22
#define GPIO2_IRQ_VECTOR       36
#define SYSTEM_IRQ_VECTOR      0
#define NPU_IRQ_VECTOR         120
#define QSPI0_IRQ_VECTOR       55
#define GPIO3_IRQ_VECTOR       44
#define I2C0_IRQ_VECTOR        57
#define I2C1_IRQ_VECTOR        70
#define CLINT_IRQ_VECTOR       83
#define I3C0_IRQ_VECTOR        86
#define NFC0_IRQ_VECTOR        94
#define GPIO4_IRQ_VECTOR       98
#define GPIO5_IRQ_VECTOR       106
#define RTC0_IRQ_VECTOR        114
#define PWM0_IRQ_VECTOR        115
#define OW0_IRQ_VECTOR         117
#define DMA0_IRQ_VECTOR        118
#define TRNG0_IRQ_VECTOR       121
#define I2CT0_IRQ_VECTOR       122
#define AFE0_IRQ_VECTOR        124
#define AFE1_IRQ_VECTOR        124
#define AFE2_IRQ_VECTOR        124
#define AFE3_IRQ_VECTOR        124

/* PER-INSTANCE RESET VALUES. These registers reset differently in different
   instances because the RTL takes the value as a GENERIC (GPIO's RstValPx*,
   I2C's default_SAD), so the block header's <REG>_reset macro -- which is the
   template's -- is WRONG for them. Use these. */
#define P0OUT_RESET            0x1u
#define P0DIR_RESET            0x41u
#define P0SEL_RESET            0x4Eu
#define P0REN_RESET            0x80u
#define P1DIR_RESET            0x10u
#define P1SEL_RESET            0x30u
#define P3REN_RESET            0x80u
#define I2C0AR_RESET           0x79u
#define I2C1AR_RESET           0x23u
#define P4REN_RESET            0xC0u
#define P5REN_RESET            0xC0u
#define P5AFS_RESET            0x1u

#endif /* CASTALIA_REGS_H */
