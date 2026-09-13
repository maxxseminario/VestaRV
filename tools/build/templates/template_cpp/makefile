# VestaRV: C++ firmware project template.
# `make <name>.cpp.new` in tools/build/makefiles copies this file into a new
# project directory, so edits here reach every project made afterwards.
# ../makefile.include at the bottom carries the compilation and helper rules.
# Name of the target, without extension; it must exist in SRC_DIR.
TARGET      = main

# Project sources from SRC_DIR and shared library sources from LIB_DIR/src.
# start.S must come first in LIB_SOURCES: start and IRQ_master_handler_asm have
# to land at exactly their reset and vector addresses.
SRC_SOURCES	= main.cpp
LIB_SOURCES	= start.S irq.c
EXTENSIONS	= im

USER_DEFINES	= 

# Shared libraries and the linker script.
LIB_DIR		= ../lib
LD_DIR		= $(LIB_DIR)/linker
LD_SCRIPT	= $(LD_DIR)/MCU.ld

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
# discarded. Add $(DISABLE_EXCEPTIONS) to CFLAGS to save the space exceptions
# cost, and set NOSTDLIB to true to link without the standard library.
OPTIMIZATION_FLAGS	= -Os -flto
DISABLE_EXCEPTIONS	= -fno-exceptions -fno-unwind-tables -fno-asynchronous-unwind-tables	# Note: If you want to save program space by disabling exceptions, add this to the CFLAGS variable below with $(DISABLE_EXCEPTIONS)
NOSTDLIB	= false	# Note: If you do not want the standard library to be linked to the program, set NOSTDLIB to true
CFLAGS	= -Werror -Wall -Wunused
LFLAGS	= -lgcc

# The compilation and helper rules.
include ../makefile.include
