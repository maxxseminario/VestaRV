/* course.h -- VestaRV course SDK student API.
 *
 * Small, self-contained surface for course labs:
 *   - the course-chip register map (chip.h)
 *   - a console: init + uart_putc/uart_puts + a tiny printf subset
 *   - the pass()/fail() sim pass-contract helpers
 *
 * The console mirrors the software/commune console API (uart_putc/uart_puts)
 * -- commune has no printf; printf() below is the course layer over the same
 * primitives. The SDK provides its own uart_putc (correct post-write TX
 * handshake); see course.c and the README "Known issues" for why.
 */
#ifndef COURSE_H
#define COURSE_H

#include <stdint.h>
#include <stdarg.h>

/* Course-chip register map (addresses + access macros). The full generated
   reference is sdk/generated/MemoryMap.h; chip.h is the C-includable subset
   the labs build against -- see the comment at the top of chip.h. */
#include "chip.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ---- CSR helpers ---------------------------------------------------------
 * The build march is rv32ima (NO zicsr); enable it just for the read. */
static inline uint32_t read_mhartid(void) {
    uint32_t id;
    __asm__ volatile(
        ".option push\n"
        ".option arch, +zicsr\n"
        "csrr %0, mhartid\n"
        ".option pop\n"
        : "=r"(id));
    return id;
}

/* ---- console -------------------------------------------------------------
 * console_init() MUST be called before any print. It parks SMCLK on HFXT
 * (SYS_CLK_CR = 0 -- the bootrom leaves SMCLK on the 32 kHz LFXT mid-boot, and
 * without this every UART frame takes ~10 ms and blows sim budgets) and then
 * enables UART0 (the shared console) at BR=1.
 */
void console_init(void);

/* console output primitives (implemented in course.c; same names/semantics as
   the software/commune console library). */
void uart_putc(char c);
void uart_puts(const void *str);

/* Course print layer. printf understands: %s %d %u %x %c %% (no width/precision
   /flags -- deliberately tiny). Returns 0. */
int  printf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
int  puts(const char *s);   /* string + newline; also catches the printf->puts
                               compiler transform */

/* ---- sim pass contract ---------------------------------------------------
 * pass()/fail() write the tb-watched value to a0 and spin forever. On the
 * simulator riscv_tb latches a0 == 0xCAFEBABE (PASS) / 0xDEADBEEF (FAIL). On
 * silicon they are just a distinctive marker in a0 + a halt loop -- harmless.
 * Neither returns.
 */
void pass(void) __attribute__((noreturn));
void fail(void) __attribute__((noreturn));

#ifdef __cplusplus
}
#endif

#endif /* COURSE_H */
