# afefsm

The simplest possible AFE bring-up program: just enable the bias
generator, route four FSM signals onto the AFE digital test ports
(DTP0..DTP3), and put the AFE FSM into continuous-measurement mode
so it cycles forever on its own.

No globals, no polling, no LED, no UART. The CPU drops into `wfi`
immediately after kicking off the first conversion.

## DTP signal map (after this program runs)

| Pin   | Mux idx | Signal       | What you should see                              |
|-------|---------|--------------|--------------------------------------------------|
| DTP0  | 4       | `adc_clk`    | Free-running ADC clock                           |
| DTP1  | 0       | `ADCACTIVE`  | High for the duration of each conversion         |
| DTP2  | 3       | `adc_done`   | Single-cycle pulse at the end of each conversion |
| DTP3  | 8       | `adc_start`  | Single-cycle pulse at the start of each conversion |

If you see DTP0 toggling and DTP1 pulsing high in a periodic pattern,
the AFE clock domain is alive and the FSM is sequencing.

## Build

```sh
make
```

Produces `bin/afefsm.hex`, `bin/afefsm.dump` and `rcf/*.rcf`.

## Run on chip

From `implementations/asic/myshkin-2025-11/`:

```sh
make run afefsm
```

(Defaults to `--method poke --verify`. Entry is `0x0000814C`.)
