/* course.c -- VestaRV course SDK console + tiny printf + pass/fail.
 *
 * Console: mirrors the software/commune console API (uart_putc/uart_puts) and
 * adds a tiny printf. Register accesses are 32-bit (word) -- the peripheral bus
 * is word-oriented, matching shuart.S's lw/sw. uart_putc uses the post-write
 * transmission-complete (TCIF) handshake so back-to-back bytes are paced.
 *
 * printf's integer conversion is deliberately divu/remu-FREE (constant divisors
 * only -> magic-multiply/shift codegen). This chip's hardware divide unit has a
 * result-hazard bug (wrong results when the quotient is consumed too soon after
 * divu/remu -- see the SDK README "Known issues"); GCC's magic division avoids
 * the instruction entirely. Build with -O2 (course.mk) so the constant
 * divisions here never fall back to divu.
 */

#include "course.h"

/* ---- freestanding libc shims (no libc under -nostdlib) -------------------- */
void *memset(void *d, int c, unsigned long n) {
    unsigned char *p = (unsigned char *)d;
    while (n--) *p++ = (unsigned char)c;
    return d;
}
void *memcpy(void *d, const void *s, unsigned long n) {
    unsigned char *pd = (unsigned char *)d;
    const unsigned char *ps = (const unsigned char *)s;
    while (n--) *pd++ = *ps++;
    return d;
}

/* ---- UART0 console --------------------------------------------------------
 * SR bit0 = TCIF (transmission complete); CR bit5 = UART enable. Poll budgets
 * are bounded so a wedged UART trips well inside the tb's 100 ms watchdog. */
#define UART_SR_TCIF   (0x01u)   /* transmission complete */
#define UART_CR_ENABLE (0x20u)
#define UART_POLL_BUDGET (20000)

/* NOTE: this peripheral bus is WORD-oriented -- register accesses use 32-bit
   loads/stores (as shuart.S does with lw/sw). Byte (lbu) reads of the status
   register return garbage, which silently defeats the TX handshake. */

void console_init(void) {
    /* SMCLK -> HFXT (the bootrom parks it on the 32 kHz LFXT mid-boot; without
       this every frame takes ~10 ms and poll budgets expire). */
    MMR_32_BIT_MACRO(SYSCLKCR_ADDRESS) = 0;
    MMR_32_BIT_MACRO(UART0BR_ADDRESS)  = 1;              /* baud = smclk/32 */
    MMR_32_BIT_MACRO(UART0CR_ADDRESS)  = UART_CR_ENABLE; /* enable, no IRQs */
}

void uart_putc(char c) {
    int budget;
    MMR_32_BIT_MACRO(UART0TX_ADDRESS) = (uint8_t)c;  /* start the frame */
    /* wait transmission complete (SR bit0 = TCIF) */
    for (budget = UART_POLL_BUDGET;
         budget && !(MMR_32_BIT_MACRO(UART0SR_ADDRESS) & UART_SR_TCIF);
         budget--) { }
    MMR_32_BIT_MACRO(UART0SR_ADDRESS) = UART_SR_TCIF;  /* clear TCIF pulse */
    /* confirm cleared before returning (so the next frame's wait is honest) */
    for (budget = UART_POLL_BUDGET;
         budget && (MMR_32_BIT_MACRO(UART0SR_ADDRESS) & UART_SR_TCIF);
         budget--) { }
}

void uart_puts(const void *str) {
    const char *s = (const char *)str;
    while (*s) uart_putc(*s++);
}

/* ---- tiny printf (%s %d %u %x %c %%) --------------------------------------
 * IMPORTANT: the base is a COMPILE-TIME CONSTANT in each helper (10 / 16), so
 * the compiler lowers the division to a magic-multiply (mulhu) / shift and
 * NEVER emits the hardware divu/remu instructions. Those instructions have a
 * result-hazard bug on this chip (see the README "Known issues" and course.mk's
 * -O2 requirement) and must be avoided. Build the SDK at -O2 (course.mk does)
 * so even the constant divisions here stay divu-free. */
/* divide-by-10 via an explicit reciprocal multiply -- uses mul/mulhu (which
   work on this chip) and never the hazard-prone divu/remu. */
static unsigned div10(unsigned n) {
    return (unsigned)(((unsigned long long)n * 0xCCCCCCCDULL) >> 35);
}

static void emit_udec(unsigned v) {
    char tmp[10];
    int i = 0;
    if (v == 0) { uart_putc('0'); return; }
    while (v) {
        unsigned q = div10(v);
        unsigned r = v - q * 10u;        /* remainder without remu */
        tmp[i++] = (char)('0' + r);
        v = q;
    }
    while (i) uart_putc(tmp[--i]);
}

static void emit_uhex(unsigned v) {
    char tmp[8];
    int i = 0;
    const char *hx = "0123456789abcdef";
    if (v == 0) { uart_putc('0'); return; }
    while (v) { tmp[i++] = hx[v & 0xFu]; v >>= 4; }   /* no division at all */
    while (i) uart_putc(tmp[--i]);
}

static void emit_int(int v) {
    if (v < 0) { uart_putc('-'); emit_udec((unsigned)(-(v))); }
    else       { emit_udec((unsigned)v); }
}

int printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    for (; *fmt; fmt++) {
        if (*fmt != '%') { uart_putc(*fmt); continue; }
        fmt++;
        switch (*fmt) {
            case 's': {
                const char *s = va_arg(ap, const char *);
                if (!s) s = "(null)";
                while (*s) uart_putc(*s++);
                break;
            }
            case 'd': emit_int(va_arg(ap, int)); break;
            case 'u': emit_udec(va_arg(ap, unsigned)); break;
            case 'x': emit_uhex(va_arg(ap, unsigned)); break;
            case 'c': uart_putc((char)va_arg(ap, int)); break;
            case '%': uart_putc('%'); break;
            case '\0': va_end(ap); return 0;   /* trailing '%' */
            default:  uart_putc('%'); uart_putc(*fmt); break;
        }
    }
    va_end(ap);
    return 0;
}

int puts(const char *s) {
    uart_puts(s);
    uart_putc('\n');
    return 0;
}

/* ---- sim pass contract ---------------------------------------------------
 * Write the tb-watched marker to a0 and spin (one asm block, nothing after can
 * clobber a0). */
void pass(void) {
    __asm__ volatile("li a0, 0xCAFEBABE\n1: j 1b" ::: "a0", "memory");
    __builtin_unreachable();
}
void fail(void) {
    __asm__ volatile("li a0, 0xDEADBEEF\n1: j 1b" ::: "a0", "memory");
    __builtin_unreachable();
}

/* ---- interrupt support (see course_lib/irq.h) ----------------------------
 * The core hardware-vectors each machine interrupt to a fixed IVT slot (0x8000
 * + 4*vector) and pushes ONLY the return PC (at sp-4, sp pre-decremented; the
 * matching retirq pops it). To let students write ordinary C handlers, every
 * armed slot jumps to one of the assembly TRAMPOLINES below, which save/restore
 * ALL caller-saved registers around a call into a C dispatcher, then retirq.
 * Callee-saved regs are preserved by the C ABI, so the full machine state of the
 * interrupted code survives -- the handler may clobber anything.
 *
 * The trampolines live in top-level asm so the SDK object list (crt0 + course)
 * is unchanged; --gc-sections drops them (and the registration functions) from
 * labs that never install a handler. */
#include "irq.h"

static irq_handler_t      _msip_cb;
static irq_handler_t      _mtip_cb;
static irq_ext_handler_t  _ext_cb;

/* C dispatchers (called from the trampolines; global so the asm `call`
 * resolves). All caller-saved state is already spilled by the trampoline. */
void _course_irq_msip_c(void) { if (_msip_cb) _msip_cb(); }
void _course_irq_mtip_c(void) { if (_mtip_cb) _mtip_cb(); }
void _course_irq_meip_c(void) {
    uint32_t id = MMR_32_BIT_MACRO(IRQR_CLAIM);   /* atomic claim */
    if (id == IRQR_CLAIM_NONE) return;            /* spurious: nothing to do */
    if (_ext_cb) _ext_cb((unsigned)id);           /* handler clears the LEVEL */
    MMR_32_BIT_MACRO(IRQR_CLAIM) = id;            /* complete(id) */
}

/* Save-all / restore-all trampolines. Entry sp points at the pushed PC (0(sp));
 * we reserve 64 bytes BELOW it for the 16 caller-saved regs, never touching the
 * saved PC, then retirq. */
__asm__(
    ".text\n"
    ".p2align 2\n"
    ".macro _CRS_SAVE\n"
    "  addi sp, sp, -64\n"
    "  sw ra,  0(sp)\n  sw t0,  4(sp)\n  sw t1,  8(sp)\n  sw t2, 12(sp)\n"
    "  sw a0, 16(sp)\n  sw a1, 20(sp)\n  sw a2, 24(sp)\n  sw a3, 28(sp)\n"
    "  sw a4, 32(sp)\n  sw a5, 36(sp)\n  sw a6, 40(sp)\n  sw a7, 44(sp)\n"
    "  sw t3, 48(sp)\n  sw t4, 52(sp)\n  sw t5, 56(sp)\n  sw t6, 60(sp)\n"
    ".endm\n"
    ".macro _CRS_REST\n"
    "  lw ra,  0(sp)\n  lw t0,  4(sp)\n  lw t1,  8(sp)\n  lw t2, 12(sp)\n"
    "  lw a0, 16(sp)\n  lw a1, 20(sp)\n  lw a2, 24(sp)\n  lw a3, 28(sp)\n"
    "  lw a4, 32(sp)\n  lw a5, 36(sp)\n  lw a6, 40(sp)\n  lw a7, 44(sp)\n"
    "  lw t3, 48(sp)\n  lw t4, 52(sp)\n  lw t5, 56(sp)\n  lw t6, 60(sp)\n"
    "  addi sp, sp, 64\n"
    ".endm\n"

    ".globl _course_irq_tramp_msip\n"
    "_course_irq_tramp_msip:\n"
    "  _CRS_SAVE\n  call _course_irq_msip_c\n  _CRS_REST\n"
    "  .insn r 0x0b, 0, 0, x0, x0, x0\n"   /* retirq */

    ".globl _course_irq_tramp_mtip\n"
    "_course_irq_tramp_mtip:\n"
    "  _CRS_SAVE\n  call _course_irq_mtip_c\n  _CRS_REST\n"
    "  .insn r 0x0b, 0, 0, x0, x0, x0\n"

    ".globl _course_irq_tramp_meip\n"
    "_course_irq_tramp_meip:\n"
    "  _CRS_SAVE\n  call _course_irq_meip_c\n  _CRS_REST\n"
    "  .insn r 0x0b, 0, 0, x0, x0, x0\n"
);

extern void _course_irq_tramp_msip(void);
extern void _course_irq_tramp_mtip(void);
extern void _course_irq_tramp_meip(void);

/* Write `jal x0, tramp` into IVT slot `vec` (at 0x8000 + 4*vec). The TCM is a
 * unified bus with no I-cache, so the store is visible to fetch immediately
 * (the bootrom self-modifies TCM the same way). */
static void _course_ivt_arm(unsigned vec, void (*tramp)(void)) {
    volatile uint32_t *slot = (volatile uint32_t *)(0x8000u + 4u * vec);
    uint32_t u = (uint32_t)((uintptr_t)tramp - (uintptr_t)slot);   /* pc-rel */
    uint32_t insn = 0x6Fu                        /* JAL, rd = x0 */
                  | (((u >> 20) & 0x1u)   << 31)
                  | (((u >> 1)  & 0x3FFu) << 21)
                  | (((u >> 11) & 0x1u)   << 20)
                  | (((u >> 12) & 0xFFu)  << 12);
    *slot = insn;
    __asm__ volatile("" ::: "memory");
}

void irq_on_soft(irq_handler_t h)     { _msip_cb = h; _course_ivt_arm(IRQ_VEC_MSIP, _course_irq_tramp_msip); }
void irq_on_timer(irq_handler_t h)    { _mtip_cb = h; _course_ivt_arm(IRQ_VEC_MTIP, _course_irq_tramp_mtip); }
void irq_on_external(irq_ext_handler_t h) { _ext_cb = h; _course_ivt_arm(IRQ_VEC_MEIP, _course_irq_tramp_meip); }
