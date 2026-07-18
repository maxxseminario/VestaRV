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

echo ""
echo "=== [verify 2/3] Test images (NHARTS=$NHARTS) ==="
STAMP="$RCF_DEST/.nharts"
RCF_COUNT=$(ls "$RCF_DEST"/*.rcf 2>/dev/null | wc -l)
# The two pre-existing canonical sets carry no stamp -- seed it (rcf/ is the
# Castalia N=4 set the behavioral_mp regression runs; rcf_argus is A3's N=18).
if [ ! -f "$STAMP" ] && [ "$RCF_COUNT" -gt 0 ]; then
    case "$RCF_DEST" in
        */verification/isa/rcf)       echo 4  > "$STAMP" ;;
        */verification/isa/rcf_argus) echo 18 > "$STAMP" ;;
    esac
fi
HAVE=$(cat "$STAMP" 2>/dev/null || echo none)
# A fresh stamp is not enough: a test ADDED to the catalog since the set was
# built has no rcf yet (afselv2 burned this on the Argus set, 2026-07-12) --
# scan the staged runner/smoke lists and rebuild if any staged rcf is missing.
MISSING=0
for f in $(grep -ho '\.\./r[a-z0-9][a-z0-9]/[^" ]*\.rcf' \
        "$STAGE_DIR"/smoke.txt "$STAGE_DIR"/xrun_parallel.sh 2>/dev/null \
        | sed 's|.*/||' | sort -u); do
    [ -f "$RCF_DEST/$f" ] || MISSING=$((MISSING+1))
done
[ "$MISSING" -gt 0 ] && echo "  $MISSING staged test image(s) missing from $RCF_DEST"
if [ "$FORCE_IMAGES" = 1 ] || [ "$HAVE" != "$NHARTS" ] || [ "$RCF_COUNT" -eq 0 ] || [ "$MISSING" -gt 0 ]; then
    echo "  building images: NHARTS=$NHARTS -> $RCF_DEST (have: NHARTS=$HAVE, $RCF_COUNT rcf)"
    command -v riscv-none-elf-gcc >/dev/null || { echo "❌ riscv-none-elf- toolchain not on PATH"; exit 1; }
    ../../verification/isa/build_mp_images.sh "$NHARTS" "$RCF_DEST" || { echo "❌ image build failed"; exit 1; }
    echo "$NHARTS" > "$STAMP"
else
    echo "  reusing $RCF_COUNT image(s) in $RCF_DEST (stamp NHARTS=$HAVE)"
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
