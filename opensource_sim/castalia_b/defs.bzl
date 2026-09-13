"""Analysis order for CastaliaB, config/castalia_b.json.

The RTL these lists name is not the tracked hdl/common/MCU.vhd. MCU.vhd and
MemoryMap.vhd are GENERATED per configuration and the tracked pair is the
default-knob Castalia; the CastaliaB pair comes out of
//platform/common:chip_artifacts_castalia_b. So the spine is spliced rather
than appended to, exactly as //opensource_sim/mcu_hart does it: MemoryMap.vhd
is the SECOND file analyzed (everything below it reads the package) and MCU.vhd
is the LAST.

    HEAD  +  generated MemoryMap.vhd  +  MID  +  generated MCU.vhd

Nothing is dropped from the shared spine here. mcu_hart drops
hdl/common/periph/NPU.vhd because that configuration sets peripherals.npu
false; CastaliaB leaves the NPU at its default true, so the file analyzes and
is instantiated.

NOTHING IS ADDED SINCE 2026-09-12. Until then this package carried a
CASTALIA_B_EXTRA list of five files (dma_regs_pkg, DMA, trng_regs_pkg,
TrngRoEnsemble_sim, TRNG), because VESTA_MCU_RTL is the analysis order of the
TRACKED MCU.vhd and that generation instantiated neither DMA0 nor TRNG0. The
tracked pair is now config/castalia.json, which sets peripherals.dma and
peripherals.trng true, so those five files are in VESTA_MCU_RTL and the extra
list would be a double analysis. The splice is therefore HEAD + generated
MemoryMap.vhd + MID + generated MCU.vhd, with nothing between MID and the top.

WHAT THIS PACKAGE IS FOR. CastaliaB differs from the tape-out configuration in
exactly one axis, the hart-0 ISA and privilege set, and that axis is the one
that decides which of the core's generate arms exist: the Zfinx FPU, the Zkn
round units, the PMP match unit and its CSR bank, the U-mode privilege
register. An all-on generation walks emitter paths and RTL arms the default
generation never does, and until this target existed nothing bound them into a
design.
"""

load("//opensource_sim/mcu:defs.bzl", "VESTA_MCU_RTL")

_MEMORY_MAP = "hdl/common/MemoryMap.vhd"
_MCU = "hdl/common/MCU.vhd"

def _split():
    if VESTA_MCU_RTL[1] != _MEMORY_MAP:
        fail("opensource_sim/castalia_b/defs.bzl: VESTA_MCU_RTL[1] is %s, not %s. " %
             (VESTA_MCU_RTL[1], _MEMORY_MAP) +
             "The generated memory-map package has to be spliced in at that " +
             "position; re-anchor this file.")
    if VESTA_MCU_RTL[-1] != _MCU:
        fail("opensource_sim/castalia_b/defs.bzl: VESTA_MCU_RTL no longer ends at %s, " % _MCU +
             "so the generated MCU top can no longer simply replace the last " +
             "entry; re-anchor this file.")
    return VESTA_MCU_RTL[:1], VESTA_MCU_RTL[2:-1]

CASTALIA_B_HEAD, CASTALIA_B_MID = _split()
