#!/bin/bash

CDS_PATH="."
LOG_PATH="log"
HDL_DIR="../../../hdl"
LIB_PATH="xcelium.d"

[ -d $LIB_PATH ] && rm -r $LIB_PATH
mkdir -p $LOG_PATH

hdlFiles="$(< cell_list_behavioral.txt)"

stdbuf -oL xrun \
	$hdlFiles \
	-top NPU_tb \
	-v200x \
	-work work \
	-controlrelax nlstex \
	-relax \
	-input ../../disable_x_warnings.tcl \
	-input run_batch.tcl \
	2>&1 | tee $LOG_PATH/xrun_batch.log
