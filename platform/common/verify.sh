#!/bin/bash
# VestaRV: the `make verify` orchestrator. Proves the currently generated
# configuration boots and passes the behavioural smoke suite.
#   make verify
#   make verify CONFIG=config/argus.json
#   SUITE=full make verify            # the config-filtered regression instead
#   MAX_PARALLEL=8 FORCE_IMAGES=1 make verify
# The Makefile runs `make generate` first, so out/ and the resolved config JSON
# already match CONFIG. Three steps follow: verify_stage.py stages the out/hdl RTL
# and the generated cell and test lists into xcelium/riscv_test/verify_<chip>/;
# build_mp_images.sh builds the ISA and sh images at the config's NHARTS if the
# stamped set is missing or stale; the staged runner runs the suite, sourcing
# cdspaths.sh itself, under a per-sim timeout at 10x the one-minute rule.
# It never touches hdl/myshkin/ or hdl/common/, never overwrites
# software/bootrom/bin/rom.rcf, and stages only under the untracked
# xcelium/riscv_test/ and verification/isa/rcf_* directories.
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
# The image half of the configuration. The variable must not be named GROUPS:
# that is a bash special array holding the current user's group ids, assignments
# to it are silently ignored, and $GROUPS then expands to the primary GID. The
# build would be invoked with that number as a group name, and a fallthrough to
# build_mp_images.sh's default list would build the wrong images in silence.
IMG_GROUPS=$(val GROUPS); DEFINES=$(val DEFINES)
case "$IMG_GROUPS" in
    ''|*[!a-z0-9\ ]*) echo "❌ IMG_GROUPS is empty or malformed: '$IMG_GROUPS'"; exit 1 ;;
esac
IMGSET=$(val IMGSET); RTL_ON=$(val RTL_ON)
# The -march the images must be built with, or empty to use the ISA Makefile's
# per-group march, which is every configuration but the uncompressed one. It is
# part of the image-set identity, so a norvc set can never be reused as, or
# overwrite, a compressed one.
IMG_MARCH=$(val MARCH)

# The polarity gate. It runs before any image is built or reused.
# Every knob that changes core behaviour has two halves that must agree: the
# hardware half is a `CORE_ENABLE_<K> : boolean := true` constant in the staged
# MemoryMap.vhd, read back out of the file just staged; the software half is a
# -DCORE_ENABLE_<K> on the image build's RISCV_GCC_OPTS, derived from the same
# resolved config. Without the software half, a knob-ON config stages ON-polarity
# RTL and runs OFF-polarity images, and the failure mode is a PASS, because the
# tests' #else arms are written to pass.
# The ISA Makefile still refuses to auto-derive these from the gitignored
# make-chip header, because a stale header would compile the ON arm against OFF
# RTL and hang the suite. The pairing here is explicit, from one resolved config,
# and checked.
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
# The two canonical sets predate the stamp, so seed it. rcf/ is the set the
# behavioral_mp regression runs; rcf_argus is the wide-hart set.
if [ ! -f "$STAMP" ] && [ "$RCF_COUNT" -gt 0 ]; then
    case "$RCF_DEST" in
        */verification/isa/rcf)       echo 4  > "$STAMP" ;;
        */verification/isa/rcf_argus) echo 18 > "$STAMP" ;;
    esac
fi
# The same seeding for the polarity stamp, with one caveat. Seeding .nharts is a
# deduction, since the directory name says which set it is. Seeding .imgset is an
# assertion: that the two canonical sets were built with no -DCORE_ENABLE_*.
# That is measured elsewhere, by the census counting zero cbo.zero encodings in
# rcf/'s shcboz image, not proven by the seed. Every other directory must carry a
# real stamp written by the build.
if [ ! -f "$ISTAMP" ] && [ "$RCF_COUNT" -gt 0 ]; then
    case "$RCF_DEST" in
        */verification/isa/rcf)       echo "NHARTS=4 DEFINES=(none)"  > "$ISTAMP" ;;
        */verification/isa/rcf_argus) echo "NHARTS=18 DEFINES=(none)" > "$ISTAMP" ;;
    esac
fi
HAVE=$(cat "$STAMP" 2>/dev/null || echo none)
IHAVE=$(cat "$ISTAMP" 2>/dev/null || echo none)
# A digest collision is the worst failure this design can have: two polarities
# silently sharing one image set. The link name is two hex digits because the
# riscv_tb TEST_FILE generic allows exactly three characters, so collisions are
# possible by construction and are therefore checked rather than made unlikely.
# The full identity lives in the directory; a disagreement stops the run.
if [ "$RCF_COUNT" -gt 0 ] && [ "$IHAVE" != none ] && [ "$IHAVE" != "$IMGSET" ]; then
    echo "❌ IMAGE-SET IDENTITY COLLISION in $RCF_DEST"
    echo "   the directory holds : $IHAVE"
    echo "   this config wants   : $IMGSET"
    echo "   Two polarities have hashed to the same 2-hex slot. Delete the"
    echo "   directory to rebuild, or widen the tag in verify_stage.rcf_mapping."
    exit 1
fi
# A fresh stamp is not enough: a test added to the catalog since the set was built
# has no rcf yet, so scan the staged runner and smoke lists and rebuild if any
# staged rcf is missing.
# The link-name pattern below must be exactly three characters and no narrower.
# An earlier form required the link to start with `r`, which matches the canonical
# sets and nothing else: every knobs-on set is `k<XX>` by construction, so MISSING
# was structurally pinned at 0 and the check could not fire on any knob-bearing
# configuration.
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
    # The group list follows the selection, because the ON-polarity suites are not
    # in build_mp_images.sh's default list and a knobs-on row would otherwise
    # select tests whose images were never built. EXTRA_GCC_DEFINES carries the
    # polarity. The build writes both stamps itself; the two lines below cover the
    # in-tree case and are asserted by the read-back.
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
# After a non-default config, out/ holds that config's artifacts: regenerate the
# defaults before relying on out/ again. The tracked config/ pair is untouched by a
# CONFIG= run, so the record of what was built is out/config/.
if grep -q '"configFile": *null' "$PC_DIR/out/config/ChipConfig.resolved.json" 2>/dev/null; then :; else
    echo "ℹ️  out/ holds a non-default config -- run plain 'make chip' (or make generate)"
    echo "    afterward and re-verify check_mcu_vhd.py exits 0 (post-Argus rule)."
fi
exit $RC
