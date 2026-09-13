// VestaRV: looptest image
// Infinite loop, no trap: the chip runs silently forever, which is how a successful forth-run load is told from a failed one.

int main(void) {
    while (1) { }
    return 0;
}
