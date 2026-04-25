/*
 * traptest - illegal instruction, expected to TRAP.
 * Use to verify forth-run actually jumped into the loaded program: the
 * chip should reset / print a trap banner shortly after `<entry> call0`.
 *
 * 0x00000000 is the canonical "all-zeros" word which is illegal on rv32i
 * (decodes as funct/opcode all zero, not a valid instruction).
 */
int main(void) {
    asm volatile (".word 0x00000000");
    while (1) { }   /* unreachable */
    return 0;
}
