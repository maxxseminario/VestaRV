# mcu_vhd.py — golden-master MCU.vhd emitter (RTL-generation track, Phase 2)
#
# Emits out/hdl/MCU.vhd from hdl_templates/MCU.template.vhd. The template is the
# verified hdl/MCU_MP/MCU.vhd with the DESCRIPTION-DRIVEN regions carved out and
# replaced by "--@GEN:<name>@" marker lines; this module regenerates those
# regions from python/generate.py's peripheral description:
#   - irq-signal-decls / irq-comb    : per-vector IRQ signals + the irq_comb aggregate
#   - shslv-subdecode / shslv-rd-sel : shared-window slave decode + registered read-select
#                                      (M11 map: pages on s_addr(14:12), window slots on
#                                      s_addr(9:6) at the legacy numbering)
#   - rdata-bridge                   : bridge registers for COMBINATIONAL-read slaves
#   - sh-rdata-mux / polarity-shims  : slave read mux + active-low en/wen shims
#   - bus:<instance>                 : each peripheral instance's memory-bus port map
#
# A1 (Argus N-hart generalization, 2026-07-10) adds the numHarts-driven regions:
#   - a0-ports                       : per-tile-hart a0 observation ports (entity)
#   - arb-fabric-decls / clint-irq-decls / tile-irq-en-flat-decl / pd-decls /
#     tile-raw-decls / sh-master-decl : the per-hart fabric signal widths
#   - hart0-instance / tile-instances : the hart_tile instances (hart 0's
#     special wiring vs the tiles' router rows — per-instance WIRING only)
#   - arb-generic / resv-generic     : mp_arbiter / resv_unit N generics
#   - clint-instance                 : NHARTS + the A0 layout-formula ADDR_W
#   - irq-router-instance / tile-rstn / iso-clamps
# At numHarts=4 every one of these reproduces the golden master BYTE-
# IDENTICALLY (check_mcu_vhd.py STRICT is the gate). Other hart counts emit
# well-formed VHDL, but the RTL only elaborates after the A2/A3 platform
# generalizations (mp_arbiter s_master width, mutex_bank master port,
# irq_router/pwr_ctrl regrow, sh_sel/SH_AW/flash move) — pwr0's instance and
# the pd_* hookup stay 4-hart RTL until pwr_ctrl regrows at A2.
#
# Division of truth (mirrors Phase 1's McuMpCompat rules):
#   - generate.py owns the per-peripheral FACTS (slots, base addresses, sharedBus
#     class, combinationalRead, clock domain) — change the chip there.
#   - this module owns the RTL's STRUCTURE: signal-name spellings, list orders and
#     narrative comments transcribed from the golden master (the RTL wins).
#   - cross-checks RAISE when the two disagree, so a description change that the
#     transcribed structure cannot express fails the build instead of emitting
#     silently-wrong RTL.
#
# The drop-in bar (same as Phase 1): python/check_mcu_vhd.py exit 0 — the emitted
# file is BYTE-IDENTICAL to hdl/MCU_MP/MCU.vhd apart from the generated header.
#
# Python 3.6 compatible.

import datetime
import os
import re

EMDASH = '—'


def _clog2(n):
	'''Smallest w with 2**w >= n.'''
	w = 0
	while (1 << w) < n:
		w += 1
	return w


# Prose spelling of small hart counts ("identical on all four tiles"); larger
# counts fall back to digits ("identical on all 18 tiles").
_HARTS_WORD = {2: 'two', 3: 'three', 4: 'four', 5: 'five', 6: 'six', 7: 'seven',
	8: 'eight', 9: 'nine', 10: 'ten', 11: 'eleven', 12: 'twelve'}

# ---------------------------------------------------------------------------
# Transcribed RTL structure (spellings + orders from hdl/MCU_MP/MCU.vhd)
# ---------------------------------------------------------------------------

# Shared-window slaves: description name -> RTL signal spellings.
#   sel   = shslv_<sel>_sel / _en / shslv_rd_<sel>
#   shim  = <shim>_sh_en_n (None for 'native' slaves that take active-high en)
#   rdata = the signal the slave drives into sh_rdata_mux
SHSLV = {
	'CLINT':     {'sel': 'clint', 'shim': None,    'rdata': 'clint_rdata'},
	'MUTEX':     {'sel': 'mtx',   'shim': None,    'rdata': 'mtx_rdata'},
	'IRQROUTER': {'sel': 'irtr',  'shim': None,    'rdata': 'irtr_rdata'},
	'PWRCTRL':   {'sel': 'pwr',   'shim': None,    'rdata': 'pwr_rdata'},
	'GPIO0':     {'sel': 'gpio0', 'shim': 'gpio0', 'rdata': 'gpio0_sh_rdata'},
	'GPIO1':     {'sel': 'gpio1', 'shim': 'gpio1', 'rdata': 'gpio1_sh_rdata'},
	'SPI0':      {'sel': 'spi0',  'shim': 'spi0',  'rdata': 'spi0_sh_rdata'},
	'SPI1':      {'sel': 'spi1',  'shim': 'spi1',  'rdata': 'spi1_sh_rdata'},
	'UART0':     {'sel': 'uart0', 'shim': 'uart0', 'rdata': 'uart0_sh_rdata'},
	'UART1':     {'sel': 'uart1', 'shim': 'uart1', 'rdata': 'uart1_sh_rdata'},
	'TIMER0':    {'sel': 'tim0',  'shim': 'tim0',  'rdata': 'tim0_sh_rdata'},
	'TIMER1':    {'sel': 'tim1',  'shim': 'tim1',  'rdata': 'tim1_sh_rdata'},
	'GPIO2':     {'sel': 'gpio2', 'shim': 'gpio2', 'rdata': 'gpio2_sh_rdata'},
	'SYSTEM':    {'sel': 'sys',   'shim': 'sys',   'rdata': 'sys_sh_rdata'},
	'NPU':       {'sel': 'npu',   'shim': 'npu',   'rdata': 'npu_sh_rdata'},
	'GPIO3':     {'sel': 'gpio3', 'shim': 'gpio3', 'rdata': 'gpio3_sh_rdata'},
	'I2C0':      {'sel': 'i2c0',  'shim': 'i2c0',  'rdata': 'i2c0_sh_rdata'},
	'I2C1':      {'sel': 'i2c1',  'shim': 'i2c1',  'rdata': 'i2c1_sh_rdata'},
}

# M11/M12 memory slaves (structural — hard macros, not description
# peripherals): sel spelling -> the macro Q net that feeds sh_rdata_mux
# directly (the macro IS the 1-cycle registered read). 'rom' = the M12
# shared boot ROM at page 000 (read-only rom_hvt_pg).
MEMSLV = {
	'rom': 'rom_q',
	'npuram': 'npuram_q',
	'bank0': 'bank0_q', 'bank1': 'bank1_q', 'bank2': 'bank2_q', 'bank3': 'bank3_q',
}

# Milestone each peripheral moved onto the shared window (RTL history; used in
# the transcribed port-map comments)
MOVED_IN = {
	'UART0': 'M6',
	'GPIO1': 'M7b', 'GPIO2': 'M7b', 'GPIO3': 'M7b', 'TIMER0': 'M7b', 'TIMER1': 'M7b',
	'SPI1': 'M7c', 'UART1': 'M7c',
	'I2C0': 'M7c.2', 'I2C1': 'M7c.2',
	'NPU': 'M7d',
	'SYSTEM': 'M11', 'GPIO0': 'M11', 'SPI0': 'M11',
}

# M11 canon: page-0 slot decode in slot-numeric order (new RTL authored by
# the M11 rework — the milestone-history ordering of the pre-M11 fabric is
# retired with it). EN/RD run memory slaves first, then the window pages,
# then the slots.
PG0_SEL_ORDER = ['GPIO0', 'GPIO1', 'SPI0', 'SPI1', 'UART0', 'UART1', 'TIMER0', 'TIMER1',
	'GPIO2', 'SYSTEM', 'NPU', 'GPIO3', 'I2C0', 'I2C1']
# M17: NATIVE slaves living IN a page-0 slot (slot-decoded like the shim
# peripherals above, but speaking the arbiter protocol directly — no shim).
# PWRCTRL took slot 11 (0x4B00), vacated by SARADC0 in the digital-only respin.
PG0_NATIVE_ORDER = ['PWRCTRL']
EN_ORDER = ['rom', 'npuram', 'bank0', 'bank1', 'bank2', 'bank3', 'CLINT', 'MUTEX', 'IRQROUTER', 'PWRCTRL'] + PG0_SEL_ORDER
RD_ORDER = list(EN_ORDER)

# Polarity-shim groups: (transcribed comment lines, [peripheral names], name pad)
SHIM_GROUPS = [
	(["-- M6: bridge the arbiter slave port onto UART0's adddec-style register bus.",
	  '-- UART.vhd already obeys the 1-cycle registered-read contract',
	  "-- (reg_read_proc) and qualifies every write by en_mem='0', so the bridge is",
	  '-- pure polarity/width adaptation: en_mem is the active-LOW one-cycle access',
	  '-- strobe, wen the active-LOW byte lanes (from the resv-GATED sh_we ' + EMDASH + ' a',
	  '-- suppressed SC write must not touch the UART), and clk_mem is the',
	  '-- free-running mclk (the gated-clock "stuck clear-pulse" behaviour of the',
	  '-- old private periph bus disappears: clr_* become true one-cycle pulses,',
	  '-- consumed asynchronously by the TX/RX FSMs).'],
	 ['UART0'], 15),
	(['-- M7b: same polarity shim for the moved TIMER/GPIO blocks (active-LOW',
	  "-- one-cycle en strobes; they share sh_wen_n's active-low lanes " + EMDASH,
	  "-- all from the resv-GATED sh_we, so a suppressed SC write can't touch",
	  '-- any shared peripheral). clk_mem = free-running mclk everywhere; the',
	  '-- M7b audit found TIMER and GPIO both already en-qualify every write and',
	  '-- register every read (UART-class movers) ' + EMDASH + ' their un-en-qualified logic',
	  '-- (timer core, pin IRQ flags) runs on its OWN muxed/pin clocks, not',
	  '-- clk_mem, so the gated->free-running change is invariant for them.'],
	 ['TIMER0', 'TIMER1', 'GPIO1', 'GPIO2', 'GPIO3'], 14),
	(["-- M7c: SPI1 + UART1 (audited clean; SPI1's flash FSM is compiled out by",
	  '-- ENABLE_EXTENDED_MEM=false, and its baud core runs on smclk ' + EMDASH + ' the',
	  '-- SYS_CLK_CR=0 rule applies to SPI software too)'],
	 ['SPI1', 'UART1'], 14),
	(['-- M7c.2: I2C0/I2C1 (combinational read handled by i2c_rdata_bridge above;',
	  '-- writes/snapshot-latches audit clean ' + EMDASH + ' single en-qualified ClkMem',
	  '-- process, core FSMs on smclk/pin edges)'],
	 ['I2C0', 'I2C1'], 14),
	(['-- M7d: NPU register bus (MabMmrCEN was HARDWIRED \'0\' on the old gated',
	  '-- bus ' + EMDASH + ' the clk_periph pulse was the only write qualifier; on the',
	  '-- free-running mclk this strobe IS the qualifier)'],
	 ['NPU'], 14),
	(['-- M11: the last three private peripherals join the window (the private',
	  '-- peripheral page is GONE). Audited: all five register their reads on',
	  '-- clk_mem ' + EMDASH + ' UART-class movers, plain shims, no bridge. SYSTEM0 note:',
	  '-- SYS_CLK_CR/SYS_CLK_DIV_CR reconfigure MCLK ITSELF ' + EMDASH + ' reconfiguring',
	  '-- with other masters mid-transaction is a software-contract violation',
	  '-- (management hart quiesces the others first).'],
	 ['SYSTEM', 'GPIO0', 'SPI0'], 14),
]

# I2C interrupt-declaration comments, transcribed verbatim (the RTL wording is
# NOT derivable from the IRQB descriptions: Master vs Master Mode differs
# between I2C0 and I2C1 in the RTL)
I2C_DECL_COMMENTS = {
	('str', 0): 'Start Received Interrupt', ('str', 1): 'Start Received Interrupt',
	('spr', 0): 'Stop Received Interrupt', ('spr', 1): 'Stop Received Interrupt',
	('msts', 0): 'Master Mode Start Condition Sent Interrupt', ('msts', 1): 'Master Mode Start Condition Sent Interrupt',
	('msps', 0): 'Master Mode Stop Condition Sent Interrupt', ('msps', 1): 'Master Mode Stop Condition Sent Interrupt',
	('marb', 0): 'Master Arbitration Lost Interrupt', ('marb', 1): 'Master Mode Arbitration Lost Interrupt',
	('mtxe', 0): 'Master Transmit Empty Interrupt', ('mtxe', 1): 'Master Mode Transmit Empty Interrupt',
	('mnr', 0): 'Master Mode NACK Received Interrupt', ('mnr', 1): 'Master Mode NACK Received Interrupt',
	('mxc', 0): 'Master Transfer Complete Interrupt', ('mxc', 1): 'Master Mode Transfer Complete Interrupt',
	('sa', 0): 'Slave Address Interrupt', ('sa', 1): 'Slave Address Interrupt',
	('stxe', 0): 'Slave Transmit Empty Interrupt', ('stxe', 1): 'Slave Transmit Empty Interrupt',
	('sovf', 0): 'Slave Overflow Interrupt', ('sovf', 1): 'Slave Overflow Interrupt',
	('snr', 0): 'Slave Mode NACK Received Interrupt', ('snr', 1): 'Slave Mode NACK Received Interrupt',
	('sxc', 0): 'Slave Transfer Complete Interrupt', ('sxc', 1): 'Slave Transfer Complete Interrupt',
}

# Memory-bus port-map specs per instance. Fields:
#   periph   : description peripheral name
#   ports    : port names in the RTL's order for this component type
#   width    : port-name column width (component-type formatting)
#   trailing : per-line trailing-space flags (RTL formatting quirks), or None
#   comment  : 'slot' (derived page-3 comment), 'plain' (window comment, no slot),
#              'i2c'/'npu' (two-line combinational-read comments), or None
BUS_ORDER_A = ['clk_mem', 'en_mem', 'wen', 'addr_periph', 'write_data', 'read_data']	# SYSTEM/UART/TIMER
BUS_ORDER_B = ['clk_mem', 'en', 'wen', 'write_data', 'read_data', 'addr_periph']	# GPIO
BUS_ORDER_C = ['clk_mem', 'en_mem', 'wen', 'write_data', 'read_data', 'addr_periph']	# SPI
BUS_SPECS = {
	'system0': {'periph': 'SYSTEM', 'ports': BUS_ORDER_A, 'width': 14, 'trailing': None, 'comment': 'slot'},
	'gpio0':   {'periph': 'GPIO0', 'ports': BUS_ORDER_B, 'width': 16, 'trailing': None, 'comment': 'slot'},
	'gpio1':   {'periph': 'GPIO1', 'ports': BUS_ORDER_B, 'width': 16, 'trailing': None, 'comment': None},
	'gpio2':   {'periph': 'GPIO2', 'ports': BUS_ORDER_B, 'width': 16, 'trailing': None, 'comment': None},
	'gpio3':   {'periph': 'GPIO3', 'ports': BUS_ORDER_B, 'width': 16, 'trailing': None, 'comment': None},
	'spi0':    {'periph': 'SPI0', 'ports': BUS_ORDER_C, 'width': 16, 'trailing': None, 'comment': 'slot'},
	'spi1':    {'periph': 'SPI1', 'ports': BUS_ORDER_C, 'width': 16, 'trailing': None, 'comment': 'slot'},
	'uart0':   {'periph': 'UART0', 'ports': BUS_ORDER_A, 'width': 12, 'trailing': None, 'comment': 'slot'},
	'uart1':   {'periph': 'UART1', 'ports': BUS_ORDER_A, 'width': 12, 'trailing': None, 'comment': 'slot'},
	'i2c0':    {'periph': 'I2C0', 'ports': None, 'width': None, 'trailing': None, 'comment': 'i2c'},
	'i2c1':    {'periph': 'I2C1', 'ports': None, 'width': None, 'trailing': None, 'comment': 'i2c'},
	'timer0':  {'periph': 'TIMER0', 'ports': BUS_ORDER_A, 'width': 13, 'trailing': None, 'comment': 'slot'},
	'timer1':  {'periph': 'TIMER1', 'ports': BUS_ORDER_A, 'width': 13, 'trailing': None, 'comment': 'slot'},
	'npu0':    {'periph': 'NPU', 'ports': None, 'width': None, 'trailing': None, 'comment': 'npu'},
}

# M11 shared-window geometry (the peripheral window at 0x4000; page 0 = the
# 16 legacy-numbered slots, pages 1-3 = CLINT / MUTEX / IRQROUTER)
SHARED_WINDOW_BASE = 0x4000
SHARED_SLOT_SIZE = 0x100
CLINT_BASE = 0x5000
MUTEX_BASE = 0x6000
IRQROUTER_BASE = 0x7000


class McuVhdEmitter():
	def __init__(self, gen):
		self.gen = gen
		self.periphsByName = {}
		for p in gen.Peripherals:
			self.periphsByName[p.Name] = p
		self.slotSpelling = gen.McuMpCompat['periphSlotSpelling']
		self.irqVectors = gen.McuMpCompat['irqVectors']
		self.crossCheck()

	def periph(self, name):
		if name not in self.periphsByName:
			raise Exception('MCU.vhd emitter: description has no peripheral named "' + name + '"')
		return self.periphsByName[name]

	def slotName(self, periphName):
		return 'PeriphSlot' + self.slotSpelling.get(periphName, periphName)

	def crossCheck(self):
		'''RAISE when the description and the transcribed RTL structure disagree.'''
		# 1. sharedBus='periph' membership must match the transcribed shim/mux structure
		descShared = set(p.Name for p in self.gen.Peripherals if getattr(p, 'SharedBus', None) == 'periph')
		rtlShared = set(n for n in SHSLV if SHSLV[n]['shim'] is not None)
		if descShared != rtlShared:
			raise Exception('MCU.vhd emitter: sharedBus=periph peripherals ' + str(sorted(descShared))
				+ ' do not match the transcribed RTL fabric ' + str(sorted(rtlShared))
				+ ' (update the SHSLV/order tables in mcu_vhd.py from the RTL)')
		descNative = set(p.Name for p in self.gen.Peripherals if getattr(p, 'SharedBus', None) == 'native')
		rtlNative = set(n for n in SHSLV if SHSLV[n]['shim'] is None)
		if descNative != rtlNative:
			raise Exception('MCU.vhd emitter: sharedBus=native peripherals ' + str(sorted(descNative))
				+ ' do not match the transcribed RTL fabric ' + str(sorted(rtlNative)))

		# 2. M11 window geometry: the three native MP blocks own pages 1-3;
		# every shared peripheral sits in page 0 at its LEGACY slot number.
		if self.periph('CLINT').BaseAddress != CLINT_BASE:
			raise Exception('MCU.vhd emitter: CLINT base address ' + hex(self.periph('CLINT').BaseAddress)
				+ ' != ' + hex(CLINT_BASE))
		if self.periph('MUTEX').BaseAddress != MUTEX_BASE:
			raise Exception('MCU.vhd emitter: MUTEX base address ' + hex(self.periph('MUTEX').BaseAddress)
				+ ' != ' + hex(MUTEX_BASE))
		if self.periph('IRQROUTER').BaseAddress != IRQROUTER_BASE:
			raise Exception('MCU.vhd emitter: IRQROUTER base address ' + hex(self.periph('IRQROUTER').BaseAddress)
				+ ' != ' + hex(IRQROUTER_BASE))
		for name in rtlShared:
			p = self.periph(name)
			slot = self.winSlot(name)
			expected = SHARED_WINDOW_BASE + SHARED_SLOT_SIZE * slot
			if p.BaseAddress != expected:
				raise Exception('MCU.vhd emitter: ' + name + ' base address ' + hex(p.BaseAddress)
					+ ' does not match window slot ' + str(slot) + ' (' + hex(expected) + ')')

		# 3. Bridge membership == combinationalRead metadata
		descComb = set(p.Name for p in self.gen.Peripherals if getattr(p, 'CombinationalRead', False))
		if descComb != set(['I2C0', 'I2C1', 'NPU']):
			raise Exception('MCU.vhd emitter: combinationalRead peripherals ' + str(sorted(descComb))
				+ ' do not match the transcribed rdata-bridge membership (I2C0, I2C1, NPU)')

		# 4. Order lists must cover the shared set exactly
		if set(PG0_SEL_ORDER) != rtlShared:
			raise Exception('MCU.vhd emitter: PG0_SEL_ORDER does not cover the window-slot peripherals')
		slots = [self.winSlot(n) for n in PG0_SEL_ORDER + PG0_NATIVE_ORDER]
		if len(set(slots)) != len(slots) or any(s < 0 or s > 15 for s in slots):
			raise Exception('MCU.vhd emitter: page-0 slots must be unique and within 0..15 (reserved gaps allowed)')
		# M17: native page-0 slaves (PWRCTRL) must be native AND sit at their slot address
		for name in PG0_NATIVE_ORDER:
			if name not in rtlNative:
				raise Exception('MCU.vhd emitter: ' + name + ' must be sharedBus=native (page-0 native slave)')
			expected = SHARED_WINDOW_BASE + SHARED_SLOT_SIZE * self.winSlot(name)
			if self.periph(name).BaseAddress != expected:
				raise Exception('MCU.vhd emitter: ' + name + ' base address ' + hex(self.periph(name).BaseAddress)
					+ ' does not match window slot ' + str(self.winSlot(name)) + ' (' + hex(expected) + ')')
		if set(RD_ORDER) != rtlShared | rtlNative | set(MEMSLV):
			raise Exception('MCU.vhd emitter: RD_ORDER does not cover the shared slaves')
		if set(EN_ORDER) != rtlShared | rtlNative | set(MEMSLV):
			raise Exception('MCU.vhd emitter: EN_ORDER does not cover the shared slaves')
		shimAll = set()
		for _, names, _ in SHIM_GROUPS:
			shimAll |= set(names)
		if shimAll != rtlShared:
			raise Exception('MCU.vhd emitter: SHIM_GROUPS do not cover the shared peripherals')

	def winSlot(self, name):
		'''Peripheral-window page-0 slot (the LEGACY 0x4000-page slot number).'''
		p = self.periph(name)
		slot = p.LegacySlot
		if slot is None or slot < 0 or slot > 15:
			raise Exception('MCU.vhd emitter: ' + name + ' has no valid window slot')
		return slot

	def selOf(self, key):
		'''EN/RD_ORDER key -> shslv_<sel> spelling (peripheral or memory slave).'''
		if key in MEMSLV:
			return key
		return SHSLV[key]['sel']

	def rdataOf(self, key):
		'''EN/RD_ORDER key -> the rdata net muxed into sh_rdata_mux.'''
		if key in MEMSLV:
			return MEMSLV[key]
		sig = SHSLV[key]['rdata']
		if getattr(self.periph(key), 'CombinationalRead', False):
			pass	# the bridge-registered net keeps the plain name
		return sig

	def rdataSignal(self, name):
		'''Signal the instance drives: bridge slaves drive the _c (combinational) net.'''
		sig = SHSLV[name]['rdata']
		if getattr(self.periph(name), 'CombinationalRead', False):
			sig += '_c'
		return sig

	# ------------------------------------------------------------------
	# Region emitters (each returns a list of lines, no trailing newlines)
	# ------------------------------------------------------------------

	def irqSignalName(self, irqbName):
		'''IRQB_* constant name -> MCU.vhd irq signal text (irq_comb right-hand side).'''
		m = re.match(r'^IRQB_GPIO(\d)_B(\d)$', irqbName)
		if m:
			return 'irq_gpio' + m.group(1) + '(' + m.group(2) + ')'
		return 'irq_' + irqbName[len('IRQB_'):].lower()

	def emitIrqSignalDecls(self):
		lines = []
		emittedGpio = set()
		for irqbName, desc in self.irqVectors:
			if irqbName.startswith('IRQB_CLINT_'):
				continue	# CLINT levels are clint_msip/mtip, declared with the fabric
			if irqbName.startswith('IRQB_RSVD'):
				continue	# reserved vector gap (removed peripheral) — tied low via 'others'
			m = re.match(r'^IRQB_GPIO(\d)_B\d$', irqbName)
			if m:
				# One vector declaration per GPIO port, grouped where GPIO0 appears
				if len(emittedGpio) > 0:
					continue
				for port in range(4):
					lines.append(' ' * 8 + 'signal ' + ('irq_gpio' + str(port)).ljust(17)
						+ ': std_logic_vector(7 downto 0);  -- GPIO' + str(port) + ' Interrupt')
					emittedGpio.add(port)
				continue
			name = 'irq_' + irqbName[len('IRQB_'):].lower()
			mi2c = re.match(r'^IRQB_I2C(\d)_(\w+)$', irqbName)
			if mi2c:
				inst = int(mi2c.group(1))
				comment = 'I2C' + mi2c.group(1) + ' ' + I2C_DECL_COMMENTS[(mi2c.group(2).lower(), inst)]
				pad = 16	# the RTL's I2C block is aligned one column tighter
			else:
				comment = desc
				pad = 17
			lines.append(' ' * 8 + 'signal ' + name.ljust(pad) + ': std_logic;  -- ' + comment)
		return lines

	def emitIrqComb(self):
		lines = [' ' * 8 + 'irq_comb <= (']
		for irqbName, desc in self.irqVectors:
			if irqbName.startswith('IRQB_CLINT_'):
				continue	# emitted below with the M5b comment
			if irqbName.startswith('IRQB_RSVD'):
				continue	# reserved vector gap — falls through to 'others => irq_tielow'
			lines.append(' ' * 12 + irqbName.ljust(16) + '=> ' + self.irqSignalName(irqbName) + ',')
		lines.append(' ' * 12 + "-- M5b: hart 0's CLINT levels (harts 1-3 get theirs via tile ports)")
		lines.append(' ' * 12 + 'IRQB_CLINT_MSIP => clint_msip(0),')
		lines.append(' ' * 12 + 'IRQB_CLINT_MTIP => clint_mtip(0),')
		lines.append(' ' * 12 + 'others          => irq_tielow')
		lines.append(' ' * 8 + ');')
		return lines

	def emitShslvSubdecode(self):
		ind = ' ' * 4
		clintBits = format((CLINT_BASE >> 12) & 3, '02b')
		mtxBits = format((MUTEX_BASE >> 12) & 3, '02b')
		irtrBits = format((IRQROUTER_BASE >> 12) & 3, '02b')
		lines = []
		lines.append(ind + '-- M11/M12: page select on s_addr(14:12). Page 000 is the shared boot')
		lines.append(ind + '-- ROM (M12 ' + EMDASH + ' the single rom_hvt_pg all four harts reset into);')
		lines.append(ind + '-- 010 is the TCM region (tile-private, never arrives here).')
		lines.append(ind + 'shslv_rom_sel'.ljust(16) + ' <= \'1\' when sh_addr(14 downto 12) = "000" else \'0\';')
		lines.append(ind + 'shslv_perwin_sel'.ljust(16) + ' <= \'1\' when sh_addr(14 downto 12) = "001" else \'0\';')
		lines.append(ind + 'shslv_npuram_sel'.ljust(16) + ' <= \'1\' when sh_addr(14 downto 12) = "011" else \'0\';')
		for b in range(4):
			lines.append(ind + ('shslv_bank' + str(b) + '_sel').ljust(16) + ' <= \'1\' when sh_addr(14 downto 12) = "1'
				+ format(b, '02b') + '" else \'0\';')
		lines.append(ind + '-- peripheral-window pages on sh_addr(11:10): page 0 = the 16 slots,')
		lines.append(ind + '-- page 1 = CLINT, page 2 = MUTEX bank, page 3 = IRQ router')
		lines.append(ind + 'shslv_pg0_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "00" else \'0\';')
		lines.append(ind + 'shslv_clint_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + clintBits + '" else \'0\';')
		lines.append(ind + 'shslv_mtx_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + mtxBits + '" else \'0\';')
		lines.append(ind + 'shslv_irtr_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + irtrBits + '" else \'0\';')
		lines.append(ind + '-- page-0 slots (slot = sh_addr(9:6)) at the LEGACY 0x4000 numbering ' + EMDASH)
		lines.append(ind + '-- every peripheral back at its original Myshkin address, shared by')
		lines.append(ind + '-- all 4 harts')
		for name in PG0_SEL_ORDER:
			selName = 'shslv_' + SHSLV[name]['sel'] + '_sel'
			lines.append(ind + selName.ljust(16) + ' <= shslv_pg0_sel when sh_addr(9 downto 6) = "'
				+ format(self.winSlot(name), '04b') + '" else \'0\';')
		lines.append(ind + '-- M17: the power controller is a NATIVE slave IN a page-0 slot (11,')
		lines.append(ind + '-- 0x4B00 ' + EMDASH + ' vacated by SARADC0): slot-decoded like the peripherals')
		lines.append(ind + '-- above, but it speaks the arbiter protocol directly (no shim).')
		for name in PG0_NATIVE_ORDER:
			selName = 'shslv_' + SHSLV[name]['sel'] + '_sel'
			lines.append(ind + selName.ljust(16) + ' <= shslv_pg0_sel when sh_addr(9 downto 6) = "'
				+ format(self.winSlot(name), '04b') + '" else \'0\';')
		for key in EN_ORDER:
			sel = self.selOf(key)
			lines.append(ind + ('shslv_' + sel + '_en').ljust(16) + ' <= sh_en and shslv_' + sel + '_sel;')
		return lines

	def emitShslvRdSel(self):
		ind = ' ' * 4
		lines = []
		lines.append(ind + 'shslv_rd_sel: process(mclk, resetn)')
		lines.append(ind + 'begin')
		lines.append(ind * 2 + "if resetn = '0' then")
		for key in RD_ORDER:
			lines.append(ind * 3 + ('shslv_rd_' + self.selOf(key)).ljust(16) + " <= '0';")
		lines.append(ind * 2 + 'elsif rising_edge(mclk) then')
		lines.append(ind * 3 + "if sh_en = '1' then")
		for key in RD_ORDER:
			sel = self.selOf(key)
			lines.append(ind * 4 + ('shslv_rd_' + sel).ljust(16) + ' <= shslv_' + sel + '_sel;')
		lines.append(ind * 3 + 'end if;')
		lines.append(ind * 2 + 'end if;')
		lines.append(ind + 'end process;')
		return lines

	def emitRdataBridge(self):
		ind = ' ' * 4
		lines = []
		lines.append(ind + "-- M7c.2: I2C read-bridge registers " + EMDASH + " capture the I2C's COMBINATIONAL")
		lines.append(ind + '-- rdata at the LATCH->DATA edge (while its one-cycle en strobe is high')
		lines.append(ind + "-- and MABPart still selects the addressed register), so the arbiter's")
		lines.append(ind + '-- end-of-DATA capture sees the right value. Every other slave registers')
		lines.append(ind + "-- its own read; I2C.vhd's collapses to register 0 when en deasserts.")
		lines.append(ind + 'i2c_rdata_bridge: process(mclk, resetn)')
		lines.append(ind + 'begin')
		lines.append(ind * 2 + "if resetn = '0' then")
		lines.append(ind * 3 + "i2c0_sh_rdata <= (others => '0');")
		lines.append(ind * 3 + "i2c1_sh_rdata <= (others => '0');")
		lines.append(ind * 3 + "npu_sh_rdata  <= (others => '0');")
		lines.append(ind * 2 + 'elsif rising_edge(mclk) then')
		lines.append(ind * 3 + "if shslv_i2c0_en = '1' then")
		lines.append(ind * 4 + 'i2c0_sh_rdata <= i2c0_sh_rdata_c;')
		lines.append(ind * 3 + 'end if;')
		lines.append(ind * 3 + "if shslv_i2c1_en = '1' then")
		lines.append(ind * 4 + 'i2c1_sh_rdata <= i2c1_sh_rdata_c;')
		lines.append(ind * 3 + 'end if;')
		lines.append(ind * 3 + "-- M7d: NPU's MabMmrQ is combinational too (same rule)")
		lines.append(ind * 3 + "if shslv_npu_en = '1' then")
		lines.append(ind * 4 + 'npu_sh_rdata <= npu_sh_rdata_c;')
		lines.append(ind * 3 + 'end if;')
		lines.append(ind * 2 + 'end if;')
		lines.append(ind + 'end process;')
		return lines

	def emitShRdataMux(self):
		lines = []
		prefix = ' ' * 4 + 'sh_rdata_mux <= '
		cont = ' ' * len(prefix)
		for i, key in enumerate(RD_ORDER):
			row = self.rdataOf(key).ljust(14) + ' when ' + ('shslv_rd_' + self.selOf(key)).ljust(16) + " = '1' else"
			lines.append((prefix if i == 0 else cont) + row)
		lines.append(cont + "(others => '0');  -- no slave (TCM page, unmapped)")
		return lines

	def emitPolarityShims(self):
		ind = ' ' * 4
		lines = []
		for gi, (comment, names, pad) in enumerate(SHIM_GROUPS):
			for c in comment:
				lines.append(ind + c)
			for name in names:
				shim = SHSLV[name]['shim'] + '_sh_en_n'
				lines.append(ind + shim.ljust(pad) + '<= not shslv_' + SHSLV[name]['sel'] + '_en;')
			if gi == 0:
				lines.append(ind + 'sh_wen_n <= not sh_we;')
				lines.append('')
		return lines

	# ------------------------------------------------------------------
	# A1 (Argus): N-hart region emitters. Every emitter reproduces the golden
	# master BYTE-IDENTICALLY at numHarts=4 (check_mcu_vhd.py STRICT); the
	# per-hart digits, widths, slice bounds and count prose are computed from
	# numHarts. Alignment paddings are the golden master's columns, widened
	# only when a longer name (h >= 10) forces it.
	# ------------------------------------------------------------------

	def nHarts(self):
		n = self.gen.NumHarts
		if type(n) != int or n < 2:
			raise Exception('MCU.vhd emitter: numHarts must be an int >= 2 for the MCU_MP template, got ' + str(n))
		return n

	def hartsWord(self):
		'''Count prose for "identical on all <N> tiles".'''
		return _HARTS_WORD.get(self.nHarts(), str(self.nHarts()))

	def sigDecl(self, name, rest):
		'''Architecture signal declaration at the golden master's name pad.'''
		return ' ' * 8 + 'signal ' + name.ljust(max(17, len(name) + 1)) + ': ' + rest

	def clintAddrW(self):
		'''CLINT word-address width from the description's register slots,
		cross-checked against the A0/A1 layout formula (mtime lo at word
		roundup16(4N)/4, mtimecmp pairs at +4; hdl/MCU_MP/clint.vhd implements
		the same formula). RAISES if generate.py's CLINT layout drifts.'''
		n = self.nHarts()
		mtimeSlot = ((4 * n + 15) // 16) * 4
		slots = {}
		maxSlot = 0
		for r in self.periph('CLINT').Registers:
			slots[r.Name] = r.RegisterMemorySlot
			if r.RegisterMemorySlot > maxSlot:
				maxSlot = r.RegisterMemorySlot
		if slots.get('MTIMEL') != mtimeSlot or slots.get('MTIMECMP0L') != mtimeSlot + 4 \
				or maxSlot != mtimeSlot + 4 + 2 * n - 1:
			raise Exception('MCU.vhd emitter: CLINT register layout does not match the A0/A1 formula '
				+ '(mtime lo at word ' + str(mtimeSlot) + ', mtimecmp at +4 .. +4+2N-1) '
				+ EMDASH + ' generate.py and clint.vhd must agree')
		return _clog2(maxSlot + 1)

	def emitA0Ports(self):
		n = self.nHarts()
		lines = [' ' * 8 + '-- M3b: per-hart pass/fail observation (a0 of the ' + str(n - 1) + ' private-memory harts)']
		for h in range(1, n):
			lines.append(' ' * 8 + 'a0_' + str(h) + ' : out std_logic_vector(31 downto 0)' + (';' if h != n - 1 else ''))
		return lines

	def emitArbFabricDecls(self):
		n = self.nHarts()
		nm1 = str(n - 1)
		lines = []
		lines.append(self.sigDecl('arb_lrsc', 'std_logic_vector(' + str(n) + '*2-1 downto 0);'))
		lines.append(self.sigDecl('arb_scfail', 'std_logic_vector(' + nm1 + ' downto 0);'))
		lines.append(self.sigDecl('sh_we_raw', 'std_logic_vector(3 downto 0);  -- arbiter s_we, pre resv gating'))
		lines.append(' ' * 8 + '-- arbiter master buses (master 0 = hart 0; masters 1-' + nm1 + ' = hart tiles).')
		lines.append(' ' * 8 + '-- we = 4 active-high byte-lane strobes per master (M4a).')
		lines.append(' ' * 8 + 'signal arb_req, arb_gnt, arb_done : std_logic_vector(' + nm1 + ' downto 0);')
		lines.append(' ' * 8 + "-- M8: per-master grant-lock (cores' amo_lock) " + EMDASH + ' pins the arbiter to a')
		lines.append(' ' * 8 + '-- master across its AMO read+write transaction pair (cross-hart AMO')
		lines.append(' ' * 8 + '-- atomicity).')
		lines.append(self.sigDecl('arb_lock', 'std_logic_vector(' + nm1 + ' downto 0);'))
		lines.append(self.sigDecl('arb_we', 'std_logic_vector(' + str(n) + '*4-1 downto 0);'))
		lines.append(self.sigDecl('arb_addr', 'std_logic_vector(' + str(n) + '*SH_AW-1 downto 0);'))
		lines.append(self.sigDecl('arb_wdata', 'std_logic_vector(' + str(n) + '*32-1 downto 0);'))
		lines.append(self.sigDecl('arb_rdata', 'std_logic_vector(31 downto 0);'))
		return lines

	def emitClintIrqDecls(self):
		nm1 = str(self.nHarts() - 1)
		return [self.sigDecl('clint_msip', 'std_logic_vector(' + nm1 + ' downto 0);'),
			self.sigDecl('clint_mtip', 'std_logic_vector(' + nm1 + ' downto 0);')]

	def emitTileIrqEnFlatDecl(self):
		return [self.sigDecl('tile_irq_en_flat', 'std_logic_vector(' + str(self.nHarts()) + '*NUM_IRQS-1 downto 0);')]

	def emitPdDecls(self):
		rng = 'std_logic_vector(' + str(self.nHarts() - 1) + ' downto 1);'
		return [self.sigDecl(nm, rng) for nm in ('pd_iso_en', 'pd_sleep', 'pd_rstn', 'tile_rstn')]

	def emitTileRawDecls(self):
		n = self.nHarts()
		lines = []
		for kind, rng in [('req', 'std_logic;'), ('we', 'std_logic_vector(3 downto 0);'),
				('addr', 'std_logic_vector(SH_AW-1 downto 0);'), ('wdata', 'std_logic_vector(31 downto 0);'),
				('lrsc', 'std_logic_vector(1 downto 0);'), ('lock', 'std_logic;')]:
			for h in range(1, n):
				lines.append(self.sigDecl('tile' + str(h) + '_' + kind + '_raw', rng))
		for h in range(1, n):
			lines.append(self.sigDecl('a0_' + str(h) + '_raw', 'std_logic_vector(31 downto 0);'))
		return lines

	def emitShMasterDecl(self):
		w = max(1, _clog2(self.nHarts()))
		return [self.sigDecl('sh_master', 'std_logic_vector(' + str(w - 1) + ' downto 0);')]

	def emitHart0Instance(self):
		nm1 = str(self.nHarts() - 1)
		lines = []
		lines.append('    -- =========================================================================')
		lines.append('    -- M13 TILE EXTRACTION: hart 0 is the SAME hart_tile as harts 1-' + nm1 + ' ' + EMDASH + ' the')
		lines.append('    -- inline core/adddec/TCM/shared-window machinery that used to live here')
		lines.append('    -- (and that hart_tile mirrored since M3c) is folded into the tile. The')
		lines.append('    -- M12 wait-for-boot-fetch reset release, the M4b/M10 qualified ack, the')
		lines.append('    -- M10 clk_cpu-staged consumption register and the M9b nop-force all')
		lines.append('    -- live in hart_tile.vhd now ' + EMDASH + " see the rationale there. Hart 0's")
		lines.append('    -- remaining specials are pure WIRING on the identical tile:')
		lines.append('    --   * sleep + flash ports -> SPI0 (XIP; tiles have no SPI0 behind them),')
		lines.append('    --   * irq_en_ext/irq_prio_ext/irq_recursion_en/isr_ret -> SYSTEM0')
		lines.append("    --     (hw_clint_en='0': SYS_IRQ_EN's reset-all-masked semantics kept;")
		lines.append('    --     tiles hardwire CLINT slots 83/84 instead and take the router row),')
		lines.append('    --   * tcm_pgen -> pgen_mem(1) (BLOCKPWR RAM gating),')
		lines.append('    --   * trap_flag -> the GPIO0 trap pin; a0 -> the tb pass/fail gate.')
		lines.append('    -- The M2 wait_inj0 stall exerciser is RETIRED (M10 proved latency')
		lines.append('    -- insensitivity at boundary depths 0/1/2; the boot fetch through the')
		lines.append('    -- arbiter exercises the stall path on every run).')
		lines.append('    -- =========================================================================')
		lines.append('    hart0: entity work.hart_tile')
		lines.append('        generic map (')
		lines.append('            PC_RST_VAL     => x"00000000",')
		lines.append('            SH_AW          => SH_AW,')
		lines.append('            -- Core ISA features (config-driven, work.MemoryMap; MUST be')
		lines.append('            -- identical on all ' + self.hartsWord() + ' tiles -- one hardened netlist)')
		lines.append('            ENABLE_MUL        => CORE_ENABLE_MUL,')
		lines.append('            ENABLE_DIV        => CORE_ENABLE_DIV,')
		lines.append('            ENABLE_ATOMICS    => CORE_ENABLE_ATOMICS,')
		lines.append('            ENABLE_COMPRESSED => CORE_ENABLE_COMPRESSED,')
		lines.append('            ENABLE_BITMANIP   => CORE_ENABLE_BITMANIP')
		lines.append('        )')
		lines.append('        port map (')
		lines.append('            clk       => mclk,')
		lines.append('            resetn    => resetn,')
		lines.append('            sleep     => sleep_cpu,')
		lines.append('            hart_id   => x"00000000",')
		lines.append('            msip_in   => clint_msip(0),')
		lines.append('            mtip_in   => clint_mtip(0),')
		lines.append('            irq_ext    => irq_deglitch,')
		lines.append('            irq_en_ext => irq_en,')
		lines.append('            irq_prio_ext     => irq_priority,')
		lines.append('            irq_recursion_en => irq_recursion_en,')
		lines.append('            isr_ret          => isr_ret,')
		lines.append("            hw_clint_en      => '0',")
		lines.append('            flash_mem_en  => mem_en_flash,')
		lines.append('            flash_clk_mem => clk_mem_flash,')
		lines.append('            flash_mab     => mab_flash,')
		lines.append('            flash_dout    => flash_dout,')
		lines.append('            sh_req    => arb_req(0),')
		lines.append('            sh_we     => arb_we(3 downto 0),')
		lines.append('            sh_addr   => arb_addr(SH_AW-1 downto 0),')
		lines.append('            sh_wdata  => arb_wdata(31 downto 0),')
		lines.append('            sh_gnt    => arb_gnt(0),')
		lines.append('            sh_done   => arb_done(0),')
		lines.append('            sh_rdata  => arb_rdata,')
		lines.append('            sh_lrsc   => arb_lrsc(1 downto 0),')
		lines.append('            sh_scfail => arb_scfail(0),')
		lines.append('            sh_lock   => arb_lock(0),')
		lines.append('            tcm_pgen  => pgen_mem(1),')
		lines.append('            -- M17: hart 0 is ALWAYS-ON ' + EMDASH + ' its domain controls are strapped')
		lines.append('            -- inactive (explicit, per the M14 netlist-boundary rule)')
		lines.append("            pd_sleep  => '0',")
		lines.append("            pd_iso_en => '0',")
		lines.append('            trap_flag => trap_out,')
		lines.append('            a0        => a0')
		lines.append('        );')
		return lines

	def emitArbGeneric(self):
		return [' ' * 8 + 'generic map (N => ' + str(self.nHarts()) + ', ADDR_WIDTH => SH_AW, DATA_WIDTH => 32)']

	def emitResvGeneric(self):
		return [' ' * 8 + 'generic map (N => ' + str(self.nHarts()) + ', ADDR_WIDTH => SH_AW)']

	def emitClintInstance(self):
		n = self.nHarts()
		addrW = self.clintAddrW()
		# the clint.vhd ADDR_W generic default (4) IS the Castalia shape; only
		# non-default widths are passed explicitly (N=4 byte-identity)
		gm = 'generic map (NHARTS => ' + str(n) + (')' if addrW == 4 else ', ADDR_W => ' + str(addrW) + ')')
		lines = []
		lines.append('    clint0: entity work.clint')
		lines.append(' ' * 8 + gm)
		lines.append('        port map (')
		lines.append('            clk    => mclk,')
		lines.append('            resetn => resetn,')
		lines.append('            en     => shslv_clint_en,')
		lines.append('            we     => sh_we,')
		lines.append('            addr   => sh_addr(' + str(addrW - 1) + ' downto 0),')
		lines.append('            wdata  => sh_wdata,')
		lines.append('            rdata  => clint_rdata,')
		lines.append('            msip   => clint_msip,')
		lines.append('            mtip   => clint_mtip')
		lines.append('        );')
		return lines

	def emitIrqRouterInstance(self):
		n = self.nHarts()
		nm1 = str(n - 1)
		# rows at +0x10*h -> 4 words per hart; 4-bit floor is the golden
		# master's sh_addr(3 downto 0) (irq_router.vhd regrows at A2 for N>4)
		addrW = max(4, _clog2(4 * n))
		lines = []
		lines.append('    -- M7a: tile IRQ fan-out ' + EMDASH + ' per-hart peripheral-IRQ enable rows, written by')
		lines.append('    -- any hart through the arbiter (resv-gated sh_we, like the CLINT). Rows')
		lines.append('    -- 1-' + nm1 + " feed the tiles' irq_en_ext; row 0 exists for symmetry but hart 0's")
		lines.append('    -- enables stay with SYSTEM0 (the management monarch). Resets all-masked,')
		lines.append('    -- so this block is a provable NO-OP until software routes an IRQ.')
		lines.append('    irtr0: entity work.irq_router')
		lines.append('        generic map (NHARTS => ' + str(n) + ', NUM_IRQS => NUM_IRQS)')
		lines.append('        port map (')
		lines.append('            clk        => mclk,')
		lines.append('            resetn     => resetn,')
		lines.append('            en         => shslv_irtr_en,')
		lines.append('            we         => sh_we,')
		lines.append('            addr       => sh_addr(' + str(addrW - 1) + ' downto 0),')
		lines.append('            wdata      => sh_wdata,')
		lines.append('            rdata      => irtr_rdata,')
		lines.append('            irq_en_out => tile_irq_en_flat')
		lines.append('        );')
		return lines

	def emitTileRstn(self):
		return ['    tile_rstn(' + str(h) + ') <= resetn and pd_rstn(' + str(h) + ');'
			for h in range(1, self.nHarts())]

	def emitIsoClamps(self):
		n = self.nHarts()
		lines = []
		for h in range(1, n):
			hs = str(h)
			addrLo = 'SH_AW' if h == 1 else hs + '*SH_AW'
			wdataLo = '32' if h == 1 else hs + '*32'
			rows = [
				('arb_req(' + hs + ')', 'tile' + hs + '_req_raw', "'0'", False),
				('arb_we(' + str(4 * h + 3) + ' downto ' + str(4 * h) + ')', 'tile' + hs + '_we_raw', "(others => '0')", False),
				('arb_addr(' + str(h + 1) + '*SH_AW-1 downto ' + addrLo + ')', 'tile' + hs + '_addr_raw', "(others => '0')", True),
				('arb_wdata(' + str(h + 1) + '*32-1 downto ' + wdataLo + ')', 'tile' + hs + '_wdata_raw', "(others => '0')", True),
				('arb_lrsc(' + str(2 * h + 1) + ' downto ' + str(2 * h) + ')', 'tile' + hs + '_lrsc_raw', '"00"', False),
				('arb_lock(' + hs + ')', 'tile' + hs + '_lock_raw', "'0'", False),
				('a0_' + hs, 'a0_' + hs + '_raw', "(others => '0')", False),
			]
			# golden-master columns: short lines pad the LHS to 24 and the RHS
			# to 16; the long addr/wdata pair aligns to itself with 1 space
			lhsPad, rhsPad, longPad = 24, 16, 0
			for lhs, rhs, els, lng in rows:
				if lng:
					longPad = max(longPad, len(lhs) + 1)
				else:
					lhsPad = max(lhsPad, len(lhs) + 1)
					rhsPad = max(rhsPad, len(rhs) + 1)
			if h > 1:
				lines.append('')
			for lhs, rhs, els, lng in rows:
				lines.append(' ' * 4 + lhs.ljust(longPad if lng else lhsPad) + '<= '
					+ (rhs + ' ' if lng else rhs.ljust(rhsPad))
					+ 'when pd_iso_en(' + hs + ") = '0' else " + els + ';')
		return lines

	def tileInstance(self, h):
		hs = str(h)
		lines = []
		lines.append('    hart' + hs + ': entity work.hart_tile')
		lines.append('        generic map (')
		lines.append('            PC_RST_VAL     => x"00000000",')
		lines.append('            SH_AW          => SH_AW,')
		lines.append('            -- Core ISA features (config-driven, work.MemoryMap; MUST be')
		lines.append('            -- identical on all ' + self.hartsWord() + ' tiles -- one hardened netlist)')
		lines.append('            ENABLE_MUL        => CORE_ENABLE_MUL,')
		lines.append('            ENABLE_DIV        => CORE_ENABLE_DIV,')
		lines.append('            ENABLE_ATOMICS    => CORE_ENABLE_ATOMICS,')
		lines.append('            ENABLE_COMPRESSED => CORE_ENABLE_COMPRESSED,')
		lines.append('            ENABLE_BITMANIP   => CORE_ENABLE_BITMANIP')
		lines.append('        )')
		lines.append('        port map (')
		lines.append('            clk       => mclk,')
		lines.append("            -- M17: pwr_ctrl's cold-gate reset folds in (tile_rstn = resetn")
		lines.append('            -- and pd_rstn) ' + EMDASH + ' a gated/waking tile is held in reset')
		lines.append('            resetn    => tile_rstn(' + hs + '),')
		lines.append("            sleep     => '0',")
		lines.append('            hart_id   => x"' + format(h, '08x') + '",')
		lines.append('            msip_in   => clint_msip(' + hs + '),')
		lines.append('            mtip_in   => clint_mtip(' + hs + '),')
		lines.append("            -- M14: EXPLICIT strap -- the entity default (:= '1') does NOT survive")
		lines.append('            -- a netlist boundary: the hierarchical top flow elaborates hart_tile')
		lines.append('            -- as a VERILOG netlist (no port defaults), and the open pin was tied')
		lines.append('            -- LOW -> tiles had no CLINT slot enables and never woke on msip.')
		lines.append("            hw_clint_en => '1',")
		if h == 1:
			lines.append('            -- M7a: deglitched peripheral levels fan out to every tile; the')
			lines.append("            -- tile's row of the irq_router gates them (slots 83/84 are")
			lines.append('            -- overridden/hardwired inside the tile)')
		lines.append('            irq_ext    => irq_deglitch,')
		lines.append('            irq_en_ext => tile_irq_en_flat(' + str(h + 1) + '*NUM_IRQS-1 downto ' + hs + '*NUM_IRQS),')
		lines.append('            -- M17: outbound signals land on _raw and pass the iso clamps')
		lines.append('            sh_req    => tile' + hs + '_req_raw,')
		lines.append('            sh_we     => tile' + hs + '_we_raw,')
		lines.append('            sh_addr   => tile' + hs + '_addr_raw,')
		lines.append('            sh_wdata  => tile' + hs + '_wdata_raw,')
		lines.append('            sh_gnt    => arb_gnt(' + hs + '),')
		lines.append('            sh_done   => arb_done(' + hs + '),')
		lines.append('            sh_rdata  => arb_rdata,')
		lines.append('            sh_lrsc   => tile' + hs + '_lrsc_raw,')
		lines.append('            sh_scfail => arb_scfail(' + hs + '),')
		lines.append('            sh_lock   => tile' + hs + '_lock_raw,')
		lines.append("            -- M17: the tile's TCM macro is on the ALWAYS-ON rail but rides")
		lines.append('            -- its own native PGEN power-down whenever the domain gates ' + EMDASH)
		lines.append("            -- tcm_pgen is a straight wire to ram0's PGEN pin (was '0')")
		lines.append('            tcm_pgen  => pd_sleep(' + hs + '),')
		lines.append('            -- M17: MTCMOS domain controls (CPF hooks; see hart_tile.vhd)')
		lines.append('            pd_sleep  => pd_sleep(' + hs + '),')
		lines.append('            pd_iso_en => pd_iso_en(' + hs + '),')
		lines.append('            trap_flag => open,')
		lines.append('            a0        => a0_' + hs + '_raw')
		lines.append('        );')
		return lines

	def emitTileInstances(self):
		lines = []
		for h in range(1, self.nHarts()):
			if h > 1:
				lines.append('')
			lines.extend(self.tileInstance(h))
		return lines

	def busComment(self, instKey, spec):
		name = spec['periph']
		ind = ' ' * 12
		if spec['comment'] is None:
			return []
		if spec['comment'] == 'plain':
			return [ind + '-- Memory Bus (arbiter slave side, ' + MOVED_IN[name] + ')']
		p = self.periph(name)
		slot = self.winSlot(name)
		addr = '0x%05X' % p.BaseAddress
		if spec['comment'] == 'slot':
			return [ind + '-- Memory Bus (arbiter slave side, ' + MOVED_IN[name] + ' ' + EMDASH
				+ ' window slot ' + str(slot) + ' @' + addr + ')']
		if spec['comment'] == 'i2c':
			return [ind + '-- Memory Bus (arbiter slave side, ' + MOVED_IN[name] + ' ' + EMDASH
					+ ' window slot ' + str(slot) + ' @' + addr + ';',
				ind + '-- rdata_out is COMBINATIONAL, registered by i2c_rdata_bridge)']
		if spec['comment'] == 'npu':
			return [ind + '-- Memory Bus Signals (arbiter slave side, ' + MOVED_IN[name] + ' ' + EMDASH
					+ ' window slot ' + str(slot),
				ind + '-- @' + addr + '; MabMmrQ is COMBINATIONAL, registered by the bridge)']
		raise Exception('unknown bus comment kind ' + str(spec['comment']))

	def busPortValues(self, spec):
		'''Values for the generic port names, private vs shared.'''
		name = spec['periph']
		p = self.periph(name)
		shared = getattr(p, 'SharedBus', None) == 'periph'
		if shared:
			return {
				'clk_mem': 'mclk',
				'en': SHSLV[name]['shim'] + '_sh_en_n',
				'en_mem': SHSLV[name]['shim'] + '_sh_en_n',
				'wen': 'sh_wen_n',
				'addr_periph': 'sh_addr(5 downto 0)',
				'write_data': 'sh_wdata',
				'read_data': self.rdataSignal(name),
			}
		slot = self.slotName(name)
		return {
			'clk_mem': 'clk_periph(' + slot + ')',
			'en': 'mem_en_periph(' + slot + ')',
			'en_mem': 'mem_en_periph(' + slot + ')',
			'wen': 'wen_fe',
			'addr_periph': 'addr_periph',
			'write_data': 'write_data',
			'read_data': 'periph_dout(' + slot + ')',
		}

	def emitBus(self, instKey):
		spec = BUS_SPECS[instKey]
		name = spec['periph']
		ind = ' ' * 12
		lines = self.busComment(instKey, spec)
		if spec['comment'] == 'i2c':
			# I2C.vhd port names, tab-aligned like the RTL
			en = SHSLV[name]['shim'] + '_sh_en_n'
			lines.append(ind + 'ClkMem\t\t\t=> mclk,')
			lines.append(ind + 'EnMemPeriph\t\t=> ' + en + ',')
			lines.append(ind + 'WEn\t\t\t\t=> sh_wen_n,')
			lines.append(ind + 'MABPart\t\t\t=> sh_addr(5 downto 0),')
			lines.append(ind + 'wdata\t\t\t=> sh_wdata,')
			lines.append(ind + 'rdata_out\t\t=> ' + self.rdataSignal(name) + ',')
			return lines
		if spec['comment'] == 'npu':
			en = SHSLV[name]['shim'] + '_sh_en_n'
			lines.append(ind + 'MabMmrA'.ljust(12) + '=> sh_addr(1 downto 0),')
			lines.append(ind + 'MabMmrD'.ljust(12) + '=> sh_wdata,')
			lines.append(ind + 'MabMmrCLK'.ljust(12) + '=> mclk,')
			lines.append(ind + 'MabMmrCEN'.ljust(12) + '=> ' + en + ',')
			lines.append(ind + 'MabMmrWEN'.ljust(12) + '=> sh_wen_n,')
			lines.append(ind + 'MabMmrQ'.ljust(12) + '=> ' + self.rdataSignal(name) + ',')
			return lines
		values = self.busPortValues(spec)
		for i, port in enumerate(spec['ports']):
			line = ind + port.ljust(spec['width']) + '=> ' + values[port] + ','
			if spec['trailing'] is not None and spec['trailing'][i]:
				line += ' '
			lines.append(line)
		return lines

	# ------------------------------------------------------------------

	def emitRegion(self, name):
		if name == 'a0-ports':
			return self.emitA0Ports()
		if name == 'arb-fabric-decls':
			return self.emitArbFabricDecls()
		if name == 'clint-irq-decls':
			return self.emitClintIrqDecls()
		if name == 'tile-irq-en-flat-decl':
			return self.emitTileIrqEnFlatDecl()
		if name == 'pd-decls':
			return self.emitPdDecls()
		if name == 'tile-raw-decls':
			return self.emitTileRawDecls()
		if name == 'sh-master-decl':
			return self.emitShMasterDecl()
		if name == 'hart0-instance':
			return self.emitHart0Instance()
		if name == 'arb-generic':
			return self.emitArbGeneric()
		if name == 'resv-generic':
			return self.emitResvGeneric()
		if name == 'clint-instance':
			return self.emitClintInstance()
		if name == 'irq-router-instance':
			return self.emitIrqRouterInstance()
		if name == 'tile-rstn':
			return self.emitTileRstn()
		if name == 'iso-clamps':
			return self.emitIsoClamps()
		if name == 'tile-instances':
			return self.emitTileInstances()
		if name == 'irq-signal-decls':
			return self.emitIrqSignalDecls()
		if name == 'irq-comb':
			return self.emitIrqComb()
		if name == 'shslv-subdecode':
			return self.emitShslvSubdecode()
		if name == 'shslv-rd-sel':
			return self.emitShslvRdSel()
		if name == 'rdata-bridge':
			return self.emitRdataBridge()
		if name == 'sh-rdata-mux':
			return self.emitShRdataMux()
		if name == 'polarity-shims':
			return self.emitPolarityShims()
		if name.startswith('bus:'):
			instKey = name[len('bus:'):]
			if instKey not in BUS_SPECS:
				raise Exception('MCU.vhd emitter: no bus spec for instance "' + instKey + '"')
			return self.emitBus(instKey)
		raise Exception('MCU.vhd emitter: unknown region "' + name + '"')


def generateMcuVhd(gen, templatePath, outPath):
	'''Fill hdl_templates/MCU.template.vhd markers from the description; write outPath.'''
	emitter = McuVhdEmitter(gen)

	with open(templatePath, 'r', newline='') as f:
		templateLines = f.read().split('\n')

	header = []
	header.append('-- MCU.vhd')
	header.append('-- Castalia MCU top-level integration layer (' + str(emitter.nHarts()) + ' harts, MCU_MP)')
	header.append('-- Golden-master templated from the verified hdl/MCU_MP/MCU.vhd: the fixed')
	header.append('-- \tboilerplate comes from hdl_templates/MCU.template.vhd; the description-')
	header.append('-- \tdriven sections are generated from python/generate.py')
	header.append('-- Generated on ' + datetime.datetime.now().strftime('%Y/%m/%d at %H:%M:%S') + ' with the generate.py chip generator')
	header.append('-- WARNING: Do not edit or modify this file!')
	header.append('-- \tEdit hdl_templates/MCU.template.vhd (fixed regions) or python/generate.py')
	header.append('-- \t+ python/mcu_vhd.py (generated regions), then re-run make chip')
	header.append('')

	out = list(header)
	marker = re.compile(r'^\s*--@GEN:([A-Za-z0-9:_-]+)@\s*$')
	seen = set()
	for line in templateLines:
		m = marker.match(line)
		if m is None:
			out.append(line)
			continue
		name = m.group(1)
		if name in seen:
			raise Exception('MCU.vhd emitter: duplicate region marker "' + name + '" in template')
		seen.add(name)
		out.extend(emitter.emitRegion(name))

	expected = set(['irq-signal-decls', 'irq-comb', 'shslv-subdecode', 'shslv-rd-sel', 'rdata-bridge',
		'sh-rdata-mux', 'polarity-shims',
		# A1 N-hart regions
		'a0-ports', 'arb-fabric-decls', 'clint-irq-decls', 'tile-irq-en-flat-decl', 'pd-decls',
		'tile-raw-decls', 'sh-master-decl', 'hart0-instance', 'arb-generic', 'resv-generic',
		'clint-instance', 'irq-router-instance', 'tile-rstn', 'iso-clamps', 'tile-instances']
		+ ['bus:' + k for k in BUS_SPECS])
	if seen != expected:
		raise Exception('MCU.vhd emitter: template regions ' + str(sorted(seen))
			+ ' do not match the expected set ' + str(sorted(expected)))

	with open(outPath, 'w', newline='\n') as f:
		f.write('\n'.join(out))

	print('VHDL MCU top-level saved to ' + outPath)
	return
