#!/usr/bin/env bash
# opensource_sim/run_sim.sh — run the full open-source simulate/verify flow:
#   1. cocotb/GHDL smoke test (sky130/sim)
#   2. GHDL ISA regression (opensource_sim/isa/run_isa.sh)
#
# Usage:
#   ./opensource_sim/run_sim.sh              [suite ...]   both stages
#   ./opensource_sim/run_sim.sh --smoke-only               smoke test only
#   ./opensource_sim/run_sim.sh --isa-only    [suite ...]   ISA suite only
#
# [suite ...] is forwarded verbatim to opensource_sim/isa/run_isa.sh (default
# suites: rv32ui rv32um rv32ua rv32uc rv32uzba rv32uzbb rv32uzbc rv32uzbs).
#
# Exit 0 iff every stage that ran is green.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"
ENV_FILE="$HERE/env.sh"

# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

RISCV_PREFIX="${RISCV_PREFIX:-riscv-none-elf-}"

log()  { echo "[run_sim] $*"; }
fail() { echo "[run_sim] ERROR: $*" >&2; }

RUN_SMOKE=1
RUN_ISA=1
ISA_ARGS=()

for arg in "$@"; do
    case "$arg" in
        --smoke-only) RUN_ISA=0 ;;
        --isa-only)   RUN_SMOKE=0 ;;
        -h|--help)
            echo "Usage: $0 [--smoke-only | --isa-only] [isa-suite ...]"
            exit 0
            ;;
        *) ISA_ARGS+=("$arg") ;;
    esac
done

if [ "$RUN_SMOKE" -eq 0 ] && [ "$RUN_ISA" -eq 0 ]; then
    fail "--smoke-only and --isa-only are mutually exclusive"
    exit 1
fi

# ---------------------------------------------------------------------------
# Preflight: fail fast with an actionable pointer at setup_env.sh instead of
# a confusing error three steps in.
# ---------------------------------------------------------------------------
preflight() {
    local missing=0

    if ! command -v ghdl >/dev/null 2>&1; then
        fail "'ghdl' not on PATH. Run ./opensource_sim/setup_env.sh (then 'source opensource_sim/env.sh')."
        missing=1
    fi
    if ! command -v "${RISCV_PREFIX}gcc" >/dev/null 2>&1; then
        fail "'${RISCV_PREFIX}gcc' not on PATH. Run ./opensource_sim/setup_env.sh (then 'source opensource_sim/env.sh'), or set RISCV_PREFIX."
        missing=1
    fi
    if ! command -v make >/dev/null 2>&1; then
        fail "'make' not on PATH. Run ./opensource_sim/setup_env.sh."
        missing=1
    fi

    if [ "$RUN_SMOKE" -eq 1 ]; then
        local venv_py="$HERE/.venv/bin/python3"
        if [ ! -x "$venv_py" ] || ! "$venv_py" -c 'import cocotb' >/dev/null 2>&1; then
            fail "cocotb venv missing/incomplete at $HERE/.venv. Run ./opensource_sim/setup_env.sh."
            missing=1
        fi
    fi

    if [ "$missing" -ne 0 ]; then
        fail "preflight failed — see ./opensource_sim/setup_env.sh --check for a full probe."
        exit 1
    fi
}

preflight

SMOKE_RESULT="SKIPPED"
ISA_RESULT="SKIPPED"
ISA_LINE=""
EXIT_CODE=0

# ---------------------------------------------------------------------------
# 1. cocotb/GHDL smoke test (sky130/sim)
# ---------------------------------------------------------------------------
if [ "$RUN_SMOKE" -eq 1 ]; then
    log "=== smoke test: make -C sky130/sim ==="
    SMOKE_DIR="$REPO_ROOT/sky130/sim"
    RESULTS_XML="$SMOKE_DIR/results.xml"
    rm -f "$RESULTS_XML"

    # Use the venv's cocotb (its bin/ is first on PATH once env.sh is sourced).
    if make -C "$SMOKE_DIR"; then
        make_rc=0
    else
        make_rc=$?
    fi

    if [ -f "$RESULTS_XML" ] && ! grep -qE 'failures="[1-9][0-9]*"|errors="[1-9][0-9]*"' "$RESULTS_XML"; then
        SMOKE_RESULT="PASS"
    else
        SMOKE_RESULT="FAIL"
        EXIT_CODE=1
    fi
    if [ "$make_rc" -ne 0 ]; then
        SMOKE_RESULT="FAIL"
        EXIT_CODE=1
    fi
    log "smoke test: $SMOKE_RESULT"
fi

# ---------------------------------------------------------------------------
# 2. ISA regression (opensource_sim/isa/run_isa.sh)
# ---------------------------------------------------------------------------
if [ "$RUN_ISA" -eq 1 ]; then
    log "=== ISA suite: opensource_sim/isa/run_isa.sh ${ISA_ARGS[*]} ==="
    ISA_LOG="$(mktemp)"
    if "$HERE/isa/run_isa.sh" "${ISA_ARGS[@]}" 2>&1 | tee "$ISA_LOG"; then
        isa_rc=0
    else
        isa_rc=1
    fi

    ISA_LINE="$(grep -E '^ISA RESULTS:' "$ISA_LOG" | tail -1 || true)"
    rm -f "$ISA_LOG"

    if [ "$isa_rc" -eq 0 ] && [ -n "$ISA_LINE" ]; then
        ISA_RESULT="PASS"
    else
        ISA_RESULT="FAIL"
        EXIT_CODE=1
    fi
    log "ISA suite: $ISA_RESULT"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "=== opensource_sim run summary ==="
echo "  smoke test (sky130/sim) : $SMOKE_RESULT"
if [ -n "$ISA_LINE" ]; then
    echo "  ISA suite                : $ISA_RESULT  ($ISA_LINE)"
else
    echo "  ISA suite                : $ISA_RESULT"
fi

exit "$EXIT_CODE"
