/*
 * looptest - infinite loop, no trap.
 * Use to verify forth-run actually loaded a program: chip should run
 * silently forever (no UART output, no reset).
 */
int main(void) {
    while (1) { }
    return 0;
}
