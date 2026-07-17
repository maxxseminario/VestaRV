#!/bin/bash
# A7 clean LVS re-run, DETACHED (setsid) so a harness background-task kill
# cannot reap pegasus mid-report (first attempt died at exactly 60min during
# report Create; compare itself was complete, balloon gone).
cd /home/mseminario2/vestarv/signoff_mp || exit 2
source ~/vestarv/cdspaths.sh 2>/dev/null
date '+%Y-%m-%d %H:%M:%S' > a7/lvs_rerun.runstart
rm -f a7/lvs_rerun.rc
LVSLABELS=pvs/chip_top_argus_a7.lvslabels ./lvs.sh chip_argus_a7_signoff chip_top \
    pvs/chip_top_argus_a7_full.lvs.v lvs_include_chip pvs/lvs_chip_argus_ctl \
    > a7/lvs_rerun.stdout 2>&1
echo "LVS_RERUN_EXIT=$?" > a7/lvs_rerun.rc
