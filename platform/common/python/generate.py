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
_PACKAGE_MODELS = ('myshkin-qfn44', 'castalia-quad-qfn64')

_CONFIG_SCHEMA = {
	'chipName':             ('non-empty string — renames the chip in the TRM/headers (docs-only; CHIP_NAME env still wins)',
	                         lambda v: isinstance(v, str) and len(v.strip()) > 0),
	'numHarts':             ('int 1..32 — hart/tile count (4 = Castalia golden master, 18 = Argus sim-proven)',
	                         lambda v: _isInt(v) and 1 <= v <= 32),
	'numMutexes':           ('int 1..1024 — HW mutex bank size (16 = Castalia, 32 = Argus)',
	                         lambda v: _isInt(v) and 1 <= v <= 1024),
	'registerFileDualPort': ('bool — dual-port register file (ASIC) vs single-port (Spartan-6 FPGA)',
	                         _isBool),
	'isa.mul':              ('bool — M multiply', _isBool),
	'isa.fastMul':          ('bool — docs-only on vesta (multiplier is already single-cycle)', _isBool),
	'isa.div':              ('bool — M divide', _isBool),
	'isa.atomics':          ('bool — A extension (LR/SC + AMO)', _isBool),
	'isa.compressed':       ('bool — C extension', _isBool),
	'isa.bitmanip':         ('bool — Zba/Zbb/Zbs', _isBool),
	'isa.counters':         ('bool — Zicntr mcycle/minstret', _isBool),
	'isa.counters64':       ('bool — 64-bit counter high halves (needs isa.counters)', _isBool),
	'memory.romSize':            ('int bytes, 1 KiB multiple <= 0x4000 (region 0x0-0x3FFF)',
	                              lambda v: _isMemSize(v, 0x4000)),
	'memory.tcmSizePerHart':     ('int bytes, 1 KiB multiple <= 0x4000 (region 0x8000-0xBFFF)',
	                              lambda v: _isMemSize(v, 0x4000)),
	'memory.sharedBulkRamSize':  ('int bytes, multiple of 0x4000 (one sram1p16k bank) from 0x10000',
	                              lambda v: _isInt(v) and v >= 0x4000 and v % 0x4000 == 0),
	'memory.npuStagingRamSize':  ('int bytes, 1 KiB multiple <= 0x4000 (region 0xC000-0xFFFF)',
	                              lambda v: _isMemSize(v, 0x4000)),
	'peripherals.npu':      ('bool — False drops the NPU entirely (slot 10 + the 0xC000 staging window read zero)',
	                         _isBool),
	'peripherals.i2c1':     ('bool — False drops the second I2C instance (slot 15 reads zero, IRQ vectors 70-82 reserved, SDA1/SCL1 pins revert to plain GPIO)',
	                         _isBool),
	'peripherals.uart1':    ('bool — False drops the second UART instance (slot 5 reads zero, IRQ vectors 52-54 reserved, TX1/RX1 pins revert to plain GPIO)',
	                         _isBool),
	'peripherals.spi1':     ('bool — False drops the second SPI instance (slot 3 reads zero, IRQ vectors 11-12 reserved, CS1/MISO1/MOSI1/SCK1 pins revert to plain GPIO)',
	                         _isBool),
	'peripherals.timer1':   ('bool — False drops the second TIMER instance (slot 7 reads zero, IRQ vectors 22-27 reserved, T1CMP*/T1CAP* pins revert to plain GPIO)',
	                         _isBool),
	'package.model':        ('string — package model name defined in generate.py (_PACKAGE_MODELS: "myshkin-qfn44" QFN-44, "castalia-quad-qfn64" QFN-64 quad pinout — new pinouts are added as Python models, never as free-form config pin lists)',
	                         lambda v: isinstance(v, str) and v in _PACKAGE_MODELS),
	'package.preliminary':  ('bool — True prints the TRM package-section "Preliminary" note (default True while the package is inherited from Myshkin unchanged)',
	                         _isBool),
}

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
numHarts = _cfg('numHarts', 4)

# Mutex count (A2/Argus: 32 for the 18-hart course chip, 16 = the Castalia
# default). Word-mapped at 0x6000 + 4*i; the page has room for far more, the
# RTL addr port width is clog2(numMutexes) (mutex_bank NMUTEX generic).
numMutexes = _cfg('numMutexes', 16)

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

# Package model selection (G4): which _PACKAGE_MODELS entry builds the pad
# ring below, and whether the TRM package section carries the "Preliminary"
# banner (True while every config inherits the Myshkin QFN-44 unchanged).
packageModel = _cfg('package.model', 'myshkin-qfn44')
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
	'counters':   _cfg('isa.counters', False),
	'counters64': _cfg('isa.counters64', False),
}
_regsDualPort = _cfg('registerFileDualPort', True)
_romSize = _cfg('memory.romSize', 16384)
_tcmSize = _cfg('memory.tcmSizePerHart', 16384)

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
		s += '_zba_zbb_zbs'
	if _isa['counters']:
		s += '_zicntr'
	return s

# Cross-knob sanity (WARN, not raise — these are legal but suspicious)
if _isa['counters64'] and not _isa['counters']:
	print('[generate] WARNING: isa.counters64 without isa.counters — the 64-bit high halves need the base Zicntr counters')
if (not _isa['atomics']) and numHarts > 1:
	print('[generate] WARNING: isa.atomics=false on a multi-hart chip breaks the LR/SC + AMO + mutex lock infrastructure the sh tests rely on')
if _CHIP_CONFIG and numHarts not in (4, 18):
	print('[generate] NOTE: numHarts=' + str(numHarts) + ' — only 4 (Castalia golden master, byte-identical RTL) and 18 (Argus, boots in simulation) are verified hart counts')

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
	0x00000-0x03FFF  THE shared boot ROM (one rom_hvt_pg, read-only; all
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
	romSize=_romSize,	# 16 KiB (region 0x0-0x3FFF; do not exceed 0x4000)
	peripheralMemoryStartAddress=0x4000,
	peripheralMemorySlotCount=16,
	registerMemorySlotsPerPeripheralMemorySlot=64, #Bytes between each peripheral's register memory slots.
	ramStartAddress=0x8000,
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
	stackPointerInit=0xC000,	# Stack pointer at top of the private TCM
	bootloaderUsesSpiFlashCommands=True,
	vectorsCount=85,	# 83 legacy vectors + CLINT msip (83) + CLINT mtip (84)
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
	ENABLE_MUL=_isa['mul'],
	ENABLE_FAST_MUL=_isa['fastMul'],
	ENABLE_DIV=_isa['div'],
	ENABLE_ATOMICS=_isa['atomics'],
	ENABLE_BITMANIP=_isa['bitmanip'],
	ENABLE_IRQ_FAST_CONTEXT_SWITCHING=False,	# Using fast context switching saves 31.042 us @ 24 MHz (745 cycles) per interrupt, but doubles the size of the CPU register file
	ENABLE_IRQ_QREGS=False,	# Evidently the ARM register file IPs are called "two-port", but one port is read-only and the other is write-only. This means you need to write your own register file definition in HDL (remember that register x0 is always all '0's!)
	ENABLE_IRQ_TIMER=False,
	MASKED_IRQ=0x00000000,	# 32-bit IRQ mask. Any bit that is a '1' is a permanently disabled interrupt vector
	PROGADDR_IRQ=0x9000,	# TODO: Set this as the address of the master IRQ handling function (this is NOT the interrupt vector table!!! This is the function that is called whenever ANY interrupt occurs)
	lastRamMemorySlotSize=_tcmSize
)



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
flashBase = 1 << (shAw + 2)
m.ExtraMemorySections = []
if npuPresent:
	m.ExtraMemorySections.append(
		('NPU_RAM (rwx)', ': ORIGIN = 0x0C000, LENGTH = ' + _hexLen(_npuRamLen), '/* NPU staging RAM (arbitrated; NPU-port-muxed during a THINK) */'))
m.ExtraMemorySections.append(
	('SHARED_RAM (rwx)', ': ORIGIN = 0x10000, LENGTH = ' + _hexLen(_sharedRamLen), '/* arbitrated shared RAM (mailbox region 0x10000-0x107FF zeroed by the bootrom; loader rows at 0x10400) */'))

# Extra hand-written TRM chapters input by the master template (copied into latex/TRM/include/)
m.ExtraLatexIntroFiles = ['MULTICORE-intro-castalia-2026-07.tex']

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



''' System '''
p = PeripheralTemplate(nameTemplate='SYSTEM', description='Controls the entire system, including the clocking and power state. Also has a CRC calculator using the CRC16_CDMA2000 polynomial.', bitFieldPrefix='SYS', latexIntroFileName='SYSTEM-intro-castalia-2026-07.tex', latexFeatureSummary=['A CRC calculation engine (CRC16\\_CDMA2000)', '2$\\times$ internal digitally controllable oscillators', '2$\\times$ external clock pins for clock generation and accurate timing', 'A windowed watchdog timer'])
m.AddPeripheralTemplate(p)

# SYSCLK
r = RegisterTemplate(nameTemplate='SYSCLKCR', registerMemorySlot=0, description='System clock control register', size=16)
p.AddRegisterTemplate(r)

#r.AddBitField(BitField(name='CLKOSSEL', msb=15, lsb=13, description='CLKO pin output clock source select', accessibility='rw', valueDescriptions=[(0b000, 'CPU Clock', '_CPU'), (0b001, 'MCLK', '_MCLK'), (0b010, 'SMCLK', '_SMCLK'), (0b011, 'Low Frequency Crystal Clock', '_LFXT'), (0b100, 'High Frequency Crystal Clock', '_HFXT'), (0b101, 'Digitally Controlled Oscillator 0', '_DCO0'), (0b110, 'Digitally Controlled Oscillator 1', '_DCO1')]))
#r.AddBitField(BitField(unused=True, msb=12))
r.AddBitField(BitField(unused=True, msb=15, lsb=9))
r.AddBitField(BitField(name='DCO1ON', msb=8, description='Digitally controlled oscillator 1 (DCO1) power enable. Set to power on DCO1. DCO1 is automatically kept on if it is currently selected as the source for MCLK or SMCLK, regardless of this bit.', accessibility='rw', valueDescriptions=[(0b0, 'DCO1 powered off'), (0b1, 'DCO1 powered on')]))
r.AddBitField(BitField(name='DCO0ON', msb=7, description='Digitally controlled oscillator 0 (DCO0) power enable. Set to power on DCO0. DCO0 is automatically kept on if it is currently selected as the source for MCLK or SMCLK, regardless of this bit.', accessibility='rw', valueDescriptions=[(0b0, 'DCO0 powered off'), (0b1, 'DCO0 powered on')]))
r.AddBitField(BitField(name='HFXTOFF', msb=6, description='High frequency external crystal clock disable. Cannot be disabled if it is currently selected as the source for MCLK or SMCLK.', accessibility='rw', valueDescriptions=[(0b0, 'HFXT enabled'), (0b1, 'HFXT disabled')]))
r.AddBitField(BitField(name='LFXTOFF', msb=5, description='Low frequency external crystal clock disable. Cannot be disabled if it is currently selected as the source for SMCLK.', accessibility='rw', valueDescriptions=[(0b0, 'LFXT enabled'), (0b1, 'LFXT disabled')]))
r.AddBitField(BitField(name='SMCLKOFF', msb=4, description='Submain clock disable. Globally and unconditionally disables SMCLK, gating all peripherals clocked from SMCLK.', accessibility='rw', valueDescriptions=[(0b0, 'SMCLK enabled'), (0b1, 'SMCLK disabled')]))
r.AddBitField(BitField(name='SMCLKSEL', msb=3, lsb=2, description='Submain clock source select', accessibility='rw', valueDescriptions=[(0b00, 'High Frequency Crystal Clock', '_HFXT'), (0b01, 'Low Frequency Crystal Clock', '_LFXT'), (0b10, 'Digitally Controlled Oscillator 0', '_DCO0'), (0b11, 'Digitally Controlled Oscillator 1', '_DCO1')]))
r.AddBitField(BitField(name='MCLKSEL', msb=1, lsb=0, description='Main clock source select (also CPU clock source select)', accessibility='rw', valueDescriptions=[(0b00, 'High Frequency Crystal Clock', '_HFXT'), (0b01, 'Submain Clock', '_SMCLK'), (0b10, 'Digitally Controlled Oscillator 0', '_DCO0'), (0b11, 'Digitally Controlled Oscillator 1', '_DCO1')]))

# CLKDIVCR
r = RegisterTemplate(nameTemplate='CLKDIVCR', registerMemorySlot=1, description='MCLK and SMCLK clock divider control register. Configures clock division for main and submain clocks using glitch-free multiplexers.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=6, unused=True))
r.AddBitField(BitField(name='SYSSMCLKDIV', msb=5, lsb=3, accessibility='rw', description='SMCLK clock division selection. Division is applied after clock source selection through glitch-free divider multiplexer.', valueDescriptions=[(0b000, '/1 (no division)', '_1'), (0b001, '/2', '_2'), (0b010, '/4', '_4'), (0b011, '/8', '_8'), (0b100, '/16', '_16'), (0b101, '/32', '_32'), (0b110, '/64', '_64'), (0b111, '/128', '_128')]))
r.AddBitField(BitField(name='SYSMCLKDIV', msb=2, lsb=0, accessibility='rw', description='MCLK clock division selection. Division is applied after clock source selection through glitch-free divider multiplexer.', valueDescriptions=[(0b000, '/1 (no division)', '_1'), (0b001, '/2', '_2'), (0b010, '/4', '_4'), (0b011, '/8', '_8'), (0b100, '/16', '_16'), (0b101, '/32', '_32'), (0b110, '/64', '_64'), (0b111, '/128', '_128')]))

# BLOCKPWR
r = RegisterTemplate(nameTemplate='BLOCKPWR', registerMemorySlot=2, description='Block power control register. Controls power gating for on-chip memory blocks.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=7, lsb=3))
r.AddBitField(BitField(name='SYSRAM1OFF', msb=2, description='RAM block 1 power control. When set, RAM block 1 is powered off. All data becomes undefined and the block no longer responds to memory access. Reduces static power consumption.', accessibility='rw', valueDescriptions=[(0b0, 'RAM block 1 powered on'), (0b1, 'RAM block 1 powered off')]))
r.AddBitField(BitField(name='SYSRAM0OFF', msb=1, description='RAM block 0 power control. When set, RAM block 0 is powered off. All data becomes undefined and the block no longer responds to memory access. Reduces static power consumption.', accessibility='rw', valueDescriptions=[(0b0, 'RAM block 0 powered on'), (0b1, 'RAM block 0 powered off')]))
r.AddBitField(BitField(name='SYSROMOFF', msb=0, description='ROM power control. When set, boot ROM is powered off. ROM no longer responds to read access. Reduces static power consumption.', accessibility='rw', valueDescriptions=[(0b0, 'ROM powered on'), (0b1, 'ROM powered off')]))

# CRCDATA
r = RegisterTemplate(nameTemplate='CRCDATA', registerMemorySlot=3, description='CRC input data register. Write the next byte of data to this register to update the CRC calculation. Uses CRC16-CDMA2000 polynomial 0xC857.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSCRCDATA', msb=7, lsb=0, accessibility='rw', description='CRC data input byte. Writing to this register feeds the byte into the CRC calculation and updates CRCSTATE.'))

# CRCSTATE
r = RegisterTemplate(nameTemplate='CRCSTATE', registerMemorySlot=4, description='CRC state register. Contains the current CRC16 calculation result. Write to this register to initialize or restart the CRC calculation. Read to obtain the computed CRC16 checksum.', size=16)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSCRCSTATE', msb=15, lsb=0, accessibility='rw', description='CRC state value. Initialize to 0xFFFF before starting CRC calculation. Read after processing all data bytes to get final CRC16 checksum.'))

# M19: the IRQENL/M/U, IRQPRIL/M/U and IRQCR registers (slots 5-11) are
# RETIRED — ALL peripheral interrupt routing/masking, hart 0 included, lives
# in the IRQROUTER's per-hart rows (claim/complete delivery, one meip wire
# per hart; priority is fixed lowest-vector-wins). The slots are reserved:
# they read 0 and ignore writes.

# WDTCR
r = RegisterTemplate(nameTemplate='WDTCR', registerMemorySlot=13, size=8, description='Watchdog timer control register. This register is protected and requires password unlock via WDTPASS before writing. Configures watchdog operation mode and timeout period.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSWDTEN', msb=7, accessibility='rw', description='Watchdog timer enable. When set, watchdog counter increments on MCLK. Watchdog generates interrupt and/or reset when counter bit selected by WDTCDIV transitions from 0 to 1. Register is write-protected; unlock with WDTPASS first.', valueDescriptions=[(0b0, 'Watchdog disabled'), (0b1, 'Watchdog enabled')]))
r.AddBitField(BitField(unused=True, msb=6))
r.AddBitField(BitField(name='SYSWDTCDIV', msb=5, lsb=2, accessibility='rw', description='Watchdog timer clock divider select. Selects which bit of the 24-bit counter triggers watchdog event. Event occurs when selected bit transitions from 0 to 1. Timeout period = 2^(WDTCDIV+16) MCLK cycles.', valueDescriptions=[(0b0000, 'Bit 16: 65,536 MCLK cycles', '_65536'), (0b0001, 'Bit 17: 131,072 MCLK cycles', '_131072'), (0b0010, 'Bit 18: 262,144 MCLK cycles', '_262144'), (0b0011, 'Bit 19: 524,288 MCLK cycles', '_524288'), (0b0100, 'Bit 20: 1,048,576 MCLK cycles', '_1048576'), (0b0101, 'Bit 21: 2,097,152 MCLK cycles', '_2097152'), (0b0110, 'Bit 22: 4,194,304 MCLK cycles', '_4194304'), (0b0111, 'Bit 23: 8,388,608 MCLK cycles', '_8388608'), (0b1000, 'Bit 24: 16,777,216 MCLK cycles', '_16777216'), (0b1001, 'Bit 25: 33,554,432 MCLK cycles', '_33554432'), (0b1010, 'Bit 26: 67,108,864 MCLK cycles', '_67108864'), (0b1011, 'Bit 27: 134,217,728 MCLK cycles', '_134217728'), (0b1100, 'Bit 28: 268,435,456 MCLK cycles', '_268435456'), (0b1101, 'Bit 29: 536,870,912 MCLK cycles', '_536870912'), (0b1110, 'Bit 30: 1,073,741,824 MCLK cycles', '_1073741824'), (0b1111, 'Bit 31: 2,147,483,648 MCLK cycles', '_2147483648')]))
r.AddBitField(BitField(name='SYSWDTIE', msb=1, accessibility='rw', description='Watchdog timer interrupt enable. When set, watchdog timeout raises the watchdog interrupt level (vector 0), delivered to whichever hart the IRQROUTER routes it to. After the servicing hart completes the claim (IRQROUTER CLAIM/COMPLETE), the system resets if SYSWDTHWRST is set. If the vector is not routed to any hart, the reset (when enabled) occurs immediately on timeout.', valueDescriptions=[(0b0, 'Watchdog interrupt disabled'), (0b1, 'Watchdog interrupt enabled')]))
r.AddBitField(BitField(name='SYSWDTHWRST', msb=0, accessibility='rw', description='Watchdog hardware reset enable. When set, watchdog timeout causes system reset. If WDTIE is set, reset occurs after interrupt service routine completes. If WDTIE is cleared or IRQ is not enabled, reset occurs immediately on timeout.', valueDescriptions=[(0b0, 'Watchdog reset disabled'), (0b1, 'Watchdog reset enabled')]))

# WDTSR
r = RegisterTemplate(nameTemplate='WDTSR', registerMemorySlot=14, size=8, description='Watchdog timer status register. Contains flags indicating watchdog reset and interrupt events. Flags are cleared by writing 1 to the respective bit.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=7, lsb=2))
r.AddBitField(BitField(name='SYSWDTIF', msb=1, accessibility='rw1', description='Watchdog timer interrupt flag. Set when watchdog timeout occurs and WDTIE is enabled. Cleared by writing 1 to this bit. If not cleared before next timeout, indicates watchdog event occurred.', valueDescriptions=[(0b0, 'No watchdog interrupt pending'), (0b1, 'Watchdog interrupt occurred')]))
r.AddBitField(BitField(name='SYSWDTRF', msb=0, accessibility='rw1', description='Watchdog timer reset flag. Set when system reset was caused by watchdog timer. Persists across resets until cleared by software. Cleared by writing 1 to this bit.', valueDescriptions=[(0b0, 'Reset not caused by watchdog'), (0b1, 'Reset caused by watchdog')]))

# WDTPASS
r = RegisterTemplate(nameTemplate='WDTPASS', registerMemorySlot=12, size=32, description='Watchdog timer password register. Write-only register for two security functions: (1) Write 0x3FB0AD1C to unlock WDTCR for 64 MCLK cycles, enabling writes to watchdog configuration. (2) Write 0xD6F402BC to clear watchdog counter to 0, preventing timeout. Reading always returns 0.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSWDTPASS', msb=31, lsb=0, accessibility='w', description='Watchdog password. Write 0x3FB0AD1C (unlock password) to enable WDTCR writes for 64 MCLK cycles. Write 0xD6F402BC (clear password) to reset watchdog counter to 0.'))

# WDTVAL
r = RegisterTemplate(nameTemplate='WDTVAL', registerMemorySlot=15, size=32, description='Watchdog timer value register. Read-only register containing current watchdog counter value. Counter increments on MCLK when watchdog is enabled. Returns 0 when watchdog is disabled.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSWDTVAL', msb=23, lsb=0, accessibility='r', description='Watchdog counter value. 24-bit up-counter that increments on MCLK cycles. Watchdog event occurs when bit selected by WDTCDIV transitions from 0 to 1.'))
r.AddBitField(BitField(unused=True, msb=31, lsb=24))

# DCO0BIAS
r = RegisterTemplate(nameTemplate='DCO0BIAS', registerMemorySlot=16, size=16, description='Digitally controlled oscillator 0 bias register. Controls DCO0 output frequency through bias voltage adjustment. Higher bias values generally produce higher frequencies.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=15, lsb=12))
r.AddBitField(BitField(name='SYSDCO0BIAS', msb=11, lsb=0, accessibility='rw', description='DCO0 bias adjustment value. 12-bit bias control for DCO0 frequency tuning. Default value loaded from constants on reset.'))

# DCO1BIAS
r = RegisterTemplate(nameTemplate='DCO1BIAS', registerMemorySlot=17, size=16, description='Digitally controlled oscillator 1 bias register. Controls DCO1 output frequency through bias voltage adjustment. Higher bias values generally produce higher frequencies.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=15, lsb=12))
r.AddBitField(BitField(name='SYSDCO1BIAS', msb=11, lsb=0, accessibility='rw', description='DCO1 bias adjustment value. 12-bit bias control for DCO1 frequency tuning. Default value loaded from constants on reset.'))

	
	
''' SPIx '''
p = PeripheralTemplate(nameTemplate='SPIx', description='Serial Peripheral Interface. Supports both master and slave modes with configurable data length (8, 16, or 32 bits), clock polarity, clock phase, and byte ordering. SPI0 includes flash extended memory capability for direct memory-mapped access to external SPI flash. SPI1 supports both master and slave modes without flash extended memory.', registerPrefix='SPIx', bitFieldPrefix='SPI', latexIntroFileName='SPI-intro-castalia-2026-07.tex', latexFeatureSummary='{count} SPI interfaces (SPI0 provides memory-mapped access to external flash memory)')
m.AddPeripheralTemplate(p)

# SPIxCR
r = RegisterTemplate(nameTemplate='SPIxCR', registerMemorySlot=0, description='SPI control register', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=20, unused=True))
r.AddBitField(BitField(name='SPIFEN', msb=19, accessibility='rw', description='SPI Flash extended memory enable. When enabled, allows native read-only memory access to the SPI flash memory via the system memory bus. The SPI peripheral automatically handles flash read commands and provides transparent memory-mapped access. Available only on SPI0; reads as 0 on SPI1.', valueDescriptions=[(0b0, 'Flash extended memory disabled'), (0b1, 'Flash extended memory enabled')]))
r.AddBitField(BitField(name='SPISM', msb=18, accessibility='rw', description='SPI slave mode select. Configures the SPI peripheral for master or slave operation. SPI0 is master-only; this bit has no effect on SPI0. SPI1 supports both master and slave modes.', valueDescriptions=[(0b0, 'Master mode'), (0b1, 'Slave mode')]))
r.AddBitField(BitField(name='SPITXSB', msb=17, accessibility='rw', description='SPI TX swap bytes. Swaps the byte order in 16- and 32-bit transmissions. In 32-bit transmissions, bytes 3 and 0 are swapped and bytes 2 and 1 are swapped. In 16-bit transmissions, bytes 1 and 0 are swapped. Does not affect 8-bit transmissions.', valueDescriptions=[(0b0, 'Bytes not swapped'), (0b1, 'Bytes swapped')]))
r.AddBitField(BitField(name='SPIRXSB', msb=16, accessibility='rw', description='SPI RX swap bytes. Swaps the byte order in 16- and 32-bit receptions. In 32-bit receptions, bytes 3 and 0 are swapped and bytes 2 and 1 are swapped. In 16-bit receptions, bytes 1 and 0 are swapped. Does not affect 8-bit receptions.', valueDescriptions=[(0b0, 'Bytes not swapped'), (0b1, 'Bytes swapped')]))
r.AddBitField(BitField(name='SPIBR', msb=15, lsb=8, description='SPI clock (SCK) baud rate control for master mode. Baud rate = SMCLK / (2 * (1 + SPIBR)). For example, with SMCLK at 24 MHz: SPIBR=0 gives 12 MHz, SPIBR=1 gives 8 MHz, SPIBR=2 gives 6 MHz, SPIBR=5 gives 4 MHz, SPIBR=11 gives 2 MHz, SPIBR=23 gives 1 MHz.', accessibility='rw'))
r.AddBitField(BitField(name='SPIEN', msb=7, description='SPI enable. When disabled, all SPI operations cease and the peripheral is held in reset state.', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='SPIMSB', msb=6, description='Bit endianness select. Determines whether data is transmitted and received MSB-first or LSB-first.', accessibility='rw', valueDescriptions=[(0b0, 'LSB-first'), (0b1, 'MSB-first')]))
r.AddBitField(BitField(name='SPITCIE', msb=5, description='SPI transmit complete interrupt enable. Interrupt triggers when a full SPI transfer (transmit and receive) completes.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='SPITEIE', msb=4, description='SPI transmit register empty interrupt enable. Interrupt triggers when SPIxTX register is empty and ready to accept new data for the next transfer.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='SPIDL', msb=3, lsb=2, description='SPI transmission data length select. Determines the number of bits transferred per SPI transaction.', accessibility='rw', valueDescriptions=[(0b00, '8-bit transfers', '_8'), (0b01, '16-bit transfers', '_16'), (0b10, '32-bit transfers', '_32'), (0b11, 'Reserved (do not use)', '_RES')]))
r.AddBitField(BitField(name='SPICPOL', msb=1, description='SPI clock (SCK) polarity. Determines the idle state of the SCK line.', accessibility='rw', valueDescriptions=[(0b0, 'SCK idles low (SPIMODE0 or SPIMODE1)'), (0b1, 'SCK idles high (SPIMODE2 or SPIMODE3)')]))
r.AddBitField(BitField(name='SPICPHA', msb=0, description='SPI clock (SCK) phase. Determines when data is sampled relative to the SCK edge. In slave mode, only SPICPHA=1 is supported.', accessibility='rw', valueDescriptions=[(0b0, 'Data sampled on leading edge, shifted on trailing edge (SPIMODE0 or SPIMODE2)'), (0b1, 'Data shifted on leading edge, sampled on trailing edge (SPIMODE1 or SPIMODE3)')]))

# SPIxSR
r = RegisterTemplate(nameTemplate='SPIxSR', registerMemorySlot=1, description='SPI status register. Provides real-time status of SPI transfer operations and interrupt flags.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=3, unused=True))
r.AddBitField(BitField(name='SPIBUSY', msb=2, description='Indicates whether a SPI transfer is currently in progress. In master mode, set when a transfer starts and cleared when complete. In slave mode, set when chip select is asserted (driven low) and cleared when deasserted.', accessibility='r', valueDescriptions=[(0b0, 'SPI is idle'), (0b1, 'SPI transfer in progress')]))
r.AddBitField(BitField(name='SPITCIF', msb=1, description='SPI transfer complete interrupt flag. Set when a SPI transfer completes. Must be cleared by writing 1 to this bit or by reading SPIxRX register.', accessibility='rw1', valueDescriptions=[(0b0, 'No transfer completed'), (0b1, 'Transfer completed')]))
r.AddBitField(BitField(name='SPITEIF', msb=0, description='SPI transmit register empty interrupt flag. Set when SPIxTX register is empty and ready to accept new data. The data will not be transmitted until any current transfer completes. Must be cleared by writing 1 to this bit.', accessibility='rw1', valueDescriptions=[(0b0, 'SPIxTX not empty'), (0b1, 'SPIxTX empty and ready')]))

# SPIxTX
r = RegisterTemplate(nameTemplate='SPIxTX', registerMemorySlot=2, description='SPI transmit buffer register. In master mode, writing to this register initiates a new SPI transfer. In slave mode, writing to this register queues data to be transmitted during the next master-initiated transfer. Actual number of bits transmitted is determined by SPIDL setting.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SPITX', msb=31, lsb=0, accessibility='rw'))

# SPIxRX
r = RegisterTemplate(nameTemplate='SPIxRX', registerMemorySlot=3, description='SPI receive buffer register. Contains the data received during the most recent SPI transfer. Reading this register also clears the SPITCIF flag. Valid data width depends on SPIDL setting; unused upper bits read as 0.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SPIRX', msb=31, lsb=0, accessibility='r'))

# SPIxFOS
r = RegisterTemplate(nameTemplate='SPIxFOS', registerMemorySlot=4, description='SPI Flash memory address offset. This 24-bit value is added to memory access addresses when flash extended memory mode is enabled (SPIFEN=1). Allows remapping of flash memory to different virtual addresses. The addition wraps around at 0x00FFFFFF. Available only on SPI0; reads as 0 on SPI1.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=24, unused=True))
r.AddBitField(BitField(name='SPIFOS', msb=23, lsb=0, accessibility='rw'))



''' GPIOx '''
p = PeripheralTemplate(nameTemplate='GPIOx', description='General Purpose Input Output', registerPrefix='Px', bitFieldPrefix='Px', latexIntroFileName='GPIO-intro-castalia-2026-07.tex', latexFeatureSummary='{count} 8-pin general purpose I/O (GPIO) ports with edge-triggered interrupts and per-pin multiplexed alternate functions (GPIO + up to 8 alternate functions per pin)')
m.AddPeripheralTemplate(p)

# PxIN
r = RegisterTemplate(nameTemplate='PxIN', registerMemorySlot=0, description='GPIO read pin register. Each bit corresponds to the input logic state of the GPIO pin of the same number. The register is latched on the falling edge of the memory enable signal. Reading a 0 in a bit indicates a logic low pin state; reading a 1 indicates a logic high state. This register always reflects the pin state regardless of pin direction or peripheral select settings.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxIN', msb=31, lsb=0, accessibility='r'))

# PxOUT
r = RegisterTemplate(nameTemplate='PxOUT', registerMemorySlot=1, description='GPIO output drive register. Each bit corresponds to the output logic state of the GPIO pin of the same number. Only has an effect if the pin is configured as an output in PxDIR and is set to GPIO (primary) mode in PxSEL. Write a 0 to the desired bit to make the corresponding pin output a logic low value; write a 1 to output a logic high value.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxOUT', msb=31, lsb=0, accessibility='rw'))

# PxOUTS
r = RegisterTemplate(nameTemplate='PxOUTS', registerMemorySlot=2, description='GPIO output drive set register. Each bit corresponds to the output logic state of the GPIO pin of the same number. Only has an effect if the pin is configured as an output in PxDIR and is in GPIO (primary) mode in PxSEL. Write a 1 to the desired bit to set the corresponding pin (make the pin output a logic high value). Writing a 0 has no effect. Reading this register is equivalent to reading the output drive register PxOUT.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxOUTS', msb=31, lsb=0, accessibility='rw1'))

# PxOUTC
r = RegisterTemplate(nameTemplate='PxOUTC', registerMemorySlot=3, description='GPIO output drive clear register. Each bit corresponds to the output logic state of the GPIO pin of the same number. Only has an effect if the pin is configured as an output in PxDIR and is in GPIO (primary) mode in PxSEL. Write a 1 to the desired bit to clear the corresponding pin (make the pin output a logic low value). Writing a 0 has no effect. Reading this register yields the inversion of the output drive register PxOUT.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxOUTC', msb=31, lsb=0, accessibility='rw1'))

# PxOUTT
r = RegisterTemplate(nameTemplate='PxOUTT', registerMemorySlot=4, description='GPIO output drive toggle register. Each bit corresponds to the output logic state of the GPIO pin of the same number. Only has an effect if the pin is configured as an output in PxDIR and is in GPIO (primary) mode in PxSEL. Write a 1 to the desired bit to toggle the corresponding pin state. Writing a 0 has no effect. Reading this register is equivalent to reading the output drive register PxOUT.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxOUTT', msb=31, lsb=0, accessibility='rw1'))

# PxDIR
r = RegisterTemplate(nameTemplate='PxDIR', registerMemorySlot=5, description='GPIO pin direction register. Each bit corresponds to the GPIO pin of the same number. Only has an effect if the pin is configured in GPIO (primary) mode in PxSEL. Write a 0 to the desired bit to set the corresponding pin to input mode; write a 1 to set to output mode.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxDIR', msb=31, lsb=0, accessibility='rw'))

# PxIF
r = RegisterTemplate(nameTemplate='PxIF', registerMemorySlot=6, description='GPIO interrupt flag register. Each bit corresponds to the GPIO pin of the same number. The register is latched on the falling edge of the memory enable signal. Reading a 0 in a bit indicates there is no pending interrupt for the corresponding pin; reading a 1 indicates there is a new interrupt pending for the corresponding pin. Write a 1 to each bit for which you wish to clear the interrupt flag. Writing 0 has no effect.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxIF', msb=31, lsb=0, accessibility='rw1'))

# PxIES
r = RegisterTemplate(nameTemplate='PxIES', registerMemorySlot=7, description='GPIO interrupt edge select register. Each bit corresponds to the GPIO pin of the same number. Write a 0 to the desired bit to set the corresponding pin interrupt to trigger on low-to-high (rising) edge; write a 1 to set to high-to-low (falling) edge triggering.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxIES', msb=31, lsb=0, accessibility='rw'))

# PxIE
r = RegisterTemplate(nameTemplate='PxIE', registerMemorySlot=8, description='GPIO interrupt enable register. Each bit corresponds to the GPIO pin of the same number. Write a 0 to the desired bit to disable the pin interrupt; write a 1 to enable the pin interrupt. Each pin has an individual interrupt output that connects to the system interrupt vector table. Interrupts function in both GPIO (primary) and secondary function (peripheral) modes.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxIE', msb=31, lsb=0, accessibility='rw'))

# PxSEL
r = RegisterTemplate(nameTemplate='PxSEL', registerMemorySlot=9, description='GPIO peripheral select register. Each bit corresponds to the GPIO pin of the same number. Write a 0 to the desired bit to set the corresponding pin to GPIO (primary) mode; write a 1 to set the pin to alternate function (peripheral) mode. When a pin is in alternate function (peripheral) mode, the governing peripheral takes control of the pin output, direction, and resistor enable states, and the PxOUT, PxDIR, and PxREN registers have no effect on the pin. WHICH alternate function governs the pin is selected by the pin\'s field in the PxAFS register: at reset all PxAFS fields are 0, selecting alternate function 0 (AF0). Pin interrupts remain available when in alternate function (peripheral) mode in addition to any interrupts the governing peripheral may generate. If a pin has no alternate function defined at the selected PxAFS plane, setting PxSEL to 1 will configure the pin as a high-impedance input.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxSEL', msb=31, lsb=0, accessibility='rw'))

# PxREN
r = RegisterTemplate(nameTemplate='PxREN', registerMemorySlot=10, description='GPIO resistor enable register. Each bit corresponds to the GPIO pin of the same number. Only has an effect if the pin is configured in GPIO (primary) mode in PxSEL. Write a 0 to the desired bit to disable the pin pullup/pulldown resistor; write a 1 to enable the pin pullup/pulldown resistor.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxREN', msb=31, lsb=0, accessibility='rw'))

# PxAFS
r = RegisterTemplate(nameTemplate='PxAFS', registerMemorySlot=11, description='GPIO alternate function select register. One 4-bit field per pin (pin y occupies bits 4y+3 downto 4y; only the low 3 bits of each field are implemented, the top bit is reserved and reads 0). When a pin is in alternate function (peripheral) mode (PxSEL bit = 1), the value of its PxAFS field selects WHICH alternate function (AF0-AF7) controls the pin. Each pin\'s available alternate functions are listed in the pin configuration table in Section \\ref{s:pinsConfig}. The register resets to 0, so every pin comes out of reset selecting its AF0 (legacy) function. Selecting an AF plane with no function defined for the pin configures the pin as a high-impedance input. While a pin is in GPIO (primary) mode its PxAFS field has no effect on the pad, but it still routes relocatable peripheral INPUTS: a peripheral input function relocated to this pin (e.g. a UART receiver or timer capture) observes the pin whenever the PxAFS field selects it, regardless of PxSEL.', size=32)
p.AddRegisterTemplate(r)

for _pin in range(8):
	r.AddBitField(BitField(name='PxAFS' + str(_pin), msb=(4 * _pin) + 2, lsb=4 * _pin, accessibility='rw', description='Alternate function select for pin ' + str(_pin) + ' (0 = AF0 ... 7 = AF7)'))
	r.AddBitField(BitField(msb=(4 * _pin) + 3, lsb=(4 * _pin) + 3, unused=True))

## PxOCEN
#r = RegisterTemplate(nameTemplate='PxOCEN', registerMemorySlot=10, description='GPIO open collector register. Each bit corresponds to the GPIO pin of the same number. Only has an effect if the pin is configured in GPIO (primary) mode in PxSEL. Write a 0 to the desired bit to disable the pin open-collector mode; write a 1 to enable the pin open-collector mode.', size=32)
#p.AddRegisterTemplate(r)



''' UARTx '''
p = PeripheralTemplate(nameTemplate='UARTx', description='Full-duplex Universal Asynchronous Receiver/Transmitter with hardware parity support', registerPrefix='UARTx', bitFieldPrefix='U', latexIntroFileName='UART-intro-castalia-2026-07.tex', latexFeatureSummary='{count} UART interfaces with hardware parity support')
m.AddPeripheralTemplate(p)

# UARTxCR
r = RegisterTemplate(nameTemplate='UARTxCR', registerMemorySlot=0, description='UART control register. Controls UART enable, parity configuration, and interrupt enable bits. When UCR.EN is disabled, the UART peripheral is held in reset state.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=7, lsb=6, unused=True))
r.AddBitField(BitField(name='UEN', msb=5, description='UART enable. When disabled, the UART peripheral is in reset state and the transmitter is idle.', accessibility='rw', valueDescriptions=[(0b0, 'UART disabled'), (0b1, 'UART enabled')]))
r.AddBitField(BitField(name='UPEN', msb=4, description='Parity enable. Enables parity generation on transmit and parity checking on receive.', accessibility='rw', valueDescriptions=[(0b0, 'Parity disabled'), (0b1, 'Parity enabled')]))
r.AddBitField(BitField(name='PSEL', msb=3, description='Parity select. Selects even or odd parity when parity is enabled.', accessibility='rw', valueDescriptions=[(0b0, 'Even parity'), (0b1, 'Odd parity')]))
r.AddBitField(BitField(name='CIE', msb=2, description='Receive complete interrupt enable. Enables interrupt generation when a byte is successfully received.', accessibility='rw', valueDescriptions=[(0b0, 'RX complete interrupt disabled'), (0b1, 'RX complete interrupt enabled')]))
r.AddBitField(BitField(name='TEIE', msb=1, description='Transmit empty interrupt enable. Enables interrupt generation when the transmit buffer becomes empty and ready for new data.', accessibility='rw', valueDescriptions=[(0b0, 'TX empty interrupt disabled'), (0b1, 'TX empty interrupt enabled')]))
r.AddBitField(BitField(name='TCIE', msb=0, description='Transmit complete interrupt enable. Enables interrupt generation when transmission is complete and the transmitter is idle.', accessibility='rw', valueDescriptions=[(0b0, 'TX complete interrupt disabled'), (0b1, 'TX complete interrupt enabled')]))

# UARTxSR
r = RegisterTemplate(nameTemplate='UARTxSR', registerMemorySlot=1, description='UART status register. Contains receiver and transmitter status flags and interrupt flags. Error flags (FEF, PEF, OVF, RCIF) are cleared by reading UARTxRX. Interrupt flags (RCIF, TEIF, TCIF) can also be cleared by writing a 1 to the respective bit.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='RXBF', msb=7, description='Receiver busy flag. Set while the UART receiver is actively receiving a byte.', accessibility='r', valueDescriptions=[(0b0, 'Receiver idle'), (0b1, 'Reception in progress')]))
r.AddBitField(BitField(name='TXBF', msb=6, description='Transmitter busy flag. Set while the UART transmitter is actively transmitting a byte or has a pending transmission.', accessibility='r', valueDescriptions=[(0b0, 'Transmitter idle'), (0b1, 'Transmission in progress')]))
r.AddBitField(BitField(name='FEF', msb=5, description='Framing error flag. Set when the stop bit is not detected (RX line not high at expected stop bit time). Cleared by reading UARTxRX.', accessibility='r', valueDescriptions=[(0b0, 'No framing error'), (0b1, 'Framing error detected on last reception')]))
r.AddBitField(BitField(name='PEF', msb=4, description='Parity error flag. Set when received parity does not match expected parity (when parity is enabled). Cleared by reading UARTxRX.', accessibility='r', valueDescriptions=[(0b0, 'No parity error'), (0b1, 'Parity error detected on last reception')]))
r.AddBitField(BitField(name='OVF', msb=3, description='Receive overflow flag. Set when a new byte is received before the previous byte in UARTxRX was read by the processor. Cleared by reading UARTxRX.', accessibility='r', valueDescriptions=[(0b0, 'No receive data overrun'), (0b1, 'Receive data overflow detected')]))
r.AddBitField(BitField(name='RCIF', msb=2, description='Receive complete interrupt flag. Set when a byte is successfully received and placed in UARTxRX. Cleared by reading UARTxRX or writing a 1 to this bit.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending RX complete interrupt'), (0b1, 'RX complete interrupt pending')]))
r.AddBitField(BitField(name='TEIF', msb=1, description='Transmit empty interrupt flag. Set when the transmit buffer is empty and ready to accept new data. Write a 1 to this bit to clear it.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending TX empty interrupt'), (0b1, 'TX empty interrupt pending')]))
r.AddBitField(BitField(name='TCIF', msb=0, description='Transmit complete interrupt flag. Set when transmission is complete (all bits sent) and the transmitter is idle. Write a 1 to this bit to clear it.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending TX complete interrupt'), (0b1, 'TX complete interrupt pending')]))

# UARTxBR
r = RegisterTemplate(nameTemplate='UARTxBR', registerMemorySlot=2, description='UART baud rate register. Configures the baud rate divisor for the UART. The UART uses 16× oversampling.', size=16)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=15, lsb=12, unused=True))
r.AddBitField(BitField(name='BR', msb=11, lsb=0, description='Baud rate divisor. UART baud rate = SMCLK ÷ (16 × (BR + 1)). For example, with SMCLK = 48 MHz: BR = 25 gives 115,200 baud; BR = 51 gives 57,600 baud; BR = 103 gives 28,800 baud.', accessibility='rw'))

# UARTxRX
r = RegisterTemplate(nameTemplate='UARTxRX', registerMemorySlot=3, description='UART receive buffer register. Contains the last received byte. Reading this register clears the FEF, PEF, OVF, and RCIF flags in UARTxSR. The value is latched on the falling edge of the memory enable signal.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='RX', msb=7, lsb=0, description='Received data byte', accessibility='r'))

# UARTxTX
r = RegisterTemplate(nameTemplate='UARTxTX', registerMemorySlot=4, description='UART transmit buffer register. Writing to this register loads the byte to transmit and initiates transmission. Do not write to this register while TXBF is set in UARTxSR.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='TX', msb=7, lsb=0, description='Transmit data byte', accessibility='rw'))



''' TIMERx '''
p = PeripheralTemplate(nameTemplate='TIMERx', description='32-bit Timer/Counter with input capture, output compare, and pulse-width modulation functionality. Features glitch-free clock source switching and configurable clock division.', registerPrefix='TIMx', bitFieldPrefix='T', latexIntroFileName='TIMER-intro-castalia-2026-07.tex', latexFeatureSummary='{count} 32-bit timers with pulse-width modulation outputs and input capture units')
m.AddPeripheralTemplate(p)

# TIMxCR
r = RegisterTemplate(nameTemplate='TIMxCR', registerMemorySlot=0, description='Timer/Counter control register. Configures clock source, clock divider, capture/compare settings, and interrupt enables.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=20, unused=True))
r.AddBitField(BitField(name='DIV', msb=19, lsb=16, description='Timer/Counter clock divider. Divides the clock source selected by SSEL to generate the timer clock for TIMxVAL increments.', accessibility='rw', valueDescriptions=[(0, '/1 (no division)', '_1'), (1, '/2', '_2'), (2, '/4', '_4'), (3, '/8', '_8'), (4, '/16', '_16'), (5, '/32', '_32'), (6, '/64', '_64'), (7, '/128', '_128'), (8, '/256', '_256'), (9, '/512', '_512'), (10, '/1,024', '_1024'), (11, '/2,048', '_2048'), (12, '/4,096', '_4096'), (13, '/8,192', '_8192'), (14, '/16,384', '_16384'), (15, '/32,768', '_32768')]))
r.AddBitField(BitField(name='CMP1IH', msb=15, description='Compare 1 initial PWM output level. Sets the TxCMP1 pin level when TIMxVAL < TIMxCMP1.', accessibility='rw', valueDescriptions=[(0b0, 'PWM output starts LOW'), (0b1, 'PWM output starts HIGH')]))
r.AddBitField(BitField(name='CMP0IH', msb=14, description='Compare 0 initial PWM output level. Sets the TxCMP0 pin level when TIMxVAL < TIMxCMP0.', accessibility='rw', valueDescriptions=[(0b0, 'PWM output starts LOW'), (0b1, 'PWM output starts HIGH')]))
r.AddBitField(BitField(name='CAP1FE', msb=13, description='Capture 1 edge select. Selects which edge on TxCAP1 pin triggers a capture event.', accessibility='rw', valueDescriptions=[(0b0, 'Capture on rising edge'), (0b1, 'Capture on falling edge')]))
r.AddBitField(BitField(name='CAP0FE', msb=12, description='Capture 0 edge select. Selects which edge on TxCAP0 pin triggers a capture event.', accessibility='rw', valueDescriptions=[(0b0, 'Capture on rising edge'), (0b1, 'Capture on falling edge')]))
r.AddBitField(BitField(name='CAP1EN', msb=11, description='Capture 1 enable. Enables input capture on TxCAP1 pin.', accessibility='rw', valueDescriptions=[(0b0, 'Capture 1 disabled'), (0b1, 'Capture 1 enabled')]))
r.AddBitField(BitField(name='CAP0EN', msb=10, description='Capture 0 enable. Enables input capture on TxCAP0 pin.', accessibility='rw', valueDescriptions=[(0b0, 'Capture 0 disabled'), (0b1, 'Capture 0 enabled')]))
r.AddBitField(BitField(name='SSEL', msb=9, lsb=8, description='Timer/Counter clock source select. Glitch-free multiplexer prevents spurious transitions when switching sources.', accessibility='rw', valueDescriptions=[(0b00, 'SMCLK', '_SMCLK'), (0b01, 'MCLK', '_MCLK'), (0b10, 'LFXT (low frequency crystal)', '_LFXT'), (0b11, 'HFXT (high frequency crystal)', '_HFXT')]))
r.AddBitField(BitField(name='CMP2RST', msb=7, description='Timer/Counter reset on Compare 2 enable. Resets TIMxVAL to 0 when TIMxVAL equals TIMxCMP2.', accessibility='rw', valueDescriptions=[(0b0, 'Free-running mode (resets at 2³²-1)'), (0b1, 'Resets on TIMxVAL = TIMxCMP2')]))
r.AddBitField(BitField(name='TEN', msb=6, description='Timer/Counter enable. When disabled, timer clock is gated off and TIMxVAL holds its value.', accessibility='rw', valueDescriptions=[(0b0, 'Timer disabled'), (0b1, 'Timer enabled')]))
r.AddBitField(BitField(name='CAP1IE', msb=5, description='Capture 1 interrupt enable. Enables interrupt when CAP1IF flag is set.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='CAP0IE', msb=4, description='Capture 0 interrupt enable. Enables interrupt when CAP0IF flag is set.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='OVIE', msb=3, description='Timer/Counter overflow interrupt enable. Enables interrupt when OVIF flag is set.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='CMP2IE', msb=2, description='Compare 2 interrupt enable. Enables interrupt when CMP2IF flag is set.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='CMP1IE', msb=1, description='Compare 1 interrupt enable. Enables interrupt when CMP1IF flag is set.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='CMP0IE', msb=0, description='Compare 0 interrupt enable. Enables interrupt when CMP0IF flag is set.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
# TIMxSR
r = RegisterTemplate(nameTemplate='TIMxSR', registerMemorySlot=1, description='Timer/Counter status register. Contains current compare output levels and interrupt flags. The register is latched on the falling edge of the memory enable signal for stable reads.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CMP1OUT', msb=7, description='Current value of the Compare 1 output pin TxCMP1. Reflects the actual PWM output level.', accessibility='r', valueDescriptions=[(0b0, 'TxCMP1 output LOW'), (0b1, 'TxCMP1 output HIGH')]))
r.AddBitField(BitField(name='CMP0OUT', msb=6, description='Current value of the Compare 0 output pin TxCMP0. Reflects the actual PWM output level.', accessibility='r', valueDescriptions=[(0b0, 'TxCMP0 output LOW'), (0b1, 'TxCMP0 output HIGH')]))
r.AddBitField(BitField(name='CAP1IF', msb=5, description='Capture 1 interrupt flag. Set when TxCAP1 pin triggers a capture event. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending capture 1 interrupt'), (0b1, 'Capture 1 interrupt pending')]))
r.AddBitField(BitField(name='CAP0IF', msb=4, description='Capture 0 interrupt flag. Set when TxCAP0 pin triggers a capture event. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending capture 0 interrupt'), (0b1, 'Capture 0 interrupt pending')]))
r.AddBitField(BitField(name='OVIF', msb=3, description='Timer/Counter overflow interrupt flag. Set when timer overflows from 2³²-1 to 0. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending overflow interrupt'), (0b1, 'Overflow interrupt pending')]))
r.AddBitField(BitField(name='CMP2IF', msb=2, description='Compare 2 interrupt flag. Set when TIMxVAL equals TIMxCMP2. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending compare 2 interrupt'), (0b1, 'Compare 2 interrupt pending')]))
r.AddBitField(BitField(name='CMP1IF', msb=1, description='Compare 1 interrupt flag. Set when TIMxVAL equals TIMxCMP1. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending compare 1 interrupt'), (0b1, 'Compare 1 interrupt pending')]))
r.AddBitField(BitField(name='CMP0IF', msb=0, description='Compare 0 interrupt flag. Set when TIMxVAL equals TIMxCMP0. Write 1 to clear.', accessibility='rw1', valueDescriptions=[(0b0, 'No pending compare 0 interrupt'), (0b1, 'Compare 0 interrupt pending')]))

# TIMxVAL
r = RegisterTemplate(nameTemplate='TIMxVAL', registerMemorySlot=2, description='Timer/Counter value register. Reads the current timer count. Writes immediately update the timer value regardless of enable state. The value is latched on the falling edge of the memory enable signal for stable reads.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='VAL', msb=31, lsb=0, description='Current timer count value', accessibility='rw'))

# TIMxCMP0
r = RegisterTemplate(nameTemplate='TIMxCMP0', registerMemorySlot=3, description='Timer/Counter Compare 0 threshold register. When TIMxVAL equals this value, CMP0IF is set and the TxCMP0 PWM output toggles.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CMP0', msb=31, lsb=0, description='Compare 0 threshold value', accessibility='rw'))

# TIMxCMP1
r = RegisterTemplate(nameTemplate='TIMxCMP1', registerMemorySlot=4, description='Timer/Counter Compare 1 threshold register. When TIMxVAL equals this value, CMP1IF is set and the TxCMP1 PWM output toggles.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CMP1', msb=31, lsb=0, description='Compare 1 threshold value', accessibility='rw'))

# TIMxCMP2
r = RegisterTemplate(nameTemplate='TIMxCMP2', registerMemorySlot=5, description='Timer/Counter Compare 2 threshold register. When TIMxVAL equals this value, CMP2IF is set. If CMP2RST is enabled, timer resets to 0 (PWM period control).', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CMP2', msb=31, lsb=0, description='Compare 2 threshold value (PWM period)', accessibility='rw'))

# TIMxCAP0
r = RegisterTemplate(nameTemplate='TIMxCAP0', registerMemorySlot=6, description='Timer/Counter Capture 0 value register. Automatically latches TIMxVAL when TxCAP0 pin edge triggers a capture event. The captured value is latched on the falling edge of the memory enable signal for stable reads.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CAP0', msb=31, lsb=0, description='Captured timer value from TxCAP0 event', accessibility='r'))

# TIMxCAP1
r = RegisterTemplate(nameTemplate='TIMxCAP1', registerMemorySlot=7, description='Timer/Counter Capture 1 value register. Automatically latches TIMxVAL when TxCAP1 pin edge triggers a capture event. The captured value is latched on the falling edge of the memory enable signal for stable reads.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='CAP1', msb=31, lsb=0, description='Captured timer value from TxCAP1 event', accessibility='r'))



''' I2Cx '''
i2cDescription = 'I2C serial port interface. The master and slave I2C interfaces are split between two sets of registers.\n\n'
i2cDescription += 'To use master transmitter mode, first configure the I2C peripheral by setting I2CMEN, clearing I2CSEN, and configuring I2CMDIV with the appropriate clock division factor, noting that the I2C clock source is SMCLK. To send a start condition, set I2CMST, wait for the I2CMSTS flag to be set (if the bus is busy, the I2C peripheral will wait for it to become idle and then send a start condition), and then clear the status register. I2CMCB will now indicate that the I2C peripheral now has control of the bus as its master. Next, write to I2CxMTX the desired slave address in the most significant 7 bits followed by the desired read/write bit (0 for write/master transmitter) in the least significant bit. Then, wait for I2CMXC or I2CMARB to be set. If I2CMARB is set, then the I2C peripheral has lost the bus arbitration contest and has released control of the bus. If I2CMNR is set, then the desired slave has not acknowledged itself. Clear the status register. Next, send the slave a byte of data by writing the desired data to I2CxMTX. When the I2C peripheral is ready for another byte of data to be queued for transmission, the I2CMTXE flag will be set. Again, wait for I2CMXC or I2CMARB, then check I2CMARB and I2CMNR, and finally clear the status register. Once finished sending all of the desired bytes, either send a stop condition to release control of the bus by setting I2CMSP, or send a repeated start condition to retain control of the bus with a new transmission (and possibly a new slave and read/write mode) by setting I2CMST. Once a stop condition is sent, wait for I2CMSTS to be set, indicating that a stop condition has been sent. Clear the status register.\n\n'
i2cDescription += 'To use master receiver mode, first configure the I2C peripheral by setting I2CMEN, clearing I2CSEN, and configuring I2CMDIV with the appropriate clock division factor, noting that the I2C clock source is SMCLK. To send a start condition, set I2CMST, wait for the I2CMSTS flag to be set (if the bus is busy, the I2C peripheral will wait for it to become idle and then send a start condition), and then clear the status register. I2CMCB will now indicate that the I2C peripheral now has control of the bus as its master. Next, write to I2CxMTX the desired slave address in the most significant 7 bits followed by the desired read/write bit (1 for read/master receiver) in the least significant bit. Then, wait for I2CMXC or I2CMARB to be set. If I2CMARB is set, then the I2C peripheral has lost the bus arbitration contest and has released control of the bus. If I2CMNR is set, then the desired slave has not acknowledged itself. Clear the status register. Next, begin to receive a byte of data from the slave by setting I2CMRB. Wait for I2CMXC to be set. Clear the status register. Read I2CxMRX to get the byte of data received from the slave. To send the slave an ACK and begin to read another byte from the slave, set I2CMRB. Or, to send the slave a NACK and send a stop condition, set I2CMSP. Or, to send the slave a NACK and send a repeated start condition, set I2CMST. Wait for the appropriate flag, then clear the status register.\n\n'
i2cDescription += 'To use slave receiver mode, first configure the I2C peripheral by setting I2CSEN, clearing I2CSEN, clearing I2CSN, and configuring I2CSCS and I2CGCE to the desired values. Note that if clock stretching is enabled with I2CSCS, the I2C peripheral will seize control of the bus by driving SCL low during every ACK/NACK bit transfer (if the I2C peripheral was addressed) until I2CSC is set, which requires user intervention to prevent indefinite hold-ups of the I2C bus. But, if clock stretching is not enabled, the master will be allowed full control of the rate data is sent over the bus, which opens the possibility that the software running on this MCU does not notice that a byte has been transferred in time before the next is transferred. Note that if I2CGCE is set, the I2C peripheral will be addressed if either its address is received or if the general call is received. Wait for the I2C peripheral to be addressed when I2CSA is set. Check I2CSTM to see if the master has requested slave receiver or slave transmitter mode (0 indicates slave receiver). Clear the status register. If clock stretching is enabled, send an ACK or NACK by clearing or setting I2CSN, and then set I2CSC to release SDA and continue with the transfer. If clock stretching is not enabled, the I2C peripheral will automatically ACK or NACK depending on the value of I2CSN. Next, wait for the slave to receive a data byte from the master when I2CSXC is set. If I2CSOVF is set, then the MCU has failed to read one of the bytes sent by the master in the past. Clear the status register, and then read I2CSRX to get the data byte sent from the master. If clock stretching is enabled, send an ACK or NACK by clearing or setting I2CSN, and then set I2CSC to release SDA and continue with the transfer. If clock stretching is not enabled, the I2C peripheral will automatically ACK or NACK depending on the value of I2CSN. Next, wait for I2CSXC, I2CSPR, or I2CSTR to be set, indicating the I2C peripheral has received a new byte of data, a stop condition, or a repeated start condition. If a stop or start condition has been received, clear the status register.\n\n'
i2cDescription += 'To use slave transmitter mode, first configure the I2C peripheral by setting I2CSEN, clearing I2CSEN, clearing I2CSN, and configuring I2CSCS and I2CGCE to the desired values. Note that if clock stretching is enabled with I2CSCS, the I2C peripheral will seize control of the bus by driving SCL low during every ACK/NACK bit transfer (if the I2C peripheral was addressed) until I2CSC is set, which requires user intervention to prevent indefinite hold-ups of the I2C bus. But, if clock stretching is not enabled, the master will be allowed full control of the rate data is sent over the bus, which opens the possibility that the software running on this MCU does not notice that a byte has been transferred in time before the next is transferred. Check I2CSTM to see if the master has requested slave receiver or slave transmitter mode (1 indicates slave transmitter). Clear the status register. Queue the byte of data to transmit to the master by writing the byte to I2CSTX. If clock stretching is enabled, set I2CSC to release SDA and continue with the transfer. If clock stretching is not enabled, the I2C peripheral will automatically ACK or NACK depending on the value of I2CSN. Wait for I2CSTXE to be set, indicating that the I2C peripheral is ready to queue the next byte to send to the master. Clear the status register, and write the next byte to send to the master to I2CxSTX. If clock stretching is enabled, wait for I2CSXC to be set, clear the status register, and set I2CSC. Wait for I2CSTXE, I2CSPR, or I2CSTR to be set, then clear the status register.'
p = PeripheralTemplate(nameTemplate='I2Cx', description=i2cDescription, registerPrefix='I2Cx', bitFieldPrefix='I2C', latexFeatureSummary='{count} I$^2$C interfaces (both master and slave mode)')
m.AddPeripheralTemplate(p)

# I2CxCR
r = RegisterTemplate(nameTemplate='I2CxCR', registerMemorySlot=0, description='I2C control register', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CSPRIE', msb=0, accessibility='rw', description='I2C stop received interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CSTRIE', msb=1, accessibility='rw', description='I2C start received interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMXCIE', msb=2, accessibility='rw', description='I2C master transfer complete interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMNRIE', msb=3, accessibility='rw', description='I2C master mode NACK received interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMTXEIE', msb=4, accessibility='rw', description='I2C master transmit register empty interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMARBIE', msb=5, accessibility='rw', description='I2C master mode arbitration error interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMSPSIE', msb=6, accessibility='rw', description='I2C master mode stop condition sent interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMSTSIE', msb=7, accessibility='rw', description='I2C master mode start condition sent interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CSXCIE', msb=8, accessibility='rw', description='I2C slave mode transfer complete interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CSNRIE', msb=9, accessibility='rw', description='I2C slave mode NACK received from master interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CSOVFIE', msb=10, accessibility='rw', description='I2C slave receive register overflow interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CSTXEIE', msb=11, accessibility='rw', description='I2C slave transmit register empty interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CSAIE', msb=12, accessibility='rw', description='I2C slave mode addressed interrupt enable', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='I2CMDIV', msb=16, lsb=13, accessibility='rw', description='I2C master mode clock divider. The master mode finite state machine clock source is SMCLK, which is divided by a factor of 4 * 2**I2CMDIV.', valueDescriptions=[(0, '/1 (no division)', '_1'), (1, '/2', '_2'), (2, '/4', '_4'), (3, '/8', '_8'), (4, '/16', '_16'), (5, '/32', '_32'), (6, '/64', '_64'), (7, '/128', '_128'), (8, '/256', '_256'), (9, '/512', '_512'), (10, '/1,024', '_1024'), (11, '/2,048', '_2048'), (12, '/4,096', '_4096'), (13, '/8,192', '_8192'), (14, '/16,384', '_16384'), (15, '/32,768', '_32768')]))
r.AddBitField(BitField(name='I2CGCE', msb=17, accessibility='rw', description='I2C slave general call enable. When enabled, this slave will be addressed if a global call is issued on the bus.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='I2CSCS', msb=18, accessibility='rw', description='I2C slave clock stretching enable. When enabled, this slave will hold the SCL line low during the ACK phase of the transmission to allow this slave more time. Note that the master will be left waiting for the ACK/NACK as long as this bit is set to 1.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='I2CSN', msb=19, accessibility='rw', description='I2C slave NACK next byte received. When enabled, this slave will reply with a NACK whenever it receives its address or whenever it receives a byte from a master. When disabled, it will send an ACK in those situations. If clock stretching is enabled, this bit can be changed in accordance with the desired ACK/NACK reply before allowing a rising edge of SCL.', valueDescriptions=[(0b0, 'ACK'), (0b1, 'NACK')]))
r.AddBitField(BitField(name='I2CSEN', msb=20, accessibility='rw', description='I2C slave enable. When enabled, this device behaves as an I2C slave and begins listening for its address. If master mode is also enabled on this device, then this device will act as a slave until commanded to send a start condition with I2CMST, whereupon it will begin acting as a master. Once the master transfer is complete, it will resume acting as a slave.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='I2CMEN', msb=21, accessibility='rw', description='I2C master enable. When enabled, this device awaits a command to send a start condition with I2CMST, and then begins acting as a master until commanded to send a stop condition with I2CMSP. If master mode is also enabled on this device, then this device will act as a slave until commanded to send a start condition with I2CMST, whereupon it will begin acting as a master. Once the master transfer is complete, it will resume acting as a slave.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(msb=31, lsb=22, unused=True))

# I2CxFCR
r = RegisterTemplate(nameTemplate='I2CxFCR', registerMemorySlot=1, description='I2C flow control register. Writing a 1 to a bit in this register initiates or queues the associated command. Writing a 0 to a bit does nothing. Reading this register always returns the value 0.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CMRB', msb=0, accessibility='w1', description='I2C master read byte command. Set this bit to 1 while in master receiver mode to read one byte from the slave. This master is required to have already sent the slave address and received an ACK from the slave before initiating this command.', valueDescriptions=[(0b0, 'No effect'), (0b1, 'Read next byte')]))
r.AddBitField(BitField(name='I2CMSP', msb=1, accessibility='w1', description='I2C master send stop condition command. Set this bit to 1 while this master is in control of the bus to send a stop condition. This master is required to have already sent a start condition and at least one address frame before initiating this command. If this master is busy with a transaction when this bit is set, then it will send the stop condition immediately after it finishes the transaction.', valueDescriptions=[(0b0, 'No effect'), (0b1, 'Send a stop condition')]))
r.AddBitField(BitField(name='I2CMST', msb=2, accessibility='w1', description='I2C master send start condition command. Set this bit to 1 to send a start condition or a repeated start condition. Once this bit is set, this master is required to send at least one address frame before initiating this command again. If another master has control of the bus when this bit is set, this master will wait until the bus is idle before seizing control of it and sending the start condition. If this master is busy with a transaction when this bit is set, then it will send a restart condition immediately after it finishes the transaction.', valueDescriptions=[(0b0, 'No effect'), (0b1, 'Send a start condition')]))
r.AddBitField(BitField(name='I2CSC', msb=3, accessibility='w1', description='I2C slave continue command. When clock stretching is enabled in slave mode, set this bit to tell the slave to continue with the ACK/NACK phase of the current byte by releasing SCL. This may only be set if clock stretching is enabled, slave mode is enabled, and the slave transfer complete flag has just been set.', valueDescriptions=[(0b0, 'No effect'), (0b1, 'Send a start condition')]))
r.AddBitField(BitField(msb=7, lsb=4, unused=True))

# I2CxSR
r = RegisterTemplate(nameTemplate='I2CxSR', registerMemorySlot=2, description='I2C status register', size=16)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CSPR', msb=0, accessibility='rw1', description='I2C stop condition received interrupt flag. This flag is set whenever a stop condition condition is detected on the bus, regardless of which device sent it. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSTR', msb=1, accessibility='rw1', description='I2C start condition received interrupt flag. This flag is set whenever a start condition or repeated start condition is detected on the bus, regardless of if this master or another sent it. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CMXC', msb=2, accessibility='rw1', description='I2C master transfer complete interrupt flag. In master transmitter mode, this flag is set after this master has sent the data byte and the slave has sent an ACK/NACK. In master receiver mode, this flag is set after the slave has sent the data byte and before this master sends an ACK/NACK. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CMNR', msb=3, accessibility='rw1', description='I2C master mode NACK received interrupt flag. This flag is set in master transmitter mode after ACK/NACK bit is sent if the slave sends a NACK. It is not set if the slave sends an ACK. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CMTXE', msb=4, accessibility='rw1', description='I2C master transmit register empty interrupt flag. This bit is set when this master latches the data stored in the master transmit register to indicate that the master transmit register is ready to accept another byte and queue it for transmission. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CMARB', msb=5, accessibility='rw1', description='I2C master mode arbitration loss interrupt flag. This bit is set when this master detects that the value it tried to write to SDA is being overridden by another master. After it detects the arbitration loss, this master releases control of the bus. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CMSPS', msb=6, accessibility='rw1', description='I2C master mode stop condition sent interrupt flag. This flag is set after this master sends a stop condition. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CMSTS', msb=7, accessibility='rw1', description='I2C master mode start condition sent interrupt flag. This flag is set after this master sends a start condition or repeated start condition. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSXC', msb=8, accessibility='rw1', description='I2C slave mode transfer complete interrupt flag. This bit is set after this slave receives a byte of data from a master, but before this slave sends an ACK/NACK. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSNR', msb=9, accessibility='rw1', description='I2C slave mode NACK received from master interrupt flag. This bit is set in slave transmitter mode if the master responds with a NACK after this slave sends it a byte of data. This bit is not set if the master responds with an ACK. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSOVF', msb=10, accessibility='rw1', description='I2C slave receive register overflow interrupt flag. Indicates that this slave has failed to read one or more bytes from the I2CxSRX register before they were overwritten by another transmission. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSTXE', msb=11, accessibility='rw1', description='I2C slave transmit register empty interrupt flag. This bit is set when this slave latches the data stored in the masslaveter transmit register to indicate that the slave transmit register is ready to accept another byte and queue it for transmission. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSA', msb=12, accessibility='rw1', description='I2C slave mode addressed interrupt flag. Indicates that this slave has been addressed by another master. Write a 1 to this bit to clear it.', valueDescriptions=[(0b0, 'No pending interrupt'), (0b1, 'Pending interrupt')]))
r.AddBitField(BitField(name='I2CSTM', msb=13, accessibility='r', description='I2C slave transmitter mode indicator. Indicates for which mode this slave has been addressed. Only valid if I2CSA is 1. This bit cannot be cleared by writing to the status register.', valueDescriptions=[(0b0, 'Slave receiver mode'), (0b1, 'Slave transmitter mode')]))
r.AddBitField(BitField(name='I2CMCB', msb=14, accessibility='r', description='I2C master controls bus indicator. This bit cannot be cleared by writing to the status register.', valueDescriptions=[(0b0, 'This master does not control the bus'), (0b1, 'This master controls the bus')]))
r.AddBitField(BitField(name='I2CBS', msb=15, accessibility='r', description='I2C bus state indicator. This bit cannot be cleared by writing to the status register.', valueDescriptions=[(0b0, 'The I2C bus is idle'), (0b1, 'The I2C bus is active')]))

# I2CxMTX
r = RegisterTemplate(nameTemplate='I2CxMTX', registerMemorySlot=3, description='I2C master transmit register. Write the desired slave address and read/write bit to this register after sending a start condition to begin a transmission with a slave. Note that the desired slave address must occupy the upper seven bits and the read/write bit must occupy the least significant bit. If the read bit is 0, the master enters master transmitter mode. If the read bit is 1, the master enters master receiver mode. Write a byte of data to this register after sending the address frame or a data frame to send that byte of data to the slave. If this master is busy with a transmission when this register is written, it will send the byte after it finishes the transmission.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CxMTX', msb=7, lsb=0, accessibility='rw'))

# I2CxMRX
r = RegisterTemplate(nameTemplate='I2CxMRX', registerMemorySlot=4, description='I2C master receive register. When in master receiver mode, read this register after the master transfer complete interrupt flag (I2CMXC) is set to get the received data byte.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CxMRX', msb=7, lsb=0, accessibility='r'))

# I2CxSTX
r = RegisterTemplate(nameTemplate='I2CxSTX', registerMemorySlot=5, description='I2C slave transmit register. When in slave transmitter mode, write to this register after the slave addressed flag (I2CSA) or the slave transaction complete flag (I2CSXC) has been set to queue the next byte to send to the master.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CxSTX', msb=7, lsb=0, accessibility='rw'))

# I2CxSRX
r = RegisterTemplate(nameTemplate='I2CxSRX', registerMemorySlot=6, description='I2C slave receive register. When in slave receiver mode, read this register after the slave transaction complete flag (I2CSXC) has been set to get the data byte sent from the master. Note that if this slave fails to clear the status register before another byte is received, the slave receive overflow flag (I2CSOVF) will be set.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CxSRX', msb=7, lsb=0, accessibility='r'))

# I2CxAR
r = RegisterTemplate(nameTemplate='I2CxAR', registerMemorySlot=7, description='I2C this slave address register. When in slave mode, any master that sends an address frame containing this address will activate this slave.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CxAR', msb=6, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=7, unused=True))

# I2CxAMR
r = RegisterTemplate(nameTemplate='I2CxAMR', registerMemorySlot=8, description='I2C this slave address mask register. Any bit set to 1 in this register indicates that the corresponding bit in the slave address register is a wildcard. Only the slave address register bits that correspond to 0s in this register will be compared to the received slave address.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='I2CxAMR', msb=6, lsb=0, accessibility='rw'))
r.AddBitField(BitField(msb=7, unused=True))

''' NPU '''
p = PeripheralTemplate(nameTemplate='NPU', description='Fixed-point multilayer perceptron (MLP) neural network processing unit. Computes a single fully-connected layer of a neural network: given an input vector and a synaptic weight matrix, it produces an output vector. Multiple layers can be computed sequentially by the CPU. Inputs are signed Q0.24 numbers (25 bits); synaptic weights and outputs are signed Q7.24 numbers (32 bits). An optional bias weight and a logistic sigmoid approximation activation function are available. The input vector, output vector, and weight matrix must all reside in hart 0\'s private RAM1 (the 16 KiB SRAM at 0xC000, multiplexed between hart 0 and the NPU). The registers are reachable by every hart through the shared window, but the data path is not: hart 0 (or software staging through shared RAM) must place the operands in RAM1. Hart 0 is put to sleep for the duration of every computation, regardless of which hart started it.', registerPrefix='NPU', bitFieldPrefix='NPU', latexIntroFileName='NPU-intro-castalia-2026-07.tex', latexFeatureSummary='A neural processing unit (NPU) co-processor for hardware acceleration of machine learning tasks')
# A2 (Argus): the template is only registered when the NPU exists — an
# unregistered template emits no MemoryMap.h structs and no TRM chapter
# (same end state as the removed AFE/SARADC blocks).
if npuPresent:
	m.AddPeripheralTemplate(p)

# NPUCR
r = RegisterTemplate(nameTemplate='NPUCR', registerMemorySlot=0, description='NPU control register', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=19, unused=True))
r.AddBitField(BitField(name='NPUBEN', msb=18, description='Bias enable. When set, the first weight of each output neuron\'s row in the weight matrix is used as a bias term: it is multiplied by an implicit input of 1.0 and accumulated before the synaptic weights.', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='NPUAEN', msb=17, description='Activation function enable. When set, the logistic sigmoid approximation activation function is applied to the accumulator output. When cleared, the raw accumulator output is used (linear/identity).', accessibility='rw', valueDescriptions=[(0b0, 'Disabled (linear output)'), (0b1, 'Enabled (logistic sigmoid approximation)')]))
r.AddBitField(BitField(name='NPUTHINK', msb=16, description='NPU computation start and status bit. Write 1 to start the NPU. Self-clears when the computation is complete. Poll this bit to determine when results are ready.', accessibility='rw1', valueDescriptions=[(0b0, 'Idle (computation complete or not started)'), (0b1, 'Running (write 1 to start)')]))
r.AddBitField(BitField(name='NPUNI', msb=15, lsb=8, description='Number of inputs in the input vector minus 1. The actual number of inputs is NPUNI + 1.', accessibility='rw'))
r.AddBitField(BitField(name='NPUNN', msb=7, lsb=0, description='Number of output neurons minus 1. The actual number of outputs is NPUNN + 1.', accessibility='rw'))

# NPUIVSAR
r = RegisterTemplate(nameTemplate='NPUIVSAR', registerMemorySlot=1, description='Input vector start word index within hart 0\'s RAM1: the byte offset from the start of RAM1 (0xC000) divided by 4. For example, an input vector at byte address 0xC100 has word index 0x40. Each input is a signed Q0.24 value stored in bits 24:0 of its 32-bit SRAM word; bits 31:25 are ignored. Bit 24 is the sign bit. The input at index 0 is at word index NPUIVSAR. The input at index 1 is at word index NPUIVSAR + 1. The rest of the inputs follow in consecutive words.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=12, unused=True))
r.AddBitField(BitField(name='NPUIVSAR', msb=11, lsb=0, description='Input vector start word index within RAM1 (byte offset from 0xC000 divided by 4)', accessibility='rw'))

# NPUWVSAR
r = RegisterTemplate(nameTemplate='NPUWVSAR', registerMemorySlot=2, description='Synaptic weight matrix start word index within hart 0\'s RAM1: the byte offset from the start of RAM1 (0xC000) divided by 4. Each weight is a signed Q7.24 value occupying all 32 bits of its SRAM word; bit 31 is the sign bit. Weights are stored row-major, one per 32-bit word, in the following order: for each output neuron (0 through NPUNN), if bias is enabled (NPUBEN = 1), the first word in the row is the bias weight (multiplied by an implicit input of 1.0), followed by NPUNI + 1 synaptic weights for inputs 0 through NPUNI. If bias is disabled, each row contains NPUNI + 1 synaptic weights only.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=12, unused=True))
r.AddBitField(BitField(name='NPUWVSAR', msb=11, lsb=0, description='Synaptic weight matrix start word index within RAM1 (byte offset from 0xC000 divided by 4)', accessibility='rw'))

# NPUOVSAR
r = RegisterTemplate(nameTemplate='NPUOVSAR', registerMemorySlot=3, description='Output vector start word index within hart 0\'s RAM1: the byte offset from the start of RAM1 (0xC000) divided by 4. Each output is a signed Q7.24 value occupying all 32 bits of its SRAM word; bit 31 is the sign bit. The output at index 0 is written to word index NPUOVSAR. The output at index 1 is at word index NPUOVSAR + 1, and so on.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=12, unused=True))
r.AddBitField(BitField(name='NPUOVSAR', msb=11, lsb=0, description='Output vector start word index within RAM1 (byte offset from 0xC000 divided by 4)', accessibility='rw'))



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

# MSIP0..MSIP(numHarts-1)
for h in range(numHarts):
	r = RegisterTemplate(nameTemplate='MSIP' + str(h), registerMemorySlot=h, size=32, description='Hart ' + str(h) + ' software interrupt (IPI) register. Any hart may write it through the shared window: writing 1 raises the software interrupt level into hart ' + str(h) + ' (interrupt vector 83); writing 0 clears it. The interrupt is level-sensitive, so hart ' + str(h) + '\'s service routine must write 0 here before returning.')
	p.AddRegisterTemplate(r)
	r.AddBitField(BitField(unused=True, msb=31, lsb=1))
	r.AddBitField(BitField(name='CLINTMSIPH' + str(h), msb=0, accessibility='rw', description='Software interrupt (IPI) level for hart ' + str(h) + '.', valueDescriptions=[(0b0, 'No software interrupt pending'), (0b1, 'Software interrupt raised')]))

# MTIMEL / MTIMEH (word slot = clintMtimeSlot, the A0/A1 layout formula)
r = RegisterTemplate(nameTemplate='MTIMEL', registerMemorySlot=clintMtimeSlot, size=32, description='Machine time counter, lower 32 bits. mtime is a free-running 64-bit counter shared by all ' + _spelled(numHarts) + ' harts that increments once per MCLK cycle. It is writable for initialization; a write merges only the addressed 32-bit half.')
p.AddRegisterTemplate(r)
r.AddBitField(BitField(name='CLINTMTIMEL', msb=31, lsb=0, accessibility='rw', description='mtime bits 31:0.'))

r = RegisterTemplate(nameTemplate='MTIMEH', registerMemorySlot=clintMtimeSlot + 1, size=32, description='Machine time counter, upper 32 bits. Read MTIMEH, then MTIMEL, then MTIMEH again (retry if the two MTIMEH reads differ) to obtain a coherent 64-bit time value.')
p.AddRegisterTemplate(r)
r.AddBitField(BitField(name='CLINTMTIMEH', msb=31, lsb=0, accessibility='rw', description='mtime bits 63:32.'))

# MTIMECMP0..(numHarts-1) (lo/hi pairs at word slots clintMtimecmpSlot+2h / +2h+1)
for h in range(numHarts):
	r = RegisterTemplate(nameTemplate='MTIMECMP' + str(h) + 'L', registerMemorySlot=clintMtimecmpSlot + 2 * h, size=32, description='Hart ' + str(h) + ' timer compare register, lower 32 bits. The timer interrupt level for hart ' + str(h) + ' (interrupt vector 84) is raised while mtime >= mtimecmp' + str(h) + '. Resets to all-ones (no interrupt). To set a new compare value without a spurious interrupt, first write all-ones to MTIMECMP' + str(h) + 'H, then the new lower half, then the real upper half.')
	p.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='CLINTMTIMECMP' + str(h) + 'L', msb=31, lsb=0, accessibility='rw', description='mtimecmp' + str(h) + ' bits 31:0.'))

	r = RegisterTemplate(nameTemplate='MTIMECMP' + str(h) + 'H', registerMemorySlot=clintMtimecmpSlot + 2 * h + 1, size=32, description='Hart ' + str(h) + ' timer compare register, upper 32 bits.')
	p.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='CLINTMTIMECMP' + str(h) + 'H', msb=31, lsb=0, accessibility='rw', description='mtimecmp' + str(h) + ' bits 63:32.'))



''' MUTEX (hardware mutex bank, shared window page 2 at 0x6000) '''
p = PeripheralTemplate(nameTemplate='MUTEX', description='Hardware mutex bank: ' + _spelled(numMutexes) + ' word-mapped advisory locks providing single-instruction cross-hart mutual exclusion. Because the multi-core arbiter serializes whole shared-window transactions, a read is atomic for free: reading a mutex word returns 0 if the mutex was free and the same transaction claims it for the reading hart (owner becomes hartid+1); reading a held mutex returns the owner\'s marker (hartid+1) and does not disturb it. Writing 0 releases a mutex (deliberately not qualified by owner, so a supervisory hart can force-release a dead hart\'s mutex); nonzero writes are ignored, so ownership cannot be forged. Never access a mutex with LR/SC or AMO instructions -- only plain loads and stores. All mutexes reset to free.', bitFieldPrefix='MTX', latexIntroFileName='MUTEX-intro-castalia-2026-07.tex')
m.AddPeripheralTemplate(p)

# A2: owner-marker value descriptions enumerate the configured hart count
_mtxOwnerValues = [(0, 'Mutex free (a read returning this value claims the mutex)', '_FREE')]
for h in range(numHarts):
	_mtxOwnerValues.append((h + 1, 'Held by hart ' + str(h), '_H' + str(h)))
for i in range(numMutexes):
	r = RegisterTemplate(nameTemplate='MUTEX' + str(i), registerMemorySlot=i, size=32, description='Hardware mutex ' + str(i) + '. Read to claim: a returned value of 0 means the mutex was free and the reading hart now holds it; a nonzero value is the current owner\'s marker (hartid+1). Write 0 to release.')
	p.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='MTXOWN' + str(i), msb=31, lsb=0, accessibility='rw', description='Owner marker: 0 = free (and a read that returns 0 claims the mutex), h+1 = held by hart h.', valueDescriptions=list(_mtxOwnerValues)))



''' IRQROUTER (M19 PLIC-lite: per-hart routing rows + CLAIM/COMPLETE delivery, shared window page 3 at 0x7000) '''
p = PeripheralTemplate(nameTemplate='IRQROUTER', description='THE peripheral interrupt controller (M19): per-hart interrupt routing/enable rows plus a claim/complete delivery stage, programmable by any hart through the shared window. Every deglitched peripheral interrupt level terminates here; the router raises a single external-interrupt wire (meip, interrupt vector 85) to each of the ' + _spelled(numHarts) + ' harts whenever some peripheral source is pending, enabled in that hart\'s row, and not already being serviced. The servicing hart reads CLAIM to atomically discover and claim the lowest-numbered such source (claims are attributed to the reading hart by the shared-bus arbiter, so simultaneous claimers are serialized and each source is delivered exactly once), runs the source\'s handler, clears the interrupt level at the peripheral, and writes the source number back to CLAIM (complete). A source under service is masked from every hart\'s meip until completed; if its level is still high at complete (a new event), it pends again. Priority is fixed: the lowest pending vector number wins. The CLINT vectors 83 (msip) and 84 (mtip) are never delivered through meip — they reach each hart on dedicated hardwired wires — so their row bits are writable but have no effect. All rows reset to 0 (everything masked), so the router is inert until software programs it. Since M19 row 0 is live: hart 0 takes meip like every other hart (the SYSTEM peripheral\'s vectored interrupt controller is retired).', bitFieldPrefix='IRQR', latexIntroFileName='IRQROUTER-intro-castalia-2026-07.tex', latexFeatureSummary='Claim/complete peripheral interrupt delivery (PLIC-style) with any-vector-to-any-hart routing')
m.AddPeripheralTemplate(p)

for h in range(numHarts):
	r = RegisterTemplate(nameTemplate='H' + str(h) + 'ENL', registerMemorySlot=4 * h, size=32, description='Hart ' + str(h) + ' interrupt routing register, vectors 31:0. Each bit enables delivery of the corresponding interrupt vector to hart ' + str(h) + ' via its meip wire (vector 85) and the CLAIM/COMPLETE mechanism.')
	p.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='IRQRH' + str(h) + 'ENL', msb=31, lsb=0, accessibility='rw', description='Interrupt enable bits for vectors 31:0, routed to hart ' + str(h) + '.'))

	r = RegisterTemplate(nameTemplate='H' + str(h) + 'ENM', registerMemorySlot=4 * h + 1, size=32, description='Hart ' + str(h) + ' interrupt routing register, vectors 63:32.')
	p.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='IRQRH' + str(h) + 'ENM', msb=31, lsb=0, accessibility='rw', description='Interrupt enable bits for vectors 63:32, routed to hart ' + str(h) + '.'))

	r = RegisterTemplate(nameTemplate='H' + str(h) + 'ENU', registerMemorySlot=4 * h + 2, size=32, description='Hart ' + str(h) + ' interrupt routing register, vectors 84:64 (bits 20:0; bits 31:21 read as 0). Unlike the retired SYSTEM IRQENU register of the single-core chip, the packing here is contiguous in both directions. Bits 19 and 20 correspond to the CLINT vectors 83 and 84, which are delivered on dedicated hardwired wires and never through meip: these two bits are writable but have no effect.')
	p.AddRegisterTemplate(r)
	r.AddBitField(BitField(unused=True, msb=31, lsb=21))
	r.AddBitField(BitField(name='IRQRH' + str(h) + 'ENU', msb=20, lsb=0, accessibility='rw', description='Interrupt enable bits for vectors 84:64, routed to hart ' + str(h) + '.'))

# M19 claim/complete block at fixed word offsets (hart-count-independent
# addresses: CLAIM at +0x800, status words at +0x810/+0x820)
r = RegisterTemplate(nameTemplate='CLAIM', registerMemorySlot=512, size=32, description='Interrupt claim/complete register (M19). READ = claim: atomically returns the lowest pending interrupt vector that is enabled in the READING hart\'s routing row and not already under service, and marks it under service (masking it from every hart\'s meip). Returns 0xFFFFFFFF if nothing is pending for the reader; a handler seeing that value treats the interrupt as spurious and simply returns. WRITE = complete: write the claimed vector number to end its service; the vector becomes deliverable again (and pends immediately if its level is still asserted, so clear the level at the peripheral BEFORE completing). Completion is deliberately not qualified by owner, so a supervisor hart can complete on behalf of a hung hart (recovery); written values that are not valid vector numbers, including a stored 0xFFFFFFFF, are ignored.')
p.AddRegisterTemplate(r)
r.AddBitField(BitField(name='IRQRCLAIM', msb=31, lsb=0, accessibility='rw', description='Read: claimed vector number (0xFFFFFFFF = none pending for this hart). Write: vector number to complete.'))

r = RegisterTemplate(nameTemplate='PENDL', registerMemorySlot=516, size=32, description='Raw pending interrupt levels, vectors 31:0 (read-only; deglitched peripheral levels before enable/claim masking). Debug and polling aid.')
p.AddRegisterTemplate(r)
r.AddBitField(BitField(name='IRQRPENDL', msb=31, lsb=0, accessibility='r', description='Deglitched interrupt levels for vectors 31:0.'))

r = RegisterTemplate(nameTemplate='PENDM', registerMemorySlot=517, size=32, description='Raw pending interrupt levels, vectors 63:32 (read-only).')
p.AddRegisterTemplate(r)
r.AddBitField(BitField(name='IRQRPENDM', msb=31, lsb=0, accessibility='r', description='Deglitched interrupt levels for vectors 63:32.'))

r = RegisterTemplate(nameTemplate='PENDU', registerMemorySlot=518, size=32, description='Raw pending interrupt levels, vectors 84:64 (bits 20:0, read-only; bits 31:21 read as 0).')
p.AddRegisterTemplate(r)
r.AddBitField(BitField(unused=True, msb=31, lsb=21))
r.AddBitField(BitField(name='IRQRPENDU', msb=20, lsb=0, accessibility='r', description='Deglitched interrupt levels for vectors 84:64.'))

r = RegisterTemplate(nameTemplate='INSVCL', registerMemorySlot=520, size=32, description='Under-service (claimed, not yet completed) flags, vectors 31:0 (read-only). Debug and recovery visibility: a stuck bit here means a hart claimed the vector and never completed it; any hart can recover by writing the vector number to CLAIM.')
p.AddRegisterTemplate(r)
r.AddBitField(BitField(name='IRQRINSVCL', msb=31, lsb=0, accessibility='r', description='Under-service flags for vectors 31:0.'))

r = RegisterTemplate(nameTemplate='INSVCM', registerMemorySlot=521, size=32, description='Under-service flags, vectors 63:32 (read-only).')
p.AddRegisterTemplate(r)
r.AddBitField(BitField(name='IRQRINSVCM', msb=31, lsb=0, accessibility='r', description='Under-service flags for vectors 63:32.'))

r = RegisterTemplate(nameTemplate='INSVCU', registerMemorySlot=522, size=32, description='Under-service flags, vectors 84:64 (bits 20:0, read-only; bits 31:21 read as 0).')
p.AddRegisterTemplate(r)
r.AddBitField(BitField(unused=True, msb=31, lsb=21))
r.AddBitField(BitField(name='IRQRINSVCU', msb=20, lsb=0, accessibility='r', description='Under-service flags for vectors 84:64.'))



''' PWRCTRL (M17 MTCMOS power controller, peripheral-window slot 11 at 0x4B00) '''
p = PeripheralTemplate(nameTemplate='PWRCTRL', description='Power controller for the switchable hart-tile power domains (M17 MTCMOS cold-gating). Each tile hart (1-' + str(numHarts - 1) + ') sits in its own header-switched power domain; setting that hart\'s gate bit walks a hardware sequencer through the only legal order: isolation clamps on, tile reset asserted, header switches opened (rail off). Clearing the bit reverses it: switches closed, a rail-settle delay, clamps released, reset released --- at which point the tile COLD-BOOTS through the shared boot ROM (all state was lost), parks in WFI, and can be relaunched through the boot-ROM loader rows and a CLINT msip exactly as at chip power-on. Hart 0 (the management hart: SPI boot, console, CLINT owner) is always-on; its bit reads 0 and ignores writes. Gate only a parked or otherwise quiesced tile: the hardware cannot deadlock (a clamped request looks released to the arbiter), but any in-flight work on the tile is destroyed --- that is what cold-gating means.', bitFieldPrefix='PWR', latexIntroFileName='PWRCTRL-intro-castalia-2026-07.tex', latexFeatureSummary='Per-tile MTCMOS power gating with hardware gate/wake sequencing (cold-boot wake)')
m.AddPeripheralTemplate(p)

r = RegisterTemplate(nameTemplate='PWRCR', registerMemorySlot=0, size=32, description='Power gate control. Setting GATE bit h powers tile hart h down (isolation, reset, rail off); clearing it powers the tile back up and cold-boots it. A request made while the sequencer is mid-sequence is honored when the sequence completes (no aborts). Bit 0 (hart 0) is reserved: always-on, reads 0, writes ignored.')
p.AddRegisterTemplate(r)
r.AddBitField(BitField(unused=True, msb=31, lsb=numHarts))
r.AddBitField(BitField(name='PWRGATE', msb=numHarts - 1, lsb=1, accessibility='rw', description='Gate request per tile hart: bit h = 1 powers tile hart h down, 0 powers it up (cold boot). Poll PWRSR for sequencer completion.', valueDescriptions=[(0, 'All tile harts powered', '_NONE')]))
r.AddBitField(BitField(name='PWRH0', msb=0, lsb=0, accessibility='r', description='Hart 0 is always-on: reads 0, writes ignored.'))

# PWRSR nibble array (A2 regrow, user decision 2026-07-10): the 4-bit state
# nibble encoding is kept and the register grows to ceil(numHarts/8)
# consecutive words at +0x4 (PWRSR0/1/2/...). At numHarts=4 this is exactly
# the original single PWRSR word — Castalia byte-identity for free.
_pwrsrWords = (numHarts + 7) // 8
for _w in range(_pwrsrWords):
	_h0 = 8 * _w						# first hart in this word
	_h1 = min(8 * _w + 7, numHarts - 1)	# last hart in this word
	_name = 'PWRSR' if _pwrsrWords == 1 else 'PWRSR' + str(_w)
	if _pwrsrWords == 1:
		_desc = 'Power sequencer state, one read-only nibble per hart (bits 4h+3:4h). 0 = ON, 1 = ISO (clamps asserting), 2 = RSTOFF (reset held, rail dying), 3 = OFF (gated), 4 = RAIL (waking, rail settling), 5 = UNISO (clamps releasing). Hart 0\'s nibble always reads 0. A tile is safely gated when its nibble reads 3, and fully awake (booting or parked in the ROM) when it returns to 0.'
	else:
		_desc = 'Power sequencer state for harts ' + str(_h0) + '-' + str(_h1) + ', one read-only nibble per hart (hart h in bits 4(h-' + str(_h0) + ')+3:4(h-' + str(_h0) + ')). 0 = ON, 1 = ISO (clamps asserting), 2 = RSTOFF (reset held, rail dying), 3 = OFF (gated), 4 = RAIL (waking, rail settling), 5 = UNISO (clamps releasing). Hart 0\'s nibble always reads 0. A tile is safely gated when its nibble reads 3, and fully awake (booting or parked in the ROM) when it returns to 0.'
	r = RegisterTemplate(nameTemplate=_name, registerMemorySlot=1 + _w, size=32, description=_desc)
	p.AddRegisterTemplate(r)
	if _h1 < 8 * _w + 7:
		r.AddBitField(BitField(unused=True, msb=31, lsb=4 * (_h1 - _h0) + 4))
	for _h in range(_h1, _h0 - 1, -1):
		_lsb = 4 * (_h - _h0)
		if _h == 0:
			r.AddBitField(BitField(name='PWRST0', msb=3, lsb=0, accessibility='r', description='Hart 0 state: always 0 (ON, always-on domain).'))
		else:
			r.AddBitField(BitField(name='PWRST' + str(_h), msb=_lsb + 3, lsb=_lsb, accessibility='r', description='Tile hart ' + str(_h) + ' sequencer state.'))



''' Check the peripheral templates for errors '''
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
	m.CreatePeripheral(nameTemplate='NPU', nameIndex='', peripheralMemorySlot=None, interruptPriority=None, absoluteBaseAddress=0x4A00, legacySlot=10, sharedBus='periph', combinationalRead=True, clockDomain='mclk', strobeNote='vectors live in the shared NPU staging RAM at 0xC000; do not touch 0xC000-0xFFFF during a THINK — poll NPUCR bit 16')	# NPU register bus shared (slot 10); data path = the 0xC000 staging RAM
# SARADC removed (vector 56 reserved gap; its slot 11 is PWRCTRL's since M17)
# AFE removed (slot 12 / vector 55 reserved gap)
m.CreatePeripheral(nameTemplate='PWRCTRL', nameIndex='', peripheralMemorySlot=None, interruptPriority=None, absoluteBaseAddress=0x4B00, legacySlot=11, sharedBus='native', clockDomain='mclk', strobeNote='cold-gate: a gated tile loses all state and reboots through the shared ROM on wake; gate only parked/quiesced tiles')	# M17 power controller (slot 11, ex-SARADC0; native arbiter slave)
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
m.CreatePeripheral(nameTemplate='MUTEX', nameIndex='', peripheralMemorySlot=None, interruptPriority=None, absoluteBaseAddress=0x6000, sharedBus='native', clockDomain='mclk', strobeNote='READ = atomic return-old-and-claim; never LR/SC or AMO a mutex address', registerSlotCount=_slotCountOverride(numMutexes))	# HW mutex bank at 0x6000 (M11: window page 2)
m.CreatePeripheral(nameTemplate='IRQROUTER', nameIndex='', peripheralMemorySlot=None, interruptPriority=None, absoluteBaseAddress=0x7000, sharedBus='native', clockDomain='mclk', registerSlotCount=_slotCountOverride(523))	# IRQ router at 0x7000 (M11: window page 3; M19: rows + the fixed-address CLAIM block through word 522 = 0x7828)



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
if packageModel == 'myshkin-qfn44':
	package = m.CreatePackage(
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
		positiveVoltage=3.3,
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

elif packageModel == 'castalia-quad-qfn64':
	# CQ3b Castalia-Quad QFN64 pinout (cq3b_pin_map.md / cq3b_generator_proposal.md):
	# 16 pins/side, 9x9 mm, 0.5 mm pitch. Numbering W 1-16 (top->bottom),
	# S 17-32 (L->R), E 33-48 (bottom->top), N 49-64 (R->L).
	package = m.CreatePackage(
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
		powerDomainName='Analog0', positiveVoltage=3.3, negativeVoltage=0.0,
		positiveRailPinNumber=64, positiveRailPinName='AVDD_0',
		negativeRailPinNumber=59, negativeRailPinName='AVSS_0')
	analog1PowerDomain = package.AddPowerDomain(
		powerDomainName='Analog1', positiveVoltage=3.3, negativeVoltage=0.0,
		positiveRailPinNumber=49, positiveRailPinName='AVDD_1',
		negativeRailPinNumber=54, negativeRailPinName='AVSS_1')
	analog2PowerDomain = package.AddPowerDomain(
		powerDomainName='Analog2', positiveVoltage=3.3, negativeVoltage=0.0,
		positiveRailPinNumber=17, positiveRailPinName='AVDD_2',
		negativeRailPinNumber=22, negativeRailPinName='AVSS_2')
	analog3PowerDomain = package.AddPowerDomain(
		powerDomainName='Analog3', positiveVoltage=3.3, negativeVoltage=0.0,
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

else:
	raise Exception('package model "' + packageModel + '" is declared but not implemented')

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
}
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
GPIO3.AddGpio(GpioConfigurator(bitNumber=7, primaryName='GPIO31', funcName='DTP3', funcIOType='io',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='Digital test port 3', altFuncs=([(1, 'T1CMP1', 'o', 'TIMER1 Compare 1 (alternate location)')] if timer1Present else [])), packagePinNumber=_gpioPkgPin(3, 7)) # necessary; AF1 gated with TIMER1 (G1b)


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
if len(_mcuMpIrqVectors) != 85:
	raise Exception('MCU_MP IRQB vector list must have 85 entries, has ' + str(len(_mcuMpIrqVectors)))

# Each interrupting peripheral's first vector name, for cross-checking interruptPriority
# against the IRQB list (build fails on mismatch)
_mcuMpIrqFirstVector = {
	'SYSTEM': 'IRQB_SYS_WDT',
	'GPIO0': 'IRQB_GPIO0_B0',
	'GPIO1': 'IRQB_GPIO1_B0',
	'GPIO2': 'IRQB_GPIO2_B0',
	'GPIO3': 'IRQB_GPIO3_B0',
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
		('RstValP4REN', 0x00000000, ''),
		('RstValP4AFS', 0x00000000, 'all pins select AF0 (legacy alternate function) at reset'),
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
]

m.McuMpCompat = {
	'sourceFile': 'hdl/common/MemoryMap.vhd',
	'periphSlotSpelling': _mcuMpPeriphSlotSpelling,
	'memSlots': _mcuMpMemSlots,
	'gpioHelpers': _mcuMpGpioHelpers,
	'sysRegSlots': _mcuMpSysRegSlots,
	'npuMmrAddr': _mcuMpNpuMmrAddr,
	'irqVectors': _mcuMpIrqVectors,
	'irqFirstVector': _mcuMpIrqFirstVector,
	'rstVals': _mcuMpRstVals,
	'pnums': _mcuMpPnums,
}

# A2 (Argus): shared-window geometry for mcu_vhd.py's generated regions —
# the SH_AW constant, the bank row and the NPU staging plumbing all derive
# from these three values (computed with the memory sections above).
m.McuMpGeometry = {
	'shAw': shAw,               # arbiter/tile word-address width (15 = Castalia)
	'sharedRamBanks': _sharedRamBanks,  # sram1p16k banks from 0x10000 (4 = Castalia)
	'npu': npuPresent,          # False = Argus (slot 10 + 0xC000 window read zero)
	'i2c1': i2c1Present,        # G1a: False drops the i2c1 instance (slot 15 dead)
	'uart1': uart1Present,      # G1b: False drops the uart1 instance (slot 5 dead)
	'spi1': spi1Present,        # G1b: False drops the spi1 instance (slot 3 dead)
	'timer1': timer1Present,    # G1b: False drops the timer1 instance (slot 7 dead)
}


''' Check for errors '''
m.CheckPeripherals()
m.CheckPackagePins()


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
	('numMutexes', numMutexes),
	('registerFileDualPort', _regsDualPort),
	('isa', _isa),
	('memory', [
		('romSize', _romSize),
		('tcmSizePerHart', _tcmSize),
		('sharedBulkRamSize', _sharedRamLen),
		('npuStagingRamSize', _npuRamLen if npuPresent else 0),
	]),
	('peripherals', [('npu', npuPresent), ('i2c1', i2c1Present), ('uart1', uart1Present),
		('spi1', spi1Present), ('timer1', timer1Present)]),
	('package', [('model', packageModel), ('preliminary', packagePreliminary)]),
	('derived', [
		('isaString', _isaString()),
		('sharedWindowAddrWidth', shAw),
		('sharedRamBanks', _sharedRamBanks),
		('flashBaseAddress', _hx(flashBase)),
		('sharedRamEndAddress', _hx(0x10000 + _sharedRamLen - 1)),
		('vectorsCount', 85),
		('clintMsipVector', 83),
		('clintMtipVector', 84),
		('clintLayout', [
			('msipAddress', '0x5000 + 4*hartid'),
			('mtimeAddress', _hx(0x5000 + 4 * clintMtimeSlot)),
			('mtimecmpBaseAddress', _hx(0x5000 + 4 * clintMtimecmpSlot)),
		]),
		('bootromLoaderRowBase', '0x10500 + 0x10*hartid'),	# Argus A3 relocation (N-agnostic, all builds — see software/bootrom_mp)
		('stackPointerInit', _hx(0xC000)),
		('peripheralCount', len(m.Peripherals)),
	]),
]

def _od(pairs):
	'''Recursively turn ('key', value) pair lists into dicts (py3.6 dicts keep
	   insertion order, so the JSON reads in schema order).'''
	if isinstance(pairs, list) and pairs and all(isinstance(p, tuple) and len(p) == 2 for p in pairs):
		return dict((k, _od(v)) for k, v in pairs)
	return pairs

m.ResolvedConfig = _od(_resolvedConfig)
m.PackagePreliminary = packagePreliminary	# G4: drives the TRM §2 "Preliminary" banner (LatexUserGuide \ifpackagepreliminary)
# Schema key -> human description, for the TRM's generated Chip Configuration
# section (documents the CONFIG= schema next to this build's resolved values)
m.ConfigSchemaDoc = dict((k, _CONFIG_SCHEMA[k][0]) for k in _CONFIG_SCHEMA)

# Derived pad ring: the package model above IS the pad-ring description
# (pin order, sides, power domains). Recorded as config/PadRing.json and
# rendered as the TRM's generated pinout diagram — there is no separate
# hand-maintained pad list to drift out of sync.
_padRingPins = []
for _pp in m.Package.Pins:
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
	_padRingPins.append(_e)

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

m.PadRing = {
	'_comment': 'Derived pad ring — computed by make chip from the package model in generate.py '
		+ '(pin numbers, sides, power domains are single-sourced there; edit generate.py, not this file).',
	'package': {
		'type': m.Package.PackageType,
		'pinCount': m.Package.PinCount,
		'dimensions': m.Package.Dimensions,
		'units': m.Package.Units,
		'pinPitch': m.Package.PinPitch,
		'pinsOnEachSide': m.Package.PinsOnEachSide,
	},
	'powerDomains': [_padRingDomainEntry(_pd) for _pd in m.Package.PowerDomains],
	'pins': _padRingPins,
}


''' Generate all output files '''
# TODO: Enable saveHardware=True once MCU.vhd has the required "Begin Automatically Generated" headers
# For now, only generating software files and documentation
m.Generate(test=False, force=True, saveHardware=True, saveSoftware=True)

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
# innovus/common/tcl/chip_top.innovus.tcl's place_side proc consumes (Flavor A
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
		_padTclLines.append('lappend PADRING_' + _sideName.upper() + ' '
			+ _padInstName(_p.Name).ljust(16)
			+ ';# pin ' + str(_p.PackagePinNumber).rjust(2) + ': ' + _nm + '  [' + _dom + ']')
	_padTclLines.append('')
_pnrDir = chipRootDirectory + '/out/pnr'
if not os.path.isdir(_pnrDir):
	os.makedirs(_pnrDir)
with open(_pnrDir + '/chip_top_padring.tcl', 'w') as _f:
	_f.write('\n'.join(_padTclLines))
	_f.write('\n')
print('[generate] wrote out/pnr/chip_top_padring.tcl (pad-placement template for the chip_top flow)')

