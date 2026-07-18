/* chip.h -- VestaRV course-chip register map (C-includable subset).
 *
 * WHY THIS FILE EXISTS
 * --------------------
 * The full generated header sdk/generated/MemoryMap.h is the authoritative
 * reference (every register, offset and bitfield). It is a faithful snapshot
 * of the chip generator's output -- but it currently does NOT compile as a C
 * include: the generator names every padding member of the absolute-base
 * peripheral structs (CLINT_t / MUTEX_t / IRQROUTER_t) "__unused0", which C
 * rejects as duplicate struct members (see sdk/generated/PROVENANCE.md and the
 * SDK README "Known issues"). This is a pre-existing generator bug (it affects
 * the N=4 Castalia header too), not something the SDK may patch.
 *
 * Until the generator is fixed, this small hand-curated header gives labs the
 * addresses + access macros they need, in a form that compiles. Values are
 * transcribed from sdk/generated/MemoryMap.h and are stable (legacy slot
 * numbering; every peripheral at its original address).
 */
#ifndef COURSE_CHIP_H
#define COURSE_CHIP_H

#include <stdint.h>

/* ---- memory-mapped register access --------------------------------------- */
#define MMR_8_BIT_MACRO(a)   (*((volatile uint8_t  *)(a)))
#define MMR_16_BIT_MACRO(a)  (*((volatile uint16_t *)(a)))
#define MMR_32_BIT_MACRO(a)  (*((volatile uint32_t *)(a)))

/* ---- peripheral base addresses (0x4000 shared peripheral window) ---------- */
#define GPIO0_BASE      (0x4000)
#define GPIO1_BASE      (0x4100)
#define SPI0_BASE       (0x4200)
#define SPI1_BASE       (0x4300)
#define UART0_BASE      (0x4400)   /* shared console UART */
#define UART1_BASE      (0x4500)
#define TIMER0_BASE     (0x4600)
#define TIMER1_BASE     (0x4700)
#define GPIO2_BASE      (0x4800)
#define SYSTEM0_BASE    (0x4900)   /* clock/system control */
#define NPU_BASE        (0x4A00)   /* restored on the course chip */
#define GPIO3_BASE      (0x4D00)
#define I2C0_BASE       (0x4E00)
#define I2C1_BASE       (0x4F00)
/* shared-window control blocks (see MemoryMap.h for register layouts) */
#define CLINT_BASE      (0x5000)
#define MUTEX_BASE      (0x6000)
#define IRQROUTER_BASE  (0x7000)

/* ---- SYSTEM0 clock control ------------------------------------------------ */
#define SYSCLKCR_ADDRESS  (0x4900)   /* SYS_CLK_CR: write 0 -> SMCLK on HFXT */

/* ---- UART0 registers (offsets shared by every UARTx) ---------------------- */
#define UART0CR_ADDRESS   (0x4400)
#define UART0SR_ADDRESS   (0x4404)
#define UART0BR_ADDRESS   (0x4408)
#define UART0RX_ADDRESS   (0x440C)
#define UART0TX_ADDRESS   (0x4410)

#endif /* COURSE_CHIP_H */
