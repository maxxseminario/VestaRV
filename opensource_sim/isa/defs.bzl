"""Shared definitions for the GHDL ISA regression package.

VESTA_ISA_RTL is the curated analysis order of opensource_sim/isa/run_isa.sh's
SOURCES array, transcribed as workspace-relative paths.
THIS LIST MUST STAY IN SYNC with run_isa.sh, sky130/synth.sh and
sky130/sim/Makefile. Three points in it are load bearing:

  * regfile_sbirq.vhd is the ONLY correct regfile of the three in the tree.
  * ClkGate must come from hdl/common/sim/, not from a synthesis stub.
  * fpu_simple.vhd and fpu.vhd MUST be analyzed, because the testbench sets
    ENABLE_ZFINX true. Leave them out and the fpu instances are unbound,
    fpu_done floats, and every FP op hangs the multicycle FSM.
"""

VESTA_ISA_RTL = [
    "hdl/common/constants.vhd",
    "hdl/common/MemoryMap.vhd",
    "hdl/common/vesta/extend.vhd",
    "hdl/common/vesta/loadext.vhd",
    "hdl/common/vesta/store_ext.vhd",
    "hdl/common/vesta/branch_valid.vhd",
    "hdl/common/vesta/pulse_extender.vhd",
    "hdl/common/vesta/aludec.vhd",
    "hdl/common/vesta/maindec.vhd",
    "hdl/common/vesta/div.vhd",
    "hdl/common/vesta/alu.vhd",
    "hdl/common/vesta/regfile_sbirq.vhd",
    "hdl/common/vesta/c_dec.vhd",
    "hdl/common/vesta/csr_unit.vhd",
    "hdl/common/vesta/irq_handler.vhd",
    "hdl/common/vesta/fpu_simple.vhd",
    "hdl/common/vesta/fpu.vhd",
    "hdl/common/vesta/controller.vhd",
    "hdl/common/vesta/datapath.vhd",
    "hdl/common/sim/ClkGate.vhd",
    "hdl/common/vesta/vesta.vhd",
]
