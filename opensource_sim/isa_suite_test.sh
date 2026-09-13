#!/usr/bin/env bash
# VestaRV: bazel sh_test entry for one GHDL ISA suite.
# Argv: <suite> <rlocationpath of @ghdl//:ghdl>
# The run is hermetic: the ghdl binary and its pre-analysed VHDL-2008 std and
# ieee libraries come from the @ghdl module, the ON-polarity images from
# //verification/isa's os_* targets and the RTL from //hdl:vhdl_sources, leaving
# the host to supply bash and coreutils. This wrapper adapts the runfiles layout
# to run_isa.sh's prebuilt-image mode: the images are staged into TEST_TMPDIR
# because run_isa.sh globs a per-suite directory, and the GHDL work library lands
# there because the runfiles tree is read-only.
set -euo pipefail

suite="$1"
ghdl_rloc="$2"

# sh_test starts in <runfiles>/_main; external repos are its siblings.
ROOT="$PWD"
RUNFILES_ROOT="$(cd .. && pwd)"

export GHDL="$RUNFILES_ROOT/$ghdl_rloc"
# vhdl_libs_v08/{std,ieee}/v08/*.cf sit next to the binary in the repo.
export GHDL_PREFIX="$(dirname "$GHDL")/vhdl_libs_v08"

export ISA_BUILD_DIR="$TEST_TMPDIR/build"
mkdir -p "$ISA_BUILD_DIR/$suite"
cp -L "$ROOT/verification/isa/os/$suite"-p-*.rcf "$ISA_BUILD_DIR/$suite/"

export ISA_WORK_DIR="$TEST_TMPDIR/work"
mkdir -p "$ISA_WORK_DIR"

exec "$ROOT/opensource_sim/isa/run_isa.sh" "$suite"
