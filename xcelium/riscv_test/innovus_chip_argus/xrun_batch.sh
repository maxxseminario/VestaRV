#!/bin/bash
# =============================================================================
# xrun_batch.sh — compile + simulate ONE Argus gate-level (post-P&R, SDF) test
# headless. Output: xrun.log (written by xrun itself); grep for "TEST PASSED"
# / "TEST FAILED". NEVER pipe through head (SIGPIPE kills the sim -> stale
# xrun.log; see CLAUDE.md).
# Gate sims are much slower than behavioral — do not apply the 1-minute rule.
#   ./xrun_batch.sh            # default test: simple
#   ./xrun_batch.sh shboot     # partial match on ../rca/*.rcf
# =============================================================================
cd "$(dirname "$0")"
XRUN_MODE="batch" exec ./xrun.sh "$@"
