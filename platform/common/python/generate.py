#!/usr/bin/env python3

import pathlib, sys, os

thisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
chipRootDirectory = thisFileDirectory + '/..'

# No need to append path since we're already in ChipGenerator/python

from ChipGenerator import ChipGenerator
from Peripheral import PeripheralTemplate, Peripheral
from Register import RegisterTemplate, Register
from BitField import BitField
from GpioConfigurator import GpioConfigurator, GpioAltFunc

# ---------------------------------------------------------------------------
# Optional configuration file:  make chip CONFIG=path/to/config.json
# A small JSON document (produced by docs/chip_configurator.html, or written by
# hand). EVERY key is OPTIONAL and falls back to the Castalia default in the
# ChipGenerator(...) call below. Only the documented SCALAR knobs are honored:
# chip name, hart count, register file, the ISA generics, and the memory-region
# sizes. The peripheral SET is fixed RTL template content (see
# platform/common/CLAUDE.md). Since A1 (Argus N-hart generalization,
# 2026-07-10) numHarts ALSO drives the generated MCU.vhd regions (hart-tile
# instances, arbiter/fabric widths, CLINT layout) — but only numHarts=4 is
# verified drop-in RTL today (check_mcu_vhd.py STRICT); other hart counts
# need the A2/A3 RTL generalizations (s_master width, irq_router/pwr_ctrl
# regrow, sh_sel/flash move) before the emitted MCU.vhd elaborates.
# Precedence for the name:  CHIP_NAME env var  >  config file  >  default.
# ---------------------------------------------------------------------------
import json
_CHIP_CONFIG = {}
_cfgPath = os.environ.get('CHIP_CONFIG', '').strip()
if _cfgPath:
	with open(_cfgPath) as _f:
		_CHIP_CONFIG = json.load(_f)
	print('[generate] loaded chip configuration from ' + _cfgPath)

# ---------------------------------------------------------------------------
# OVERLAY (2026-09-12). A chip whose blocks cannot live in the public tree
# names an out-of-tree directory that contributes extra configurations,
# register descriptions, package models, peripheral definitions and emitter
# fragments. `overlay` is a GENERATOR DIRECTIVE, not a schema knob: it is
# consumed and removed here, so it never reaches _validateChipConfig, the
# resolved-config record, the configurator or the TRM tables -- the same
# treatment CHIP_NAME gets. A relative path resolves against the configuration
# file's own directory; VESTA_OVERLAY in the environment wins over both.
# With neither set every overlay entry point below is inert.
# See platform/common/python/overlay.py for the contract.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# THE config schema — the single authoritative list of knobs a CONFIG= file
# may set. docs/chip_configurator.html emits exactly these keys, the TRM's
# generated Chip Configuration section documents them, and the resolved
# values land in config/ChipConfig.resolved.json. Keep all four in sync.
# Every key is optional (missing = the Castalia default). Unknown keys RAISE:
# a typo that silently falls back to the default is worse than an error.
#
# THE DESCRIPTION STRING IS A TABLE CELL, SO WRITE IT AS ONE (2026-08-15, USER
# review of TRM table 1). Each description is rendered THREE ways — the TRM's
# "Meaning / valid values" column, the configurator's help text, and the
# unknown-key error listing — and the narrow TRM column is the binding one: a
# knob whose description had grown into a paragraph printed a FULL PAGE for one
# row (`orchestrator` and `priv.trapCsr` were the two the user named). Keep it
# to one sentence: the valid values, then what the knob does, ~80 characters,
# never more than about two rendered lines. The mechanism detail belongs in the
# TRM chapter and in the comments HERE — where a description was cut, its long
# form is preserved verbatim in a `Long form, preserved` comment above the entry,
# so nothing was lost, only moved out of the table.
# ---------------------------------------------------------------------------
def _isBool(v):
	return isinstance(v, bool)
def _isInt(v):
	return isinstance(v, int) and not isinstance(v, bool)
def _isMemSize(v, ceiling):
	return _isInt(v) and 0 < v <= ceiling and v % 0x400 == 0

# Package models (G4, 2026-07-11): the pad ring derives from a PYTHON-DEFINED
# package model; a config SELECTS one by name. Free-form pin assignment in the
# config is intentionally unsupported — a chip gets its own pinout by adding a
# model here (Argus will, once its package is decided), never in JSON.
_PACKAGE_MODELS = ('myshkin-qfn44', 'castalia-quad-qfn64', 'castalia-lqfp100')
# An overlay may add package models of its own (a ring whose pad map is not
# distributable); _buildPackageData's `packageData` stage builds them.
_PACKAGE_MODELS = tuple(overlay.call('packageModels', default=_PACKAGE_MODELS,
	models=_PACKAGE_MODELS))
_CONFIG_SCHEMA = {
	'chipName':             ('non-empty string: renames the chip in the TRM and headers (CHIP_NAME env wins)',
	                         lambda v: isinstance(v, str) and len(v.strip()) > 0),
	'numHarts':             ('int 1..32: hart count; hart 0 is the always-on management hart and harts 1..N-1 are the power-gateable tiles',
	                         lambda v: _isInt(v) and 1 <= v <= 32),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# CPR3/R1 (Castalia-Penta rework): is there an always-on soft ORCHESTRATOR hart? false
	# (the default) is the historical shape — every hart is a hardened `hart_tile`, hart 0 is
	# the management hart, and the generated RTL is byte-identical to a build that never heard
	# of this knob. true makes HART 0 the orchestrator: it is emitted as `entity
	# work.orch_tile` (a thin wrapper whose only job is to keep the soft core's module names
	# disjoint from the hardened hart_tile netlist — see orch_tile.vhd and CP1 D6), keeps
	# every hart-0 wiring special it already had (the SPI0 flash/XIP quartet, sleep =>
	# sleep_cpu, trap_flag => the GPIO0 trap pin, a0 => the tb pass/fail gate, tcm_pgen =>
	# pgen_mem(1), arbiter master slice 0 with no isolation clamps), and harts 1..numHarts-1
	# become FULLY UNIFORM channel tiles — hart_id 1..N-1, pwr_ctrl rows 1..N-1 (so PWRCR
	# gains a gate bit for what used to be hart 0's always-on tile), iso clamps, tcm_pgen =>
	# pd_sleep(h), flash ports open, a0_h monitored. It also switches the memory map to v2
	# (R3): SH_AW = max(derived, 16), five READ-ONLY TCM apertures at TCMWIN[h] = 0x20000 +
	# h*0x4000 through which the management hart (and only it — the s_master = 0 gate) reads
	# any hart's private TCM, and extended flash at the automatic strict complement 0x40000.
	# The management hart is hart 0 in BOTH shapes, so afe_stub's MGMT_HART generic is never
	# overridden (its entity default 0 is correct everywhere) and only the AFE bank's
	# OWNER_HART literals shift with the tiles (AFE0-3 own harts 1-4; the EIS engine stays
	# hart-0/management-only). Everything else follows the existing single sources —
	# nMasters()/masterW()/dmMasterIndex() and clint/irq_router/debug_module NHARTS =>
	# numHarts (the CLINT layout SHIFTS with the hart count: mtime 0x5010 -> 0x5020 at N=5 —
	# firmware must derive CLINT addresses from NHARTS)
	'orchestrator':         ('bool: hart 0 is the always-on orchestrator; harts 1..N-1 are gateable tiles',
	                         _isBool),
	'numMutexes':           ('int 1..1024: hardware mutex bank size, the number of MUTEXn registers',
	                         lambda v: _isInt(v) and 1 <= v <= 1024),
	'registerFileDualPort': ('bool: docs-only, the register file is dual-port in the RTL either way',
	                         _isBool),
	# Fetch-ahead (ENABLE_IF_AHEAD, 2026-08-23). A C-extension straddling fetch
	# costs the core a repeat_if bubble: the second half of a 32-bit instruction
	# sitting across a word boundary forces a re-fetch of a word the core held
	# one cycle earlier. Fetch-ahead keeps that word in a single flip-flop and
	# serves the straddle from it. Measured on the shipped core: 85% of the
	# straddling-fetch penalty removed, aggregate CPI 1.523 -> 1.260, about 17%
	# fewer cycles on qsort, and STA shows the added flop is off the critical
	# path. It has no software-visible effect -- no CSR, no instruction, no
	# memory-map change -- so it is a pure timing knob and it costs one flop.
	# Meaningless without the C extension: the straddle it removes only exists
	# when 16-bit instructions can misalign a 32-bit one, so an isa.compressed
	# OFF build wires the generic on and the core's own gate keeps it inert.
	'core.fetchAhead':      ('bool: C-extension fetch-ahead (one flip-flop; removes most of the straddling-fetch stall)',
	                         _isBool),
	'isa.mul':              ('bool: M multiply', _isBool),
	'isa.fastMul':          ('bool: docs-only, the multiplier is already single-cycle', _isBool),
	'isa.div':              ('bool: M divide', _isBool),
	'isa.atomics':          ('bool: A extension (LR/SC + AMO)', _isBool),
	'isa.compressed':       ('bool: C extension', _isBool),
	'isa.bitmanip':         ('bool: Zba/Zbb/Zbs/Zbc', _isBool),
	# ASYMMETRIC ISA (2026-08-16, USER: "minimal rv32iac for each tile ... make this
	# chip as small and low power as possible"). True = the HARDENED CORNER TILES
	# (harts 1..numHarts-1) drop M and B and are built rv32iac, while HART 0 -- the
	# soft orchestrator, which runs boot, management and anything needing arithmetic
	# -- keeps the full chip ISA above. This is the ONE asymmetry the chip has, and
	# it lands on the seam that already exists: hart 0 is an orch_tile (soft,
	# synthesized from RTL) and harts 1..N-1 are instances of ONE hardened hart_tile
	# macro, so the split costs no extra hardening -- still harden once, place 4x.
	# MEASURED on the 8 KiB tile at genus, full vs rv32iac:
	#   tile 132,657 -> 109,926 um2 (-17.1%)   core 60,540 -> 37,808 um2 (-37.5%)
	#   flops 2,576 -> 2,210 (-366)            power 2.687 -> 1.945 mW (-27.6%)
	#   leakage 460 -> 379 uW (-17.6%)         x4 tiles = ~91,000 um2 and ~3.0 mW
	# A AND C ARE NOT DROPPED, deliberately: the tiles are exactly the harts that run
	# the M7c/M8 shared-fabric locking (LR/SC + AMOs), so removing A would break the
	# mutex infrastructure outright; and C is decoder-only (456 um2 measured) while
	# it SHRINKS code, which matters more now that a TCM is 8 KiB.
	# SOFTWARE CONTRACT this creates: no binary may migrate between hart 0 and a
	# corner tile, and anything the tiles execute must be built without M/B. Verified
	# at the flip that no tile-executed test uses them (the three M/B uses in
	# tile-launching tests -- dbgdarkmp, packalias, fk51mp -- all sit in hart-0-only
	# code, above each test's tile_entry label).
	'isa.minimalTiles':     ('bool: harts 1..N-1 drop M and B (rv32iac); hart 0 keeps the full ISA',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# Zicntr mcycle/minstret; docs/march-only on vesta (cycle/instret and their high halves
	# are always present — this gates only the _zicntr march suffix and the legacy constants).
	# NOTE the march suffix over-promises since DD11-N1: time/timeh (0xC01/0xC81) are NOT
	# implemented in any build and a read of either raises illegal-instruction, because no
	# real time source is wired to the core
	'isa.counters':         ('bool: Zicntr march suffix only (cycle/instret always exist, time/timeh never do)', _isBool),
	'isa.counters64':       ('bool: docs-only high counter halves (always present); needs isa.counters', _isBool),
	# ISA extensions. X1 (2026-07-17) implemented the six Tier-1 knobs below
	# (zicond zcb zimop zihint zihpm zawrs) — default false, decode + tests +
	# both-polarity gates landed. X2 (zabha zacas), X3 (zicboz zcmp zcmt zbkb
	# zbkc zbkx zkn) and X4 (zfinx, 2026-07-18) implemented the rest: every
	# isa.* knob below is real hardware and the X0 scaffolding hard-error
	# list (_SCAFFOLDED_ISA) is empty — no knob advertises hardware it lacks.
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
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# Zfinx single-precision FP in x-regs (shared FMA-based backend, exactly one rounding, all
	# 5 rounding modes, full subnormals; radix-2 iterative div/sqrt; fcvt family). Implemented
	# X4 — the largest single extension (0.034 mm² of tile area).
	'isa.zfinx':            ('bool: Zfinx single-precision floating point in the x registers', _isBool),
	# P-series PRIVILEGED ARCHITECTURE. The generics ride the full chain
	# (generate.py -> ChipGenerator -> mcu_vhd -> MemoryMap CORE_* ->
	# hart_tile -> vesta -> maindec/csr_unit). ALL THREE HAVE GRADUATED:
	# 'trapCsr' at P1 and 'umode' at P2 (2026-07-28), 'pmp' at P3
	# (2026-07-29) -- _SCAFFOLDED_PRIV below is now EMPTY, so none of them
	# hard-errors any more. The dependency validations (umode => trapCsr,
	# pmp => umode) stay LIVE and are the only gate left.
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool — P1:
	# standard M-mode trap architecture, IMPLEMENTED in full (P1, 2026-07-28): the CSR file
	# (mstatus/mstatush/mtvec/mie/mip/mscratch/mepc/mcause/mtval + the custom mtrapctl @0x7C0
	# legacy-select bit) AND standard delivery — MRET/ECALL/EBREAK decode, mtvec-vectored
	# exceptions and interrupts (MEI>MSI>MTI), the mstatus MPIE/MIE stack. mtrapctl.LEGACY
	# resets 1, so even an ON chip boots on the legacy irq_handler/IVT path and is suite-
	# identical until software clears the bit. DEFAULT TRUE since K7/R-DK3 (2026-08-04) on
	# both Castalia and Argus: the CSR file and standard delivery are present, boot is bit-
	# identical, and a hart enters standard delivery only when its own firmware writes
	# mtrapctl (csrw 0x7C0, x0). Cost, measured at K6: +144 flops per tile (genus sequential
	# 2251 -> 2395), +3.85% standard-cell area, +1.29% tile area, timing neutral. Set false to
	# get a pre-P1 chip back: all ten addresses and the three encodings stay illegal. HAZARD
	# any firmware policy must respect: clearing LEGACY on a hart that then EXTINGUISHes makes
	# it unwakeable (the legacy IVT slot-83 msip path is what the bootrom park/wake contract
	# uses) -- per-hart only, never before park
	'priv.trapCsr':         ('bool: standard M-mode trap CSRs and delivery; firmware opts in via mtrapctl', _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool — D1:
	# CORE-SIDE DEBUG MODE (2026-08-05). Debug mode as a privilege state: the Debug-Mode CSRs
	# dcsr/dpc/dscratch0/dscratch1 (0x7B0-0x7B3, accessible ONLY in debug mode -- from M or U
	# they raise illegal-instruction), the DRET encoding, an unmaskable halt request sampled
	# at the same fourteen FSM points an interrupt is (including the terminal TRAP_STATE, so a
	# debugger can rescue a wedged hart), halt-on-reset, ebreak-to-debug under dcsr.ebreakm,
	# and single-step. Debug entry vectors to DEBUG_ENTRY_ADDR, which is the SHARED-WINDOW
	# debug program page 0x00010780 on every debug-ON build (R-DD3/R-D2-1(3): a tile's TCM is
	# unreachable from the shared bus, so a Debug Module could never place code at the old TCM
	# default 0xBE00 -- that address survives only as the VHDL generic's fail-safe declaration
	# default). REQUIRES priv.trapCsr: ebreak and the whole SYSTEM PRIV decode arm are
	# trapCsr-gated, so a debug-without-trapCsr chip could not recognise a software breakpoint
	# at all. Default false: the four CSR addresses and the DRET encoding stay illegal, the
	# three tile debug ports fold away, and the core is bit-identical to a chip built before
	# D1. THE KNOB NOW CARRIES THE WHOLE TRANSPORT. D2 added the assembly-level Debug Module
	# dm0 (run control, dmstatus truth-telling against PWRCTRL, abstract access-register
	# commands, a 2-word program buffer, halt groups, hartsel/haltsum at N=4 AND N=18) with
	# its eight dmi_* MCU ports; D3 added the JTAG DTM dtm0 (16-state TAP, 5-bit IR,
	# IDCODE/dtmcs/dmi(41)/BYPASS, the TCK<->mclk crossing) with the five pins
	# tck/tms/tdi/tdo/trstn, and merged it with the dmi_* ports by valid-gated OR so both
	# masters reach the one DM. D4 LANDED 2026-08-07 AND THERE IS NO DEBUG ROM: R-DD5 took
	# option B, so dm0 PLANTS the 40-word entry code itself, out of a constant table, through
	# the master port it already owned -- once at every dmactive 0->1, and again before it
	# consumes a newly-halted hart's token. A ROM was rejected on STRUCTURE, not cost: 24 of
	# the entry page's 64 words are DM-written at runtime and must stay writable, so read-only
	# memory there would break the Debug Module outright. The table is held equal to the built
	# software/dbg_trampoline/dbg_trampoline.S by tools/cosim/check_dbg_trampoline.py, a
	# standing gate (rc 0 equal / 1 mismatch / 2 missing -- never a silent skip). The page is
	# self-repairing for every word but the FIRST (F-D4-1: a hart that halts into a wrong word
	# 0 re-asks for that same word and hart_tile's same-word ack hold keeps re-serving the
	# stale copy, so it wedges until a PWRCTRL tile power-cycle). STILL OUT OF SCOPE and
	# arriving later in the D-series: OpenOCD/gdb bring-up (D5) and hardware triggers (D6).
	# System Bus Access is out FOREVER by design -- memory access is progbuf lw/sw through the
	# halted hart. Cost, measured: +742 flops on the Castalia assembly at D2 (452 core + 265
	# dm0 + 25 fabric), plus dtm0 at D3, plus 4 for the D4 plant (assembly 18,159 -> 18,163)
	'debug.enable':         ('bool: debug mode, the Debug Module and the JTAG DTM; needs priv.trapCsr', _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool — P2:
	# user mode, IMPLEMENTED in full (P2, 2026-07-28): the 1-bit privilege register (reset M)
	# with the MPP push/pop riding trap entry and MRET, mstatus.MPP WARL widened to {00,11}
	# (unsupported 01/10 map to M), mstatus.TW, a real mcounteren (CY/TM/IR/HPM3/HPM4),
	# misa.U, ECALL-from-U cause 8, the standard WFI encoding with its wake-on-(mip&mie) rule,
	# and the U-mode decode gate — every machine/custom CSR (csr_addr(9:8)/="00"), MRET, the
	# three custom Vesta instructions and a TW-denied WFI trap illegal-instruction, and a
	# denied CSR access commits no write. Requires priv.trapCsr. Default false: no privilege
	# register, misa.U clear, MPP WARL {11}, mcounteren read-zero — bit-identical to a P1 chip
	'priv.umode':           ('bool: user mode (privilege register, MPP stack, mcounteren); needs priv.trapCsr', _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool — P3:
	# physical memory protection (Smpmp), IMPLEMENTED (P3, 2026-07-29): the pmpcfg0-3 /
	# pmpaddr0-15 CSR bank (packed 4x8-bit cfg, R/W/X/A(4:3)/L with bits 6:5 WARL 0, W pinned
	# 0 when R=0, pmpaddr bits 31:30 WARL 0), the full lock semantics (a locked entry's cfg
	# AND address are immutable until reset, a TOR-locked entry also write-locks its
	# predecessor address, per-byte lock filtering inside a pmpcfg word), and the
	# combinational match unit (OFF/TOR/NA4/NAPOT at G=0, lowest-numbered match decides alone,
	# locked entries enforce on M-mode, no-match grants M and faults U). The pre-issue
	# fetch/load/store CHECK INTEGRATION with its access-fault causes 1/5/7 lands with the
	# vesta diff of the same phase. Requires priv.umode. Default false: all twenty addresses
	# stay illegal CSRs and the match unit is not instantiated — bit-identical to a P2 chip
	'priv.pmp':             ('bool: PMP (Smpmp) CSR bank and match unit; needs priv.umode', _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): int — PMP
	# entry count, {8, 16} ONLY (the PMP_ENTRIES generic). Consulted only when priv.pmp is
	# true; the CSR map is the 16-entry superset regardless (entries above the count are WARL
	# all-zero). Default 16
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
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# False drops the NPU entirely (slot 10 + the 0xC000 staging window read zero)
	'peripherals.npu':      ('bool: false drops the NPU (slot 10 and the 0xC000 staging window read zero)',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# False drops the second I2C instance (slot 15 reads zero, IRQ vectors 70-82 reserved,
	# SDA1/SCL1 pins revert to plain GPIO)
	'peripherals.i2c1':     ('bool: false drops I2C1 (slot 15 reads zero; SDA1/SCL1 revert to plain GPIO)',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# False drops the second UART instance (slot 5 reads zero, IRQ vectors 52-54 reserved,
	# TX1/RX1 pins revert to plain GPIO)
	'peripherals.uart1':    ('bool: false drops UART1 (slot 5 reads zero; TX1/RX1 revert to plain GPIO)',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# False drops the second SPI instance (slot 3 reads zero, IRQ vectors 11-12 reserved,
	# CS1/MISO1/MOSI1/SCK1 pins revert to plain GPIO)
	'peripherals.spi1':     ('bool: false drops SPI1 (slot 3 reads zero; its four pins revert to plain GPIO)',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# False drops the second TIMER instance (slot 7 reads zero, IRQ vectors 22-27 reserved,
	# T1CMP*/T1CAP* pins revert to plain GPIO)
	'peripherals.timer1':   ('bool: false drops TIMER1 (slot 7 reads zero; the T1 pins revert to plain GPIO)',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# True instantiates the four AFE register stubs (page-0 slot 12 @0x4C00, sub-slots on
	# sh_addr(5:4)) and the shared EIS engine stub (0x7C00); the Castalia golden master keeps
	# them. False frees slot 12 for a native peripheral (mutually exclusive with
	# peripherals.qspi) and reserves IRQ vectors 55/56
	'peripherals.cqAfeStubs': ('bool: the four AFE register stubs and the EIS engine stub (slot 12, 0x4C00)',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# True instantiates the QSPI0 controller in page-0 slot 12 (0x4C00), driving IRQ vectors
	# 55 (transfer-complete) and 56 (RX-full); requires peripherals.cqAfeStubs=false (both
	# claim slot 12). Default false
	'peripherals.qspi':     ('bool: QSPI0 controller in slot 12 (0x4C00); needs cqAfeStubs false',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# True instantiates the I3C0 controller (MVP+DAA+IBI) at 0x6100: page-2 (MUTEX page) sub-
	# slot 1. Tightens the mutex-bank decode to its 256 B sub-slot 0 (retiring the page-wide
	# alias whose reads had a CLAIM side effect), adds a page-2 sub-decode, and GROWS the IRQ
	# source list to 94 (a reserved placeholder at the frozen meip slot 85, then I3C vectors
	# 86-93: tc/rxf/txe/nack/eod/arb/daa/ibi). Default false
	'peripherals.i3c':      ('bool: I3C0 controller (MVP + DAA + IBI) at 0x6100',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# True instantiates the NFC0 ISO 14443A tag / card-emulation engine at 0x6200: page-2
	# (MUTEX page) sub-slot 2. Like I3C it tightens the mutex-bank decode to its 256 B sub-
	# slot 0 (retiring the aliased-CLAIM side effect) and adds the page-2 sub-decode. GROWS
	# the IRQ source list to 98 (meip stays frozen at slot 85; sources 86-93 are I3C or
	# reserved; NFC drives vectors 94-97: field/rxf/txdone/crcerr). The digital AFE / RF
	# interface is off-die (placeholder-tied). Default false
	'peripherals.nfc':      ('bool: NFC0 ISO 14443A tag engine at 0x6200 (the RF front end is off-die)',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# True instantiates the RTC0 real-time clock (32.768 kHz always-on wall clock + one-shot
	# alarm + periodic tick) at 0x6500: page-2 (MUTEX page) sub-slot 5. Zero pins; clocks off
	# the UNGATED lfxt_in pad crystal, with the CDC synchronizers / sticky W1C flags / IRQ
	# combiner on the free-running MCLK. GROWS the IRQ source list to 115: vector 114 = RTC0
	# (single combined alarm/tick IRQ, above GPIO5's 106-113). NUM_EN_WORDS stays 4 (115 <=
	# 128). Default false
	'peripherals.rtc':      ('bool: RTC0 32.768 kHz wall clock with alarm and tick at 0x6500',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# True instantiates the PWM0 buffered PWM generator (2 channels, glitch-free double-
	# buffered update, software fault trip, period-event tick) at 0x6600: page-2 (MUTEX page)
	# sub-slot 6. Zero input pins; the two outputs pwm_out(0)/(1) REPLACE two redundant timer-
	# compare spread copies (P2.2/P2.3 AF2, the pin-mux-v2 replaced-spread-slot precedent).
	# Free-running MCLK engine (no LFXT, no generated clocks). GROWS the IRQ source list per
	# the GLOBAL VECTOR RULE (A5): vectors 115 = PWM0_FAULT (lower id = router priority), 116
	# = PWM0_EVT; when a lower library block (RTC vector 114) is off but pwm is on, 114
	# backfills as IRQB_RSVD114. NUM_EN_WORDS stays 4 (117 <= 128). Default false
	'peripherals.pwm':      ('bool: PWM0 two-channel buffered PWM at 0x6600 (outputs on P2.2/P2.3)',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# True instantiates the OW0 Dallas/Maxim 1-Wire master (reset+presence, write/read bit +
	# byte link-layer primitives off a programmable time base; ROM search + CRC-8 in firmware;
	# standard + overdrive; one open-drain DQ pin) at 0x6700: page-2 (MUTEX page) sub-slot 7.
	# One pad: DQ on P4.7 / GPIO31 (DTP3), alt plane AF2, open-drain, rstREN=1 — the pin-
	# mux-v2 REPLACED-SPREAD-SLOT mechanism (it takes over the redundant T0CMP1 output-spread
	# copy in that slot; T0CMP1 keeps its P3.1/GPIO17 AF0 primary, its P2.1/P4.5 AF1
	# relocations and 26 other spread copies, so the replacement is pure redundancy). Free-
	# running MCLK engine (no LFXT, no generated clocks, no clock on the DQ pad — DQ is 2-FF
	# synchronized). EXTENDS the IRQ source list per the GLOBAL VECTOR RULE (A5) to 118:
	# vector 117 = OW0 (single combined transaction-complete/error IRQ); when a lower library
	# block (RTC 114, PWM 115/116) is off but onewire is on, those slots backfill as
	# IRQB_RSVD. NUM_EN_WORDS stays 4 (118 <= 128). Default false
	'peripherals.onewire':  ('bool: OW0 1-Wire master at 0x6700, open-drain DQ on P4.7',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# True wires the DP-S3 field-powered-mode supervision inputs into PWRCTRL: P6.7/GPIO47 =
	# PGOOD supply-supervisor input, P6.6/GPIO46 = harvested-boot strap. Both are plain-GPIO
	# DIRECT TAPS of the pad-input plane (always readable, independent of PxSEL/PxAFS — PGOOD
	# must gate boot before any software can program a mux), with reset attrs rstDIR=input,
	# rstREN=1, pull-DOWN: unconnected reads power-not-good + NORMAL(SPI) boot. Also taps
	# NFC0's field_detect level as an optional PWRCTRL wake/release source (tied 0 when NFC is
	# absent). The PWRCTRL PWRWAKE/PWRSTS registers and the pgood_rstn HOLD-IN-RESET boot gate
	# exist in the RTL unconditionally; this knob only controls the pad-side ties, so False
	# leaves the feature a provable NO-OP (gate stuck released). Default true (the Castalia
	# golden master carries the live wiring)
	'peripherals.fieldPower': ('bool: wires the field-power pins (PGOOD, harvest strap) into PWRCTRL',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# True instantiates the DMA0 configurable multi-channel single-shot DMA controller
	# (peripheral-paced or software-GO mem-to-mem transfers, CRC16 ride-along) at 0x6800:
	# page-2 (MUTEX page) sub-slot 8. Zero pins. DMA0 is the FIRST new arbiter MASTER since
	# the four harts (M13): enabling it WIDENS the shared fabric from N=4 to N=5 masters (the
	# DMA is master index numHarts, the last slice) — mp_arbiter N=>5/MW=>3, resv_unit N=>5,
	# mutex_bank/irq_router MW=>3, sh_master 2->3 bits, arb_* buses grow a 5th slice. EXTENDS
	# the IRQ source list per the GLOBAL VECTOR RULE (A5) to 119: vectors 118 = DMA0_DONE
	# (combined channels-done), 119 = DMA0_ERR; when a lower library block (RTC 114, PWM
	# 115/116, OW 117) is off but dma is on, those slots backfill as IRQB_RSVD. NUM_EN_WORDS
	# stays 4 (119 <= 128). Default false
	'peripherals.dma':      ('bool: DMA0 multi-channel DMA at 0x6800; adds one more arbiter master',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): int — DMA0
	# channel count, {2, 4} ONLY (the NCH generic; the register map is the 4-channel superset
	# regardless, absent channels read 0). Consulted only when peripherals.dma is true.
	# Default 4
	'peripherals.dmaChannels': ('int, 2 or 4: DMA0 channel count when peripherals.dma is true (default 4)',
	                         lambda v: _isInt(v) and v in (2, 4)),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# True instantiates the I2CT0 hardware-autonomous I2C TARGET (slave) at 0x6A00: page-2
	# (MUTEX page) sub-slot 10. 7-bit address match + mask + general call, byte-at-a-time
	# RX/TX with ready/empty status, hardware clock stretching, START/STOP/repeated-START/NACK
	# framing flags, and a stuck-SCL watchdog — all in the free-running MCLK domain (D4-clean,
	# 2-FF SDA/SCL sync, no pad-clocked processes). Two combined IRQs delivered per the GLOBAL
	# VECTOR RULE (A5): vector 122 = I2CT0_AE (address/error), 123 = I2CT0_DATA (tx-ready/rx-
	# full); vectors 120/121 belong to the DP-SG blocks (120 = NPU0 think-done, 121 = TRNG0 —
	# landed 2026-07-22; each backfills as IRQB_RSVD when its block is absent), so 122/123
	# hold under the frozen-numbering rule. NUM_EN_WORDS stays 4 (124 <= 128). NO new pins:
	# I2CT0 SHARES the I2C0 SDA0/SCL0 pad planes via an open-drain wired-AND DIR merge (a
	# separate shared-RTL edit). mclk-domain, so the SYS_CLK_CR=0 footgun does NOT bind I2CT0
	# (unlike the smclk I2C0). Default false
	'peripherals.i2ctarget': ('bool: I2CT0 hardware I2C target at 0x6A00, sharing the I2C0 pads',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# True instantiates the TRNG0 ring-oscillator entropy source + harvest engine at 0x6900:
	# page-2 (MUTEX page) sub-slot 9. Free-running RO ensemble (NRO rings, {4,8} via
	# peripherals.trngRings) 2-FF synchronized into MCLK, decimated/packed into 32-bit words
	# with a read-CONSUMES data register (exactly-once consume + DRDY same-cycle blind-window
	# fix), and an SP 800-90B-lite repetition-count health test whose alarm auto-halts
	# harvesting — all in the free-running MCLK domain (D4-clean, plain raw-strobe active-low
	# shim, neither combinationalRead nor CAPTURE_CLOCK). ONE combined IRQ (data-ready |
	# health-alarm) delivered per the GLOBAL VECTOR RULE (A5): vector 121 = TRNG0; vector 120
	# (npu-thinkdone) is gated by the EXISTING peripherals.npu knob. NUM_EN_WORDS stays 4
	# (ceil(122/32) = 4, 122 <= 128 when TRNG is the highest enabled tail block). Zero pins —
	# the RO ensemble is internal combinational fabric behind a SIM/REAL architecture split
	# (TrngRoEnsemble_sim.vhd behavioral-only, TrngRoEnsemble.vhd genus/gate-only; the two
	# must never co-list). ENTROPY CAVEAT (bring-up-grade, not certified — see the TRM
	# chapter): firmware MUST DRBG the raw words and honor ALMF. Default false — the default
	# emission (no page-2 sub-slot 9, no MmrAddrTRNG0, no vector 121) is byte-identical
	'peripherals.trng':      ('bool: TRNG0 ring-oscillator entropy source at 0x6900 (firmware must DRBG it)',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): int —
	# TRNG0 ring-oscillator ensemble size, {4, 8} ONLY (the NRO generic; the register map is
	# NRO-invariant — ROSEL/RCTC/RUNLEN semantics are unchanged by the knob). Consulted only
	# when peripherals.trng is true. Default 8
	'peripherals.trngRings': ('int, 4 or 8: TRNG0 ring count when peripherals.trng is true (default 8)',
	                         lambda v: _isInt(v) and v in (4, 8)),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): bool —
	# True instantiates the EVFAB0 event/trigger fabric (PPI-style crossbar) at 0x6B00: page-2
	# (MUTEX page) sub-slot 11. 8 channels, each a {EVSEL, TASKSEL} pair, route one of 16
	# hardware EVENTS to one of 10 hardware TASKS with a registered one-MCLK pulse and 1 MCLK
	# of in-fabric latency, so peripheral-to-peripheral chains run with every hart asleep.
	# Producers are pre-mask SET-condition taps on
	# RTC0/PWM0/TIMER0/TIMER1/UART0/NFC0/DMA0/TRNG0/I2CT0 plus a GPIO0 masked-edge path (the
	# fabric owns all CDC: per-input pulse/toggle/level modes via the EV_MODE_TGL/EV_MODE_LVL
	# generic masks); consumers are DMA0 channel GO, TIMER0 START/STOP, PWM0 fault trip,
	# PWRCTRL tile wake, NPU0 THINK and GPIO0 OUT-SET/OUT-CLR (the PxTASK pin-select byte).
	# Every producer/consumer whose block is absent from the configuration is TIED OFF ("0")
	# rather than left open (design-doc D23) — the knob composes with every other peripheral
	# knob. VECTORLESS v1: no IRQ vector is spent (irq_evfab is a constant "0", the IE slot is
	# reserved), so NUM_IRQ_SRCS is untouched and the frozen vector numbering is undisturbed.
	# Zero pins. Free-running MCLK in the always-on shared domain (WFI keeps it alive, DP-S3
	# field-power only slows it, PWRCTRL never gates it). Default false — the default emission
	# (no page-2 sub-slot 11, no EVF* register block, no tap port maps) is byte-identical
	'peripherals.eventFabric': ('bool: EVFAB0 event/trigger crossbar at 0x6B00 (8 channels, no IRQ vector)',
	                         _isBool),
	# Long form, preserved from the pre-2026-08-15 schema (the TRM chapters and this file's
	# own notes are where this detail belongs; the string below is the table cell): string —
	# package model name defined in generate.py (_PACKAGE_MODELS: "myshkin-qfn44" QFN-44,
	# "castalia-quad-qfn64" QFN-64 quad pinout, "castalia-lqfp100" LQFP-100 single-MCU large
	# package [Stage G2, 2026-07-22: all 48 GPIO bonded] — new pinouts are added as Python
	# models, never as free-form config pin lists)
	'package.model':        ('string: package pinout model, one of the pinout models defined in the generator (QFN-44, QFN-64 quad, or LQFP-100)',
	                         lambda v: isinstance(v, str) and v in _PACKAGE_MODELS),
	'package.preliminary':  ('bool: prints the Preliminary note in the TRM package section',
	                         _isBool),
}

# ---------------------------------------------------------------------------
# _CONFIG_META (S2, 2026-07-16): declarative, MACHINE-READABLE metadata for the
# SAME schema keys — a parallel source of truth to the opaque validator lambdas
# above, consumed by the `make web` export (out/web/chip_data.js) so the
# configurator/register-browser can read ranges/enums/defaults instead of
# re-hardcoding them. The lambdas stay authoritative for VALIDATION; these
# fields describe the same constraints declaratively. `_checkConfigMeta()` below
# proves the two never disagree (default passes the lambda, range/enum
# boundaries agree), so a future knob edit that touches only one side is caught.
#   type    : 'bool' | 'int' | 'enum' | 'string'
#   default : the Castalia default (== the _cfg(...) fallbacks further down)
#   min/max : inclusive integer bounds ('int' only; max omitted = unbounded)
#   step    : required integer multiple ('int' only, when the lambda demands one)
#   enum    : allowed values ('enum' only)
# ---------------------------------------------------------------------------
_CONFIG_META = {
	'chipName':             {'type': 'string', 'default': 'Castalia'},
	'numHarts':             {'type': 'int', 'default': 5, 'min': 1, 'max': 32},
	# CPR3/R1: false = no orchestrator (the historical 4-hart shape). true (the DEFAULT since
	# CPR8/R7) = hart 0 is the always-on soft orchestrator and harts 1..N-1 are
	# the channel tiles. THE TWO-PLACES RULE: this default and the literal at
	# the knob's _cfg site below must agree (check_config_defaults.py enforces).
	'orchestrator':         {'type': 'bool', 'default': True},
	'numMutexes':           {'type': 'int', 'default': 16, 'min': 1, 'max': 1024},
	'registerFileDualPort': {'type': 'bool', 'default': True},
	# Fetch-ahead. SHIPPED ON: the owner directed Castalia to carry it, and the
	# cost is one flip-flop against a measured CPI 1.523 -> 1.260. THE TWO-PLACES
	# RULE, as on orchestrator above: this literal is the SCHEMA default and the
	# OPERATIVE one is the _cfg() fallback at _core below; check_config_defaults.py
	# is what keeps the two in step. There is a THIRD and a FOURTH place that
	# behave like defaults and answer to a different rule -- the vesta entity
	# generic (false, so a core instantiated with no named association is inert)
	# and the hart_tile/orch_tile wrapper generics (true, tracking the shipped
	# value so a bare `elaborate` hardens the macro the assembly wires). Those
	# are policed by tools/python/check_entity_defaults.py.
	'core.fetchAhead':      {'type': 'bool', 'default': True},
	'isa.mul':              {'type': 'bool', 'default': True},
	'isa.fastMul':          {'type': 'bool', 'default': True},
	'isa.div':              {'type': 'bool', 'default': True},
	'isa.atomics':          {'type': 'bool', 'default': True},
	'isa.compressed':       {'type': 'bool', 'default': True},
	'isa.bitmanip':         {'type': 'bool', 'default': True},
	# NOTE, as everywhere: this is the SCHEMA default; the OPERATIVE one is the
	# _cfg() fallback in _isa below, and check_config_defaults.py gates the pair.
	'isa.minimalTiles':     {'type': 'bool', 'default': True},
	'isa.counters':         {'type': 'bool', 'default': False},
	'isa.counters64':       {'type': 'bool', 'default': False},
	# X-series ISA extensions (X1-X4, all implemented; default false)
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
	# P-series privileged architecture. trapCsr DEFAULTS TRUE since K7/R-DK3
	# (2026-08-04, USER decision on k6_trap_default_pack.md): both Castalia and
	# Argus ship the standard M-mode trap architecture. Boot behaviour is
	# bit-identical -- mtrapctl.LEGACY resets 1 -- so standard delivery is a
	# per-hart firmware opt-in, never a boot-time change. umode/pmp stay false.
	# NOTE: this literal is the SCHEMA default (configurator + TRM + validation);
	# the OPERATIVE default is the _cfg() fallback in _priv below. They are two
	# separate literals and nothing checks they agree -- change both together.
	'priv.trapCsr':         {'type': 'bool', 'default': True},
	'priv.umode':           {'type': 'bool', 'default': False},
	'priv.pmp':             {'type': 'bool', 'default': False},
	'priv.pmpEntries':      {'type': 'int', 'default': 16, 'min': 8, 'max': 16, 'step': 8},
	# D-series core-side debug (D1, 2026-08-05). DEFAULT FLIPPED TO TRUE
	# 2026-08-16 (USER directive: "I want all of these features including
	# debug"): the shipped Castalia now carries the Debug Module dm0 AND the
	# JTAG DTM dtm0, and the default package moved to castalia-lqfp100 in the
	# same change because it is the ONLY model that bonds the five TAP balls
	# (47=TCK/48=TMS/49=TDI/50=TDO/51=TRSTn) -- castalia-quad-qfn64 has all 64
	# balls committed, so an enabled TAP there is on-die but unreachable, which
	# is what _checkDebugTransportBonded below now refuses to ship silently.
	# The D-series inertness claim (a knob-OFF build is bit-identical to a
	# pre-D1 chip) is NOT retired, but no shipped configuration exercises the
	# knob-OFF arm any more: prove it by setting the knob in a scratch config.
	# NOTE, as above: this literal is the SCHEMA default; the OPERATIVE one is
	# the _cfg() fallback in _debug below, and check_config_defaults.py is what
	# keeps the two in step.
	'debug.enable':         {'type': 'bool', 'default': True},
	# DEFAULT HALVED 16384 -> 8192 on 2026-08-23, and this one is a MACRO change,
	# not just a map change. The boot image became rv32ic and measures 7,376
	# bytes, 816 under 8,192, so the 16 KiB plate was more than half empty. The
	# 2048x32 ROM rom2k_hvt_pg was compiled to replace it and is 156.525 x 181.41
	# against rom_hvt_pg's 156.525 x 325.055 -- SAME WIDTH, 143.645 um shorter,
	# 22,484 um2 (44.19%) off the MCU floor, and slightly faster at every corner.
	# MCU.template.vhd instantiates rom2k_hvt_pg and mcu_vhd.py's
	# ROM_MACRO_ADDR_BITS is 11, so this literal and those two move TOGETHER: the
	# concurrent assert at rom0 refuses to elaborate any other combination.
	# The schema max stays 0x4000. It is the address-space ceiling the memory map
	# reserves for the ROM page, not a claim that a 16 KiB macro is instantiated;
	# asking for one now fails elaboration rather than silently shipping a map the
	# array does not honour.
	'memory.romSize':            {'type': 'int', 'default': 8192, 'min': 0x400, 'max': 0x4000, 'step': 0x400},
	# DEFAULT HALVED 16384 -> 8192 on 2026-08-16 (USER directive: use the 8 KiB
	# SRAM for each core's private TCM, "make each tile as small as possible").
	# The 8 KiB macro sram1p8k_hvt_pg is 319.65 x 208.675 against the 16 KiB
	# sram1p16k_hvt_pg's 319.65 x 383.085 -- SAME WIDTH, 174.41 um shorter, which
	# is why it drops into the tile's bottom-left TCM slot without re-plumbing the
	# U-notch floorplan's X axis. NOTE what this does NOT change: the TCM APERTURE
	# STRIDE stays 0x4000 (tcmWindows below). Apertures are address space, not
	# silicon -- packing them to 0x2000 would buy no area and would force the
	# aperture sub-decode off its 16 KiB s_addr(15:12) granularity, so the upper
	# half of each aperture simply reads unmapped. The OPERATIVE default is the
	# _cfg() fallback at _tcmSize; check_config_defaults.py keeps the two in step.
	'memory.tcmSizePerHart':     {'type': 'int', 'default': 8192, 'min': 0x400, 'max': 0x4000, 'step': 0x400},
	'memory.sharedBulkRamSize':  {'type': 'int', 'default': 0x10000, 'min': 0x4000, 'step': 0x4000},
	'memory.npuStagingRamSize':  {'type': 'int', 'default': 0x4000, 'min': 0x400, 'max': 0x4000, 'step': 0x400},
	'peripherals.npu':      {'type': 'bool', 'default': True},
	'peripherals.i2c1':     {'type': 'bool', 'default': True},
	'peripherals.uart1':    {'type': 'bool', 'default': True},
	'peripherals.spi1':     {'type': 'bool', 'default': True},
	'peripherals.timer1':   {'type': 'bool', 'default': True},
	'peripherals.cqAfeStubs': {'type': 'bool', 'default': True},
	'peripherals.qspi':     {'type': 'bool', 'default': False},
	'peripherals.i3c':      {'type': 'bool', 'default': False},
	'peripherals.nfc':      {'type': 'bool', 'default': True},
	'peripherals.rtc':      {'type': 'bool', 'default': False},
	'peripherals.pwm':      {'type': 'bool', 'default': False},
	'peripherals.onewire':  {'type': 'bool', 'default': False},
	'peripherals.fieldPower': {'type': 'bool', 'default': True},
	'peripherals.dma':      {'type': 'bool', 'default': False},
	'peripherals.dmaChannels': {'type': 'int', 'default': 4, 'min': 2, 'max': 4, 'step': 2},
	'peripherals.i2ctarget': {'type': 'bool', 'default': False},
	'peripherals.trng':      {'type': 'bool', 'default': False},
	'peripherals.trngRings': {'type': 'int', 'default': 8, 'min': 4, 'max': 8, 'step': 4},
	'peripherals.eventFabric': {'type': 'bool', 'default': False},
	# DEFAULT MOVED qfn64 -> lqfp100 2026-08-16, as the pad-side half of the
	# debug.enable flip: castalia-lqfp100 is the only model that bonds the TAP
	# (47-51, carved from NC balls at D3), and it is already the tape-out
	# product's package (castalia.json). See _checkDebugTransportBonded.
	'package.model':        {'type': 'enum', 'default': 'castalia-lqfp100', 'enum': list(_PACKAGE_MODELS)},
	'package.preliminary':  {'type': 'bool', 'default': True},
}

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

# An overlay's knobs join the schema HERE, before the consistency gate, so they
# are held to the same standard as the tree's own: a validator lambda, matching
# metadata, and a default that passes its own validator.
overlay.call('configSchema', schema=_CONFIG_SCHEMA, meta=_CONFIG_META)

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

# Hart count, hoisted so the per-hart register loops below (CLINT, IRQROUTER)
# and the ChipGenerator call share ONE value (A1 N-hart generalization).
numHarts = _cfg('numHarts', 5)

# CPR3/R1 (Castalia-Penta REWORK): the orchestrator PRESENCE boolean. False =
# the historical shape (four identical hart_tile corners, hart 0 the management
# hart). True = HART 0 is the always-on soft orchestrator, emitted as
# `entity work.orch_tile`, and harts 1..numHarts-1 are the channel tiles.
#
# WHY THIS REPLACED `managementHart` OUTRIGHT (CPR1 R1): the old knob was an
# INDEX whose OFF sentinel was 0, so "the orchestrator is hart 0" — the shape
# the user asked for — is literally inexpressible in it, at five independent
# sites. The management hart is now ALWAYS hart 0 in both shapes, which is why
# `afe_stub`'s MGMT_HART generic is never overridden any more (its entity
# default 0 is correct everywhere; check_entity_defaults.py grades exactly that).
orchestrator = _cfg('orchestrator', True)
if orchestrator and numHarts < 2:
	raise Exception('orchestrator requires numHarts >= 2 (hart 0 is the orchestrator, '
		+ 'harts 1..numHarts-1 are the tiles — a one-hart orchestrator has nothing to orchestrate)')

# Mutex count (A2/Argus: 32 for the 18-hart Argus chip, 16 = the Castalia
# default). Word-mapped at 0x6000 + 4*i; the page has room for far more, the
# RTL addr port width is clog2(numMutexes) (mutex_bank NMUTEX generic).
numMutexes = _cfg('numMutexes', 16)

# Watchdog passwords — SINGLE SOURCE for the TRM must equal the RTL constants in
# hdl/common/constants.vhd (WDT_UNLCK_PASSWD / WDT_CLR_PASSWD). These feed BOTH
# the SYSTEM register descriptions (below) and the \WdtUnlockPassword /
# \WdtClearPassword TRM defines (LatexUserGuide, via m.Wdt*Password).
wdtUnlockPassword = 0x5F3759DF	# hdl/common/constants.vhd: WDT_UNLCK_PASSWD x"5f3759df"
wdtClearPassword  = 0xA0C8A620	# hdl/common/constants.vhd: WDT_CLR_PASSWD   x"A0C8A620"
_wdtUnlockHex = '0x%08X' % wdtUnlockPassword
_wdtClearHex  = '0x%08X' % wdtClearPassword

# NPU presence (A2/Argus: the A0 decision DROPS the NPU — window slot 10
# @0x4A00 becomes a reserved gap like slots 11/12's analog blocks, and the
# 0xC000 staging-RAM window reads zero through the arbiter). True = the
# Castalia default.
npuPresent = _cfg('peripherals.npu', True)

# I2C1 presence (G1a, 2026-07-11): the first config-droppable peripheral
# INSTANCE (the NPU pattern extended to a second-instance peripheral). False:
# window slot 15 becomes a dead gap (reads zero via the mux fall-through), its
# 13 IRQ vectors 70-82 become IRQB_RSVD* (numbering FROZEN — the IVT slots and
# every other vector number stay put; the RTL ties them low), the SDA1/SCL1
# pad planes degrade to hi-Z (P4.2/4.3 revert to plain GPIO26/27, the P3.2/3
# AF1 relocation plane goes unassigned). True = the Castalia default.
i2c1Present = _cfg('peripherals.i2c1', True)

# UART1/SPI1/TIMER1 presence (G1b, 2026-07-11): the G1a machinery fanned out
# to the remaining second-instance peripherals. Each False empties its legacy
# window slot (5/3/7 — dead gap, reads zero), reserves its frozen IRQ vectors
# (52-54 / 11-12 / 22-27 -> IRQB_RSVD*), reverts its primary pads to plain
# GPIO and hi-Zs its rows in the AF relocation + output-spread planes (the
# spread map below is filtered before it is applied). True = the Castalia
# defaults.
uart1Present = _cfg('peripherals.uart1', True)
spi1Present = _cfg('peripherals.spi1', True)
timer1Present = _cfg('peripherals.timer1', True)

# digperiphs #1 (QSPI, 2026-07-18): page-0 slot 12 (0x4C00) real estate. The
# Castalia-Quad respin's four AFE register stubs + the shared EIS engine stub
# (afe_stub.vhd instances, wired in the generated MCU.vhd) occupy slot 12 and
# the IRQ-router page top quarter (0x7C00) by DEFAULT — the committed golden
# master and the shafe mp-suite test depend on them, so cqAfeStubs defaults
# TRUE. The QSPI0 controller is the ALTERNATE occupant of slot 12 (default
# FALSE): enabling it claims 0x4C00 and drives IRQ vectors 55 (transfer
# complete) / 56 (RX full). The two are mutually exclusive — both decode slot
# 12. The EIS stub is tied to the SAME cqAfeStubs knob: in the RTL it shares
# the afe_eis_irq(4:0) vector and the AFE sub-decode/read-mux emitters with the
# four AFE sites (fully entangled), so it lives and dies with them.
cqAfeStubsPresent = _cfg('peripherals.cqAfeStubs', True)
qspiPresent = _cfg('peripherals.qspi', False)
if cqAfeStubsPresent and qspiPresent:
	raise Exception('Chip-config conflict: peripherals.cqAfeStubs and peripherals.qspi '
		'both claim page-0 slot 12 (0x4C00) — set cqAfeStubs=false to enable qspi.')

# The overlay derives its own knobs and raises its own conflicts here, with the
# chip shape already resolved. `_overlayVals` is the ONE channel from this point
# to every later stage: whatever the overlay puts in it, it reads back. The
# public tree neither writes nor reads its contents.
_overlayVals = {'numHarts': numHarts, 'orchestrator': orchestrator,
	'cqAfeStubs': cqAfeStubsPresent}
overlay.call('configResolve', cfg=_cfg, vals=_overlayVals)

# digperiphs #2 (I3C, 2026-07-18): the I3C0 controller (MVP+DAA+IBI) claims
# page-2 (the MUTEX page, 0x6000-0x6FFF) SUB-SLOT 1 @0x6100. This carves the
# mutex bank down to sub-slot 0 (0x6000-0x60FF, 256 B): by default the mutex
# decode ALIASES across the whole page and an aliased read fires the atomic
# CLAIM side effect, so tightening it is a correctness improvement that ships
# ONLY when I3C is enabled (the default keeps the historic aliasing decode,
# byte-identical). Enabling I3C also GROWS the IRQ SOURCE list from 85 to 94:
# the meip external-interrupt slot stays FROZEN at IVT slot 85 (m.MeipVector),
# a reserved never-pending placeholder sits at source index 85, and the eight
# I3C sources (tc/rxf/txe/nack/eod/arb/daa/ibi) sit ABOVE it at 86-93, reached
# through the existing meip dispatcher. Default FALSE — the default emission
# (mutex aliasing, 85-entry vector list, no page-2 sub-decode) is unchanged.
i3cPresent = _cfg('peripherals.i3c', False)

# digperiphs #3 (NFC, 2026-07-18): the NFC0 ISO 14443A tag / card-emulation
# engine claims page-2 (the MUTEX page) SUB-SLOT 2 @0x6200, joining I3C's gated
# carve. It tightens the same mutex decode to sub-slot 0 (the tightening ships
# whenever I3C *or* NFC is present) and takes sub-slot 2. Enabling NFC GROWS the
# IRQ SOURCE list to 98: meip stays FROZEN at slot 85, sources 86-93 are I3C's
# (or reserved gaps when I3C is off), and NFC's four sources sit at 94-97 in the
# fixed order field/rxf/txdone/crcerr (NFC.vhd's irq_* port order). Because 98
# sources cross a 32-bit boundary, NFC is the first config to need a 4th
# glitch-filter instance (the irq-gf region is now geometry-driven). The digital
# AFE / RF interface is off-die (placeholder-tied, no pads). Default FALSE — the
# default emission (85-entry vector list, 3 glitch filters) is byte-identical.
# DEFAULT FLIPPED TO TRUE 2026-08-16 (USER directive, same change as debug.enable
# above). Measured at the flip, and it is the reason this was cheap: enabling NFC
# does NOT move vectorsCount (121 both ways) -- 94-97 are already RESERVED GAPS in
# the vector space, not new entries appended above it, so none of the
# vectorsCount-drift class applies. peripheralCount goes 20 -> 21. The
# byte-identical default-emission claim in the note above is not carried by any
# shipped configuration: the default has NFC on.
nfcPresent = _cfg('peripherals.nfc', True)

# digperiphs #4 (RTC, 2026-07-20): the RTC0 real-time clock (32.768 kHz always-on
# wall clock + one-shot alarm + recurring periodic tick, ONE combined IRQ) claims
# page-2 (the MUTEX page) SUB-SLOT 5 @0x6500, joining the I3C/NFC/GPIO4/GPIO5 carve
# (the mutex-bank decode is already tightened to sub-slot 0 whenever any page-2 sub-
# slot device is present). RTC0 is ZERO-PIN: it clocks off the UNGATED lfxt_in pad
# crystal (D1), with the LFXT->bus CDC synchronizers, the sticky W1C flags and the
# IRQ combiner on the free-running MCLK (orchestrator adjudication A2 — wired to
# mclk, not smclk). Unlike I3C/NFC it needs NO falling_edge(EnMemPeriph) pre-latch
# (D4, post-X-collapse bus rules): it is the FIRST library block that is neither
# combinationalRead NOR in mcu_vhd.py's CAPTURE_CLOCK set — a plain raw-strobe shim
# (the GPIO4/5 native-slave idiom). Enabling RTC GROWS the IRQ SOURCE list from 114
# to 115: vector 114 = RTC0 (single combined alarm/tick source), ABOVE GPIO5's
# 106-113 (the I3C/NFC conditional-growth pattern, NOT the GPIO4/5 unconditional
# one). NUM_EN_WORDS stays 4 (ceil(115/32) = 4, 115 <= 128). Default FALSE — the
# default emission (114-source vector list, no page-2 sub-slot 5, no MmrAddrRTC0)
# is byte-identical.
rtcPresent = _cfg('peripherals.rtc', False)

# digperiphs #5 (PWM, 2026-07-20): the PWM0 buffered PWM generator (2 channels,
# glitch-free double-buffered update, software/mask-only fault, period-event tick)
# claims page-2 (the MUTEX page) SUB-SLOT 6 @0x6600, joining the I3C/NFC/GPIO4/GPIO5/
# RTC0 carve. PWM0 has ZERO INPUT pins: its two outputs pwm_out(0)/(1) REPLACE two
# redundant timer-compare spread copies (A7 — the pin-mux-v2 replaced-spread-slot
# precedent; NOT an AF0 co-tenant and NOT a new spread-pool member). The whole engine
# (prescaler / 16-bit counter / comparators / shadow-commit / sticky FLTF/PEVF flags /
# IRQ combiner) rides the free-running MCLK — no LFXT, no generated/gated clocks (D1/
# D6), and the register file rides ClkMem (= mclk at integration). Like RTC0 it needs
# NO falling_edge(EnMemPeriph) pre-latch (D4): a plain raw-strobe shim, neither
# combinationalRead NOR in mcu_vhd.py's CAPTURE_CLOCK set. Enabling PWM extends the
# IRQ source list per the GLOBAL VECTOR RULE (A5, see the library-tail machinery
# below): vectors 115 = PWM0_FAULT (lower id -> router priority), 116 = PWM0_EVT.
# NUM_EN_WORDS stays 4 (ceil(117/32) = 4, 117 <= 128). Default FALSE — the default
# emission (no page-2 sub-slot 6, no MmrAddrPWM0, the two spread slots keep their
# original T0CMP0/T0CMP1 copies) is byte-identical.
pwmPresent = _cfg('peripherals.pwm', False)

# digperiphs #5 (OneWire, 2026-07-20): the OW0 Dallas/Maxim 1-Wire master (reset+
# presence, write/read bit + byte link-layer primitives off a programmable time base;
# ROM search + CRC-8 in firmware; standard + overdrive speeds; one open-drain DQ)
# claims page-2 (the MUTEX page) SUB-SLOT 7 @0x6700, joining the I3C/NFC/GPIO4/GPIO5/
# RTC0/PWM0 carve. OW0 has ONE pad: DQ on P4.7 / GPIO31 (DTP3), alt plane AF2,
# open-drain, rstREN=1 — the pin-mux-v2 REPLACED-SPREAD-SLOT mechanism (see the
# _GPIO_AF_SPREAD gate below), NOT an AF1 plane: the slot's redundant T0CMP1 spread
# copy steps aside for it. The whole engine (OW0DIV time base / slot FSM / DQ
# 2-FF synchronizer / sticky W1C flags / BUSY-PRES / IRQ combiner) rides the free-
# running MCLK (clk => mclk, D1/D2) — no LFXT, no generated/gated clocks, and NO clock
# on the DQ pad (DQ is 2-FF synchronized, PURE DATA, D10). Like RTC0/PWM0 it needs NO
# falling_edge(EnMemPeriph) pre-latch (D4): a plain raw-strobe shim, neither
# combinationalRead NOR in mcu_vhd.py's CAPTURE_CLOCK set. Enabling OneWire extends the
# IRQ source list per the GLOBAL VECTOR RULE (A4/A5, see the library-tail machinery
# below): vector 117 = OW0 (single combined transaction-complete/error source), with
# 114/115/116 backfilling as IRQB_RSVD per their own rtc/pwm knobs. NUM_EN_WORDS stays
# 4 (ceil(118/32) = 4, 118 <= 128). Default FALSE — the default emission (no page-2
# sub-slot 7, no MmrAddrOW0, P4.7/GPIO31 AF2 keeps its T0CMP1 spread copy) is
# byte-identical.
onewirePresent = _cfg('peripherals.onewire', False)

# DP-S3 (field-powered NFC mode, 2026-07-24): PWRCTRL supervision-input wiring.
# PGOOD on P6.7/GPIO47, harvested-boot strap on P6.6/GPIO46 — plain-GPIO direct
# taps (NOT AF1 planes: they must be readable before any software runs), pull
# defaults chosen so an unfitted board reads power-good-not-asserted + NORMAL
# boot. The pwr_ctrl.vhd RTL (PWRWAKE/PWRSTS words 5/6, pgood_rstn boot gate)
# is unconditional; this knob only decides the pad-side ties in the generated
# pwr0 port map. INDEPENDENT of every other knob since the Stage H re-pin
# (2026-07-26): OW0's DQ moved off P6.6 to P4.7/GPIO31 AF2, so the old
# fieldPower/onewire hard conflict is GONE — both may be on at once (the wound
# configuration is the proof).
fieldPowerPresent = _cfg('peripherals.fieldPower', True)

# digperiphs #6 (DMA, 2026-07-21): the DMA0 configurable multi-channel single-shot
# DMA controller (peripheral-paced or software-GO mem-to-mem transfers off the shared
# arbiter, CRC16-CDMA2000 ride-along) claims page-2 (the MUTEX page) SUB-SLOT 8 @0x6800,
# joining the I3C/NFC/GPIO4/GPIO5/RTC0/PWM0/OW0 carve. ZERO pins. DMA0 is architecturally
# TWO peripherals fused: an arbiter SLAVE (register file @0x6800, D4-xcollapse-clean like
# RTC/PWM/OW — plain raw-strobe shim, neither combinationalRead NOR in CAPTURE_CLOCK) AND
# an arbiter MASTER (the transfer engine, D2/D3) — the FIRST new arbiter master since the
# four harts (M13). Enabling DMA is THE ONE place the digperiphs program touches shared
# fabric RTL: the arbiter master count goes N=4 -> N=5 (the DMA is master index numHarts,
# the LAST slice), rippling through mp_arbiter (N=>5, MW=>3), resv_unit (N=>5),
# mutex_bank/irq_router (MW=>3), the sh_master decl (2->3 bits) and the arb_* buses (a 5th
# slice + the D18 lrsc/lock ties). Enabling DMA extends the IRQ source list per the GLOBAL
# VECTOR RULE (A5, the library-tail machinery below): vectors 118 = DMA0_DONE (combined
# channels-done), 119 = DMA0_ERR, with 114/115/116/117 backfilling as IRQB_RSVD per their
# own rtc/pwm/onewire knobs. NUM_EN_WORDS stays 4 (ceil(119/32) = 4, 119 <= 128).
# dmaChannels (the NCH generic, {2,4}) is consulted only when dma is true; the register
# map is the 4-channel SUPERSET regardless (absent channels read 0, A19/D6). Default
# FALSE — the default emission (no page-2 sub-slot 8, no MmrAddrDMA, arbiter stays
# N=4/MW=2, sh_master 2 bits, no vectors 118/119) is byte-identical.
dmaPresent = _cfg('peripherals.dma', False)
dmaChannels = _cfg('peripherals.dmaChannels', 4)

# digperiphs (I2CT, 2026-07-22): the I2CT0 hardware-autonomous I2C TARGET (slave)
# claims page-2 (the MUTEX page) SUB-SLOT 10 @0x6A00, joining the
# I3C/NFC/GPIO4/GPIO5/RTC0/PWM0/OW0/DMA0 carve. 7-bit address match + mask + general
# call, byte-at-a-time RX/TX with ready/empty status, hardware clock stretching,
# START/STOP/repeated-START/NACK framing flags, and a stuck-SCL watchdog — all in the
# free-running MCLK domain (D4-xcollapse-clean like RTC/PWM/OW: a plain raw-strobe
# active-low shim, neither combinationalRead NOR in CAPTURE_CLOCK; 2-FF SDA/SCL sync,
# no pad-clocked processes). NO new pins: I2CT0 SHARES I2C0's SDA0/SCL0 pad planes via
# an open-drain wired-AND DIR merge (the one shared-RTL edit, done separately). Enabling
# I2CT0 extends the IRQ source list per the GLOBAL VECTOR RULE (A5, the library-tail
# machinery below): vectors 122 = I2CT0_AE (address/error), 123 = I2CT0_DATA (tx-ready/
# rx-full). Vectors 120/121 belong to the DP-SG blocks (npu-thinkdone / TRNG0, landed
# 2026-07-22 — gated on npuPresent/trngPresent in _LIBRARY_TAIL_SPEC), so 122/123 hold
# under the frozen-numbering rule; an absent block's row backfills as IRQB_RSVD120/121
# when I2CT0 is the highest enabled block. NUM_EN_WORDS stays 4 (124 <= 128). Default FALSE —
# the default emission (no page-2 sub-slot 10, no MmrAddrI2CT0, no vectors 122/123, merged
# planes at their golden-master text) is byte-identical.
i2ctargetPresent = _cfg('peripherals.i2ctarget', False)

# digperiphs (TRNG, 2026-07-22): the TRNG0 ring-oscillator entropy source + harvest
# engine claims page-2 (the MUTEX page) SUB-SLOT 9 @0x6900, joining the
# I3C/NFC/GPIO4/GPIO5/RTC0/PWM0/OW0/DMA0/I2CT0 carve. A free-running NRO-ring RO
# ensemble (peripherals.trngRings, {4,8}) is 2-FF synchronized into the free-running
# MCLK domain (D4-xcollapse-clean like RTC/PWM/OW/DMA/I2CT: a plain raw-strobe
# active-low shim, neither combinationalRead nor CAPTURE_CLOCK), decimated and packed
# into 32-bit words behind a read-CONSUMES data register (exactly-once consume strobe
# + a DRDY same-cycle blind-window fix — the new library mechanism this block
# introduces), with an SP 800-90B-lite repetition-count health test whose alarm
# auto-halts harvesting. ZERO pins: the RO ensemble is internal combinational fabric
# behind a SIM/REAL architecture split (TrngRoEnsemble_sim.vhd behavioral-only,
# TrngRoEnsemble.vhd genus/gate-only — the two must never co-list, D6). Enabling TRNG
# extends the IRQ source list per the GLOBAL VECTOR RULE (A5, the library-tail
# machinery below): vector 121 = TRNG0 (single combined data-ready | health-alarm
# source); vector 120 (npu-thinkdone) is gated by the EXISTING peripherals.npu knob,
# not a new one. NUM_EN_WORDS stays 4 (ceil(122/32) = 4, 122 <= 128). Default FALSE —
# the default emission (no page-2 sub-slot 9, no MmrAddrTRNG0, no vector 121) is
# byte-identical. Bring-up-grade entropy ONLY (THE ENTROPY CAVEAT, D16): no
# certification, no HW conditioner — firmware MUST DRBG the output and honor ALMF.
trngPresent = _cfg('peripherals.trng', False)
trngRings = _cfg('peripherals.trngRings', 8)

# digperiphs (EVFAB, 2026-07-24): the EVFAB0 event/trigger fabric claims page-2 (the
# MUTEX page) SUB-SLOT 11 @0x6B00, the last one taken by the digital-peripheral
# library (0x6000 mutex / 0x6100 I3C0 / 0x6200 NFC0 / 0x6300 GPIO4 / 0x6400 GPIO5 /
# 0x6500 RTC0 / 0x6600 PWM0 / 0x6700 OW0 / 0x6800 DMA0 / 0x6900 TRNG0 / 0x6A00 I2CT0).
# It is a PPI-style crossbar: 8 channels, each {EVSEL, TASKSEL}, routing one of 16
# hardware EVENTS to one of 10 hardware TASKS as a registered one-MCLK pulse (1 MCLK
# of in-fabric latency), so peripheral-to-peripheral chains keep running with every
# hart in WFI. Zero pins. Free-running MCLK in the always-on shared domain (D1/D2:
# PWRCTRL never gates it, DP-S3 field-power only slows it); D4-xcollapse-clean like
# RTC/PWM/OW/DMA/TRNG/I2CT — a plain raw-strobe active-low shim, neither
# combinationalRead nor CAPTURE_CLOCK. VECTORLESS v1 (design-doc D20 / brief §1): the
# free vector budget is 124-127 and Phase-0 rule 2 wants >= 2 free at end state, so
# irq_evfab is a constant '0', the IE register slot is reserved, and SR.FIREDIF/OVRIF
# are live RO reductions firmware polls — NUM_IRQ_SRCS and _LIBRARY_TAIL_SPEC are
# therefore UNTOUCHED by this knob (spending a vector later is purely additive).
# CROSS-KNOB DEGRADE (D23): every producer/consumer whose source block is absent is
# tied '0' at the MCU level, never left open, so the fabric composes with every other
# peripherals.* knob. Default FALSE — the default emission (no page-2 sub-slot 11, no
# EVF* register block, no tap port-map lines on the existing instances) is byte-identical.
eventFabricPresent = _cfg('peripherals.eventFabric', False)

# digperiphs A5 — GLOBAL VECTOR RULE (BINDING, applies to every library block).
# Beyond the 114 UNCONDITIONAL vectors (0-113: legacy + CLINT + meip placeholder +
# I3C/NFC RSVD-or-real + GPIO4/5), each optional library block owns a FROZEN,
# never-renumbered vector range in the "library tail" (RTC0 = 114, PWM0 = 115/116,
# onewire = 117 when it lands...). The emitted IRQ source list extends up to the LAST
# vector of the HIGHEST ENABLED tail block; every DISABLED block BELOW that high-water
# mark backfills its slots as IRQB_RSVD<n> (the I2C1-drop idiom) so a higher block
# keeps its number. Nothing is emitted above the highest enabled block (byte-identical
# default when the whole tail is off). Adding a new library block is ONE table row
# here + one row in the emission table further down (kept in lockstep by the
# _LIB_TAIL_BASE cross-check). (name, present, vectorCount) per block, in vector order.
_LIB_TAIL_BASE = 114
_LIBRARY_TAIL_SPEC = [
	('rtc', rtcPresent, 1),   # vector 114        (RTC0 combined alarm/tick)
	('pwm', pwmPresent, 2),   # vectors 115, 116  (PWM0_FAULT, PWM0_EVT)
	('onewire', onewirePresent, 1),  # vector 117  (OW0 combined TC/error)
	('dma', dmaPresent, 2),   # vectors 118, 119  (DMA0_DONE, DMA0_ERR)
	# DP-SG (2026-07-22): vector 120 = NPU think-done, gated by the EXISTING
	# peripherals.npu knob (no new schema key — npu_irq_spec.md). 121 = TRNG0
	# (digperiphs TRNG, 2026-07-22), gated by the new peripherals.trng knob.
	# See ~/work/chip_docs/castalia/digperiphs/irq_budget_phase0.md §1.
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

# Package model selection (G4): which _PACKAGE_MODELS entry builds the pad
# ring below, and whether the TRM package section carries the "Preliminary"
# banner.
#
# THE SHIPPED DEFAULT PACKAGE IS THE CASTALIA-QUAD QFN-64 (user directive,
# 2026-08-16). It was 'myshkin-qfn44' -- the inherited single-core pinout, kept
# as the default only because no Castalia package had been chosen. The QFN-64
# quad pinout (16/side, 9x9 mm, 0.5 mm pitch, four per-quadrant analog domains,
# 16 electrode pads) is that choice, so a bare `make chip` now documents the
# real package and config/cq.json is left as a named alias of the default rather
# than the only way to reach it.
#
# The default is stated TWICE (here and in _CONFIG_META) and
# check_config_defaults.py enforces that the two agree -- change both.
#
# WHAT THIS DOES NOT TOUCH: the pad ring is DOCUMENTATION + PnR pad-list data.
# MCU.vhd and MemoryMap.vhd are package-agnostic by construction (the shared
# GPIO structure is one table; only each bit's package PIN NUMBER is per-model),
# so the RTL products are byte-unaffected by this flip -- proven by A/B md5.
# Two DOC consequences ride it, both intended: the TRM's pinout chapter becomes
# the QFN-64 one, and the CQ analog front-end chapter (AFE0-3 + EIS, gated on
# this model below) now renders in the default manual.
#
# `package.preliminary` is a SEPARATE knob and is deliberately NOT flipped with
# the model: it states whether the bond-out is confirmed, which is a different
# question from which pinout is documented. config/cq.json still carries
# `preliminary: false`, so that file is not fully redundant.
packageModel = _cfg('package.model', 'castalia-lqfp100')
packagePreliminary = _cfg('package.preliminary', True)

# Remaining scalar knobs, hoisted so the ChipGenerator(...) call and the
# resolved-config record at the bottom share ONE value per knob.
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
	# X0 scaffolded extensions (default false, plumbed to the vesta ENABLE_* generics)
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

# X0 scaffolding gate: during the X-series bring-up the ISA-extension generics
# were plumbed end-to-end AHEAD of their decode/logic; a scaffolded name set
# true would advertise hardware that does not exist — HARD-ERROR so nothing
# downstream (misa/ISA-string/tests) can lie about it. Names were removed as
# their phase (X1-X4) landed the real logic; all knobs are implemented now.
_SCAFFOLDED_ISA = ()   # X4 landed Zfinx (the last scaffolded name); this is now a
	                   # VALID EMPTY TUPLE. Keep it `()` -- never a bare string like
	                   # ('zfinx') without a trailing comma (iterated char-by-char ->
	                   # KeyError). Re-add a name here only if a future extension is
	                   # scaffolded ahead of its implementation.
for _sx in _SCAFFOLDED_ISA:
	if _isa[_sx]:
		raise Exception('isa.' + _sx + ': scaffolded (X0) but not implemented yet')

# X2 (Zabha): byte/half AMOs reuse the A-extension datapath — meaningless
# (and unimplemented) without atomics. HARD-ERROR so no config advertises
# Zabha on a chip that lacks LR/SC/AMO.
if _isa['zabha'] and not _isa['atomics']:
	raise Exception('isa.zabha requires isa.atomics (byte/half AMOs build on the A extension)')

# X2 (Zacas): amocas.{w,b,h} ride the A-extension AMO datapath — meaningless
# (and unimplemented) without atomics. HARD-ERROR so no config advertises Zacas
# on a chip that lacks LR/SC/AMO. (amocas.b/.h additionally require Zabha, but
# that is a legal Zacas-word-only config, so it is only WARNed below.)
if _isa['zacas'] and not _isa['atomics']:
	raise Exception('isa.zacas requires isa.atomics (compare-and-swap builds on the A extension)')

# X1 (Zawrs): wrs.nto/wrs.sto wait on the LR reservation set, so maindec gates
# is_wrs_instr on ENABLE_ZAWRS *and* ENABLE_ATOMICS -- without A the RTL raises
# illegal-instruction on both encodings. HARD-ERROR so no config advertises
# Zawrs on a chip that lacks LR/SC/AMO. (Added K1, 2026-08-03: the schema help
# text and the RTL both carried this dependency; the validator did not, so
# {zawrs:true, atomics:false} generated an isaString ending _zawrs -- a lie the
# Spike oracle would retire and the core would trap. K0 inventory probe 2.3 /
# oracle probe 1.3(k).)
if _isa['zawrs'] and not _isa['atomics']:
	raise Exception('isa.zawrs requires isa.atomics (wrs.nto/wrs.sto wait on the A extension reservation set)')

# X3 (Zcmp): compressed push/pop + reg-moves are C-quadrant encodings -- they
# only exist with the C extension. HARD-ERROR so no config advertises Zcmp on a
# chip without compressed decode.
if _isa['zcmp'] and not _isa['compressed']:
	raise Exception('isa.zcmp requires isa.compressed (cm.push/pop live in the C2 quadrant)')

# X3 (Zcmt): compressed table jump is a C-quadrant encoding + the jvt CSR.
if _isa['zcmt'] and not _isa['compressed']:
	raise Exception('isa.zcmt requires isa.compressed (cm.jt/cm.jalt live in the C2 quadrant)')

# P-series privileged architecture (P0 scaffolding, 2026-07-28). Hoisted like
# _isa so the ChipGenerator(...) call and the resolved-config record at the
# bottom share ONE value per knob.
_priv = {
	# K7/R-DK3 (2026-08-04): TRUE. This is the OPERATIVE default -- _cfg()
	# returns THIS value for a config with no priv key, not the SCHEMA's.
	# The schema entry at 'priv.trapCsr' must carry the same value; nothing
	# enforces that, so the two are marked at both sites.
	'trapCsr':    _cfg('priv.trapCsr', True),
	'umode':      _cfg('priv.umode', False),
	'pmp':        _cfg('priv.pmp', False),
	'pmpEntries': _cfg('priv.pmpEntries', 16),
}

# P0 scaffolding gate (the X0 _SCAFFOLDED_ISA idiom, verbatim): the
# privileged-architecture generics are plumbed end-to-end AHEAD of their
# CSR/decode/PMP logic. A scaffolded name set true would advertise hardware that
# does not exist — HARD-ERROR so nothing downstream (MemoryMap constants, the
# core_features.h defines the priv* tests dispatch on, the TRM) can lie about
# it. Remove a name from this tuple when its phase lands the real logic:
# P1 -> 'trapCsr' (GRADUATED 2026-07-28), P2 -> 'umode' (GRADUATED 2026-07-28),
# P3 -> 'pmp' (GRADUATED 2026-07-29). The P-series scaffold is now EMPTY — the
# tuple stays as the mechanism for any future phase, and the loop below is a
# provable no-op over it. Keep it a TUPLE — a bare ('pmp') without a trailing
# comma is a STRING and iterates char-by-char (KeyError), the trap the X0
# comment records; `()` is the correct empty form (`(,)` is a syntax error).
_SCAFFOLDED_PRIV = ()
for _sp in _SCAFFOLDED_PRIV:
	if _priv[_sp]:
		raise Exception('priv.' + _sp + ': scaffolded (P0) but not implemented yet')

# P2 (U-mode) requires P1 (trap CSRs): U-mode has nowhere to store privilege
# state (mstatus.MPP/MPIE) and a U-mode trap has nowhere to land (mepc/mcause/
# mtvec) without the standard trap architecture. Written at P0, INERT while the
# scaffold gate above fires first, ACTIVE the moment umode graduates.
if _priv['umode'] and not _priv['trapCsr']:
	raise Exception('priv.umode requires priv.trapCsr (U-mode needs mstatus/mepc/mcause/mtvec to trap into)')

# P3 (PMP) requires P2 (U-mode): PMP's protection story is M-vs-U, and a PMP
# access fault is an EXCEPTION — only the standard trap architecture can take
# one (in legacy mode it would land in the terminal TRAP_STATE). Same timing:
# written at P0, active when pmp graduates.
if _priv['pmp'] and not _priv['umode']:
	raise Exception('priv.pmp requires priv.umode (PMP protects U-mode; its access faults are standard-mode exceptions)')

# D-series core-side debug (D1, 2026-08-05). Hoisted like _isa/_priv so the
# ChipGenerator(...) call and the resolved-config record share ONE value.
_debug = {
	'enable': _cfg('debug.enable', True),
}

# D1 REQUIRES P1 (R-DD1). The coupling is not tidiness, it is decode: maindec
# gates `ebreak_op` AND the whole SYSTEM PRIV_FN3 legality arm on
# ENABLE_TRAPCSR, so on a trapCsr-OFF build `ebreak` does not decode at all and
# dcsr.ebreakm would have nothing to interpose on -- the chip would carry a
# debug interface that cannot recognise a software breakpoint (D0/P2 N8). The
# alternative (widen ebreak_op's gate) was rejected: it needs TWO sites moved in
# lockstep and leaves DRET's legality arm behind. Same shape and same placement
# as the umode/pmp ladder above; vesta.vhd carries a concurrent assert for
# anyone instantiating the core outside the generator.
# CONSEQUENCE, verified rather than assumed: a configuration that sets
# priv.trapCsr=false and names no `debug` key takes this default (false) and is
# a debug-OFF row by construction, which is what keeps the two knobs consistent.
if _debug['enable'] and not _priv['trapCsr']:
	raise Exception('debug.enable requires priv.trapCsr (ebreak and the SYSTEM PRIV decode arm do not exist without it, so a software breakpoint could never be recognised)')

# Fetch-ahead (2026-08-23). Hoisted like _isa/_priv/_debug so the
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
	# X1 extensions (2026-07-17). Simplified march order, matching web_export.py.
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
	# X3 Stage B scalar-crypto bit-manip (misa: none). Independent of Zbb —
	# Zbkb makes its Zbb-shared subset legal even when Zbb is off.
	if _isa['zbkb']:
		s += '_zbkb'
	if _isa['zbkc']:
		s += '_zbkc'
	if _isa['zbkx']:
		s += '_zbkx'
	# X3 Stage B AES+SHA (Zkn generic = Zknd+Zkne+Zknh). Composite _zkn only
	# when Zbkb+Zbkc+Zbkx+Zkn all on (X0 spec).
	if _isa['zkn']:
		s += '_zknd_zkne_zknh'
		if _isa['zbkb'] and _isa['zbkc'] and _isa['zbkx']:
			s += '_zkn'
	# X4 Zfinx: single-precision FP in the integer regfile (misa.F stays 0 — Zfinx
	# explicitly does not set F). Keep IDENTICAL to web_export.py._isaString().
	if _isa['zfinx']:
		s += '_zfinx'
	return s

# Cross-knob sanity (WARN, not raise — these are legal but suspicious)
if _isa['counters64'] and not _isa['counters']:
	print('[generate] WARNING: isa.counters64 without isa.counters — the 64-bit high halves need the base Zicntr counters')
if (not _isa['atomics']) and numHarts > 1:
	print('[generate] WARNING: isa.atomics=false on a multi-hart chip breaks the LR/SC + AMO + mutex lock infrastructure the sh tests rely on')
# ---------------------------------------------------------------------------
# THE verified-hart-count record. ONE authority, because this fact is PUBLISHED
# in two places -- the console NOTE just below, and web_export.py's
# `verifiedHarts` bundle, which is spliced into docs/chip_configurator.html and
# drives the per-hart-count badge on that page -- and keeping two copies has
# already failed twice:
#
#   * CPR8 (2026-08-15) made numHarts=5 the shipped default and updated the NOTE
#     here, but nobody updated the published bundle. For eight days the
#     configurator called 4 harts "the Castalia golden master" and badged the
#     actual tape-out chip, 5 harts, "sim-only (not elaborated)".
#   * Both copies still said 18 (Argus) "boots in simulation" a week after the
#     8 KiB TCM landed and made that false (see the Argus entry below).
#
# So the values and their descriptions live here, and web_export reads
# m.VerifiedHarts rather than transcribing them a second time.
#
# The bar for membership is a hart count this tree can still BUILD AND ELABORATE
# today, not one that passed a suite once. `argus_generation_test` proves only
# that a configuration generates and that its JSON parses, which is exactly what
# the closing sentence of the note calls unproven.
# ---------------------------------------------------------------------------
_VERIFIED_HART_COUNTS = [
	(1, 'the single-hart DRC/LVS vehicle, the named matrix row config/mcu_hart.json'),
	(4, 'the pre-CPR8 four-hart shape, orchestrator=false'),
	(5, 'Castalia-Penta golden master since CPR8, the shipped default, byte-identical drop-in RTL'),
]

# 1 EARNED ITS ROW ON 2026-08-24, against the bar in the note above and not
# against a generation run. //opensource_sim/mcu_hart:mcu_hart_elaborate binds
# the hierarchy the mcu_hart configuration emits and runs it to time zero, so
# MCU.vhd's RomAddrBits assert and hart_tile.vhd's RamSize assert both execute;
# //opensource_sim/mcu_hart:mcu_hart_boot then boots that chip out of the real
# mask-ROM image and grades the banner the ROM monitor prints on UART0. Both
# are standing bazel tests over the GENERATED RTL, not a run somebody did once.
# What getting there cost, listed because it is the answer to "why was 1 not
# already here": the MCU.vhd and riscv_tb.vhd emitters indexed harts 1..N-1
# with no N = 1 arm, pwr_ctrl.vhd asserted NHARTS >= 2, and PWRCR's gate field
# was emitted msb = 0, lsb = 1. Every one of those is fixed at the source and
# the N >= 2 emission is byte-identical.

# 18 (Argus) IS DELIBERATELY ABSENT, and this is the note that says so rather
# than leaving a silent gap where a value used to be. Argus was a verified count
# until 2026-08-16. On that day the shipped per-hart TCM halved to the 8 KiB
# sram1p8k_hvt_pg macro, and hdl/common/hart_tile.vhd now closes over it with
# `assert RamSize = 8192 ... severity failure`. RamSize is a MemoryMap package
# constant, not a generic, so no instance can override it, and every Argus row
# (config/argus.json, argus_debug.json, and the frozen
# hdl/argus/MemoryMap.vhd) asks for memory.tcmSizePerHart = 16384. An 18-hart
# build therefore still GENERATES -- the schema permits any 1 KiB multiple up to
# 0x4000 -- and then fails elaboration in all eighteen tiles. That assertion is
# working as designed; Argus is simply a configuration that no longer satisfies
# it, and Argus is no longer a development target. Re-proving it means giving it
# an 8 KiB TCM or giving hart_tile back its 16 KiB macro, re-running
# `make verify CONFIG=config/argus.json`, and only then adding the row back
# here. Do not restore it on the strength of the 2026-08-15 run.
_ARGUS_NOTE = ('18 (Argus) was a verified count until 2026-08-16 and is not one now: '
	'hdl/common/hart_tile.vhd asserts RamSize = 8192 with severity failure, and every '
	'Argus configuration asks for memory.tcmSizePerHart = 16384, so an 18-hart build '
	'still generates but no longer elaborates.')


def _verifiedHartsNote():
	'''The one sentence both publication sites use, built from the record above.'''
	parts = ['%d (%s)' % (_n, _d) for _n, _d in _VERIFIED_HART_COUNTS]
	# Guarded, because the list has shrunk before and can shrink again: a bare
	# ', '.join(parts[:-1]) + ' and ' renders "Only  and 5 (...)" at length 1.
	joined = parts[0] if len(parts) == 1 else ', '.join(parts[:-1]) + ' and ' + parts[-1]
	return ('Only ' + joined + ' are verified hart counts. Other values emit '
		'well-formed but unproven RTL. ' + _ARGUS_NOTE)


if _CHIP_CONFIG and numHarts not in [_n for _n, _d in _VERIFIED_HART_COUNTS]:
	print('[generate] NOTE: numHarts=' + str(numHarts) + ' — ' + _verifiedHartsNote())

# CLINT register-layout formula (A0/A1; must match hdl/common/clint.vhd):
# msip[h] at word h; mtime lo at word roundup16(4*numHarts)/4; mtimecmp[h]
# lo/hi at mtime word + 4 + 2h. At numHarts=4 this reproduces the original
# M5b layout EXACTLY (msip 0-3, mtime 4/5, mtimecmp 8+2h) — that identity is
# the A1 no-op gate.
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
	'''registerSlotCount value for a shared-window peripheral needing `words`
	   register words: None while it still fits the 64-word global (so the
	   Castalia description is provably untouched), the count once it does not
	   (A2 engine delta — see Peripheral.registerSlotCount).'''
	return words if words > 64 else None

# Spelled-out counts for TRM prose ("the four harts"); larger counts fall
# back to digits. Mirrors mcu_vhd.py's _HARTS_WORD.
_SPELLED = {2: 'two', 3: 'three', 4: 'four', 5: 'five', 6: 'six', 7: 'seven',
	8: 'eight', 9: 'nine', 10: 'ten', 11: 'eleven', 12: 'twelve', 16: 'sixteen',
	18: 'eighteen', 20: 'twenty', 24: 'twenty-four', 32: 'thirty-two'}
def _spelled(n):
	return _SPELLED.get(n, str(n))


''' Create Memory Map

Castalia: 4-hart multi-core VestaRV MCU (hdl/common), M11 memory map +
M12 single-ROM boot. Per-hart PRIVATE view: ONLY the 16 KiB TCM at
0x8000-0xBFFF (same local address in every tile). Everything else is the
arbitrated SHARED window, reachable by ALL harts through the mp_arbiter:
	0x00000-0x01FFF  THE shared boot ROM (one rom2k_hvt_pg, read-only; all
	                 four harts reset to PC 0x0 and dispatch on mhartid --
	                 tiles park in WFI until loaded/ignited through the
	                 bootrom loader mailboxes at 0x10400 + CLINT msip)
	0x04000-0x07FFF  shared peripheral window:
	                 page 0 (0x4000-0x4FFF) = 16 x 256 B slots at the LEGACY
	                     slot numbering -- every peripheral is back at its
	                     original Myshkin address, shared by all 4 harts
	                 page 1 (0x5000) = CLINT (msip IPIs + mtime/mtimecmp)
	                 page 2 (0x6000) = HW mutex bank
	                 page 3 (0x7000) = IRQ router
	0x0C000-0x0FFFF  NPU staging RAM (sram1p16k, NPU-port-muxed; was hart 0's
	                 private RAM1 -- same addresses, now any hart can stage)
	0x10000-0x1FFFF  shared bulk RAM, 64 KiB = 4 sram1p16k banks (test/app
	                 mailboxes at 0x10100+ keep their addresses; the M12
	                 bootrom zeroes 0x10000-0x107FF before releasing tiles
	                 and reads its loader rows SRC/LEN/ENTRY at 0x10400+16h)
Extended SPI flash (XIP) begins at 0x20000 (hart 0's adddec decode).
'''
m = ChipGenerator(
	chipRootDirectory=chipRootDirectory,
	# CHIP_NAME env var overrides the chip name everywhere it appears (TRM title page,
	# headers, prose, generated file headers): `make chip CHIP_NAME=MyChip`
	asicName=(os.environ.get('CHIP_NAME') or _cfg('chipName', None) or 'Castalia'),
	asicNameForUserGuide=(os.environ.get('CHIP_NAME') or _cfg('chipName', None) or 'Castalia'),
	mcuUserGuideLatexTemplateFileName='TRM.template.tex',
	numHarts=numHarts,	# multiprocessor hart count (default 4) — drives the TRM's \NumHarts/\NumHartsWord defines, the multi-core feature bullets, AND (since A1) the per-hart generated MCU.vhd regions + CLINT/IRQROUTER register loops below
	romStartAddress=0x0000,
	romSize=_romSize,	# 8 KiB (region 0x0-0x1FFF; the page reserves 0x0-0x3FFF, so do not exceed 0x4000)
	peripheralMemoryStartAddress=0x4000,
	peripheralMemorySlotCount=16,
	registerMemorySlotsPerPeripheralMemorySlot=64, #Bytes between each peripheral's register memory slots.
	ramStartAddress=_ramStart,
	ramMemorySlotSize=_tcmSize,	# 16 KiB private TCM/tile (region 0x8000-0xBFFF; do not exceed 0x4000)
	# Neither 0 nor 1 may be in ramMemorySlotsAvailable. This is because the ROM and the peripheral memory technically take slots 0 and 1.
	# M11: ONE private TCM per tile (slot 2 = 0x8000-0xBFFF). The old RAM1
	# slot is the shared NPU staging RAM (an ExtraMemorySection below), and
	# the bulk RAM lives at 0x10000-0x1FFFF behind the arbiter.
	ramMemorySlotsAvailable=[2],
	ramMemorySlotsUsed=[2],
	ramMemorySlotsMuxed={},
	spiFlashProgramAddress=0x8200,
	nativeSpiFlashMemoryReadAccess=True,
	nativeSpiFlashMemoryWriteAccess=False,
	stackPointerInit=_stackPointerInit,	# Stack pointer at top of the private TCM (derived from memory.tcmSizePerHart -- never a literal again)
	bootloaderUsesSpiFlashCommands=True,
	vectorsCount=_vectorsCount,	# digperiphs Mission B: GPIO4/5 UNCONDITIONAL -> fixed 114. Layout: 0-84 legacy (incl CLINT msip 83 / mtip 84), 85 meip placeholder, 86-93 I3C (RSVD when off), 94-97 NFC (RSVD when off), 98-105 GPIO4, 106-113 GPIO5. digperiphs #4/#5: the library tail (RTC 114, PWM 115/116, ...) extends the source count per the A5 GLOBAL VECTOR RULE (_libraryTailVectorsCount(); 114 when the tail is off). meip slot stays 85 via m.MeipVector below
	padOutPosLogic=True,
	padDIRPosLogic=False,
	padRENPosLogic=False,
	ENABLE_COUNTERS=_isa['counters'],
	ENABLE_COUNTERS64=_isa['counters64'],
	ENABLE_REGS_DUALPORT=_regsDualPort,	# TODO: Enable for ASIC synthesis if using a dual port register file, disable for Xilinx Spartan 6 FPGAs
	LATCHED_MEM_RDATA=False,
	TWO_STAGE_SHIFT=False,
	BARREL_SHIFTER=False,
	# Core ISA feature switches. Since the core-features work (2026-07-08) these are
	# REAL hardware knobs: they drive the vesta core's ENABLE_* generics through
	# MemoryMap.vhd's CORE_ENABLE_* constants (decode-gated to the illegal-instruction
	# trap when off, hardware pruned at elaboration, advertised in the read-only misa
	# CSR) — as well as the TRM feature list and MemoryMap.h defines, as before.
	# ENABLE_FAST_MUL/BARREL_SHIFTER/TWO_STAGE_SHIFT remain docs-only (picorv32-era;
	# vesta's multiplier is single-cycle combinational and its shifter is fixed).
	# WARNING: disabling ENABLE_ATOMICS on a multi-hart chip breaks the LR/SC +
	# AMO + (never-LR/SC-a-mutex aside) lock infrastructure the sh tests rely on.
	COMPRESSED_ISA=_isa['compressed'],
	MINIMAL_TILES=_isa['minimalTiles'],	# asymmetric ISA: harts 1..N-1 built rv32iac (TILE_ENABLE_*), hart 0 keeps the full ISA
	ENABLE_MUL=_isa['mul'],
	ENABLE_FAST_MUL=_isa['fastMul'],
	ENABLE_DIV=_isa['div'],
	ENABLE_ATOMICS=_isa['atomics'],
	ENABLE_BITMANIP=_isa['bitmanip'],
	# X0 scaffolded ISA extensions (default false; drive the vesta ENABLE_Z* generics)
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
	# Privileged-architecture generics (default false / 16 entries; drive the
	# vesta ENABLE_TRAPCSR/ENABLE_UMODE/ENABLE_PMP + PMP_ENTRIES generics through
	# MemoryMap.vhd's CORE_* constants). trapCsr (P1) and umode (P2) are REAL
	# hardware; pmp is still scaffolded — see the _SCAFFOLDED_PRIV gate above.
	ENABLE_TRAPCSR=_priv['trapCsr'],
	ENABLE_UMODE=_priv['umode'],
	ENABLE_PMP=_priv['pmp'],
	PMP_ENTRIES=_priv['pmpEntries'],
	# D1 core-side debug mode (default false; drives the vesta/hart_tile
	# ENABLE_DEBUG generic through MemoryMap.vhd's CORE_ENABLE_DEBUG).
	ENABLE_DEBUG=_debug['enable'],
	# Fetch-ahead (default false at the generator API; drives the
	# vesta/hart_tile/orch_tile ENABLE_IF_AHEAD generic through MemoryMap.vhd's
	# CORE_ENABLE_IF_AHEAD).
	ENABLE_IF_AHEAD=_core['fetchAhead'],
	ENABLE_IRQ_FAST_CONTEXT_SWITCHING=False,	# Using fast context switching saves 31.042 us @ 24 MHz (745 cycles) per interrupt, but doubles the size of the CPU register file
	ENABLE_IRQ_QREGS=False,	# Evidently the ARM register file IPs are called "two-port", but one port is read-only and the other is write-only. This means you need to write your own register file definition in HDL (remember that register x0 is always all '0's!)
	ENABLE_IRQ_TIMER=False,
	MASKED_IRQ=0x00000000,	# 32-bit IRQ mask. Any bit that is a '1' is a permanently disabled interrupt vector
	PROGADDR_IRQ=0x9000,	# TODO: Set this as the address of the master IRQ handling function (this is NOT the interrupt vector table!!! This is the function that is called whenever ANY interrupt occurs)
	lastRamMemorySlotSize=_tcmSize
)

# digperiphs #2 (M19 IVT freeze): the meip external-interrupt vector is pinned
# at IVT slot 85 for this whole chip family, INDEPENDENT of the source count.
# With I3C the source list grows to 94 (sources 86-93 sit ABOVE meip), but
# IRQB_EXT_MEIP stays 85 (hart_tile vectors meip via IRQB_EXT_MEIP, not
# NUM_IRQS-1). At the default (85 sources) this reproduces the historic
# IRQB_EXT_MEIP=85 / NUM_IRQS=86 emission byte-for-byte.
m.MeipVector = 85



# Extra memory sections: the multi-core shared regions (behind the mp_arbiter, all harts)
_npuRamLen = _cfg('memory.npuStagingRamSize', 0x4000)   # region 0xC000-0xFFFF; do not exceed 0x4000
_sharedRamLen = _cfg('memory.sharedBulkRamSize', 0x10000)  # bulk RAM bytes from 0x10000 (Castalia 64 KiB / Argus 128 KiB); extended flash begins at the next power of two above the window
if _sharedRamLen % 0x4000 != 0 or _sharedRamLen < 0x4000:
	raise Exception('memory.sharedBulkRamSize must be a positive multiple of 0x4000 (one sram1p16k bank)')

# A2 (Argus) shared-window geometry, consumed by mcu_vhd.py's generated
# regions AND recorded here as the single source of truth:
#   banks : sram1p16k bank count behind the arbiter (bank = 16 KiB)
#   shAw  : arbiter/tile word-address width — the window is
#           0x0..2^(shAw+2)-1 (bulk RAM end rounded UP to a power of two;
#           the round-up gap, e.g. Argus 0x30000-0x3FFFF, reads zero) and
#           EXTENDED FLASH decodes at exactly 2^(shAw+2) (strict sh_sel
#           complement — the M3c.3 double-claim lesson).
# Castalia (64 KiB): banks=4, shAw=15, flash at 0x20000 — the M11 values.
_sharedRamBanks = _sharedRamLen // 0x4000
shAw = _clog2(0x10000 + _sharedRamLen) - 2
# CPR3/R3 (memory map v2): shAw gains a SECOND input. An orchestrator config
# carries the five READ-ONLY TCM apertures at TCMWIN[h] = 0x20000 + h*0x4000
# (h = 0..numHarts-1), which need pages 1000..1100 of a 4-bit page field, so
# the shared window must reach 0x3FFFF whatever the bulk-RAM size says:
#     shAw = max(derived-from-sharedBulkRamSize, 16)
# Peripheral page layout is UNCHANGED by the widening (proven by the Argus
# SH_AW=16 shape: the pages widen, the addresses stay). Extended flash follows
# automatically at the strict sh_sel complement 1 << (shAw+2) = 0x40000 — never
# hand-set it, or the M3c.3 double-claim deadlock returns.
if orchestrator and shAw < 16:
	shAw = 16
flashBase = 1 << (shAw + 2)
# CPR3/R3: the aperture windows themselves, derived once here so no consumer
# re-derives the arithmetic. Empty without an orchestrator.
# THE APERTURE STRIDE IS 0x4000 AND IS *NOT* THE TCM SIZE (USER decision,
# 2026-08-16, taken when memory.tcmSizePerHart dropped to 8 KiB). They were the
# same number until then, which is why one literal used to serve both jobs.
# They are different jobs:
#   * the TCM size is SILICON -- it is the sram1p*_hvt_pg macro in the tile;
#   * the aperture stride is ADDRESS SPACE, and address space is free here.
# Packing the apertures to 0x2000 would buy no area whatsoever and would force
# the MCU aperture sub-decode off its 16 KiB s_addr(15:12) granularity (the
# codes 1000..1100), so the stride stays 0x4000 and the DECODE IS UNTOUCHED.
# CONSEQUENCE, stated plainly because the alternative is a figure that lies:
# the aperture sequencer carries only sh_addr(10:0) to the tile's tcm_ext_addr,
# because that port is the 8 KiB array's width, so AN 8 KiB TCM APPEARS TWICE IN
# ITS 16 KiB APERTURE -- the upper half is a MIRROR of the lower, not unmapped
# space and not zeros. The TRM says so.
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
# Watchdog passwords exposed to LatexUserGuide's \WdtUnlockPassword /
# \WdtClearPassword defines (single source: the wdt*Password constants above,
# which equal hdl/common/constants.vhd).
m.WdtUnlockPassword = wdtUnlockPassword
m.WdtClearPassword = wdtClearPassword

m.ExtraMemorySections = []
if npuPresent:
	m.ExtraMemorySections.append(
		('NPU_RAM (rwx)', ': ORIGIN = 0x0C000, LENGTH = ' + _hexLen(_npuRamLen), '/* NPU staging RAM (arbitrated; NPU-port-muxed during a THINK) */'))
m.ExtraMemorySections.append(
	('SHARED_RAM (rwx)', ': ORIGIN = 0x10000, LENGTH = ' + _hexLen(_sharedRamLen), '/* arbitrated shared RAM (mailbox region 0x10000-0x107FF zeroed by the bootrom; loader rows at 0x10400) */'))

# Extra hand-written TRM chapters input by the master template (copied into latex/TRM/include/)
m.ExtraLatexIntroFiles = ['MULTICORE-intro-castalia-2026-07.tex',
	# P-series privileged architecture. The chapter always renders (the legacy
	# vectored trap mechanism it documents is the shipping default); its
	# standard-mode/U-mode/PMP sections are gated by \ifprivtrapcsr /
	# \ifprivumode / \ifprivpmp, emitted from priv.* by LatexUserGuide.py.
	'PRIVARCH-intro-castalia-2026-07.tex',
	# D-series debug support. The chapter always renders, for the same reason
	# the privileged-architecture one does: its JTAG and debug-stack sections
	# are architecture background, and a debug-OFF build still has a true
	# statement to make (the 0x7Bx CSRs and DRET are illegal, there is no
	# port). Its implementation sections are gated by \ifdebugenable, emitted
	# from debug.enable by LatexUserGuide.GenerateDefinesFile().
	'DEBUG-intro-castalia-2026-08.tex']

# Shared window regions drawn in the TRM address space diagram (M11 map)
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
# CPR3/R3: the read-only TCM apertures. One 16 KiB window per hart through
# which the MANAGEMENT HART (hart 0, the orchestrator) reads that hart's
# private TCM; every other master reads zero. Reads only -- a write path into a
# live core's memory is a coherence hazard the architecture refuses (R4).
for _h, _w in enumerate(tcmWindows):
	m.SharedWindowSections.append(
		('TCM aperture ' + str(_h), _w, _w + 0x3FFF,
		 'Read-only view of hart ' + str(_h) + "'s private TCM (management hart only; a gated tile reads zero)"))



# ---------------------------------------------------------------------------
# THE REGISTER MAPS COME FROM SystemRDL (tools/rdl/README.md, reports R1-R5).
#
# Each peripheral below declares its identity -- name, prose, register/bit-field
# prefixes, intro chapter, feature summary -- and then loads its REGISTERS from
# hdl/common/regs/rdl/<block>.rdl, the description that
# //platform/common:rdl_vs_vhdl_<block>_test re-derives out of the VHDL.
# There is no second copy of a register, a width, an access code, a reset value
# or a field description in this file; a correction is made in the .rdl and
# reaches the TRM table, MemoryMap.h, the configurator and the register browser
# from there.
#
# ALL TWENTY-TWO PERIPHERALS COME FROM SystemRDL (report R7, 2026-09-10). The
# last four -- CLINT, MUTEX, IRQROUTER and PWRCTRL, whose register SET and field
# GEOMETRY are functions of numHarts / numMutexes / masterW() / vectorsCount --
# are PARAMETERISED components: register arrays, expressions in offsets and
# widths, and one description per array with the index rendered where this
# file's loops used to render it. _rdlRegisters() elaborates them with the knob
# values below, the same ones the RTL is given, so the 1-, 5- and 18-hart
# configurations come out of one file. PCT has no .rdl at all and no RTL to read
# one out of.
# ---------------------------------------------------------------------------
import rdl_model

def _rdlRegisters(peripheralTemplateName, template, sources=None, parameters=None, defines=None):
	'''Load a peripheral\'s register templates from its SystemRDL description.

	   `sources` restricts which .rdl blocks feed the template, for a peripheral
	   whose register file is assembled from more than one description. No
	   peripheral in the public tree uses it today.

	   `parameters` and `defines` are for the four PARAMETERISED blocks (CLINT,
	   MUTEX, IRQROUTER, PWRCTRL), whose register SET and field GEOMETRY are
	   functions of numHarts / numMutexes / masterW() / vectorsCount. The values
	   passed here are THIS file\'s own -- the same ones the RTL is given -- so
	   the description and the hardware are elaborated for one configuration.
	   `defines` are preprocessor guards, for the two things a SystemRDL
	   parameter cannot do: instantiate a register conditionally and choose
	   between two descriptions. Every guard is written so that no defines is the
	   default five-hart chip.'''
	if not rdl_model.rdlSourced(peripheralTemplateName):
		raise Exception('generate.py asks for %s\'s registers from SystemRDL, but '
			'config/rdl.json does not say registerSource "rdl" for it. The two must '
			'agree: either flag it, or keep the hand-written template.'
			% peripheralTemplateName)
	for _rt in rdl_model.registerTemplatesFor(peripheralTemplateName, sources=sources,
	                                          parameters=parameters, defines=defines):
		template.AddRegisterTemplate(_rt)


''' System '''
p = PeripheralTemplate(nameTemplate='SYSTEM', description='Controls the entire system, including the clocking and power state. Also has a CRC calculator using the CRC16_CDMA2000 polynomial.', bitFieldPrefix='SYS', latexIntroFileName='SYSTEM-intro-castalia-2026-07.tex', latexFeatureSummary=['A CRC calculation engine (CRC16\\_CDMA2000)', '2$\\times$ internal digitally controllable oscillators', '2$\\times$ external clock pins for clock generation and accurate timing', 'A windowed watchdog timer'])
m.AddPeripheralTemplate(p)

_rdlRegisters('SYSTEM', p)

''' SPIx '''
p = PeripheralTemplate(nameTemplate='SPIx', description='Serial Peripheral Interface. Supports both master and slave modes with configurable data length (8, 16, or 32 bits), clock polarity, clock phase, and byte ordering. SPI0 includes flash extended memory capability for direct memory-mapped access to external SPI flash. SPI1 supports both master and slave modes without flash extended memory.', registerPrefix='SPIx', bitFieldPrefix='SPI', latexIntroFileName='SPI-intro-castalia-2026-07.tex', latexFeatureSummary='{count} SPI interfaces (SPI0 provides memory-mapped access to external flash memory)')
m.AddPeripheralTemplate(p)

_rdlRegisters('SPIx', p)



''' GPIOx '''
p = PeripheralTemplate(nameTemplate='GPIOx', description='General Purpose Input Output', registerPrefix='Px', bitFieldPrefix='Px', latexIntroFileName='GPIO-intro-castalia-2026-07.tex', latexFeatureSummary='{count} 8-pin general purpose I/O (GPIO) ports with edge-triggered interrupts and per-pin multiplexed alternate functions (GPIO + up to 8 alternate functions per pin)')
m.AddPeripheralTemplate(p)

_rdlRegisters('GPIOx', p)
#p.AddRegisterTemplate(r)



''' UARTx '''
p = PeripheralTemplate(nameTemplate='UARTx', description='Full-duplex Universal Asynchronous Receiver/Transmitter with hardware parity support', registerPrefix='UARTx', bitFieldPrefix='U', latexIntroFileName='UART-intro-castalia-2026-07.tex', latexFeatureSummary='{count} UART interfaces with hardware parity support')
m.AddPeripheralTemplate(p)

_rdlRegisters('UARTx', p)



''' TIMERx '''
p = PeripheralTemplate(nameTemplate='TIMERx', description='32-bit Timer/Counter with input capture, output compare, and pulse-width modulation functionality. Features glitch-free clock source switching and configurable clock division.', registerPrefix='TIMx', bitFieldPrefix='T', latexIntroFileName='TIMER-intro-castalia-2026-07.tex', latexFeatureSummary='{count} 32-bit timers with pulse-width modulation outputs and input capture units')
m.AddPeripheralTemplate(p)

_rdlRegisters('TIMERx', p)



''' I2Cx '''
i2cDescription = 'I2C serial port interface. The master and slave I2C interfaces are split between two sets of registers.\n\n'
i2cDescription += 'To use master transmitter mode, first configure the I2C peripheral by setting I2CMEN, clearing I2CSEN, and configuring I2CMDIV with the appropriate clock division factor, noting that the I2C clock source is SMCLK. To send a start condition, set I2CMST, wait for the I2CMSTS flag to be set (if the bus is busy, the I2C peripheral will wait for it to become idle and then send a start condition), and then clear the status register. I2CMCB will now indicate that the I2C peripheral now has control of the bus as its master. Next, write to I2CxMTX the desired slave address in the most significant 7 bits followed by the desired read/write bit (0 for write/master transmitter) in the least significant bit. Then, wait for I2CMXC or I2CMARB to be set. If I2CMARB is set, then the I2C peripheral has lost the bus arbitration contest and has released control of the bus. If I2CMNR is set, then the desired slave has not acknowledged itself. Clear the status register. Next, send the slave a byte of data by writing the desired data to I2CxMTX. When the I2C peripheral is ready for another byte of data to be queued for transmission, the I2CMTXE flag will be set. Again, wait for I2CMXC or I2CMARB, then check I2CMARB and I2CMNR, and finally clear the status register. Once finished sending all of the desired bytes, either send a stop condition to release control of the bus by setting I2CMSP, or send a repeated start condition to retain control of the bus with a new transmission (and possibly a new slave and read/write mode) by setting I2CMST. Once a stop condition is sent, wait for I2CMSTS to be set, indicating that a stop condition has been sent. Clear the status register.\n\n'
i2cDescription += 'To use master receiver mode, first configure the I2C peripheral by setting I2CMEN, clearing I2CSEN, and configuring I2CMDIV with the appropriate clock division factor, noting that the I2C clock source is SMCLK. To send a start condition, set I2CMST, wait for the I2CMSTS flag to be set (if the bus is busy, the I2C peripheral will wait for it to become idle and then send a start condition), and then clear the status register. I2CMCB will now indicate that the I2C peripheral now has control of the bus as its master. Next, write to I2CxMTX the desired slave address in the most significant 7 bits followed by the desired read/write bit (1 for read/master receiver) in the least significant bit. Then, wait for I2CMXC or I2CMARB to be set. If I2CMARB is set, then the I2C peripheral has lost the bus arbitration contest and has released control of the bus. If I2CMNR is set, then the desired slave has not acknowledged itself. Clear the status register. Next, begin to receive a byte of data from the slave by setting I2CMRB. Wait for I2CMXC to be set. Clear the status register. Read I2CxMRX to get the byte of data received from the slave. To send the slave an ACK and begin to read another byte from the slave, set I2CMRB. Or, to send the slave a NACK and send a stop condition, set I2CMSP. Or, to send the slave a NACK and send a repeated start condition, set I2CMST. Wait for the appropriate flag, then clear the status register.\n\n'
i2cDescription += 'To use slave receiver mode, first configure the I2C peripheral by setting I2CSEN, clearing I2CSEN, clearing I2CSN, and configuring I2CSCS and I2CGCE to the desired values. Note that if clock stretching is enabled with I2CSCS, the I2C peripheral will seize control of the bus by driving SCL low during every ACK/NACK bit transfer (if the I2C peripheral was addressed) until I2CSC is set, which requires user intervention to prevent indefinite hold-ups of the I2C bus. But, if clock stretching is not enabled, the master will be allowed full control of the rate data is sent over the bus, which opens the possibility that the software running on this MCU does not notice that a byte has been transferred in time before the next is transferred. Note that if I2CGCE is set, the I2C peripheral will be addressed if either its address is received or if the general call is received. Wait for the I2C peripheral to be addressed when I2CSA is set. Check I2CSTM to see if the master has requested slave receiver or slave transmitter mode (0 indicates slave receiver). Clear the status register. If clock stretching is enabled, send an ACK or NACK by clearing or setting I2CSN, and then set I2CSC to release SDA and continue with the transfer. If clock stretching is not enabled, the I2C peripheral will automatically ACK or NACK depending on the value of I2CSN. Next, wait for the slave to receive a data byte from the master when I2CSXC is set. If I2CSOVF is set, then the MCU has failed to read one of the bytes sent by the master in the past. Clear the status register, and then read I2CSRX to get the data byte sent from the master. If clock stretching is enabled, send an ACK or NACK by clearing or setting I2CSN, and then set I2CSC to release SDA and continue with the transfer. If clock stretching is not enabled, the I2C peripheral will automatically ACK or NACK depending on the value of I2CSN. Next, wait for I2CSXC, I2CSPR, or I2CSTR to be set, indicating the I2C peripheral has received a new byte of data, a stop condition, or a repeated start condition. If a stop or start condition has been received, clear the status register.\n\n'
i2cDescription += 'To use slave transmitter mode, first configure the I2C peripheral by setting I2CSEN, clearing I2CSEN, clearing I2CSN, and configuring I2CSCS and I2CGCE to the desired values. Note that if clock stretching is enabled with I2CSCS, the I2C peripheral will seize control of the bus by driving SCL low during every ACK/NACK bit transfer (if the I2C peripheral was addressed) until I2CSC is set, which requires user intervention to prevent indefinite hold-ups of the I2C bus. But, if clock stretching is not enabled, the master will be allowed full control of the rate data is sent over the bus, which opens the possibility that the software running on this MCU does not notice that a byte has been transferred in time before the next is transferred. Check I2CSTM to see if the master has requested slave receiver or slave transmitter mode (1 indicates slave transmitter). Clear the status register. Queue the byte of data to transmit to the master by writing the byte to I2CSTX. If clock stretching is enabled, set I2CSC to release SDA and continue with the transfer. If clock stretching is not enabled, the I2C peripheral will automatically ACK or NACK depending on the value of I2CSN. Wait for I2CSTXE to be set, indicating that the I2C peripheral is ready to queue the next byte to send to the master. Clear the status register, and write the next byte to send to the master to I2CxSTX. If clock stretching is enabled, wait for I2CSXC to be set, clear the status register, and set I2CSC. Wait for I2CSTXE, I2CSPR, or I2CSTR to be set, then clear the status register.'
p = PeripheralTemplate(nameTemplate='I2Cx', description=i2cDescription, registerPrefix='I2Cx', bitFieldPrefix='I2C', latexIntroFileName='I2C-intro-castalia-2026-07.tex', latexFeatureSummary='{count} I$^2$C interfaces (both master and slave mode)')
m.AddPeripheralTemplate(p)

_rdlRegisters('I2Cx', p)

''' NPU '''
p = PeripheralTemplate(nameTemplate='NPU', description='Fixed-point multilayer perceptron (MLP) neural network processing unit. Computes a single fully-connected layer of a neural network: given an input vector and a synaptic weight matrix, it produces an output vector. Multiple layers can be computed sequentially by the CPU. Inputs are signed Q0.24 numbers (25 bits); synaptic weights and outputs are signed Q7.24 numbers (32 bits). An optional bias weight and a logistic sigmoid approximation activation function are available. The input vector, output vector, and weight matrix must all reside in the shared NPU staging RAM (the 16 KiB SRAM at 0xC000-0xFFFF, multiplexed between the harts and the NPU compute port). Both the registers and the data path are reachable by every hart through the shared window: any hart may stage the operands in the staging RAM. No hart is put to sleep during a computation; while THINK is set the staging RAM is owned by the NPU, so no hart may access 0xC000-0xFFFF until NPUCR bit 16 (NPUTHINK) reads 0 again.', registerPrefix='NPU', bitFieldPrefix='NPU', latexIntroFileName='NPU-intro-castalia-2026-07.tex', latexFeatureSummary='A neural processing unit (NPU) co-processor for hardware acceleration of machine learning tasks')
# A2 (Argus): the template is only registered when the NPU exists — an
# unregistered template emits no MemoryMap.h structs and no TRM chapter
# (same end state as the removed AFE/SARADC blocks).
if npuPresent:
	m.AddPeripheralTemplate(p)

_rdlRegisters('NPU', p)



''' SARADC (REMOVED) '''
# SARADC removed from Castalia (digital-only chip). Peripheral window slot 11
# (0x4B00) and IRQ vector 56 are left as RESERVED GAPS — no other peripheral
# address or vector number moves.



''' Opamp (NOT INCLUDED IN VESTARV - REMOVED) '''
# Removed DAC, Opamp, PCT peripherals - not present in vestarv chip
# AFE/SARADC removed from Castalia (digital-only) — see the reserved-gap notes above



''' Pulse Counter '''
p = PeripheralTemplate(nameTemplate='PCT', description='Pulse counter. Counts the number of digital pulses generated by a sensor, such as a Domino Neutron detector or a Geiger-Muller tube.', registerPrefix='PCT', bitFieldPrefix='PCT', latexFeatureSummary='A pulse counter for digital pulse sources (e.g. neutron detectors, Geiger--Muller tubes)')
m.AddPeripheralTemplate(p)

# PCCR
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


# PCCNT0
r = RegisterTemplate(nameTemplate='PCTCNT0', registerMemorySlot=1, size=32, description='Pulse counter 0 count register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PCTCNT0', msb=31, lsb=0, accessibility='r'))

# PCCNT1
r = RegisterTemplate(nameTemplate='PCTCNT1', registerMemorySlot=2, size=32, description='Pulse counter 1 count register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PCTCNT1', msb=31, lsb=0, accessibility='r'))

# PCCNT2
r = RegisterTemplate(nameTemplate='PCTCNT2', registerMemorySlot=3, size=32, description='Pulse counter 2 count register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PCTCNT2', msb=31, lsb=0, accessibility='r'))

# PCCNT3
r = RegisterTemplate(nameTemplate='PCTCNT3', registerMemorySlot=4, size=32, description='Pulse counter 3 count register')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PCTCNT3', msb=31, lsb=0, accessibility='r'))



''' AFE (REMOVED) '''
# AFE (DSADC + potentiostat analog front end) removed from Castalia
# (digital-only chip). Peripheral window slot 12 (0x4C00) and IRQ vector 55
# are left as RESERVED GAPS — no other peripheral address or vector moves.


''' CLINT (multi-core core-local interruptor, shared window page 1 at 0x5000) '''
# A2: the alias granularity follows the decoded word count (the RTL ADDR_W)
_clintAliasBytes = 4 << _clog2(clintSlotCount)
p = PeripheralTemplate(nameTemplate='CLINT', description='Core-local interruptor for the ' + _spelled(numHarts) + ' harts. Provides per-hart software interrupts (msip, the inter-processor interrupt mechanism) and a shared free-running 64-bit mtime counter with one 64-bit mtimecmp compare register per hart (timer interrupts). Lives in the shared window behind the multi-core arbiter, so any hart can raise or clear any hart\'s interrupts. The msip and mtip outputs are level interrupts into each hart\'s interrupt vector (vectors 83 and 84); the interrupt service routine must clear the level (write 0 to its MSIP register, or advance its MTIMECMP past mtime) before returning, or the interrupt re-triggers. The block decodes only its low address bits, so its registers alias every ' + str(_clintAliasBytes) + ' bytes throughout 0x5000-0x5FFF.', bitFieldPrefix='CLINT', latexIntroFileName='CLINT-intro-castalia-2026-07.tex')
m.AddPeripheralTemplate(p)

# The register table comes from hdl/common/regs/rdl/clint.rdl, elaborated for
# THIS configuration: MSIPh is a register array over numHarts, the MTIMECMPhL/H
# pair is a regfile array on an 8-byte stride, and the two word bases are the
# A0/A1 layout formula above -- passed in rather than recomputed, so the .rdl and
# the numbers the RTL is given cannot drift apart.
_rdlRegisters('CLINT', p, parameters={
		'NHARTS': numHarts,
		'NHARTS_WORD': _spelled(numHarts),
		'MTIME_W': clintMtimeSlot,
		'CMP_W': clintMtimecmpSlot,
	})



''' MUTEX (hardware mutex bank, shared window page 2 at 0x6000) '''
p = PeripheralTemplate(nameTemplate='MUTEX', description='Hardware mutex bank: ' + _spelled(numMutexes) + ' word-mapped advisory locks providing single-instruction cross-hart mutual exclusion. Because the multi-core arbiter serializes whole shared-window transactions, a read is atomic for free: reading a mutex word returns 0 if the mutex was free and the same transaction claims it for the reading hart (owner becomes hartid+1); reading a held mutex returns the owner\'s marker (hartid+1) and does not disturb it. Writing 0 releases a mutex (deliberately not qualified by owner, so a supervisory hart can force-release a dead hart\'s mutex); nonzero writes are ignored, so ownership cannot be forged. Never access a mutex with LR/SC or AMO instructions -- only plain loads and stores. All mutexes reset to free.', bitFieldPrefix='MTX', latexIntroFileName='MUTEX-intro-castalia-2026-07.tex')
m.AddPeripheralTemplate(p)

# Owner-marker WIDTH (2026-09-10, was a blocked correction in R3; unblocked by the
# owner and landed with the MemoryMap.vhd regeneration in the same commit).
# hdl/common/mutex_bank.vhd:70-71 reads back
#     rdata_reg              <= (others => '0');
#     rdata_reg(MW downto 0) <= owner(idx);
# so the marker is MW+1 bits at MW:0 and bits 31:MW+1 always read 0. MW is the
# mp_arbiter granted-master width, NOT a constant: mcu_vhd.py's masterW() sizes it
# from the arbiter master count (harts + the DMA + the debug module) and hands the
# same number to mp_arbiter, resv_unit, irq_router and mutex_bank, so the field
# tracks the configuration rather than the 3 that hdl/common/MCU.vhd:2981 happens
# to print today. The expression below IS masterW(); mcu_vhd.emitMutexInstance
# cross-checks the two and raises if they ever drift, so it cannot go stale
# silently.
#
# Publishing one 32-bit field described a register the chip does not have: bits
# 31:MW+1 are hardwired 0, not owner bits. Firmware is unaffected -- the release
# comparison in mutex_bank.vhd is against the full written word, so only a store of
# exactly 0 frees a mutex either way.
_mtxOwnerMsb = max(2, _clog2(numHarts + (1 if dmaPresent else 0) + (1 if _debug['enable'] else 0)))

# The register table comes from hdl/common/regs/rdl/mutex_bank.rdl: NMUTEX
# registers as one array, the owner field MW+1 bits wide, and one owner marker
# enumerated per hart (a run of value descriptions whose count is a parameter,
# because a SystemRDL enum is a static type whose member values must fit the
# field -- 32 harts need 6 bits and this field is 4).
_rdlRegisters('MUTEX', p, parameters={
		'NMUTEX': numMutexes,
		'MW': _mtxOwnerMsb,
		'NHARTS': numHarts,
	})



''' IRQROUTER (M19 PLIC-lite: per-hart routing rows + CLAIM/COMPLETE delivery, shared window page 3 at 0x7000) '''
p = PeripheralTemplate(nameTemplate='IRQROUTER', description='THE peripheral interrupt controller (M19): per-hart interrupt routing/enable rows plus a claim/complete delivery stage, programmable by any hart through the shared window. Every deglitched peripheral interrupt level terminates here; the router raises a single external-interrupt wire (meip, interrupt vector 85) to each of the ' + _spelled(numHarts) + ' harts whenever some peripheral source is pending, enabled in that hart\'s row, and not already being serviced. The servicing hart reads CLAIM to atomically discover and claim the lowest-numbered such source (claims are attributed to the reading hart by the shared-bus arbiter, so simultaneous claimers are serialized and each source is delivered exactly once), runs the source\'s handler, clears the interrupt level at the peripheral, and writes the source number back to CLAIM (complete). A source under service is masked from every hart\'s meip until completed; if its level is still high at complete (a new event), it pends again. Priority is fixed: the lowest pending vector number wins. The CLINT vectors 83 (msip) and 84 (mtip) are never delivered through meip (they reach each hart on dedicated hardwired wires), so their row bits are writable but have no effect. All rows reset to 0 (everything masked), so the router is inert until software programs it. Since M19 row 0 is live: hart 0 takes meip like every other hart (the SYSTEM peripheral\'s vectored interrupt controller is retired).', bitFieldPrefix='IRQR', latexIntroFileName='IRQROUTER-intro-castalia-2026-07.tex', latexFeatureSummary='Claim/complete peripheral interrupt delivery (PLIC-style) with any-vector-to-any-hart routing')
m.AddPeripheralTemplate(p)

# Stage E rider (2026-07-21): the routing rows and the RO status readback are
# vectorsCount-driven. Every current config has > 96 sources (114 default since
# GPIO4/5 went unconditional; up to 125 wound), so the router carries FOUR
# enable words per hart -- the fourth (HhENX, row word 4h+3, the formerly
# reserved slot) covers vectors (vectorsCount-1):96 -- and the RO status
# readback has the matching PENDX/INSVCX words at 0x781C/0x782C. The U words
# are then fully live (vectors 95:64, bits 31:0). The historic 3-word form
# (U = 84:64, bits 20:0, no X words) survives for <= 96-source configs, as the
# two guards below.
_irqrXWords = _vectorsCount > 96			# HhENX/PENDX/INSVCX exist
_irqrXMsb   = _vectorsCount - 97			# live msb in the X words (when they exist)
_irqrUMsb   = 31 if _vectorsCount >= 96 else _vectorsCount - 65
_irqrUTop   = min(_vectorsCount, 96) - 1	# top vector covered by the U words

# The register table comes from hdl/common/regs/rdl/irq_router.rdl: one
# four-word routing row per hart as a regfile array, and the U/X field widths as
# parameters. The two shapes SystemRDL cannot parameterise -- a register that
# does not exist, and a description that reads differently -- are preprocessor
# guards, and both are absent in every configuration this generator emits today.
_rdlRegisters('IRQROUTER', p, parameters={
		'NHARTS': numHarts,
		'VECTORS': _vectorsCount,
		'UMSB': _irqrUMsb,
		'UTOP': _irqrUTop,
		'XMSB': max(0, _irqrXMsb),
	}, defines=dict(
		([] if _irqrXWords else [('VESTA_IRQR_NO_XWORDS', '')])
		+ ([] if _irqrUMsb == 31 else [('VESTA_IRQR_U_NARROW', '')])))



''' PWRCTRL (M17 MTCMOS power controller, peripheral-window slot 11 at 0x4B00) '''
# CPR3/R2: every hart-count number in this block is numHarts again. The CP2
# `numHarts` special case (which withheld a row from the LAST hart) is DELETED:
# with the orchestrator renumbered to hart 0 the always-on hart is hart 0 in
# BOTH shapes, and every hart 1..numHarts-1 is a gateable channel tile. At
# numHarts=5 that means PWRCR GAINS bit 4 -- the ex-hart-0 tile is now gateable
# like its siblings -- and PWRSR gains nibble 4.
# CP2: the hart-0 clause is conditional so a NON-orchestrator build keeps the
# historical sentence VERBATIM (this text reaches MemoryMap.json, the register
# browser page and the TRM -- a reworded default would churn all three).
_pwrHart0Clause = ('Hart 0 (the always-on soft orchestrator: SPI boot, console, CLINT owner) is always-on; its bit reads 0 and ignores writes.' if orchestrator else 'Hart 0 (the management hart: SPI boot, console, CLINT owner) is always-on; its bit reads 0 and ignores writes.')
_pwrOrchNote = (' The orchestrator sits outside the MTCMOS fabric entirely (there are no header switches for the centre band), so a gate request for it would be a hardware lie, but it IS hart 0, so that is the same reserved bit 0 every configuration has always had, and a blanket PWRCR write gates every channel tile and leaves the orchestrator running.' if orchestrator else '')
p = PeripheralTemplate(nameTemplate='PWRCTRL', description='Power controller for the switchable hart-tile power domains (M17 MTCMOS cold-gating). Each tile hart (1-' + str(numHarts - 1) + ') sits in its own header-switched power domain; setting that hart\'s gate bit walks a hardware sequencer through the only legal order: isolation clamps on, tile reset asserted, header switches opened (rail off). Clearing the bit reverses it: switches closed, a rail-settle delay, clamps released, reset released, at which point the tile COLD-BOOTS through the shared boot ROM (all state was lost), parks in WFI, and can be relaunched through the boot-ROM loader rows and a CLINT msip exactly as at chip power-on. ' + _pwrHart0Clause + _pwrOrchNote + ' Gate only a parked or otherwise quiesced tile: the hardware cannot deadlock (a clamped request looks released to the arbiter), but any in-flight work on the tile is destroyed; that is what cold-gating means.', bitFieldPrefix='PWR', latexIntroFileName='PWRCTRL-intro-castalia-2026-07.tex', latexFeatureSummary='Per-tile MTCMOS power gating with hardware gate/wake sequencing (cold-boot wake)')
m.AddPeripheralTemplate(p)

# The register table comes from hdl/common/regs/rdl/pwr_ctrl.rdl, elaborated
# for THIS configuration. Only NHARTS moves: PWRCR.PWRGATE and TASKWKM.PWRTASKWKM
# span harts numHarts-1 downto 1 (a range that is EMPTY at numHarts = 1, where
# the .rdl's vesta_live removes the field and leaves its bits reserved), and
# PWRSR is ceil(numHarts/8) consecutive words of one nibble per hart. The two
# guards below are the word count, which SystemRDL cannot express as a parameter
# because an array dimension "must be greater than zero" and because the
# single-word register is named PWRSR while the multi-word ones are PWRSR0/1/2.
_pwrsrWords = (numHarts + 7) // 8
_pwrDefines = {}
if _pwrsrWords > 1:
	_pwrDefines['VESTA_PWR_MULTIWORD'] = ''
if _pwrsrWords > 2:
	_pwrDefines['VESTA_PWR_MIDWORDS'] = ''
_rdlRegisters('PWRCTRL', p, parameters={'NHARTS': numHarts}, defines=_pwrDefines)



''' Check the peripheral templates for errors '''
# digperiphs #1 (2026-07-18): QSPI0 register template. Added unconditionally
# (before CheckPeripheralTemplates) so the template exists whenever qspiPresent
# CreatePeripheral()s it at slot 12; with qspi off it is simply never instanced.
if qspiPresent:
	qspi = PeripheralTemplate(nameTemplate='QSPIx', description='Quad Serial Peripheral Interface flash controller. Issues single-/dual-/quad-lane command, address, dummy, and data phases to an external SPI-family memory over a 6-wire bus (SCK, active-low CS, and four bidirectional IO lines). Each phase has an independently configurable lane width, so the same engine drives legacy 1-1-1 flash, dual-output (1-1-2), and quad-output/quad-I/O (1-1-4 / 1-4-4) devices. A transaction is described by the control, command, and address registers and launched by a byte-lane-0 write to QSPIxCMD; the registered read path returns snapshots with no read side effects. The serial core runs in the SMCLK domain (SYS_CLK_CR=0 rule applies), with a programmable baud divider off SMCLK.', registerPrefix='QSPIx', bitFieldPrefix='QSPI', latexIntroFileName='QSPI-intro-castalia-2026-07.tex', latexFeatureSummary='{count} QSPI flash controller (single/dual/quad lane; per-phase width)')
	m.AddPeripheralTemplate(qspi)

	_rdlRegisters('QSPIx', qspi)

# digperiphs #2 (2026-07-18): I3C0 register template (design doc S3, 10 slots).
# Added unconditionally (before CheckPeripheralTemplates) so the template exists
# whenever i3cPresent CreatePeripheral()s it at 0x6100; with I3C off it is never
# instanced. The serial core is smclk-domain (SYS_CLK_CR=0 rule); the register
# read path is registered with NO side effects.
if i3cPresent:
	i3c = PeripheralTemplate(nameTemplate='I3Cx', description='I3C controller (MIPI I3C basic, single-controller). Drives an I3C bus (SDA/SCL, open-drain and push-pull SDR) as the active controller, and interoperates with legacy I2C targets on the same wires. This MVP-plus implementation supports single-byte SDR private read/write transfers, repeated-START chaining, Common Command Codes (CCC), hardware Dynamic Address Assignment (DAA via ENTDAA and SETDASA), and In-Band Interrupts (IBI) from targets. A transaction is described by the control and command registers and launched by a byte-lane-0 write to I3CxCMD; the registered read path returns snapshots with no read side effects. The serial core runs in the SMCLK domain (SYS_CLK_CR=0 rule applies) with independent open-drain and push-pull baud dividers.', registerPrefix='I3Cx', bitFieldPrefix='I3C', latexIntroFileName='I3C-intro-castalia-2026-07.tex', latexFeatureSummary='{count} I3C controller (SDR + legacy-I2C, dynamic address assignment, in-band interrupts)')
	m.AddPeripheralTemplate(i3c)

	_rdlRegisters('I3Cx', i3c)
	# Slot 9 is reserved (reads 0) and is intentionally NOT modelled as a
	# register: an all-unused register generates no _Register_t typedef and
	# breaks the emitted MemoryMap.h. The I3C address window is the 256 B
	# sub-slot; word 9 simply reads 0.

# digperiphs #3 (2026-07-18): NFC0 register template (design doc S8, 10 slots
# @0x6200). Added unconditionally (before CheckPeripheralTemplates) so the
# template exists whenever nfcPresent CreatePeripheral()s it; with NFC off it is
# never instanced. The bus/CDC core is smclk-domain and the register read path
# is registered with NO side effects (QSPI/I3C house style); the protocol core
# runs on the AFE carrier-derived rf_clk (off-die).
if nfcPresent:
	nfc = PeripheralTemplate(nameTemplate='NFCx', description='NFC controller: ISO/IEC 14443 Type A (14443A) tag / card-emulation digital protocol engine. Emulates a contactless smart-card / tag to an external reader: it recovers the reader-to-tag frames (Miller decode, byte + odd-parity de-framing, CRC_A check), runs the tag transaction state machine (REQA/WUPA to ATQA, bit-frame anticollision by 4-byte UID to SAK, then a Type-2 READ that auto-answers from a firmware-filled payload window), and load-modulates the tag response (Manchester subcarrier at fc/16). The register read path is registered with no read side effects. The block spans three clock domains: the gated memory bus (ClkMem), a free-running SMCLK reference that hosts the clock-domain-crossing synchronizers and write-1-to-clear retirement (the SYS_CLK_CR=0 rule applies), and the AFE carrier-derived rf_clk that clocks the entire protocol core. The 13.56 MHz RF analog front-end is off-die: the block presents only a small digital AFE interface (demodulated RX envelope, field-detect, load-modulation drive, listen-power enable).', registerPrefix='NFCx', bitFieldPrefix='NFC', latexIntroFileName='NFC-intro-castalia-2026-07.tex', latexFeatureSummary='{count} NFC ISO 14443A tag / card-emulation engine (Miller/Manchester codec, CRC-A, anticollision, digital AFE boundary)')
	m.AddPeripheralTemplate(nfc)

	_rdlRegisters('NFCx', nfc)

# digperiphs #4 (2026-07-20): RTC0 register template (design doc D5, 6 live word
# slots @0x6500 + a reserved TRIM slot). Added only when rtcPresent CreatePeripheral()s
# it; with RTC off it is never instanced (byte-identical default). The register read
# path is REGISTERED on rising ClkMem over data already synchronized into the bus
# domain (D4/D7/D10) — NO combinationalRead bridge and NO CAPTURE_CLOCK pre-latch
# shim (the RTC is the first library block clean of both). The wall clock rides the
# ungated lfxt_in domain (D1); the CDC synchronizers + sticky W1C flags + IRQ combiner
# ride the free-running clk (wired to MCLK at integration, A2). Coherent SEC/SUB reads
# are up to ~1 LFXT period (~30.5 us) stale and a torn-free 47-bit pair needs the
# firmware SEC-recompare idiom (driver contract, A3); the count is IMMUNE to clock
# reconfig / PWRCTRL gating, so a driver must NOT copy the "write SYS_CLK_CR=0 first"
# rule (inverted-SYS_CLK_CR note, D1).
if rtcPresent:
	rtc = PeripheralTemplate(nameTemplate='RTCx', description='Real-Time Clock: a 32.768 kHz always-on wall clock (32-bit seconds + 15-bit subsecond prescaler) with a one-shot alarm compare and a recurring periodic tick, delivered on ONE combined interrupt (vector 114). It clocks off the ungated LFXT crystal, so timekeeping survives clock reconfiguration and PWRCTRL tile power-gating; unlike the SMCLK peripherals it does NOT want SYS_CLK_CR = 0 (the count is immune to the SMCLK source). The {sec, subsecond} pair is one 47-bit counter (the prescaler rolls at exactly 2^15 = 32768, so seconds is literally its carry-out, giving exact 1 Hz). Reads return a coherent double-buffered snapshot synchronized into the bus domain (no read side effects); a torn-free 47-bit pair uses the standard read-SEC / read-SUB / read-SEC-again retry. Set-time and alarm / period updates cross into the LFXT domain through a request/acknowledge handshake reported by SR.SYNC; software must poll SR.SYNC = 0 before the next committing write. The block has zero pins.', registerPrefix='RTCx', bitFieldPrefix='RTC', latexIntroFileName='RTC-intro-castalia-2026-07.tex', latexFeatureSummary='{count} real-time clock (32.768 kHz always-on wall clock, one-shot alarm, periodic tick, single combined IRQ)')
	m.AddPeripheralTemplate(rtc)

	_rdlRegisters('RTCx', rtc)

# An overlay's peripheral templates are built here, with the same two calls the
# tree's own blocks use: AddPeripheralTemplate and _rdlRegisters. Its register
# descriptions come from its own rdl/ and rdl.json (rdl_model.addOverlay), so a
# private block is described in SystemRDL exactly like a public one.
overlay.call('peripheralTemplates', m=m, vals=_overlayVals,
	PeripheralTemplate=PeripheralTemplate, rdlRegisters=_rdlRegisters)
# digperiphs #5 (2026-07-20): PWM0 register template (design doc D5, 9 word slots
# @0x6600). Added only when pwmPresent CreatePeripheral()s it; with PWM off it is
# never instanced (byte-identical default). The register read path is REGISTERED on
# rising ClkMem over data already in the bus/mclk domain (staging readback +
# clk-domain sticky flags) — NO combinationalRead bridge and NO CAPTURE_CLOCK
# pre-latch shim (D4; the second library block, after RTC0, clean of both). The
# waveform words (PER/DTY0/DTY1) are DOUBLE-BUFFERED — a write stages them and arms
# UPDF; they commit atomically at the next period boundary (D9, the glitch-free
# guarantee). POL is immediate (D11). FLTTRIG is a write-1 self-clearing software
# trip (A2); FLTF/PEVF are sticky W1C flags (D14). The engine rides the free-running
# MCLK (D1) — the count is IMMUNE to clock reconfig, so unlike the SMCLK peripherals
# a driver must NOT write SYS_CLK_CR=0 for the PWM. The reserved DTY2/DTY3/DT slots +
# CR CH2EN/CH3EN/CNTMODE/DTEN/FLTPOL + POL[3:2]/[7:6] + SR.DIR bits are D16/D19
# bolt-on reservations (4-channel, center-aligned, deadtime — read 0, no map break).
if pwmPresent:
	pwm = PeripheralTemplate(nameTemplate='PWMx', description='Buffered PWM Generator: a glitch-free 2-channel edge-aligned PWM engine (16-bit period + two 16-bit per-channel duties) with double-buffered waveform update, per-channel polarity and an absolute programmable safe/off level, a software fault trip that forces both outputs safe the same cycle, and a period-event tick. It runs on a prescaled free-running MCLK (no LFXT, no generated clocks); the register file rides the gated bus clock. The three waveform words (period + the two duties) are double-buffered: writes stage into shadow registers and commit atomically at the next period boundary (SR.UPDF reports a pending commit), so a mid-period duty/period change never produces a runt or double pulse. Polarity and the safe level are immediate (program them before enabling). The fault is software/mask-only (no HW pin): with FLTEN set, writing FLTTRIG forces both outputs to their safe levels within one clock and latches SR.FLTF (write-1-to-clear, then the output resumes tracking the still-running comparator). Two lean interrupts are delivered on the router: PWM0_FAULT (vector 115, lower id = router priority) and PWM0_EVT (vector 116). The two channel outputs ride existing bonded AF-spread pins (P2.2/P2.3 AF2); the block has zero input pins. Reserved slots and control bits are provisioned for deferred 4-channel, center-aligned and deadtime/complementary bolt-ons without a register-map break.', registerPrefix='PWMx', bitFieldPrefix='PWM', latexIntroFileName='PWM-intro-castalia-2026-07.tex', latexFeatureSummary='{count} buffered PWM generator (2 channels, glitch-free double-buffered update, software fault trip, period-event tick, two IRQs)')
	m.AddPeripheralTemplate(pwm)

	_rdlRegisters('PWMx', pwm)

# digperiphs #5 (2026-07-20): OW0 register template (design doc D5 maps, 6 live word
# slots @0x6700 + a reserved SPU slot 6). Added only when onewirePresent
# CreatePeripheral()s it; with OneWire off it is never instanced (byte-identical
# default). The register read path is REGISTERED on rising ClkMem over data already in
# the bus/mclk domain (the clk-domain sticky flags + DQ synchronizer are the same mclk
# family at integration, D1/D4) — NO combinationalRead bridge and NO CAPTURE_CLOCK
# pre-latch shim (the second library block, after RTC0, clean of both). OW0CMD is
# WRITE-ONLY-LAUNCH: a byte-lane-0 write captures {OP,BITVAL,ODS,TX} into a launch
# descriptor and (unless OWEN=0 or BUSY=1) starts the slot FSM (D8); OW0TX/OW0CR/OW0DIV
# writes never launch. Results land side-effect-free in OW0RX (A3: RDBIT -> [0], RDBYTE
# -> [7:0]). The engine rides the free-running MCLK (D1/D2), so unlike the SMCLK
# peripherals a driver must NOT write SYS_CLK_CR=0 for the 1-Wire; OW0DIV calibrates the
# 0.5 us tick base (A1: DIV=11 at 24 MHz). SPUEN (CR bit 2) + OW0SPU (slot 6) are the
# strong-pullup reservation stub (D15 — writable-but-inert / reads 0, no driven-high
# phase this stage), provisioned so a future parasite-power SPU bolts on without a
# register-map break.
if onewirePresent:
	ow = PeripheralTemplate(nameTemplate='OWx', description='1-Wire Master: a Dallas/Maxim 1-Wire link-layer controller that runs the five microsecond-scale bus primitives in hardware (reset+presence, write-bit, read-bit, write-byte and read-byte) off a programmable time base, leaving ROM search and CRC-8 to firmware over those primitives. It is master-only and supports both standard and overdrive speeds (selected by CR.ODS, latched at each transaction launch). A transaction is described by the control and command registers and LAUNCHED by a byte-lane-0 write to OW0CMD (the launch is suppressed while the master is disabled or busy); the registered read path returns status and the received byte with no read side effects. The whole engine (the OW0DIV counter-compare time base, the slot state machine, the two-flop DQ synchronizer, the sticky write-1-to-clear status flags, and the interrupt combiner) rides the free-running MCLK, so the tick base is immune to clock reconfiguration and unlike the SMCLK peripherals a driver must NOT write SYS_CLK_CR to 0. One combined interrupt (transaction-complete or error) is delivered on the router at vector 117. The block has one open-drain DQ pin; the strong-pullup enable and its register slot are a reserved stub (no driven-high phase this stage).', registerPrefix='OWx', bitFieldPrefix='OW', latexIntroFileName='OneWire-intro-castalia-2026-07.tex', latexFeatureSummary='{count} 1-Wire master (reset/presence + bit/byte primitives, standard + overdrive, firmware ROM search + CRC-8, single combined IRQ)')
	m.AddPeripheralTemplate(ow)

	_rdlRegisters('OWx', ow)

# digperiphs (2026-07-22): I2CT0 register template (design doc D5 bit maps, 5 live word
# slots @0x6A00: I2CTCR / I2CTSR / I2CTTX / I2CTRX / I2CTWDG). Added only when
# i2ctargetPresent CreatePeripheral()s it; with I2CT0 off it is never instanced
# (byte-identical default). Registered read on rising ClkMem (D4 — no bridge, no
# CAPTURE_CLOCK; the plain raw-strobe active-low en shim, RTC/PWM/OW precedent). W1C
# status flags, BUSY same-cycle status rule where applicable, RSVD reads 0 (slots >=5
# read 0). bitFieldPrefix I2CT.
if i2ctargetPresent:
	i2ct = PeripheralTemplate(nameTemplate='I2CTx', description='Hardware-Autonomous I2C Target: an I2C slave engine that handles the protocol in hardware: 7-bit address match with a wildcard mask and optional general-call response, byte-at-a-time receive and transmit with ready/empty status, hardware clock stretching for lossless flow control, START / STOP / repeated-START / NACK framing detection, and a configurable stuck-SCL watchdog. The whole engine (the two-flop SDA/SCL synchronizers, the edge/framing detectors, the address matcher, the RX/TX byte paths, the clock-stretch driver, the sticky write-1-to-clear status flags, and the two interrupt combiners) rides the free-running MCLK, so its timing is immune to clock reconfiguration and unlike the SMCLK I2C0/I2C1 cores a driver need not write SYS_CLK_CR to 0 for the target itself. Two combined interrupts are delivered on the router: vector 122 (address/error) and vector 123 (tx-ready/rx-full). It is complementary to the software-serviced slave-mode registers of I2C0/I2C1: I2CT0 shares the same open-drain SDA0/SCL0 pads through a wired-AND merge and needs no per-byte firmware bit-banging. The guaranteed bus-speed floor is f_SCL <= MCLK/24 (Standard 100 kHz and Fast 400 kHz at 24 MHz MCLK).', registerPrefix='I2CTx', bitFieldPrefix='I2CT', latexIntroFileName='I2CT-intro-castalia-2026-07.tex', latexFeatureSummary='{count} hardware-autonomous I2C target (7-bit address match + mask + general call, hardware clock stretching, START/STOP framing flags, single-byte RX/TX with ready/empty status, stuck-SCL watchdog, 2 combined IRQs)')
	m.AddPeripheralTemplate(i2ct)

	_rdlRegisters('I2CTx', i2ct)

# digperiphs #6 (2026-07-21): DMA0 register template (design doc D5 bit maps, the
# 4-channel SUPERSET: 20 word slots @0x6800 -- global CR/SR, four fixed-stride
# per-channel {SRC,DST,LEN,CFG} blocks, DMA0CRC, reserved DMA0DESC). Added only when
# dmaPresent CreatePeripheral()s it; with DMA off it is never instanced (byte-identical
# default). The register map is the 4-channel superset REGARDLESS of dmaChannels (the
# NCH generic): a 2-channel build reads 0 on CH2/CH3 slots and their CR/SR bits and
# ignores writes to them (D6). The register file rides the gated bus clock (ClkMem =
# mclk at integration); the read mux registers on rising ClkMem over data already in
# the mclk domain -- neither combinationalRead NOR in mcu_vhd.py's CAPTURE_CLOCK set
# (a plain raw-strobe shim, D4). No latexIntroFileName here: the TRM chapter/intro is a
# documentation follow-up (the register tables generate; the chapter carries no intro
# prose until then).
if dmaPresent:
	dma = PeripheralTemplate(nameTemplate='DMAx', description='Configurable multi-channel single-shot DMA controller: it moves words source->dest over the shared arbiter as a stream of single-word transactions, either flat-out under software GO (memory-to-memory) or paced one word per peripheral data-ready event (UART0 RC / QSPI0 RX-full / NFC0 payload-ready), with optional per-channel source/dest auto-increment, a per-channel 2-level priority + word-granular round-robin, an optional CRC16-CDMA2000 ride-along, and a hardware read-side-effect guard (reads targeting the mutex sub-slot window 0x6000-0x60FF or the irq_router CLAIM word 0x7800 raise an error instead of issuing). The channel count is the NCH build generic ({2,4}); this register map is the 4-channel SUPERSET regardless -- on a 2-channel build the CH2/CH3 register blocks and their CR/SR bits read 0 and ignore writes. The whole transfer engine (master-port FSM, per-channel SRC/DST/LEN working counters, round-robin picker, CRC datapath, pacing edge-detectors, sticky W1C flags and the two IRQ combiners) rides the free-running MCLK; the register file rides the gated bus clock. The block has zero pins and delivers two interrupts: DMA0_DONE (combined channels-done, vector 118) and DMA0_ERR (vector 119).', registerPrefix='DMAx', bitFieldPrefix='DMA', latexIntroFileName='DMA-intro-castalia-2026-07.tex', latexFeatureSummary='{count} multi-channel single-shot DMA controller (2/4 channels, peripheral-paced or mem-to-mem, CRC16 ride-along, read-side-effect guard, two IRQs)')
	m.AddPeripheralTemplate(dma)

	_rdlRegisters('DMAx', dma)

# digperiphs (TRNG, 2026-07-22): TRNG0 register template (design doc D5 bit maps, 4 live
# word slots @0x6900: TRNG0CR / TRNG0SR / TRNG0DR / TRNG0HT). Added only when trngPresent
# CreatePeripheral()s it; with TRNG off it is never instanced (byte-identical default).
# Registered read on rising ClkMem (D4 -- no bridge, no CAPTURE_CLOCK; the plain
# raw-strobe active-low en shim, RTC/PWM/OW/DMA/I2CT precedent). TRNG0DR is the ONE
# read-side-effect exception in this library (D9: read-CONSUMES, exactly-once, with a
# DRDY same-cycle blind-window fix); ALMF is sticky W1C and auto-halts harvesting while
# set (D8). Slots >= 4 read 0. bitFieldPrefix TRNG.
if trngPresent:
	trng = PeripheralTemplate(nameTemplate='TRNGx', description='Ring-oscillator entropy source and harvest engine: a free-running ensemble of NRO ring oscillators (peripherals.trngRings, {4,8}) is XOR-reduced to one noisy bit, 2-FF synchronized into the free-running MCLK, decimated (one raw sample every 2^DECIM MCLK cycles) and direct-packed 32 raw bits at a time into a holding register. A qualified read of the data register returns the word and CONSUMES it in the same access (DRDY clears the same cycle, the next word is requested) so no read ever exposes a stale or partial word; a read while no word is ready returns 0 and has no side effect. A lightweight SP 800-90B-style Repetition Count Test watches the raw stream: when RCTC (or the hardware default of 32) consecutive raw samples are identical it raises a sticky health alarm and AUTO-HALTS harvesting (the rings keep spinning only if EN is set and no alarm is latched) until firmware clears it. The whole engine -- the RO 2-flop synchronizer, the decimator, the 32-bit assembler, the repetition-count health test, the sticky alarm flag, and the interrupt combiner -- rides the free-running MCLK; the register file rides the gated bus clock. The block has zero pins (the RO ensemble is internal combinational fabric) and delivers one combined interrupt (data-ready or health-alarm, vector 121). THE ENTROPY CAVEAT: this is a bring-up-grade entropy source, not a certified one -- firmware MUST run the raw words through a vetted DRBG before using them as key material and MUST honor the health alarm.', registerPrefix='TRNGx', bitFieldPrefix='TRNG', latexIntroFileName='TRNG-intro-castalia-2026-07.tex', latexFeatureSummary='{count} ring-oscillator true-random-number-generator harvest engine (NRO-ring ensemble, read-consumes data register, repetition-count health test with auto-halt, single combined IRQ, bring-up-grade entropy)')
	m.AddPeripheralTemplate(trng)

	_rdlRegisters('TRNGx', trng)


# digperiphs (EVFAB, 2026-07-24): EVFAB0 register template (design doc D18 bit maps,
# 64-word map @0x6B00; 13 named word slots + the 16-address CHnCFG array). Added only
# when eventFabricPresent CreatePeripheral()s it; with the fabric off it is never
# instanced (byte-identical default). Single instance, so the register names carry NO
# instance index (the PWRCTRL/MUTEX/CLINT class): EVFCR, EVFSR, ... EVFCH0CFG.
# Slots 12-14 stay reserved for the earmarked TKSTAT/FIREDIE/OVRIE (D18) and slots
# 32-63 read 0. bitFieldPrefix EVF.
if eventFabricPresent:
	_EVFAB_N_CH = 8			# EVFAB.vhd N_CH generic (live channels; the array is 16 addresses)
	_EVFAB_N_EV = 16		# N_EV generic (live event lines; EVSEL encode space is 32)
	_EVFAB_N_TASK = 10		# N_TASK generic (live task lines; TASKSEL encode space is 16)
	_EVFAB_VER = 1			# VER generic (CAP.VER)
	evfab = PeripheralTemplate(nameTemplate='EVFAB', description='Event/trigger fabric: a PPI-style crossbar that lets peripherals command each other with no processor in the loop. Eight independent channels each hold one {EVSEL, TASKSEL} pair; when the selected EVENT fires and the channel is enabled, the fabric emits a registered one-MCLK pulse on the selected TASK line, one MCLK after the event. Sixteen event lines are wired: RTC0 tick and alarm, PWM0 period and fault, TIMER0 compare0 and overflow, TIMER1 compare0, UART0 receive, NFC0 field-detect and rx-frame, DMA0 channel-0/1 done and error, TRNG0 data-ready, I2CT0 address-match, and a masked GPIO0 pad-edge path (event 15) whose eight raw pad edges are selected by EVFGPIOMASK. Ten task lines are wired: DMA0 channel-0/1 GO, TIMER0 START and STOP, PWM0 fault trip, PWRCTRL tile wake, NPU0 THINK, and GPIO0 output SET and CLEAR (acting on the pins selected by that port\'s PxTASK register). Every event tap is taken from its source flag\'s SET condition BEFORE any interrupt mask, so a chain works with every interrupt disabled, and the fabric owns all clock-domain crossing (each input is a pulse, a toggle or a level according to the block\'s domain, converted by a uniform three-flop front end). The whole block rides the free-running MCLK in the always-on domain: WFI keeps it alive, field-power mode only slows it, and PWRCTRL never gates it -- so chains keep firing with every hart asleep, which is the entire point. A channel is completely inert unless both the global enable and its own channel-enable bit are set; enables are changed through the write-1 CHENSET/CHENCLR aliases so two harts never race a read-modify-write. Sticky FIRED, OVR and EVSTAT words record what happened (EVSTAT records raw events even while the fabric is disabled, which makes a mis-taken post-mask event tap directly observable), and CHTRIG/EVTRIG let firmware inject a channel firing or a raw event with no producer hardware at all. The fabric is never a bus master, never stalls, never rate-limits and never backpressures a consumer: OVR only records that a pulse was degraded (the consumer was busy, or two channels merged onto one task in the same cycle). This version spends no interrupt vector -- the interrupt output is a constant 0 and the EVFIE slot is reserved -- so firmware polls EVFSR, whose two flags are live reductions of the FIRED and OVR words.', registerPrefix='EVF', bitFieldPrefix='EVF', latexIntroFileName='EVFAB-intro-castalia-2026-07.tex', latexFeatureSummary='{count} event/trigger fabric (PPI-style crossbar: ' + str(_EVFAB_N_CH) + ' channels, ' + str(_EVFAB_N_EV) + ' event producers, ' + str(_EVFAB_N_TASK) + ' task consumers, one-MCLK registered pulses, peripheral-to-peripheral chains with every hart asleep)')
	m.AddPeripheralTemplate(evfab)

	_rdlRegisters('EVFAB', evfab)


m.CheckPeripheralTemplates()




''' Create Peripherals from PeripheralTemplates and add them to the memory map '''
# Based on MCU_MP MCU.vhd region decode. Hart-0-private peripherals keep their legacy
# 0x4000-page slots. The shared peripherals live ONLY at their shared-window addresses
# (UART0 at 0x12000; the rest in the 0x13000 page at 0x13000 + 256*legacy_slot) — their
# old 0x4X00 windows read zeros in the RTL, so the legacy addresses must not be published.
# RTL-generation track Phase 2: sharedBus/combinationalRead/clockDomain/strobeNote are the
# per-peripheral BUS metadata consumed by python/mcu_vhd.py when generating MCU.vhd
# (sharedBus='periph' = standard register bus bridged onto the mp_arbiter with the
# active-low en/wen shim; 'native' = speaks the arbiter slave protocol directly;
# combinationalRead=True = read path collapses when en deasserts -> MCU-side bridge
# register at the LATCH->DATA edge, NEVER a stretched en strobe).
# M11: the private peripheral page is GONE — EVERY peripheral is an arbiter
# slave in the shared window, back at its ORIGINAL legacy 0x4000-page address
# (window page 0, slot = legacySlot). sharedBus='periph' requires the
# absolute-base form, so the addresses are spelled out (0x4000 + 0x100*slot).
GPIO0 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=1, absoluteBaseAddress=0x4000, legacySlot=0, sharedBus='periph', clockDomain='mclk')	# GPIO0 (M11 shared; the bootrom still programs the flash CS through it — now via the arbiter)
GPIO1 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=1, peripheralMemorySlot=None, interruptPriority=28, absoluteBaseAddress=0x4100, legacySlot=1, sharedBus='periph', clockDomain='mclk')	# GPIO1 shared (slot 1)
m.CreatePeripheral(nameTemplate='SPIx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=9, absoluteBaseAddress=0x4200, legacySlot=2, sharedBus='periph', clockDomain='smclk', strobeNote='reading SPI0RX auto-clears TCIF')	# SPI0 (M11 shared; its flash/XIP port stays on hart 0's >=0x20000 decode)
if spi1Present:
	m.CreatePeripheral(nameTemplate='SPIx', nameIndex=1, peripheralMemorySlot=None, interruptPriority=11, absoluteBaseAddress=0x4300, legacySlot=3, sharedBus='periph', clockDomain='smclk', strobeNote='reading SPI1RX auto-clears TCIF')	# SPI1 shared (slot 3; config-droppable since G1b)
m.CreatePeripheral(nameTemplate='UARTx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=13, absoluteBaseAddress=0x4400, legacySlot=4, sharedBus='periph', clockDomain='smclk')	# UART0 shared console UART (M11: back at its original 0x4400)
if uart1Present:
	m.CreatePeripheral(nameTemplate='UARTx', nameIndex=1, peripheralMemorySlot=None, interruptPriority=52, absoluteBaseAddress=0x4500, legacySlot=5, sharedBus='periph', clockDomain='smclk')	# UART1 shared (slot 5; config-droppable since G1b)
m.CreatePeripheral(nameTemplate='TIMERx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=16, absoluteBaseAddress=0x4600, legacySlot=6, sharedBus='periph', clockDomain='muxed', strobeNote='ClockMuxGlitchFree needs 3 edges of the OLD source to release; poll-until-counting after enable')	# TIMER0 shared (slot 6)
if timer1Present:
	m.CreatePeripheral(nameTemplate='TIMERx', nameIndex=1, peripheralMemorySlot=None, interruptPriority=22, absoluteBaseAddress=0x4700, legacySlot=7, sharedBus='periph', clockDomain='muxed', strobeNote='ClockMuxGlitchFree needs 3 edges of the OLD source to release; poll-until-counting after enable')	# TIMER1 shared (slot 7; config-droppable since G1b)
GPIO2 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=2, peripheralMemorySlot=None, interruptPriority=36, absoluteBaseAddress=0x4800, legacySlot=8, sharedBus='periph', clockDomain='mclk')	# GPIO2 shared (slot 8)
m.CreatePeripheral(nameTemplate='SYSTEM', nameIndex='', peripheralMemorySlot=None, interruptPriority=0, absoluteBaseAddress=0x4900, legacySlot=9, sharedBus='periph', clockDomain='mclk', strobeNote='SYS_CLK_CR/SYS_CLK_DIV_CR reconfigure MCLK itself: quiesce the other harts before clock reconfiguration (software contract)')	# SYSTEM (M11 shared; clock/power/WDT monarch — hart-0 management by convention)
if npuPresent:
	m.CreatePeripheral(nameTemplate='NPU', nameIndex='', peripheralMemorySlot=None, interruptPriority=120, absoluteBaseAddress=0x4A00, legacySlot=10, sharedBus='periph', combinationalRead=True, clockDomain='mclk', strobeNote='vectors live in the shared NPU staging RAM at 0xC000; do not touch 0xC000-0xFFFF during a THINK — poll NPUCR bit 16 (or take the vector-120 think-done IRQ, DP-SG)')	# NPU register bus shared (slot 10); data path = the 0xC000 staging RAM
# SARADC removed (vector 56 reserved gap; its slot 11 is PWRCTRL's since M17)
# AFE: no CreatePeripheral. By default the four AFE + one EIS afe_stub instances
# (peripherals.cqAfeStubs) occupy slot 12 / 0x7C00 as MCU.vhd wiring only (see
# the CQ doc sub-slot blocks + mcu_vhd.py); with cqAfeStubs=false the QSPI0
# controller below (peripherals.qspi) can claim slot 12 instead.
m.CreatePeripheral(nameTemplate='PWRCTRL', nameIndex='', peripheralMemorySlot=None, interruptPriority=None, absoluteBaseAddress=0x4B00, legacySlot=11, sharedBus='native', clockDomain='mclk', strobeNote='cold-gate: a gated tile loses all state and reboots through the shared ROM on wake; gate only parked/quiesced tiles')	# M17 power controller (slot 11, ex-SARADC0; native arbiter slave)
if qspiPresent:
	m.CreatePeripheral(nameTemplate='QSPIx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=55, absoluteBaseAddress=0x4C00, legacySlot=12, sharedBus='periph', clockDomain='smclk')	# QSPI0 (digperiphs #1, slot 12; registered read, no bridge, no RX read side effects)
GPIO3 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=3, peripheralMemorySlot=None, interruptPriority=44, absoluteBaseAddress=0x4D00, legacySlot=13, sharedBus='periph', clockDomain='mclk')	# GPIO3 shared (slot 13)
m.CreatePeripheral(nameTemplate='I2Cx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=57, absoluteBaseAddress=0x4E00, legacySlot=14, sharedBus='periph', combinationalRead=True, clockDomain='smclk')	# I2C0 shared (slot 14)
if i2c1Present:
	m.CreatePeripheral(nameTemplate='I2Cx', nameIndex=1, peripheralMemorySlot=None, interruptPriority=70, absoluteBaseAddress=0x4F00, legacySlot=15, sharedBus='periph', combinationalRead=True, clockDomain='smclk')	# I2C1 shared (slot 15; config-droppable since G1a)

# Multi-core shared-window peripherals (behind the mp_arbiter, reachable by all harts)
# A2: the three whole-page native slaves may outgrow the 64-word page-0 slot
# pitch at large hart counts (IRQROUTER rows at 4h need word 68 at h=17) —
# registerSlotCount is the per-peripheral engine override (None while it fits,
# so the Castalia N=4 description is provably untouched).
m.CreatePeripheral(nameTemplate='CLINT', nameIndex='', peripheralMemorySlot=None, interruptPriority=83, absoluteBaseAddress=0x5000, sharedBus='native', clockDomain='mclk', registerSlotCount=_slotCountOverride(clintSlotCount))	# CLINT at 0x5000 (M11: window page 1; vectors 83 msip, 84 mtip)
m.CreatePeripheral(nameTemplate='MUTEX', nameIndex='', peripheralMemorySlot=None, interruptPriority=None, absoluteBaseAddress=0x6000, sharedBus='native', clockDomain='mclk', strobeNote='READ = atomic return-old-and-claim; never LR/SC or AMO a mutex address', registerSlotCount=_slotCountOverride(numMutexes))	# HW mutex bank at 0x6000 (M11: window page 2; digperiphs tightens the decode to sub-slot 0 @0x6000-0x60FF when I3C or NFC is present)
if i3cPresent:
	# digperiphs #2: I3C0 at 0x6100 = MUTEX page (page 2) SUB-SLOT 1. sharedBus is
	# left None on purpose: the mutex page is not the page-0 shim fabric, so the
	# RTL (decode carve + instance + the registered-read shim inside emitI3cInstance)
	# is hand-emitted by mcu_vhd.py under geo['i3c'] rather than through the page-0
	# CreatePeripheral machinery. This CreatePeripheral exists for the register map,
	# TRM chapter, address table, and the vectors-86..93 interrupt-table entry.
	m.CreatePeripheral(nameTemplate='I3Cx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=86, absoluteBaseAddress=0x6100, sharedBus='native', clockDomain='smclk', strobeNote='page-2 sub-slot 1; registered read, no side effects; smclk serial core (SYS_CLK_CR=0 rule)')	# I3C0 (digperiphs #2). sharedBus=native = "outside the page-0 shim fabric"; the mcu_vhd emitter hand-decodes the sub-slot + emits the registered-read shim inside its instance
if nfcPresent:
	# digperiphs #3: NFC0 at 0x6200 = MUTEX page (page 2) SUB-SLOT 2. Same shape
	# as I3C (sharedBus=None -> the mcu_vhd emitter hand-decodes the sub-slot and
	# emits the registered-read shim + instance under geo['nfc']). This
	# CreatePeripheral exists for the register map, TRM chapter, address table,
	# and the vectors-94..97 interrupt-table entry. clockDomain='smclk' names the
	# bus/CDC reference clock; the protocol core runs on the off-die rf_clk.
	m.CreatePeripheral(nameTemplate='NFCx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=94, absoluteBaseAddress=0x6200, sharedBus='native', clockDomain='smclk', strobeNote='page-2 sub-slot 2; registered read, no side effects; smclk CDC + off-die rf_clk protocol core (SYS_CLK_CR=0 rule); digital AFE / RF interface is off-die (placeholder-tied)')	# NFC0 (digperiphs #3). sharedBus=native = "outside the page-0 shim fabric"; the mcu_vhd emitter hand-decodes the sub-slot + emits the registered-read shim inside its instance
# digperiphs Mission B: GPIO4 (port 5) @0x6300 and GPIO5 (port 6) @0x6400 = MUTEX
# page (page 2) SUB-SLOTS 3 and 4. UNCONDITIONAL (present in EVERY config, like
# GPIO0-3). Same page-2 native shape as I3C0/NFC0 (sharedBus=native, outside the
# page-0 shim fabric), but the instance is a full GPIO block with a registered-read
# shim + AF muxing: mcu_vhd.py hand-decodes the sub-slot and emits the shim +
# GPIO component + AF planes. Their pins carry the QSPI/I3C (P5) and NFC (P6) pin
# functions on AF1 when those controllers are present, plain GPIO otherwise.
GPIO4 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=4, peripheralMemorySlot=None, interruptPriority=98, absoluteBaseAddress=0x6300, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 3; registered read; AF1 = QSPI0 (P5.0-5) + I3C0 (P5.6/7) pin functions when present')	# GPIO4 (Mission B). native page-2 sub-slot 3; mcu_vhd hand-emits the shim + GPIO instance + AF planes
GPIO5 = m.CreatePeripheral(nameTemplate='GPIOx', nameIndex=5, peripheralMemorySlot=None, interruptPriority=106, absoluteBaseAddress=0x6400, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 4; registered read; AF1 = NFC0 digital-AFE pin functions (P6.0-5) when present')	# GPIO5 (Mission B). native page-2 sub-slot 4; mcu_vhd hand-emits the shim + GPIO instance + AF planes
if rtcPresent:
	# digperiphs #4: RTC0 at 0x6500 = MUTEX page (page 2) SUB-SLOT 5. Same page-2
	# native shape as I3C0/NFC0/GPIO4/GPIO5 (sharedBus='native' = "outside the page-0
	# shim fabric"; the mutex-bank decode is already tightened to sub-slot 0 whenever
	# any page-2 sub-slot device is present). This CreatePeripheral exists for the
	# register map, TRM chapter, address table, and the vector-114 interrupt-table
	# entry; the RTL (sub-slot 5 decode + the registered-read shim + the RTC instance)
	# is hand-emitted by mcu_vhd.py under geo['rtc']. clockDomain='mclk' names BOTH the
	# bus clock (ClkMem) AND the free-running CDC/flag/IRQ reference clock (clk => mclk,
	# adjudication A2); the wall clock itself rides the ungated lfxt_in pad crystal (D1).
	# NOT combinationalRead and NOT a CAPTURE_CLOCK slave (D4): the instance uses a plain
	# raw-strobe active-low en shim (rtc0_sh_en_n <= not shslv_rtc0_en, the GPIO4/5 idiom),
	# with no falling_edge(EnMemPeriph) pre-latch — the first library block clean of both.
	m.CreatePeripheral(nameTemplate='RTCx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=114, absoluteBaseAddress=0x6500, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 5; registered read, no bridge, no CAPTURE_CLOCK pre-latch; ungated lfxt_in wall clock (D1); count immune to SYS_CLK_CR (do NOT write SYS_CLK_CR=0 for the RTC)')	# RTC0 (digperiphs #4). native page-2 sub-slot 5; mcu_vhd hand-emits the raw-strobe shim + RTC instance
if pwmPresent:
	# digperiphs #5: PWM0 at 0x6600 = MUTEX page (page 2) SUB-SLOT 6. Same page-2
	# native shape as I3C0/NFC0/GPIO4/GPIO5/RTC0 (sharedBus='native' = "outside the
	# page-0 shim fabric"; the mutex-bank decode is already tightened to sub-slot 0
	# whenever any page-2 sub-slot device is present). This CreatePeripheral exists for
	# the register map, TRM chapter, address table, and the vector-115 interrupt-table
	# entry (interruptPriority=115 = the FIRST of PWM's two frozen vectors, 115/116); the
	# RTL (sub-slot 6 decode + the raw-strobe registered-read shim + the PWM instance +
	# the two pwm_out spread aliases) is hand-emitted by mcu_vhd.py under geo['pwm'].
	# clockDomain='mclk' names BOTH the bus clock (ClkMem) AND the free-running engine
	# clock (clk => mclk, D1 — prescaler/counter/compare/flags/IRQ all on MCLK). NOT
	# combinationalRead and NOT a CAPTURE_CLOCK slave (D4): a plain raw-strobe active-low
	# en shim (pwm0_sh_en_n <= not shslv_pwm0_en), no falling_edge(EnMemPeriph) pre-latch.
	m.CreatePeripheral(nameTemplate='PWMx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=115, absoluteBaseAddress=0x6600, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 6; registered read, no bridge, no CAPTURE_CLOCK pre-latch; free-running MCLK engine (no LFXT, no generated clocks); count immune to SYS_CLK_CR (do NOT write SYS_CLK_CR=0 for the PWM); pwm_out(0)/(1) replace P2.2/P2.3 AF2 spread slots (A7)')	# PWM0 (digperiphs #5). native page-2 sub-slot 6; mcu_vhd hand-emits the raw-strobe shim + PWM instance + spread aliases
if onewirePresent:
	# digperiphs #5: OW0 at 0x6700 = MUTEX page (page 2) SUB-SLOT 7. Same page-2
	# native shape as I3C0/NFC0/GPIO4/GPIO5/RTC0/PWM0 (sharedBus='native' = "outside the
	# page-0 shim fabric"; the mutex-bank decode is already tightened to sub-slot 0
	# whenever any page-2 sub-slot device is present). This CreatePeripheral exists for
	# the register map, TRM chapter, address table, and the vector-117 interrupt-table
	# entry (interruptPriority=117 = OW0's single frozen vector); the RTL (sub-slot 7
	# decode + the raw-strobe registered-read shim + the OneWire instance + the DQ input
	# mux / ren alias) is hand-emitted by mcu_vhd.py under geo['onewire'], while the DQ
	# OUTPUT/DIR plane comes from the P4.7 AF2 spread slot. clockDomain=
	# 'mclk' names BOTH the bus clock (ClkMem) AND the free-running engine clock (clk =>
	# mclk, D1/D2 — time base / slot FSM / DQ synchronizer / flags / IRQ all on MCLK).
	# NOT combinationalRead and NOT a CAPTURE_CLOCK slave (D4): a plain raw-strobe active-
	# low en shim (ow0_sh_en_n <= not shslv_ow0_en), no falling_edge(EnMemPeriph) pre-latch.
	m.CreatePeripheral(nameTemplate='OWx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=117, absoluteBaseAddress=0x6700, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 7; registered read, no bridge, no CAPTURE_CLOCK pre-latch; free-running MCLK engine (no LFXT, no generated clocks, no clock on the DQ pad); count immune to SYS_CLK_CR (do NOT write SYS_CLK_CR=0 for the 1-Wire); DQ on P4.7/GPIO31 AF2 open-drain (rstREN=1, replaced-spread-slot)')	# OW0 (digperiphs #5). native page-2 sub-slot 7; mcu_vhd hand-emits the raw-strobe shim + OneWire instance + P4.7 AF2 DQ routing
if i2ctargetPresent:
	# digperiphs (I2CT): I2CT0 at 0x6A00 = MUTEX page (page 2) SUB-SLOT 10. Same page-2
	# native shape as I3C0/NFC0/GPIO4/GPIO5/RTC0/PWM0/OW0/DMA0 (sharedBus='native' =
	# "outside the page-0 shim fabric"; the mutex-bank decode is already tightened to
	# sub-slot 0 whenever any page-2 sub-slot device is present). This CreatePeripheral
	# exists for the register map, TRM chapter, address table, and the vector-122 interrupt-
	# table entry (interruptPriority=122 = the FIRST of I2CT0's two frozen vectors, 122/123).
	# clockDomain='mclk' names BOTH the bus clock (ClkMem) AND the free-running engine clock
	# (clk => mclk, D1/D2 — the whole target FSM / SDA/SCL 2-FF sync / flags / watchdog / IRQ
	# combiners on MCLK). NOT combinationalRead and NOT a CAPTURE_CLOCK slave (D4): a plain
	# raw-strobe active-low en shim (i2ct0_sh_en_n <= not shslv_i2ct0_en), no
	# falling_edge(EnMemPeriph) pre-latch. NO new pins — I2CT0 shares I2C0's SDA0/SCL0 pad
	# planes via a wired-AND DIR merge (emitted separately); the RTL (sub-slot 10 decode +
	# raw-strobe shim + the I2CTarget instance + SDA_IN/SCL_IN fanout + the new i2ct0_*_dir
	# scalars) is hand-emitted by mcu_vhd.py under geo['i2ctarget'].
	m.CreatePeripheral(nameTemplate='I2CTx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=122, absoluteBaseAddress=0x6A00, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 10; registered read, no bridge, no CAPTURE_CLOCK pre-latch; free-running MCLK engine (whole target FSM + SDA/SCL 2-FF sync + flags + watchdog + IRQ on MCLK); count immune to SYS_CLK_CR (do NOT write SYS_CLK_CR=0 for the target); shares I2C0 SDA0/SCL0 pads via a wired-AND DIR merge, no new pins')	# I2CT0 (digperiphs I2CT). native page-2 sub-slot 10; mcu_vhd hand-emits the raw-strobe shim + I2CTarget instance + SDA/SCL fanout + i2ct0_*_dir scalars
if dmaPresent:
	# digperiphs #6: DMA0 at 0x6800 = MUTEX page (page 2) SUB-SLOT 8. Same page-2
	# native SLAVE shape as I3C0/NFC0/GPIO4/GPIO5/RTC0/PWM0/OW0 (sharedBus='native' =
	# "outside the page-0 shim fabric"; the mutex-bank decode is already tightened to
	# sub-slot 0 whenever any page-2 sub-slot device is present, A19). This
	# CreatePeripheral exists for the register map, TRM chapter, address table, and the
	# vector-118 interrupt-table entry (interruptPriority=118 = the FIRST of DMA's two
	# frozen vectors, 118/119). clockDomain='mclk' names BOTH the bus clock (ClkMem) AND
	# the free-running engine/master-port clock (clk => mclk, D1). NOT combinationalRead
	# and NOT a CAPTURE_CLOCK slave (D4): a plain raw-strobe active-low en shim
	# (dma0_sh_en_n <= not shslv_dma0_en), no falling_edge(EnMemPeriph) pre-latch. UNLIKE
	# every prior library block DMA0 is ALSO an arbiter MASTER (slice numHarts of arb_*);
	# the sub-slot-8 decode + raw-strobe read shim + the dma0 instance (NCH => dmaChannels)
	# + the N->N+1 FABRIC WIDENING (mp_arbiter/resv_unit/mutex_bank/irq_router generics,
	# the arb_* 5th slice + D18 lrsc/lock ties, the trigger taps, the two irq levels) are
	# all hand-emitted by mcu_vhd.py under geo['dma'] / geo['dmaChannels'].
	m.CreatePeripheral(nameTemplate='DMAx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=118, absoluteBaseAddress=0x6800, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 8; registered read, no bridge, no CAPTURE_CLOCK pre-latch; free-running MCLK engine + arbiter MASTER (slice numHarts); enabling DMA widens the arbiter N=4->5 / MW=3, sh_master 2->3 bits (the ONE shared-fabric touch); read-side-effect guard denies engine reads of 0x6000-0x60FF / 0x7800')	# DMA0 (digperiphs #6). native page-2 sub-slot 8 + the FIRST new arbiter master; mcu_vhd hand-emits the raw-strobe shim + dma0 instance + fabric widening
if trngPresent:
	# digperiphs (TRNG): TRNG0 at 0x6900 = MUTEX page (page 2) SUB-SLOT 9. Same page-2
	# native shape as I3C0/NFC0/GPIO4/GPIO5/RTC0/PWM0/OW0/DMA0/I2CT0 (sharedBus='native' =
	# "outside the page-0 shim fabric"; the mutex-bank decode is already tightened to
	# sub-slot 0 whenever any page-2 sub-slot device is present). This CreatePeripheral
	# exists for the register map, TRM chapter, address table, and the vector-121
	# interrupt-table entry (interruptPriority=121 = TRNG0's single combined source).
	# clockDomain='mclk' names BOTH the bus clock (ClkMem) AND the free-running engine
	# clock (clk => mclk, D1/D2 -- the RO 2-FF sync / decimator / assembler / health test /
	# IRQ combiner all on MCLK). NOT combinationalRead and NOT a CAPTURE_CLOCK slave (D4):
	# a plain raw-strobe active-low en shim (trng0_sh_en_n <= not shslv_trng0_en), no
	# falling_edge(EnMemPeriph) pre-latch. NO pins: the RO ensemble (u_ro, TrngRoEnsemble)
	# is a sibling MCU.vhd instance wired through trng0's ro_enable/ro_sel/ro_sclk/ro_raw
	# ports, never a pad; the sub-slot-9 decode + raw-strobe shim + the trng0 + u_ro
	# instances (NRO => trngRings) are hand-emitted by mcu_vhd.py under geo['trng'] /
	# geo['trngRings']. Bring-up-grade entropy only (THE ENTROPY CAVEAT, D16): firmware
	# MUST DRBG the output and honor ALMF.
	m.CreatePeripheral(nameTemplate='TRNGx', nameIndex=0, peripheralMemorySlot=None, interruptPriority=121, absoluteBaseAddress=0x6900, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 9; registered read, no bridge, no CAPTURE_CLOCK pre-latch; free-running MCLK harvest engine (RO 2-FF sync, decimator, assembler, repetition-count health test); do not poll TRNG0DR blindly -- check TRNG0SR.DRDY first (an empty read returns 0 and does not consume); bring-up-grade entropy only (see THE ENTROPY CAVEAT) -- firmware MUST DRBG the output and honor ALMF')	# TRNG0 (digperiphs TRNG). native page-2 sub-slot 9; mcu_vhd hand-emits the raw-strobe shim + trng0 instance + the sibling u_ro TrngRoEnsemble instance
if eventFabricPresent:
	# digperiphs (EVFAB): EVFAB0 at 0x6B00 = MUTEX page (page 2) SUB-SLOT 11 — the last
	# sub-slot the digital-peripheral library takes. Same page-2 native shape as
	# I3C0/NFC0/GPIO4/GPIO5/RTC0/PWM0/OW0/DMA0/TRNG0/I2CT0 (sharedBus='native' = "outside
	# the page-0 shim fabric"; the mutex-bank decode is already tightened to sub-slot 0
	# whenever any page-2 sub-slot device is present). Single instance, so nameIndex=''
	# and the registers carry NO index (the PWRCTRL/MUTEX/CLINT class): the RTL block is
	# EVFAB, the instance is evfab0, the registers are EVFCR/EVFSR/...  VECTORLESS:
	# interruptPriority=None (D20 — irq_evfab is a constant '0'), so this knob adds
	# NOTHING to _LIBRARY_TAIL_SPEC, NUM_IRQ_SRCS or _mcuMpIrqFirstVector. clockDomain=
	# 'mclk' names BOTH the bus clock (ClkMem) AND the free-running fabric clock (clk =>
	# mclk, D1/D2 — front end, crossbar, output register, stickies and the action path
	# all on the always-on MCLK). NOT combinationalRead and NOT a CAPTURE_CLOCK slave
	# (D4): a plain raw-strobe active-low en shim (evfab0_sh_en_n <= not
	# shslv_evfab0_en), no falling_edge(EnMemPeriph) pre-latch. ZERO pins. The sub-slot-11
	# decode, the raw-strobe shim, the evfab0 instance AND the producer/consumer tap
	# port-map lines on the existing instances are emitted by mcu_vhd.py under
	# geo['eventFabric'], with every absent source tied '0' (D23).
	m.CreatePeripheral(nameTemplate='EVFAB', nameIndex='', peripheralMemorySlot=None, interruptPriority=None, absoluteBaseAddress=0x6B00, sharedBus='native', clockDomain='mclk', strobeNote='page-2 sub-slot 11; registered read, no bridge, no CAPTURE_CLOCK pre-latch; free-running MCLK fabric in the always-on domain (never gated by PWRCTRL, alive through WFI); vectorless — poll EVFSR, there is no interrupt; a CHTRIG/EVTRIG/W1C write takes effect 3 MCLK after the access opens, so a read issued immediately after one (only possible from a faster master than the shared bus) can see stale state; disable a channel before changing its EVSEL/TASKSEL')	# EVFAB0 (digperiphs EVFAB). native page-2 sub-slot 11; mcu_vhd hand-emits the raw-strobe shim + evfab0 instance + every producer/consumer tap
overlay.call('peripheralInstances', m=m, vals=_overlayVals)	# an overlay's CreatePeripheral calls; page-2 sub-slots 12-15 are free in every public configuration
m.CreatePeripheral(nameTemplate='IRQROUTER', nameIndex='', peripheralMemorySlot=None, interruptPriority=None, absoluteBaseAddress=0x7000, sharedBus='native', clockDomain='mclk', registerSlotCount=_slotCountOverride(524))	# IRQ router at 0x7000 (M11: window page 3; M19: rows + the fixed-address CLAIM block; Stage E rider: through word 523 = 0x782C = INSVCX)



# TODO!!
''' Create the package and power domains '''
# List of necessary pins for a hypothetical /home/mseminario/vestarv/sw/ChipGenerator/latex/MCU-User-Guide44 package: West = {3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23}, South = {28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48} East = {53, 55, 57, 59, 61, 63, 65, 67, 69, 71, 73} North = {78, 80, 82, 84, 86, 88, 90, 92, 94, 96, 98}
# Necessary pin population:
# 3: VDDPST
# 5: VSSPST
# 7: VSS
# 9: VDD
# 11: resetn
# 13: P1.0/CS_FLASH
# 15: P1.1/MISO0
# 17: P1.2/MOSI0
# 19: P1.3/SCK0
# 21: P1.4/TX0
# 23: P1.5/RX0
# 28: P1.6/TRAP
# 30: P1.7/BOOT
# 32: P2.0/CS1
# 34: P2.1/MISO1
# 36: P2.2/MOSI1
# 38: P2.3/SCK1
# 40: P2.4/TX1
# 42: P2.5/RX1
# 44: P2.6/SDA0
# 46: P2.7/SCL0
# 48: P3.0/CS2
# 53: P3.1/MISO2
# 55: P3.2/MOSI2
# 57: P3.3/SCK2
# 59: P3.4/LFXT
# 61: P3.5/HFXT
# 63: P3.6/SH0
# 65: P4.1/T0CMP1
# 67: P4.3/DTP0/T0CAP1
# 69: P4.7/DTP1/T1CAP1
# 71: P5.0/PC0
# 73: P5.2/PC2
# 78: DAC0
# 80: CH3
# 82: Op0Out
# 84: Op0InM
# 86: Op0InP
# 88: ATP0
# 90: CH2
# 92: CH1
# 94: CH0
# 96: AVSS
# 98: AVDD

# G4: CreatePackage + the power domains + the special/analog pins below are a
# PER-MODEL block selected on packageModel (the schema already validates the
# name). The GPIO port STRUCTURE further down (func/altfunc/gating) is SHARED
# across models — only each GPIO bit's package PIN NUMBER differs, so that is a
# per-model table (_GPIO_PKG_PINS) applied to the shared AddGpio rows. Adding a
# model = adding a branch here + a row in that table; the RTL (MCU.vhd/
# MemoryMap) is package-agnostic and stays byte-identical across models.
def _buildPackageData(model):
	'''Build a standalone PackageData (power domains + special/analog pins;
	   NO GPIO) for `model`. ONE source of pin numbers drives both the
	   selected build's m.Package AND web_export's other-model pad tables
	   (GPIO pads are attached separately from the shared GPIO structure).'''
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
		# CQ3b Castalia-Quad QFN64 pinout (cq3b_pin_map.md / cq3b_generator_proposal.md):
		# 16 pins/side, 9x9 mm, 0.5 mm pitch. Numbering W 1-16 (top->bottom),
		# S 17-32 (L->R), E 33-48 (bottom->top), N 49-64 (R->L).
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

		# Two physical pad pairs each for the core (L/R) and IO (T/B) supplies — a
		# multi-pad rail (CQ1 #1); the primary pin is the die-LEFT/BOTTOM pad, the
		# extra pin the die-RIGHT/TOP pad, both on the one rail net.
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

		# Four per-quadrant analog domains (AFE0 top-left ... AFE3 bottom-right,
		# CQ1 #1/#5), each with its own AVDD_h/AVSS_h rail.
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

		# Special / analog signal pins (replaces the Myshkin NC/ATP/CE/RE section).
		package.AddPin(packagePinNumber=9, name='RESETN', ioType='i', powerDomain=digitalIOPowerDomain)
		package.AddPin(packagePinNumber=40, name='POC', ioType='i', powerDomain=digitalIOPowerDomain)
		# 16 electrode pads (PDB3A_G), each in its per-quadrant analog domain; the
		# flat aio[4*h+e] bus, e in {0:WE, 1:RE, 2:RE2, 3:CE} (cq3b_pin_map.md §3/§4).
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
		# Stage G2 (2026-07-22): the CastaliaDP LARGE package — LQFP-100,
		# 14x14 mm body, 0.5 mm pitch, 25 pins/side. User directive 2026-07-22:
		# the QFN-44 is retired as the respin target ("we can have more digital
		# pins"); this model bonds the FULL digital complement — all 48 GPIO
		# (prt1-prt6, first package to bond P5/P6), RESETN, POC — plus 3 core
		# and 3 IO supply pairs (one per digital edge) and a NORTH analog-
		# band (AVDD/AVSS + the sixteen electrode pads) for the U-tile-notch
		# potentiostat drop-in. Numbering follows the house convention: pin 1 at the top of
		# the WEST edge, counterclockwise (W 1-25 top->bottom, S 26-50 L->R,
		# E 51-75 bottom->top, N 76-100 R->L). Leaded LQFP chosen for bring-up
		# friendliness (probing/hand-rework) per the 2026-07-22 user pick.
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

		# Three physical pad pairs per digital rail — one pair on each of the
		# three digital edges (W primary, S/E extras; the multi-pad-rail
		# mechanism from the CQ QFN-64 model).
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

		# ONE analog domain on the NORTH edge, and one is what the die has: the
		# north band is the single PRCUT_G-bracketed analog island (the G0
		# ring-break pair added at the wound-quad cut), with exactly one AVDD/AVSS
		# pair feeding all of it. This is the ONE convention this model does NOT
		# take from castalia-quad-qfn64, which carries four per-quadrant AVDD_h/
		# AVSS_h domains because its four AFE sites sit at four separate die
		# corners with four separate islands. Declaring four domains here would
		# assert an isolation this pad ring does not build (and would cost six more
		# rail balls the north edge does not have), so the sixteen electrode pads
		# below all name this one domain.
		analogPowerDomain = package.AddPowerDomain(
			powerDomainName='Analog',
			positiveVoltage=2.5,
			negativeVoltage=0.0,
			positiveRailPinNumber=76,
			positiveRailPinName='AVDD',
			negativeRailPinNumber=77,
			negativeRailPinName='AVSS'
		)

		# Special pins (both bonded for the first time on a Castalia package:
		# the QFN-44 model has no POC ball).
		package.AddPin(packagePinNumber=1, name='RESETN', ioType='i', powerDomain=digitalIOPowerDomain)
		package.AddPin(packagePinNumber=2, name='POC', ioType='i', powerDomain=digitalIOPowerDomain)

		# ---- the sixteen electrode pads (USER DECISION, 2026-08-17) ----------
		# The LQFP-100 is the shipped default package, and a Castalia that bonds no
		# electrodes is a monitoring chip with nothing to monitor: the whole-chip
		# flat figure loses its analog row, and the analog chapter it points at
		# never renders. This band bonds them, on the SAME naming and grouping
		# convention as castalia-quad-qfn64 above — four measurement sites, four
		# pads each on the flat aio[4*h+e] bus, e in {0:WE, 1:RE, 2:RE2, 3:CE}:
		# WE_h the working electrode, RE_h the reference, CE_h the counter, and
		# RE2_h the second sense electrode of the optional four-terminal (Kelvin)
		# configuration.
		#
		# WHERE THEY LAND, AND WHAT THEY COST. The north edge (76-100) is the only
		# place they may go: it is the PRCUT-isolated analog island, and the other
		# three edges have no analog supply at all. Its free pins were the eight
		# ARSV0-7 reserve pads (78-85) plus fifteen NC balls (86-100) — twenty-
		# three free, sixteen needed. The reserve band is spent FIRST and by its
		# own charter: ARSV0-7 was declared as "uncommitted analog pads for the
		# notch drop-in (electrode/test points; unconnected until an analog
		# respin)", and these sixteen pads ARE that drop-in — the reserve is
		# discharged, not stolen. Nothing with a function was displaced: no GPIO,
		# no supply, no JTAG ball moves, and seven NC balls (94-100) stay as the
		# new north spare. Every pad below is analog-domain and bonded on the
		# island side of the PRCUT ring breaks.
		#
		# THIS IS INTENT, NOT AS-BUILT, and the manual says so: `package
		# .preliminary' (default true) prints the Preliminary banner over
		# Section \ref{s:pinsConfig} — "the bonding shown here is the planned
		# assignment, not a confirmed bond-out". The as-built ring
		# (innovus/common/MCU_castalia/tcl/chip_top_wound_padlists.tcl, 77 pads)
		# carries PAD_ARSV0-7 and nothing on 86-100; renaming those eight and
		# adding eight more PDB3A_G instances in the north band is work for the
		# AFE integration programme, exactly as castalia-quad-qfn64 declared its
		# sixteen before any analog IP existed. The model documents the pinout the
		# chip is being built toward; it does not claim the metal is drawn.
		#
		# ORDER WITHIN A SITE follows the QFN-64 model: the current-carrying pair
		# (CE, WE) abut, then the sense pair (RE, RE2), so a site's four pads are
		# four adjacent balls and a probe card lands on one contiguous block.
		# The 16-pad RE2 layout: four electrodes per site on 78-93, 94-100 NC.
		_lqfpElectrodes = []
		for _s in range(4):
			_p0 = 78 + 4 * _s
			_lqfpElectrodes += [(_p0, 'CE_' + str(_s)), (_p0 + 1, 'WE_' + str(_s)),
				(_p0 + 2, 'RE_' + str(_s)), (_p0 + 3, 'RE2_' + str(_s))]
		for (_epn, _enm) in _lqfpElectrodes:
			package.AddPin(packagePinNumber=_epn, name=_enm, ioType='io', powerDomain=analogPowerDomain)

		# D3 (2026-08-06, R-DD4(2) -- USER): the JTAG debug port takes five of the
		# NC balls. 47=TCK, 48=TMS, 49=TDI, 50=TDO on the SOUTH edge (pins 26-50)
		# and 51=TRSTn at the foot of the EAST edge (51-75) -- the NC grouping's
		# own edges, chosen so nothing lands on the NORTH band, which is the
		# PRCUT-isolated analog island with no digital IO supply. The die-side
		# instances and their pull-cell types live in
		# innovus/common/MCU_castalia/in/MCU_castalia.v (TCK/TRSTn pull-DOWN,
		# TMS/TDI/TDO pull-UP); this model is the PACKAGE authority only.
		package.AddPin(packagePinNumber=47, name='TCK', ioType='i', powerDomain=digitalIOPowerDomain)
		package.AddPin(packagePinNumber=48, name='TMS', ioType='i', powerDomain=digitalIOPowerDomain)
		package.AddPin(packagePinNumber=49, name='TDI', ioType='i', powerDomain=digitalIOPowerDomain)
		package.AddPin(packagePinNumber=50, name='TDO', ioType='o', powerDomain=digitalIOPowerDomain)
		package.AddPin(packagePinNumber=51, name='TRSTn', ioType='i', powerDomain=digitalIOPowerDomain)

		# Explicit NC balls (every remaining pin; Myshkin-QFN44 precedent).
		# 47-51 LEFT this list at D3 -- see the JTAG block above.
		# 78-93 LEFT this list at the electrode block above (they were 78-85 ARSV
		# and 86-93 NC); 94-100 are the north band's remaining spare.
		for _ncp in ([23, 24, 25] + [26] + [72, 73, 74, 75] + list(range(94, 101))):
			package.AddPin(packagePinNumber=_ncp, name='NC', ioType='', noConnect=True)

	else:
		package = None
	# The overlay gets the last word on the ball map: it BUILDS a model it
	# declared itself (nothing above matched), and it may RE-CUT a public
	# model's analog band when a block only it knows about changes which pads
	# the die carries. package.Pins is a plain list, so a re-cut is a filter
	# plus its own AddPin calls; the cross-check against its die-row file lives
	# with the overlay. Returns the package to use, or None for a model nobody
	# implements.
	package = overlay.call('packageData', default=package, model=model, package=package,
		PackageData=PackageData, vals=_overlayVals)
	if package is None:
		raise Exception('package model "' + model + '" is declared but not implemented')
	return package


m.Package = _buildPackageData(packageModel)


def _checkDebugTransportBonded(_pkg, _model, _dbgOn):
	'''GATE (2026-08-16, added with the debug.enable default flip): a chip that
	   instantiates the JTAG DTM must be on a package that BONDS the TAP.

	   THE DEFECT THIS EXISTS FOR, measured before the flip: `debug.enable` is
	   the only JTAG knob (D3 rides it), and turning it on emits the five
	   tck/tms/tdi/tdo/trstn ports on the MCU entity and instantiates dtm0 --
	   on EVERY package model, because the knob and the pad ring never spoke.
	   Built on castalia-quad-qfn64 (all 64 balls committed, no NC band) the
	   run SUCCEEDS and PadRing.json simply contains no TCK and no TRSTn. The
	   result is a working TAP with no way to reach it, and a TRM that
	   documents a debug port the package cannot expose -- the same
	   silent-split class check_config_defaults.py was written for, one layer
	   out. Nothing caught it; this does.

	   FAIL LOUDLY, never warn: a warning here is a tape-out that ships an
	   unreachable debug port.'''
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

# Per-model GPIO bit -> package pin number (objGPIOk, bit b). None = unbonded
# (kept in the RTL/register map, but no package ball — the netlist ties the
# port bit). objGPIO0 = PadRing "P0" = RTL prt1 (boot flash); objGPIOk = prt(k+1).
# myshkin-qfn44 reproduces the original QFN-44 ring byte-for-byte; the CQ model
# is cq3b_pin_map.md §5, with objGPIO2.b0 (GPIO16/T0CMP0) and objGPIO2.b4
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
	# Stage G2 LQFP-100: the FIRST model to bond all six ports (48 GPIO).
	# W: P0 5-12, P1 15-22 · S: P2 27-34, P3 37-44 · E: P5 52-59, P6 62-69
	# (ascending bit -> ascending pin on every port).
	'castalia-lqfp100': {
		(0, 0): 5, (0, 1): 6, (0, 2): 7, (0, 3): 8, (0, 4): 9, (0, 5): 10, (0, 6): 11, (0, 7): 12,
		(1, 0): 15, (1, 1): 16, (1, 2): 17, (1, 3): 18, (1, 4): 19, (1, 5): 20, (1, 6): 21, (1, 7): 22,
		(2, 0): 27, (2, 1): 28, (2, 2): 29, (2, 3): 30, (2, 4): 31, (2, 5): 32, (2, 6): 33, (2, 7): 34,
		(3, 0): 37, (3, 1): 38, (3, 2): 39, (3, 3): 40, (3, 4): 41, (3, 5): 42, (3, 6): 43, (3, 7): 44,
		(4, 0): 52, (4, 1): 53, (4, 2): 54, (4, 3): 55, (4, 4): 56, (4, 5): 57, (4, 6): 58, (4, 7): 59,
		(5, 0): 62, (5, 1): 63, (5, 2): 64, (5, 3): 65, (5, 4): 66, (5, 5): 67, (5, 6): 68, (5, 7): 69,
	},
}
# A model an overlay declared brings its own ball map; the overlay adds it here
# so the lookup below stays one table.
overlay.call('gpioPinMap', maps=_GPIO_PKG_PINS)
def _gpioPkgPin(gpioIndex, bitNumber):
	'''Package pin number for objGPIO<gpioIndex> bit <bitNumber> under the
	   selected model, or None (unbonded — Peripheral.AddGpio skips the pad).'''
	return _GPIO_PKG_PINS[packageModel].get((gpioIndex, bitNumber))





''' Add pins to the GPIO ports (and optionally change the GPIO port sizes) '''
''' WARNING: Look at the documentation for GpioConfigurator.__init__() for important instructions on how to use the function, especially concerning the funcIOType argument '''
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

GPIO1.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO8', funcName=('CS1' if spi1Present else ''), funcIOType=('i' if spi1Present else ''),		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('SPI1 chip select' if spi1Present else 'General-purpose I/O (ex-CS1; SPI1 dropped by this configuration)'), altFuncs=[(1, 'T0CMP0', 'o', 'TIMER0 Compare 0 (alternate location)')]), packagePinNumber=_gpioPkgPin(1, 0)) # necessary; primary gated with SPI1 (G1b), AF1 is a TIMER0 source
GPIO1.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO9', funcName=('MISO1' if spi1Present else ''), funcIOType=('io' if spi1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('SPI1 Master In Slave Out' if spi1Present else 'General-purpose I/O (ex-MISO1; SPI1 dropped by this configuration)'), altFuncs=[(1, 'T0CMP1', 'o', 'TIMER0 Compare 1 (alternate location)')]), packagePinNumber=_gpioPkgPin(1, 1)) # necessary; primary gated with SPI1 (G1b), AF1 is a TIMER0 source
GPIO1.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO10', funcName=('MOSI1' if spi1Present else ''), funcIOType=('io' if spi1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('SPI1 Master Out Slave In' if spi1Present else 'General-purpose I/O (ex-MOSI1; SPI1 dropped by this configuration)'), altFuncs=([(1, 'T1CMP0', 'o', 'TIMER1 Compare 0 (alternate location)')] if timer1Present else [])), packagePinNumber=_gpioPkgPin(1, 2)) # necessary; primary gated with SPI1, AF1 with TIMER1 (G1b)
GPIO1.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO11', funcName=('SCK1' if spi1Present else ''), funcIOType=('io' if spi1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('SPI1 serial clock' if spi1Present else 'General-purpose I/O (ex-SCK1; SPI1 dropped by this configuration)'), altFuncs=([(1, 'T1CMP1', 'o', 'TIMER1 Compare 1 (alternate location)')] if timer1Present else [])), packagePinNumber=_gpioPkgPin(1, 3)) # necessary; primary gated with SPI1, AF1 with TIMER1 (G1b)
GPIO1.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO12', funcName='TX0', funcIOType='o',		rstOUT=0, rstDIR=1, rstSEL=1, rstREN=0, description='UART0 transmitter', altFuncs=([(1, 'SDA1', 'io', 'I2C1 serial data (second alternate location)')] if i2c1Present else [])), packagePinNumber=_gpioPkgPin(1, 4)) # necessary; rstDIR=1 matches the RTL (RstValP2DIR=0x10); AF1 gated with I2C1 (pin-mux v2)
GPIO1.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO13', funcName='RX0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=1, rstREN=0, description='UART0 receiver', altFuncs=([(1, 'SCL1', 'io', 'I2C1 serial clock (second alternate location)')] if i2c1Present else [])), packagePinNumber=_gpioPkgPin(1, 5)) # necessary; AF1 gated with I2C1 (pin-mux v2)
GPIO1.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO14', funcName=('TX1' if uart1Present else ''), funcIOType=('o' if uart1Present else ''),		rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('UART1 transmitter' if uart1Present else 'General-purpose I/O (ex-TX1; UART1 dropped by this configuration)'), altFuncs=[(1, 'SDA0', 'io', 'I2C0 serial data (alternate location)')]), packagePinNumber=_gpioPkgPin(1, 6)) # necessary; primary gated with UART1 (G1b), AF1 is an I2C0 source
GPIO1.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO15', funcName=('RX1' if uart1Present else ''), funcIOType=('io' if uart1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('UART1 receiver' if uart1Present else 'General-purpose I/O (ex-RX1; UART1 dropped by this configuration)'), altFuncs=[(1, 'SCL0', 'io', 'I2C0 serial clock (alternate location)')]), packagePinNumber=_gpioPkgPin(1, 7)) # necessary; primary gated with UART1 (G1b), AF1 is an I2C0 source

# GPIO2 (P3.0-P3.7)
GPIO2.ChangeGPIOPortSize(8)

GPIO2.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO16', funcName='T0CMP0', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Compare 0', altFuncs=([(1, 'TX1', 'o', 'UART1 transmitter (alternate location)')] if uart1Present else [])), packagePinNumber=_gpioPkgPin(2, 0)) # necessary; AF1 gated with UART1 (G1b)
GPIO2.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO17', funcName='T0CMP1', funcIOType='o',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Compare 1', altFuncs=([(1, 'RX1', 'io', 'UART1 receiver (alternate location)')] if uart1Present else [])), packagePinNumber=_gpioPkgPin(2, 1)) # necessary; AF1 gated with UART1 (G1b)
GPIO2.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO18', funcName='T0CAP0', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Capture 0', altFuncs=([(1, 'SDA1', 'io', 'I2C1 serial data (alternate location)')] if i2c1Present else [])), packagePinNumber=_gpioPkgPin(2, 2)) # necessary; AF1 gated with I2C1 (G1a)
GPIO2.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO19', funcName='T0CAP1', funcIOType='i',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='TIMER0 Capture 1', altFuncs=([(1, 'SCL1', 'io', 'I2C1 serial clock (alternate location)')] if i2c1Present else [])), packagePinNumber=_gpioPkgPin(2, 3)) # necessary; AF1 gated with I2C1 (G1a)
GPIO2.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO20', funcName=('T1CMP0' if timer1Present else ''), funcIOType=('o' if timer1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('TIMER1 Compare 0' if timer1Present else 'General-purpose I/O (ex-T1CMP0; TIMER1 dropped by this configuration)'), altFuncs=[(1, 'TX0', 'o', 'UART0 transmitter (alternate location)')]), packagePinNumber=_gpioPkgPin(2, 4)) # necessary; primary gated with TIMER1 (G1b), AF1 is a UART0 source
GPIO2.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO21', funcName=('T1CMP1' if timer1Present else ''), funcIOType=('o' if timer1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('TIMER1 Compare 1' if timer1Present else 'General-purpose I/O (ex-T1CMP1; TIMER1 dropped by this configuration)'), altFuncs=[(1, 'RX0', 'io', 'UART0 receiver (alternate location)')]), packagePinNumber=_gpioPkgPin(2, 5)) # necessary; primary gated with TIMER1 (G1b), AF1 is a UART0 source
GPIO2.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO22', funcName=('T1CAP0' if timer1Present else ''), funcIOType=('i' if timer1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('TIMER1 Capture 0' if timer1Present else 'General-purpose I/O (ex-T1CAP0; TIMER1 dropped by this configuration)'), altFuncs=[(1, 'SDA0', 'io', 'I2C0 serial data (second alternate location)')]), packagePinNumber=_gpioPkgPin(2, 6)) # necessary; primary gated with TIMER1 (G1b), AF1 is an I2C0 source (pin-mux v2)
GPIO2.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO23', funcName=('T1CAP1' if timer1Present else ''), funcIOType=('i' if timer1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('TIMER1 Capture 1' if timer1Present else 'General-purpose I/O (ex-T1CAP1; TIMER1 dropped by this configuration)'), altFuncs=[(1, 'SCL0', 'io', 'I2C0 serial clock (second alternate location)')]), packagePinNumber=_gpioPkgPin(2, 7)) # necessary; primary gated with TIMER1 (G1b), AF1 is an I2C0 source (pin-mux v2)

# GPIO3 (P4.0-P4.7)
GPIO3.ChangeGPIOPortSize(8)

GPIO3.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO24', funcName='SDA0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='I2C0 serial data', altFuncs=[(1, 'T0CAP0', 'i', 'TIMER0 Capture 0 (alternate location)')]), packagePinNumber=_gpioPkgPin(3, 0)) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO25', funcName='SCL0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='I2C0 serial clock', altFuncs=[(1, 'T0CAP1', 'i', 'TIMER0 Capture 1 (alternate location)')]), packagePinNumber=_gpioPkgPin(3, 1)) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO26', funcName=('SDA1' if i2c1Present else ''), funcIOType=('io' if i2c1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('I2C1 serial data' if i2c1Present else 'General-purpose I/O (ex-SDA1; I2C1 dropped by this configuration)'), altFuncs=([(1, 'T1CAP0', 'i', 'TIMER1 Capture 0 (alternate location)')] if timer1Present else [])), packagePinNumber=_gpioPkgPin(3, 2)) # necessary; primary gated with I2C1 (G1a), AF1 with TIMER1 (G1b)
GPIO3.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO27', funcName=('SCL1' if i2c1Present else ''), funcIOType=('io' if i2c1Present else ''),	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description=('I2C1 serial clock' if i2c1Present else 'General-purpose I/O (ex-SCL1; I2C1 dropped by this configuration)'), altFuncs=([(1, 'T1CAP1', 'i', 'TIMER1 Capture 1 (alternate location)')] if timer1Present else [])), packagePinNumber=_gpioPkgPin(3, 3)) # necessary; primary gated with I2C1 (G1a), AF1 with TIMER1 (G1b)
GPIO3.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO28', funcName='DTP0', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Digital test port 0', altFuncs=[(1, 'T0CMP0', 'o', 'TIMER0 Compare 0 (alternate location)')]), packagePinNumber=_gpioPkgPin(3, 4)) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO29', funcName='DTP1', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Digital test port 1', altFuncs=[(1, 'T0CMP1', 'o', 'TIMER0 Compare 1 (alternate location)')]), packagePinNumber=_gpioPkgPin(3, 5)) # necessary
GPIO3.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO30', funcName='DTP2', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Digital test port 2', altFuncs=([(1, 'T1CMP0', 'o', 'TIMER1 Compare 0 (alternate location)')] if timer1Present else [])), packagePinNumber=_gpioPkgPin(3, 6)) # necessary; AF1 gated with TIMER1 (G1b)
GPIO3.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO31', funcName='DTP3', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=(1 if onewirePresent else 0), description=('Digital test port 3 (AF2 = OW0 1-Wire DQ, open-drain, when OneWire present)' if onewirePresent else 'Digital test port 3'), altFuncs=([(1, 'T1CMP1', 'o', 'TIMER1 Compare 1 (alternate location)')] if timer1Present else [])), packagePinNumber=_gpioPkgPin(3, 7)) # necessary; AF1 gated with TIMER1 (G1b); digperiphs #5 re-pin: AF2 spread slot carries OW0's open-drain DQ when OneWire present (pull enabled at reset)

# GPIO4 (P5.0-P5.7) — digperiphs Mission B. Every pin's PRIMARY (AF0) is plain
# general-purpose I/O (funcName=''); AF1 carries the QSPI0 (P5.0-5) and I3C0
# (P5.6/7) pin functions ONLY when those controllers are present (Hi-Z otherwise).
# Pad names continue the numeric GPIOxx sequence (GPIO32+) to avoid colliding with
# GPIO0's bit-4/5 pad names (LFXT/HFXT). Package pins are MODEL-DRIVEN since G2
# (2026-07-22): _gpioPkgPin returns None on the QFN-44/QFN-64 models (unbonded,
# the pre-G2 behavior) and real balls on castalia-lqfp100 (E 52-59).
GPIO4.ChangeGPIOPortSize(8)
GPIO4.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO32', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = QSPI0 serial clock when QSPI present)', altFuncs=([(1, 'QSPI_SCK', 'o', 'QSPI0 serial clock (alt plane AF1)')] if qspiPresent else [])), packagePinNumber=_gpioPkgPin(4, 0)) # AF1 gated with QSPI0
GPIO4.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO33', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = QSPI0 chip select when QSPI present)', altFuncs=([(1, 'QSPI_CS', 'o', 'QSPI0 chip select (alt plane AF1)')] if qspiPresent else [])), packagePinNumber=_gpioPkgPin(4, 1)) # AF1 gated with QSPI0
GPIO4.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO34', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = QSPI0 IO0 when QSPI present)', altFuncs=([(1, 'QSPI_IO0', 'io', 'QSPI0 quad data 0 (alt plane AF1)')] if qspiPresent else [])), packagePinNumber=_gpioPkgPin(4, 2)) # AF1 gated with QSPI0
GPIO4.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO35', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = QSPI0 IO1 when QSPI present)', altFuncs=([(1, 'QSPI_IO1', 'io', 'QSPI0 quad data 1 (alt plane AF1)')] if qspiPresent else [])), packagePinNumber=_gpioPkgPin(4, 3)) # AF1 gated with QSPI0
GPIO4.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO36', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = QSPI0 IO2 when QSPI present)', altFuncs=([(1, 'QSPI_IO2', 'io', 'QSPI0 quad data 2 (alt plane AF1)')] if qspiPresent else [])), packagePinNumber=_gpioPkgPin(4, 4)) # AF1 gated with QSPI0
GPIO4.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO37', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = QSPI0 IO3 when QSPI present)', altFuncs=([(1, 'QSPI_IO3', 'io', 'QSPI0 quad data 3 (alt plane AF1)')] if qspiPresent else [])), packagePinNumber=_gpioPkgPin(4, 5)) # AF1 gated with QSPI0
GPIO4.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO38', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=(1 if i3cPresent else 0), description='General-purpose I/O (AF1 = I3C0 SDA, open-drain, when I3C present)', altFuncs=([(1, 'I3C_SDA', 'io', 'I3C0 serial data, open-drain (alt plane AF1)')] if i3cPresent else [])), packagePinNumber=_gpioPkgPin(4, 6)) # AF1 gated with I3C0; PxREN pull-up enabled at reset when I3C present
GPIO4.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO39', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=(1 if i3cPresent else 0), description='General-purpose I/O (AF1 = I3C0 SCL, open-drain, when I3C present)', altFuncs=([(1, 'I3C_SCL', 'io', 'I3C0 serial clock, open-drain (alt plane AF1)')] if i3cPresent else [])), packagePinNumber=_gpioPkgPin(4, 7)) # AF1 gated with I3C0; PxREN pull-up enabled at reset when I3C present

# GPIO5 (P6.0-P6.7) — digperiphs Mission B. AF1 carries the NFC0 off-die digital-AFE
# interface (P6.0-5) when NFC is present; P6.6/7 are always spare plain GPIO. P6.0's
# reset AFS selects AF1 (RstValP6AFS below) so the off-die rf_clk arrives without a
# runtime mux switch (D5). Package pins model-driven like GPIO4 (LQFP-100: E 62-69).
GPIO5.ChangeGPIOPortSize(8)
GPIO5.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO40', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, rstAFS=(1 if nfcPresent else 0), description='General-purpose I/O (AF1 = NFC0 off-die carrier clock input when NFC present)', altFuncs=([(1, 'NFC_RF_CLK', 'i', 'NFC0 off-die RF carrier clock (alt plane AF1)')] if nfcPresent else [])), packagePinNumber=_gpioPkgPin(5, 0)) # AF1 gated with NFC0; reset AFS = AF1 when NFC is present (D5), which is the RTL's RstValP6AFS below -- the pin table and the register index now print the same value (was R3 open item 2)
GPIO5.AddGpio(GpioConfigurator(bitNumber=1, primaryName='GPIO41', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = NFC0 RX envelope input when NFC present)', altFuncs=([(1, 'NFC_RF_RX', 'i', 'NFC0 off-die RX Miller envelope (alt plane AF1)')] if nfcPresent else [])), packagePinNumber=_gpioPkgPin(5, 1)) # AF1 gated with NFC0
GPIO5.AddGpio(GpioConfigurator(bitNumber=2, primaryName='GPIO42', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = NFC0 field-detect input when NFC present)', altFuncs=([(1, 'NFC_FIELD_DETECT', 'i', 'NFC0 off-die RF field detect (alt plane AF1)')] if nfcPresent else [])), packagePinNumber=_gpioPkgPin(5, 2)) # AF1 gated with NFC0
GPIO5.AddGpio(GpioConfigurator(bitNumber=3, primaryName='GPIO43', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = NFC0 TX modulation output when NFC present)', altFuncs=([(1, 'NFC_RF_TXMOD', 'o', 'NFC0 off-die TX load modulation (alt plane AF1)')] if nfcPresent else [])), packagePinNumber=_gpioPkgPin(5, 3)) # AF1 gated with NFC0
GPIO5.AddGpio(GpioConfigurator(bitNumber=4, primaryName='GPIO44', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = NFC0 TX enable output when NFC present)', altFuncs=([(1, 'NFC_RF_TX_EN', 'o', 'NFC0 off-die TX enable (alt plane AF1)')] if nfcPresent else [])), packagePinNumber=_gpioPkgPin(5, 4)) # AF1 gated with NFC0
GPIO5.AddGpio(GpioConfigurator(bitNumber=5, primaryName='GPIO45', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = NFC0 AFE enable output when NFC present)', altFuncs=([(1, 'NFC_AFE_EN', 'o', 'NFC0 off-die AFE enable (alt plane AF1)')] if nfcPresent else [])), packagePinNumber=_gpioPkgPin(5, 5)) # AF1 gated with NFC0
GPIO5.AddGpio(GpioConfigurator(bitNumber=6, primaryName='GPIO46', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=(1 if fieldPowerPresent else 0), description=('General-purpose I/O; also the DP-S3 harvested-boot strap (direct PWRCTRL tap, always readable; pull-down at reset = NORMAL/SPI boot when unconnected, strap high = harvested boot)' if fieldPowerPresent else 'General-purpose I/O (spare)'), altFuncs=[]), packagePinNumber=_gpioPkgPin(5, 6)) # DP-S3: harvested-boot strap direct tap when fieldPower, pull-down at reset (OW0's DQ left this pin at the Stage H re-pin -- it is P4.7/GPIO31 AF2 now)
GPIO5.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO47', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=(1 if fieldPowerPresent else 0), description=('General-purpose I/O; also the DP-S3 PGOOD supply-supervisor input (direct PWRCTRL tap, always readable; pull-down at reset = power-not-good when unconnected)' if fieldPowerPresent else 'General-purpose I/O (spare)'), altFuncs=[]), packagePinNumber=_gpioPkgPin(5, 7)) # DP-S3: PGOOD direct tap when fieldPower (pull-down at reset), else spare plain GPIO


# --- GPIO alternate-function output-spread (v1): fill AF planes AF1..AF7 with the
# shared timer/UART/SPI OUTPUT pool, fanned across all four ports so each output is
# reachable on ~24 pins (RPi-style placement flexibility). Dormant at reset (PxAFS=0
# selects AF0). The RTL wires these with LITERAL pin indices, so no pnum_* reverse
# constants are emitted; the spread altFuncs are flagged FromSpread and skipped by the
# altFunc<->pnum cross-check in ChipGenerator.generateMemoryMapVHD(). They still drive
# the TRM AF matrix table and the location-qualified C-header AF defines.
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
# digperiphs #5 (PWM, A7): pwm_out(0)/(1) REPLACE two REDUNDANT timer-compare spread
# copies — the pin-mux-v2 replaced-spread-slot precedent (P4.5 AF2 RX0-was-TX1 /
# P4.6 AF7 MISO1-was-TX0 above). Chosen slots: P2.2 AF2 (was the redundant T0CMP0
# spread copy) -> PWM0, and P2.3 AF2 (was T0CMP1) -> PWM1. GPIO index 2 = port P2;
# these two pins sit right beside the T0CMP0/T0CMP1 AF0 primaries on P2.0/P2.1
# (teaching coherence, D20 pin class). REDUNDANCY PROOF: T0CMP0 and T0CMP1 each remain
# spread onto ~20 other pins, so removing ONE copy of each keeps both timer compares
# fully reachable (pure redundancy — the A7 constraint). Knob-gated: with PWM OFF the
# two slots keep their original T0CMP0/T0CMP1 rows => byte-identical (D17); with PWM ON
# they carry PWM0/PWM1 (SPREAD_SIG in mcu_vhd.py owns the pwm0/pwm1 RTL spellings; the
# scalar aliases pwm0_out/pwm1_out are emitted in the gated PWM instance region).
if pwmPresent:
	_GPIO_AF_SPREAD[(2, 2)] = [(2, 'PWM0', 'o', 'PWM0 channel 0 output (replaces the redundant T0CMP0 spread copy; alt plane AF2)')] + _GPIO_AF_SPREAD[(2, 2)][1:]
	_GPIO_AF_SPREAD[(2, 3)] = [(2, 'PWM1', 'o', 'PWM0 channel 1 output (replaces the redundant T0CMP1 spread copy; alt plane AF2)')] + _GPIO_AF_SPREAD[(2, 3)][1:]
# digperiphs #5 RE-PIN (Stage H, 2026-07-26): OW0's open-drain DQ REPLACES a
# REDUNDANT timer-compare spread copy instead of owning an AF1 plane — the same
# pin-mux-v2 replaced-spread-slot precedent as PWM above (and as P4.5 AF2 RX0-was-TX1
# / P4.6 AF7 MISO1-was-TX0). Chosen slot: P4.7 AF2 (was the redundant T0CMP1 spread
# copy) -> OW_DQ. GPIO index 3 = port P4; P4.7 is DTP3, the last of the digital
# test-port pins, and it sits with the other two v2 io completions on P4.5/P4.6
# (teaching coherence). REDUNDANCY PROOF: T0CMP1 keeps its AF0 PRIMARY on
# P3.1/GPIO17, its AF1 relocations on P2.1 and P4.5, and 26 further spread copies
# across the four ports, so removing THIS one copy leaves TIMER0 compare 1 fully
# reachable (pure redundancy — the A7 constraint). This slot is an io CLASS entry
# (bidirectional, like RX0/MISO1): the spread emitter drives the pad's AF2
# out/dir/ren planes from ow0_dq_out/ow0_dq_dir/ow0_dq_ren (SPREAD_SIG in
# mcu_vhd.py owns the RTL spellings), and the DQ pad INPUT is tapped by a
# fixed-priority AFS-keyed mux emitted with the gated OW0 instance. Knob-gated:
# with OneWire OFF the slot keeps its original T0CMP1 row => byte-identical.
if onewirePresent:
	_GPIO_AF_SPREAD[(3, 7)] = [(2, 'OW_DQ', 'io', 'OW0 1-Wire DQ, open-drain (replaces the redundant T0CMP1 spread copy; alt plane AF2)')] + _GPIO_AF_SPREAD[(3, 7)][1:]
# G1b: a dropped second instance's outputs leave the spread pool BEFORE the
# map is applied — its plane slots go unassigned everywhere (the RTL emitter
# reads the surviving FromSpread altFuncs and wires '0' for the gaps).
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


''' MCU_MP drop-in compatibility facts (RTL-generation track Phase 1, 2026-07-04) '''
# Everything below is either transcribed verbatim from hdl/common/MemoryMap.vhd (the RTL
# wins; values were NOT invented) or maps the RTL's constant-name spelling onto facts the
# description already knows. Consumed ONLY by ChipGenerator.generateMemoryMapVHD(), which
# emits an "MCU_MP compatibility" section making out/hdl/MemoryMap.vhd a drop-in
# replacement for the hand-written RTL package. Nothing here affects the TRM, the C/asm
# headers, or the linker scripts.

# The RTL spells some legacy-slot constant names differently than the description's
# peripheral names (trailing instance digit): PeriphSlotSystem0, PeriphSlotNPU0, ...
_mcuMpPeriphSlotSpelling = {
	'SYSTEM': 'System0',
	'NPU': 'NPU0',
}

# Memory block slot assignments (hdl/common/MemoryMap.vhd "Memory Block Memory Slot
# Assignments"; these are decoder block indices, not address-region numbers)
_mcuMpMemSlots = [
	('MemSlotROM', 0, 'base address = 0x00000'),
	('MemSlotRAM0', 1, 'base address = 0x08000'),
	('MemSlotRAM1', 2, 'base address = 0x0C000'),
	('MemSlotPeriph', 4, 'base address = 0x04000'),
]

# GPIO register-level logic helpers (fixed by the GPIO register spec; the RTL uses them
# to compose reset values)
_mcuMpGpioHelpers = [
	('gpio_dir_out', '1', 'GPIO output direction'),
	('gpio_dir_in', '0', 'GPIO input direction'),
	('gpio_ren_en', '1', 'GPIO resistor enable'),
	('gpio_ren_dis', '0', 'GPIO resistor disable'),
	('gpio_out_high', '1', 'GPIO output high'),
	('gpio_out_low', '0', 'GPIO output low'),
]

# SYSTEM register slots in the RTL's RegSlotSYS_* spelling. The slot numbers are
# transcribed from the RTL (which SYSTEM.vhd decodes against). Third element = the
# corresponding register in this description, for a consistency cross-check.
# ~~KNOWN DISCREPANCY~~ FIXED (G5a, 2026-07-11): the description now matches the RTL's
# WDT_PASS=12/WDT_CR=13/WDT_SR=14 (it had WDTCR=12/WDTSR=13/WDTPASS=14 since Myshkin — the
# TRM and MemoryMap.h documented the WDT registers WRONG; software/ was audited first:
# the only WDT users go through myshkin{,_s}.h, which always had the RTL order).
_mcuMpSysRegSlots = [
	('RegSlotSYS_CLK_CR', 0, 'SYSCLKCR'),
	('RegSlotSYS_CLK_DIV_CR', 1, 'CLKDIVCR'),
	('RegSlotSYS_BLOCK_PWR', 2, 'BLOCKPWR'),
	('RegSlotSYS_CRC_DATA', 3, 'CRCDATA'),
	('RegSlotSYS_CRC_STATE', 4, 'CRCSTATE'),
	# M19: slots 5-11 (SYS_IRQ_ENL/M/U, PRIL/M/U, CR) are RETIRED — reserved
	# gaps; routing/masking lives in the IRQROUTER rows.
	('RegSlotSYS_WDT_PASS', 12, 'WDTPASS'),
	('RegSlotSYS_WDT_CR', 13, 'WDTCR'),
	('RegSlotSYS_WDT_SR', 14, 'WDTSR'),
	('RegSlotSYS_WDT_VAL', 15, 'WDTVAL'),
	('RegSlotDCO0_BIAS', 16, 'DCO0BIAS'),
	('RegSlotDCO1_BIAS', 17, 'DCO1BIAS'),
]

# NPU register slots in the RTL's MmrAddrNPU* spelling; values come from the
# description's NPU register slots (they agree with the RTL)
_mcuMpNpuMmrAddr = [
	('MmrAddrNPUCR', 'NPUCR'),
	('MmrAddrNPUIVSAR', 'NPUIVSAR'),
	('MmrAddrNPUWVSAR', 'NPUWVSAR'),
	('MmrAddrNPUOVSAR', 'NPUOVSAR'),
	('MmrAddrNPUSR', 'NPUSR'),	# DP-SG think-done rider (slot 4)
	('MmrAddrNPUCFG1', 'NPUCFG1'),	# P4.1 family per-mode config (slot 5)
	('MmrAddrNPUCFG2', 'NPUCFG2'),	# P4.1 family per-mode config (slot 6)
]

# Per-vector interrupt names (IRQB_*), copied verbatim from the RTL. List index = vector
# number. The description only knows each peripheral's FIRST vector (interruptPriority);
# the generator cross-checks those against this list via _mcuMpIrqFirstVector and fails
# the build on disagreement.
_mcuMpIrqVectors = [('IRQB_SYS_WDT', 'Watchdog Timer Interrupt')]
for _b in range(8):
	_mcuMpIrqVectors.append(('IRQB_GPIO0_B' + str(_b), 'GPIO0 Bit ' + str(_b) + ' Interrupt'))
# G1b: dropped second instances leave RSVD gaps — the NUMBERING IS FROZEN
# (same rule as the G1a I2C1 gate below: the RTL ties RSVD vectors low)
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
# Vectors 55/56 (ex-AFE0 / ex-SARADC0 gaps): QSPI0's two sources when the QSPI
# controller occupies slot 12, else reserved (numbering FROZEN either way).
if qspiPresent:
	_mcuMpIrqVectors.append(('IRQB_QSPI0_TC', 'QSPI0 Transfer Complete Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_QSPI0_RXF', 'QSPI0 Receive-Register Full Interrupt'))
else:
	_mcuMpIrqVectors.append(('IRQB_RSVD55', 'Reserved (vector 55; formerly AFE0 Receive Complete)'))
	_mcuMpIrqVectors.append(('IRQB_RSVD56', 'Reserved (vector 56; formerly SARADC0 Conversion Complete)'))
# I2C vector suffixes are lowercase in the RTL except STR — copied verbatim.
# G1a: with I2C1 dropped its 13 vectors become RSVD gaps — the NUMBERING IS
# FROZEN (IVT slots, CLINT vectors 83/84 and every other number stay put; the
# RTL ties RSVD vectors low exactly like the ex-AFE/SARADC gaps above).
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
# M5b: real CLINT (hdl/common/clint.vhd, shared window 0x11000); per-hart msip/mtip
_mcuMpIrqVectors.append(('IRQB_CLINT_MSIP', 'CLINT software interrupt (IPI)'))
_mcuMpIrqVectors.append(('IRQB_CLINT_MTIP', 'CLINT timer interrupt'))
# digperiphs #2/#3 (I3C, NFC): the meip external-interrupt slot is FROZEN at IVT
# slot 85 (m.MeipVector), so digperiph sources grow ABOVE it. Index 85 is a
# reserved, never-pending placeholder (the meip self-slot; tied low in irq_comb,
# ignored by the router). The eight I3C sources sit at 86-93 in the fixed order
# tc/rxf/txe/nack/eod/arb/daa/ibi (I3C.vhd's irq_* port order); when I3C is
# absent but NFC is present those eight stay reserved gaps (numbering FROZEN).
# The four NFC sources sit at 94-97 in the fixed order field/rxf/txdone/crcerr
# (NFC.vhd's irq_* port order). CLINT stays at 83/84 and the numbering below 85
# is untouched.
# Mission B: GPIO4/5 are UNCONDITIONAL and their 16 sources sit at 98-113, so the
# 85-97 band ALWAYS materializes now (in every config). Slot 85 = the meip
# self-slot placeholder; 86-93 = I3C0 (RSVD gaps when I3C absent); 94-97 = NFC0
# (RSVD gaps when NFC absent). Numbering FROZEN below and above.
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
	# I3C absent: sources 86-93 stay reserved (numbering frozen).
	for _v in range(86, 94):
		_mcuMpIrqVectors.append(('IRQB_RSVD' + str(_v), 'Reserved (vector ' + str(_v) + '; I3C0 disabled by this configuration)'))
if nfcPresent:
	_mcuMpIrqVectors.append(('IRQB_NFC0_FIELD', 'NFC0 RF Field-Detect Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_NFC0_RXF', 'NFC0 Reader-Frame Received Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_NFC0_TXDONE', 'NFC0 Tag-Response Transmit-Done Interrupt'))
	_mcuMpIrqVectors.append(('IRQB_NFC0_CRCERR', 'NFC0 RX CRC / Parity Error Interrupt'))
else:
	# NFC absent: sources 94-97 stay reserved (numbering frozen).
	for _v in range(94, 98):
		_mcuMpIrqVectors.append(('IRQB_RSVD' + str(_v), 'Reserved (vector ' + str(_v) + '; NFC0 disabled by this configuration)'))
# GPIO4 (vectors 98-105) and GPIO5 (vectors 106-113) — one per pin, UNCONDITIONAL.
for _p in (4, 5):
	for _b in range(8):
		_mcuMpIrqVectors.append(('IRQB_GPIO' + str(_p) + '_B' + str(_b), 'GPIO' + str(_p) + ' Bit ' + str(_b) + ' Interrupt'))
# digperiphs A5 (GLOBAL VECTOR RULE) — the library tail (vector 114+, ABOVE GPIO5's
# 106-113). Ordered EMISSION table, one row per optional library block in FROZEN
# vector order, kept in lockstep with _LIBRARY_TAIL_SPEC (present-flags + counts) up
# near the flag hoists. Each row's names are emitted up to the LAST vector of the
# HIGHEST ENABLED block; every DISABLED block BELOW that high-water mark backfills its
# slots as IRQB_RSVD<n> (frozen numbering, the I2C1-drop idiom) so a higher block keeps
# its number; nothing is emitted above the highest enabled block. Examples: rtc only ->
# 114 real, len 115; pwm only -> 114 RSVD + 115/116 real, len 117; rtc+pwm -> all real,
# len 117; nothing -> len 114 (byte-identical default). Adding onewire (117) is ONE row
# here + one in _LIBRARY_TAIL_SPEC. The two tables' (present, len(names)) must agree —
# cross-checked against _libraryTailVectorsCount() below.
_libraryTailEmit = [
	(rtcPresent, [('IRQB_RTC0', 'RTC0 combined alarm/periodic-tick Interrupt')]),
	(pwmPresent, [('IRQB_PWM0_FAULT', 'PWM0 fault-trip Interrupt'),
		('IRQB_PWM0_EVT', 'PWM0 period-event Interrupt')]),
	(onewirePresent, [('IRQB_OW0', 'OW0 1-Wire combined transaction-complete/error Interrupt')]),
	(dmaPresent, [('IRQB_DMA0_DONE', 'DMA0 combined channels-done Interrupt'),
		('IRQB_DMA0_ERR', 'DMA0 error (deny/LEN0/misalign/out-of-window) Interrupt')]),
	# DP-SG (2026-07-22): vector 120 = NPU0 think-done, live whenever the NPU is
	# (backfills IRQB_RSVD120 in npu-less configs with a higher tail block on). 121 =
	# TRNG0 (digperiphs TRNG, 2026-07-22 — combined data-ready/health-alarm),
	# gated by the new peripherals.trng knob (backfills IRQB_RSVD121 when off with a
	# higher tail block on). Kept in lockstep with _LIBRARY_TAIL_SPEC (irq_budget_phase0.md §1).
	(npuPresent, [('IRQB_NPU0_TD', 'NPU0 think-done Interrupt')]),
	(trngPresent, [('IRQB_TRNG0', 'TRNG0 combined data-ready/health-alarm Interrupt')]),
	(i2ctargetPresent, [('IRQB_I2CT0_AE', 'I2CT0 combined address-match/error Interrupt'),
		('IRQB_I2CT0_DATA', 'I2CT0 combined tx-ready/rx-full Interrupt')]),
]
# The emission rows for an overlay's tail blocks, in lockstep with the
# _LIBRARY_TAIL_SPEC rows it added above.
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
# Per-vector interrupt CLEAR METHODS for the TRM interrupt tables, keyed by IRQB name.
# Derived from the RTL flag registers of the peripherals whose flags are documented here.
# The table is optional: a vector with no entry prints no clear method, so every
# configuration (any hart count, any dropped peripheral) still builds.
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
# against the IRQB list (build fails on mismatch)
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
	_mcuMpIrqFirstVector['NPU'] = 'IRQB_NPU0_TD'	# vector 120 (interruptPriority 120; DP-SG think-done rider)
if rtcPresent:
	_mcuMpIrqFirstVector['RTC0'] = 'IRQB_RTC0'	# vector 114 (interruptPriority 114; single combined source)
if pwmPresent:
	_mcuMpIrqFirstVector['PWM0'] = 'IRQB_PWM0_FAULT'	# vectors 115-116 (interruptPriority 115; fault at the lower id, D18)
if onewirePresent:
	_mcuMpIrqFirstVector['OW0'] = 'IRQB_OW0'	# vector 117 (interruptPriority 117; single combined TC/error source)
if dmaPresent:
	_mcuMpIrqFirstVector['DMA0'] = 'IRQB_DMA0_DONE'	# vectors 118-119 (interruptPriority 118; done at the lower id, err at 119)
if i2ctargetPresent:
	_mcuMpIrqFirstVector['I2CT0'] = 'IRQB_I2CT0_AE'	# vectors 122-123 (interruptPriority 122; AE=address/error at the lower id, DATA=tx-ready/rx-full at 123)
if trngPresent:
	_mcuMpIrqFirstVector['TRNG0'] = 'IRQB_TRNG0'	# vector 121 (interruptPriority 121; single combined data-ready/health-alarm source)

# GPIO register reset values, transcribed VERBATIM (values + comments) from the RTL.
# NOTE the RTL numbers GPIO ports from 1 (GPIO0 = P1 ... GPIO3 = P4) while this
# description numbers from 0 — the emitted names use the RTL numbering. These values are
# boot-critical (P1 drives the flash chip select during SPI boot).
# KNOWN DISCREPANCY (2026-07-04): the description's per-pin rstOUT/rstDIR/rstSEL/rstREN
# attributes (which feed the TRM pin tables) disagree with the RTL for GPIO0 (trap DIR,
# lfxt/hfxt SEL) and GPIO1 (tx0 DIR). The RTL wins here; the TRM-track owns the pin
# attributes. The generator prints a warning for each such mismatch.
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
	# Mission B: GPIO4 (P5) / GPIO5 (P6). All pins reset to plain-GPIO input mode.
	# P5.6/7 (I3C SDA/SCL) enable their pull-ups at reset (open-drain idle-high) when
	# I3C is present; P6.0 (NFC rf_clk) resets to AF1 so the off-die clock is routed
	# without a runtime AFS switch (D5) when NFC is present.
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

# GPIO pin-number constants in the RTL's pnum_* spelling (MCU.vhd routes pads by these).
# (group header, RTL port number, [(name, bit)]) — transcribed from the RTL; bit numbers
# agree with the description's pin list where names correspond (the RTL names differ,
# e.g. pnum_gpio0_spi_clk vs PinNumGPIO0SCK0; pnum_gpio0_boot has no FuncName-bearing pin)
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
	# Multi-AF (AF1) pin assignments — plane-1 positions inside the flattened
	# alt_func vectors (the groups above are plane 0 / AF0). Cross-checked
	# against each pin's altFuncs metadata by generateMemoryMapVHD. G1b: rows
	# whose SOURCE peripheral is dropped leave the group with it (the gated
	# altFunc rows above are the other side of the bidirectional check).
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
	# Mission B: GPIO4 (P5) AF1 = QSPI0 (P5.0-5) + I3C0 (P5.6/7); GPIO5 (P6) AF1 =
	# NFC0 digital-AFE (P6.0-5). Rows gated with their controller (bidirectional
	# cross-check vs the AddGpio altFuncs above). All absent in the default config.
	('GPIO4 (P5) AF1: '
		+ ('QSPI0 pins on P5.0-5' if qspiPresent else 'P5.0-5 reserved (QSPI0 absent)')
		+ ' + ' + ('I3C0 open-drain on P5.6/7' if i3cPresent else 'P5.6/7 reserved (I3C0 absent)'), 5,
		([('pnum_gpio4_af1_qspi_sck', 0), ('pnum_gpio4_af1_qspi_cs', 1),
			('pnum_gpio4_af1_qspi_io0', 2), ('pnum_gpio4_af1_qspi_io1', 3),
			('pnum_gpio4_af1_qspi_io2', 4), ('pnum_gpio4_af1_qspi_io3', 5)] if qspiPresent else [])
		+ ([('pnum_gpio4_af1_i3c_sda', 6), ('pnum_gpio4_af1_i3c_scl', 7)] if i3cPresent else [])),
	# (OW0's DQ used to add a pnum_gpio5_af1_ow_dq row on P6.6 here; the Stage H re-pin
	# moved it to the P4.7 AF2 SPREAD slot, and spread slots wire literal pin indices
	# with no pnum_* reverse constant — the RX0/MISO1 v2 precedent.)
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

# ---------------------------------------------------------------------------
# PER-INSTANCE RESET VALUES (2026-09-10)
# ---------------------------------------------------------------------------
# A RegisterTemplate carries ONE reset value, but two peripherals reset the same
# register differently per INSTANCE, because the RTL passes the value in as a
# generic: GPIO's RstValPx{OUT,DIR,SEL,REN,AFS} (the _mcuMpRstVals table above,
# transcribed from hdl/common/MemoryMap.vhd) and I2C's default_SAD
# (hdl/common/constants.vhd i2c0_default_SAD / i2c1_default_SAD). Until now the
# register table and MemoryMap.h published 0x00 for all of them on every
# instance -- 22 register-index rows describing a chip that does not exist.
# Applied to the INSTANCE registers, after ChangeGPIOPortSize has narrowed them,
# so the template (and therefore //platform/common:rdl_vs_generator_test, which
# grades templates) is untouched and the per-instance values reach the emitted
# artifacts. The .rdl side assigns exactly these at the top addrmap
# (hdl/common/regs/rdl/castalia_penta_wound.rdl).
i2cDefaultSad = {'0': 0x79, '1': 0x23}	# hdl/common/constants.vhd: i2c{0,1}_default_SAD

def _setInstanceReset(peripheralName, registerName, value):
	'''Set one INSTANCE register's reset value and redistribute it over its bit
	   fields. Reserved (unused) bits are dropped, exactly as
	   RegisterTemplate.CheckBitFields computes a template reset, so a
	   nibble-packed register like PxAFS lands in the right 3-bit fields.'''
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

# A2 (Argus): shared-window geometry for mcu_vhd.py's generated regions —
# the SH_AW constant, the bank row and the NPU staging plumbing all derive
# from these three values (computed with the memory sections above).
m.McuMpGeometry = {
	'orchestrator': orchestrator,  # CPR3/R1: False = no orchestrator (byte-identical historical shape); True = HART 0 is the always-on SOFT orchestrator emitted as `entity work.orch_tile` (keeping every hart-0 wiring special) and harts 1..numHarts-1 are FULLY UNIFORM channel tiles -- pwr_ctrl rows 1..numHarts-1 (PWRCR gains bit numHarts-1), iso clamps on all of them, and the memory map goes to v2 (SH_AW >= 16 + the five read-only TCM apertures). The management hart is hart 0 in both shapes, so afe_stub's MGMT_HART is never overridden any more
	'shAw': shAw,               # arbiter/tile word-address width (15 = Castalia, 16 = Argus and every orchestrator config)
	'tcmWindows': tcmWindows,   # CPR3/R3: byte base of the read-only TCM aperture for hart h (index = h); [] = no apertures
	'tcmApertureSize': _tcmApertureSize,  # 2026-08-16: aperture STRIDE/SPAN in bytes, deliberately DECOUPLED from the TCM size (address space, not silicon). >= tcmSizePerHart; an 8 KiB TCM mirrors twice inside its 16 KiB aperture. The decode granularity s_addr(15:12) depends on this being 0x4000.
	'sharedRamBanks': _sharedRamBanks,  # sram1p16k banks from 0x10000 (4 = Castalia)
	'npu': npuPresent,          # False = Argus (slot 10 + 0xC000 window read zero)
	'i2c1': i2c1Present,        # G1a: False drops the i2c1 instance (slot 15 dead)
	'uart1': uart1Present,      # G1b: False drops the uart1 instance (slot 5 dead)
	'spi1': spi1Present,        # G1b: False drops the spi1 instance (slot 3 dead)
	'timer1': timer1Present,    # G1b: False drops the timer1 instance (slot 7 dead)
	'afeStubs': cqAfeStubsPresent, # digperiphs #1: True = the four AFE stubs + EIS occupy slot 12/0x7C00 (golden-master default)
	'i3c': i3cPresent,          # digperiphs #2: True = I3C0 in MUTEX-page sub-slot 1 (0x6100); tightens the mutex decode, vectors 86-93
	'nfc': nfcPresent,          # digperiphs #3: True = NFC0 in MUTEX-page sub-slot 2 (0x6200); tightens the mutex decode, vectors 94-97, 4th glitch filter
	'qspi': qspiPresent,        # digperiphs #1: True = QSPI0 controller in slot 12 (0x4C00), vectors 55/56 (needs afeStubs=False)
	'rtc': rtcPresent,          # digperiphs #4: True = RTC0 in MUTEX-page sub-slot 5 (0x6500); raw-strobe shim, vector 114, source list grows to 115
	'pwm': pwmPresent,          # digperiphs #5: True = PWM0 in MUTEX-page sub-slot 6 (0x6600); raw-strobe shim, vectors 115/116, source list grows to 117 (A5 global vector rule)
	'onewire': onewirePresent,  # digperiphs #5: True = OW0 1-Wire master in MUTEX-page sub-slot 7 (0x6700); raw-strobe shim, DQ on P4.7/GPIO31 AF2 open-drain (replaced-spread-slot), vector 117, source list grows to 118 (A5 global vector rule)
	'fieldPower': fieldPowerPresent,  # DP-S3: True = pwr0's supervision inputs wired (pgood_pad=prt6_in(7), strap_pad=prt6_in(6), field_detect=NFC tap-or-0); False = all tied inert. The pgood_rstn reset folds are emitted unconditionally (provable no-op when tied).
	'dma': dmaPresent,          # digperiphs #6: True = DMA0 in MUTEX-page sub-slot 8 (0x6800) + the FIRST new arbiter MASTER; raw-strobe slave shim, vectors 118/119, source list grows to 119, and the arbiter N=4->5 / MW=3 / sh_master 2->3 FABRIC WIDENING (the one shared-RTL touch)
	'dmaChannels': dmaChannels, # digperiphs #6: DMA0 NCH generic {2,4} (consulted only when dma); the 4-channel register superset is emitted regardless
	'i2ctarget': i2ctargetPresent,  # digperiphs (I2CT): True = I2CT0 hardware-autonomous I2C target in MUTEX-page sub-slot 10 (0x6A00); raw-strobe shim, shares I2C0 SDA0/SCL0 pads (wired-AND DIR merge, emitted separately), vectors 122/123, source list grows to 124 (A5 global vector rule, with 120/121 always-RSVD DP-SG placeholders)
	'trng': trngPresent,        # digperiphs (TRNG): True = TRNG0 ring-oscillator entropy source + harvest engine in MUTEX-page sub-slot 9 (0x6900); raw-strobe shim, sibling u_ro TrngRoEnsemble instance, vector 121, source list grows to 122 (A5 global vector rule)
	'trngRings': trngRings,     # digperiphs (TRNG): TRNG0 NRO generic {4,8} (consulted only when trng); the register map is NRO-invariant
	'eventFabric': eventFabricPresent,  # digperiphs (EVFAB): True = EVFAB0 event/trigger fabric in MUTEX-page sub-slot 11 (0x6B00); raw-strobe shim, VECTORLESS (no vector spend), plus the producer/consumer tap port maps on RTC0/PWM0/TIMER0/TIMER1/UART0/NFC0/DMA0/TRNG0/I2CT0/GPIO0/NPU0/pwr0 (every absent source tied '0', D23)
	'chipNameConfigured': (_cfg('chipName', None) or ''),  # D3: the CONFIG FILE's chip name -- NEVER the CHIP_NAME env override, which is documentation-only. One half of the JTAG IDCODE chip-identity discriminator (mcu_vhd.isArgusFamily; the other half is numHarts == 18, which is what the acceptance instruments key on). A docs-only switch must never be able to change an RTL constant.
	'debug': _debug['enable'],  # D2: True = the Debug Module (dm0) + the eight MCU-entity dmi_* ports + the per-tile dbg_* hookup + DEBUG_ENTRY_ADDR => 0x00010780. dm0 is the SECOND new arbiter MASTER after the DMA (index nMasters-1, i.e. numHarts when the DMA is off and numHarts+1 when it is on), so it drags the same fabric widening the DMA documents. OFF (the default) emits NO TRACE: no ports, no decls, no instance, no clamp row -- check_mcu_vhd.py STRICT is the bar. D3 RIDES THE SAME KNOB (no debug.jtag sub-knob): it adds the five JTAG pins (tck/tms/tdi/tdo/trstn, the LAST entity port group), the dtm0 jtag_dtm instance beside dm0, and the valid-gated OR-merge that keeps the raw dmi_* ports reaching the DM with the DTM present-and-inert.
}
# The emitters' knob dictionary is the ONE channel to mcu_vhd.py and tb_vhd.py,
# so an overlay's placement knobs ride it too and entity and testbench cannot
# disagree about what was built.
overlay.call('mcuGeometry', geo=m.McuMpGeometry, vals=_overlayVals)


''' Check for errors '''
m.CheckPeripherals()
m.CheckPackagePins()


# ---------------------------------------------------------------------------
# CQ analog front-end — DOCUMENTATION-ONLY sub-slot blocks (AFE0-3 + EIS)
# ---------------------------------------------------------------------------
# The Castalia-Quad respin instantiates five s_master-gated register-stub
# arbiter slaves (afe_stub.vhd, wired in the generated MCU.vhd): four per-hart
# AFE sites in the four 64 B sub-slots of page-0 slot 12 (0x4C00) and one
# hart-0 EIS engine in the top quarter of the IRQ-router page (0x7C00). These
# sit at SUB-SLOT / page-carved base addresses that a native arbiter slave is
# forbidden from (the whole-slot cross-checks in Peripheral assume one slave per
# whole slot), so they are NOT CreatePeripheral()'d — documenting them that way
# would require weakening those checks for every config. Instead they are
# DOCUMENTATION sub-slot blocks: their own data model, validated by
# m.CheckDocSubSlotBlocks() (its own sub-slot alignment / containment / no-shadow
# rules), feeding ONLY the TRM (a config-gated generated chapter). They never
# enter the peripheral / address / interrupt tables, MemoryMap.vhd, or MCU.vhd.
# WHICH CONFIGURATIONS GET THEM, and why it is no longer a package-model NAME.
# This used to read `packageModel == 'castalia-quad-qfn64'', which was a stand-in
# for the two facts the chapter and both whole-chip figures actually assert:
# (1) the package BONDS the sixteen electrode pads, so there is an analog story
#     to tell at all -- AfeSystemDiagram re-derives WE/RE/RE2/CE_0..3 from the
#     pin list and refuses to draw pads the chip does not have, and
#     ChipSystemFlatDiagram's channel row is built from the same lookup; and
# (2) the chip is the SHAPE that chapter describes -- an orchestrator hart 0
#     plus one channel tile per site, which is numHarts == 5 with orchestrator
#     true (AfeSystemDiagram asserts both, by name, and raises otherwise).
# Keying on the model name held (1) only by coincidence and (2) not at all, and
# when castalia-lqfp100 became the shipped default on 2026-08-17 the coincidence
# broke the other way: the default TRM lost its analog row and its analog
# chapter although the RTL still instantiates all five afe_stub slaves. With the
# electrode pads now bonded on the LQFP-100 (above), the honest gate is the two
# facts themselves. castalia-quad-qfn64 is unchanged by this (it bonds the
# sixteen and is a 5-hart orchestrator), myshkin-qfn44 bonds no electrode group
# and stays off, and config/argus_debug.json -- eighteen harts, no orchestrator,
# wearing the LQFP-100 provisionally to reach the JTAG balls -- stays off too:
# the degrade is the AFE block back on the peripheral rank, never a figure that
# names five harts on an eighteen-hart chip.
_pkgPinNames = set(_p.Name for _p in m.Package.Pins)
_bondsElectrodes = all((_e + '_' + str(_i)) in _pkgPinNames
	for _i in range(4) for _e in ('WE', 'RE', 'RE2', 'CE'))
if _bondsElectrodes and cqAfeStubsPresent and orchestrator and numHarts == 5:
	# The 16-word (64 B) register file shared by every afe_stub instance (AFE and
	# EIS are the same entity — only the ownership gate differs). Word offset,
	# name, access, description; byte offset = 4 x word offset.
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
	# THE OWNER FOLLOWS THE TILE, NOT THE SITE INDEX. mcu_vhd.afeStubsOrchOwners()
	# shifts every AFE site's OWNER_HART generic by +1 on an orchestrator config,
	# because hart 0 is the orchestrator and the four CHANNEL harts are 1..4: the
	# emitted MCU.vhd reads `afe0 ... OWNER_HART => 1  -- 0x4C00: tile hart 1 or
	# hart 0'. This table used to hard-code ownerHart = site index regardless, so
	# the TRM's ownership table and gating prose described the pre-orchestrator
	# shape, and since the chapter renders ONLY on the CQ package model, which IS
	# an orchestrator config, every rendered copy of it was wrong: it told the
	# reader AFE0 answered hart 0 alone when the RTL gives it to hart 1. Derived
	# here from the same knob mcu_vhd.py derives from, so the two cannot drift.
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


# ---------------------------------------------------------------------------
# THE unified configuration record. One dict holds every knob the CONFIG=
# schema accepts plus everything derived from them; it is (a) attached to the
# generator so the TRM's generated Chip Configuration section renders from it,
# and (b) written to config/ChipConfig.resolved.json after generation so
# `make show`, scripts, and the configurator can read back exactly what was
# built. Addresses are 0x-strings for readability; sizes are byte ints.
# ---------------------------------------------------------------------------
def _hx(v):
	return '0x' + format(int(v), 'X')

_resolvedConfig = [
	('_comment', 'Resolved chip configuration — written by make chip (platform/common/python/generate.py). '
		+ 'Inputs follow the CONFIG= JSON schema (docs/chip_configurator.html emits it); '
		+ 'everything under "derived" is computed, not configurable.'),
	('configFile', _cfgPath if _cfgPath else None),
	('chipName', m.AsicName),
	('numHarts', numHarts),
	# CPR3/R1: the orchestrator knob. Dumped so verify_stage.py (cell list +
	# test tags) and any script can read the shape that was actually built
	# rather than re-deriving it -- the debug-knob precedent (d2_probe finding
	# 10). `powerGatedHarts` is gone with the CP2 pwrHarts special case: every
	# hart 1..numHarts-1 is gateable in both shapes now, so the value was
	# numHarts unconditionally and a second name for it could only rot.
	('orchestrator', orchestrator),
	('numMutexes', numMutexes),
	('registerFileDualPort', _regsDualPort),
	# Fetch-ahead. Recorded for the same reason the debug branch is: a build
	# that carries it must be distinguishable from one that does not in the
	# artifact scripts read back, not only in the RTL.
	('core', _core),
	('isa', _isa),
	('priv', _priv),
	# D2: the resolved dump gains the debug branch (d2_probe finding 10 /
	# d2_spec 6). Until now a debug-ON build's ChipConfig.resolved.json was
	# byte-indistinguishable from a debug-OFF one -- in the very artifact
	# CLAUDE.md calls a LIVE INPUT to the lockstep oracle -- so nothing
	# downstream could derive from the knob. verify_stage.py's config_tags()
	# is the first consumer; oracle_isa.py is deliberately NOT keyed on it
	# (its derive_triggers() says so and returns 0 unconditionally), so no
	# oracle behaviour changes.
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
		# DP-S3: the field-power knob was declared in _CONFIG_SCHEMA and consumed
		# everywhere (RstValP6REN, the P6.6/P6.7 pad descriptions, mcu_vhd's pwr0
		# port wiring) but never recorded here, so the resolved dump could not
		# report the shape it had built. The TRM's configuration table reads its
		# rows straight out of this record, so the published manual shipped
		# "peripherals.fieldPower  None" for the whole life of the knob. Every
		# other knob in _CONFIG_SCHEMA has a row here; this one is the omission.
		('fieldPower', fieldPowerPresent),
		('dma', dmaPresent),
		('dmaChannels', dmaChannels), ('i2ctarget', i2ctargetPresent),
		('trng', trngPresent), ('trngRings', trngRings),
		('eventFabric', eventFabricPresent)]),
	('package', [('model', packageModel), ('preliminary', packagePreliminary)]),
	('derived', [
		('isaString', _isaString()),
		('sharedWindowAddrWidth', shAw),
		('sharedRamBanks', _sharedRamBanks),
		('flashBaseAddress', _hx(flashBase)),
		('sharedRamEndAddress', _hx(0x10000 + _sharedRamLen - 1)),
		# CPR3/R3: the read-only TCM apertures (orchestrator configs only).
		# Empty list everywhere else, so a consumer keys on the list, never
		# on the knob (the resolved dump is the shape that was BUILT).
		('tcmWindowAddresses', [_hx(_w) for _w in tcmWindows]),
		('vectorsCount', _vectorsCount),	# Mission B: GPIO4/5 unconditional -> 114; digperiphs #4/#5: the library tail (RTC 114, PWM 115/116) extends it per the A5 global vector rule (_libraryTailVectorsCount())
		('meipVector', 85),
		('clintMsipVector', 83),
		('clintMtipVector', 84),
		('clintLayout', [
			('msipAddress', '0x5000 + 4*hartid'),
			('mtimeAddress', _hx(0x5000 + 4 * clintMtimeSlot)),
			('mtimecmpBaseAddress', _hx(0x5000 + 4 * clintMtimecmpSlot)),
		]),
		('bootromLoaderRowBase', '0x10500 + 0x10*hartid'),	# Argus A3 relocation (N-agnostic, all builds — see software/bootrom_mp)
		('stackPointerInit', _hx(_stackPointerInit)),
		('peripheralCount', len(m.Peripherals)),
	]),
]
# An overlay's knobs are recorded like every other, so the resolved dump reports
# the shape that was actually built. With no overlay the record is unchanged.
_resolvedConfig = list(overlay.call('resolvedConfig', default=_resolvedConfig,
	rows=_resolvedConfig, vals=_overlayVals))

def _od(pairs):
	'''Recursively turn ('key', value) pair lists into dicts (py3.6 dicts keep
	   insertion order, so the JSON reads in schema order).'''
	if isinstance(pairs, list) and pairs and all(isinstance(p, tuple) and len(p) == 2 for p in pairs):
		return dict((k, _od(v)) for k, v in pairs)
	return pairs

m.ResolvedConfig = _od(_resolvedConfig)
m.PackagePreliminary = packagePreliminary	# G4: drives the TRM §2 "Preliminary" banner (LatexUserGuide \ifpackagepreliminary)
# CPR3/R1: the orchestrator PRESENCE flag, for the TRM's config-driven prose
# (LatexUserGuide \iforchpresent; \OrchHartIndex is now the constant 0 — the
# orchestrator IS hart 0). False = every piece of orchestrator prose folds away
# — the same "inert unless declared" discipline as \ifcqanalog and
# \ifdebugenable, which is what keeps the default TRM byte-identical.
m.Orchestrator = orchestrator
# Schema key -> human description, for the TRM's generated Chip Configuration
# section (documents the CONFIG= schema next to this build's resolved values)
m.ConfigSchemaDoc = dict((k, _CONFIG_SCHEMA[k][0]) for k in _CONFIG_SCHEMA)
# S2: declarative schema metadata + the resolved defaults, attached for the
# `make web` export (out/web/chip_data.js) so the configurator can read
# ranges/enums/defaults from the generator rather than re-hardcoding them.
m.ConfigMeta = dict((k, dict(_CONFIG_META[k])) for k in _CONFIG_META)
m.ConfigDefaults = dict((k, _CONFIG_META[k]['default']) for k in _CONFIG_META)
# The verified hart counts, from the single record above, for the same export.
# web_export.py publishes this verbatim as VESTA_DATA.verifiedHarts; the
# configurator badges cfg.numHarts on the `values` list, so anything added here
# renders as a proven hart count on a published page.
m.VerifiedHarts = {
	'values': [_n for _n, _d in _VERIFIED_HART_COUNTS],
	'note': _verifiedHartsNote(),
}

# Derived pad ring: the package model above IS the pad-ring description
# (pin order, sides, power domains). Recorded as config/PadRing.json and
# rendered as the TRM's generated pinout diagram — there is no separate
# hand-maintained pad list to drift out of sync.
def _padRingDomainEntry(_pd):
	'''One PadRing.json powerDomains entry. Single-pad rails emit exactly the
	   historical shape (name/voltage/positiveRail/negativeRail — the QFN44
	   model stays byte-identical); a multi-pad rail additionally lists ALL of
	   its pads under positiveRailPins/negativeRailPins.'''
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
	'''Serialize a fully-built PackageData (sides assigned) into the PadRing.json
	   shape. Used for m.Package (the selected model → config/PadRing.json) AND
	   for the web export's other-model pad tables — ONE serializer, so every
	   model's pad table has the identical shape.'''
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

# S2: pad tables for EVERY package model (not just the selected one) so the web
# export can offer a live pinout for each. Built via the SAME machinery: the
# GPIO func/altfunc STRUCTURE is model-independent (already attached to the GPIO
# peripherals above), so a non-selected model reuses those exact gpio objects,
# remaps each to that model's package pin number (_GPIO_PKG_PINS), and reruns
# the CheckPackagePins side assignment. No pin number is transcribed twice.
def _padRingForModel(_model):
	if _model == packageModel:
		return m.PadRing	# the authoritative, already-built + side-assigned ring
	_pkg = _buildPackageData(_model)
	for _gp in (GPIO0, GPIO1, GPIO2, GPIO3, GPIO4, GPIO5):	# G2: all six ports (P5/P6 bond on castalia-lqfp100; QFN models return None = skip)
		_gi = int(_gp.Name[len('GPIO'):])
		for _gpio in _gp.Pins:
			_num = _GPIO_PKG_PINS[_model].get((_gi, _gpio.BitNumber))
			if _num is None:
				continue	# unbonded on this model (no package ball)
			_p = _pkg.AddGpioPin(_num, _gpio)
			_p.PowerDomain = _pkg.GpioPowerDomain
	# Mirror ChipGenerator.CheckPackagePins side assignment (sort then W/S/E/N).
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


''' Generate all output files '''
# TODO: Enable saveHardware=True once MCU.vhd has the required "Begin Automatically Generated" headers
# For now, only generating software files and documentation
m.Generate(test=False, force=True, saveHardware=True, saveSoftware=True)

# ---------------------------------------------------------------------------
# SystemRDL SIDE artifacts (tools/rdl/README.md, reports R1 and R5).
#
# The register maps themselves are already in: _rdlRegisters() built most of the
# peripheral templates above out of hdl/common/regs/rdl/, so the TRM tables,
# MemoryMap.h, MemoryMap.vhd and the configurator data that m.Generate() has just
# written ARE the descriptions. What is emitted here is the rest of what the
# descriptions can produce and the generator does not otherwise write:
#
#   out/rdl/<TAG>_reg_pkg.vhd   the offset/field/reset package a NEW peripheral
#                               can `use` instead of declaring constants locally
#                               (level 3 of the adoption plan)
#   out/rdl/<TAG>_rdl.json      the block's register sub-tree with its SystemRDL
#                               provenance (source file, addrmap, word base)
#   out/rdl/<TAG>-registers-rdl.tex, MemoryMap_<TAG>_rdl.h
#                               the per-block table and header fragment
#
# and ONE file the TRM actually inputs: DEBUG-registers-rdl.tex. The Debug Module
# is not memory-mapped -- its registers live in the DMI address space, reachable
# only through the JTAG DTM -- so it has no PeripheralTemplate, no register-index
# row and no place in MemoryMap.h, and hdl/common/regs/rdl/debug_module.rdl is
# the only machine-readable description of it. The debug chapter inputs the table.
#
# systemrdl-compiler is NOT optional any more: the chip's register map comes out
# of it. A missing toolchain must stop the generation, not silently emit a chip
# with 18 peripherals' registers missing.
# ---------------------------------------------------------------------------
def _emitRdlArtifacts():
	import rdl_emit
	cfgPath = chipRootDirectory + '/config/rdl.json'
	flags = rdl_emit.loadFlags(cfgPath)
	# A peripheral this configuration does not instantiate has nothing to
	# document. A block that is not memory-mapped at all is always emitted:
	# there is no instance to look for.
	present = set(p.Template.NameTemplate for p in m.Peripherals)
	flags = [f for f in flags if f['peripheral'] is None or f['peripheral'] in present]
	outDir = chipRootDirectory + '/out/rdl'
	if not os.path.isdir(outDir):
		os.makedirs(outDir)
	trmInclude = chipRootDirectory + '/latex/TRM/include'
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

# Unified-config artifacts (written last, so they only land on a successful build)
with open(chipRootDirectory + '/config/ChipConfig.resolved.json', 'w') as _f:
	json.dump(m.ResolvedConfig, _f, indent=2)
	_f.write('\n')
print('[generate] wrote config/ChipConfig.resolved.json (resolved configuration)')
with open(chipRootDirectory + '/config/PadRing.json', 'w') as _f:
	json.dump(m.PadRing, _f, indent=2)
	_f.write('\n')
print('[generate] wrote config/PadRing.json (derived pad ring)')

# ---------------------------------------------------------------------------
# G4: Innovus pad-placement template for the connected chip_top flow (roadmap
# C0 "pad ring Flavor B") — ONE derived pad ring feeding the docs (PadRing.json
# + the TRM pinout) AND PnR. Emits ordered per-side pad lists in the format
# the innovus chip-top flows' place_side proc (chip_top_quad.innovus.tcl lineage) consumes (Flavor A
# hand-codes these lists today). Lists are in placeInstance GEOMETRIC order
# (+x for bottom/top rows, +y for left/right rows); QFN pin 1 sits at the TOP
# of the left edge (top view, counter-clockwise numbering), so the W and N
# side lists run in DESCENDING pin order. Pad instance names are placeholders
# (PAD_<pad>) — Flavor B binds them to tphn65gpgv2od3_sl cells + nets.
# ---------------------------------------------------------------------------
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
# Uniquify repeated instance placeholders (G2 2026-07-23: multi-pair supply
# models emit PAD_VDD three times etc. — an illegal duplicate instance name the
# consuming netlist/padlists then have to hand-fix). Bases that occur ONCE keep
# their bare name (PAD_RESETN, PAD_P3_0, ... — QFN models unchanged); repeats
# get _0/_1/... in EMISSION order (W desc, S asc, E asc, N desc — the same
# order the chip_top_dp staging used, so the names line up).
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
_pnrDir = chipRootDirectory + '/out/pnr'
if not os.path.isdir(_pnrDir):
	os.makedirs(_pnrDir)
with open(_pnrDir + '/chip_top_padring.tcl', 'w') as _f:
	_f.write('\n'.join(_padTclLines))
	_f.write('\n')
print('[generate] wrote out/pnr/chip_top_padring.tcl (pad-placement template for the chip_top flow)')

