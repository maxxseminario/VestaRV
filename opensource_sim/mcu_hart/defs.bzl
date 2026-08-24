"""Analysis orders for the SINGLE-HART chip, config/mcu_hart.json.

The RTL these lists name is not the tracked hdl/common/MCU.vhd. MCU.vhd and
MemoryMap.vhd are GENERATED per configuration, and the tracked pair is the
five-hart Castalia; the single-hart pair comes out of
//platform/common:chip_artifacts_mcu_hart. So the spine has to be spliced
rather than appended to: MemoryMap.vhd is the SECOND file analyzed (everything
below it reads the package) and MCU.vhd is the LAST, and the two generated
files go in at exactly those two positions.

MCU_HART_HEAD and MCU_HART_MID are the two runs of tracked files either side of
them. The BUILD file interleaves:

    HEAD  +  generated MemoryMap.vhd  +  MID  +  generated MCU.vhd

hdl/common/periph/NPU.vhd is the one file dropped from the shared spine, and it
is dropped because of the configuration and not for convenience: mcu_hart sets
peripherals.npu false, so its MemoryMap.vhd declares no MmrAddrNPU* constants
and NPU.vhd does not ANALYZE against it. Nothing instantiates the NPU on this
chip, so the file has no business in this build.
"""

load("//opensource_sim/mcu:defs.bzl", "VESTA_MCU_RTL")

_MEMORY_MAP = "hdl/common/MemoryMap.vhd"
_MCU = "hdl/common/MCU.vhd"
_NPU = "hdl/common/periph/NPU.vhd"

# The testbench spine, on top of the MCU. macros.vhd has to precede everything
# that uses it and tb_defs/TestbenchLibrary have to precede the bench.
MCU_HART_MACROS = "hdl/common/macros/macros.vhd"

MCU_HART_TB = [
    "hdl/common/tb/tb_defs.vhd",
    "hdl/common/tb/TestbenchLibrary.vhd",
]

def _split():
    if VESTA_MCU_RTL[1] != _MEMORY_MAP:
        fail("opensource_sim/mcu_hart/defs.bzl: VESTA_MCU_RTL[1] is %s, not %s. " %
             (VESTA_MCU_RTL[1], _MEMORY_MAP) +
             "The generated memory-map package has to be spliced in at that " +
             "position; re-anchor this file.")
    if VESTA_MCU_RTL[-1] != _MCU:
        fail("opensource_sim/mcu_hart/defs.bzl: VESTA_MCU_RTL no longer ends at %s, " % _MCU +
             "so the generated MCU top can no longer simply replace the last " +
             "entry; re-anchor this file.")
    if _NPU not in VESTA_MCU_RTL:
        fail("opensource_sim/mcu_hart/defs.bzl: %s is no longer in VESTA_MCU_RTL, " % _NPU +
             "so this list's reason for dropping it is stale. Delete the drop.")
    mid = [f for f in VESTA_MCU_RTL[2:-1] if f != _NPU]
    return [MCU_HART_MACROS] + VESTA_MCU_RTL[:1], mid

MCU_HART_HEAD, MCU_HART_MID = _split()
