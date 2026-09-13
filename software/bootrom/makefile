# VestaRV: the single-hart boot ROM image.
# EXTENSIONS below is the ISA the ROM is compiled for; the multi-hart ROM at
# ../bootrom_mp reads its own from isa.bzl instead.
# Name of the target, without extension; it must exist in SRC_DIR.
TARGET      = flashboot

# Project sources from SRC_DIR and shared library sources from LIB_DIR/src.
# start.S must be first in SRC_SOURCES so it lands at the reset address.
SRC_SOURCES	= start.S main.c rv4th.c uart.c spi.c flash_memory.c
LIB_SOURCES	= 
EXTENSIONS	= ic

# Shared libraries and the linker script.
LIB_DIR		= ../commune
LD_DIR		= ../../tools/build/linker-scripts
LD_SCRIPT	= $(LD_DIR)/MCU-bootrom.ld

# The MCU library tree.
LIB_SRC_DIR = $(LIB_DIR)/src
LIB_INC_DIR = $(LIB_DIR)/include

# Project directories.
SRC_DIR		= ./src
INC_DIR		= ./include
OBJ_DIR		= ./obj
BIN_DIR		= ./bin

# RAM and ROM extents, read from the linker-script directory at recipe time.
RAM_START	= `cat $(LD_DIR)/RAM_START.txt`
RAM_SIZE	= `cat $(LD_DIR)/RAM_SIZE.txt`
ROM_START	= `cat $(LD_DIR)/ROM_START.txt`
ROM_SIZE	= `cat $(LD_DIR)/ROM_SIZE.txt`

# Compiler flags. -flto drops every function the main path and the interrupts do
# not reach, which is what keeps the image inside the ROM; an interrupt handler
# must therefore carry its __attribute__ or it is discarded.
OPTIMIZATION_FLAGS = -Os -flto
#OPTIMIZATION_FLAGS = -flto
ARCH	= rv32$(EXTENSIONS)

# -fno-tree-loop-distribute-patterns declines gcc's transform of ordinary loops in
# rv4th.c into calls to memset and memmove. Neither is called by name anywhere in
# this program, so declining the transform preserves behaviour by construction and
# keeps the libgcc string routines out of the image. It must appear on the link
# line too: with -flto the loop passes run during link-time codegen.
SIZE_FLAGS	= -fno-tree-loop-distribute-patterns

CFLAGS	= -Werror -Wall -Wunused -march=$(ARCH) $(OPTIMIZATION_FLAGS) $(SIZE_FLAGS) -D__nostdlib__ -I $(GCC_INC_DIR) -I $(INC_DIR) -I $(LIB_INC_DIR) -g
LFLAGS	= -lgcc -march=$(ARCH) $(OPTIMIZATION_FLAGS) $(SIZE_FLAGS) -nostartfiles -Wl,-Bstatic,-T,$(LD_SCRIPT),-Map,$(BIN_DIR)/$(TARGET).map,--cref -L $(LD_DIR) -g

# Toolchain. The path below is the openSUSE VM on poseidon.

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

SRC_OBJECTS	= $(patsubst %,%.src.o,$(SRC_SOURCES))
LIB_OBJECTS	= $(patsubst %,%.lib.o,$(LIB_SOURCES))

SOURCES		= $(patsubst %,$(SRC_DIR)/%,$(SRC_SOURCES)) $(patsubst %,$(LIB_DIR)/%,$(LIB_SOURCES))
OBJECTS     = $(patsubst %,$(OBJ_DIR)/%,$(SRC_OBJECTS)) $(patsubst %,$(OBJ_DIR)/%,$(LIB_OBJECTS))

HEADERS     =  $(wildcard $(GCC_INC_DIR)/*.h) $(wildcard $(LIB_INC_DIR)/*.h) $(wildcard $(INC_DIR)/*.h)

# Compilation rules.

.PHONY: all
all: $(BIN_DIR)/$(TARGET).hex $(BIN_DIR)/$(TARGET).lst $(BIN_DIR)/$(TARGET).dump $(BIN_DIR)/rom.rcf

# Project source files to object files.
$(OBJ_DIR)/%.src.o: $(SRC_DIR)/% $(HEADERS)
	@echo ""
	@echo "> Compiling project source file $<"
	@echo ""
	$(CC) -c $(CFLAGS) $< -o $@
	
# Library source files to object files.
$(OBJ_DIR)/%.lib.o: $(LIB_SRC_DIR)/% $(HEADERS)
	@echo ""
	@echo "> Compiling library source file $<"
	@echo ""
	$(CC) -c $(CFLAGS) $< -o $@

# Link the objects into the ELF.
$(BIN_DIR)/$(TARGET).elf: $(OBJECTS)
	@echo ""
	@echo "> Linking $@"
	@echo ""
	$(CC) $(LFLAGS) $(OBJECTS) -o $@

# ELF to Intel hex.
$(BIN_DIR)/%.hex: $(BIN_DIR)/%.elf
	@echo ""
	@echo "> Creating output hex file $@"
	@echo ""
	$(OBJCOPY) -O ihex $< $@

# ELF to the C-to-assembly listing.
$(BIN_DIR)/%.lst: $(BIN_DIR)/%.elf
	@echo ""
	@echo "> Creating C-to-assembly lst file $@"
	@echo ""
	$(OBJDUMP) --prefix-addresses --show-raw-insn -SrlD $< > $@
	@make memory -s

# The HDL memory initialisation file.
$(BIN_DIR)/rom.rcf: $(BIN_DIR)/$(TARGET).hex
	@echo ""
	@echo "> Creating boot ROM RCF file $@"
	@echo ""
	$(RCF) $< $@ $(ROM_START) $(ROM_SIZE) 32 --default 0x00000000

# ELF to the disassembly dump, for debugging.
$(BIN_DIR)/$(TARGET).dump: $(BIN_DIR)/$(TARGET).elf
	@echo ""
	@echo "> Creating disassembly dump file $@"
	@echo ""
	$(OBJDUMP) --disassemble-all --disassemble-zeroes \
		--section=.text --section=.text.startup --section=.text.init \
		--section=.data --section=.rodata --section=.bss \
		--prefix-addresses --show-raw-insn \
		$< > $@


# rv4th.c compiled without LTO, so `make bin/rv4th.dump` gives a disassembly in
# which every word is still present.
$(OBJ_DIR)/rv4th_for_dump.o: $(SRC_DIR)/rv4th.c $(HEADERS)
	@echo ""
	@echo "> Compiling rv4th.c without LTO for disassembly"
	@echo ""
	$(CC) -c -march=$(ARCH) -Os -D__nostdlib__ \
		-I $(GCC_INC_DIR) -I $(INC_DIR) -I $(LIB_INC_DIR) \
		-g $(SRC_DIR)/rv4th.c -o $@

# The rv4th dump, executable sections only.
$(BIN_DIR)/rv4th.dump: $(OBJ_DIR)/rv4th_for_dump.o
	@echo ""
	@echo "> Creating rv4th executable code dump"
	@echo ""
	$(OBJDUMP) --disassemble-all --prefix-addresses --show-raw-insn \
		--section=.text --section=.text.* \
		$(OBJ_DIR)/rv4th_for_dump.o > $@
	@echo "rv4th dump created with `grep -c '^[0-9a-f]* <' $@` functions"

	
# Helper rules.

.PHONY: tidy
tidy:
	@echo ""
	@echo "> Tidying up"
	@echo ""
	find $(OBJ_DIR) -type f -regextype posix-extended -iregex '.*\.(o)' -delete
	find $(BIN_DIR) -type f -regextype posix-extended -iregex '.*\.(map|xout|out|d|lst|map)' -delete

# Remove every non-source compilation artifact.
.PHONY: clean
clean: tidy
	@echo ""
	@echo "> Cleaning"
	@echo ""
	find $(BIN_DIR) -type f -regextype posix-extended -iregex '.*\.(hex|elf|rcf|hdlmem|dump)' -delete

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

# Create the directory hierarchy a fresh checkout does not carry.
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
