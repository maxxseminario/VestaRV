#!/usr/bin/env bash
# VestaRV: regenerate everything derived from the register descriptions, in
# dependency order: .rdl -> VHDL packages -> C headers -> chip generator
# (MCU.vhd, MemoryMap.vhd, firmware headers, TRM inputs). Outputs land in the
# source tree and are tracked; the identity gates hold them to these emitters.
# Usage: tools/bin/bazel run //:regs
set -euo pipefail
: "${BUILD_WORKSPACE_DIRECTORY:?run through bazel run}"
pkgs="$1"; headers="$2"; generate="$3"
echo "regs: VHDL packages";  "$pkgs"
echo "regs: C headers";      "$headers"
echo "regs: chip generator"; "$generate"
echo "regs: done; review with git status"
