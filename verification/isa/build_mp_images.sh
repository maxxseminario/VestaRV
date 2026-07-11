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

mkdir -p "$DEST"
rm -f "$DEST"/*.rcf
cp rcf/*.rcf "$DEST"/
echo "=== done: $(ls "$DEST"/*.rcf | wc -l) rcf files in $DEST (NHARTS=$NH) ==="
