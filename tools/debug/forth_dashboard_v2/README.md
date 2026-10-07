# Forth Dashboard v2 — Myshkin rv4th debug GUI

Browser dashboard for the Myshkin MCU running its rv4th Forth ROM (BOOT `P1.7` low at reset →
`myshkin rv4th-rom!` banner and `>` prompt, 115200 8N1). FastAPI backend plus a self-contained
JS frontend with no CDN or internet dependency. Rework of
[`../forth_dashboard`](../forth_dashboard/README.md) (port 8050, unchanged); both can run at once.

Features: connection manager with GPIO reset, terminal, register browser with bitfield editors,
memory dump/peek/poke/erase, code runner (upload `.bin` to RAM, `call0`), flash programmer,
GPIO panel, clock/system panel, macro library, session log.

## Run

```bash
cd tools/debug/forth_dashboard_v2
python3 -m pip install -r requirements.txt                          # first time
./run.sh --sim                                                      # no hardware
./run.sh --port /dev/ttyAMA0 --listen 0.0.0.0:8060 --reset-pin 17   # Raspberry Pi
```

Open `http://<host>:8060`. Flags (`--sim --port --baud --listen --reset-pin`) pass through to
`server/main.py`. `--sim` uses `SimChip`, a byte-level emulation of the REPL that exercises
the full stack. GPIO reset needs `gpiozero`; without it reset reports `gpiozero-missing`.

Pi setup and wiring: [`../README.md`](../README.md), [`../RPI_SETUP.md`](../RPI_SETUP.md).
Disable the serial login console, or its echo doubles characters.

At boot via systemd (edit `WorkingDirectory`/`ExecStart` if the checkout is elsewhere):

```bash
sudo cp myshkin-dashboard.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now myshkin-dashboard.service
```

## Layout

| Path | Role |
|---|---|
| `server/main.py` | FastAPI app: REST + one WebSocket `/ws` (`--help` for the API) |
| `server/serial_manager.py` | Single thread owns the port; all requests queue through it; prompt-driven framing |
| `server/forth.py`, `memops.py` | Forth command builders/parsers; bulk `mr`, `!`-loop upload, `fw` handshake |
| `server/sim_chip.py` | `SimChip` transport |
| `data/registers.json` | Register map, generated — never hand-edit |

Regenerate the register map from v1's config dicts:

```bash
cd tools/debug/forth_dashboard_v2/data && python3 gen_registers.py
```

## Tests

`python3 -m pytest tests/ -q` from this directory; all tests run against `SimChip` and skip if
`fastapi`/`uvicorn` are missing.

## Limitations

- Never send `0 echo`: it suppresses the echo and `>` prompt the framing depends on; every
  command then times out until reconnect/reset.
- `mw` is a ROM stub, so RAM uploads use `!` loops at about 1.3 KB/s.
- API flash `page` parameters are page indices; byte address = `page × 256`.
- Compressed (mode 2) `mr`/`fw` transfers are unsupported; only modes 0 and 1.
