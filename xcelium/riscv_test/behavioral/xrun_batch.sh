#!/bin/bash

# Batch-mode simulation — compiles and runs without opening the SimVision GUI.
# Usage: ./xrun_batch.sh
# Output: xrun.log (in this directory)

source ~/vestarv/cdspaths.sh

CDS_PATH="."
LOG_PATH="log"
LIB_PATH="xcelium.d"

# Clean up the library directory to prevent stale state from corrupting the run.
[ -d $LIB_PATH ] && rm -r $LIB_PATH
mkdir -p $LOG_PATH

hdlFiles="$(< cell_list_behavioral.txt)"

xrun \
    $hdlFiles \
    -top riscv_tb \
    -v200x \
    -work work \
    -access +r \
    -controlrelax nlstex \
    -relax \
    -input batch_run.tcl
