"""Analysis order for the FPGA bring-up cut, config/fpga.json.

The RTL these lists name is not the tracked hdl/common/MCU.vhd. MCU.vhd and
MemoryMap.vhd are GENERATED per configuration and the tracked pair is the
default-knob Castalia; the one-hart FPGA pair comes out of
//platform/common:chip_artifacts_fpga. So the spine is spliced rather than
appended to, exactly as //opensource_sim/mcu_hart and //opensource_sim/
castalia_b do it: MemoryMap.vhd is the SECOND file analyzed (everything below it
reads the package) and MCU.vhd is the LAST.

    HEAD  +  generated MemoryMap.vhd  +  MID  +  generated MCU.vhd

WHAT IS SUBSTITUTED, and it is why this package exists. hdl/common/sim/ and
hdl/fpga/ declare the same entities, and EXACTLY ONE of the two may appear in
any file list (hdl/fpga/README.md): compile both and the tool binds whichever
architecture it analyzed last. _FPGA_SUBS swaps the four sim cells hdl/fpga/
supersedes for the synthesizable stand-ins, in place, so the order the shared
spine fixes is preserved. hdl/common/sim/ClockMuxGlitchFree.vhd is the one file
in that directory which stays: it is ordinary synthesizable RTL, SYSTEM.vhd
instantiates it, and hdl/fpga/ does not replace it.

WHAT IS DROPPED. hdl/common/periph/NPU.vhd, for the configuration and not for
convenience: fpga.json sets peripherals.npu false, so the generated
MemoryMap.vhd declares no MmrAddrNPU* constants and NPU.vhd does not ANALYZE
against it. _FPGA_DROP carries it, alongside the DMA and TRNG sources, which
fpga.json pins off the same way and which the shared spine does not carry
today. That half of the set is TOLERANT of absence on purpose: the spine
follows the tracked MCU.vhd, so a block arriving there later must not silently
arrive in a design that pins it off.

NOTHING IS ADDED. //opensource_sim/castalia_b has to splice in DMA.vhd and
TRNG.vhd because its configuration turns those blocks on; fpga.json pins every
optional peripheral false, so its MCU.vhd instantiates a subset of the shared
spine and never a superset.
"""

load("//opensource_sim/mcu:defs.bzl", "VESTA_MCU_RTL")

_MEMORY_MAP = "hdl/common/MemoryMap.vhd"
_MCU = "hdl/common/MCU.vhd"
_NPU = "hdl/common/periph/NPU.vhd"

# Sources for blocks fpga.json pins false. _NPU is checked for presence below
# because it is in the spine today and its drop is load bearing; the rest are
# dropped only if they appear, since the spine tracks a generation that does
# not carry them yet.
_FPGA_DROP = [
    _NPU,
    "hdl/common/regs/vhdl/dma_regs_pkg.vhd",
    "hdl/common/periph/DMA.vhd",
    "hdl/common/regs/vhdl/trng_regs_pkg.vhd",
    "hdl/common/periph/TrngRoEnsemble.vhd",
    "hdl/common/periph/TrngRoEnsemble_sim.vhd",
    "hdl/common/periph/TRNG.vhd",
]

# The synthesizable stand-ins, keyed by the simulation cell each one replaces.
# A None value means the entity moved into a file another key already names:
# hdl/fpga/analog_stubs.vhd carries GlitchFilter, PowerOnResetCheng,
# OscillatorCurrentStarved and DCO together, so it is listed once.
_FPGA_SUBS = {
    "hdl/common/sim/ClkGate.vhd": "hdl/fpga/ClkGate.vhd",
    "hdl/common/sim/PowerOnResetCheng_behav.vhd": "hdl/fpga/analog_stubs.vhd",
    "hdl/common/sim/OscillatorCurrentStarved_simulation.vhd": None,
    "hdl/common/sim/GlitchFilter_behav.vhd": None,
}

# The memory macros, which the shared spine does not carry at all: the tracked
# MCU.vhd instantiates them by name and each consumer supplies its own model.
# These are hdl/fpga/'s, so the arrays that elaborate here are the ones a
# synthesis run would infer block RAM from.
FPGA_MACROS = [
    "hdl/fpga/ARM_IP_ROM.vhd",
    "hdl/fpga/ARM_IP_RAM.vhd",
]

def _split():
    if VESTA_MCU_RTL[1] != _MEMORY_MAP:
        fail("opensource_sim/fpga/defs.bzl: VESTA_MCU_RTL[1] is %s, not %s. " %
             (VESTA_MCU_RTL[1], _MEMORY_MAP) +
             "The generated memory-map package has to be spliced in at that " +
             "position; re-anchor this file.")
    if VESTA_MCU_RTL[-1] != _MCU:
        fail("opensource_sim/fpga/defs.bzl: VESTA_MCU_RTL no longer ends at %s, " % _MCU +
             "so the generated MCU top can no longer simply replace the last " +
             "entry; re-anchor this file.")
    if _NPU not in VESTA_MCU_RTL:
        fail("opensource_sim/fpga/defs.bzl: %s is no longer in VESTA_MCU_RTL, " % _NPU +
             "so this list's reason for dropping it is stale. Delete the drop.")
    for sim in _FPGA_SUBS:
        if sim not in VESTA_MCU_RTL[2:-1]:
            fail("opensource_sim/fpga/defs.bzl: %s is no longer in VESTA_MCU_RTL " % sim +
                 "between MemoryMap.vhd and MCU.vhd, so the hdl/fpga/ cell that " +
                 "replaces it would be analyzed on top of nothing; re-anchor this " +
                 "file against hdl/fpga/README.md.")

    mid = []
    for f in VESTA_MCU_RTL[2:-1]:
        if f in _FPGA_DROP:
            continue
        if f in _FPGA_SUBS:
            sub = _FPGA_SUBS[f]
            if sub:
                mid.append(sub)
            continue
        mid.append(f)
    return VESTA_MCU_RTL[:1], mid

FPGA_HEAD, FPGA_MID = _split()
