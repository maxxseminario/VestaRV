# Myshkin Forth mode from a Raspberry Pi 4

Pi setup and wiring: [`RPI_SETUP.md`](RPI_SETUP.md) (`enable_uart=1`, `dtoverlay=disable-bt`,
serial console off, user in `dialout,gpio`, `python3-serial python3-gpiozero`).

```bash
cd ~/vestarv/tools/debug
python3 rv4th_terminal.py --reset-pin 17
```

Selects Forth mode (BOOT via GPIO18), resets the chip, and shows `myshkin rv4th-rom!` and a
`>` prompt. `-500 75689 * .` prints `-37844500`. Ctrl-C exits.

| Directory | Contents |
|---|---|
| [`forth_dashboard/`](forth_dashboard/README.md) | Browser GUI v1, port 8050 (installed on boards) |
| [`forth_dashboard_v2/`](forth_dashboard_v2/README.md) | FastAPI rework, port 8060 |
| [`riscv-tests-debug/`](riscv-tests-debug/README.md) | gdb/OpenOCD debug tests |
