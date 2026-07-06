#!/usr/bin/env python3
"""Convert the per-hart TCM preload image (.ram0.rcf, 4096 lines of 32
binary chars, line N = word N MSB-first) into an xmsim tcl deposit script for
the gate-level netlist's SRAM macros (M11 memory map).

The ARM sram1p16k_hvt_pg Verilog model stores 4096 words as 128 rows of 1024
bits, column-interleaved: bit i of word w lives at mem[w>>5][i*32 + (w&31)].
The gate netlist has no INIT_FILE generic (stripped for synthesis), so the
behavioral flow's preload generic is replaced by these deposits, applied to
harts 1-3 (hart 0 boots via SPI flash exactly like the single-core chip).

M11: tiles have a single TCM (ram0). The shared bulk RAM banks (shbank0-3)
and the NPU staging RAM (npuram0) are real macros now — the sh-protocol
zero-init assumption (DONE[h]==0 parked-proofs) is satisfied by zero-
depositing all five macros (a deposit holds only until the first real write,
so written words behave identically to silicon).

Usage: make_ram_deposit.py <ram0.rcf> <hier-prefix>  > preload.tcl
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
    ram0, prefix = sys.argv[1], sys.argv[2]
    print(f"# tile TCM preload generated from {ram0}")
    rows = rows_from_rcf(ram0)
    for hart in (1, 2, 3):
        for r, bits in enumerate(rows):
            print(f"deposit {prefix}:hart{hart}:ram0:mem[{r}] = 1024'b{bits}")
    print(f'puts "tile TCM preload deposited (harts 1-3, ram0)"')
    # M11 shared macros: bulk RAM banks + NPU staging RAM have no reset and
    # no preload at gate level; the sh-protocol mailbox discipline (DONE[h]==0
    # parked-proofs, GO polls) reads words before any hart has written them,
    # so an undeposited macro returns X -> X on the unified bus -> chip-wide
    # collapse (M9b round 3 class). Zero rows match the behavioral models'
    # zero-fill; silicon relies on the M12 bootrom write-before-read contract.
    zrow = "0" * 1024
    for macro in ("shbank0", "shbank1", "shbank2", "shbank3", "npuram0"):
        for r in range(ROWS):
            print(f"deposit {prefix}:{macro}:mem[{r}] = 1024'b{zrow}")
    print(f'puts "shared macros zeroed (shbank0-3 + npuram0)"')


if __name__ == "__main__":
    main()
