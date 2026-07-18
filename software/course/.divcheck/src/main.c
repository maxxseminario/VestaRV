#include "course.h"
volatile unsigned ga = 100, gd = 10;
int main(void)
{
    console_init();
    unsigned a, b, c, d;
    a = ga; asm volatile("divu %0, %0, %1" : "+r"(a) : "r"(gd));   /* rd==rs1 */
    b = gd; asm volatile("divu %0, %1, %0" : "+r"(b) : "r"(ga));   /* rd==rs2 */
    c = ga; asm volatile("remu %0, %0, %1" : "+r"(c) : "r"(gd));   /* rd==rs1 */
    d = ga; asm volatile("divu %0, %0, %0" : "+r"(d));             /* rd==rs1==rs2 */
    printf("rd==rs1 divu:%u  rd==rs2 divu:%u  rd==rs1 remu:%u  self:%u\n", a, b, c, d);
    if (a == 10 && b == 10 && c == 0 && d == 1) pass();
    fail();
}
