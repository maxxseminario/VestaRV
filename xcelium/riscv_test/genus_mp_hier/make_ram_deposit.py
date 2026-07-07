#!/usr/bin/env python3
"""Emit an xmsim tcl deposit script that ZERO-INITS the shared SRAM macros of
the gate-level netlist (M11 memory map, M12 single-ROM boot).

M12: tiles no longer boot from a preloaded TCM image. Every hart boots from the
SHARED ROM exactly like silicon, so the per-hart TCM (ram0) deposits are GONE —
a tile's TCM starts X at gate level just like real silicon, and the software
write-before-read contract (the M12 bootrom msip loader stages each tile's code
into its TCM before releasing it) is what makes that safe. This script therefore
takes NO rcf image any more; it only zeroes the shared macros.

The gate ROM image lives in xcelium/riscv_test/genus_mp/rom_hvt_pg_verilog.rcf
(a symlink into the ARM rom_hvt_pg IP dir), loaded by the ARM rom_hvt_pg Verilog
model's $readmemb under its INITIALIZE_MEMORY define. It was regenerated from
software/bootrom_mp/bin/rom.rcf, so the gate netlist's ROM contains the real M12
bootrom — hart 0 SPI-boots and the loader brings up harts 1-3 from there.

Still required: the shared bulk RAM banks (shbank0-3) and the NPU staging RAM
(npuram0) are real macros with no reset and no preload at gate level. The
sh-protocol mailbox discipline (DONE[h]==0 parked-proofs, GO polls) reads words
before any hart has written them, so an undeposited macro returns X -> X on the
unified bus -> chip-wide collapse (M9b round-3 class). Zero rows match the
behavioral models' zero-fill; silicon relies on the M12 bootrom write-before-read
contract. A deposit holds only until the first real write, so written words
behave identically to silicon.

Usage: make_ram_deposit.py <hier-prefix>  > preload.tcl
       hier-prefix e.g. ":dut" (direct riscv_tb top) or ":uut:dut" (wrapper)
"""
import sys

ROWS = 128  # 128 rows of 1024 bits per sram1p16k macro


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: make_ram_deposit.py <hier-prefix>  > preload.tcl")
    prefix = sys.argv[1]
    # M11 shared macros: bulk RAM banks + NPU staging RAM have no reset and no
    # preload at gate level; zero-deposit them so the sh-protocol mailbox reads
    # (DONE[h]==0 parked-proofs, GO polls) never see X before the first write.
    zrow = "0" * 1024
    for macro in ("shbank0", "shbank1", "shbank2", "shbank3", "npuram0"):
        for r in range(ROWS):
            print(f"deposit {prefix}:{macro}:mem[{r}] = 1024'b{zrow}")
    print(f'puts "shared macros zeroed (shbank0-3 + npuram0)"')


if __name__ == "__main__":
    main()
