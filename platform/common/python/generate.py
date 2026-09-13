#!/usr/bin/env python3
# VestaRV: chip generator entry point. Builds every generated artifact (RTL, memory
# map, headers, linker scripts, pad ring, TRM sources, web bundle) from _CONFIG_SCHEMA.
# One command line: --config <file> selects the configuration and --out <dir> the output
# root; CHIP_CONFIG is the same knob as --config in the environment, for the Makefile and
# the hermetic bazel action, and the two disagreeing is an error. CHIP_NAME wins over the
# file's chipName. Every knob states its default twice, in _CONFIG_SCHEMA and at its _cfg()
# site; check_config_defaults.py gates the pair. The emitted files are byte-compared by the
# bazel chip_artifacts tests, so any change here that moves a byte must be intended.

import argparse, pathlib, sys, os

# The chip root holds python/, latex/, hdl_templates/ and config/, and every INPUT is read
# from it. Under `bazel run` __file__ points into a runfiles tree that carries the generator
# modules but none of the LaTeX or template inputs, so the chip root is taken from the source
# tree bazel names in BUILD_WORKSPACE_DIRECTORY. The hermetic action scrubs its child's
# environment, so that variable is never set there and the staged tree stays authoritative.
thisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
chipRootDirectory = thisFileDirectory + '/..'
_workspaceRoot = os.environ.get('BUILD_WORKSPACE_DIRECTORY', '')
if _workspaceRoot:
	_runfilesMark = '.runfiles' + os.sep
	_at = thisFileDirectory.find(_runfilesMark)
	if _at >= 0:
		# <bin>/generate.runfiles/<repo>/platform/common/python -> <workspace>/platform/common
		_parts = thisFileDirectory[_at + len(_runfilesMark):].split(os.sep)
		chipRootDirectory = os.path.join(_workspaceRoot, *_parts[1:-1])

_argParser = argparse.ArgumentParser(prog='generate.py',
	description='VestaRV chip generator: one configuration in; RTL, headers, linker scripts, '
		'pad ring and TRM sources out.')
_argParser.add_argument('--config', metavar='FILE', default='',
	help='chip configuration JSON, the Makefile\'s CONFIG= file. Omitted means the built-in '
		'defaults, which are the Castalia tape-out chip. CHIP_CONFIG is the environment form.')
_argParser.add_argument('--out', metavar='DIR', default='',
	help='output root. Default: the chip root, so out/, config/*.json and latex/TRM/ land '
		'exactly where the Makefile has always put them. Inputs are read from the chip root '
		'either way, so --out never writes into the source tree.')
_args = _argParser.parse_args()

def _userPath(givenPath):
	'''A path off the command line. `bazel run` starts the binary in its runfiles tree, so a
	relative path there means the workspace the run was launched from, not the cwd.'''
	if givenPath and _workspaceRoot and not os.path.isabs(givenPath):
		return os.path.join(_workspaceRoot, givenPath)
	return givenPath

# Output root: everything the generator writes hangs off it. Defaulting to the chip root is
# what keeps every byte-compare gate valid; --out puts the same tree somewhere else.
_outArg = _userPath(_args.out)
outputRootDirectory = os.path.abspath(_outArg) if _outArg else chipRootDirectory


from ChipGenerator import ChipGenerator
from Peripheral import PeripheralTemplate, Peripheral
from Register import RegisterTemplate, Register
from BitField import BitField
from GpioConfigurator import GpioConfigurator, GpioAltFunc

# Optional configuration file: generate.py --config path/to/config.json, or the same path in
# CHIP_CONFIG (make chip CONFIG=..., and the hermetic action). Every key is optional and falls
# back to the _CONFIG_SCHEMA default below; an unknown key raises.
# numHarts drives the emitted MCU.vhd regions (hart-tile instances, arbiter and fabric
# widths, CLINT layout), but only the counts in _VERIFIED_HART_COUNTS elaborate.
# Name precedence: CHIP_NAME environment variable, then the config file, then the default.
# The flag and the variable are one knob under two names, so naming different files is an
# error rather than a silent precedence rule nobody can see in the log.
import json
_cfgFlag = _userPath((_args.config or '').strip())
_cfgEnv = os.environ.get('CHIP_CONFIG', '').strip()
if _cfgFlag and _cfgEnv and os.path.abspath(_cfgFlag) != os.path.abspath(_cfgEnv):
	raise SystemExit('[generate] --config and CHIP_CONFIG name different configurations:\n'
		+ '  --config     ' + os.path.abspath(_cfgFlag) + '\n'
		+ '  CHIP_CONFIG  ' + os.path.abspath(_cfgEnv) + '\n'
		+ '  Pass one of the two, or make them agree.')
_CHIP_CONFIG = {}
_cfgPath = _cfgFlag or _cfgEnv
if _cfgPath:
	with open(_cfgPath) as _f:
		_CHIP_CONFIG = json.load(_f)
	print('[generate] loaded chip configuration from ' + _cfgPath)

# The path recorded in config/ChipConfig.resolved.json and the web bundle. Relative to
# the chip root when it is inside it, otherwise the bare file name. An absolute path
# would differ between two staged trees and break a byte-compare of the two.
_cfgRecord = None
if _cfgPath:
	_cfgRel = os.path.relpath(os.path.abspath(_cfgPath), os.path.abspath(chipRootDirectory))
	_cfgRecord = _cfgRel if not _cfgRel.startswith('..') else os.path.basename(_cfgPath)

# Overlay: an out-of-tree directory contributing extra configurations, register
# descriptions, package models, peripheral definitions and emitter fragments.
# `overlay` is a generator directive, not a schema knob. It is consumed and removed
# here, so it never reaches _validateChipConfig, the resolved-config record, the
# configurator or the TRM tables. A relative path resolves against the configuration
# file's directory; VESTA_OVERLAY wins over both. Contract: overlay.py.
import overlay
overlay.setRoot(_CHIP_CONFIG.pop('overlay', ''),
	relativeTo=(os.path.dirname(os.path.abspath(_cfgPath)) if _cfgPath else None))
if overlay.has():
	print('[generate] overlay: ' + overlay.root())

def _cfg(dottedKey, default):
	'''Dotted-path lookup into the loaded JSON config, e.g. _cfg('isa.mul', True).
	   Returns `default` for any missing key so partial configs are fine.'''
	node = _CHIP_CONFIG
	for part in dottedKey.split('.'):
		if not isinstance(node, dict) or part not in node:
			return default
		node = node[part]
	return node

# _CONFIG_SCHEMA is the authoritative list of knobs a CONFIG= file may set.
# docs/chip_configurator.html emits exactly these keys, the TRM's generated Chip
# Configuration section documents them, and the resolved values land in
# config/ChipConfig.resolved.json; all four move together. Every key is optional
# (missing means the default here). An unknown key raises rather than falling back.
# The defaults below are config/castalia.json, the tape-out product: a build with no
# CONFIG resolves to that record byte for byte except the provenance field `configFile`.
# Each `description` is rendered three ways, and the narrow TRM table column binds:
# keep it to one sentence of about 80 characters, valid values then effect. Mechanism
# detail belongs in the TRM chapter and in the comments here.
def _isBool(v):
	return isinstance(v, bool)
def _isInt(v):
	return isinstance(v, int) and not isinstance(v, bool)
def _isMemSize(v, ceiling):
	return _isInt(v) and 0 < v <= ceiling and v % 0x400 == 0

# The pad ring derives from a Python package model; a config selects one by name.
# Free-form pin assignment is unsupported: a new pinout is a new model here, never JSON.
_PACKAGE_MODELS = ('myshkin-qfn44', 'castalia-quad-qfn64', 'castalia-lqfp100')
# An overlay may add package models of its own; _buildPackageData's `packageData`
# stage builds them.
_PACKAGE_MODELS = tuple(overlay.call('packageModels', default=_PACKAGE_MODELS,
	models=_PACKAGE_MODELS))
_CONFIG_SCHEMA = {
	'chipName':             ('non-empty string: renames the chip in the TRM and headers (CHIP_NAME env wins)',
	                         lambda v: isinstance(v, str) and len(v.strip()) > 0),
	'numHarts':             ('int 1..32: hart count; hart 0 is the always-on management hart and harts 1..N-1 are the power-gateable tiles',
	                         lambda v: _isInt(v) and 1 <= v <= 32),
	# true makes hart 0 an always-on soft orchestrator, emitted as `entity work.orch_tile`,
	# and harts 1..numHarts-1 uniform channel tiles: hart_id 1..N-1, pwr_ctrl rows 1..N-1,
	# iso clamps, tcm_pgen => pd_sleep(h), flash ports open, a0_h monitored. Hart 0 keeps
	# its wiring specials (SPI0 flash/XIP, sleep_cpu, the GPIO0 trap pin, the tb pass/fail
	# gate, arbiter master slice 0 with no isolation clamps). It also selects memory map v2:
	# SH_AW = max(derived, 16), read-only TCM apertures at 0x20000 + h*0x4000 readable only
	# by the management hart (the s_master = 0 gate), extended flash at 0x40000.
	# false is the historical shape: every hart a hardened hart_tile, RTL byte-identical to
	# a build that never heard of this knob. The management hart is hart 0 either way, so
	# afe_stub's MGMT_HART generic is never overridden and only the AFE bank's OWNER_HART
	# literals shift with the tiles. The CLINT layout shifts with the hart count
	# (mtime 0x5010 at N=4, 0x5020 at N=5), so firmware must derive CLINT addresses from NHARTS.
	'orchestrator':         ('bool: hart 0 is the always-on orchestrator; harts 1..N-1 are gateable tiles',
	                         _isBool),
	'numMutexes':           ('int 1..1024: hardware mutex bank size, the number of MUTEXn registers',
	                         lambda v: _isInt(v) and 1 <= v <= 1024),
	'registerFileDualPort': ('bool: docs-only, the register file is dual-port in the RTL either way',
	                         _isBool),
	# Fetch-ahead keeps the last fetched word in one flip-flop and serves a straddling
	# C-extension fetch from it instead of re-fetching. Measured on the shipped core:
	# aggregate CPI 1.523 -> 1.260, the added flop off the critical path, nothing software
	# visible. Meaningless without isa.compressed; an OFF build wires the generic on and
	# the core's own gate keeps it inert.
	'core.fetchAhead':      ('bool: C-extension fetch-ahead (one flip-flop; removes most of the straddling-fetch stall)',
	                         _isBool),
	'isa.mul':              ('bool: M multiply', _isBool),
	'isa.fastMul':          ('bool: docs-only, the multiplier is already single-cycle', _isBool),
	'isa.div':              ('bool: M divide', _isBool),
	'isa.atomics':          ('bool: A extension (LR/SC + AMO)', _isBool),
	'isa.compressed':       ('bool: C extension', _isBool),
	'isa.bitmanip':         ('bool: Zba/Zbb/Zbs/Zbc', _isBool),
	# Asymmetric ISA. true builds the hardened corner tiles (harts 1..numHarts-1) rv32iac,
	# dropping M and B, while hart 0, the soft orchestrator, keeps the full chip ISA above.
	# The split costs no extra hardening: hart 0 is already an orch_tile and the corners are
	# instances of one hart_tile macro. Measured per tile at genus, full versus rv32iac:
	#   tile 132,657 -> 109,926 um2   core 60,540 -> 37,808 um2   flops 2,576 -> 2,210
	#   power 2.687 -> 1.945 mW       leakage 460 -> 379 uW
	# A and C stay: the tiles run the shared-fabric LR/SC and AMO locking, and C is
	# decoder-only (456 um2) while it shrinks code against an 8 KiB TCM.
	# Software contract: no binary may migrate between hart 0 and a corner tile, and
	# anything a tile executes must be built without M and B.
	'isa.minimalTiles':     ('bool: harts 1..N-1 drop M and B (rv32iac); hart 0 keeps the full ISA',
	                         _isBool),
	# cycle/instret and their high halves are always present; this knob gates only the
	# _zicntr march suffix and the legacy constants. The suffix over-promises: time and
	# timeh (0xC01/0xC81) are unimplemented in every build, because no time source is wired
	# to the core, and a read of either raises illegal-instruction.
	'isa.counters':         ('bool: Zicntr march suffix only (cycle/instret always exist, time/timeh never do)', _isBool),
	'isa.counters64':       ('bool: docs-only high counter halves (always present); needs isa.counters', _isBool),
	# ISA extensions. Every isa.* knob below is real hardware; the scaffolding hard-error
	# list _SCAFFOLDED_ISA is empty, so no knob advertises hardware it lacks.
	'isa.zicond':           ('bool: Zicond conditional-zero ops (czero.eqz/czero.nez)', _isBool),
	'isa.zcb':              ('bool: Zcb extra compressed loads/stores and ALU ops; needs isa.compressed', _isBool),
	'isa.zimop':            ('bool: Zimop+Zcmop may-be-ops (mop.r/mop.rr rd<-0, c.mop.n nops)', _isBool),
	'isa.zihint':           ('bool: Zihintpause+Zihintntl (PAUSE = 16-cycle arbiter-yield window; ntl.* nops)', _isBool),
	'isa.zihpm':            ('bool: Zihpm performance counters 3 and 4 (four chip events)', _isBool),
	'isa.zawrs':            ('bool: Zawrs wrs.nto/wrs.sto wait-on-reservation-set (needs isa.atomics)', _isBool),
	'isa.zabha':            ('bool: Zabha byte/halfword AMOs; needs isa.atomics', _isBool),
	'isa.zacas':            ('bool: Zacas compare-and-swap (amocas.w/.b/.h); needs isa.atomics', _isBool),
	'isa.zicboz':           ('bool: Zicboz cbo.zero cache-block zero (64-byte block)', _isBool),
	'isa.zcmp':             ('bool: Zcmp compressed push/pop and register moves; needs isa.compressed', _isBool),
	'isa.zcmt':             ('bool: Zcmt compressed table jump and the jvt CSR; needs isa.compressed', _isBool),
	'isa.zbkb':             ('bool: Zbkb crypto bit-manipulation (pack/brev8/zip/unzip)', _isBool),
	'isa.zbkc':             ('bool: Zbkc carry-less multiply (clmul/clmulh)', _isBool),
	'isa.zbkx':             ('bool: Zbkx crossbar permute (xperm8/xperm4)', _isBool),
	'isa.zkn':              ('bool: Zkn AES+SHA (Zknd+Zkne+Zknh)', _isBool),
	# Zfinx single-precision FP in the x-registers: shared FMA backend, exactly one rounding
	# per operation, all five rounding modes, full subnormals, radix-2 iterative div/sqrt,
	# the fcvt family. The largest single extension, 0.034 mm2 of tile area.
	'isa.zfinx':            ('bool: Zfinx single-precision floating point in the x registers', _isBool),
	# P-series privileged architecture. The generics ride generate.py -> ChipGenerator ->
	# mcu_vhd -> MemoryMap CORE_* -> hart_tile -> vesta -> maindec/csr_unit. _SCAFFOLDED_PRIV
	# is empty; the dependency validations (umode requires trapCsr, pmp requires umode) are
	# the only gate left.
	# trapCsr is the standard M-mode trap architecture: the CSR file (mstatus, mstatush,
	# mtvec, mie, mip, mscratch, mepc, mcause, mtval and the custom mtrapctl at 0x7C0) plus
	# MRET/ECALL/EBREAK decode, mtvec-vectored exceptions and interrupts (MEI > MSI > MTI),
	# and the mstatus MPIE/MIE stack. mtrapctl.LEGACY resets 1, so an ON chip still boots on
	# the legacy IVT path and a hart enters standard delivery only when its own firmware
	# writes 0x7C0. Cost: +144 flops per tile, +3.85% standard-cell area, +1.29% tile area,
	# timing neutral. false keeps all ten addresses and the three encodings illegal.
	# Hazard for any firmware policy: clearing LEGACY on a hart that then extinguishes makes
	# it unwakeable, because the bootrom park/wake contract uses the legacy slot-83 msip path.
	# Clear it per hart only, never before park.
	'priv.trapCsr':         ('bool: standard M-mode trap CSRs and delivery; firmware opts in via mtrapctl', _isBool),
	# Core-side debug mode plus the whole transport.
	# Core: the debug-mode CSRs dcsr/dpc/dscratch0/dscratch1 at 0x7B0-0x7B3 (illegal outside
	# debug mode), the DRET encoding, an unmaskable halt request sampled at the same fourteen
	# FSM points an interrupt is (including the terminal TRAP_STATE, so a wedged hart can be
	# rescued), halt-on-reset, ebreak-to-debug under dcsr.ebreakm, and single-step. Debug
	# entry vectors to DEBUG_ENTRY_ADDR, the shared-window debug program page 0x00010780; a
	# tile's TCM is unreachable from the shared bus, so the old TCM default 0xBE00 survives
	# only as the VHDL generic's fail-safe declaration default.
	# Transport: the Debug Module dm0 with its eight dmi_* MCU ports, and the JTAG DTM dtm0
	# (16-state TAP, 5-bit IR, IDCODE/dtmcs/dmi(41)/BYPASS, the TCK to mclk crossing) on
	# tck/tms/tdi/tdo/trstn, merged into the one DM by valid-gated OR.
	# There is no debug ROM. dm0 plants the 40-word entry code from a constant table through
	# its own master port, once at every dmactive 0->1 and again before it consumes a
	# newly-halted hart's token; 24 of the entry page's 64 words are DM-written at runtime and
	# must stay writable, which is why read-only memory there would break the Debug Module.
	# tools/cosim/check_dbg_trampoline.py holds the table equal to the built
	# software/dbg_trampoline/dbg_trampoline.S (rc 0 equal, 1 mismatch, 2 missing).
	# The page self-repairs for every word but the first: a hart that halts into a wrong word
	# 0 re-asks for that word, hart_tile's same-word ack hold re-serves the stale copy, and
	# the hart wedges until a PWRCTRL tile power-cycle.
	# Requires priv.trapCsr: ebreak and the SYSTEM PRIV decode arm are trapCsr-gated.
	# System Bus Access is out by design; memory access is progbuf lw/sw through the halted
	# hart. Cost: +742 flops (452 core, 265 dm0, 25 fabric), plus dtm0 and 4 for the plant.
	# false keeps the four CSR addresses and DRET illegal and folds the three tile debug ports
	# away; no shipped configuration exercises that arm, so prove it in a scratch config.
	'debug.enable':         ('bool: debug mode, the Debug Module and the JTAG DTM; needs priv.trapCsr', _isBool),
	# User mode: the 1-bit privilege register (reset M) with the MPP push/pop on trap entry
	# and MRET, mstatus.MPP WARL {00,11} (01/10 map to M), mstatus.TW, a real mcounteren
	# (CY/TM/IR/HPM3/HPM4), misa.U, ECALL-from-U cause 8, the standard WFI encoding with its
	# wake-on-(mip & mie) rule, and the U-mode decode gate: every machine or custom CSR
	# (csr_addr(9:8) = "00"), MRET, the three custom Vesta instructions and a TW-denied WFI
	# raise illegal-instruction, and a denied CSR access commits no write. Requires
	# priv.trapCsr. false is bit-identical to a trapCsr-only chip: no privilege register,
	# misa.U clear, MPP WARL {11}, mcounteren reads zero.
	'priv.umode':           ('bool: user mode (privilege register, MPP stack, mcounteren); needs priv.trapCsr', _isBool),
	# Physical memory protection (Smpmp): the pmpcfg0-3 and pmpaddr0-15 CSR bank (packed
	# 4x8-bit cfg, R/W/X/A(4:3)/L with bits 6:5 WARL 0, W pinned 0 when R=0, pmpaddr bits
	# 31:30 WARL 0), the full lock semantics (a locked entry's cfg and address are immutable
	# until reset, a TOR-locked entry also write-locks its predecessor address, per-byte lock
	# filtering inside a pmpcfg word), and the combinational match unit (OFF/TOR/NA4/NAPOT at
	# G=0, lowest-numbered match decides alone, locked entries enforce on M-mode, no match
	# grants M and faults U). Pre-issue fetch/load/store checks raise access faults 1/5/7.
	# Requires priv.umode. false keeps all twenty addresses illegal and leaves the match unit
	# uninstantiated, bit-identical to a umode-only chip.
	'priv.pmp':             ('bool: PMP (Smpmp) CSR bank and match unit; needs priv.umode', _isBool),
	# PMP entry count, 8 or 16 only (the PMP_ENTRIES generic). Consulted only when priv.pmp
	# is true; the CSR map is the 16-entry superset regardless, and entries above the count
	# are WARL all-zero.
	'priv.pmpEntries':      ('int, 8 or 16: PMP entry count when priv.pmp is true (default 16)',
	                         lambda v: _isInt(v) and v in (8, 16)),
	'memory.romSize':            ('int bytes, 1 KiB multiple <= 0x4000: boot ROM (0x0-0x1FFF at the shipped 8 KiB; the page runs to 0x3FFF and its tail is unmapped)',
	                              lambda v: _isMemSize(v, 0x4000)),
	'memory.tcmSizePerHart':     ('int bytes, 1 KiB multiple <= 0x4000: per-hart TCM based at 0x8000 (top = 0x8000 + size - 1; 0x9FFF at the shipped 8 KiB)',
	                              lambda v: _isMemSize(v, 0x4000)),
	'memory.sharedBulkRamSize':  ('int bytes, multiple of 0x4000: shared bulk RAM from 0x10000, one bank per 16 KiB',
	                              lambda v: _isInt(v) and v >= 0x4000 and v % 0x4000 == 0),
	'memory.npuStagingRamSize':  ('int bytes, 1 KiB multiple <= 0x4000: NPU staging RAM (0xC000-0xFFFF)',
	                              lambda v: _isMemSize(v, 0x4000)),
	# false drops the NPU entirely: slot 10 at 0x4A00 and the 0xC000 staging window read zero.
	'peripherals.npu':      ('bool: false drops the NPU (slot 10 and the 0xC000 staging window read zero)',
	                         _isBool),
	# false drops the second I2C instance: slot 15 reads zero, IRQ vectors 70-82 are reserved,
	# SDA1/SCL1 revert to plain GPIO.
	'peripherals.i2c1':     ('bool: false drops I2C1 (slot 15 reads zero; SDA1/SCL1 revert to plain GPIO)',
	                         _isBool),
	# false drops the second UART instance: slot 5 reads zero, IRQ vectors 52-54 are reserved,
	# TX1/RX1 revert to plain GPIO.
	'peripherals.uart1':    ('bool: false drops UART1 (slot 5 reads zero; TX1/RX1 revert to plain GPIO)',
	                         _isBool),
	# false drops the second SPI instance: slot 3 reads zero, IRQ vectors 11-12 are reserved,
	# CS1/MISO1/MOSI1/SCK1 revert to plain GPIO.
	'peripherals.spi1':     ('bool: false drops SPI1 (slot 3 reads zero; its four pins revert to plain GPIO)',
	                         _isBool),
	# false drops the second TIMER instance: slot 7 reads zero, IRQ vectors 22-27 are reserved,
	# T1CMP* and T1CAP* revert to plain GPIO.
	'peripherals.timer1':   ('bool: false drops TIMER1 (slot 7 reads zero; the T1 pins revert to plain GPIO)',
	                         _isBool),
	# true instantiates the four AFE register stubs (page-0 slot 12 at 0x4C00, sub-slots on
	# sh_addr(5:4)) and the shared EIS engine stub at 0x7C00. false frees slot 12 for a native
	# peripheral and reserves IRQ vectors 55 and 56. Mutually exclusive with peripherals.qspi.
	'peripherals.cqAfeStubs': ('bool: the four AFE register stubs and the EIS engine stub (slot 12, 0x4C00)',
	                         _isBool),
	# true instantiates the QSPI0 controller in page-0 slot 12 (0x4C00), driving IRQ vectors
	# 55 (transfer complete) and 56 (RX full). Requires peripherals.cqAfeStubs false: both
	# decode slot 12.
	'peripherals.qspi':     ('bool: QSPI0 controller in slot 12 (0x4C00); needs cqAfeStubs false',
	                         _isBool),
	# true instantiates the I3C0 controller (MVP, DAA, IBI) at 0x6100, page-2 sub-slot 1. It
	# tightens the mutex-bank decode to its 256 B sub-slot 0, retiring the page-wide alias
	# whose reads fired the atomic CLAIM side effect, adds a page-2 sub-decode, and grows the
	# IRQ source list to 94: a reserved placeholder at the frozen meip slot 85, then I3C
	# vectors 86-93 (tc, rxf, txe, nack, eod, arb, daa, ibi).
	'peripherals.i3c':      ('bool: I3C0 controller (MVP + DAA + IBI) at 0x6100',
	                         _isBool),
	# true instantiates the NFC0 ISO 14443A tag and card-emulation engine at 0x6200, page-2
	# sub-slot 2. Like I3C it tightens the mutex-bank decode to sub-slot 0 and adds the page-2
	# sub-decode. It grows the IRQ source list to 98: meip stays frozen at slot 85, 86-93 are
	# I3C or reserved, and NFC drives 94-97 (field, rxf, txdone, crcerr). The digital AFE and
	# RF interface are off-die, placeholder-tied.
	'peripherals.nfc':      ('bool: NFC0 ISO 14443A tag engine at 0x6200 (the RF front end is off-die)',
	                         _isBool),
	# true instantiates the RTC0 real-time clock (32.768 kHz always-on wall clock, one-shot
	# alarm, periodic tick) at 0x6500, page-2 sub-slot 5. Zero pins; it clocks off the ungated
	# lfxt_in pad crystal, with the CDC synchronizers, sticky W1C flags and IRQ combiner on the
	# free-running MCLK. It grows the IRQ source list to 115, vector 114 being the single
	# combined RTC0 alarm/tick source above GPIO5's 106-113. NUM_EN_WORDS stays 4.
	'peripherals.rtc':      ('bool: RTC0 32.768 kHz wall clock with alarm and tick at 0x6500',
	                         _isBool),
	# true instantiates the PWM0 buffered PWM generator (2 channels, glitch-free
	# double-buffered update, software fault trip, period-event tick) at 0x6600, page-2
	# sub-slot 6. Zero input pins: the outputs pwm_out(0) and (1) replace two redundant
	# timer-compare spread copies on P2.2/P2.3 AF2. Free-running MCLK engine, no LFXT and no
	# generated clocks. It extends the IRQ source list per the global vector rule: 115 =
	# PWM0_FAULT (lower id wins router priority), 116 = PWM0_EVT, with 114 backfilling as
	# IRQB_RSVD114 when RTC is off. NUM_EN_WORDS stays 4.
	'peripherals.pwm':      ('bool: PWM0 two-channel buffered PWM at 0x6600 (outputs on P2.2/P2.3)',
	                         _isBool),
	# true instantiates the OW0 Dallas/Maxim 1-Wire master (reset and presence, write/read bit
	# and byte primitives off a programmable time base, standard and overdrive; ROM search and
	# CRC-8 in firmware) at 0x6700, page-2 sub-slot 7. One pad: DQ on P4.7 / GPIO31, alt plane
	# AF2, open-drain, rstREN=1, taking over the redundant T0CMP1 output-spread copy in that
	# slot. T0CMP1 keeps its P3.1/GPIO17 AF0 primary, its P2.1 and P4.5 AF1 relocations and 26
	# other spread copies. Free-running MCLK engine, no clock on the DQ pad (DQ is 2-FF
	# synchronized). It extends the IRQ source list to 118, vector 117 being the single
	# combined OW0 complete/error source, with 114-116 backfilling as IRQB_RSVD when their own
	# blocks are off. NUM_EN_WORDS stays 4.
	'peripherals.onewire':  ('bool: OW0 1-Wire master at 0x6700, open-drain DQ on P4.7',
	                         _isBool),
	# true wires the field-powered-mode supervision inputs into PWRCTRL: P6.7/GPIO47 = PGOOD
	# supply-supervisor input, P6.6/GPIO46 = harvested-boot strap. Both are plain-GPIO direct
	# taps of the pad-input plane, always readable and independent of PxSEL/PxAFS, because
	# PGOOD must gate boot before any software can program a mux. Reset attributes rstDIR=input,
	# rstREN=1, pull-down, so an unconnected pad reads power-not-good and NORMAL (SPI) boot.
	# It also taps NFC0's field_detect level as an optional PWRCTRL wake/release source, tied 0
	# when NFC is absent. The PWRWAKE/PWRSTS registers and the pgood_rstn boot gate exist in the
	# RTL unconditionally; this knob only decides the pad-side ties, so false leaves the feature
	# a provable no-op with the gate stuck released.
	'peripherals.fieldPower': ('bool: wires the field-power pins (PGOOD, harvest strap) into PWRCTRL',
	                         _isBool),
	# true instantiates the DMA0 multi-channel single-shot DMA controller (peripheral-paced or
	# software-GO mem-to-mem transfers, CRC16 ride-along) at 0x6800, page-2 sub-slot 8. Zero
	# pins. DMA0 is the first new arbiter master since the four harts: enabling it widens the
	# shared fabric from N=4 to N=5 masters, the DMA taking master index numHarts, the last
	# slice. mp_arbiter N=>5 MW=>3, resv_unit N=>5, mutex_bank and irq_router MW=>3, sh_master
	# 2 -> 3 bits, and the arb_* buses grow a fifth slice. It extends the IRQ source list to
	# 119: 118 = DMA0_DONE (combined channels-done), 119 = DMA0_ERR, with 114-117 backfilling
	# as IRQB_RSVD per their own knobs. NUM_EN_WORDS stays 4.
	'peripherals.dma':      ('bool: DMA0 multi-channel DMA at 0x6800; adds one more arbiter master',
	                         _isBool),
	# DMA0 channel count, 2 or 4 only (the NCH generic). Consulted only when peripherals.dma
	# is true; the register map is the 4-channel superset regardless and absent channels read 0.
	'peripherals.dmaChannels': ('int, 2 or 4: DMA0 channel count when peripherals.dma is true (default 4)',
	                         lambda v: _isInt(v) and v in (2, 4)),
	# true instantiates the I2CT0 hardware-autonomous I2C target at 0x6A00, page-2 sub-slot 10:
	# 7-bit address match with mask and general call, byte-at-a-time RX/TX with ready/empty
	# status, hardware clock stretching, START/STOP/repeated-START/NACK framing flags, and a
	# stuck-SCL watchdog, all in the free-running MCLK domain with 2-FF SDA/SCL sync and no
	# pad-clocked processes. No new pins: I2CT0 shares the I2C0 SDA0/SCL0 pad planes through an
	# open-drain wired-AND DIR merge. Two combined IRQs: 122 = I2CT0_AE (address/error),
	# 123 = I2CT0_DATA (tx-ready/rx-full); 120 and 121 belong to NPU0 think-done and TRNG0 and
	# backfill as IRQB_RSVD when those blocks are absent, so 122/123 hold under the
	# frozen-numbering rule. NUM_EN_WORDS stays 4. Being mclk-domain, I2CT0 is not bound by the
	# SYS_CLK_CR=0 footgun that binds the smclk I2C0.
	'peripherals.i2ctarget': ('bool: I2CT0 hardware I2C target at 0x6A00, sharing the I2C0 pads',
	                         _isBool),
	# true instantiates the TRNG0 ring-oscillator entropy source and harvest engine at 0x6900,
	# page-2 sub-slot 9. A free-running RO ensemble (NRO rings, 4 or 8 via
	# peripherals.trngRings) is 2-FF synchronized into MCLK, decimated and packed into 32-bit
	# words behind a read-consumes data register (exactly-once consume, DRDY same-cycle
	# blind-window fix), with an SP 800-90B-lite repetition-count health test whose alarm
	# auto-halts harvesting. One combined IRQ (data-ready or health-alarm) at vector 121;
	# vector 120, NPU think-done, is gated by peripherals.npu. NUM_EN_WORDS stays 4.
	# Zero pins: the RO ensemble is internal combinational fabric behind a sim/real
	# architecture split (TrngRoEnsemble_sim.vhd behavioral, TrngRoEnsemble.vhd gate-only),
	# and the two must never co-list. Entropy caveat: bring-up grade, not certified, no
	# hardware conditioner. Firmware must DRBG the raw words and honor ALMF.
	'peripherals.trng':      ('bool: TRNG0 ring-oscillator entropy source at 0x6900 (firmware must DRBG it)',
	                         _isBool),
	# TRNG0 ring-oscillator ensemble size, 4 or 8 only (the NRO generic). Consulted only when
	# peripherals.trng is true; the register map is NRO-invariant, so ROSEL, RCTC and RUNLEN
	# semantics do not change with it.
	'peripherals.trngRings': ('int, 4 or 8: TRNG0 ring count when peripherals.trng is true (default 8)',
	                         lambda v: _isInt(v) and v in (4, 8)),
	# true instantiates the EVFAB0 event and trigger fabric at 0x6B00, page-2 sub-slot 11:
	# a PPI-style crossbar of 8 channels, each an {EVSEL, TASKSEL} pair routing one of 16
	# hardware events to one of 10 hardware tasks as a registered one-MCLK pulse, so
	# peripheral-to-peripheral chains keep running with every hart asleep. Producers are
	# pre-mask SET-condition taps on RTC0, PWM0, TIMER0, TIMER1, UART0, NFC0, DMA0, TRNG0 and
	# I2CT0 plus a GPIO0 masked-edge path; the fabric owns all CDC through the per-input
	# pulse/toggle/level modes in the EV_MODE_TGL and EV_MODE_LVL generic masks. Consumers are
	# DMA0 channel GO, TIMER0 START/STOP, PWM0 fault trip, PWRCTRL tile wake, NPU0 THINK and
	# GPIO0 OUT-SET/OUT-CLR. Every producer or consumer whose block is absent is tied '0'
	# rather than left open, so the knob composes with every other peripheral knob.
	# Vectorless: irq_evfab is a constant '0' and the IE slot is reserved, so NUM_IRQ_SRCS and
	# the frozen vector numbering are untouched. Zero pins; free-running MCLK in the always-on
	# shared domain, which PWRCTRL never gates.
	'peripherals.eventFabric': ('bool: EVFAB0 event/trigger crossbar at 0x6B00 (8 channels, no IRQ vector)',
	                         _isBool),
	# Package model name defined in _PACKAGE_MODELS below: "myshkin-qfn44" QFN-44,
	# "castalia-quad-qfn64" QFN-64 quad pinout, "castalia-lqfp100" LQFP-100 with all 48 GPIO
	# bonded. New pinouts are added as Python models, never as free-form config pin lists.
	'package.model':        ('string: package pinout model, one of the pinout models defined in the generator (QFN-44, QFN-64 quad, or LQFP-100)',
	                         lambda v: isinstance(v, str) and v in _PACKAGE_MODELS),
	'package.preliminary':  ('bool: prints the Preliminary note in the TRM package section',
	                         _isBool),
}

# _CONFIG_META: machine-readable metadata for the same schema keys, exported by
# `make web` to out/web/chip_data.js so the configurator and register browser read
# ranges, enums and defaults instead of re-hardcoding them. The validator lambdas above
# stay authoritative for validation; these fields describe the same constraints
# declaratively, and _checkConfigMeta() below proves the two never disagree.
#   type    : 'bool' | 'int' | 'enum' | 'string'
#   default : the default, equal to the matching _cfg(...) fallback further down
#   min/max : inclusive integer bounds ('int' only; max omitted means unbounded)
#   step    : required integer multiple ('int' only, when the lambda demands one)
#   enum    : allowed values ('enum' only)
_CONFIG_META = {
	'chipName':             {'type': 'string', 'default': 'Castalia'},
	'numHarts':             {'type': 'int', 'default': 5, 'min': 1, 'max': 32},
	# This literal is the schema default; the operative one is the _cfg() fallback below.
	# check_config_defaults.py enforces that the two agree.
	'orchestrator':         {'type': 'bool', 'default': True},
	'numMutexes':           {'type': 'int', 'default': 16, 'min': 1, 'max': 1024},
	'registerFileDualPort': {'type': 'bool', 'default': True},
	# Schema default; the operative one is the _cfg() fallback at _core below, and
	# check_config_defaults.py keeps the two in step. Two further literals behave like
	# defaults under a different rule: the vesta entity generic is false, so a core
	# instantiated with no named association is inert, and the hart_tile/orch_tile wrapper
	# generics are true, so a bare elaborate hardens the macro the assembly wires.
	# tools/python/check_entity_defaults.py polices those.
	'core.fetchAhead':      {'type': 'bool', 'default': True},
	'isa.mul':              {'type': 'bool', 'default': True},
	'isa.fastMul':          {'type': 'bool', 'default': True},
	'isa.div':              {'type': 'bool', 'default': True},
	'isa.atomics':          {'type': 'bool', 'default': True},
	'isa.compressed':       {'type': 'bool', 'default': True},
	'isa.bitmanip':         {'type': 'bool', 'default': True},
	# Schema default; the operative one is the _cfg() fallback in _isa below, and
	# check_config_defaults.py gates the pair.
	'isa.minimalTiles':     {'type': 'bool', 'default': True},
	'isa.counters':         {'type': 'bool', 'default': False},
	'isa.counters64':       {'type': 'bool', 'default': False},
	# X-series ISA extensions, all implemented, default false
	'isa.zicond':           {'type': 'bool', 'default': False},
	'isa.zcb':              {'type': 'bool', 'default': False},
	'isa.zimop':            {'type': 'bool', 'default': False},
	'isa.zihint':           {'type': 'bool', 'default': False},
	'isa.zihpm':            {'type': 'bool', 'default': False},
	'isa.zawrs':            {'type': 'bool', 'default': False},
	'isa.zabha':            {'type': 'bool', 'default': False},
	'isa.zacas':            {'type': 'bool', 'default': False},
	'isa.zicboz':           {'type': 'bool', 'default': False},
	'isa.zcmp':             {'type': 'bool', 'default': False},
	'isa.zcmt':             {'type': 'bool', 'default': False},
	'isa.zbkb':             {'type': 'bool', 'default': False},
	'isa.zbkc':             {'type': 'bool', 'default': False},
	'isa.zbkx':             {'type': 'bool', 'default': False},
	'isa.zkn':              {'type': 'bool', 'default': False},
	'isa.zfinx':            {'type': 'bool', 'default': False},
	# P-series privileged architecture. trapCsr defaults true: boot behaviour is
	# bit-identical because mtrapctl.LEGACY resets 1, so standard delivery is a per-hart
	# firmware opt-in. umode and pmp stay false.
	# These literals are the schema defaults; the operative ones are the _cfg() fallbacks in
	# _priv below. Nothing checks the two agree, so change both together.
	'priv.trapCsr':         {'type': 'bool', 'default': True},
	'priv.umode':           {'type': 'bool', 'default': False},
	'priv.pmp':             {'type': 'bool', 'default': False},
	'priv.pmpEntries':      {'type': 'int', 'default': 16, 'min': 8, 'max': 16, 'step': 8},
	# Core-side debug. The shipped chip carries the Debug Module dm0 and the JTAG DTM dtm0,
	# and the default package is castalia-lqfp100 because it is the only model that bonds the
	# five TAP balls (47 TCK, 48 TMS, 49 TDI, 50 TDO, 51 TRSTn). castalia-quad-qfn64 has all
	# 64 balls committed, so an enabled TAP there would be on-die but unreachable;
	# _checkDebugTransportBonded below refuses to ship that silently.
	# A knob-OFF build is bit-identical to a chip built before core-side debug, but no shipped
	# configuration exercises that arm: prove it in a scratch config.
	# This literal is the schema default; the operative one is the _cfg() fallback in _debug
	# below, and check_config_defaults.py keeps the two in step.
	'debug.enable':         {'type': 'bool', 'default': True},
	# The ROM macro and this literal move together: MCU.template.vhd instantiates the 2048x32
	# rom2k_hvt_pg and mcu_vhd.py's ROM_MACRO_ADDR_BITS is 11, and the concurrent assert at
	# rom0 refuses to elaborate any other combination. The boot image is rv32ic and measures
	# 7,376 bytes. rom2k_hvt_pg is 156.525 x 181.41 against rom_hvt_pg's 156.525 x 325.055:
	# same width, 143.645 um shorter, 22,484 um2 (44.19%) off the MCU floor, slightly faster
	# at every corner. The schema max stays 0x4000, which is the address space the memory map
	# reserves for the ROM page, not a claim that a 16 KiB macro exists; asking for one fails
	# elaboration rather than shipping a map the array does not honour.
	'memory.romSize':            {'type': 'int', 'default': 8192, 'min': 0x400, 'max': 0x4000, 'step': 0x400},
	# The 8 KiB macro sram1p8k_hvt_pg is 319.65 x 208.675 against the 16 KiB
	# sram1p16k_hvt_pg's 319.65 x 383.085: same width, 174.41 um shorter, so it drops into the
	# tile's bottom-left TCM slot without re-plumbing the U-notch floorplan's X axis.
	# The TCM aperture stride stays 0x4000 (tcmWindows below). Apertures are address space,
	# not silicon: packing them to 0x2000 would buy no area and would force the aperture
	# sub-decode off its 16 KiB s_addr(15:12) granularity, so the upper half of each aperture
	# simply reads unmapped. The operative default is the _cfg() fallback at _tcmSize.
	'memory.tcmSizePerHart':     {'type': 'int', 'default': 8192, 'min': 0x400, 'max': 0x4000, 'step': 0x400},
	'memory.sharedBulkRamSize':  {'type': 'int', 'default': 0x10000, 'min': 0x4000, 'step': 0x4000},
	'memory.npuStagingRamSize':  {'type': 'int', 'default': 0x4000, 'min': 0x400, 'max': 0x4000, 'step': 0x400},
	'peripherals.npu':      {'type': 'bool', 'default': True},
	'peripherals.i2c1':     {'type': 'bool', 'default': True},
	'peripherals.uart1':    {'type': 'bool', 'default': True},
	'peripherals.spi1':     {'type': 'bool', 'default': True},
	'peripherals.timer1':   {'type': 'bool', 'default': True},
	'peripherals.cqAfeStubs': {'type': 'bool', 'default': False},
	'peripherals.qspi':     {'type': 'bool', 'default': True},
	'peripherals.i3c':      {'type': 'bool', 'default': True},
	'peripherals.nfc':      {'type': 'bool', 'default': True},
	'peripherals.rtc':      {'type': 'bool', 'default': True},
	'peripherals.pwm':      {'type': 'bool', 'default': True},
	'peripherals.onewire':  {'type': 'bool', 'default': True},
	'peripherals.fieldPower': {'type': 'bool', 'default': True},
	'peripherals.dma':      {'type': 'bool', 'default': True},
	'peripherals.dmaChannels': {'type': 'int', 'default': 4, 'min': 2, 'max': 4, 'step': 2},
	'peripherals.i2ctarget': {'type': 'bool', 'default': True},
	'peripherals.trng':      {'type': 'bool', 'default': True},
	'peripherals.trngRings': {'type': 'int', 'default': 8, 'min': 4, 'max': 8, 'step': 4},
	'peripherals.eventFabric': {'type': 'bool', 'default': True},
	# castalia-lqfp100 is the only model that bonds the TAP (balls 47-51, carved from NC
	# balls), and it is the tape-out product's package. See _checkDebugTransportBonded.
	'package.model':        {'type': 'enum', 'default': 'castalia-lqfp100', 'enum': list(_PACKAGE_MODELS)},
	'package.preliminary':  {'type': 'bool', 'default': True},
}

# Knob groups. `basic` is the shape of the chip most configurations touch: the hart count and
# orchestrator, the fabric knobs, the ISA letters, the memory sizes, the peripheral toggles and
# the package. `advanced` is everything else: the Z-series extensions, the privileged
# architecture, debug, and the int knobs that size a block that is already on. The group is
# presentation metadata only. It changes no default, no validation and no emitted byte; it
# orders the TRM's configuration table, and docs/chip_configurator.html renders the advanced
# knobs collapsed. Anything not matched here is advanced, so a knob added without a thought
# about grouping hides rather than clutters.
_BASIC_KNOBS = ('chipName', 'numHarts', 'orchestrator', 'numMutexes', 'registerFileDualPort',
	'isa.mul', 'isa.fastMul', 'isa.div', 'isa.atomics', 'isa.compressed', 'isa.bitmanip',
	'isa.counters', 'isa.counters64')

def _knobGroup(key):
	if key in _BASIC_KNOBS or key.startswith('memory.') or key.startswith('package.'):
		return 'basic'
	# A bool under peripherals.* turns a block on; an int there sizes a block that is already
	# on (dmaChannels, trngRings), which is a second-order decision.
	if key.startswith('peripherals.') and _CONFIG_META.get(key, {}).get('type') == 'bool':
		return 'basic'
	return 'advanced'

def _checkConfigMeta():
	'''Consistency gate: _CONFIG_META must cover exactly the _CONFIG_SCHEMA keys,
	   and each declared constraint must AGREE with that key's validator lambda
	   (the lambda stays the authority; the metadata must not lie about it).'''
	if set(_CONFIG_META) != set(_CONFIG_SCHEMA):
		raise Exception('_CONFIG_META keys != _CONFIG_SCHEMA keys: '
			+ str(sorted(set(_CONFIG_META) ^ set(_CONFIG_SCHEMA))))
	for k in _CONFIG_SCHEMA:
		desc, check = _CONFIG_SCHEMA[k]
		meta = _CONFIG_META[k]
		if meta.get('group') not in ('basic', 'advanced'):
			raise Exception('_CONFIG_META["' + k + '"] has no basic/advanced group')
		if not check(meta['default']):
			raise Exception('_CONFIG_META["' + k + '"].default ' + repr(meta['default']) + ' fails its own validator')
		t = meta['type']
		if t == 'bool':
			if not (check(True) and check(False)):
				raise Exception('_CONFIG_META["' + k + '"] typed bool but its validator rejects True/False')
		elif t == 'enum':
			for c in meta['enum']:
				if not check(c):
					raise Exception('_CONFIG_META["' + k + '"].enum member ' + repr(c) + ' fails the validator')
			if check('__definitely_not_a_valid_choice__'):
				raise Exception('_CONFIG_META["' + k + '"] typed enum but the validator accepts arbitrary strings')
		elif t == 'int':
			lo = meta.get('min')
			hi = meta.get('max')
			step = meta.get('step', 1)
			if lo is not None:
				if not check(lo):
					raise Exception('_CONFIG_META["' + k + '"].min ' + repr(lo) + ' fails the validator')
				if lo - step > 0 and check(lo - step):
					raise Exception('_CONFIG_META["' + k + '"].min is loose: ' + repr(lo - step) + ' also passes')
			if hi is not None:
				if not check(hi):
					raise Exception('_CONFIG_META["' + k + '"].max ' + repr(hi) + ' fails the validator')
				if check(hi + step):
					raise Exception('_CONFIG_META["' + k + '"].max is loose: ' + repr(hi + step) + ' also passes')
	return True

# An overlay's knobs join the schema here, before the consistency gate, so they are held
# to the same standard as the tree's own: a validator lambda, matching metadata, and a
# default that passes its own validator.
overlay.call('configSchema', schema=_CONFIG_SCHEMA, meta=_CONFIG_META)

# The group is derived, not typed out per key, so it cannot drift from the rule above; an
# overlay that set one explicitly keeps it.
for _k in _CONFIG_META:
	_CONFIG_META[_k].setdefault('group', _knobGroup(_k))

_checkConfigMeta()

def _validateChipConfig(node, path=''):
	'''Walk the loaded JSON: leading-underscore keys are free-form comments,
	   peripheralsPreview is a tolerated planning aid from older configurator
	   exports, everything else must be a schema key with a passing value.'''
	for key in node:
		if key.startswith('_'):
			continue
		dotted = (path + '.' + key) if path else key
		if dotted == 'peripheralsPreview':
			print('[generate] NOTE: config key "peripheralsPreview" is a planning aid — ignored')
			continue
		hasChildren = any(k.startswith(dotted + '.') for k in _CONFIG_SCHEMA)
		if hasChildren and isinstance(node[key], dict):
			_validateChipConfig(node[key], dotted)
			continue
		if dotted not in _CONFIG_SCHEMA:
			valid = '\n'.join('  ' + k + '  — ' + _CONFIG_SCHEMA[k][0] for k in sorted(_CONFIG_SCHEMA))
			raise Exception('Unknown chip-config key "' + dotted + '". Valid keys (all optional):\n' + valid
				+ '\n(Beyond the peripherals.* knobs above the peripheral SET is fixed template content,'
				+ '\n and the pad ring derives from the package model in generate.py — see'
				+ '\n config/PadRing.json for the derived ring.)')
		desc, check = _CONFIG_SCHEMA[dotted]
		if not check(node[key]):
			raise Exception('Chip-config key "' + dotted + '" has invalid value ' + repr(node[key]) + ' — expected: ' + desc)

if _CHIP_CONFIG:
	_validateChipConfig(_CHIP_CONFIG)

def _hexLen(nBytes):
	'''0x-prefixed uppercase-digit length string for a linker-script LENGTH field.'''
	return '0x' + format(int(nBytes), 'X')

# Hart count, hoisted so the per-hart register loops below (CLINT, IRQROUTER) and the
# ChipGenerator call share one value.
numHarts = _cfg('numHarts', 5)

# Orchestrator presence. false is the historical shape: four identical hart_tile corners
# with hart 0 the management hart. true makes hart 0 an always-on soft orchestrator,
# emitted as `entity work.orch_tile`, with harts 1..numHarts-1 as channel tiles.
# This replaced an index-valued `managementHart` knob whose OFF sentinel was 0, which made
# "the orchestrator is hart 0" inexpressible at five independent sites. The management
# hart is now always hart 0 in both shapes, so afe_stub's MGMT_HART generic is never
# overridden and its entity default 0 is correct everywhere; check_entity_defaults.py
# grades exactly that.
orchestrator = _cfg('orchestrator', True)
if orchestrator and numHarts < 2:
	raise Exception('orchestrator requires numHarts >= 2 (hart 0 is the orchestrator, '
		+ 'harts 1..numHarts-1 are the tiles — a one-hart orchestrator has nothing to orchestrate)')

# Mutex count: 16 by default, 32 for the 18-hart Argus chip. Word-mapped at 0x6000 + 4*i;
# the page has room for far more, and the RTL addr port width is clog2(numMutexes)
# (the mutex_bank NMUTEX generic).
numMutexes = _cfg('numMutexes', 16)

# Watchdog passwords: the single source for the TRM, and must equal the RTL constants
# WDT_UNLCK_PASSWD and WDT_CLR_PASSWD in hdl/common/constants.vhd. They feed both the
# SYSTEM register descriptions below and the \WdtUnlockPassword and \WdtClearPassword TRM
# defines, through LatexUserGuide's m.Wdt*Password.
wdtUnlockPassword = 0x5F3759DF	# hdl/common/constants.vhd: WDT_UNLCK_PASSWD x"5f3759df"
wdtClearPassword  = 0xA0C8A620	# hdl/common/constants.vhd: WDT_CLR_PASSWD   x"A0C8A620"
_wdtUnlockHex = '0x%08X' % wdtUnlockPassword
_wdtClearHex  = '0x%08X' % wdtClearPassword

# NPU presence. false makes window slot 10 at 0x4A00 a reserved gap and the 0xC000
# staging-RAM window read zero through the arbiter.
npuPresent = _cfg('peripherals.npu', True)

# I2C1 presence. false makes window slot 15 a dead gap reading zero through the mux
# fall-through, turns its 13 IRQ vectors 70-82 into IRQB_RSVD* with the numbering frozen
# and the RTL ties low, and degrades the SDA1/SCL1 pad planes to hi-Z: P4.2 and P4.3
# revert to plain GPIO26/27 and the P3.2/P3.3 AF1 relocation plane goes unassigned.
i2c1Present = _cfg('peripherals.i2c1', True)

# UART1, SPI1 and TIMER1 presence, on the I2C1 pattern. Each false empties its legacy
# window slot (5, 3, 7) to a dead gap reading zero, reserves its frozen IRQ vectors
# (52-54, 11-12, 22-27) as IRQB_RSVD*, reverts its primary pads to plain GPIO and hi-Zs
# its rows in the AF relocation and output-spread planes. The spread map below is filtered
# before it is applied.
uart1Present = _cfg('peripherals.uart1', True)
spi1Present = _cfg('peripherals.spi1', True)
timer1Present = _cfg('peripherals.timer1', True)

# Page-0 slot 12 (0x4C00) has two mutually exclusive occupants and the raise below is what
# stops a configuration asking for both. The four AFE register stubs plus the shared EIS
# engine stub (afe_stub.vhd instances) take slot 12 and the IRQ-router page top quarter at
# 0x7C00; the QSPI0 controller takes 0x4C00 and IRQ vectors 55 (transfer complete) and 56
# (RX full). The tape-out chip ships QSPI0, so cqAfeStubs defaults false and qspi true; the
# stub bank is still real RTL and asic_default.json selects it. The EIS stub answers to the
# same cqAfeStubs knob because it shares the afe_eis_irq(4:0) vector and the AFE sub-decode
# and read-mux emitters with the four AFE sites.
cqAfeStubsPresent = _cfg('peripherals.cqAfeStubs', False)
qspiPresent = _cfg('peripherals.qspi', True)
if cqAfeStubsPresent and qspiPresent:
	raise Exception('Chip-config conflict: peripherals.cqAfeStubs and peripherals.qspi '
		'both claim page-0 slot 12 (0x4C00) — set cqAfeStubs=false to enable qspi.')

# The overlay derives its own knobs and raises its own conflicts here, with the chip shape
# already resolved. `_overlayVals` is the only channel from this point to every later
# stage: whatever the overlay puts in it, it reads back. The public tree neither writes
# nor reads its contents.
_overlayVals = {'numHarts': numHarts, 'orchestrator': orchestrator,
	'cqAfeStubs': cqAfeStubsPresent}
overlay.call('configResolve', cfg=_cfg, vals=_overlayVals)

# I3C0 takes page-2 (the mutex page, 0x6000-0x6FFF) sub-slot 1 at 0x6100 and carves the
# mutex bank down to sub-slot 0 (0x6000-0x60FF, 256 B). By default the mutex decode
# aliases across the whole page and an aliased read fires the atomic CLAIM side effect,
# so that tightening is a correctness improvement and it ships only when I3C is enabled.
# I3C also grows the IRQ source list from 85 to 94: the meip external-interrupt slot stays
# frozen at IVT slot 85 (m.MeipVector), a reserved never-pending placeholder sits at source
# index 85, and the eight I3C sources (tc, rxf, txe, nack, eod, arb, daa, ibi) sit above it
# at 86-93, reached through the existing meip dispatcher.
i3cPresent = _cfg('peripherals.i3c', True)

# NFC0 takes page-2 sub-slot 2 at 0x6200 and joins I3C's carve; the mutex-decode
# tightening ships whenever I3C or NFC is present. NFC grows the IRQ source list to 98:
# meip stays frozen at slot 85, 86-93 are I3C's or reserved gaps when I3C is off, and NFC's
# four sources sit at 94-97 in NFC.vhd's irq_* port order (field, rxf, txdone, crcerr).
# 98 sources cross a 32-bit boundary, so NFC is the first configuration to need a fourth
# glitch-filter instance; the irq-gf region is geometry-driven. The digital AFE and RF
# interface are off-die, placeholder-tied, with no pads. Enabling NFC does not move
# vectorsCount, which is 121 either way, because 94-97 are already reserved gaps rather
# than new entries above the top; peripheralCount goes 20 to 21.
nfcPresent = _cfg('peripherals.nfc', True)

# RTC0 takes page-2 sub-slot 5 at 0x6500. Zero pins: it clocks off the ungated lfxt_in pad
# crystal, with the LFXT-to-bus CDC synchronizers, the sticky W1C flags and the IRQ
# combiner on the free-running MCLK, not smclk. It needs no falling_edge(EnMemPeriph)
# pre-latch: it is the first library block that is neither combinationalRead nor in
# mcu_vhd.py's CAPTURE_CLOCK set, so it uses the plain raw-strobe shim the GPIO4/5 native
# slaves use. RTC grows the IRQ source list from 114 to 115, vector 114 being the single
# combined alarm/tick source above GPIO5's 106-113. NUM_EN_WORDS stays 4.
rtcPresent = _cfg('peripherals.rtc', True)

# PWM0 takes page-2 sub-slot 6 at 0x6600. Zero input pins: the outputs pwm_out(0) and (1)
# replace two redundant timer-compare spread copies through the replaced-spread-slot
# mechanism, not as AF0 co-tenants and not as new spread-pool members. The whole engine
# (prescaler, 16-bit counter, comparators, shadow commit, sticky FLTF and PEVF flags, IRQ
# combiner) rides the free-running MCLK with no LFXT and no gated clocks, and the register
# file rides ClkMem, which is mclk at integration. Like RTC0 it uses the plain raw-strobe
# shim: neither combinationalRead nor in mcu_vhd.py's CAPTURE_CLOCK set. It extends the IRQ
# source list to 115 = PWM0_FAULT (lower id wins router priority) and 116 = PWM0_EVT.
# NUM_EN_WORDS stays 4.
pwmPresent = _cfg('peripherals.pwm', True)

# OW0 takes page-2 sub-slot 7 at 0x6700. One pad: DQ on P4.7 / GPIO31, alt plane AF2,
# open-drain, rstREN=1, through the replaced-spread-slot mechanism (see the _GPIO_AF_SPREAD
# gate below) rather than an AF1 plane: the slot's redundant T0CMP1 spread copy steps aside
# for it. The engine (OW0DIV time base, slot FSM, DQ 2-FF synchronizer, sticky W1C flags,
# BUSY and PRES, IRQ combiner) rides the free-running MCLK with no gated clocks and no
# clock on the DQ pad, which is pure synchronized data. Like RTC0 and PWM0 it uses the
# plain raw-strobe shim. It extends the IRQ source list to 118, vector 117 being the single
# combined transaction-complete/error source, with 114-116 backfilling as IRQB_RSVD per
# their own knobs. NUM_EN_WORDS stays 4.
onewirePresent = _cfg('peripherals.onewire', True)

# PWRCTRL supervision-input wiring: PGOOD on P6.7/GPIO47, harvested-boot strap on
# P6.6/GPIO46. Both are plain-GPIO direct taps, not AF1 planes, because they must be
# readable before any software runs; the pull defaults make an unfitted board read
# power-good-not-asserted and NORMAL boot. The pwr_ctrl.vhd RTL (PWRWAKE and PWRSTS words
# 5 and 6, the pgood_rstn boot gate) is unconditional, so this knob only decides the
# pad-side ties in the generated pwr0 port map. It is independent of every other knob:
# OW0's DQ sits on P4.7/GPIO31 AF2, so fieldPower and onewire may both be on.
fieldPowerPresent = _cfg('peripherals.fieldPower', True)

# DMA0 takes page-2 sub-slot 8 at 0x6800. Zero pins. It is two peripherals fused: an
# arbiter slave (the register file at 0x6800, on the plain raw-strobe shim like RTC, PWM
# and OW) and an arbiter master (the transfer engine). It is the first new arbiter master
# since the four harts, and the one place a peripheral knob touches shared fabric RTL: the
# master count goes from N=4 to N=5 with the DMA as master index numHarts, the last slice,
# rippling through mp_arbiter (N=>5, MW=>3), resv_unit (N=>5), mutex_bank and irq_router
# (MW=>3), the sh_master declaration (2 -> 3 bits) and the arb_* buses (a fifth slice plus
# the lrsc and lock ties). At numHarts=5 the shipped fabric therefore has nMasters = 6 and
# MW = 3. It extends the IRQ source list to 119: 118 = DMA0_DONE (combined channels-done),
# 119 = DMA0_ERR, with 114-117 backfilling as IRQB_RSVD per their own knobs. NUM_EN_WORDS
# stays 4. dmaChannels (the NCH generic, 2 or 4) is consulted only when dma is true; the
# register map is the 4-channel superset regardless and absent channels read 0.
dmaPresent = _cfg('peripherals.dma', True)
dmaChannels = _cfg('peripherals.dmaChannels', 4)

# I2CT0 takes page-2 sub-slot 10 at 0x6A00: 7-bit address match with mask and general call,
# byte-at-a-time RX/TX with ready and empty status, hardware clock stretching,
# START/STOP/repeated-START/NACK framing flags, and a stuck-SCL watchdog, all in the
# free-running MCLK domain on the plain raw-strobe shim, with 2-FF SDA/SCL sync and no
# pad-clocked processes. No new pins: I2CT0 shares I2C0's SDA0/SCL0 pad planes through an
# open-drain wired-AND DIR merge, which is a separate shared-RTL edit. It extends the IRQ
# source list to 124: 122 = I2CT0_AE (address or error), 123 = I2CT0_DATA (tx-ready or
# rx-full). Vectors 120 and 121 belong to NPU think-done and TRNG0, gated on npuPresent and
# trngPresent in _LIBRARY_TAIL_SPEC, and backfill as IRQB_RSVD120/121 when I2CT0 is the
# highest enabled block, so 122 and 123 hold under the frozen-numbering rule.
# NUM_EN_WORDS stays 4, and 123 is the top live vector in the shipped map.
i2ctargetPresent = _cfg('peripherals.i2ctarget', True)

# TRNG0 takes page-2 sub-slot 9 at 0x6900. A free-running RO ensemble (peripherals.trngRings
# rings, 4 or 8) is 2-FF synchronized into the free-running MCLK domain on the plain
# raw-strobe shim, decimated and packed into 32-bit words behind a read-consumes data
# register (exactly-once consume strobe plus a DRDY same-cycle blind-window fix), with an
# SP 800-90B-lite repetition-count health test whose alarm auto-halts harvesting.
# Zero pins: the RO ensemble is internal combinational fabric behind a sim/real
# architecture split (TrngRoEnsemble_sim.vhd behavioral, TrngRoEnsemble.vhd gate-only),
# and the two must never co-list. It extends the IRQ source list to 122, vector 121 being
# the single combined data-ready or health-alarm source; vector 120, NPU think-done, is
# gated by peripherals.npu. NUM_EN_WORDS stays 4.
# Entropy caveat: bring-up grade, uncertified, no hardware conditioner. Firmware must DRBG
# the output and honor ALMF.
trngPresent = _cfg('peripherals.trng', True)
trngRings = _cfg('peripherals.trngRings', 8)

# EVFAB0 takes page-2 sub-slot 11 at 0x6B00, the last slot the peripheral library uses
# (0x6000 mutex, 0x6100 I3C0, 0x6200 NFC0, 0x6300 GPIO4, 0x6400 GPIO5, 0x6500 RTC0,
# 0x6600 PWM0, 0x6700 OW0, 0x6800 DMA0, 0x6900 TRNG0, 0x6A00 I2CT0). It is a PPI-style
# crossbar of 8 channels, each an {EVSEL, TASKSEL} pair routing one of 16 hardware events
# to one of 10 hardware tasks as a registered one-MCLK pulse, so peripheral-to-peripheral
# chains keep running with every hart in WFI. Zero pins; free-running MCLK in the always-on
# shared domain, which PWRCTRL never gates, on the plain raw-strobe shim.
# Vectorless: the free vector budget is 124-127 and at least two must stay free, so
# irq_evfab is a constant '0', the IE register slot is reserved, and SR.FIREDIF and OVRIF
# are live read-only reductions firmware polls. NUM_IRQ_SRCS and _LIBRARY_TAIL_SPEC are
# untouched by this knob, and spending a vector later would be purely additive.
# Every producer or consumer whose source block is absent is tied '0' at the MCU level,
# never left open, so the fabric composes with every other peripherals.* knob.
eventFabricPresent = _cfg('peripherals.eventFabric', True)

# Global vector rule, binding on every library block. Beyond the 114 unconditional vectors
# 0-113 (legacy, CLINT, the meip placeholder, I3C and NFC reserved-or-real, GPIO4 and
# GPIO5), each optional library block owns a frozen, never-renumbered range in the library
# tail. The emitted IRQ source list extends up to the last vector of the highest enabled
# tail block; every disabled block below that high-water mark backfills its slots as
# IRQB_RSVD<n> so a higher block keeps its number, and nothing is emitted above the highest
# enabled block. Adding a library block is one row here and one row in the emission table
# further down, kept in lockstep by the _LIB_TAIL_BASE cross-check.
# Rows are (name, present, vectorCount), in vector order.
_LIB_TAIL_BASE = 114
_LIBRARY_TAIL_SPEC = [
	('rtc', rtcPresent, 1),   # vector 114        (RTC0 combined alarm/tick)
	('pwm', pwmPresent, 2),   # vectors 115, 116  (PWM0_FAULT, PWM0_EVT)
	('onewire', onewirePresent, 1),  # vector 117  (OW0 combined TC/error)
	('dma', dmaPresent, 2),   # vectors 118, 119  (DMA0_DONE, DMA0_ERR)
	# Vector 120 is NPU think-done, gated by the existing peripherals.npu knob rather than a
	# schema key of its own; 121 is TRNG0, gated by peripherals.trng.
	('npu_thinkdone', npuPresent, 1),  # vector 120  (NPU0 think-done, DP-SG Part A)
	('trng', trngPresent, 1),          # vector 121  (TRNG0 combined data-ready/alarm)
	('i2ctarget', i2ctargetPresent, 2),  # vectors 122, 123  (I2CT0_AE, I2CT0_DATA)
]
# An overlay's blocks take the vectors above the tree's own, in the same
# (name, present, count) shape; with no overlay the list is unchanged.
_LIBRARY_TAIL_SPEC = list(overlay.call('libraryTailVectors', default=_LIBRARY_TAIL_SPEC,
	rows=_LIBRARY_TAIL_SPEC, vals=_overlayVals))
def _libraryTailVectorsCount():
	'''Total vector count = 114 + (last vector of the highest enabled tail block).
	Returns 114 when the whole tail is off (byte-identical default).'''
	_v = _LIB_TAIL_BASE
	_high = _LIB_TAIL_BASE
	for _name, _present, _cnt in _LIBRARY_TAIL_SPEC:
		_v += _cnt
		if _present:
			_high = _v
	return _high
_vectorsCount = _libraryTailVectorsCount()

# Package model selection: which _PACKAGE_MODELS entry builds the pad ring below, and
# whether the TRM package section carries the "Preliminary" banner.
# The default is stated twice, here and in _CONFIG_META, and check_config_defaults.py
# enforces that the two agree.
# The pad ring is documentation plus PnR pad-list data. MCU.vhd and MemoryMap.vhd are
# package-agnostic by construction, since the shared GPIO structure is one table and only
# each bit's package pin number is per-model, so changing the model does not move an RTL
# byte. It does move two documents: the TRM's pinout chapter, and the quad analog
# front-end chapter, which is gated on this model below.
# `package.preliminary` is a separate knob and is deliberately not tied to the model: it
# states whether the bond-out is confirmed, which is a different question from which
# pinout is documented.
packageModel = _cfg('package.model', 'castalia-lqfp100')
packagePreliminary = _cfg('package.preliminary', True)

# Remaining scalar knobs, hoisted so the ChipGenerator(...) call and the resolved-config
# record at the bottom share one value per knob.
_isa = {
	'mul':        _cfg('isa.mul', True),
	'fastMul':    _cfg('isa.fastMul', True),
	'div':        _cfg('isa.div', True),
	'atomics':    _cfg('isa.atomics', True),
	'compressed': _cfg('isa.compressed', True),
	'bitmanip':   _cfg('isa.bitmanip', True),
	'minimalTiles': _cfg('isa.minimalTiles', True),
	'counters':   _cfg('isa.counters', False),
	'counters64': _cfg('isa.counters64', False),
	# Scaffolded extensions, default false, plumbed to the vesta ENABLE_* generics
	'zicond':     _cfg('isa.zicond', False),
	'zcb':        _cfg('isa.zcb', False),
	'zimop':      _cfg('isa.zimop', False),
	'zihint':     _cfg('isa.zihint', False),
	'zihpm':      _cfg('isa.zihpm', False),
	'zawrs':      _cfg('isa.zawrs', False),
	'zabha':      _cfg('isa.zabha', False),
	'zacas':      _cfg('isa.zacas', False),
	'zicboz':     _cfg('isa.zicboz', False),
	'zcmp':       _cfg('isa.zcmp', False),
	'zcmt':       _cfg('isa.zcmt', False),
	'zbkb':       _cfg('isa.zbkb', False),
	'zbkc':       _cfg('isa.zbkc', False),
	'zbkx':       _cfg('isa.zbkx', False),
	'zkn':        _cfg('isa.zkn', False),
	'zfinx':      _cfg('isa.zfinx', False),
}

# Scaffolding gate. An ISA-extension generic may be plumbed end to end ahead of its decode
# logic; a scaffolded name set true would advertise hardware that does not exist, so it is
# a hard error and nothing downstream (misa, the ISA string, the tests) can lie about it.
# The tuple is empty: every knob is implemented. Keep it a tuple: a bare string like
# ('zfinx') without a trailing comma iterates character by character and raises KeyError.
_SCAFFOLDED_ISA = ()   # re-add a name only if an extension is scaffolded ahead of its logic
for _sx in _SCAFFOLDED_ISA:
	if _isa[_sx]:
		raise Exception('isa.' + _sx + ': scaffolded (X0) but not implemented yet')

# Zabha byte and half AMOs reuse the A-extension datapath, so they are meaningless and
# unimplemented without atomics. Hard error, so no config advertises Zabha on a chip that
# lacks LR/SC and AMO.
if _isa['zabha'] and not _isa['atomics']:
	raise Exception('isa.zabha requires isa.atomics (byte/half AMOs build on the A extension)')

# Zacas amocas.{w,b,h} ride the A-extension AMO datapath, so they are meaningless and
# unimplemented without atomics. Hard error. amocas.b and .h additionally require Zabha,
# but Zacas word-only is a legal configuration, so that case is only warned below.
if _isa['zacas'] and not _isa['atomics']:
	raise Exception('isa.zacas requires isa.atomics (compare-and-swap builds on the A extension)')

# Zawrs wrs.nto and wrs.sto wait on the LR reservation set, so maindec gates is_wrs_instr
# on ENABLE_ZAWRS and ENABLE_ATOMICS together and without A the RTL raises
# illegal-instruction on both encodings. Hard error: {zawrs:true, atomics:false} otherwise
# generates an isaString ending _zawrs, which the Spike oracle would retire and the core
# would trap on.
if _isa['zawrs'] and not _isa['atomics']:
	raise Exception('isa.zawrs requires isa.atomics (wrs.nto/wrs.sto wait on the A extension reservation set)')

# Zcmp compressed push, pop and reg-moves are C-quadrant encodings and exist only with the
# C extension. Hard error, so no config advertises Zcmp without compressed decode.
if _isa['zcmp'] and not _isa['compressed']:
	raise Exception('isa.zcmp requires isa.compressed (cm.push/pop live in the C2 quadrant)')

# Zcmt compressed table jump is a C-quadrant encoding plus the jvt CSR.
if _isa['zcmt'] and not _isa['compressed']:
	raise Exception('isa.zcmt requires isa.compressed (cm.jt/cm.jalt live in the C2 quadrant)')

# Privileged-architecture knobs, hoisted like _isa so the ChipGenerator(...) call and the
# resolved-config record at the bottom share one value per knob.
_priv = {
	# This is the operative default: _cfg() returns this value for a config with no priv key,
	# not the schema's. The schema entry at 'priv.trapCsr' must carry the same value, and
	# nothing enforces that, so both sites are marked.
	'trapCsr':    _cfg('priv.trapCsr', True),
	'umode':      _cfg('priv.umode', False),
	'pmp':        _cfg('priv.pmp', False),
	'pmpEntries': _cfg('priv.pmpEntries', 16),
}

# Scaffolding gate, the _SCAFFOLDED_ISA idiom. A privileged-architecture generic may be
# plumbed end to end ahead of its CSR, decode or PMP logic; a scaffolded name set true
# would advertise hardware that does not exist, so it is a hard error and nothing
# downstream (MemoryMap constants, the core_features.h defines the priv tests dispatch on,
# the TRM) can lie about it. The tuple is empty, so the loop below is a provable no-op;
# remove a name from it when its phase lands the real logic.
# Keep it a tuple: a bare ('pmp') without a trailing comma is a string and iterates
# character by character, raising KeyError. `()` is the correct empty form, and `(,)` is a
# syntax error.
_SCAFFOLDED_PRIV = ()
for _sp in _SCAFFOLDED_PRIV:
	if _priv[_sp]:
		raise Exception('priv.' + _sp + ': scaffolded (P0) but not implemented yet')

# U-mode requires the trap CSRs: it has nowhere to store privilege state (mstatus.MPP and
# MPIE) and a U-mode trap has nowhere to land (mepc, mcause, mtvec) without the standard
# trap architecture. Inert while the scaffold gate above fires first.
if _priv['umode'] and not _priv['trapCsr']:
	raise Exception('priv.umode requires priv.trapCsr (U-mode needs mstatus/mepc/mcause/mtvec to trap into)')

# PMP requires U-mode: PMP's protection story is M versus U, and a PMP access fault is an
# exception, which only the standard trap architecture can take. In legacy mode it would
# land in the terminal TRAP_STATE.
if _priv['pmp'] and not _priv['umode']:
	raise Exception('priv.pmp requires priv.umode (PMP protects U-mode; its access faults are standard-mode exceptions)')

# Debug knobs, hoisted like _isa and _priv so the ChipGenerator(...) call and the
# resolved-config record share one value.
_debug = {
	'enable': _cfg('debug.enable', True),
}

# Debug requires trapCsr, and the coupling is decode: maindec gates ebreak_op and the whole
# SYSTEM PRIV_FN3 legality arm on ENABLE_TRAPCSR, so on a trapCsr-OFF build ebreak does not
# decode at all and dcsr.ebreakm would have nothing to interpose on. The chip would carry a
# debug interface that cannot recognise a software breakpoint. Widening ebreak_op's gate
# instead was rejected: it needs two sites moved in lockstep and leaves DRET's legality arm
# behind. vesta.vhd carries a concurrent assert for anyone instantiating the core outside
# the generator. A configuration that sets priv.trapCsr false and names no `debug` key
# takes this default, false, so the two knobs stay consistent by construction.
if _debug['enable'] and not _priv['trapCsr']:
	raise Exception('debug.enable requires priv.trapCsr (ebreak and the SYSTEM PRIV decode arm do not exist without it, so a software breakpoint could never be recognised)')

# Fetch-ahead. Hoisted like _isa/_priv/_debug so the
# ChipGenerator(...) call and the resolved-config record share ONE value.
# No ladder entry below: this knob requires nothing and nothing requires it.
# It is meaningless without the C extension, but it is not ILLEGAL there --
# vesta.vhd ANDs if_ahead_req with ENABLE_COMPRESSED, so on a compressed-OFF
# build the arm is statically '0' and the whole path is inert whatever this
# knob says. A hard error would refuse a legal configuration to no purpose.
_core = {
	'fetchAhead': _cfg('core.fetchAhead', True),
}

_regsDualPort = _cfg('registerFileDualPort', True)
_romSize = _cfg('memory.romSize', 8192)
_tcmSize = _cfg('memory.tcmSizePerHart', 8192)
# The TCM's top address + 1, and therefore the stack pointer's reset value: the
# stack starts at the top of the private TCM and grows down. THIS USED TO BE THE
# LITERAL 0xC000, which silently encoded "the TCM is 16 KiB" in a second place --
# and it FAILED CLOSED the moment the knob moved, which is how it was found:
# ChipGenerator's validator refused 0xC000 against an 8 KiB TCM ending at 0x9FFF
# ("Invalid stack pointer initial value: 49152"). Deriving it is the fix, so the
# knob now has exactly one authority. 16 KiB -> 0xC000 (the historical value,
# unchanged), 8 KiB -> 0xA000.
_ramStart = 0x8000
_stackPointerInit = _ramStart + _tcmSize

def _isaString():
	'''The march string this configuration implements (mirrors the misa CSR
	   advertisement and the configurator's live ISA banner).'''
	s = 'rv32i'
	if _isa['mul'] or _isa['div']:
		s += 'm'
	if _isa['atomics']:
		s += 'a'
	if _isa['compressed']:
		s += 'c'
	if _isa['bitmanip']:
		s += '_zba_zbb_zbs_zbc'
	if _isa['counters']:
		s += '_zicntr'
	# X1 extensions. Simplified march order, matching web_export.py.
	if _isa['zihpm']:
		s += '_zihpm'
	if _isa['zicond']:
		s += '_zicond'
	if _isa['zicboz']:
		s += '_zicboz'
	if _isa['zihint']:
		s += '_zihintpause_zihintntl'
	if _isa['zimop']:
		s += '_zimop'
		if _isa['compressed']:
			s += '_zcmop'
	if _isa['zcb'] and _isa['compressed']:
		s += '_zca_zcb'
	if _isa['zawrs']:
		s += '_zawrs'
	if _isa['zabha']:
		s += '_zabha'
	if _isa['zacas']:
		s += '_zacas'
	if _isa['zcmp']:
		s += '_zcmp'
	if _isa['zcmt']:
		s += '_zcmt'
	# Scalar-crypto bit-manip, no misa bit. Independent of Zbb: Zbkb makes its Zbb-shared
	# subset legal even when Zbb is off.
	if _isa['zbkb']:
		s += '_zbkb'
	if _isa['zbkc']:
		s += '_zbkc'
	if _isa['zbkx']:
		s += '_zbkx'
	# AES and SHA; the Zkn generic is Zknd + Zkne + Zknh. The composite _zkn suffix appears
	# only when Zbkb, Zbkc, Zbkx and Zkn are all on.
	if _isa['zkn']:
		s += '_zknd_zkne_zknh'
		if _isa['zbkb'] and _isa['zbkc'] and _isa['zbkx']:
			s += '_zkn'
	# Zfinx: single-precision FP in the integer register file. misa.F stays 0, because Zfinx
	# explicitly does not set it. Keep identical to web_export.py._isaString().
	if _isa['zfinx']:
		s += '_zfinx'
	return s

# Cross-knob sanity: warnings, not raises, for combinations that are legal but suspicious
if _isa['counters64'] and not _isa['counters']:
	print('[generate] WARNING: isa.counters64 without isa.counters — the 64-bit high halves need the base Zicntr counters')
if (not _isa['atomics']) and numHarts > 1:
	print('[generate] WARNING: isa.atomics=false on a multi-hart chip breaks the LR/SC + AMO + mutex lock infrastructure the sh tests rely on')
# The verified-hart-count record, and the only authority for it. The fact is published
# twice, in the console note below and in web_export.py's `verifiedHarts` bundle, which is
# spliced into docs/chip_configurator.html and drives that page's per-hart-count badge, so
# web_export reads m.VerifiedHarts rather than transcribing the values a second time.
# The bar for membership is a hart count this tree can still build and elaborate today,
# not one that passed a suite once. argus_generation_test proves only that a configuration
# generates and that its JSON parses, which does not meet the bar.
_VERIFIED_HART_COUNTS = [
	(1, 'the single-hart DRC/LVS vehicle, the named matrix row config/asic_default.json'),
	(4, 'the pre-CPR8 four-hart shape, orchestrator=false'),
	(5, 'Castalia-Penta golden master since CPR8, the shipped default, byte-identical drop-in RTL'),
]

# 1 qualifies on elaboration, not on a generation run.
# //opensource_sim/asic_default:asic_default_elaborate binds the hierarchy the
# asic_default configuration emits and runs it to time zero, so MCU.vhd's RomAddrBits
# assert and hart_tile.vhd's RamSize assert both execute;
# //opensource_sim/asic_default:asic_default_boot then boots that chip out of the real
# mask-ROM image and grades the banner the ROM monitor prints on UART0. Both are standing
# bazel tests over the generated RTL. Getting there needed four source fixes: the MCU.vhd
# and riscv_tb.vhd emitters had no N = 1 arm for their 1..N-1 hart loops, pwr_ctrl.vhd
# asserted NHARTS >= 2, and PWRCR's gate field was emitted msb = 0, lsb = 1. The N >= 2
# emission is byte-identical after all four.

# 18 (Argus) is deliberately absent. The shipped per-hart TCM is the 8 KiB
# sram1p8k_hvt_pg macro and hdl/common/hart_tile.vhd closes over it with
# `assert RamSize = 8192 ... severity failure`. RamSize is a MemoryMap package constant,
# not a generic, so no instance can override it, and every Argus row (config/argus.json,
# argus_debug.json and the frozen hdl/argus/MemoryMap.vhd) asks for
# memory.tcmSizePerHart = 16384. An 18-hart build therefore still generates, because the
# schema permits any 1 KiB multiple up to 0x4000, and then fails elaboration in all
# eighteen tiles. Restoring the row means giving Argus an 8 KiB TCM or giving hart_tile
# back its 16 KiB macro, re-running `make verify CONFIG=config/argus.json`, and only then
# adding it back.
_ARGUS_NOTE = ('18 (Argus) was a verified count until 2026-08-16 and is not one now: '
	'hdl/common/hart_tile.vhd asserts RamSize = 8192 with severity failure, and every '
	'Argus configuration asks for memory.tcmSizePerHart = 16384, so an 18-hart build '
	'still generates but no longer elaborates.')


def _verifiedHartsNote():
	'''The one sentence both publication sites use, built from the record above.'''
	parts = ['%d (%s)' % (_n, _d) for _n, _d in _VERIFIED_HART_COUNTS]
	# Guarded because the list has shrunk before: a bare ', '.join(parts[:-1]) + ' and '
	# renders "Only  and 5 (...)" at length 1.
	joined = parts[0] if len(parts) == 1 else ', '.join(parts[:-1]) + ' and ' + parts[-1]
	return ('Only ' + joined + ' are verified hart counts. Other values emit '
		'well-formed but unproven RTL. ' + _ARGUS_NOTE)


if _CHIP_CONFIG and numHarts not in [_n for _n, _d in _VERIFIED_HART_COUNTS]:
	print('[generate] NOTE: numHarts=' + str(numHarts) + ' — ' + _verifiedHartsNote())

# CLINT register-layout formula, which must match hdl/common/clint.vhd: msip[h] at word h;
# mtime lo at word roundup16(4*numHarts)/4; mtimecmp[h] lo and hi at mtime word + 4 + 2h.
# At numHarts=4 this reproduces the original layout exactly (msip 0-3, mtime 4/5,
# mtimecmp 8+2h), which is the no-op gate for the N-hart generalization.
clintMtimeSlot = ((4 * numHarts + 15) // 16) * 4
clintMtimecmpSlot = clintMtimeSlot + 4
clintSlotCount = clintMtimecmpSlot + 2 * numHarts	# words the CLINT decodes

def _clog2(n):
	'''Smallest w with 2**w >= n (matches mcu_vhd.py / the RTL ADDR_W math).'''
	w = 0
	while (1 << w) < n:
		w += 1
	return w

def _slotCountOverride(words):
	'''registerSlotCount for a shared-window peripheral needing `words` register words: None while
	it still fits the 64-word global, so the Castalia description is provably untouched, and the
	count once it does not.
	'''
	return words if words > 64 else None

# Spelled-out counts for TRM prose ("the four harts"); larger counts fall back to digits.
# Mirrors mcu_vhd.py's _HARTS_WORD.
_SPELLED = {2: 'two', 3: 'three', 4: 'four', 5: 'five', 6: 'six', 7: 'seven',
	8: 'eight', 9: 'nine', 10: 'ten', 11: 'eleven', 12: 'twelve', 16: 'sixteen',
	18: 'eighteen', 20: 'twenty', 24: 'twenty-four', 32: 'thirty-two'}
def _spelled(n):
	return _SPELLED.get(n, str(n))


# Create the memory map. A hart's PRIVATE view is its TCM at 0x8000; everything else is the
# arbitrated shared window every hart reaches through mp_arbiter: the single boot ROM at 0x0,
# the peripheral window at 0x4000 (page 0 legacy slots, page 1 CLINT, page 2 mutex bank,
# page 3 IRQ router), the NPU staging RAM at 0xC000, the shared bulk RAM from 0x10000 and
# extended SPI flash above it. Every address and size is knob-derived, so the record of what
# a build actually emitted is out/config/ChipConfig.resolved.json, not this comment.
m = ChipGenerator(
	chipRootDirectory=chipRootDirectory,
	# Where the generated tree lands. Equal to the chip root unless --out was given.
	outputRootDirectory=outputRootDirectory,
	# CHIP_NAME overrides the chip name everywhere it appears (TRM title page, headers, prose,
	# generated file headers): make chip CHIP_NAME=MyChip
	asicName=(os.environ.get('CHIP_NAME') or _cfg('chipName', None) or 'Castalia'),
	asicNameForUserGuide=(os.environ.get('CHIP_NAME') or _cfg('chipName', None) or 'Castalia'),
	mcuUserGuideLatexTemplateFileName='TRM.template.tex',
	numHarts=numHarts,	# hart count; drives the TRM \NumHarts and \NumHartsWord defines, the multi-core feature bullets, and the per-hart generated MCU.vhd regions and CLINT/IRQROUTER register loops below
	romStartAddress=0x0000,
	romSize=_romSize,	# region 0x0-0x1FFF; the page reserves 0x0-0x3FFF, so do not exceed 0x4000
	peripheralMemoryStartAddress=0x4000,
	peripheralMemorySlotCount=16,
	registerMemorySlotsPerPeripheralMemorySlot=64, #Bytes between each peripheral's register memory slots.
	ramStartAddress=_ramStart,
	ramMemorySlotSize=_tcmSize,	# private TCM per tile, region 0x8000-0xBFFF; do not exceed 0x4000
	# Neither 0 nor 1 may appear in ramMemorySlotsAvailable: the ROM and the peripheral memory
	# take slots 0 and 1. Slot 2 (0x8000-0xBFFF) is the one private TCM per tile. The old RAM1
	# slot is the shared NPU staging RAM, an ExtraMemorySection below, and the bulk RAM lives
	# at 0x10000-0x1FFFF behind the arbiter.
	ramMemorySlotsAvailable=[2],
	ramMemorySlotsUsed=[2],
	ramMemorySlotsMuxed={},
	spiFlashProgramAddress=0x8200,
	nativeSpiFlashMemoryReadAccess=True,
	nativeSpiFlashMemoryWriteAccess=False,
	stackPointerInit=_stackPointerInit,	# top of the private TCM, derived from memory.tcmSizePerHart
	bootloaderUsesSpiFlashCommands=True,
	vectorsCount=_vectorsCount,	# 114 unconditional sources: 0-84 legacy including CLINT msip 83 and mtip 84, 85 the meip placeholder, 86-93 I3C (reserved when off), 94-97 NFC (reserved when off), 98-105 GPIO4, 106-113 GPIO5. The library tail extends the count per the global vector rule; the meip slot stays 85 via m.MeipVector below
	padOutPosLogic=True,
	padDIRPosLogic=False,
	padRENPosLogic=False,
	ENABLE_COUNTERS=_isa['counters'],
	ENABLE_COUNTERS64=_isa['counters64'],
	ENABLE_REGS_DUALPORT=_regsDualPort,	# enable for ASIC synthesis with a dual-port register file; disable on Xilinx Spartan 6
	LATCHED_MEM_RDATA=False,
	TWO_STAGE_SHIFT=False,
	BARREL_SHIFTER=False,
	# Core ISA feature switches. These are real hardware knobs: they drive the vesta core's
	# ENABLE_* generics through MemoryMap.vhd's CORE_ENABLE_* constants, decode-gated to the
	# illegal-instruction trap when off, pruned at elaboration and advertised in the read-only
	# misa CSR, as well as feeding the TRM feature list and the MemoryMap.h defines.
	# ENABLE_FAST_MUL, ENABLE_BARREL_SHIFTER and ENABLE_TWO_STAGE_SHIFT are docs-only:
	# vesta's multiplier is single-cycle combinational and its shifter is fixed.
	# Disabling ENABLE_ATOMICS on a multi-hart chip breaks the LR/SC and AMO lock
	# infrastructure the shared-fabric tests rely on.
	COMPRESSED_ISA=_isa['compressed'],
	MINIMAL_TILES=_isa['minimalTiles'],	# asymmetric ISA: harts 1..N-1 built rv32iac (TILE_ENABLE_*), hart 0 keeps the full ISA
	ENABLE_MUL=_isa['mul'],
	ENABLE_FAST_MUL=_isa['fastMul'],
	ENABLE_DIV=_isa['div'],
	ENABLE_ATOMICS=_isa['atomics'],
	ENABLE_BITMANIP=_isa['bitmanip'],
	# Scaffolded ISA extensions, default false; they drive the vesta ENABLE_Z* generics
	ENABLE_ZICOND=_isa['zicond'],
	ENABLE_ZCB=_isa['zcb'],
	ENABLE_ZIMOP=_isa['zimop'],
	ENABLE_ZIHINT=_isa['zihint'],
	ENABLE_ZIHPM=_isa['zihpm'],
	ENABLE_ZAWRS=_isa['zawrs'],
	ENABLE_ZABHA=_isa['zabha'],
	ENABLE_ZACAS=_isa['zacas'],
	ENABLE_ZICBOZ=_isa['zicboz'],
	ENABLE_ZCMP=_isa['zcmp'],
	ENABLE_ZCMT=_isa['zcmt'],
	ENABLE_ZBKB=_isa['zbkb'],
	ENABLE_ZBKC=_isa['zbkc'],
	ENABLE_ZBKX=_isa['zbkx'],
	ENABLE_ZKN=_isa['zkn'],
	ENABLE_ZFINX=_isa['zfinx'],
	# Privileged-architecture generics, default false and 16 entries. They drive the vesta
	# ENABLE_TRAPCSR, ENABLE_UMODE, ENABLE_PMP and PMP_ENTRIES generics through MemoryMap.vhd's
	# CORE_* constants.
	ENABLE_TRAPCSR=_priv['trapCsr'],
	ENABLE_UMODE=_priv['umode'],
	ENABLE_PMP=_priv['pmp'],
	PMP_ENTRIES=_priv['pmpEntries'],
	# Core-side debug mode, default false; drives the vesta and hart_tile ENABLE_DEBUG generic
	# through MemoryMap.vhd's CORE_ENABLE_DEBUG.
	ENABLE_DEBUG=_debug['enable'],
	# Fetch-ahead, default false at the generator API; drives the vesta, hart_tile and
	# orch_tile ENABLE_IF_AHEAD generic through MemoryMap.vhd's CORE_ENABLE_IF_AHEAD.
	ENABLE_IF_AHEAD=_core['fetchAhead'],
	ENABLE_IRQ_FAST_CONTEXT_SWITCHING=False,	# fast context switching saves 745 cycles (31.042 us at 24 MHz) per interrupt and doubles the register file
	ENABLE_IRQ_QREGS=False,	# an ARM "two-port" register file IP has one read-only and one write-only port, so this needs a hand-written HDL register file (x0 reads all zeros)
	ENABLE_IRQ_TIMER=False,
	MASKED_IRQ=0x00000000,	# 32-bit IRQ mask. Any bit that is a '1' is a permanently disabled interrupt vector
	PROGADDR_IRQ=0x9000,	# address of the master IRQ handling function, which is not the interrupt vector table
	lastRamMemorySlotSize=_tcmSize
)

# The meip external-interrupt vector is pinned at IVT slot 85 for this chip family,
# independent of the source count: hart_tile vectors meip via IRQB_EXT_MEIP, not NUM_IRQS-1.
# With I3C the source list grows to 94 and sources 86-93 sit above meip, but IRQB_EXT_MEIP
# stays 85. At 85 sources this reproduces the historic IRQB_EXT_MEIP=85 / NUM_IRQS=86
# emission byte for byte.
m.MeipVector = 85



# Extra memory sections: the shared regions behind the mp_arbiter, reachable by all harts
_npuRamLen = _cfg('memory.npuStagingRamSize', 0x4000)   # region 0xC000-0xFFFF; do not exceed 0x4000
_sharedRamLen = _cfg('memory.sharedBulkRamSize', 0x10000)  # bulk RAM bytes from 0x10000; extended flash begins at the next power of two above the window
if _sharedRamLen % 0x4000 != 0 or _sharedRamLen < 0x4000:
	raise Exception('memory.sharedBulkRamSize must be a positive multiple of 0x4000 (one sram1p16k bank)')

# Shared-window geometry, consumed by mcu_vhd.py's generated regions and recorded here as
# the single source of truth:
#   banks : sram1p16k bank count behind the arbiter, one bank per 16 KiB
#   shAw  : arbiter and tile word-address width. The window is 0x0..2^(shAw+2)-1, the bulk
#           RAM end rounded up to a power of two, and the round-up gap reads zero.
#           Extended flash decodes at exactly 2^(shAw+2), the strict sh_sel complement.
# Castalia at 64 KiB: banks=4, shAw=15, flash at 0x20000.
_sharedRamBanks = _sharedRamLen // 0x4000
shAw = _clog2(0x10000 + _sharedRamLen) - 2
# Memory map v2 gives shAw a second input. An orchestrator config carries the read-only TCM
# apertures at TCMWIN[h] = 0x20000 + h*0x4000 for h = 0..numHarts-1, which need pages
# 1000..1100 of a 4-bit page field, so the shared window must reach 0x3FFFF whatever the
# bulk-RAM size says:
#     shAw = max(derived-from-sharedBulkRamSize, 16)
# Peripheral page layout is unchanged by the widening: the pages widen, the addresses stay.
# Extended flash follows automatically at the strict sh_sel complement 1 << (shAw+2) =
# 0x40000. Never hand-set it, or the double-claim deadlock returns.
if orchestrator and shAw < 16:
	shAw = 16
flashBase = 1 << (shAw + 2)
# The aperture windows, derived once here so no consumer re-derives the arithmetic. Empty
# without an orchestrator.
# The aperture stride is 0x4000 and is not the TCM size. The TCM size is silicon, the
# sram1p*_hvt_pg macro in the tile; the aperture stride is address space. Packing the
# apertures to 0x2000 would buy no area and would force the MCU aperture sub-decode off its
# 16 KiB s_addr(15:12) granularity, the codes 1000..1100, so the stride stays 0x4000 and
# the decode is untouched.
# Consequence: the aperture sequencer carries only sh_addr(10:0) to the tile's
# tcm_ext_addr, because that port is the 8 KiB array's width, so an 8 KiB TCM appears twice
# in its 16 KiB aperture. The upper half mirrors the lower; it is neither unmapped nor zero.
_tcmApertureSize = 0x4000
if _tcmApertureSize % _tcmSize != 0:
	raise Exception('TCM aperture stride 0x%X is not a whole multiple of the TCM size 0x%X, '
		'so the aperture would expose a RAGGED mirror (a partial final copy). Choose a '
		'power-of-two TCM size that divides the stride.' % (_tcmApertureSize, _tcmSize))
if _tcmSize > _tcmApertureSize:
	raise Exception('TCM size 0x%X exceeds the aperture stride 0x%X -- the apertures would '
		'overlap and hart h would read hart h+1\'s memory.' % (_tcmSize, _tcmApertureSize))
tcmWindows = [(0x20000 + _tcmApertureSize * _h) for _h in range(numHarts)] if orchestrator else []
if tcmWindows and tcmWindows[-1] + 0x4000 > flashBase:
	raise Exception('orchestrator: ' + str(numHarts) + ' TCM apertures (top 0x%05X)' % (tcmWindows[-1] + 0x3FFF)
		+ ' do not fit under the shared window top 0x%05X' % (flashBase - 1)
		+ ' — widen memory.sharedBulkRamSize or reduce numHarts')
# Watchdog passwords exposed to LatexUserGuide's \WdtUnlockPassword and \WdtClearPassword
# defines. Single source: the wdt*Password constants above, which equal
# hdl/common/constants.vhd.
m.WdtUnlockPassword = wdtUnlockPassword
m.WdtClearPassword = wdtClearPassword

m.ExtraMemorySections = []
if npuPresent:
	m.ExtraMemorySections.append(
		('NPU_RAM (rwx)', ': ORIGIN = 0x0C000, LENGTH = ' + _hexLen(_npuRamLen), '/* NPU staging RAM (arbitrated; NPU-port-muxed during a THINK) */'))
m.ExtraMemorySections.append(
	('SHARED_RAM (rwx)', ': ORIGIN = 0x10000, LENGTH = ' + _hexLen(_sharedRamLen), '/* arbitrated shared RAM (mailbox region 0x10000-0x107FF zeroed by the bootrom; loader rows at 0x10400) */'))

# Extra hand-written TRM chapters read by the master template, copied into latex/TRM/include/
m.ExtraLatexIntroFiles = ['MULTICORE-intro-castalia-2026-07.tex',
	# The privileged-architecture chapter always renders, because the legacy vectored trap
	# mechanism it documents is the shipping default. Its standard-mode, U-mode and PMP
	# sections are gated by \ifprivtrapcsr, \ifprivumode and \ifprivpmp, emitted from priv.*
	# by LatexUserGuide.py.
	'PRIVARCH-intro-castalia-2026-07.tex',
	# The debug chapter always renders: its JTAG and debug-stack sections are architecture
	# background, and a debug-OFF build still has a true statement to make, namely that the
	# 0x7Bx CSRs and DRET are illegal and there is no port. Its implementation sections are
	# gated by \ifdebugenable, emitted from debug.enable by LatexUserGuide.GenerateDefinesFile().
	'DEBUG-intro-castalia-2026-08.tex']

# Shared window regions drawn in the TRM address space diagram
m.SharedWindowSections = [
	('CLINT', 0x5000, 0x5FFF, 'Core-local interruptor: msip IPIs, mtime/mtimecmp'),
	('Mutex bank', 0x6000, 0x6FFF, 'HW mutex bank: ' + str(numMutexes) + ' word-mapped mutexes, claim-on-read'),
	('IRQ router', 0x7000, 0x7FFF, 'Per-hart peripheral-IRQ enable rows (tile IRQ fan-out)'),
]
if npuPresent:
	m.SharedWindowSections.append(
		('NPU staging RAM', 0xC000, 0xFFFF, 'NPU vector staging RAM (NPU-port-muxed during a THINK)'))
m.SharedWindowSections.append(
	('Shared RAM', 0x10000, 0x10000 + _sharedRamLen - 1, 'Arbitrated shared bulk RAM, ' + str(_sharedRamBanks) + ' banks (locks, mailboxes, inter-hart data)'))
# The read-only TCM apertures: one 16 KiB window per hart through which the management hart
# reads that hart's private TCM. Every other master reads zero. Reads only, because a write
# path into a live core's memory is a coherence hazard the architecture refuses.
for _h, _w in enumerate(tcmWindows):
	m.SharedWindowSections.append(
		('TCM aperture ' + str(_h), _w, _w + 0x3FFF,
		 'Read-only view of hart ' + str(_h) + "'s private TCM (management hart only; a gated tile reads zero)"))



# The register maps come from SystemRDL (tools/rdl/README.md).
# Each peripheral below declares its identity (name, prose, register and bit-field
# prefixes, intro chapter, feature summary) and then loads its registers from
# hdl/common/regs/rdl/<block>.rdl, the description that
# //platform/common:rdl_vs_vhdl_<block>_test re-derives out of the VHDL. There is no second
# copy of a register, a width, an access code, a reset value or a field description in this
# file: a correction is made in the .rdl and reaches the TRM table, MemoryMap.h, the
# configurator and the register browser from there.
# All twenty-two peripherals come from SystemRDL. CLINT, MUTEX, IRQROUTER and PWRCTRL,
# whose register set and field geometry are functions of numHarts, numMutexes, masterW()
# and vectorsCount, are parameterised components: register arrays, expressions in offsets
# and widths, and one description per array with the index rendered where this file's loops
# used to render it. _rdlRegisters() elaborates them with the same knob values the RTL is
# given, so the 1-, 5- and 18-hart configurations come out of one file. PCT has no .rdl and
# no RTL to read one out of.
import rdl_model

def _rdlRegisters(peripheralTemplateName, template, sources=None, parameters=None, defines=None):
	'''Load a peripheral's register templates from its SystemRDL description. `sources` restricts
	which .rdl blocks feed it; `parameters` and `defines` elaborate the four parameterised blocks
	for this file's own numHarts, numMutexes, masterW() and vectorsCount, as given to the RTL.
	'''
	if not rdl_model.rdlSourced(peripheralTemplateName):
		raise Exception('generate.py asks for %s\'s registers from SystemRDL, but '
			'config/rdl.json does not say registerSource "rdl" for it. The two must '
			'agree: either flag it, or keep the hand-written template.'
			% peripheralTemplateName)
	for _rt in rdl_model.registerTemplatesFor(peripheralTemplateName, sources=sources,
	                                          parameters=parameters, defines=defines):
		template.AddRegisterTemplate(_rt)


# SYSTEM
p = PeripheralTemplate(nameTemplate='SYSTEM', description='Controls the entire system, including the clocking and power state. Also has a CRC calculator using the CRC16_CDMA2000 polynomial.', bitFieldPrefix='SYS', latexIntroFileName='SYSTEM-intro-castalia-2026-07.tex', latexFeatureSummary=['A CRC calculation engine (CRC16\\_CDMA2000)', '2$\\times$ internal digitally controllable oscillators', '2$\\times$ external clock pins for clock generation and accurate timing', 'A windowed watchdog timer'])
m.AddPeripheralTemplate(p)

_rdlRegisters('SYSTEM', p)

# SPIx
p = PeripheralTemplate(nameTemplate='SPIx', description='Serial Peripheral Interface. Supports both master and slave modes with configurable data length (8, 16, or 32 bits), clock polarity, clock phase, and byte ordering. SPI0 includes flash extended memory capability for direct memory-mapped access to external SPI flash. SPI1 supports both master and slave modes without flash extended memory.', registerPrefix='SPIx', bitFieldPrefix='SPI', latexIntroFileName='SPI-intro-castalia-2026-07.tex', latexFeatureSummary='{count} SPI interfaces (SPI0 provides memory-mapped access to external flash memory)')
m.AddPeripheralTemplate(p)

_rdlRegisters('SPIx', p)



# GPIOx
p = PeripheralTemplate(nameTemplate='GPIOx', description='General Purpose Input Output', registerPrefix='Px', bitFieldPrefix='Px', latexIntroFileName='GPIO-intro-castalia-2026-07.tex', latexFeatureSummary='{count} 8-pin general purpose I/O (GPIO) ports with edge-triggered interrupts and per-pin multiplexed alternate functions (GPIO + up to 8 alternate functions per pin)')
m.AddPeripheralTemplate(p)

_rdlRegisters('GPIOx', p)



# UARTx
p = PeripheralTemplate(nameTemplate='UARTx', description='Full-duplex Universal Asynchronous Receiver/Transmitter with hardware parity support', registerPrefix='UARTx', bitFieldPrefix='U', latexIntroFileName='UART-intro-castalia-2026-07.tex', latexFeatureSummary='{count} UART interfaces with hardware parity support')
m.AddPeripheralTemplate(p)

_rdlRegisters('UARTx', p)



# TIMERx
p = PeripheralTemplate(nameTemplate='TIMERx', description='32-bit Timer/Counter with input capture, output compare, and pulse-width modulation functionality. Features glitch-free clock source switching and configurable clock division.', registerPrefix='TIMx', bitFieldPrefix='T', latexIntroFileName='TIMER-intro-castalia-2026-07.tex', latexFeatureSummary='{count} 32-bit timers with pulse-width modulation outputs and input capture units')
m.AddPeripheralTemplate(p)

_rdlRegisters('TIMERx', p)



# I2Cx
i2cDescription = 'I2C serial port interface. The master and slave I2C interfaces are split between two sets of registers.\n\n'
i2cDescription += 'To use master transmitter mode, first configure the I2C peripheral by setting I2CMEN, clearing I2CSEN, and configuring I2CMDIV with the appropriate clock division factor, noting that the I2C clock source is SMCLK. To send a start condition, set I2CMST, wait for the I2CMSTS flag to be set (if the bus is busy, the I2C peripheral will wait for it to become idle and then send a start condition), and then clear the status register. I2CMCB will now indicate that the I2C peripheral now has control of the bus as its master. Next, write to I2CxMTX the desired slave address in the most significant 7 bits followed by the desired read/write bit (0 for write/master transmitter) in the least significant bit. Then, wait for I2CMXC or I2CMARB to be set. If I2CMARB is set, then the I2C peripheral has lost the bus arbitration contest and has released control of the bus. If I2CMNR is set, then the desired slave has not acknowledged itself. Clear the status register. Next, send the slave a byte of data by writing the desired data to I2CxMTX. When the I2C peripheral is ready for another byte of data to be queued for transmission, the I2CMTXE flag will be set. Again, wait for I2CMXC or I2CMARB, then check I2CMARB and I2CMNR, and finally clear the status register. Once finished sending all of the desired bytes, either send a stop condition to release control of the bus by setting I2CMSP, or send a repeated start condition to retain control of the bus with a new transmission (and possibly a new slave and read/write mode) by setting I2CMST. Once a stop condition is sent, wait for I2CMSTS to be set, indicating that a stop condition has been sent. Clear the status register.\n\n'
i2cDescription += 'To use master receiver mode, first configure the I2C peripheral by setting I2CMEN, clearing I2CSEN, and configuring I2CMDIV with the appropriate clock division factor, noting that the I2C clock source is SMCLK. To send a start condition, set I2CMST, wait for the I2CMSTS flag to be set (if the bus is busy, the I2C peripheral will wait for it to become idle and then send a start condition), and then clear the status register. I2CMCB will now indicate that the I2C peripheral now has control of the bus as its master. Next, write to I2CxMTX the desired slave address in the most significant 7 bits followed by the desired read/write bit (1 for read/master receiver) in the least significant bit. Then, wait for I2CMXC or I2CMARB to be set. If I2CMARB is set, then the I2C peripheral has lost the bus arbitration contest and has released control of the bus. If I2CMNR is set, then the desired slave has not acknowledged itself. Clear the status register. Next, begin to receive a byte of data from the slave by setting I2CMRB. Wait for I2CMXC to be set. Clear the status register. Read I2CxMRX to get the byte of data received from the slave. To send the slave an ACK and begin to read another byte from the slave, set I2CMRB. Or, to send the slave a NACK and send a stop condition, set I2CMSP. Or, to send the slave a NACK and send a repeated start condition, set I2CMST. Wait for the appropriate flag, then clear the status register.\n\n'
i2cDescription += 'To use slave receiver mode, first configure the I2C peripheral by setting I2CSEN, clearing I2CSEN, clearing I2CSN, and configuring I2CSCS and I2CGCE to the desired values. Note that if clock stretching is enabled with I2CSCS, the I2C peripheral will seize control of the bus by driving SCL low during every ACK/NACK bit transfer (if the I2C peripheral was addressed) until I2CSC is set, which requires user intervention to prevent indefinite hold-ups of the I2C bus. But, if clock stretching is not enabled, the master will be allowed full control of the rate data is sent over the bus, which opens the possibility that the software running on this MCU does not notice that a byte has been transferred in time before the next is transferred. Note that if I2CGCE is set, the I2C peripheral will be addressed if either its address is received or if the general call is received. Wait for the I2C peripheral to be addressed when I2CSA is set. Check I2CSTM to see if the master has requested slave receiver or slave transmitter mode (0 indicates slave receiver). Clear the status register. If clock stretching is enabled, send an ACK or NACK by clearing or setting I2CSN, and then set I2CSC to release SDA and continue with the transfer. If clock stretching is not enabled, the I2C peripheral will automatically ACK or NACK depending on the value of I2CSN. Next, wait for the slave to receive a data byte from the master when I2CSXC is set. If I2CSOVF is set, then the MCU has failed to read one of the bytes sent by the master in the past. Clear the status register, and then read I2CSRX to get the data byte sent from the master. If clock stretching is enabled, send an ACK or NACK by clearing or setting I2CSN, and then set I2CSC to release SDA and continue with the transfer. If clock stretching is not enabled, the I2C peripheral will automatically ACK or NACK depending on the value of I2CSN. Next, wait for I2CSXC, I2CSPR, or I2CSTR to be set, indicating the I2C peripheral has received a new byte of data, a stop condition, or a repeated start condition. If a stop or start condition has been received, clear the status register.\n\n'
i2cDescription += 'To use slave transmitter mode, first configure the I2C peripheral by setting I2CSEN, clearing I2CSEN, clearing I2CSN, and configuring I2CSCS and I2CGCE to the desired values. Note that if clock stretching is enabled with I2CSCS, the I2C peripheral will seize control of the bus by driving SCL low during every ACK/NACK bit transfer (if the I2C peripheral was addressed) until I2CSC is set, which requires user intervention to prevent indefinite hold-ups of the I2C bus. But, if clock stretching is not enabled, the master will be allowed full control of the rate data is sent over the bus, which opens the possibility that the software running on this MCU does not notice that a byte has been transferred in time before the next is transferred. Check I2CSTM to see if the master has requested slave receiver or slave transmitter mode (1 indicates slave transmitter). Clear the status register. Queue the byte of data to transmit to the master by writing the byte to I2CSTX. If clock stretching is enabled, set I2CSC to release SDA and continue with the transfer. If clock stretching is not enabled, the I2C peripheral will automatically ACK or NACK depending on the value of I2CSN. Wait for I2CSTXE to be set, indicating that the I2C peripheral is ready to queue the next byte to send to the master. Clear the status register, and write the next byte to send to the master to I2CxSTX. If clock stretching is enabled, wait for I2CSXC to be set, clear the status register, and set I2CSC. Wait for I2CSTXE, I2CSPR, or I2CSTR to be set, then clear the status register.'
p = PeripheralTemplate(nameTemplate='I2Cx', description=i2cDescription, registerPrefix='I2Cx', bitFieldPrefix='I2C', latexIntroFileName='I2C-intro-castalia-2026-07.tex', latexFeatureSummary='{count} I$^2$C interfaces (both master and slave mode)')
m.AddPeripheralTemplate(p)

_rdlRegisters('I2Cx', p)

# NPU
p = PeripheralTemplate(nameTemplate='NPU', description='Fixed-point multilayer perceptron (MLP) neural network processing unit. Computes a single fully-connected layer of a neural network: given an input vector and a synaptic weight matrix, it produces an output vector. Multiple layers can be computed sequentially by the CPU. Inputs are signed Q0.24 numbers (25 bits); synaptic weights and outputs are signed Q7.24 numbers (32 bits). An optional bias weight and a logistic sigmoid approximation activation function are available. The input vector, output vector, and weight matrix must all reside in the shared NPU staging RAM (the 16 KiB SRAM at 0xC000-0xFFFF, multiplexed between the harts and the NPU compute port). Both the registers and the data path are reachable by every hart through the shared window: any hart may stage the operands in the staging RAM. No hart is put to sleep during a computation; while THINK is set the staging RAM is owned by the NPU, so no hart may access 0xC000-0xFFFF until NPUCR bit 16 (NPUTHINK) reads 0 again.', registerPrefix='NPU', bitFieldPrefix='NPU', latexIntroFileName='NPU-intro-castalia-2026-07.tex', latexFeatureSummary='A neural processing unit (NPU) co-processor for hardware acceleration of machine learning tasks')
# The template is only registered when the NPU exists: an unregistered template emits no
# MemoryMap.h structs and no TRM chapter.
if npuPresent:
	m.AddPeripheralTemplate(p)

_rdlRegisters('NPU', p)



# SARADC (removed)
# SARADC is not on this chip. Peripheral window slot 11 (0x4B00) and IRQ vector 56 are left
# as reserved gaps, so no other peripheral address or vector number moves.



# Opamp (removed)
# DAC, Opamp, AFE and SARADC are not on this chip; see the reserved-gap notes above.



# Pulse counter
p = PeripheralTemplate(nameTemplate='PCT', description='Pulse counter. Counts the number of digital pulses generated by a sensor, such as a Domino Neutron detector or a Geiger-Muller tube.', registerPrefix='PCT', bitFieldPrefix='PCT', latexFeatureSummary='A pulse counter for digital pulse sources (e.g. neutron detectors, Geiger--Muller tubes)')
m.AddPeripheralTemplate(p)

r = RegisterTemplate(nameTemplate='PCTCR', registerMemorySlot=0, size=8, description='Pulse counter control register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='ENPCT0', msb=0, accessibility='rw', description='Enables pulse counter 0', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='ENPCT1', msb=1, accessibility='rw', description='Enables pulse counter 1', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='ENPCT2', msb=2, accessibility='rw', description='Enables pulse counter 2', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='ENPCT3', msb=3, accessibility='rw', description='Enables pulse counter 3', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='ESPCT0', msb=4, accessibility='rw', description='Edge select for pulse counter 0', valueDescriptions=[(0b0, 'Rising edge'), (0b1, 'Falling edge')]))
r.AddBitField(BitField(name='ESPCT1', msb=5, accessibility='rw', description='Edge select for pulse counter 1', valueDescriptions=[(0b0, 'Rising edge'), (0b1, 'Falling edge')]))
r.AddBitField(BitField(name='ESPCT2', msb=6, accessibility='rw', description='Edge select for pulse counter 2', valueDescriptions=[(0b0, 'Rising edge'), (0b1, 'Falling edge')]))
r.AddBitField(BitField(name='ESPCT3', msb=7, accessibility='rw', description='Edge select for pulse counter 3', valueDescriptions=[(0b0, 'Rising edge'), (0b1, 'Falling edge')]))


r = RegisterTemplate(nameTemplate='PCTCNT0', registerMemorySlot=1, size=32, description='Pulse counter 0 count register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PCTCNT0', msb=31, lsb=0, accessibility='r'))

r = RegisterTemplate(nameTemplate='PCTCNT1', registerMemorySlot=2, size=32, description='Pulse counter 1 count register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PCTCNT1', msb=31, lsb=0, accessibility='r'))

r = RegisterTemplate(nameTemplate='PCTCNT2', registerMemorySlot=3, size=32, description='Pulse counter 2 count register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PCTCNT2', msb=31, lsb=0, accessibility='r'))

r = RegisterTemplate(nameTemplate='PCTCNT3', registerMemorySlot=4, size=32, description='Pulse counter 3 count register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PCTCNT3', msb=31, lsb=0, accessibility='r'))



# AFE (removed)
# The AFE (DSADC plus potentiostat front end) is not on this chip. Peripheral window slot
# 12 (0x4C00) and IRQ vector 55 are left as reserved gaps, so no other address or vector
# moves.


# CLINT: the core-local interruptor, shared window page 1 at 0x5000
# The alias granularity follows the decoded word count, the RTL ADDR_W
_clintAliasBytes = 4 << _clog2(clintSlotCount)
p = PeripheralTemplate(nameTemplate='CLINT', description='Core-local interruptor for the ' + _spelled(numHarts) + ' harts. Provides per-hart software interrupts (msip, the inter-processor interrupt mechanism) and a shared free-running 64-bit mtime counter with one 64-bit mtimecmp compare register per hart (timer interrupts). Lives in the shared window behind the multi-core arbiter, so any hart can raise or clear any hart\'s interrupts. The msip and mtip outputs are level interrupts into each hart\'s interrupt vector (vectors 83 and 84); the interrupt service routine must clear the level (write 0 to its MSIP register, or advance its MTIMECMP past mtime) before returning, or the interrupt re-triggers. The block decodes only its low address bits, so its registers alias every ' + str(_clintAliasBytes) + ' bytes throughout 0x5000-0x5FFF.', bitFieldPrefix='CLINT', latexIntroFileName='CLINT-intro-castalia-2026-07.tex')
m.AddPeripheralTemplate(p)

# The register table comes from hdl/common/regs/rdl/clint.rdl, elaborated for this
# configuration: MSIPh is a register array over numHarts, the MTIMECMPhL/H pair is a
# regfile array on an 8-byte stride, and the two word bases are the layout formula above,
# passed in rather than recomputed, so the .rdl and the numbers the RTL is given cannot
# drift apart.
_rdlRegisters('CLINT', p, parameters={
		'NHARTS': numHarts,
		'NHARTS_WORD': _spelled(numHarts),
		'MTIME_W': clintMtimeSlot,
		'CMP_W': clintMtimecmpSlot,
	})



# MUTEX: the hardware mutex bank, shared window page 2 at 0x6000
p = PeripheralTemplate(nameTemplate='MUTEX', description='Hardware mutex bank: ' + _spelled(numMutexes) + ' word-mapped advisory locks providing single-instruction cross-hart mutual exclusion. Because the multi-core arbiter serializes whole shared-window transactions, a read is atomic for free: reading a mutex word returns 0 if the mutex was free and the same transaction claims it for the reading hart (owner becomes hartid+1); reading a held mutex returns the owner\'s marker (hartid+1) and does not disturb it. Writing 0 releases a mutex (deliberately not qualified by owner, so a supervisory hart can force-release a dead hart\'s mutex); nonzero writes are ignored, so ownership cannot be forged. Never access a mutex with LR/SC or AMO instructions -- only plain loads and stores. All mutexes reset to free.', bitFieldPrefix='MTX', latexIntroFileName='MUTEX-intro-castalia-2026-07.tex')
m.AddPeripheralTemplate(p)

# Owner-marker width. hdl/common/mutex_bank.vhd:70-71 reads back
#     rdata_reg              <= (others => '0');
#     rdata_reg(MW downto 0) <= owner(idx);
# so the marker is MW+1 bits at MW:0 and bits 31:MW+1 always read 0. MW is the mp_arbiter
# granted-master width, not a constant: mcu_vhd.py's masterW() sizes it from the arbiter
# master count (harts plus the DMA plus the debug module) and hands the same number to
# mp_arbiter, resv_unit, irq_router and mutex_bank, so the field tracks the configuration.
# The expression below is masterW(), and mcu_vhd.emitMutexInstance cross-checks the two and
# raises if they drift.
# Firmware is unaffected by the width: the release comparison in mutex_bank.vhd is against
# the full written word, so only a store of exactly 0 frees a mutex either way.
_mtxOwnerMsb = max(2, _clog2(numHarts + (1 if dmaPresent else 0) + (1 if _debug['enable'] else 0)))

# The register table comes from hdl/common/regs/rdl/mutex_bank.rdl: NMUTEX registers as one
# array, the owner field MW+1 bits wide, and one owner marker enumerated per hart. The
# enumeration count is a parameter because a SystemRDL enum is a static type whose member
# values must fit the field, and 32 harts need 6 bits while this field is 4.
_rdlRegisters('MUTEX', p, parameters={
		'NMUTEX': numMutexes,
		'MW': _mtxOwnerMsb,
		'NHARTS': numHarts,
	})



# IRQROUTER: PLIC-lite per-hart routing rows and CLAIM/COMPLETE delivery, shared window page 3 at 0x7000
p = PeripheralTemplate(nameTemplate='IRQROUTER', description='THE peripheral interrupt controller (M19): per-hart interrupt routing/enable rows plus a claim/complete delivery stage, programmable by any hart through the shared window. Every deglitched peripheral interrupt level terminates here; the router raises a single external-interrupt wire (meip, interrupt vector 85) to each of the ' + _spelled(numHarts) + ' harts whenever some peripheral source is pending, enabled in that hart\'s row, and not already being serviced. The servicing hart reads CLAIM to atomically discover and claim the lowest-numbered such source (claims are attributed to the reading hart by the shared-bus arbiter, so simultaneous claimers are serialized and each source is delivered exactly once), runs the source\'s handler, clears the interrupt level at the peripheral, and writes the source number back to CLAIM (complete). A source under service is masked from every hart\'s meip until completed; if its level is still high at complete (a new event), it pends again. Priority is fixed: the lowest pending vector number wins. The CLINT vectors 83 (msip) and 84 (mtip) are never delivered through meip (they reach each hart on dedicated hardwired wires), so their row bits are writable but have no effect. All rows reset to 0 (everything masked), so the router is inert until software programs it. Since M19 row 0 is live: hart 0 takes meip like every other hart (the SYSTEM peripheral\'s vectored interrupt controller is retired).', bitFieldPrefix='IRQR', latexIntroFileName='IRQROUTER-intro-castalia-2026-07.tex', latexFeatureSummary='Claim/complete peripheral interrupt delivery (PLIC-style) with any-vector-to-any-hart routing')
m.AddPeripheralTemplate(p)

# The routing rows and the read-only status readback are vectorsCount-driven. Every current
# configuration has more than 96 sources (114 by default, up to 125 wound), so the router
# carries four enable words per hart: the fourth, HhENX at row word 4h+3, covers vectors
# (vectorsCount-1):96, and the status readback has the matching PENDX and INSVCX words at
# 0x781C and 0x782C. The U words are then fully live, vectors 95:64 in bits 31:0. The
# three-word form (U = 84:64, bits 20:0, no X words) survives for configurations of 96
# sources or fewer, as the two guards below.
_irqrXWords = _vectorsCount > 96			# HhENX/PENDX/INSVCX exist
_irqrXMsb   = _vectorsCount - 97			# live msb in the X words (when they exist)
_irqrUMsb   = 31 if _vectorsCount >= 96 else _vectorsCount - 65
_irqrUTop   = min(_vectorsCount, 96) - 1	# top vector covered by the U words

# The register table comes from hdl/common/regs/rdl/irq_router.rdl: one four-word routing
# row per hart as a regfile array, and the U and X field widths as parameters. The two
# shapes SystemRDL cannot parameterise, a register that does not exist and a description
# that reads differently, are preprocessor guards, and both are absent in every
# configuration this generator emits today.
_rdlRegisters('IRQROUTER', p, parameters={
		'NHARTS': numHarts,
		'VECTORS': _vectorsCount,
		'UMSB': _irqrUMsb,
		'UTOP': _irqrUTop,
		'XMSB': max(0, _irqrXMsb),
	}, defines=dict(
		([] if _irqrXWords else [('VESTA_IRQR_NO_XWORDS', '')])
		+ ([] if _irqrUMsb == 31 else [('VESTA_IRQR_U_NARROW', '')])))



# PWRCTRL: the MTCMOS power controller, peripheral-window slot 11 at 0x4B00
# Every hart-count number in this block is numHarts. With the orchestrator at hart 0 the
# always-on hart is hart 0 in both shapes and every hart 1..numHarts-1 is a gateable channel
# tile, so at numHarts=5 PWRCR gains bit 4 and PWRSR gains nibble 4.
# The hart-0 clause is conditional so a non-orchestrator build keeps the historical sentence
# verbatim: this text reaches MemoryMap.json, the register browser page and the TRM, and a
# reworded default would churn all three.
_pwrHart0Clause = ('Hart 0 (the always-on soft orchestrator: SPI boot, console, CLINT owner) is always-on; its bit reads 0 and ignores writes.' if orchestrator else 'Hart 0 (the management hart: SPI boot, console, CLINT owner) is always-on; its bit reads 0 and ignores writes.')
_pwrOrchNote = (' The orchestrator sits outside the MTCMOS fabric entirely (there are no header switches for the centre band), so a gate request for it would be a hardware lie, but it IS hart 0, so that is the same reserved bit 0 every configuration has always had, and a blanket PWRCR write gates every channel tile and leaves the orchestrator running.' if orchestrator else '')
p = PeripheralTemplate(nameTemplate='PWRCTRL', description='Power controller for the switchable hart-tile power domains (M17 MTCMOS cold-gating). Each tile hart (1-' + str(numHarts - 1) + ') sits in its own header-switched power domain; setting that hart\'s gate bit walks a hardware sequencer through the only legal order: isolation clamps on, tile reset asserted, header switches opened (rail off). Clearing the bit reverses it: switches closed, a rail-settle delay, clamps released, reset released, at which point the tile COLD-BOOTS through the shared boot ROM (all state was lost), parks in WFI, and can be relaunched through the boot-ROM loader rows and a CLINT msip exactly as at chip power-on. ' + _pwrHart0Clause + _pwrOrchNote + ' Gate only a parked or otherwise quiesced tile: the hardware cannot deadlock (a clamped request looks released to the arbiter), but any in-flight work on the tile is destroyed; that is what cold-gating means.', bitFieldPrefix='PWR', latexIntroFileName='PWRCTRL-intro-castalia-2026-07.tex', latexFeatureSummary='Per-tile MTCMOS power gating with hardware gate/wake sequencing (cold-boot wake)')
m.AddPeripheralTemplate(p)

# The register table comes from hdl/common/regs/rdl/pwr_ctrl.rdl, elaborated for this
# configuration. Only NHARTS moves: PWRCR.PWRGATE and TASKWKM.PWRTASKWKM span harts
# numHarts-1 downto 1, a range that is empty at numHarts = 1 where the .rdl's vesta_live
# removes the field and leaves its bits reserved, and PWRSR is ceil(numHarts/8) consecutive
# words of one nibble per hart. The two guards below are the word count, which SystemRDL
# cannot express as a parameter because an array dimension must be greater than zero and
# because the single-word register is named PWRSR while the multi-word ones are PWRSR0/1/2.
_pwrsrWords = (numHarts + 7) // 8
_pwrDefines = {}
if _pwrsrWords > 1:
	_pwrDefines['VESTA_PWR_MULTIWORD'] = ''
if _pwrsrWords > 2:
	_pwrDefines['VESTA_PWR_MIDWORDS'] = ''
_rdlRegisters('PWRCTRL', p, parameters={'NHARTS': numHarts}, defines=_pwrDefines)



# Check the peripheral templates for errors
# QSPI0 register template, added unconditionally before CheckPeripheralTemplates so the
# template exists whenever qspiPresent CreatePeripheral()s it at slot 12. With qspi off it
# is never instanced.
if qspiPresent:
	qspi = PeripheralTemplate(nameTemplate='QSPIx', description='Quad Serial Peripheral Interface flash controller. Issues single-/dual-/quad-lane command, address, dummy, and data phases to an external SPI-family memory over a 6-wire bus (SCK, active-low CS, and four bidirectional IO lines). Each phase has an independently configurable lane width, so the same engine drives legacy 1-1-1 flash, dual-output (1-1-2), and quad-output/quad-I/O (1-1-4 / 1-4-4) devices. A transaction is described by the control, command, and address registers and launched by a byte-lane-0 write to QSPIxCMD; the registered read path returns snapshots with no read side effects. The serial core runs in the SMCLK domain (SYS_CLK_CR=0 rule applies), with a programmable baud divider off SMCLK.', registerPrefix='QSPIx', bitFieldPrefix='QSPI', latexIntroFileName='QSPI-intro-castalia-2026-07.tex', latexFeatureSummary='{count} QSPI flash controller (single/dual/quad lane; per-phase width)')
	m.AddPeripheralTemplate(qspi)

	_rdlRegisters('QSPIx', qspi)

# I3C0 register template, added unconditionally before CheckPeripheralTemplates so the
# template exists whenever i3cPresent CreatePeripheral()s it at 0x6100. The serial core is
# smclk-domain, under the SYS_CLK_CR=0 rule; the register read path is registered and has
# no side effects.
if i3cPresent:
	i3c = PeripheralTemplate(nameTemplate='I3Cx', description='I3C controller (MIPI I3C basic, single-controller). Drives an I3C bus (SDA/SCL, open-drain and push-pull SDR) as the active controller, and interoperates with legacy I2C targets on the same wires. This MVP-plus implementation supports single-byte SDR private read/write transfers, repeated-START chaining, Common Command Codes (CCC), hardware Dynamic Address Assignment (DAA via ENTDAA and SETDASA), and In-Band Interrupts (IBI) from targets. A transaction is described by the control and command registers and launched by a byte-lane-0 write to I3CxCMD; the registered read path returns snapshots with no read side effects. The serial core runs in the SMCLK domain (SYS_CLK_CR=0 rule applies) with independent open-drain and push-pull baud dividers.', registerPrefix='I3Cx', bitFieldPrefix='I3C', latexIntroFileName='I3C-intro-castalia-2026-07.tex', latexFeatureSummary='{count} I3C controller (SDR + legacy-I2C, dynamic address assignment, in-band interrupts)')
	m.AddPeripheralTemplate(i3c)

	_rdlRegisters('I3Cx', i3c)
	# Slot 9 is reserved, reads 0, and is deliberately not modelled as a register: an
	# all-unused register generates no _Register_t typedef and breaks the emitted MemoryMap.h.
	# The I3C address window is the 256 B sub-slot, and word 9 simply reads 0.

# NFC0 register template (10 slots at 0x6200), added unconditionally before
# CheckPeripheralTemplates so the template exists whenever nfcPresent CreatePeripheral()s
# it. The bus and CDC core is smclk-domain and the register read path is registered with no
# side effects; the protocol core runs on the off-die carrier-derived rf_clk.
if nfcPresent:
	nfc = PeripheralTemplate(nameTemplate='NFCx', description='NFC controller: ISO/IEC 14443 Type A (14443A) tag / card-emulation digital protocol engine. Emulates a contactless smart-card / tag to an external reader: it recovers the reader-to-tag frames (Miller decode, byte + odd-parity de-framing, CRC_A check), runs the tag transaction state machine (REQA/WUPA to ATQA, bit-frame anticollision by 4-byte UID to SAK, then a Type-2 READ that auto-answers from a firmware-filled payload window), and load-modulates the tag response (Manchester subcarrier at fc/16). The register read path is registered with no read side effects. The block spans three clock domains: the gated memory bus (ClkMem), a free-running SMCLK reference that hosts the clock-domain-crossing synchronizers and write-1-to-clear retirement (the SYS_CLK_CR=0 rule applies), and the AFE carrier-derived rf_clk that clocks the entire protocol core. The 13.56 MHz RF analog front-end is off-die: the block presents only a small digital AFE interface (demodulated RX envelope, field-detect, load-modulation drive, listen-power enable).', registerPrefix='NFCx', bitFieldPrefix='NFC', latexIntroFileName='NFC-intro-castalia-2026-07.tex', latexFeatureSummary='{count} NFC ISO 14443A tag / card-emulation engine (Miller/Manchester codec, CRC-A, anticollision, digital AFE boundary)')
	m.AddPeripheralTemplate(nfc)

	_rdlRegisters('NFCx', nfc)

# RTC0 register template (6 live word slots at 0x6500 plus a reserved TRIM slot), added
# only when rtcPresent CreatePeripheral()s it. The register read path is registered on
# rising ClkMem over data already synchronized into the bus domain: no combinationalRead
# bridge and no CAPTURE_CLOCK pre-latch shim. The wall clock rides the ungated lfxt_in
# domain; the CDC synchronizers, sticky W1C flags and IRQ combiner ride the free-running
# clk, wired to MCLK at integration.
# Driver contract: coherent SEC and SUB reads are up to about one LFXT period (30.5 us)
# stale and a tear-free 47-bit pair needs the SEC-recompare idiom. The count is immune to
# clock reconfiguration and PWRCTRL gating, so a driver must not copy the "write
# SYS_CLK_CR=0 first" rule.
if rtcPresent:
	rtc = PeripheralTemplate(nameTemplate='RTCx', description='Real-Time Clock: a 32.768 kHz always-on wall clock (32-bit seconds + 15-bit subsecond prescaler) with a one-shot alarm compare and a recurring periodic tick, delivered on ONE combined interrupt (vector 114). It clocks off the ungated LFXT crystal, so timekeeping survives clock reconfiguration and PWRCTRL tile power-gating; unlike the SMCLK peripherals it does NOT want SYS_CLK_CR = 0 (the count is immune to the SMCLK source). The {sec, subsecond} pair is one 47-bit counter (the prescaler rolls at exactly 2^15 = 32768, so seconds is literally its carry-out, giving exact 1 Hz). Reads return a coherent double-buffered snapshot synchronized into the bus domain (no read side effects); a torn-free 47-bit pair uses the standard read-SEC / read-SUB / read-SEC-again retry. Set-time and alarm / period updates cross into the LFXT domain through a request/acknowledge handshake reported by SR.SYNC; software must poll SR.SYNC = 0 before the next committing write. The block has zero pins.', registerPrefix='RTCx', bitFieldPrefix='RTC', latexIntroFileName='RTC-intro-castalia-2026-07.tex', latexFeatureSummary='{count} real-time clock (32.768 kHz always-on wall clock, one-shot alarm, periodic tick, single combined IRQ)')
	m.AddPeripheralTemplate(rtc)

	_rdlRegisters('RTCx', rtc)

# An overlay's peripheral templates are built here, with the same two calls the tree's own
# blocks use: AddPeripheralTemplate and _rdlRegisters. Its register descriptions come from
# its own rdl/ and rdl.json through rdl_model.addOverlay, so a private block is described in
# SystemRDL exactly like a public one.
overlay.call('peripheralTemplates', m=m, vals=_overlayVals,
	PeripheralTemplate=PeripheralTemplate, rdlRegisters=_rdlRegisters)
# PWM0 register template (9 word slots at 0x6600), added only when pwmPresent
# CreatePeripheral()s it. The register read path is registered on rising ClkMem over data
# already in the bus/mclk domain: no combinationalRead bridge and no CAPTURE_CLOCK
# pre-latch shim. The engine rides the free-running MCLK, so the count is immune to clock
# reconfiguration and a driver must not write SYS_CLK_CR=0 for the PWM.
# Register behaviour: the waveform words PER, DTY0 and DTY1 are double-buffered, so a write
# stages them and arms UPDF and they commit atomically at the next period boundary; POL is
# immediate; FLTTRIG is a write-1 self-clearing software trip; FLTF and PEVF are sticky W1C.
# The reserved DTY2, DTY3 and DT slots, the CR CH2EN, CH3EN, CNTMODE, DTEN and FLTPOL bits,
# POL[3:2] and [7:6], and SR.DIR are bolt-on reservations for a 4-channel center-aligned
# deadtime variant: they read 0 and break no map.
if pwmPresent:
	pwm = PeripheralTemplate(nameTemplate='PWMx', description='Buffered PWM Generator: a glitch-free 2-channel edge-aligned PWM engine (16-bit period + two 16-bit per-channel duties) with double-buffered waveform update, per-channel polarity and an absolute programmable safe/off level, a software fault trip that forces both outputs safe the same cycle, and a period-event tick. It runs on a prescaled free-running MCLK (no LFXT, no generated clocks); the register file rides the gated bus clock. The three waveform words (period + the two duties) are double-buffered: writes stage into shadow registers and commit atomically at the next period boundary (SR.UPDF reports a pending commit), so a mid-period duty/period change never produces a runt or double pulse. Polarity and the safe level are immediate (program them before enabling). The fault is software/mask-only (no HW pin): with FLTEN set, writing FLTTRIG forces both outputs to their safe levels within one clock and latches SR.FLTF (write-1-to-clear, then the output resumes tracking the still-running comparator). Two lean interrupts are delivered on the router: PWM0_FAULT (vector 115, lower id = router priority) and PWM0_EVT (vector 116). The two channel outputs ride existing bonded AF-spread pins (P2.2/P2.3 AF2); the block has zero input pins. Reserved slots and control bits are provisioned for deferred 4-channel, center-aligned and deadtime/complementary bolt-ons without a register-map break.', registerPrefix='PWMx', bitFieldPrefix='PWM', latexIntroFileName='PWM-intro-castalia-2026-07.tex', latexFeatureSummary='{count} buffered PWM generator (2 channels, glitch-free double-buffered update, software fault trip, period-event tick, two IRQs)')
	m.AddPeripheralTemplate(pwm)

	_rdlRegisters('PWMx', pwm)

# OW0 register template (6 live word slots at 0x6700 plus a reserved SPU slot 6), added
# only when onewirePresent CreatePeripheral()s it. The register read path is registered on
# rising ClkMem over data already in the bus/mclk domain: no combinationalRead bridge and
# no CAPTURE_CLOCK pre-latch shim. The engine rides the free-running MCLK, so a driver must
# not write SYS_CLK_CR=0 for the 1-Wire; OW0DIV calibrates the 0.5 us tick base, DIV=11 at
# 24 MHz.
# OW0CMD is write-only-launch: a byte-lane-0 write captures {OP, BITVAL, ODS, TX} into a
# launch descriptor and starts the slot FSM unless OWEN=0 or BUSY=1. Writes to OW0TX,
# OW0CR and OW0DIV never launch. Results land side-effect-free in OW0RX: RDBIT in [0],
# RDBYTE in [7:0].
# SPUEN (CR bit 2) and OW0SPU (slot 6) are the strong-pullup reservation stub: writable but
# inert, reads 0, no driven-high phase, provisioned so a parasite-power SPU bolts on without
# a register-map break.
if onewirePresent:
	ow = PeripheralTemplate(nameTemplate='OWx', description='1-Wire Master: a Dallas/Maxim 1-Wire link-layer controller that runs the five microsecond-scale bus primitives in hardware (reset+presence, write-bit, read-bit, write-byte and read-byte) off a programmable time base, leaving ROM search and CRC-8 to firmware over those primitives. It is master-only and supports both standard and overdrive speeds (selected by CR.ODS, latched at each transaction launch). A transaction is described by the control and command registers and LAUNCHED by a byte-lane-0 write to OW0CMD (the launch is suppressed while the master is disabled or busy); the registered read path returns status and the received byte with no read side effects. The whole engine (the OW0DIV counter-compare time base, the slot state machine, the two-flop DQ synchronizer, the sticky write-1-to-clear status flags, and the interrupt combiner) rides the free-running MCLK, so the tick base is immune to clock reconfiguration and unlike the SMCLK peripherals a driver must NOT write SYS_CLK_CR to 0. One combined interrupt (transaction-complete or error) is delivered on the router at vector 117. The block has one open-drain DQ pin; the strong-pullup enable and its register slot are a reserved stub (no driven-high phase this stage).', registerPrefix='OWx', bitFieldPrefix='OW', latexIntroFileName='OneWire-intro-castalia-2026-07.tex', latexFeatureSummary='{count} 1-Wire master (reset/presence + bit/byte primitives, standard + overdrive, firmware ROM search + CRC-8, single combined IRQ)')
	m.AddPeripheralTemplate(ow)

	_rdlRegisters('OWx', ow)

# I2CT0 register template (5 live word slots at 0x6A00: I2CTCR, I2CTSR, I2CTTX, I2CTRX,
# I2CTWDG), added only when i2ctargetPresent CreatePeripheral()s it. Registered read on
# rising ClkMem with no bridge and no CAPTURE_CLOCK, on the plain raw-strobe active-low en
# shim. W1C status flags, BUSY same-cycle status rule where applicable, and slots 5 and
# above read 0. bitFieldPrefix I2CT.
if i2ctargetPresent:
	i2ct = PeripheralTemplate(nameTemplate='I2CTx', description='Hardware-Autonomous I2C Target: an I2C slave engine that handles the protocol in hardware: 7-bit address match with a wildcard mask and optional general-call response, byte-at-a-time receive and transmit with ready/empty status, hardware clock stretching for lossless flow control, START / STOP / repeated-START / NACK framing detection, and a configurable stuck-SCL watchdog. The whole engine (the two-flop SDA/SCL synchronizers, the edge/framing detectors, the address matcher, the RX/TX byte paths, the clock-stretch driver, the sticky write-1-to-clear status flags, and the two interrupt combiners) rides the free-running MCLK, so its timing is immune to clock reconfiguration and unlike the SMCLK I2C0/I2C1 cores a driver need not write SYS_CLK_CR to 0 for the target itself. Two combined interrupts are delivered on the router: vector 122 (address/error) and vector 123 (tx-ready/rx-full). It is complementary to the software-serviced slave-mode registers of I2C0/I2C1: I2CT0 shares the same open-drain SDA0/SCL0 pads through a wired-AND merge and needs no per-byte firmware bit-banging. The guaranteed bus-speed floor is f_SCL <= MCLK/24 (Standard 100 kHz and Fast 400 kHz at 24 MHz MCLK).', registerPrefix='I2CTx', bitFieldPrefix='I2CT', latexIntroFileName='I2CT-intro-castalia-2026-07.tex', latexFeatureSummary='{count} hardware-autonomous I2C target (7-bit address match + mask + general call, hardware clock stretching, START/STOP framing flags, single-byte RX/TX with ready/empty status, stuck-SCL watchdog, 2 combined IRQs)')
	m.AddPeripheralTemplate(i2ct)

	_rdlRegisters('I2CTx', i2ct)

# DMA0 register template, the 4-channel superset: 20 word slots at 0x6800, being global CR
# and SR, four fixed-stride per-channel {SRC, DST, LEN, CFG} blocks, DMA0CRC and a reserved
# DMA0DESC. Added only when dmaPresent CreatePeripheral()s it. The map is the 4-channel
# superset regardless of dmaChannels: a 2-channel build reads 0 on the CH2 and CH3 slots
# and their CR and SR bits and ignores writes to them. The register file rides the gated bus
# clock ClkMem, and the read mux registers on rising ClkMem over data already in the mclk
# domain, on the plain raw-strobe shim. No latexIntroFileName: the register tables generate
# but the TRM chapter carries no intro prose yet.
if dmaPresent:
	dma = PeripheralTemplate(nameTemplate='DMAx', description='Configurable multi-channel single-shot DMA controller: it moves words source->dest over the shared arbiter as a stream of single-word transactions, either flat-out under software GO (memory-to-memory) or paced one word per peripheral data-ready event (UART0 RC / QSPI0 RX-full / NFC0 payload-ready), with optional per-channel source/dest auto-increment, a per-channel 2-level priority + word-granular round-robin, an optional CRC16-CDMA2000 ride-along, and a hardware read-side-effect guard (reads targeting the mutex sub-slot window 0x6000-0x60FF or the irq_router CLAIM word 0x7800 raise an error instead of issuing). The channel count is the NCH build generic ({2,4}); this register map is the 4-channel SUPERSET regardless -- on a 2-channel build the CH2/CH3 register blocks and their CR/SR bits read 0 and ignore writes. The whole transfer engine (master-port FSM, per-channel SRC/DST/LEN working counters, round-robin picker, CRC datapath, pacing edge-detectors, sticky W1C flags and the two IRQ combiners) rides the free-running MCLK; the register file rides the gated bus clock. The block has zero pins and delivers two interrupts: DMA0_DONE (combined channels-done, vector 118) and DMA0_ERR (vector 119).', registerPrefix='DMAx', bitFieldPrefix='DMA', latexIntroFileName='DMA-intro-castalia-2026-07.tex', latexFeatureSummary='{count} multi-channel single-shot DMA controller (2/4 channels, peripheral-paced or mem-to-mem, CRC16 ride-along, read-side-effect guard, two IRQs)')
	m.AddPeripheralTemplate(dma)

	_rdlRegisters('DMAx', dma)

# TRNG0 register template (4 live word slots at 0x6900: TRNG0CR, TRNG0SR, TRNG0DR,
# TRNG0HT), added only when trngPresent CreatePeripheral()s it. Registered read on rising
# ClkMem with no bridge and no CAPTURE_CLOCK, on the plain raw-strobe active-low en shim.
# TRNG0DR is the one read-side-effect exception in this library: read consumes, exactly
# once, with a DRDY same-cycle blind-window fix. ALMF is sticky W1C and auto-halts
# harvesting while set. Slots 4 and above read 0. bitFieldPrefix TRNG.
if trngPresent:
	trng = PeripheralTemplate(nameTemplate='TRNGx', description='Ring-oscillator entropy source and harvest engine: a free-running ensemble of NRO ring oscillators (peripherals.trngRings, {4,8}) is XOR-reduced to one noisy bit, 2-FF synchronized into the free-running MCLK, decimated (one raw sample every 2^DECIM MCLK cycles) and direct-packed 32 raw bits at a time into a holding register. A qualified read of the data register returns the word and CONSUMES it in the same access (DRDY clears the same cycle, the next word is requested) so no read ever exposes a stale or partial word; a read while no word is ready returns 0 and has no side effect. A lightweight SP 800-90B-style Repetition Count Test watches the raw stream: when RCTC (or the hardware default of 32) consecutive raw samples are identical it raises a sticky health alarm and AUTO-HALTS harvesting (the rings keep spinning only if EN is set and no alarm is latched) until firmware clears it. The whole engine -- the RO 2-flop synchronizer, the decimator, the 32-bit assembler, the repetition-count health test, the sticky alarm flag, and the interrupt combiner -- rides the free-running MCLK; the register file rides the gated bus clock. The block has zero pins (the RO ensemble is internal combinational fabric) and delivers one combined interrupt (data-ready or health-alarm, vector 121). THE ENTROPY CAVEAT: this is a bring-up-grade entropy source, not a certified one -- firmware MUST run the raw words through a vetted DRBG before using them as key material and MUST honor the health alarm.', registerPrefix='TRNGx', bitFieldPrefix='TRNG', latexIntroFileName='TRNG-intro-castalia-2026-07.tex', latexFeatureSummary='{count} ring-oscillator true-random-number-generator harvest engine (NRO-ring ensemble, read-consumes data register, repetition-count health test with auto-halt, single combined IRQ, bring-up-grade entropy)')
	m.AddPeripheralTemplate(trng)

	_rdlRegisters('TRNGx', trng)


# EVFAB0 register template: a 64-word map at 0x6B00, 13 named word slots plus the
# 16-address CHnCFG array. Added only when eventFabricPresent CreatePeripheral()s it.
# Single instance, so the register names carry no instance index, like PWRCTRL, MUTEX and
# CLINT: EVFCR, EVFSR, ... EVFCH0CFG. Slots 12-14 stay reserved for the earmarked TKSTAT,
# FIREDIE and OVRIE, and slots 32-63 read 0. bitFieldPrefix EVF.
if eventFabricPresent:
	_EVFAB_N_CH = 8			# EVFAB.vhd N_CH generic (live channels; the array is 16 addresses)
	_EVFAB_N_EV = 16		# N_EV generic (live event lines; EVSEL encode space is 32)
	_EVFAB_N_TASK = 10		# N_TASK generic (live task lines; TASKSEL encode space is 16)
	_EVFAB_VER = 1			# VER generic (CAP.VER)
	evfab = PeripheralTemplate(nameTemplate='EVFAB', description='Event/trigger fabric: a PPI-style crossbar that lets peripherals command each other with no processor in the loop. Eight independent channels each hold one {EVSEL, TASKSEL} pair; when the selected EVENT fires and the channel is enabled, the fabric emits a registered one-MCLK pulse on the selected TASK line, one MCLK after the event. Sixteen event lines are wired: RTC0 tick and alarm, PWM0 period and fault, TIMER0 compare0 and overflow, TIMER1 compare0, UART0 receive, NFC0 field-detect and rx-frame, DMA0 channel-0/1 done and error, TRNG0 data-ready, I2CT0 address-match, and a masked GPIO0 pad-edge path (event 15) whose eight raw pad edges are selected by EVFGPIOMASK. Ten task lines are wired: DMA0 channel-0/1 GO, TIMER0 START and STOP, PWM0 fault trip, PWRCTRL tile wake, NPU0 THINK, and GPIO0 output SET and CLEAR (acting on the pins selected by that port\'s PxTASK register). Every event tap is taken from its source flag\'s SET condition BEFORE any interrupt mask, so a chain works with every interrupt disabled, and the fabric owns all clock-domain crossing (each input is a pulse, a toggle or a level according to the block\'s domain, converted by a uniform three-flop front end). The whole block rides the free-running MCLK in the always-on domain: WFI keeps it alive, field-power mode only slows it, and PWRCTRL never gates it -- so chains keep firing with every hart asleep, which is the entire point. A channel is completely inert unless both the global enable and its own channel-enable bit are set; enables are changed through the write-1 CHENSET/CHENCLR aliases so two harts never race a read-modify-write. Sticky FIRED, OVR and EVSTAT words record what happened (EVSTAT records raw events even while the fabric is disabled, which makes a mis-taken post-mask event tap directly observable), and CHTRIG/EVTRIG let firmware inject a channel firing or a raw event with no producer hardware at all. The fabric is never a bus master, never stalls, never rate-limits and never backpressures a consumer: OVR only records that a pulse was degraded (the consumer was busy, or two channels merged onto one task in the same cycle). This version spends no interrupt vector -- the interrupt output is a constant 0 and the EVFIE slot is reserved -- so firmware polls EVFSR, whose two flags are live reductions of the FIRED and OVR words.', registerPrefix='EVF', bitFieldPrefix='EVF', latexIntroFileName='EVFAB-intro-castalia-2026-07.tex', latexFeatureSummary='{count} event/trigger fabric (PPI-style crossbar: ' + str(_EVFAB_N_CH) + ' channels, ' + str(_EVFAB_N_EV) + ' event producers, ' + str(_EVFAB_N_TASK) + ' task consumers, one-MCLK registered pulses, peripheral-to-peripheral chains with every hart asleep)')
	m.AddPeripheralTemplate(evfab)

	_rdlRegisters('EVFAB', evfab)


m.CheckPeripheralTemplates()




# Create the peripherals from the templates and add them to the memory map
# Address assignment, from the MCU.vhd region decode. Every peripheral is an arbiter slave
# in the shared window at its original legacy 0x4000-page address (window page 0, slot =
# legacySlot), spelled out as 0x4000 + 0x100*slot because sharedBus='periph' requires the
# absolute-base form. There is no private peripheral page.
# sharedBus, combinationalRead, clockDomain and strobeNote are the per-peripheral bus
# metadata python/mcu_vhd.py consumes when generating MCU.vhd. sharedBus='periph' is the
# standard register bus bridged onto the mp_arbiter through the active-low en/wen shim;
# 'native' speaks the arbiter slave protocol directly. combinationalRead=True means the read
# path collapses when en deasserts, so the MCU side needs a bridge register at the
# LATCH-to-DATA edge, never a stretched en strobe.
GPIO0 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=1, absoluteBaseAddress=0x4000, legacySlot=0, sharedBus='periph', clockDomain='mclk')	# GPIO0; the bootrom programs the flash CS through it, via the arbiter
GPIO1 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=1, peripheralMemorySlot=None, interruptPriority=28, absoluteBaseAddress=0x4100, legacySlot=1, sharedBus='periph', clockDomain='mclk')	# GPIO1 shared (slot 1)
m.CreatePeripheral(nameTemplate='SPIx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=9, absoluteBaseAddress=0x4200, legacySlot=2, sharedBus='periph', clockDomain='smclk', strobeNote='reading SPI0RX auto-clears TCIF')	# SPI0; its flash and XIP port stays on hart 0's >=0x20000 decode
if spi1Present:
	m.CreatePeripheral(nameTemplate='SPIx', nameIndex=1, peripheralMemorySlot=None, interruptPriority=11, absoluteBaseAddress=0x4300, legacySlot=3, sharedBus='periph', clockDomain='smclk', strobeNote='reading SPI1RX auto-clears TCIF')	# SPI1 shared (slot 3; config-droppable since G1b)
m.CreatePeripheral(nameTemplate='UARTx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=13, absoluteBaseAddress=0x4400, legacySlot=4, sharedBus='periph', clockDomain='smclk')	# UART0, the shared console UART, at its original 0x4400
if uart1Present:
	m.CreatePeripheral(nameTemplate='UARTx', nameIndex=1, peripheralMemorySlot=None, interruptPriority=52, absoluteBaseAddress=0x4500, legacySlot=5, sharedBus='periph', clockDomain='smclk')	# UART1 shared (slot 5; config-droppable since G1b)
m.CreatePeripheral(nameTemplate='TIMERx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=16, absoluteBaseAddress=0x4600, legacySlot=6, sharedBus='periph', clockDomain='muxed', strobeNote='ClockMuxGlitchFree needs 3 edges of the OLD source to release; poll-until-counting after enable')	# TIMER0 shared (slot 6)
if timer1Present:
	m.CreatePeripheral(nameTemplate='TIMERx', nameIndex=1, peripheralMemorySlot=None, interruptPriority=22, absoluteBaseAddress=0x4700, legacySlot=7, sharedBus='periph', clockDomain='muxed', strobeNote='ClockMuxGlitchFree needs 3 edges of the OLD source to release; poll-until-counting after enable')	# TIMER1 shared (slot 7; config-droppable since G1b)
GPIO2 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=2, peripheralMemorySlot=None, interruptPriority=36, absoluteBaseAddress=0x4800, legacySlot=8, sharedBus='periph', clockDomain='mclk')	# GPIO2 shared (slot 8)
m.CreatePeripheral(nameTemplate='SYSTEM', nameIndex='', peripheralMemorySlot=None, interruptPriority=0, absoluteBaseAddress=0x4900, legacySlot=9, sharedBus='periph', clockDomain='mclk', strobeNote='SYS_CLK_CR/SYS_CLK_DIV_CR reconfigure MCLK itself: quiesce the other harts before clock reconfiguration (software contract)')	# SYSTEM: clock, power and WDT monarch, hart-0 management by convention
if npuPresent:
	m.CreatePeripheral(nameTemplate='NPU', nameIndex='', peripheralMemorySlot=None, interruptPriority=120, absoluteBaseAddress=0x4A00, legacySlot=10, sharedBus='periph', combinationalRead=True, clockDomain='mclk', strobeNote='vectors live in the shared NPU staging RAM at 0xC000; do not touch 0xC000-0xFFFF during a THINK — poll NPUCR bit 16 (or take the vector-120 think-done IRQ, DP-SG)')	# NPU register bus; the data path is the 0xC000 staging RAM
# SARADC is absent (vector 56 is a reserved gap; slot 11 belongs to PWRCTRL).
# The AFE has no CreatePeripheral: when peripherals.cqAfeStubs is set, the four AFE and one
# EIS afe_stub instances occupy slot 12 and 0x7C00 as MCU.vhd wiring only. With cqAfeStubs
# false the QSPI0 controller below can claim slot 12 instead.
m.CreatePeripheral(nameTemplate='PWRCTRL', nameIndex='', peripheralMemorySlot=None, interruptPriority=None, absoluteBaseAddress=0x4B00, legacySlot=11, sharedBus='native', clockDomain='mclk', strobeNote='cold-gate: a gated tile loses all state and reboots through the shared ROM on wake; gate only parked/quiesced tiles')	# power controller, slot 11, native arbiter slave
if qspiPresent:
	m.CreatePeripheral(nameTemplate='QSPIx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=55, absoluteBaseAddress=0x4C00, legacySlot=12, sharedBus='periph', clockDomain='smclk')	# QSPI0, slot 12; registered read, no bridge, no RX read side effects
GPIO3 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=3, peripheralMemorySlot=None, interruptPriority=44, absoluteBaseAddress=0x4D00, legacySlot=13, sharedBus='periph', clockDomain='mclk')	# GPIO3 shared (slot 13)
m.CreatePeripheral(nameTemplate='I2Cx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=57, absoluteBaseAddress=0x4E00, legacySlot=14, sharedBus='periph', combinationalRead=True, clockDomain='smclk')	# I2C0 shared (slot 14)
if i2c1Present:
	m.CreatePeripheral(nameTemplate='I2Cx', nameIndex=1, peripheralMemorySlot=None, interruptPriority=70, absoluteBaseAddress=0x4F00, legacySlot=15, sharedBus='periph', combinationalRead=True, clockDomain='smclk')	# I2C1 shared (slot 15; config-droppable since G1a)

# Shared-window peripherals, behind the mp_arbiter and reachable by all harts.
# The three whole-page native slaves may outgrow the 64-word page-0 slot pitch at large hart
# counts (IRQROUTER rows at 4h need word 68 at h=17), so registerSlotCount is the
# per-peripheral engine override, left None while it fits.
m.CreatePeripheral(nameTemplate='CLINT', nameIndex='', peripheralMemorySlot=None, interruptPriority=83, absoluteBaseAddress=0x5000, sharedBus='native', clockDomain='mclk', registerSlotCount=_slotCountOverride(clintSlotCount))	# CLINT at 0x5000, window page 1; vectors 83 msip and 84 mtip
m.CreatePeripheral(nameTemplate='MUTEX', nameIndex='', peripheralMemorySlot=None, interruptPriority=None, absoluteBaseAddress=0x6000, sharedBus='native', clockDomain='mclk', strobeNote='READ = atomic return-old-and-claim; never LR/SC or AMO a mutex address', registerSlotCount=_slotCountOverride(numMutexes))	# HW mutex bank at 0x6000, window page 2; the decode tightens to sub-slot 0 (0x6000-0x60FF) when any page-2 device is present
if i3cPresent:
	# I3C0 at 0x6100 is mutex-page sub-slot 1. sharedBus is left None on purpose: the mutex
	# page is not the page-0 shim fabric, so the RTL (decode carve, instance, and the registered
	# read shim inside emitI3cInstance) is hand-emitted by mcu_vhd.py under geo['i3c']. This
	# CreatePeripheral exists for the register map, TRM chapter, address table and the
	# vectors-86..93 interrupt-table entry.
	m.CreatePeripheral(nameTemplate='I3Cx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=86, absoluteBaseAddress=0x6100, sharedBus='native', clockDomain='smclk', strobeNote='page-2 sub-slot 1; registered read, no side effects; smclk serial core (SYS_CLK_CR=0 rule)')	# I3C0. sharedBus='native' means outside the page-0 shim fabric; the mcu_vhd emitter hand-decodes the sub-slot and emits the registered-read shim inside its instance
if nfcPresent:
	# NFC0 at 0x6200 is mutex-page sub-slot 2, the same shape as I3C: sharedBus=None, so the
	# mcu_vhd emitter hand-decodes the sub-slot and emits the registered-read shim and instance
	# under geo['nfc']. This CreatePeripheral exists for the register map, TRM chapter, address
	# table and the vectors-94..97 interrupt-table entry. clockDomain='smclk' names the bus and
	# CDC reference clock; the protocol core runs on the off-die rf_clk.
	m.CreatePeripheral(nameTemplate='NFCx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=94, absoluteBaseAddress=0x6200, sharedBus='native', clockDomain='smclk', strobeNote='page-2 sub-slot 2; registered read, no side effects; smclk CDC + off-die rf_clk protocol core (SYS_CLK_CR=0 rule); digital AFE / RF interface is off-die (placeholder-tied)')	# NFC0. sharedBus='native' means outside the page-0 shim fabric; the mcu_vhd emitter hand-decodes the sub-slot and emits the registered-read shim inside its instance
# GPIO4 (port 5) at 0x6300 and GPIO5 (port 6) at 0x6400 are mutex-page sub-slots 3 and 4,
# and are present in every configuration like GPIO0-3. Same page-2 native shape as I3C0 and
# NFC0, outside the page-0 shim fabric, but the instance is a full GPIO block with a
# registered-read shim and AF muxing: mcu_vhd.py hand-decodes the sub-slot and emits the
# shim, the GPIO component and the AF planes. Their pins carry the QSPI and I3C (P5) and NFC
# (P6) functions on AF1 when those controllers are present, and plain GPIO otherwise.
GPIO4 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=4, peripheralMemorySlot=None, interruptPriority=98, absoluteBaseAddress=0x6300, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 3; registered read; AF1 = QSPI0 (P5.0-5) + I3C0 (P5.6/7) pin functions when present')	# GPIO4: native page-2 sub-slot 3; mcu_vhd emits the shim, the GPIO instance and the AF planes
GPIO5 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=5, peripheralMemorySlot=None, interruptPriority=106, absoluteBaseAddress=0x6400, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 4; registered read; AF1 = NFC0 digital-AFE pin functions (P6.0-5) when present')	# GPIO5: native page-2 sub-slot 4; mcu_vhd emits the shim, the GPIO instance and the AF planes
if rtcPresent:
	# RTC0 at 0x6500 is mutex-page sub-slot 5, the same native page-2 shape as I3C0, NFC0,
	# GPIO4 and GPIO5: sharedBus='native' means outside the page-0 shim fabric, and the
	# mutex-bank decode is already tightened to sub-slot 0 whenever any page-2 sub-slot device
	# is present. This CreatePeripheral exists for the register map, TRM chapter, address table
	# and the vector-114 interrupt-table entry; the RTL is hand-emitted by mcu_vhd.py under
	# geo['rtc']. clockDomain='mclk' names both the bus clock ClkMem and the free-running CDC,
	# flag and IRQ reference clock; the wall clock itself rides the ungated lfxt_in pad crystal.
	# The instance is neither combinationalRead nor a CAPTURE_CLOCK slave: it uses a plain
	# raw-strobe active-low en shim, rtc0_sh_en_n <= not shslv_rtc0_en, with no
	# falling_edge(EnMemPeriph) pre-latch.
	m.CreatePeripheral(nameTemplate='RTCx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=114, absoluteBaseAddress=0x6500, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 5; registered read, no bridge, no CAPTURE_CLOCK pre-latch; ungated lfxt_in wall clock (D1); count immune to SYS_CLK_CR (do NOT write SYS_CLK_CR=0 for the RTC)')	# RTC0: native page-2 sub-slot 5; mcu_vhd emits the raw-strobe shim and the RTC instance
if pwmPresent:
	# PWM0 at 0x6600 is mutex-page sub-slot 6, the same native page-2 shape as RTC0. This
	# CreatePeripheral exists for the register map, TRM chapter, address table and the
	# vector-115 interrupt-table entry; interruptPriority=115 is the first of PWM's two frozen
	# vectors, 115 and 116. The RTL (sub-slot 6 decode, the raw-strobe registered-read shim,
	# the PWM instance and the two pwm_out spread aliases) is hand-emitted by mcu_vhd.py under
	# geo['pwm']. clockDomain='mclk' names both the bus clock ClkMem and the free-running engine
	# clock: prescaler, counter, compare, flags and IRQ are all on MCLK. Neither
	# combinationalRead nor a CAPTURE_CLOCK slave: a plain raw-strobe active-low en shim,
	# pwm0_sh_en_n <= not shslv_pwm0_en, with no falling_edge(EnMemPeriph) pre-latch.
	m.CreatePeripheral(nameTemplate='PWMx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=115, absoluteBaseAddress=0x6600, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 6; registered read, no bridge, no CAPTURE_CLOCK pre-latch; free-running MCLK engine (no LFXT, no generated clocks); count immune to SYS_CLK_CR (do NOT write SYS_CLK_CR=0 for the PWM); pwm_out(0)/(1) replace P2.2/P2.3 AF2 spread slots (A7)')	# PWM0: native page-2 sub-slot 6; mcu_vhd emits the raw-strobe shim, the PWM instance and the spread aliases
if onewirePresent:
	# OW0 at 0x6700 is mutex-page sub-slot 7, the same native page-2 shape as RTC0 and PWM0.
	# This CreatePeripheral exists for the register map, TRM chapter, address table and the
	# vector-117 interrupt-table entry, OW0's single frozen vector. The RTL (sub-slot 7 decode,
	# the raw-strobe registered-read shim, the OneWire instance and the DQ input mux and ren
	# alias) is hand-emitted by mcu_vhd.py under geo['onewire']; the DQ output and DIR plane
	# comes from the P4.7 AF2 spread slot. clockDomain='mclk' names both the bus clock ClkMem
	# and the free-running engine clock: time base, slot FSM, DQ synchronizer, flags and IRQ
	# are all on MCLK. Neither combinationalRead nor a CAPTURE_CLOCK slave: a plain raw-strobe
	# active-low en shim, ow0_sh_en_n <= not shslv_ow0_en, with no falling_edge(EnMemPeriph)
	# pre-latch.
	m.CreatePeripheral(nameTemplate='OWx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=117, absoluteBaseAddress=0x6700, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 7; registered read, no bridge, no CAPTURE_CLOCK pre-latch; free-running MCLK engine (no LFXT, no generated clocks, no clock on the DQ pad); count immune to SYS_CLK_CR (do NOT write SYS_CLK_CR=0 for the 1-Wire); DQ on P4.7/GPIO31 AF2 open-drain (rstREN=1, replaced-spread-slot)')	# OW0: native page-2 sub-slot 7; mcu_vhd emits the raw-strobe shim, the OneWire instance and the P4.7 AF2 DQ routing
if i2ctargetPresent:
	# I2CT0 at 0x6A00 is mutex-page sub-slot 10, the same native page-2 shape as RTC0. This
	# CreatePeripheral exists for the register map, TRM chapter, address table and the
	# vector-122 interrupt-table entry; interruptPriority=122 is the first of I2CT0's two frozen
	# vectors, 122 and 123. clockDomain='mclk' names both the bus clock ClkMem and the
	# free-running engine clock: the target FSM, the SDA and SCL 2-FF sync, the flags, the
	# watchdog and the IRQ combiners are all on MCLK. Neither combinationalRead nor a
	# CAPTURE_CLOCK slave: a plain raw-strobe active-low en shim, i2ct0_sh_en_n <= not
	# shslv_i2ct0_en, with no falling_edge(EnMemPeriph) pre-latch. No new pins: I2CT0 shares
	# I2C0's SDA0/SCL0 pad planes through a wired-AND DIR merge, emitted separately. The RTL
	# (sub-slot 10 decode, raw-strobe shim, the I2CTarget instance, the SDA_IN and SCL_IN
	# fanout and the i2ct0_*_dir scalars) is hand-emitted by mcu_vhd.py under geo['i2ctarget'].
	m.CreatePeripheral(nameTemplate='I2CTx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=122, absoluteBaseAddress=0x6A00, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 10; registered read, no bridge, no CAPTURE_CLOCK pre-latch; free-running MCLK engine (whole target FSM + SDA/SCL 2-FF sync + flags + watchdog + IRQ on MCLK); count immune to SYS_CLK_CR (do NOT write SYS_CLK_CR=0 for the target); shares I2C0 SDA0/SCL0 pads via a wired-AND DIR merge, no new pins')	# I2CT0: native page-2 sub-slot 10; mcu_vhd emits the raw-strobe shim, the I2CTarget instance, the SDA and SCL fanout and the i2ct0_*_dir scalars
if dmaPresent:
	# DMA0 at 0x6800 is mutex-page sub-slot 8, the same native page-2 slave shape as RTC0.
	# This CreatePeripheral exists for the register map, TRM chapter, address table and the
	# vector-118 interrupt-table entry; interruptPriority=118 is the first of DMA's two frozen
	# vectors, 118 and 119. clockDomain='mclk' names both the bus clock ClkMem and the
	# free-running engine and master-port clock. Neither combinationalRead nor a CAPTURE_CLOCK
	# slave: a plain raw-strobe active-low en shim, dma0_sh_en_n <= not shslv_dma0_en, with no
	# falling_edge(EnMemPeriph) pre-latch.
	# Unlike every other library block DMA0 is also an arbiter master, slice numHarts of arb_*.
	# The sub-slot-8 decode, the raw-strobe read shim, the dma0 instance (NCH => dmaChannels)
	# and the N to N+1 fabric widening (the mp_arbiter, resv_unit, mutex_bank and irq_router
	# generics, the arb_* fifth slice with its lrsc and lock ties, the trigger taps and the two
	# irq levels) are all hand-emitted by mcu_vhd.py under geo['dma'] and geo['dmaChannels'].
	m.CreatePeripheral(nameTemplate='DMAx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=118, absoluteBaseAddress=0x6800, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 8; registered read, no bridge, no CAPTURE_CLOCK pre-latch; free-running MCLK engine + arbiter MASTER (slice numHarts); enabling DMA widens the arbiter N=4->5 / MW=3, sh_master 2->3 bits (the ONE shared-fabric touch); read-side-effect guard denies engine reads of 0x6000-0x60FF / 0x7800')	# DMA0: native page-2 sub-slot 8 and the first new arbiter master; mcu_vhd emits the raw-strobe shim, the dma0 instance and the fabric widening
if trngPresent:
	# TRNG0 at 0x6900 is mutex-page sub-slot 9, the same native page-2 shape as RTC0. This
	# CreatePeripheral exists for the register map, TRM chapter, address table and the
	# vector-121 interrupt-table entry, TRNG0's single combined source. clockDomain='mclk'
	# names both the bus clock ClkMem and the free-running engine clock: the RO 2-FF sync, the
	# decimator, the assembler, the health test and the IRQ combiner are all on MCLK. Neither
	# combinationalRead nor a CAPTURE_CLOCK slave: a plain raw-strobe active-low en shim,
	# trng0_sh_en_n <= not shslv_trng0_en, with no falling_edge(EnMemPeriph) pre-latch.
	# No pins: the RO ensemble u_ro (TrngRoEnsemble) is a sibling MCU.vhd instance wired
	# through trng0's ro_enable, ro_sel, ro_sclk and ro_raw ports, never a pad. The sub-slot-9
	# decode, the raw-strobe shim and the trng0 and u_ro instances (NRO => trngRings) are
	# hand-emitted by mcu_vhd.py under geo['trng'] and geo['trngRings'].
	# Bring-up-grade entropy only: firmware must DRBG the output and honor ALMF.
	m.CreatePeripheral(nameTemplate='TRNGx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=121, absoluteBaseAddress=0x6900, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 9; registered read, no bridge, no CAPTURE_CLOCK pre-latch; free-running MCLK harvest engine (RO 2-FF sync, decimator, assembler, repetition-count health test); do not poll TRNG0DR blindly -- check TRNG0SR.DRDY first (an empty read returns 0 and does not consume); bring-up-grade entropy only (see THE ENTROPY CAVEAT) -- firmware MUST DRBG the output and honor ALMF')	# TRNG0: native page-2 sub-slot 9; mcu_vhd emits the raw-strobe shim, the trng0 instance and the sibling u_ro TrngRoEnsemble instance
if eventFabricPresent:
	# EVFAB0 at 0x6B00 is mutex-page sub-slot 11, the last sub-slot the peripheral library
	# takes, and the same native page-2 shape as RTC0. Single instance, so nameIndex='' and the
	# registers carry no index, like PWRCTRL, MUTEX and CLINT: the RTL block is EVFAB, the
	# instance is evfab0, the registers are EVFCR, EVFSR and the rest.
	# Vectorless: interruptPriority=None, because irq_evfab is a constant '0', so this knob adds
	# nothing to _LIBRARY_TAIL_SPEC, NUM_IRQ_SRCS or _mcuMpIrqFirstVector. clockDomain='mclk'
	# names both the bus clock ClkMem and the free-running fabric clock: front end, crossbar,
	# output register, stickies and the action path are all on the always-on MCLK. Neither
	# combinationalRead nor a CAPTURE_CLOCK slave: a plain raw-strobe active-low en shim,
	# evfab0_sh_en_n <= not shslv_evfab0_en, with no falling_edge(EnMemPeriph) pre-latch.
	# Zero pins. The sub-slot-11 decode, the raw-strobe shim, the evfab0 instance and the
	# producer and consumer tap port-map lines on the existing instances are emitted by
	# mcu_vhd.py under geo['eventFabric'], with every absent source tied '0'.
	m.CreatePeripheral(nameTemplate='EVFAB', nameIndex='', peripheralMemorySlot=None, interruptPriority=None, absoluteBaseAddress=0x6B00, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 11; registered read, no bridge, no CAPTURE_CLOCK pre-latch; free-running MCLK fabric in the always-on domain (never gated by PWRCTRL, alive through WFI); vectorless — poll EVFSR, there is no interrupt; a CHTRIG/EVTRIG/W1C write takes effect 3 MCLK after the access opens, so a read issued immediately after one (only possible from a faster master than the shared bus) can see stale state; disable a channel before changing its EVSEL/TASKSEL')	# EVFAB0: native page-2 sub-slot 11; mcu_vhd emits the raw-strobe shim, the evfab0 instance and every producer and consumer tap
overlay.call('peripheralInstances', m=m, vals=_overlayVals)	# an overlay's CreatePeripheral calls; page-2 sub-slots 12-15 are free in every public configuration
m.CreatePeripheral(nameTemplate='IRQROUTER', nameIndex='', peripheralMemorySlot=None, interruptPriority=None, absoluteBaseAddress=0x7000, sharedBus='native', clockDomain='mclk', registerSlotCount=_slotCountOverride(524))	# IRQ router at 0x7000, window page 3: routing rows plus the fixed-address CLAIM block, through word 523 = 0x782C = INSVCX



# Create the package and power domains

# CreatePackage, the power domains and the special and analog pins below are a per-model
# block selected on packageModel; the schema already validates the name. The GPIO port
# structure further down (func, altfunc, gating) is shared across models, and only each GPIO
# bit's package pin number differs, so that is the per-model table _GPIO_PKG_PINS applied to
# the shared AddGpio rows. Adding a model is a branch here plus a row in that table; the RTL
# is package-agnostic and stays byte-identical across models.
def _buildPackageData(model):
	'''Build a standalone PackageData for `model`: power domains plus special and analog pins, no
	GPIO. One source of pin numbers drives both the selected build's m.Package and web_export's
	other-model pad tables; GPIO pads attach separately from the shared GPIO structure.
	'''
	from Package import PackageData
	if model == 'myshkin-qfn44':
		package = PackageData(
			packageType='QFN',
			pinCount=44,
			units='mm',
			dimensions=[7, 7],
			pinsOnEachSide={'W': 11, 'S': 11, 'E': 11, 'N': 11},
			pinPitch=0.5,
			pinWidth=0.25,
			pinDepth=0.4
		)

		digitalIOPowerDomain = package.AddPowerDomain(
			powerDomainName='Digital I/O',
			positiveVoltage=3.3,
			negativeVoltage=0.0,
			positiveRailPinNumber=12,
			positiveRailPinName='VDDPST',
			negativeRailPinNumber=21,
			negativeRailPinName='VSSPST',
			isGpioPowerDomain=True
		)

		digitalCorePowerDomain = package.AddPowerDomain(
			powerDomainName='Digital Core',
			positiveVoltage=1.0,
			negativeVoltage=0.0,
			positiveRailPinNumber=10,
			positiveRailPinName='VDD',
			negativeRailPinNumber=22,
			negativeRailPinName='VSS'
		)

		analogPowerDomain = package.AddPowerDomain(
			powerDomainName='Analog',
			positiveVoltage=2.5,
			negativeVoltage=0.0,
			positiveRailPinNumber=37,
			positiveRailPinName='AVDD',
			negativeRailPinNumber=32,
			negativeRailPinName='AVSS'
		)

		# Special pins
		package.AddPin(packagePinNumber=11, name='RESETN', ioType='i', powerDomain=digitalIOPowerDomain)
		package.AddPin(packagePinNumber=23, name='NC', ioType='', noConnect=True)
		package.AddPin(packagePinNumber=36, name='ATP-OUT', ioType='o', powerDomain=analogPowerDomain)
		package.AddPin(packagePinNumber=35, name='ATP-IN', ioType='i', powerDomain=analogPowerDomain)
		package.AddPin(packagePinNumber=34, name='CE', ioType='io', powerDomain=analogPowerDomain)
		package.AddPin(packagePinNumber=33, name='RE', ioType='io', powerDomain=analogPowerDomain)

	elif model == 'castalia-quad-qfn64':
		# Castalia-Quad QFN-64 pinout: 16 pins per side, 9x9 mm, 0.5 mm pitch. Numbering is
		# W 1-16 top to bottom, S 17-32 left to right, E 33-48 bottom to top, N 49-64 right to left.
		package = PackageData(
			packageType='QFN',
			pinCount=64,
			units='mm',
			dimensions=[9, 9],
			pinsOnEachSide={'W': 16, 'S': 16, 'E': 16, 'N': 16},
			pinPitch=0.5,
			pinWidth=0.25,
			pinDepth=0.4
		)

		# Two physical pad pairs each for the core (left and right) and IO (top and bottom)
		# supplies. The primary pin is the die-left or die-bottom pad and the extra pin the
		# die-right or die-top pad, both on the one rail net.
		digitalCorePowerDomain = package.AddPowerDomain(
			powerDomainName='Digital Core',
			positiveVoltage=1.0,
			negativeVoltage=0.0,
			positiveRailPinNumber=10,
			positiveRailPinName='VDD',
			negativeRailPinNumber=11,
			negativeRailPinName='VSS',
			positiveRailExtraPins=[(39, 'VDD')],
			negativeRailExtraPins=[(38, 'VSS')]
		)

		digitalIOPowerDomain = package.AddPowerDomain(
			powerDomainName='Digital I/O',
			positiveVoltage=3.3,
			negativeVoltage=0.0,
			positiveRailPinNumber=23,
			positiveRailPinName='VDDPST',
			negativeRailPinNumber=26,
			negativeRailPinName='VSSPST',
			isGpioPowerDomain=True,
			positiveRailExtraPins=[(58, 'VDDPST')],
			negativeRailExtraPins=[(55, 'VSSPST')]
		)

		# Four per-quadrant analog domains, AFE0 top-left through AFE3 bottom-right, each with its
		# own AVDD_h and AVSS_h rail.
		analog0PowerDomain = package.AddPowerDomain(
			powerDomainName='Analog0', positiveVoltage=2.5, negativeVoltage=0.0,
			positiveRailPinNumber=64, positiveRailPinName='AVDD_0',
			negativeRailPinNumber=59, negativeRailPinName='AVSS_0')
		analog1PowerDomain = package.AddPowerDomain(
			powerDomainName='Analog1', positiveVoltage=2.5, negativeVoltage=0.0,
			positiveRailPinNumber=49, positiveRailPinName='AVDD_1',
			negativeRailPinNumber=54, negativeRailPinName='AVSS_1')
		analog2PowerDomain = package.AddPowerDomain(
			powerDomainName='Analog2', positiveVoltage=2.5, negativeVoltage=0.0,
			positiveRailPinNumber=17, positiveRailPinName='AVDD_2',
			negativeRailPinNumber=22, negativeRailPinName='AVSS_2')
		analog3PowerDomain = package.AddPowerDomain(
			powerDomainName='Analog3', positiveVoltage=2.5, negativeVoltage=0.0,
			positiveRailPinNumber=32, positiveRailPinName='AVDD_3',
			negativeRailPinNumber=27, negativeRailPinName='AVSS_3')

		# Special and analog signal pins
		package.AddPin(packagePinNumber=9, name='RESETN', ioType='i', powerDomain=digitalIOPowerDomain)
		package.AddPin(packagePinNumber=40, name='POC', ioType='i', powerDomain=digitalIOPowerDomain)
		# 16 electrode pads (PDB3A_G), each in its per-quadrant analog domain, on the flat
		# aio[4*h+e] bus with e in {0:WE, 1:RE, 2:RE2, 3:CE}.
		_cqElectrodes = [
			# (pin, name, analog domain)
			(61, 'WE_0', analog0PowerDomain), (62, 'RE_0', analog0PowerDomain), (63, 'RE2_0', analog0PowerDomain), (60, 'CE_0', analog0PowerDomain),
			(52, 'WE_1', analog1PowerDomain), (51, 'RE_1', analog1PowerDomain), (50, 'RE2_1', analog1PowerDomain), (53, 'CE_1', analog1PowerDomain),
			(20, 'WE_2', analog2PowerDomain), (19, 'RE_2', analog2PowerDomain), (18, 'RE2_2', analog2PowerDomain), (21, 'CE_2', analog2PowerDomain),
			(29, 'WE_3', analog3PowerDomain), (30, 'RE_3', analog3PowerDomain), (31, 'RE2_3', analog3PowerDomain), (28, 'CE_3', analog3PowerDomain),
		]
		for (_epn, _enm, _edom) in _cqElectrodes:
			package.AddPin(packagePinNumber=_epn, name=_enm, ioType='io', powerDomain=_edom)

	elif model == 'castalia-lqfp100':
		# The large package: LQFP-100, 14x14 mm body, 0.5 mm pitch, 25 pins per side, leaded for
		# bring-up probing and hand-rework. It bonds the full digital complement, all 48 GPIO
		# (prt1-prt6, the first package to bond P5 and P6), RESETN and POC, plus three core and
		# three IO supply pairs, one per digital edge, and a north analog band (AVDD/AVSS and the
		# sixteen electrode pads) for the U-tile-notch potentiostat drop-in. Numbering follows the
		# house convention: pin 1 at the top of the west edge, counterclockwise, so W 1-25 top to
		# bottom, S 26-50 left to right, E 51-75 bottom to top, N 76-100 right to left.
		package = PackageData(
			packageType='LQFP',
			pinCount=100,
			units='mm',
			dimensions=[14, 14],
			pinsOnEachSide={'W': 25, 'S': 25, 'E': 25, 'N': 25},
			pinPitch=0.5,
			pinWidth=0.22,
			pinDepth=0.6
		)

		# Three physical pad pairs per digital rail, one pair on each of the three digital edges:
		# west primary, south and east extras, on the multi-pad-rail mechanism the QFN-64 uses.
		digitalCorePowerDomain = package.AddPowerDomain(
			powerDomainName='Digital Core',
			positiveVoltage=1.0,
			negativeVoltage=0.0,
			positiveRailPinNumber=3,
			positiveRailPinName='VDD',
			negativeRailPinNumber=4,
			negativeRailPinName='VSS',
			positiveRailExtraPins=[(35, 'VDD'), (60, 'VDD')],
			negativeRailExtraPins=[(36, 'VSS'), (61, 'VSS')]
		)

		digitalIOPowerDomain = package.AddPowerDomain(
			powerDomainName='Digital I/O',
			positiveVoltage=3.3,
			negativeVoltage=0.0,
			positiveRailPinNumber=13,
			positiveRailPinName='VDDPST',
			negativeRailPinNumber=14,
			negativeRailPinName='VSSPST',
			isGpioPowerDomain=True,
			positiveRailExtraPins=[(45, 'VDDPST'), (70, 'VDDPST')],
			negativeRailExtraPins=[(46, 'VSSPST'), (71, 'VSSPST')]
		)

		# One analog domain on the north edge, which is what the die has: the north band is the
		# single PRCUT_G-bracketed analog island with exactly one AVDD/AVSS pair feeding all of it.
		# This is the one convention this model does not take from castalia-quad-qfn64, which
		# carries four per-quadrant AVDD_h/AVSS_h domains because its four AFE sites sit at four
		# separate die corners with four separate islands. Declaring four domains here would assert
		# an isolation this pad ring does not build and would cost six more rail balls the north
		# edge does not have, so the sixteen electrode pads below all name this one domain.
		analogPowerDomain = package.AddPowerDomain(
			powerDomainName='Analog',
			positiveVoltage=2.5,
			negativeVoltage=0.0,
			positiveRailPinNumber=76,
			positiveRailPinName='AVDD',
			negativeRailPinNumber=77,
			negativeRailPinName='AVSS'
		)

		# Special pins; this is the first Castalia package with a POC ball.
		package.AddPin(packagePinNumber=1, name='RESETN', ioType='i', powerDomain=digitalIOPowerDomain)
		package.AddPin(packagePinNumber=2, name='POC', ioType='i', powerDomain=digitalIOPowerDomain)

		# The sixteen electrode pads, on the same naming and grouping convention as
		# castalia-quad-qfn64: four measurement sites, four pads each on the flat aio[4*h+e] bus
		# with e in {0:WE, 1:RE, 2:RE2, 3:CE}. WE_h is the working electrode, RE_h the reference,
		# CE_h the counter, and RE2_h the second sense electrode of the optional four-terminal
		# (Kelvin) configuration. Order within a site puts the current-carrying pair (CE, WE) next
		# to the sense pair (RE, RE2), so a site's four pads are four adjacent balls and a probe
		# card lands on one contiguous block.
		# The north edge (76-100) is the only place they may go: it is the PRCUT-isolated analog
		# island, and the other three edges have no analog supply. Its free pins were the eight
		# ARSV0-7 reserve pads (78-85) plus fifteen NC balls (86-100). The reserve band is spent
		# first and by its own charter, since ARSV0-7 was declared as uncommitted analog pads for
		# the notch drop-in. Nothing with a function is displaced: no GPIO, supply or JTAG ball
		# moves, and pins 94-100 stay as the north spare. Every pad is analog-domain and bonded on
		# the island side of the PRCUT ring breaks.
		# This is intent, not as-built, and the manual says so: package.preliminary, default true,
		# prints the Preliminary banner over Section \ref{s:pinsConfig}. The as-built ring in
		# innovus/common/MCU_castalia/tcl/chip_top_wound_padlists.tcl has 77 pads, carrying
		# PAD_ARSV0-7 and nothing on 86-100; renaming those eight and adding eight more PDB3A_G
		# instances in the north band is work for the AFE integration programme.
		_lqfpElectrodes = []
		for _s in range(4):
			_p0 = 78 + 4 * _s
			_lqfpElectrodes += [(_p0, 'CE_' + str(_s)), (_p0 + 1, 'WE_' + str(_s)),
				(_p0 + 2, 'RE_' + str(_s)), (_p0 + 3, 'RE2_' + str(_s))]
		for (_epn, _enm) in _lqfpElectrodes:
			package.AddPin(packagePinNumber=_epn, name=_enm, ioType='io', powerDomain=analogPowerDomain)

		# The JTAG debug port takes five NC balls: 47 TCK, 48 TMS, 49 TDI and 50 TDO on the south
		# edge (26-50), and 51 TRSTn at the foot of the east edge (51-75). Those are the NC
		# grouping's own edges, chosen so nothing lands on the north band, which is the
		# PRCUT-isolated analog island with no digital IO supply. The die-side instances and their
		# pull-cell types live in innovus/common/MCU_castalia/in/MCU_castalia.v (TCK and TRSTn
		# pull-down, TMS, TDI and TDO pull-up); this model is the package authority only.
		package.AddPin(packagePinNumber=47, name='TCK', ioType='i', powerDomain=digitalIOPowerDomain)
		package.AddPin(packagePinNumber=48, name='TMS', ioType='i', powerDomain=digitalIOPowerDomain)
		package.AddPin(packagePinNumber=49, name='TDI', ioType='i', powerDomain=digitalIOPowerDomain)
		package.AddPin(packagePinNumber=50, name='TDO', ioType='o', powerDomain=digitalIOPowerDomain)
		package.AddPin(packagePinNumber=51, name='TRSTn', ioType='i', powerDomain=digitalIOPowerDomain)

		# Explicit NC balls, every remaining pin. 47-51 are the JTAG block above; 78-93 are the
		# electrode block above, formerly 78-85 ARSV and 86-93 NC; 94-100 are the north band's
		# remaining spare.
		for _ncp in ([23, 24, 25] + [26] + [72, 73, 74, 75] + list(range(94, 101))):
			package.AddPin(packagePinNumber=_ncp, name='NC', ioType='', noConnect=True)

	else:
		package = None
	# The overlay gets the last word on the ball map: it builds a model it declared itself when
	# nothing above matched, and it may re-cut a public model's analog band when a block only it
	# knows about changes which pads the die carries. package.Pins is a plain list, so a re-cut
	# is a filter plus its own AddPin calls, and the cross-check against its die-row file lives
	# with the overlay. Returns the package to use, or None for a model nobody implements.
	package = overlay.call('packageData', default=package, model=model, package=package,
		PackageData=PackageData, vals=_overlayVals)
	if package is None:
		raise Exception('package model "' + model + '" is declared but not implemented')
	return package


m.Package = _buildPackageData(packageModel)


def _checkDebugTransportBonded(_pkg, _model, _dbgOn):
	'''A chip that instantiates the JTAG DTM must be on a package that bonds the TAP. Without this,
	a build on a model with no NC band succeeds and simply leaves TCK and TRSTn out of
	PadRing.json, shipping a working TAP with no way to reach it. Raises rather than warns.
	'''
	if not _dbgOn:
		return
	_tap = ('TCK', 'TMS', 'TDI', 'TDO', 'TRSTn')
	_have = set(_p.Name for _p in _pkg.Pins)
	_missing = [_n for _n in _tap if _n not in _have]
	if _missing:
		raise Exception(
			'debug.enable is true but package model "' + _model + '" bonds no '
			+ 'JTAG TAP: missing ' + ', '.join(_missing) + '. The DTM would be '
			+ 'on-die and unreachable. Use package.model "castalia-lqfp100" '
			+ '(bonds TCK/TMS/TDI/TDO/TRSTn at pins 47-51), or set '
			+ 'debug.enable false for this package.')


_checkDebugTransportBonded(m.Package, packageModel, _debug['enable'])

# Per-model GPIO bit to package pin number, keyed (objGPIOk, bit b). None means unbonded:
# the bit stays in the RTL and register map but has no package ball, and the netlist ties
# the port bit. objGPIO0 is PadRing "P0" and RTL prt1, the boot flash port; objGPIOk is
# prt(k+1). The QFN-64 model leaves objGPIO2.b0 (GPIO16/T0CMP0) and objGPIO2.b4
# (GPIO20/T1CMP0) unbonded.
_GPIO_PKG_PINS = {
	'myshkin-qfn44': {
		(0, 0): 31, (0, 1): 30, (0, 2): 29, (0, 3): 28, (0, 4): 27, (0, 5): 26, (0, 6): 25, (0, 7): 24,
		(1, 0): 20, (1, 1): 19, (1, 2): 18, (1, 3): 17, (1, 4): 16, (1, 5): 15, (1, 6): 14, (1, 7): 13,
		(2, 0): 9, (2, 1): 8, (2, 2): 7, (2, 3): 6, (2, 4): 5, (2, 5): 4, (2, 6): 3, (2, 7): 2,
		(3, 0): 1, (3, 1): 44, (3, 2): 43, (3, 3): 42, (3, 4): 41, (3, 5): 40, (3, 6): 39, (3, 7): 38,
	},
	'castalia-quad-qfn64': {
		(0, 0): 8, (0, 1): 7, (0, 2): 6, (0, 3): 5, (0, 4): 4, (0, 5): 3, (0, 6): 2, (0, 7): 1,
		(1, 0): 41, (1, 1): 42, (1, 2): 43, (1, 3): 44, (1, 4): 45, (1, 5): 46, (1, 6): 47, (1, 7): 48,
		(2, 0): None, (2, 1): 16, (2, 2): 15, (2, 3): 14, (2, 4): None, (2, 5): 13, (2, 6): 12, (2, 7): 33,
		(3, 0): 34, (3, 1): 35, (3, 2): 36, (3, 3): 37, (3, 4): 57, (3, 5): 56, (3, 6): 24, (3, 7): 25,
	},
	# The LQFP-100 is the first model to bond all six ports, 48 GPIO:
	# W: P0 5-12, P1 15-22.  S: P2 27-34, P3 37-44.  E: P5 52-59, P6 62-69.
	# Ascending bit maps to ascending pin on every port.
	'castalia-lqfp100': {
		(0, 0): 5, (0, 1): 6, (0, 2): 7, (0, 3): 8, (0, 4): 9, (0, 5): 10, (0, 6): 11, (0, 7): 12,
		(1, 0): 15, (1, 1): 16, (1, 2): 17, (1, 3): 18, (1, 4): 19, (1, 5): 20, (1, 6): 21, (1, 7): 22,
		(2, 0): 27, (2, 1): 28, (2, 2): 29, (2, 3): 30, (2, 4): 31, (2, 5): 32, (2, 6): 33, (2, 7): 34,
		(3, 0): 37, (3, 1): 38, (3, 2): 39, (3, 3): 40, (3, 4): 41, (3, 5): 42, (3, 6): 43, (3, 7): 44,
		(4, 0): 52, (4, 1): 53, (4, 2): 54, (4, 3): 55, (4, 4): 56, (4, 5): 57, (4, 6): 58, (4, 7): 59,
		(5, 0): 62, (5, 1): 63, (5, 2): 64, (5, 3): 65, (5, 4): 66, (5, 5): 67, (5, 6): 68, (5, 7): 69,
	},
}
# A model an overlay declared brings its own ball map; the overlay adds it here so the
# lookup below stays one table.
overlay.call('gpioPinMap', maps=_GPIO_PKG_PINS)
def _gpioPkgPin(gpioIndex, bitNumber):
	'''Package pin number for objGPIO<gpioIndex> bit <bitNumber> under the
	   selected model, or None (unbonded — Peripheral.AddGpio skips the pad).'''
	return _GPIO_PKG_PINS[packageModel].get((gpioIndex, bitNumber))





# Add pins to the GPIO ports (and optionally change the GPIO port sizes).
# GpioConfigurator.__init__()'s documentation governs how these calls must be made, the
# funcIOType argument in particular.
# GPIO0 (P1.0-P1.7)
GPIO0.ChangeGPIOPortSize(8)

GPIO0.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO0', funcName='CS_FLASH', funcIOType='o',	rstOUT=1, rstDIR=1, rstSEL=0, rstREN=0, description='Chip select pin for SPI flash memory'), packagePinNumber=_gpioPkgPin(0, 0)) # necessary
GPIO0.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO1', funcName='MISO0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='SPI0 Master In Slave Out (connected to SPI flash memory)'), packagePinNumber=_gpioPkgPin(0, 1)) # necessary
GPIO0.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO2', funcName='MOSI0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='SPI0 Master Out Slave In (connected to SPI flash memory)'), packagePinNumber=_gpioPkgPin(0, 2)) # necessary
GPIO0.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO3', funcName='SCK0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='SPI0 serial clock (connected to SPI flash memory)'), packagePinNumber=_gpioPkgPin(0, 3)) # necessary
GPIO0.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO4', funcName='LFXT', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Low frequency external clock'), packagePinNumber=_gpioPkgPin(0, 4)) # necessary; rstSEL=0 matches the RTL (RstValP1SEL=0x4E)
GPIO0.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO5', funcName='HFXT', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='High frequency external clock'), packagePinNumber=_gpioPkgPin(0, 5)) # necessary; rstSEL=0 matches the RTL (RstValP1SEL=0x4E)
GPIO0.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO6', funcName='TRAP', funcIOType='o',	rstOUT=0, rstDIR=1, rstSEL=1, rstREN=0, description='CPU trap state'), packagePinNumber=_gpioPkgPin(0, 6)) # necessary; rstDIR=1 matches the RTL (RstValP1DIR=0x41)
GPIO0.AddGpio(GpioConfigurator(bitNumber=7, primaryName='BOOT', funcName='', funcIOType='',		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=1, description='Boot select pin (Boots to forth interpreter when LOW, boots from SPI flash when HIGH)'), packagePinNumber=_gpioPkgPin(0, 7)) # necessary

# GPIO1 (P2.0-P2.7)
GPIO1.ChangeGPIOPortSize(8)

GPIO1.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO8', funcName=('CS1' if spi1Present else ''), funcIOType=('i' if spi1Present else ''),		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('SPI1 chip select' if spi1Present else 'General-purpose I/O (ex-CS1; SPI1 dropped by this configuration)'), altFuncs=[(1, 'T0CMP0', 'o', 'TIMER0 Compare 0 (alternate location)')]), packagePinNumber=_gpioPkgPin(1, 0)) # necessary; primary gated with SPI1, AF1 is a TIMER0 source
GPIO1.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO9', funcName=('MISO1' if spi1Present else ''), funcIOType=('io' if spi1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('SPI1 Master In Slave Out' if spi1Present else 'General-purpose I/O (ex-MISO1; SPI1 dropped by this configuration)'), altFuncs=[(1, 'T0CMP1', 'o', 'TIMER0 Compare 1 (alternate location)')]), packagePinNumber=_gpioPkgPin(1, 1)) # necessary; primary gated with SPI1, AF1 is a TIMER0 source
GPIO1.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO10', funcName=('MOSI1' if spi1Present else ''), funcIOType=('io' if spi1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('SPI1 Master Out Slave In' if spi1Present else 'General-purpose I/O (ex-MOSI1; SPI1 dropped by this configuration)'), altFuncs=([(1, 'T1CMP0', 'o', 'TIMER1 Compare 0 (alternate location)')] if timer1Present else [])), packagePinNumber=_gpioPkgPin(1, 2)) # necessary; primary gated with SPI1, AF1 with TIMER1 (G1b)
GPIO1.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO11', funcName=('SCK1' if spi1Present else ''), funcIOType=('io' if spi1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('SPI1 serial clock' if spi1Present else 'General-purpose I/O (ex-SCK1; SPI1 dropped by this configuration)'), altFuncs=([(1, 'T1CMP1', 'o', 'TIMER1 Compare 1 (alternate location)')] if timer1Present else [])), packagePinNumber=_gpioPkgPin(1, 3)) # necessary; primary gated with SPI1, AF1 with TIMER1 (G1b)
GPIO1.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO12', funcName='TX0', funcIOType='o',		rstOUT=0, rstDIR=1, rstSEL=1, rstREN=0, description='UART0 transmitter', altFuncs=([(1, 'SDA1', 'io', 'I2C1 serial data (second alternate location)')] if i2c1Present else [])), packagePinNumber=_gpioPkgPin(1, 4)) # necessary; rstDIR=1 matches the RTL (RstValP2DIR=0x10); AF1 gated with I2C1
GPIO1.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO13', funcName='RX0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='UART0 receiver', altFuncs=([(1, 'SCL1', 'io', 'I2C1 serial clock (second alternate location)')] if i2c1Present else [])), packagePinNumber=_gpioPkgPin(1, 5)) # necessary; AF1 gated with I2C1 (pin-mux v2)
GPIO1.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO14', funcName=('TX1' if uart1Present else ''), funcIOType=('o' if uart1Present else ''),		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('UART1 transmitter' if uart1Present else 'General-purpose I/O (ex-TX1; UART1 dropped by this configuration)'), altFuncs=[(1, 'SDA0', 'io', 'I2C0 serial data (alternate location)')]), packagePinNumber=_gpioPkgPin(1, 6)) # necessary; primary gated with UART1, AF1 is an I2C0 source
GPIO1.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO15', funcName=('RX1' if uart1Present else ''), funcIOType=('io' if uart1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('UART1 receiver' if uart1Present else 'General-purpose I/O (ex-RX1; UART1 dropped by this configuration)'), altFuncs=[(1, 'SCL0', 'io', 'I2C0 serial clock (alternate location)')]), packagePinNumber=_gpioPkgPin(1, 7)) # necessary; primary gated with UART1, AF1 is an I2C0 source

# GPIO2 (P3.0-P3.7)
GPIO2.ChangeGPIOPortSize(8)

GPIO2.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO16', funcName='T0CMP0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Compare 0', altFuncs=([(1, 'TX1', 'o', 'UART1 transmitter (alternate location)')] if uart1Present else [])), packagePinNumber=_gpioPkgPin(2, 0)) # necessary; AF1 gated with UART1 (G1b)
GPIO2.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO17', funcName='T0CMP1', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Compare 1', altFuncs=([(1, 'RX1', 'io', 'UART1 receiver (alternate location)')] if uart1Present else [])), packagePinNumber=_gpioPkgPin(2, 1)) # necessary; AF1 gated with UART1 (G1b)
GPIO2.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO18', funcName='T0CAP0', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Capture 0', altFuncs=([(1, 'SDA1', 'io', 'I2C1 serial data (alternate location)')] if i2c1Present else [])), packagePinNumber=_gpioPkgPin(2, 2)) # necessary; AF1 gated with I2C1 (G1a)
GPIO2.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO19', funcName='T0CAP1', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Capture 1', altFuncs=([(1, 'SCL1', 'io', 'I2C1 serial clock (alternate location)')] if i2c1Present else [])), packagePinNumber=_gpioPkgPin(2, 3)) # necessary; AF1 gated with I2C1 (G1a)
GPIO2.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO20', funcName=('T1CMP0' if timer1Present else ''), funcIOType=('o' if timer1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('TIMER1 Compare 0' if timer1Present else 'General-purpose I/O (ex-T1CMP0; TIMER1 dropped by this configuration)'), altFuncs=[(1, 'TX0', 'o', 'UART0 transmitter (alternate location)')]), packagePinNumber=_gpioPkgPin(2, 4)) # necessary; primary gated with TIMER1, AF1 is a UART0 source
GPIO2.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO21', funcName=('T1CMP1' if timer1Present else ''), funcIOType=('o' if timer1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('TIMER1 Compare 1' if timer1Present else 'General-purpose I/O (ex-T1CMP1; TIMER1 dropped by this configuration)'), altFuncs=[(1, 'RX0', 'io', 'UART0 receiver (alternate location)')]), packagePinNumber=_gpioPkgPin(2, 5)) # necessary; primary gated with TIMER1, AF1 is a UART0 source
GPIO2.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO22', funcName=('T1CAP0' if timer1Present else ''), funcIOType=('i' if timer1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('TIMER1 Capture 0' if timer1Present else 'General-purpose I/O (ex-T1CAP0; TIMER1 dropped by this configuration)'), altFuncs=[(1, 'SDA0', 'io', 'I2C0 serial data (second alternate location)')]), packagePinNumber=_gpioPkgPin(2, 6)) # necessary; primary gated with TIMER1, AF1 is an I2C0 source
GPIO2.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO23', funcName=('T1CAP1' if timer1Present else ''), funcIOType=('i' if timer1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('TIMER1 Capture 1' if timer1Present else 'General-purpose I/O (ex-T1CAP1; TIMER1 dropped by this configuration)'), altFuncs=[(1, 'SCL0', 'io', 'I2C0 serial clock (second alternate location)')]), packagePinNumber=_gpioPkgPin(2, 7)) # necessary; primary gated with TIMER1, AF1 is an I2C0 source

# GPIO3 (P4.0-P4.7)
GPIO3.ChangeGPIOPortSize(8)

GPIO3.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO24', funcName='SDA0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='I2C0 serial data', altFuncs=[(1, 'T0CAP0', 'i', 'TIMER0 Capture 0 (alternate location)')]), packagePinNumber=_gpioPkgPin(3, 0)) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO25', funcName='SCL0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='I2C0 serial clock', altFuncs=[(1, 'T0CAP1', 'i', 'TIMER0 Capture 1 (alternate location)')]), packagePinNumber=_gpioPkgPin(3, 1)) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO26', funcName=('SDA1' if i2c1Present else ''), funcIOType=('io' if i2c1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('I2C1 serial data' if i2c1Present else 'General-purpose I/O (ex-SDA1; I2C1 dropped by this configuration)'), altFuncs=([(1, 'T1CAP0', 'i', 'TIMER1 Capture 0 (alternate location)')] if timer1Present else [])), packagePinNumber=_gpioPkgPin(3, 2)) # necessary; primary gated with I2C1, AF1 with TIMER1
GPIO3.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO27', funcName=('SCL1' if i2c1Present else ''), funcIOType=('io' if i2c1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('I2C1 serial clock' if i2c1Present else 'General-purpose I/O (ex-SCL1; I2C1 dropped by this configuration)'), altFuncs=([(1, 'T1CAP1', 'i', 'TIMER1 Capture 1 (alternate location)')] if timer1Present else [])), packagePinNumber=_gpioPkgPin(3, 3)) # necessary; primary gated with I2C1, AF1 with TIMER1
GPIO3.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO28', funcName='DTP0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Digital test port 0', altFuncs=[(1, 'T0CMP0', 'o', 'TIMER0 Compare 0 (alternate location)')]), packagePinNumber=_gpioPkgPin(3, 4)) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO29', funcName='DTP1', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Digital test port 1', altFuncs=[(1, 'T0CMP1', 'o', 'TIMER0 Compare 1 (alternate location)')]), packagePinNumber=_gpioPkgPin(3, 5)) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO30', funcName='DTP2', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Digital test port 2', altFuncs=([(1, 'T1CMP0', 'o', 'TIMER1 Compare 0 (alternate location)')] if timer1Present else [])), packagePinNumber=_gpioPkgPin(3, 6)) # necessary; AF1 gated with TIMER1 (G1b)
GPIO3.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO31', funcName='DTP3', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=(1 if onewirePresent else 0), description=('Digital test port 3 (AF2 = OW0 1-Wire DQ, open-drain, when OneWire present)' if onewirePresent else 'Digital test port 3'), altFuncs=([(1, 'T1CMP1', 'o', 'TIMER1 Compare 1 (alternate location)')] if timer1Present else [])), packagePinNumber=_gpioPkgPin(3, 7)) # AF1 gated with TIMER1; the AF2 spread slot carries OW0's open-drain DQ when OneWire is present, with the pull enabled at reset

# GPIO4 (P5.0-P5.7). Every pin's primary AF0 is plain general-purpose I/O (funcName='');
# AF1 carries the QSPI0 (P5.0-5) and I3C0 (P5.6/7) pin functions only when those
# controllers are present, and is Hi-Z otherwise. Pad names continue the numeric GPIOxx
# sequence from GPIO32 so they do not collide with GPIO0's bit-4 and bit-5 pad names, LFXT
# and HFXT. Package pins are model-driven: _gpioPkgPin returns None on the QFN-44 and
# QFN-64 models (unbonded) and real balls on castalia-lqfp100 (E 52-59).
GPIO4.ChangeGPIOPortSize(8)
GPIO4.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO32', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = QSPI0 serial clock when QSPI present)', altFuncs=([(1, 'QSPI_SCK', 'o', 'QSPI0 serial clock (alt plane AF1)')] if qspiPresent else [])), packagePinNumber=_gpioPkgPin(4, 0)) # AF1 gated with QSPI0
GPIO4.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO33', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = QSPI0 chip select when QSPI present)', altFuncs=([(1, 'QSPI_CS', 'o', 'QSPI0 chip select (alt plane AF1)')] if qspiPresent else [])), packagePinNumber=_gpioPkgPin(4, 1)) # AF1 gated with QSPI0
GPIO4.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO34', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = QSPI0 IO0 when QSPI present)', altFuncs=([(1, 'QSPI_IO0', 'io', 'QSPI0 quad data 0 (alt plane AF1)')] if qspiPresent else [])), packagePinNumber=_gpioPkgPin(4, 2)) # AF1 gated with QSPI0
GPIO4.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO35', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = QSPI0 IO1 when QSPI present)', altFuncs=([(1, 'QSPI_IO1', 'io', 'QSPI0 quad data 1 (alt plane AF1)')] if qspiPresent else [])), packagePinNumber=_gpioPkgPin(4, 3)) # AF1 gated with QSPI0
GPIO4.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO36', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = QSPI0 IO2 when QSPI present)', altFuncs=([(1, 'QSPI_IO2', 'io', 'QSPI0 quad data 2 (alt plane AF1)')] if qspiPresent else [])), packagePinNumber=_gpioPkgPin(4, 4)) # AF1 gated with QSPI0
GPIO4.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO37', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = QSPI0 IO3 when QSPI present)', altFuncs=([(1, 'QSPI_IO3', 'io', 'QSPI0 quad data 3 (alt plane AF1)')] if qspiPresent else [])), packagePinNumber=_gpioPkgPin(4, 5)) # AF1 gated with QSPI0
GPIO4.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO38', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=(1 if i3cPresent else 0), description='General-purpose I/O (AF1 = I3C0 SDA, open-drain, when I3C present)', altFuncs=([(1, 'I3C_SDA', 'io', 'I3C0 serial data, open-drain (alt plane AF1)')] if i3cPresent else [])), packagePinNumber=_gpioPkgPin(4, 6)) # AF1 gated with I3C0; PxREN pull-up enabled at reset when I3C present
GPIO4.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO39', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=(1 if i3cPresent else 0), description='General-purpose I/O (AF1 = I3C0 SCL, open-drain, when I3C present)', altFuncs=([(1, 'I3C_SCL', 'io', 'I3C0 serial clock, open-drain (alt plane AF1)')] if i3cPresent else [])), packagePinNumber=_gpioPkgPin(4, 7)) # AF1 gated with I3C0; PxREN pull-up enabled at reset when I3C present

# GPIO5 (P6.0-P6.7). AF1 carries the NFC0 off-die digital-AFE interface (P6.0-5) when NFC
# is present; P6.6 and P6.7 are always spare plain GPIO. P6.0's reset AFS selects AF1
# (RstValP6AFS below) so the off-die rf_clk arrives without a runtime mux switch. Package
# pins are model-driven like GPIO4; on the LQFP-100 they are E 62-69.
GPIO5.ChangeGPIOPortSize(8)
GPIO5.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO40', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, rstAFS=(1 if nfcPresent else 0), description='General-purpose I/O (AF1 = NFC0 off-die carrier clock input when NFC present)', altFuncs=([(1, 'NFC_RF_CLK', 'i', 'NFC0 off-die RF carrier clock (alt plane AF1)')] if nfcPresent else [])), packagePinNumber=_gpioPkgPin(5, 0)) # AF1 gated with NFC0; reset AFS is AF1 when NFC is present, matching the RTL's RstValP6AFS below, so the pin table and the register index print the same value
GPIO5.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO41', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = NFC0 RX envelope input when NFC present)', altFuncs=([(1, 'NFC_RF_RX', 'i', 'NFC0 off-die RX Miller envelope (alt plane AF1)')] if nfcPresent else [])), packagePinNumber=_gpioPkgPin(5, 1)) # AF1 gated with NFC0
GPIO5.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO42', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = NFC0 field-detect input when NFC present)', altFuncs=([(1, 'NFC_FIELD_DETECT', 'i', 'NFC0 off-die RF field detect (alt plane AF1)')] if nfcPresent else [])), packagePinNumber=_gpioPkgPin(5, 2)) # AF1 gated with NFC0
GPIO5.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO43', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = NFC0 TX modulation output when NFC present)', altFuncs=([(1, 'NFC_RF_TXMOD', 'o', 'NFC0 off-die TX load modulation (alt plane AF1)')] if nfcPresent else [])), packagePinNumber=_gpioPkgPin(5, 3)) # AF1 gated with NFC0
GPIO5.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO44', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = NFC0 TX enable output when NFC present)', altFuncs=([(1, 'NFC_RF_TX_EN', 'o', 'NFC0 off-die TX enable (alt plane AF1)')] if nfcPresent else [])), packagePinNumber=_gpioPkgPin(5, 4)) # AF1 gated with NFC0
GPIO5.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO45', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = NFC0 AFE enable output when NFC present)', altFuncs=([(1, 'NFC_AFE_EN', 'o', 'NFC0 off-die AFE enable (alt plane AF1)')] if nfcPresent else [])), packagePinNumber=_gpioPkgPin(5, 5)) # AF1 gated with NFC0
GPIO5.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO46', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=(1 if fieldPowerPresent else 0), description=('General-purpose I/O; also the DP-S3 harvested-boot strap (direct PWRCTRL tap, always readable; pull-down at reset = NORMAL/SPI boot when unconnected, strap high = harvested boot)' if fieldPowerPresent else 'General-purpose I/O (spare)'), altFuncs=[]), packagePinNumber=_gpioPkgPin(5, 6)) # harvested-boot strap direct tap when fieldPower, pull-down at reset
GPIO5.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO47', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=(1 if fieldPowerPresent else 0), description=('General-purpose I/O; also the DP-S3 PGOOD supply-supervisor input (direct PWRCTRL tap, always readable; pull-down at reset = power-not-good when unconnected)' if fieldPowerPresent else 'General-purpose I/O (spare)'), altFuncs=[]), packagePinNumber=_gpioPkgPin(5, 7)) # PGOOD direct tap when fieldPower, pull-down at reset, else spare plain GPIO


# GPIO alternate-function output spread: AF planes AF1..AF7 are filled with the shared
# timer, UART and SPI output pool, fanned across all four ports so each output is reachable
# on about 24 pins. Dormant at reset, since PxAFS=0 selects AF0. The RTL wires these with
# literal pin indices, so no pnum_* reverse constants are emitted and the spread altFuncs
# are flagged FromSpread and skipped by the altFunc-to-pnum cross-check in
# ChipGenerator.generateMemoryMapVHD(). They still drive the TRM AF matrix table and the
# location-qualified C-header AF defines.
_AF_IOMAP = {'i':'I','o':'O','io':'IO'}
_GPIO_AF_SPREAD = {
	(0, 0): [(1, 'TX0', 'o', 'UART0 transmitter (alt plane AF1)'), (2, 'TX1', 'o', 'UART1 transmitter (alt plane AF2)'), (3, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF3)'), (4, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF4)'), (5, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF5)'), (6, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF6)'), (7, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF7)')],
	(0, 1): [(1, 'TX1', 'o', 'UART1 transmitter (alt plane AF1)'), (2, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF2)'), (3, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF3)'), (4, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF4)'), (5, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF5)'), (6, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF6)'), (7, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF7)')],
	(0, 2): [(1, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF1)'), (2, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF2)'), (3, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF3)'), (4, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF4)'), (5, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF5)'), (6, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF6)'), (7, 'TX0', 'o', 'UART0 transmitter (alt plane AF7)')],
	(0, 3): [(1, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF1)'), (2, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF2)'), (3, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF3)'), (4, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF4)'), (5, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF5)'), (6, 'TX0', 'o', 'UART0 transmitter (alt plane AF6)'), (7, 'TX1', 'o', 'UART1 transmitter (alt plane AF7)')],
	(0, 4): [(1, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF1)'), (2, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF2)'), (3, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF3)'), (4, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF4)'), (5, 'TX0', 'o', 'UART0 transmitter (alt plane AF5)'), (6, 'TX1', 'o', 'UART1 transmitter (alt plane AF6)'), (7, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF7)')],
	(0, 5): [(1, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF1)'), (2, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF2)'), (3, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF3)'), (4, 'TX0', 'o', 'UART0 transmitter (alt plane AF4)'), (5, 'TX1', 'o', 'UART1 transmitter (alt plane AF5)'), (6, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF6)'), (7, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF7)')],
	(0, 6): [(1, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF1)'), (2, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF2)'), (3, 'TX0', 'o', 'UART0 transmitter (alt plane AF3)'), (4, 'TX1', 'o', 'UART1 transmitter (alt plane AF4)'), (5, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF5)'), (6, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF6)'), (7, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF7)')],
	(0, 7): [(1, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF1)'), (2, 'TX0', 'o', 'UART0 transmitter (alt plane AF2)'), (3, 'TX1', 'o', 'UART1 transmitter (alt plane AF3)'), (4, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF4)'), (5, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF5)'), (6, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF6)'), (7, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF7)')],
	(1, 0): [(2, 'TX1', 'o', 'UART1 transmitter (alt plane AF2)'), (3, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF3)'), (4, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF4)'), (5, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF5)'), (6, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF6)'), (7, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF7)')],
	(1, 1): [(2, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF2)'), (3, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF3)'), (4, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF4)'), (5, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF5)'), (6, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF6)'), (7, 'TX0', 'o', 'UART0 transmitter (alt plane AF7)')],
	(1, 2): [(2, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF2)'), (3, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF3)'), (4, 'TX0', 'o', 'UART0 transmitter (alt plane AF4)'), (5, 'TX1', 'o', 'UART1 transmitter (alt plane AF5)'), (6, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF6)'), (7, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF7)')],
	(1, 3): [(2, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF2)'), (3, 'TX0', 'o', 'UART0 transmitter (alt plane AF3)'), (4, 'TX1', 'o', 'UART1 transmitter (alt plane AF4)'), (5, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF5)'), (6, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF6)'), (7, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF7)')],
	(1, 4): [(2, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF2)'), (3, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF3)'), (4, 'TX1', 'o', 'UART1 transmitter (alt plane AF4)'), (5, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF5)'), (6, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF6)'), (7, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF7)')],
	(1, 5): [(2, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF2)'), (3, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF3)'), (4, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF4)'), (5, 'TX0', 'o', 'UART0 transmitter (alt plane AF5)'), (6, 'TX1', 'o', 'UART1 transmitter (alt plane AF6)'), (7, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF7)')],
	(1, 6): [(2, 'TX0', 'o', 'UART0 transmitter (alt plane AF2)'), (3, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF3)'), (4, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF4)'), (5, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF5)'), (6, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF6)'), (7, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF7)')],
	(1, 7): [(2, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF2)'), (3, 'TX0', 'o', 'UART0 transmitter (alt plane AF3)'), (4, 'TX1', 'o', 'UART1 transmitter (alt plane AF4)'), (5, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF5)'), (6, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF6)'), (7, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF7)')],
	(2, 0): [(2, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF2)'), (3, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF3)'), (4, 'TX0', 'o', 'UART0 transmitter (alt plane AF4)'), (5, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF5)'), (6, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF6)'), (7, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF7)')],
	(2, 1): [(2, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF2)'), (3, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF3)'), (4, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF4)'), (5, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF5)'), (6, 'TX0', 'o', 'UART0 transmitter (alt plane AF6)'), (7, 'TX1', 'o', 'UART1 transmitter (alt plane AF7)')],
	(2, 2): [(2, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF2)'), (3, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF3)'), (4, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF4)'), (5, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF5)'), (6, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF6)'), (7, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF7)')],
	(2, 3): [(2, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF2)'), (3, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF3)'), (4, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF4)'), (5, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF5)'), (6, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF6)'), (7, 'TX0', 'o', 'UART0 transmitter (alt plane AF7)')],
	(2, 4): [(2, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF2)'), (3, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF3)'), (4, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF4)'), (5, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF5)'), (6, 'TX1', 'o', 'UART1 transmitter (alt plane AF6)'), (7, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF7)')],
	(2, 5): [(2, 'TX0', 'o', 'UART0 transmitter (alt plane AF2)'), (3, 'TX1', 'o', 'UART1 transmitter (alt plane AF3)'), (4, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF4)'), (5, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF5)'), (6, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF6)'), (7, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF7)')],
	(2, 6): [(2, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF2)'), (3, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF3)'), (4, 'TX0', 'o', 'UART0 transmitter (alt plane AF4)'), (5, 'TX1', 'o', 'UART1 transmitter (alt plane AF5)'), (6, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF6)'), (7, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF7)')],
	(2, 7): [(2, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF2)'), (3, 'TX0', 'o', 'UART0 transmitter (alt plane AF3)'), (4, 'TX1', 'o', 'UART1 transmitter (alt plane AF4)'), (5, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF5)'), (6, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF6)'), (7, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF7)')],
	(3, 0): [(2, 'TX0', 'o', 'UART0 transmitter (alt plane AF2)'), (3, 'TX1', 'o', 'UART1 transmitter (alt plane AF3)'), (4, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF4)'), (5, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF5)'), (6, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF6)'), (7, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF7)')],
	(3, 1): [(2, 'TX1', 'o', 'UART1 transmitter (alt plane AF2)'), (3, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF3)'), (4, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF4)'), (5, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF5)'), (6, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF6)'), (7, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF7)')],
	(3, 2): [(2, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF2)'), (3, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF3)'), (4, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF4)'), (5, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF5)'), (6, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF6)'), (7, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF7)')],
	(3, 3): [(2, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF2)'), (3, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF3)'), (4, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF4)'), (5, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF5)'), (6, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF6)'), (7, 'TX0', 'o', 'UART0 transmitter (alt plane AF7)')],
	(3, 4): [(2, 'TX0', 'o', 'UART0 transmitter (alt plane AF2)'), (3, 'TX1', 'o', 'UART1 transmitter (alt plane AF3)'), (4, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF4)'), (5, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF5)'), (6, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF6)'), (7, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF7)')],
	(3, 5): [(2, 'RX0', 'io', 'UART0 receiver (alternate location; pairs with TX0 on P3.4 AF2)'), (3, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF3)'), (4, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF4)'), (5, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF5)'), (6, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF6)'), (7, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF7)')],
	(3, 6): [(2, 'T0CMP0', 'o', 'TIMER0 compare 0 (PWM) (alt plane AF2)'), (3, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF3)'), (4, 'T1CMP1', 'o', 'TIMER1 compare 1 (PWM) (alt plane AF4)'), (5, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF5)'), (6, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF6)'), (7, 'MISO1', 'io', 'SPI1 master-in (alternate location; completes SPI1 on P3.4/5/6 AF7)')],
	(3, 7): [(2, 'T0CMP1', 'o', 'TIMER0 compare 1 (PWM) (alt plane AF2)'), (3, 'T1CMP0', 'o', 'TIMER1 compare 0 (PWM) (alt plane AF3)'), (4, 'SCK1', 'o', 'SPI1 serial clock (alt plane AF4)'), (5, 'MOSI1', 'o', 'SPI1 master-out (alt plane AF5)'), (6, 'TX0', 'o', 'UART0 transmitter (alt plane AF6)'), (7, 'TX1', 'o', 'UART1 transmitter (alt plane AF7)')],
}
# pwm_out(0) and (1) replace two redundant timer-compare spread copies, the same
# replaced-spread-slot mechanism as P4.5 AF2 and P4.6 AF7 above. The slots are P2.2 AF2,
# which was the redundant T0CMP0 spread copy, for PWM0, and P2.3 AF2, which was T0CMP1, for
# PWM1. GPIO index 2 is port P2, and the two pins sit beside the T0CMP0 and T0CMP1 AF0
# primaries on P2.0 and P2.1. T0CMP0 and T0CMP1 each remain spread onto about 20 other
# pins, so removing one copy of each keeps both timer compares fully reachable.
# Knob-gated: with PWM off the two slots keep their original T0CMP0 and T0CMP1 rows; with
# PWM on they carry PWM0 and PWM1. SPREAD_SIG in mcu_vhd.py owns the pwm0 and pwm1 RTL
# spellings, and the scalar aliases pwm0_out and pwm1_out are emitted in the gated PWM
# instance region.
if pwmPresent:
	_GPIO_AF_SPREAD[(2, 2)] = [(2, 'PWM0', 'o', 'PWM0 channel 0 output (replaces the redundant T0CMP0 spread copy; alt plane AF2)')] + _GPIO_AF_SPREAD[(2, 2)][1:]
	_GPIO_AF_SPREAD[(2, 3)] = [(2, 'PWM1', 'o', 'PWM0 channel 1 output (replaces the redundant T0CMP1 spread copy; alt plane AF2)')] + _GPIO_AF_SPREAD[(2, 3)][1:]
# OW0's open-drain DQ replaces a redundant timer-compare spread copy rather than owning an
# AF1 plane, the same mechanism as PWM above. The slot is P4.7 AF2, which was the redundant
# T0CMP1 spread copy. GPIO index 3 is port P4, and P4.7 is DTP3, the last digital test-port
# pin, beside the other two completions on P4.5 and P4.6. T0CMP1 keeps its AF0 primary on
# P3.1/GPIO17, its AF1 relocations on P2.1 and P4.5 and 26 further spread copies, so
# removing this copy leaves TIMER0 compare 1 fully reachable.
# This slot is an io-class entry, bidirectional like RX0 and MISO1: the spread emitter
# drives the pad's AF2 out, dir and ren planes from ow0_dq_out, ow0_dq_dir and ow0_dq_ren
# (SPREAD_SIG in mcu_vhd.py owns the RTL spellings), and the DQ pad input is tapped by a
# fixed-priority AFS-keyed mux emitted with the gated OW0 instance. Knob-gated: with
# OneWire off the slot keeps its original T0CMP1 row.
if onewirePresent:
	_GPIO_AF_SPREAD[(3, 7)] = [(2, 'OW_DQ', 'io', 'OW0 1-Wire DQ, open-drain (replaces the redundant T0CMP1 spread copy; alt plane AF2)')] + _GPIO_AF_SPREAD[(3, 7)][1:]
# A dropped second instance's outputs leave the spread pool before the map is applied, so
# its plane slots go unassigned everywhere; the RTL emitter reads the surviving FromSpread
# altFuncs and wires '0' for the gaps.
_droppedSpreadFuncs = set()
if not uart1Present:
	_droppedSpreadFuncs.add('TX1')
if not spi1Present:
	_droppedSpreadFuncs.update(('SCK1', 'MOSI1', 'MISO1'))	# MISO1: pin-mux v2 io slot (P4.6 AF7)
if not timer1Present:
	_droppedSpreadFuncs.update(('T1CMP0', 'T1CMP1'))
for _gp in (GPIO0, GPIO1, GPIO2, GPIO3):
	_gi = int(_gp.Name[len('GPIO'):])
	for _pin in _gp.Pins:
		for _af in _GPIO_AF_SPREAD.get((_gi, _pin.BitNumber), []):
			if _af[1] in _droppedSpreadFuncs:
				continue
			_afo = GpioAltFunc(_af[0], _af[1], _AF_IOMAP[_af[2]], _af[3])
			_afo.FromSpread = True
			_pin.AltFuncs.append(_afo)
		_pin.AltFuncs.sort(key=lambda _a: _a.Index)


# MCU_MP drop-in compatibility facts.
# Everything below is transcribed from hdl/common/MemoryMap.vhd, which wins, or maps the
# RTL's constant-name spelling onto facts the description already knows. It is consumed only
# by ChipGenerator.generateMemoryMapVHD(), which emits the compatibility section that makes
# out/hdl/MemoryMap.vhd a drop-in replacement for the hand-written RTL package. Nothing here
# affects the TRM, the C and assembly headers, or the linker scripts.

# The RTL spells some legacy-slot constant names with a trailing instance digit that the
# description's peripheral names lack: PeriphSlotSystem0, PeriphSlotNPU0 and so on.
_mcuMpPeriphSlotSpelling = {
	'SYSTEM': 'System0',
	'NPU': 'NPU0',
}

# Memory block slot assignments, from MemoryMap.vhd. These are decoder block indices, not
# address-region numbers.
_mcuMpMemSlots = [
	('MemSlotROM', 0, 'base address = 0x00000'),
	('MemSlotRAM0', 1, 'base address = 0x08000'),
	('MemSlotRAM1', 2, 'base address = 0x0C000'),
	('MemSlotPeriph', 4, 'base address = 0x04000'),
]

# GPIO register-level logic helpers, fixed by the GPIO register spec; the RTL uses them to
# compose reset values.
_mcuMpGpioHelpers = [
	('gpio_dir_out', '1', 'GPIO output direction'),
	('gpio_dir_in', '0', 'GPIO input direction'),
	('gpio_ren_en', '1', 'GPIO resistor enable'),
	('gpio_ren_dis', '0', 'GPIO resistor disable'),
	('gpio_out_high', '1', 'GPIO output high'),
	('gpio_out_low', '0', 'GPIO output low'),
]

# SYSTEM register slots in the RTL's RegSlotSYS_* spelling. The slot numbers are transcribed
# from the RTL, which SYSTEM.vhd decodes against. The third element is the corresponding
# register in this description, for a consistency cross-check.
# The description matches the RTL's WDT_PASS=12, WDT_CR=13, WDT_SR=14. It previously had
# WDTCR=12, WDTSR=13, WDTPASS=14, so the TRM and MemoryMap.h documented the WDT registers
# wrongly; the only software users go through myshkin{,_s}.h, which always had the RTL order.
_mcuMpSysRegSlots = [
	('RegSlotSYS_CLK_CR', 0, 'SYSCLKCR'),
	('RegSlotSYS_CLK_DIV_CR', 1, 'CLKDIVCR'),
	('RegSlotSYS_BLOCK_PWR', 2, 'BLOCKPWR'),
	('RegSlotSYS_CRC_DATA', 3, 'CRCDATA'),
	('RegSlotSYS_CRC_STATE', 4, 'CRCSTATE'),
	# Slots 5-11 (SYS_IRQ_ENL/M/U, PRIL/M/U, CR) are retired reserved gaps; routing and masking
	# live in the IRQROUTER rows.
	('RegSlotSYS_WDT_PASS', 12, 'WDTPASS'),
	('RegSlotSYS_WDT_CR', 13, 'WDTCR'),
	('RegSlotSYS_WDT_SR', 14, 'WDTSR'),
	('RegSlotSYS_WDT_VAL', 15, 'WDTVAL'),
	('RegSlotDCO0_BIAS', 16, 'DCO0BIAS'),
	('RegSlotDCO1_BIAS', 17, 'DCO1BIAS'),
]

# NPU register slots in the RTL's MmrAddrNPU* spelling; the values come from the
# description's NPU register slots, which agree with the RTL.
_mcuMpNpuMmrAddr = [
	('MmrAddrNPUCR', 'NPUCR'),
	('MmrAddrNPUIVSAR', 'NPUIVSAR'),
	('MmrAddrNPUWVSAR', 'NPUWVSAR'),
	('MmrAddrNPUOVSAR', 'NPUOVSAR'),
	('MmrAddrNPUSR', 'NPUSR'),	# DP-SG think-done rider (slot 4)
	('MmrAddrNPUCFG1', 'NPUCFG1'),	# P4.1 family per-mode config (slot 5)
	('MmrAddrNPUCFG2', 'NPUCFG2'),	# P4.1 family per-mode config (slot 6)
]

# Per-vector interrupt names (IRQB_*), copied from the RTL. The list index is the vector
# number. The description only knows each peripheral's first vector, interruptPriority, and
# the generator cross-checks those against this list via _mcuMpIrqFirstVector and fails the
# build on disagreement.
_mcuMpIrqVectors = [('IRQB_SYS_WDT', 'Watchdog Timer Interrupt')]
for _b in range(8):
	_mcuMpIrqVectors.append(('IRQB_GPIO0_B' + str(_b), 'GPIO0 Bit ' + str(_b) + ' Interrupt'))
# Dropped second instances leave RSVD gaps and the numbering is frozen: the RTL ties RSVD
# vectors low.
for _i in (0, 1):
	if _i == 1 and not spi1Present:
		for _n in range(2):
			_v = len(_mcuMpIrqVectors)
			_mcuMpIrqVectors.append(('IRQB_RSVD' + str(_v), 'Reserved (vector ' + str(_v) + '; SPI1 dropped by this configuration)'))
	else:
		_mcuMpIrqVectors.append(('IRQB_SPI' + str(_i) + '_TC', 'SPI' + str(_i) + ' Transmission Complete Interrupt'))
		_mcuMpIrqVectors.append(('IRQB_SPI' + str(_i) + '_TE', 'SPI' + str(_i) + ' Transmission Buffer Empty Interrupt'))
_mcuMpIrqVectors.append(('IRQB_UART0_RC', 'UART0 Receive Complete Interrupt'))
_mcuMpIrqVectors.append(('IRQB_UART0_TE', 'UART0 Transmission Buffer Empty Interrupt'))
_mcuMpIrqVectors.append(('IRQB_UART0_TC', 'UART0 Transmission Complete Interrupt'))
for _i in (0, 1):
	for _sfx, _desc in [('CAP0', 'Capture 0'), ('CAP1', 'Capture 1'), ('OVF', 'Overflow'), ('CMP0', 'Compare 0'), ('CMP1', 'Compare 1'), ('CMP2', 'Compare 2')]:
		if _i == 1 and not timer1Present:
			_v = len(_mcuMpIrqVectors)
			_mcuMpIrqVectors.append(('IRQB_RSVD' + str(_v), 'Reserved (vector ' + str(_v) + '; TIMER1 dropped by this configuration)'))
		else:
			_mcuMpIrqVectors.append(('IRQB_TIM' + str(_i) + '_' + _sfx, 'TIMER' + str(_i) + ' ' + _desc + ' Interrupt'))
for _p in (1, 2, 3):
	for _b in range(8):
		_mcuMpIrqVectors.append(('IRQB_GPIO' + str(_p) + '_B' + str(_b), 'GPIO' + str(_p) + ' Bit ' + str(_b) + ' Interrupt'))
if uart1Present:
	_mcuMpIrqVectors.append(('IRQB_UART1_RC', 'UART1 Receive Complete Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_UART1_TE', 'UART1 Transmission Buffer Empty Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_UART1_TC', 'UART1 Transmission Complete Interrupt'))
else:
	for _n in range(3):
		_v = len(_mcuMpIrqVectors)
		_mcuMpIrqVectors.append(('IRQB_RSVD' + str(_v), 'Reserved (vector ' + str(_v) + '; UART1 dropped by this configuration)'))
# Vectors 55 and 56 are QSPI0's two sources when the QSPI controller occupies slot 12, and
# reserved otherwise. The numbering is frozen either way.
if qspiPresent:
	_mcuMpIrqVectors.append(('IRQB_QSPI0_TC', 'QSPI0 Transfer Complete Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_QSPI0_RXF', 'QSPI0 Receive-Register Full Interrupt'))
else:
	_mcuMpIrqVectors.append(('IRQB_RSVD55', 'Reserved (vector 55; formerly AFE0 Receive Complete)'))
	_mcuMpIrqVectors.append(('IRQB_RSVD56', 'Reserved (vector 56; formerly SARADC0 Conversion Complete)'))
# I2C vector suffixes are lowercase in the RTL except STR, and are copied from it.
# With I2C1 dropped its 13 vectors become RSVD gaps and the numbering is frozen: the IVT
# slots, CLINT vectors 83 and 84 and every other number stay put, and the RTL ties RSVD
# vectors low.
for _i in (0, 1):
	for _sfx, _desc in [
			('STR', 'start received'), ('spr', 'stop received'),
			('msts', 'master mode start condition sent'), ('msps', 'master mode stop condition sent'),
			('marb', 'master mode arbitration lost'), ('mtxe', 'master mode transmit empty'),
			('mnr', 'master mode NACK received'), ('mxc', 'master mode transfer complete'),
			('sa', 'slave address'), ('stxe', 'slave transmit empty'), ('sovf', 'slave overflow'),
			('snr', 'slave mode NACK received'), ('sxc', 'slave mode transfer complete')]:
		if _i == 1 and not i2c1Present:
			_v = len(_mcuMpIrqVectors)
			_mcuMpIrqVectors.append(('IRQB_RSVD' + str(_v), 'Reserved (vector ' + str(_v) + '; I2C1 dropped by this configuration)'))
		else:
			_mcuMpIrqVectors.append(('IRQB_I2C' + str(_i) + '_' + _sfx, 'I2C' + str(_i) + ' ' + _desc + ' Interrupt'))
# The real CLINT (hdl/common/clint.vhd, shared window 0x11000): per-hart msip and mtip
_mcuMpIrqVectors.append(('IRQB_CLINT_MSIP', 'CLINT software interrupt (IPI)'))
_mcuMpIrqVectors.append(('IRQB_CLINT_MTIP', 'CLINT timer interrupt'))
# The meip external-interrupt slot is frozen at IVT slot 85 (m.MeipVector), so peripheral
# sources grow above it. Index 85 is a reserved, never-pending placeholder, the meip
# self-slot, tied low in irq_comb and ignored by the router. The eight I3C sources sit at
# 86-93 in I3C.vhd's irq_* port order (tc, rxf, txe, nack, eod, arb, daa, ibi) and the four
# NFC sources at 94-97 in NFC.vhd's order (field, rxf, txdone, crcerr); an absent block
# leaves its slots as reserved gaps with the numbering frozen. CLINT stays at 83 and 84 and
# the numbering below 85 is untouched.
# GPIO4 and GPIO5 are unconditional and their 16 sources sit at 98-113, so the 85-97 band
# materializes in every configuration.
_mcuMpIrqVectors.append(('IRQB_RSVD85', 'Reserved (vector 85; coincides with the meip external-interrupt IVT slot, never a pending source)'))
if i3cPresent:
	_mcuMpIrqVectors.append(('IRQB_I3C0_TC', 'I3C0 Transfer Complete Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_I3C0_RXF', 'I3C0 Receive-Register Full Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_I3C0_TXE', 'I3C0 Transmit-Register Empty Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_I3C0_NACK', 'I3C0 Address / Byte NACK Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_I3C0_EOD', 'I3C0 Early End-of-Data Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_I3C0_ARB', 'I3C0 Arbitration-Lost Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_I3C0_DAA', 'I3C0 Dynamic-Address-Assignment Done Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_I3C0_IBI', 'I3C0 In-Band Interrupt Pending Interrupt'))
else:
	# I3C absent: sources 86-93 stay reserved, numbering frozen.
	for _v in range(86, 94):
		_mcuMpIrqVectors.append(('IRQB_RSVD' + str(_v), 'Reserved (vector ' + str(_v) + '; I3C0 disabled by this configuration)'))
if nfcPresent:
	_mcuMpIrqVectors.append(('IRQB_NFC0_FIELD', 'NFC0 RF Field-Detect Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_NFC0_RXF', 'NFC0 Reader-Frame Received Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_NFC0_TXDONE', 'NFC0 Tag-Response Transmit-Done Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_NFC0_CRCERR', 'NFC0 RX CRC / Parity Error Interrupt'))
else:
	# NFC absent: sources 94-97 stay reserved, numbering frozen.
	for _v in range(94, 98):
		_mcuMpIrqVectors.append(('IRQB_RSVD' + str(_v), 'Reserved (vector ' + str(_v) + '; NFC0 disabled by this configuration)'))
# GPIO4 (vectors 98-105) and GPIO5 (vectors 106-113), one per pin, unconditional.
for _p in (4, 5):
	for _b in range(8):
		_mcuMpIrqVectors.append(('IRQB_GPIO' + str(_p) + '_B' + str(_b), 'GPIO' + str(_p) + ' Bit ' + str(_b) + ' Interrupt'))
# The library tail, vector 114 and above, sitting above GPIO5's 106-113. This is the ordered
# emission table: one row per optional library block in frozen vector order, kept in lockstep
# with _LIBRARY_TAIL_SPEC (present flags and counts) up near the flag hoists. Names are
# emitted up to the last vector of the highest enabled block; every disabled block below that
# high-water mark backfills its slots as IRQB_RSVD<n> so a higher block keeps its number, and
# nothing is emitted above the highest enabled block. rtc alone gives 114 real and len 115;
# pwm alone gives 114 RSVD plus 115 and 116 real, len 117; both give len 117; none gives
# len 114. Adding a block is one row here and one in _LIBRARY_TAIL_SPEC, and the two tables'
# (present, len(names)) must agree: _libraryTailVectorsCount() below cross-checks them.
_libraryTailEmit = [
	(rtcPresent, [('IRQB_RTC0', 'RTC0 combined alarm/periodic-tick Interrupt')]),
	(pwmPresent, [('IRQB_PWM0_FAULT', 'PWM0 fault-trip Interrupt'),
		('IRQB_PWM0_EVT', 'PWM0 period-event Interrupt')]),
	(onewirePresent, [('IRQB_OW0', 'OW0 1-Wire combined transaction-complete/error Interrupt')]),
	(dmaPresent, [('IRQB_DMA0_DONE', 'DMA0 combined channels-done Interrupt'),
		('IRQB_DMA0_ERR', 'DMA0 error (deny/LEN0/misalign/out-of-window) Interrupt')]),
	# Vector 120 is NPU0 think-done, live whenever the NPU is, and 121 is TRNG0's combined
	# data-ready and health-alarm source. Each backfills as IRQB_RSVD when its block is off and
	# a higher tail block is on. Kept in lockstep with _LIBRARY_TAIL_SPEC.
	(npuPresent, [('IRQB_NPU0_TD', 'NPU0 think-done Interrupt')]),
	(trngPresent, [('IRQB_TRNG0', 'TRNG0 combined data-ready/health-alarm Interrupt')]),
	(i2ctargetPresent, [('IRQB_I2CT0_AE', 'I2CT0 combined address-match/error Interrupt'),
		('IRQB_I2CT0_DATA', 'I2CT0 combined tx-ready/rx-full Interrupt')]),
]
# The emission rows for an overlay's tail blocks, in lockstep with the _LIBRARY_TAIL_SPEC
# rows it added above.
_libraryTailEmit = list(overlay.call('irqNames', default=_libraryTailEmit,
	rows=_libraryTailEmit, vals=_overlayVals))
_tailHigh = _libraryTailVectorsCount()	# vector count including the tail high-water mark
_v = _LIB_TAIL_BASE
for _present, _names in _libraryTailEmit:
	_rowStart = _v
	_v += len(_names)
	if _rowStart >= _tailHigh:
		break	# this row (and every row above) is entirely above the high-water mark
	for _i, (_nm, _desc) in enumerate(_names):
		if _present:
			_mcuMpIrqVectors.append((_nm, _desc))
		else:
			_vec = _rowStart + _i
			_mcuMpIrqVectors.append(('IRQB_RSVD' + str(_vec),
				'Reserved (vector ' + str(_vec) + '; ' + _nm[len('IRQB_'):]
				+ ' source, disabled by this configuration)'))
# Per-vector interrupt clear methods for the TRM interrupt tables, keyed by IRQB name and
# derived from the RTL flag registers. The table is optional: a vector with no entry prints
# no clear method, so every configuration still builds.
_I2C_IRQ_FLAGS = {'STR': 'I2CSTR', 'spr': 'I2CSPR', 'msts': 'I2CMSTS', 'msps': 'I2CMSPS',
	'marb': 'I2CMARB', 'mtxe': 'I2CMTXE', 'mnr': 'I2CMNR', 'mxc': 'I2CMXC', 'sa': 'I2CSA',
	'stxe': 'I2CSTXE', 'sovf': 'I2CSOVF', 'snr': 'I2CSNR', 'sxc': 'I2CSXC'}
_TIM_IRQ_FLAGS = {'CAP0': 'CAP0IF', 'CAP1': 'CAP1IF', 'OVF': 'OVIF', 'CMP0': 'CMP0IF', 'CMP1': 'CMP1IF', 'CMP2': 'CMP2IF'}
_NFC_IRQ_FLAGS = {'FIELD': 'NFCFIELDF', 'RXF': 'NFCRXFRAMEF', 'TXDONE': 'NFCTXDONEF'}

def _irqClearMethod(irqbName):
	"""The software action that clears the source of one interrupt vector, or None when not documented here."""
	import re as _re
	if irqbName == 'IRQB_SYS_WDT':
		return 'Write 1 to WDTSR.SYSWDTIF'
	if irqbName == 'IRQB_AFE':
		return 'Per site: write 1 to AFExSR.AFEDRDY (pop) until AFECNT = 0, and to AFEOVF / AFETO'
	_m = _re.match(r'^IRQB_GPIO(\d)_B(\d)$', irqbName)
	if _m:
		return 'Write 1 to P' + _m.group(1) + 'IF bit ' + _m.group(2)
	_m = _re.match(r'^IRQB_SPI(\d)_(TC|TE)$', irqbName)
	if _m:
		if _m.group(2) == 'TC':
			return 'Write 1 to SPI' + _m.group(1) + 'SR.SPITCIF, or read SPI' + _m.group(1) + 'RX'
		return 'Write 1 to SPI' + _m.group(1) + 'SR.SPITEIF'
	_m = _re.match(r'^IRQB_UART(\d)_(RC|TE|TC)$', irqbName)
	if _m:
		if _m.group(2) == 'RC':
			return 'Write 1 to UART' + _m.group(1) + 'SR.RCIF, or read UART' + _m.group(1) + 'RX'
		return 'Write 1 to UART' + _m.group(1) + 'SR.' + _m.group(2) + 'IF'
	_m = _re.match(r'^IRQB_TIM(\d)_(\w+)$', irqbName)
	if _m and _m.group(2) in _TIM_IRQ_FLAGS:
		return 'Write 1 to TIM' + _m.group(1) + 'SR.' + _TIM_IRQ_FLAGS[_m.group(2)]
	_m = _re.match(r'^IRQB_I2C(\d)_(\w+)$', irqbName)
	if _m and _m.group(2) in _I2C_IRQ_FLAGS:
		return 'Write 1 to I2C' + _m.group(1) + 'SR.' + _I2C_IRQ_FLAGS[_m.group(2)]
	if irqbName == 'IRQB_CLINT_MSIP':
		return 'Write 0 to the MSIPn register of the hart'
	if irqbName == 'IRQB_CLINT_MTIP':
		return 'Write MTIMECMPn of the hart to a value above mtime'
	_m = _re.match(r'^IRQB_NFC(\d)_(\w+)$', irqbName)
	if _m and _m.group(2) in _NFC_IRQ_FLAGS:
		return 'Write 1 to NFC' + _m.group(1) + 'SR.' + _NFC_IRQ_FLAGS[_m.group(2)]
	if _m and _m.group(2) == 'CRCERR':
		return 'Write 1 to NFC' + _m.group(1) + 'SR.NFCCRCERRF and NFCPARERRF'
	if irqbName == 'IRQB_NPU0_TD':
		return 'Write 1 to NPUSR.NPUTHINKDONE'
	_m = _re.match(r'^IRQB_DMA(\d)_(DONE|ERR)$', irqbName)
	if _m:
		return 'Write 1 to the set DMA' + _m.group(1) + 'SR.DMA' + _m.group(2) + ' channel bits'
	return None

_mcuMpIrqClearMethods = {}
for _nm, _desc in _mcuMpIrqVectors:
	_cm = _irqClearMethod(_nm)
	if _cm is not None:
		_mcuMpIrqClearMethods[_nm] = _cm
_expectedVectorCount = _tailHigh
if len(_mcuMpIrqVectors) != _expectedVectorCount:
	raise Exception('MCU_MP IRQB vector list must have ' + str(_expectedVectorCount)
		+ ' entries, has ' + str(len(_mcuMpIrqVectors)))

# Each interrupting peripheral's first vector name, for cross-checking interruptPriority
# against the IRQB list. The build fails on mismatch.
_mcuMpIrqFirstVector = {
	'SYSTEM': 'IRQB_SYS_WDT',
	'GPIO0': 'IRQB_GPIO0_B0',
	'GPIO1': 'IRQB_GPIO1_B0',
	'GPIO2': 'IRQB_GPIO2_B0',
	'GPIO3': 'IRQB_GPIO3_B0',
	'GPIO4': 'IRQB_GPIO4_B0',	# Mission B: vectors 98-105 (interruptPriority 98)
	'GPIO5': 'IRQB_GPIO5_B0',	# Mission B: vectors 106-113 (interruptPriority 106)
	'SPI0': 'IRQB_SPI0_TC',
	'UART0': 'IRQB_UART0_RC',
	'TIMER0': 'IRQB_TIM0_CAP0',
	'I2C0': 'IRQB_I2C0_STR',
	'CLINT': 'IRQB_CLINT_MSIP',
}
if spi1Present:
	_mcuMpIrqFirstVector['SPI1'] = 'IRQB_SPI1_TC'
if uart1Present:
	_mcuMpIrqFirstVector['UART1'] = 'IRQB_UART1_RC'
if timer1Present:
	_mcuMpIrqFirstVector['TIMER1'] = 'IRQB_TIM1_CAP0'
if i2c1Present:
	_mcuMpIrqFirstVector['I2C1'] = 'IRQB_I2C1_STR'
if qspiPresent:
	_mcuMpIrqFirstVector['QSPI0'] = 'IRQB_QSPI0_TC'
overlay.call('irqFirstVector', firstVector=_mcuMpIrqFirstVector, vals=_overlayVals)
if i3cPresent:
	_mcuMpIrqFirstVector['I3C0'] = 'IRQB_I3C0_TC'	# vectors 86-93 (interruptPriority 86)
if nfcPresent:
	_mcuMpIrqFirstVector['NFC0'] = 'IRQB_NFC0_FIELD'	# vectors 94-97 (interruptPriority 94)
if npuPresent:
	_mcuMpIrqFirstVector['NPU'] = 'IRQB_NPU0_TD'	# vector 120, NPU think-done
if rtcPresent:
	_mcuMpIrqFirstVector['RTC0'] = 'IRQB_RTC0'	# vector 114 (interruptPriority 114; single combined source)
if pwmPresent:
	_mcuMpIrqFirstVector['PWM0'] = 'IRQB_PWM0_FAULT'	# vectors 115-116; interruptPriority 115, fault at the lower id
if onewirePresent:
	_mcuMpIrqFirstVector['OW0'] = 'IRQB_OW0'	# vector 117 (interruptPriority 117; single combined TC/error source)
if dmaPresent:
	_mcuMpIrqFirstVector['DMA0'] = 'IRQB_DMA0_DONE'	# vectors 118-119; interruptPriority 118, done at the lower id and err at 119
if i2ctargetPresent:
	_mcuMpIrqFirstVector['I2CT0'] = 'IRQB_I2CT0_AE'	# vectors 122-123; interruptPriority 122, address/error at the lower id and tx-ready/rx-full at 123
if trngPresent:
	_mcuMpIrqFirstVector['TRNG0'] = 'IRQB_TRNG0'	# vector 121 (interruptPriority 121; single combined data-ready/health-alarm source)

# GPIO register reset values, transcribed verbatim, values and comments, from the RTL.
# The RTL numbers GPIO ports from 1 (GPIO0 = P1 ... GPIO3 = P4) while this description
# numbers from 0, and the emitted names use the RTL numbering. These values are boot-critical:
# P1 drives the flash chip select during SPI boot.
# Known discrepancy: the description's per-pin rstOUT, rstDIR, rstSEL and rstREN attributes,
# which feed the TRM pin tables, disagree with the RTL for GPIO0 (trap DIR, lfxt and hfxt
# SEL) and GPIO1 (tx0 DIR). The RTL wins; the generator prints a warning for each mismatch.
_mcuMpRstVals = [
	('GPIO0', [
		('RstValP1OUT', 0x00000001, "cs0 default to '1' to disable flash"),
		('RstValP1DIR', 0x00000041, 'only cs0, and trap is an output'),
		('RstValP1SEL', 0x0000004E, 'all alt fn except boot, cs0'),
		('RstValP1REN', 0x00000080, "only boot has pullup/pulldown - should default to '1' to load from flash"),
		('RstValP1AFS', 0x00000000, 'all pins select AF0 (legacy alternate function) at reset'),
	]),
	('GPIO1', [
		('RstValP2OUT', 0x00000000, 'all pads output low'),
		('RstValP2DIR', 0x00000010, 'tx0 is output'),
		('RstValP2SEL', 0x00000030, 'uart0 default to alt fn'),
		('RstValP2REN', 0x00000000, 'disable rens'),
		('RstValP2AFS', 0x00000000, 'all pins select AF0 (legacy alternate function) at reset'),
	]),
	('GPIO2', [
		('RstValP3OUT', 0x00000000, ''),
		('RstValP3DIR', 0x00000000, ''),
		('RstValP3SEL', 0x00000000, ''),
		('RstValP3REN', 0x00000000, ''),
		('RstValP3AFS', 0x00000000, 'all pins select AF0 (legacy alternate function) at reset'),
	]),
	('GPIO3', [
		('RstValP4OUT', 0x00000000, ''),
		('RstValP4DIR', 0x00000000, ''),
		('RstValP4SEL', 0x00000000, ''),
		('RstValP4REN', (0x00000080 if onewirePresent else 0x00000000), ('P4.7 (OW0 DQ, AF2 replaced-spread-slot) pull enabled when OneWire present' if onewirePresent else '')),
		('RstValP4AFS', 0x00000000, 'all pins select AF0 (legacy alternate function) at reset'),
	]),
	# GPIO4 (P5) and GPIO5 (P6). All pins reset to plain-GPIO input mode. P5.6 and P5.7, the
	# I3C SDA and SCL, enable their pull-ups at reset for open-drain idle-high when I3C is
	# present; P6.0, the NFC rf_clk, resets to AF1 so the off-die clock is routed without a
	# runtime AFS switch when NFC is present.
	('GPIO4', [
		('RstValP5OUT', 0x00000000, 'all pads output low'),
		('RstValP5DIR', 0x00000000, 'all pins input at reset'),
		('RstValP5SEL', 0x00000000, 'all pins in GPIO mode at reset'),
		('RstValP5REN', (0x000000C0 if i3cPresent else 0x00000000), 'P5.6/7 (I3C SDA/SCL) pull-ups enabled when I3C present, else none'),
		('RstValP5AFS', 0x00000000, 'all pins select AF0 (plain GPIO) at reset'),
	]),
	('GPIO5', [
		('RstValP6OUT', 0x00000000, 'all pads output low'),
		('RstValP6DIR', 0x00000000, 'all pins input at reset'),
		('RstValP6SEL', 0x00000000, 'all pins in GPIO mode at reset'),
		('RstValP6REN', (0x000000C0 if fieldPowerPresent else 0x00000000), ('P6.6 (harvested-boot strap) + P6.7 (PGOOD) pulls enabled when fieldPower present (pull DIRECTION is a pad-cell property: chip-top rings must use PDDW16SDGZ_G pull-DOWN cells on these two pads; PxOUT does NOT set pull direction)' if fieldPowerPresent else 'no pulls enabled at reset')),
		('RstValP6AFS', (0x00000001 if nfcPresent else 0x00000000), 'P6.0 (NFC rf_clk) resets to AF1 for clock routing when NFC present, else all AF0'),
	]),
]

# GPIO pin-number constants in the RTL's pnum_* spelling; MCU.vhd routes pads by these.
# Rows are (group header, RTL port number, [(name, bit)]), transcribed from the RTL. Bit
# numbers agree with the description's pin list where names correspond, but the RTL names
# differ (pnum_gpio0_spi_clk against PinNumGPIO0SCK0), and pnum_gpio0_boot has no
# FuncName-bearing pin.
_mcuMpPnums = [
	('GPIO0 Pin Assignments (Serial Flash)', 1, [
		('pnum_gpio0_cs_flash', 0), ('pnum_gpio0_miso', 1), ('pnum_gpio0_mosi', 2),
		('pnum_gpio0_spi_clk', 3), ('pnum_gpio0_lfxt', 4), ('pnum_gpio0_hfxt', 5),
		('pnum_gpio0_trap', 6), ('pnum_gpio0_boot', 7),
	]),
	('GPIO1 Pin Assignments (SPI1, UART0, UART1)', 2, [
		('pnum_gpio1_cs1', 0), ('pnum_gpio1_miso1', 1), ('pnum_gpio1_mosi1', 2),
		('pnum_gpio1_sck1', 3), ('pnum_gpio1_tx0', 4), ('pnum_gpio1_rx0', 5),
		('pnum_gpio1_tx1', 6), ('pnum_gpio1_rx1', 7),
	]),
	('GPIO2 Pin Assignments (TIMER0, TIMER1)', 3, [
		('pnum_gpio2_t0_cmp0', 0), ('pnum_gpio2_t0_cmp1', 1), ('pnum_gpio2_t0_cap0', 2),
		('pnum_gpio2_t0_cap1', 3), ('pnum_gpio2_t1_cmp0', 4), ('pnum_gpio2_t1_cmp1', 5),
		('pnum_gpio2_t1_cap0', 6), ('pnum_gpio2_t1_cap1', 7),
	]),
	('GPIO3 Pin Assignments (DTP)', 4, [
		('pnum_gpio3_sda0', 0), ('pnum_gpio3_scl0', 1), ('pnum_gpio3_sda1', 2),
		('pnum_gpio3_scl1', 3), ('pnum_gpio3_dtp0', 4), ('pnum_gpio3_dtp1', 5),
		('pnum_gpio3_dtp2', 6), ('pnum_gpio3_dtp3', 7),
	]),
	# Multi-AF (AF1) pin assignments: plane-1 positions inside the flattened alt_func vectors,
	# where the groups above are plane 0 / AF0. Cross-checked against each pin's altFuncs
	# metadata by generateMemoryMapVHD. A row whose source peripheral is dropped leaves the
	# group with it; the gated altFunc rows above are the other side of that check.
	('GPIO1 (P2) AF1: '
		+ ('TIMER compare (PWM) relocations' if timer1Present else 'TIMER0 compare (PWM) relocations')
		+ (' + I2C1 relocation (v2)' if i2c1Present else '')
		+ ' + I2C0 relocation'
		+ ('' if (timer1Present and i2c1Present)
			else ' (' + ', '.join((['TIMER1 dropped: P2.2/3 reserved'] if not timer1Present else [])
				+ (['I2C1 dropped: P2.4/5 reserved'] if not i2c1Present else [])) + ')'), 2,
		[('pnum_gpio1_af1_t0_cmp0', 0), ('pnum_gpio1_af1_t0_cmp1', 1)]
		+ ([('pnum_gpio1_af1_t1_cmp0', 2), ('pnum_gpio1_af1_t1_cmp1', 3)] if timer1Present else [])
		+ ([('pnum_gpio1_af1_sda1', 4), ('pnum_gpio1_af1_scl1', 5)] if i2c1Present else [])
		+ [('pnum_gpio1_af1_sda0', 6), ('pnum_gpio1_af1_scl0', 7)]),
	({(True, True): 'GPIO2 (P3) AF1: UART0/UART1 + I2C1 relocations + I2C0 relocation (v2)',
		(True, False): 'GPIO2 (P3) AF1: UART0/UART1 relocations + I2C0 relocation (v2) (I2C1 dropped: P3.2/3 reserved)',
		(False, True): 'GPIO2 (P3) AF1: UART0 + I2C1 relocations + I2C0 relocation (v2) (UART1 dropped: P3.0/1 reserved)',
		(False, False): 'GPIO2 (P3) AF1: UART0 relocations + I2C0 relocation (v2) (UART1, I2C1 dropped: P3.0-3 reserved)',
		}[(uart1Present, i2c1Present)], 3,
		([('pnum_gpio2_af1_tx1', 0), ('pnum_gpio2_af1_rx1', 1)] if uart1Present else [])
		+ ([('pnum_gpio2_af1_sda1', 2), ('pnum_gpio2_af1_scl1', 3)] if i2c1Present else [])
		+ [('pnum_gpio2_af1_tx0', 4), ('pnum_gpio2_af1_rx0', 5),
			('pnum_gpio2_af1_sda0', 6), ('pnum_gpio2_af1_scl0', 7)]),
	('GPIO3 (P4) AF1: TIMER capture + compare relocations' if timer1Present
		else 'GPIO3 (P4) AF1: TIMER0 capture + compare relocations (TIMER1 dropped: P4.2/3/6/7 reserved)', 4,
		[('pnum_gpio3_af1_t0_cap0', 0), ('pnum_gpio3_af1_t0_cap1', 1)]
		+ ([('pnum_gpio3_af1_t1_cap0', 2), ('pnum_gpio3_af1_t1_cap1', 3)] if timer1Present else [])
		+ [('pnum_gpio3_af1_t0_cmp0', 4), ('pnum_gpio3_af1_t0_cmp1', 5)]
		+ ([('pnum_gpio3_af1_t1_cmp0', 6), ('pnum_gpio3_af1_t1_cmp1', 7)] if timer1Present else [])),
	# GPIO4 (P5) AF1 is QSPI0 on P5.0-5 and I3C0 on P5.6/7; GPIO5 (P6) AF1 is the NFC0
	# digital-AFE on P6.0-5. Rows are gated with their controller, the other side of the
	# cross-check against the AddGpio altFuncs above.
	('GPIO4 (P5) AF1: '
		+ ('QSPI0 pins on P5.0-5' if qspiPresent else 'P5.0-5 reserved (QSPI0 absent)')
		+ ' + ' + ('I3C0 open-drain on P5.6/7' if i3cPresent else 'P5.6/7 reserved (I3C0 absent)'), 5,
		([('pnum_gpio4_af1_qspi_sck', 0), ('pnum_gpio4_af1_qspi_cs', 1),
			('pnum_gpio4_af1_qspi_io0', 2), ('pnum_gpio4_af1_qspi_io1', 3),
			('pnum_gpio4_af1_qspi_io2', 4), ('pnum_gpio4_af1_qspi_io3', 5)] if qspiPresent else [])
		+ ([('pnum_gpio4_af1_i3c_sda', 6), ('pnum_gpio4_af1_i3c_scl', 7)] if i3cPresent else [])),
	# OW0's DQ has no pnum_* row: it lives in the P4.7 AF2 spread slot, and spread slots wire
	# literal pin indices with no reverse constant, on the RX0 and MISO1 precedent.
	('GPIO5 (P6) AF1: '
		+ ('NFC0 digital-AFE on P6.0-5' if nfcPresent else 'P6.0-5 reserved (NFC0 absent)'), 6,
		([('pnum_gpio5_af1_nfc_rf_clk', 0), ('pnum_gpio5_af1_nfc_rf_rx', 1),
			('pnum_gpio5_af1_nfc_field_detect', 2), ('pnum_gpio5_af1_nfc_rf_txmod', 3),
			('pnum_gpio5_af1_nfc_rf_tx_en', 4), ('pnum_gpio5_af1_nfc_afe_en', 5)] if nfcPresent else [])),
]

m.McuMpCompat = {
	'sourceFile': 'hdl/common/MemoryMap.vhd',
	'periphSlotSpelling': _mcuMpPeriphSlotSpelling,
	'memSlots': _mcuMpMemSlots,
	'gpioHelpers': _mcuMpGpioHelpers,
	'sysRegSlots': _mcuMpSysRegSlots,
	'npuMmrAddr': _mcuMpNpuMmrAddr,
	'irqVectors': _mcuMpIrqVectors,
	'irqClearMethods': _mcuMpIrqClearMethods,	# optional per-vector clear method text, keyed by IRQB name
	'irqFirstVector': _mcuMpIrqFirstVector,
	'rstVals': _mcuMpRstVals,
	'pnums': _mcuMpPnums,
}

# Per-instance reset values. A RegisterTemplate carries one reset value, but two peripherals
# reset the same register differently per instance because the RTL passes the value in as a
# generic: GPIO's RstValPx{OUT,DIR,SEL,REN,AFS} (the _mcuMpRstVals table above, transcribed
# from hdl/common/MemoryMap.vhd) and I2C's default_SAD (hdl/common/constants.vhd
# i2c0_default_SAD and i2c1_default_SAD). Without this the register table and MemoryMap.h
# publish 0x00 for all of them on every instance, 22 register-index rows describing a chip
# that does not exist.
# Applied to the instance registers, after ChangeGPIOPortSize has narrowed them, so the
# template stays untouched and //platform/common:rdl_vs_generator_test, which grades
# templates, still passes while the per-instance values reach the emitted artifacts. The
# .rdl side assigns exactly these at the top addrmap
# (hdl/common/regs/rdl/castalia_penta_wound.rdl).
i2cDefaultSad = {'0': 0x79, '1': 0x23}	# hdl/common/constants.vhd: i2c{0,1}_default_SAD

def _setInstanceReset(peripheralName, registerName, value):
	'''Set one instance register's reset value and redistribute it over its bit fields. Reserved bits
	are dropped, exactly as RegisterTemplate.CheckBitFields computes a template reset, so a
	nibble-packed register lands in the right fields.
	'''
	per = None
	for cand in m.Peripherals:
		if cand.Name == peripheralName:
			per = cand
			break
	if per is None:
		return False
	for r in per.Registers:
		if r.Name != registerName:
			continue
		rv = 0
		for bf in r.BitFields:
			if bf.Unused:
				continue
			bf.ResetValue = (value >> bf.LSB) & ((1 << bf.Size) - 1)
			rv |= bf.ResetValue << bf.LSB
		r.ResetValue = rv
		return True
	raise Exception('_setInstanceReset: peripheral "' + peripheralName + '" has no register "' + registerName + '"')

for _gpioName, _entries in _mcuMpRstVals:
	for _rstName, _rstValue, _rstComment in _entries:
		_setInstanceReset(_gpioName, 'P' + _gpioName[len('GPIO'):] + _rstName[-3:], _rstValue)

for _i2cIdx, _sad in sorted(i2cDefaultSad.items()):
	_setInstanceReset('I2C' + _i2cIdx, 'I2C' + _i2cIdx + 'AR', _sad)

# Shared-window geometry for mcu_vhd.py's generated regions: the SH_AW constant, the bank
# row and the NPU staging plumbing all derive from these three values, computed with the
# memory sections above.
m.McuMpGeometry = {
	'orchestrator': orchestrator,  # False = no orchestrator; True = hart 0 is the always-on soft orchestrator emitted as `entity work.orch_tile` and harts 1..numHarts-1 are uniform channel tiles, with pwr_ctrl rows 1..numHarts-1, iso clamps on all of them, and memory map v2 (SH_AW >= 16 plus the read-only TCM apertures). The management hart is hart 0 in both shapes, so afe_stub's MGMT_HART is never overridden
	'shAw': shAw,               # arbiter/tile word-address width (15 = Castalia, 16 = Argus and every orchestrator config)
	'tcmWindows': tcmWindows,   # CPR3/R3: byte base of the read-only TCM aperture for hart h (index = h); [] = no apertures
	'tcmApertureSize': _tcmApertureSize,  # aperture stride and span in bytes, decoupled from the TCM size because it is address space, not silicon. It must be >= tcmSizePerHart, an 8 KiB TCM mirrors twice inside its 16 KiB aperture, and the decode granularity s_addr(15:12) depends on this being 0x4000
	'sharedRamBanks': _sharedRamBanks,  # sram1p16k banks from 0x10000 (4 = Castalia)
	'npu': npuPresent,          # False = Argus (slot 10 + 0xC000 window read zero)
	'i2c1': i2c1Present,        # G1a: False drops the i2c1 instance (slot 15 dead)
	'uart1': uart1Present,      # G1b: False drops the uart1 instance (slot 5 dead)
	'spi1': spi1Present,        # G1b: False drops the spi1 instance (slot 3 dead)
	'timer1': timer1Present,    # G1b: False drops the timer1 instance (slot 7 dead)
	'afeStubs': cqAfeStubsPresent, # True = the four AFE stubs and the EIS engine occupy slot 12 and 0x7C00
	'i3c': i3cPresent,          # True = I3C0 in mutex-page sub-slot 1 (0x6100); tightens the mutex decode, vectors 86-93
	'nfc': nfcPresent,          # True = NFC0 in mutex-page sub-slot 2 (0x6200); tightens the mutex decode, vectors 94-97, fourth glitch filter
	'qspi': qspiPresent,        # True = the QSPI0 controller in slot 12 (0x4C00), vectors 55 and 56; requires cqAfeStubs False
	'rtc': rtcPresent,          # True = RTC0 in mutex-page sub-slot 5 (0x6500); raw-strobe shim, vector 114, source list grows to 115
	'pwm': pwmPresent,          # True = PWM0 in mutex-page sub-slot 6 (0x6600); raw-strobe shim, vectors 115 and 116, source list grows to 117
	'onewire': onewirePresent,  # True = OW0 in mutex-page sub-slot 7 (0x6700); raw-strobe shim, DQ on P4.7/GPIO31 AF2 open-drain, vector 117, source list grows to 118
	'fieldPower': fieldPowerPresent,  # True = pwr0's supervision inputs are wired (pgood_pad=prt6_in(7), strap_pad=prt6_in(6), field_detect = the NFC tap or 0); False ties them inert. The pgood_rstn reset folds are emitted unconditionally and are a provable no-op when tied
	'dma': dmaPresent,          # True = DMA0 in mutex-page sub-slot 8 (0x6800) and the first new arbiter master: raw-strobe slave shim, vectors 118 and 119, source list grows to 119, and the arbiter widens N=4 to 5 with MW=3 and sh_master 2 to 3 bits
	'dmaChannels': dmaChannels, # DMA0 NCH generic, 2 or 4, consulted only when dma is true; the 4-channel register superset is emitted regardless
	'i2ctarget': i2ctargetPresent,  # True = the I2CT0 I2C target in mutex-page sub-slot 10 (0x6A00): raw-strobe shim, shares the I2C0 SDA0/SCL0 pads through a wired-AND DIR merge emitted separately, vectors 122 and 123, source list grows to 124 with 120 and 121 as DP-SG placeholders
	'trng': trngPresent,        # True = TRNG0 in mutex-page sub-slot 9 (0x6900); raw-strobe shim, sibling u_ro TrngRoEnsemble instance, vector 121, source list grows to 122
	'trngRings': trngRings,     # TRNG0 NRO generic, 4 or 8, consulted only when trng is true; the register map is NRO-invariant
	'eventFabric': eventFabricPresent,  # True = the EVFAB0 event and trigger fabric in mutex-page sub-slot 11 (0x6B00): raw-strobe shim, vectorless, plus the producer and consumer tap port maps on RTC0, PWM0, TIMER0, TIMER1, UART0, NFC0, DMA0, TRNG0, I2CT0, GPIO0, NPU0 and pwr0, with every absent source tied '0'
	'chipNameConfigured': (_cfg('chipName', None) or ''),  # the config file's chip name, never the CHIP_NAME environment override, which is documentation-only. One half of the JTAG IDCODE chip-identity discriminator (mcu_vhd.isArgusFamily); the other half is numHarts == 18. A docs-only switch must never change an RTL constant
	'debug': _debug['enable'],  # True = the Debug Module dm0, the eight MCU-entity dmi_* ports, the per-tile dbg_* hookup and DEBUG_ENTRY_ADDR => 0x00010780. dm0 is the second new arbiter master after the DMA, at index nMasters-1, so it drags the same fabric widening. False, the pre-debug default shape, emits no trace: no ports, no declarations, no instance, no clamp row, which check_mcu_vhd.py STRICT grades. The same knob carries JTAG: the five tck/tms/tdi/tdo/trstn pins (the last entity port group), the dtm0 jtag_dtm instance beside dm0, and the valid-gated OR-merge that keeps the raw dmi_* ports reaching the DM with the DTM present and inert
}
# The emitters' knob dictionary is the only channel to mcu_vhd.py and tb_vhd.py, so an
# overlay's placement knobs ride it too and entity and testbench cannot disagree about what
# was built.
overlay.call('mcuGeometry', geo=m.McuMpGeometry, vals=_overlayVals)


# Check for errors
m.CheckPeripherals()
m.CheckPackagePins()


# Analog front-end documentation sub-slot blocks (AFE0-3 and EIS).
# The respin instantiates five s_master-gated register-stub arbiter slaves (afe_stub.vhd,
# wired in the generated MCU.vhd): four per-hart AFE sites in the four 64 B sub-slots of
# page-0 slot 12 (0x4C00) and one hart-0 EIS engine in the top quarter of the IRQ-router
# page (0x7C00). Those sub-slot and page-carved base addresses are forbidden to a native
# arbiter slave, because the whole-slot cross-checks in Peripheral assume one slave per whole
# slot, so they are not CreatePeripheral()'d. They are documentation sub-slot blocks
# instead: their own data model, validated by m.CheckDocSubSlotBlocks() against its own
# sub-slot alignment, containment and no-shadow rules, feeding only a config-gated generated
# TRM chapter. They never enter the peripheral, address or interrupt tables, MemoryMap.vhd
# or MCU.vhd.
# The gate is two facts, not a package-model name. First, the package must bond the sixteen
# electrode pads, or there is no analog story: AfeSystemDiagram re-derives WE, RE, RE2 and
# CE_0..3 from the pin list and refuses to draw pads the chip does not have, and
# ChipSystemFlatDiagram's channel row is built from the same lookup. Second, the chip must be
# the shape the chapter describes, an orchestrator hart 0 plus one channel tile per site,
# which is numHarts == 5 with orchestrator true; AfeSystemDiagram asserts both by name and
# raises otherwise. Keying on packageModel == 'castalia-quad-qfn64' held the first only by
# coincidence and the second not at all, and the default TRM lost its analog row and chapter
# when castalia-lqfp100 became the default although the RTL still instantiated all five
# afe_stub slaves. castalia-quad-qfn64 still qualifies, myshkin-qfn44 bonds no electrode
# group and stays off, and config/argus_debug.json (eighteen harts, no orchestrator, wearing
# the LQFP-100 to reach the JTAG balls) stays off: the degrade is the AFE block back on the
# peripheral rank, never a figure that names five harts on an eighteen-hart chip.
_pkgPinNames = set(_p.Name for _p in m.Package.Pins)
_bondsElectrodes = all((_e + '_' + str(_i)) in _pkgPinNames
	for _i in range(4) for _e in ('WE', 'RE', 'RE2', 'CE'))
if _bondsElectrodes and cqAfeStubsPresent and orchestrator and numHarts == 5:
	# The 16-word (64 B) register file shared by every afe_stub instance; AFE and EIS are the
	# same entity and only the ownership gate differs. Columns are word offset, name, access
	# and description; the byte offset is 4 times the word offset.
	_afeRegisters = [
		(0x0, 'CTRL',   'RW',  'Control. Placeholder for the analog IP. As a bring-up test hook (until the analog IP drives real events), a write whose data bit 0 is 1 soft-sets \\register{IF} bit 0, which exercises the block\'s level-interrupt path end to end.'),
		(0x1, 'DACPAT', 'RW',  'DAC excitation-pattern control. Placeholder for the analog IP.'),
		(0x2, 'TIA',    'RW',  'Transimpedance-amplifier gain-range select. Placeholder for the analog IP.'),
		(0x3, 'SWM',    'RW',  'Switch-matrix / analog-multiplexer configuration. Placeholder for the analog IP.'),
		(0x4, 'ADCC',   'RW',  'ADC control. Placeholder for the analog IP.'),
		(0x5, 'ADCD',   'RW',  'ADC data. Placeholder for the analog IP.'),
		(0x6, 'STAT',   'RW',  'Status. Placeholder for the analog IP.'),
		(0x7, 'IF',     'W1C', 'Interrupt-flag word. While any bit is set the block drives its level interrupt high; write a 1 to a bit to clear that bit (write-1-to-clear). Reads are side-effect-free. This is the word hart 0 reads to demultiplex which site raised the shared AFE interrupt.'),
		(0x8, '-', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0x9, '-', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0xA, '-', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0xB, '-', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0xC, '-', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0xD, '-', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0xE, '-', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0xF, '-', 'RW',  'Scratch / reserved (plain read-write storage).'),
	]
	# The owner follows the tile, not the site index. mcu_vhd.afeStubsOrchOwners() shifts every
	# AFE site's OWNER_HART generic by +1 on an orchestrator configuration, because hart 0 is
	# the orchestrator and the four channel harts are 1..4, so the emitted MCU.vhd reads
	# `afe0 ... OWNER_HART => 1'. Derived here from the same knob mcu_vhd.py derives from, so
	# the TRM's ownership table and gating prose cannot drift from the RTL.
	_cqDocBlocks = []
	for _h in range(4):
		_owner = _h + 1 if orchestrator else _h
		_cqDocBlocks.append({
			'name':      'AFE' + str(_h),
			'base':      0x4C00 + 0x40 * _h,
			'sizeBytes': 0x40,
			'parent':    ('page-0 slot 12 (0x4C00-0x4CFF, the reserved ex-SARADC/AFE slot)', 0x4C00, 0x4CFF),
			'ownerHart': _owner,
			'gate':      ('s\\_master = 0' if _owner == 0 else 's\\_master = ' + str(_owner) + ' or s\\_master = 0'),
			'irqSource': 55,
			'registers': _afeRegisters,
		})
	_cqDocBlocks.append({
		'name':      'EIS',
		'base':      0x7C00,
		'sizeBytes': 0x40,
		'parent':    ('IRQ-router page top quarter (0x7C00-0x7FFF)', 0x7C00, 0x7FFF),
		'ownerHart': 0,
		'gate':      's\\_master = 0',
		'irqSource': 56,
		'registers': _afeRegisters,
	})
	m.DocSubSlotBlocks = _cqDocBlocks
	m.CheckDocSubSlotBlocks()


# The per-hart-class ISA table is web_export's, not a second copy here. Importing it is the
# point: chip_data.js, this record, the TRM and the repository README then all render one
# function's output. Imported at the point of use because web_export is otherwise a pure
# output-side module.
import web_export as _webExport

# The unified configuration record. One dict holds every knob the CONFIG= schema accepts
# plus everything derived from them. It is attached to the generator so the TRM's generated
# Chip Configuration section renders from it, and written to config/ChipConfig.resolved.json
# after generation so `make show`, scripts and the configurator can read back exactly what
# was built. Addresses are 0x-strings; sizes are byte integers.
def _hx(v):
	return '0x' + format(int(v), 'X')

_resolvedConfig = [
	('_comment', 'Resolved chip configuration — written by make chip (platform/common/python/generate.py). '
		+ 'Inputs follow the CONFIG= JSON schema (docs/chip_configurator.html emits it); '
		+ 'everything under "derived" is computed, not configurable.'),
	('configFile', _cfgRecord),
	('chipName', m.AsicName),
	('numHarts', numHarts),
	# The orchestrator knob, dumped so verify_stage.py (cell list and test tags) and any script
	# can read the shape that was built rather than re-deriving it. There is no
	# `powerGatedHarts` key: every hart 1..numHarts-1 is gateable in both shapes, so the value
	# was numHarts unconditionally and a second name for it could only rot.
	('orchestrator', orchestrator),
	('numMutexes', numMutexes),
	('registerFileDualPort', _regsDualPort),
	# Fetch-ahead, recorded for the same reason the debug branch is: a build that carries it
	# must be distinguishable from one that does not in the artifacts scripts read back, not
	# only in the RTL.
	('core', _core),
	('isa', _isa),
	('priv', _priv),
	# The debug branch. Without it a debug-ON build's ChipConfig.resolved.json is
	# byte-indistinguishable from a debug-OFF one, in the artifact CLAUDE.md calls a live input
	# to the lockstep oracle, so nothing downstream can derive from the knob. verify_stage.py's
	# config_tags() is the first consumer. oracle_isa.py is deliberately not keyed on it: its
	# derive_triggers() returns 0 unconditionally, so no oracle behaviour changes.
	('debug', _debug),
	('memory', [
		('romSize', _romSize),
		('tcmSizePerHart', _tcmSize),
		('sharedBulkRamSize', _sharedRamLen),
		('npuStagingRamSize', _npuRamLen if npuPresent else 0),
	]),
	('peripherals', [('npu', npuPresent), ('i2c1', i2c1Present), ('uart1', uart1Present),
		('spi1', spi1Present), ('timer1', timer1Present),
		('cqAfeStubs', cqAfeStubsPresent), ('qspi', qspiPresent), ('i3c', i3cPresent),
		('nfc', nfcPresent), ('rtc', rtcPresent), ('pwm', pwmPresent),
		('onewire', onewirePresent),
		# The field-power knob is declared in _CONFIG_SCHEMA and consumed everywhere (RstValP6REN,
		# the P6.6 and P6.7 pad descriptions, mcu_vhd's pwr0 port wiring), and this row is what lets
		# the resolved dump report the shape it built. The TRM's configuration table reads its rows
		# straight out of this record, and without the row the published manual printed
		# "peripherals.fieldPower  None".
		('fieldPower', fieldPowerPresent),
		('dma', dmaPresent),
		('dmaChannels', dmaChannels), ('i2ctarget', i2ctargetPresent),
		('trng', trngPresent), ('trngRings', trngRings),
		('eventFabric', eventFabricPresent)]),
	('package', [('model', packageModel), ('preliminary', packagePreliminary)]),
	# The knob grouping, so a consumer of this record can present the schema the way the TRM and
	# the configurator do without re-deriving the rule. Names only: the values are above.
	('knobGroups', [
		('basic', sorted(_k for _k in _CONFIG_META if _CONFIG_META[_k]['group'] == 'basic')),
		('advanced', sorted(_k for _k in _CONFIG_META if _CONFIG_META[_k]['group'] == 'advanced')),
	]),
	('derived', [
		('isaString', _isaString()),
		# The asymmetric-ISA table (isa.minimalTiles), imported rather than re-derived:
		# web_export.hartClasses() is the one authority, and this record, the chip_data.js bundle,
		# the TRM's configuration chapter and the repository README all read it, so none of the four
		# can drift from the RTL this build emitted. One row per hart class that exists; a
		# configuration with no minimal tiles degenerates to a single row.
		('hartClasses', _webExport.hartClasses({
			'numHarts': numHarts,
			'orchestrator': orchestrator,
			'isa': _isa,
			'priv': _priv,
			'debug': _debug,
		})),
		('sharedWindowAddrWidth', shAw),
		('sharedRamBanks', _sharedRamBanks),
		('flashBaseAddress', _hx(flashBase)),
		('sharedRamEndAddress', _hx(0x10000 + _sharedRamLen - 1)),
		# The read-only TCM apertures, on orchestrator configurations only, and an empty list
		# everywhere else. A consumer keys on the list, never on the knob, because the resolved dump
		# is the shape that was built.
		('tcmWindowAddresses', [_hx(_w) for _w in tcmWindows]),
		('vectorsCount', _vectorsCount),	# 114 unconditional sources; the library tail extends it per the global vector rule (_libraryTailVectorsCount())
		('meipVector', 85),
		('clintMsipVector', 83),
		('clintMtipVector', 84),
		('clintLayout', [
			('msipAddress', '0x5000 + 4*hartid'),
			('mtimeAddress', _hx(0x5000 + 4 * clintMtimeSlot)),
			('mtimecmpBaseAddress', _hx(0x5000 + 4 * clintMtimecmpSlot)),
		]),
		('bootromLoaderRowBase', '0x10500 + 0x10*hartid'),	# hart-count-agnostic relocation, all builds; see software/bootrom_mp
		('stackPointerInit', _hx(_stackPointerInit)),
		('peripheralCount', len(m.Peripherals)),
	]),
]
# An overlay's knobs are recorded like every other, so the resolved dump reports the shape
# that was actually built. With no overlay the record is unchanged.
_resolvedConfig = list(overlay.call('resolvedConfig', default=_resolvedConfig,
	rows=_resolvedConfig, vals=_overlayVals))

def _od(pairs):
	'''Recursively turn ('key', value) pair lists into dicts (py3.6 dicts keep
	   insertion order, so the JSON reads in schema order).'''
	if isinstance(pairs, list) and pairs and all(isinstance(p, tuple) and len(p) == 2 for p in pairs):
		return dict((k, _od(v)) for k, v in pairs)
	return pairs

m.ResolvedConfig = _od(_resolvedConfig)
m.PackagePreliminary = packagePreliminary	# drives the TRM section 2 "Preliminary" banner (LatexUserGuide \ifpackagepreliminary)
# The orchestrator presence flag, for the TRM's config-driven prose (LatexUserGuide
# \iforchpresent; \OrchHartIndex is the constant 0, because the orchestrator is hart 0).
# False folds every piece of orchestrator prose away, the same inert-unless-declared
# discipline as \ifcqanalog and \ifdebugenable.
m.Orchestrator = orchestrator
# Schema key to human description, for the TRM's generated Chip Configuration section, which
# documents the CONFIG= schema next to this build's resolved values.
m.ConfigSchemaDoc = dict((k, _CONFIG_SCHEMA[k][0]) for k in _CONFIG_SCHEMA)
# Declarative schema metadata and the resolved defaults, attached for the `make web` export
# to out/web/chip_data.js so the configurator reads ranges, enums and defaults from the
# generator rather than re-hardcoding them.
m.ConfigMeta = dict((k, dict(_CONFIG_META[k])) for k in _CONFIG_META)
m.ConfigDefaults = dict((k, _CONFIG_META[k]['default']) for k in _CONFIG_META)
# The verified hart counts, from the single record above, for the same export. web_export.py
# publishes this verbatim as VESTA_DATA.verifiedHarts and the configurator badges
# cfg.numHarts against the `values` list, so anything added here renders as a proven hart
# count on a published page.
m.VerifiedHarts = {
	'values': [_n for _n, _d in _VERIFIED_HART_COUNTS],
	'note': _verifiedHartsNote(),
}

# Derived pad ring: the package model above is the pad-ring description, giving pin order,
# sides and power domains. It is recorded as config/PadRing.json and rendered as the TRM's
# generated pinout diagram, so there is no separate hand-maintained pad list to drift.
def _padRingDomainEntry(_pd):
	'''One PadRing.json powerDomains entry. A single-pad rail emits the historical shape, so the
	QFN44 model stays byte-identical; a multi-pad rail additionally lists all of its pads under
	positiveRailPins and negativeRailPins.
	'''
	_pairs = [
		('name', _pd.Name),
		('voltage', _pd.PositiveVoltage),
		('positiveRail', {'pin': _pd.PositiveRailPackagePin.PackagePinNumber, 'name': _pd.PositiveRailPackagePin.Name}),
		('negativeRail', {'pin': _pd.NegativeRailPackagePin.PackagePinNumber, 'name': _pd.NegativeRailPackagePin.Name}),
	]
	if len(_pd.PositiveRailPins) > 1 or len(_pd.NegativeRailPins) > 1:
		_pairs.append(('positiveRailPins', [{'pin': _p.PackagePinNumber, 'name': _p.Name} for _p in _pd.PositiveRailPins]))
		_pairs.append(('negativeRailPins', [{'pin': _p.PackagePinNumber, 'name': _p.Name} for _p in _pd.NegativeRailPins]))
	return dict(_pairs)

def _padRingDict(pkg):
	'''Serialize a fully-built PackageData, sides assigned, into the PadRing.json shape. Used both
	for the selected model and for the web export's other-model pad tables, so every model's pad
	table has the identical shape.
	'''
	_pins = []
	for _pp in pkg.Pins:
		_e = {
			'pin': _pp.PackagePinNumber,
			'side': _pp.Side,
			'name': _pp.FullName if not _pp.NoConnect else 'NC',
			'io': _pp.IOString if not _pp.NoConnect else 'NC',
		}
		if _pp.NoConnect:
			_e['noConnect'] = True
		else:
			_e['powerDomain'] = _pp.PowerDomain.Name
			if _pp.Gpio is not None:
				_e['gpio'] = _pp.Gpio.GpioName
				if len(_pp.Gpio.FuncName) > 0:
					_e['af0'] = _pp.Gpio.FuncName
				_af = [a for a in _pp.Gpio.AltFuncs if a.Index >= 1]
				if _af:
					_e['altFuncs'] = dict(('AF' + str(a.Index), a.Name) for a in sorted(_af, key=lambda a: a.Index))
		_pins.append(_e)
	return {
		'_comment': 'Derived pad ring — computed by make chip from the package model in generate.py '
			+ '(pin numbers, sides, power domains are single-sourced there; edit generate.py, not this file).',
		'package': {
			'type': pkg.PackageType,
			'pinCount': pkg.PinCount,
			'dimensions': pkg.Dimensions,
			'units': pkg.Units,
			'pinPitch': pkg.PinPitch,
			'pinsOnEachSide': pkg.PinsOnEachSide,
		},
		'powerDomains': [_padRingDomainEntry(_pd) for _pd in pkg.PowerDomains],
		'pins': _pins,
	}

m.PadRing = _padRingDict(m.Package)

# Pad tables for every package model, not just the selected one, so the web export can offer
# a live pinout for each. Built by the same machinery: the GPIO func and altfunc structure is
# model-independent and already attached to the GPIO peripherals above, so a non-selected
# model reuses those exact gpio objects, remaps each to that model's package pin number from
# _GPIO_PKG_PINS, and reruns the CheckPackagePins side assignment. No pin number is
# transcribed twice.
def _padRingForModel(_model):
	if _model == packageModel:
		return m.PadRing	# the authoritative, already-built + side-assigned ring
	_pkg = _buildPackageData(_model)
	for _gp in (GPIO0, GPIO1, GPIO2, GPIO3, GPIO4, GPIO5):	# all six ports; P5 and P6 bond on castalia-lqfp100, and the QFN models return None so the pad is skipped
		_gi = int(_gp.Name[len('GPIO'):])
		for _gpio in _gp.Pins:
			_num = _GPIO_PKG_PINS[_model].get((_gi, _gpio.BitNumber))
			if _num is None:
				continue	# unbonded on this model (no package ball)
			_p = _pkg.AddGpioPin(_num, _gpio)
			_p.PowerDomain = _pkg.GpioPowerDomain
	# Mirror ChipGenerator.CheckPackagePins side assignment: sort, then W/S/E/N.
	_pkg.Pins.sort(key=lambda _x: _x.PackagePinNumber)
	if len(_pkg.Pins) != _pkg.PinCount:
		raise Exception('package model "' + _model + '" attached ' + str(len(_pkg.Pins))
			+ ' pads but declares ' + str(_pkg.PinCount) + ' pins')
	_i = 0
	for _side in ('W', 'S', 'E', 'N'):
		for _ in range(_pkg.PinsOnEachSide[_side]):
			_pkg.Pins[_i].Side = _side
			_i += 1
	return _padRingDict(_pkg)

m.PackageModels = dict((_model, _padRingForModel(_model)) for _model in _PACKAGE_MODELS)


# Generate all output files
m.Generate(test=False, force=True, saveHardware=True, saveSoftware=True)

# SystemRDL side artifacts (tools/rdl/README.md).
# The register maps are already in: _rdlRegisters() built most of the peripheral templates
# above out of hdl/common/regs/rdl/, so the TRM tables, MemoryMap.h, MemoryMap.vhd and the
# configurator data m.Generate() has just written are the descriptions. What is emitted here
# is the rest of what the descriptions can produce and the generator does not otherwise
# write:
#   out/rdl/<TAG>_reg_pkg.vhd   the offset, field and reset package a new peripheral can
#                               `use` instead of declaring constants locally
#   out/rdl/<TAG>_rdl.json      the block's register sub-tree with its SystemRDL provenance
#                               (source file, addrmap, word base)
#   out/rdl/<TAG>-registers-rdl.tex, MemoryMap_<TAG>_rdl.h
#                               the per-block table and header fragment
# One of these the TRM inputs directly: DEBUG-registers-rdl.tex. The Debug Module is not
# memory-mapped, since its registers live in the DMI address space reachable only through
# the JTAG DTM, so it has no PeripheralTemplate, no register-index row and no place in
# MemoryMap.h, and hdl/common/regs/rdl/debug_module.rdl is its only machine-readable
# description.
# systemrdl-compiler is not optional: the chip's register map comes out of it, so a missing
# toolchain must stop the generation rather than silently emit a chip with eighteen
# peripherals' registers missing.
def _emitRdlArtifacts():
	import rdl_emit
	cfgPath = chipRootDirectory + '/config/rdl.json'
	flags = rdl_emit.loadFlags(cfgPath)
	# A peripheral this configuration does not instantiate has nothing to document. A block that
	# is not memory-mapped at all is always emitted: there is no instance to look for.
	present = set(p.Template.NameTemplate for p in m.Peripherals)
	flags = [f for f in flags if f['peripheral'] is None or f['peripheral'] in present]
	outDir = outputRootDirectory + '/out/rdl'
	if not os.path.isdir(outDir):
		os.makedirs(outDir)
	trmInclude = outputRootDirectory + '/latex/TRM/include'
	for flag in flags:
		block, written = rdl_emit.emitBlock(flag, outDir)
		tag = flag['name'].replace('_', '')
		if flag['peripheral'] is None and os.path.isdir(trmInclude):
			name = tag + '-registers-rdl.tex'
			with open(os.path.join(outDir, name)) as _rf:
				_tex = _rf.read()
			with open(os.path.join(trmInclude, name), 'w') as _wf:
				_wf.write(_tex)
		print('[generate] SystemRDL: ' + flag['name'] + ' from hdl/common/regs/rdl/'
			+ flag['source'] + ' (' + str(len(block.RegisterTemplates)) + ' registers, '
			+ str(len(written)) + ' files)')
	return

_emitRdlArtifacts()

# Unified-config artifacts, written last so they only land on a successful build.
# Both are TRACKED files under config/, and rewriting them in place made every CONFIG= run
# dirty the working tree, so the next default build had to restore them. They are therefore
# always written beside the other outputs, in out/config/, and config/ is refreshed only by
# a default build (no --config and no CHIP_CONFIG) or when the bytes would not change.
# Read out/config/ for the record of THIS build and config/ for the default chip's.
def _writeResolvedRecord(fileName, payload, what):
	body = json.dumps(payload, indent=2) + '\n'
	besideDirectory = os.path.join(outputRootDirectory, 'out', 'config')
	if not os.path.isdir(besideDirectory):
		os.makedirs(besideDirectory)
	with open(os.path.join(besideDirectory, fileName), 'w') as _f:
		_f.write(body)
	print('[generate] wrote out/config/' + fileName + ' (' + what + ')')
	trackedPath = os.path.join(outputRootDirectory, 'config', fileName)
	unchanged = False
	if os.path.isfile(trackedPath):
		with open(trackedPath) as _f:
			unchanged = (_f.read() == body)
	if _cfgPath and not unchanged:
		print('[generate] kept config/' + fileName + ' (the default chip\'s record; this build is '
			+ os.path.basename(_cfgPath) + ')')
		return
	if not os.path.isdir(os.path.dirname(trackedPath)):
		os.makedirs(os.path.dirname(trackedPath))
	with open(trackedPath, 'w') as _f:
		_f.write(body)
	print('[generate] wrote config/' + fileName + ' (' + what + ')')

_writeResolvedRecord('ChipConfig.resolved.json', m.ResolvedConfig, 'resolved configuration')
_writeResolvedRecord('PadRing.json', m.PadRing, 'derived pad ring')

# Innovus pad-placement template for the connected chip_top flow: one derived pad ring feeds
# the docs (PadRing.json and the TRM pinout) and PnR. It emits ordered per-side pad lists in
# the format the innovus chip-top flows' place_side proc consumes. Lists are in placeInstance
# geometric order (+x for the bottom and top rows, +y for the left and right rows), and QFN
# pin 1 sits at the top of the left edge under top-view counter-clockwise numbering, so the
# W and N side lists run in descending pin order. Pad instance names are placeholders,
# PAD_<pad>, bound to tphn65gpgv2od3_sl cells and nets downstream.
def _padInstName(_name):
	'''"P3.0(GPIO24)/SDA0" -> PAD_P3_0 ; "VDDPST" -> PAD_VDDPST ; "ATP-IN" -> PAD_ATP_IN'''
	_base = _name.split('(')[0].split('/')[0].strip()
	return 'PAD_' + _base.replace('.', '_').replace('-', '_')

_sideGeom = [	# (PadRing side, Flavor-A side name, geometric pin order)
	('W', 'left', True),	# descending: pin 1 at the top, +y order = 11..1
	('S', 'bottom', False),	# ascending: 12..22 left-to-right (+x)
	('E', 'right', False),	# ascending: 23..33 bottom-to-top (+y)
	('N', 'top', True),		# descending: 34 at the right, +x order = 44..34
]
_padTclLines = [
	'# chip_top_padring.tcl -- GENERATED by platform/common (make chip); do not hand-edit.',
	'# Ordered pad lists for the chip_top pad-ring flow (innovus/common, Flavor A/B):',
	'#   source out/pnr/chip_top_padring.tcl',
	'#   place_side left $PADRING_LEFT   ;# etc. (place_side/place_pad from chip_top.innovus.tcl)',
	'# Derived from the same package model as config/PadRing.json + the TRM pinout',
	'# (model "' + packageModel + '", ' + m.Package.PackageType + '-' + str(m.Package.PinCount) + '). Lists are in placeInstance geometric order:',
	'# +x for bottom/top rows, +y for left/right rows; QFN pin 1 is at the TOP of the',
	'# left edge (top view, CCW numbering), so the left/top lists run pin-descending.',
	'# Instance names are placeholders (PAD_<pad>); Flavor B binds cells and nets.',
	'',
]
# Uniquify repeated instance placeholders: a multi-pair supply model emits PAD_VDD three
# times, which is an illegal duplicate instance name in the consuming netlist and padlists.
# A base that occurs once keeps its bare name (PAD_RESETN, PAD_P3_0), and repeats get
# _0/_1/... in emission order (W descending, S ascending, E ascending, N descending), so the
# names line up with the staged netlist.
_instTotals = {}
for _sd, _sideName, _desc in _sideGeom:
	for _p in sorted([_q for _q in m.Package.Pins if _q.Side == _sd],
			key=lambda _q: _q.PackagePinNumber, reverse=_desc):
		if _p.NoConnect:
			continue
		_b = _padInstName(_p.Name)
		_instTotals[_b] = _instTotals.get(_b, 0) + 1
_instSeen = {}
for _sd, _sideName, _desc in _sideGeom:
	_sidePins = sorted([_p for _p in m.Package.Pins if _p.Side == _sd],
		key=lambda _p: _p.PackagePinNumber, reverse=_desc)
	_padTclLines.append('set PADRING_' + _sideName.upper() + ' {}')
	for _p in _sidePins:
		if _p.NoConnect:
			_padTclLines.append('# (pin ' + str(_p.PackagePinNumber) + ': NC -- no pad instance; filler closes the gap)')
			continue
		_nm = _p.FullName
		_dom = _p.PowerDomain.Name
		_b = _padInstName(_p.Name)
		if _instTotals[_b] > 1:
			_inst = _b + '_' + str(_instSeen.get(_b, 0))
			_instSeen[_b] = _instSeen.get(_b, 0) + 1
		else:
			_inst = _b
		_padTclLines.append('lappend PADRING_' + _sideName.upper() + ' '
			+ _inst.ljust(16)
			+ ';# pin ' + str(_p.PackagePinNumber).rjust(2) + ': ' + _nm + '  [' + _dom + ']')
	_padTclLines.append('')
_pnrDir = outputRootDirectory + '/out/pnr'
if not os.path.isdir(_pnrDir):
	os.makedirs(_pnrDir)
with open(_pnrDir + '/chip_top_padring.tcl', 'w') as _f:
	_f.write('\n'.join(_padTclLines))
	_f.write('\n')
print('[generate] wrote out/pnr/chip_top_padring.tcl (pad-placement template for the chip_top flow)')

# One closing line naming where this run put each family of artifact, so a reader of the log
# never has to work out whether --out was in play.
print('[generate] outputs under ' + os.path.abspath(outputRootDirectory)
	+ ': RTL out/hdl/, headers out/software/include/, linker scripts out/linker-scripts/,'
	+ ' pad ring out/config/PadRing.json and out/pnr/chip_top_padring.tcl,'
	+ ' TRM sources latex/TRM/')

