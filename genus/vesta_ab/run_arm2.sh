#!/bin/bash
# usage: run_arm2.sh <ARM_NAME> <VESTA_FILE> [IF_AHEAD_PARAM]   (v2 TCL)
set +u
source /home/mseminario2/vestarv/cdspaths.sh
cd /home/mseminario2/vestarv/genus/vesta_ab
export ARM_NAME="$1"
export VESTA_FILE="$2"
export IF_AHEAD_PARAM="${3:-}"
echo "=== starting arm $ARM_NAME at $(date) ==="
genus -no_gui -overwrite -log log/$ARM_NAME -files tcl/vesta_ab.genus.v2.tcl
echo "=== arm $ARM_NAME genus exit=$? at $(date) ==="
