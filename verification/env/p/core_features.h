// core_features.h -- build-time ISA-feature switches for tests (X1 program).
//
// Carries the make-chip CORE_ENABLE_<EXT> presence defines WITHOUT dragging in
// the full generated MemoryMap.h (whose <bits.h>/<stdint.h>/<custom_ops.S>
// transitive includes are not on the -nostdlib assembly path). A test that
// must dispatch on the build's ISA config (#ifdef CORE_ENABLE_ZIHINT, ...)
// includes THIS header (env/p is first on the -I search path).
//
// REGENERATE per polarity from the config-under-test's make-chip product:
//     { head -19 core_features.h; echo; \
//       grep '^#define CORE_ENABLE' \
//         platform/common/out/software/include/MemoryMap.h; } > new && mv new ...
//     (then `rm -rf verification/isa/build/` -- shared-header change)
//
// COMMITTED STATE = DEFAULT (off) config: CORE_ENABLE_ZIHINT is UNDEFINED, so
// shpause.S takes its forward-progress (#else) arm and the suite stays green
// under the default build. Stage the ON copy (adds CORE_ENABLE_ZIHINT) to arm
// the latency assertion for the ON sim; revert this file before committing.
#pragma once
