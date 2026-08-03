#!/bin/bash
# verify.sh -- `make verify` orchestrator: prove the CURRENT generated
# configuration boots and passes the behavioral smoke suite.
#
#   make verify                       # Castalia defaults
#   make verify CONFIG=config/argus.json
#   SUITE=full make verify            # full config-filtered regression instead
#   MAX_PARALLEL=8 FORCE_IMAGES=1 make verify
#
# Steps (the Makefile runs `make generate` first, so out/ + the resolved
# config JSON already match the requested CONFIG):
#   1. python/verify_stage.py  -- stage out/hdl RTL + generated cell/test
#      lists into xcelium/riscv_test/verify_<chip>/ (A3 pattern, productized)
#   2. build the ISA/sh test images at the config's NHARTS if the stamped
#      image set is missing/stale (verification/isa/build_mp_images.sh)
#   3. run the smoke suite through the staged runner (sources cdspaths.sh
#      itself; per-sim timeout enforces the 1-minute rule at 10x margin)
#
# Never touches hdl/myshkin/ or hdl/common/, never overwrites
# software/bootrom/bin/rom.rcf, and stages only under the untracked
# xcelium/riscv_test/ + verification/isa/rcf_* image dirs.
set -uo pipefail
cd "$(dirname "$0")"
PC_DIR=$(pwd)

MAX_PARALLEL=${MAX_PARALLEL:-6}
SUITE=${SUITE:-smoke}
FORCE_IMAGES=${FORCE_IMAGES:-0}

echo "=== [verify 1/3] Staging generated RTL into a simulation flow ==="
INFO=$(python3 python/verify_stage.py) || { echo "$INFO"; echo "❌ staging failed"; exit 1; }
echo "$INFO" | sed 's/^/  /'
val() { sed -n "s/^$1=//p" <<<"$INFO"; }
CHIP=$(val CHIP); STAGE_DIR=$(val STAGE_DIR); NHARTS=$(val NHARTS)
RCF_DEST=$(val RCF_DEST); NTESTS_SMOKE=$(val NTESTS_SMOKE); NTESTS_FULL=$(val NTESTS_FULL)
# K2/G3: the image half of the configuration.
# NOT `GROUPS` -- that is a BASH SPECIAL ARRAY (the current user's group ids).
# Assignments to it are SILENTLY IGNORED and `$GROUPS` then expands to
# ${GROUPS[0]}, i.e. the primary GID. This cost a run: the build was invoked as
# `build_mp_images.sh 4 <dest> 100` and died on `No rule to make target
# '100-flash'`. It failed loudly only by luck -- had the empty/garbage list
# fallen through to build_mp_images.sh's default group list, the row would have
# built the WRONG set of images and said nothing.
IMG_GROUPS=$(val GROUPS); DEFINES=$(val DEFINES)
case "$IMG_GROUPS" in
    ''|*[!a-z0-9\ ]*) echo "❌ IMG_GROUPS is empty or malformed: '$IMG_GROUPS'"; exit 1 ;;
esac
IMGSET=$(val IMGSET); RTL_ON=$(val RTL_ON)
# K4 (row C3): the `-march` the images must be built with, or empty for "use
# the ISA Makefile's per-group march" -- which is every configuration but C3.
# It is part of the image-set IDENTITY (verify_stage.imgset_identity), so a
# norvc set can never be reused as, or overwrite, a compressed one.
IMG_MARCH=$(val MARCH)

# ---------------------------------------------------------------------------
# K2/G3 -- THE POLARITY GATE. Run BEFORE any image is built or reused.
#
# Every knob that changes core behaviour has TWO halves that must agree:
#   HARDWARE -- a `CORE_ENABLE_<K> : boolean := true` constant in the staged
#               MemoryMap.vhd (RTL_ON, read back out of the file just staged);
#   SOFTWARE -- a `-DCORE_ENABLE_<K>` on the image build's RISCV_GCC_OPTS
#               (DEFINES, derived from the same resolved config).
# Until K2 the software half did not exist at all: build_mp_images.sh's only
# define was -DNHARTS, so `make verify CONFIG=<knob ON>` staged ON-polarity RTL
# and ran OFF-polarity images -- and the failure mode was a PASS, because the
# tests' #else arms are written to pass. That is has-a-bench != has-coverage,
# wired in at programme scale, and it is the defect K2 exists to close.
#
# The ISA Makefile's REFUSAL to auto-derive these from the gitignored make-chip
# header STAYS (verification/isa/Makefile: "a stale header would silently
# compile the ON arm against OFF RTL and hang the suite"). What changes is that
# the explicit pairing is now produced from ONE resolved config AND CHECKED.
# ---------------------------------------------------------------------------
want_from_defines=$(echo "$DEFINES" | tr ' ' '\n' | sed -n 's/^-DCORE_ENABLE_//p' | sort | tr '\n' ' ')
have_from_rtl=$(echo "$RTL_ON" | tr ' ' '\n' | grep -v '^$' | sort | tr '\n' ' ')
if [ "$want_from_defines" != "$have_from_rtl" ]; then
    echo "❌ POLARITY MISMATCH between the staged RTL and the image build flags."
    echo "   staged MemoryMap.vhd says ON : ${have_from_rtl:-(none)}"
    echo "   image -D flags would say ON : ${want_from_defines:-(none)}"
    echo "   These are the two halves of one switch. Running them apart means the"
    echo "   suite tests OFF-arm software against ON-polarity hardware (or worse,"
    echo "   the reverse) and REPORTS PASS. Refusing."
    exit 1
fi
echo "  polarity  : ON knobs = ${have_from_rtl:-(none)}  (staged RTL == image -D flags)"

echo ""
echo "=== [verify 2/3] Test images (NHARTS=$NHARTS) ==="
STAMP="$RCF_DEST/.nharts"
ISTAMP="$RCF_DEST/.imgset"
RCF_COUNT=$(ls "$RCF_DEST"/*.rcf 2>/dev/null | wc -l)
# The two pre-existing canonical sets carry no stamp -- seed it (rcf/ is the
# Castalia N=4 set the behavioral_mp regression runs; rcf_argus is A3's N=18).
if [ ! -f "$STAMP" ] && [ "$RCF_COUNT" -gt 0 ]; then
    case "$RCF_DEST" in
        */verification/isa/rcf)       echo 4  > "$STAMP" ;;
        */verification/isa/rcf_argus) echo 18 > "$STAMP" ;;
    esac
fi
# K2/G3: the same seeding for the POLARITY stamp, and it deserves a warning
# label. `.nharts` seeding is a deduction (the dir name says which set it is);
# `.imgset` seeding is an ASSERTION -- that the pre-existing canonical sets were
# built with no -DCORE_ENABLE_*. The assertion is well-founded (the standing
# suite passes, and every both-polarity test's OFF arm is what passes on those
# images) but it is not proven by the seed itself. It is proven by the K2
# acceptance-D census: the OFF control counts ZERO cbo.zero encodings in
# rcf/'s shcboz image, which is exactly this claim measured. Anything OTHER
# than these two directories must carry a real stamp written by the build.
if [ ! -f "$ISTAMP" ] && [ "$RCF_COUNT" -gt 0 ]; then
    case "$RCF_DEST" in
        */verification/isa/rcf)       echo "NHARTS=4 DEFINES=(none)"  > "$ISTAMP" ;;
        */verification/isa/rcf_argus) echo "NHARTS=18 DEFINES=(none)" > "$ISTAMP" ;;
    esac
fi
HAVE=$(cat "$STAMP" 2>/dev/null || echo none)
IHAVE=$(cat "$ISTAMP" 2>/dev/null || echo none)
# A digest COLLISION would be the worst failure this design can have: two
# different polarities silently sharing one image set. The link name is 2 hex
# digits because the riscv_tb TEST_FILE generic gives us exactly 3 characters,
# so collisions are possible by construction -- and therefore CHECKED, not made
# unlikely. The full identity lives in the directory; if it disagrees with the
# one this config wants, stop.
if [ "$RCF_COUNT" -gt 0 ] && [ "$IHAVE" != none ] && [ "$IHAVE" != "$IMGSET" ]; then
    echo "❌ IMAGE-SET IDENTITY COLLISION in $RCF_DEST"
    echo "   the directory holds : $IHAVE"
    echo "   this config wants   : $IMGSET"
    echo "   Two polarities have hashed to the same 2-hex slot. Delete the"
    echo "   directory to rebuild, or widen the tag in verify_stage.rcf_mapping."
    exit 1
fi
# A fresh stamp is not enough: a test ADDED to the catalog since the set was
# built has no rcf yet (afselv2 burned this on the Argus set, 2026-07-12) --
# scan the staged runner/smoke lists and rebuild if any staged rcf is missing.
#
# K4 (ledger K4-L8): the pattern used to be `\.\./r[a-z0-9][a-z0-9]/`, i.e. it
# required the 3-character link to START WITH `r`. That matches the canonical
# sets (rcf / rca / r18) and NOTHING ELSE -- every knobs-on set is `k<XX>` by
# construction (verify_stage.rcf_mapping prefixes the digest tag with `k`), so
# on every knob-bearing configuration MISSING was structurally pinned at 0 and
# this check could not fire. It stayed latent from K2/G3 until the first
# CATALOG row landed on a knobs-on config; then A3 and the D2 canary aborted at
# 40 NS with "Test file not found" while the detector built for exactly that
# said nothing. The link contract is "exactly 3 characters", so the pattern is
# now exactly that and no narrower.
MISSING=0
for f in $(grep -hoE '\.\./[a-z0-9]{3}/[^" ]*\.rcf' \
        "$STAGE_DIR"/smoke.txt "$STAGE_DIR"/xrun_parallel.sh 2>/dev/null \
        | sed 's|.*/||' | sort -u); do
    [ -f "$RCF_DEST/$f" ] || MISSING=$((MISSING+1))
done
[ "$MISSING" -gt 0 ] && echo "  $MISSING staged test image(s) missing from $RCF_DEST"
if [ "$FORCE_IMAGES" = 1 ] || [ "$HAVE" != "$NHARTS" ] || [ "$RCF_COUNT" -eq 0 ] || [ "$MISSING" -gt 0 ]; then
    echo "  building images: NHARTS=$NHARTS -> $RCF_DEST (have: NHARTS=$HAVE, $RCF_COUNT rcf)"
    echo "    groups : $IMG_GROUPS"
    echo "    defines: ${DEFINES:-(none -- default OFF polarity)}"
    echo "    march  : ${IMG_MARCH:-(per-group, from verification/isa/Makefile)}"
    command -v riscv-none-elf-gcc >/dev/null || { echo "❌ riscv-none-elf- toolchain not on PATH"; exit 1; }
    # K2/G3: GROUPS follows the selection (the ON-polarity suites are NOT in
    # build_mp_images.sh's default group list, so a knobs-on row would otherwise
    # select tests whose images were never built) and EXTRA_GCC_DEFINES carries
    # the polarity. The build writes BOTH stamps itself; the two lines below are
    # belt-and-braces for the in-tree case and are asserted by the read-back.
    EXTRA_GCC_DEFINES="$DEFINES" EXTRA_GCC_MARCH="$IMG_MARCH" IMGSET_IDENTITY="$IMGSET" \
        ../../verification/isa/build_mp_images.sh "$NHARTS" "$RCF_DEST" $IMG_GROUPS \
        || { echo "❌ image build failed"; exit 1; }
    echo "$NHARTS" > "$STAMP"
    echo "$IMGSET" > "$ISTAMP"
else
    echo "  reusing $RCF_COUNT image(s) in $RCF_DEST (stamp NHARTS=$HAVE)"
    echo "    imgset : $IHAVE"
fi

echo ""
echo "=== [verify 3/3] Behavioral $SUITE suite ($CHIP) ==="
cd "$STAGE_DIR" || exit 1
if [ "$SUITE" = full ]; then
    MAX_PARALLEL="$MAX_PARALLEL" ./xrun_parallel.sh
else
    TESTS_FILE=smoke.txt MAX_PARALLEL="$MAX_PARALLEL" ./xrun_parallel.sh
fi
RC=$?

echo ""
if [ $RC -eq 0 ]; then
    echo "✅ make verify: $CHIP (NHARTS=$NHARTS) passed the $SUITE suite"
else
    echo "❌ make verify: $CHIP (NHARTS=$NHARTS) FAILED -- logs in $STAGE_DIR/log/"
fi
# Post-Argus rule: if this was a non-default config, out/ now holds ITS
# artifacts; regenerate the defaults before relying on out/ again.
if grep -q '"configFile": *null' "$PC_DIR/config/ChipConfig.resolved.json" 2>/dev/null; then :; else
    echo "ℹ️  out/ holds a non-default config -- run plain 'make chip' (or make generate)"
    echo "    afterward and re-verify check_mcu_vhd.py exits 0 (post-Argus rule)."
fi
exit $RC
