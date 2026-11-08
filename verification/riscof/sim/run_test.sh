#!/bin/bash
# Run one flash image on the staged library.
#   run_test.sh <image.rcf> <rundir> [<timeout-seconds>] [<tcl>]
# With bank0..3.rcf beside the image (mk_rcf.py preload), a private snapshot is
# elaborated with them baked into the bulk RAM macros, whose init is evaluated at
# static elaboration; otherwise the common snapshot runs and flash loads everything.
# Leaves <rundir>/signature.out and <rundir>/xrun.log. Exit 0 only on the bench's
# own "signature complete" line.
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
STAGE="${STAGE:-$REPO/xcelium/riscof}"
RCF="$(readlink -f "$1")"; RUN="$2"; TMO="${3:-900}"; TCL="${4:-$HERE/run.tcl}"
source "$REPO/tools/source_cdspaths.sh" >/dev/null
mkdir -p "$RUN"; cd "$RUN" || exit 2
rm -f signature.out xrun.log elab.log xxxxxxxxxxxxxxxxxxxximage.rcf
ln -s "$RCF" xxxxxxxxxxxxxxxxxxxximage.rcf
LIBS=(-cdslib "$STAGE/xcelium.d/riscof.d/cds.lib" -hdlvar "$STAGE/xcelium.d/riscof.d/hdlrun.var")
SNAP=riscof
IMGDIR="$(dirname "$RCF")"
if [ -f "$IMGDIR/bank0.rcf" ]; then
    SNAP="s$$"
    GPG=()
    for b in 0 1 2 3; do
        GPG+=(-gpg "riscv_tb.dut.shbank$b.INIT_FILE => \"$IMGDIR/bank$b.rcf\"")
    done
    xmelab "${LIBS[@]}" -access +r -relax -snapshot "$SNAP" \
        "${GPG[@]}" -logfile elab.log work.riscv_tb:behavioral >/dev/null 2>&1
fi
timeout -s KILL "$TMO" xmsim "${LIBS[@]}" -input "$TCL" -logfile xrun.log -nokey "$SNAP" >/dev/null 2>&1
rc=$?
[ "$SNAP" = riscof ] || xmrm "${LIBS[@]}" -snapshot "work.$SNAP" >/dev/null 2>&1
rm -rf .simvision waves.shm
if [ $rc -eq 137 ]; then echo "VESTA: wall-clock timeout ${TMO}s" >> xrun.log; fi
grep -q 'RISCOF: signature complete' xrun.log
