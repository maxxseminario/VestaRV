# VestaRV: the rv4th Forth interpreter image, linked for the boot ROM.
# The compilation and helper rules come from ../makefile.include; this file only
# sets the sources, the ISA and the flags.
# Name of the target, without extension; it must exist in SRC_DIR.
TARGET      = main

# Project sources from SRC_DIR and shared library sources from LIB_DIR/src.
# start.S must come first in LIB_SOURCES: start and IRQ_master_handler_asm have
# to land at exactly their reset and vector addresses.
SRC_SOURCES	= main.c rv4th.c
# LIB_SOURCES	= start.S irq.c uart.c spi.c flash_memory.c lzw.c
LIB_SOURCES	= uart.c
EXTENSIONS	= im

USER_DEFINES	= 

# Shared libraries and the linker script.
LIB_DIR		= ../lib/src
LD_DIR		= $(LIB_DIR)/env/p
LD_SCRIPT	= $(LD_DIR)/link_boot.ld #For boot, make separate linker script

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
# not reach, so an interrupt handler must carry its __attribute__ or it is
# discarded. Set NOSTDLIB to true to link without the standard library.
OPTIMIZATION_FLAGS = -Os -flto
NOSTDLIB	= false
CFLAGS	= -Werror -Wall -Wunused
LFLAGS	= -lgcc

# The compilation and helper rules.
include ../makefile.include



