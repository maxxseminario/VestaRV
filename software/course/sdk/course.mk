# course.mk -- VestaRV course SDK build template (include-style).
#
# A lab makefile sets TARGET and SRC_SOURCES, then includes this file:
#
#     TARGET       = lab01_hello
#     SRC_SOURCES  = src/main.c          # student sources, relative to the lab
#     include ../../../sdk/course.mk
#
# Produces (like software/blinky): ELF -> bin -> padded bin -> rcf -> rcf with
# SPI-flash load/execute headers (via verification/isa/flash_prepend.sh, 22).
# Targets: all (default), sim, deploy, clean.
#
# Toolchain: riscv-none-elf- on PATH; -march=rv32ima -mabi=ilp32.

# --- locate the SDK / repo from this file's own path -----------------------
SDK_DIR    := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
COURSE_DIR := $(abspath $(SDK_DIR)/..)
REPO       := $(abspath $(SDK_DIR)/../../..)
COMMUNE    := $(REPO)/software/commune
FLASH_SCRIPT := $(REPO)/verification/isa/flash_prepend.sh
RUN_SIM      := $(SDK_DIR)/run_sim.sh

# --- toolchain -------------------------------------------------------------
PREFIX  ?= riscv-none-elf-
CC      := $(PREFIX)gcc
OBJCOPY := $(PREFIX)objcopy
OBJDUMP := $(PREFIX)objdump
SIZE    := $(PREFIX)size

ARCH = rv32ima
ABI  = ilp32

# --- directories -----------------------------------------------------------
OBJ_DIR = ./obj
BIN_DIR = ./bin
RCF_DIR = ./rcf
INC_DIR = ./include

# --- flags -----------------------------------------------------------------
# -ffreestanding/-nostdlib: bare metal, no host libc. gc-sections drops the
# unused (float) commune console helpers so no soft-float libgcc refs survive.
# -fno-builtin-{printf,puts}: keep the compiler from rewriting our calls.
# -O2 (not -Os) is REQUIRED: it lowers constant integer division to a
# magic-multiply, so the compiler never emits the hardware divu/remu
# instructions -- those have a result-hazard bug on this chip (see the SDK
# README "Known issues"). Student code that divides by a runtime value would
# still emit divu; keep divisors constant.
CFLAGS_BASE = -march=$(ARCH) -mabi=$(ABI) -O2 -g -Wall \
              -ffreestanding -nostdlib -ffunction-sections -fdata-sections \
              -fno-builtin-printf -fno-builtin-puts

# Course/student translation units: SDK API (course.h + chip.h) + lab include.
CFLAGS = $(CFLAGS_BASE) -I$(INC_DIR) -I$(SDK_DIR)/course_lib

LDFLAGS = -march=$(ARCH) -mabi=$(ABI) -nostartfiles -nostdlib \
          -T$(SDK_DIR)/course.ld -Wl,--gc-sections \
          -Wl,-Map=$(BIN_DIR)/$(TARGET).map
LDLIBS = -lgcc

# --- objects ---------------------------------------------------------------
SRC_OBJS = $(patsubst %.c,$(OBJ_DIR)/%.o,$(patsubst %.S,$(OBJ_DIR)/%.o,$(SRC_SOURCES)))
ALL_OBJS = $(OBJ_DIR)/crt0.o $(SRC_OBJS) $(OBJ_DIR)/course.o

# padded image (matches software/blinky: full window, zero-filled)
MEM_SIZE   = $(shell printf "%d" 0x14000)
WORD_COUNT = $(shell echo $$(( $(MEM_SIZE) / 4 )))

.PHONY: all sim deploy clean help
.PRECIOUS: $(RCF_DIR)/$(TARGET).rcf

all: $(BIN_DIR)/$(TARGET).dump $(RCF_DIR)/.$(TARGET).flashed
	@echo ""
	@echo "Build complete: $(TARGET)"
	@$(SIZE) $(BIN_DIR)/$(TARGET).elf
	@echo "Flash image (SPI headers added): $(wildcard $(RCF_DIR)/*$(TARGET).rcf)"

# --- compile ---------------------------------------------------------------
$(OBJ_DIR)/crt0.o: $(SDK_DIR)/crt0.S | $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ_DIR)/course.o: $(SDK_DIR)/course_lib/course.c | $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ_DIR)/%.o: %.c | $(OBJ_DIR)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ_DIR)/%.o: %.S | $(OBJ_DIR)
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

# --- link / image ----------------------------------------------------------
$(BIN_DIR)/$(TARGET).elf: $(ALL_OBJS) | $(BIN_DIR)
	$(CC) $(LDFLAGS) -o $@ $(ALL_OBJS) $(LDLIBS)

$(BIN_DIR)/$(TARGET).dump: $(BIN_DIR)/$(TARGET).elf
	$(OBJDUMP) -D $< > $@

$(BIN_DIR)/$(TARGET).bin: $(BIN_DIR)/$(TARGET).elf
	$(OBJCOPY) -O binary $< $@

$(BIN_DIR)/$(TARGET)_padded.bin: $(BIN_DIR)/$(TARGET).bin
	@dd if=/dev/zero of=$@ bs=$(MEM_SIZE) count=1 2>/dev/null
	@dd if=$< of=$@ bs=1 seek=0 conv=notrunc 2>/dev/null

# raw rcf: one 32-bit word per line as binary text (MSB..LSB), WORD_COUNT lines
$(RCF_DIR)/$(TARGET).rcf: $(BIN_DIR)/$(TARGET)_padded.bin | $(RCF_DIR)
	@od -v -An -tx4 -w4 $< | awk '{ \
	    hex=$$1; bin=""; \
	    for (i=1;i<=8;i++){ c=substr(hex,i,1); \
	        if(c=="0")bin=bin"0000"; else if(c=="1")bin=bin"0001"; \
	        else if(c=="2")bin=bin"0010"; else if(c=="3")bin=bin"0011"; \
	        else if(c=="4")bin=bin"0100"; else if(c=="5")bin=bin"0101"; \
	        else if(c=="6")bin=bin"0110"; else if(c=="7")bin=bin"0111"; \
	        else if(c=="8")bin=bin"1000"; else if(c=="9")bin=bin"1001"; \
	        else if(c=="a")bin=bin"1010"; else if(c=="b")bin=bin"1011"; \
	        else if(c=="c")bin=bin"1100"; else if(c=="d")bin=bin"1101"; \
	        else if(c=="e")bin=bin"1110"; else if(c=="f")bin=bin"1111"; } \
	    print bin; }' > $@
	@lines=$$(wc -l < $@); \
	 if [ $$lines -ne $(WORD_COUNT) ]; then \
	    echo "Error: $@ has $$lines lines (expected $(WORD_COUNT))"; exit 1; fi
	@echo "RCF written: $@ ($(WORD_COUNT) words)"

# add SPI-flash load/execute headers + x-pad the basename to 22 chars.
# stamp .$(TARGET).flashed tracks that the (idempotent) header pass has run.
$(RCF_DIR)/.$(TARGET).flashed: $(RCF_DIR)/$(TARGET).rcf
	$(FLASH_SCRIPT) "$(RCF_DIR)/$(TARGET).rcf" 22
	@touch $@
	@echo "Flash headers added (basename padded to 22 chars)."

# --- run in the instructor simulator --------------------------------------
sim: all
	@img="$(wildcard $(RCF_DIR)/*$(TARGET).rcf)"; \
	 if [ -z "$$img" ]; then echo "no flashed rcf for $(TARGET)"; exit 1; fi; \
	 echo "Simulating $$img ..."; \
	 "$(RUN_SIM)" "$$img"

# --- deploy to hardware (platform TBD) ------------------------------------
deploy: all
	@echo "hardware platform TBD -- students will flash the SPI boot flash"
	@echo "image: $(wildcard $(RCF_DIR)/*$(TARGET).rcf)"

$(OBJ_DIR) $(BIN_DIR) $(RCF_DIR):
	@mkdir -p $@

clean:
	rm -rf $(OBJ_DIR) $(BIN_DIR) $(RCF_DIR)

help:
	@echo "$(TARGET) targets: all (build image), sim (instructor sim run),"
	@echo "                   deploy (flash to board -- TBD), clean"
