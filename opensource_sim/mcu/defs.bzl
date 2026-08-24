"""Shared definitions for the GHDL MCU elaboration gate.

VESTA_MCU_RTL is the analysis order that reaches hdl/common/MCU.vhd: the bare
core of //opensource_sim/isa, followed by the peripheral and system blocks the
MCU adds on top of it.

The core half is DERIVED from VESTA_ISA_RTL rather than copied, so the sync
guard //opensource_sim/isa:source_list_sync_test stays the single authority on
the shared sequence and this package cannot drift away from it. The MCU half
is transcribed from tools/cosim/gate/behavioral_mp/cell_list_behavioral.txt,
which is the xcelium cell list for the same design, minus four entries:

  * the TSMC pad library, which is Verilog and which GHDL cannot read;
  * hdl/common/tb/riscv_tb.vhd, the testbench that instantiates those pads;
  * hdl/common/tb/serial_flash.vhd and hdl/common/macros/macros.vhd, which are
    read only by that testbench and by no synthesizable unit;
  * hdl/common/sim/ARM_IP_ROM.vhd and hdl/common/sim/ARM_IP_RAM.vhd, replaced
    by the tracked elaboration stub in this package. See the note on
    mem_macros_stub.vhd in BUILD.bazel for why.

Two entries here are NOT in that cell list and are deliberate:

  * hdl/common/vesta/pmp_unit.vhd. MemoryMap's CORE_ENABLE_PMP is false today,
    so vesta's gen_pmp instantiates nothing and the cell list needs no entry.
    pmp_unit is a COMPONENT there, and an unbound component is a GHDL warning
    rather than an error, so leaving it out would let a CORE_ENABLE_PMP flip
    elaborate to a silently missing unit instead of being covered here.
  * hdl/common/vesta/aludec.vhd and hdl/common/vesta/pulse_extender.vhd arrive
    with VESTA_ISA_RTL and are absent from the cell list for the same reason.

hdl/common/vesta/vesta_tracer.vhd is the one cell-list entry deliberately left
out. vesta.vhd's own note at its declaration says the tracer is a component
precisely so that only a flow which turns TRACE_ENABLE on has to carry the
file; this gate runs at TRACE_ENABLE false.
"""

load("//opensource_sim/isa:defs.bzl", "VESTA_ISA_RTL")

# The last unit of the core spine. VESTA_MCU_RTL appends to it, so if the core
# list ever stops ending at the core itself this file has to be re-anchored
# rather than silently analyzing the MCU blocks in front of their dependencies.
_CORE_ANCHOR = "hdl/common/vesta/vesta.vhd"

# Everything the MCU adds on top of the bare core, in analysis order.
# Direct `entity work.x` instantiation binds at ANALYSIS, so every unit here
# must precede the unit that names it; MCU.vhd is last for that reason.
_MCU_EXTRA = [
    # Fixed-point packages and the arithmetic cells the NPU is built from.
    "hdl/common/commune/fixed_float_types_c.vhdl",
    "hdl/common/commune/fixed_pkg_c.vhdl",
    "hdl/common/commune/FPMac.vhd",
    "hdl/common/commune/FPSigmoid.vhd",
    "hdl/common/commune/TieLow.vhd",
    # Behavioural models of the analog and clocking cells the MCU instantiates.
    "hdl/common/sim/ClockMuxGlitchFree.vhd",
    "hdl/common/sim/PowerOnResetCheng_behav.vhd",
    "hdl/common/sim/OscillatorCurrentStarved_simulation.vhd",
    "hdl/common/commune/CRC16.vhd",
    "hdl/common/sim/GlitchFilter_behav.vhd",
    "hdl/common/commune/ClkDivPower2.vhd",
    # The peripheral slots.
    "hdl/common/periph/GPIO.vhd",
    "hdl/common/periph/SPI.vhd",
    "hdl/common/periph/QSPI.vhd",
    "hdl/common/periph/I3C.vhd",
    "hdl/common/periph/NFC.vhd",
    "hdl/common/periph/RTC.vhd",
    "hdl/common/periph/PWM.vhd",
    "hdl/common/periph/OneWire.vhd",
    "hdl/common/periph/I2CTarget.vhd",
    "hdl/common/periph/EVFAB.vhd",
    "hdl/common/periph/UART.vhd",
    "hdl/common/periph/I2C.vhd",
    "hdl/common/periph/TIMER.vhd",
    "hdl/common/periph/SYSTEM.vhd",
    "hdl/common/periph/NPU.vhd",
    # The privileged unit vesta binds when CORE_ENABLE_PMP is true.
    "hdl/common/vesta/pmp_unit.vhd",
    # The system fabric, then the tiles, then the MCU that wires them together.
    "hdl/common/adddec.vhd",
    "hdl/common/clint.vhd",
    "hdl/common/irq_router.vhd",
    "hdl/common/mp_arbiter.vhd",
    "hdl/common/mutex_bank.vhd",
    "hdl/common/pwr_ctrl.vhd",
    "hdl/common/resv_unit.vhd",
    "hdl/common/hart_tile.vhd",
    "hdl/common/afe_stub.vhd",
    "hdl/common/debug_module.vhd",
    "hdl/common/jtag_dtm.vhd",
    "hdl/common/orch_tile.vhd",
    "hdl/common/MCU.vhd",
]

def _derive():
    if VESTA_ISA_RTL[-1] != _CORE_ANCHOR:
        fail("opensource_sim/mcu/defs.bzl: VESTA_ISA_RTL no longer ends at %s, " % _CORE_ANCHOR +
             "so the MCU blocks can no longer simply be appended to it; re-anchor this list.")
    for f in _MCU_EXTRA:
        if f in VESTA_ISA_RTL:
            fail("opensource_sim/mcu/defs.bzl: %s is now in VESTA_ISA_RTL as well as " % f +
                 "_MCU_EXTRA; analyzing one file twice redefines its design units. " +
                 "Drop it from _MCU_EXTRA.")
    return VESTA_ISA_RTL + _MCU_EXTRA

VESTA_MCU_RTL = _derive()
