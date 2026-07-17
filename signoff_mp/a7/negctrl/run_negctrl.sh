#!/bin/bash
cd /home/mseminario2/vestarv/signoff_mp || exit 2
source ~/vestarv/cdspaths.sh 2>/dev/null
which pegasus > a7/negctrl/negctrl.runstart 2>&1
date '+NEGCTRL_START %Y-%m-%d %H:%M:%S' >> a7/negctrl/negctrl.runstart
DECK=/opt/design_kits/TSMC65-PDK/kit/PVS/LVS/pvs.lvs
CTL=$(readlink -f pvs/lvs_chip_argus_ctl)
WORK=a7/negctrl/work
mkdir -p "$WORK"
pegasus -lvs -check_schematic -control "$CTL" \
    -gds a7/negctrl/chip_top_short.gds -layout_top_cell chip_top \
    -source_top_cell chip_top -source_cdl a7/negctrl/clean.cdl \
    -run_dir "$WORK" \
    "$DECK" > a7/negctrl/pegasus_stdout.log 2>&1
echo "NEGCTRL_RC=$?" > a7/negctrl/negctrl.rc
