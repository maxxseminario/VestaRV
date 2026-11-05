#!/bin/bash
# One RISCOF run: an ISA profile on a hart, against Spike and Sail.
#   run_riscof.sh <tile|orch> <hart> <workdir> [only-glob ...]
# Environment:
#   RISCOF_ENV  prefix of a python>=3.7 environment holding riscof (bin/riscof)
#   ARCH_TEST   a riscv-arch-test 3.x checkout (riscv-test-suite/ inside)
#   SAIL        sail_riscv_sim binary; empty runs Spike alone
#   JOBS        parallel sims (default 4)      LOAD  preload|flash (default preload)
#   PRIMARY     spike|sail, whose signature RISCOF compares (default spike)
#   CORRUPT     word:value, overwrite one word of every DUT signature (negative control)
#   SUITE       suite directory (default $ARCH_TEST/riscv-test-suite/rv32i_m)
set -euo pipefail
PROFILE="$1"; HART="$2"; WORK="$3"; shift 3
HERE="$(cd "$(dirname "$0")" && pwd)"
SUITE="${SUITE:-$ARCH_TEST/riscv-test-suite/rv32i_m}"
ENVDIR="$ARCH_TEST/riscv-test-suite/env"
mkdir -p "$(dirname "$WORK")"
CFG="$WORK.ini"
SAILCFG=""
if [ -n "${SAIL:-}" ]; then
    SAILCFG="$WORK.sail.json"
    /usr/bin/python3.6 "$HERE/ref/gen_sail_config.py" "$SAIL" "$PROFILE" "$SAILCFG"
fi
cat > "$CFG" <<EOF
[RISCOF]
ReferencePlugin=refmodel
ReferencePluginPath=$HERE/ref
DUTPlugin=vesta
DUTPluginPath=$HERE/vesta

[vesta]
pluginpath=$HERE/vesta
ispec=$HERE/vesta/vesta_${PROFILE}_isa.yaml
pspec=$HERE/vesta/vesta_platform.yaml
target_run=1
jobs=${JOBS:-4}
hart=$HART
timeout=${SIM_TIMEOUT:-900}
load=${LOAD:-preload}
corrupt_signature=${CORRUPT:-}

[refmodel]
pluginpath=$HERE/ref
primary=${PRIMARY:-spike}
jobs=8
sail=${SAIL:-}
sail_config=$SAILCFG
EOF
R="$RISCOF_ENV/bin"
cd "$HERE"
"$R/riscof" testlist --config "$CFG" --suite "$SUITE" --env "$ENVDIR" --work-dir "$WORK"
"$R/python" "$HERE/sim/filter_testlist.py" "$WORK/test_list.yaml" "$HERE/exclusions.txt" "$@"
cp "$WORK/test_list.yaml.run" "$WORK.testlist.yaml"
cp "$WORK/test_list.yaml.excluded" "$WORK.excluded"
"$R/riscof" run --config "$CFG" --suite "$SUITE" --env "$ENVDIR" --work-dir "$WORK" \
    --testfile "$WORK.testlist.yaml" --no-browser
