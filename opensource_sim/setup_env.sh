#!/usr/bin/env bash
# opensource_sim/setup_env.sh — set up a 100%-open-source simulate/verify
# toolchain for VestaRV: GHDL, a Python venv with cocotb, and the xPack
# RISC-V GCC toolchain. Safe to re-run (idempotent) — re-running only fills
# in whatever is still missing.
#
# Usage:
#   ./opensource_sim/setup_env.sh            install everything that's missing
#   ./opensource_sim/setup_env.sh --check     probe only, install nothing;
#                                              exits nonzero if anything
#                                              required is missing
#
# After a successful run:
#   source opensource_sim/env.sh
set -euo pipefail

# ---------------------------------------------------------------------------
# Pin ONE known-good xPack RISC-V GCC release. Bump deliberately, not
# silently — this version is what CI/docs assume.
#   https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases
# ---------------------------------------------------------------------------
XPACK_VERSION="14.2.0-3"
XPACK_TAG="v${XPACK_VERSION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
TOOLS_DIR="$SCRIPT_DIR/tools"
ENV_FILE="$SCRIPT_DIR/env.sh"
XPACK_DIR_NAME="xpack-riscv-none-elf-gcc-${XPACK_VERSION}"
XPACK_INSTALL_DIR="$TOOLS_DIR/$XPACK_DIR_NAME"

RISCV_PREFIX="${RISCV_PREFIX:-riscv-none-elf-}"

CHECK_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        -h|--help)
            echo "Usage: $0 [--check]"
            echo "  --check   probe tool versions only; install nothing; exit nonzero if"
            echo "            anything required is missing"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

REQUIRED_MISSING=0
declare -A STATUS=()

log()  { echo "[setup_env] $*"; }
warn() { echo "[setup_env] WARNING: $*" >&2; }
record() { STATUS["$1"]="$2"; }

# ---------------------------------------------------------------------------
# sudo / root detection
# ---------------------------------------------------------------------------
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        warn "not root and no 'sudo' on PATH — system package installation will be skipped"
    fi
fi

# ---------------------------------------------------------------------------
# Package manager detection
# ---------------------------------------------------------------------------
PKG_MGR=""
if command -v apt-get >/dev/null 2>&1; then
    PKG_MGR=apt
elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR=dnf
elif command -v zypper >/dev/null 2>&1; then
    PKG_MGR=zypper
elif command -v pacman >/dev/null 2>&1; then
    PKG_MGR=pacman
fi

# ---------------------------------------------------------------------------
# 1. System packages: ghdl, gcc, make, python3-venv equivalent, curl/wget, xz
#    apt (Debian trixie / Ubuntu 24.04+) is the primary, tested path — it
#    ships GHDL >= 5. Other managers are best-effort: ghdl may be absent or
#    too old there, which is handled by the version check below, not here.
# ---------------------------------------------------------------------------
install_system_packages() {
    if [ -z "$PKG_MGR" ]; then
        warn "no supported package manager found (apt/dnf/zypper/pacman) — skipping system package install; install ghdl/gcc/make/python3-venv/curl/wget/xz manually"
        return
    fi
    if [ -z "$SUDO" ] && [ "$(id -u)" -ne 0 ]; then
        warn "skipping system package install (no root, no sudo)"
        return
    fi

    case "$PKG_MGR" in
        apt)
            log "apt: installing base packages"
            $SUDO apt-get update -qq || warn "apt-get update failed"
            $SUDO apt-get install -y gcc make python3-venv curl wget xz-utils \
                || warn "apt-get install of base packages failed"
            log "apt: installing ghdl"
            $SUDO apt-get install -y ghdl \
                || warn "apt-get could not install ghdl (see the version check below)"
            ;;
        dnf)
            log "dnf: installing base packages"
            $SUDO dnf install -y gcc make python3 python3-pip curl wget xz \
                || warn "dnf install of base packages failed"
            log "dnf: installing ghdl"
            $SUDO dnf install -y ghdl \
                || warn "dnf could not install ghdl (see the version check below)"
            ;;
        zypper)
            log "zypper: installing base packages"
            $SUDO zypper --non-interactive install gcc make python3 python3-venv curl wget xz \
                || warn "zypper install of base packages failed"
            log "zypper: installing ghdl"
            $SUDO zypper --non-interactive install ghdl \
                || warn "zypper could not install ghdl (openSUSE main repos often lack it — see the version check below)"
            ;;
        pacman)
            log "pacman: installing base packages"
            $SUDO pacman -Sy --noconfirm gcc make python curl wget xz \
                || warn "pacman install of base packages failed"
            log "pacman: installing ghdl"
            $SUDO pacman -Sy --noconfirm ghdl \
                || warn "pacman could not install ghdl (see the version check below)"
            ;;
    esac
}

print_ghdl_help() {
    cat >&2 <<EOF
[setup_env] GHDL >= 5.x is required and was not found (or is too old). Two options:

  1. Distro upgrade path — use a distro release that ships GHDL >= 5.x
     (Debian trixie / Ubuntu 24.04+: 'apt-get install ghdl'). On dnf/zypper/
     pacman hosts, check for a newer release, a backports/updates repo, or a
     community package (e.g. Arch's 'ghdl' / 'ghdl-llvm' in AUR/extra) that
     carries GHDL 5.x.
  2. Container fallback — run this whole flow inside debian:trixie-slim,
     which has GHDL 5.x in its own repos (see "Container fallback" in
     opensource_sim/README.md):

       podman run --rm -it -v "\$PWD":/work -w /work debian:trixie-slim bash -c '
         apt-get update && apt-get install -y ghdl gcc make python3-venv python3-pip curl xz-utils git &&
         ./opensource_sim/setup_env.sh && source opensource_sim/env.sh && ./opensource_sim/run_sim.sh'

  Do NOT build GHDL from source for this flow.
EOF
}

check_ghdl() {
    if ! command -v ghdl >/dev/null 2>&1; then
        record ghdl "MISSING"
        REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
        print_ghdl_help
        return
    fi
    local raw ver major
    raw="$(ghdl --version 2>&1 | head -1)"
    ver="$(grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' <<<"$raw" | head -1 || true)"
    major="${ver%%.*}"
    if [ -z "$major" ]; then
        record ghdl "found, unknown version ($raw)"
    elif [ "$major" -lt 5 ]; then
        record ghdl "found but too old: $ver (need >= 5.x)"
        REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
        print_ghdl_help
    else
        record ghdl "found ($ver)"
    fi
}

probe_simple() {
    local name="$1" cmd="$2"
    if command -v "$cmd" >/dev/null 2>&1; then
        local v
        v="$("$cmd" --version 2>/dev/null | head -1 || true)"
        record "$name" "found (${v:-present})"
    else
        record "$name" "MISSING"
        REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    fi
}

probe_curl_wget() {
    if command -v curl >/dev/null 2>&1; then
        record "curl/wget" "found (curl $(curl --version | head -1 | awk '{print $2}'))"
    elif command -v wget >/dev/null 2>&1; then
        record "curl/wget" "found (wget $(wget --version | head -1 | awk '{print $3}'))"
    else
        record "curl/wget" "MISSING (need at least one)"
        REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    fi
}

# ---------------------------------------------------------------------------
# 2. Python venv + cocotb
# ---------------------------------------------------------------------------
setup_venv() {
    if [ ! -x "$VENV_DIR/bin/python3" ]; then
        log "creating venv at $VENV_DIR"
        if ! python3 -m venv "$VENV_DIR"; then
            warn "python3 -m venv failed — install your distro's venv package (Debian/Ubuntu: python3-venv; openSUSE: python3-venv or pythonXY-venv; Fedora/Arch ship it with python3) and re-run"
            return
        fi
    else
        log "venv already exists at $VENV_DIR"
    fi
    log "installing cocotb>=2.0 into the venv"
    "$VENV_DIR/bin/pip" install --upgrade pip -q || warn "pip self-upgrade failed (continuing)"
    "$VENV_DIR/bin/pip" install -q 'cocotb>=2.0' || warn "pip install cocotb failed"
}

probe_venv() {
    if [ -x "$VENV_DIR/bin/python3" ]; then
        local cv
        cv="$("$VENV_DIR/bin/python3" -c 'import cocotb; print(cocotb.__version__)' 2>/dev/null || true)"
        if [ -n "$cv" ]; then
            record "python venv + cocotb" "ok (cocotb $cv, $VENV_DIR)"
        else
            record "python venv + cocotb" "venv exists but cocotb MISSING"
            REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
        fi
    else
        record "python venv + cocotb" "MISSING (no venv at $VENV_DIR)"
        REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    fi
}

# ---------------------------------------------------------------------------
# 3. RISC-V toolchain: use PATH if present, else fetch the pinned xPack
#    prebuilt release into opensource_sim/tools/ (never system-wide).
# ---------------------------------------------------------------------------
RISCV_BIN_DIR=""

detect_xpack_arch() {
    case "$(uname -m)" in
        x86_64) echo "x64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) echo "" ;;
    esac
}

setup_riscv_toolchain() {
    if command -v "${RISCV_PREFIX}gcc" >/dev/null 2>&1; then
        log "found ${RISCV_PREFIX}gcc already on PATH — using the system toolchain, not downloading xPack"
        return
    fi
    if [ -x "$XPACK_INSTALL_DIR/bin/${RISCV_PREFIX}gcc" ]; then
        log "xPack RISC-V toolchain already present at $XPACK_INSTALL_DIR"
        RISCV_BIN_DIR="$XPACK_INSTALL_DIR/bin"
        return
    fi

    local arch
    arch="$(detect_xpack_arch)"
    if [ -z "$arch" ]; then
        warn "unsupported host architecture '$(uname -m)' for the prebuilt xPack toolchain; install ${RISCV_PREFIX}gcc manually (or set RISCV_PREFIX to a toolchain already on PATH) and re-run"
        return
    fi

    local asset url tmp
    asset="xpack-riscv-none-elf-gcc-${XPACK_VERSION}-linux-${arch}.tar.gz"
    url="https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/${XPACK_TAG}/${asset}"
    mkdir -p "$TOOLS_DIR"
    tmp="$TOOLS_DIR/$asset"

    log "downloading xPack RISC-V GCC ${XPACK_VERSION} ($arch) — ~300 MB, this may take a while"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar -o "$tmp" "$url" || { warn "download failed: $url"; rm -f "$tmp"; return; }
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$tmp" "$url" || { warn "download failed: $url"; rm -f "$tmp"; return; }
    else
        warn "neither curl nor wget available — cannot download the RISC-V toolchain"
        return
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        local expected got
        expected="$(curl -fsL "${url}.sha" 2>/dev/null | awk '{print $1}' || true)"
        if [ -n "$expected" ]; then
            got="$(sha256sum "$tmp" | awk '{print $1}')"
            if [ "$expected" != "$got" ]; then
                rm -f "$tmp"
                echo "[setup_env] ERROR: sha256 mismatch for $asset (expected $expected, got $got)" >&2
                exit 1
            fi
            log "sha256 checksum verified"
        fi
    fi

    log "extracting into $TOOLS_DIR"
    tar -xf "$tmp" -C "$TOOLS_DIR"
    rm -f "$tmp"

    if [ -x "$XPACK_INSTALL_DIR/bin/${RISCV_PREFIX}gcc" ]; then
        RISCV_BIN_DIR="$XPACK_INSTALL_DIR/bin"
    else
        warn "extraction finished but ${RISCV_PREFIX}gcc not found under $XPACK_INSTALL_DIR/bin — check the archive layout"
    fi
}

probe_riscv_gcc() {
    if command -v "${RISCV_PREFIX}gcc" >/dev/null 2>&1; then
        local v
        v="$("${RISCV_PREFIX}gcc" -dumpversion 2>/dev/null || echo '?')"
        record "RISC-V toolchain" "found on PATH (${RISCV_PREFIX}gcc $v)"
    elif [ -x "$XPACK_INSTALL_DIR/bin/${RISCV_PREFIX}gcc" ]; then
        record "RISC-V toolchain" "found (bundled xPack $XPACK_VERSION at $XPACK_INSTALL_DIR)"
    else
        record "RISC-V toolchain" "MISSING"
        REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
    fi
}

# ---------------------------------------------------------------------------
# 4. Generated env.sh
# ---------------------------------------------------------------------------
write_env_file() {
    {
        echo "# Generated by opensource_sim/setup_env.sh — do not edit by hand."
        echo "# Usage: source opensource_sim/env.sh"
        if [ -n "$RISCV_BIN_DIR" ]; then
            echo "export PATH=\"$RISCV_BIN_DIR:\$PATH\""
        fi
        echo "export PATH=\"$VENV_DIR/bin:\$PATH\""
        echo "export RISCV_PREFIX=\"${RISCV_PREFIX}\""
    } > "$ENV_FILE"
    log "wrote $ENV_FILE"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
echo "=== VestaRV opensource_sim environment setup ==="
if [ "$CHECK_ONLY" -eq 1 ]; then
    log "--check: probing only, nothing will be installed or downloaded"
else
    install_system_packages
fi

check_ghdl
probe_simple gcc gcc
probe_simple make make
probe_curl_wget
probe_simple xz xz

if [ "$CHECK_ONLY" -eq 0 ]; then
    setup_venv
fi
probe_venv

if [ "$CHECK_ONLY" -eq 0 ]; then
    setup_riscv_toolchain
fi
probe_riscv_gcc

if [ "$CHECK_ONLY" -eq 0 ]; then
    write_env_file
fi

echo
echo "=== Tool summary ==="
for k in ghdl gcc make "curl/wget" xz "python venv + cocotb" "RISC-V toolchain"; do
    printf '  %-24s %s\n' "$k" "${STATUS[$k]:-MISSING}"
done
echo

if [ "$REQUIRED_MISSING" -gt 0 ]; then
    echo "[setup_env] $REQUIRED_MISSING required tool(s) missing — see messages above."
    exit 1
fi

echo "[setup_env] All required tools present."
if [ "$CHECK_ONLY" -eq 0 ]; then
    echo "[setup_env] Next: source opensource_sim/env.sh"
fi
exit 0
