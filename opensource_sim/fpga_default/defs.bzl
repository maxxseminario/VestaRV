"""Analysis order for the FPGA bring-up cut, config/fpga_default.json.

The RTL these lists name is not the tracked hdl/common/MCU.vhd. MCU.vhd and
MemoryMap.vhd are GENERATED per configuration and the tracked pair is the
default-knob Castalia; the one-hart FPGA pair comes out of
//platform/common:chip_artifacts_fpga_default. So the spine is spliced rather
than appended to, exactly as //opensource_sim/asic_default and //opensource_sim/
castalia_b do it: MemoryMap.vhd is the SECOND file analyzed (everything below it
reads the package) and MCU.vhd is the LAST.

    HEAD  +  generated MemoryMap.vhd  +  MID  +  generated MCU.vhd

WHAT IS SUBSTITUTED, and it is why this package exists. hdl/common/sim/ and
hdl/fpga/ declare the same entities, and EXACTLY ONE of the two may appear in
any file list (hdl/fpga/README.md): compile both and the tool binds whichever
architecture it analyzed last. _FPGA_SUBS swaps each superseded cell for the
synthesizable stand-in, in place, so the order the shared spine fixes is
preserved. A substitution may expand to SEVERAL files: hdl/fpga/ClkGate.vhd
instantiates hdl/fpga/ClockPrimitives.vhd's ClkBufEn, and `entity work.x` binds
at ANALYSIS, so the primitive entity and its architecture are spliced in ahead
of it at the position the sim gate held.

The clocking substitution is the whole of report Z3. hdl/common/sim/
ClockMuxGlitchFree.vhd and hdl/common/commune/ClkDivPower2.vhd are ordinary
synthesizable RTL and the ASIC uses them as drawn, but both build a clock
network an FPGA cannot afford: the mux clocks three flip-flops and a gate from
EVERY input, which turns SYSTEM.vhd's fourteen divider taps into fourteen flop
clock pins, and the divider is a ripple chain of three clock nets. hdl/fpga/
replaces both. Neither hdl/common/ file changes.

WHAT IS DROPPED. hdl/common/periph/NPU.vhd, for the configuration and not for
convenience: fpga_default.json sets peripherals.npu false, so the generated
MemoryMap.vhd declares no MmrAddrNPU* constants and NPU.vhd does not ANALYZE
against it. _FPGA_DROP carries it, alongside the DMA and TRNG sources, which
fpga_default.json pins off the same way and which the shared spine does not carry
today. That half of the set is TOLERANT of absence on purpose: the spine
follows the tracked MCU.vhd, so a block arriving there later must not silently
arrive in a design that pins it off.

NOTHING IS ADDED. //opensource_sim/castalia_b has to splice in DMA.vhd and
TRNG.vhd because its configuration turns those blocks on; fpga_default.json pins every
optional peripheral false, so its MCU.vhd instantiates a subset of the shared
spine and never a superset.
"""

load("//opensource_sim/mcu:defs.bzl", "VESTA_MCU_RTL")

_MEMORY_MAP = "hdl/common/MemoryMap.vhd"
_MCU = "hdl/common/MCU.vhd"
_NPU = "hdl/common/periph/NPU.vhd"

# Sources for blocks fpga_default.json pins false. _NPU is checked for presence below
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

# The synthesizable stand-ins, keyed by the source cell each one replaces. The
# value is the list of files that go in at that position, in analysis order; an
# EMPTY list means the entity moved into a file another key already names, as
# hdl/fpga/analog_stubs.vhd carries GlitchFilter, PowerOnResetCheng,
# OscillatorCurrentStarved and DCO together and is listed once.
#
# hdl/fpga/ClockPrimitives.vhd declares ClkBufEn and ClkBuf, the two cells every
# clock-generation stand-in here is built from, and ClockPrimitives_generic.vhd
# holds their vendor-neutral architectures. Its pair file,
# ClockPrimitives_xilinx.vhd, instantiates BUFGCE and BUFG and is what a Vivado
# run takes instead; EXACTLY ONE of the two may appear in any file list, which
# is hdl/fpga/README.md's one rule applied one level down. GHDL takes the
# generic pair because it has no cell to bind a UNISIM primitive to.
_FPGA_SUBS = {
    "hdl/common/sim/ClkGate.vhd": [
        "hdl/fpga/ClockPrimitives.vhd",
        "hdl/fpga/ClockPrimitives_generic.vhd",
        "hdl/fpga/ClkGate.vhd",
    ],
    "hdl/common/sim/ClockMuxGlitchFree.vhd": ["hdl/fpga/ClockMuxGlitchFree.vhd"],
    "hdl/common/commune/ClkDivPower2.vhd": ["hdl/fpga/ClkDivPower2.vhd"],
    "hdl/common/sim/PowerOnResetCheng_behav.vhd": ["hdl/fpga/analog_stubs.vhd"],
    "hdl/common/sim/OscillatorCurrentStarved_simulation.vhd": [],
    "hdl/common/sim/GlitchFilter_behav.vhd": [],
}

# The memory macros, which the shared spine does not carry at all: the tracked
# MCU.vhd instantiates them by name and each consumer supplies its own model.
# These are hdl/fpga/'s, so the arrays that elaborate here are the ones a
# synthesis run would infer block RAM from.
FPGA_DEFAULT_MACROS = [
    "hdl/fpga/ARM_IP_ROM.vhd",
    "hdl/fpga/ARM_IP_RAM.vhd",
]

def _split():
    if VESTA_MCU_RTL[1] != _MEMORY_MAP:
        fail("opensource_sim/fpga_default/defs.bzl: VESTA_MCU_RTL[1] is %s, not %s. " %
             (VESTA_MCU_RTL[1], _MEMORY_MAP) +
             "The generated memory-map package has to be spliced in at that " +
             "position; re-anchor this file.")
    if VESTA_MCU_RTL[-1] != _MCU:
        fail("opensource_sim/fpga_default/defs.bzl: VESTA_MCU_RTL no longer ends at %s, " % _MCU +
             "so the generated MCU top can no longer simply replace the last " +
             "entry; re-anchor this file.")
    if _NPU not in VESTA_MCU_RTL:
        fail("opensource_sim/fpga_default/defs.bzl: %s is no longer in VESTA_MCU_RTL, " % _NPU +
             "so this list's reason for dropping it is stale. Delete the drop.")
    for sim in _FPGA_SUBS:
        if sim not in VESTA_MCU_RTL[2:-1]:
            fail("opensource_sim/fpga_default/defs.bzl: %s is no longer in VESTA_MCU_RTL " % sim +
                 "between MemoryMap.vhd and MCU.vhd, so the hdl/fpga/ cell that " +
                 "replaces it would be analyzed on top of nothing; re-anchor this " +
                 "file against hdl/fpga/README.md.")

    mid = []
    for f in VESTA_MCU_RTL[2:-1]:
        if f in _FPGA_DROP:
            continue
        if f in _FPGA_SUBS:
            mid.extend(_FPGA_SUBS[f])
            continue
        mid.append(f)
    return VESTA_MCU_RTL[:1], mid

FPGA_DEFAULT_HEAD, FPGA_DEFAULT_MID = _split()

# The same MID list with the Xilinx clock primitives in place of the
# vendor-neutral ones, for the Vivado file manifest. GHDL cannot take this list:
# it has no cell to bind BUFGCE and BUFG to. See implementations/fpga/synth/.
_PRIM_GENERIC = "hdl/fpga/ClockPrimitives_generic.vhd"
_PRIM_XILINX = "hdl/fpga/ClockPrimitives_xilinx.vhd"

def _vivado_mid():
    if _PRIM_GENERIC not in FPGA_DEFAULT_MID:
        fail("opensource_sim/fpga_default/defs.bzl: %s is no longer in the analysis " % _PRIM_GENERIC +
             "list, so there is nothing for the Xilinx pair file to replace; " +
             "re-anchor this file against hdl/fpga/README.md.")
    return [_PRIM_XILINX if f == _PRIM_GENERIC else f for f in FPGA_DEFAULT_MID]

FPGA_DEFAULT_MID_VIVADO = _vivado_mid()
