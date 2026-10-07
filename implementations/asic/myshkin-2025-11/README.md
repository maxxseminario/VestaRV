# Myshkin

First VestaRV tape-out: single-core mixed-signal MCU, TSMC 65 nm, November 2025;
silicon validated March 2026. RTL: frozen [`hdl/myshkin/`](../../../hdl/myshkin/README.md).

| | |
|---|---|
| Core | RV32IMAC + Zba/Zbb/Zbc/Zbs, 24 MHz; 16 KiB ROM, 32 KiB RAM |
| Peripherals | 4× GPIO, 2× SPI, 2× UART, 2× I²C, 2× timer, NPU, system control |
| Analog | Potentiostat front end, ADC |
| Die / package | 1.0 × 1.5 mm, QFN-44 |

The generator is frozen and outside Bazel (it overwrites tracked files); regenerate
only with `platform/myshkin/regenerate.sh`. Its register map
(`//platform/myshkin/gcc/lib:platform_headers`, `:linker_fragments`) is what every
Bazel firmware image compiles against.

Board: `make help` in this directory lists the serial flash and RAM-upload targets
(e.g. `make run-rcf blinky`).

Docs: `docs/TRM.pdf`; configs in `config/`; diagrams in `images/`.
Contact: Maxx Seminario (mseminario2@huskers.unl.edu).
