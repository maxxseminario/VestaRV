#!/bin/bash
# One simulation in the current directory. $1 = run dir (holds cds.lib), $2 = snapshot name.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/cdspaths.sh" >/dev/null 2>&1
printf 'run\nexit\n' > batch.tcl
exec xmsim -cdslib "$1/cds.lib" "work.$2:behavioral" -input "$ROOT/xcelium/disable_x_warnings.tcl" -input batch.tcl -licqueue -LOGFILE xmsim.log
