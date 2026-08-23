/* The benchmark sources already bracket every kernel with setStats(1)/setStats(0).
   Defining it as a store to the testbench's magic address turns that existing hook into the kernel-window marker, so no benchmark source needs editing.
   The string and memory routines are here because -O2 can still emit calls to them; the benchmarks are not allowed a libc. */

#include <stddef.h>

#define STATS_PORT (*(volatile unsigned int *)0x00004000u)

void setStats(int enable)
{
    STATS_PORT = enable ? 1u : 2u;
}

void *memcpy(void *dst, const void *src, size_t n)
{
    char *d = (char *)dst;
    const char *s = (const char *)src;
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
    const unsigned char *x = (const unsigned char *)a;
    const unsigned char *y = (const unsigned char *)b;
    while (n--) { if (*x != *y) return *x - *y; x++; y++; }
    return 0;
}

size_t strlen(const char *s)
{
    const char *p = s;
    while (*p) p++;
    return (size_t)(p - s);
}

char *strcpy(char *d, const char *s)
{
    char *r = d;
    while ((*d++ = *s++)) ;
    return r;
}

int strcmp(const char *a, const char *b)
{
    while (*a && (*a == *b)) { a++; b++; }
    return *(const unsigned char *)a - *(const unsigned char *)b;
}

/* Reporting only. The harness has no console, and every call site sits OUTSIDE the setStats() window, so discarding the output does not perturb the measured kernel. */
int printf(const char *fmt, ...)       { (void)fmt; return 0; }
int puts(const char *s)                { (void)s;   return 0; }
