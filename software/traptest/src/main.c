// VestaRV: traptest image
// Executes the all-zeros word, which is an illegal instruction on rv32i, so the chip traps shortly after the loaded program is entered. Use it to tell a real jump into loaded code from a silent no-op.

int main(void) {
    asm volatile (".word 0x00000000");
    while (1) { }   /* unreachable */
    return 0;
}
