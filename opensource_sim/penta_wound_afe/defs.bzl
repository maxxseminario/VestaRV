"""Analysis order for the AFE-bearing tape-out configuration, config/penta_wound_afe.json.

Same splice as //opensource_sim/mcu_hart: the generated MemoryMap.vhd goes in
second and the generated MCU.vhd last, with the tracked spine either side of
them. Unlike mcu_hart this configuration keeps the NPU, and it carries four
blocks the default spine does not name because the default Castalia has them
off: DMA, TRNG (with the behavioural ring-ensemble model, the real
TrngRoEnsemble is a zero-delay oscillator loop GHDL cannot run) and AFE2.
Direct `entity work.x` instantiation binds at analysis, so all four precede
MCU.vhd. AFE2.vhd `use`s the generated afe2_regs_pkg (SystemRDL level 2, report
R6), so the package precedes IT.
"""

load("//opensource_sim/mcu:defs.bzl", "VESTA_MCU_RTL")

_MEMORY_MAP = "hdl/common/MemoryMap.vhd"
_MCU = "hdl/common/MCU.vhd"

_WOUND_EXTRA = [
    "hdl/common/periph/DMA.vhd",
    "hdl/common/periph/TrngRoEnsemble_sim.vhd",
    "hdl/common/periph/TRNG.vhd",
    "hdl/common/periph/afe2_regs_pkg.vhd",
    "hdl/common/periph/AFE2.vhd",
]

def _split():
    if VESTA_MCU_RTL[1] != _MEMORY_MAP:
        fail("opensource_sim/penta_wound_afe/defs.bzl: VESTA_MCU_RTL[1] is %s, not %s; re-anchor." %
             (VESTA_MCU_RTL[1], _MEMORY_MAP))
    if VESTA_MCU_RTL[-1] != _MCU:
        fail("opensource_sim/penta_wound_afe/defs.bzl: VESTA_MCU_RTL no longer ends at %s; re-anchor." % _MCU)
    for f in _WOUND_EXTRA:
        if f in VESTA_MCU_RTL:
            fail("opensource_sim/penta_wound_afe/defs.bzl: %s is now in VESTA_MCU_RTL; drop it from _WOUND_EXTRA." % f)
    return VESTA_MCU_RTL[:1], VESTA_MCU_RTL[2:-1] + _WOUND_EXTRA

WOUND_AFE_HEAD, WOUND_AFE_MID = _split()
