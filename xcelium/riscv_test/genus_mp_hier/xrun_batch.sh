#!/bin/bash
# =============================================================================
# xrun_batch.sh — compile + simulate ONE gate-level (post-genus, SDF) MCU_MP
# test headless. Output: xrun.log; grep for "TEST PASSED" / "TEST FAILED".
# Gate sims are much slower than behavioral — do not apply the 1-minute rule.
#   ./xrun_batch.sh            # default test: simple
#   ./xrun_batch.sh add        # partial match on ../rcf/*.rcf
# =============================================================================
cd "$(dirname "$0")"
XRUN_MODE="batch" exec ./xrun.sh "$@"
