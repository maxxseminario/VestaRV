#!/bin/bash
# =============================================================================
# xrun_batch.sh — compile + simulate ONE MCU_MP test headless (no GUI).
#
#   ./xrun_batch.sh            # default test: shmem
#   ./xrun_batch.sh add        # partial match on ../rcf/*.rcf
#
# Output: xrun.log. Healthy sim = ~1 min after compile (~4 min); grep for
# "TEST PASSED" / "TEST FAILED". Longer = HUNG: Ctrl-C, pkill -9 xmsim,
# investigate (SHMEM_DEBUG_NOTES.txt).
# =============================================================================
cd "$(dirname "$0")"
XRUN_MODE="batch" XRUN_EXTRA_INPUT="batch_run.tcl" exec ./xrun.sh "$@"
