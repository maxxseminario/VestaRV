# Name of target (without file extension, must be in SRC_DIR)
TARGET      = flashboot

# Project Sources (file names to use in SRC_DIR) and Global Library Sources (file names to use from LIB_DIR/src)
# WARNING: start.S must be first in the SRC_SOURCES list. This is to ensure it is placed in the appropriate memory location
SRC_SOURCES	= start.S main.c rv4th.c uart.c spi.c flash_memory.c
LIB_SOURCES	= 

# Chip Global Libraries and Linker Script
LIB_DIR		= ../commune
LD_DIR		= ../../tools/build/linker-scripts
LD_SCRIPT	= $(LD_DIR)/MCU-bootrom.ld

# MCU Libraries
LIB_SRC_DIR = $(LIB_DIR)/src
LIB_INC_DIR = $(LIB_DIR)/include

# Project Files Source
SRC_DIR		= ./src
INC_DIR		= ./include
OBJ_DIR		= ./obj
BIN_DIR		= ./bin

# RAM and ROM Sizes
RAM_START	= `cat $(LD_DIR)/RAM_START.txt`
RAM_SIZE	= `cat $(LD_DIR)/RAM_SIZE.txt`
ROM_START	= `cat $(LD_DIR)/ROM_START.txt`
ROM_SIZE	= `cat $(LD_DIR)/ROM_SIZE.txt`

# Compiler flags
# Unused: Generate assembly listings for each C file: -Wa,-ahls=$*.lst
# Note: the -flto flag initiates link time optimization. It seems to force the compiler/linker to include only the functions explicitly used by the main function in the final output file. It also seems to require interrupts to have the __attribute__ prefix. This means that only the functions that are called by the main function and the interrupts will be added to the final binary file.
OPTIMIZATION_FLAGS = -Os -flto
#OPTIMIZATION_FLAGS = -flto

# ISA string and size-coupled flags: single authority, read from isa.bzl.
# BUILD.bazel loads that same file, so the make and bazel build paths cannot
# disagree about what the mask ROM is compiled for.
# There used to be an EXTENSIONS variable here and a march= attribute there,
# and flipping one of them left the other silently building the old ISA.
ISA_BZL	= isa.bzl
ARCH	:= $(shell sed -n 's/^BOOTROM_MARCH = "\([^"]*\)".*/\1/p' $(ISA_BZL))
SIZE_FLAGS	:= $(shell sed -n 's/^BOOTROM_SIZE_COPTS = \[\(.*\)\].*/\1/p' $(ISA_BZL) | tr -d '",')
ifeq ($(strip $(ARCH)),)
$(error could not read BOOTROM_MARCH out of $(ISA_BZL))
endif

CFLAGS	= -Werror -Wall -Wunused -march=$(ARCH) $(OPTIMIZATION_FLAGS) $(SIZE_FLAGS) -D__nostdlib__ -I $(GCC_INC_DIR) -I $(INC_DIR) -I $(LIB_INC_DIR) -g
LFLAGS	= -lgcc -march=$(ARCH) $(OPTIMIZATION_FLAGS) $(SIZE_FLAGS) -nostartfiles -Wl,-Bstatic,-T,$(LD_SCRIPT),-Map,$(BIN_DIR)/$(TARGET).map,--cref -L $(LD_DIR) -g

##################################################
### TOOLCHAIN DIRECTORIES
##################################################
# ifdef RISCV
# 	RISCV_DIR = ${RISCV}
# else
# 	RISCV_DIR = /opt/riscv
# endif

# For openSUSE VM on Poseidon
RISCV_DIR	= ~/riscv-toolchain/xpack-riscv-none-elf-gcc-13.2.0-2

RISCV_TOOLCHAIN_DIR	= $(RISCV_DIR)
PYTHON_DIR	= ../../tools/build/scripts
GCC_INC_DIR	= $(RISCV_TOOLCHAIN_DIR)/riscv-none-elf/include
CC			= $(RISCV_TOOLCHAIN_DIR)/bin/riscv-none-elf-gcc
LD			= $(RISCV_TOOLCHAIN_DIR)/bin/riscv-none-elf-ld
AR			= $(RISCV_TOOLCHAIN_DIR)/bin/riscv-none-elf-ar
AS			= $(RISCV_TOOLCHAIN_DIR)/bin/riscv-none-elf-gcc
GASP		= $(RISCV_TOOLCHAIN_DIR)/bin/riscv-none-elf-gasp
NM			= $(RISCV_TOOLCHAIN_DIR)/bin/riscv-none-elf-nm
OBJCOPY		= $(RISCV_TOOLCHAIN_DIR)/bin/riscv-none-elf-objcopy
OBJDUMP		= $(RISCV_TOOLCHAIN_DIR)/bin/riscv-none-elf-objdump
RANLIB		= $(RISCV_TOOLCHAIN_DIR)/bin/riscv-none-elf-ranlib
STRIP		= $(RISCV_TOOLCHAIN_DIR)/bin/riscv-none-elf-strip
SIZE		= $(RISCV_TOOLCHAIN_DIR)/bin/riscv-none-elf-size
READELF		= $(RISCV_TOOLCHAIN_DIR)/bin/riscv-none-elf-readelf
GDB			= $(RISCV_TOOLCHAIN_DIR)/bin/riscv-none-elf-gdb
MAKETXT		= srec_cat
CP			= cp -p
RM			= rm -f
MV			= mv
MKDIR		= mkdir
RCF			= $(PYTHON_DIR)/ihex2rcf.py

# Dependencies
SRC_OBJECTS	= $(patsubst %,%.src.o,$(SRC_SOURCES))
LIB_OBJECTS	= $(patsubst %,%.lib.o,$(LIB_SOURCES))

SOURCES		= $(patsubst %,$(SRC_DIR)/%,$(SRC_SOURCES)) $(patsubst %,$(LIB_DIR)/%,$(LIB_SOURCES))
OBJECTS     = $(patsubst %,$(OBJ_DIR)/%,$(SRC_OBJECTS)) $(patsubst %,$(OBJ_DIR)/%,$(LIB_OBJECTS))

HEADERS     =  $(wildcard $(GCC_INC_DIR)/*.h) $(wildcard $(LIB_INC_DIR)/*.h) $(wildcard $(INC_DIR)/*.h) $(ISA_BZL)

##################################################
### COMPILATION RULES
##################################################

# Make the entire project
.PHONY: all
all: $(BIN_DIR)/$(TARGET).hex $(BIN_DIR)/$(TARGET).lst $(BIN_DIR)/$(TARGET).dump $(BIN_DIR)/rom.rcf

# Step 1: Src files to object files 
# Compile project source files from the project source directory into object files
$(OBJ_DIR)/%.src.o: $(SRC_DIR)/% $(HEADERS)
	@echo ""
	@echo "> Compiling project source file $<"
	@echo ""
	$(CC) -c $(CFLAGS) $< -o $@
	
# Step 1b: Lib files to object files
# Compile library source files from the library source directory into object files
$(OBJ_DIR)/%.lib.o: $(LIB_SRC_DIR)/% $(HEADERS)
	@echo ""
	@echo "> Compiling library source file $<"
	@echo ""
	$(CC) -c $(CFLAGS) $< -o $@

# Step 2: Object files to elf / binary files
# Link object files together to create binary elf output file, show memory usage
$(BIN_DIR)/$(TARGET).elf: $(OBJECTS)
	@echo ""
	@echo "> Linking $@"
	@echo ""
	$(CC) $(LFLAGS) $(OBJECTS) -o $@

# Step 3: elf to hex file
# Convert elf file into Intel hex file
$(BIN_DIR)/%.hex: $(BIN_DIR)/%.elf
	@echo ""
	@echo "> Creating output hex file $@"
	@echo ""
	$(OBJCOPY) -O ihex $< $@

# Step 4: elf to lst file (list of data)
# Create assembly lst file
$(BIN_DIR)/%.lst: $(BIN_DIR)/%.elf
	@echo ""
	@echo "> Creating C-to-assembly lst file $@"
	@echo ""
	$(OBJDUMP) --prefix-addresses --show-raw-insn -SrlD $< > $@
	@make memory -s

# Step 4b: Create HDL memory initialization file
# Create ROM RCF file. M12: pure objcopy+od+awk (the verification/isa recipe)
# instead of ihex2rcf.py — this machine's python3 (Calibre aoj_cal wrapper)
# has no intelhex module. Output format is identical: ROM_SIZE/4 lines of
# 32 '0'/'1' chars, line N = the little-endian word at ROM byte 4*N.
#
# 16384/4096 -> 8192/2048 on 2026-08-23. The ROM macro at rom0 is now
# rom2k_hvt_pg, 2048 x 32, so a 4096-line file is no longer an image of the
# part: the padding width here and the ROM's depth are the same number, and
# the line check below is what keeps them the same number.
$(BIN_DIR)/rom.rcf: $(BIN_DIR)/$(TARGET).elf
	@echo ""
	@echo "> Creating boot ROM RCF file $@"
	@echo ""
	$(OBJCOPY) -O binary --gap-fill=0x00 $< $(BIN_DIR)/$(TARGET).rom.bin
	dd if=/dev/zero of=$(BIN_DIR)/$(TARGET).rom_padded.bin bs=8192 count=1 2>/dev/null
	dd if=$(BIN_DIR)/$(TARGET).rom.bin of=$(BIN_DIR)/$(TARGET).rom_padded.bin bs=1 conv=notrunc 2>/dev/null
	@od -v -An -tx4 -w4 $(BIN_DIR)/$(TARGET).rom_padded.bin | awk '\
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
	if [ $$lines -ne 2048 ]; then \
	    echo "Error: $@ has $$lines lines (expected 2048)"; \
	    exit 1; \
	fi

# Step 5: elf to dump file (for debugging purposes)
# Create disassembly dump file - Maxx Seminario 09/27/2025
# $(BIN_DIR)/$(TARGET).dump: $(BIN_DIR)/$(TARGET).elf
# 	@echo ""
# 	@echo "> Creating disassembly dump file $@"
# 	@echo ""
# 	$(OBJDUMP) -D -S --prefix-addresses --show-raw-insn $< > $@
# Create disassembly dump file (explicit rule)
$(BIN_DIR)/$(TARGET).dump: $(BIN_DIR)/$(TARGET).elf
	@echo ""
	@echo "> Creating disassembly dump file $@"
	@echo ""
	$(OBJDUMP) --disassemble-all --disassemble-zeroes \
		--section=.text --section=.text.startup --section=.text.init \
		--section=.data --section=.rodata --section=.bss \
		--prefix-addresses --show-raw-insn \
		$< > $@


# Added rule to dump just the 4th interpreter object file - Maxx Seminario 09/27/2025
# Run as: make bin/rv4th.dump
# Special compilation of rv4th.c without LTO for clean disassembly
$(OBJ_DIR)/rv4th_for_dump.o: $(SRC_DIR)/rv4th.c $(HEADERS)
	@echo ""
	@echo "> Compiling rv4th.c without LTO for disassembly"
	@echo ""
	$(CC) -c -march=$(ARCH) -Os $(SIZE_FLAGS) -D__nostdlib__ \
		-I $(GCC_INC_DIR) -I $(INC_DIR) -I $(LIB_INC_DIR) \
		-g $(SRC_DIR)/rv4th.c -o $@

# Create clean rv4th dump with only executable code
$(BIN_DIR)/rv4th.dump: $(OBJ_DIR)/rv4th_for_dump.o
	@echo ""
	@echo "> Creating rv4th executable code dump"
	@echo ""
	$(OBJDUMP) --disassemble-all --prefix-addresses --show-raw-insn \
		--section=.text --section=.text.* \
		$(OBJ_DIR)/rv4th_for_dump.o > $@
	@echo "rv4th dump created with `grep -c '^[0-9a-f]* <' $@` functions"

	
##################################################
### HELPER RULES
##################################################

# Remove junk
.PHONY: tidy
tidy:
	@echo ""
	@echo "> Tidying up"
	@echo ""
	find $(OBJ_DIR) -type f -regextype posix-extended -iregex '.*\.(o)' -delete
	find $(BIN_DIR) -type f -regextype posix-extended -iregex '.*\.(map|xout|out|d|lst|map)' -delete

# Remove all non-source compilation artifacts
.PHONY: clean
clean: tidy
	@echo ""
	@echo "> Cleaning"
	@echo ""
	find $(BIN_DIR) -type f -regextype posix-extended -iregex '.*\.(hex|elf|rcf|hdlmem|dump)' -delete

# Print the memory usage of the target
.PHONY: memory
memory:
	@echo ""
	@echo "> Memory usage for $(TARGET)"
	@echo "    text is length of program in bytes (decimal)"
	@echo "    data is length of global vars in bytes (decimal)"
	@echo "    bss is length of uninitialized vars in bytes (decimal)"
	@echo "    dec is combined memory usage in bytes (decimal)"
	@echo ""
	$(SIZE) $(BIN_DIR)/$(TARGET).elf --format=berkeley --radix=10

# Set up the folder hierarchy
.PHONY: setup
setup:
	@if [ ! -d $(SRC_DIR) ] ; then $(MKDIR) $(SRC_DIR) ; fi
	@if [ ! -d $(INC_DIR) ] ; then $(MKDIR) $(INC_DIR) ; fi
	@if [ ! -d $(OBJ_DIR) ] ; then $(MKDIR) $(OBJ_DIR) ; fi
	@if [ ! -d $(BIN_DIR) ] ; then $(MKDIR) $(BIN_DIR) ; fi
	@echo "!.gitignore" > $(SRC_DIR)/.gitignore
	@echo "!.gitignore" > $(INC_DIR)/.gitignore
	@echo "*" > $(OBJ_DIR)/.gitignore && echo "!.gitignore" >> $(OBJ_DIR)/.gitignore
	@echo "!.gitignore" > $(BIN_DIR)/.gitignore
