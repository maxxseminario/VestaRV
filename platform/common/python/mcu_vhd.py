# mcu_vhd.py — golden-master MCU.vhd emitter (RTL-generation track, Phase 2)
#
# Emits out/hdl/MCU.vhd from hdl_templates/MCU.template.vhd. The template is the
# verified hdl/common/MCU.vhd with the DESCRIPTION-DRIVEN regions carved out and
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
#   - arb-fabric-decls / clint-irq-decls / meip-decl / pd-decls /
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
# file is BYTE-IDENTICAL to hdl/common/MCU.vhd apart from the generated header.
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
# Transcribed RTL structure (spellings + orders from hdl/common/MCU.vhd)
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

# X-collapse fix (2026-07-20): shim peripherals whose RTL clocks status/RX
# snapshot registers on falling_edge(en_mem). Their shims take the
# falling-mclk re-registered shslv_<sel>_en_q strobe (emitPolarityShims);
# I3C0/NFC0 carry the same treatment inside their own instance regions.
# GPIO/SYSTEM/NPU sample en_mem only on rising clk_mem edges - raw strobe.
CAPTURE_CLOCK = {'SPI0', 'SPI1', 'UART0', 'UART1', 'TIMER0', 'TIMER1',
	'I2C0', 'I2C1', 'QSPI0'}

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

# ---------------------------------------------------------------------------
# G1a (2026-07-11): I2C1 is the first config-droppable peripheral INSTANCE.
# The four regions below are transcribed VERBATIM from the golden master (they
# were fixed template content until G1a carved them out); each emitter returns
# them unchanged when I2C1 is present and degrades the I2C1 rows when it is
# dropped (aggregate choices -> '0' hi-Z idiom, muxes/decls removed, comments
# reworded). The two pure-verbatim blocks (pad decls, the i2c1 instance) live
# in hdl_templates/MCU.template.i2c1.vhd instead (NPU side-template mechanism).
# ---------------------------------------------------------------------------
I2C_FABRIC_DECLS = [
	"        -- M7c.2 movers: I2C0/I2C1 (M11: window slots 14/15). I2C's register",
	'        -- READ is COMBINATIONAL (rdata_out collapses to register 0 the moment',
	'        -- EnMemPeriph deasserts), so the bridge REGISTERS it at the',
	'        -- LATCH->DATA edge (i2c*_sh_rdata below) ' + EMDASH + ' reproducing exactly the',
	'        -- old adddec timing the I2C.vhd comment assumes ("EnMemPeriph has a',
	'        -- leading edge exactly one clock cycle before rdata latches").',
	'        signal shslv_i2c0_sel,  shslv_i2c0_en   : std_logic;',
	'        signal shslv_i2c1_sel,  shslv_i2c1_en   : std_logic;',
	"        signal shslv_rd_i2c0    : std_logic := '0';",
	"        signal shslv_rd_i2c1    : std_logic := '0';",
	'        signal i2c0_sh_en_n     : std_logic;',
	'        signal i2c1_sh_en_n     : std_logic;',
	'        signal shslv_i2c0_en_q  : std_logic;   -- X-fix: falling-mclk registered strobes',
	'        signal shslv_i2c1_en_q  : std_logic;   -- (snapshot capture clocks)',
	'        signal i2c0_sh_rdata_c  : std_logic_vector(31 downto 0); -- combinational, from the instance',
	'        signal i2c1_sh_rdata_c  : std_logic_vector(31 downto 0);',
	"        signal i2c0_sh_rdata    : std_logic_vector(31 downto 0) := (others => '0'); -- bridge-registered",
	"        signal i2c1_sh_rdata    : std_logic_vector(31 downto 0) := (others => '0');",
]
GPIO2_AF1_PLANES = [
	'        -- AF1 plane: UART1 relocation on P3.0/1, I2C1 relocation on P3.2/3,',
	'        -- UART0 relocation on P3.4/5, I2C0 relocation on P3.6/7 (v2) ' + EMDASH + ' the',
	'        -- full serial-relocation row (both UARTs + both I2C buses).',
	'        afunc3_af1_out <= (',
	'            pnum_gpio2_af1_scl0 => scl0_out,    -- GPIO2 pin 7',
	'            pnum_gpio2_af1_sda0 => sda0_out,    -- GPIO2 pin 6',
	'            pnum_gpio2_af1_rx0  => rx0_out,     -- GPIO2 pin 5',
	'            pnum_gpio2_af1_tx0  => tx0_out,     -- GPIO2 pin 4',
	'            pnum_gpio2_af1_scl1 => scl1_out,    -- GPIO2 pin 3',
	'            pnum_gpio2_af1_sda1 => sda1_out,    -- GPIO2 pin 2',
	'            pnum_gpio2_af1_rx1  => rx1_out,     -- GPIO2 pin 1',
	'            pnum_gpio2_af1_tx1  => tx1_out      -- GPIO2 pin 0',
	'        );',
	'        afunc3_af1_dir <= (',
	'            pnum_gpio2_af1_scl0 => scl0_dir,    -- GPIO2 pin 7',
	'            pnum_gpio2_af1_sda0 => sda0_dir,    -- GPIO2 pin 6',
	'            pnum_gpio2_af1_rx0  => rx0_dir,     -- GPIO2 pin 5',
	'            pnum_gpio2_af1_tx0  => tx0_dir,     -- GPIO2 pin 4',
	'            pnum_gpio2_af1_scl1 => scl1_dir,    -- GPIO2 pin 3',
	'            pnum_gpio2_af1_sda1 => sda1_dir,    -- GPIO2 pin 2',
	'            pnum_gpio2_af1_rx1  => rx1_dir,     -- GPIO2 pin 1',
	'            pnum_gpio2_af1_tx1  => tx1_dir      -- GPIO2 pin 0',
	'        );',
	'        afunc3_af1_ren <= (',
	'            pnum_gpio2_af1_scl0 => scl0_ren,    -- GPIO2 pin 7',
	'            pnum_gpio2_af1_sda0 => sda0_ren,    -- GPIO2 pin 6',
	'            pnum_gpio2_af1_rx0  => rx0_ren,     -- GPIO2 pin 5',
	'            pnum_gpio2_af1_tx0  => tx0_ren,     -- GPIO2 pin 4',
	'            pnum_gpio2_af1_scl1 => scl1_ren,    -- GPIO2 pin 3',
	'            pnum_gpio2_af1_sda1 => sda1_ren,    -- GPIO2 pin 2',
	'            pnum_gpio2_af1_rx1  => rx1_ren,     -- GPIO2 pin 1',
	'            pnum_gpio2_af1_tx1  => tx1_ren      -- GPIO2 pin 0',
	'        );',
]
I2C_INPUT_MUXES = [
	'        -- Resistor Enables (I2C0 relocates to P2.6/7 or P3.6/7 (v2), I2C1 to',
	'        -- P3.2/3 or P2.4/5 (v2) ' + EMDASH + ' the peripheral ren_in follows the same AF',
	'        -- selection as the inputs below, fixed priority: v2 pad > AF1 pad > home)',
	'        sda0_ren_in <= p3_ren(pnum_gpio2_af1_sda0)',
	'                       when p3_afs((3 * pnum_gpio2_af1_sda0) + 2 downto 3 * pnum_gpio2_af1_sda0) = "001"',
	'                       else p2_ren(pnum_gpio1_af1_sda0)',
	'                       when p2_afs((3 * pnum_gpio1_af1_sda0) + 2 downto 3 * pnum_gpio1_af1_sda0) = "001"',
	'                       else p4_ren(pnum_gpio3_sda0);',
	'        scl0_ren_in <= p3_ren(pnum_gpio2_af1_scl0)',
	'                       when p3_afs((3 * pnum_gpio2_af1_scl0) + 2 downto 3 * pnum_gpio2_af1_scl0) = "001"',
	'                       else p2_ren(pnum_gpio1_af1_scl0)',
	'                       when p2_afs((3 * pnum_gpio1_af1_scl0) + 2 downto 3 * pnum_gpio1_af1_scl0) = "001"',
	'                       else p4_ren(pnum_gpio3_scl0);',
	'        sda1_ren_in <= p2_ren(pnum_gpio1_af1_sda1)',
	'                       when p2_afs((3 * pnum_gpio1_af1_sda1) + 2 downto 3 * pnum_gpio1_af1_sda1) = "001"',
	'                       else p3_ren(pnum_gpio2_af1_sda1)',
	'                       when p3_afs((3 * pnum_gpio2_af1_sda1) + 2 downto 3 * pnum_gpio2_af1_sda1) = "001"',
	'                       else p4_ren(pnum_gpio3_sda1);',
	'        scl1_ren_in <= p2_ren(pnum_gpio1_af1_scl1)',
	'                       when p2_afs((3 * pnum_gpio1_af1_scl1) + 2 downto 3 * pnum_gpio1_af1_scl1) = "001"',
	'                       else p3_ren(pnum_gpio2_af1_scl1)',
	'                       when p3_afs((3 * pnum_gpio2_af1_scl1) + 2 downto 3 * pnum_gpio2_af1_scl1) = "001"',
	'                       else p4_ren(pnum_gpio3_scl1);',
	'',
	'        -- Inputs (relocated pad wins, home pad is the default)',
	'        sda0_in <= prt3_in(pnum_gpio2_af1_sda0)',
	'                   when p3_afs((3 * pnum_gpio2_af1_sda0) + 2 downto 3 * pnum_gpio2_af1_sda0) = "001"',
	'                   else prt2_in(pnum_gpio1_af1_sda0)',
	'                   when p2_afs((3 * pnum_gpio1_af1_sda0) + 2 downto 3 * pnum_gpio1_af1_sda0) = "001"',
	'                   else prt4_in(pnum_gpio3_sda0);',
	'        scl0_in <= prt3_in(pnum_gpio2_af1_scl0)',
	'                   when p3_afs((3 * pnum_gpio2_af1_scl0) + 2 downto 3 * pnum_gpio2_af1_scl0) = "001"',
	'                   else prt2_in(pnum_gpio1_af1_scl0)',
	'                   when p2_afs((3 * pnum_gpio1_af1_scl0) + 2 downto 3 * pnum_gpio1_af1_scl0) = "001"',
	'                   else prt4_in(pnum_gpio3_scl0);',
	'        sda1_in <= prt2_in(pnum_gpio1_af1_sda1)',
	'                   when p2_afs((3 * pnum_gpio1_af1_sda1) + 2 downto 3 * pnum_gpio1_af1_sda1) = "001"',
	'                   else prt3_in(pnum_gpio2_af1_sda1)',
	'                   when p3_afs((3 * pnum_gpio2_af1_sda1) + 2 downto 3 * pnum_gpio2_af1_sda1) = "001"',
	'                   else prt4_in(pnum_gpio3_sda1);',
	'        scl1_in <= prt2_in(pnum_gpio1_af1_scl1)',
	'                   when p2_afs((3 * pnum_gpio1_af1_scl1) + 2 downto 3 * pnum_gpio1_af1_scl1) = "001"',
	'                   else prt3_in(pnum_gpio2_af1_scl1)',
	'                   when p3_afs((3 * pnum_gpio2_af1_scl1) + 2 downto 3 * pnum_gpio2_af1_scl1) = "001"',
	'                   else prt4_in(pnum_gpio3_scl1);',
]
GPIO3_PRIMARY_PLANES = [
	'        afunc4_out <= (',
	'            pnum_gpio3_dtp3     => dtp3_out,  -- GPIO3 pin 7',
	'            pnum_gpio3_dtp2     => dtp2_out,  -- GPIO3 pin 6',
	'            pnum_gpio3_dtp1     => dtp1_out,  -- GPIO3 pin 5',
	'            pnum_gpio3_dtp0     => dtp0_out,  -- GPIO3 pin 4',
	'            pnum_gpio3_scl1     => scl1_out,  -- GPIO3 pin 3',
	'            pnum_gpio3_sda1     => sda1_out,  -- GPIO3 pin 2',
	'            pnum_gpio3_scl0     => scl0_out,  -- GPIO3 pin 1',
	'            pnum_gpio3_sda0     => sda0_out   -- GPIO3 pin 0',
	'        );',
	'        afunc4_dir <= (',
	'            pnum_gpio3_dtp3 => dtp3_dir,      -- GPIO3 pin 7',
	'            pnum_gpio3_dtp2 => dtp2_dir,      -- GPIO3 pin 6',
	'            pnum_gpio3_dtp1 => dtp1_dir,      -- GPIO3 pin 5',
	'            pnum_gpio3_dtp0 => dtp0_dir,      -- GPIO3 pin 4',
	'            pnum_gpio3_scl1 => scl1_dir,      -- GPIO3 pin 3',
	'            pnum_gpio3_sda1 => sda1_dir,      -- GPIO3 pin 2',
	'            pnum_gpio3_scl0 => scl0_dir,      -- GPIO3 pin 1',
	'            pnum_gpio3_sda0 => sda0_dir       -- GPIO3 pin 0',
	'        );',
	'        afunc4_ren <= (',
	'            pnum_gpio3_dtp3 => dtp3_ren,      -- GPIO3 pin 7',
	'            pnum_gpio3_dtp2 => dtp2_ren,      -- GPIO3 pin 6',
	'            pnum_gpio3_dtp1 => dtp1_ren,      -- GPIO3 pin 5',
	'            pnum_gpio3_dtp0 => dtp0_ren,      -- GPIO3 pin 4',
	'            pnum_gpio3_scl1 => scl1_ren,      -- GPIO3 pin 3',
	'            pnum_gpio3_sda1 => sda1_ren,      -- GPIO3 pin 2',
	'            pnum_gpio3_scl0 => scl0_ren,      -- GPIO3 pin 1',
	'            pnum_gpio3_sda0 => sda0_ren       -- GPIO3 pin 0',
	'        );',
]

# ---------------------------------------------------------------------------
# G1b (2026-07-11): UART1 / SPI1 / TIMER1 join I2C1 as config-droppable
# INSTANCES. Same machinery: the mixed fixed/config regions below are
# transcribed VERBATIM from the golden master and degrade line-by-line when an
# instance is dropped (aggregate choices -> the '0' hi-Z idiom, muxes/decls
# removed, comments reworded); the pure-verbatim pad-decl + instance blocks
# live in hdl_templates/MCU.template.{uart1,spi1,timer1}.vhd (side templates).
# The AF2-AF7 output-spread planes are NOT transcribed: they are emitted from
# the description's FromSpread altFuncs (generate.py filters _GPIO_AF_SPREAD
# by config first), with SPREAD_SIG below owning the RTL signal spellings —
# check_mcu_vhd.py STRICT at defaults is the transcription proof.
# ---------------------------------------------------------------------------
# The shared timer/UART/SPI output pool's RTL signal spellings (spread planes
# wire LITERAL pin indices; a plane slot with no surviving function reads '0')
SPREAD_SIG = {
	'TX0': 'tx0', 'TX1': 'tx1', 'SCK1': 'sck1', 'MOSI1': 'mosi1',
	'T0CMP0': 't0_cmp0', 'T0CMP1': 't0_cmp1', 'T1CMP0': 't1_cmp0', 'T1CMP1': 't1_cmp1',
	# pin-mux v2: io slots carried by the spread planes (their INPUT side is a
	# separate relocation mux — RX0 in the fixed template, MISO1 in
	# SPI1_INPUT_TAPS — keyed on the pin's PxAFS, always-visible idiom)
	'RX0': 'rx0', 'MISO1': 'miso1',
}
# Per-port spread-block header comments (transcribed; the flatten lines are
# emitted by the same region so the whole block is one marker per port)
SPREAD_HEADERS = {
	0: ['        -- Flattened AF planes (7 downto 1 unassigned, plane 0 = AF0): the',
		'        -- boot/flash/clock port keeps exactly one alternate function per pin.',
		'        -- GPIO0 AF output-function spread: aggregates + 8-plane flatten'],
	1: ['        -- Flattened AF planes (7 downto 2 unassigned)',
		'        -- GPIO1 AF output-function spread: aggregates + 8-plane flatten'],
	2: ['        -- Flattened AF planes (7 downto 2 unassigned)',
		'        -- GPIO2 AF output-function spread: aggregates + 8-plane flatten'],
	3: ['        -- Flattened AF planes (7 downto 2 unassigned)',
		'        -- GPIO3 AF output-function spread: aggregates + 8-plane flatten'],
}
MOVER_FABRIC_DECLS = [
	'        -- M7b movers: TIMER0/1 + GPIO1/2/3 (M11: window slots 6/7/1/8/13)',
	'        signal shslv_tim0_sel,  shslv_tim0_en   : std_logic;',
	'        signal shslv_tim1_sel,  shslv_tim1_en   : std_logic;',
	'        signal shslv_gpio1_sel, shslv_gpio1_en  : std_logic;',
	'        signal shslv_gpio2_sel, shslv_gpio2_en  : std_logic;',
	'        signal shslv_gpio3_sel, shslv_gpio3_en  : std_logic;',
	"        signal shslv_rd_tim0    : std_logic := '0';",
	"        signal shslv_rd_tim1    : std_logic := '0';",
	"        signal shslv_rd_gpio1   : std_logic := '0';",
	"        signal shslv_rd_gpio2   : std_logic := '0';",
	"        signal shslv_rd_gpio3   : std_logic := '0';",
	'        signal tim0_sh_en_n     : std_logic;   -- periph buses are active-LOW en/wen',
	'        signal tim1_sh_en_n     : std_logic;',
	'        signal shslv_tim0_en_q  : std_logic;   -- X-fix: falling-mclk registered strobes',
	'        signal shslv_tim1_en_q  : std_logic;   -- (snapshot capture clocks)',
	'        signal gpio1_sh_en_n    : std_logic;',
	'        signal gpio2_sh_en_n    : std_logic;',
	'        signal gpio3_sh_en_n    : std_logic;',
	'        signal tim0_sh_rdata    : std_logic_vector(31 downto 0);',
	'        signal tim1_sh_rdata    : std_logic_vector(31 downto 0);',
	'        signal gpio1_sh_rdata   : std_logic_vector(31 downto 0);',
	'        signal gpio2_sh_rdata   : std_logic_vector(31 downto 0);',
	'        signal gpio3_sh_rdata   : std_logic_vector(31 downto 0);',
	'        -- M7c movers: SPI1 + UART1 (M11: window slots 3/5)',
	'        signal shslv_spi1_sel,  shslv_spi1_en   : std_logic;',
	'        signal shslv_uart1_sel, shslv_uart1_en  : std_logic;',
	"        signal shslv_rd_spi1    : std_logic := '0';",
	"        signal shslv_rd_uart1   : std_logic := '0';",
	'        signal spi1_sh_en_n     : std_logic;',
	'        signal uart1_sh_en_n    : std_logic;',
	'        signal shslv_spi1_en_q  : std_logic;   -- X-fix: falling-mclk registered strobes',
	'        signal shslv_uart1_en_q : std_logic;   -- (snapshot capture clocks)',
	'        signal spi1_sh_rdata    : std_logic_vector(31 downto 0);',
	'        signal uart1_sh_rdata   : std_logic_vector(31 downto 0);',
]
SPI1_INPUT_TAPS = [
	'        cs1_in   <= prt2_in(pnum_gpio1_cs1);',
	'        -- MISO1 relocates to P4.6 (AF7, v2 spread slot ' + EMDASH + ' literal index, no pnum;',
	'        -- completes a full SPI1 on P4.4/5/6 at AF7); home pad is the default',
	'        miso1_in <= prt4_in(6)',
	'                    when p4_afs((3 * 6) + 2 downto 3 * 6) = "111"',
	'                    else prt2_in(pnum_gpio1_miso1);',
	'        mosi1_in <= prt2_in(pnum_gpio1_mosi1);',
	'        sck1_in  <= prt2_in(pnum_gpio1_sck1);',
	'        sck1_ren_in <= p2_ren(pnum_gpio1_sck1);',
	'        mosi1_ren_in <= p2_ren(pnum_gpio1_mosi1);',
	'        miso1_ren_in <= p4_ren(6)',
	'                        when p4_afs((3 * 6) + 2 downto 3 * 6) = "111"',
	'                        else p2_ren(pnum_gpio1_miso1);',
	'        -- cs1_ren_in <= p2_ren(pnum_gpio1_cs1);',
]
UART1_INPUT_MUXES = [
	'        -- GPIO1 Connections (UART1)',
	'        tx1_ren_in <= p3_ren(pnum_gpio2_af1_tx1)',
	'                      when p3_afs((3 * pnum_gpio2_af1_tx1) + 2 downto 3 * pnum_gpio2_af1_tx1) = "001"',
	'                      else p2_ren(pnum_gpio1_tx1);',
	'        rx1_ren_in <= p3_ren(pnum_gpio2_af1_rx1)',
	'                      when p3_afs((3 * pnum_gpio2_af1_rx1) + 2 downto 3 * pnum_gpio2_af1_rx1) = "001"',
	'                      else p2_ren(pnum_gpio1_rx1);',
	'        rx1_in <= prt3_in(pnum_gpio2_af1_rx1)',
	'                  when p3_afs((3 * pnum_gpio2_af1_rx1) + 2 downto 3 * pnum_gpio2_af1_rx1) = "001"',
	'                  else prt2_in(pnum_gpio1_rx1);',
]
GPIO1_PRIMARY_PLANES = [
	'        afunc2_out <= (',
	'            pnum_gpio1_rx1 => rx1_out,      -- GPIO1 pin 7',
	'            pnum_gpio1_tx1 => tx1_out,      -- GPIO1 pin 6',
	'            pnum_gpio1_rx0 => rx0_out,      -- GPIO1 pin 5',
	'            pnum_gpio1_tx0 => tx0_out,      -- GPIO1 pin 4',
	'            pnum_gpio1_sck1 => sck1_out,    -- GPIO1 pin 3',
	'            pnum_gpio1_mosi1 => mosi1_out,  -- GPIO1 pin 2',
	'            pnum_gpio1_miso1 => miso1_out,  -- GPIO1 pin 1',
	'            0 => p2_out(0)                  -- CS1 line manually toggled with GPIO1',
	'        );',
	'        afunc2_dir <= (',
	'            pnum_gpio1_rx1 => rx1_dir,      -- GPIO1 pin 7',
	'            pnum_gpio1_tx1 => tx1_dir,      -- GPIO1 pin 6',
	'            pnum_gpio1_rx0 => rx0_dir,      -- GPIO1 pin 5',
	'            pnum_gpio1_tx0 => tx0_dir,      -- GPIO1 pin 4',
	'            pnum_gpio1_sck1 => sck1_dir,    -- GPIO1 pin 3',
	'            pnum_gpio1_mosi1 => mosi1_dir,  -- GPIO1 pin 2',
	'            pnum_gpio1_miso1 => miso1_dir,  -- GPIO1 pin 1',
	'            0 => p2_dir(0)',
	'        );',
	'        afunc2_ren <= (',
	'            pnum_gpio1_rx1 => rx1_ren,      -- GPIO1 pin 7',
	'            pnum_gpio1_tx1 => tx1_ren,      -- GPIO1 pin 6',
	'            pnum_gpio1_rx0 => rx0_ren,      -- GPIO1 pin 5',
	'            pnum_gpio1_tx0 => tx0_ren,      -- GPIO1 pin 4',
	'            pnum_gpio1_sck1 => sck1_ren,    -- GPIO1 pin 3',
	'            pnum_gpio1_mosi1 => mosi1_ren,  -- GPIO1 pin 2',
	'            pnum_gpio1_miso1 => miso1_ren,  -- GPIO1 pin 1',
	'            0 => p2_ren(0)',
	'        );',
]
GPIO1_AF1_PLANES = [
	'        -- AF1 plane: TIMER0/1 compare (PWM) outputs on P2.0-3 (the SPI1 pins),',
	'        -- I2C1 relocation on P2.4/5 (v2), I2C0 relocation on P2.6/7 (the UART1 pins)',
	'        -- ' + EMDASH + ' both I2C buses land on this port at AF1.',
	'        afunc2_af1_out <= (',
	'            pnum_gpio1_af1_scl0 => scl0_out,        -- GPIO1 pin 7',
	'            pnum_gpio1_af1_sda0 => sda0_out,        -- GPIO1 pin 6',
	'            pnum_gpio1_af1_scl1 => scl1_out,        -- GPIO1 pin 5',
	'            pnum_gpio1_af1_sda1 => sda1_out,        -- GPIO1 pin 4',
	'            pnum_gpio1_af1_t1_cmp1 => t1_cmp1_out,  -- GPIO1 pin 3',
	'            pnum_gpio1_af1_t1_cmp0 => t1_cmp0_out,  -- GPIO1 pin 2',
	'            pnum_gpio1_af1_t0_cmp1 => t0_cmp1_out,  -- GPIO1 pin 1',
	'            pnum_gpio1_af1_t0_cmp0 => t0_cmp0_out   -- GPIO1 pin 0',
	'        );',
	'        afunc2_af1_dir <= (',
	'            pnum_gpio1_af1_scl0 => scl0_dir,        -- GPIO1 pin 7',
	'            pnum_gpio1_af1_sda0 => sda0_dir,        -- GPIO1 pin 6',
	'            pnum_gpio1_af1_scl1 => scl1_dir,        -- GPIO1 pin 5',
	'            pnum_gpio1_af1_sda1 => sda1_dir,        -- GPIO1 pin 4',
	'            pnum_gpio1_af1_t1_cmp1 => t1_cmp1_dir,  -- GPIO1 pin 3',
	'            pnum_gpio1_af1_t1_cmp0 => t1_cmp0_dir,  -- GPIO1 pin 2',
	'            pnum_gpio1_af1_t0_cmp1 => t0_cmp1_dir,  -- GPIO1 pin 1',
	'            pnum_gpio1_af1_t0_cmp0 => t0_cmp0_dir   -- GPIO1 pin 0',
	'        );',
	'        afunc2_af1_ren <= (',
	'            pnum_gpio1_af1_scl0 => scl0_ren,        -- GPIO1 pin 7',
	'            pnum_gpio1_af1_sda0 => sda0_ren,        -- GPIO1 pin 6',
	'            pnum_gpio1_af1_scl1 => scl1_ren,        -- GPIO1 pin 5',
	'            pnum_gpio1_af1_sda1 => sda1_ren,        -- GPIO1 pin 4',
	'            pnum_gpio1_af1_t1_cmp1 => t1_cmp1_ren,  -- GPIO1 pin 3',
	'            pnum_gpio1_af1_t1_cmp0 => t1_cmp0_ren,  -- GPIO1 pin 2',
	'            pnum_gpio1_af1_t0_cmp1 => t0_cmp1_ren,  -- GPIO1 pin 1',
	'            pnum_gpio1_af1_t0_cmp0 => t0_cmp0_ren   -- GPIO1 pin 0',
	'        );',
]
GPIO2_TIMER_MUXES = [
	'        -- Compare (PWM) outputs are available at three locations (home P3.0/1/4/5,',
	'        -- AF1 on P2.0-3, AF1 on P4.4-7): the peripheral ren_in follows the',
	'        -- selection with fixed priority P2 > P4 > home.',
	'        t0_cmp0_ren_in  <= p2_ren(pnum_gpio1_af1_t0_cmp0)',
	'                           when p2_afs((3 * pnum_gpio1_af1_t0_cmp0) + 2 downto 3 * pnum_gpio1_af1_t0_cmp0) = "001"',
	'                           else p4_ren(pnum_gpio3_af1_t0_cmp0)',
	'                           when p4_afs((3 * pnum_gpio3_af1_t0_cmp0) + 2 downto 3 * pnum_gpio3_af1_t0_cmp0) = "001"',
	'                           else p3_ren(pnum_gpio2_t0_cmp0);',
	'        t0_cmp1_ren_in  <= p2_ren(pnum_gpio1_af1_t0_cmp1)',
	'                           when p2_afs((3 * pnum_gpio1_af1_t0_cmp1) + 2 downto 3 * pnum_gpio1_af1_t0_cmp1) = "001"',
	'                           else p4_ren(pnum_gpio3_af1_t0_cmp1)',
	'                           when p4_afs((3 * pnum_gpio3_af1_t0_cmp1) + 2 downto 3 * pnum_gpio3_af1_t0_cmp1) = "001"',
	'                           else p3_ren(pnum_gpio2_t0_cmp1);',
	'        t1_cmp0_ren_in  <= p2_ren(pnum_gpio1_af1_t1_cmp0)',
	'                           when p2_afs((3 * pnum_gpio1_af1_t1_cmp0) + 2 downto 3 * pnum_gpio1_af1_t1_cmp0) = "001"',
	'                           else p4_ren(pnum_gpio3_af1_t1_cmp0)',
	'                           when p4_afs((3 * pnum_gpio3_af1_t1_cmp0) + 2 downto 3 * pnum_gpio3_af1_t1_cmp0) = "001"',
	'                           else p3_ren(pnum_gpio2_t1_cmp0);',
	'        t1_cmp1_ren_in  <= p2_ren(pnum_gpio1_af1_t1_cmp1)',
	'                           when p2_afs((3 * pnum_gpio1_af1_t1_cmp1) + 2 downto 3 * pnum_gpio1_af1_t1_cmp1) = "001"',
	'                           else p4_ren(pnum_gpio3_af1_t1_cmp1)',
	'                           when p4_afs((3 * pnum_gpio3_af1_t1_cmp1) + 2 downto 3 * pnum_gpio3_af1_t1_cmp1) = "001"',
	'                           else p3_ren(pnum_gpio2_t1_cmp1);',
	'',
	'        -- Capture inputs relocate to P4.0-3 (AF1); home pads stay the default',
	'        t0_cap0_in      <= prt4_in(pnum_gpio3_af1_t0_cap0)',
	'                           when p4_afs((3 * pnum_gpio3_af1_t0_cap0) + 2 downto 3 * pnum_gpio3_af1_t0_cap0) = "001"',
	'                           else prt3_in(pnum_gpio2_t0_cap0);',
	'        t0_cap1_in      <= prt4_in(pnum_gpio3_af1_t0_cap1)',
	'                           when p4_afs((3 * pnum_gpio3_af1_t0_cap1) + 2 downto 3 * pnum_gpio3_af1_t0_cap1) = "001"',
	'                           else prt3_in(pnum_gpio2_t0_cap1);',
	'        t1_cap0_in      <= prt4_in(pnum_gpio3_af1_t1_cap0)',
	'                           when p4_afs((3 * pnum_gpio3_af1_t1_cap0) + 2 downto 3 * pnum_gpio3_af1_t1_cap0) = "001"',
	'                           else prt3_in(pnum_gpio2_t1_cap0);',
	'        t1_cap1_in      <= prt4_in(pnum_gpio3_af1_t1_cap1)',
	'                           when p4_afs((3 * pnum_gpio3_af1_t1_cap1) + 2 downto 3 * pnum_gpio3_af1_t1_cap1) = "001"',
	'                           else prt3_in(pnum_gpio2_t1_cap1);',
	'        t0_cap0_ren_in  <= p4_ren(pnum_gpio3_af1_t0_cap0)',
	'                           when p4_afs((3 * pnum_gpio3_af1_t0_cap0) + 2 downto 3 * pnum_gpio3_af1_t0_cap0) = "001"',
	'                           else p3_ren(pnum_gpio2_t0_cap0);',
	'        t1_cap0_ren_in  <= p4_ren(pnum_gpio3_af1_t1_cap0)',
	'                           when p4_afs((3 * pnum_gpio3_af1_t1_cap0) + 2 downto 3 * pnum_gpio3_af1_t1_cap0) = "001"',
	'                           else p3_ren(pnum_gpio2_t1_cap0);',
	'        t0_cap1_ren_in  <= p4_ren(pnum_gpio3_af1_t0_cap1)',
	'                           when p4_afs((3 * pnum_gpio3_af1_t0_cap1) + 2 downto 3 * pnum_gpio3_af1_t0_cap1) = "001"',
	'                           else p3_ren(pnum_gpio2_t0_cap1);',
	'        t1_cap1_ren_in  <= p4_ren(pnum_gpio3_af1_t1_cap1)',
	'                           when p4_afs((3 * pnum_gpio3_af1_t1_cap1) + 2 downto 3 * pnum_gpio3_af1_t1_cap1) = "001"',
	'                           else p3_ren(pnum_gpio2_t1_cap1);',
]
GPIO2_PRIMARY_PLANES = [
	'        afunc3_out <= (',
	'            pnum_gpio2_t1_cap1 => t1_cap1_out,                  -- GPIO2 pin 7',
	'            pnum_gpio2_t1_cap0 => p3_out(pnum_gpio2_t1_cap0),   -- GPIO2 pin 6',
	'            pnum_gpio2_t1_cmp1 => t1_cmp1_out,                  -- GPIO2 pin 5',
	'            pnum_gpio2_t1_cmp0 => t1_cmp0_out,                  -- GPIO2 pin 4',
	'            pnum_gpio2_t0_cap1 => t0_cap1_out,                  -- GPIO2 pin 3',
	'            pnum_gpio2_t0_cap0 => p3_out(pnum_gpio2_t0_cap0),   -- GPIO2 pin 2',
	'            pnum_gpio2_t0_cmp1 => t0_cmp1_out,                  -- GPIO2 pin 1',
	'            pnum_gpio2_t0_cmp0 => t0_cmp0_out                   -- GPIO2 pin 0',
	'        );',
	'        afunc3_dir <= (',
	'            pnum_gpio2_t1_cap1 => t1_cap1_dir, -- GPIO2 pin 7',
	'            pnum_gpio2_t1_cap0 => t1_cap0_dir, -- GPIO2 pin 6',
	'            pnum_gpio2_t1_cmp1 => t1_cmp1_dir, -- GPIO2 pin 5',
	'            pnum_gpio2_t1_cmp0 => t1_cmp0_dir, -- GPIO2 pin 4',
	'            pnum_gpio2_t0_cap1 => t0_cap1_dir, -- GPIO2 pin 3',
	'            pnum_gpio2_t0_cap0 => t0_cap0_dir, -- GPIO2 pin 2',
	'            pnum_gpio2_t0_cmp1 => t0_cmp1_dir, -- GPIO2 pin 1',
	'            pnum_gpio2_t0_cmp0 => t0_cmp0_dir  -- GPIO2 pin 0',
	'        );',
	'        afunc3_ren <= (',
	'            pnum_gpio2_t1_cap1 => t1_cap1_ren, -- GPIO2 pin 7',
	'            pnum_gpio2_t1_cap0 => t1_cap0_ren, -- GPIO2 pin 6',
	'            pnum_gpio2_t1_cmp1 => t1_cmp1_ren, -- GPIO2 pin 5',
	'            pnum_gpio2_t1_cmp0 => t1_cmp0_ren, -- GPIO2 pin 4',
	'            pnum_gpio2_t0_cap1 => t0_cap1_ren, -- GPIO2 pin 3',
	'            pnum_gpio2_t0_cap0 => t0_cap0_ren, -- GPIO2 pin 2',
	'            pnum_gpio2_t0_cmp1 => t0_cmp1_ren, -- GPIO2 pin 1',
	'            pnum_gpio2_t0_cmp0 => t0_cmp0_ren  -- GPIO2 pin 0',
	'        );',
]
GPIO3_AF1_PLANES = [
	'        -- AF1 plane: TIMER0/1 capture inputs relocate to P4.0-3 (the I2C pins),',
	'        -- TIMER0/1 compare (PWM) outputs relocate to P4.4-7 (the dead DTP pins).',
	"        -- Captures are inputs: out slice '0', dir/ren from the timer.",
	'        afunc4_af1_out <= (',
	'            pnum_gpio3_af1_t1_cmp1 => t1_cmp1_out,  -- GPIO3 pin 7',
	'            pnum_gpio3_af1_t1_cmp0 => t1_cmp0_out,  -- GPIO3 pin 6',
	'            pnum_gpio3_af1_t0_cmp1 => t0_cmp1_out,  -- GPIO3 pin 5',
	'            pnum_gpio3_af1_t0_cmp0 => t0_cmp0_out,  -- GPIO3 pin 4',
	"            pnum_gpio3_af1_t1_cap1 => '0',          -- GPIO3 pin 3",
	"            pnum_gpio3_af1_t1_cap0 => '0',          -- GPIO3 pin 2",
	"            pnum_gpio3_af1_t0_cap1 => '0',          -- GPIO3 pin 1",
	"            pnum_gpio3_af1_t0_cap0 => '0'           -- GPIO3 pin 0",
	'        );',
	'        afunc4_af1_dir <= (',
	'            pnum_gpio3_af1_t1_cmp1 => t1_cmp1_dir,  -- GPIO3 pin 7',
	'            pnum_gpio3_af1_t1_cmp0 => t1_cmp0_dir,  -- GPIO3 pin 6',
	'            pnum_gpio3_af1_t0_cmp1 => t0_cmp1_dir,  -- GPIO3 pin 5',
	'            pnum_gpio3_af1_t0_cmp0 => t0_cmp0_dir,  -- GPIO3 pin 4',
	'            pnum_gpio3_af1_t1_cap1 => t1_cap1_dir,  -- GPIO3 pin 3',
	'            pnum_gpio3_af1_t1_cap0 => t1_cap0_dir,  -- GPIO3 pin 2',
	'            pnum_gpio3_af1_t0_cap1 => t0_cap1_dir,  -- GPIO3 pin 1',
	'            pnum_gpio3_af1_t0_cap0 => t0_cap0_dir   -- GPIO3 pin 0',
	'        );',
	'        afunc4_af1_ren <= (',
	'            pnum_gpio3_af1_t1_cmp1 => t1_cmp1_ren,  -- GPIO3 pin 7',
	'            pnum_gpio3_af1_t1_cmp0 => t1_cmp0_ren,  -- GPIO3 pin 6',
	'            pnum_gpio3_af1_t0_cmp1 => t0_cmp1_ren,  -- GPIO3 pin 5',
	'            pnum_gpio3_af1_t0_cmp0 => t0_cmp0_ren,  -- GPIO3 pin 4',
	'            pnum_gpio3_af1_t1_cap1 => t1_cap1_ren,  -- GPIO3 pin 3',
	'            pnum_gpio3_af1_t1_cap0 => t1_cap0_ren,  -- GPIO3 pin 2',
	'            pnum_gpio3_af1_t0_cap1 => t0_cap1_ren,  -- GPIO3 pin 1',
	'            pnum_gpio3_af1_t0_cap0 => t0_cap0_ren   -- GPIO3 pin 0',
	'        );',
]
ANALOG_TIE_OFFS = [
	'    -- AFE / SARADC removed (digital-only Castalia). Peripheral-window slots',
	'    -- 11/12 (0x4B00/0x4C00) and IRQ vectors 55/56 are reserved gaps (read 0,',
	'    -- tied low). Tie off the GPIO alt-function outputs the two analog blocks',
	'    -- used to drive so those pins act as plain GPIO:',
	'    --   GPIO2 pins 3/7 (T0/T1 CAP1 out, formerly SARADC DTP0/1)',
	'    --   GPIO3 pins 4-7 (formerly AFE DTP0-3)',
	"    t0_cap1_out <= '0';",
	"    t1_cap1_out <= '0';",
	"    dtp0_out <= '0';  dtp0_dir <= '0';  dtp0_ren <= '0';",
	"    dtp1_out <= '0';  dtp1_dir <= '0';  dtp1_ren <= '0';",
	"    dtp2_out <= '0';  dtp2_dir <= '0';  dtp2_ren <= '0';",
	"    dtp3_out <= '0';  dtp3_dir <= '0';  dtp3_ren <= '0';",
]

# digperiphs #1 (2026-07-18): page-0 slot 12 (0x4C00) is shared real estate.
# By default the four AFE register stubs + the shared EIS engine stub occupy it
# (transcribed VERBATIM below — they were fixed template content until this
# carve; emitted whenever geo['afeStubs'], the Castalia golden-master default,
# so the default MCU.vhd stays byte-identical). With afeStubs off the QSPI0
# controller can claim the slot instead (geo['qspi']); the two are mutually
# exclusive. The AFE decl/instance blocks are emitted by emitSlot12Decls /
# emitSlot12Instances (the --@GEN:slot12-decls@ / slot12-instances@ markers).
AFE_SLOT12_DECLS = [
	'        -- CQ2a: AFE digital register stubs (four 64 B sub-slots of page-0 slot',
	'        -- 12 @0x4C00/40/80/C0) + the shared EIS engine stub (carved from the',
	'        -- IRQ-router page top quarter @0x7C00-0x7FFF). Each is an afe_stub',
	'        -- with an s_master ownership gate; the EIS block is hart-0-only.',
	'        -- Reads are REGISTERED (no bridge). See afe_stub.vhd.',
	'        signal shslv_afe_sel    : std_logic;   -- page-0 slot 12 (0x4C00) hit',
	'        signal shslv_afe0_sel,  shslv_afe0_en  : std_logic;',
	'        signal shslv_afe1_sel,  shslv_afe1_en  : std_logic;',
	'        signal shslv_afe2_sel,  shslv_afe2_en  : std_logic;',
	'        signal shslv_afe3_sel,  shslv_afe3_en  : std_logic;',
	'        signal shslv_eis_sel,   shslv_eis_en   : std_logic;',
	"        signal shslv_rd_afe0    : std_logic := '0';",
	"        signal shslv_rd_afe1    : std_logic := '0';",
	"        signal shslv_rd_afe2    : std_logic := '0';",
	"        signal shslv_rd_afe3    : std_logic := '0';",
	"        signal shslv_rd_eis     : std_logic := '0';",
	'        signal afe0_rdata       : std_logic_vector(31 downto 0);',
	'        signal afe1_rdata       : std_logic_vector(31 downto 0);',
	'        signal afe2_rdata       : std_logic_vector(31 downto 0);',
	'        signal afe3_rdata       : std_logic_vector(31 downto 0);',
	'        signal eis_rdata        : std_logic_vector(31 downto 0);',
	"        -- CQ2a: level IRQ from each stub's IF word. NOT yet routed to the",
	'        -- irq_router (the frozen 85-source map has only 2 reserved slots for 5',
	'        -- needed sources — see the CQ2a report); aggregated here for a clean',
	'        -- future hookup and observability.',
	'        signal afe_eis_irq      : std_logic_vector(4 downto 0);',
]
AFE_SLOT12_INSTANCES = [
	'    -- =========================================================================',
	'    -- CQ2a: AFE digital register stubs + shared EIS engine stub.',
	'    -- Four AFE sites subdivide page-0 slot 12 (0x4C00) into 64 B sub-slots',
	'    -- (sub-slot = sh_addr(5:4)); each answers only for its owner hart OR hart 0',
	'    -- (mp_arbiter s_master gate, inside afe_stub). The EIS engine lives in the',
	'    -- IRQ-router page top quarter (0x7C00-0x7FFF, carved in the sub-decode',
	"    -- above — irq_router's ADDR_W=10 decode is inert there) and is hart-0-only",
	'    -- (OWNER_HART=0). Reads are registered; denied reads return 0, denied',
	'    -- writes drop — no bus error, no stall, no arbiter-contract change. Every',
	'    -- stub resets all-zero -> a provable NO-OP (irq low) until software writes.',
	'    -- =========================================================================',
	'    afe0: entity work.afe_stub',
	'        generic map (OWNER_HART => 0)   -- 0x4C00: hart 0 only',
	'        port map (clk => mclk, resetn => resetn, en => shslv_afe0_en,',
	'            we => sh_we, addr => sh_addr(3 downto 0), wdata => sh_wdata,',
	'            master => sh_master, rdata => afe0_rdata, irq => afe_eis_irq(0));',
	'    afe1: entity work.afe_stub',
	'        generic map (OWNER_HART => 1)   -- 0x4C40: hart 1 or hart 0',
	'        port map (clk => mclk, resetn => resetn, en => shslv_afe1_en,',
	'            we => sh_we, addr => sh_addr(3 downto 0), wdata => sh_wdata,',
	'            master => sh_master, rdata => afe1_rdata, irq => afe_eis_irq(1));',
	'    afe2: entity work.afe_stub',
	'        generic map (OWNER_HART => 2)   -- 0x4C80: hart 2 or hart 0',
	'        port map (clk => mclk, resetn => resetn, en => shslv_afe2_en,',
	'            we => sh_we, addr => sh_addr(3 downto 0), wdata => sh_wdata,',
	'            master => sh_master, rdata => afe2_rdata, irq => afe_eis_irq(2));',
	'    afe3: entity work.afe_stub',
	'        generic map (OWNER_HART => 3)   -- 0x4CC0: hart 3 or hart 0',
	'        port map (clk => mclk, resetn => resetn, en => shslv_afe3_en,',
	'            we => sh_we, addr => sh_addr(3 downto 0), wdata => sh_wdata,',
	'            master => sh_master, rdata => afe3_rdata, irq => afe_eis_irq(3));',
	'    eis0: entity work.afe_stub',
	'        generic map (OWNER_HART => 0)   -- 0x7C00: EIS engine, hart 0 only',
	'        port map (clk => mclk, resetn => resetn, en => shslv_eis_en,',
	'            we => sh_we, addr => sh_addr(3 downto 0), wdata => sh_wdata,',
	'            master => sh_master, rdata => eis_rdata, irq => afe_eis_irq(4));',
]

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
	def __init__(self, gen, npuBlocks=None, i2c1Blocks=None, uart1Blocks=None,
			spi1Blocks=None, timer1Blocks=None):
		self.gen = gen
		self.periphsByName = {}
		for p in gen.Peripherals:
			self.periphsByName[p.Name] = p
		self.slotSpelling = gen.McuMpCompat['periphSlotSpelling']
		self.irqVectors = gen.McuMpCompat['irqVectors']

		# A2 (Argus): shared-window geometry — SH_AW, bank count and NPU
		# presence drive the memory-slave regions. Castalia defaults.
		geo = getattr(gen, 'McuMpGeometry', None) or {}
		self.shAw = geo.get('shAw', 15)
		self.banks = geo.get('sharedRamBanks', 4)
		self.npu = geo.get('npu', True)
		self.npuBlocks = npuBlocks or {}
		# G1a: droppable second I2C instance (the first config-droppable
		# peripheral INSTANCE — window slot 15, vectors 70-82, SDA1/SCL1 pads)
		self.i2c1 = geo.get('i2c1', True)
		self.i2c1Blocks = i2c1Blocks or {}
		# G1b: droppable UART1 / SPI1 / TIMER1 instances (window slots 5/3/7,
		# vectors 52-54 / 11-12 / 22-27; primaries on P2.6/7, P2.0-3, P3.4-7)
		self.uart1 = geo.get('uart1', True)
		self.uart1Blocks = uart1Blocks or {}
		self.spi1 = geo.get('spi1', True)
		self.spi1Blocks = spi1Blocks or {}
		self.timer1 = geo.get('timer1', True)
		self.timer1Blocks = timer1Blocks or {}
		# digperiphs #1: page-0 slot 12 (0x4C00) occupant. afeStubs (default,
		# golden master) = the four AFE stubs + shared EIS engine stub; qspi =
		# the QSPI0 controller instead. Mutually exclusive (both decode slot 12).
		self.afeStubs = geo.get('afeStubs', True)
		self.qspi = geo.get('qspi', False)
		if self.afeStubs and self.qspi:
			raise Exception('MCU.vhd emitter: afeStubs and qspi both claim page-0 slot 12')
		# digperiphs #2: I3C0 in MUTEX-page (page 2) sub-slot 1 @0x6100. When set,
		# the mutex-bank decode is tightened to sub-slot 0 (0x6000-0x60FF) and a
		# page-2 sub-decode + the I3C0 shim/instance are hand-emitted. I3C0 is NOT
		# a page-0 shim peripheral, so it lives outside shslv/pg0SelOrder/rdOrder
		# (its rd-sel, rdata-mux and enable are emitted in explicit self.i3c blocks,
		# the AFE-stub precedent). Default false => every one of those is inert.
		self.i3c = geo.get('i3c', False)
		# digperiphs #3: NFC0 in MUTEX-page (page 2) sub-slot 2 @0x6200. Same shape
		# as I3C0 (native slave outside the page-0 shim fabric; hand-emitted
		# sub-decode + shim/instance under self.nfc). When either I3C or NFC is
		# present the mutex-bank decode is tightened to sub-slot 0. Default false.
		self.nfc = geo.get('nfc', False)
		# digperiphs #4: RTC0 in MUTEX-page (page 2) sub-slot 5 @0x6500. Same
		# native-slave shape as I3C0/NFC0/GPIO4/GPIO5 (outside the page-0 shim
		# fabric; hand-emitted sub-decode + shim/instance under self.rtc), but with
		# a PLAIN raw-strobe en shim — NO falling_edge(EnMemPeriph) pre-latch and NO
		# CAPTURE_CLOCK en_q (D4): the first library block clean of both. Default
		# false => every RTC region is inert (byte-identical default).
		self.rtc = geo.get('rtc', False)

		# Geometry-filtered copies of the transcribed structure tables. The
		# module-level tables stay the Castalia golden-master transcription;
		# these are what the emitters consume.
		self.shslv = dict(SHSLV)
		self.pg0SelOrder = list(PG0_SEL_ORDER)
		self.busSpecs = dict(BUS_SPECS)
		self.shimGroups = list(SHIM_GROUPS)
		self.memslv = {'rom': 'rom_q'}
		if self.npu:
			self.memslv['npuram'] = 'npuram_q'
		for b in range(self.banks):
			self.memslv['bank' + str(b)] = 'bank' + str(b) + '_q'
		if not self.npu:
			del self.shslv['NPU']
			self.pg0SelOrder.remove('NPU')
			del self.busSpecs['npu0']
			self.shimGroups = [g for g in self.shimGroups if g[1] != ['NPU']]
		if not self.i2c1:
			del self.shslv['I2C1']
			self.pg0SelOrder.remove('I2C1')
			del self.busSpecs['i2c1']
			groups = []
			for (comment, names, pad) in self.shimGroups:
				if 'I2C1' in names:
					names = [n for n in names if n != 'I2C1']
					comment = [c.replace('I2C0/I2C1', 'I2C0 (I2C1 dropped)') for c in comment]
				groups.append((comment, names, pad))
			self.shimGroups = groups
		# G1b drops: same shslv/order/bus/shim treatment as I2C1. The M7c shim
		# group covers SPI1+UART1 (comment reworded per survivor; the group
		# disappears when both are dropped); TIMER1 leaves the M7b group whose
		# comment stays valid for the surviving TIMER0/GPIO movers.
		for flag, pname, bkey in ((self.uart1, 'UART1', 'uart1'),
				(self.spi1, 'SPI1', 'spi1'), (self.timer1, 'TIMER1', 'timer1')):
			if flag:
				continue
			del self.shslv[pname]
			self.pg0SelOrder.remove(pname)
			del self.busSpecs[bkey]
			self.shimGroups = [(c, [n for n in ns if n != pname], p)
				for (c, ns, p) in self.shimGroups]
		if not (self.spi1 and self.uart1):
			if self.spi1 and not self.uart1:
				m7c = ["-- M7c: SPI1 (UART1 dropped by this configuration; audited clean;",
					"-- SPI1's flash FSM is compiled out by ENABLE_EXTENDED_MEM=false, and",
					'-- its baud core runs on smclk ' + EMDASH + ' the SYS_CLK_CR=0 rule applies to',
					'-- SPI software too)']
			elif self.uart1 and not self.spi1:
				m7c = ['-- M7c: UART1 (SPI1 dropped by this configuration; audited clean ' + EMDASH,
					'-- its baud core runs on smclk, so the SYS_CLK_CR=0 rule applies)']
			else:
				m7c = None	# both dropped: the whole M7c shim group disappears
			groups = []
			for (comment, names, pad) in self.shimGroups:
				if comment and comment[0].startswith('-- M7c: SPI1'):
					if m7c is None:
						continue
					comment = m7c
				groups.append((comment, names, pad))
			self.shimGroups = groups
		# digperiphs #1: QSPI0 is an ADDED page-0 slot-12 slave (the opposite of
		# the droppable instances above). It enters the shim/decode/read-mux
		# fabric like any 'periph' peripheral; its instance (with the QSPI serial
		# pins) is emitted by emitSlot12Instances, not a bus: side block.
		if self.qspi:
			self.shslv['QSPI0'] = {'sel': 'qspi0', 'shim': 'qspi0', 'rdata': 'qspi0_sh_rdata'}
			insertAt = self.pg0SelOrder.index('GPIO3') if 'GPIO3' in self.pg0SelOrder else len(self.pg0SelOrder)
			self.pg0SelOrder.insert(insertAt, 'QSPI0')	# slot 12, between NPU (10) and GPIO3 (13)
			self.shimGroups.append((
				['-- digperiphs #1: QSPI0 (slot 12 @0x4C00) shim. Registered read',
				 '-- (no bridge); smclk baud core (SYS_CLK_CR=0 rule). Active-low',
				 '-- one-cycle en + resv-gated lanes like the other shim peripherals.'],
				['QSPI0'], 14))
		self.shimGroups = [g for g in self.shimGroups if g[1]]
		# digperiphs #2: I3C0 is a sharedBus='native' slave, but it lives on the
		# MUTEX page (not page 0), so its SEL is hand-decoded in emitShslvSubdecode
		# rather than the pg0SelOrder loop. It DOES join the shslv/en/rd fabric so
		# the standard enable, registered rd-sel and rdata-mux loops cover it (the
		# instance emits its own active-low en shim). shim=None = no polarity-shim
		# group (like the other native slaves); its en_n is made in emitI3cInstance.
		if self.i3c:
			self.shslv = dict(self.shslv)
			self.shslv['I3C0'] = {'sel': 'i3c0', 'shim': None, 'rdata': 'i3c0_sh_rdata'}
		# digperiphs #3: NFC0 joins the same native-slave fabric (MUTEX-page
		# sub-slot 2). Its SEL is hand-decoded in emitShslvSubdecode; the shslv
		# entry (shim=None) puts it through the standard enable / registered rd-sel
		# / rdata-mux loops, and its active-low en shim lives in emitNfcInstance.
		if self.nfc:
			self.shslv = dict(self.shslv)
			self.shslv['NFC0'] = {'sel': 'nfc0', 'shim': None, 'rdata': 'nfc0_sh_rdata'}
		# digperiphs #4: RTC0 joins the same native-slave fabric (MUTEX-page
		# sub-slot 5). Its SEL is hand-decoded in emitShslvSubdecode; the shslv
		# entry (shim=None) puts it through the standard enable / registered rd-sel
		# / rdata-mux loops, and its active-low RAW-strobe en shim lives in
		# emitRtcInstance (no en_q register — D4).
		if self.rtc:
			self.shslv = dict(self.shslv)
			self.shslv['RTC0'] = {'sel': 'rtc0', 'shim': None, 'rdata': 'rtc0_sh_rdata'}
		# Mission B: GPIO4/GPIO5 are UNCONDITIONAL native slaves on the MUTEX page
		# (sub-slots 3/4 @0x6300/0x6400). Same native-fabric membership as I3C0/NFC0
		# (shim=None, hand-decoded SEL, own en_n shim inside the instance emitter),
		# but the instance is a full GPIO block with a registered-read shim + AF
		# muxing. They join the enable / registered rd-sel / rdata-mux loops.
		self.shslv = dict(self.shslv)
		self.shslv['GPIO4'] = {'sel': 'gpio4', 'shim': None, 'rdata': 'gpio4_sh_rdata'}
		self.shslv['GPIO5'] = {'sel': 'gpio5', 'shim': None, 'rdata': 'gpio5_sh_rdata'}
		nativeOrder = ['CLINT', 'MUTEX', 'IRQROUTER', 'PWRCTRL'] \
			+ (['I3C0'] if self.i3c else []) + (['NFC0'] if self.nfc else []) \
			+ ['GPIO4', 'GPIO5'] + (['RTC0'] if self.rtc else [])
		self.enOrder = ['rom'] \
			+ (['npuram'] if self.npu else []) \
			+ ['bank' + str(b) for b in range(self.banks)] \
			+ nativeOrder + self.pg0SelOrder
		self.rdOrder = list(self.enOrder)

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
		rtlShared = set(n for n in self.shslv if self.shslv[n]['shim'] is not None)
		if descShared != rtlShared:
			raise Exception('MCU.vhd emitter: sharedBus=periph peripherals ' + str(sorted(descShared))
				+ ' do not match the transcribed RTL fabric ' + str(sorted(rtlShared))
				+ ' (update the SHSLV/order tables in mcu_vhd.py from the RTL)')
		descNative = set(p.Name for p in self.gen.Peripherals if getattr(p, 'SharedBus', None) == 'native')
		rtlNative = set(n for n in self.shslv if self.shslv[n]['shim'] is None)
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
		expectComb = set(['I2C0']) | (set(['I2C1']) if self.i2c1 else set()) | (set(['NPU']) if self.npu else set())
		if descComb != expectComb:
			raise Exception('MCU.vhd emitter: combinationalRead peripherals ' + str(sorted(descComb))
				+ ' do not match the transcribed rdata-bridge membership ' + str(sorted(expectComb)))

		# 4. Order lists must cover the shared set exactly
		if set(self.pg0SelOrder) != rtlShared:
			raise Exception('MCU.vhd emitter: PG0_SEL_ORDER does not cover the window-slot peripherals')
		slots = [self.winSlot(n) for n in self.pg0SelOrder + PG0_NATIVE_ORDER]
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
		if set(self.rdOrder) != rtlShared | rtlNative | set(self.memslv):
			raise Exception('MCU.vhd emitter: RD_ORDER does not cover the shared slaves')
		if set(self.enOrder) != rtlShared | rtlNative | set(self.memslv):
			raise Exception('MCU.vhd emitter: EN_ORDER does not cover the shared slaves')
		shimAll = set()
		for _, names, _ in self.shimGroups:
			shimAll |= set(names)
		if shimAll != rtlShared:
			raise Exception('MCU.vhd emitter: SHIM_GROUPS do not cover the shared peripherals')

		# 5. A2 geometry sanity: the window must round to a power of two that
		# holds the bank row, and the NPU-block splice source must be loaded
		# whenever the NPU is present.
		if 0x10000 + self.banks * 0x4000 > (1 << (self.shAw + 2)):
			raise Exception('MCU.vhd emitter: ' + str(self.banks) + ' banks do not fit under SH_AW=' + str(self.shAw))
		if self.npu and self.npuBlocks == {}:
			raise Exception('MCU.vhd emitter: NPU present but MCU.template.npu.vhd blocks were not loaded')
		if self.i2c1 and self.i2c1Blocks == {}:
			raise Exception('MCU.vhd emitter: I2C1 present but MCU.template.i2c1.vhd blocks were not loaded')
		for flag, blocks, tpl in ((self.uart1, self.uart1Blocks, 'uart1'),
				(self.spi1, self.spi1Blocks, 'spi1'), (self.timer1, self.timer1Blocks, 'timer1')):
			if flag and blocks == {}:
				raise Exception('MCU.vhd emitter: ' + tpl.upper() + ' present but MCU.template.'
					+ tpl + '.vhd blocks were not loaded')

		# 6. G1b: every FromSpread altFunc must be a known output-pool member
		# (SPREAD_SIG owns the RTL signal spelling the spread planes wire)
		for gi in range(4):
			for pin in self.periph('GPIO' + str(gi)).Pins:
				for af in pin.AltFuncs:
					if getattr(af, 'FromSpread', False) and af.Name not in SPREAD_SIG:
						raise Exception('MCU.vhd emitter: spread function ' + af.Name
							+ ' (GPIO' + str(gi) + ' pin ' + str(pin.BitNumber) + ' AF'
							+ str(af.Index) + ') has no SPREAD_SIG spelling')

	def winSlot(self, name):
		'''Peripheral-window page-0 slot (the LEGACY 0x4000-page slot number).'''
		p = self.periph(name)
		slot = p.LegacySlot
		if slot is None or slot < 0 or slot > 15:
			raise Exception('MCU.vhd emitter: ' + name + ' has no valid window slot')
		return slot

	def selOf(self, key):
		'''EN/RD_ORDER key -> shslv_<sel> spelling (peripheral or memory slave).'''
		if key in self.memslv:
			return key
		return self.shslv[key]['sel']

	def rdataOf(self, key):
		'''EN/RD_ORDER key -> the rdata net muxed into sh_rdata_mux.'''
		if key in self.memslv:
			return self.memslv[key]
		sig = self.shslv[key]['rdata']
		if getattr(self.periph(key), 'CombinationalRead', False):
			pass	# the bridge-registered net keeps the plain name
		return sig

	def rdataSignal(self, name):
		'''Signal the instance drives: bridge slaves drive the _c (combinational) net.'''
		sig = self.shslv[name]['rdata']
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
				# Mission B: 6 GPIO ports now (GPIO4/GPIO5 added), all declared here.
				for port in range(6):
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
			if irqbName == 'IRQB_RSVD55' and self.afeStubs:
				# CQ2b: ex-AFE0 slot = the AGGREGATED AFE_SHARED source. OR of the
				# four per-hart AFE IF level lines; hart 0 (the only master that
				# can read all four AFE IF words) demuxes it in its source-55 handler.
				lines.append(' ' * 12 + irqbName.ljust(16)
					+ '=> afe_eis_irq(0) or afe_eis_irq(1) or afe_eis_irq(2) or afe_eis_irq(3),')
				continue
			if irqbName == 'IRQB_RSVD56' and self.afeStubs:
				# CQ2b: ex-SARADC0 slot = the shared EIS engine level (hart-0-only).
				lines.append(' ' * 12 + irqbName.ljust(16) + '=> afe_eis_irq(4),')
				continue
			if irqbName.startswith('IRQB_RSVD'):
				continue	# reserved vector gap — falls through to 'others => irq_tielow'
			lines.append(' ' * 12 + irqbName.ljust(16) + '=> ' + self.irqSignalName(irqbName) + ',')
		lines.append(' ' * 12 + '-- M19: the CLINT slots (83/84) fall through to irq_tielow — every')
		lines.append(' ' * 12 + "-- hart gets its own msip/mtip on dedicated wires; the source")
		lines.append(' ' * 12 + '-- vector feeds ONLY the irq_router (meip claim/complete delivery)')
		lines.append(' ' * 12 + 'others          => irq_tielow')
		lines.append(' ' * 8 + ');')
		return lines

	def pageBits(self, page):
		'''Page code at the geometry's width (SH_AW-12 bits; 3 = Castalia).'''
		return format(page, '0' + str(self.shAw - 12) + 'b')

	def pageSlice(self):
		return 'sh_addr(' + str(self.shAw - 1) + ' downto 12)'

	def emitShslvSubdecode(self):
		ind = ' ' * 4
		clintBits = format((CLINT_BASE >> 12) & 3, '02b')
		mtxBits = format((MUTEX_BASE >> 12) & 3, '02b')
		irtrBits = format((IRQROUTER_BASE >> 12) & 3, '02b')
		psl = self.pageSlice()
		lines = []
		# NOTE the comment spells the ARBITER port name (s_addr), the code the
		# fabric net (sh_addr) — transcribed from the golden master.
		lines.append(ind + '-- M11/M12: page select on s_addr(' + str(self.shAw - 1) + ':12). Page ' + self.pageBits(0) + ' is the shared boot')
		lines.append(ind + '-- ROM (M12 ' + EMDASH + ' the single rom_hvt_pg all ' + self.hartsWord() + ' harts reset into);')
		lines.append(ind + '-- ' + self.pageBits(2) + ' is the TCM region (tile-private, never arrives here).')
		lines.append(ind + 'shslv_rom_sel'.ljust(16) + ' <= \'1\' when ' + psl + ' = "' + self.pageBits(0) + '" else \'0\';')
		lines.append(ind + 'shslv_perwin_sel'.ljust(16) + ' <= \'1\' when ' + psl + ' = "' + self.pageBits(1) + '" else \'0\';')
		if self.npu:
			lines.append(ind + 'shslv_npuram_sel'.ljust(16) + ' <= \'1\' when ' + psl + ' = "' + self.pageBits(3) + '" else \'0\';')
		for b in range(self.banks):
			lines.append(ind + ('shslv_bank' + str(b) + '_sel').ljust(16) + ' <= \'1\' when ' + psl + ' = "'
				+ self.pageBits(4 + b) + '" else \'0\';')
		lines.append(ind + '-- peripheral-window pages on sh_addr(11:10): page 0 = the 16 slots,')
		lines.append(ind + '-- page 1 = CLINT, page 2 = MUTEX bank, page 3 = IRQ router')
		lines.append(ind + 'shslv_pg0_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "00" else \'0\';')
		lines.append(ind + 'shslv_clint_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + clintBits + '" else \'0\';')
		# Mission B: page-2 (MUTEX/0x6000) is ALWAYS carved into 256 B sub-slots on
		# sh_addr(9:6) now — GPIO4/GPIO5 (sub-slots 3/4) are unconditional. The mutex
		# bank keeps sub-slot 0 (0x6000-0x60FF); I3C0 sub-slot 1 (0x6100), NFC0
		# sub-slot 2 (0x6200), GPIO4 sub-slot 3 (0x6300), GPIO5 sub-slot 4 (0x6400);
		# the rest reserved. Tightening the mutex decode from the page-wide alias
		# retires the aliased CLAIM side effect (an aliased mutex read used to fire an
		# atomic claim). All 16 mutexes live below 0x6040, so this is behaviorally safe.
		lines.append(ind + '-- Mission B: page-2 (MUTEX/0x6000) carved into 256 B sub-slots on')
		lines.append(ind + '-- sh_addr(9:6). Mutex bank = sub-slot 0 (0x6000-0x60FF); I3C0 sub-slot 1')
		lines.append(ind + '-- (0x6100), NFC0 sub-slot 2 (0x6200), GPIO4 sub-slot 3 (0x6300), GPIO5')
		lines.append(ind + '-- sub-slot 4 (0x6400). Tightening the mutex decode retires the aliased')
		lines.append(ind + '-- CLAIM side effect (all 16 mutexes live below 0x6040 = behaviorally safe).')
		lines.append(ind + 'shslv_mtx_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + mtxBits + '" and sh_addr(9 downto 6) = "0000" else \'0\';')
		if self.i3c:
			lines.append(ind + 'shslv_i3c0_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + mtxBits + '" and sh_addr(9 downto 6) = "0001" else \'0\';')
		if self.nfc:
			lines.append(ind + 'shslv_nfc0_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + mtxBits + '" and sh_addr(9 downto 6) = "0010" else \'0\';')
		lines.append(ind + 'shslv_gpio4_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + mtxBits + '" and sh_addr(9 downto 6) = "0011" else \'0\';')
		lines.append(ind + 'shslv_gpio5_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + mtxBits + '" and sh_addr(9 downto 6) = "0100" else \'0\';')
		if self.rtc:
			# digperiphs #4: RTC0 = page-2 sub-slot 5 (0x6500).
			lines.append(ind + 'shslv_rtc0_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + mtxBits + '" and sh_addr(9 downto 6) = "0101" else \'0\';')
		if self.afeStubs:
			lines.append(ind + '-- CQ2a: page-3 sub-decode ' + EMDASH + ' irq_router keeps 0x7000-0x7BFF; the shared')
			lines.append(ind + '-- EIS engine stub owns the top quarter 0x7C00-0x7FFF (irq_router ADDR_W=10')
			lines.append(ind + '-- decode is inert above word 522, so this removes only never-used aliased space).')
			lines.append(ind + 'shslv_irtr_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + irtrBits + '" and sh_addr(9 downto 8) /= "11" else \'0\';')
			lines.append(ind + 'shslv_eis_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + irtrBits + '" and sh_addr(9 downto 8) = "11" else \'0\';')
		else:
			# digperiphs #1: no EIS stub — irq_router owns the whole page 3.
			lines.append(ind + 'shslv_irtr_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + irtrBits + '" else \'0\';')
		lines.append(ind + '-- page-0 slots (slot = sh_addr(9:6)) at the LEGACY 0x4000 numbering ' + EMDASH)
		lines.append(ind + '-- every peripheral back at its original Myshkin address, shared by')
		lines.append(ind + '-- all ' + str(self.nHarts()) + ' harts')
		for name in self.pg0SelOrder:
			selName = 'shslv_' + self.shslv[name]['sel'] + '_sel'
			lines.append(ind + selName.ljust(16) + ' <= shslv_pg0_sel when sh_addr(9 downto 6) = "'
				+ format(self.winSlot(name), '04b') + '" else \'0\';')
		lines.append(ind + '-- M17: the power controller is a NATIVE slave IN a page-0 slot (11,')
		lines.append(ind + '-- 0x4B00 ' + EMDASH + ' vacated by SARADC0): slot-decoded like the peripherals')
		lines.append(ind + '-- above, but it speaks the arbiter protocol directly (no shim).')
		for name in PG0_NATIVE_ORDER:
			selName = 'shslv_' + self.shslv[name]['sel'] + '_sel'
			lines.append(ind + selName.ljust(16) + ' <= shslv_pg0_sel when sh_addr(9 downto 6) = "'
				+ format(self.winSlot(name), '04b') + '" else \'0\';')
		# CQ2a: AFE stubs subdivide page-0 slot 12 (0x4C00) into four 64 B
		# sub-slots on sh_addr(5:4). The s_master ownership gate lives inside
		# afe_stub; here we only address-decode the sub-slots. (digperiphs #1:
		# only when the AFE stubs occupy slot 12 — with qspi the slot is decoded
		# whole as shslv_qspi0_sel in the pg0SelOrder loop above.)
		if self.afeStubs:
			lines.append(ind + '-- CQ2a: AFE stubs subdivide page-0 slot 12 (0x4C00) into four 64 B')
			lines.append(ind + '-- sub-slots on sh_addr(5:4); the s_master ownership gate is inside afe_stub.')
			lines.append(ind + 'shslv_afe_sel'.ljust(16) + ' <= shslv_pg0_sel when sh_addr(9 downto 6) = "1100" else \'0\';')
			for sub in range(4):
				lines.append(ind + ('shslv_afe' + str(sub) + '_sel').ljust(16) + ' <= shslv_afe_sel when sh_addr(5 downto 4) = "'
					+ format(sub, '02b') + '" else \'0\';')
		for key in self.enOrder:
			sel = self.selOf(key)
			lines.append(ind + ('shslv_' + sel + '_en').ljust(16) + ' <= sh_en and shslv_' + sel + '_sel;')
		# CQ2a: AFE sub-slot + EIS enables
		if self.afeStubs:
			for sub in range(4):
				lines.append(ind + ('shslv_afe' + str(sub) + '_en').ljust(16) + ' <= sh_en and shslv_afe' + str(sub) + '_sel;')
			lines.append(ind + 'shslv_eis_en'.ljust(16) + ' <= sh_en and shslv_eis_sel;')
		return lines

	def emitShslvRdSel(self):
		ind = ' ' * 4
		lines = []
		lines.append(ind + 'shslv_rd_sel: process(mclk, resetn)')
		lines.append(ind + 'begin')
		lines.append(ind * 2 + "if resetn = '0' then")
		for key in self.rdOrder:
			lines.append(ind * 3 + ('shslv_rd_' + self.selOf(key)).ljust(16) + " <= '0';")
		if self.afeStubs:
			for sel in ['afe0', 'afe1', 'afe2', 'afe3', 'eis']:  # CQ2a
				lines.append(ind * 3 + ('shslv_rd_' + sel).ljust(16) + " <= '0';")
		lines.append(ind * 2 + 'elsif rising_edge(mclk) then')
		lines.append(ind * 3 + "if sh_en = '1' then")
		for key in self.rdOrder:
			sel = self.selOf(key)
			lines.append(ind * 4 + ('shslv_rd_' + sel).ljust(16) + ' <= shslv_' + sel + '_sel;')
		if self.afeStubs:
			for sel in ['afe0', 'afe1', 'afe2', 'afe3', 'eis']:  # CQ2a
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
		if self.i2c1:
			lines.append(ind * 3 + "i2c1_sh_rdata <= (others => '0');")
		if self.npu:
			lines.append(ind * 3 + "npu_sh_rdata  <= (others => '0');")
		lines.append(ind * 2 + 'elsif rising_edge(mclk) then')
		lines.append(ind * 3 + "if shslv_i2c0_en = '1' then")
		lines.append(ind * 4 + 'i2c0_sh_rdata <= i2c0_sh_rdata_c;')
		lines.append(ind * 3 + 'end if;')
		if self.i2c1:
			lines.append(ind * 3 + "if shslv_i2c1_en = '1' then")
			lines.append(ind * 4 + 'i2c1_sh_rdata <= i2c1_sh_rdata_c;')
			lines.append(ind * 3 + 'end if;')
		if self.npu:
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
		for i, key in enumerate(self.rdOrder):
			row = self.rdataOf(key).ljust(14) + ' when ' + ('shslv_rd_' + self.selOf(key)).ljust(16) + " = '1' else"
			lines.append((prefix if i == 0 else cont) + row)
		# CQ2a: AFE sub-slot + EIS reads (each afe_stub gates internally, so a
		# denied read already returns 0 on these nets)
		if self.afeStubs:
			for sel in ['afe0', 'afe1', 'afe2', 'afe3', 'eis']:
				lines.append(cont + (sel + '_rdata').ljust(14) + ' when ' + ('shslv_rd_' + sel).ljust(16) + " = '1' else")
		lines.append(cont + "(others => '0');  -- no slave (TCM page, unmapped)")
		return lines

	def emitSlot12Decls(self):
		'''digperiphs #1: page-0 slot 12 (0x4C00) declarative region. The AFE
		stubs + EIS (golden-master default, VERBATIM) OR the QSPI0 controller
		fabric nets, else nothing (slot 12 unused).'''
		if self.afeStubs:
			return list(AFE_SLOT12_DECLS)
		if self.qspi:
			return [
				'        -- digperiphs #1: QSPI0 (Quad-SPI flash controller) occupies page-0',
				'        -- slot 12 (0x4C00, the ex-AFE reserved gap). sharedBus=periph shim;',
				'        -- the read path is REGISTERED inside QSPI.vhd (no rdata bridge).',
				'        signal shslv_qspi0_sel, shslv_qspi0_en : std_logic;',
				"        signal shslv_rd_qspi0   : std_logic := '0';",
				'        signal qspi0_sh_rdata   : std_logic_vector(31 downto 0);',
				'        signal qspi0_sh_en_n    : std_logic;',
				'        signal shslv_qspi0_en_q : std_logic;   -- X-fix: falling-mclk registered strobe (snapshot capture clock)',
				'        -- QSPI0 serial pins. PLACEHOLDER wiring (digperiphs #1): the six QSPI',
				'        -- pins (SCK, CS, IO0-3) are NOT yet routed through the GPIO alt-',
				'        -- function planes — pin-map pending a user decision. io_in is tied',
				'        -- low; the outputs are observed by nothing (no pad hookup yet).',
				'        signal qspi_sck_out, qspi_sck_dir : std_logic;',
				'        signal qspi_cs_out,  qspi_cs_dir  : std_logic;',
				'        signal qspi_io_in       : std_logic_vector(3 downto 0);',
				'        signal qspi_io_out      : std_logic_vector(3 downto 0);',
				'        signal qspi_io_dir      : std_logic_vector(3 downto 0);',
			]
		return []

	def emitSlot12Instances(self):
		'''digperiphs #1: page-0 slot 12 (0x4C00) instance region. AFE + EIS
		stubs (default, VERBATIM) OR the QSPI0 controller, else nothing.'''
		if self.afeStubs:
			return list(AFE_SLOT12_INSTANCES)
		if self.qspi:
			return [
				'    -- =========================================================================',
				'    -- QSPI0 (digperiphs #1): Quad-SPI flash controller, page-0 slot 12 (0x4C00).',
				'    -- smclk-domain serial core (SYS_CLK_CR=0 rule). Registered read (no bridge);',
				'    -- RX reads have NO side effects. irq_tc -> vector 55, irq_rxf -> vector 56.',
				'    -- PLACEHOLDER pins (see report): io_in tied low, outputs unobserved.',
				'    -- =========================================================================',
				'    qspi0: entity work.QSPI',
				'        port map (',
				'            clk         => smclk,',
				'            resetn      => resetn,',
				'            irq_tc      => irq_qspi0_tc,',
				'            irq_rxf     => irq_qspi0_rxf,',
				'            ClkMem      => mclk,',
				'            EnMemPeriph => qspi0_sh_en_n,',
				'            WEn         => sh_wen_n,',
				'            MABPart     => sh_addr(5 downto 0),',
				'            wdata       => sh_wdata,',
				'            rdata_out   => qspi0_sh_rdata,',
				'            sck_out     => qspi_sck_out,',
				'            sck_dir     => qspi_sck_dir,',
				'            cs_out      => qspi_cs_out,',
				'            cs_dir      => qspi_cs_dir,',
				'            io_in       => qspi_io_in,',
				'            io_out      => qspi_io_out,',
				'            io_dir      => qspi_io_dir);',
				'    -- Mission B: qspi_io_in is driven from the P5.2-5 AF1 input muxes (GPIO4).',
			]
		return []

	def emitI3cDecls(self):
		'''digperiphs #2: I3C0 (page-2 sub-slot 1 @0x6100) declarative region.
		Fabric nets for the hand-emitted shim + the placeholder serial pins;
		nothing when I3C is absent.'''
		if not self.i3c:
			return []
		return [
			'        -- digperiphs #2: I3C0 (I3C controller, MVP + dynamic address',
			'        -- assignment + in-band interrupts). Page-2 (MUTEX page) sub-slot 1',
			'        -- @0x6100 — the mutex bank keeps sub-slot 0 @0x6000, now decoded to',
			'        -- 256 B (the page-wide alias, whose reads fired an atomic CLAIM, is',
			'        -- retired). Registered-read shim (no bridge); active-low one-cycle en;',
			'        -- smclk serial core (SYS_CLK_CR=0 rule). irq_* -> vectors 86-93, above',
			'        -- the frozen meip slot 85.',
			'        signal shslv_i3c0_sel, shslv_i3c0_en : std_logic;',
			"        signal shslv_rd_i3c0    : std_logic := '0';",
			'        signal i3c0_sh_rdata    : std_logic_vector(31 downto 0);',
			'        signal i3c0_sh_en_n     : std_logic;',
			'        signal shslv_i3c0_en_q  : std_logic;   -- X-fix: falling-mclk registered strobe (snapshot capture clock)',
			'        -- I3C0 SDA/SCL pins. PLACEHOLDER wiring (digperiphs, pin-map',
			'        -- DEFERRED): not yet routed through the GPIO alt-function planes.',
			"        -- SDA_IN/SCL_IN are tied HIGH ('1') = idle (released) bus; the",
			'        -- outputs/direction controls are observed by nothing (no pad yet).',
			'        signal i3c0_sda_out, i3c0_sda_dir : std_logic;',
			'        signal i3c0_scl_out, i3c0_scl_dir : std_logic;',
		]

	def emitI3cInstance(self):
		'''digperiphs #2: I3C0 instance region (page-2 sub-slot 1 @0x6100).
		The active-low en shim + the I3C entity + placeholder pin ties; nothing
		when I3C is absent.'''
		if not self.i3c:
			return []
		return [
			'',
			'    -- =========================================================================',
			'    -- I3C0 (digperiphs #2): I3C controller (MVP + dynamic address assignment +',
			'    -- in-band interrupts), page-2 (MUTEX page) sub-slot 1 @0x6100. smclk-domain',
			'    -- serial core (SYS_CLK_CR=0 rule). Registered read (no bridge); register/RX',
			'    -- reads have NO side effects. The eight irq_* lines drive vectors 86-93',
			'    -- (tc/rxf/txe/nack/eod/arb/daa/ibi) through the irq_router, ABOVE the frozen',
			"    -- meip slot 85. PLACEHOLDER pins: SDA_IN/SCL_IN tied HIGH (idle bus), the",
			'    -- outputs unobserved — pin-map DEFERRED (see the digperiphs report).',
			'    -- =========================================================================',
			'    -- X-collapse fix: I3C clocks its snapshot latches on en_mem\'s falling',
			'    -- edge; falling-mclk re-registered strobe (see snapshot_strobe_reg).',
			'    i3c0_enq_reg: process(mclk)',
			'    begin',
			'        if falling_edge(mclk) then',
			'            shslv_i3c0_en_q <= shslv_i3c0_en;',
			'        end if;',
			'    end process;',
			'    i3c0_sh_en_n <= not shslv_i3c0_en_q;',
			'    i3c0: entity work.I3C',
			'        port map (',
			'            clk         => smclk,',
			'            resetn      => resetn,',
			'            irq_tc      => irq_i3c0_tc,',
			'            irq_rxf     => irq_i3c0_rxf,',
			'            irq_txe     => irq_i3c0_txe,',
			'            irq_nack    => irq_i3c0_nack,',
			'            irq_eod     => irq_i3c0_eod,',
			'            irq_arb     => irq_i3c0_arb,',
			'            irq_daa     => irq_i3c0_daa,',
			'            irq_ibi     => irq_i3c0_ibi,',
			'            ClkMem      => mclk,',
			'            EnMemPeriph => i3c0_sh_en_n,',
			'            WEn         => sh_wen_n,',
			'            MABPart     => sh_addr(5 downto 0),',
			'            wdata       => sh_wdata,',
			'            rdata_out   => i3c0_sh_rdata,',
			'            SDA_IN      => i3c0_sda_in,   -- Mission B: routed from P5.6 AF1 (GPIO4)',
			'            SDA_OUT     => i3c0_sda_out,',
			'            SDA_DIR     => i3c0_sda_dir,',
			'            SCL_IN      => i3c0_scl_in,   -- Mission B: routed from P5.7 AF1 (GPIO4)',
			'            SCL_OUT     => i3c0_scl_out,',
			'            SCL_DIR     => i3c0_scl_dir);',
		]

	def emitNfcDecls(self):
		'''digperiphs #3: NFC0 (page-2 sub-slot 2 @0x6200) declarative region.
		Fabric nets for the hand-emitted shim + the placeholder digital-AFE pins;
		nothing when NFC is absent.'''
		if not self.nfc:
			return []
		return [
			'        -- digperiphs #3: NFC0 (ISO 14443A tag / card-emulation engine).',
			'        -- Page-2 (MUTEX page) sub-slot 2 @0x6200 — the mutex bank keeps',
			'        -- sub-slot 0 @0x6000 (now 256 B, the aliased-CLAIM decode retired).',
			'        -- Registered-read shim (no bridge); active-low one-cycle en. Three',
			'        -- clock domains inside NFC.vhd: ClkMem (bus), clk = smclk (the CDC',
			'        -- synchronizers + W1C retirement; SYS_CLK_CR=0 rule), and the off-die',
			'        -- rf_clk protocol core. irq_* -> vectors 94-97, above the frozen meip',
			"        -- slot 85 and I3C's 86-93.",
			'        signal shslv_nfc0_sel, shslv_nfc0_en : std_logic;',
			"        signal shslv_rd_nfc0    : std_logic := '0';",
			'        signal nfc0_sh_rdata    : std_logic_vector(31 downto 0);',
			'        signal nfc0_sh_en_n     : std_logic;',
			'        signal shslv_nfc0_en_q  : std_logic;   -- X-fix: falling-mclk registered strobe (snapshot capture clock)',
			'        -- NFC0 digital-AFE / RF interface. PLACEHOLDER wiring (digperiphs,',
			'        -- pin/AFE-map DEFERRED): the six AFE signals are NOT routed to pads.',
			"        -- rf_clk and field_detect tie '0' (no carrier, no field); rf_rx ties",
			"        -- '1' (idle envelope, no pause); the outputs are observed by nothing.",
			'        signal nfc0_rf_txmod, nfc0_rf_tx_en, nfc0_afe_en : std_logic;',
		]

	def emitNfcInstance(self):
		'''digperiphs #3: NFC0 instance region (page-2 sub-slot 2 @0x6200). The
		active-low en shim + the NFC entity + placeholder AFE ties; nothing when
		NFC is absent.'''
		if not self.nfc:
			return []
		return [
			'',
			'    -- =========================================================================',
			'    -- NFC0 (digperiphs #3): ISO 14443A tag / card-emulation engine, page-2',
			'    -- (MUTEX page) sub-slot 2 @0x6200. Bus/CDC reference clock = smclk (the',
			'    -- SYS_CLK_CR=0 rule applies); the whole protocol core runs on the off-die',
			'    -- carrier-derived rf_clk. Registered read (no bridge); register/RX reads',
			'    -- have NO side effects. The four irq_* lines drive vectors 94-97',
			'    -- (field/rxf/txdone/crcerr) through the irq_router, ABOVE the frozen meip',
			'    -- slot 85. PLACEHOLDER digital-AFE interface: rf_clk/field_detect tied low,',
			"    -- rf_rx tied high (idle bus), outputs unobserved — the 13.56 MHz RF front",
			'    -- end is off-die and the pin-map is DEFERRED (see the digperiphs report).',
			'    -- =========================================================================',
			'    -- X-collapse fix: NFC clocks its snapshot latches on en_mem\'s falling',
			'    -- edge; falling-mclk re-registered strobe (see snapshot_strobe_reg).',
			'    nfc0_enq_reg: process(mclk)',
			'    begin',
			'        if falling_edge(mclk) then',
			'            shslv_nfc0_en_q <= shslv_nfc0_en;',
			'        end if;',
			'    end process;',
			'    nfc0_sh_en_n <= not shslv_nfc0_en_q;',
			'    nfc0: entity work.NFC',
			'        port map (',
			'            clk          => smclk,',
			'            resetn       => resetn,',
			'            irq_field    => irq_nfc0_field,',
			'            irq_rxf      => irq_nfc0_rxf,',
			'            irq_txdone   => irq_nfc0_txdone,',
			'            irq_crcerr   => irq_nfc0_crcerr,',
			'            ClkMem       => mclk,',
			'            EnMemPeriph  => nfc0_sh_en_n,',
			'            WEn          => sh_wen_n,',
			'            MABPart      => sh_addr(5 downto 0),',
			'            wdata        => sh_wdata,',
			'            rdata_out    => nfc0_sh_rdata,',
			'            rf_clk       => nfc0_rf_clk,       -- Mission B: routed from P6.0 AF1 (GPIO5)',
			'            field_detect => nfc0_field_detect, -- Mission B: routed from P6.2 AF1 (GPIO5)',
			'            rf_rx        => nfc0_rf_rx,        -- Mission B: routed from P6.1 AF1 (GPIO5)',
			'            rf_txmod     => nfc0_rf_txmod,',
			'            rf_tx_en     => nfc0_rf_tx_en,',
			'            afe_en       => nfc0_afe_en);',
		]

	def emitRtcDecls(self):
		'''digperiphs #4: RTC0 (page-2 sub-slot 5 @0x6500) declarative region.
		Fabric nets for the hand-emitted RAW-strobe shim; nothing when RTC is
		absent. UNLIKE I3C0/NFC0 there is NO shslv_rtc0_en_q register (D4: the RTC
		has no falling_edge(EnMemPeriph) snapshot capture, so no re-registered
		strobe) and NO placeholder pins (the block is zero-pin; its only external
		signal is the already-bonded ungated lfxt_in).'''
		if not self.rtc:
			return []
		return [
			'        -- digperiphs #4: RTC0 (real-time clock: 32.768 kHz always-on wall',
			'        -- clock + one-shot alarm + periodic tick, ONE combined IRQ). Page-2',
			'        -- (MUTEX page) sub-slot 5 @0x6500 — the mutex bank keeps sub-slot 0',
			'        -- @0x6000. Registered-read native slave with a PLAIN active-low',
			'        -- one-cycle en shim: NO falling_edge(EnMemPeriph) pre-latch and NO',
			'        -- CAPTURE_CLOCK en_q register (D4 — the RTC registers its read on',
			'        -- rising ClkMem over data already synchronized into the bus domain,',
			'        -- so it needs neither a bridge nor a capture strobe; the first',
			'        -- library block clean of both). clk => mclk (A2: the free-running',
			'        -- fabric clock hosts the LFXT->bus CDC synchronizers, the sticky W1C',
			'        -- flags and the IRQ combiner); the wall clock rides the ungated',
			'        -- lfxt_in pad crystal (D1). Zero pins. irq_rtc -> vector 114.',
			'        signal shslv_rtc0_sel, shslv_rtc0_en : std_logic;',
			"        signal shslv_rd_rtc0    : std_logic := '0';",
			'        signal rtc0_sh_rdata    : std_logic_vector(31 downto 0);',
			'        signal rtc0_sh_en_n     : std_logic;',
		]

	def emitRtcInstance(self):
		'''digperiphs #4: RTC0 instance region (page-2 sub-slot 5 @0x6500). The
		PLAIN raw-strobe active-low en shim + the RTC entity; nothing when RTC is
		absent. No enq_reg process (D4), no placeholder ties (zero pins).'''
		if not self.rtc:
			return []
		return [
			'',
			'    -- =========================================================================',
			'    -- RTC0 (digperiphs #4): 32.768 kHz always-on real-time clock, page-2',
			'    -- (MUTEX page) sub-slot 5 @0x6500. The 47-bit {seconds, subsecond} wall',
			'    -- clock, alarm compare and periodic-tick down-counter all ride the UNGATED',
			'    -- lfxt_in pad crystal (D1) — firmware CANNOT stop it (SYS_CLK_CR is',
			'    -- irrelevant to the count) and PWRCTRL cannot gate it. clk => mclk (A2):',
			'    -- the free-running fabric clock hosts the LFXT->bus CDC synchronizers, the',
			'    -- sticky ALMF/TICKF W1C flags and the combinational IRQ combiner, so the',
			'    -- flags set and irq_rtc asserts autonomously while the bus is idle.',
			'    -- Registered read (no bridge); register/RX reads have NO side effects.',
			'    -- The single irq_rtc line drives vector 114 (combined alarm/tick) through',
			'    -- the irq_router, ABOVE GPIO5\'s 106-113. Zero pins.',
			'    -- =========================================================================',
			'    -- D4: PLAIN raw active-low en strobe (the GPIO4/5 native-slave idiom) —',
			'    -- NO falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q here.',
			'    rtc0_sh_en_n <= not shslv_rtc0_en;',
			'    rtc0: entity work.RTC',
			'        port map (',
			'            clk         => mclk,',
			'            resetn      => resetn,',
			'            lfxt_in     => lfxt_in,',
			'            irq_rtc     => irq_rtc0,',
			'            ClkMem      => mclk,',
			'            EnMemPeriph => rtc0_sh_en_n,',
			'            WEn         => sh_wen_n,',
			'            MABPart     => sh_addr(5 downto 0),',
			'            wdata       => sh_wdata,',
			'            rdata_out   => rtc0_sh_rdata);',
		]

	def emitGpio45Decls(self, port):
		'''Mission B: GPIO4 (port 5) / GPIO5 (port 6) declarative region — the
		registered-read shim nets, the register/AF-plane signals, and (in configs
		that route them) the peripheral-input nets GPIO4/5 drive from the pads.'''
		gi = port - 1
		sub = gi - 1
		base = 0x6000 + sub * 0x100
		if gi == 4:
			af1desc = 'QSPI0 (P5.0-5) + I3C0 (P5.6/7)'
			vecrange = '98-105'
		else:
			af1desc = 'NFC0 digital-AFE (P6.0-5)'
			vecrange = '106-113'
		lines = [
			'        -- Mission B: GPIO%d (port %d), MUTEX-page sub-slot %d @0x%04X.' % (gi, port, sub, base),
			'        -- Registered-read native slave with its own active-low en shim (like',
			'        -- I3C0/NFC0). AF0 = plain GPIO on every pin; AF1 carries the %s' % af1desc,
			'        -- pin functions when present, Hi-Z otherwise. Per-pin IRQs -> vectors %s.' % vecrange,
			'        signal shslv_gpio%d_sel, shslv_gpio%d_en : std_logic;' % (gi, gi),
			"        signal shslv_rd_gpio%d   : std_logic := '0';" % gi,
			'        signal gpio%d_sh_rdata   : std_logic_vector(31 downto 0);' % gi,
			'        signal gpio%d_sh_en_n    : std_logic;' % gi,
			'        signal p%d_out, p%d_dir, p%d_ren : std_logic_vector(7 downto 0);' % (port, port, port),
			'        signal p%d_afs           : std_logic_vector(23 downto 0);' % port,
			'        signal afunc%d_out, afunc%d_dir, afunc%d_ren : std_logic_vector(7 downto 0);' % (port, port, port),
			'        signal afunc%d_af1_out, afunc%d_af1_dir, afunc%d_af1_ren : std_logic_vector(7 downto 0);' % (port, port, port),
			'        signal afunc%d_all_out   : std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);' % port,
			'        signal afunc%d_all_dir   : std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);' % port,
			'        signal afunc%d_all_ren   : std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);' % port,
		]
		if port == 5 and self.i3c:
			lines.append('        -- I3C0 SDA/SCL pad inputs, routed by GPIO4 from P5.6/7 (D4).')
			lines.append('        signal i3c0_sda_in, i3c0_scl_in : std_logic;')
		if port == 6 and self.nfc:
			lines.append('        -- NFC0 off-die AFE inputs, routed by GPIO5 from P6.0-2 (D5).')
			lines.append('        signal nfc0_rf_clk, nfc0_rf_rx, nfc0_field_detect : std_logic;')
		return lines

	def emitGpioBusInstance(self, port, af1Lines, muxLines):
		'''Common tail: AF-plane flatten + the GPIO component instance + shim.'''
		gi = port - 1
		flat = lambda sfx: ('    afunc%d_all_%s <= ' % (port, sfx)
			+ ' & '.join(['afunc_none'] * 6 + ['afunc%d_af1_%s' % (port, sfx), 'afunc%d_%s' % (port, sfx)]) + ';')
		lines = []
		lines.append('    gpio%d_sh_en_n <= not shslv_gpio%d_en;' % (gi, gi))
		lines.append('    -- AF0 plane = plain-GPIO passthrough (AF0 == GPIO for every pin)')
		lines.append('    afunc%d_out <= p%d_out;' % (port, port))
		lines.append('    afunc%d_dir <= p%d_dir;' % (port, port))
		lines.append('    afunc%d_ren <= p%d_ren;' % (port, port))
		lines += af1Lines
		lines.append('    -- Flatten the 8 AF planes (AF7..AF2 unused = afunc_none, then AF1, AF0)')
		lines.append(flat('out'))
		lines.append(flat('dir'))
		lines.append(flat('ren'))
		lines += muxLines
		lines.append('    gpio%d: GPIO' % gi)
		lines.append('        generic map (')
		lines.append('            num_pins        => 8,')
		lines.append('            PadOUTPosLogic  => true,')
		lines.append('            PadDIRPosLogic  => false,')
		lines.append('            PadRENPosLogic  => false,')
		lines.append('            RstValPxOUT     => RstValP%dOUT,' % port)
		lines.append('            RstValPxDIR     => RstValP%dDIR,' % port)
		lines.append('            RstValPxSEL     => RstValP%dSEL,' % port)
		lines.append('            RstValPxREN     => RstValP%dREN,' % port)
		lines.append('            RstValPxAFS     => RstValP%dAFS' % port)
		lines.append('        )')
		lines.append('        port map (')
		lines.append('            resetn          => resetn,')
		lines.append('            irq             => irq_gpio%d,' % gi)
		lines.append('            clk_mem         => mclk,')
		lines.append('            en              => gpio%d_sh_en_n,' % gi)
		lines.append('            wen             => sh_wen_n,')
		lines.append('            write_data      => sh_wdata,')
		lines.append('            read_data       => gpio%d_sh_rdata,' % gi)
		lines.append('            addr_periph     => sh_addr(5 downto 0),')
		lines.append('            prt_in          => prt%d_in,' % port)
		lines.append('            prt_out_out     => prt%d_out,' % port)
		lines.append('            prt_dir_out     => prt%d_dir,' % port)
		lines.append('            prt_ren_out     => prt%d_ren,' % port)
		lines.append('            PxOUT_out       => p%d_out,' % port)
		lines.append('            PxDIR_out       => p%d_dir,' % port)
		lines.append('            PxREN_out       => p%d_ren,' % port)
		lines.append('            PxSEL_out       => open,')
		lines.append('            PxAFS_out       => p%d_afs,' % port)
		lines.append('            alt_func_out_in => afunc%d_all_out,' % port)
		lines.append('            alt_func_dir_in => afunc%d_all_dir,' % port)
		lines.append('            alt_func_ren_in => afunc%d_all_ren' % port)
		lines.append('    );')
		return lines

	def emitGpio4Instance(self):
		'''Mission B: GPIO4 (port 5) instance — AF1 = QSPI0 (P5.0-5) + I3C0 (P5.6/7)
		when present, Hi-Z otherwise; the P5 input muxes route the QSPI IO and I3C
		SDA/SCL pad inputs back to the controllers (D4).'''
		af1 = []
		mux = []
		if self.qspi or self.i3c:
			# AF1 output plane
			def cell(idx, sig, note):
				return "            %d => %s," % (idx, sig) if idx != 0 else "            %d => %s" % (idx, sig)
			# out
			outMap = {
				7: 'i3c0_scl_out' if self.i3c else "'0'",
				6: 'i3c0_sda_out' if self.i3c else "'0'",
				5: 'qspi_io_out(3)' if self.qspi else "'0'",
				4: 'qspi_io_out(2)' if self.qspi else "'0'",
				3: 'qspi_io_out(1)' if self.qspi else "'0'",
				2: 'qspi_io_out(0)' if self.qspi else "'0'",
				1: 'qspi_cs_out' if self.qspi else "'0'",
				0: 'qspi_sck_out' if self.qspi else "'0'",
			}
			dirMap = {
				7: 'i3c0_scl_dir' if self.i3c else "'0'",
				6: 'i3c0_sda_dir' if self.i3c else "'0'",
				5: 'qspi_io_dir(3)' if self.qspi else "'0'",
				4: 'qspi_io_dir(2)' if self.qspi else "'0'",
				3: 'qspi_io_dir(1)' if self.qspi else "'0'",
				2: 'qspi_io_dir(0)' if self.qspi else "'0'",
				1: 'qspi_cs_dir' if self.qspi else "'0'",
				0: 'qspi_sck_dir' if self.qspi else "'0'",
			}
			af1.append('    -- AF1 output/dir plane: QSPI0 on P5.0-5, I3C0 (open-drain) on P5.6/7')
			af1.append('    afunc5_af1_out <= (')
			for b in range(7, -1, -1):
				af1.append('        %d => %s%s' % (b, outMap[b], '' if b == 0 else ','))
			af1.append('    );')
			af1.append('    afunc5_af1_dir <= (')
			for b in range(7, -1, -1):
				af1.append('        %d => %s%s' % (b, dirMap[b], '' if b == 0 else ','))
			af1.append('    );')
			# ren plane follows the register pull preference (PxREN); I3C pull-ups
			# reach the pads this way when the pin is in AF1 mode.
			af1.append('    afunc5_af1_ren <= p5_ren;')
			# Input muxes (AFS-keyed, always-visible like the I2C relocations)
			if self.qspi:
				mux.append('    -- QSPI0 IO input muxes: read the P5.2-5 pad when that pin selects AF1')
				for k in range(4):
					pin = 2 + k
					mux.append('    qspi_io_in(%d) <= prt5_in(%d) when p5_afs((3 * %d) + 2 downto 3 * %d) = "001" else \'0\';' % (k, pin, pin, pin))
			if self.i3c:
				mux.append('    -- I3C0 SDA/SCL input muxes (P5.6/7); idle-high when not in AF1 mode')
				mux.append('    i3c0_sda_in <= prt5_in(6) when p5_afs((3 * 6) + 2 downto 3 * 6) = "001" else \'1\';')
				mux.append('    i3c0_scl_in <= prt5_in(7) when p5_afs((3 * 7) + 2 downto 3 * 7) = "001" else \'1\';')
		else:
			af1.append('    -- AF1 plane unused in this configuration (QSPI0/I3C0 absent): Hi-Z.')
			af1.append('    afunc5_af1_out <= afunc_none;')
			af1.append('    afunc5_af1_dir <= afunc_none;')
			af1.append('    afunc5_af1_ren <= afunc_none;')
		head = [
			'',
			'    -- =========================================================================',
			'    -- GPIO4 (Mission B): general-purpose I/O port 5, MUTEX-page sub-slot 3 @0x6300.',
			'    -- Registered read; own active-low one-cycle en shim. AF0 = plain GPIO; AF1 =',
			'    -- QSPI0/I3C0 pin functions (Hi-Z when absent). Per-pin IRQs -> vectors 98-105.',
			'    -- =========================================================================',
		]
		return head + self.emitGpioBusInstance(5, af1, mux)

	def emitGpio5Instance(self):
		'''Mission B: GPIO5 (port 6) instance — AF1 = NFC0 digital-AFE (P6.0-5) when
		present, Hi-Z otherwise. P6.0-2 are inputs (rf_clk/rf_rx/field_detect, routed
		to NFC0); P6.3-5 are outputs (rf_txmod/rf_tx_en/afe_en). P6.6/7 spare.'''
		af1 = []
		mux = []
		if self.nfc:
			outMap = {
				7: "'0'", 6: "'0'",
				5: 'nfc0_afe_en', 4: 'nfc0_rf_tx_en', 3: 'nfc0_rf_txmod',
				2: "'0'", 1: "'0'", 0: "'0'",
			}
			# P6.0-2 are inputs -> AF dir '0' (input); P6.3-5 outputs -> AF dir '1'.
			dirMap = {7: "'0'", 6: "'0'", 5: "'1'", 4: "'1'", 3: "'1'", 2: "'0'", 1: "'0'", 0: "'0'"}
			af1.append('    -- AF1 plane: NFC0 outputs on P6.3-5 (txmod/tx_en/afe_en); P6.0-2 are')
			af1.append('    -- inputs (rf_clk/rf_rx/field_detect), so their AF1 out/dir stay 0 (input).')
			af1.append('    afunc6_af1_out <= (')
			for b in range(7, -1, -1):
				af1.append('        %d => %s%s' % (b, outMap[b], '' if b == 0 else ','))
			af1.append('    );')
			af1.append('    afunc6_af1_dir <= (')
			for b in range(7, -1, -1):
				af1.append('        %d => %s%s' % (b, dirMap[b], '' if b == 0 else ','))
			af1.append('    );')
			af1.append('    afunc6_af1_ren <= p6_ren;')
			mux.append('    -- NFC0 off-die AFE input muxes: read the P6.0-2 pads when in AF1 mode')
			mux.append('    nfc0_rf_clk       <= prt6_in(0) when p6_afs((3 * 0) + 2 downto 3 * 0) = "001" else \'0\';')
			mux.append('    nfc0_rf_rx        <= prt6_in(1) when p6_afs((3 * 1) + 2 downto 3 * 1) = "001" else \'1\';')
			mux.append('    nfc0_field_detect <= prt6_in(2) when p6_afs((3 * 2) + 2 downto 3 * 2) = "001" else \'0\';')
		else:
			af1.append('    -- AF1 plane unused in this configuration (NFC0 absent): Hi-Z.')
			af1.append('    afunc6_af1_out <= afunc_none;')
			af1.append('    afunc6_af1_dir <= afunc_none;')
			af1.append('    afunc6_af1_ren <= afunc_none;')
		head = [
			'',
			'    -- =========================================================================',
			'    -- GPIO5 (Mission B): general-purpose I/O port 6, MUTEX-page sub-slot 4 @0x6400.',
			'    -- Registered read; own active-low one-cycle en shim. AF0 = plain GPIO; AF1 =',
			'    -- NFC0 digital-AFE pins (Hi-Z when absent). Per-pin IRQs -> vectors 106-113.',
			'    -- =========================================================================',
		]
		return head + self.emitGpioBusInstance(6, af1, mux)

	def gfCount(self):
		'''Number of 32-bit GlitchFilter instances = ceil(NUM_IRQ_SRCS / 32).
		3 at the Castalia default (85 sources) and with I3C (94); 4 with NFC
		(98 sources cross the third 32-bit boundary).'''
		return (len(self.irqVectors) + 31) // 32

	def emitIrqGfDecls(self):
		'''digperiphs #3: irq_comb / gf_out width, sized to the glitch-filter
		count (was a fixed std_logic_vector(95 downto 0) with 3 instances). At
		gfCount = 3 this reproduces the golden master byte-identically.'''
		w = str(32 * self.gfCount() - 1)
		return [
			'        signal irq_comb         : std_logic_vector(' + w + ' downto 0);',
			'        signal irq_deglitch     : std_logic_vector(NUM_IRQ_SRCS -1 downto 0);',
			'        signal gf_out           : std_logic_vector(' + w + ' downto 0);',
		]

	def emitIrqGfInstances(self):
		'''digperiphs #3: the 32-bit GlitchFilter instances (one per 32 sources)
		+ the irq_deglitch slice. Was 3 fixed instances; now geometry-driven so
		NFC (4 instances) elaborates. At gfCount = 3 this is byte-identical.'''
		lines = ['    -- Glitch Filter for IRQ signals']
		for i in range(self.gfCount()):
			hi = str(32 * i + 31)
			lo = str(32 * i)
			lines.append('    irq_gf' + str(i) + ' : entity work.GlitchFilter')
			lines.append('        port map')
			lines.append('        (')
			lines.append('            IrqGlitchy\t\t=> irq_comb(' + hi + ' downto ' + lo + '),')
			lines.append('            IrqDeglitched\t=> gf_out(' + hi + ' downto ' + lo + ')')
			lines.append('\t);')
		lines.append('    irq_deglitch <= gf_out(NUM_IRQ_SRCS-1 downto 0);')
		return lines

	def emitPolarityShims(self):
		ind = ' ' * 4
		lines = []
		# X-collapse fix (2026-07-20): the capture-clock strobe re-register.
		# Emitted first so every group below can reference its _q signal.
		capture = [n for (c, ns, p) in self.shimGroups for n in ns if n in CAPTURE_CLOCK]
		if capture:
			lines += [
				ind + '-- X-collapse fix (2026-07-20): SPI/UART/TIMER/I2C (and QSPI when',
				ind + '-- configured) CLOCK their status/RX snapshot registers on en_mem\'s',
				ind + '-- FALLING EDGE (the falling_edge(en_mem) idiom inside the',
				ind + '-- peripherals). sh_en/sh_addr are registered arbiter outputs, so the',
				ind + '-- combinational en AND decode below glitches only in the skew window',
				ind + '-- right after each rising mclk edge ' + EMDASH + ' and a glitch there is a',
				ind + '-- spurious capture-clock edge racing its own D (the gate-level',
				ind + '-- X-collapse; root cause + proof: digperiphs xcollapse_findings).',
				ind + '-- Those shims therefore take a FALLING-MCLK re-registered strobe:',
				ind + '-- half a cycle later the decode has long settled, and every other',
				ind + '-- en_mem consumer samples on rising mclk edges, for which the',
				ind + '-- registered strobe is indistinguishable from the raw one.',
				ind + 'snapshot_strobe_reg: process(mclk)',
				ind + 'begin',
				ind + '    if falling_edge(mclk) then',
			]
			qpad = max(len('shslv_' + self.shslv[n]['sel'] + '_en_q') for n in capture)
			for n in capture:
				q = 'shslv_' + self.shslv[n]['sel'] + '_en_q'
				lines.append(ind + '        ' + q.ljust(qpad) + ' <= shslv_' + self.shslv[n]['sel'] + '_en;')
			lines += [
				ind + '    end if;',
				ind + 'end process;',
				'',
			]
		for gi, (comment, names, pad) in enumerate(self.shimGroups):
			for c in comment:
				lines.append(ind + c)
			for name in names:
				shim = self.shslv[name]['shim'] + '_sh_en_n'
				if name in CAPTURE_CLOCK:
					lines.append(ind + shim.ljust(pad) + '<= not shslv_' + self.shslv[name]['sel'] + '_en_q;')
				else:
					lines.append(ind + shim.ljust(pad) + '<= not shslv_' + self.shslv[name]['sel'] + '_en;')
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
		roundup16(4N)/4, mtimecmp pairs at +4; hdl/common/clint.vhd implements
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
		lines.append(self.sigDecl('arb_resvvld', 'std_logic_vector(' + nm1 + ' downto 0);  -- X1 Zawrs: per-master reservation-valid level'))
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

	def emitMeipDecl(self):
		# M19: one registered external-IRQ wire per hart (replaces the M7a
		# NHARTS*NUM_IRQS enable fan-out) + the D2 WDT hooks into SYSTEM0
		return [self.sigDecl('meip', 'std_logic_vector(' + str(self.nHarts() - 1) + ' downto 0);'),
			self.sigDecl('wdt_irq_routed', 'std_logic;   -- irq_router: source 0 enabled in some row'),
			self.sigDecl('wdt_irq_complete', 'std_logic;   -- irq_router: COMPLETE(0) pulse (WDT EOI)')]

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
		lines.append('    --   * tcm_pgen -> pgen_mem(1) (BLOCKPWR RAM gating),')
		lines.append('    --   * trap_flag -> the GPIO0 trap pin; a0 -> the tb pass/fail gate.')
		lines.append('    -- M19: the IRQ interface is IDENTICAL on every hart ' + EMDASH + ' msip/mtip from')
		lines.append("    -- the CLINT + this hart's meip row from the irq_router (SYSTEM0's")
		lines.append('    -- vectored path and the hw_clint_en strap are retired).')
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
		lines.append('            ENABLE_BITMANIP   => CORE_ENABLE_BITMANIP,')
		lines.append('            ENABLE_ZICOND     => CORE_ENABLE_ZICOND,')
		lines.append('            ENABLE_ZCB        => CORE_ENABLE_ZCB,')
		lines.append('            ENABLE_ZIMOP      => CORE_ENABLE_ZIMOP,')
		lines.append('            ENABLE_ZIHINT     => CORE_ENABLE_ZIHINT,')
		lines.append('            ENABLE_ZIHPM      => CORE_ENABLE_ZIHPM,')
		lines.append('            ENABLE_ZAWRS      => CORE_ENABLE_ZAWRS,')
		lines.append('            ENABLE_ZABHA      => CORE_ENABLE_ZABHA,')
		lines.append('            ENABLE_ZACAS      => CORE_ENABLE_ZACAS,')
		lines.append('            ENABLE_ZICBOZ     => CORE_ENABLE_ZICBOZ,')
		lines.append('            ENABLE_ZCMP       => CORE_ENABLE_ZCMP,')
		lines.append('            ENABLE_ZCMT       => CORE_ENABLE_ZCMT,')
		lines.append('            ENABLE_ZBKB       => CORE_ENABLE_ZBKB,')
		lines.append('            ENABLE_ZBKC       => CORE_ENABLE_ZBKC,')
		lines.append('            ENABLE_ZBKX       => CORE_ENABLE_ZBKX,')
		lines.append('            ENABLE_ZKN        => CORE_ENABLE_ZKN,')
		lines.append('            ENABLE_ZFINX      => CORE_ENABLE_ZFINX')
		lines.append('        )')
		lines.append('        port map (')
		lines.append('            clk       => mclk,')
		lines.append('            resetn    => resetn,')
		lines.append('            sleep     => sleep_cpu,')
		lines.append('            hart_id   => x"00000000",')
		lines.append('            msip_in   => clint_msip(0),')
		lines.append('            mtip_in   => clint_mtip(0),')
		lines.append('            meip_in   => meip(0),')
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
		lines.append('            sh_resv_valid => arb_resvvld(0),')
		lines.append('            sh_lock   => arb_lock(0),')
		lines.append('            tcm_pgen  => pgen_mem(1),')
		lines.append("            tcm_retn  => '1',")
		lines.append('            -- M17: hart 0 is ALWAYS-ON ' + EMDASH + ' its domain controls are strapped')
		lines.append('            -- inactive (explicit, per the M14 netlist-boundary rule)')
		lines.append("            pd_sleep  => '0',")
		lines.append("            pd_iso_en => '0',")
		lines.append('            trap_flag => trap_out,')
		lines.append('            a0        => a0')
		lines.append('        );')
		return lines

	def masterW(self):
		'''mp_arbiter s_master / mutex_bank master width (A2: the MW generic,
		default 2 = the Castalia shape).'''
		return max(1, _clog2(self.nHarts()))

	def emitArbGeneric(self):
		# A2: MW (s_master width) is emitted only when it differs from the
		# RTL default 2 (N=4 byte-identity)
		mw = self.masterW()
		return [' ' * 8 + 'generic map (N => ' + str(self.nHarts()) + ', ADDR_WIDTH => SH_AW, DATA_WIDTH => 32'
			+ ('' if mw == 2 else ', MW => ' + str(mw)) + ')']

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
		# M19: ADDR_W is fixed 10 (full-page decode; CLAIM at word 512) = the
		# RTL default, so the generic is never emitted. MW follows the
		# arbiter's s_master width (emitted only when != the RTL default 2).
		mw = self.masterW()
		lines = []
		lines.append('    -- M19 PLIC-lite: THE peripheral interrupt controller ' + EMDASH + ' per-hart routing')
		lines.append('    -- rows (any hart programs any row through the arbiter; resv-gated sh_we')
		lines.append('    -- like the CLINT) + CLAIM/COMPLETE delivery @0x7800. The deglitched')
		lines.append('    -- source vector TERMINATES here; delivery to harts 0-' + nm1 + ' is the one')
		lines.append('    -- registered meip wire each (IVT slot 85). sh_master attributes claim')
		lines.append('    -- reads (the mutex-bank idiom). Resets all-masked, so this block is a')
		lines.append('    -- provable NO-OP until software routes an IRQ. The wdt_* hooks carry')
		lines.append("    -- the D2 watchdog contract into SYSTEM0 (source 0's routed/EOI state).")
		lines.append('    irtr0: entity work.irq_router')
		lines.append('        generic map (NHARTS => ' + str(n) + ', NUM_SRCS => NUM_IRQ_SRCS'
			+ ('' if mw == 2 else ', MW => ' + str(mw)) + ')')
		lines.append('        port map (')
		lines.append('            clk          => mclk,')
		lines.append('            resetn       => resetn,')
		lines.append('            en           => shslv_irtr_en,')
		lines.append('            we           => sh_we,')
		lines.append('            addr         => sh_addr(9 downto 0),')
		lines.append('            wdata        => sh_wdata,')
		lines.append('            rdata        => irtr_rdata,')
		lines.append('            master       => sh_master,')
		lines.append('            irq_in       => irq_deglitch,')
		lines.append('            meip_out     => meip,')
		lines.append('            wdt_routed   => wdt_irq_routed,')
		lines.append('            wdt_complete => wdt_irq_complete')
		lines.append('        );')
		return lines

	# ------------------------------------------------------------------
	# A2 (Argus): geometry regions — SH_AW constant, memory-slave decls,
	# bank row, and the NPU-conditional verbatim blocks. Every emitter
	# reproduces the golden master byte-identically at the Castalia
	# geometry (SH_AW=15, 4 banks, NPU present).
	# ------------------------------------------------------------------

	def spliceSideBlock(self, blocks, sourceName, name):
		'''Verbatim side-template block, re-running any inner --@GEN:bus:*@
		marker through the bus emitter (the instance blocks carry their own
		bus marker since the main template no longer does).'''
		if name not in blocks:
			raise Exception('MCU.vhd emitter: ' + sourceName + ' has no block "' + name + '"')
		lines = []
		for line in blocks[name]:
			m = re.match(r'^\s*--@GEN:bus:(\w+)@\s*$', line)
			if m:
				lines.extend(self.emitBus(m.group(1)))
			else:
				lines.append(line)
		return lines

	def npuBlock(self, name):
		'''Verbatim NPU-conditional block from MCU.template.npu.vhd (empty
		when the config drops the NPU).'''
		if not self.npu:
			return []
		return self.spliceSideBlock(self.npuBlocks, 'MCU.template.npu.vhd', name)

	def i2c1Block(self, name):
		'''Verbatim I2C1-conditional block from MCU.template.i2c1.vhd (G1a).
		When the config drops I2C1 the instance marker leaves a breadcrumb
		comment; everything else emits nothing.'''
		if not self.i2c1:
			if name == 'i2c1-instance':
				return ['    -- I2C1 dropped by this configuration (window slot 15 reads zero;',
					'    -- vectors 70-82 are reserved; the SDA1/SCL1 pad planes are hi-Z)']
			return []
		return self.spliceSideBlock(self.i2c1Blocks, 'MCU.template.i2c1.vhd', name)

	def emitI2cFabricDecls(self):
		'''The I2C0/I2C1 shared-window fabric declarations (G1a transcription).'''
		lines = list(I2C_FABRIC_DECLS)
		if not self.i2c1:
			lines[0] = lines[0].replace('I2C0/I2C1 (M11: window slots 14/15)',
				'I2C0 (M11: window slot 14; I2C1 dropped)')
			lines = [l for l in lines if 'i2c1' not in l]
		return lines

	def emitGpio2Af1Planes(self):
		'''The P3 (GPIO2) AF1 relocation-plane aggregates. Dropped I2C1/UART1
		rows degrade to the existing "unassigned" hi-Z idiom (literal pin
		index, since the pnum_gpio2_af1_{sda1,scl1,tx1,rx1} constants are
		gated with their owner). The two knobs gate independently (G1b).'''
		lines = list(GPIO2_AF1_PLANES)
		dropRows = {}
		if not self.i2c1:
			dropRows.update({'scl1': ('3', 'I2C1'), 'sda1': ('2', 'I2C1')})
		if not self.uart1:
			dropRows.update({'rx1': ('1', 'UART1'), 'tx1': ('0', 'UART1')})
		if dropRows:
			out = []
			for l in lines:
				if not self.i2c1 and 'I2C1 relocation on P3.2/3' in l:
					l = l.replace('I2C1 relocation on P3.2/3,', 'P3.2/3 reserved (I2C1 dropped),')
				if not self.uart1 and 'UART1 relocation on P3.0/1' in l:
					l = l.replace('UART1 relocation on P3.0/1,', 'P3.0/1 reserved (UART1 dropped),')
				m = re.match(r'^(\s*)pnum_gpio2_af1_(\w+)\s*=> \w+_(out|dir|ren)(,?)\s*--.*$', l)
				if m and m.group(2) in dropRows:
					pin, owner = dropRows[m.group(2)]
					mode = {'out': 'hi-Z input', 'dir': 'input', 'ren': 'pull disabled'}[m.group(3)]
					col = l.index('--')
					body = m.group(1) + pin + " => '0'" + m.group(4)
					l = body.ljust(col) + '-- GPIO2 pin ' + pin + ': reserved, ' + owner + ' dropped (' + mode + ')'
				out.append(l)
			lines = out
		return lines

	def emitI2cInputMuxes(self):
		'''The I2C input/REN AF-selection muxes (fixed priority: v2 pad > AF1
		pad > home). The I2C1 muxes disappear with the instance; the comment
		drops its mention.'''
		lines = list(I2C_INPUT_MUXES)
		if not self.i2c1:
			out = []
			skip = 0
			for l in lines:
				if skip:
					if l.rstrip().endswith(';'):
						skip = 0
					continue
				s = l.strip()
				if s.startswith(('sda1_ren_in <=', 'scl1_ren_in <=', 'sda1_in <=', 'scl1_in <=')):
					skip = 1	# each mux runs to its terminating ';'
					continue
				if 'I2C1 to' in l:
					l = l.replace('I2C0 relocates to P2.6/7 or P3.6/7 (v2), I2C1 to',
						'I2C0 relocates to P2.6/7 or P3.6/7 (v2)')
				elif s.startswith('-- P3.2/3 or P2.4/5 (v2)'):
					l = l.replace('-- P3.2/3 or P2.4/5 (v2) ', '-- ')
				out.append(l)
			lines = out
		return lines

	def emitGpio3PrimaryPlanes(self):
		'''The P4 (GPIO3) primary alt-function aggregates. Dropped I2C1 rows
		keep their pnum choice (the AF0 pnum constants are transcription,
		not gated) but drive the hi-Z '0' idiom.'''
		lines = list(GPIO3_PRIMARY_PLANES)
		if not self.i2c1:
			out = []
			for l in lines:
				m = re.match(r'^(\s*pnum_gpio3_(scl1|sda1)\s*=> )\w+_(?:out|dir|ren),\s*--.*$', l)
				if m:
					pin = '3' if m.group(2) == 'scl1' else '2'
					col = l.index('--')
					body = m.group(1) + "'0',"
					l = body.ljust(col) + '-- GPIO3 pin ' + pin + ': reserved (I2C1 dropped)'
				out.append(l)
			lines = out
		return lines

	# ------------------------------------------------------------------
	# G1b emitters: UART1 / SPI1 / TIMER1 config-droppable regions
	# ------------------------------------------------------------------

	def uart1Block(self, name):
		'''Verbatim UART1-conditional block from MCU.template.uart1.vhd.'''
		if not self.uart1:
			if name == 'uart1-instance':
				return ['    -- UART1 dropped by this configuration (window slot 5 reads zero;',
					'    -- vectors 52-54 are reserved; the TX1/RX1 pad planes are hi-Z)']
			return []
		return self.spliceSideBlock(self.uart1Blocks, 'MCU.template.uart1.vhd', name)

	def spi1Block(self, name):
		'''Verbatim SPI1-conditional block from MCU.template.spi1.vhd.'''
		if not self.spi1:
			if name == 'spi1-instance':
				return ['    -- SPI1 dropped by this configuration (window slot 3 reads zero;',
					'    -- vectors 11-12 are reserved; the CS1/MISO1/MOSI1/SCK1 pad planes',
					'    -- are hi-Z)']
			return []
		return self.spliceSideBlock(self.spi1Blocks, 'MCU.template.spi1.vhd', name)

	def timer1Block(self, name):
		'''Verbatim TIMER1-conditional block from MCU.template.timer1.vhd.'''
		if not self.timer1:
			if name == 'timer1-instance':
				return ['    -- TIMER1 dropped by this configuration (window slot 7 reads zero;',
					'    -- vectors 22-27 are reserved; the T1CMP0/T1CMP1/T1CAP0/T1CAP1 pad',
					'    -- planes are hi-Z)']
			return []
		return self.spliceSideBlock(self.timer1Blocks, 'MCU.template.timer1.vhd', name)

	def emitMoverFabricDecls(self):
		'''The M7b/M7c mover fabric declarations (G1b transcription): TIMER1
		rows leave the M7b sub-block, SPI1/UART1 rows the M7c sub-block (the
		whole M7c sub-block disappears when both are dropped).'''
		lines = list(MOVER_FABRIC_DECLS)
		if not self.timer1:
			lines[0] = lines[0].replace('TIMER0/1 + GPIO1/2/3 (M11: window slots 6/7/1/8/13)',
				'TIMER0 + GPIO1/2/3 (M11: window slots 6/1/8/13; TIMER1 dropped)')
			lines = [l for l in lines if 'tim1' not in l]
		m7cAt = [i for i, l in enumerate(lines) if l.strip().startswith('-- M7c movers:')][0]
		if not self.spi1 and not self.uart1:
			lines = lines[:m7cAt]
		elif not self.uart1:
			lines[m7cAt] = lines[m7cAt].replace('SPI1 + UART1 (M11: window slots 3/5)',
				'SPI1 (M11: window slot 3; UART1 dropped)')
			lines = [l for l in lines if 'uart1' not in l]
		elif not self.spi1:
			lines[m7cAt] = lines[m7cAt].replace('SPI1 + UART1 (M11: window slots 3/5)',
				'UART1 (M11: window slot 5; SPI1 dropped)')
			lines = [l for l in lines if 'spi1' not in l]
		return lines

	def emitSpi1InputTaps(self):
		'''The SPI1 pad input taps on P2.0-3 (disappear with the instance).'''
		return list(SPI1_INPUT_TAPS) if self.spi1 else []

	def emitUart1InputMuxes(self):
		'''The UART1 relocatable-input muxes (RX1/ren; disappear with the
		instance — the pnum_gpio2_af1_tx1/rx1 constants they read are gated).'''
		return list(UART1_INPUT_MUXES) if self.uart1 else []

	def emitGpio1PrimaryPlanes(self):
		'''The P2 (GPIO1) primary alt-function aggregates. Dropped UART1/SPI1
		rows keep their pnum choice (AF0 pnum constants are transcription,
		not gated) but drive the hi-Z '0' idiom; the CS1 manual-toggle
		passthrough survives an SPI1 drop as a plain-GPIO passthrough.'''
		lines = list(GPIO1_PRIMARY_PLANES)
		drops = {}
		if not self.uart1:
			drops.update({'rx1': ('7', 'UART1'), 'tx1': ('6', 'UART1')})
		if not self.spi1:
			drops.update({'sck1': ('3', 'SPI1'), 'mosi1': ('2', 'SPI1'), 'miso1': ('1', 'SPI1')})
		if not drops:
			return lines
		out = []
		for l in lines:
			m = re.match(r'^(\s*pnum_gpio1_(\w+) => )\w+_(?:out|dir|ren),\s*--.*$', l)
			if m and m.group(2) in drops:
				pin, owner = drops[m.group(2)]
				col = l.index('--')
				body = m.group(1) + "'0',"
				l = body.ljust(col) + '-- GPIO1 pin ' + pin + ': reserved (' + owner + ' dropped)'
			elif not self.spi1 and 'CS1 line manually toggled' in l:
				col = l.index('--')
				l = l[:col].rstrip().ljust(col) + '-- GPIO1 pin 0 (ex-CS1; SPI1 dropped)'
			out.append(l)
		return out

	def emitGpio1Af1Planes(self):
		'''The P2 (GPIO1) AF1 relocation-plane aggregates. TIMER1's compare
		relocations on P2.2/3 and I2C1's v2 relocations on P2.4/5 degrade to
		the '0' idiom (literal pin index — the pnum_gpio1_af1_t1_cmp* /
		pnum_gpio1_af1_{sda1,scl1} constants are gated with their owner).'''
		lines = list(GPIO1_AF1_PLANES)
		if not self.spi1:
			lines[0] = lines[0].replace('(the SPI1 pins)', '(the ex-SPI1 pins)')
		if not self.uart1:
			lines[1] = lines[1].replace('(the UART1 pins)', '(the ex-UART1 pins)')
		dropRows = {}
		if not self.timer1:
			lines[0] = lines[0].replace('TIMER0/1 compare (PWM) outputs on P2.0-3',
				'TIMER0 compare (PWM) outputs on P2.0/1 (TIMER1 dropped)')
			dropRows.update({'t1_cmp0': ('2', 'TIMER1'), 't1_cmp1': ('3', 'TIMER1')})
		if not self.i2c1:
			lines[1] = lines[1].replace('I2C1 relocation on P2.4/5 (v2), ',
				'P2.4/5 reserved (I2C1 dropped), ')
			lines[2] = lines[2].replace('both I2C buses land', 'I2C0 lands')
			dropRows.update({'sda1': ('4', 'I2C1'), 'scl1': ('5', 'I2C1')})
		if dropRows:
			out = []
			for l in lines:
				m = re.match(r'^(\s*)pnum_gpio1_af1_(\w+) => \w+_(out|dir|ren),\s*--.*$', l)
				if m and m.group(2) in dropRows:
					pin, owner = dropRows[m.group(2)]
					mode = {'out': 'hi-Z input', 'dir': 'input', 'ren': 'pull disabled'}[m.group(3)]
					col = l.index('--')
					body = m.group(1) + pin + " => '0',"
					l = body.ljust(col) + '-- GPIO1 pin ' + pin + ': reserved, ' + owner + ' dropped (' + mode + ')'
				out.append(l)
			lines = out
		return lines

	def emitGpio2TimerMuxes(self):
		'''The TIMER compare-ren / capture-input AF-selection muxes. TIMER1's
		muxes disappear with the instance (their pnum_gpio*_af1_t1_* and
		peripheral-side signals are gated); comments narrow to TIMER0.'''
		lines = list(GPIO2_TIMER_MUXES)
		if self.timer1:
			return lines
		out = []
		skip = 0
		for l in lines:
			if skip:
				skip -= 1
				continue
			s = l.strip()
			if s.startswith(('t1_cmp0_ren_in', 't1_cmp1_ren_in')):
				skip = 4	# 5-line two-stage conditional assignment
				continue
			if s.startswith(('t1_cap0_in', 't1_cap1_in', 't1_cap0_ren_in', 't1_cap1_ren_in')):
				skip = 2	# 3-line conditional assignment
				continue
			if 'three locations (home P3.0/1/4/5,' in l:
				l = l.replace('(home P3.0/1/4/5,', '(home P3.0/1,')
			elif s.startswith('-- AF1 on P2.0-3, AF1 on P4.4-7)'):
				l = l.replace('AF1 on P2.0-3, AF1 on P4.4-7)', 'AF1 on P2.0/1, AF1 on P4.4/5)')
			elif s.startswith('-- selection with fixed priority'):
				l = l.replace('priority P2 > P4 > home.', 'priority P2 > P4 > home (TIMER1 dropped).')
			elif s.startswith('-- Capture inputs relocate to P4.0-3'):
				l = l.replace('relocate to P4.0-3 (AF1)', 'relocate to P4.0/1 (AF1; TIMER1 dropped)')
			out.append(l)
		return out

	def emitGpio2PrimaryPlanes(self):
		'''The P3 (GPIO2) primary alt-function aggregates. Dropped TIMER1 rows
		keep their pnum choice (AF0 transcription) and drive '0'; the
		t1_cap0 out-plane passthrough (p3_out) survives — it references no
		TIMER1 signal and is already the plain-GPIO idiom.'''
		lines = list(GPIO2_PRIMARY_PLANES)
		if self.timer1:
			return lines
		pinMap = {'t1_cmp0': '4', 't1_cmp1': '5', 't1_cap0': '6', 't1_cap1': '7'}
		out = []
		for l in lines:
			m = re.match(r'^(\s*pnum_gpio2_(t1_(?:cmp[01]|cap[01])) => )t1_\w+_(?:out|dir|ren),\s*--.*$', l)
			if m:
				col = l.index('--')
				body = m.group(1) + "'0',"
				l = body.ljust(col) + '-- GPIO2 pin ' + pinMap[m.group(2)] + ': reserved (TIMER1 dropped)'
			out.append(l)
		return out

	def emitGpio3Af1Planes(self):
		'''The P4 (GPIO3) AF1 relocation-plane aggregates. TIMER1's capture
		relocations (P4.2/3) and compare relocations (P4.6/7) degrade to the
		'0' idiom with literal pin indices (their pnums are gated).'''
		lines = list(GPIO3_AF1_PLANES)
		if self.timer1:
			return lines
		hdr = ['        -- AF1 plane: TIMER0 capture inputs relocate to P4.0/1 (the I2C0 pins),',
			'        -- TIMER0 compare (PWM) outputs relocate to P4.4/5 (the dead DTP pins;',
			"        -- TIMER1 dropped). Captures are inputs: out slice '0', dir/ren from the timer."]
		pinMap = {'t1_cap0': '2', 't1_cap1': '3', 't1_cmp0': '6', 't1_cmp1': '7'}
		out = list(hdr)
		for l in lines[3:]:
			m = re.match(r"^(\s*)pnum_gpio3_af1_(t1_(?:cmp[01]|cap[01])) => (?:\w+_(?:out|dir|ren)|'0'),\s*--.*$", l)
			if m:
				pin = pinMap[m.group(2)]
				col = l.index('--')
				body = m.group(1) + pin + " => '0',"
				l = body.ljust(col) + '-- GPIO3 pin ' + pin + ': reserved, TIMER1 dropped'
			out.append(l)
		return out

	def emitAfSpread(self, gi):
		'''One GPIO port's AF output-spread block: the AF1..AF7 (GPIO0) /
		AF2..AF7 (GPIO1-3) plane aggregates + the 8-plane flatten, emitted
		from the description's FromSpread altFuncs (generate.py filters
		_GPIO_AF_SPREAD by config, so a dropped source's slots read '0').
		SPREAD_SIG owns the RTL signal spellings; byte-identity at defaults
		is proven by check_mcu_vhd.py STRICT.'''
		port = self.periph('GPIO' + str(gi))
		n = gi + 1
		byPin = {}
		for pin in port.Pins:
			byPin[pin.BitNumber] = pin
		lines = list(SPREAD_HEADERS[gi])
		planes = range(1, 8) if gi == 0 else range(2, 8)
		for k in planes:
			for sfx in ('out', 'dir', 'ren'):
				lines.append('        afunc%d_af%d_%s <= (' % (n, k, sfx))
				for b in range(7, -1, -1):
					src = "'0'"
					for af in byPin[b].AltFuncs:
						if af.Index == k and getattr(af, 'FromSpread', False):
							src = SPREAD_SIG[af.Name] + '_' + sfx
					lines.append('            %d => %s%s' % (b, src, '' if b == 0 else ','))
				lines.append('        );')
		for sfx in ('out', 'dir', 'ren'):
			parts = ['afunc%d_af%d_%s' % (n, k, sfx) for k in range(7, 0, -1)]
			parts.append('afunc%d_%s' % (n, sfx))
			lines.append('        afunc%d_all_%s <= ' % (n, sfx) + ' & '.join(parts) + ';')
		return lines

	def emitAnalogTieOffs(self):
		'''The ex-SARADC/AFE alt-function tie-offs. t1_cap1_out's tie leaves
		with TIMER1 (its declaration lives in the TIMER1 pad-decl block).'''
		lines = list(ANALOG_TIE_OFFS)
		if not self.timer1:
			lines = [l for l in lines if not l.strip().startswith('t1_cap1_out')]
			lines = [l.replace('GPIO2 pins 3/7 (T0/T1 CAP1 out, formerly SARADC DTP0/1)',
				'GPIO2 pin 3 (T0 CAP1 out, formerly SARADC DTP0; TIMER1 dropped)') for l in lines]
		return lines

	def windowTop(self):
		return (1 << (self.shAw + 2)) - 1

	def banksTop(self):
		return 0x10000 + self.banks * 0x4000 - 1

	def emitShWindowConst(self):
		ind = ' ' * 8
		pw = self.shAw - 12
		lines = []
		lines.append(ind + '-- M3c.2: shared window behind mp_arbiter on mclk. M5b widened SH_AW')
		lines.append(ind + '-- 8 -> 12 (whole pre-M11 region 4). M11 memory-map rework: SH_AW')
		lines.append(ind + '-- 12 -> ' + str(self.shAw) + ' ' + EMDASH + ' the arbiter word address now covers ALL of')
		lines.append(ind + '-- 0x00000-0x%05X (word addr = data_addr(%d:2)) and the slave' % (self.windowTop(), self.shAw + 1))
		lines.append(ind + '-- sub-decode selects on s_addr(' + str(self.shAw - 1) + ':12):')
		lines.append(ind + '--   ' + self.pageBits(0) + ' = boot ROM 0x0-0x3FFF (M12: THE shared boot ROM ' + EMDASH + ' one')
		lines.append(ind + '--   ' + ' ' * pw + '   rom_hvt_pg, read-only slave; all ' + self.hartsWord() + ' harts reset here)')
		lines.append(ind + '--   ' + self.pageBits(1) + ' = peripheral window 0x4000-0x7FFF (page 0 = 16 x 256B slots')
		lines.append(ind + '--   ' + ' ' * pw + '   at the LEGACY slot numbering, page 1 = CLINT @0x5000,')
		lines.append(ind + '--   ' + ' ' * pw + '   page 2 = MUTEX bank @0x6000, page 3 = IRQ router @0x7000)')
		lines.append(ind + '--   ' + self.pageBits(2) + ' = dead (TCM region ' + EMDASH + ' tile-private, never arrives here)')
		if self.npu:
			lines.append(ind + '--   ' + self.pageBits(3) + ' = NPU staging RAM 0xC000-0xFFFF (one sram1p16k, NPU-muxed)')
		else:
			lines.append(ind + '--   ' + self.pageBits(3) + ' = dead (ex-NPU staging window 0xC000-0xFFFF ' + EMDASH + ' the NPU is')
			lines.append(ind + '--   ' + ' ' * pw + '   dropped in this configuration; reads return zero)')
		bankBits = _clog2(self.banks)
		if pw == 3 and self.banks == 4:
			bankCode = '1xx'
		else:
			bankCode = self.pageBits(4) + '-' + self.pageBits(4 + self.banks - 1)
		lines.append(ind + '--   ' + bankCode + ' = shared bulk RAM 0x10000-0x%05X (%d x sram1p16k banks,' % (self.banksTop(), self.banks))
		lines.append(ind + '--   ' + ' ' * len(bankCode) + '   bank = s_addr(' + str(11 + bankBits) + ':12))')
		if 4 + self.banks < (1 << pw):
			lines.append(ind + '--   ' + self.pageBits(4 + self.banks) + '-' + self.pageBits((1 << pw) - 1)
				+ ' = unmapped (window power-of-two round-up gap; reads zero)')
		lines.append((ind + 'constant SH_AW : natural := ' + str(self.shAw) + ';').ljust(55)
			+ '-- shared-window word-address width')
		return lines

	def emitMemslvDecls(self):
		ind = ' ' * 8
		pw = self.shAw - 12
		lines = []
		lines.append(ind + '-- M11 slave fabric: page select on s_addr(' + str(self.shAw - 1) + ':12) (see the SH_AW')
		lines.append(ind + '-- comment above for the map). The peripheral window sub-decodes on')
		lines.append(ind + '-- s_addr(11:10) into 4 pages; page 0 = 16 x 256B slots at the LEGACY')
		lines.append(ind + '-- 0x4000 slot numbering (slot = s_addr(9:6)) ' + EMDASH + ' every peripheral is')
		lines.append(ind + '-- back at its original Myshkin address, now shared by all ' + str(self.nHarts()) + ' harts.')
		def decl(name, comment=None):
			line = ind + 'signal ' + name.ljust(17) + ': std_logic;'
			if comment is not None:
				line += '   -- ' + comment
			return line
		lines.append(decl('shslv_rom_sel', self.pageBits(0) + ' -> shared boot ROM 0x0-0x3FFF (M12)'))
		lines.append(decl('shslv_perwin_sel', self.pageBits(1) + ' -> peripheral window 0x4000-0x7FFF'))
		lines.append(decl('shslv_pg0_sel', 'window page 0 -> the 16 slots'))
		if self.npu:
			lines.append(decl('shslv_npuram_sel', self.pageBits(3) + ' -> NPU staging RAM 0xC000-0xFFFF'))
		for b in range(self.banks):
			lines.append(decl('shslv_bank' + str(b) + '_sel',
				self.pageBits(4 + b) + ' -> bulk RAM bank %d (0x%05X)' % (b, 0x10000 + b * 0x4000)))
		lines.append(decl('shslv_rom_en'))
		if self.npu:
			lines.append(decl('shslv_npuram_en'))
		for b in range(self.banks):
			lines.append(decl('shslv_bank' + str(b) + '_en'))
		def rddecl(name, comment=None):
			line = ind + 'signal ' + name.ljust(17) + ": std_logic := '0';"
			if comment is not None:
				line += ' -- ' + comment
			return line
		lines.append(rddecl('shslv_rd_rom', 'registered: last access was the boot ROM'))
		if self.npu:
			lines.append(rddecl('shslv_rd_npuram', 'registered: last access was the NPU RAM'))
		for b in range(self.banks):
			lines.append(rddecl('shslv_rd_bank' + str(b)))
		lines.append(ind + '-- boot ROM + bulk RAM banks' + (' + NPU staging RAM' if self.npu else '') + ' are hard macros: their')
		lines.append(ind + '-- Q is the 1-cycle registered read the arbiter\'s slave model')
		lines.append(ind + '-- expects, so the macro output IS the rdata (no extra register).')
		lines.append(ind + '-- Enables/WEN are ACTIVE-LOW at the macro ' + EMDASH + ' shims below.')
		def vdecl(name):
			return ind + 'signal ' + name.ljust(17) + ': std_logic_vector(31 downto 0);'
		lines.append(vdecl('rom_q'))
		for b in range(self.banks):
			lines.append(vdecl('bank' + str(b) + '_q'))
		if self.npu:
			lines.append(vdecl('npuram_q'))
		lines.append(decl('rom_cen_n'))
		if self.npu:
			lines.append(decl('npuram_cen_n'))
		for b in range(self.banks):
			lines.append(decl('bank' + str(b) + '_cen_n'))
		lines.append(ind + 'signal ' + 'shmem_gwen_n'.ljust(17) + ': std_logic;   -- shared-macro global write enable (active-low)')
		return lines

	def emitPgenDecls(self):
		ind = ' ' * 8
		lines = []
		if self.npu:
			lines.append(ind + "-- (M13: hart 0's adddec<->TCM bus moved into hart_tile; pgen_mem")
			lines.append(ind + '-- stays ' + EMDASH + " SYSTEM0's BLOCKPWR gates rom0 (0), hart 0's TCM via the")
			lines.append(ind + "-- tile's tcm_pgen port (1) and npuram0 (2).)")
		else:
			lines.append(ind + "-- (M13: hart 0's adddec<->TCM bus moved into hart_tile; pgen_mem")
			lines.append(ind + '-- stays ' + EMDASH + " SYSTEM0's BLOCKPWR gates rom0 (0) and hart 0's TCM via the")
			lines.append(ind + "-- tile's tcm_pgen port (1); bit 2 (ex-npuram0) has no consumer")
			lines.append(ind + '-- in this configuration ' + EMDASH + ' the NPU and its staging RAM are dropped.)')
		lines.append(ind + 'signal ' + 'RAM_Dout'.ljust(17) + ': std_logic_vector(31 downto 0);')
		lines.append(ind + 'signal ' + 'pgen_mem'.ljust(17) + ': std_logic_vector(2 downto 0);')
		return lines

	def emitShslvBanner(self):
		ind = ' ' * 4
		lines = []
		lines.append(ind + '-- M5b/M11/M12: slave-side sub-decode of the shared window. The arbiter')
		lines.append(ind + '-- serializes ALL masters onto ONE slave port; the ' + str(self.shAw) + '-bit word address')
		lines.append(ind + '-- then selects which physical slave this transaction hits (s_addr(' + str(self.shAw - 1) + ':12)')
		lines.append(ind + '-- pages, see the SH_AW comment):')
		lines.append(ind + '--   0x00000-0x03FFF -> THE shared boot ROM (M12: one rom_hvt_pg,')
		lines.append(ind + '--                      read-only ' + EMDASH + ' writes complete but are discarded)')
		lines.append(ind + '--   0x04000-0x07FFF -> peripheral window: page 0 = 16 x 256B slots at')
		lines.append(ind + '--                      the LEGACY slot numbering (every peripheral back')
		lines.append(ind + '--                      at its Myshkin address, shared by all ' + str(self.nHarts()) + ' harts),')
		lines.append(ind + '--                      page 1 = CLINT, page 2 = MUTEX, page 3 = router')
		if self.npu:
			lines.append(ind + '--   0x0C000-0x0FFFF -> NPU staging RAM (sram1p16k, NPU-port-muxed)')
		lines.append(ind + '--   0x10000-0x%05X -> bulk RAM banks 0-%d (%d x sram1p16k)' % (self.banksTop(), self.banks - 1, self.banks))
		lines.append(ind + '--   everything else -> no slave (reads return 0)')
		lines.append(ind + '-- Every slave obeys the same 1-cycle registered-read contract (the SRAM')
		lines.append(ind + '-- macros natively; peripherals via their clk_mem-registered reads), so')
		lines.append(ind + "-- the arbiter's IDLE->LATCH->DATA timing is untouched; the shslv_rd_*")
		lines.append(ind + '-- selects are registered at the access cycle and steer s_rdata during')
		lines.append(ind + '-- DATA. resv_unit still snoops every transaction (its s_we_gated drives')
		lines.append(ind + '-- ALL slaves: a suppressed SC write must not touch a peripheral either).')
		return lines

	def emitSharedRamBanks(self):
		ind = ' ' * 4
		lines = []
		lines.append(ind + '-- =========================================================================')
		lines.append(ind + '-- M11: shared bulk RAM = %d x sram1p16k macros (%d KB, 0x10000-0x%05X),'
			% (self.banks, self.banks * 16, self.banksTop()))
		lines.append(ind + "-- replacing the M3c 256-word behavioral array. The macro IS the arbiter's")
		lines.append(ind + '-- slave model: CEN sampled with the address at the s_en cycle\'s ending')
		lines.append(ind + '-- edge, Q valid the next cycle (1-cycle registered read). Enables/WEN are')
		lines.append(ind + '-- ACTIVE-LOW at the macro ' + EMDASH + ' inverted from the arbiter\'s active-high')
		lines.append(ind + '-- strobes; WEN comes from the resv-GATED sh_we (a suppressed SC write')
		lines.append(ind + '-- must not touch memory), per-byte lanes (M4a). No INIT: power-up')
		lines.append(ind + '-- contents are undefined on silicon ' + EMDASH + ' the write-before-read contract')
		lines.append(ind + '-- (mailbox zeroing) is an M12 bootrom obligation; behavioral models')
		lines.append(ind + '-- zero-fill, the gate flow deposits zeros.')
		lines.append(ind + '-- =========================================================================')
		for b in range(self.banks):
			nm = 'bank' + str(b) + '_cen_n'
			lines.append(ind + nm.ljust(13) + '<= not shslv_bank' + str(b) + '_en;')
		if self.npu:
			lines.append(ind + 'npuram_cen_n'.ljust(13) + '<= not shslv_npuram_en;')
		lines.append(ind + 'rom_cen_n'.ljust(13) + '<= not shslv_rom_en;   -- M12: shared boot ROM (read-only, no WEN)')
		lines.append(ind + 'shmem_gwen_n <= \'0\' when sh_we /= "0000" else \'1\';')
		for b in range(self.banks):
			lines.append('')
			lines.append(ind + 'shbank' + str(b) + ': entity work.sram1p16k_hvt_pg')
			lines.append(ind * 2 + 'port map (')
			lines.append(ind * 3 + 'Q     => bank' + str(b) + '_q,')
			lines.append(ind * 3 + 'CLK   => mclk,')
			lines.append(ind * 3 + 'CEN   => bank' + str(b) + '_cen_n,')
			lines.append(ind * 3 + 'WEN   => sh_wen_n,')
			lines.append(ind * 3 + 'A     => sh_addr(11 downto 0),')
			lines.append(ind * 3 + 'D     => sh_wdata,')
			lines.append(ind * 3 + 'EMA   => "000",')
			lines.append(ind * 3 + 'GWEN  => shmem_gwen_n,')
			lines.append(ind * 3 + "RETN  => '1',")
			lines.append(ind * 3 + "PGEN  => '0'")
			lines.append(ind * 2 + ');')
		return lines

	def emitMutexInstance(self):
		'''mtx0 (A2): NMUTEX from the description's MUTEX register count; the
		AW/MW generics and the addr slice follow. At 16 mutexes / 4 harts this
		is the golden master byte-identically (defaults omitted).'''
		nMutex = len(self.periph('MUTEX').Registers)
		aw = _clog2(nMutex)
		if 2**aw != nMutex:
			raise Exception('MCU.vhd emitter: MUTEX register count ' + str(nMutex)
				+ ' must be a power of two (exact word alias, mutex_bank AW)')
		mw = self.masterW()
		gm = 'generic map (NMUTEX => ' + str(nMutex)
		if aw != 4:
			gm += ', AW => ' + str(aw)
		if mw != 2:
			gm += ', MW => ' + str(mw)
		gm += ')'
		lines = []
		lines.append('    mtx0: entity work.mutex_bank')
		lines.append(' ' * 8 + gm)
		lines.append('        port map (')
		lines.append('            clk    => mclk,')
		lines.append('            resetn => resetn,')
		lines.append('            en     => shslv_mtx_en,')
		lines.append('            we     => sh_we,')
		lines.append('            addr   => sh_addr(' + str(aw - 1) + ' downto 0),')
		lines.append('            wdata  => sh_wdata,')
		lines.append('            master => sh_master,')
		lines.append('            rdata  => mtx_rdata')
		lines.append('        );')
		return lines

	def emitPwrInstance(self):
		'''pwr0 (A2): NHARTS generic emitted when != the RTL default 4. The
		description's PWRSR word count is cross-checked against the nibble-
		array formula ceil(N/8) (RAISES on drift, like the CLINT layout).'''
		n = self.nHarts()
		nsrw = (n + 7) // 8
		maxSlot = 0
		for r in self.periph('PWRCTRL').Registers:
			if r.RegisterMemorySlot > maxSlot:
				maxSlot = r.RegisterMemorySlot
		if maxSlot != nsrw:
			raise Exception('MCU.vhd emitter: PWRCTRL register layout does not match the A2 '
				+ 'PWRSR nibble-array formula (PWRCR + ceil(N/8) PWRSR words) '
				+ EMDASH + ' generate.py and pwr_ctrl.vhd must agree')
		gm = 'generic map ('
		if n != 4:
			gm += 'NHARTS => ' + str(n) + ', '
		gm += 'T_SEQ => 4, T_RAIL => 256)'
		lines = []
		lines.append('    pwr0: entity work.pwr_ctrl')
		lines.append(' ' * 8 + gm)
		lines.append('        port map (')
		lines.append('            clk       => mclk,')
		lines.append('            resetn    => resetn,')
		lines.append('            en        => shslv_pwr_en,')
		lines.append('            we        => sh_we,')
		lines.append('            addr      => sh_addr(3 downto 0),')
		lines.append('            wdata     => sh_wdata,')
		lines.append('            rdata     => pwr_rdata,')
		lines.append('            pd_iso_en => pd_iso_en,')
		lines.append('            pd_sleep  => pd_sleep,')
		lines.append('            pd_rstn   => pd_rstn')
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
		lines.append('            ENABLE_BITMANIP   => CORE_ENABLE_BITMANIP,')
		lines.append('            ENABLE_ZICOND     => CORE_ENABLE_ZICOND,')
		lines.append('            ENABLE_ZCB        => CORE_ENABLE_ZCB,')
		lines.append('            ENABLE_ZIMOP      => CORE_ENABLE_ZIMOP,')
		lines.append('            ENABLE_ZIHINT     => CORE_ENABLE_ZIHINT,')
		lines.append('            ENABLE_ZIHPM      => CORE_ENABLE_ZIHPM,')
		lines.append('            ENABLE_ZAWRS      => CORE_ENABLE_ZAWRS,')
		lines.append('            ENABLE_ZABHA      => CORE_ENABLE_ZABHA,')
		lines.append('            ENABLE_ZACAS      => CORE_ENABLE_ZACAS,')
		lines.append('            ENABLE_ZICBOZ     => CORE_ENABLE_ZICBOZ,')
		lines.append('            ENABLE_ZCMP       => CORE_ENABLE_ZCMP,')
		lines.append('            ENABLE_ZCMT       => CORE_ENABLE_ZCMT,')
		lines.append('            ENABLE_ZBKB       => CORE_ENABLE_ZBKB,')
		lines.append('            ENABLE_ZBKC       => CORE_ENABLE_ZBKC,')
		lines.append('            ENABLE_ZBKX       => CORE_ENABLE_ZBKX,')
		lines.append('            ENABLE_ZKN        => CORE_ENABLE_ZKN,')
		lines.append('            ENABLE_ZFINX      => CORE_ENABLE_ZFINX')
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
		if h == 1:
			lines.append('            -- M19: ONE external-IRQ wire per tile ' + EMDASH + " the irq_router's")
			lines.append('            -- registered claim/complete output (routing/masking lives in')
			lines.append("            -- the router rows; the tile hardwires its three live slots)")
		lines.append('            meip_in   => meip(' + hs + '),')
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
		lines.append('            sh_resv_valid => arb_resvvld(' + hs + '),')
		lines.append('            sh_lock   => tile' + hs + '_lock_raw,')
		lines.append("            -- M17: the tile's TCM macro is on the ALWAYS-ON rail but rides")
		lines.append('            -- its own native PGEN power-down whenever the domain gates ' + EMDASH)
		lines.append("            -- tcm_pgen is a straight wire to ram0's PGEN pin (was '0')")
		lines.append('            tcm_pgen  => pd_sleep(' + hs + '),')
		lines.append('            -- PG1 F2: retention strapped OFF from the ALWAYS-ON top (the macro')
		lines.append('            -- RETN receiver is AO ' + EMDASH + ' an in-tile tie was a dying-rail driver)')
		lines.append("            tcm_retn  => '1',")
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
				'en': self.shslv[name]['shim'] + '_sh_en_n',
				'en_mem': self.shslv[name]['shim'] + '_sh_en_n',
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
		spec = self.busSpecs[instKey]
		name = spec['periph']
		ind = ' ' * 12
		lines = self.busComment(instKey, spec)
		if spec['comment'] == 'i2c':
			# I2C.vhd port names, tab-aligned like the RTL
			en = self.shslv[name]['shim'] + '_sh_en_n'
			lines.append(ind + 'ClkMem\t\t\t=> mclk,')
			lines.append(ind + 'EnMemPeriph\t\t=> ' + en + ',')
			lines.append(ind + 'WEn\t\t\t\t=> sh_wen_n,')
			lines.append(ind + 'MABPart\t\t\t=> sh_addr(5 downto 0),')
			lines.append(ind + 'wdata\t\t\t=> sh_wdata,')
			lines.append(ind + 'rdata_out\t\t=> ' + self.rdataSignal(name) + ',')
			return lines
		if spec['comment'] == 'npu':
			en = self.shslv[name]['shim'] + '_sh_en_n'
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
		if name == 'meip-decl':
			return self.emitMeipDecl()
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
		if name == 'mutex-instance':
			return self.emitMutexInstance()
		if name == 'pwr-instance':
			return self.emitPwrInstance()
		if name == 'sh-window-const':
			return self.emitShWindowConst()
		if name == 'memslv-decls':
			return self.emitMemslvDecls()
		if name == 'pgen-decls':
			return self.emitPgenDecls()
		if name == 'shslv-banner':
			return self.emitShslvBanner()
		if name == 'shared-ram-banks':
			return self.emitSharedRamBanks()
		if name in ('npu-component', 'npu-fabric-decls', 'npu-mux-decls',
				'npu-sleep-comment', 'npu-instance', 'npuram-instance'):
			return self.npuBlock(name)
		if name in ('i2c1-pad-decls', 'i2c1-instance'):
			return self.i2c1Block(name)
		if name == 'i2c-fabric-decls':
			return self.emitI2cFabricDecls()
		if name == 'gpio2-af1-planes':
			return self.emitGpio2Af1Planes()
		if name == 'i2c-input-muxes':
			return self.emitI2cInputMuxes()
		if name == 'gpio3-primary-planes':
			return self.emitGpio3PrimaryPlanes()
		if name in ('uart1-pad-decls', 'uart1-instance'):
			return self.uart1Block(name)
		if name in ('spi1-pad-decls', 'spi1-instance'):
			return self.spi1Block(name)
		if name in ('timer1-pad-decls', 'timer1-instance'):
			return self.timer1Block(name)
		if name == 'mover-fabric-decls':
			return self.emitMoverFabricDecls()
		if name == 'spi1-input-taps':
			return self.emitSpi1InputTaps()
		if name == 'uart1-input-muxes':
			return self.emitUart1InputMuxes()
		if name == 'gpio1-primary-planes':
			return self.emitGpio1PrimaryPlanes()
		if name == 'gpio1-af1-planes':
			return self.emitGpio1Af1Planes()
		if name == 'gpio2-timer-muxes':
			return self.emitGpio2TimerMuxes()
		if name == 'gpio2-primary-planes':
			return self.emitGpio2PrimaryPlanes()
		if name == 'gpio3-af1-planes':
			return self.emitGpio3Af1Planes()
		if name in ('gpio0-af-spread', 'gpio1-af-spread', 'gpio2-af-spread', 'gpio3-af-spread'):
			return self.emitAfSpread(int(name[4]))
		if name == 'analog-tie-offs':
			return self.emitAnalogTieOffs()
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
		if name == 'slot12-decls':
			return self.emitSlot12Decls()
		if name == 'slot12-instances':
			return self.emitSlot12Instances()
		if name == 'i3c-decls':
			return self.emitI3cDecls()
		if name == 'i3c-instance':
			return self.emitI3cInstance()
		if name == 'nfc-decls':
			return self.emitNfcDecls()
		if name == 'nfc-instance':
			return self.emitNfcInstance()
		if name == 'rtc-decls':
			return self.emitRtcDecls()
		if name == 'rtc-instance':
			return self.emitRtcInstance()
		if name == 'gpio4-decls':
			return self.emitGpio45Decls(5)
		if name == 'gpio5-decls':
			return self.emitGpio45Decls(6)
		if name == 'gpio4-instance':
			return self.emitGpio4Instance()
		if name == 'gpio5-instance':
			return self.emitGpio5Instance()
		if name == 'irq-gf-decls':
			return self.emitIrqGfDecls()
		if name == 'irq-gf-instances':
			return self.emitIrqGfInstances()
		if name == 'rdata-bridge':
			return self.emitRdataBridge()
		if name == 'sh-rdata-mux':
			return self.emitShRdataMux()
		if name == 'polarity-shims':
			return self.emitPolarityShims()
		if name.startswith('bus:'):
			instKey = name[len('bus:'):]
			if instKey not in self.busSpecs:
				raise Exception('MCU.vhd emitter: no bus spec for instance "' + instKey + '"')
			return self.emitBus(instKey)
		raise Exception('MCU.vhd emitter: unknown region "' + name + '"')


def loadSideBlocks(path, tag):
	'''Parse a side template: --@<tag>:<name>@ marker lines delimit the
	verbatim conditional blocks (A2 NPU mechanism, generalized at G1a).'''
	blocks = {}
	cur = None
	marker = re.compile(r'^--@' + tag + r':([A-Za-z0-9:_-]+)@$')
	with open(path, 'r', newline='') as f:
		for line in f.read().split('\n'):
			m = marker.match(line)
			if m:
				cur = []
				blocks[m.group(1)] = cur
			elif cur is not None:
				cur.append(line)
	# strip one trailing blank line per block (the inter-block separator)
	for name in blocks:
		while blocks[name] and blocks[name][-1] == '':
			blocks[name].pop()
	return blocks


def generateMcuVhd(gen, templatePath, outPath):
	'''Fill hdl_templates/MCU.template.vhd markers from the description; write outPath.'''
	tplDir = os.path.dirname(templatePath)
	emitter = McuVhdEmitter(gen,
		npuBlocks=loadSideBlocks(os.path.join(tplDir, 'MCU.template.npu.vhd'), 'NPUBLOCK'),
		i2c1Blocks=loadSideBlocks(os.path.join(tplDir, 'MCU.template.i2c1.vhd'), 'I2C1BLOCK'),
		uart1Blocks=loadSideBlocks(os.path.join(tplDir, 'MCU.template.uart1.vhd'), 'UART1BLOCK'),
		spi1Blocks=loadSideBlocks(os.path.join(tplDir, 'MCU.template.spi1.vhd'), 'SPI1BLOCK'),
		timer1Blocks=loadSideBlocks(os.path.join(tplDir, 'MCU.template.timer1.vhd'), 'TIMER1BLOCK'))

	with open(templatePath, 'r', newline='') as f:
		templateLines = f.read().split('\n')

	header = []
	header.append('-- MCU.vhd')
	header.append('-- Castalia MCU top-level integration layer (' + str(emitter.nHarts()) + ' harts, MCU_MP)')
	header.append('-- Golden-master templated from the verified hdl/common/MCU.vhd: the fixed')
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
		# digperiphs #1: page-0 slot 12 (0x4C00) real estate (AFE stubs / QSPI0)
		'slot12-decls', 'slot12-instances',
		# digperiphs #2: I3C0 in MUTEX-page (page 2) sub-slot 1 @0x6100
		'i3c-decls', 'i3c-instance',
		# digperiphs #3: NFC0 in MUTEX-page (page 2) sub-slot 2 @0x6200 +
		# the geometry-driven glitch-filter region (NFC needs a 4th instance)
		'nfc-decls', 'nfc-instance', 'irq-gf-decls', 'irq-gf-instances',
		# digperiphs #4: RTC0 in MUTEX-page (page 2) sub-slot 5 @0x6500
		'rtc-decls', 'rtc-instance',
		# Mission B: GPIO4/GPIO5 in MUTEX-page (page 2) sub-slots 3/4 @0x6300/0x6400
		'gpio4-decls', 'gpio5-decls', 'gpio4-instance', 'gpio5-instance',
		# A1 N-hart regions
		'a0-ports', 'arb-fabric-decls', 'clint-irq-decls', 'meip-decl', 'pd-decls',
		'tile-raw-decls', 'sh-master-decl', 'hart0-instance', 'arb-generic', 'resv-generic',
		'clint-instance', 'irq-router-instance', 'mutex-instance', 'pwr-instance',
		'tile-rstn', 'iso-clamps', 'tile-instances',
		# A2 geometry / NPU-conditional regions
		'sh-window-const', 'memslv-decls', 'pgen-decls', 'shslv-banner', 'shared-ram-banks',
		'npu-component', 'npu-fabric-decls', 'npu-mux-decls', 'npu-sleep-comment',
		'npu-instance', 'npuram-instance',
		# G1a I2C1-conditional regions (i2c1-pad-decls/instance are side-template
		# verbatim; the other four are transcribed emitters that degrade the
		# I2C1 rows to the hi-Z idiom when the config drops the instance)
		'i2c1-pad-decls', 'i2c1-instance', 'i2c-fabric-decls', 'gpio2-af1-planes',
		'i2c-input-muxes', 'gpio3-primary-planes',
		# G1b UART1/SPI1/TIMER1-conditional regions (pad-decls/instances are
		# side-template verbatim; the rest are transcribed emitters, except
		# the four *-af-spread blocks which emit from the FromSpread altFuncs)
		'uart1-pad-decls', 'uart1-instance', 'spi1-pad-decls', 'spi1-instance',
		'timer1-pad-decls', 'timer1-instance', 'mover-fabric-decls',
		'spi1-input-taps', 'uart1-input-muxes', 'gpio1-primary-planes',
		'gpio1-af1-planes', 'gpio2-timer-muxes', 'gpio2-primary-planes',
		'gpio3-af1-planes', 'gpio0-af-spread', 'gpio1-af-spread',
		'gpio2-af-spread', 'gpio3-af-spread', 'analog-tie-offs']
		# bus:npu0/i2c1/uart1/spi1/timer1 live INSIDE their instance side blocks
		+ ['bus:' + k for k in emitter.busSpecs if k not in ('npu0', 'i2c1', 'uart1', 'spi1', 'timer1')])
	if seen != expected:
		raise Exception('MCU.vhd emitter: template regions ' + str(sorted(seen))
			+ ' do not match the expected set ' + str(sorted(expected)))

	with open(outPath, 'w', newline='\n') as f:
		f.write('\n'.join(out))

	print('VHDL MCU top-level saved to ' + outPath)
	return
