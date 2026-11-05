#!/bin/bash
# VestaRV: coverage collection over the Castalia multi-hart behavioral suite.
#
#   verification/coverage/run_coverage.sh build            compile, elaborate both snapshots
#   verification/coverage/run_coverage.sh run  base|cov    simulate the test list
#   verification/coverage/run_coverage.sh merge            merge cov results into report data
#
# Prerequisite, once per tree (README.md here has the exact commands): `make generate`,
# python/verify_stage.py and build_mp_images.sh, which is what `make verify` does before
# its simulation step. This script reuses that stage and those images and changes nothing
# in them.
#
# Environment:
#   COV_WORK      work directory; default <repo>/xcelium/riscv_test/cov_castalia (gitignored)
#   TESTS_FILE    one image name or path per line; default: the staged runner's catalog
#   IMG_DIR       image directory; default: the stage's rcf set
#   RUN_TAG       results subdirectory; default: the mode, `base` or `cov`
#   MAX_PARALLEL  simultaneous simulations; default 4
#   SIM_TIMEOUT   seconds before a sim is killed and reported HUNG; default 900
#
# One snapshot serves every test. riscv_tb takes its image from a 29-character generic, so
# the generic names a relative path and each test runs in a directory where that path is a
# link to its own image. A snapshot per test, as xrun_parallel.sh does it, would give every
# test a different top entity, a different coverage model and nothing to merge.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PY="env -u LD_LIBRARY_PATH /usr/bin/python3.6"   # cdspaths.sh puts a Cadence libpython on that path
set +u; source ~/chips/castalia/cdspaths.sh; set -u

STAGE="$ROOT/xcelium/riscv_test/verify_castalia"
COV_WORK="${COV_WORK:-$ROOT/xcelium/riscv_test/cov_castalia}"
IMG_DIR="${IMG_DIR:-$ROOT/verification/isa/rcf_kf8}"
MAX_PARALLEL="${MAX_PARALLEL:-4}"
SIM_TIMEOUT="${SIM_TIMEOUT:-900}"
NHARTS=$(cat "$IMG_DIR/.nharts" 2>/dev/null || echo 5)
LINK="x""xxxxxxxxxxxxxxxxx.rcf"     # 18 x + .rcf, see gen_cov_mon.py

# The gitignored ARM memory models are not in a worktree; they are read in place, and the
# ROM model opens this absolute path, so its identity is checked against the tracked record.
SIM_MODELS="$HOME/vestarv/hdl/common/sim"
ROM_ABS="$HOME/vestarv/software/bootrom_mp/bin/rom.rcf"
ROM_REF="$ROOT/tools/cosim/gate/bootrom_mp_rom.rcf"

die() { echo "run_coverage: $*" >&2; exit 1; }

do_build() {
    [ -f "$STAGE/cell_list_behavioral.txt" ] || die "no stage at $STAGE; see README.md"
    cmp -s "$ROM_ABS" "$ROM_REF" || die "boot ROM $ROM_ABS differs from $ROM_REF"
    mkdir -p "$COV_WORK/gen" "$COV_WORK/log" "$COV_WORK/xcelium.d/work"
    cd "$COV_WORK" || exit 1
    cat > cds.lib <<LIB
SOFTINCLUDE ${XCELIUM_HOME}/tools/xcelium/files/cds.lib
DEFINE work $COV_WORK/xcelium.d/work
LIB
    : > hdl.var
    $PY "$HERE/gen_cov_mon.py" "$ROOT" "$NHARTS" gen || exit 1

    # The stage derives from tools/cosim/gate/behavioral_mp/cell_list_behavioral.txt, which
    # lags the tree: sync and PINMUX are instantiated but neither is listed, and verify_stage
    # injects neither. `entity work.x` binds at analysis, so both go ahead of their users.
    # A list that already has them, once the tracked file is repaired, is left alone.
    CELLS=()
    for f in $(< "$STAGE/cell_list_behavioral.txt"); do
        case "$f" in
            */hdl/common/periph_regs.vhd)
                grep -q '/sync.vhd' "$STAGE/cell_list_behavioral.txt" \
                    || CELLS+=("$ROOT/hdl/common/sync.vhd")
                CELLS+=("$f")
                grep -q 'PINMUX.vhd' "$STAGE/cell_list_behavioral.txt" \
                    || CELLS+=("$ROOT/hdl/common/regs/vhdl/pinmux_regs_pkg.vhd" \
                               "$ROOT/hdl/common/periph/PINMUX.vhd")
                ;;
            *) CELLS+=("$f") ;;
        esac
    done

    VLOG=(); VHDL=()
    for f in "${CELLS[@]}"; do
        case "$f" in \#*) continue ;; esac
        case "$f" in
            */hdl/common/sim/ARM_IP_*) f="$SIM_MODELS/$(basename "$f")" ;;
            /*) ;;
            *) f="$STAGE/$f" ;;
        esac
        [ -e "$f" ] || die "missing source: $f"
        case "${f##*.}" in
            v) VLOG+=("$f") ;;
            vhd|vhdl) VHDL+=("$f") ;;
        esac
    done
    if [ ${#VLOG[@]} -gt 0 ]; then
        xmvlog -CDSLIB cds.lib -HDLVAR hdl.var -WORK work "${VLOG[@]}" > log/compile_vlog.log 2>&1 \
            || die "xmvlog failed, see log/compile_vlog.log"
    fi
    xmvhdl -CDSLIB cds.lib -HDLVAR hdl.var -V200X -WORK work -CONTROLRELAX nlstex -RELAX \
        "${VHDL[@]}" gen/cov_hart_mon.vhd gen/cov_tops.vhd > log/compile_vhdl.log 2>&1 \
        || die "xmvhdl failed, see log/compile_vhdl.log"

    # The base snapshot takes the stock flags and nothing else.
    xmelab -CDSLIB cds.lib -HDLVAR hdl.var -ACCESS +r work.base_top:behavioral \
        > log/elab_base.log 2>&1 || die "base elaboration failed, see log/elab_base.log"

    # Write access on the monitor alone: the batch tcl deposits mon_dump and xm_mirror drives
    # the monitor's signals. Without the latter xmsim prints *E,OBJACC for each mirror.
    {
        printf 'DEFAULT +r\nPATH :mon_dump +rw\n'
        for h in $(seq 0 $((NHARTS - 1))); do
            for sig in st clk mclk irq_save amo_lock sh_sel arb_st arb_cur; do
                echo "PATH :mon$h:$sig +rw"
            done
        done
    } > access.txt
    xmelab -CDSLIB cds.lib -HDLVAR hdl.var -AFILE access.txt \
        -MESSAGES -COVERAGE all -COVFILE "$HERE/castalia.ccf" \
        work.cov_top:behavioral > log/elab_cov.log 2>&1 \
        || die "coverage elaboration failed, see log/elab_cov.log"
    echo "build complete: $(grep -c 'FSM extracted' log/elab_cov.log) FSM extraction lines"
    du -sh cov_work xcelium.d
}

test_list() {
    if [ -n "${TESTS_FILE:-}" ]; then
        grep -vE '^\s*(#|$)' "$TESTS_FILE"
    else
        grep -E '^\s*"\.\./' "$STAGE/xrun_parallel.sh" | tr -d ' "'
    fi
}

test_name() { basename "$1" .rcf | sed 's/^x*//'; }

run_one() {
    local mode="$1" rcf="$2" res="$3"
    local name; name=$(test_name "$rcf")
    local dir="$COV_WORK/run/$RUN_TAG/$name"
    local img="$IMG_DIR/$(basename "$rcf")"
    rm -rf "$dir"; mkdir -p "$dir/cur" "$dir/w"
    ln -s "$img" "$dir/cur/$LINK"
    cd "$dir/w" || return

    cat > go.tcl <<'TCL'
set severity_pack_assert_off {warning}
set pack_assert_off {std_logic_arith numeric_std}
set rangecnst_severity_level {warning}
set intovf_severity_level {warning}
run
TCL
    local snap=work.base_top:behavioral
    local args=()
    if [ "$mode" = cov ]; then
        snap=work.cov_top:behavioral
        args=(-COVWORKDIR "$COV_WORK/cov_work" -COVTEST "${RUN_TAG}_$name" -COVOVERWRITE)
        cat >> go.tcl <<'TCL'
deposit :mon_dump {'1'}
run 1 ns
TCL
    fi
    echo exit >> go.tcl

    local t0=$SECONDS
    timeout "$SIM_TIMEOUT" xmsim -CDSLIB "$COV_WORK/cds.lib" -HDLVAR "$COV_WORK/hdl.var" \
        "$snap" "${args[@]}" -input go.tcl -licqueue -LOGFILE sim.log > /dev/null 2>&1
    local rc=$?
    local verdict=FAIL
    grep -aq 'TEST PASSED' sim.log 2>/dev/null && verdict=PASS
    [ $rc -eq 124 ] && verdict=HUNG
    local end; end=$(grep -aoE '\(time [0-9]+ FS\)' sim.log | tail -n 1 | tr -dc '0-9')
    local tiles; tiles=$(grep -a -c 'pass=true' sim.log)
    echo "$name $verdict ${end:-none} tiles_pass=$tiles wall=$((SECONDS - t0))" > "$res/$name.verdict"

    if [ "$mode" = cov ]; then
        grep -aq 'E,EMIRR' sim.log && echo "$name: xm_mirror errors, see its log" | tee "$res/$name.mirrorerr"
        local ucd; ucd=$(ls "$COV_WORK/cov_work/scope/${RUN_TAG}_$name"/*.ucd 2>/dev/null | head -1)
        if [ -n "$ucd" ]; then
            $PY "$HERE/ucis_dump.py" "$ucd" "$res/$name.json.gz" 2>> "$res/$name.dumperr"
            [ -s "$res/$name.dumperr" ] || rm -f "$res/$name.dumperr"
            rm -rf "$COV_WORK/cov_work/scope/${RUN_TAG}_$name"
        fi
        mkdir -p "$res/mon"
        for h in $(seq 0 $((NHARTS - 1))); do
            [ -f "mon_h$h.txt" ] && gzip -c "mon_h$h.txt" > "$res/mon/$name.h$h.txt.gz"
        done
    fi
    cp sim.log "$res/$name.log" 2>/dev/null
    gzip -f "$res/$name.log" 2>/dev/null
    cd "$COV_WORK" && rm -rf "$dir"
    cat "$res/$name.verdict"
}

do_run() {
    local mode="$1"
    RUN_TAG="${RUN_TAG:-$mode}"
    local res="$COV_WORK/results/$RUN_TAG"
    mkdir -p "$res"
    mapfile -t TESTS < <(test_list)
    echo "run $mode: ${#TESTS[@]} tests, MAX_PARALLEL=$MAX_PARALLEL, results in $res"
    for rcf in "${TESTS[@]}"; do
        [ -f "$IMG_DIR/$(basename "$rcf")" ] || die "no image for $rcf in $IMG_DIR"
        [ -f "$res/$(test_name "$rcf").verdict" ] && [ -z "${FORCE:-}" ] && continue
        while [ "$(jobs -r -p | wc -l)" -ge "$MAX_PARALLEL" ]; do sleep 0.5; done
        run_one "$mode" "$rcf" "$res" &
    done
    wait
    echo "run $mode complete: $(cat "$res"/*.verdict | awk '{print $2}' | sort | uniq -c | tr '\n' ' ')"
}

case "${1:-}" in
    build) do_build ;;
    run)   do_run "${2:?base or cov}" ;;
    merge) shift; $PY "$HERE/merge_cov.py" "$COV_WORK" "$@" ;;
    *)     sed -n 2,6p "$0"; exit 2 ;;
esac
