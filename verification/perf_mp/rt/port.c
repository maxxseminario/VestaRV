/* verification/perf_mp bare-metal support: the libc subset the benchmarks need, and the print-window reporter.
   Everything here runs outside the timed windows except memcpy/strcpy/strcmp, which Dhrystone's rules count as
   part of the benchmark; those are byte loops identical to verification/cpi/bmark_stubs.c, so the two harnesses agree. */
#include <stdarg.h>
#include <stddef.h>

#define PRINT_BASE 0x1F000u

static inline unsigned hartid(void) { unsigned h; __asm__ volatile("csrr %0, mhartid" : "=r"(h)); return h; }
unsigned rd_mcycle(void)   { unsigned v; __asm__ volatile("csrr %0, mcycle" : "=r"(v)); return v; }
unsigned rd_minstret(void) { unsigned v; __asm__ volatile("csrr %0, minstret" : "=r"(v)); return v; }

void perf_report(unsigned tag, unsigned a, unsigned b)
{
    volatile unsigned *p = (volatile unsigned *)(PRINT_BASE + 0x100u * hartid());
    p[0] = tag; p[1] = a; p[2] = b;
}
void perf_stats_dump(void) { *(volatile unsigned *)0x1FFFCu = 0; }

static void putch(char c) { *(volatile unsigned *)(PRINT_BASE + 0x100u * hartid() + 0x40u) = (unsigned char)c; }

void *memcpy(void *dst, const void *src, size_t n)
{
    char *d = (char *)dst; const char *s = (const char *)src;
    while (n--) *d++ = *s++;
    return dst;
}
void *memset(void *dst, int c, size_t n)
{
    char *d = (char *)dst;
    while (n--) *d++ = (char)c;
    return dst;
}
int memcmp(const void *a, const void *b, size_t n)
{
    const unsigned char *x = (const unsigned char *)a, *y = (const unsigned char *)b;
    while (n--) { if (*x != *y) return *x - *y; x++; y++; }
    return 0;
}
size_t strlen(const char *s) { const char *p = s; while (*p) p++; return (size_t)(p - s); }
char *strcpy(char *d, const char *s) { char *r = d; while ((*d++ = *s++)) ; return r; }
int strcmp(const char *a, const char *b)
{
    while (*a && (*a == *b)) { a++; b++; }
    return *(const unsigned char *)a - *(const unsigned char *)b;
}

static void put_num(unsigned v, unsigned base, int width, int zero, int neg)
{
    char b[12]; int i = 0;
    do { unsigned d = v % base; b[i++] = (char)(d < 10 ? '0' + d : 'a' + d - 10); v /= base; } while (v);
    if (neg) width--;
    if (neg && zero) putch('-');
    for (int k = i; k < width; k++) putch(zero ? '0' : ' ');
    if (neg && !zero) putch('-');
    while (i) putch(b[--i]);
}

static int vfmt(const char *f, va_list ap)
{
    for (; *f; f++) {
        if (*f != '%') { putch(*f); continue; }
        f++;
        int zero = 0, width = 0;
        if (*f == '0') { zero = 1; f++; }
        while (*f >= '0' && *f <= '9') width = width * 10 + (*f++ - '0');
        while (*f == 'l') f++;
        switch (*f) {
        case 'd': { int v = va_arg(ap, int); put_num(v < 0 ? (unsigned)-v : (unsigned)v, 10, width, zero, v < 0); break; }
        case 'u': put_num(va_arg(ap, unsigned), 10, width, zero, 0); break;
        case 'x': put_num(va_arg(ap, unsigned), 16, width, zero, 0); break;
        case 'c': putch((char)va_arg(ap, int)); break;
        case 's': { const char *s = va_arg(ap, const char *); while (*s) putch(*s++); break; }
        case '%': putch('%'); break;
        default: putch('?'); break;
        }
    }
    return 0;
}

int ee_printf(const char *fmt, ...)    { va_list a; va_start(a, fmt); vfmt(fmt, a); va_end(a); return 0; }
int printf(const char *fmt, ...)       { va_list a; va_start(a, fmt); vfmt(fmt, a); va_end(a); return 0; }
void dh_log(const char *fmt, ...) { va_list a; va_start(a, fmt); vfmt(fmt, a); va_end(a); }
int puts(const char *s)                { while (*s) putch(*s++); putch('\n'); return 0; }
