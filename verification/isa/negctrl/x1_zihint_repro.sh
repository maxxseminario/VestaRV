#!/bin/bash
# X1 Zihintpause negative control — proves the directed mp test shpause.S
# actually observes PAUSE's arbiter-yield side-effect (not just any nop).
#
# The seed x1_zihint_seed.patch sets the RTL PAUSE window to 0 cycles, so a
# retiring PAUSE decodes down the ordinary FENCE_WAIT path (no side-effect).
# The antagonist's pause-phase burst then matches its control-phase burst
# (RPAU ~= RCTL), so shpause's ON assertion (RCTL + MARGIN < RPAU) FAILS.
#
# Repro (worktree root), with the ON config staged for sim (see the self-report
# staging steps: make chip CONFIG=<zihint on>, copy out/hdl/{MemoryMap,MCU}.vhd
# over hdl/common/, stage env/p/core_features.h with #define CORE_ENABLE_ZIHINT):
#
#   # 1. baseline (window=16) -> PASS
#   grep PAUSE_WINDOW_CYCLES hdl/common/constants.vhd     # := 16
#   cd verification/isa && ./build_mp_images.sh 4 ../../xcelium/riscv_test/rcf rv32ua
#   cd ../../xcelium/riscv_test/behavioral_mp && ./xrun_batch.sh shpause   # TEST PASSED
#
#   # 2. apply the seed (window -> 0), re-run -> FAIL
#   cd <worktree root>
#   git apply verification/isa/negctrl/x1_zihint_seed.patch
#   grep PAUSE_WINDOW_CYCLES hdl/common/constants.vhd     # := 0
#   cd xcelium/riscv_test/behavioral_mp && ./xrun_batch.sh shpause         # TEST FAILED
#
#   # 3. revert the seed (window -> 16), re-run -> PASS again
#   cd <worktree root>
#   git apply -R verification/isa/negctrl/x1_zihint_seed.patch
#   cd xcelium/riscv_test/behavioral_mp && ./xrun_batch.sh shpause         # TEST PASSED
#
# Observed latency (mtime mclk, hart0 s4=RCTL / s5=RPAU):
#   window=16 : RCTL=6680  RPAU=10017  (gap 3337 > MARGIN 2000) -> PASS
#   window= 0 : RCTL=6680  RPAU= 6689  (gap    9 < MARGIN 2000) -> FAIL
echo "See the comments in this file for the negative-control repro steps."
