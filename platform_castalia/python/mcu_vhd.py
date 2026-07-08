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
EN_ORDER = ['rom', 'npuram', 'bank0', 'bank1', 'bank2', 'bank3', 'CLINT', 'MUTEX', 'IRQROUTER'] + PG0_SEL_ORDER
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
		slots = [self.winSlot(n) for n in PG0_SEL_ORDER]
		if len(set(slots)) != len(slots) or any(s < 0 or s > 15 for s in slots):
			raise Exception('MCU.vhd emitter: PG0_SEL_ORDER slots must be unique and within 0..15 (reserved gaps allowed)')
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
	header.append('-- Castalia MCU top-level integration layer (4 harts, MCU_MP)')
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
		'sh-rdata-mux', 'polarity-shims'] + ['bus:' + k for k in BUS_SPECS])
	if seen != expected:
		raise Exception('MCU.vhd emitter: template regions ' + str(sorted(seen))
			+ ' do not match the expected set ' + str(sorted(expected)))

	with open(outPath, 'w', newline='\n') as f:
		f.write('\n'.join(out))

	print('VHDL MCU top-level saved to ' + outPath)
	return
