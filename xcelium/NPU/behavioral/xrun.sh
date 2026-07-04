#!/bin/bash
# Standalone behavioral sim of the NPU peripheral testbench (tb/NPU_tb.vhd).
#
# Self-checking: loads inputs/weights into SRAM, runs the 2-layer MLP over all
# test points, compares each output against npu_expected_fp_outputs.txt, then
# prints "ALL CHECKS PASSED" or "N CHECK(S) FAILED" and ends with std.env.stop.
# Run headless by default; pass -gui for SimVision.
#
# Headless runs read stdin from /dev/null so that after std.env.stop drops to
# the xcelium> prompt, the EOF makes xrun exit instead of hanging.
#
# Requires npu_fp_inputs.txt, npu_fp_weights.txt, npu_expected_fp_outputs.txt
# in this directory. Remember to `source ~/vestarv/cdspaths.sh` first.

set -e

GUI=""
STDIN_REDIR="< /dev/null"
if [ "$1" == "-gui" ]; then
    GUI="-gui -input restore.tcl -input ../../disable_x_warnings.tcl"
    STDIN_REDIR=""
fi

LOG_PATH="log"
LIB_PATH="xcelium.d"

[ -d "$LIB_PATH" ] && rm -r "$LIB_PATH"
mkdir -p "$LOG_PATH"

hdlFiles="$(< cell_list_behavioral.txt)"

eval xrun \
    $hdlFiles \
    -top NPU_tb \
    -v200x \
    -work work \
    -access +r \
    -controlrelax nlstex \
    -relax \
    $GUI \
    -timescale 1ns/1ps \
    -log "$LOG_PATH/xrun_npu.log" \
    $STDIN_REDIR
