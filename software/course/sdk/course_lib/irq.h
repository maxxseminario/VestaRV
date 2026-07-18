/* irq.h -- VestaRV course SDK interrupt support (student API).
 *
 * The course chip takes three machine interrupts, each hardware-vectored to a
 * fixed slot in the IVT at 0x8000 (see crt0.S -- the table starts life all
 * zeros; this module ARMS the slots you ask for at runtime, in TCM):
 *
 *     vector 83  msip  -- CLINT software interrupt        (per-hart MSIP[h])
 *     vector 84  mtip  -- CLINT timer interrupt           (MTIME >= MTIMECMP[h])
 *     vector 85  meip  -- external, via the IRQ ROUTER    (claim/complete)
 *
 * The CLINT slots (83/84) are hardwire-enabled on every hart -- no unmask step.
 * A peripheral (e.g. TIMER0 compare) reaches meip only after you ROUTE its
 * source id to this hart's router row and enable the source at the peripheral.
 *
 * HARDWARE ISR CONTRACT (TRM ch. 6): on an interrupt the hardware pushes ONLY
 * the return PC (sp must already be valid -- crt0 sets sp = 0xBFF0). Handling is
 * non-recursive. This SDK wraps your C handler in an assembly trampoline that
 * saves/restores ALL caller-saved registers around the call and issues the
 * interrupt-return instruction (`retirq`, exposed as irq_return()) for you, so
 * your handler is an ordinary C function. Its ONE hard rule: clear the source
 * LEVEL (the peripheral / CLINT condition) before it returns, or the interrupt
 * re-fires immediately.
 *
 * Register facts below are transcribed from sdk/generated/MemoryMap.h for the
 * course chip (18 harts): the CLINT layout is N-parameterized, so MTIME sits
 * after the 18-entry MSIP array (MTIMEL_OFFSET = 80) and MTIMECMP[0] follows
 * (MTIMECMP0L_OFFSET = 96). All accesses are 32-bit (word-oriented bus).
 */
#ifndef COURSE_IRQ_H
#define COURSE_IRQ_H

#include <stdint.h>
#include "chip.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ---- IVT vector numbers (TRM ch. 6) -------------------------------------- */
#define IRQ_VEC_MSIP   (83)   /* CLINT software  */
#define IRQ_VEC_MTIP   (84)   /* CLINT timer     */
#define IRQ_VEC_MEIP   (85)   /* external / router */

/* ---- CLINT registers (base 0x5000; N=18 layout, TRM ch. 19) --------------
 * MSIP[h]        = 0x5000 + 4*h                       (bit 0, level)
 * MTIME  lo/hi   = 0x5050 / 0x5054                    (free-running, writable)
 * MTIMECMP[h]    = 0x5060 + 8*h  (lo) / +4 (hi)       (resets ALL-ONES = quiet) */
#define CLINT_MSIP(h)        (CLINT_BASE + 0x00 + 4*(h))
#define CLINT_MTIME_LO       (CLINT_BASE + 0x50)
#define CLINT_MTIME_HI       (CLINT_BASE + 0x54)
#define CLINT_MTIMECMP_LO(h) (CLINT_BASE + 0x60 + 8*(h))
#define CLINT_MTIMECMP_HI(h) (CLINT_BASE + 0x64 + 8*(h))

/* ---- IRQ ROUTER (base 0x7000, TRM ch. 21) --------------------------------
 * Per-hart routing rows HhENL/M/U at 0x7000 + 0x10*h + 0/4/8 gate sources
 * [31:0]/[63:32]/[84:64] into that hart's meip. Reset = all masked.
 * CLAIM (read = atomic lowest-id claim; 0xFFFFFFFF = spurious) at 0x7800;
 * COMPLETE = write the id back. */
#define IRQR_ROW_ENL(h)  (IRQROUTER_BASE + 0x10*(h) + 0x00)  /* sources 0..31  */
#define IRQR_ROW_ENM(h)  (IRQROUTER_BASE + 0x10*(h) + 0x04)  /* sources 32..63 */
#define IRQR_ROW_ENU(h)  (IRQROUTER_BASE + 0x10*(h) + 0x08)  /* sources 64..84 */
#define IRQR_CLAIM       (IRQROUTER_BASE + 0x800)
#define IRQR_CLAIM_NONE  (0xFFFFFFFFu)

/* ---- routable interrupt source ids (MemoryMap.h IRQB_*, TRM ch. 6) -------- */
#define IRQ_SRC_UART0_TC   (15)   /* UART0 transmit complete   */
#define IRQ_SRC_TIM0_CMP0  (19)   /* TIMER0 compare 0 (used by lab08) */
#define IRQ_SRC_TIM0_CMP1  (20)
#define IRQ_SRC_TIM0_CMP2  (21)
#define IRQ_SRC_TIM0_OVF   (18)

/* ---- interrupt-return instruction (retirq; TRM ch. 6) --------------------
 * Custom opcode 0x0b, funct3=0, funct7=0 -> retirq (restores the pushed PC).
 * The SDK trampolines issue this for you; exposed for hand-written asm ISRs. */
#define irq_return()  __asm__ volatile(".insn r 0x0b, 0, 0, x0, x0, x0")

/* ---- handler registration ------------------------------------------------
 * Install a C handler for one of the three machine interrupts. The handler
 * runs with all caller-saved registers preserved and returns normally (the SDK
 * trampoline does the retirq). Each installer writes a jump to its trampoline
 * into the corresponding IVT slot, in TCM, at call time.
 *
 *   irq_on_timer   -- CLINT mtip (vector 84). Re-arm/disable MTIMECMP[0] to
 *                     clear the level before returning.
 *   irq_on_soft    -- CLINT msip (vector 83). Clear MSIP[hart] before return.
 *   irq_on_external-- meip (vector 85). The trampoline CLAIMs the router,
 *                     calls your handler with the claimed source id, then
 *                     COMPLETEs it -- your handler clears the source LEVEL at
 *                     the peripheral before returning. A spurious claim
 *                     (0xFFFFFFFF) is swallowed and your handler is not called.
 */
typedef void (*irq_handler_t)(void);
typedef void (*irq_ext_handler_t)(unsigned src_id);

void irq_on_timer(irq_handler_t h);
void irq_on_soft(irq_handler_t h);
void irq_on_external(irq_ext_handler_t h);

#ifdef __cplusplus
}
#endif

#endif /* COURSE_IRQ_H */
