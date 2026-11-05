#!/bin/bash
# $1 = flat dir (cds.lib), $2 = image .rcf, $3 = tag. One elaboration per image: TEST_FILE is a generic.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/cdspaths.sh" >/dev/null 2>&1
xmelab -cdslib "$1/cds.lib" -ACCESS +r -GENERIC "vesta_cpi_tb:TEST_FILE=>\"$2\"" -GENERIC "vesta_cpi_tb:TEST_NAME=>\"$3\"" -SNAPSHOT "work.flat_$3" work.vesta_cpi_tb:sim > elab.log 2>&1 || { tail elab.log; exit 1; }
printf 'run\nexit\n' > batch.tcl
xmsim -cdslib "$1/cds.lib" "work.flat_$3:sim" -input batch.tcl -licqueue -LOGFILE xmsim.log
