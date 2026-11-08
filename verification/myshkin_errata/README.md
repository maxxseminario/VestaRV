# verification/myshkin_errata: Myshkin errata checks

Directed checks of the Myshkin core and peripheral errata. Nothing here writes to `hdl/myshkin`
or to the Myshkin tape-out tree.

| Script | Runs | Reference |
|---|---|---|
| `run.sh <dir>` | `errata.S` on a bare core, without and with a clock freeze | `hdl/myshkin`, or `MYSHKIN_RTL=<tape-out tree>/hdl/MCU` for the fabricated RTL |
| `chip.sh <dir> behavioral [hdl]` | `errata.S -DCHIP` on the whole chip through the original `riscv_tb` | Fabricated RTL |
| `chip.sh <dir> innovus` | The same on `MCU.xsim.v` with the sign-off SDF, about 14 minutes | Tape-out netlist |
| `TEST=flash chip.sh <dir> <kind>` | `errata_flash.S`: a CSR read-modify-write executed from flash | As above |

`chip.sh` needs the Myshkin tape-out tree (fabricated RTL, IP, netlist, SDF), which is not in this
repository. `hdl/myshkin` carries fixes made after tape-out, so only the tape-out RTL and netlist
show what was fabricated; `hdl/myshkin` serves as the control for those fixes.

The mask image is `ip/rom_hvt_pg/rom_hvt_pg_tmax.rcf` in the tape-out tree, from the ROM compiler
run of 2025-11-18. `ip/rom_hvt_pg/rom_hvt_pg_verilog.rcf` was later overwritten with a different
image, and the behavioral ROM model opens it by absolute path, so `chip.sh` swaps both.

The chip program reports through the `a0` port: a marker `A5A50000+n`, then signature word `n`.
Do not edit `chip.sh` while it runs: bash reads the script as it goes.
