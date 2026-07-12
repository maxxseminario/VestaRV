#!/bin/bash
# Show the current resolved chip configuration (make show).
# Thin wrapper: the real work is python/show_config.py, which reads the
# unified-config artifacts (config/ChipConfig.resolved.json, PadRing.json,
# MemoryMap.json) written by every `make chip` / `make generate` run.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
exec python3 "$SCRIPT_DIR/python/show_config.py"
