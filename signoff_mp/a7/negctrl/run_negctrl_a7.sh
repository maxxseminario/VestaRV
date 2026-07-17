#!/bin/bash
# A7 negative control (DEF-verified opposite-net B1-band VDD/VSS followpin short).
# Injects M1 bridge x[200,201] y[1254.5,1257.5]um shorting VSS@1255 (DEF line 20234)
# and VDD@1257 (DEF line 278). Runs an ISOLATED pegasus LVS vs the clean A7 run.
cd /home/mseminario2/vestarv/signoff_mp || exit 2
source ~/vestarv/cdspaths.sh 2>/dev/null
which pegasus > a7/negctrl/negctrl_a7.runstart 2>&1
date '+NEGCTRL_A7_START %Y-%m-%d %H:%M:%S' >> a7/negctrl/negctrl_a7.runstart
DECK=/opt/design_kits/TSMC65-PDK/kit/PVS/LVS/pvs.lvs
CTL=$(readlink -f pvs/lvs_chip_argus_ctl)
WORK=a7/negctrl/work_a7
rm -rf "$WORK"; mkdir -p "$WORK"
pegasus -lvs -check_schematic -control "$CTL" \
    -gds a7/negctrl/chip_top_short_a7.gds -layout_top_cell chip_top \
    -source_top_cell chip_top -source_cdl a7/negctrl/clean_a7.cdl \
    -run_dir "$WORK" \
    "$DECK" > a7/negctrl/pegasus_a7_stdout.log 2>&1
echo "NEGCTRL_A7_RC=$?" > a7/negctrl/negctrl_a7.rc
cat a7/negctrl/negctrl_a7.rc
