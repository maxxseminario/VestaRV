# Name of target (without file extension, must be in SRC_DIR)
TARGET      = main

# Project Sources (file names to use in SRC_DIR) and Global Library Sources (file names to use from LIB_DIR/src)
# WARNING: start.S MUST come first in LIB_SOURCES. This because the start and the IRQ_master_handler_asm functions need to appear in exactly the right memory location
SRC_SOURCES	= main.c rv4th.c
# LIB_SOURCES	= start.S irq.c uart.c spi.c flash_memory.c lzw.c
LIB_SOURCES	= uart.c
EXTENSIONS	= im

USER_DEFINES	= 

# Chip Global Libraries and Linker Script
LIB_DIR		= ../lib/src
LD_DIR		= $(LIB_DIR)/env/p
LD_SCRIPT	= $(LD_DIR)/link_boot.ld #For boot, make separate linker script

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
# Note: If you do not want the standard library to be linked to the program, set NOSTDLIB to true
OPTIMIZATION_FLAGS = -Os -flto
NOSTDLIB	= false
CFLAGS	= -Werror -Wall -Wunused
LFLAGS	= -lgcc

# Include the template makefile that contains all of the compilation and helper rules
include ../makefile.include



