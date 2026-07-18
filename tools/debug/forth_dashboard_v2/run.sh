#!/usr/bin/env bash
#
# Forth Dashboard v2 launcher.
#
# Usage:
#   ./run.sh [--sim] [--port /dev/ttyAMA0] [--baud 115200] \
#            [--listen 0.0.0.0:8060] [--reset-pin N]
#
# All arguments are passed through verbatim to server/main.py.  Sim mode needs
# no hardware:
#   ./run.sh --sim
# then open http://<host>:8060 .  On the Raspberry Pi (real UART):
#   ./run.sh --port /dev/ttyAMA0 --reset-pin 17
#
# The script cd's to its own directory first, so it works from anywhere.
set -euo pipefail

# --- locate ourselves and cd there -----------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIR"

# --- pick an interpreter ----------------------------------------------------
PYTHON="${PYTHON:-python3}"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
    echo "ERROR: '$PYTHON' not found on PATH." >&2
    echo "       Install Python 3.6 or newer (target Raspberry Pi ships 3.9+)." >&2
    exit 1
fi

# --- require Python >= 3.6 --------------------------------------------------
# Read stdin (never 'python3 -c \"...\"': this host's Calibre python3 wrapper
# strips quotes from -c arguments).
if ! "$PYTHON" - <<'PY'
import sys
sys.exit(0 if sys.version_info[:2] >= (3, 6) else 1)
PY
then
    ver="$("$PYTHON" --version 2>&1 || true)"
    echo "ERROR: Python 3.6+ required, found: $ver" >&2
    exit 1
fi

# --- require fastapi (names requirements.txt on failure) --------------------
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

# --- launch (all args pass through to the backend) --------------------------
exec "$PYTHON" server/main.py "$@"
