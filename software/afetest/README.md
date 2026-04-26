# afetest — Minimal AFE bring-up test

Smallest possible firmware to prove the Myshkin AFE peripheral is alive.

## What it does

1. Enables the on-chip bias generator (`BIAS_CR.EN`, `BIAS_CR.BUFEN`).
2. Programs the two AFE DACs:
   - `BIAS_DSADC_VCM` = 8192 (VDD/2 common mode)
   - `BIAS_REV_POT`   = 9192 (small +Δv excitation across the dummy cell)
3. Sets the TIA gain to the **minimum** (`BIAS_TIA_G_POT = 0x1FFFF`) so the amplifier cannot rail on an unknown resistor.
4. Routes useful internal signals to the four AFE digital test ports:
   - DTP0 → `adc_clk`
   - DTP1 → `ADCACTIVE`
   - DTP2 → `adc_done`
   - DTP3 → `adc_start`
5. Configures `AFE_CR` with `RAMPNUM=0xFFF`, `ADCEXTIN=1`, `DACEN=1`, `EN=1`, `ADCEN=1`.
6. Triggers 8 single-shot conversions and stores the latest 12-bit result in the global `afe_result`.
7. Blinks **P3.0** slowly (4 long pulses) on success or fast (8 short pulses) on timeout.

## Inspecting results

After flashing/running:

| Symbol | Meaning |
|---|---|
| `afe_result` | last successful 12-bit DSADC code |
| `afe_n_done` | how many of the 8 conversions completed |
| `afe_n_timeout` | how many timed out (FSM stuck) |
| `afe_status_snapshot` | last `AFE_SR` byte read |

Read them via GDB / OpenOCD, or watch DTP0–DTP3 on a scope to confirm the FSM is running even before any debugger is attached.

## Wiring (resistor dummy cell)

Connect a single resistor (e.g. 100 kΩ) between RE and WE pads, and tie CE to RE. With `BIAS_REV_POT` ≈ midscale + 1000 LSB the cell sees Δv ≈ +50 mV → I ≈ 500 nA, well inside the TIA range at minimum gain.

## Build

```bash
export RISCV_TOOLCHAIN_DIR=~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2
make all
```

Output: `bin/afetest.elf`, `bin/afetest.hex`, `bin/afetest.dump`, `rcf/*afetest.rcf`.
