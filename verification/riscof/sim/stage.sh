#!/bin/bash
# Compile and elaborate the behavioural Castalia sim once into STAGE (default
# <repo>/xcelium/riscof). Each test then runs from its own directory against
# this one snapshot, through sim/run_test.sh.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
STAGE="${STAGE:-$REPO/xcelium/riscof}"
set +u; source "$REPO/tools/source_cdspaths.sh"; set -u
# cell_list.txt names the pad library as $VESTA_TSMC65_IP; expanded below.
VESTA_TSMC65_IP="${VESTA_TSMC65_IP:-$HOME/lib/TSMC65-IP}"
mkdir -p "$STAGE"
cd "$STAGE"
if [ ! -f "$REPO/software/bootrom_mp/bin/rom.rcf" ]; then
    mkdir -p "$REPO/software/bootrom_mp/obj" "$REPO/software/bootrom_mp/bin"
    make -C "$REPO/software/bootrom_mp"
fi
# ARM_IP_ROM.vhd is an untracked model with the ROM path hardcoded to the owner's
# checkout, so prove that ROM is the one this tree builds.
cmp "$REPO/software/bootrom_mp/bin/rom.rcf" "$HOME/vestarv/software/bootrom_mp/bin/rom.rcf"
/usr/bin/python3.6 "$HERE/gen_tb.py" "$REPO/hdl/common/tb/riscv_tb.vhd" riscof_tb.vhd
sed -e "s#^\.\./\.\./hdl/common/sim/ARM_IP#$HOME/vestarv/hdl/common/sim/ARM_IP#" \
    -e "s#^\.\./\.\./#$REPO/#" -e "s#^\$VESTA_TSMC65_IP/#$VESTA_TSMC65_IP/#" "$HERE/cell_list.txt" > cell_list.txt
rm -rf xcelium.d
xrun -elaborate $(cat cell_list.txt) -top riscv_tb -v200x -work work -access +r \
     -controlrelax nlstex -relax -snapshot riscof -xmlibdirname "$STAGE/xcelium.d" \
     -l "$STAGE/elab.log"
tail -3 "$STAGE/elab.log"
