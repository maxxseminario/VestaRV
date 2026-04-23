# Myshkin-2025-11 Implementation Makefile
# Chip-specific build and flash operations

# Paths
REPO_ROOT = ../../..
FLASH_PROG = $(REPO_ROOT)/tools/flash_programmer/forthprog.py
CHIP_NAME = myshkin-2025-11
BOARD_NAME = MyshkinDevBoard

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

.PHONY: help flash flash-verify flash-rcf flash-rcf-verify clean clean-% build-%

# Catch-all for program names
%:
	@:

help:
	@echo "Myshkin-2025-11 Implementation Targets:"
	@echo "  make flash [program-name]          - Flash program to chip"
	@echo "  make flash-verify [program-name]   - Flash with verification"
	@echo "  make build-<program>               - Build specific software project"
	@echo "  make clean-<program>               - Clean specific software project"
	@echo "  make clean                         - Clean build artifacts"
	@echo ""
	@echo "Examples:"
	@echo "  make build-blinky                  # Build blinky software"
	@echo "  make flash                         # Flash default (blinky)"
	@echo "  make flash bootrom                 # Flash bootrom"
	@echo "  make flash-verify rv4th            # Flash rv4th with verification"
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

build-%:
	@echo "Building $* software..."
	@$(MAKE) -C $(REPO_ROOT)/software/$* all

clean-%:
	@echo "Cleaning $* software..."
	@$(MAKE) -C $(REPO_ROOT)/software/$* clean

clean:
	@echo "Nothing to clean in implementation directory"
