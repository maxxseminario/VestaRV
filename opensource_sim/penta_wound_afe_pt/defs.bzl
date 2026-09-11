"""Analysis order for the PER-TILE AFE tape-out configuration, config/penta_wound_afe_pt.json.

The topology-A splice (//opensource_sim/penta_wound_afe) plus the two files the
per-tile build adds below MCU.vhd:

  hdl/common/hart_tile_pt.vhd   the channel-tile wrapper the generated MCU.vhd
                                instantiates in place of hart_tile
  hdl/common/sim/sar_macro_model.vhd
                                the behavioural converter its SIM_CHANNEL arm
                                instantiates, one per tile. In this topology the
                                generated riscv_tb hangs NO model of its own, so
                                these four are the only converters in the design
  hdl/common/periph/BIASG.vhd   the one-word shared-bias-generator register that
                                sits on AFE2 site 0's enable (AFE0BIASG @0x6C24)

Both AFE2.vhd and BIASG.vhd `use` a GENERATED register package (SystemRDL level
2, report R6), so afe2_regs_pkg.vhd and biasg_regs_pkg.vhd precede them.

Direct `entity work.x` instantiation binds at analysis, so all of them precede
MCU.vhd; hart_tile_pt names hart_tile and sar_macro_model, so it goes after both.
"""

load("//opensource_sim/mcu:defs.bzl", "VESTA_MCU_RTL")

_MEMORY_MAP = "hdl/common/MemoryMap.vhd"
_MCU = "hdl/common/MCU.vhd"
_HART_TILE = "hdl/common/hart_tile.vhd"

_WOUND_EXTRA = [
    "hdl/common/regs/vhdl/dma_regs_pkg.vhd",
    "hdl/common/periph/DMA.vhd",
    "hdl/common/periph/TrngRoEnsemble_sim.vhd",
    "hdl/common/regs/vhdl/trng_regs_pkg.vhd",
    "hdl/common/periph/TRNG.vhd",
    "hdl/common/regs/vhdl/afe2_regs_pkg.vhd",
    "hdl/common/periph/AFE2.vhd",
    "hdl/common/regs/vhdl/biasg_regs_pkg.vhd",
    "hdl/common/periph/BIASG.vhd",
    "hdl/common/sim/sar_macro_model.vhd",
    "hdl/common/hart_tile_pt.vhd",
]

def _split():
    if VESTA_MCU_RTL[1] != _MEMORY_MAP:
        fail("opensource_sim/penta_wound_afe_pt/defs.bzl: VESTA_MCU_RTL[1] is %s, not %s; re-anchor." %
             (VESTA_MCU_RTL[1], _MEMORY_MAP))
    if VESTA_MCU_RTL[-1] != _MCU:
        fail("opensource_sim/penta_wound_afe_pt/defs.bzl: VESTA_MCU_RTL no longer ends at %s; re-anchor." % _MCU)
    if _HART_TILE not in VESTA_MCU_RTL:
        fail("opensource_sim/penta_wound_afe_pt/defs.bzl: %s is no longer in VESTA_MCU_RTL; hart_tile_pt wraps it." % _HART_TILE)
    for f in _WOUND_EXTRA:
        if f in VESTA_MCU_RTL:
            fail("opensource_sim/penta_wound_afe_pt/defs.bzl: %s is now in VESTA_MCU_RTL; drop it from _WOUND_EXTRA." % f)
    return VESTA_MCU_RTL[:1], VESTA_MCU_RTL[2:-1] + _WOUND_EXTRA

WOUND_AFE_PT_HEAD, WOUND_AFE_PT_MID = _split()
