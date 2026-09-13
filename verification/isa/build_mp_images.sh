#!/bin/bash
# VestaRV: build the multi-hart sh and ISA test images at a chosen NHARTS into a
# chosen rcf output directory.
#   ./build_mp_images.sh <NHARTS> <dest_rcf_dir> [group ...]
# Groups default to the full set the behavioral_mp runner consumes. Each output
# directory holds one image set: the Argus N=18 set must stay separate from the
# Castalia set, because the runner symlinks ../rcf to ./rcf. NHARTS arrives as
# -DNHARTS=<n> appended to a reproduction of the Makefile's RISCV_GCC_OPTS, since
# overriding that variable on the command line replaces it wholesale. build/ is
# removed first: `make <g>-flash` does not rebuild on a shared-header change, so
# stale images would keep the old NHARTS and loader base.
set -euo pipefail

NH="${1:?usage: build_mp_images.sh <NHARTS> <dest_rcf_dir> [group ...]}"
DEST="${2:?usage: build_mp_images.sh <NHARTS> <dest_rcf_dir> [group ...]}"
shift 2
if [ "$#" -eq 0 ]; then
    set -- rv32ui rv32ua rv32um rv32uc rv32uzba rv32uzbb rv32uzbc rv32uzbs
fi

BASE_OPTS="-static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles"

# EXTRA_GCC_DEFINES carries the config's -DCORE_ENABLE_* list, derived by
# platform/common/python/verify_stage.py from one resolved config and checked
# against the staged MemoryMap.vhd before this script runs. Without it an
# ON-polarity image is unreachable: a zicboz:true config runs shcboz.S's #else
# arm and reports PASS. This script never reads core_features.h or any make-chip
# product; the defines arrive explicitly from a caller that has already proven
# them equal to the staged RTL's constants. Group order is the caller's too:
# base images first, then the ON suite rebuilt on top.
EXTRA_GCC_DEFINES="${EXTRA_GCC_DEFINES:-}"
GCC_OPTS="$BASE_OPTS -DNHARTS=$NH"
[ -n "$EXTRA_GCC_DEFINES" ] && GCC_OPTS="$GCC_OPTS $EXTRA_GCC_DEFINES"

# The Makefile fixes a per-group march and emits $(RISCV_GCC_OPTS) after it, so a
# -march carried here wins. One supported configuration needs that lever:
# isa.compressed false, where gas would otherwise auto-compress and fill the
# images with encodings the core cannot decode. verify_stage.py's image_march()
# derives it. It is part of the image set identity below, so a norvc set and a
# compressed set share neither a directory nor a stamp.
EXTRA_GCC_MARCH="${EXTRA_GCC_MARCH:-}"
[ -n "$EXTRA_GCC_MARCH" ] && GCC_OPTS="$GCC_OPTS -march=$EXTRA_GCC_MARCH"

# The identity recorded in the image set's `.imgset` stamp. Defaulted here so a
# hand invocation still leaves a truthful record instead of none.
IMGSET_IDENTITY="${IMGSET_IDENTITY:-NHARTS=$NH DEFINES=${EXTRA_GCC_DEFINES:-(none)}${EXTRA_GCC_MARCH:+ MARCH=$EXTRA_GCC_MARCH}}"

cd "$(dirname "$0")"

# rcf/ transit protection. The build transits through rcf/ because the Makefile's
# *-flash recipes write there unconditionally, so an out-of-tree build would
# leave rcf/ holding foreign-N images under a stamp claiming otherwise. rcf/ is
# therefore snapshotted before the build and restored after staging, images and
# stamp together; the restore also runs on an aborted build through the EXIT trap
# and a read-back assertion proves it. Restoring the stamp alone would leave the
# canonical rcf/.nharts over foreign-N images, so the runners' guards would pass
# on poisoned images: strictly worse than a loud refusal. If rcf/ did not exist
# before the run the restored pre-state is an empty unstamped rcf/, which fails
# loudly downstream. The canonical set is NHARTS=5, the shipped five-hart
# orchestrator chip. Both directories are materialised before being resolved: on
# a fresh checkout neither exists, and two unresolvable paths compare equal, which
# would misclassify the CI job's out-of-tree build as in-tree. Deciding up front
# also keeps the snapshot and the stage-out from disagreeing about which case
# this is.
mkdir -p rcf "$DEST"
RCF_PHYS="$(cd rcf && pwd -P)"
DEST_PHYS="$(cd "$DEST" && pwd -P)"
OUT_OF_TREE=0
[ "$DEST_PHYS" != "$RCF_PHYS" ] && OUT_OF_TREE=1
RCF_SNAP=""
RCF_PRE_STAMP="<absent>"
if [ "$OUT_OF_TREE" = 1 ]; then
    RCF_SNAP="$(mktemp -d "${TMPDIR:-/tmp}/build_mp_rcf_snap.XXXXXX")"
    if [ -d rcf ]; then
        cp -p rcf/*.rcf "$RCF_SNAP"/ 2>/dev/null || true
        if [ -f rcf/.nharts ]; then
            cp -p rcf/.nharts "$RCF_SNAP"/.nharts
            RCF_PRE_STAMP="$(cat rcf/.nharts)"
        fi
        # .imgset joins the snapshot for the same reason .nharts does: stamp and
        # images move together or not at all. Nothing in an out-of-tree build
        # writes rcf/.imgset today, but a polarity record left behind by restored
        # images would be exactly the fail-safe inversion this prevents.
        [ -f rcf/.imgset ] && cp -p rcf/.imgset "$RCF_SNAP"/.imgset
    fi
    echo "  rcf/ snapshot: $(ls "$RCF_SNAP"/*.rcf 2>/dev/null | wc -l) rcf, .nharts=$RCF_PRE_STAMP -> $RCF_SNAP"
fi

restore_rcf() {                     # idempotent; called explicitly AND by trap
    [ -n "$RCF_SNAP" ] || return 0
    if [ -d "$RCF_SNAP" ]; then
        mkdir -p rcf
        rm -f rcf/*.rcf rcf/.nharts rcf/.imgset
        cp -p "$RCF_SNAP"/*.rcf rcf/ 2>/dev/null || true
        if [ -f "$RCF_SNAP/.nharts" ]; then cp -p "$RCF_SNAP/.nharts" rcf/.nharts; fi
        if [ -f "$RCF_SNAP/.imgset" ]; then cp -p "$RCF_SNAP/.imgset" rcf/.imgset; fi
        rm -rf "$RCF_SNAP"
    fi
    RCF_SNAP=""
    return 0
}
trap restore_rcf EXIT

echo "=== build_mp_images: NHARTS=$NH  dest=$DEST  groups=[$*] ==="
echo "    RISCV_GCC_OPTS=$GCC_OPTS"
echo "    imgset identity=$IMGSET_IDENTITY"
rm -rf build/                       # force full rebuild (header-dep gotcha)

for g in "$@"; do
    echo "--- ${g}-flash (NHARTS=$NH) ---"
    make "${g}-flash" RISCV_GCC_OPTS="$GCC_OPTS"
done
# Stamp the ELF cache itself, not only the image set. build/ is shared with
# xrun_cosim.sh's ensure_elf, which rebuilds only what is missing and reuses
# whatever polarity it finds. build/ was just removed and refilled wholesale at
# $GCC_OPTS, so the stamp is exactly true here. The lockstep gate compares it
# against the polarity it needs and wipes the cache on disagreement; an unstamped
# cache counts as a disagreement.
echo "NHARTS=$NH DEFINES=${EXTRA_GCC_DEFINES:-(none)}" > build/.imgset

# Stage out only when DEST is a different directory: make already populates rcf/
# during the build, so the rm/cp below would delete the fresh set and then fail to
# copy it onto itself. The comparison must be physical (pwd -P), because
# xcelium/riscv_test/rcf is a symlink to this rcf/ and a logical compare misses
# that. OUT_OF_TREE carries that comparison, taken up front.
if [ "$OUT_OF_TREE" = 1 ]; then
    mkdir -p "$DEST"
    rm -f "$DEST"/*.rcf
    cp rcf/*.rcf "$DEST"/
    # The transit through rcf/ is undone below, images and .nharts together.
    echo "NOTE: the build transited through rcf/ (NHARTS=$NH images landed there);"
    echo "      restoring rcf/ to its pre-build state: images AND .nharts=$RCF_PRE_STAMP."
fi
# .nharts records what each directory currently holds; the runners guard on it.
echo "$NH" > "$DEST/.nharts"
# .imgset records the full polarity, which .nharts alone does not carry. An image
# set is rebuildable in two to four minutes, but only if the exact
# RISCV_GCC_OPTS polarity is known; verify.sh refuses to reuse a set whose
# identity disagrees with what it needs.
echo "$IMGSET_IDENTITY" > "$DEST/.imgset"
restore_rcf                         # out-of-tree only; no-op for an in-tree build

# Read both stamps back off disk and die loudly on a mismatch. An expected state
# needs proof the instrument was live, not trust that the writes above landed.
readstamp() { cat "$1/.nharts" 2>/dev/null || echo "<absent>"; }
if [ "$OUT_OF_TREE" = 1 ]; then WANT_RCF="$RCF_PRE_STAMP"; else WANT_RCF="$NH"; fi
GOT_DEST="$(readstamp "$DEST")"
GOT_RCF="$(readstamp rcf)"
RB_FAIL=0
if [ "$GOT_DEST" != "$NH" ]; then
    echo "FATAL: $DEST/.nharts reads '$GOT_DEST', expected '$NH'" >&2; RB_FAIL=1
fi
if [ "$GOT_RCF" != "$WANT_RCF" ]; then
    echo "FATAL: rcf/.nharts reads '$GOT_RCF', expected '$WANT_RCF'" >&2; RB_FAIL=1
fi
if [ "$RB_FAIL" != 0 ]; then
    echo "FATAL: build_mp_images.sh read-back assertion FAILED — image dirs may be" >&2
    echo "       poisoned. Rebuild the canonical set before ANY Castalia sim:" >&2
    echo "       ./build_mp_images.sh 5 ../../xcelium/riscv_test/rcf" >&2
    exit 2
fi
GOT_IMGSET="$(cat "$DEST/.imgset" 2>/dev/null || echo "<absent>")"
if [ "$GOT_IMGSET" != "$IMGSET_IDENTITY" ]; then
    echo "FATAL: $DEST/.imgset reads '$GOT_IMGSET', expected '$IMGSET_IDENTITY'" >&2
    echo "       An image set whose polarity record is wrong is worse than one" >&2
    echo "       with no record: verify.sh would REUSE it as the wrong polarity." >&2
    exit 2
fi
# The stamps prove the set's polarity, not that each image is executable. A bare
# `make <group>` publishes raw padded images through collect_rcf_ without ever
# reaching flash_prepend.sh, and those die silently on the testbench watchdog.
# check-rcf-flashed reads line 1 of every image and demands the 0x10ADBEEF
# command word, the content predicate flash_prepend.sh's idempotency guard uses.
if ! make check-rcf-flashed RCF_DIR="$DEST"; then
    echo "FATAL: $DEST holds images with no SPI-flash header -- they load nothing" >&2
    echo "       and die on the testbench watchdog. The build above did not finish." >&2
    exit 2
fi
echo "  read-back OK: $DEST/.nharts=$GOT_DEST  rcf/.nharts=$GOT_RCF"
echo "                $DEST/.imgset=$GOT_IMGSET"
echo "=== done: $(ls "$DEST"/*.rcf | wc -l) rcf files in $DEST (NHARTS=$NH) ==="
