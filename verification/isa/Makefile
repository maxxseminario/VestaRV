# #=======================================================================
# Makefile for riscv-tests/isa
#-----------------------------------------------------------------------

XLEN ?= 32

src_dir := ./tests
build_dir := ./build

ifeq ($(XLEN),64)
include $(src_dir)/rv64ui/Makefrag
include $(src_dir)/rv64uc/Makefrag
include $(src_dir)/rv64um/Makefrag
include $(src_dir)/rv64ua/Makefrag
include $(src_dir)/rv64uf/Makefrag
include $(src_dir)/rv64ud/Makefrag
include $(src_dir)/rv64uzfh/Makefrag
include $(src_dir)/rv64uzba/Makefrag
include $(src_dir)/rv64uzbb/Makefrag
include $(src_dir)/rv64uzbc/Makefrag
include $(src_dir)/rv64uzbs/Makefrag
include $(src_dir)/rv64si/Makefrag
include $(src_dir)/rv64ssvnapot/Makefrag
include $(src_dir)/rv64mi/Makefrag
include $(src_dir)/rv64mzicbo/Makefrag
include $(src_dir)/hypervisor/Makefrag
endif
include $(src_dir)/rv32ui/Makefrag
include $(src_dir)/rv32uc/Makefrag
include $(src_dir)/rv32um/Makefrag
include $(src_dir)/rv32ua/Makefrag
include $(src_dir)/rv32uf/Makefrag
include $(src_dir)/rv32ud/Makefrag
include $(src_dir)/rv32uzfh/Makefrag
include $(src_dir)/rv32uzba/Makefrag
include $(src_dir)/rv32uzbb/Makefrag
include $(src_dir)/rv32uzbc/Makefrag
include $(src_dir)/rv32uzbs/Makefrag
include $(src_dir)/rv32uzicond/Makefrag
include $(src_dir)/rv32uzabha/Makefrag
include $(src_dir)/rv32uzacas/Makefrag
include $(src_dir)/rv32uzkne/Makefrag
include $(src_dir)/rv32uzknd/Makefrag
include $(src_dir)/rv32uzknh/Makefrag
include $(src_dir)/rv32si/Makefrag
include $(src_dir)/rv32ziscr/Makefrag # Added by Maxx Seminario 10/21/2025
include $(src_dir)/rv32mi/Makefrag
include $(src_dir)/periph/Makefrag
include $(src_dir)/boot/Makefrag
include $(src_dir)/spifem/Makefrag

# Create build directories
$(shell mkdir -p $(build_dir))

default: all

#--------------------------------------------------------------------
# Build rules
#--------------------------------------------------------------------

# RISCV_PREFIX ?= riscv$(XLEN)-none-elf-
RISCV_PREFIX ?= riscv-none-elf-
RISCV_GCC ?= $(RISCV_PREFIX)gcc
RISCV_GCC_OPTS ?= -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump --disassemble-all --disassemble-zeroes \
	--section=.text --section=.text.startup --section=.text.init --section=.ivt \
	--section=.data --section=.tohost --section=.bss \
	--section=.npu0_yhat --section=.npu0_x --section=.npu0_w \
	--section=.isr_sys_wdt \
	--section=.isr_gpio0_b0 --section=.isr_gpio0_b1 --section=.isr_gpio0_b2 --section=.isr_gpio0_b3 \
	--section=.isr_gpio0_b4 --section=.isr_gpio0_b5 --section=.isr_gpio0_b6 --section=.isr_gpio0_b7 \
	--section=.isr_spi0_tc --section=.isr_spi0_te \
	--section=.isr_spi1_tc --section=.isr_spi1_te \
	--section=.isr_uart0_rc --section=.isr_uart0_te --section=.isr_uart0_tc \
	--section=.isr_tim0_cap0 --section=.isr_tim0_cap1 --section=.isr_tim0_ovf \
	--section=.isr_tim0_cmp0 --section=.isr_tim0_cmp1 --section=.isr_tim0_cmp2 \
	--section=.isr_tim1_cap0 --section=.isr_tim1_cap1 --section=.isr_tim1_ovf \
	--section=.isr_tim1_cmp0 --section=.isr_tim1_cmp1 --section=.isr_tim1_cmp2 \
	--section=.isr_gpio1_b0 --section=.isr_gpio1_b1 --section=.isr_gpio1_b2 --section=.isr_gpio1_b3 \
	--section=.isr_gpio1_b4 --section=.isr_gpio1_b5 --section=.isr_gpio1_b6 --section=.isr_gpio1_b7 \
	--section=.isr_gpio2_b0 --section=.isr_gpio2_b1 --section=.isr_gpio2_b2 --section=.isr_gpio2_b3 \
	--section=.isr_gpio2_b4 --section=.isr_gpio2_b5 --section=.isr_gpio2_b6 --section=.isr_gpio2_b7 \
	--section=.isr_gpio3_b0 --section=.isr_gpio3_b1 --section=.isr_gpio3_b2 --section=.isr_gpio3_b3 \
	--section=.isr_gpio3_b4 --section=.isr_gpio3_b5 --section=.isr_gpio3_b6 --section=.isr_gpio3_b7 \
	--section=.isr_uart1_rc --section=.isr_uart1_te --section=.isr_uart1_tc \
	--section=.isr_afe0_rc --section=.isr_afe0_ovf --section=.isr_afe0_err \
	--section=.isr_sar0_rc --section=.isr_sar0_ovf
RISCV_SIM ?= spike
vpath %.S $(src_dir)


# Maxx Seminario 06/17/25
# Variables for generating rcf files

RISCV_OBJCOPY ?= $(RISCV_PREFIX)objcopy
MEM_SIZE ?= $(shell printf "%d" 0x14000) #Including ROM and Peripherals?
BIN_OFFSET ?= $(shell printf "%d" 0x0000) # Remember to account for 0x4000 offset of ROM
WORD_COUNT ?= $(shell echo $$(( $(MEM_SIZE) / 4 )))  

BOOT_MEM_SIZE := $(shell printf "%d" 0x4000)
BOOT_WORD_COUNT := $(shell echo $$(( $(BOOT_MEM_SIZE) / 4 )))
boot_p_linker = -T$(src_dir)/../env/p/link_boot.ld


boot-p-boot_padded.bin: boot-p-boot.bin
	dd if=/dev/zero of=$@ bs=$(BOOT_MEM_SIZE) count=1 2>/dev/null
	dd if=$< of=$@ bs=1 seek=$(BIN_OFFSET) conv=notrunc 2>/dev/null

boot-p-boot.rcf: boot-p-boot_padded.bin
	@echo "Generating $@ (binary format, $(BOOT_WORD_COUNT) words)"
	@od -v -An -tx4 -w4 $< | awk '\
	{ \
	    hex = $$1; \
	    bin = ""; \
	    for (i = 1; i <= 8; i++) { \
	        c = substr(hex, i, 1); \
	        if (c == "0") bin = bin "0000"; \
	        else if (c == "1") bin = bin "0001"; \
	        else if (c == "2") bin = bin "0010"; \
	        else if (c == "3") bin = bin "0011"; \
	        else if (c == "4") bin = bin "0100"; \
	        else if (c == "5") bin = bin "0101"; \
	        else if (c == "6") bin = bin "0110"; \
	        else if (c == "7") bin = bin "0111"; \
	        else if (c == "8") bin = bin "1000"; \
	        else if (c == "9") bin = bin "1001"; \
	        else if (c == "a") bin = bin "1010"; \
	        else if (c == "b") bin = bin "1011"; \
	        else if (c == "c") bin = bin "1100"; \
	        else if (c == "d") bin = bin "1101"; \
	        else if (c == "e") bin = bin "1110"; \
	        else if (c == "f") bin = bin "1111"; \
	    } \
	    print bin; \
	}' > $@
	@lines=$$(wc -l < $@); \
	if [ $$lines -ne $(BOOT_WORD_COUNT) ]; then \
	    echo "Error: $@ has $$lines lines (expected $(BOOT_WORD_COUNT))"; \
	    exit 1; \
	fi

#------------------------------------------------------------
# Build assembly tests

%.dump: %
	$(RISCV_OBJDUMP) $< > $@

%.out: %
	$(RISCV_SIM) --isa=rv64gch_zfh_zicboz_svnapot_zicntr_zba_zbb_zbc_zbs --misaligned $< 2> $@

%.out32: %
	$(RISCV_SIM) --isa=rv32gc_zfh_zicboz_svnapot_zicntr_zba_zbb_zbc_zbs --misaligned $< 2> $@


#=======================================================================
# RCF generation rules
# Maxx Seminario 06/17/2025
#-----------------------------------------------------------------------




# Rule to convert ELF to binary
%.bin: %
	$(RISCV_OBJCOPY) -O binary --gap-fill=0x00 $< $@

%_padded.bin: %.bin
	@# Create full-size zero file
	dd if=/dev/zero of=$@ bs=$(MEM_SIZE) count=1 2>/dev/null
	@# Overlay binary at offset BIN_OFFSET (e.g., 0x4000)
	dd if=$< of=$@ bs=1 seek=$(BIN_OFFSET) conv=notrunc 2>/dev/null

# Rule to convert padded binary to binary-formatted RCF (1s/0s)
%.rcf: %_padded.bin
	@echo "Generating $@ (binary format, $(WORD_COUNT) words)"
	@od -v -An -tx4 -w4 $< | awk '\
	{ \
	    hex = $$1; \
	    bin = ""; \
	    for (i = 1; i <= 8; i++) { \
	        c = substr(hex, i, 1); \
	        if (c == "0") bin = bin "0000"; \
	        else if (c == "1") bin = bin "0001"; \
	        else if (c == "2") bin = bin "0010"; \
	        else if (c == "3") bin = bin "0011"; \
	        else if (c == "4") bin = bin "0100"; \
	        else if (c == "5") bin = bin "0101"; \
	        else if (c == "6") bin = bin "0110"; \
	        else if (c == "7") bin = bin "0111"; \
	        else if (c == "8") bin = bin "1000"; \
	        else if (c == "9") bin = bin "1001"; \
	        else if (c == "a") bin = bin "1010"; \
	        else if (c == "b") bin = bin "1011"; \
	        else if (c == "c") bin = bin "1100"; \
	        else if (c == "d") bin = bin "1101"; \
	        else if (c == "e") bin = bin "1110"; \
	        else if (c == "f") bin = bin "1111"; \
	    } \
	    print bin; \
	}' > $@
	@# Verify we have exactly WORD_COUNT lines
	@lines=$$(wc -l < $@); \
	if [ $$lines -ne $(WORD_COUNT) ]; then \
	    echo "Error: $@ has $$lines lines (expected $(WORD_COUNT))"; \
	    exit 1; \
	fi


# Generate list of all RCF targets for built tests
tests_rcf = $(addsuffix .rcf, $(tests))

# Add to junk list for cleaning
junk += $(addsuffix .bin, $(tests)) $(addsuffix _padded.bin, $(tests)) $(tests_rcf)


# ---------------------------------------------------------------
# Compile Template - 
# Maxx Seminario 06/17/2025 - Added rcf generation
# Updated: Builds into organized build/ subdirectories
# ---------------------------------------------------------------


define compile_template

# Create build subdirectory for this test suite
$$(shell mkdir -p $$(build_dir)/$(1))

# Update test names to include build directory path
$(1)_p_tests_build = $$(patsubst %,$$(build_dir)/$(1)/%,$$(notdir $$($(1)_p_tests)))

$$($(1)_p_tests_build): $$(build_dir)/$(1)/$(1)-p-%: $$(src_dir)/$(1)/%.S
	$$(RISCV_GCC) $(2) $$(RISCV_GCC_OPTS) -I../env/p -I./macros/scalar -I../../platform/myshkin/gcc/lib/include -T../env/p/link.ld $$< -o $$@
	$$(MAKE) $$@.rcf  
$(1)_tests += $$($(1)_p_tests_build)

$(1)_tests_dump = $$(addsuffix .dump, $$($(1)_tests))

$(1): $$($(1)_tests_dump)
	@$$(MAKE) pad_rcf_filenames_$(1)
	@$$(MAKE) collect_rcf_$(1)

.PHONY: $(1)

COMPILER_SUPPORTS_$(1) := $$(shell $$(RISCV_GCC) $(2) -c -x c /dev/null -o /dev/null 2> /dev/null; echo $$$$?)

ifeq ($$(COMPILER_SUPPORTS_$(1)),0)
tests += $$($(1)_tests)
endif

endef


# boot-p-boot: boot/boot.S
# 	$(RISCV_GCC) -march=rv32g -mabi=ilp32 $(RISCV_GCC_OPTS) \
# 	-I$(src_dir)/../env/p -I$(src_dir)/macros/scalar \
# 	-T$(src_dir)/../env/p/link_boot.ld $< -o $@
# 	$(MAKE) $@.rcf

$(eval $(call compile_template,boot,-march=rv32g -mabi=ilp32 -T$(src_dir)/../env/p/link_boot.ld)) # rv32ui
$(eval $(call compile_template,spifem,-march=rv32g -mabi=ilp32 -T$(src_dir)/../env/p/link_fem.ld)) # rv32ui

# Note -march=rv32g implies -march=rv32imafd
$(eval $(call compile_template,periph,-march=rv32im -mabi=ilp32))
$(eval $(call compile_template,rv32ui,-march=rv32imc -mabi=ilp32))
$(eval $(call compile_template,rv32uc,-march=rv32imc -mabi=ilp32)) 
$(eval $(call compile_template,rv32um,-march=rv32imc -mabi=ilp32))
# rv32ua: the extzicond ext-probe dispatches at build time on CORE_ENABLE_ZICOND.
# The DEFAULT build always compiles the OFF arm (no -D) -- it NEVER auto-derives
# the symbol from the gitignored make-chip header (a stale header would silently
# compile the ON arm against OFF RTL and hang the suite). To build the ON arm,
# EXPLICITLY append -DCORE_ENABLE_ZICOND to RISCV_GCC_OPTS when staging the ON
# polarity, e.g. (after rm -rf build/):
#   make rv32ua-flash RISCV_GCC_OPTS="-static -mcmodel=medany -fvisibility=hidden \
#       -nostdlib -nostartfiles -DNHARTS=4 -DCORE_ENABLE_ZICOND"
# See verification/isa/tests/rv32ua/extzicond.S.
$(eval $(call compile_template,rv32ua,-march=rv32imac -mabi=ilp32))
$(eval $(call compile_template,rv32uf,-march=rv32imc -mabi=ilp32))
$(eval $(call compile_template,rv32ud,-march=rv32imc -mabi=ilp32))
$(eval $(call compile_template,rv32uzfh,-march=rv32g_zfh -mabi=ilp32))
$(eval $(call compile_template,rv32uzba,-march=rv32gc_zba -mabi=ilp32))
$(eval $(call compile_template,rv32uzbb,-march=rv32gc_zbb -mabi=ilp32))
$(eval $(call compile_template,rv32uzbc,-march=rv32gc_zbc -mabi=ilp32))
$(eval $(call compile_template,rv32uzbs,-march=rv32gc_zbs -mabi=ilp32))
# rv32uzicond (X1): directed czero.eqz/czero.nez via mnemonics. The installed
# gas/gcc 13.2 accept _zicond in -march, so no .insn fallback is needed. This
# suite is ON-polarity only and is NOT wired into the default (off) suite runner.
$(eval $(call compile_template,rv32uzicond,-march=rv32imac_zicond -mabi=ilp32))
# rv32uzabha (X2): directed byte/halfword AMOs. gas 13.2 has NO `zabha' -march
# suffix and NO amoadd.b/... mnemonics (verified at X2 bring-up), so the tests
# emit explicit `.insn` R-types and build under the base -march. ON-polarity
# only; NOT wired into the default (off) suite runner.
$(eval $(call compile_template,rv32uzabha,-march=rv32imac -mabi=ilp32))
# rv32uzacas (X2): directed amocas.{w,b,h}. gas 13.2 has no zacas -march
# suffix and no amocas mnemonic (verified at X2 bring-up), so the tests emit
# explicit .insn R-types and build under the base -march. ON-polarity only;
# NOT wired into the default (off) suite runner.
$(eval $(call compile_template,rv32uzacas,-march=rv32imac -mabi=ilp32))
# rv32uzkne / rv32uzknd (X3 Zkne/Zknd AES-32): directed aes32e*/aes32d* per-op
# tests + the AES-128 FIPS-197 KAT. gas 13.2 has no `zkne'/`zknd' -march suffix
# and no aes32* mnemonics, so the tests emit explicit `.insn` R-types and build
# under the base -march. ON-polarity only (built with -DCORE_ENABLE_ZKN); NOT
# wired into the default (off) suite runner.
$(eval $(call compile_template,rv32uzkne,-march=rv32imac -mabi=ilp32))
$(eval $(call compile_template,rv32uzknd,-march=rv32imac -mabi=ilp32))
# rv32uzknh (X3): directed sha256*/sha512* per-op tests. gas 13.2 has no zknh
# -march suffix and no sha256*/sha512* mnemonics, so the tests emit explicit
# .insn forms and build under the base -march. ON-polarity only; NOT wired into
# the default (off) suite runner.
$(eval $(call compile_template,rv32uzknh,-march=rv32imac -mabi=ilp32))
$(eval $(call compile_template,rv32si,-march=rv32g -mabi=ilp32))
$(eval $(call compile_template,rv32ziscr,-march=rv32gc -mabi=ilp32)) # Added by Maxx Seminario 10/21/2025 
$(eval $(call compile_template,rv32mi,-march=rv32g -mabi=ilp32))
ifeq ($(XLEN),64)
$(eval $(call compile_template,rv64ui,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64uc,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64um,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64ua,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64uf,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64ud,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64uzfh,-march=rv64g_zfh -mabi=lp64))
$(eval $(call compile_template,rv64uzba,-march=rv64g_zba -mabi=lp64))
$(eval $(call compile_template,rv64uzbb,-march=rv64g_zbb -mabi=lp64))
$(eval $(call compile_template,rv64uzbc,-march=rv64g_zbc -mabi=lp64))
$(eval $(call compile_template,rv64uzbs,-march=rv64g_zbs -mabi=lp64))
$(eval $(call compile_template,rv64mzicbo,-march=rv64g_zicboz -mabi=lp64))
$(eval $(call compile_template,rv64si,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64ssvnapot,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,rv64mi,-march=rv64g -mabi=lp64))
$(eval $(call compile_template,hypervisor,-march=rv64gh -mabi=lp64))
endif

tests_dump = $(addsuffix .dump, $(tests))
tests_hex = $(addsuffix .hex, $(tests))
tests_out = $(addsuffix .out, $(filter rv64%,$(tests)))
tests32_out = $(addsuffix .out32, $(filter rv32%,$(tests)))
boot_junk = boot-p-boot_padded.bin boot-p-boot.rcf

run: $(tests_out) $(tests32_out)

junk += $(tests) $(tests_dump) $(tests_hex) $(tests_out) $(tests32_out) $(boot_junk)

# -------------------------------
# Groupings for clean targets
# -------------------------------

# riscv32 group: all rv32* generated files (.dump, .elf, .rcf)
riscv32_elfs  = $(filter rv32%, $(tests))
riscv32_dumps = $(addsuffix .dump, $(riscv32_elfs))
riscv32_rcfs  = $(addsuffix .rcf, $(riscv32_elfs))
riscv32_group = $(riscv32_elfs) $(riscv32_dumps) $(riscv32_rcfs)
rv32um_group = $(filter %rv32um%, $(wildcard *))
rv32uc_group = $(filter %rv32uc%, $(wildcard *))
rv32ua_group = $(filter %rv32ua%, $(wildcard *))
rv32uzba_group = $(filter %rv32uzba%, $(wildcard *))
rv32uzbb_group = $(filter %rv32uzbb%, $(wildcard *))
rv32uzbs_group = $(filter %rv32uzbs%, $(wildcard *))
rv32uzbc_group = $(filter %rv32uzbc%, $(wildcard *))
rv32ziscr_group = $(filter %rv32ziscr%, $(wildcard *))

.PHONY: riscv32-clean
riscv32-clean:
	rm -f $(riscv32_group)

riscv32um-clean :
	rm -f $(rv32um_group)

riscv32uc-clean :
	rm -f $(rv32uc_group)

riscv32ua-clean :
	rm -f $(rv32ua_group)

riscv32uzba-clean :
	rm -f $(rv32uzba_group)

riscv32uzbb-clean :
	rm -f $(rv32uzbb_group)

riscv32uzbs-clean :
	rm -f $(rv32uzbs_group)

riscv32uzbc-clean :
	rm -f $(rv32uzbc_group)

riscv32ziscr-clean :
	rm -f $(rv32ziscr_group)


	
# boot group: all boot* generated files (.dump, .elf, .rcf, .bin, _padded.bin)
boot_elfs  = $(filter boot%, $(tests)) boot-p-boot
boot_dumps = $(addsuffix .dump, $(boot_elfs))
boot_rcfs  = $(addsuffix .rcf, $(boot_elfs))
boot_bins  = $(addsuffix .bin, $(boot_elfs))
boot_padded_bins = $(addsuffix _padded.bin, $(boot_elfs))
boot_group = $(boot_elfs) $(boot_dumps) $(boot_bins) $(boot_padded_bins) $(boot_rcfs)

.PHONY: boot-clean
boot-clean:
	rm -f $(boot_group)

# periph group: all periph* generated files (.dump, .elf, .rcf)
periph_elfs  = $(filter periph%, $(tests))
periph_dumps = $(addsuffix .dump, $(periph_elfs))
periph_rcfs  = $(addsuffix .rcf, $(periph_elfs))
periph_group = $(periph_elfs) $(periph_dumps) $(periph_rcfs)

.PHONY: periph-clean
periph-clean:
	rm -f $(periph_group)

#=======================================================================
# 
#-----------------------------------------------------------------------
.PHONY: all-rcf

all-rcf: $(tests_rcf)


.PHONY: rv32ui-flash
rv32ui-flash: riscv32-clean rv32ui
	@echo "Flashing: Prepending binary header lines to rv32ui .rcf files ..."
	@echo "Files to flash: " rcf/*rv32ui*.rcf
	@./flash_prepend.sh "rcf/*rv32ui*.rcf"

.PHONY: rv32um-flash
rv32um-flash: riscv32um-clean rv32um
	@echo "Flashing: Prepending binary header lines to rv32um .rcf files ..."
	@echo "Files to flash: " rcf/*rv32um*.rcf
	@./flash_prepend.sh "rcf/*rv32um*.rcf"

.PHONY: rv32uc-flash
rv32uc-flash: riscv32uc-clean rv32uc
	@echo "Flashing: Prepending binary header lines to rv32uc .rcf files ..."
	@echo "Files to flash: " rcf/*rv32uc*.rcf
	@./flash_prepend.sh "rcf/*rv32uc*.rcf"

.PHONY: rv32ua-flash
rv32ua-flash: riscv32ua-clean rv32ua
	@echo "Flashing: Prepending binary header lines to rv32ua .rcf files ..."
	@echo "Files to flash: " rcf/*rv32ua*.rcf
	@./flash_prepend.sh "rcf/*rv32ua*.rcf"

.PHONY: rv32uzba-flash
rv32uzba-flash: riscv32uzba-clean rv32uzba
	@echo "Flashing: Prepending binary header lines to rv32uzba .rcf files ..."
	@echo "Files to flash: " rcf/*rv32uzba*.rcf
	@./flash_prepend.sh "rcf/*rv32uzba*.rcf"

.PHONY: rv32uzbb-flash
rv32uzbb-flash: riscv32uzbb-clean rv32uzbb
	@echo "Flashing: Prepending binary header lines to rv32uzbb .rcf files ..."
	@echo "Files to flash: " rcf/*rv32uzbb*.rcf
	@./flash_prepend.sh "rcf/*rv32uzbb*.rcf"

.PHONY: rv32uzbs-flash
rv32uzbs-flash: riscv32uzbs-clean rv32uzbs
	@echo "Flashing: Prepending binary header lines to rv32uzbs .rcf files ..."
	@echo "Files to flash: " rcf/*rv32uzbs*.rcf
	@./flash_prepend.sh "rcf/*rv32uzbs*.rcf"

.PHONY: rv32uzbc-flash
rv32uzbc-flash: riscv32uzbc-clean rv32uzbc
	@echo "Flashing: Prepending binary header lines to rv32uzbc .rcf files ..."
	@echo "Files to flash: " rcf/*rv32uzbc*.rcf
	@./flash_prepend.sh "rcf/*rv32uzbc*.rcf"

.PHONY: rv32ziscr-flash
rv32ziscr-flash: riscv32ziscr-clean rv32ziscr
	@echo "Flashing: Prepending binary header lines to rv32ziscr .rcf files ..."
	@echo "Files to flash: " rcf/*rv32ziscr*.rcf
	@./flash_prepend.sh "rcf/*rv32ziscr*.rcf"

.PHONY: rv32uzicond-flash
rv32uzicond-flash: rv32uzicond
	@echo "Flashing: Prepending binary header lines to rv32uzicond .rcf files ..."
	@echo "Files to flash: " rcf/*rv32uzicond*.rcf
	@./flash_prepend.sh "rcf/*rv32uzicond*.rcf"

.PHONY: rv32uzabha-flash
rv32uzabha-flash: rv32uzabha
	@echo "Flashing: Prepending binary header lines to rv32uzabha .rcf files ..."
	@echo "Files to flash: " rcf/*rv32uzabha*.rcf
	@./flash_prepend.sh "rcf/*rv32uzabha*.rcf"

.PHONY: rv32uzacas-flash
rv32uzacas-flash: rv32uzacas
	@echo "Flashing: Prepending binary header lines to rv32uzacas .rcf files ..."
	@echo "Files to flash: " rcf/*rv32uzacas*.rcf
	@./flash_prepend.sh "rcf/*rv32uzacas*.rcf"

.PHONY: rv32uzkne-flash
rv32uzkne-flash: rv32uzkne
	@echo "Flashing: Prepending binary header lines to rv32uzkne .rcf files ..."
	@echo "Files to flash: " rcf/*rv32uzkne*.rcf
	@./flash_prepend.sh "rcf/*rv32uzkne*.rcf"

.PHONY: rv32uzknd-flash
rv32uzknd-flash: rv32uzknd
	@echo "Flashing: Prepending binary header lines to rv32uzknd .rcf files ..."
	@echo "Files to flash: " rcf/*rv32uzknd*.rcf
	@./flash_prepend.sh "rcf/*rv32uzknd*.rcf"
.PHONY: rv32uzknh-flash
rv32uzknh-flash: rv32uzknh
	@echo "Flashing: Prepending binary header lines to rv32uzknh .rcf files ..."
	@echo "Files to flash: " rcf/*rv32uzknh*.rcf
	@./flash_prepend.sh "rcf/*rv32uzknh*.rcf"

.PHONY: spifem-flash
spifem-flash: spifem
	@echo "SPIFEM Test Code compiled"
	@echo *spifem*.rcf

.PHONY: periph-flash
periph-flash: periph-clean periph
	@echo "Flashing: Prepending binary header lines to periph .rcf files ..."
	@echo "Files to flash: " rcf/*periph*.rcf
	@./flash_prepend.sh "rcf/*periph*.rcf"
	@echo "Inserting test code into flash image at offset 0x2000..."
	@python3 ../python/rcf_insert.py rcf/xxxxperiph-p-SPIEM.rcf rcf/xxxxxxxspifem-p-lw.rcf rcf/xxxxperiph-p-SPIFM.rcf --index 0x800


# Target basename length for all RCF files (must match flash_prepend.sh TARGET_BASENAME_LEN).
# Reference: "xxxxxxperiph-p-NPU.rcf" = 22 characters.
TARGET_RCF_NAMELEN := 22

.PHONY: pad_rcf_filenames
pad_rcf_filenames:
	@echo "Note: Use pad_rcf_filenames_<suite> for specific test suites"

# Per-suite RCF filename padding
.PHONY: pad_rcf_filenames_%
pad_rcf_filenames_%:
	@if [ -d "$(build_dir)/$*" ] && [ -n "$$(find $(build_dir)/$* -maxdepth 1 -name '*.rcf' 2>/dev/null)" ]; then \
	  cd $(build_dir)/$* && for f in *.rcf; do \
	    if [ "$$f" = "boot-p-boot.rcf" ]; then continue; fi; \
	    stripped="$${f#$${f%%[!x]*}}"; \
	    slen=$${#stripped}; \
	    pad_count=$$(( $(TARGET_RCF_NAMELEN) - slen )); \
	    if [ $$pad_count -lt 0 ]; then pad_count=0; fi; \
	    newname="$$(printf '%*s' $$pad_count '' | tr ' ' x)$${stripped}"; \
	    if [ "$$f" != "$$newname" ]; then mv "$$f" "$$newname"; fi; \
	  done; \
	  echo "Padded RCF filenames in $(build_dir)/$* to length $(TARGET_RCF_NAMELEN)"; \
	fi

# Collect RCF files from specific test suite to central rcf/ directory
.PHONY: collect_rcf_%
collect_rcf_%:
	@if [ -d "$(build_dir)/$*" ] && [ -n "$$(find $(build_dir)/$* -maxdepth 1 -name '*.rcf' 2>/dev/null)" ]; then \
	  mkdir -p rcf; \
	  cp $(build_dir)/$*/*.rcf rcf/; \
	  echo "Copied RCF files from $(build_dir)/$* to rcf/"; \
	  $(MAKE) pad_all_rcf; \
	fi

# Pad all RCF filenames in rcf/ directory to same length
.PHONY: pad_all_rcf
pad_all_rcf:
	@if [ -d "rcf" ] && [ -n "$$(find rcf -maxdepth 1 -name '*.rcf' 2>/dev/null)" ]; then \
	  cd rcf && for f in *.rcf; do \
	    if [ "$$f" = "boot-p-boot.rcf" ]; then continue; fi; \
	    stripped="$${f#$${f%%[!x]*}}"; \
	    slen=$${#stripped}; \
	    pad_count=$$(( $(TARGET_RCF_NAMELEN) - slen )); \
	    if [ $$pad_count -lt 0 ]; then pad_count=0; fi; \
	    newname="$$(printf '%*s' $$pad_count '' | tr ' ' x)$${stripped}"; \
	    if [ "$$f" != "$$newname" ]; then mv "$$f" "$$newname"; fi; \
	  done; \
	fi

# Collect all RCF files from all test suites to central rcf/ directory
.PHONY: collect-all-rcf
collect-all-rcf:
	@echo "Collecting all RCF files to rcf/..."
	@mkdir -p rcf
	@find $(build_dir) -name '*.rcf' -exec cp {} rcf/ \;
	@$(MAKE) pad_all_rcf
	@count=$$(ls rcf/*.rcf 2>/dev/null | wc -l); \
	echo "Collected $$count RCF files to rcf/ (all names padded to same length)"

junk += $(wildcard build/*/*.rcf) $(wildcard build/*/*.bin) $(wildcard build/*/*.dump) $(wildcard build/*/*.elf) $(wildcard rcf/*.rcf)

.PHONY: clean-boot-intermediates
clean-boot-intermediates:
	rm -f boot-p-boot boot-p-boot.bin boot-p-boot_padded.bin

# Ensure boot target depends on this phony cleanup target
boot: clean-boot-intermediates

boot: clean-boot-intermediates


#------------------------------------------------------------
# Default

all: $(tests_dump) all-rcf

#------------------------------------------------------------
# Helper targets

# List all available test suites
.PHONY: list-suites
list-suites:
	@echo "Available test suites:"
	@echo "  rv32ui    - User-level integer instructions"
	@echo "  rv32um    - User-level multiply/divide"
	@echo "  rv32ua    - User-level atomic instructions"
	@echo "  rv32uc    - User-level compressed instructions"
	@echo "  rv32uf    - User-level single-precision float"
	@echo "  rv32ud    - User-level double-precision float"
	@echo "  periph    - Peripheral tests"
	@echo "  boot      - Boot tests"
	@echo "  spifem    - SPI flash tests"

# List tests in a specific suite
.PHONY: list-tests-%
list-tests-%:
	@if [ -d "$(src_dir)/$*" ]; then \
	  echo "Tests in $*:"; \
	  find $(src_dir)/$* -name "*.S" -exec basename {} .S \; | sort; \
	else \
	  echo "Test suite $* not found"; \
	fi

# Clean specific test suite
.PHONY: clean-%
clean-%:
	@echo "Cleaning build artifacts for $*..."
	@rm -rf $(build_dir)/$*
	@echo "Cleaned $(build_dir)/$*"

# Clean all build artifacts
.PHONY: clean-all
clean-all:
	@echo "Cleaning all build artifacts..."
	@rm -rf $(build_dir)/* rcf/*
	@echo "Cleaned $(build_dir)/ and rcf/"
	@echo "Cleaned $(build_dir)/"

#------------------------------------------------------------
# Clean up

clean:
	rm -rf $(junk) $(build_dir)/* rcf/*
