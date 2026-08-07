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
_PACKAGE_MODELS = ('myshkin-qfn44', 'castalia-quad-qfn64', 'castalia-lqfp100')

_CONFIG_SCHEMA = {
	'chipName':             ('non-empty string — renames the chip in the TRM/headers (docs-only; CHIP_NAME env still wins)',
	                         lambda v: isinstance(v, str) and len(v.strip()) > 0),
	'numHarts':             ('int 1..32 — hart/tile count (4 = Castalia golden master, 18 = Argus sim-proven)',
	                         lambda v: _isInt(v) and 1 <= v <= 32),
	'numMutexes':           ('int 1..1024 — HW mutex bank size (16 = Castalia, 32 = Argus)',
	                         lambda v: _isInt(v) and 1 <= v <= 1024),
	'registerFileDualPort': ('bool — docs-only on vesta (regfile is dual-port in the RTL regardless; only the legacy picorv32_* MemoryMap constant changes)',
	                         _isBool),
	'isa.mul':              ('bool — M multiply', _isBool),
	'isa.fastMul':          ('bool — docs-only on vesta (multiplier is already single-cycle)', _isBool),
	'isa.div':              ('bool — M divide', _isBool),
	'isa.atomics':          ('bool — A extension (LR/SC + AMO)', _isBool),
	'isa.compressed':       ('bool — C extension', _isBool),
	'isa.bitmanip':         ('bool — Zba/Zbb/Zbs/Zbc', _isBool),
	'isa.counters':         ('bool — Zicntr mcycle/minstret; docs/march-only on vesta (cycle/instret and their high halves are always present — this gates only the _zicntr march suffix and the legacy constants). NOTE the march suffix over-promises since DD11-N1: time/timeh (0xC01/0xC81) are NOT implemented in any build and a read of either raises illegal-instruction, because no real time source is wired to the core', _isBool),
	'isa.counters64':       ('bool — 64-bit counter high halves (needs isa.counters); docs-only on vesta (the high halves are always present)', _isBool),
	# ISA extensions. X1 (2026-07-17) implemented the six Tier-1 knobs below
	# (zicond zcb zimop zihint zihpm zawrs) — default false, decode + tests +
	# both-polarity gates landed. X2 (zabha zacas), X3 (zicboz zcmp zcmt zbkb
	# zbkc zbkx zkn) and X4 (zfinx, 2026-07-18) implemented the rest: every
	# isa.* knob below is real hardware and the X0 scaffolding hard-error
	# list (_SCAFFOLDED_ISA) is empty — no knob advertises hardware it lacks.
	'isa.zicond':           ('bool — Zicond conditional-zero ops (czero.eqz/czero.nez)', _isBool),
	'isa.zcb':              ('bool — Zcb extra compressed insns (c.lbu/lhu/lh/sb/sh, zext/sext, c.not, c.mul; needs isa.compressed)', _isBool),
	'isa.zimop':            ('bool — Zimop+Zcmop may-be-ops (mop.r/mop.rr rd<-0, c.mop.n nops)', _isBool),
	'isa.zihint':           ('bool — Zihintpause+Zihintntl (PAUSE = 16-cycle arbiter-yield window; ntl.* nops)', _isBool),
	'isa.zihpm':            ('bool — Zihpm perf counters 3/4 (events: arbiter-stall, bus-grants, sleep, trap-entry)', _isBool),
	'isa.zawrs':            ('bool — Zawrs wrs.nto/wrs.sto wait-on-reservation-set (needs isa.atomics)', _isBool),
	'isa.zabha':            ('bool — Zabha byte/half AMOs (requires atomics). Implemented X2.', _isBool),
	'isa.zacas':            ('bool — Zacas amocas.w/.b/.h compare-and-swap (requires atomics; .b/.h also need zabha). Implemented X2.', _isBool),
	'isa.zicboz':           ('bool — Zicboz cbo.zero cache-block zero (64-byte block). Implemented X3.', _isBool),
	'isa.zcmp':             ('bool — Zcmp compressed push/pop + reg-moves (requires isa.compressed). Implemented X3.', _isBool),
	'isa.zcmt':             ('bool — Zcmt compressed table jump + jvt CSR (requires isa.compressed). Implemented X3.', _isBool),
	'isa.zbkb':             ('bool — Zbkb crypto bit-manip (pack/packh/brev8/zip/unzip + Zbb-shared subset). Implemented X3.', _isBool),
	'isa.zbkc':             ('bool — Zbkc carryless multiply (clmul/clmulh; reuses the Zbc datapath). Implemented X3.', _isBool),
	'isa.zbkx':             ('bool — Zbkx crossbar permute (xperm8/xperm4). Implemented X3.', _isBool),
	'isa.zkn':              ('bool — Zkn AES+SHA (Zknd+Zkne+Zknh). Implemented X3.', _isBool),
	'isa.zfinx':            ('bool — Zfinx single-precision FP in x-regs (shared FMA-based backend, exactly one rounding, all 5 rounding modes, full subnormals; radix-2 iterative div/sqrt; fcvt family). Implemented X4 — the largest single extension (0.034 mm² of tile area).', _isBool),
	# P-series PRIVILEGED ARCHITECTURE. The generics ride the full chain
	# (generate.py -> ChipGenerator -> mcu_vhd -> MemoryMap CORE_* ->
	# hart_tile -> vesta -> maindec/csr_unit). ALL THREE HAVE GRADUATED:
	# 'trapCsr' at P1 and 'umode' at P2 (2026-07-28), 'pmp' at P3
	# (2026-07-29) -- _SCAFFOLDED_PRIV below is now EMPTY, so none of them
	# hard-errors any more. The dependency validations (umode => trapCsr,
	# pmp => umode) stay LIVE and are the only gate left.
	'priv.trapCsr':         ('bool — P1: standard M-mode trap architecture, IMPLEMENTED in full (P1, 2026-07-28): the CSR file (mstatus/mstatush/mtvec/mie/mip/mscratch/mepc/mcause/mtval + the custom mtrapctl @0x7C0 legacy-select bit) AND standard delivery — MRET/ECALL/EBREAK decode, mtvec-vectored exceptions and interrupts (MEI>MSI>MTI), the mstatus MPIE/MIE stack. mtrapctl.LEGACY resets 1, so even an ON chip boots on the legacy irq_handler/IVT path and is suite-identical until software clears the bit. DEFAULT TRUE since K7/R-DK3 (2026-08-04) on both Castalia and Argus: the CSR file and standard delivery are present, boot is bit-identical, and a hart enters standard delivery only when its own firmware writes mtrapctl (csrw 0x7C0, x0). Cost, measured at K6: +144 flops per tile (genus sequential 2251 -> 2395), +3.85% standard-cell area, +1.29% tile area, timing neutral. Set false to get a pre-P1 chip back: all ten addresses and the three encodings stay illegal. HAZARD any firmware policy must respect: clearing LEGACY on a hart that then EXTINGUISHes makes it unwakeable (the legacy IVT slot-83 msip path is what the bootrom park/wake contract uses) -- per-hart only, never before park', _isBool),
	'debug.enable':         ('bool — D1: CORE-SIDE DEBUG MODE (2026-08-05). Debug mode as a privilege state: the Debug-Mode CSRs dcsr/dpc/dscratch0/dscratch1 (0x7B0-0x7B3, accessible ONLY in debug mode -- from M or U they raise illegal-instruction), the DRET encoding, an unmaskable halt request sampled at the same fourteen FSM points an interrupt is (including the terminal TRAP_STATE, so a debugger can rescue a wedged hart), halt-on-reset, ebreak-to-debug under dcsr.ebreakm, and single-step. Debug entry vectors to DEBUG_ENTRY_ADDR, which is the SHARED-WINDOW debug program page 0x00010780 on every debug-ON build (R-DD3/R-D2-1(3): a tile\'s TCM is unreachable from the shared bus, so a Debug Module could never place code at the old TCM default 0xBE00 -- that address survives only as the VHDL generic\'s fail-safe declaration default). REQUIRES priv.trapCsr: ebreak and the whole SYSTEM PRIV decode arm are trapCsr-gated, so a debug-without-trapCsr chip could not recognise a software breakpoint at all. Default false: the four CSR addresses and the DRET encoding stay illegal, the three tile debug ports fold away, and the core is bit-identical to a chip built before D1. THE KNOB NOW CARRIES THE WHOLE TRANSPORT. D2 added the assembly-level Debug Module dm0 (run control, dmstatus truth-telling against PWRCTRL, abstract access-register commands, a 2-word program buffer, halt groups, hartsel/haltsum at N=4 AND N=18) with its eight dmi_* MCU ports; D3 added the JTAG DTM dtm0 (16-state TAP, 5-bit IR, IDCODE/dtmcs/dmi(41)/BYPASS, the TCK<->mclk crossing) with the five pins tck/tms/tdi/tdo/trstn, and merged it with the dmi_* ports by valid-gated OR so both masters reach the one DM. D4 LANDED 2026-08-07 AND THERE IS NO DEBUG ROM: R-DD5 took option B, so dm0 PLANTS the 40-word entry code itself, out of a constant table, through the master port it already owned -- once at every dmactive 0->1, and again before it consumes a newly-halted hart\'s token. A ROM was rejected on STRUCTURE, not cost: 24 of the entry page\'s 64 words are DM-written at runtime and must stay writable, so read-only memory there would break the Debug Module outright. The table is held equal to the built software/dbg_trampoline/dbg_trampoline.S by tools/cosim/check_dbg_trampoline.py, a standing gate (rc 0 equal / 1 mismatch / 2 missing -- never a silent skip). The page is self-repairing for every word but the FIRST (F-D4-1: a hart that halts into a wrong word 0 re-asks for that same word and hart_tile\'s same-word ack hold keeps re-serving the stale copy, so it wedges until a PWRCTRL tile power-cycle). STILL OUT OF SCOPE and arriving later in the D-series: OpenOCD/gdb bring-up (D5) and hardware triggers (D6). System Bus Access is out FOREVER by design -- memory access is progbuf lw/sw through the halted hart. Cost, measured: +742 flops on the Castalia assembly at D2 (452 core + 265 dm0 + 25 fabric), plus dtm0 at D3, plus 4 for the D4 plant (assembly 18,159 -> 18,163)', _isBool),
	'priv.umode':           ('bool — P2: user mode, IMPLEMENTED in full (P2, 2026-07-28): the 1-bit privilege register (reset M) with the MPP push/pop riding trap entry and MRET, mstatus.MPP WARL widened to {00,11} (unsupported 01/10 map to M), mstatus.TW, a real mcounteren (CY/TM/IR/HPM3/HPM4), misa.U, ECALL-from-U cause 8, the standard WFI encoding with its wake-on-(mip&mie) rule, and the U-mode decode gate — every machine/custom CSR (csr_addr(9:8)/="00"), MRET, the three custom Vesta instructions and a TW-denied WFI trap illegal-instruction, and a denied CSR access commits no write. Requires priv.trapCsr. Default false: no privilege register, misa.U clear, MPP WARL {11}, mcounteren read-zero — bit-identical to a P1 chip', _isBool),
	'priv.pmp':             ('bool — P3: physical memory protection (Smpmp), IMPLEMENTED (P3, 2026-07-29): the pmpcfg0-3 / pmpaddr0-15 CSR bank (packed 4x8-bit cfg, R/W/X/A(4:3)/L with bits 6:5 WARL 0, W pinned 0 when R=0, pmpaddr bits 31:30 WARL 0), the full lock semantics (a locked entry\'s cfg AND address are immutable until reset, a TOR-locked entry also write-locks its predecessor address, per-byte lock filtering inside a pmpcfg word), and the combinational match unit (OFF/TOR/NA4/NAPOT at G=0, lowest-numbered match decides alone, locked entries enforce on M-mode, no-match grants M and faults U). The pre-issue fetch/load/store CHECK INTEGRATION with its access-fault causes 1/5/7 lands with the vesta diff of the same phase. Requires priv.umode. Default false: all twenty addresses stay illegal CSRs and the match unit is not instantiated — bit-identical to a P2 chip', _isBool),
	'priv.pmpEntries':      ('int — PMP entry count, {8, 16} ONLY (the PMP_ENTRIES generic). Consulted only when priv.pmp is true; the CSR map is the 16-entry superset regardless (entries above the count are WARL all-zero). Default 16',
	                         lambda v: _isInt(v) and v in (8, 16)),
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
	'peripherals.cqAfeStubs': ('bool — True instantiates the four AFE register stubs (page-0 slot 12 @0x4C00, sub-slots on sh_addr(5:4)) and the shared EIS engine stub (0x7C00); the Castalia golden master keeps them. False frees slot 12 for a native peripheral (mutually exclusive with peripherals.qspi) and reserves IRQ vectors 55/56',
	                         _isBool),
	'peripherals.qspi':     ('bool — True instantiates the QSPI0 controller in page-0 slot 12 (0x4C00), driving IRQ vectors 55 (transfer-complete) and 56 (RX-full); requires peripherals.cqAfeStubs=false (both claim slot 12). Default false',
	                         _isBool),
	'peripherals.i3c':      ('bool — True instantiates the I3C0 controller (MVP+DAA+IBI) at 0x6100: page-2 (MUTEX page) sub-slot 1. Tightens the mutex-bank decode to its 256 B sub-slot 0 (retiring the page-wide alias whose reads had a CLAIM side effect), adds a page-2 sub-decode, and GROWS the IRQ source list to 94 (a reserved placeholder at the frozen meip slot 85, then I3C vectors 86-93: tc/rxf/txe/nack/eod/arb/daa/ibi). Default false',
	                         _isBool),
	'peripherals.nfc':      ('bool — True instantiates the NFC0 ISO 14443A tag / card-emulation engine at 0x6200: page-2 (MUTEX page) sub-slot 2. Like I3C it tightens the mutex-bank decode to its 256 B sub-slot 0 (retiring the aliased-CLAIM side effect) and adds the page-2 sub-decode. GROWS the IRQ source list to 98 (meip stays frozen at slot 85; sources 86-93 are I3C or reserved; NFC drives vectors 94-97: field/rxf/txdone/crcerr). The digital AFE / RF interface is off-die (placeholder-tied). Default false',
	                         _isBool),
	'peripherals.rtc':      ('bool — True instantiates the RTC0 real-time clock (32.768 kHz always-on wall clock + one-shot alarm + periodic tick) at 0x6500: page-2 (MUTEX page) sub-slot 5. Zero pins; clocks off the UNGATED lfxt_in pad crystal, with the CDC synchronizers / sticky W1C flags / IRQ combiner on the free-running MCLK. GROWS the IRQ source list to 115: vector 114 = RTC0 (single combined alarm/tick IRQ, above GPIO5\'s 106-113). NUM_EN_WORDS stays 4 (115 <= 128). Default false',
	                         _isBool),
	'peripherals.pwm':      ('bool — True instantiates the PWM0 buffered PWM generator (2 channels, glitch-free double-buffered update, software fault trip, period-event tick) at 0x6600: page-2 (MUTEX page) sub-slot 6. Zero input pins; the two outputs pwm_out(0)/(1) REPLACE two redundant timer-compare spread copies (P2.2/P2.3 AF2, the pin-mux-v2 replaced-spread-slot precedent). Free-running MCLK engine (no LFXT, no generated clocks). GROWS the IRQ source list per the GLOBAL VECTOR RULE (A5): vectors 115 = PWM0_FAULT (lower id = router priority), 116 = PWM0_EVT; when a lower library block (RTC vector 114) is off but pwm is on, 114 backfills as IRQB_RSVD114. NUM_EN_WORDS stays 4 (117 <= 128). Default false',
	                         _isBool),
	'peripherals.onewire':  ('bool — True instantiates the OW0 Dallas/Maxim 1-Wire master (reset+presence, write/read bit + byte link-layer primitives off a programmable time base; ROM search + CRC-8 in firmware; standard + overdrive; one open-drain DQ pin) at 0x6700: page-2 (MUTEX page) sub-slot 7. One pad: DQ on P4.7 / GPIO31 (DTP3), alt plane AF2, open-drain, rstREN=1 — the pin-mux-v2 REPLACED-SPREAD-SLOT mechanism (it takes over the redundant T0CMP1 output-spread copy in that slot; T0CMP1 keeps its P3.1/GPIO17 AF0 primary, its P2.1/P4.5 AF1 relocations and 26 other spread copies, so the replacement is pure redundancy). Free-running MCLK engine (no LFXT, no generated clocks, no clock on the DQ pad — DQ is 2-FF synchronized). EXTENDS the IRQ source list per the GLOBAL VECTOR RULE (A5) to 118: vector 117 = OW0 (single combined transaction-complete/error IRQ); when a lower library block (RTC 114, PWM 115/116) is off but onewire is on, those slots backfill as IRQB_RSVD. NUM_EN_WORDS stays 4 (118 <= 128). Default false',
	                         _isBool),
	'peripherals.fieldPower': ('bool — True wires the DP-S3 field-powered-mode supervision inputs into PWRCTRL: P6.7/GPIO47 = PGOOD supply-supervisor input, P6.6/GPIO46 = harvested-boot strap. Both are plain-GPIO DIRECT TAPS of the pad-input plane (always readable, independent of PxSEL/PxAFS — PGOOD must gate boot before any software can program a mux), with reset attrs rstDIR=input, rstREN=1, pull-DOWN: unconnected reads power-not-good + NORMAL(SPI) boot. Also taps NFC0\'s field_detect level as an optional PWRCTRL wake/release source (tied 0 when NFC is absent). The PWRCTRL PWRWAKE/PWRSTS registers and the pgood_rstn HOLD-IN-RESET boot gate exist in the RTL unconditionally; this knob only controls the pad-side ties, so False leaves the feature a provable NO-OP (gate stuck released). Default true (the Castalia golden master and castalia_dp carry the live wiring)',
	                         _isBool),
	'peripherals.dma':      ('bool — True instantiates the DMA0 configurable multi-channel single-shot DMA controller (peripheral-paced or software-GO mem-to-mem transfers, CRC16 ride-along) at 0x6800: page-2 (MUTEX page) sub-slot 8. Zero pins. DMA0 is the FIRST new arbiter MASTER since the four harts (M13): enabling it WIDENS the shared fabric from N=4 to N=5 masters (the DMA is master index numHarts, the last slice) — mp_arbiter N=>5/MW=>3, resv_unit N=>5, mutex_bank/irq_router MW=>3, sh_master 2->3 bits, arb_* buses grow a 5th slice. EXTENDS the IRQ source list per the GLOBAL VECTOR RULE (A5) to 119: vectors 118 = DMA0_DONE (combined channels-done), 119 = DMA0_ERR; when a lower library block (RTC 114, PWM 115/116, OW 117) is off but dma is on, those slots backfill as IRQB_RSVD. NUM_EN_WORDS stays 4 (119 <= 128). Default false',
	                         _isBool),
	'peripherals.dmaChannels': ('int — DMA0 channel count, {2, 4} ONLY (the NCH generic; the register map is the 4-channel superset regardless, absent channels read 0). Consulted only when peripherals.dma is true. Default 4',
	                         lambda v: _isInt(v) and v in (2, 4)),
	'peripherals.i2ctarget': ('bool — True instantiates the I2CT0 hardware-autonomous I2C TARGET (slave) at 0x6A00: page-2 (MUTEX page) sub-slot 10. 7-bit address match + mask + general call, byte-at-a-time RX/TX with ready/empty status, hardware clock stretching, START/STOP/repeated-START/NACK framing flags, and a stuck-SCL watchdog — all in the free-running MCLK domain (D4-clean, 2-FF SDA/SCL sync, no pad-clocked processes). Two combined IRQs delivered per the GLOBAL VECTOR RULE (A5): vector 122 = I2CT0_AE (address/error), 123 = I2CT0_DATA (tx-ready/rx-full); vectors 120/121 belong to the DP-SG blocks (120 = NPU0 think-done, 121 = TRNG0 — landed 2026-07-22; each backfills as IRQB_RSVD when its block is absent), so 122/123 hold under the frozen-numbering rule. NUM_EN_WORDS stays 4 (124 <= 128). NO new pins: I2CT0 SHARES the I2C0 SDA0/SCL0 pad planes via an open-drain wired-AND DIR merge (a separate shared-RTL edit). mclk-domain, so the SYS_CLK_CR=0 footgun does NOT bind I2CT0 (unlike the smclk I2C0). Default false',
	                         _isBool),
	'peripherals.trng':      ('bool — True instantiates the TRNG0 ring-oscillator entropy source + harvest engine at 0x6900: page-2 (MUTEX page) sub-slot 9. Free-running RO ensemble (NRO rings, {4,8} via peripherals.trngRings) 2-FF synchronized into MCLK, decimated/packed into 32-bit words with a read-CONSUMES data register (exactly-once consume + DRDY same-cycle blind-window fix), and an SP 800-90B-lite repetition-count health test whose alarm auto-halts harvesting — all in the free-running MCLK domain (D4-clean, plain raw-strobe active-low shim, neither combinationalRead nor CAPTURE_CLOCK). ONE combined IRQ (data-ready | health-alarm) delivered per the GLOBAL VECTOR RULE (A5): vector 121 = TRNG0; vector 120 (npu-thinkdone) is gated by the EXISTING peripherals.npu knob. NUM_EN_WORDS stays 4 (ceil(122/32) = 4, 122 <= 128 when TRNG is the highest enabled tail block). Zero pins — the RO ensemble is internal combinational fabric behind a SIM/REAL architecture split (TrngRoEnsemble_sim.vhd behavioral-only, TrngRoEnsemble.vhd genus/gate-only; the two must never co-list). ENTROPY CAVEAT (bring-up-grade, not certified — see the TRM chapter): firmware MUST DRBG the raw words and honor ALMF. Default false — the default emission (no page-2 sub-slot 9, no MmrAddrTRNG0, no vector 121) is byte-identical',
	                         _isBool),
	'peripherals.trngRings': ('int — TRNG0 ring-oscillator ensemble size, {4, 8} ONLY (the NRO generic; the register map is NRO-invariant — ROSEL/RCTC/RUNLEN semantics are unchanged by the knob). Consulted only when peripherals.trng is true. Default 8',
	                         lambda v: _isInt(v) and v in (4, 8)),
	'peripherals.eventFabric': ('bool — True instantiates the EVFAB0 event/trigger fabric (PPI-style crossbar) at 0x6B00: page-2 (MUTEX page) sub-slot 11. 8 channels, each a {EVSEL, TASKSEL} pair, route one of 16 hardware EVENTS to one of 10 hardware TASKS with a registered one-MCLK pulse and 1 MCLK of in-fabric latency, so peripheral-to-peripheral chains run with every hart asleep. Producers are pre-mask SET-condition taps on RTC0/PWM0/TIMER0/TIMER1/UART0/NFC0/DMA0/TRNG0/I2CT0 plus a GPIO0 masked-edge path (the fabric owns all CDC: per-input pulse/toggle/level modes via the EV_MODE_TGL/EV_MODE_LVL generic masks); consumers are DMA0 channel GO, TIMER0 START/STOP, PWM0 fault trip, PWRCTRL tile wake, NPU0 THINK and GPIO0 OUT-SET/OUT-CLR (the PxTASK pin-select byte). Every producer/consumer whose block is absent from the configuration is TIED OFF ("0") rather than left open (design-doc D23) — the knob composes with every other peripheral knob. VECTORLESS v1: no IRQ vector is spent (irq_evfab is a constant "0", the IE slot is reserved), so NUM_IRQ_SRCS is untouched and the frozen vector numbering is undisturbed. Zero pins. Free-running MCLK in the always-on shared domain (WFI keeps it alive, DP-S3 field-power only slows it, PWRCTRL never gates it). Default false — the default emission (no page-2 sub-slot 11, no EVF* register block, no tap port maps) is byte-identical',
	                         _isBool),
	'package.model':        ('string — package model name defined in generate.py (_PACKAGE_MODELS: "myshkin-qfn44" QFN-44, "castalia-quad-qfn64" QFN-64 quad pinout, "castalia-lqfp100" LQFP-100 single-MCU large package [Stage G2, 2026-07-22: all 48 GPIO bonded] — new pinouts are added as Python models, never as free-form config pin lists)',
	                         lambda v: isinstance(v, str) and v in _PACKAGE_MODELS),
	'package.preliminary':  ('bool — True prints the TRM package-section "Preliminary" note (default True while the package is inherited from Myshkin unchanged)',
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
	'numHarts':             {'type': 'int', 'default': 4, 'min': 1, 'max': 32},
	'numMutexes':           {'type': 'int', 'default': 16, 'min': 1, 'max': 1024},
	'registerFileDualPort': {'type': 'bool', 'default': True},
	'isa.mul':              {'type': 'bool', 'default': True},
	'isa.fastMul':          {'type': 'bool', 'default': True},
	'isa.div':              {'type': 'bool', 'default': True},
	'isa.atomics':          {'type': 'bool', 'default': True},
	'isa.compressed':       {'type': 'bool', 'default': True},
	'isa.bitmanip':         {'type': 'bool', 'default': True},
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
	# D-series core-side debug (D1, 2026-08-05). Default FALSE -- the whole
	# programme's inertness claim is that a knob-OFF build is bit-identical to
	# a pre-D1 chip. NOTE, as above: this literal is the SCHEMA default; the
	# OPERATIVE one is the _cfg() fallback in _debug below, and
	# check_config_defaults.py is what keeps the two in step.
	'debug.enable':         {'type': 'bool', 'default': False},
	'memory.romSize':            {'type': 'int', 'default': 16384, 'min': 0x400, 'max': 0x4000, 'step': 0x400},
	'memory.tcmSizePerHart':     {'type': 'int', 'default': 16384, 'min': 0x400, 'max': 0x4000, 'step': 0x400},
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
	'peripherals.nfc':      {'type': 'bool', 'default': False},
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
	'package.model':        {'type': 'enum', 'default': 'myshkin-qfn44', 'enum': list(_PACKAGE_MODELS)},
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
numHarts = _cfg('numHarts', 4)

# Mutex count (A2/Argus: 32 for the 18-hart course chip, 16 = the Castalia
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
nfcPresent = _cfg('peripherals.nfc', False)

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

# ===========================================================================
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
	# See ~/vesta_docs/digperiphs/irq_budget_phase0.md §1.
	('npu_thinkdone', npuPresent, 1),  # vector 120  (NPU0 think-done, DP-SG Part A)
	('trng', trngPresent, 1),          # vector 121  (TRNG0 combined data-ready/alarm)
	('i2ctarget', i2ctargetPresent, 2),  # vectors 122, 123  (I2CT0_AE, I2CT0_DATA)
]
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
# ===========================================================================

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
	'enable': _cfg('debug.enable', False),
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
# CONSEQUENCE, verified rather than assumed: config/castalia_notrapcsr.json --
# the 28th matrix row and the ONLY one exercising the trapCsr-OFF RTL arm --
# names no `debug` key, so it takes this default (false) and is a debug-OFF row
# by construction. It does not need editing and must not be given a debug key.
if _debug['enable'] and not _priv['trapCsr']:
	raise Exception('debug.enable requires priv.trapCsr (ebreak and the SYSTEM PRIV decode arm do not exist without it, so a software breakpoint could never be recognised)')

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
flashBase = 1 << (shAw + 2)
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
r = RegisterTemplate(nameTemplate='BLOCKPWR', registerMemorySlot=2, description='Block power control register. Controls power gating for on-chip memory blocks. All bits reset to 0 (every block powered). DP-S3: bits 6:3 gate the four low shared bulk-RAM banks individually; a gated bank LOSES ITS CONTENTS (no retention) and stops responding — software must keep the bank holding its stack, mailboxes, or live payload powered, and must treat a re-powered bank as uninitialized (the boot-ROM zero-fill contract is write-before-read anyway). In configurations with more than four banks, banks 4 and up are hardwired always-on.', size=8)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(unused=True, msb=7, lsb=7))
for _b in range(3, -1, -1):
	r.AddBitField(BitField(name='SYSSHB' + str(_b) + 'OFF', msb=3 + _b, description='Shared bulk-RAM bank ' + str(_b) + ' (0x' + format(0x10000 + _b * 0x4000, 'X') + '-0x' + format(0x10000 + _b * 0x4000 + 0x3FFF, 'X') + ') power control. When set, the bank is powered off: contents are LOST and accesses no longer respond. Reduces static power (a gated sram1p16k halves its leakage).', accessibility='rw', valueDescriptions=[(0b0, 'Bank ' + str(_b) + ' powered on'), (0b1, 'Bank ' + str(_b) + ' powered off (contents lost)')]))
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
r = RegisterTemplate(nameTemplate='WDTPASS', registerMemorySlot=12, size=32, description='Watchdog timer password register. Write-only register for two security functions: (1) Write ' + _wdtUnlockHex + ' to unlock WDTCR for 64 MCLK cycles, enabling writes to watchdog configuration. (2) Write ' + _wdtClearHex + ' to clear watchdog counter to 0, preventing timeout. Reading always returns 0.')
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='SYSWDTPASS', msb=31, lsb=0, accessibility='w', description='Watchdog password. Write ' + _wdtUnlockHex + ' (unlock password) to enable WDTCR writes for 64 MCLK cycles. Write ' + _wdtClearHex + ' (clear password) to reset watchdog counter to 0.'))

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

# PxTASK (digperiphs EVFAB: the event-fabric task pin-select byte, GPIO.vhd slot 12).
# The register exists in EVERY GPIO instance unconditionally (it is plain RTL state,
# writable and readable whatever the peripherals.eventFabric knob says); only its
# EFFECT needs the fabric, because task_outset/task_outclr are tied '0' in a cut with
# no EVFAB0. NOTE: GPIO.vhd also declares a LOCAL `constant RegSlotPxTASK : natural
# := 12` — it must stay, because the peripheral-test suite compiles GPIO.vhd against
# the FROZEN hdl/myshkin/MemoryMap.vhd, which will never carry this constant. The
# local declaration legally hides the (identically valued) package one in the cuts
# that use the generated package.
r = RegisterTemplate(nameTemplate='PxTASK', registerMemorySlot=12, description='GPIO event-fabric task pin-select register. Each bit corresponds to the GPIO pin of the same number and selects whether that pin participates in the EVFAB0 event-fabric output tasks: when the fabric fires the port\'s OUT-SET task, every pin whose PxTASK bit is 1 has its PxOUT bit set; when it fires the OUT-CLR task, every selected pin has its PxOUT bit cleared. The two task pulses are applied AFTER the CPU register write in the same cycle (a task wins its own pins against a coincident PxOUT write) and CLR is applied after SET (a same-cycle set+clear on an overlapping pin resolves to CLEAR, the safe direction). A toggle task is deliberately not offered. Resets to 0, so no pin is fabric-driven out of reset. In a configuration WITHOUT the event fabric (peripherals.eventFabric false) the register is still readable and writable but has no effect, because both task inputs are tied inactive. Only the port\'s implemented pins have bits; the rest read 0.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='PxTASK', msb=31, lsb=0, accessibility='rw'))

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
p = PeripheralTemplate(nameTemplate='I2Cx', description=i2cDescription, registerPrefix='I2Cx', bitFieldPrefix='I2C', latexIntroFileName='I2C-intro-castalia-2026-07.tex', latexFeatureSummary='{count} I$^2$C interfaces (both master and slave mode)')
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
p = PeripheralTemplate(nameTemplate='NPU', description='Fixed-point multilayer perceptron (MLP) neural network processing unit. Computes a single fully-connected layer of a neural network: given an input vector and a synaptic weight matrix, it produces an output vector. Multiple layers can be computed sequentially by the CPU. Inputs are signed Q0.24 numbers (25 bits); synaptic weights and outputs are signed Q7.24 numbers (32 bits). An optional bias weight and a logistic sigmoid approximation activation function are available. The input vector, output vector, and weight matrix must all reside in the shared NPU staging RAM (the 16 KiB SRAM at 0xC000-0xFFFF, multiplexed between the harts and the NPU compute port). Both the registers and the data path are reachable by every hart through the shared window: any hart may stage the operands in the staging RAM. No hart is put to sleep during a computation; while THINK is set the staging RAM is owned by the NPU, so no hart may access 0xC000-0xFFFF until NPUCR bit 16 (NPUTHINK) reads 0 again.', registerPrefix='NPU', bitFieldPrefix='NPU', latexIntroFileName='NPU-intro-castalia-2026-07.tex', latexFeatureSummary='A neural processing unit (NPU) co-processor for hardware acceleration of machine learning tasks')
# A2 (Argus): the template is only registered when the NPU exists — an
# unregistered template emits no MemoryMap.h structs and no TRM chapter
# (same end state as the removed AFE/SARADC blocks).
if npuPresent:
	m.AddPeripheralTemplate(p)

# NPUCR
r = RegisterTemplate(nameTemplate='NPUCR', registerMemorySlot=0, description='NPU control register', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=26, unused=True))
r.AddBitField(BitField(name='NPUACTF', msb=25, lsb=23, description='Post-accumulator activation function select, effective when NPUAEN = 1 (P4 architecture family; NPUAEN = 0 is always raw passthrough regardless of this field). 0 = logistic sigmoid approximation (the legacy activation; reset default), output Q0.24 in [0,1). 1 = ReLU (max(0, x)), output Q7.24 -- note a ReLU output at or above 1.0 is not a valid Q0.24 next-layer input. 2 = tanh approximation computed as 2*sigmoid(2x)-1 through the same sigmoid hardware, output in [-1,1) sign-extended (the low 25 bits are a valid Q0.24 next-layer input); saturates for |x| >= 2. 3 = clamp (hardtanh): the identity saturated to the Q0.24 rails [-1, 1), sign-extended. 4 = exponential approximation 2*sigmoid(x), output Q1.24 in [0,2), for the softmax leg -- hardware emits per-element scores only, firmware performs the sum and normalize (subtracting the maximum logit first is recommended, mapping the maximum to exactly 1.0). Codes 5-7 are reserved and behave as 0 (sigmoid). The selection is latched when THINK is set; a mid-THINK write takes effect at the next THINK.', accessibility='rw'))
r.AddBitField(BitField(name='NPUMODE', msb=22, lsb=20, description='Datapath mode select for the NPU architecture family (P4). 0 = multilayer-perceptron mode (the legacy datapath; reset default). 1 = one-dimensional convolution mode. 2 = XNOR-popcount binary mode (1-bit activations/weights packed 32 per word, LSB-first; NPUBEN and NPUAEN must be 0 in this mode). 3 = general matrix-multiply (GEMM) mode: C = A x B with A (M x K, row-major at NPUIVSAR, Q0.24 elements in [-1,1)), B (K x N, column-major at NPUWVSAR, Q7.24), C (M x N, row-major at NPUOVSAR, Q7.24 or Q0.24 through the sigmoid when NPUAEN=1); K-1 in NPUNI, N-1 in NPUNN, M-1 in NPUCFG1 bits 7:0; NPUBEN must be 0 in this mode; the working set M*K + K*N + M*N must fit the 4096-word staging RAM (larger problems tile by re-pointing the start-address registers between THINKs — there is no hardware accumulation across tiles). Codes 4-7 are reserved. Reserved and unimplemented codes behave as mode 0.', accessibility='rw'))
r.AddBitField(BitField(name='NPUTDIE', msb=19, description='Think-done interrupt enable. When set, NPUSR.THINKDONE drives the NPU think-done interrupt (vector 120). When cleared (reset default) the NPU is polling-only, exactly as before the interrupt existed.', accessibility='rw', valueDescriptions=[(0b0, 'Interrupt disabled (polling only)'), (0b1, 'Interrupt enabled')]))
r.AddBitField(BitField(name='NPUBEN', msb=18, description='Bias enable. When set, the first weight of each output neuron\'s row in the weight matrix is used as a bias term: it is multiplied by an implicit input of 1.0 and accumulated before the synaptic weights.', accessibility='rw', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
r.AddBitField(BitField(name='NPUAEN', msb=17, description='Activation function enable. When set, the logistic sigmoid approximation activation function is applied to the accumulator output. When cleared, the raw accumulator output is used (linear/identity).', accessibility='rw', valueDescriptions=[(0b0, 'Disabled (linear output)'), (0b1, 'Enabled (logistic sigmoid approximation)')]))
r.AddBitField(BitField(name='NPUTHINK', msb=16, description='NPU computation start and status bit. Write 1 to start the NPU. Self-clears when the computation is complete. Poll this bit to determine when results are ready.', accessibility='rw1', valueDescriptions=[(0b0, 'Idle (computation complete or not started)'), (0b1, 'Running (write 1 to start)')]))
r.AddBitField(BitField(name='NPUNI', msb=15, lsb=8, description='Number of inputs in the input vector minus 1. The actual number of inputs is NPUNI + 1.', accessibility='rw'))
r.AddBitField(BitField(name='NPUNN', msb=7, lsb=0, description='Number of output neurons minus 1. The actual number of outputs is NPUNN + 1.', accessibility='rw'))

# NPUIVSAR
r = RegisterTemplate(nameTemplate='NPUIVSAR', registerMemorySlot=1, description='Input vector start word index within the shared NPU staging RAM: the byte offset from the start of the staging RAM (0xC000) divided by 4. For example, an input vector at byte address 0xC100 has word index 0x40. Each input is a signed Q0.24 value stored in bits 24:0 of its 32-bit SRAM word; bits 31:25 are ignored. Bit 24 is the sign bit. The input at index 0 is at word index NPUIVSAR. The input at index 1 is at word index NPUIVSAR + 1. The rest of the inputs follow in consecutive words.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=12, unused=True))
r.AddBitField(BitField(name='NPUIVSAR', msb=11, lsb=0, description='Input vector start word index within the NPU staging RAM (byte offset from 0xC000 divided by 4)', accessibility='rw'))

# NPUWVSAR
r = RegisterTemplate(nameTemplate='NPUWVSAR', registerMemorySlot=2, description='Synaptic weight matrix start word index within the shared NPU staging RAM: the byte offset from the start of the staging RAM (0xC000) divided by 4. Each weight is a signed Q7.24 value occupying all 32 bits of its SRAM word; bit 31 is the sign bit. Weights are stored row-major, one per 32-bit word, in the following order: for each output neuron (0 through NPUNN), if bias is enabled (NPUBEN = 1), the first word in the row is the bias weight (multiplied by an implicit input of 1.0), followed by NPUNI + 1 synaptic weights for inputs 0 through NPUNI. If bias is disabled, each row contains NPUNI + 1 synaptic weights only.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=12, unused=True))
r.AddBitField(BitField(name='NPUWVSAR', msb=11, lsb=0, description='Synaptic weight matrix start word index within the NPU staging RAM (byte offset from 0xC000 divided by 4)', accessibility='rw'))

# NPUOVSAR
r = RegisterTemplate(nameTemplate='NPUOVSAR', registerMemorySlot=3, description='Output vector start word index within the shared NPU staging RAM: the byte offset from the start of the staging RAM (0xC000) divided by 4. Each output is a signed Q7.24 value occupying all 32 bits of its SRAM word; bit 31 is the sign bit. The output at index 0 is written to word index NPUOVSAR. The output at index 1 is at word index NPUOVSAR + 1, and so on.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=12, unused=True))
r.AddBitField(BitField(name='NPUOVSAR', msb=11, lsb=0, description='Output vector start word index within the NPU staging RAM (byte offset from 0xC000 divided by 4)', accessibility='rw'))

# NPUSR (DP-SG 2026-07-22: think-done IRQ rider, vector 120)
r = RegisterTemplate(nameTemplate='NPUSR', registerMemorySlot=4, description='NPU status register. THINKDONE is write-1-to-clear (write a 1 to bit 0 to clear it; writing 0 leaves it unchanged) and is never cleared by a read. The NPU think-done interrupt (vector 120) is THINKDONE and NPUCR.NPUTDIE. Clearing THINKDONE does not affect NPUCR.NPUTHINK, which self-clears at completion as before; the staging-RAM ownership contract is unchanged (no hart may access 0xC000-0xFFFF until NPUCR bit 16 reads 0 again).', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=1, unused=True))
r.AddBitField(BitField(name='NPUTHINKDONE', msb=0, accessibility='rw1', description='Think-done flag. Set once per computation, when the NPU finishes (the same event that self-clears NPUCR.NPUTHINK); sticky. Drives the think-done interrupt (vector 120) when NPUCR.NPUTDIE is set. Write 1 to clear. On a same-cycle collision between a completing computation and a write-1-to-clear, the set wins (a completion is never lost).', valueDescriptions=[(0b0, 'No completed computation pending'), (0b1, 'A computation has completed')]))

# NPUCFG1/NPUCFG2 (P4.1 architecture family, npu_family_spec.md 2026-07-23):
# per-mode configuration words behind the 4-bit MMR decode; word offsets 7-15
# are reserved and read 0 (no storage until a future mode claims them).
r = RegisterTemplate(nameTemplate='NPUCFG1', registerMemorySlot=5, description='NPU mode configuration word 1. The interpretation depends on NPUCR.NPUMODE. Multilayer-perceptron mode (0): unused, no effect. One-dimensional convolution mode (1): bits 3:0 = stride S (1-15), bits 7:4 = dilation D (1-15), bits 23:8 = input length L per channel in samples, bits 31:24 = number of input channels minus 1 (the actual channel count Cin is this field + 1). XNOR-popcount mode (2): the full 32-bit signed firing threshold THRESH — a neuron fires (output +1.0) when 2*popcount(XNOR(activations, weights)) - K is greater than or equal to THRESH, else outputs -1.0. GEMM mode (3): bits 7:0 = M - 1, the number of A rows minus 1 (the actual row count M is this field + 1); bits 31:8 are ignored in this mode.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(name='NPUCFG1', msb=31, lsb=0, description='Per-mode configuration word 1 (interpretation selected by NPUCR.NPUMODE)', accessibility='rw'))

r = RegisterTemplate(nameTemplate='NPUCFG2', registerMemorySlot=6, description='NPU mode configuration word 2. The interpretation depends on NPUCR.NPUMODE. Multilayer-perceptron mode (0): unused, no effect. One-dimensional convolution mode (1): bits 15:0 = output length Lout per filter in samples. Lout is computed by the host (the sequencer trusts this value; the valid/same padding convention is a firmware decision) and every referenced input sample index j*S + k*D must be less than L. XNOR-popcount mode (2): bits 12:0 = K, the exact input bit count (1-4096); NPUNI must hold ceil(K/32) - 1, the packed words per neuron, and when K mod 32 is nonzero the unused high bits of each last packed word are masked out of the popcount by hardware. GEMM mode (3): unused, no effect. Bits 31:16 are reserved and read 0.', size=32)
p.AddRegisterTemplate(r)

r.AddBitField(BitField(msb=31, lsb=16, unused=True))
r.AddBitField(BitField(name='NPUCFG2', msb=15, lsb=0, description='Per-mode configuration word 2 (interpretation selected by NPUCR.NPUMODE)', accessibility='rw'))



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

# Stage E rider (2026-07-21): the routing rows and the RO status readback are
# vectorsCount-driven. Every current config has > 96 sources (114 default since
# GPIO4/5 went unconditional; up to 120 wound), so the router carries FOUR
# enable words per hart — the fourth (HhENX, row word 4h+3, the formerly
# reserved slot) covers vectors (vectorsCount-1):96 — and the RO status
# readback has the matching PENDX/INSVCX words at 0x781C/0x782C. The U words
# are then fully live (vectors 95:64, bits 31:0). The historic 3-word form
# (U = 84:64, bits 20:0, no X words) survives for <= 96-source configs.
_irqrXWords = _vectorsCount > 96			# HhENX/PENDX/INSVCX exist
_irqrXMsb   = _vectorsCount - 97			# live msb in the X words (when they exist)
_irqrUMsb   = 31 if _vectorsCount >= 96 else _vectorsCount - 65
_irqrUTop   = min(_vectorsCount, 96) - 1	# top vector covered by the U words

for h in range(numHarts):
	r = RegisterTemplate(nameTemplate='H' + str(h) + 'ENL', registerMemorySlot=4 * h, size=32, description='Hart ' + str(h) + ' interrupt routing register, vectors 31:0. Each bit enables delivery of the corresponding interrupt vector to hart ' + str(h) + ' via its meip wire (vector 85) and the CLAIM/COMPLETE mechanism.')
	p.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='IRQRH' + str(h) + 'ENL', msb=31, lsb=0, accessibility='rw', description='Interrupt enable bits for vectors 31:0, routed to hart ' + str(h) + '.'))

	r = RegisterTemplate(nameTemplate='H' + str(h) + 'ENM', registerMemorySlot=4 * h + 1, size=32, description='Hart ' + str(h) + ' interrupt routing register, vectors 63:32.')
	p.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='IRQRH' + str(h) + 'ENM', msb=31, lsb=0, accessibility='rw', description='Interrupt enable bits for vectors 63:32, routed to hart ' + str(h) + '.'))

	if _irqrUMsb == 31:
		r = RegisterTemplate(nameTemplate='H' + str(h) + 'ENU', registerMemorySlot=4 * h + 2, size=32, description='Hart ' + str(h) + ' interrupt routing register, vectors 95:64. Unlike the retired SYSTEM IRQENU register of the single-core chip, the packing here is contiguous in both directions. Bits 19 and 20 correspond to the CLINT vectors 83 and 84, which are delivered on dedicated hardwired wires and never through meip: these two bits are writable but have no effect.')
		p.AddRegisterTemplate(r)
		r.AddBitField(BitField(name='IRQRH' + str(h) + 'ENU', msb=31, lsb=0, accessibility='rw', description='Interrupt enable bits for vectors 95:64, routed to hart ' + str(h) + '.'))
	else:
		r = RegisterTemplate(nameTemplate='H' + str(h) + 'ENU', registerMemorySlot=4 * h + 2, size=32, description='Hart ' + str(h) + ' interrupt routing register, vectors ' + str(_irqrUTop) + ':64 (bits ' + str(_irqrUMsb) + ':0; bits 31:' + str(_irqrUMsb + 1) + ' read as 0). Unlike the retired SYSTEM IRQENU register of the single-core chip, the packing here is contiguous in both directions. Bits 19 and 20 correspond to the CLINT vectors 83 and 84, which are delivered on dedicated hardwired wires and never through meip: these two bits are writable but have no effect.')
		p.AddRegisterTemplate(r)
		r.AddBitField(BitField(unused=True, msb=31, lsb=_irqrUMsb + 1))
		r.AddBitField(BitField(name='IRQRH' + str(h) + 'ENU', msb=_irqrUMsb, lsb=0, accessibility='rw', description='Interrupt enable bits for vectors ' + str(_irqrUTop) + ':64, routed to hart ' + str(h) + '.'))

	if _irqrXWords:
		r = RegisterTemplate(nameTemplate='H' + str(h) + 'ENX', registerMemorySlot=4 * h + 3, size=32, description='Hart ' + str(h) + ' interrupt routing register, vectors ' + str(_vectorsCount - 1) + ':96 (bits ' + str(_irqrXMsb) + ':0; upper bits read as 0).')
		p.AddRegisterTemplate(r)
		if _irqrXMsb < 31:
			r.AddBitField(BitField(unused=True, msb=31, lsb=_irqrXMsb + 1))
		r.AddBitField(BitField(name='IRQRH' + str(h) + 'ENX', msb=_irqrXMsb, lsb=0, accessibility='rw', description='Interrupt enable bits for vectors ' + str(_vectorsCount - 1) + ':96, routed to hart ' + str(h) + '.'))

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

if _irqrUMsb == 31:
	r = RegisterTemplate(nameTemplate='PENDU', registerMemorySlot=518, size=32, description='Raw pending interrupt levels, vectors 95:64 (read-only).')
	p.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='IRQRPENDU', msb=31, lsb=0, accessibility='r', description='Deglitched interrupt levels for vectors 95:64.'))
else:
	r = RegisterTemplate(nameTemplate='PENDU', registerMemorySlot=518, size=32, description='Raw pending interrupt levels, vectors ' + str(_irqrUTop) + ':64 (bits ' + str(_irqrUMsb) + ':0, read-only; bits 31:' + str(_irqrUMsb + 1) + ' read as 0).')
	p.AddRegisterTemplate(r)
	r.AddBitField(BitField(unused=True, msb=31, lsb=_irqrUMsb + 1))
	r.AddBitField(BitField(name='IRQRPENDU', msb=_irqrUMsb, lsb=0, accessibility='r', description='Deglitched interrupt levels for vectors ' + str(_irqrUTop) + ':64.'))

if _irqrXWords:
	r = RegisterTemplate(nameTemplate='PENDX', registerMemorySlot=519, size=32, description='Raw pending interrupt levels, vectors ' + str(_vectorsCount - 1) + ':96 (bits ' + str(_irqrXMsb) + ':0, read-only; upper bits read as 0). Completes the raw-level readback for the fourth enable word (added with the peripheral-library program; before it, sources above 95 were routable and claimable but absent from the debug readback).')
	p.AddRegisterTemplate(r)
	if _irqrXMsb < 31:
		r.AddBitField(BitField(unused=True, msb=31, lsb=_irqrXMsb + 1))
	r.AddBitField(BitField(name='IRQRPENDX', msb=_irqrXMsb, lsb=0, accessibility='r', description='Deglitched interrupt levels for vectors ' + str(_vectorsCount - 1) + ':96.'))

r = RegisterTemplate(nameTemplate='INSVCL', registerMemorySlot=520, size=32, description='Under-service (claimed, not yet completed) flags, vectors 31:0 (read-only). Debug and recovery visibility: a stuck bit here means a hart claimed the vector and never completed it; any hart can recover by writing the vector number to CLAIM.')
p.AddRegisterTemplate(r)
r.AddBitField(BitField(name='IRQRINSVCL', msb=31, lsb=0, accessibility='r', description='Under-service flags for vectors 31:0.'))

r = RegisterTemplate(nameTemplate='INSVCM', registerMemorySlot=521, size=32, description='Under-service flags, vectors 63:32 (read-only).')
p.AddRegisterTemplate(r)
r.AddBitField(BitField(name='IRQRINSVCM', msb=31, lsb=0, accessibility='r', description='Under-service flags for vectors 63:32.'))

if _irqrUMsb == 31:
	r = RegisterTemplate(nameTemplate='INSVCU', registerMemorySlot=522, size=32, description='Under-service flags, vectors 95:64 (read-only).')
	p.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='IRQRINSVCU', msb=31, lsb=0, accessibility='r', description='Under-service flags for vectors 95:64.'))
else:
	r = RegisterTemplate(nameTemplate='INSVCU', registerMemorySlot=522, size=32, description='Under-service flags, vectors ' + str(_irqrUTop) + ':64 (bits ' + str(_irqrUMsb) + ':0, read-only; bits 31:' + str(_irqrUMsb + 1) + ' read as 0).')
	p.AddRegisterTemplate(r)
	r.AddBitField(BitField(unused=True, msb=31, lsb=_irqrUMsb + 1))
	r.AddBitField(BitField(name='IRQRINSVCU', msb=_irqrUMsb, lsb=0, accessibility='r', description='Under-service flags for vectors ' + str(_irqrUTop) + ':64.'))

if _irqrXWords:
	r = RegisterTemplate(nameTemplate='INSVCX', registerMemorySlot=523, size=32, description='Under-service flags, vectors ' + str(_vectorsCount - 1) + ':96 (bits ' + str(_irqrXMsb) + ':0, read-only; upper bits read as 0). Completes the under-service readback for the fourth enable word.')
	p.AddRegisterTemplate(r)
	if _irqrXMsb < 31:
		r.AddBitField(BitField(unused=True, msb=31, lsb=_irqrXMsb + 1))
	r.AddBitField(BitField(name='IRQRINSVCX', msb=_irqrXMsb, lsb=0, accessibility='r', description='Under-service flags for vectors ' + str(_vectorsCount - 1) + ':96.'))



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

# DP-S3 (field-powered NFC mode, 2026-07-24): PWRWAKE/PWRSTS at FIXED word
# offsets 5/6 — above the PWRSR nibble array's worst case (ceil(N/8) <= 4 at
# N <= 32), so the layout is hart-count-independent. Both reset to a provable
# NO-OP; the boot gate they control is the HOLD-IN-RESET pgood_rstn output
# (ANDed into every hart's outer reset at the top level). The registers exist
# in every configuration; peripherals.fieldPower only decides whether the
# pad-side inputs (PGOOD P6.7, strap P6.6, NFC field level) are wired or tied.
r = RegisterTemplate(nameTemplate='PWRWAKE', registerMemorySlot=5, size=32, description='Boot-gate / wake-source control (DP-S3 field-powered mode). The harvested-boot STRAP drives the hardware defaults (a strapped board self-arms the gate, waits on PGOOD, and re-holds on brownout with no software involvement); these bits OR-IN software overrides on top. Resets to 0 = no software override = the gate is released on every normal boot. Write with full-word stores (byte-lane-0 qualified, like PWRCR).')
r.AddBitField(BitField(unused=True, msb=31, lsb=5))
r.AddBitField(BitField(name='PWREHOLD', msb=4, lsb=4, accessibility='rw', description='Re-hold policy override: 1 = re-assert the boot hold when the release condition drops (brownout re-hold; PGOOD return then cold-boots the harts through the shared ROM). 0 = one-shot — once released, stays released (see PWRSTS.PWRRLSLATCH). The strap ORs this in on a harvested board.'))
r.AddBitField(BitField(name='PWSWRLS', msb=3, lsb=3, accessibility='rw', description='Software-forced release: 1 releases an armed gate unconditionally (test/override, or "software says proceed"). With no release source enabled, an armed gate holds until this bit — the negative-control proof that the gate is load-bearing.'))
r.AddBitField(BitField(name='PWRLSFIELD', msb=2, lsb=2, accessibility='rw', description='1 = the synchronized NFC field level (PWRSTS.PWFIELDLIV) is a release condition — the field_detect WAKE source: a reader arriving releases the boot gate. No IRQ vector is involved. Reads as tied-0 field when NFC is absent or fieldPower is off.'))
r.AddBitField(BitField(name='PWRLSPGOOD', msb=1, lsb=1, accessibility='rw', description='1 = the synchronized PGOOD pad level (PWRSTS.PWPGOODLIV) is a release condition. The strap ORs this in on a harvested board (it always waits on the supply supervisor).'))
r.AddBitField(BitField(name='PWGATEEN', msb=0, lsb=0, accessibility='rw', description='Software boot-gate arm: 1 arms the HOLD-IN-RESET gate (every hart\'s outer reset held until a release condition fires). The harvested-boot strap ORs this in — a strapped board arms with no software.'))
p.AddRegisterTemplate(r)
r = RegisterTemplate(nameTemplate='PWRSTS', registerMemorySlot=6, size=32, description='Boot-gate / wake-source status (read-only). The synchronized live pad levels, the one-shot strap sample (THE bootrom harvested-boot branch bit), and the gate state.')
r.AddBitField(BitField(unused=True, msb=31, lsb=6))
r.AddBitField(BitField(name='PWRRLSLATCH', msb=5, lsb=5, accessibility='r', description='One-shot release has latched (sticky until reset; only meaningful with PWREHOLD = 0).'))
r.AddBitField(BitField(name='PWBOOTHOLD', msb=4, lsb=4, accessibility='r', description='Current gate state: 1 = the boot gate is holding every hart in reset (pgood_rstn asserted).'))
r.AddBitField(BitField(name='PWSTRAPVLD', msb=3, lsb=3, accessibility='r', description='Strap sample complete (the one-shot sample lands a few mclk after reset release; poll before consuming PWSTRAP).'))
r.AddBitField(BitField(name='PWSTRAP', msb=2, lsb=2, accessibility='r', description='Latched harvested-boot strap sample: 1 = harvested boot (the bootrom skips the SPI-flash copy and runs the ROM-resident service loop), 0 = normal SPI boot. Sampled ONCE after reset; mid-run strap changes are ignored.'))
r.AddBitField(BitField(name='PWFIELDLIV', msb=1, lsb=1, accessibility='r', description='Synchronized NFC field_detect level (0 when NFC is absent or fieldPower is off).'))
r.AddBitField(BitField(name='PWPGOODLIV', msb=0, lsb=0, accessibility='r', description='Synchronized PGOOD pad level (P6.7). Reads 0 = power-not-good when the pin is unconnected (reset pull-down).'))
p.AddRegisterTemplate(r)



''' Check the peripheral templates for errors '''
# digperiphs #1 (2026-07-18): QSPI0 register template. Added unconditionally
# (before CheckPeripheralTemplates) so the template exists whenever qspiPresent
# CreatePeripheral()s it at slot 12; with qspi off it is simply never instanced.
if qspiPresent:
	qspi = PeripheralTemplate(nameTemplate='QSPIx', description='Quad Serial Peripheral Interface flash controller. Issues single-/dual-/quad-lane command, address, dummy, and data phases to an external SPI-family memory over a 6-wire bus (SCK, active-low CS, and four bidirectional IO lines). Each phase has an independently configurable lane width, so the same engine drives legacy 1-1-1 flash, dual-output (1-1-2), and quad-output/quad-I/O (1-1-4 / 1-4-4) devices. A transaction is described by the control, command, and address registers and launched by a byte-lane-0 write to QSPIxCMD; the registered read path returns snapshots with no read side effects. The serial core runs in the SMCLK domain (SYS_CLK_CR=0 rule applies), with a programmable baud divider off SMCLK.', registerPrefix='QSPIx', bitFieldPrefix='QSPI', latexIntroFileName='QSPI-intro-castalia-2026-07.tex', latexFeatureSummary='{count} QSPI flash controller (single/dual/quad lane; per-phase width)')
	m.AddPeripheralTemplate(qspi)

	# QSPIxCR (slot 0) -- control
	r = RegisterTemplate(nameTemplate='QSPIxCR', registerMemorySlot=0, description='QSPI control register. Configures the per-phase lane widths, SPI mode, address size, dummy cycles, chip select, baud rate, and interrupt enables. Take care to reconfigure this register only while the controller is idle (QSPIBUSY = 0).', size=32)
	qspi.AddRegisterTemplate(r)
	_widthVals = [(0b00, '1-bit (single lane, IO0 only)'), (0b01, '2-bit (dual lane, IO0-1)'), (0b10, '4-bit (quad lane, IO0-3)'), (0b11, 'Reserved')]
	r.AddBitField(BitField(name='QSPIEN', msb=0, accessibility='rw', description='QSPI enable. When 0 the controller is held idle: the serial pins are released, no transaction launches, and a write to QSPIxCMD is ignored. Set to 1 before launching a transaction.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
	r.AddBitField(BitField(name='QSPICMDW', msb=2, lsb=1, accessibility='rw', description='Command-phase lane width. Selects how many IO lines carry the 8-bit opcode.', valueDescriptions=_widthVals))
	r.AddBitField(BitField(name='QSPIADRW', msb=4, lsb=3, accessibility='rw', description='Address-phase lane width. Selects how many IO lines carry the transaction address (when QSPIAWID is non-zero).', valueDescriptions=_widthVals))
	r.AddBitField(BitField(name='QSPIDATW', msb=6, lsb=5, accessibility='rw', description='Data-phase lane width. Selects how many IO lines carry the payload.', valueDescriptions=_widthVals))
	r.AddBitField(BitField(name='QSPICPOL', msb=7, accessibility='rw', description='Clock polarity. Sets the idle level of SCK.', valueDescriptions=[(0b0, 'SCK idles low'), (0b1, 'SCK idles high')]))
	r.AddBitField(BitField(name='QSPICPHA', msb=8, accessibility='rw', description='Clock phase. Selects the SCK edge on which data is sampled.', valueDescriptions=[(0b0, 'Sample on the leading edge'), (0b1, 'Sample on the trailing edge')]))
	r.AddBitField(BitField(name='QSPIAWID', msb=10, lsb=9, accessibility='rw', description='Address-phase width in bits. Selects whether the transaction emits an address phase and how wide it is (from QSPIxADR).', valueDescriptions=[(0b00, 'No address phase'), (0b01, '24-bit address (low 24 bits of QSPIxADR)'), (0b10, '32-bit address'), (0b11, 'Reserved')]))
	r.AddBitField(BitField(name='QSPIDUMMY', msb=15, lsb=11, accessibility='rw', description='Dummy SCK cycles inserted after the address phase and before the data phase, with the bus released (all IO lines tri-stated). Required for dual/quad fast-read commands (at least 1 dummy cycle); set to 0 for commands with no dummy phase.'))
	r.AddBitField(BitField(name='QSPICSSEL', msb=18, lsb=16, accessibility='rw', description='Chip-select index. Selects which chip-select output drives the transaction. In this MVP only CS0 is wired to a pin; write 0.'))
	r.AddBitField(BitField(name='QSPIBR', msb=26, lsb=19, accessibility='rw', description='Baud-rate divider. The serial clock is SCK = SMCLK / (2 * (1 + QSPIBR)), so 0 gives the fastest clock (SMCLK/2). SMCLK is the SYSTEM clock source (write SYS_CLK_CR = 0 to run SMCLK from HFXT before using the controller).'))
	r.AddBitField(BitField(name='QSPITCIE', msb=27, accessibility='rw', description='Transfer-complete interrupt enable. When set, the QSPITCIF flag drives interrupt vector 55.', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='QSPIRXFIE', msb=28, accessibility='rw', description='Receive-full interrupt enable. When set, the QSPIRXFULL flag drives interrupt vector 56.', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(msb=31, lsb=29, unused=True))

	# QSPIxCMD (slot 1) -- command; a byte-lane-0 write launches the transaction
	r = RegisterTemplate(nameTemplate='QSPIxCMD', registerMemorySlot=1, description='QSPI command register. Holds the opcode, data length, and direction of the next transaction. Writing this register with byte lane 0 asserted LAUNCHES the transaction (the write is ignored when QSPIEN = 0 or QSPIBUSY = 1). Program QSPIxCR, QSPIxADR, and (for writes) QSPIxTX first, then write QSPIxCMD last.', size=32)
	qspi.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='QSPICMD', msb=7, lsb=0, accessibility='rw', description='Command opcode, shifted out most-significant bit first during the command phase at the QSPICMDW lane width.'))
	r.AddBitField(BitField(name='QSPIDLEN', msb=9, lsb=8, accessibility='rw', description='Data-phase length. Selects how many payload bits the data phase transfers (right-justified in QSPIxTX / QSPIxRX).', valueDescriptions=[(0b00, 'No data phase'), (0b01, '8-bit'), (0b10, '16-bit'), (0b11, '32-bit')]))
	r.AddBitField(BitField(name='QSPIDIR', msb=10, accessibility='rw', description='Data-phase direction.', valueDescriptions=[(0b0, 'Write (drive QSPIxTX out on the IO lines)'), (0b1, 'Read (capture the IO lines into QSPIxRX)')]))
	r.AddBitField(BitField(msb=31, lsb=11, unused=True))

	# QSPIxADR (slot 2) -- address
	r = RegisterTemplate(nameTemplate='QSPIxADR', registerMemorySlot=2, description='QSPI transaction address. Emitted during the address phase at the QSPIADRW lane width when QSPIAWID is non-zero. When QSPIAWID selects 24-bit, only the low 24 bits are used.', size=32)
	qspi.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='QSPIADR', msb=31, lsb=0, accessibility='rw', description='Transaction address value.'))

	# QSPIxTX (slot 3) -- write data (never triggers)
	r = RegisterTemplate(nameTemplate='QSPIxTX', registerMemorySlot=3, description='QSPI transmit data. Holds the write-direction payload, right-justified (the low QSPIDLEN bits are significant). Writing this register never triggers a transaction; only a QSPIxCMD write does.', size=32)
	qspi.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='QSPITX', msb=31, lsb=0, accessibility='rw', description='Write payload, right-justified.'))

	# QSPIxRX (slot 4) -- read data (no side effects)
	r = RegisterTemplate(nameTemplate='QSPIxRX', registerMemorySlot=4, description='QSPI receive data. A snapshot of the most recent read-direction data phase, right-justified (the low QSPIDLEN bits are significant). Reads have NO side effects: reading QSPIxRX does not clear any flag or advance any state (deliberately unlike the SPI RX-read-clears-TCIF behaviour).', size=32)
	qspi.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='QSPIRX', msb=31, lsb=0, accessibility='r', description='Read payload snapshot, right-justified.'))

	# QSPIxSR (slot 5) -- status (W1C flags)
	r = RegisterTemplate(nameTemplate='QSPIxSR', registerMemorySlot=5, description='QSPI status register. QSPIBUSY is read-only; the three event flags are write-1-to-clear (write a 1 to a bit to clear it; writing 0 leaves it unchanged).', size=32)
	qspi.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='QSPIBUSY', msb=0, accessibility='r', description='Busy. Reads 1 while a transaction is in progress; a QSPIxCMD launch is ignored while this bit is set.', valueDescriptions=[(0b0, 'Idle'), (0b1, 'Transaction in progress')]))
	r.AddBitField(BitField(name='QSPITXEIF', msb=1, accessibility='rw1', description='Transmit-empty flag. Set when the transmit path has consumed QSPIxTX and can accept the next word. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Transmit register empty')]))
	r.AddBitField(BitField(name='QSPIRXFULL', msb=2, accessibility='rw1', description='Receive-full flag. Set when a read-direction data phase has captured a fresh word into QSPIxRX; drives vector 56 when QSPIRXFIE is set. Write 1 to clear. (Reading QSPIxRX does NOT clear it.)', valueDescriptions=[(0b0, 'No event'), (0b1, 'Receive register full')]))
	r.AddBitField(BitField(name='QSPITCIF', msb=3, accessibility='rw1', description='Transfer-complete flag. Set when a transaction finishes; drives vector 55 when QSPITCIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Transfer complete')]))
	r.AddBitField(BitField(msb=31, lsb=4, unused=True))

# digperiphs #2 (2026-07-18): I3C0 register template (design doc S3, 10 slots).
# Added unconditionally (before CheckPeripheralTemplates) so the template exists
# whenever i3cPresent CreatePeripheral()s it at 0x6100; with I3C off it is never
# instanced. The serial core is smclk-domain (SYS_CLK_CR=0 rule); the register
# read path is registered with NO side effects.
if i3cPresent:
	i3c = PeripheralTemplate(nameTemplate='I3Cx', description='I3C controller (MIPI I3C basic, single-controller). Drives an I3C bus (SDA/SCL, open-drain and push-pull SDR) as the active controller, and interoperates with legacy I2C targets on the same wires. This MVP-plus implementation supports single-byte SDR private read/write transfers, repeated-START chaining, Common Command Codes (CCC), hardware Dynamic Address Assignment (DAA via ENTDAA and SETDASA), and In-Band Interrupts (IBI) from targets. A transaction is described by the control and command registers and launched by a byte-lane-0 write to I3CxCMD; the registered read path returns snapshots with no read side effects. The serial core runs in the SMCLK domain (SYS_CLK_CR=0 rule applies) with independent open-drain and push-pull baud dividers.', registerPrefix='I3Cx', bitFieldPrefix='I3C', latexIntroFileName='I3C-intro-castalia-2026-07.tex', latexFeatureSummary='{count} I3C controller (SDR + legacy-I2C, dynamic address assignment, in-band interrupts)')
	m.AddPeripheralTemplate(i3c)

	# I3CxCR (slot 0) -- control (reset 0 except I3CSDAPP = 1)
	r = RegisterTemplate(nameTemplate='I3CxCR', registerMemorySlot=0, description='I3C control register. Configures the bus mode, SDA drive style, open-drain and push-pull baud dividers, and the interrupt enables. Reconfigure only while the controller is idle (I3CBUSY = 0); the mode and drive bits are additionally latched at each transaction launch. Resets to 0 except I3CSDAPP, which resets to 1.', size=32)
	i3c.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I3CEN', msb=0, accessibility='rw', description='Controller enable. When 0 the serial core is held in reset (no transaction launches and the serial pins are released) but the RX register, DAT table, and status flags are preserved. Set to 1 before launching a transaction.', valueDescriptions=[(0b0, 'Disabled (serial core in reset)'), (0b1, 'Enabled')]))
	r.AddBitField(BitField(name='I3CBUSMODE', msb=1, accessibility='rw', description='Bus mode, latched at launch. Selects the framing for the next transaction.', valueDescriptions=[(0b0, 'I3C SDR'), (0b1, 'Legacy I2C')]))
	r.AddBitField(BitField(name='I3CSDAPP', msb=2, accessibility='rw', description='SDA drive style for SDR data, latched at launch (resets to 1). When 0 the data phase is forced open-drain (required for legacy-I2C targets).', valueDescriptions=[(0b0, 'Force open-drain'), (0b1, 'Push-pull SDR data')]))
	r.AddBitField(BitField(name='I3CIBIEN', msb=3, accessibility='rw', description='In-band interrupt accept enable. When set, the controller ACKs a target-initiated IBI and captures it into I3CxIBI; when clear, IBIs are NACKed.', valueDescriptions=[(0b0, 'IBIs NACKed'), (0b1, 'IBIs accepted')]))
	r.AddBitField(BitField(msb=7, lsb=4, unused=True))
	r.AddBitField(BitField(name='I3CODBR', msb=15, lsb=8, accessibility='rw', description='Open-drain baud divider. The open-drain SCL rate is SMCLK / (2 * (1 + I3CODBR)); used for the arbitrated address header and legacy-I2C phases.'))
	r.AddBitField(BitField(name='I3CPPBR', msb=23, lsb=16, accessibility='rw', description='Push-pull baud divider. The push-pull SCL rate is SMCLK / (2 * (1 + I3CPPBR)); used for SDR data once the bus is in push-pull. SMCLK is the SYSTEM clock source (write SYS_CLK_CR = 0 to run SMCLK from HFXT before using the controller).'))
	r.AddBitField(BitField(name='I3CTCIE', msb=24, accessibility='rw', description='Transfer-complete interrupt enable (interrupt vector 86).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='I3CERRIE', msb=25, accessibility='rw', description='Error interrupt enable: gates the address-NACK (vector 89), early-end-of-data (vector 90), and arbitration-lost (vector 91) sources.', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='I3CDAAIE', msb=26, accessibility='rw', description='Dynamic-address-assignment done interrupt enable (interrupt vector 92).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='I3CIBIIE', msb=27, accessibility='rw', description='In-band interrupt pending interrupt enable (interrupt vector 93).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='I3CRXFIE', msb=28, accessibility='rw', description='Receive-full interrupt enable (interrupt vector 87).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='I3CTXEIE', msb=29, accessibility='rw', description='Transmit-empty interrupt enable (interrupt vector 88).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(msb=31, lsb=30, unused=True))

	# I3CxCMD (slot 1) -- command; a byte-lane-0 write launches the transaction
	r = RegisterTemplate(nameTemplate='I3CxCMD', registerMemorySlot=1, description='I3C command register. Describes the next transaction: target address, direction, START/STOP framing, optional CCC and dynamic-address-assignment operations, and the data length. Writing this register with byte lane 0 asserted LAUNCHES the transaction; the content is always captured, but the launch is suppressed when I3CEN = 0 or I3CBUSY = 1. Program I3CxCR (and, for a write, I3CxTX) first, then write I3CxCMD last. All command and control fields are latched at launch.', size=32)
	i3c.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I3CADDR', msb=6, lsb=0, accessibility='rw', description='7-bit target address. The broadcast address 0x7E is auto-prepended by hardware only when I3CCCC = 1.'))
	r.AddBitField(BitField(name='I3CRNW', msb=7, accessibility='rw', description='Direction.', valueDescriptions=[(0b0, 'Write (controller drives I3CxTX out)'), (0b1, 'Read (controller captures into I3CxRX)')]))
	r.AddBitField(BitField(name='I3CREPSTART', msb=8, accessibility='rw', description='Repeated-START (Sr) entry. When set, the transaction begins with a repeated START instead of a START, chaining onto a bus previously held (see I3CSTOPEN).', valueDescriptions=[(0b0, 'START'), (0b1, 'Repeated START')]))
	r.AddBitField(BitField(name='I3CSTOPEN', msb=9, accessibility='rw', description='STOP enable.', valueDescriptions=[(0b0, 'Hold the bus at end (for a following repeated START)'), (0b1, 'Issue STOP at end')]))
	r.AddBitField(BitField(name='I3CCCC', msb=10, accessibility='rw', description='Common Command Code transaction. When set, the transaction is a CCC (0x7E broadcast auto-prepended; the opcode is in I3CCCCOP).', valueDescriptions=[(0b0, 'Private transfer'), (0b1, 'CCC')]))
	r.AddBitField(BitField(name='I3CCCCDIR', msb=11, accessibility='rw', description='CCC direction.', valueDescriptions=[(0b0, 'Broadcast CCC'), (0b1, 'Direct CCC')]))
	r.AddBitField(BitField(name='I3CDAARUN', msb=12, accessibility='rw', description='Run ENTDAA dynamic address assignment. When set (with I3CCCC and I3CCCCOP = 0x07), the controller runs the ENTDAA loop, assigning the dynamic addresses programmed in the DAT entries to newly discovered targets.', valueDescriptions=[(0b0, 'No ENTDAA'), (0b1, 'Run ENTDAA')]))
	r.AddBitField(BitField(name='I3CDASA', msb=13, accessibility='rw', description='Run SETDASA (set dynamic address from static address) for the addressed DAT entry.', valueDescriptions=[(0b0, 'No SETDASA'), (0b1, 'Run SETDASA')]))
	r.AddBitField(BitField(msb=15, lsb=14, unused=True))
	r.AddBitField(BitField(name='I3CDLEN', msb=23, lsb=16, accessibility='rw', description='Data length, 0 to 255 bytes. The number of payload bytes the data phase transfers.'))
	r.AddBitField(BitField(name='I3CCCCOP', msb=31, lsb=24, accessibility='rw', description='CCC opcode (used when I3CCCC = 1; e.g. 0x07 = ENTDAA).'))

	# I3CxTX (slot 2) -- write data (arms the byte-pending handshake; never launches)
	r = RegisterTemplate(nameTemplate='I3CxTX', registerMemorySlot=2, description='I3C transmit data. Writing the low byte arms the per-byte transmit handshake for the data phase; writing this register never launches a transaction (only an I3CxCMD write does). The upper bits are reserved for future word-packing.', size=32)
	i3c.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I3CTX', msb=7, lsb=0, accessibility='rw', description='Next write byte.'))
	r.AddBitField(BitField(msb=31, lsb=8, unused=True))

	# I3CxRX (slot 3) -- read data (no side effects)
	r = RegisterTemplate(nameTemplate='I3CxRX', registerMemorySlot=3, description='I3C receive data. The most recently received byte. Reads have NO side effects (reading I3CxRX clears nothing). Reset-cleared to 0.', size=32)
	i3c.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I3CRX', msb=7, lsb=0, accessibility='r', description='Last received byte.'))
	r.AddBitField(BitField(msb=31, lsb=8, unused=True))

	# I3CxSR (slot 4) -- status (W1C flags + read-only live/busy bits)
	r = RegisterTemplate(nameTemplate='I3CxSR', registerMemorySlot=4, description='I3C status register. I3CBUSY and I3CIBIWON are read-only; the event flags are write-1-to-clear (write a 1 to a bit to clear it; writing 0 leaves it unchanged).', size=32)
	i3c.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I3CBUSY', msb=0, accessibility='r', description='Busy. Reads 1 while a transaction is in progress; an I3CxCMD launch is ignored while this bit is set.', valueDescriptions=[(0b0, 'Idle'), (0b1, 'Transaction in progress')]))
	r.AddBitField(BitField(name='I3CTCIF', msb=1, accessibility='rw1', description='Transfer-complete flag. Set when a transaction finishes; drives vector 86 when I3CTCIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Transfer complete')]))
	r.AddBitField(BitField(name='I3CRXFULL', msb=2, accessibility='rw1', description='Receive-full flag. Set when the data phase captures a fresh byte into I3CxRX; drives vector 87 when I3CRXFIE is set. Write 1 to clear. (Reading I3CxRX does NOT clear it.)', valueDescriptions=[(0b0, 'No event'), (0b1, 'Receive register full')]))
	r.AddBitField(BitField(name='I3CTXEIF', msb=3, accessibility='rw1', description='Transmit-empty flag. Set when the transmit path has consumed I3CxTX and can accept the next byte; drives vector 88 when I3CTXEIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Transmit register empty')]))
	r.AddBitField(BitField(name='I3CANACK', msb=4, accessibility='rw1', description='Address-NACK flag. Set when a target NACKs the address (or a legacy per-byte NACK occurs); drives vector 89 when I3CERRIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Address / byte NACK')]))
	r.AddBitField(BitField(name='I3CEODF', msb=5, accessibility='rw1', description='Early end-of-data flag (read). Set when a target ends a read (T = 0) before I3CDLEN bytes; drives vector 90 when I3CERRIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Early end-of-data')]))
	r.AddBitField(BitField(name='I3CARBLOST', msb=6, accessibility='rw1', description='Arbitration-lost flag. Set when the controller loses address-header arbitration; drives vector 91 when I3CERRIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Arbitration lost')]))
	r.AddBitField(BitField(name='I3CDAADONE', msb=7, accessibility='rw1', description='Dynamic-address-assignment done flag. Set when an ENTDAA/SETDASA run completes; drives vector 92 when I3CDAAIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'DAA complete')]))
	r.AddBitField(BitField(name='I3CDAAFULL', msb=8, accessibility='rw1', description='DAA capture-full flag. Set when a DAA run captured a newly discovered device into a DAT entry. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'DAT entry captured')]))
	r.AddBitField(BitField(name='I3CIBIP', msb=9, accessibility='rw1', description='In-band interrupt pending flag. Set when an accepted IBI has been captured into I3CxIBI; drives vector 93 when I3CIBIIE is set. Write 1 to clear (which also releases the I3CxIBI snapshot).', valueDescriptions=[(0b0, 'No event'), (0b1, 'IBI captured')]))
	r.AddBitField(BitField(name='I3CIBIWON', msb=10, accessibility='r', description='IBI-won (live). Reads 1 while a target is currently winning IBI arbitration on the bus.', valueDescriptions=[(0b0, 'No live IBI'), (0b1, 'IBI in arbitration')]))
	r.AddBitField(BitField(msb=31, lsb=11, unused=True))

	# I3CxDAT (slot 5) -- device address table window (indexed by I3CIDX)
	r = RegisterTemplate(nameTemplate='I3CxDAT', registerMemorySlot=5, description='Device Address Table window. I3CIDX selects which of the 4 DAT entries this window (and I3CxDATPID / I3CxDATINFO) addresses; the index persists across accesses. Each entry holds a target\'s dynamic address, static address, and validity bits used by DAA and by private transfers.', size=32)
	i3c.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I3CIDX', msb=2, lsb=0, accessibility='rw', description='DAT entry index (0 to 3; the upper values are ignored). Selects the entry for this register, I3CxDATPID, and I3CxDATINFO.'))
	r.AddBitField(BitField(name='I3CEVALID', msb=3, accessibility='rw', description='Entry valid. Marks the selected DAT entry as populated.', valueDescriptions=[(0b0, 'Empty'), (0b1, 'Valid')]))
	r.AddBitField(BitField(name='I3CDYNADDR', msb=10, lsb=4, accessibility='rw', description='Dynamic address (7-bit) assigned to (or to assign to) this device.'))
	r.AddBitField(BitField(name='I3CDYNVALID', msb=11, accessibility='rw', description='Dynamic address valid.', valueDescriptions=[(0b0, 'No dynamic address'), (0b1, 'Dynamic address assigned')]))
	r.AddBitField(BitField(name='I3CSTATADDR', msb=18, lsb=12, accessibility='rw', description='Static (legacy-I2C) address (7-bit) of this device, used by SETDASA.'))
	r.AddBitField(BitField(name='I3CSTATVALID', msb=19, accessibility='rw', description='Static address valid.', valueDescriptions=[(0b0, 'No static address'), (0b1, 'Static address present')]))
	r.AddBitField(BitField(msb=31, lsb=20, unused=True))

	# I3CxDATPID (slot 6) -- selected entry's provisional ID, low 32 bits
	r = RegisterTemplate(nameTemplate='I3CxDATPID', registerMemorySlot=6, description='Provisional ID (low 32 bits) of the DAT entry selected by I3CIDX. During ENTDAA the controller captures the discovered device\'s 48-bit PID; software reads it here (and the high 16 bits from I3CxDATINFO) to identify the device.', size=32)
	i3c.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I3CPIDLO', msb=31, lsb=0, accessibility='rw', description='Provisional ID bits 31:0.'))

	# I3CxDATINFO (slot 7) -- selected entry's PID high bits + BCR + DCR
	r = RegisterTemplate(nameTemplate='I3CxDATINFO', registerMemorySlot=7, description='High provisional-ID bits and the bus/device characteristic registers of the DAT entry selected by I3CIDX.', size=32)
	i3c.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I3CPIDHI', msb=15, lsb=0, accessibility='rw', description='Provisional ID bits 47:32.'))
	r.AddBitField(BitField(name='I3CBCR', msb=23, lsb=16, accessibility='rw', description='Bus Characteristic Register of the device. BCR bit 2 = 1 indicates the device\'s IBIs carry a mandatory data byte (captured into I3CIBIMDB).'))
	r.AddBitField(BitField(name='I3CDCR', msb=31, lsb=24, accessibility='rw', description='Device Characteristic Register of the device (device type code).'))

	# I3CxIBI (slot 8) -- captured in-band interrupt snapshot (cleared via SR.I3CIBIP)
	r = RegisterTemplate(nameTemplate='I3CxIBI', registerMemorySlot=8, description='In-band interrupt capture. A read-only snapshot of the most recently accepted IBI: which target raised it, its optional mandatory data byte, and whether it was ACKed. The snapshot is held until the I3CIBIP flag is cleared (write 1 to I3CIBIP in I3CxSR).', size=32)
	i3c.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I3CIBIADDR', msb=6, lsb=0, accessibility='r', description='Dynamic address of the target that raised the IBI.'))
	r.AddBitField(BitField(name='I3CIBIVALID', msb=7, accessibility='r', description='IBI snapshot valid.', valueDescriptions=[(0b0, 'Empty'), (0b1, 'Valid capture')]))
	r.AddBitField(BitField(name='I3CIBIMDB', msb=15, lsb=8, accessibility='r', description='Mandatory data byte, when the device\'s BCR bit 2 = 1 (see I3CIBIHASDATA).'))
	r.AddBitField(BitField(name='I3CIBIHASDATA', msb=16, accessibility='r', description='Mandatory-data-byte present.', valueDescriptions=[(0b0, 'No data byte'), (0b1, 'I3CIBIMDB valid')]))
	r.AddBitField(BitField(name='I3CIBIACKED', msb=17, accessibility='r', description='IBI ACK result.', valueDescriptions=[(0b0, 'NACKed'), (0b1, 'ACKed')]))
	r.AddBitField(BitField(msb=31, lsb=18, unused=True))
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

	# NFCxCR (slot 0) -- control (reset 0 except NFCAUTOREAD = 1)
	r = RegisterTemplate(nameTemplate='NFCxCR', registerMemorySlot=0, description='NFC control register. Enables the protocol core, arms the tag to respond, selects the auto-answer path, and holds the interrupt enables and the carrier-division note. Resets to 0 except NFCAUTOREAD, which resets to 1. Program the identity and timing registers before setting NFCEN.', size=32)
	nfc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='NFCEN', msb=0, accessibility='rw', description='NFC enable. When 0 the rf_clk protocol core is held in reset; it does NOT wipe the UID, CFG, payload window, or status flags (disable-preserves-data rule). Set to 1 to run the tag engine.', valueDescriptions=[(0b0, 'Disabled (protocol core in reset)'), (0b1, 'Enabled')]))
	r.AddBitField(BitField(name='NFCLISTEN', msb=1, accessibility='rw', description='Listen arm. When set, the tag responds to reader commands once a field is present; when clear, the tag stays deaf even in a field.', valueDescriptions=[(0b0, 'Deaf (no response)'), (0b1, 'Armed to respond')]))
	r.AddBitField(BitField(name='NFCHALTCLR', msb=2, accessibility='rw', description='Halt-clear pulse. Writing 1 forces the transaction FSM from the HALT state back to IDLE (a self-clearing, write-1-style event pulse); it reads 0.', valueDescriptions=[(0b0, 'No action'), (0b1, 'Force HALT to IDLE')]))
	r.AddBitField(BitField(msb=7, lsb=3, unused=True))
	r.AddBitField(BitField(name='NFCFIELDIE', msb=8, accessibility='rw', description='Field-detect interrupt enable. When set, the NFCFIELDF flag drives interrupt vector 94.', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='NFCRXFIE', msb=9, accessibility='rw', description='Frame-received interrupt enable. When set, the NFCRXFRAMEF flag drives interrupt vector 95.', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='NFCTXIE', msb=10, accessibility='rw', description='Transmit-done interrupt enable. When set, the NFCTXDONEF flag drives interrupt vector 96.', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='NFCCRCIE', msb=11, accessibility='rw', description='CRC / parity-error interrupt enable. When set, an RX CRC or parity error (NFCCRCERRF or NFCPARERRF) drives interrupt vector 97.', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='NFCAUTOREAD', msb=12, accessibility='rw', description='Auto-answer READ path (resets to 1). When set, hardware answers a Type-2 READ command directly from the payload window without firmware intervention. When clear, standard frames are surfaced to firmware through NFCxRXST and the RX buffer for a firmware-composed response.', valueDescriptions=[(0b0, 'Firmware-handled reads'), (0b1, 'Hardware auto-answer')]))
	r.AddBitField(BitField(msb=15, lsb=13, unused=True))
	r.AddBitField(BitField(name='NFCRFDIV', msb=19, lsb=16, accessibility='rw', description='Carrier-division note. Documents the assumed division from the 13.56 MHz carrier to rf_clk (informational; the off-die AFE supplies rf_clk).'))
	r.AddBitField(BitField(msb=31, lsb=20, unused=True))

	# NFCxSR (slot 1) -- status (W1C flags + read-only live bits, pre-latched)
	r = RegisterTemplate(nameTemplate='NFCxSR', registerMemorySlot=1, description='NFC status register. NFCBUSY, NFCFIELDLIVE, NFCHALTED, and NFCSTATE are read-only live status; the five event flags (bits 1-5) are write-1-to-clear (write a 1 to a bit to clear it; writing 0 leaves it unchanged). The volatile bits are captured by the registered pre-latch read.', size=32)
	nfc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='NFCBUSY', msb=0, accessibility='r', description='Busy. Reads 1 while a reader frame is being received or a tag response is in flight.', valueDescriptions=[(0b0, 'Idle'), (0b1, 'RX or TX in progress')]))
	r.AddBitField(BitField(name='NFCFIELDF', msb=1, accessibility='rw1', description='Field-detect flag. Set on a synchronized rising edge of the RF field-present input; drives vector 94 when NFCFIELDIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'RF field detected')]))
	r.AddBitField(BitField(name='NFCRXFRAMEF', msb=2, accessibility='rw1', description='Reader-frame-received flag. Set when a reader frame has landed for firmware (its CRC / parity result is summarized in NFCxRXST); drives vector 95 when NFCRXFIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Reader frame received')]))
	r.AddBitField(BitField(name='NFCTXDONEF', msb=3, accessibility='rw1', description='Transmit-done flag. Set when the tag response end-of-frame has been sent; drives vector 96 when NFCTXIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Tag response sent')]))
	r.AddBitField(BitField(name='NFCCRCERRF', msb=4, accessibility='rw1', description='RX CRC-error flag. Set when a received frame fails the CRC_A check; drives vector 97 when NFCCRCIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'RX CRC error')]))
	r.AddBitField(BitField(name='NFCPARERRF', msb=5, accessibility='rw1', description='RX parity-error flag. Set when a received frame fails an odd-parity check; drives vector 97 (folded with NFCCRCERRF) when NFCCRCIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'RX parity error')]))
	r.AddBitField(BitField(name='NFCFIELDLIVE', msb=6, accessibility='r', description='Field-live level. The synchronized RF field-present level (1 while a reader field is on the tag).', valueDescriptions=[(0b0, 'No field'), (0b1, 'Field present')]))
	r.AddBitField(BitField(name='NFCHALTED', msb=7, accessibility='r', description='Halted. Reads 1 while the transaction FSM is in the HALT state (the tag has been HLTA / halted by the reader).', valueDescriptions=[(0b0, 'Not halted'), (0b1, 'FSM halted')]))
	r.AddBitField(BitField(name='NFCSTATE', msb=11, lsb=8, accessibility='r', description='Transaction FSM state: 0 = POWER_OFF, 1 = IDLE, 2 = READY, 3 = ACTIVE, 4 = HALT.'))
	r.AddBitField(BitField(msb=31, lsb=12, unused=True))

	# NFCxUID (slot 2) -- provisioned tag UID
	r = RegisterTemplate(nameTemplate='NFCxUID', registerMemorySlot=2, description='Provisioned single-size 4-byte tag UID, used by bit-frame anticollision. Byte order on air is UID byte 0 first: UID[7:0] is the first byte, UID[31:24] the last. Hardware derives the BCC check byte. Latched transaction-locally at the start of each transaction.', size=32)
	nfc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='NFCUID', msb=31, lsb=0, accessibility='rw', description='4-byte UID (UID0 in bits 7:0, first on air).'))

	# NFCxCFG (slot 3) -- ATQA / SAK identity
	r = RegisterTemplate(nameTemplate='NFCxCFG', registerMemorySlot=3, description='Tag identity response configuration: the ATQA answer-to-request word and the SAK select-acknowledge byte. Latched transaction-locally.', size=32)
	nfc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='NFCATQA', msb=15, lsb=0, accessibility='rw', description='Answer To Request, Type A (resets to 0x0044). Bits 7:0 are the first byte on air.'))
	r.AddBitField(BitField(name='NFCSAK', msb=23, lsb=16, accessibility='rw', description='Select Acknowledge byte (resets to 0x00) returned after the final anticollision level.'))
	r.AddBitField(BitField(msb=31, lsb=24, unused=True))

	# NFCxTIM (slot 4) -- protocol timing divisors (real-grid resets)
	r = RegisterTemplate(nameTemplate='NFCxTIM', registerMemorySlot=4, description='Protocol timing divisors, all in rf_clk ticks, latched transaction-locally so a mid-count reload never glitches. The reset values are the real 13.56 MHz grid; a bench compresses all three for fast simulation.', size=32)
	nfc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='NFCFDT', msb=15, lsb=0, accessibility='rw', description='Frame Delay Time, in rf_clk ticks (resets to approximately 1236, the ISO 14443A tag response grid). The composed response is released when the FDT down-counter reaches zero.'))
	r.AddBitField(BitField(name='NFCETU', msb=23, lsb=16, accessibility='rw', description='Elementary Time Unit (bit period), in rf_clk ticks (resets to 128).'))
	r.AddBitField(BitField(name='NFCSUBCDIV', msb=31, lsb=24, accessibility='rw', description='Subcarrier half-period, in rf_clk ticks (resets to 8, giving the fc/16 load-modulation subcarrier).'))

	# NFCxRXST (slot 5) -- RX inspection (firmware-handled frames; no side effects)
	r = RegisterTemplate(nameTemplate='NFCxRXST', registerMemorySlot=5, description='Received-frame inspection, for firmware-handled frames (NFCAUTOREAD = 0 or an unrecognized command). Read side-effect-free; the frame byte payload is read separately through the indexed RX buffer (NFCxIDX / NFCxDATA with NFCIDXSEL = 1). Pre-latched.', size=32)
	nfc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='NFCCMD', msb=7, lsb=0, accessibility='r', description='Command byte: the first byte of the last received standard frame.'))
	r.AddBitField(BitField(name='NFCRXLEN', msb=15, lsb=8, accessibility='r', description='Received length in bytes, including the CRC.'))
	r.AddBitField(BitField(name='NFCRXCRCOK', msb=16, accessibility='r', description='CRC OK for the last received frame.', valueDescriptions=[(0b0, 'CRC bad'), (0b1, 'CRC good')]))
	r.AddBitField(BitField(name='NFCRXPAROK', msb=17, accessibility='r', description='Parity OK for the last received frame.', valueDescriptions=[(0b0, 'Parity bad'), (0b1, 'Parity good')]))
	r.AddBitField(BitField(msb=31, lsb=18, unused=True))

	# NFCxIDX (slot 6) -- indexed-window pointer
	r = RegisterTemplate(nameTemplate='NFCxIDX', registerMemorySlot=6, description='Byte-index pointer into one of the two 64-byte windows accessed through NFCxDATA. The index persists across accesses; NFCIDXSEL selects which window. Mirrors the indexed-window idiom used by I3C\'s Device Address Table.', size=32)
	nfc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='NFCIDX', msb=5, lsb=0, accessibility='rw', description='Byte index (0 to 63) into the selected window.'))
	r.AddBitField(BitField(name='NFCIDXAINC', msb=6, accessibility='rw', description='Auto-increment. When set, NFCIDX increments after each NFCxDATA access (streaming).', valueDescriptions=[(0b0, 'Index held'), (0b1, 'Auto-increment after each access')]))
	r.AddBitField(BitField(msb=7, unused=True))
	r.AddBitField(BitField(name='NFCIDXSEL', msb=8, accessibility='rw', description='Window select for NFCxDATA.', valueDescriptions=[(0b0, 'Payload TX window (64 B, firmware-filled, HW-read)'), (0b1, 'RX frame buffer (64 B, HW-filled, firmware-read)')]))
	r.AddBitField(BitField(msb=31, lsb=9, unused=True))

	# NFCxDATA (slot 7) -- indexed-window data byte (no read side effects)
	r = RegisterTemplate(nameTemplate='NFCxDATA', registerMemorySlot=7, description='The byte at NFCIDX in the window selected by NFCIDXSEL. The payload TX window is read/write (firmware fills the record the reader collects; hardware reads it for the auto-answer READ); the RX frame buffer is read-only (hardware fills it from the reader frame; writes are ignored). Auto-increments per NFCIDXAINC. Pre-latched on read (no side effects).', size=32)
	nfc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='NFCDATA', msb=7, lsb=0, accessibility='rw', description='Window data byte at the current index.'))
	r.AddBitField(BitField(msb=31, lsb=8, unused=True))

	# NFCxTXCTL (slot 8) -- firmware response path (inert in the MVP)
	r = RegisterTemplate(nameTemplate='NFCxTXCTL', registerMemorySlot=8, description='Firmware-composed response control (used when NFCAUTOREAD = 0 or for a vendor command). INERT in this MVP (auto-answer is the default path); present in the frozen register map so the firmware-WRITE stage bolts on without a map change.', size=32)
	nfc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='NFCTXLEN', msb=7, lsb=0, accessibility='rw', description='Number of payload bytes to send from the payload TX window.'))
	r.AddBitField(BitField(name='NFCTXGO', msb=8, accessibility='rw', description='Launch a firmware-composed response (a lane-0 write is a held-level launch, suppressed unless the FSM is in ACTIVE and awaiting a firmware reply).', valueDescriptions=[(0b0, 'No launch'), (0b1, 'Send response')]))
	r.AddBitField(BitField(name='NFCTXAPPCRC', msb=9, accessibility='rw', description='Append CRC_A to the firmware-composed response.', valueDescriptions=[(0b0, 'No CRC appended'), (0b1, 'Append CRC_A')]))
	r.AddBitField(BitField(msb=31, lsb=10, unused=True))

	# NFCxDBG (slot 9) -- telemetry counters
	r = RegisterTemplate(nameTemplate='NFCxDBG', registerMemorySlot=9, description='Debug telemetry / bench cross-checks: frame counters. Read-only; resets to 0.', size=32)
	nfc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='NFCRXFRAMECNT', msb=15, lsb=0, accessibility='r', description='Received-frame count.'))
	r.AddBitField(BitField(name='NFCTXFRAMECNT', msb=31, lsb=16, accessibility='r', description='Transmitted-frame count.'))

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

	# RTC0CR (slot 0) -- control (reset 0)
	r = RegisterTemplate(nameTemplate='RTCxCR', registerMemorySlot=0, description='RTC control register. Enables the seconds/subsecond counter, the alarm compare, and the periodic-tick down-counter, and holds the two interrupt enables. The three enables cross into the LFXT domain as synchronized held levels; the interrupt enables stay in the bus/MCLK domain and gate the combined interrupt combinationally. Resets to 0. The reserved upper bits hold a future trim-enable field (RTC0TRIM, digital calibration, deferred).', size=32)
	rtc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='RTCEN', msb=0, accessibility='rw', description='Wall-clock enable. When set, the 47-bit {seconds, subsecond} counter advances on every LFXT edge; when clear the count is frozen (its value is preserved).', valueDescriptions=[(0b0, 'Counter frozen'), (0b1, 'Counting')]))
	r.AddBitField(BitField(name='RTCALMEN', msb=1, accessibility='rw', description='Alarm-compare enable. When set, the alarm engine compares the seconds counter against RTC0ALM and sets the alarm flag on the match; when clear no alarm event is generated.', valueDescriptions=[(0b0, 'Alarm disabled'), (0b1, 'Alarm enabled')]))
	r.AddBitField(BitField(name='RTCTICKEN', msb=2, accessibility='rw', description='Periodic-tick enable. When set, the independent subsecond down-counter reloaded from RTC0PER runs and sets the tick flag on each underflow; when clear no tick event is generated. The tick counter never disturbs the wall-clock prescaler.', valueDescriptions=[(0b0, 'Tick disabled'), (0b1, 'Tick enabled')]))
	r.AddBitField(BitField(name='RTCALMIE', msb=3, accessibility='rw', description='Alarm interrupt enable. When set, RTC0SR.ALMF drives the combined RTC interrupt (vector 114).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='RTCTICKIE', msb=4, accessibility='rw', description='Periodic-tick interrupt enable. When set, RTC0SR.TICKF drives the combined RTC interrupt (vector 114).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(msb=31, lsb=5, unused=True))

	# RTC0SEC (slot 1) -- seconds (coherent snapshot read; atomic set-time write)
	r = RegisterTemplate(nameTemplate='RTCxSEC', registerMemorySlot=1, description='Wall-clock seconds. READ returns a coherent double-buffered snapshot synchronized into the bus domain (up to ~1 LFXT period, ~30.5 us, behind the live count; no read side effects). WRITE stages the seconds value and atomically commits set-time {SEC, SUB} into the LFXT domain through the SR.SYNC handshake (write SUB first if subseconds are also being set); the loaded value takes priority over the increment on the applying LFXT edge.', size=32)
	rtc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='RTCSEC', msb=31, lsb=0, accessibility='rw', description='Seconds counter (0 to 2^32-1).'))

	# RTC0SUB (slot 2) -- subsecond prescaler
	r = RegisterTemplate(nameTemplate='RTCxSUB', registerMemorySlot=2, description='Subsecond prescaler, 0 to 32767 (2^15 - 1). READ returns the coherent snapshot from the SAME instant as RTC0SEC (D7). WRITE only STAGES the subsecond value; it is committed by the following RTC0SEC write (to set subseconds alone, write SUB then SEC).', size=32)
	rtc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='RTCSUB', msb=14, lsb=0, accessibility='rw', description='Subsecond prescaler count (0 to 32767); wraps at 32768, carrying seconds by exactly one (exact 1 Hz).'))
	r.AddBitField(BitField(msb=31, lsb=15, unused=True))

	# RTC0ALM (slot 3) -- alarm compare (seconds, one-shot)
	r = RegisterTemplate(nameTemplate='RTCxALM', registerMemorySlot=3, description='Alarm compare value, in seconds. The alarm flag (RTC0SR.ALMF) sets once when the seconds counter first equals this value (one-shot, full 32-bit equality); re-arm by writing a new value past the current second. READ returns the last written value (bus-domain staging readback, no CDC). WRITE stages and commits the new compare through the SR.SYNC handshake.', size=32)
	rtc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='RTCALM', msb=31, lsb=0, accessibility='rw', description='Alarm seconds compare value.'))

	# RTC0PER (slot 4) -- periodic reload (subsecond ticks, 16-bit, A4)
	r = RegisterTemplate(nameTemplate='RTCxPER', registerMemorySlot=4, description='Periodic-tick reload, in subsecond (LFXT) ticks: a tick event fires every reload+1 LFXT ticks (~2 s max interval at 32.768 kHz, adjudication A4). READ returns the last written value (bus-domain staging readback). WRITE stages and commits the new reload through the SR.SYNC handshake.', size=32)
	rtc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='RTCPER', msb=15, lsb=0, accessibility='rw', description='Periodic-tick reload in LFXT ticks (0 to 65535).'))
	r.AddBitField(BitField(msb=31, lsb=16, unused=True))

	# RTC0SR (slot 5) -- status (busy level + W1C event flags)
	r = RegisterTemplate(nameTemplate='RTCxSR', registerMemorySlot=5, description='RTC status register. SYNC is read-only; the two event flags (ALMF, TICKF) are write-1-to-clear (write a 1 to a bit to clear it; writing 0 leaves it unchanged) and are never cleared by a read. The combined RTC interrupt (vector 114) is (ALMF and RTCALMIE) or (TICKF and RTCTICKIE).', size=32)
	rtc.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='RTCSYNC', msb=0, accessibility='r', description='Sync/busy. Reads 1 while a set-time / alarm / period commit is still crossing into the LFXT domain; software must poll this 0 before the next committing write (single outstanding commit).', valueDescriptions=[(0b0, 'Idle (safe to commit)'), (0b1, 'Commit in flight')]))
	r.AddBitField(BitField(name='RTCALMF', msb=1, accessibility='rw1', description='Alarm flag. Set once when the seconds counter first matches RTC0ALM (one-shot); drives vector 114 when RTCALMIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Alarm fired')]))
	r.AddBitField(BitField(name='RTCTICKF', msb=2, accessibility='rw1', description='Periodic-tick flag. Set on each periodic-tick underflow; drives vector 114 when RTCTICKIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Tick fired')]))
	r.AddBitField(BitField(msb=31, lsb=3, unused=True))

	# RTC0TRIM (slot 6) -- reserved (digital calibration deferred, D16)
	r = RegisterTemplate(nameTemplate='RTCxTRIM', registerMemorySlot=6, description='Reserved for digital fractional-prescaler / ppm calibration (deferred). Reads 0, writes ignored. The slot and the RTC0CR trim-enable field are reserved so calibration bolts on without a register-map break.', size=32)
	rtc.AddRegisterTemplate(r)
	r.AddBitField(BitField(msb=31, lsb=0, unused=True))

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

	# PWM0CR (slot 0) -- control (reset 0)
	r = RegisterTemplate(nameTemplate='PWMxCR', registerMemorySlot=0, description='PWM control register. Enables the prescaler + main counter (PWMEN) and each channel output (CH0EN/CH1EN), holds the two interrupt enables (PEVIE/FLTIE), the fault-system enable (FLTEN) and the write-1 software fault trip (FLTTRIG), and the 4-bit prescaler (PSC, divide by 2^PSC). Resets to 0 (disabled, outputs safe). The reserved bits are provisioned for the 4-channel (CH2EN/CH3EN), center-aligned (CNTMODE), deadtime (DTEN) and HW-fault-polarity (FLTPOL) bolt-ons.', size=32)
	pwm.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='PWMEN', msb=0, accessibility='rw', description='Master enable. When set, the prescaler and 16-bit main counter run; when clear the counter holds at 0 (clean restart on enable) and both outputs drive their safe levels.', valueDescriptions=[(0b0, 'Disabled (counter held, outputs safe)'), (0b1, 'Running')]))
	r.AddBitField(BitField(name='CH0EN', msb=1, accessibility='rw', description='Channel 0 output enable. When clear, CH0 drives its absolute safe level (POL.SAFE0) regardless of the waveform.', valueDescriptions=[(0b0, 'CH0 drives safe level'), (0b1, 'CH0 drives the waveform')]))
	r.AddBitField(BitField(name='CH1EN', msb=2, accessibility='rw', description='Channel 1 output enable. When clear, CH1 drives its absolute safe level (POL.SAFE1) regardless of the waveform.', valueDescriptions=[(0b0, 'CH1 drives safe level'), (0b1, 'CH1 drives the waveform')]))
	r.AddBitField(BitField(msb=6, lsb=3, unused=True))	# CH2EN[3]/CH3EN[4] (4-ch), CNTMODE[5] (center-aligned), DTEN[6] (deadtime) — D16/D19 reserved
	r.AddBitField(BitField(name='PEVIE', msb=7, accessibility='rw', description='Period-event interrupt enable. When set, SR.PEVF drives the PWM0_EVT interrupt (vector 116).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='FLTIE', msb=8, accessibility='rw', description='Fault interrupt enable. When set, SR.FLTF drives the PWM0_FAULT interrupt (vector 115).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(msb=11, lsb=9, unused=True))
	r.AddBitField(BitField(name='FLTEN', msb=12, accessibility='rw', description='Fault-system enable. Gates the software trip: a FLTTRIG write latches SR.FLTF only while FLTEN is set; with FLTEN clear the FLTTRIG write is ignored.', valueDescriptions=[(0b0, 'Fault system disabled (FLTTRIG ignored)'), (0b1, 'Fault system enabled')]))
	r.AddBitField(BitField(msb=13, lsb=13, unused=True))	# FLTPOL[13] — HW fault-pin polarity, respin bolt-on (D16) reserved
	r.AddBitField(BitField(name='FLTTRIG', msb=14, accessibility='w1', description='Software fault trip (write-1 self-clearing command; reads 0). Writing 1 requests a trip: while FLTEN is set it latches SR.FLTF and forces both outputs safe within one clock. Re-arm by write-1-clearing SR.FLTF.', valueDescriptions=[(0b1, 'Trip the fault (if FLTEN set)')]))
	r.AddBitField(BitField(msb=15, lsb=15, unused=True))
	r.AddBitField(BitField(name='PSC', msb=19, lsb=16, accessibility='rw', description='Prescaler: the main counter advances once every 2^PSC MCLK cycles (PSC=0 -> every cycle). Frequency = f_MCLK / 2^PSC / (PER+1).'))
	r.AddBitField(BitField(msb=31, lsb=20, unused=True))

	# PWM0PER (slot 1) -- period modulus (BUFFERED)
	r = RegisterTemplate(nameTemplate='PWMxPER', registerMemorySlot=1, description='PWM period modulus (buffered, D9). The waveform period is (PER+1) prescale ticks: frequency = f_MCLK / 2^PSC / (PER+1). READ returns the last written value (bus-domain staging readback, no side effects). WRITE stages the value and arms SR.UPDF; it commits to the live waveform at the next period boundary (glitch-free).', size=32)
	pwm.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='PWMPER', msb=15, lsb=0, accessibility='rw', description='Period modulus (0 to 65535); the counter wraps 0..PER, so the period is PER+1 ticks.'))
	r.AddBitField(BitField(msb=31, lsb=16, unused=True))

	# PWM0DTY0 (slot 2) -- CH0 duty (BUFFERED)
	r = RegisterTemplate(nameTemplate='PWMxDTY0', registerMemorySlot=2, description='Channel 0 duty compare (buffered, D9). CH0 is active for the first DTY0 prescale ticks of each period (DTY0=0 -> constant inactive; DTY0 >= PER+1 -> constant active). READ returns the staging value; WRITE stages and arms SR.UPDF (commits at the next period boundary).', size=32)
	pwm.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='PWMDTY0', msb=15, lsb=0, accessibility='rw', description='Channel 0 duty compare (0 to 65535).'))
	r.AddBitField(BitField(msb=31, lsb=16, unused=True))

	# PWM0DTY1 (slot 3) -- CH1 duty (BUFFERED)
	r = RegisterTemplate(nameTemplate='PWMxDTY1', registerMemorySlot=3, description='Channel 1 duty compare (buffered, D9). CH1 is active for the first DTY1 prescale ticks of each period (same corner rules as DTY0). READ returns the staging value; WRITE stages and arms SR.UPDF (commits at the next period boundary).', size=32)
	pwm.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='PWMDTY1', msb=15, lsb=0, accessibility='rw', description='Channel 1 duty compare (0 to 65535).'))
	r.AddBitField(BitField(msb=31, lsb=16, unused=True))

	# PWM0DTY2 (slot 4) -- reserved (4-channel bolt-on, D16)
	r = RegisterTemplate(nameTemplate='PWMxDTY2', registerMemorySlot=4, description='Reserved for the channel 2 duty compare (4-channel bolt-on, D16). Reads 0, writes ignored — provisioned so >2 channels bolt on without a register-map break.', size=32)
	pwm.AddRegisterTemplate(r)
	r.AddBitField(BitField(msb=31, lsb=0, unused=True))

	# PWM0DTY3 (slot 5) -- reserved (4-channel bolt-on, D16)
	r = RegisterTemplate(nameTemplate='PWMxDTY3', registerMemorySlot=5, description='Reserved for the channel 3 duty compare (4-channel bolt-on, D16). Reads 0, writes ignored.', size=32)
	pwm.AddRegisterTemplate(r)
	r.AddBitField(BitField(msb=31, lsb=0, unused=True))

	# PWM0POL (slot 6) -- polarity + absolute safe level (immediate, NOT buffered, D11)
	r = RegisterTemplate(nameTemplate='PWMxPOL', registerMemorySlot=6, description='Per-channel polarity and absolute safe/off level (immediate, NOT buffered, D11; program before enabling). POLn inverts the channel waveform; SAFEn is the ABSOLUTE pin level (0 = drive low, 1 = drive high) forced when the channel is disabled or faulted — polarity-independent, so the fault/idle physical state is deterministic. Resets to 0 (active-high, safe = low). The reserved bits hold the CH2/CH3 polarity and safe fields (4-channel bolt-on, D16).', size=32)
	pwm.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='POL0', msb=0, accessibility='rw', description='Channel 0 polarity.', valueDescriptions=[(0b0, 'Active-high'), (0b1, 'Active-low (invert)')]))
	r.AddBitField(BitField(name='POL1', msb=1, accessibility='rw', description='Channel 1 polarity.', valueDescriptions=[(0b0, 'Active-high'), (0b1, 'Active-low (invert)')]))
	r.AddBitField(BitField(msb=3, lsb=2, unused=True))	# CH2/CH3 polarity (4-ch bolt-on, D16) reserved
	r.AddBitField(BitField(name='SAFE0', msb=4, accessibility='rw', description='Channel 0 absolute safe/off pin level (driven when CH0 is disabled or faulted).', valueDescriptions=[(0b0, 'Drive low'), (0b1, 'Drive high')]))
	r.AddBitField(BitField(name='SAFE1', msb=5, accessibility='rw', description='Channel 1 absolute safe/off pin level (driven when CH1 is disabled or faulted).', valueDescriptions=[(0b0, 'Drive low'), (0b1, 'Drive high')]))
	r.AddBitField(BitField(msb=31, lsb=6, unused=True))	# CH2/CH3 safe (7:6, 4-ch bolt-on) + upper reserved

	# PWM0DT (slot 7) -- reserved (deadtime bolt-on, D16)
	r = RegisterTemplate(nameTemplate='PWMxDT', registerMemorySlot=7, description='Reserved for the deadtime value (deadtime / complementary-pair bolt-on, D16). Reads 0, writes ignored — provisioned so deadtime bolts on without a register-map break.', size=32)
	pwm.AddRegisterTemplate(r)
	r.AddBitField(BitField(msb=31, lsb=0, unused=True))

	# PWM0SR (slot 8) -- status (sticky W1C flags + read-only UPDF)
	r = RegisterTemplate(nameTemplate='PWMxSR', registerMemorySlot=8, description='PWM status register. FLTF and PEVF are sticky write-1-to-clear event flags (write a 1 to a bit to clear it; writing 0 leaves it unchanged; never cleared by a read; a set arriving the same cycle as a clear survives). UPDF is read-only. PWM0_FAULT (vector 115) = FLTF and CR.FLTIE; PWM0_EVT (vector 116) = PEVF and CR.PEVIE (both combinational). The reserved DIR bit is the center-aligned count direction (D19).', size=32)
	pwm.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='FLTF', msb=0, accessibility='rw1', description='Fault flag. Set when a FLTTRIG trip is accepted (FLTEN set); while set both outputs are forced to their safe levels. Write 1 to clear (re-arm).', valueDescriptions=[(0b0, 'No fault'), (0b1, 'Fault latched (outputs safe)')]))
	r.AddBitField(BitField(name='PEVF', msb=1, accessibility='rw1', description='Period-event flag. Set at every active period boundary. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Period event')]))
	r.AddBitField(BitField(name='UPDF', msb=2, accessibility='r', description='Buffered-update pending. Reads 1 from a staged PER/DTY0/DTY1 write until that write has been absorbed at the next period boundary.', valueDescriptions=[(0b0, 'Staging absorbed'), (0b1, 'Commit pending')]))
	r.AddBitField(BitField(msb=31, lsb=3, unused=True))	# DIR[3] (center-aligned direction, D19) + upper reserved

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
	ow = PeripheralTemplate(nameTemplate='OWx', description='1-Wire Master: a Dallas/Maxim 1-Wire link-layer controller that runs the five microsecond-scale bus primitives in hardware — reset+presence, write-bit, read-bit, write-byte and read-byte — off a programmable time base, leaving ROM search and CRC-8 to firmware over those primitives. It is master-only and supports both standard and overdrive speeds (selected by CR.ODS, latched at each transaction launch). A transaction is described by the control and command registers and LAUNCHED by a byte-lane-0 write to OW0CMD (the launch is suppressed while the master is disabled or busy); the registered read path returns status and the received byte with no read side effects. The whole engine — the OW0DIV counter-compare time base, the slot state machine, the two-flop DQ synchronizer, the sticky write-1-to-clear status flags, and the interrupt combiner — rides the free-running MCLK, so the tick base is immune to clock reconfiguration and unlike the SMCLK peripherals a driver must NOT write SYS_CLK_CR to 0. One combined interrupt (transaction-complete or error) is delivered on the router at vector 117. The block has one open-drain DQ pin; the strong-pullup enable and its register slot are a reserved stub (no driven-high phase this stage).', registerPrefix='OWx', bitFieldPrefix='OW', latexIntroFileName='OneWire-intro-castalia-2026-07.tex', latexFeatureSummary='{count} 1-Wire master (reset/presence + bit/byte primitives, standard + overdrive, firmware ROM search + CRC-8, single combined IRQ)')
	m.AddPeripheralTemplate(ow)

	# OW0CR (slot 0) -- control (reset 0)
	r = RegisterTemplate(nameTemplate='OWxCR', registerMemorySlot=0, description='1-Wire control register. Enables the master (OWEN), selects the bus speed (ODS: standard or overdrive, latched into the transaction descriptor at launch so a mid-flight change never glitches a running slot), holds the transaction-complete and error interrupt enables (TCIE, ERRIE), and carries the reserved strong-pullup enable stub (SPUEN, no effect this stage). Resets to 0 (master idle). The reserved upper bits reserve a future strong-pullup window and timing fields.', size=32)
	ow.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='OWEN', msb=0, accessibility='rw', description='Master enable. When 0 the slot FSM is held idle and an OW0CMD launch is suppressed (the descriptor is still captured); RX and the status flags are preserved. Set to 1 to run transactions.', valueDescriptions=[(0b0, 'Disabled (FSM idle, launch suppressed)'), (0b1, 'Enabled')]))
	r.AddBitField(BitField(name='OWODS', msb=1, accessibility='rw', description='Overdrive speed select, latched into the transaction descriptor at launch. 0 selects the standard slot-timing set, 1 the overdrive (~10x faster) set. (Named ODS; supersedes the spec sketch ODEN, adjudication A2.)', valueDescriptions=[(0b0, 'Standard speed'), (0b1, 'Overdrive speed')]))
	r.AddBitField(BitField(name='OWSPUEN', msb=2, accessibility='rw', description='Strong-pullup enable (reserved stub, D15). Writable but inert this stage: there is no driven-high strong-pullup phase (DQ is open-drain, never driven high). Reserved so a future parasite-power SPU bolts on without a register-map break.', valueDescriptions=[(0b0, 'No effect'), (0b1, 'No effect (reserved)')]))
	r.AddBitField(BitField(name='OWTCIE', msb=3, accessibility='rw', description='Transaction-complete interrupt enable. When set, OW0SR.TCIF drives the combined 1-Wire interrupt (vector 117).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='OWERRIE', msb=4, accessibility='rw', description='Error interrupt enable. When set, OW0SR.NOPRES or OW0SR.SHORT drives the combined 1-Wire interrupt (vector 117).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(msb=31, lsb=5, unused=True))

	# OW0CMD (slot 1) -- command (LANE-0 WRITE LAUNCHES, D8)
	r = RegisterTemplate(nameTemplate='OWxCMD', registerMemorySlot=1, description='1-Wire command register. A byte-lane-0 write LAUNCHES a transaction (D8): it always captures {OP, BITVAL, current ODS, current OW0TX byte} into the launch descriptor, and starts the slot FSM unless OWEN=0 or the master is busy (in which case the content is captured but no bus activity or completion occurs). OP selects the primitive (reset / write-bit / read-bit / write-byte / read-byte); BITVAL is the write-bit value. A read returns the last-written OP and BITVAL. Bytes are transmitted/received LSB-first.', size=32)
	ow.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='OWOP', msb=2, lsb=0, accessibility='rw', description='Operation: 000 = reset+presence, 001 = write-bit, 010 = read-bit, 011 = write-byte (OW0TX, LSB-first), 100 = read-byte (into OW0RX, LSB-first); 101-111 reserved (no bus activity, no launch).'))
	r.AddBitField(BitField(msb=7, lsb=3, unused=True))
	r.AddBitField(BitField(name='OWBITVAL', msb=8, accessibility='rw', description='Write-bit value for OP = write-bit (latched at launch; ignored by the other operations).', valueDescriptions=[(0b0, 'Write a 0 bit'), (0b1, 'Write a 1 bit')]))
	r.AddBitField(BitField(msb=31, lsb=9, unused=True))

	# OW0TX (slot 2) -- next write byte (NEVER launches, D8)
	r = RegisterTemplate(nameTemplate='OWxTX', registerMemorySlot=2, description='Next write byte, the write-byte (OP = 011) source, transmitted LSB-first. Writing this register never launches a transaction (D8); the byte is sampled into the descriptor at the next OW0CMD launch.', size=32)
	ow.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='OWTX', msb=7, lsb=0, accessibility='rw', description='Write byte (0 to 255).'))
	r.AddBitField(BitField(msb=31, lsb=8, unused=True))

	# OW0RX (slot 3) -- last received byte / bit (read-only, side-effect-free, A3)
	r = RegisterTemplate(nameTemplate='OWxRX', registerMemorySlot=3, description='Last received data (read-only, side-effect-free, A3): a read-byte (OP = 100) assembles into [7:0] LSB-first; a read-bit (OP = 010) lands in [0]. Reset-cleared to 0; a read never clears or launches anything.', size=32)
	ow.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='OWRX', msb=7, lsb=0, accessibility='r', description='Received byte (read-byte) or received bit in [0] (read-bit).'))
	r.AddBitField(BitField(msb=31, lsb=8, unused=True))

	# OW0DIV (slot 4) -- time-base divisor (D6/A1)
	r = RegisterTemplate(nameTemplate='OWxDIV', registerMemorySlot=4, description='Time-base divisor. The slot FSM counts ticks; one tick is (OW0DIV + 1) MCLK cycles. Program OW0DIV = 11 for a 0.5 microsecond tick at 24 MHz MCLK (adjudication A1: all slot counts are integer half-microsecond ticks); a bench uses a small divisor to compress simulation time. Resets to 0.', size=32)
	ow.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='OWDIV', msb=15, lsb=0, accessibility='rw', description='Time-base divisor (0 to 65535); tick period = OW0DIV + 1 MCLK cycles.'))
	r.AddBitField(BitField(msb=31, lsb=16, unused=True))

	# OW0SR (slot 5) -- status (BUSY/PRES read-only + W1C error/complete flags, D12)
	r = RegisterTemplate(nameTemplate='OWxSR', registerMemorySlot=5, description='1-Wire status register. BUSY and PRES are read-only levels; TCIF, NOPRES and SHORT are sticky write-1-to-clear flags (write a 1 to a bit to clear it; writing 0 leaves it unchanged; never cleared by a read; a set arriving the same cycle as a clear survives). BUSY covers the launch instant (it reads 1 the same cycle as the launching OW0CMD write, A6), so firmware may poll BUSY-clear immediately after CMD; observe the single-outstanding-transaction rule (poll BUSY before the next CMD). The combined interrupt (vector 117) is (TCIF and TCIE) or ((NOPRES or SHORT) and ERRIE). On a stuck-low bus SHORT wins and NOPRES is suppressed (A5).', size=32)
	ow.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='OWBUSY', msb=0, accessibility='r', description='Transaction in progress. An OW0CMD launch is ignored while set. Reads 1 from the cycle of the launching write until completion (A6).', valueDescriptions=[(0b0, 'Idle'), (0b1, 'Busy')]))
	r.AddBitField(BitField(name='OWTCIF', msb=1, accessibility='rw1', description='Transaction-complete flag. Set when the current transaction finishes; drives vector 117 when TCIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Transaction complete')]))
	r.AddBitField(BitField(name='OWPRES', msb=2, accessibility='r', description='Presence detected. Set when a device answered the last reset with a presence pulse (updated per reset transaction).', valueDescriptions=[(0b0, 'No device / not yet reset'), (0b1, 'Device present')]))
	r.AddBitField(BitField(name='OWNOPRES', msb=3, accessibility='rw1', description='No-presence error. Set when the last reset saw no presence pulse (clean high release, no device); suppressed if SHORT sets on the same reset (A5). Drives vector 117 when ERRIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No error'), (0b1, 'No presence pulse')]))
	r.AddBitField(BitField(name='OWSHORT', msb=4, accessibility='rw1', description='Bus-short error. Set when DQ is still low at the end of a recovery window (bus stuck/short) after the master has released it. On a reset, SHORT wins over NOPRES (A5). Drives vector 117 when ERRIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No error'), (0b1, 'Bus stuck low')]))
	r.AddBitField(BitField(msb=31, lsb=5, unused=True))

	# OW0SPU (slot 6) -- reserved strong-pullup stub (D15)
	r = RegisterTemplate(nameTemplate='OWxSPU', registerMemorySlot=6, description='Reserved for the strong-pullup / parasite-power stage (D15). Reads 0, writes ignored. The slot and the OW0CR.SPUEN field are reserved so a future driven-high strong-pullup (with its bounded firmware-armed safety window) bolts on without a register-map break.', size=32)
	ow.AddRegisterTemplate(r)
	r.AddBitField(BitField(msb=31, lsb=0, unused=True))

# digperiphs (2026-07-22): I2CT0 register template (design doc D5 bit maps, 5 live word
# slots @0x6A00: I2CTCR / I2CTSR / I2CTTX / I2CTRX / I2CTWDG). Added only when
# i2ctargetPresent CreatePeripheral()s it; with I2CT0 off it is never instanced
# (byte-identical default). Registered read on rising ClkMem (D4 — no bridge, no
# CAPTURE_CLOCK; the plain raw-strobe active-low en shim, RTC/PWM/OW precedent). W1C
# status flags, BUSY same-cycle status rule where applicable, RSVD reads 0 (slots >=5
# read 0). bitFieldPrefix I2CT.
if i2ctargetPresent:
	i2ct = PeripheralTemplate(nameTemplate='I2CTx', description='Hardware-Autonomous I2C Target: an I2C slave engine that handles the protocol in hardware — 7-bit address match with a wildcard mask and optional general-call response, byte-at-a-time receive and transmit with ready/empty status, hardware clock stretching for lossless flow control, START / STOP / repeated-START / NACK framing detection, and a configurable stuck-SCL watchdog. The whole engine — the two-flop SDA/SCL synchronizers, the edge/framing detectors, the address matcher, the RX/TX byte paths, the clock-stretch driver, the sticky write-1-to-clear status flags, and the two interrupt combiners — rides the free-running MCLK, so its timing is immune to clock reconfiguration and unlike the SMCLK I2C0/I2C1 cores a driver need not write SYS_CLK_CR to 0 for the target itself. Two combined interrupts are delivered on the router: vector 122 (address/error) and vector 123 (tx-ready/rx-full). It is complementary to the software-serviced slave-mode registers of I2C0/I2C1: I2CT0 shares the same open-drain SDA0/SCL0 pads through a wired-AND merge and needs no per-byte firmware bit-banging. The guaranteed bus-speed floor is f_SCL <= MCLK/24 (Standard 100 kHz and Fast 400 kHz at 24 MHz MCLK).', registerPrefix='I2CTx', bitFieldPrefix='I2CT', latexIntroFileName='I2CT-intro-castalia-2026-07.tex', latexFeatureSummary='{count} hardware-autonomous I2C target (7-bit address match + mask + general call, hardware clock stretching, START/STOP framing flags, single-byte RX/TX with ready/empty status, stuck-SCL watchdog, 2 combined IRQs)')
	m.AddPeripheralTemplate(i2ct)

	# I2CTCR (slot 0) -- control (reset 0)
	r = RegisterTemplate(nameTemplate='I2CTxCR', registerMemorySlot=0, description='I2C target control register. Enables the target (EN), the general-call response (GCEN), and hardware clock stretching (CSEN); holds the two interrupt enables (AEIE for the address/error IRQ at vector 122, DATAIE for the tx-ready/rx-full IRQ at vector 123); and carries the 7-bit target address (SAD) with a per-bit wildcard mask (SADM, a 1 makes that address bit dont-care). Resets to 0 (target idle, SDA/SCL released).', size=32)
	i2ct.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I2CTEN', msb=0, accessibility='rw', description='Target enable. When 0 the FSM is held idle with SDA/SCL released; the received byte and the status flags are preserved. Set to 1 to respond on the bus.', valueDescriptions=[(0b0, 'Disabled (FSM idle, bus released)'), (0b1, 'Enabled')]))
	r.AddBitField(BitField(name='I2CTGCEN', msb=1, accessibility='rw', description='General-call enable. When set, the target also matches the general-call address (0x00, write direction) and sets GCF alongside AMF.', valueDescriptions=[(0b0, 'General call ignored'), (0b1, 'General call answered')]))
	r.AddBitField(BitField(name='I2CTCSEN', msb=2, accessibility='rw', description='Clock-stretch enable. When set, the target holds SCL low after an ACK until firmware services the transfer (reads I2CTRX / writes I2CTTX) — lossless flow control. When 0 the target never stretches; firmware must service within one bit-time or accept an RX overrun / a stale 0xFF transmit byte.', valueDescriptions=[(0b0, 'No clock stretching'), (0b1, 'Clock stretching enabled')]))
	r.AddBitField(BitField(name='I2CTAEIE', msb=3, accessibility='rw', description='Address/error interrupt enable. When set, the OR of the address/error status flags (AMF, GCF, OVF, NACKF, STOPF, RSTARTF, ERRF) drives the combined interrupt at vector 122.', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='I2CTDATAIE', msb=4, accessibility='rw', description='Data interrupt enable. When set, the OR of RXF and TXE drives the combined interrupt at vector 123.', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(msb=7, lsb=5, unused=True))
	r.AddBitField(BitField(name='I2CTSAD', msb=14, lsb=8, accessibility='rw', description='7-bit target address matched against the incoming address byte (masked by SADM).'))
	r.AddBitField(BitField(msb=15, lsb=15, unused=True))
	r.AddBitField(BitField(name='I2CTSADM', msb=22, lsb=16, accessibility='rw', description='Address match mask: a 1 in a bit position makes the corresponding SAD address bit a wildcard (dont-care) during the match.'))
	r.AddBitField(BitField(msb=31, lsb=23, unused=True))

	# I2CTSR (slot 1) -- status (BUSY/TM/TXE read-only + W1C event flags, D5)
	r = RegisterTemplate(nameTemplate='I2CTxSR', registerMemorySlot=1, description='I2C target status register. BUSY, TM and TXE are read-only levels; AMF, GCF, RXF, OVF, NACKF, STOPF, RSTARTF and ERRF are sticky write-1-to-clear event flags (write a 1 to a bit to clear it; writing 0 leaves it unchanged; never cleared by a read; a set arriving the same cycle as a clear survives). The address/error interrupt (vector 122) is (AMF or GCF or OVF or NACKF or STOPF or RSTARTF or ERRF) and AEIE; the data interrupt (vector 123) is (RXF or TXE) and DATAIE.', size=32)
	i2ct.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I2CTBUSY', msb=0, accessibility='r', description='Bus busy: set on START, cleared on STOP or a watchdog abort. Distinguishes an initial START from a repeated-START.', valueDescriptions=[(0b0, 'Bus idle'), (0b1, 'Transaction in progress')]))
	r.AddBitField(BitField(name='I2CTTM', msb=1, accessibility='r', description='Transfer direction (latched R/W from the matched address). 1 = target-transmitter (host read); 0 = target-receiver (host write).', valueDescriptions=[(0b0, 'Target-receiver (host write)'), (0b1, 'Target-transmitter (host read)')]))
	r.AddBitField(BitField(name='I2CTAMF', msb=2, accessibility='rw1', description='Address-match flag: our address (masked) matched this transaction. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Address matched')]))
	r.AddBitField(BitField(name='I2CTGCF', msb=3, accessibility='rw1', description='General-call flag: the general-call address matched (set alongside AMF when GCEN is set). Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'General call matched')]))
	r.AddBitField(BitField(name='I2CTRXF', msb=4, accessibility='rw1', description='Receive-full flag: a received byte is available in I2CTRX. Read I2CTRX (side-effect-free) then write 1 here to free the buffer. Write 1 to clear.', valueDescriptions=[(0b0, 'Buffer empty'), (0b1, 'Byte available')]))
	r.AddBitField(BitField(name='I2CTTXE', msb=5, accessibility='r', description='Transmit-empty level: asserted while the target is in transmit mode and needs the next byte loaded into I2CTTX. Reads clear (0) in the same cycle as the I2CTTX write that loads a byte (BUSY-same-cycle rule).', valueDescriptions=[(0b0, 'Byte loaded / not transmitting'), (0b1, 'Load I2CTTX')]))
	r.AddBitField(BitField(name='I2CTOVF', msb=6, accessibility='rw1', description='Receive-overrun flag: a byte arrived while RXF was still set (previous byte unread); the target auto-NACKed and dropped the byte. Write 1 to clear.', valueDescriptions=[(0b0, 'No overrun'), (0b1, 'RX overrun')]))
	r.AddBitField(BitField(name='I2CTNACKF', msb=7, accessibility='rw1', description='NACK flag: the host NACKed a transmitted byte (normal read termination), or the target auto-NACKed a received byte on overrun (disambiguate with TM/OVF). Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'NACK handshake')]))
	r.AddBitField(BitField(name='I2CTSTOPF', msb=8, accessibility='rw1', description='STOP flag: a STOP condition was detected. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'STOP detected')]))
	r.AddBitField(BitField(name='I2CTRSTARTF', msb=9, accessibility='rw1', description='Repeated-START flag: a repeated-START was detected (START while BUSY); the target re-enters the address phase without dropping BUSY. Write 1 to clear.', valueDescriptions=[(0b0, 'No event'), (0b1, 'Repeated-START detected')]))
	r.AddBitField(BitField(name='I2CTERRF', msb=10, accessibility='rw1', description='Error flag: a protocol error or the SCL-low watchdog timeout (I2CTWDG). On expiry the transaction is aborted and BUSY drops. Write 1 to clear.', valueDescriptions=[(0b0, 'No error'), (0b1, 'Protocol error / watchdog timeout')]))
	r.AddBitField(BitField(msb=31, lsb=11, unused=True))

	# I2CTTX (slot 2) -- transmit byte (a lane-0 write loads the buffer, clears TXE, D10)
	r = RegisterTemplate(nameTemplate='I2CTxTX', registerMemorySlot=2, description='Transmit byte buffer. A byte-lane-0 write loads the next transmit byte and clears TXE (the loaded byte is shifted out MSB-first on the next host read). Reads back the last-written value.', size=32)
	i2ct.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I2CTTX', msb=7, lsb=0, accessibility='rw', description='Next transmit byte (0 to 255).'))
	r.AddBitField(BitField(msb=31, lsb=8, unused=True))

	# I2CTRX (slot 3) -- received byte (read-only, side-effect-free, D9)
	r = RegisterTemplate(nameTemplate='I2CTxRX', registerMemorySlot=3, description='Last received byte (read-only, side-effect-free, D9): the most recent host-written byte, valid while RXF is set. A read never clears RXF (write 1 to I2CTSR.RXF to free the buffer). Reset 0.', size=32)
	i2ct.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I2CTRX', msb=7, lsb=0, accessibility='r', description='Received byte.'))
	r.AddBitField(BitField(msb=31, lsb=8, unused=True))

	# I2CTWDG (slot 4) -- SCL-low watchdog timeout (0 = disabled, D13)
	r = RegisterTemplate(nameTemplate='I2CTxWDG', registerMemorySlot=4, description='SCL-low watchdog timeout. A counter increments while SCL is held low and the bus is busy; on reaching WDTO x 256 MCLK cycles it sets ERRF, aborts the transaction and drops BUSY. WDTO = 0 disables the watchdog (the reset value, so the default is off — identity-safe). The counter resets on every SCL rising edge and when not busy, so a healthy idle bus never trips it.', size=32)
	i2ct.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='I2CTWDTO', msb=15, lsb=0, accessibility='rw', description='SCL-low watchdog timeout in units of 256 MCLK cycles (0 to 65535); 0 disables the watchdog.'))
	r.AddBitField(BitField(msb=31, lsb=16, unused=True))

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

	# DMA0CR (slot 0) -- control (reset 0)
	r = RegisterTemplate(nameTemplate='DMAxCR', registerMemorySlot=0, description='DMA control register. Holds the master enable (DMAEN), the per-channel arm/launch and orderly-abort command strobes (CHnGO / CHnABORT, self-clearing, read 0), and the two interrupt enables (DONEIE / ERRIE). Resets to 0. A byte-lane-0 write setting CHnGO[n] captures the channel n {SRC,DST,LEN,CFG} into the working registers and launches it (the launch is suppressed while DMAEN=0 or channel n is already busy). CHnGO/CHnABORT bits for n >= NCH read 0 and ignore writes.', size=32)
	dma.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='DMAEN', msb=0, accessibility='rw', description='Master enable. When 0 all channels are held idle and every CHnGO launch is suppressed. Set to 1 before arming a channel.', valueDescriptions=[(0b0, 'Disabled'), (0b1, 'Enabled')]))
	r.AddBitField(BitField(name='DMAGO', msb=4, lsb=1, accessibility='rw', description='Per-channel arm+launch command (CHnGO[3:0], bit 1+n = channel n). Write 1 to a bit to capture that channel\'s programmed descriptor and start the transfer; self-clearing command (reads 0, D8). The launch is suppressed while DMAEN=0 or that channel is busy. Bits for n >= NCH read 0 / ignore writes.'))
	r.AddBitField(BitField(name='DMAABORT', msb=8, lsb=5, accessibility='rw', description='Per-channel orderly-abort command (CHnABORT[3:0], bit 5+n = channel n). Write 1 to request channel n stop; any in-flight arbiter transaction completes normally (the handshake is never truncated), then the channel\'s busy drops WITHOUT setting CHnDONE or CHnERR (abort is neither done nor error, D15). Self-clearing command (reads 0). Bits for n >= NCH read 0 / ignore writes.'))
	r.AddBitField(BitField(msb=11, lsb=9, unused=True))
	r.AddBitField(BitField(name='DMADONEIE', msb=12, accessibility='rw', description='Combined-done interrupt enable. When set, DMA0SR.CHnDONE (OR over channels) drives the DMA0_DONE interrupt (vector 118).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='DMAERRIE', msb=13, accessibility='rw', description='Error interrupt enable. When set, DMA0SR.CHnERR (OR over channels) drives the DMA0_ERR interrupt (vector 119).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(msb=31, lsb=14, unused=True))

	# DMA0SR (slot 1) -- status (BUSY level + W1C event flags + ACTIVECH)
	r = RegisterTemplate(nameTemplate='DMAxSR', registerMemorySlot=1, description='DMA status register. BUSY and ACTIVECH are read-only; CHnDONE and CHnERR are sticky write-1-to-clear event flags (write a 1 to a bit to clear it; writing 0 leaves it unchanged; never cleared by a read; a set arriving the same cycle as a clear survives). BUSY asserts the SAME cycle as the triggering CHnGO write (busy OR a GO pending, D8/D16), so a driver may write GO then immediately spin on BUSY. DMA0_DONE (vector 118) = (OR of CHnDONE) and CR.DONEIE; DMA0_ERR (vector 119) = (OR of CHnERR) and CR.ERRIE, both combinational. CHnDONE/CHnERR/ACTIVECH bits for n >= NCH read 0.', size=32)
	dma.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='DMABUSY', msb=0, accessibility='r', description='Any channel active OR a GO pending. Asserts the same cycle as the CHnGO write and stays high through real engine activity (no blind window, D8).', valueDescriptions=[(0b0, 'Idle'), (0b1, 'Busy')]))
	r.AddBitField(BitField(name='DMADONE', msb=4, lsb=1, accessibility='rw1', description='Per-channel done flags (CHnDONE[3:0], bit 1+n = channel n). Set when channel n reaches LEN=0 (clean completion); drives vector 118 when DONEIE is set. Write 1 to clear. Bits for n >= NCH read 0.'))
	r.AddBitField(BitField(name='DMAERR', msb=8, lsb=5, accessibility='rw1', description='Per-channel error flags (CHnERR[3:0], bit 5+n = channel n). Set on a deny-guard hit, LEN=0 at GO, misaligned/out-of-window/TCM-hole SRC or DST (D13/A18); drives vector 119 when ERRIE is set. Write 1 to clear. Bits for n >= NCH read 0.'))
	r.AddBitField(BitField(name='DMAACTIVECH', msb=11, lsb=9, accessibility='r', description='Index of the currently-serviced channel (0 when idle, engine-set, D16).'))
	r.AddBitField(BitField(msb=31, lsb=12, unused=True))

	# Slots 2..17 -- four fixed-stride per-channel {SRC,DST,LEN,CFG} blocks
	# (CH0 = slots 2-5, CH1 = 6-9, CH2 = 10-13, CH3 = 14-17). The register map
	# is the 4-channel superset; a 2-channel build reads 0 / ignores writes on
	# the CH2/CH3 blocks (D6). Byte pointers (word-aligned; D19).
	for _ch in range(4):
		_base = 2 + 4 * _ch
		_absent = ' (reads 0 / ignores writes when the build has NCH=2)' if _ch >= 2 else ''
		r = RegisterTemplate(nameTemplate='DMAxC%dSRC' % _ch, registerMemorySlot=_base + 0, description='Channel %d source byte address in the 0x0-0x1FFFF shared window (word-aligned: bits[1:0] must be 0; bits[31:17] must be 0). The full written 32-bit value reads back; the engine presents byte_ptr(16:2) as the 15-bit arbiter word address. A misaligned, out-of-window (>= 0x20000), or TCM-hole (0x8000-0xBFFF) SRC is rejected at GO with CHnERR (D13/A18).%s' % (_ch, _absent), size=32)
		dma.AddRegisterTemplate(r)
		r.AddBitField(BitField(name='DMAC%dSRC' % _ch, msb=16, lsb=0, accessibility='rw', description='Source byte address (word-aligned).'))
		r.AddBitField(BitField(msb=31, lsb=17, unused=True))

		r = RegisterTemplate(nameTemplate='DMAxC%dDST' % _ch, registerMemorySlot=_base + 1, description='Channel %d destination byte address (same word-aligned / in-window / TCM-hole rules as C%dSRC, D13/A18).%s' % (_ch, _ch, _absent), size=32)
		dma.AddRegisterTemplate(r)
		r.AddBitField(BitField(name='DMAC%dDST' % _ch, msb=16, lsb=0, accessibility='rw', description='Destination byte address (word-aligned).'))
		r.AddBitField(BitField(msb=31, lsb=17, unused=True))

		r = RegisterTemplate(nameTemplate='DMAxC%dLEN' % _ch, registerMemorySlot=_base + 2, description='Channel %d transfer length in WORDS. Decrements as the engine runs (a read returns the current remaining count, so pointers/LEN show where an aborted transfer stopped, D15); reads 0 before the first GO. LEN=0 at GO is a programming error (CHnERR, no transfer issued, D13).%s' % (_ch, _absent), size=32)
		dma.AddRegisterTemplate(r)
		r.AddBitField(BitField(name='DMAC%dLEN' % _ch, msb=16, lsb=0, accessibility='rw', description='Remaining transfer length in words.'))
		r.AddBitField(BitField(msb=31, lsb=17, unused=True))

		r = RegisterTemplate(nameTemplate='DMAxC%dCFG' % _ch, registerMemorySlot=_base + 3, description='Channel %d configuration: source/dest auto-increment (SINC/DINC, +4 per word when set, else a fixed peripheral data register), trigger source (TRIG), channel priority class (PRIO) and CRC ride-along enable (CRCEN). Program before GO.%s' % (_ch, _absent), size=32)
		dma.AddRegisterTemplate(r)
		r.AddBitField(BitField(name='DMAC%dSINC' % _ch, msb=0, accessibility='rw', description='Source auto-increment. 1 = src += 4 per word (block copy); 0 = src held (peripheral data register, the paced-drain case, D11).', valueDescriptions=[(0b0, 'Fixed source'), (0b1, 'Increment source')]))
		r.AddBitField(BitField(name='DMAC%dDINC' % _ch, msb=1, accessibility='rw', description='Destination auto-increment. 1 = dst += 4 per word; 0 = dst held (peripheral fill register, D11).', valueDescriptions=[(0b0, 'Fixed destination'), (0b1, 'Increment destination')]))
		r.AddBitField(BitField(name='DMAC%dTRIG' % _ch, msb=5, lsb=2, accessibility='rw', description='Trigger source (D9/D10/A8). 0 = software / mem-to-mem (continuously serviceable); 1 = UART0 RC (one word per received byte, read-to-clear); 2 = QSPI0 RX-full (one word per event + an extra W1C ack txn); 3 = NFC0 payload-ready (a frame event launches the full LEN-word burst + one ack); 4-15 reserved. Pacing requires the source peripheral\'s own receive interrupt-enable bit set (A8).', valueDescriptions=[(0, 'Software / mem-to-mem'), (1, 'UART0 receive-complete'), (2, 'QSPI0 RX-full'), (3, 'NFC0 payload-ready')]))
		r.AddBitField(BitField(name='DMAC%dPRIO' % _ch, msb=6, accessibility='rw', description='Priority class. Among serviceable channels the high class (1) is picked before the low class (0); within a class a round-robin pointer prevents starvation (D7). A continuously-serviceable PRIO=1 channel can hold off PRIO=0 channels (standard DMA priority semantic).', valueDescriptions=[(0b0, 'Low priority class'), (0b1, 'High priority class')]))
		r.AddBitField(BitField(name='DMAC%dCRCEN' % _ch, msb=7, accessibility='rw', description='CRC ride-along enable. When set, each transferred word is folded (bytes low-to-high) into the shared DMA0CRC accumulator (CRC16-CDMA2000, D14). Use one CRCEN channel per measurement session (a single shared accumulator).', valueDescriptions=[(0b0, 'No CRC'), (0b1, 'Accumulate CRC')]))
		r.AddBitField(BitField(msb=31, lsb=8, unused=True))

	# DMA0CRC (slot 18) -- CRC16-CDMA2000 accumulator / seed (reset 0xFFFF, D14)
	r = RegisterTemplate(nameTemplate='DMAxCRC', registerMemorySlot=18, description='CRC16-CDMA2000 (poly 0xC857) accumulator / seed, resets to 0xFFFF. Firmware writes the 0xFFFF seed before GO (the SYSTEM0 seed-via-state convention, no auto-seed) and reads the result after DONE; the engine accumulates in the MCLK domain, feeding each CRCEN word\'s four bytes low-to-high. No input/output reflection, no final XOR (the work.CRC16 contract). Upper bits read 0.', size=32)
	dma.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='DMACRC', msb=15, lsb=0, accessibility='rw', description='CRC16-CDMA2000 accumulator/seed (reset 0xFFFF).'))
	r.AddBitField(BitField(msb=31, lsb=16, unused=True))

	# DMA0DESC (slot 19) -- reserved descriptor-chain head (single-shot phase, D5)
	r = RegisterTemplate(nameTemplate='DMAxDESC', registerMemorySlot=19, description='Reserved for a descriptor-chain head pointer (out of scope this single-shot phase). Reads 0, writes ignored -- provisioned so scatter-gather bolts on at this slot without a register-map break. Slots >= 20 also read 0.', size=32)
	dma.AddRegisterTemplate(r)
	r.AddBitField(BitField(msb=31, lsb=0, unused=True))

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

	# TRNG0CR (slot 0) -- control (reset 0, D12)
	r = RegisterTemplate(nameTemplate='TRNGxCR', registerMemorySlot=0, description='TRNG control register. EN gates the entropy source (0 parks the RO rings -- the power/leakage lever -- and freezes harvesting; flags and the last assembled word are preserved). DRDYIE/ALMIE independently gate the two halves of the combined interrupt (vector 121). ROSEL selects/masks which rings in the ensemble contribute to the XOR reduction (0000 = all rings, the safe default-on encoding, D6 ruling 4). DECIM sets the decimation: one raw sample is taken every 2^DECIM MCLK cycles (0 = every cycle); a larger DECIM lets more independent ring jitter accumulate between samples. Resets to 0 (disabled).', size=32)
	trng.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='TRNGEN', msb=0, accessibility='rw', description='Entropy engine enable. 0 parks the RO ensemble and freezes the decimator/assembler/health test; the last assembled word, DRDY, and ALMF are preserved. 1 lets the rings oscillate and harvesting proceed (subject to the health-test auto-halt, D8/ruling 3).', valueDescriptions=[(0b0, 'Disabled (rings parked)'), (0b1, 'Enabled')]))
	r.AddBitField(BitField(name='TRNGDRDYIE', msb=1, accessibility='rw', description='Data-ready interrupt enable. When set, TRNG0SR.DRDY drives the combined interrupt (vector 121).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(name='TRNGALMIE', msb=2, accessibility='rw', description='Health-alarm interrupt enable. When set, TRNG0SR.ALMF drives the combined interrupt (vector 121).', valueDescriptions=[(0b0, 'Interrupt disabled'), (0b1, 'Interrupt enabled')]))
	r.AddBitField(BitField(msb=3, lsb=3, unused=True))
	r.AddBitField(BitField(name='TRNGROSEL', msb=7, lsb=4, accessibility='rw', description='Ring-oscillator ensemble contribution select/mask, forwarded to the entropy source. 0000 selects every ring in the ensemble (the reset-safe all-on encoding); a nonzero value masks a subset of the NRO rings into the XOR reduction (D6 ruling 4).'))
	r.AddBitField(BitField(name='TRNGDECIM', msb=11, lsb=8, accessibility='rw', description='Decimation exponent. One raw sample is taken every 2^TRNGDECIM MCLK cycles (0 = every MCLK cycle, up to 32768 cycles at 15). A nonzero value is recommended for real accumulation between independent samples (D7).'))
	r.AddBitField(BitField(msb=31, lsb=12, unused=True))

	# TRNG0SR (slot 1) -- status (DRDY/RUN read-only + ALMF W1C, D9/D8/D12)
	r = RegisterTemplate(nameTemplate='TRNGxSR', registerMemorySlot=1, description='TRNG status register. DRDY and RUN are read-only levels; ALMF is a sticky write-1-to-clear health-alarm flag (write a 1 to clear it; writing 0 leaves it unchanged; never cleared by a read; a set arriving the same cycle as a clear survives, D8). DRDY reflects the D9 blind-window-corrected level: a qualifying TRNG0DR read clears DRDY in the SAME cycle as the consuming read (an SR read issued immediately after a DR read observes DRDY=0 even though the harvest engine has not yet finished tearing the word down internally), so polling DRDY right after draining TRNG0DR is always accurate. The combined interrupt (vector 121) is (DRDY and TRNGDRDYIE) or (ALMF and TRNGALMIE).', size=32)
	trng.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='TRNGDRDY', msb=0, accessibility='r', description='Data ready: a fresh 32-bit entropy word is available in TRNG0DR. Clears the SAME cycle as the qualifying TRNG0DR read that consumes the word (D9 blind-window fix), and re-asserts only once the harvest engine assembles the NEXT word.', valueDescriptions=[(0b0, 'No word ready (a TRNG0DR read now returns 0 and does not consume)'), (0b1, 'Word ready')]))
	r.AddBitField(BitField(name='TRNGALMF', msb=1, accessibility='rw1', description='Health-test alarm flag (sticky). Set when the repetition-count health test (TRNG0HT.RCTC, or the hardware default of 32) reaches its cutoff; while set, harvesting is AUTO-HALTED (D8/ruling 3: no new sample feeds the assembler, DRDY cannot re-assert, RUN reads 0) -- write 1 to clear and let harvesting resume once the raw stream is healthy again. Drives vector 121 when TRNGALMIE is set. Write 1 to clear.', valueDescriptions=[(0b0, 'No alarm'), (0b1, 'Repetition-count cutoff reached')]))
	r.AddBitField(BitField(name='TRNGRUN', msb=2, accessibility='r', description='Entropy engine running: TRNGEN is set and no health alarm is currently latched (D12). Reads 0 whenever the rings are parked, either because TRNGEN=0 or because TRNGALMF is set (auto-halt).', valueDescriptions=[(0b0, 'Idle / halted'), (0b1, 'Running')]))
	r.AddBitField(BitField(msb=31, lsb=3, unused=True))

	# TRNG0DR (slot 2) -- entropy word (ro, READ-CONSUMES, D9)
	r = RegisterTemplate(nameTemplate='TRNGxDR', registerMemorySlot=2, description='Entropy data register. [31:0] is the most recently assembled 32-bit entropy word, direct-packed MSB-first from decimated ring-oscillator samples (D7, ruling 1: no hardware whitening -- firmware DRBGs the output, D16). READ SIDE EFFECT (D9, the one exception to "no read side effects" in this register library): a qualifying read (TRNGDRDY=1 at the time of the access) CONSUMES the word -- TRNG0SR.DRDY clears the SAME cycle, and the harvest engine begins assembling the next word. The consume is gated to fire EXACTLY ONCE per real bus access (a repeated internal edge in the same access cannot double-pop). A read while TRNGDRDY=0 (no word ready, or the previous word is still being retired) returns 0 and does NOT consume anything -- the next real word is still delivered intact on a later read. Writes are ignored.', size=32)
	trng.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='TRNGDR', msb=31, lsb=0, accessibility='r', description='Entropy word. A read while TRNGDRDY=1 returns the word and consumes it (DRDY clears the same cycle, D9); a read while TRNGDRDY=0 returns 0 and does not consume.'))

	# TRNG0HT (slot 3) -- health-test cutoff (rw) + run-length diagnostic (ro), D8
	r = RegisterTemplate(nameTemplate='TRNGxHT', registerMemorySlot=3, description='Health-test control/diagnostic register. RCTC is the repetition-count cutoff: the number of consecutive identical raw samples that trips the alarm (TRNG0SR.ALMF). RCTC=0 selects the hardware default of 32 (ruling 3), so the reset value is a safe default-on cutoff; a nonzero value is a firmware override. RUNLEN is a read-only saturating diagnostic exposing the CURRENT consecutive-identical-sample run length (resets to 1 on any change, saturates at 63) -- useful for tuning RCTC or observing ring health without waiting for an alarm. Other bits reserved, read 0. Resets to 0.', size=32)
	trng.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='TRNGRCTC', msb=7, lsb=0, accessibility='rw', description='Repetition-count cutoff (0 to 255). 0 selects the hardware default of 32 consecutive identical raw samples (D8/ruling 3); a nonzero value overrides it.'))
	r.AddBitField(BitField(msb=15, lsb=8, unused=True))
	r.AddBitField(BitField(name='TRNGRUNLEN', msb=21, lsb=16, accessibility='r', description='Current consecutive-identical-raw-sample run length (0 to 63, saturating diagnostic). Resets to 1 (via have_prev) on the first sample after any change; does not itself trigger the alarm -- compare against TRNGRCTC to see how close the raw stream is to tripping it.'))
	r.AddBitField(BitField(msb=31, lsb=22, unused=True))


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

	# EVFCR (slot 0) -- global enable (D21: resets 0 = nothing can fire)
	r = RegisterTemplate(nameTemplate='EVFCR', registerMemorySlot=0, description='Event fabric control register. EN is the global kill switch: with EN clear NO channel can fire, no FIRED or OVR flag can set, and no task pulse can be emitted, whatever the channel enables and configuration words say (raw events are still recorded in EVFEVSTAT, which sits upstream of the gate). Resets to 0, so the fabric comes out of reset completely inert; configure the channels first, then set EN. Other bits reserved, read 0.', size=32)
	evfab.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='EVFEN', msb=0, accessibility='rw', description='Global fabric enable. Gates every channel together with its own EVFCHEN bit (both must be set for a channel to fire).', valueDescriptions=[(0b0, 'Fabric disabled (no pulses, no flags)'), (0b1, 'Fabric enabled')]))
	r.AddBitField(BitField(msb=31, lsb=1, unused=True))

	# EVFSR (slot 1) -- live RO reductions (D20)
	r = RegisterTemplate(nameTemplate='EVFSR', registerMemorySlot=1, description='Event fabric status register. Both bits are LIVE read-only reductions of the sticky words, not state of their own: firmware polls this one word to learn whether anything at all has fired or been degraded, then reads EVFFIRED / EVFOVR to find out which channels. There is no interrupt in this version of the fabric (EVFIE is reserved), so this register is the whole notification mechanism. Other bits reserved, read 0.', size=32)
	evfab.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='EVFFIREDIF', msb=0, accessibility='r', description='Set while ANY bit of EVFFIRED is set (a logical OR of the sticky per-channel fired flags). Clears only when every EVFFIRED bit has been written back to 0.', valueDescriptions=[(0b0, 'No channel has fired since the flags were cleared'), (0b1, 'At least one channel has fired')]))
	r.AddBitField(BitField(name='EVFOVRIF', msb=1, accessibility='r', description='Set while ANY bit of EVFOVR is set (a logical OR of the sticky per-channel overrun flags).', valueDescriptions=[(0b0, 'No overrun recorded'), (0b1, 'At least one overrun recorded')]))
	r.AddBitField(BitField(msb=31, lsb=2, unused=True))

	# EVFIE (slot 2) -- RESERVED in the vectorless v1 (D20)
	r = RegisterTemplate(nameTemplate='EVFIE', registerMemorySlot=2, description='Reserved interrupt-enable register. This version of the event fabric is deliberately VECTORLESS: it spends no interrupt vector, its interrupt output is tied inactive, and this slot reads 0 and ignores writes. The slot is reserved so that a later revision can add per-flag interrupt enables without moving any other register.', size=32)
	evfab.AddRegisterTemplate(r)
	r.AddBitField(BitField(msb=31, lsb=0, unused=True))

	# EVFCAP (slot 3) -- RO capability constant (D19)
	r = RegisterTemplate(nameTemplate='EVFCAP', registerMemorySlot=3, description='Capability register (read-only constant). Reports the LIVE line counts of this build so a driver can size its loops instead of hardcoding them: the number of channels, event lines and task lines actually implemented, plus a version number. At the Castalia configuration it reads 0x010A1008.', size=32)
	evfab.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='EVFNCH', msb=7, lsb=0, accessibility='r', description='Number of implemented channels (' + str(_EVFAB_N_CH) + '). Channel registers above this count read 0 and ignore writes.'))
	r.AddBitField(BitField(name='EVFNEV', msb=15, lsb=8, accessibility='r', description='Number of implemented event lines (' + str(_EVFAB_N_EV) + '). EVSEL codes at or above this count select nothing, which makes the channel inert (EVSEL 31 is the documented NONE encoding).'))
	r.AddBitField(BitField(name='EVFNTASK', msb=23, lsb=16, accessibility='r', description='Number of implemented task lines (' + str(_EVFAB_N_TASK) + '). A TASKSEL at or above this count still sets EVFFIRED but drives no task line and can never set EVFOVR.'))
	r.AddBitField(BitField(name='EVFVER', msb=31, lsb=24, accessibility='r', description='Fabric version (' + str(_EVFAB_VER) + ').'))

	# EVFCHEN (slot 4) + the w1s/w1c aliases (slots 5/6) -- D18, multi-hart safe
	r = RegisterTemplate(nameTemplate='EVFCHEN', registerMemorySlot=4, description='Channel enable register. Bit n enables channel n; a channel fires only when this bit AND EVFCR.EN are both set, and a disabled channel is completely inert (no task pulse, no EVFFIRED, no EVFOVR). Resets to 0. Writing this register directly is safe only for a single owner: when several harts share the fabric, use the EVFCHENSET / EVFCHENCLR aliases instead, which set or clear individual bits without a read-modify-write. Bits above the implemented channel count read 0.', size=32)
	evfab.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='EVFCHEN', msb=_EVFAB_N_CH - 1, lsb=0, accessibility='rw', description='Per-channel enable bits (bit n = channel n).'))
	r.AddBitField(BitField(msb=31, lsb=_EVFAB_N_CH, unused=True))

	r = RegisterTemplate(nameTemplate='EVFCHENSET', registerMemorySlot=5, description='Channel enable SET alias. Writing a 1 to bit n sets EVFCHEN bit n; writing 0 leaves that bit alone, so a hart can enable its own channels without disturbing another hart\'s. Reading this address returns the current EVFCHEN value.', size=32)
	evfab.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='EVFCHENSET', msb=_EVFAB_N_CH - 1, lsb=0, accessibility='rw', description='Write 1 to enable channel n (write 0 = no effect). Reads back EVFCHEN.'))
	r.AddBitField(BitField(msb=31, lsb=_EVFAB_N_CH, unused=True))

	r = RegisterTemplate(nameTemplate='EVFCHENCLR', registerMemorySlot=6, description='Channel enable CLEAR alias. Writing a 1 to bit n clears EVFCHEN bit n; writing 0 leaves that bit alone. Reading this address returns the current EVFCHEN value. Disable a channel through this register before changing its EVFCHnCFG selectors.', size=32)
	evfab.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='EVFCHENCLR', msb=_EVFAB_N_CH - 1, lsb=0, accessibility='rw', description='Write 1 to disable channel n (write 0 = no effect). Reads back EVFCHEN.'))
	r.AddBitField(BitField(msb=31, lsb=_EVFAB_N_CH, unused=True))

	# EVFCHTRIG (slot 7) -- software channel injection (D16)
	r = RegisterTemplate(nameTemplate='EVFCHTRIG', registerMemorySlot=7, description='Channel trigger injection register. Writing a 1 to bit n makes channel n fire exactly once, as if its selected event had occurred: the task pulse, EVFFIRED and EVFOVR all behave identically to a hardware firing. The injection still honours the enables -- a trigger written to a disabled channel, or with EVFCR.EN clear, does nothing. However long the bus write is held, exactly one firing is injected. Reads 0.', size=32)
	evfab.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='EVFCHTRIG', msb=_EVFAB_N_CH - 1, lsb=0, accessibility='w', description='Write 1 to inject one firing on channel n.'))
	r.AddBitField(BitField(msb=31, lsb=_EVFAB_N_CH, unused=True))

	# EVFFIRED / EVFOVR (slots 8/9) -- sticky per-channel W1C flags (D14/D15)
	r = RegisterTemplate(nameTemplate='EVFFIRED', registerMemorySlot=8, description='Sticky channel-fired flags. Bit n sets whenever channel n fires (from a hardware event or an EVFCHTRIG injection) and stays set until firmware writes a 1 to it. A firing arriving in the same cycle as the clearing write WINS -- the flag survives -- so no event can be lost between a read and a clear. Bits above the implemented channel count read 0.', size=32)
	evfab.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='EVFFIRED', msb=_EVFAB_N_CH - 1, lsb=0, accessibility='rw1', description='Channel n has fired. Write 1 to clear.'))
	r.AddBitField(BitField(msb=31, lsb=_EVFAB_N_CH, unused=True))

	r = RegisterTemplate(nameTemplate='EVFOVR', registerMemorySlot=9, description='Sticky channel-overrun flags. Bit n sets when channel n fires but its task pulse was DEGRADED: either the target consumer was already busy at that moment, or another enabled channel fired onto the SAME task line in the same cycle (the two firings merge into one pulse and BOTH channels record an overrun -- the fabric cannot say which one won). An overrun never suppresses the pulse and never applies backpressure; it is a diagnostic. A channel whose TASKSEL selects a reserved code can never set this flag, since no task line exists to be busy. Set wins over a same-cycle clear. Bits above the implemented channel count read 0.', size=32)
	evfab.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='EVFOVR', msb=_EVFAB_N_CH - 1, lsb=0, accessibility='rw1', description='Channel n fired while its task was busy, or merged with another channel onto the same task in the same cycle. Write 1 to clear.'))
	r.AddBitField(BitField(msb=31, lsb=_EVFAB_N_CH, unused=True))

	# EVFEVSTAT (slot 10) -- raw event record, UNGATED (D14) + EVFEVTRIG (slot 11, D17)
	r = RegisterTemplate(nameTemplate='EVFEVSTAT', registerMemorySlot=10, description='Sticky raw-event record. Bit e sets whenever event line e is seen by the fabric front end, INDEPENDENTLY of EVFCR.EN and of any channel enable or configuration -- it is upstream of every gate. That makes it both a bring-up aid (does this producer actually pulse?) and a direct test of tap discipline: because every event is tapped from its source flag\'s SET condition rather than from a masked interrupt line, clearing a producer\'s interrupt enable must NOT stop its bit appearing here. Set wins over a same-cycle clear. Bits above the implemented event count read 0.', size=32)
	evfab.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='EVFEVSTAT', msb=_EVFAB_N_EV - 1, lsb=0, accessibility='rw1', description='Event line e has been seen. Write 1 to clear.'))
	r.AddBitField(BitField(msb=31, lsb=_EVFAB_N_EV, unused=True))

	r = RegisterTemplate(nameTemplate='EVFEVTRIG', registerMemorySlot=11, description='Raw event injection register. Writing a 1 to bit e injects one occurrence of event line e exactly as if the producer had generated it: it is recorded in EVFEVSTAT and offered to every channel selecting that event. However long the bus write is held, exactly one event is injected. With this register the entire crossbar -- every event to every task, including events whose producer block is absent from the configuration -- is testable from firmware with no producer hardware at all. Reads 0.', size=32)
	evfab.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='EVFEVTRIG', msb=_EVFAB_N_EV - 1, lsb=0, accessibility='w', description='Write 1 to inject one occurrence of event line e.'))
	r.AddBitField(BitField(msb=31, lsb=_EVFAB_N_EV, unused=True))

	# EVFGPIOMASK (slot 15) -- the GPIO0 edge-path mask (D10/D18); slots 12-14 stay
	# reserved for the earmarked TKSTAT/FIREDIE/OVRIE names.
	r = RegisterTemplate(nameTemplate='EVFGPIOMASK', registerMemorySlot=15, description='GPIO0 edge-path mask. Event line ' + str(_EVFAB_N_EV - 1) + ' is generated inside the fabric from GPIO0\'s eight raw pad edges: each pad is synchronized, edge-detected, ANDed with its bit here, and the eight results are ORed into one event. A bit clear means that pad contributes nothing -- and, because the mask is applied BEFORE the OR, a masked-off pad also absorbs an undriven or unbonded pin instead of poisoning the event. The port\'s own PxIE interrupt enables are never consulted, so a pin can drive the fabric without ever raising an interrupt. Resets to 0, leaving the whole path inert. Other bits reserved, read 0.', size=32)
	evfab.AddRegisterTemplate(r)
	r.AddBitField(BitField(name='EVFGPIOMASK', msb=7, lsb=0, accessibility='rw', description='Per-pad enable for the GPIO0 edge path (bit i = GPIO0 pin i).'))
	r.AddBitField(BitField(msb=31, lsb=8, unused=True))

	# EVFCHnCFG (slots 16+n, n = 0..15) -- the channel array. The map reserves 16
	# addresses; only the first N_CH are implemented (the rest read 0, D18).
	for _ch in range(16):
		_live = _ch < _EVFAB_N_CH
		_desc = ('Channel ' + str(_ch) + ' configuration. EVSEL picks which event line feeds the channel and TASKSEL picks which task line it drives; ENR is a read-only mirror of this channel\'s EVFCHEN bit, so one read shows a channel\'s whole state. Selector encoding is deliberately forgiving: EVSEL 31 is the documented NONE code, and any EVSEL or TASKSEL value with no line behind it simply makes the channel (or its output) inert rather than aliasing onto a real one. Change EVSEL or TASKSEL only while the channel is disabled -- the fabric does not interlock a live reconfiguration. Resets to 0, which is harmless because a channel is double-gated by EVFCR.EN and EVFCHEN.'
			if _live else
			'Reserved channel-' + str(_ch) + ' configuration slot. This build implements ' + str(_EVFAB_N_CH) + ' channels, so this address reads 0 and ignores writes; the map reserves 16 channel addresses so a wider fabric needs no register move.')
		r = RegisterTemplate(nameTemplate='EVFCH' + str(_ch) + 'CFG', registerMemorySlot=16 + _ch, description=_desc, size=32)
		evfab.AddRegisterTemplate(r)
		if _live:
			r.AddBitField(BitField(name='EVFEVSEL' + str(_ch), msb=4, lsb=0, accessibility='rw', description='Event select for channel ' + str(_ch) + ': the event line whose occurrence fires this channel. 0 = RTC0 tick, 1 = RTC0 alarm, 2 = PWM0 period, 3 = PWM0 fault, 4 = TIMER0 compare0, 5 = TIMER0 overflow, 6 = TIMER1 compare0, 7 = UART0 receive, 8 = NFC0 field-detect, 9 = NFC0 rx-frame, 10 = DMA0 channel-0 done, 11 = DMA0 channel-1 done, 12 = DMA0 error, 13 = TRNG0 data-ready, 14 = I2CT0 address-match, 15 = masked GPIO0 pad edge (see EVFGPIOMASK). 31 = NONE; other codes select nothing. An event whose producer block is absent from this configuration is tied inactive and simply never fires.'))
			r.AddBitField(BitField(msb=7, lsb=5, unused=True))
			r.AddBitField(BitField(name='EVFTASKSEL' + str(_ch), msb=11, lsb=8, accessibility='rw', description='Task select for channel ' + str(_ch) + ': the task line this channel pulses. 0 = DMA0 channel-0 GO, 1 = DMA0 channel-1 GO, 2 = TIMER0 START, 3 = TIMER0 STOP, 4 = PWM0 fault trip, 5 = PWRCTRL tile wake, 6 = NPU0 THINK, 7 = GPIO0 output SET, 8 = GPIO0 output CLEAR. Codes 9 and above drive no line (the channel still records EVFFIRED). A task whose consumer block is absent from this configuration is left unconnected.'))
			r.AddBitField(BitField(msb=30, lsb=12, unused=True))
			r.AddBitField(BitField(name='EVFENR' + str(_ch), msb=31, accessibility='r', description='Read-only mirror of EVFCHEN bit ' + str(_ch) + ' (this channel\'s enable).', valueDescriptions=[(0b0, 'Channel disabled'), (0b1, 'Channel enabled')]))
		else:
			r.AddBitField(BitField(msb=31, lsb=0, unused=True))


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

	elif model == 'castalia-lqfp100':
		# Stage G2 (2026-07-22): the CastaliaDP LARGE package — LQFP-100,
		# 14x14 mm body, 0.5 mm pitch, 25 pins/side. User directive 2026-07-22:
		# the QFN-44 is retired as the respin target ("we can have more digital
		# pins"); this model bonds the FULL digital complement — all 48 GPIO
		# (prt1-prt6, first package to bond P5/P6), RESETN, POC — plus 3 core
		# and 3 IO supply pairs (one per digital edge) and a NORTH analog-
		# reserve band (AVDD/AVSS + ARSV0-7) for the U-tile-notch potentiostat
		# drop-in. Numbering follows the house convention: pin 1 at the top of
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

		# One analog domain on the NORTH edge: the CastaliaDP die is digital-only,
		# but the four hart-tile U-notches (top-center analog reserve, potentiostat
		# drop-in at Virtuoso) face north — the band reserves supply + 8 pins.
		analogPowerDomain = package.AddPowerDomain(
			powerDomainName='Analog',
			positiveVoltage=3.3,
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

		# North analog-reserve band: 8 uncommitted analog pads for the notch
		# drop-in (electrode/test points; unconnected until an analog respin).
		for _ai in range(8):
			package.AddPin(packagePinNumber=78 + _ai, name='ARSV' + str(_ai), ioType='io', powerDomain=analogPowerDomain)

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
		for _ncp in ([23, 24, 25] + [26] + [72, 73, 74, 75] + list(range(86, 101))):
			package.AddPin(packagePinNumber=_ncp, name='NC', ioType='', noConnect=True)

	else:
		raise Exception('package model "' + model + '" is declared but not implemented')
	return package


m.Package = _buildPackageData(packageModel)

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
GPIO5.AddGpio(GpioConfigurator(bitNumber=0, primaryName='GPIO40', funcName='', funcIOType='',	rstOUT=0, rstDIR=0, rstSEL=0, rstREN=0, description='General-purpose I/O (AF1 = NFC0 off-die carrier clock input when NFC present)', altFuncs=([(1, 'NFC_RF_CLK', 'i', 'NFC0 off-die RF carrier clock (alt plane AF1)')] if nfcPresent else [])), packagePinNumber=_gpioPkgPin(5, 0)) # AF1 gated with NFC0; reset AFS = AF1 (D5)
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
# Populated only for the CQ package model, so the default TRM stays byte-identical.
if packageModel == 'castalia-quad-qfn64' and cqAfeStubsPresent:
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
		(0x8, '—', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0x9, '—', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0xA, '—', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0xB, '—', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0xC, '—', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0xD, '—', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0xE, '—', 'RW',  'Scratch / reserved (plain read-write storage).'),
		(0xF, '—', 'RW',  'Scratch / reserved (plain read-write storage).'),
	]
	_cqDocBlocks = []
	for _h in range(4):
		_cqDocBlocks.append({
			'name':      'AFE' + str(_h),
			'base':      0x4C00 + 0x40 * _h,
			'sizeBytes': 0x40,
			'parent':    ('page-0 slot 12 (0x4C00-0x4CFF, the reserved ex-SARADC/AFE slot)', 0x4C00, 0x4CFF),
			'ownerHart': _h,
			'gate':      ('s\\_master = 0' if _h == 0 else 's\\_master = ' + str(_h) + ' or s\\_master = 0'),
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
	('numMutexes', numMutexes),
	('registerFileDualPort', _regsDualPort),
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
		('onewire', onewirePresent), ('dma', dmaPresent),
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
# S2: declarative schema metadata + the resolved defaults, attached for the
# `make web` export (out/web/chip_data.js) so the configurator can read
# ranges/enums/defaults from the generator rather than re-hardcoding them.
m.ConfigMeta = dict((k, dict(_CONFIG_META[k])) for k in _CONFIG_META)
m.ConfigDefaults = dict((k, _CONFIG_META[k]['default']) for k in _CONFIG_META)

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

