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

THREE FILES ARE ADDED, and they are a property of the configuration rather than
of this package. VESTA_MCU_RTL is the analysis order of the TRACKED MCU.vhd, the
default-knob generation, and that generation instantiates neither DMA0 nor
TRNG0. CastaliaB (like config/castalia.json) sets peripherals.dma and
peripherals.trng true, so `entity work.DMA` and `entity work.TRNG` appear in its
MCU.vhd and bind at ANALYSIS. CASTALIA_B_EXTRA carries them, and it goes after
CASTALIA_B_MID and before the generated MCU.vhd.

TrngRoEnsemble has an architecture split that this list has to decide:
hdl/common/periph/TrngRoEnsemble_sim.vhd is the behavioural ring model and
hdl/common/periph/TrngRoEnsemble.vhd is the genus/gate-only one, they declare
the same entity, and the two must never co-list. A GHDL run takes the _sim
model, the same substitution //opensource_sim/isa makes for ClkGate.

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
    for f in CASTALIA_B_EXTRA:
        if f in VESTA_MCU_RTL:
            fail("opensource_sim/castalia_b/defs.bzl: %s is now in VESTA_MCU_RTL " % f +
                 "as well as CASTALIA_B_EXTRA; analyzing one file twice redefines " +
                 "its design units. Drop it from CASTALIA_B_EXTRA.")
    return VESTA_MCU_RTL[:1], VESTA_MCU_RTL[2:-1]

# The two peripherals CastaliaB instantiates and the tracked default generation
# does not, each preceded by the register package it `use`s, and the ring model
# preceding the TRNG that binds it.
CASTALIA_B_EXTRA = [
    "hdl/common/regs/vhdl/dma_regs_pkg.vhd",
    "hdl/common/periph/DMA.vhd",
    "hdl/common/regs/vhdl/trng_regs_pkg.vhd",
    "hdl/common/periph/TrngRoEnsemble_sim.vhd",
    "hdl/common/periph/TRNG.vhd",
]

CASTALIA_B_HEAD, CASTALIA_B_MID = _split()
