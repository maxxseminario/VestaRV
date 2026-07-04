#!/usr/bin/env python3
"""Convert per-hart RAM preload images (.ram0/.ram1.rcf, 4096 lines of 32
binary chars, line N = word N MSB-first) into an xmsim tcl deposit script for
the gate-level netlist's tile SRAM macros.

The ARM sram1p16k_hvt_pg Verilog model stores 4096 words as 128 rows of 1024
bits, column-interleaved: bit i of word w lives at mem[w>>5][i*32 + (w&31)].
The gate netlist has no INIT_FILE generic (stripped for synthesis), so the
behavioral flow's preload generics are replaced by these deposits, applied to
harts 1-3 (hart 0 boots via SPI flash exactly like the single-core chip).

Usage: make_ram_deposit.py <ram0.rcf> <ram1.rcf> <hier-prefix>  > preload.tcl
       hier-prefix e.g. ":dut" (direct riscv_tb top) or ":uut:dut" (wrapper)
"""
import sys

WORDS, ROWWORDS, ROWS, BITS = 4096, 32, 128, 32


def rows_from_rcf(path):
    with open(path) as f:
        lines = [l.strip() for l in f if l.strip()]
    if len(lines) != WORDS:
        sys.exit(f"ERROR: {path} has {len(lines)} lines, expected {WORDS}")
    rows = []
    for r in range(ROWS):
        row = ["0"] * 1024  # index p = bit position p of the 1024-bit row
        for col in range(ROWWORDS):
            w = lines[r * ROWWORDS + col]
            if len(w) != BITS:
                sys.exit(f"ERROR: {path} line {r*ROWWORDS+col+1}: {len(w)} chars")
            for i in range(BITS):          # bit i of the word (i=0 is LSB)
                row[i * 32 + col] = w[BITS - 1 - i]
        rows.append("".join(reversed(row)))  # emit MSB (bit 1023) first
    return rows


def main():
    ram0, ram1, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
    print(f"# tile RAM preload generated from {ram0} / {ram1}")
    for ram, path in (("ram0", ram0), ("ram1", ram1)):
        rows = rows_from_rcf(path)
        for hart in (1, 2, 3):
            for r, bits in enumerate(rows):
                print(f"deposit {prefix}:hart{hart}:{ram}:mem[{r}] = 1024'b{bits}")
    print(f'puts "tile RAM preload deposited (harts 1-3, ram0+ram1)"')


if __name__ == "__main__":
    main()
