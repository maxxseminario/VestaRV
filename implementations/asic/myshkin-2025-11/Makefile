# Myshkin-2025-11 Implementation Makefile
# Chip-specific build and flash operations

# Paths
REPO_ROOT = ../../..
FLASH_PROG = $(REPO_ROOT)/tools/flash_programmer/forthprog.py
RAM_PROG   = $(REPO_ROOT)/tools/flash_programmer/forthram.py
RCF2FORTH  = $(REPO_ROOT)/tools/flash_programmer/rcf2forth.py
FORTHRUN   = $(REPO_ROOT)/tools/flash_programmer/forthrun.py
CHIP_NAME = myshkin-2025-11
BOARD_NAME = MyshkinDevBoard

# Entry point used by `make run*` (forthram.py `call0` target).
# Override on the command line, e.g.  make run-rcf blinky RAM_ENTRY=0x8000
RAM_ENTRY = 0x0000814c

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

# Upload method for `make run*`: "poke" (default, slow per-word `!` writes;
# robust when the ROM UART drops bytes) or "mw" (fast binary stream, may
# drop bytes on noisy UARTs).
#   make run blinky METHOD=mw
METHOD ?= poke
METHOD_ARG = --method $(METHOD)

# Per-word verify log: when verify is failing the same way every pass, set
# VERIFY_LOG=auto to dump every (expected, actual) pair to a file:
#   make run blinky VERIFY_LOG=auto
#   make run blinky VERIFY_LOG=./mychip-verify.log
# Or set VERBOSE_VERIFY=1 to print the first few mismatches inline each pass.
VERIFY_LOG ?=
VERBOSE_VERIFY ?=
ifneq ($(strip $(VERIFY_LOG)),)
    VERIFY_LOG_ARG = --verify-log $(VERIFY_LOG)
endif
ifneq ($(strip $(VERBOSE_VERIFY)),)
    VERBOSE_VERIFY_ARG = --verbose-verify
endif

# Read-back path during verify: "ascii" (default, plain `<addr> @ .` reads --
# works on any rv4th ROM) or "mr" (fast binary CRC read; only if the chip's
# Forth ROM actually defines `mr`).
#   make run afefsm VERIFY_METHOD=mr
VERIFY_METHOD ?= ascii
VERIFY_METHOD_ARG = --verify-method $(VERIFY_METHOD)

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

.PHONY: help flash flash-verify flash-rcf flash-rcf-verify run run-verify run-rcf run-rcf-verify forth-script forth-script-rcf forth-run forth-run-file clean clean-% build-%

# Catch-all for program names
%:
	@:

help:
	@echo "Myshkin-2025-11 Implementation Targets:"
	@echo "  make flash [program-name]          - Flash program to chip"
	@echo "  make flash-verify [program-name]   - Flash with verification"
	@echo "  make run [program-name]            - Upload program to RAM via Forth (verify+repair, method=poke) and jump to \$$(RAM_ENTRY) (default 0x814C)"
	@echo "  make run-verify [program-name]     - Alias for 'run' (kept for compatibility)"
	@echo "  make run-rcf [program-name]        - Same, but uploads the .rcf file"
	@echo "  make run-rcf-verify [program-name] - Alias for 'run-rcf'"
	@echo "  make forth-script [program-name]     - Convert program's .hex to a Forth !/call0 script (-> <program>.forth)"
	@echo "  make forth-script-rcf [program-name] - Same, but from the program's .rcf file"
	@echo "  make forth-run [program-name]        - Stream the program's generated .forth file to the chip over UART"
	@echo "  make forth-run-file FORTH_FILE=<path> - Stream an arbitrary .forth file to the chip over UART"
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
	@echo "  make run-rcf blinky METHOD=poke    # Slow per-word '!' upload (robust if mw drops bytes)"
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
	@echo "Uploading $(HEX_FILE) to RAM (verify + repair, method=$(METHOD)) and jumping to $(RAM_ENTRY)..."
	$(PYTHON) $(RAM_PROG) $(HEX_FILE) \
		--chip $(CHIP_NAME) \
		--board $(BOARD_NAME) \
		--entry $(RAM_ENTRY) \
		--verify \
		$(METHOD_ARG) $(LOG_ARG) $(VERIFY_LOG_ARG) $(VERBOSE_VERIFY_ARG) $(VERIFY_METHOD_ARG)

run-verify: run

run-rcf:
	@echo "Uploading $(RCF_FILE) to RAM (verify + repair, method=$(METHOD)) and jumping to $(RAM_ENTRY)..."
	$(PYTHON) $(RAM_PROG) $(RCF_FILE) \
		--chip $(CHIP_NAME) \
		--board $(BOARD_NAME) \
		--entry $(RAM_ENTRY) \
		--verify \
		$(METHOD_ARG) $(LOG_ARG) $(VERIFY_LOG_ARG) $(VERBOSE_VERIFY_ARG) $(VERIFY_METHOD_ARG)

run-rcf-verify: run-rcf

# --- Offline: convert program file to Forth !/call0 script ---------------
# Produces <program>.forth in the program's software dir that can be pasted /
# streamed into the rv4th ROM REPL to load the program into RAM and jump to it.
FORTH_SCRIPT_DIR = $(REPO_ROOT)/software/$(PROGRAM)/forth
FORTH_SCRIPT     = $(FORTH_SCRIPT_DIR)/$(PROGRAM).forth

forth-script:
	@mkdir -p $(FORTH_SCRIPT_DIR)
	@echo "Generating Forth script from $(HEX_FILE) (entry $(RAM_ENTRY)) -> $(FORTH_SCRIPT)"
	$(PYTHON) $(RCF2FORTH) $(HEX_FILE) \
		--entry $(RAM_ENTRY) \
		--header \
		-o $(FORTH_SCRIPT)

forth-script-rcf:
	@mkdir -p $(FORTH_SCRIPT_DIR)
	@echo "Generating Forth script from $(RCF_FILE) (entry $(RAM_ENTRY)) -> $(FORTH_SCRIPT)"
	$(PYTHON) $(RCF2FORTH) $(RCF_FILE) \
		--entry $(RAM_ENTRY) \
		--header \
		-o $(FORTH_SCRIPT)

# --- Stream a *.forth script to the chip over UART ------------------------
# Uses forthrun.py, which mirrors rv4th_terminal.py's transport (serial port,
# optional boot-mode / reset GPIOs) but reads commands from a file instead
# of the keyboard. Skips blank lines and '\' comments.
#
# Extra knobs:
#   FORTH_FILE      path to the script (default: $(FORTH_SCRIPT))
#   FORTH_PORT      serial device        (default: /dev/ttyAMA0)
#   FORTH_BAUD      baud rate            (default: 115200)
#   FORTH_DELAY     inter-line delay (s) (default: 0.010)
#   FORTH_BOOT_PIN  optional BCM GPIO to hold HIGH during session
#   FORTH_RESET_PIN optional BCM GPIO to pulse for chip reset
#   FORTH_LOG       optional log file path
#   FORTH_EXTRA     any extra forthrun.py args (e.g. --wait-boot --quiet)
FORTH_FILE      ?= $(FORTH_SCRIPT)
FORTH_PORT      ?=
FORTH_BAUD      ?=
FORTH_DELAY     ?=
FORTH_BOOT_PIN  ?=
FORTH_RESET_PIN ?=
FORTH_LOG       ?=
FORTH_EXTRA     ?=

FORTH_PORT_ARG      = $(if $(FORTH_PORT),--port $(FORTH_PORT),)
FORTH_BAUD_ARG      = $(if $(FORTH_BAUD),--baud $(FORTH_BAUD),)
FORTH_DELAY_ARG     = $(if $(FORTH_DELAY),--line-delay $(FORTH_DELAY),)
FORTH_BOOT_ARG      = $(if $(FORTH_BOOT_PIN),--boot-pin $(FORTH_BOOT_PIN),)
FORTH_RESET_ARG     = $(if $(FORTH_RESET_PIN),--reset-pin $(FORTH_RESET_PIN),)
FORTH_LOG_ARG       = $(if $(FORTH_LOG),--log $(FORTH_LOG),)

forth-run:
	@test -f $(FORTH_SCRIPT) || (echo "ERROR: $(FORTH_SCRIPT) does not exist. Run 'make forth-script-rcf $(PROGRAM)' first." && exit 1)
	@echo "Streaming $(FORTH_SCRIPT) to chip over UART"
	$(PYTHON) $(FORTHRUN) $(FORTH_SCRIPT) \
		$(FORTH_PORT_ARG) $(FORTH_BAUD_ARG) $(FORTH_DELAY_ARG) \
		$(FORTH_BOOT_ARG) $(FORTH_RESET_ARG) $(FORTH_LOG_ARG) \
		$(FORTH_EXTRA)

forth-run-file:
	@test -n "$(FORTH_FILE)" || (echo "ERROR: set FORTH_FILE=<path to *.forth>" && exit 1)
	@test -f $(FORTH_FILE) || (echo "ERROR: $(FORTH_FILE) not found" && exit 1)
	@echo "Streaming $(FORTH_FILE) to chip over UART"
	$(PYTHON) $(FORTHRUN) $(FORTH_FILE) \
		$(FORTH_PORT_ARG) $(FORTH_BAUD_ARG) $(FORTH_DELAY_ARG) \
		$(FORTH_BOOT_ARG) $(FORTH_RESET_ARG) $(FORTH_LOG_ARG) \
		$(FORTH_EXTRA)

build-%:
	@echo "Building $* software..."
	@$(MAKE) -C $(REPO_ROOT)/software/$* all

clean-%:
	@echo "Cleaning $* software..."
	@$(MAKE) -C $(REPO_ROOT)/software/$* clean

clean:
	@echo "Nothing to clean in implementation directory"
