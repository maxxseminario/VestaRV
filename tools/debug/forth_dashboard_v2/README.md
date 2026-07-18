# Forth Dashboard v2 — Myshkin rv4th debug GUI

A browser dashboard for driving the **Myshkin** RISC-V MCU over UART while it
runs its on-chip **rv4th Forth ROM** (BOOT pin `P1.7` held LOW at reset → the
chip prints `myshkin rv4th-rom!` and drops to a `>` Forth REPL at 115200 8N1).

This is the v2 rework of `tools/debug/forth_dashboard/` (the Plotly Dash app,
still available on port 8050). v2 is a FastAPI backend + a self-contained
vanilla-JS single-page frontend — **zero CDN / zero internet dependency at
runtime** (the Raspberry Pi may be offline). v1 is untouched; both can run at
once.

## What it is

A single-owner serial core (one thread owns the port, everything queues through
it, framing is driven by the chip's echo + `>` prompt — no `sleep()`
synchronization) behind a REST + one-WebSocket API, serving these features:

| # | Feature |
|---|---------|
| F1 | Connection manager — port scan/pick, baud, connect/disconnect, GPIO reset, live state badge, banner detect |
| F2 | Interactive terminal — WS-streamed, colored TX/RX, ↑/↓ history, Tab-completion of Forth words + register names, log export |
| F3 | Register browser — per-peripheral panels from `registers.json`; bitfield editors; read/write/read-all; cached-vs-chip dirty highlighting; raw hex entry |
| F4 | Memory tools — hex-dump viewer (`mr`, paged), poke/peek (`@`/`!`), region erase (`me`), dump-to-file |
| F5 | Code runner — upload `.bin` → `!`-loop into RAM (verify readback) → `call0` at entry ("jump the PC"); shows the return value |
| F6 | Flash programmer — page erase (`fe` key 123) / write (`fw`) / read-verify (`fr`), image upload with progress, per-page status |
| F7 | GPIO panel — 4 ports × 8 pins live view; click-toggle outputs, direction switches (`POUTS`/`POUTC`/`POUTT`) |
| F8 | Clock / system panel — `clk` measurements for the clock-mux inputs, `rst`, system-register shortcuts |
| F9 | Macros / scripts — named Forth-snippet library (JSON on disk), one-click run, record-from-terminal |
| F10 | Session log — every TX/RX with timestamps, filter, download |

## Quick start (sim mode — no hardware)

Sim mode runs an in-process byte-level emulation of the rv4th REPL (`SimChip`),
so the whole stack works with nothing plugged in:

```bash
cd tools/debug/forth_dashboard_v2
python3 -m pip install -r requirements.txt   # first time only
./run.sh --sim
```

Then open **http://<host>:8060** (default port 8060; v1 keeps 8050).

`run.sh` cd's to its own directory, checks for Python ≥ 3.6 and that `fastapi`
imports (pointing you at `requirements.txt` otherwise), then execs
`server/main.py`. All flags pass straight through:

```
./run.sh [--sim] [--port /dev/ttyAMA0] [--baud 115200] \
         [--listen 0.0.0.0:8060] [--reset-pin N]
```

## Hardware setup (Raspberry Pi 4)

Proven steps from `tools/debug/RPI_SETUP.md` and `rv4th_terminal.py`.

**1. Move the PL011 UART off Bluetooth onto GPIO14/15.** Edit `/boot/config.txt`
(or `/boot/firmware/config.txt` on newer Raspberry Pi OS) and add:

```ini
enable_uart=1
dtoverlay=disable-bt
```

Reboot, then confirm `/dev/ttyAMA0` exists (`ls -la /dev/ttyAMA0 /dev/serial0`).

**2. Join the `dialout` group** (log out/in afterward):

```bash
sudo usermod -aG dialout $USER
```

If a serial login console is enabled, disable the *login shell* on serial but
keep the hardware UART (`sudo raspi-config` → Interface Options → Serial Port),
or the console's echo doubles your characters.

**3. Wiring** (both sides are 3.3 V — no level shifter; a 1 kΩ series resistor on
the chip TX line is optional protection). It is a crossover:

| Myshkin chip pad | → | RPi 4 header |
|------------------|---|--------------|
| `P2.4` (TX0, UART out) | → | Pin 10 (GPIO15 / RXD0) |
| `P2.5` (RX0, UART in)  | ← | Pin 8 (GPIO14 / TXD0) |
| `GND`                  | — | Pin 6 (GND) |
| `resetn` (active-low, optional) | ← | Pin 11 (GPIO17) — use `--reset-pin 17` |

**4. Enter rv4th-ROM mode.** Hold **BOOT (`P1.7`) LOW** while resetting the chip
(button, or GPIO17 via the reset button in the UI / `--reset-pin`). You should
see the `myshkin rv4th-rom!` banner and a `>` prompt. GPIO reset needs
`gpiozero` (pre-installed on Raspberry Pi OS; `sudo apt install python3-gpiozero`
otherwise). It is optional — the backend runs fine without it (reset just
reports `gpiozero-missing`).

**5. Run:**

```bash
cd tools/debug/forth_dashboard_v2
./run.sh --port /dev/ttyAMA0 --listen 0.0.0.0:8060 --reset-pin 17
```

### Run at boot with systemd

`myshkin-dashboard.service` runs `run.sh` against the real UART as user `pi`
(group `dialout`), `Restart=on-failure`, `After=network.target`. Edit its
`WorkingDirectory`/`ExecStart` paths if your checkout is elsewhere, then:

```bash
sudo cp myshkin-dashboard.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now myshkin-dashboard.service
journalctl -u myshkin-dashboard.service -f     # follow logs
```

## Architecture

```
browser SPA  ──REST──▶  FastAPI (server/main.py)  ──▶  SerialManager  ──▶  UART / SimChip
     └────── WebSocket /ws ──────────────────────────────┘   (one owner thread + queue)
```

- **`serial_manager.py`** — the heart: ONE thread owns the port; every REST
  handler and every WS terminal keystroke enqueues a transaction and awaits a
  Future, so nothing ever interleaves. Framing is prompt-driven (consume the
  chip's echo, read to the `>` prompt) with per-command timeout + resync-retry;
  explicit connection state machine and auto-reconnect.
- **`forth.py`** — command builders + response parsers for every Forth word the
  dashboard uses (`@`/`!`, `mr`, `fr`/`fw`/`fe`, `call0..4`, `clk`, …).
- **`sim_chip.py`** — `SimChip`, a transport (same read/write/close surface as
  the real serial port) that emulates the rv4th REPL at the *byte* level. It
  does NOT special-case API endpoints, so sim mode exercises the whole real
  stack.
- **`memops.py`** — bulk ops: ASCII/binary `mr` framing, the word-wise `!`-loop
  upload, and the `fw` `$`/CRC/`Y` flash handshake.
- **`registers.py` / `data/registers.json`** — the register map is data (see
  below). **`macros.py`** — the JSON-file macro store.
- **REST** for request/response; **one WebSocket `/ws`** streams every serial
  event (`tx`/`rx`/`info`/`error`/`state`, timestamped) to all clients, and the
  terminal's keystrokes ride the same socket.

Run `python3 server/main.py --help` (or read the plan) for the full frozen API
contract.

## Regenerating `data/registers.json`

The register map is generated from v1's Python config dicts (the single source
of truth), never hand-edited:

```bash
cd tools/debug/forth_dashboard_v2/data
python3 gen_registers.py          # imports v1 peripherals_config + bitfields_config
```

## Running the tests

```bash
cd tools/debug/forth_dashboard_v2
python3 -m pytest tests/ -q
```

`tests/test_e2e_sim.py` boots the real server as a subprocess in sim mode on a
random localhost port and drives a full bench session over plain HTTP (command
round-trip, register write/readback, memory + flash cycles, exec, macros). All
tests run against `SimChip` and need no hardware; they skip cleanly if
`fastapi`/`uvicorn` are missing.

## Known limitations

- **Never send `0 echo`.** The GUI's serial framing depends on the chip echoing
  every character AND printing the `>` prompt. `0 echo` suppresses *both* (it
  gates `getLine`), so every framed command then times out until you
  reconnect/reset the chip. Leave echo ON.
- **`mw` is a ROM stub** (does nothing). Bulk RAM uploads therefore use `!`
  loops — word-by-word — at roughly **1.3 KB/s** effective over 115200. Fine for
  KB-scale images (the code runner shows a progress bar), but not for large
  blobs.
- **Flash `page` parameters in the API are page INDICES**, not byte addresses.
  The backend multiplies by 256 (`page × 256` = byte address) before issuing
  `fe`/`fw`. So `page: 3` programs the flash page starting at byte `0x300`.
- **Compressed (mode 2) `mr`/`fw` payloads are not supported by the backend.**
  Only ASCII-hex (mode 0) and raw-binary (mode 1) transfers are implemented;
  the ROM's compressed mode is out of scope for v2.0.
