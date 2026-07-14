#!/bin/bash
# build_mp_images.sh -- build multi-hart sh + ISA test images at a chosen NHARTS
# into a chosen rcf output dir. Argus (A3) needs an N=18 image set kept SEPARATE
# from the Castalia N=4 rcf/ (the behavioral_mp runner symlinks ../rcf -> ./rcf).
#
#   ./build_mp_images.sh <NHARTS> <dest_rcf_dir> [group ...]
#
# groups default to the full set the behavioral_mp runner consumes. NHARTS is
# injected as -DNHARTS=<n> (the sh tests' "#ifndef NHARTS" default is 4). We
# reproduce the Makefile default RISCV_GCC_OPTS and APPEND the define, because
# overriding RISCV_GCC_OPTS on the command line replaces it wholesale.
#
# WAR STORY (memory: vestarv-isa-build-header-dep-gotcha): "make <g>-flash"
# riscv32-clean does NOT rebuild on a shared-header (mp_boot.h) change, so we
# "rm -rf build/" FIRST to force a full rebuild -- otherwise stale images
# silently keep the old NHARTS / loader base.
#
# NOTE: this env's bash mis-expands "arr=(\"$@\")" after a shift, so we iterate
# the positional params directly instead of copying them into an array.
set -euo pipefail

NH="${1:?usage: build_mp_images.sh <NHARTS> <dest_rcf_dir> [group ...]}"
DEST="${2:?usage: build_mp_images.sh <NHARTS> <dest_rcf_dir> [group ...]}"
shift 2
if [ "$#" -eq 0 ]; then
    set -- rv32ui rv32ua rv32um rv32uc rv32uzba rv32uzbb rv32uzbc rv32uzbs
fi

BASE_OPTS="-static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles"
cd "$(dirname "$0")"

echo "=== build_mp_images: NHARTS=$NH  dest=$DEST  groups=[$*] ==="
rm -rf build/                       # force full rebuild (header-dep gotcha)

for g in "$@"; do
    echo "--- ${g}-flash (NHARTS=$NH) ---"
    make "${g}-flash" RISCV_GCC_OPTS="$BASE_OPTS -DNHARTS=$NH"
done

# DEST == rcf/ guard (M19 war story): make already populates rcf/ during the
# build; the rm/cp below would DELETE the fresh set and then fail to copy it
# onto itself. Only stage out when DEST is a different directory.
# M19c: pwd -P (PHYSICAL) — xcelium/riscv_test/rcf is a SYMLINK to this
# rcf/; the logical-pwd compare missed that and the stage-out rm'd the
# canonical set through the alias, then cp'd onto an empty glob.
if [ "$(cd "$DEST" 2>/dev/null && pwd -P)" != "$(cd rcf && pwd -P)" ]; then
    mkdir -p "$DEST"
    rm -f "$DEST"/*.rcf
    cp rcf/*.rcf "$DEST"/
    # M19c POST-MORTEM: the build TRANSITS through rcf/, so after an
    # out-of-tree stage (e.g. the Argus N=18 set) rcf/ is left holding
    # $NH-flavored images too — this silently poisoned the Castalia rcf/
    # after the M19b Argus verify (sh tests gathered h=1..17 at N=4;
    # 12/26 behavioral smoke failures, chased through three sim levels).
    echo "WARNING: rcf/ now ALSO holds the NHARTS=$NH set (build transit)."
    echo "         Rebuild the canonical set before Castalia sims:"
    echo "         ./build_mp_images.sh 4 ../../xcelium/riscv_test/rcf"
fi
# .nharts = the TRUTH of what each dir currently holds (runners guard on it).
echo "$NH" > "$DEST/.nharts"
echo "$NH" > rcf/.nharts
echo "=== done: $(ls "$DEST"/*.rcf | wc -l) rcf files in $DEST (NHARTS=$NH) ==="
