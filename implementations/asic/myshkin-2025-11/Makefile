# Myshkin-2025-11 Implementation Makefile
# Chip-specific build and flash operations

# Paths
REPO_ROOT = ../../..
FLASH_PROG = $(REPO_ROOT)/tools/flash_programmer/forthprog.py
RAM_PROG   = $(REPO_ROOT)/tools/flash_programmer/forthram.py
CHIP_NAME = myshkin-2025-11
BOARD_NAME = MyshkinDevBoard

# Entry point used by `make run*` (forthram.py `call0` target).
# Override on the command line, e.g.  make run-rcf blinky RAM_ENTRY=0x8000
RAM_ENTRY = 0x8200

# Optional UART transcript log for `make run*`. Set to a path or to "auto"
# to get ./forthram-<timestamp>.log. Example:
#   make run-rcf blinky LOG=auto
#   make run-rcf blinky LOG=/tmp/blinky.log
LOG =
ifeq ($(LOG),)
    LOG_ARG =
else
    LOG_ARG = --log $(LOG)
endif

# Get program name from command line arguments
PROGRAM = $(filter-out $@,$(MAKECMDGOALS))
ifeq ($(PROGRAM),)
    PROGRAM = blinky
endif

# Construct hex file path (if PROGRAM doesn't already contain .hex)
ifeq (,$(findstring .hex,$(PROGRAM)))
    HEX_FILE = $(REPO_ROOT)/software/$(PROGRAM)/bin/$(PROGRAM).hex
    RCF_FILE = $(REPO_ROOT)/software/$(PROGRAM)/rcf/xxxxxxxxxxxxblinky.rcf
else
    HEX_FILE = $(PROGRAM)
    RCF_FILE = $(PROGRAM)
endif

# Python
PYTHON = python3

.PHONY: help flash flash-verify flash-rcf flash-rcf-verify run run-verify run-rcf run-rcf-verify clean clean-% build-%

# Catch-all for program names
%:
	@:

help:
	@echo "Myshkin-2025-11 Implementation Targets:"
	@echo "  make flash [program-name]          - Flash program to chip"
	@echo "  make flash-verify [program-name]   - Flash with verification"
	@echo "  make run [program-name]            - Upload program to RAM via Forth and jump to \$$(RAM_ENTRY) (default 0x8200)"
	@echo "  make run-verify [program-name]     - Same as run, with RAM readback verification"
	@echo "  make run-rcf [program-name]        - Upload RCF file to RAM and jump"
	@echo "  make run-rcf-verify [program-name] - Upload RCF to RAM with verification and jump"
	@echo "  make build-<program>               - Build specific software project"
	@echo "  make clean-<program>               - Clean specific software project"
	@echo "  make clean                         - Clean build artifacts"
	@echo ""
	@echo "Examples:"
	@echo "  make build-blinky                  # Build blinky software"
	@echo "  make flash                         # Flash default (blinky)"
	@echo "  make flash bootrom                 # Flash bootrom"
	@echo "  make flash-verify rv4th            # Flash rv4th with verification"
	@echo "  make run-rcf blinky                # Upload blinky to RAM and execute at 0x8200"
	@echo "  make run-rcf blinky RAM_ENTRY=0x8000  # Override entry address"
	@echo "  make run-rcf blinky LOG=auto       # Also write UART transcript to ./forthram-<ts>.log"
	@echo "  make clean-blinky                  # Clean blinky software"

flash:
	@echo "Flashing $(HEX_FILE) to Myshkin chip..."
	$(PYTHON) $(FLASH_PROG) $(HEX_FILE) \
		--chip $(CHIP_NAME) \
		--board $(BOARD_NAME)

flash-verify:
	@echo "Flashing with verification: $(HEX_FILE)"
	$(PYTHON) $(FLASH_PROG) $(HEX_FILE) \
		--chip $(CHIP_NAME) \
		--board $(BOARD_NAME) \
		--verify

flash-rcf:
	@echo "Flashing RCF file: $(RCF_FILE)"
	$(PYTHON) $(FLASH_PROG) $(RCF_FILE) \
		--chip $(CHIP_NAME) \
		--board $(BOARD_NAME)

flash-rcf-verify:
	@echo "Flashing RCF with verification: $(RCF_FILE)"
	$(PYTHON) $(FLASH_PROG) $(RCF_FILE) \
		--chip $(CHIP_NAME) \
		--board $(BOARD_NAME) \
		--verify

# --- RAM upload + execute via Forth (bypasses SPI flash boot path) ----------
# Uses forthram.py to upload the program directly into RAM over the Forth UART
# and jump to $(RAM_ENTRY) via the `call0` opcode. Useful on silicon where the
# SPI-flash boot path is broken.

run:
	@echo "Uploading $(HEX_FILE) to RAM and jumping to $(RAM_ENTRY)..."
	$(PYTHON) $(RAM_PROG) $(HEX_FILE) \
		--chip $(CHIP_NAME) \
		--board $(BOARD_NAME) \
		--entry $(RAM_ENTRY) \
		$(LOG_ARG)

run-verify:
	@echo "Uploading $(HEX_FILE) to RAM (with verify) and jumping to $(RAM_ENTRY)..."
	$(PYTHON) $(RAM_PROG) $(HEX_FILE) \
		--chip $(CHIP_NAME) \
		--board $(BOARD_NAME) \
		--entry $(RAM_ENTRY) \
		--verify \
		$(LOG_ARG)

run-rcf:
	@echo "Uploading $(RCF_FILE) to RAM and jumping to $(RAM_ENTRY)..."
	$(PYTHON) $(RAM_PROG) $(RCF_FILE) \
		--chip $(CHIP_NAME) \
		--board $(BOARD_NAME) \
		--entry $(RAM_ENTRY) \
		$(LOG_ARG)

run-rcf-verify:
	@echo "Uploading $(RCF_FILE) to RAM (with verify) and jumping to $(RAM_ENTRY)..."
	$(PYTHON) $(RAM_PROG) $(RCF_FILE) \
		--chip $(CHIP_NAME) \
		--board $(BOARD_NAME) \
		--entry $(RAM_ENTRY) \
		--verify \
		$(LOG_ARG)

build-%:
	@echo "Building $* software..."
	@$(MAKE) -C $(REPO_ROOT)/software/$* all

clean-%:
	@echo "Cleaning $* software..."
	@$(MAKE) -C $(REPO_ROOT)/software/$* clean

clean:
	@echo "Nothing to clean in implementation directory"
