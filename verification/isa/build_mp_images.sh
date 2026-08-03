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

# --- rcf/ TRANSIT PROTECTION (K1, from the K0 harness probe's G4 finding) -----
# The build TRANSITS through rcf/: the Makefile's *-flash recipes write there
# unconditionally. So an OUT-OF-TREE build (e.g. the Argus N=18 set staged into
# rcf_argus/) used to leave rcf/ holding N!=4 images AND stamped rcf/.nharts
# with $NH -- poisoning the Castalia 136-suite, both lockstep gates and the
# course runner until a manual rebuild (M19b war story; harness probe G4).
# We now snapshot rcf/ BEFORE the build and restore it after staging, so an
# out-of-tree build is a NO-OP on rcf/ -- images AND stamp. The restore also
# runs on an aborted build (EXIT trap) and is proved by a read-back assertion.
# DESIGN NOTE (fail-safe direction): we deliberately restore the IMAGES too.
# Restoring only the stamp would leave rcf/.nharts=4 sitting over N!=4 images
# -- the runners' guards would then PASS on poisoned images, which is strictly
# worse than the old loud refusal. Stamp and images move together or not at all.
# EDGE: if rcf/ did not exist before the run, the "pre-state" is an empty
# unstamped rcf/, and that is what the restore leaves behind (loud downstream:
# RCF_COUNT=0 rebuilds, runners glob nothing).
# Materialize BOTH dirs before resolving them: on a fresh checkout (rcf/ and
# rcf_ci/ are both gitignored) neither exists yet, and two unresolvable paths
# would compare EQUAL — mis-classifying the CI job's out-of-tree
# `build_mp_images.sh 4 rcf_ci` as in-tree. Deciding up front (rather than
# after the build, as the old inline compare did) also guarantees the snapshot
# and the stage-out cannot disagree about which case this is.
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
    fi
    echo "  rcf/ snapshot: $(ls "$RCF_SNAP"/*.rcf 2>/dev/null | wc -l) rcf, .nharts=$RCF_PRE_STAMP -> $RCF_SNAP"
fi

restore_rcf() {                     # idempotent; called explicitly AND by trap
    [ -n "$RCF_SNAP" ] || return 0
    if [ -d "$RCF_SNAP" ]; then
        mkdir -p rcf
        rm -f rcf/*.rcf rcf/.nharts
        cp -p "$RCF_SNAP"/*.rcf rcf/ 2>/dev/null || true
        if [ -f "$RCF_SNAP/.nharts" ]; then cp -p "$RCF_SNAP/.nharts" rcf/.nharts; fi
        rm -rf "$RCF_SNAP"
    fi
    RCF_SNAP=""
    return 0
}
trap restore_rcf EXIT

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
# (OUT_OF_TREE carries exactly that physical compare, taken up front so the
# snapshot and the stage-out cannot disagree about which case this is.)
if [ "$OUT_OF_TREE" = 1 ]; then
    mkdir -p "$DEST"
    rm -f "$DEST"/*.rcf
    cp rcf/*.rcf "$DEST"/
    # M19c POST-MORTEM: the build TRANSITS through rcf/, so after an
    # out-of-tree stage (e.g. the Argus N=18 set) rcf/ was left holding
    # $NH-flavored images too — this silently poisoned the Castalia rcf/
    # after the M19b Argus verify (sh tests gathered h=1..17 at N=4;
    # 12/26 behavioral smoke failures, chased through three sim levels).
    # K1: no longer — the transit is now UNDONE below (images and .nharts).
    echo "NOTE: the build transited through rcf/ (NHARTS=$NH images landed there);"
    echo "      restoring rcf/ to its pre-build state: images AND .nharts=$RCF_PRE_STAMP."
fi
# .nharts = the TRUTH of what each dir currently holds (runners guard on it).
echo "$NH" > "$DEST/.nharts"
restore_rcf                         # out-of-tree only; no-op for an in-tree build

# --- READ-BACK ASSERTION -----------------------------------------------------
# An expected state needs proof the instrument was live (method rule 5): read
# BOTH stamps back off disk and die loudly on any mismatch, rather than trust
# that the writes above did what they say.
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
    echo "       ./build_mp_images.sh 4 ../../xcelium/riscv_test/rcf" >&2
    exit 2
fi
echo "  read-back OK: $DEST/.nharts=$GOT_DEST  rcf/.nharts=$GOT_RCF"
echo "=== done: $(ls "$DEST"/*.rcf | wc -l) rcf files in $DEST (NHARTS=$NH) ==="
