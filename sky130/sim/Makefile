# VestaRV: cocotb 2.x smoke test for the vesta core on GHDL. Run `make` from this
# directory; it needs ghdl, cocotb 2.x and a host gcc and make.
# The sources come from ../../hdl/common in a curated dependency order that must
# stay in step with ../synth.sh: regfile_sbirq.vhd is the only regfile and
# sim/ClkGate.vhd the only ClkGate.
SIM ?= ghdl
TOPLEVEL_LANG = vhdl

COMMON = $(PWD)/../../hdl/common

VHDL_SOURCES = \
    $(COMMON)/constants.vhd \
    $(COMMON)/MemoryMap.vhd \
    $(COMMON)/vesta/extend.vhd \
    $(COMMON)/vesta/loadext.vhd \
    $(COMMON)/vesta/store_ext.vhd \
    $(COMMON)/vesta/branch_valid.vhd \
    $(COMMON)/vesta/pulse_extender.vhd \
    $(COMMON)/vesta/aludec.vhd \
    $(COMMON)/vesta/maindec.vhd \
    $(COMMON)/vesta/div.vhd \
    $(COMMON)/vesta/alu.vhd \
    $(COMMON)/vesta/regfile_sbirq.vhd \
    $(COMMON)/vesta/c_dec.vhd \
    $(COMMON)/vesta/csr_unit.vhd \
    $(COMMON)/vesta/irq_handler.vhd \
    $(COMMON)/vesta/controller.vhd \
    $(COMMON)/vesta/datapath.vhd \
    $(COMMON)/sim/ClkGate.vhd \
    $(COMMON)/vesta/vesta.vhd \
    $(PWD)/vesta_harness.vhd

COCOTB_TOPLEVEL = vesta_harness
COCOTB_TEST_MODULES = test_vesta_smoke

# --std=08 matches the documented sim target and -fsynopsys resolves the
# ieee.std_logic_arith and std_logic_unsigned use-clauses in constants.vhd and
# regfile_sbirq.vhd. Both must ride EXTRA_ARGS: cocotb folds that into GHDL_ARGS
# for analyse and for run, which is the only place that reaches the runtime
# library lookup. SIM_ARGS goes after the unit name, where it is design runtime
# args only, and the elaboration fails with "cannot find entity vesta_harness".
EXTRA_ARGS += --std=08 -fsynopsys
SIM_ARGS ?= --vcd=vesta_smoke.vcd

include $(shell cocotb-config --makefiles)/Makefile.sim
