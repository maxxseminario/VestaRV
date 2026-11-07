# rv32uscar: bugs that reached silicon

A scar is the mark a bug left on a taped-out chip. Each test here reproduces one defect from the
Myshkin errata, and must fail if that defect returns. Nothing joins this directory unless the bug
was in a taped-out design: a bug caught before tape-out is a regression test, and belongs in its
ordinary suite.

Run them with the rest of the regression (`make verify SUITE=full`), or alone:

    cd xcelium/riscv_test/verify_castalia
    grep -h rv32uscar xrun_parallel.sh | tr -d ' "' > scars.txt
    TESTS_FILE=scars.txt ./xrun_parallel.sh

| Test | Erratum | Needs |
|---|---|---|
| `divrd` | `div`, `divu`, `rem`, `remu` fail when `rd` equals a source | `div` |
| `caddsp` | Compressed stack adjustments and calls are wrong | `compressed` |
| `xori80` | `xori` with immediate `0x80` executes as `zext.h` | |
| `misald` | Misaligned loads and stores use the aligned location | `trapCsr` |
| `cluix0` | `c.lui` with destination `x0` stops the core | `compressed` |
| `csrrmw` | A CSR read-modify-write under a stall returns the value it wrote | `trapCsr` |
| `jalrb0` | `jalr` does not clear bit 0 of its target | |
| `wdtirq` | The watchdog never fires | |
| `UARTov` | The UART overflow flag is unreliable | `uart1` |
| `nputhk` | `NPUTHINK` always reads 0 | `npu` |

`UARTov` keeps its capitals because `riscv_tb` shorts the UART pins only for an image whose name
contains `UART`.

`wdtirq` runs twice: the watchdog really resets the chip, the boot re-enters the image, and the
second pass finds `WDTRF` set.

## Proof

Each fix was reverted alone on Castalia. The clean build passes all ten; each revert fails its test
at this check, in `t4`:

| Reverted fix | Test | Check |
|---|---|---|
| `xori` decode | `xori80` | 2 |
| `jalr` bit 0 | `jalrb0` | 1 |
| `c.lui x0` HINT | `cluix0` | 2 |
| Misaligned trap | `misald` | 2 |
| CSR stall gate | `csrrmw` | 2 |
| `rd` commit before the divide | `divrd` | 2 |
| `c.addi16sp` low bits | `caddsp` | 2 |
| Compressed link | `caddsp` | 4 |
| Watchdog edge detector | `wdtirq` | 2 |
| UART overflow flag | `UARTov` | 3 |
| `NPUTHINK` readback | `nputhk` | 1 |

## Errata with no scar

| Erratum | Why |
|---|---|
| SARADC converts at one quarter of the intended rate | The trigger waveform drives the analog macro, which the behavioral model does not reproduce |
| The bootloader cannot boot from SPI flash | A wrong register in Myshkin's mask ROM; Castalia has a different boot ROM |
| The potentiostat control loop oscillates | Analog |

## Adding a scar

1. The test name has at most six characters: `TEST_FILE` is a fixed 29-character string.
2. Set `t4` before each check, so a failure names the check. `scar.h` holds the trap plumbing.
3. Include a control: an operand or encoding that passed even with the bug.
4. Prove it. Revert the fix, confirm the test fails at the expected check, and record that here.
5. Add the test to `Makefrag`, the `CATALOG` in `platform/common/python/verify_stage.py`, and
   `_RV32USCAR_TESTS` in `verification/isa/BUILD.bazel`.
