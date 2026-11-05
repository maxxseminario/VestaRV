# myshkin_errata

Directed checks of the Myshkin core and peripheral errata. Nothing here writes to `hdl/myshkin`
or `~/chips`.

| Script | Runs | Reference |
|---|---|---|
| `run.sh <dir>` | `errata.S` on a bare core, without and with a clock freeze | `hdl/myshkin`, or `MYSHKIN_RTL=~/chips/myshkin/hdl/MCU` for the fabricated RTL |
| `chip.sh <dir> behavioral [hdl]` | `errata.S -DCHIP` on the whole chip through the original `riscv_tb` | Fabricated RTL |
| `chip.sh <dir> innovus` | The same on `MCU.xsim.v` with the sign-off SDF, about 14 minutes | Tape-out netlist |
| `TEST=flash chip.sh <dir> <kind>` | `errata_flash.S`: a CSR read-modify-write executed from flash | As above |

`hdl/myshkin` carries fixes made after tape-out, so only `~/chips/myshkin/hdl/MCU` and the netlist
show what was fabricated. `hdl/myshkin` serves as the control for those fixes.

The mask image is `ip/rom_hvt_pg/rom_hvt_pg_tmax.rcf`, from the ROM compiler run of 2025-11-18.
`ip/rom_hvt_pg/rom_hvt_pg_verilog.rcf` was overwritten in July 2026 with a different image, and
the behavioral ROM model opens it by absolute path, so `chip.sh` swaps both.

The chip program reports through the `a0` port: a marker `A5A50000+n`, then signature word `n`.
Do not edit `chip.sh` while it runs: bash reads the script as it goes.
