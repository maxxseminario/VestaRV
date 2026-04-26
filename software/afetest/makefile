# afetest Firmware Makefile
# Minimal AFE bring-up test for the Myshkin chip.
# Cloned from software/blinky/makefile -- only TARGET differs.

TARGET = afetest

# Project source files (start.S MUST be first)
SRC_SOURCES = start.S main.c
LIB_SOURCES =
EXTENSIONS = ima

# Directories
LIB_DIR = ../commune
PLATFORM_DIR = ../../platform/gcc/lib
TOOLS_DIR = ../../tools/build
LD_DIR = $(TOOLS_DIR)/linker-scripts
LD_SCRIPT = $(LD_DIR)/MCU.ld
LIB_SRC_DIR = $(LIB_DIR)/src
LIB_INC_DIR = $(LIB_DIR)/include
SRC_DIR = ./src
INC_DIR = ./include
OBJ_DIR = ./obj
BIN_DIR = ./bin
RCF_DIR = ./rcf

# Scripts
PYTHON_DIR = $(TOOLS_DIR)/scripts
FLASH_SCRIPT = ../../verification/isa/flash_prepend.sh

# Memory configuration (platform-generated if available, otherwise tools/build)
ifneq (,$(wildcard $(PLATFORM_DIR)/linker/memory.x))
    PLATFORM_LD_DIR = $(PLATFORM_DIR)/linker
else
    PLATFORM_LD_DIR = $(LD_DIR)
endif
RAM_START = `cat $(PLATFORM_LD_DIR)/RAM_START.txt 2>/dev/null || cat $(LD_DIR)/RAM_START.txt`
RAM_SIZE  = `cat $(PLATFORM_LD_DIR)/RAM_SIZE.txt  2>/dev/null || cat $(LD_DIR)/RAM_SIZE.txt`
ROM_START = `cat $(PLATFORM_LD_DIR)/ROM_START.txt 2>/dev/null || cat $(LD_DIR)/ROM_START.txt`
ROM_SIZE  = `cat $(PLATFORM_LD_DIR)/ROM_SIZE.txt  2>/dev/null || cat $(LD_DIR)/ROM_SIZE.txt`
MEM_SIZE   = $(shell printf "%d" 0x14000)
WORD_COUNT = $(shell echo $$(( $(MEM_SIZE) / 4 )))

# Toolchain
ifndef RISCV_TOOLCHAIN_DIR
$(error RISCV_TOOLCHAIN_DIR is not set. Please set it to your RISC-V toolchain path)
endif
TOOLCHAIN_DIR = $(RISCV_TOOLCHAIN_DIR)
PREFIX  = $(TOOLCHAIN_DIR)/bin/riscv-none-elf-
CC      = $(PREFIX)gcc
OBJCOPY = $(PREFIX)objcopy
OBJDUMP = $(PREFIX)objdump
SIZE    = $(PREFIX)size

ARCH = rv32$(EXTENSIONS)
ABI  = ilp32

CFLAGS  = -march=$(ARCH) -mabi=$(ABI) -Wall -O2 -g \
          -I$(INC_DIR) -I$(PLATFORM_DIR)/include -I$(LIB_INC_DIR) \
          -ffreestanding -nostdlib
LDFLAGS = -march=$(ARCH) -mabi=$(ABI) -T$(LD_SCRIPT) -nostartfiles -nostdlib \
          -Wl,-Map=$(BIN_DIR)/$(TARGET).map \
          -L$(PLATFORM_LD_DIR) -L$(LD_DIR)

SRC_FILES = $(addprefix $(SRC_DIR)/,$(SRC_SOURCES))
LIB_FILES = $(addprefix $(LIB_SRC_DIR)/,$(LIB_SOURCES))
SRC_OBJS  = $(patsubst $(SRC_DIR)/%.S,$(OBJ_DIR)/%.o,$(patsubst $(SRC_DIR)/%.c,$(OBJ_DIR)/%.o,$(SRC_FILES)))
LIB_OBJS  = $(patsubst $(LIB_SRC_DIR)/%.c,$(OBJ_DIR)/%.o,$(filter %.c,$(LIB_FILES)))
ALL_OBJS  = $(SRC_OBJS) $(LIB_OBJS)

.PHONY: all clean help

help:
	@echo "$(TARGET) Build Targets:"
	@echo "  make all   - Build ELF, binary, hex, dump, and RCF with flash headers"
	@echo "  make clean - Remove all build artifacts"

all: $(BIN_DIR)/$(TARGET).hex $(BIN_DIR)/$(TARGET).dump $(RCF_DIR)/*$(TARGET).rcf
	@echo ""
	@echo "Build complete: $(TARGET)"
	@$(SIZE) $(BIN_DIR)/$(TARGET).elf
	@echo "Intel hex file: $(BIN_DIR)/$(TARGET).hex"
	@echo "RCF file with flash headers ready for simulation"

$(BIN_DIR)/$(TARGET).elf: $(ALL_OBJS) | $(BIN_DIR)
	$(CC) $(LDFLAGS) -o $@ $(ALL_OBJS)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c | $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ_DIR)/%.o: $(LIB_SRC_DIR)/%.c | $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.S | $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BIN_DIR)/$(TARGET).bin: $(BIN_DIR)/$(TARGET).elf
	$(OBJCOPY) -O binary $< $@

$(BIN_DIR)/$(TARGET).hex: $(BIN_DIR)/$(TARGET).elf
	$(OBJCOPY) -O ihex $< $@

$(BIN_DIR)/$(TARGET).dump: $(BIN_DIR)/$(TARGET).elf
	$(OBJDUMP) -D $< > $@

$(BIN_DIR)/$(TARGET)_padded.bin: $(BIN_DIR)/$(TARGET).bin
	@echo "Creating padded binary ($(MEM_SIZE) bytes)..."
	@dd if=/dev/zero of=$@ bs=$(MEM_SIZE) count=1 2>/dev/null
	@dd if=$< of=$@ bs=1 seek=0 conv=notrunc 2>/dev/null

$(RCF_DIR)/$(TARGET).rcf: $(BIN_DIR)/$(TARGET)_padded.bin | $(RCF_DIR)
	@echo "Generating RCF file ($(WORD_COUNT) words)..."
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
	if [ $$lines -ne $(WORD_COUNT) ]; then \
	    echo "Error: $@ has $$lines lines (expected $(WORD_COUNT))"; \
	    exit 1; \
	fi
	@echo "RCF file created: $@"

$(RCF_DIR)/*$(TARGET).rcf: $(RCF_DIR)/$(TARGET).rcf
	@echo "Adding SPI flash headers to RCF file..."
	@$(FLASH_SCRIPT) "$(RCF_DIR)/$(TARGET).rcf" 22
	@echo "Flash headers added successfully"

$(OBJ_DIR): ; mkdir -p $@
$(BIN_DIR): ; mkdir -p $@
$(RCF_DIR): ; mkdir -p $@

clean:
	rm -rf $(OBJ_DIR) $(BIN_DIR) $(RCF_DIR)
