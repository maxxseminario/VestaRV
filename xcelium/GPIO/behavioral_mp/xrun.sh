#!/bin/bash
# Standalone behavioral sim of the MCU_MP (Castalia) GPIO peripheral testbench
# (hdl/common/tb/GPIO_tb.vhd) — the multi-AF (PxAFS) capable twin of
# xcelium/GPIO/behavioral, which covers the frozen Myshkin GPIO.
#
# Self-checking: the TB prints "ALL CHECKS PASSED" or "N CHECK(S) FAILED" and
# ends with std.env.stop. Run headless by default; pass -gui for SimVision.
#
# Headless runs read stdin from /dev/null so that after std.env.stop drops to
# the xcelium> prompt, the EOF makes xrun exit instead of hanging.
#
# Remember to `source ~/vestarv/cdspaths.sh` first (sets PATH + license).

set -e

GUI=""
STDIN_REDIR="< /dev/null"
if [ "$1" == "-gui" ]; then
    GUI="-gui -input ../../disable_x_warnings.tcl"
    STDIN_REDIR=""
fi

LOG_PATH="log"
LIB_PATH="xcelium.d"

[ -d "$LIB_PATH" ] && rm -r "$LIB_PATH"
mkdir -p "$LOG_PATH"

hdlFiles="$(< cell_list_behavioral.txt)"

eval xrun \
    $hdlFiles \
    -top GPIO_tb \
    -v200x \
    -work work \
    -access +r \
    -controlrelax nlstex \
    -relax \
    $GUI \
    -timescale 1ns/1ps \
    -log "$LOG_PATH/xrun_gpio.log" \
    $STDIN_REDIR
