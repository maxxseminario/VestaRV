#!/usr/bin/env bash
# VestaRV: Forth dashboard v2 launcher.
# Usage: ./run.sh [--sim] [--port /dev/ttyAMA0] [--baud 115200]
#                 [--listen 0.0.0.0:8060] [--reset-pin N]
# Arguments pass through verbatim to server/main.py. --sim needs no hardware;
# on the Raspberry Pi use --port /dev/ttyAMA0 --reset-pin 17. The dashboard
# serves on http://<host>:8060. Runs from anywhere: it cd's to its own directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIR"

PYTHON="${PYTHON:-python3}"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
    echo "ERROR: '$PYTHON' not found on PATH." >&2
    echo "       Install Python 3.6 or newer (target Raspberry Pi ships 3.9+)." >&2
    exit 1
fi

# The probe reads stdin rather than taking -c: this host's Calibre python3
# wrapper strips the quotes from a -c argument.
if ! "$PYTHON" - <<'PY'
import sys
sys.exit(0 if sys.version_info[:2] >= (3, 6) else 1)
PY
then
    ver="$("$PYTHON" --version 2>&1 || true)"
    echo "ERROR: Python 3.6+ required, found: $ver" >&2
    exit 1
fi

if ! "$PYTHON" - <<'PY' 2>/dev/null
import importlib
importlib.import_module("fastapi")
importlib.import_module("uvicorn")
PY
then
    echo "ERROR: the 'fastapi' / 'uvicorn' packages are not importable." >&2
    echo "       Install the dependencies first:" >&2
    echo "           $PYTHON -m pip install -r ${SCRIPT_DIR}/requirements.txt" >&2
    exit 1
fi

exec "$PYTHON" server/main.py "$@"
