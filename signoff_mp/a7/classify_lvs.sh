#!/bin/bash
# A7 LVS residual classifier -- headers/bounded greps ONLY (cls can be ~53GB).
set -u
cd /home/mseminario2/vestarv/signoff_mp
W=pvs/chip_argus_a7_signoff/chip_top
CLS=$W/lvs.rep.cls
echo "===== A7 LVS classification ($(date '+%H:%M:%S')) ====="
echo "--- report freshness ---"
ls -la $W/lvs.rep $CLS $W/lvs.rep.shorts 2>/dev/null
echo "--- pegasus rc ---"; cat a7/lvs.rc 2>/dev/null
echo "--- Run Result + summary table (top of cls, fast) ---"
grep -a -m 8 -E 'Run Result|^Total\s+\||^Nets\s+\||^Instances\s+\||^Ports\s+\|' "$CLS" 2>/dev/null
echo "--- lvs.rep.shorts (must be empty) ---"
if [ -s "$W/lvs.rep.shorts" ]; then echo "NON-EMPTY:"; head -20 "$W/lvs.rep.shorts"; else echo "EMPTY (0 shorts) OR absent"; ls -la "$W/lvs.rep.shorts"; fi
echo "--- softchk substrate class (n_psub/psub, accepted) ---"
grep -aE 'n_psub|[^_]psub .*-TYPE|Stamping conflict' $W/lvs.rep 2>/dev/null | head
echo "--- VDD_SW cpoint bindings (label-transform proof: expect ~18, small) ---"
grep -a -m 40 'VDD_SW' "$CLS" 2>/dev/null | head -40
echo "--- VDD_SW_H count in mismatch (bounded) ---"
grep -a -m 60 -c 'VDD_SW_H' "$CLS" 2>/dev/null
