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
# CP2 (Castalia-Penta, 2026-08-13) adds the THIRD hart-instance emitter beside
# emitHart0Instance and tileInstance:
#   - orch-instance                   : the always-on SOFT ORCHESTRATOR hart,
#     `hart<N-1> : entity work.orch_tile` — hart-0-style power/reset (no
#     pwr_ctrl row, no iso clamps, sh_* direct into its arbiter slice) with
#     tile-style boot/IRQ wiring. Driven by the managementHart knob; emits
#     NOTHING at managementHart=0, which is what keeps the golden master
#     byte-identical. The knob also (a) shortens the pd_*/tile_rstn/iso-clamp/
#     tile-raw ranges to the GATEABLE tiles (pwrHarts) while CLINT, irq_router,
#     debug_module and every master index stay on the full nHarts, and (b)
#     passes afe_stub's MGMT_HART / eis0's OWNER_HART (D4).
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
	# digperiphs #5 (A7): PWM0 outputs REPLACE the P2.2/P2.3 AF2 redundant timer-
	# compare spread copies (generate.py gates this on peripherals.pwm). The pwm0/
	# pwm1 output-alias scalars are emitted in the gated PWM instance region
	# (emitPwmInstance); harmless keys when PWM is off (nothing references them).
	'PWM0': 'pwm0', 'PWM1': 'pwm1',
	# digperiphs #5 RE-PIN (Stage H): OW0's open-drain DQ REPLACES the redundant
	# T0CMP1 spread copy on P4.7 AF2 (generate.py gates this on peripherals.onewire).
	# An io slot like RX0/MISO1: the out/dir planes come from the OneWire entity's
	# OW_DQ_OUT/OW_DQ_DIR, the ren plane from the pad's own PxREN preference
	# (ow0_dq_ren, aliased in the gated OW0 instance region), and the pad INPUT is a
	# separate AFS-keyed relocation mux there too.
	'OW_DQ': 'ow0_dq',
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
		# CP2 (Castalia-Penta): the MANAGEMENT / ORCHESTRATOR hart index. 0 =
		# no orchestrator, and EVERY CP2 emitter degenerates to its pre-CP2
		# form (check_mcu_vhd.py STRICT is the bar). Non-zero = hart mgmtHart
		# (== numHarts-1, validated in generate.py) is the always-on soft
		# orchestrator: emitted as `entity work.orch_tile`, wired hart-0-style
		# for power/reset and tile-style for boot/IRQ, excluded from pwr_ctrl's
		# rows and from the isolation clamps, and passed as afe_stub's
		# MGMT_HART. self.orchHart is the ONE place the index lives here.
		self.mgmtHart = geo.get('mgmtHart', 0)
		self.orch = (self.mgmtHart != 0)
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
		# digperiphs #5: PWM0 in MUTEX-page (page 2) sub-slot 6 @0x6600. Same
		# native-slave shape as RTC0 — a PLAIN raw-strobe en shim (NO
		# falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q, D4). Zero
		# INPUT pins: the two outputs pwm_out(0)/(1) are aliased into the AF spread
		# (P2.2/P2.3 AF2, A7). Default false => every PWM region is inert
		# (byte-identical default; the two spread slots keep their T0CMP0/T0CMP1 copies).
		self.pwm = geo.get('pwm', False)
		# digperiphs #5: OW0 (1-Wire master) in MUTEX-page (page 2) sub-slot 7 @0x6700.
		# Same native-slave shape as RTC0/PWM0 — a PLAIN raw-strobe en shim (NO
		# falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q, D4). One pad:
		# DQ on P4.7/GPIO31 AF2 open-drain (rstREN=1) — the pin-mux-v2 REPLACED-SPREAD-
		# SLOT mechanism: the out/dir/ren planes fall out of the GPIO3 AF spread emitter
		# (SPREAD_SIG['OW_DQ']), and the pad input mux + the ren alias are emitted with
		# the gated instance. Default false => every OneWire region is inert
		# (byte-identical default; the P4.7 AF2 slot keeps its T0CMP1 spread copy).
		self.onewire = geo.get('onewire', False)
		# DP-S3 (field-powered NFC mode): True wires pwr0's supervision inputs
		# (pgood_pad => prt6_in(7), strap_pad => prt6_in(6), field_detect =>
		# nfc0_field_detect-or-'0'); False ties all three inert ('1'/'0'/'0').
		# The pgood_rstn/hart0_rstn decls and the reset folds are emitted
		# UNCONDITIONALLY (a tied gate is stuck released — provable no-op);
		# only the pwr0 port-map ties vary. Independent of every other knob
		# since the Stage H re-pin (OW0's DQ left P6.6 for P4.7 AF2).
		self.fieldpower = geo.get('fieldPower', True)
		# digperiphs #6: DMA0 in MUTEX-page (page 2) sub-slot 8 @0x6800. Same
		# native-slave shape as RTC0/PWM0/OW0 (outside the page-0 shim fabric;
		# hand-decoded SEL + a PLAIN raw-strobe en shim, NO falling_edge(EnMemPeriph)
		# pre-latch and NO CAPTURE_CLOCK en_q, D4). UNLIKE every prior library block
		# DMA0 is ALSO an arbiter MASTER (the FIRST new master since the four harts):
		# self.dma widens the shared fabric from N=numHarts to N=numHarts+1 (the DMA is
		# master index numHarts, the LAST slice) -- see nMasters()/masterW() and the
		# arb_* / mp_arbiter / resv_unit / mutex_bank / irq_router emitters below.
		# dmaChannels ({2,4}) is the DMA entity NCH generic (register map is the
		# 4-channel superset regardless). Default false => every DMA region is inert
		# (byte-identical default; arbiter stays N=numHarts / MW / sh_master unchanged).
		self.dma = geo.get('dma', False)
		self.dmaChannels = geo.get('dmaChannels', 4)
		if self.dma and self.dmaChannels not in (2, 4):
			raise Exception('MCU.vhd emitter: dmaChannels must be 2 or 4, got ' + str(self.dmaChannels))
		# digperiphs (I2CT): I2CT0 (hardware-autonomous I2C target) in MUTEX-page (page 2)
		# sub-slot 10 @0x6A00. Same native-slave shape as RTC0/PWM0/OW0 — a PLAIN raw-strobe
		# en shim (NO falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q, D4). NO
		# new pins: I2CT0 shares I2C0's SDA0/SCL0 pad planes. The instance FANS OUT the
		# existing sda0_in/scl0_in inputs to its SDA_IN/SCL_IN and drives the NEW open-drain
		# DIR scalars i2ct0_sda_dir/i2ct0_scl_dir from its SDA_DIR/SCL_DIR ports; the
		# wired-AND merge of those into the sda0/scl0 DIR planes is a SEPARATE shared-RTL edit
		# (they are consumed nowhere in this emitter — an unused-signal state is expected at
		# this stage). Default false => every I2CT0 region is inert (byte-identical default).
		self.i2ctarget = geo.get('i2ctarget', False)
		# digperiphs (TRNG): TRNG0 (ring-oscillator entropy source + harvest engine) in
		# MUTEX-page (page 2) sub-slot 9 @0x6900. Same native-slave shape as
		# RTC0/PWM0/OW0/DMA0/I2CT0 -- a PLAIN raw-strobe en shim (NO falling_edge
		# (EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q, D4). Zero pins: the entropy
		# source is a SIBLING instance (u_ro, TrngRoEnsemble) wired through trng0's
		# ro_enable/ro_sel/ro_sclk (out) / ro_raw (in) ports -- not a pad group. trngRings
		# ({4,8}) is the shared NRO generic for BOTH trng0 and u_ro (the register map is
		# NRO-invariant). Default false => every TRNG region is inert (byte-identical
		# default).
		# D2: the Debug Module. Assembly level, always-on mclk, knob-gated by
		# debug.enable -- and the SECOND new arbiter MASTER after the DMA.
		# D3 adds the JTAG DTM (dtm0) behind the SAME knob: no debug.jtag
		# sub-knob exists, because the OR-merge keeps the raw-DMI drive path
		# alive with the DTM present-and-inert (d3_cdc_spec 7).
		self.debug = geo.get('debug', False)
		# D3: the CONFIG FILE's chipName (never the CHIP_NAME env override,
		# which is documentation-only) -- one half of the IDCODE chip-identity
		# discriminator in jtagIdcode().
		self.chipNameConfigured = geo.get('chipNameConfigured', '')
		self.trng = geo.get('trng', False)
		self.trngRings = geo.get('trngRings', 8)
		if self.trng and self.trngRings not in (4, 8):
			raise Exception('MCU.vhd emitter: trngRings must be 4 or 8, got ' + str(self.trngRings))
		# digperiphs (EVFAB): EVFAB0 (event/trigger fabric, PPI-style crossbar) in
		# MUTEX-page (page 2) sub-slot 11 @0x6B00. Same native-slave shape as
		# RTC0/PWM0/OW0/DMA0/TRNG0/I2CT0 -- a PLAIN raw-strobe en shim (NO
		# falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q, D4). Zero pins,
		# VECTORLESS (no irq net at all, D20). Its instance region ALSO owns the
		# crossbar wiring: the ev_in / gpio0_evin / task_busy inputs and the
		# task_pulse fan-out, with every producer or consumer whose block this config
		# drops TIED '0' (D23 -- never left open). The tap PORT-MAP lines on the
		# existing peripheral instances are emitted conditionally next to those
		# instances (generated ones inline, fixed/side-template ones through the
		# --@GEN:evfab-taps:<inst>@ markers). Default false => every EVFAB region is
		# inert and no existing instance grows a port (byte-identical default).
		self.eventFabric = geo.get('eventFabric', False)

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
		# digperiphs #5: PWM0 joins the same native-slave fabric (MUTEX-page
		# sub-slot 6). Its SEL is hand-decoded in emitShslvSubdecode; the shslv
		# entry (shim=None) puts it through the standard enable / registered rd-sel
		# / rdata-mux loops, and its active-low RAW-strobe en shim lives in
		# emitPwmInstance (no en_q register — D4).
		if self.pwm:
			self.shslv = dict(self.shslv)
			self.shslv['PWM0'] = {'sel': 'pwm0', 'shim': None, 'rdata': 'pwm0_sh_rdata'}
		# digperiphs #5: OW0 joins the same native-slave fabric (MUTEX-page sub-slot
		# 7). Its SEL is hand-decoded in emitShslvSubdecode; the shslv entry (shim=None)
		# puts it through the standard enable / registered rd-sel / rdata-mux loops, and
		# its active-low RAW-strobe en shim lives in emitOwInstance (no en_q register, D4).
		if self.onewire:
			self.shslv = dict(self.shslv)
			self.shslv['OW0'] = {'sel': 'ow0', 'shim': None, 'rdata': 'ow0_sh_rdata'}
		# digperiphs #6: DMA0 joins the same native-slave fabric (MUTEX-page sub-slot
		# 8). Its SEL is hand-decoded in emitShslvSubdecode; the shslv entry (shim=None)
		# puts its register file through the standard enable / registered rd-sel /
		# rdata-mux loops, and its active-low RAW-strobe en shim lives in
		# emitDmaInstance (no en_q register, D4). The DMA's MASTER port + the fabric
		# widening are separate (emitArbFabricDecls / the arbiter generics / the slice-4
		# port map), not part of the slave-fabric membership here.
		if self.dma:
			self.shslv = dict(self.shslv)
			self.shslv['DMA0'] = {'sel': 'dma0', 'shim': None, 'rdata': 'dma0_sh_rdata'}
		# digperiphs (I2CT): I2CT0 joins the same native-slave fabric (MUTEX-page sub-slot
		# 10). Its SEL is hand-decoded in emitShslvSubdecode; the shslv entry (shim=None) puts
		# its register file through the standard enable / registered rd-sel / rdata-mux loops,
		# and its active-low RAW-strobe en shim lives in emitI2ctInstance (no en_q register, D4).
		if self.i2ctarget:
			self.shslv = dict(self.shslv)
			self.shslv['I2CT0'] = {'sel': 'i2ct0', 'shim': None, 'rdata': 'i2ct0_sh_rdata'}
		# digperiphs (TRNG): TRNG0 joins the same native-slave fabric (MUTEX-page sub-slot
		# 9). Its SEL is hand-decoded in emitShslvSubdecode; the shslv entry (shim=None)
		# puts its register file through the standard enable / registered rd-sel /
		# rdata-mux loops, and its active-low RAW-strobe en shim lives in emitTrngInstance
		# (no en_q register, D4). The sibling u_ro TrngRoEnsemble instance (D6) is emitted
		# alongside trng0 in the same instance region -- it is not itself a bus slave.
		if self.trng:
			self.shslv = dict(self.shslv)
			self.shslv['TRNG0'] = {'sel': 'trng0', 'shim': None, 'rdata': 'trng0_sh_rdata'}
		# digperiphs (EVFAB): EVFAB0 joins the same native-slave fabric (MUTEX-page
		# sub-slot 11). Its SEL is hand-decoded in emitShslvSubdecode; the shslv entry
		# (shim=None) puts its register file through the standard enable / registered
		# rd-sel / rdata-mux loops, and its active-low RAW-strobe en shim lives in
		# emitEvfabInstance (no en_q register, D4). The description peripheral is named
		# EVFAB (single instance, unindexed registers like PWRCTRL/MUTEX), while the
		# RTL nets/instance carry the 0 (evfab0_*) like every other page-2 block.
		if self.eventFabric:
			self.shslv = dict(self.shslv)
			self.shslv['EVFAB'] = {'sel': 'evfab0', 'shim': None, 'rdata': 'evfab0_sh_rdata'}
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
			+ ['GPIO4', 'GPIO5'] + (['RTC0'] if self.rtc else []) \
			+ (['PWM0'] if self.pwm else []) \
			+ (['OW0'] if self.onewire else []) \
			+ (['DMA0'] if self.dma else []) \
			+ (['I2CT0'] if self.i2ctarget else []) \
			+ (['TRNG0'] if self.trng else []) \
			+ (['EVFAB'] if self.eventFabric else [])
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
		if self.pwm:
			# digperiphs #5: PWM0 = page-2 sub-slot 6 (0x6600).
			lines.append(ind + 'shslv_pwm0_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + mtxBits + '" and sh_addr(9 downto 6) = "0110" else \'0\';')
		if self.onewire:
			# digperiphs #5: OW0 = page-2 sub-slot 7 (0x6700).
			lines.append(ind + 'shslv_ow0_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + mtxBits + '" and sh_addr(9 downto 6) = "0111" else \'0\';')
		if self.dma:
			# digperiphs #6: DMA0 = page-2 sub-slot 8 (0x6800). Slave register file
			# only; the DMA's MASTER port slices into arb_*(numHarts) separately.
			lines.append(ind + 'shslv_dma0_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + mtxBits + '" and sh_addr(9 downto 6) = "1000" else \'0\';')
		if self.trng:
			# digperiphs (TRNG): TRNG0 = page-2 sub-slot 9 (0x6900).
			lines.append(ind + 'shslv_trng0_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + mtxBits + '" and sh_addr(9 downto 6) = "1001" else \'0\';')
		if self.i2ctarget:
			# digperiphs (I2CT): I2CT0 = page-2 sub-slot 10 (0x6A00).
			lines.append(ind + 'shslv_i2ct0_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + mtxBits + '" and sh_addr(9 downto 6) = "1010" else \'0\';')
		if self.eventFabric:
			# digperiphs (EVFAB): EVFAB0 = page-2 sub-slot 11 (0x6B00).
			lines.append(ind + 'shslv_evfab0_sel'.ljust(16) + ' <= shslv_perwin_sel when sh_addr(11 downto 10) = "' + mtxBits + '" and sh_addr(9 downto 6) = "1011" else \'0\';')
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
		stubs (default, VERBATIM) OR the QSPI0 controller, else nothing.

		CP2/D4: with a management hart the five generic maps are rewritten —
		AFE0-3 KEEP OWNER_HART 0..3 and GAIN `MGMT_HART => <m>`, and eis0
		becomes OWNER_HART => <m> (the orchestrator owns the EIS engine). The
		association is OMITTED entirely at management hart 0, so the default
		build is the verbatim golden-master text (STRICT byte-identity), which
		is also why afe_stub.vhd defaults MGMT_HART to 0.'''
		if self.afeStubs:
			if not self.orch:
				return list(AFE_SLOT12_INSTANCES)
			return self.afeStubsWithMgmt()
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

	def afeStubsWithMgmt(self):
		'''CP2/D4: the AFE/EIS instance block with the management-hart generic.
		DEGRADES THE VERBATIM TEXT LINE BY LINE (the G1a idiom) rather than
		re-transcribing it, so the two versions cannot drift: only the five
		`generic map (...)` lines and the two narrative comment lines that name
		hart 0 as the manager are touched.'''
		m = str(self.mgmtHart)
		out = []
		for ln in AFE_SLOT12_INSTANCES:
			s = ln.strip()
			if s.startswith('generic map (OWNER_HART =>'):
				# '        generic map (OWNER_HART => N)   -- comment'
				owner = s.split('=>')[1].split(')')[0].strip()
				isEis = 'EIS' in ln
				if isEis:
					# The EIS engine follows the MANAGER, not hart 0 (D4). BOTH
					# generics must be given: MGMT_HART's entity DEFAULT is 0, so
					# `OWNER_HART => m` alone leaves the gate at {m, 0} and hart 0
					# keeps the EIS access D4 moved to the orchestrator -- the
					# comment on this very line would then be false. Found at CP3
					# by shorch's negative control (hart 0 read a seeded EIS word
					# it must not see); the emitted text and the RTL agree only
					# when the association is explicit.
					out.append('        generic map (OWNER_HART => ' + m + ', MGMT_HART => ' + m + ')'
						+ '   -- 0x7C00: EIS engine, management hart ' + m + ' only')
				else:
					site = ln.split('--')[1].split(':')[0].strip()
					out.append('        generic map (OWNER_HART => ' + owner + ', MGMT_HART => ' + m + ')'
						+ '   -- ' + site + ': hart ' + owner + ' or hart ' + m)
				continue
			if 'each answers only for its owner hart OR hart 0' in ln:
				out.append(ln.replace('OR hart 0', 'OR the CP2 management hart ' + m))
				continue
			if 'is hart-0-only' in ln:
				out.append(ln.replace('is hart-0-only', 'is management-hart-only'))
				continue
			if ln.strip().startswith('-- (OWNER_HART=0).'):
				out.append(ln.replace('(OWNER_HART=0)', '(OWNER_HART=' + m + ')'))
				continue
			out.append(ln)
		return out

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
		lines = [
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
		# digperiphs (EVFAB): EV8/EV9 producer taps (toggle exports)
		return self.evfabInsertTaps(lines, '            irq_crcerr   => irq_nfc0_crcerr,', 'nfc0')

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
		lines = [
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
		# digperiphs (EVFAB): EV1/EV0 producer taps
		return self.evfabInsertTaps(lines, '            irq_rtc     => irq_rtc0,', 'rtc0')

	def emitPwmDecls(self):
		'''digperiphs #5: PWM0 (page-2 sub-slot 6 @0x6600) declarative region.
		Fabric nets for the hand-emitted RAW-strobe shim + the two output-alias
		scalars fed into the AF spread (P2.2/P2.3 AF2, A7); nothing when PWM is
		absent. Like RTC0 there is NO shslv_pwm0_en_q register (D4) and NO
		placeholder INPUT pins (the block is zero-input; its only external signals
		are the two outputs, aliased onto already-bonded spread pins).'''
		if not self.pwm:
			return []
		return [
			'        -- digperiphs #5: PWM0 (buffered PWM generator: 2 channels, glitch-free',
			'        -- double-buffered update, software fault trip, period-event tick). Page-2',
			'        -- (MUTEX page) sub-slot 6 @0x6600 — the mutex bank keeps sub-slot 0',
			'        -- @0x6000. Registered-read native slave with a PLAIN active-low one-cycle',
			'        -- en shim: NO falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q',
			'        -- (D4 — registers its read on rising ClkMem over data already in the bus',
			'        -- domain). The whole engine (prescaler/counter/compare/shadow-commit/sticky',
			'        -- flags/IRQ) rides the free-running MCLK (clk => mclk, D1) — no LFXT, no',
			'        -- generated/gated clocks. irq_fault -> vector 115, irq_evt -> vector 116.',
			'        -- Zero INPUT pins; pwm_out(0)/(1) alias onto the AF spread (P2.2/P2.3 AF2,',
			'        -- A7) via the pwm0_out/pwm1_out scalars below.',
			'        signal shslv_pwm0_sel, shslv_pwm0_en : std_logic;',
			"        signal shslv_rd_pwm0    : std_logic := '0';",
			'        signal pwm0_sh_rdata    : std_logic_vector(31 downto 0);',
			'        signal pwm0_sh_en_n     : std_logic;',
			'        signal pwm0_pwm_out     : std_logic_vector(1 downto 0);',
			'        -- Output-only spread aliases (A7): scalar taps the AF-spread planes wire',
			'        -- as pwm0_out/pwm1_out (SPREAD_SIG). Push-pull outputs: dir = output, no pull.',
			'        signal pwm0_out, pwm0_dir, pwm0_ren : std_logic;',
			'        signal pwm1_out, pwm1_dir, pwm1_ren : std_logic;',
		]

	def emitPwmInstance(self):
		'''digperiphs #5: PWM0 instance region (page-2 sub-slot 6 @0x6600). The
		PLAIN raw-strobe active-low en shim + the PWM entity + the two output-alias
		assignments into the AF spread; nothing when PWM is absent. No en_q process
		(D4), no placeholder input ties (zero input pins).'''
		if not self.pwm:
			return []
		lines = [
			'',
			'    -- =========================================================================',
			'    -- PWM0 (digperiphs #5): 2-channel buffered PWM generator, page-2 (MUTEX',
			'    -- page) sub-slot 6 @0x6600. The prescaler, 16-bit main counter, comparators,',
			'    -- shadow->active commit, output stage, sticky FLTF/PEVF flags and the IRQ',
			'    -- combiner all ride the free-running MCLK (clk => mclk, D1) so the counter',
			'    -- and PEVF advance autonomously while the bus is idle; the register file',
			'    -- rides ClkMem (= mclk at integration). No LFXT, no generated/gated clocks',
			'    -- (D6). Waveform writes (PER/DTY0/DTY1) are double-buffered and commit at the',
			'    -- period boundary (glitch-free, D9). The software fault (FLTTRIG + FLTEN)',
			'    -- forces both outputs safe within one clock (D12). Registered read (no',
			'    -- bridge). irq_fault -> vector 115 (lower id = router priority), irq_evt ->',
			'    -- vector 116, through the irq_router (ABOVE GPIO5\'s 106-113). Zero INPUT pins.',
			'    -- =========================================================================',
			'    -- D4: PLAIN raw active-low en strobe (the GPIO4/5 native-slave idiom) —',
			'    -- NO falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q here.',
			'    pwm0_sh_en_n <= not shslv_pwm0_en;',
			'    pwm0: entity work.PWM',
			'        port map (',
			'            clk         => mclk,',
			'            resetn      => resetn,',
			'            irq_fault   => irq_pwm0_fault,',
			'            irq_evt     => irq_pwm0_evt,',
			'            pwm_out     => pwm0_pwm_out,',
			'            ClkMem      => mclk,',
			'            EnMemPeriph => pwm0_sh_en_n,',
			'            WEn         => sh_wen_n,',
			'            MABPart     => sh_addr(5 downto 0),',
			'            wdata       => sh_wdata,',
			'            rdata_out   => pwm0_sh_rdata);',
			'    -- A7: pwm_out(0)/(1) drive the AF-spread slots P2.2/P2.3 AF2 (replacing the',
			'    -- redundant T0CMP0/T0CMP1 spread copies). Output-only push-pull: dir = output',
			'    -- (like the timer compares, cmp_dir=1), no pull resistor (ren=0).',
			'    pwm0_out <= pwm0_pwm_out(0);',
			"    pwm0_dir <= '1';",
			"    pwm0_ren <= '0';",
			'    pwm1_out <= pwm0_pwm_out(1);',
			"    pwm1_dir <= '1';",
			"    pwm1_ren <= '0';",
		]
		# digperiphs (EVFAB): EV2/EV3 producer taps + the T4 fault-trip task
		return self.evfabInsertTaps(lines, '            irq_evt     => irq_pwm0_evt,', 'pwm0')

	def emitOwDecls(self):
		'''digperiphs #5: OW0 (1-Wire master, page-2 sub-slot 7 @0x6700) declarative
		region. Fabric nets for the hand-emitted RAW-strobe shim + the whole DQ pad
		scalar group (out/dir/ren driven into the P4.7 AF2 spread slot, in tapped from
		the pad by the relocation mux). Nothing when OneWire is absent. Like RTC0/PWM0
		there is NO shslv_ow0_en_q register (D4).'''
		if not self.onewire:
			return []
		return [
			'        -- digperiphs #5: OW0 (Dallas/Maxim 1-Wire master: reset+presence,',
			'        -- write/read bit + byte primitives off a programmable time base; ROM',
			'        -- search + CRC-8 in firmware; standard + overdrive). Page-2 (MUTEX page)',
			'        -- sub-slot 7 @0x6700 — the mutex bank keeps sub-slot 0 @0x6000.',
			'        -- Registered-read native slave with a PLAIN active-low one-cycle en shim:',
			'        -- NO falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q (D4 —',
			'        -- registers its read on rising ClkMem over data already in the bus/mclk',
			'        -- family). The time base / slot FSM / DQ 2-FF synchronizer / sticky W1C',
			'        -- flags / BUSY-PRES / IRQ combiner all ride the free-running MCLK (clk =>',
			'        -- mclk, D1/D2) — no LFXT, no generated/gated clocks, and NO clock on the',
			'        -- DQ pad (DQ is PURE DATA, 2-FF synced, D10). irq_ow -> vector 117. One',
			'        -- pad: DQ on P4.7/GPIO31 AF2 open-drain (rstREN=1) — the pin-mux-v2',
			'        -- replaced-spread-slot mechanism (it takes the redundant T0CMP1 spread',
			'        -- copy): the AF2 plane drives the pad low from ow0_dq_dir (out fixed 0)',
			'        -- and the relocation mux below taps ow0_dq_in from the pad.',
			'        signal shslv_ow0_sel, shslv_ow0_en : std_logic;',
			"        signal shslv_rd_ow0     : std_logic := '0';",
			'        signal ow0_sh_rdata     : std_logic_vector(31 downto 0);',
			'        signal ow0_sh_en_n      : std_logic;',
			'        -- DQ pad scalars (open-drain, D11): ow0_dq_out is the fixed-0 open-drain',
			'        -- output, ow0_dq_dir drives DQ low ( = 1) or releases Hi-Z, ow0_dq_ren',
			'        -- carries the pad register pull preference into the AF2 plane, and',
			'        -- ow0_dq_in is the 2-FF-synchronized pad input (D10).',
			'        signal ow0_dq_out, ow0_dq_dir, ow0_dq_ren : std_logic;',
			'        signal ow0_dq_in        : std_logic;',
		]

	def emitOwInstance(self):
		'''digperiphs #5: OW0 instance region (page-2 sub-slot 7 @0x6700). The PLAIN
		raw-strobe active-low en shim + the OneWire entity; nothing when OneWire is
		absent. No en_q process (D4). The DQ pad OUTPUT group (OW_DQ_OUT/DIR + the
		ow0_dq_ren pull alias) crosses to the P4.7 AF2 SPREAD slot emitted by
		emitAfSpread(3); the pad INPUT tap (OW_DQ_IN) is the AFS-keyed relocation mux
		emitted right here — the RX0/MISO1 v2 io-slot idiom.'''
		if not self.onewire:
			return []
		return [
			'',
			'    -- =========================================================================',
			'    -- OW0 (digperiphs #5): Dallas/Maxim 1-Wire master, page-2 (MUTEX page)',
			'    -- sub-slot 7 @0x6700. The OW0DIV counter-compare time base, the slot FSM,',
			'    -- the DQ 2-FF synchronizer, the sticky W1C flags, BUSY/PRES and the IRQ',
			'    -- combiner all ride the free-running MCLK (clk => mclk, D1/D2), so the tick',
			'    -- base is immune to clock reconfig; the register file rides ClkMem (= mclk',
			'    -- at integration). No LFXT, no generated/gated clocks, and NO clock on the',
			'    -- DQ pad — OW_DQ_IN is 2-FF synchronized, PURE DATA (D10), the deliberate',
			'    -- contrast with I3C0 SDA_IN. Registered read (no bridge, no CAPTURE_CLOCK',
			'    -- pre-latch, D4). Master only; standard + overdrive; ROM search + CRC-8 in',
			'    -- firmware. irq_ow -> vector 117 (single combined TC/error) through the',
			'    -- irq_router, ABOVE GPIO5\'s 106-113. One open-drain DQ pad: P4.7/GPIO31',
			'    -- (DTP3) alt plane AF2, the pin-mux-v2 REPLACED-SPREAD-SLOT mechanism —',
			'    -- the slot\'s redundant T0CMP1 spread copy steps aside (T0CMP1 keeps its',
			'    -- P3.1 primary, its P2.1/P4.5 AF1 relocations and 26 other spread copies).',
			'    -- =========================================================================',
			'    -- D4: PLAIN raw active-low en strobe (the GPIO4/5 native-slave idiom) —',
			'    -- NO falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q here.',
			'    ow0_sh_en_n <= not shslv_ow0_en;',
			'    -- DQ pad tie-in (P4.7 AF2, io spread slot — literal index, no pnum):',
			'    -- the AF2 out/dir planes come from the GPIO3 spread block; the ren plane',
			'    -- follows the pad register\'s own pull preference (PxREN, reset bit 7 = 1),',
			'    -- and the input mux reads the pad ONLY when P4.7 selects AF2 (idle-high',
			'    -- otherwise, so an unrouted DQ never fakes a presence pulse).',
			'    ow0_dq_ren <= p4_ren(7);',
			'    ow0_dq_in  <= prt4_in(7)',
			'                  when p4_afs((3 * 7) + 2 downto 3 * 7) = "010"',
			"                  else '1';",
			'    ow0: entity work.OneWire',
			'        port map (',
			'            clk         => mclk,',
			'            resetn      => resetn,',
			'            irq_ow      => irq_ow0,',
			'            ClkMem      => mclk,',
			'            EnMemPeriph => ow0_sh_en_n,',
			'            WEn         => sh_wen_n,',
			'            MABPart     => sh_addr(5 downto 0),',
			'            wdata       => sh_wdata,',
			'            rdata_out   => ow0_sh_rdata,',
			'            OW_DQ_IN    => ow0_dq_in,    -- digperiphs #5: routed from P4.7 AF2 (GPIO3)',
			'            OW_DQ_OUT   => ow0_dq_out,',
			'            OW_DQ_DIR   => ow0_dq_dir);',
		]

	def emitDmaDecls(self):
		'''digperiphs #6: DMA0 (page-2 sub-slot 8 @0x6800) declarative region.
		Fabric nets for the hand-emitted RAW-strobe slave shim; nothing when DMA is
		absent. Like RTC0/PWM0/OW0 there is NO shslv_dma0_en_q register (D4). The DMA's
		two irq levels (irq_dma0_done / irq_dma0_err -> vectors 118/119) are auto-declared
		by emitIrqSignalDecls from the IRQB_DMA0_* vector names; the master-port nets slice
		DIRECTLY into arb_*(numHarts), so no intermediate master signals are declared.'''
		if not self.dma:
			return []
		return [
			'        -- digperiphs #6: DMA0 (configurable multi-channel single-shot DMA',
			'        -- controller: peripheral-paced or software-GO mem-to-mem transfers over',
			'        -- the shared arbiter, CRC16-CDMA2000 ride-along). Page-2 (MUTEX page)',
			'        -- sub-slot 8 @0x6800 — the mutex bank keeps sub-slot 0 @0x6000. This is',
			'        -- the SLAVE register-file fabric only: a registered-read native slave',
			'        -- with a PLAIN active-low one-cycle en shim (NO falling_edge(EnMemPeriph)',
			'        -- pre-latch and NO CAPTURE_CLOCK en_q, D4 — it registers its read on',
			'        -- rising ClkMem over data already in the mclk domain). DMA0 is ALSO the',
			'        -- FIRST new arbiter MASTER (slice numHarts of arb_*); the fabric widening',
			'        -- (arb_* 5th slice, mp_arbiter/resv_unit/mutex_bank/irq_router generics,',
			'        -- D18 lrsc/lock ties, trigger taps) lives in the arb/instance emitters.',
			'        -- irq_dma0_done -> vector 118, irq_dma0_err -> vector 119. Zero pins.',
			'        signal shslv_dma0_sel, shslv_dma0_en : std_logic;',
			"        signal shslv_rd_dma0    : std_logic := '0';",
			'        signal dma0_sh_rdata    : std_logic_vector(31 downto 0);',
			'        signal dma0_sh_en_n     : std_logic;',
		]

	def emitDmaInstance(self):
		'''digperiphs #6: DMA0 instance region (page-2 sub-slot 8 @0x6800). The PLAIN
		raw-strobe active-low slave en shim + the DMA entity (slave register port +
		MASTER port sliced into arb_*(numHarts) at depth 0 + the trigger taps + the two
		irq levels) + the D18 fabric ties. Nothing when DMA is absent. No en_q process
		(D4). The MASTER-port width widening (arb_* -> numHarts+1 slices) is in
		emitArbFabricDecls; the arbiter/resv/mutex/router generics regrow via nMasters().'''
		if not self.dma:
			return []
		n = self.nHarts()			# the DMA is master index numHarts (the LAST slice)
		ns = str(n)
		np1 = str(n + 1)
		we_hi = str(4 * n + 3)
		we_lo = str(4 * n)
		lr_hi = str(2 * n + 1)
		lr_lo = str(2 * n)
		# A8/A9: tap the EXISTING IE-gated irq_* LEVELS (not raw flags — none is a port);
		# QSPI0/NFC0 are knob-gated fabric citizens, so their taps are conditional.
		qspiTap = 'irq_qspi0_rxf' if self.qspi else "'0'"
		nfcTap = 'irq_nfc0_rxf' if self.nfc else "'0'"
		lines = [
			'',
			'    -- =========================================================================',
			'    -- DMA0 (digperiphs #6): configurable multi-channel single-shot DMA',
			'    -- controller, page-2 (MUTEX page) sub-slot 8 @0x6800. TWO peripherals fused:',
			'    -- an arbiter SLAVE (the register file @0x6800, on ClkMem) AND an arbiter',
			'    -- MASTER (the transfer engine, on the free-running clk => mclk, D1) — the',
			'    -- FIRST new arbiter master since the four harts (M13). The master port',
			'    -- speaks the VERBATIM WAIT-FOR-RELEASE handshake (D2/D3) at boundary depth 0',
			'    -- (the DMA lives inside MCU fabric on mclk like mp_arbiter itself, NOT behind',
			'    -- a tile boundary), slicing DIRECTLY into arb_*(' + ns + ') — the ' + np1 + 'th master. Single-txn',
			'    -- words, no grant-holding: lock is tied \'0\' forever and lrsc "00" (D18), so',
			'    -- the LOCKED path is unreachable for the DMA. The whole engine (master FSM,',
			'    -- SRC/DST/LEN counters, RR+priority picker, CRC16 datapath, pacing edge',
			'    -- detectors, sticky W1C flags, IRQ combiners) rides mclk; the register file',
			'    -- rides ClkMem (= mclk at integration). Registered read (no bridge, no',
			'    -- CAPTURE_CLOCK pre-latch, D4). The three trigger inputs are the ONLY true CDC',
			'    -- (2-FF synced, D9); they tap the IE-gated irq_* LEVELS (A8): UART0 RC always,',
			'    -- QSPI0/NFC0 RX-full only when those knob-gated blocks are present (A9, else',
			'    -- \'0\'). irq_done -> vector 118, irq_err -> vector 119 (irq_router). Zero pins.',
			'    -- =========================================================================',
			'    -- D4: PLAIN raw active-low slave en strobe (the GPIO4/5 native-slave idiom) —',
			'    -- NO falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q here.',
			'    dma0_sh_en_n <= not shslv_dma0_en;',
			'    dma0: entity work.DMA',
			'        generic map (NCH => ' + str(self.dmaChannels) + ', AW => SH_AW)',
			'        port map (',
			'            clk         => mclk,',
			'            resetn      => resetn,',
			'            -- slave register-file port (page-2 sub-slot 8 @0x6800)',
			'            ClkMem      => mclk,',
			'            EnMemPeriph => dma0_sh_en_n,',
			'            WEn         => sh_wen_n,',
			'            MABPart     => sh_addr(5 downto 0),',
			'            wdata       => sh_wdata,',
			'            rdata_out   => dma0_sh_rdata,',
			'            -- arbiter MASTER port: slice ' + ns + ' of arb_* (depth 0, D2/D3)',
			'            m_req       => arb_req(' + ns + '),',
			'            m_we        => arb_we(' + we_hi + ' downto ' + we_lo + '),',
			'            m_addr      => arb_addr(' + np1 + '*SH_AW-1 downto ' + ns + '*SH_AW),',
			'            m_wdata     => arb_wdata(' + np1 + '*32-1 downto ' + ns + '*32),',
			'            m_gnt       => arb_gnt(' + ns + '),',
			'            m_done      => arb_done(' + ns + '),',
			'            m_rdata     => arb_rdata,',
			'            -- pacing triggers: the IE-gated irq_* levels (A8/A9)',
			'            trig_uart0_rc  => irq_uart0_rc,',
			'            trig_qspi0_rxf => ' + qspiTap + ',',
			'            trig_nfc0_rxf  => ' + nfcTap + ',',
			'            irq_done    => irq_dma0_done,',
			'            irq_err     => irq_dma0_err);',
			'    -- D18: the DMA never does LR/SC and never grant-locks, so lrsc/lock are',
			'    -- tied here in fabric (not DMA ports); arb_scfail(' + ns + ')/arb_resvvld(' + ns + ') from the',
			'    -- arbiter/resv_unit are left ignored (the DMA never issues an SC). resv_unit',
			'    -- N=nMasters still keys cur=' + ns + ' on a DMA plain write, killing matching',
			'    -- reservations (cross-hart LR/SC stays sound across a DMA write).',
			'    arb_lrsc(' + lr_hi + ' downto ' + lr_lo + ') <= "00";',
			"    arb_lock(" + ns + ") <= '0';",
		]
		# digperiphs (EVFAB): the T0/T1 GO tasks + the EV10-EV12 event pulses + ch_busy
		return self.evfabInsertTaps(lines, '            m_rdata     => arb_rdata,', 'dma0')

	def emitI2ctDecls(self):
		'''digperiphs (I2CT): I2CT0 (hardware-autonomous I2C target, page-2 sub-slot 10
		@0x6A00) declarative region. Fabric nets for the hand-emitted RAW-strobe shim +
		the NEW open-drain DIR scalars driven from the instance's SDA_DIR/SCL_DIR. Nothing
		when I2CT0 is absent. Like RTC0/PWM0/OW0 there is NO shslv_i2ct0_en_q register (D4).
		The two irq levels (irq_i2ct0_ae / irq_i2ct0_data -> vectors 122/123) are
		auto-declared by emitIrqSignalDecls from the IRQB_I2CT0_* vector names. NO input
		signal is declared: SDA_IN/SCL_IN fan out from the EXISTING sda0_in/scl0_in.'''
		if not self.i2ctarget:
			return []
		return [
			'        -- digperiphs (I2CT): I2CT0 (hardware-autonomous I2C TARGET: 7-bit',
			'        -- address match + mask + general call, byte-at-a-time RX/TX with',
			'        -- ready/empty status, hardware clock stretching, START/STOP/repeated-',
			'        -- START/NACK framing flags, stuck-SCL watchdog). Page-2 (MUTEX page)',
			'        -- sub-slot 10 @0x6A00 — the mutex bank keeps sub-slot 0 @0x6000.',
			'        -- Registered-read native slave with a PLAIN active-low one-cycle en shim:',
			'        -- NO falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q (D4 —',
			'        -- registers its read on rising ClkMem over data already in the bus/mclk',
			'        -- family). The whole target FSM / SDA-SCL 2-FF synchronizers / edge +',
			'        -- framing detectors / sticky W1C flags / BUSY-TM / watchdog / IRQ combiners',
			'        -- all ride the free-running MCLK (clk => mclk, D1/D2) — no LFXT, no',
			'        -- generated/gated clocks, and NO clock on the SDA/SCL pads (they are PURE',
			'        -- DATA, 2-FF synced, D6). irq_i2ct0_ae -> vector 122, irq_i2ct0_data ->',
			"        -- vector 123. NO new pins: I2CT0 shares I2C0's SDA0/SCL0 pad planes —",
			'        -- SDA_IN/SCL_IN fan out from the existing sda0_in/scl0_in inputs.',
			'        signal shslv_i2ct0_sel, shslv_i2ct0_en : std_logic;',
			"        signal shslv_rd_i2ct0   : std_logic := '0';",
			'        signal i2ct0_sh_rdata   : std_logic_vector(31 downto 0);',
			'        signal i2ct0_sh_en_n    : std_logic;',
			"        -- SDA/SCL open-drain DIR scalars (D19): driven by the I2CT0 instance's",
			"        -- SDA_DIR/SCL_DIR ('1' drives the line low, '0' releases Hi-Z). The",
			'        -- *_mrg scalars are the D19 wired-AND merge consumed by the sda0/scl0',
			'        -- DIR plane aggregates (all three locations: GPIO3 home + GPIO1/GPIO2',
			"        -- relocations): either engine's drive-low wins — I2C0 (master) or I2CT0",
			'        -- (target ACK/data on SDA, clock stretch on SCL). OUT planes stay tied',
			"        -- '0' (open-drain); REN/pull policy stays I2C0's.",
			'        signal i2ct0_sda_dir, i2ct0_scl_dir : std_logic;',
			'        signal sda0_dir_mrg,  scl0_dir_mrg  : std_logic;',
		]

	def emitI2ctInstance(self):
		'''digperiphs (I2CT): I2CT0 instance region (page-2 sub-slot 10 @0x6A00). The PLAIN
		raw-strobe active-low en shim + the I2CTarget entity; nothing when I2CT0 is absent.
		No en_q process (D4). SDA_IN/SCL_IN fan out from the existing sda0_in/scl0_in (pure
		fanout); SDA_DIR/SCL_DIR drive the new i2ct0_sda_dir/i2ct0_scl_dir scalars (the
		wired-AND DIR merge into the sda0/scl0 planes is a separate shared-RTL edit).'''
		if not self.i2ctarget:
			return []
		lines = [
			'',
			'    -- =========================================================================',
			'    -- I2CT0 (digperiphs I2CT): hardware-autonomous I2C TARGET (slave), page-2',
			'    -- (MUTEX page) sub-slot 10 @0x6A00. The whole target FSM, the SDA/SCL 2-FF',
			'    -- synchronizers, the edge/framing detectors, the address matcher, the RX/TX',
			'    -- byte paths, the clock-stretch driver, the sticky W1C flags, BUSY/TM, the',
			'    -- stuck-SCL watchdog and the two IRQ combiners all ride the free-running MCLK',
			'    -- (clk => mclk, D1/D2), so the block is immune to clock reconfig; the register',
			'    -- file rides ClkMem (= mclk at integration). No LFXT, no generated/gated',
			'    -- clocks, and NO clock on the SDA/SCL pads — SDA_IN/SCL_IN are 2-FF',
			"    -- synchronized, PURE DATA (D6), the deliberate contrast with I2C0's",
			'    -- SCL-pad-clocked slave FSM. Registered read (no bridge, no CAPTURE_CLOCK',
			'    -- pre-latch, D4). irq_i2ct0_ae -> vector 122 (address/error), irq_i2ct0_data',
			'    -- -> vector 123 (tx-ready/rx-full) through the irq_router. NO new pins: I2CT0',
			"    -- shares I2C0's open-drain SDA0/SCL0 pad planes — SDA_IN/SCL_IN fan out from",
			'    -- the existing sda0_in/scl0_in, and SDA_DIR/SCL_DIR drive i2ct0_sda_dir/',
			'    -- i2ct0_scl_dir (the wired-AND merge into the sda0/scl0 DIR planes is a',
			'    -- separate shared-RTL edit; those scalars are unused here at this stage).',
			'    -- =========================================================================',
			'    -- D4: PLAIN raw active-low en strobe (the GPIO4/5 native-slave idiom) —',
			'    -- NO falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q here.',
			'    i2ct0_sh_en_n <= not shslv_i2ct0_en;',
			'    i2ct0: entity work.I2CTarget',
			'        port map (',
			'            clk         => mclk,',
			'            resetn      => resetn,',
			'            irq_ae      => irq_i2ct0_ae,',
			'            irq_data    => irq_i2ct0_data,',
			'            ClkMem      => mclk,',
			'            EnMemPeriph => i2ct0_sh_en_n,',
			'            WEn         => sh_wen_n,',
			'            MABPart     => sh_addr(5 downto 0),',
			'            wdata       => sh_wdata,',
			'            rdata_out   => i2ct0_sh_rdata,',
			'            SDA_IN      => sda0_in,     -- digperiphs I2CT: shared with I2C0 (pure fanout)',
			'            SDA_DIR     => i2ct0_sda_dir,',
			'            SCL_IN      => scl0_in,     -- digperiphs I2CT: shared with I2C0 (pure fanout)',
			'            SCL_DIR     => i2ct0_scl_dir);',
			'',
			'    -- D19 shared-pad wired-AND (the one I2CT shared-RTL edit): the sda0/scl0',
			'    -- DIR planes (GPIO3 home + GPIO1/GPIO2 relocations) bind these merges, so',
			"    -- the pad drives low when EITHER engine drives — I2C0's master engine or",
			"    -- I2CT0's target engine (ACK/data on SDA, clock stretch on SCL). This is",
			'    -- what makes the wi2ct I2C0-as-host loopback on the SAME pads legal.',
			'    sda0_dir_mrg <= sda0_dir or i2ct0_sda_dir;',
			'    scl0_dir_mrg <= scl0_dir or i2ct0_scl_dir;',
		]
		# digperiphs (EVFAB): EV14 producer tap
		return self.evfabInsertTaps(lines, '            irq_data    => irq_i2ct0_data,', 'i2ct0')

	def emitTrngDecls(self):
		'''digperiphs (TRNG): TRNG0 (ring-oscillator entropy source + harvest engine,
		page-2 sub-slot 9 @0x6900) declarative region. Fabric nets for the hand-emitted
		RAW-strobe shim + the four entropy-source fan-out scalars that wire trng0 to its
		sibling u_ro TrngRoEnsemble instance (D6). Nothing when TRNG is absent. Like
		RTC0/PWM0/OW0/DMA0/I2CT0 there is NO shslv_trng0_en_q register (D4). NO pad
		signals: the RO ensemble is internal fabric, not a pin group.'''
		if not self.trng:
			return []
		return [
			'        -- digperiphs (TRNG): TRNG0 (ring-oscillator entropy source + harvest',
			'        -- engine: NRO free-running rings 2-FF synchronized into MCLK, decimated',
			'        -- and direct-packed into 32-bit words behind a read-CONSUMES data',
			'        -- register, with a repetition-count health test that auto-halts',
			'        -- harvesting on alarm). Page-2 (MUTEX page) sub-slot 9 @0x6900 — the',
			'        -- mutex bank keeps sub-slot 0 @0x6000. Registered-read native slave with',
			'        -- a PLAIN active-low one-cycle en shim: NO falling_edge(EnMemPeriph)',
			'        -- pre-latch and NO CAPTURE_CLOCK en_q (D4 — registers its read on rising',
			'        -- ClkMem over data already in the bus/mclk family). The RO 2-FF sync,',
			'        -- decimator, 32-bit assembler, repetition-count health test, sticky ALMF',
			'        -- and the IRQ combiner all ride the free-running MCLK (clk => mclk,',
			'        -- D1/D2) — no LFXT, no generated/gated clocks. irq_trng -> vector 121.',
			'        -- ZERO pins: the entropy source is the SIBLING u_ro TrngRoEnsemble',
			'        -- instance (D6), wired through the four ro_* fan-out scalars below —',
			'        -- never a pad group.',
			'        signal shslv_trng0_sel, shslv_trng0_en : std_logic;',
			"        signal shslv_rd_trng0   : std_logic := '0';",
			'        signal trng0_sh_rdata   : std_logic_vector(31 downto 0);',
			'        signal trng0_sh_en_n    : std_logic;',
			'        -- Entropy-source fan-out to u_ro (D6): ro_enable/ro_sel/ro_sclk are',
			'        -- trng0 OUTPUTS (ro_sclk = mclk, for the sim arch only); ro_raw is the',
			'        -- XOR-ensembled jitter bit u_ro drives back INTO trng0 (2-FF',
			'        -- synchronized inside TRNG before any use, D7 — never a clock).',
			'        signal trng0_ro_enable  : std_logic;',
			'        signal trng0_ro_sel     : std_logic_vector(3 downto 0);',
			'        signal trng0_ro_sclk    : std_logic;',
			'        signal trng0_ro_raw     : std_logic;',
		]

	def emitTrngInstance(self):
		'''digperiphs (TRNG): TRNG0 instance region (page-2 sub-slot 9 @0x6900). The
		PLAIN raw-strobe active-low en shim + the TRNG entity + the sibling u_ro
		TrngRoEnsemble instance (D6), wired through the four ro_* fan-out scalars.
		Nothing when TRNG is absent. No en_q process (D4), no pad ties (zero pins).
		Both trng0 and u_ro take the SHARED NRO generic (trngRings, {4,8}) — the
		register map is NRO-invariant.'''
		if not self.trng:
			return []
		nro = str(self.trngRings)
		lines = [
			'',
			'    -- =========================================================================',
			'    -- TRNG0 (digperiphs TRNG): ring-oscillator entropy source + harvest engine,',
			'    -- page-2 (MUTEX page) sub-slot 9 @0x6900. The RO 2-FF synchronizer, the',
			'    -- decimator, the 32-bit direct-pack assembler, the repetition-count health',
			'    -- test, the sticky ALMF flag and the IRQ combiner all ride the free-running',
			'    -- MCLK (clk => mclk, D1/D2), so the harvest engine is immune to clock',
			'    -- reconfig; the register file rides ClkMem (= mclk at integration). No LFXT,',
			'    -- no generated/gated clocks. Registered read (no bridge, no CAPTURE_CLOCK',
			'    -- pre-latch, D4); TRNG0DR is the ONE read-side-effect exception in this',
			'    -- library (read-CONSUMES, D9). irq_trng -> vector 121 (combined data-ready |',
			'    -- health-alarm) through the irq_router. ZERO pins: the entropy source is the',
			'    -- sibling u_ro TrngRoEnsemble instance (D6) — an internal fabric-only',
			'    -- instance, never wired to a pad. Both instances share the NRO generic',
			'    -- (trngRings = ' + nro + ').',
			'    -- =========================================================================',
			'    -- D4: PLAIN raw active-low en strobe (the GPIO4/5 native-slave idiom) —',
			'    -- NO falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q here.',
			'    trng0_sh_en_n <= not shslv_trng0_en;',
			'    trng0: entity work.TRNG',
			'        generic map (NRO => ' + nro + ')',
			'        port map (',
			'            clk         => mclk,',
			'            resetn      => resetn,',
			'            irq_trng    => irq_trng0,',
			'            ClkMem      => mclk,',
			'            EnMemPeriph => trng0_sh_en_n,',
			'            WEn         => sh_wen_n,',
			'            MABPart     => sh_addr(5 downto 0),',
			'            wdata       => sh_wdata,',
			'            rdata_out   => trng0_sh_rdata,',
			'            ro_enable   => trng0_ro_enable,',
			'            ro_sel      => trng0_ro_sel,',
			'            ro_sclk     => trng0_ro_sclk,',
			'            ro_raw      => trng0_ro_raw);',
			'    -- D6: the sibling entropy-source instance — the SAME entity as trng0\'s',
			'    -- expectation, bound to the sim (behavioral) or rtl (genus/gate) architecture',
			'    -- by cell-list discipline (the two architectures\' files must never co-list).',
			'    u_ro: entity work.TrngRoEnsemble',
			'        generic map (NRO => ' + nro + ')',
			'        port map (',
			'            enable      => trng0_ro_enable,',
			'            sel         => trng0_ro_sel,',
			'            sclk        => trng0_ro_sclk,',
			'            ro_raw      => trng0_ro_raw);',
		]
		# digperiphs (EVFAB): EV13 producer tap (the true data-ready level)
		return self.evfabInsertTaps(lines, '            irq_trng    => irq_trng0,', 'trng0')

	# ------------------------------------------------------------------
	# digperiphs (EVFAB): the event/trigger fabric — page-2 sub-slot 11
	# @0x6B00 — plus the whole producer/consumer crossbar wiring. The
	# EVSEL/TASKSEL id tables below are the FROZEN ABI of
	# ~/vesta_docs/digperiphs/event_fabric_spec.md §2/§3: (id, net, source
	# block flag attribute, human note). A row whose block is absent from
	# the configuration TIES '0' (design-doc D23) — never left open.
	# ------------------------------------------------------------------
	EVFAB_GPIO_EV = 15		# EVFAB EV_GPIO_IDX generic: the event served by the GPIO0 front end

	def evfabEvRows(self):
		'''The 16 ev_in rows: (EVSEL id, tap net or None, present?, note).
		None net at EVFAB_GPIO_EV = generated INSIDE the fabric from gpio0_evin.'''
		return [
			(0,  'evfab0_rtc0_tick',    self.rtc,      'RTC0 tick (P)'),
			(1,  'evfab0_rtc0_alarm',   self.rtc,      'RTC0 alarm (P)'),
			(2,  'evfab0_pwm0_period',  self.pwm,      'PWM0 period boundary (P)'),
			(3,  'evfab0_pwm0_fault',   self.pwm,      'PWM0 fault trip (P)'),
			(4,  'evfab0_tim0_cmp0',    True,          'TIMER0 compare0 (T, timer_clock)'),
			(5,  'evfab0_tim0_ovf',     True,          'TIMER0 overflow (T, timer_clock)'),
			(6,  'evfab0_tim1_cmp0',    self.timer1,   'TIMER1 compare0 (T, timer_clock)'),
			(7,  'evfab0_uart0_rx',     True,          'UART0 rx-done (P)'),
			(8,  'evfab0_nfc0_field',   self.nfc,      'NFC0 field detect (T, smclk)'),
			(9,  'evfab0_nfc0_rxframe', self.nfc,      'NFC0 rx frame (T, smclk)'),
			(10, 'evfab0_dma0_evt_done(0)', self.dma,  'DMA0 ch0 done (P)'),
			(11, 'evfab0_dma0_evt_done(1)', self.dma,  'DMA0 ch1 done (P)'),
			(12, 'evfab0_dma0_evt_err', self.dma,      'DMA0 error, combined (P)'),
			(13, 'evfab0_trng0_drdy',   self.trng,     'TRNG0 data ready (L)'),
			(14, 'evfab0_i2ct0_amf',    self.i2ctarget, 'I2CT0 address match (P)'),
			(15, None,                  True,          'GPIO0 masked edge (served INSIDE the fabric from gpio0_evin)'),
		]

	def emitEvfabDecls(self):
		'''digperiphs (EVFAB): EVFAB0 (event/trigger fabric, page-2 sub-slot 11
		@0x6B00) declarative region. The native-slave fabric nets for the hand-emitted
		RAW-strobe shim + the crossbar wiring vectors + one named tap net per PRESENT
		producer. Nothing when the fabric is absent. Like RTC0/PWM0/OW0/DMA0/TRNG0/I2CT0
		there is NO shslv_evfab0_en_q register (D4), and unlike all of them there is no
		irq net at all (VECTORLESS v1, D20).'''
		if not self.eventFabric:
			return []
		lines = [
			'        -- digperiphs (EVFAB): EVFAB0 (event/trigger fabric, PPI-style crossbar:',
			'        -- 8 channels routing 16 hardware EVENTS to 10 hardware TASKS as REGISTERED',
			'        -- one-mclk pulses, 1 mclk of in-fabric latency). Page-2 (MUTEX page)',
			'        -- sub-slot 11 @0x6B00 ' + EMDASH + ' the mutex bank keeps sub-slot 0 @0x6000.',
			'        -- Registered-read native slave with a PLAIN active-low one-cycle en shim:',
			'        -- NO falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q (D4).',
			'        -- The WHOLE fabric ' + EMDASH + ' event front-end, GPIO0 edge path, crossbar, output',
			'        -- register, sticky flags and the D3 action path ' + EMDASH + ' rides the FREE-RUNNING',
			'        -- mclk in the always-on domain (D1/D2): WFI keeps it alive, DP-S3',
			'        -- field-power only slows it, PWRCTRL never gates it, so chains keep firing',
			'        -- with every hart asleep. VECTORLESS v1 (D20): irq_evfab is a constant \'0\'',
			'        -- inside the block and is left OPEN here ' + EMDASH + ' no irq net, no vector spent.',
			'        signal shslv_evfab0_sel, shslv_evfab0_en : std_logic;',
			"        signal shslv_rd_evfab0  : std_logic := '0';",
			'        signal evfab0_sh_rdata  : std_logic_vector(31 downto 0);',
			'        signal evfab0_sh_en_n   : std_logic;',
			'        -- Crossbar wiring. ev_in index = the FROZEN EVSEL id, task index = the',
			'        -- FROZEN TASKSEL id (event_fabric_spec.md §2/§3 ' + EMDASH + ' ABI, never renumbered).',
			'        -- Every bit whose producer/consumer block is absent from this',
			"        -- configuration is tied '0' in the instance region below (D23), never left",
			'        -- open; the per-tap nets exist only when their block does.',
			'        signal evfab0_ev_in     : std_logic_vector(15 downto 0);',
			'        signal evfab0_gpio0_evin : std_logic_vector(7 downto 0);',
			'        signal evfab0_task_busy : std_logic_vector(9 downto 0);',
			'        signal evfab0_task_pulse : std_logic_vector(9 downto 0);',
		]
		# producer tap nets, in EVSEL order, only for present blocks (the DMA's are
		# vectors: the block exports 4-wide evt_done/ch_busy and takes a 4-wide task_go)
		if self.rtc:
			lines.append('        signal evfab0_rtc0_tick, evfab0_rtc0_alarm : std_logic;      -- EV0/EV1')
		if self.pwm:
			lines.append('        signal evfab0_pwm0_period, evfab0_pwm0_fault : std_logic;    -- EV2/EV3')
		lines.append('        signal evfab0_tim0_cmp0, evfab0_tim0_ovf : std_logic;        -- EV4/EV5 (toggles)')
		if self.timer1:
			lines.append('        signal evfab0_tim1_cmp0 : std_logic;                         -- EV6 (toggle)')
		lines.append('        signal evfab0_uart0_rx  : std_logic;                         -- EV7')
		if self.nfc:
			lines.append('        signal evfab0_nfc0_field, evfab0_nfc0_rxframe : std_logic;   -- EV8/EV9 (toggles)')
		if self.dma:
			lines.append('        signal evfab0_dma0_evt_done : std_logic_vector(3 downto 0);  -- EV10/EV11 = bits 0/1')
			lines.append('        signal evfab0_dma0_evt_err  : std_logic;                     -- EV12')
			lines.append('        signal evfab0_dma0_ch_busy  : std_logic_vector(3 downto 0);  -- task_busy(0)/(1)')
			lines.append('        signal evfab0_dma0_task_go  : std_logic_vector(3 downto 0);  -- T0/T1 = bits 0/1')
		if self.trng:
			lines.append('        signal evfab0_trng0_drdy : std_logic;                        -- EV13 (level)')
		if self.i2ctarget:
			lines.append('        signal evfab0_i2ct0_amf : std_logic;                         -- EV14')
		return lines

	def emitEvfabInstance(self):
		'''digperiphs (EVFAB): EVFAB0 instance region (page-2 sub-slot 11 @0x6B00). The
		PLAIN raw-strobe active-low en shim, the D23 crossbar wiring ledger (ev_in /
		gpio0_evin / task_busy in, task_pulse out, every absent source tied \'0\') and the
		EVFAB entity. Nothing when the fabric is absent. No en_q process (D4), no pad
		ties (zero pins), no generic map: N_CH=8 / N_EV=16 / N_TASK=10 / EV_GPIO_IDX=15 /
		EV_MODE_TGL=X"00000370" / EV_MODE_LVL=X"00002000" / VER=1 are the ENTITY DEFAULTS
		and this integration wires exactly that shape (the house rule: emit a generic only
		when it differs from the RTL default).'''
		if not self.eventFabric:
			return []
		lines = [
			'',
			'    -- =========================================================================',
			'    -- EVFAB0 (digperiphs EVFAB): event/trigger fabric, page-2 (MUTEX page)',
			'    -- sub-slot 11 @0x6B00. A PPI-style crossbar: 8 channels, each {EVSEL,',
			'    -- TASKSEL}, turn one of 16 hardware EVENTS into a registered one-mclk pulse',
			'    -- on one of 10 hardware TASKS ' + EMDASH + ' peripheral-to-peripheral command paths that',
			'    -- run with every hart in WFI. The fabric is NEVER a bus master, never',
			'    -- stalls and never rate-limits; it rides the free-running mclk in the',
			'    -- always-on domain (D1/D2) and owns ALL the CDC for its taps (per-input',
			'    -- pulse/toggle/level modes carried by the EV_MODE_* generic masks, D7/D9).',
			'    -- Registered read (no bridge, no CAPTURE_CLOCK pre-latch, D4). VECTORLESS',
			'    -- v1 (D20): irq_evfab is constant \'0\' in the block and is left open here.',
			'    -- =========================================================================',
			'    -- D4: PLAIN raw active-low en strobe (the GPIO4/5 native-slave idiom) ' + EMDASH,
			'    -- NO falling_edge(EnMemPeriph) pre-latch and NO CAPTURE_CLOCK en_q here.',
			'    evfab0_sh_en_n <= not shslv_evfab0_en;',
			'    -- D23 TIE-OFF LEDGER (ev_in): index = the frozen EVSEL id',
			'    -- (event_fabric_spec.md §2). Producers this configuration does not build',
			"    -- are tied '0' here, never left open.",
		]
		for (evId, net, present, note) in self.evfabEvRows():
			idx = 'evfab0_ev_in(' + str(evId) + ')'
			if evId == self.EVFAB_GPIO_EV:
				src = "'0'"
			elif present:
				src = net
			else:
				src = "'0'"
				note = note + ' ' + EMDASH + ' block absent'
			lines.append('    ' + idx.ljust(21) + '<= ' + (src + ';').ljust(28)
				+ '-- EV' + str(evId) + ' ' + note)
		lines.append('    -- GPIO0 masked-edge path: the RAW pre-mask edge-select vector (prt1_in xor')
		lines.append('    -- P1IES, GPIO.vhd) ' + EMDASH + ' PxIE is NEVER consulted. The fabric does the per-bit')
		lines.append('    -- 2-FF sync + rising edge + EVGPIOMASK AND-before-OR (D10; the AND is what')
		lines.append('    -- absorbs an X from an unbonded pad) and serves the result as EV15.')
		lines.append('    -- (gpio0_evin is driven by the gpio0 instance below.)')
		lines.append('    -- D23 TIE-OFF LEDGER (task_busy): index = the frozen TASKSEL id')
		lines.append('    -- (event_fabric_spec.md §3). A busy level only feeds OVR ' + EMDASH + ' it can never')
		lines.append('    -- gate, delay or suppress a task pulse (D15).')
		if self.dma:
			lines.append('    evfab0_task_busy(0)  <= evfab0_dma0_ch_busy(0);   -- T0 DMA0 ch0 GO')
			lines.append('    evfab0_task_busy(1)  <= evfab0_dma0_ch_busy(1);   -- T1 DMA0 ch1 GO')
		else:
			lines.append("    evfab0_task_busy(0)  <= '0';                      -- T0 DMA0 ch0 GO " + EMDASH + ' block absent')
			lines.append("    evfab0_task_busy(1)  <= '0';                      -- T1 DMA0 ch1 GO " + EMDASH + ' block absent')
		lines.append("    evfab0_task_busy(5 downto 2) <= (others => '0');  -- T2/T3 TIMER0, T4 PWM0, T5 PWRCTRL:")
		lines.append('                                                     -- no busy line exists (idempotent tasks)')
		if self.npu:
			lines.append('    evfab0_task_busy(6)  <= npu0_active;              -- T6 NPU0 THINK (the EXISTING NpuActive)')
		else:
			lines.append("    evfab0_task_busy(6)  <= '0';                      -- T6 NPU0 THINK " + EMDASH + ' block absent')
		lines.append("    evfab0_task_busy(9 downto 7) <= (others => '0');  -- T7/T8 GPIO0 set/clr (idempotent),")
		lines.append('                                                     -- T9 reserved (unconnected)')
		if self.dma:
			lines.append('    -- T0/T1 fan-out: the DMA takes a 4-wide task_go; only channels 0/1 are')
			lines.append("    -- fabric-driven, channels 2/3 are tied '0' (reserved TASKSEL codes, D23).")
			lines.append('    evfab0_dma0_task_go <= "00" & evfab0_task_pulse(1 downto 0);')
		lines += [
			'    evfab0: entity work.EVFAB',
			'        port map (',
			'            clk         => mclk,',
			'            resetn      => resetn,',
			'            irq_evfab   => open,',
			'            ClkMem      => mclk,',
			'            EnMemPeriph => evfab0_sh_en_n,',
			'            WEn         => sh_wen_n,',
			'            MABPart     => sh_addr(5 downto 0),',
			'            wdata       => sh_wdata,',
			'            rdata_out   => evfab0_sh_rdata,',
			'            ev_in       => evfab0_ev_in,',
			'            gpio0_evin  => evfab0_gpio0_evin,',
			'            task_busy   => evfab0_task_busy,',
			'            task_pulse  => evfab0_task_pulse);',
		]
		return lines

	# The producer/consumer TAP port-map lines, keyed by instance. Emitted into the
	# --@GEN:evfab-taps:<inst>@ markers (fixed template + side templates) and inline
	# by the generated instance emitters. Every one of these formals has a VHDL
	# default (in) or is an out port that may stay unassociated, so a cut WITHOUT the
	# fabric simply omits the lines and stays byte-identical.
	def emitEvfabTaps(self, instKey):
		if not self.eventFabric:
			return []
		taps = {
			# fixed-template instances
			'gpio0': [
				'            -- EVFAB taps: the pre-mask pad-edge export (EV15 front-end) and the',
				'            -- two output tasks, acting on the pins selected by P1TASK (T7/T8).',
				'            evt_edge_raw    => evfab0_gpio0_evin,',
				'            task_outset     => evfab0_task_pulse(7),',
				'            task_outclr     => evfab0_task_pulse(8),',
			],
			'uart0': [
				'            -- EVFAB tap: the RCIF SET condition, pre-mask (EV7)',
				'            evt_rx       => evfab0_uart0_rx,',
			],
			'timer0': [
				'            -- EVFAB taps: producer toggles EV4/EV5 (timer_clock domain, the',
				'            -- fabric does the 2-FF + XOR) and the START/STOP tasks (T2/T3).',
				'            evt_compare0 => evfab0_tim0_cmp0,',
				'            evt_overflow => evfab0_tim0_ovf,',
				'            task_start   => evfab0_task_pulse(2),',
				'            task_stop    => evfab0_task_pulse(3),',
			],
			# side-template instances
			'timer1': [
				'            -- EVFAB tap: TIMER1 contributes EV6 only (compare0); its overflow',
				'            -- toggle is a reserved event in v1 and stays unconnected.',
				'            evt_compare0 => evfab0_tim1_cmp0,',
			],
			'npu0': [
				'            -- EVFAB task (T6): one-mclk THINK launch, ORed with the NPUCR bit-16',
				'            -- write path. The fabric\'s task_busy(6) tap is NpuActive above.',
				'            task_think      => evfab0_task_pulse(6),',
			],
			# instances emitted by this module (inserted through evfabInsertTaps)
			'rtc0': [
				'            -- EVFAB taps: the synchronized alarm/tick event edges (EV1/EV0),',
				'            -- taken from the flags\' SET conditions, pre-IE.',
				'            evt_alarm   => evfab0_rtc0_alarm,',
				'            evt_tick    => evfab0_rtc0_tick,',
			],
			'pwm0': [
				'            -- EVFAB taps: period boundary + fault SET condition (EV2/EV3), and',
				'            -- the fault-trip task (T4, still FLTEN-gated inside the block).',
				'            evt_period  => evfab0_pwm0_period,',
				'            evt_fault   => evfab0_pwm0_fault,',
				'            task_flttrig => evfab0_task_pulse(4),',
			],
			'nfc0': [
				'            -- EVFAB taps: field-detect / rx-frame TOGGLES (EV8/EV9). NFC0 runs on',
				'            -- smclk, so these are toggle exports and the fabric owns the CDC.',
				'            evt_field    => evfab0_nfc0_field,',
				'            evt_rxframe  => evfab0_nfc0_rxframe,',
			],
			'dma0': [
				'            -- EVFAB taps: the channel GO tasks (T0/T1 in bits 0/1, channels 2/3',
				'            -- tied \'0\'), the done/err event pulses (EV10/EV11/EV12) and the',
				'            -- per-channel busy levels the fabric samples for OVR.',
				'            task_go     => evfab0_dma0_task_go,',
				'            evt_done    => evfab0_dma0_evt_done,',
				'            evt_err     => evfab0_dma0_evt_err,',
				'            ch_busy     => evfab0_dma0_ch_busy,',
			],
			'trng0': [
				'            -- EVFAB tap: the true data-ready LEVEL (EV13, L-mode input)',
				'            evt_drdy    => evfab0_trng0_drdy,',
			],
			'i2ct0': [
				'            -- EVFAB tap: the address-match SET condition (EV14)',
				'            evt_amf     => evfab0_i2ct0_amf,',
			],
			'pwr0': [
				'            -- EVFAB task (T5): one-mclk tile-wake pulse. Policy stays in PWRCTRL',
				'            -- (the pulse clears gate_req under PWRWAKE\'s mask); the boot-gate',
				'            -- release is deliberately NOT a task.',
				'            task_wake    => evfab0_task_pulse(5),',
			],
		}
		if instKey not in taps:
			raise Exception('MCU.vhd emitter: no EVFAB tap group for instance "' + instKey + '"')
		return taps[instKey]

	def emitEvfabCompPorts(self, comp):
		'''The matching tap PORT DECLARATIONS for the three COMPONENT declarations the
		fixed template still uses (gpio0/uart0/timer0/timer1 are component instances,
		not `entity work.X` ones, so their component decl must grow the same ports or
		the association is an unknown formal). Every added line ends in ";" and is
		inserted after an existing port that already does, so the list's LAST
		declaration is never touched; with the fabric off nothing is added and the
		component decls are byte-identical.'''
		if not self.eventFabric:
			return []
		ports = {
			'gpio': [
				'            -- EVFAB taps (digperiphs): the PRE-MASK pad-edge export that feeds',
				'            -- the fabric\'s GPIO0 front end, and the two PxTASK-selected output',
				'            -- tasks. Only GPIO0 wires them; every other port leaves them open.',
				'            evt_edge_raw    : out std_logic_vector(num_pins - 1 downto 0);',
				"            task_outset     : in  std_logic := '0';",
				"            task_outclr     : in  std_logic := '0';",
			],
			'uart': [
				'            -- EVFAB tap (digperiphs): the RCIF SET condition, pre-mask (EV7)',
				'            evt_rx      : out std_logic;',
			],
			'timer': [
				'            -- EVFAB taps (digperiphs): the producer TOGGLES (timer_clock domain;',
				'            -- the fabric does the 2-FF + XOR) and the START/STOP tasks.',
				'            evt_compare0 : out std_logic;',
				'            evt_overflow : out std_logic;',
				"            task_start   : in  std_logic := '0';",
				"            task_stop    : in  std_logic := '0';",
			],
		}
		if comp not in ports:
			raise Exception('MCU.vhd emitter: no EVFAB component-port group for "' + comp + '"')
		return ports[comp]

	def evfabInsertTaps(self, lines, anchor, instKey):
		'''Insert instKey's EVFAB tap port-map lines directly after `anchor` inside a
		port map this module emits. The anchor is a line that already ends in a comma,
		so the insertion never has to touch the map's LAST association (and with the
		fabric off nothing is inserted at all — byte-identical). RAISES if the anchor
		moved: a silent miss would drop a tap.'''
		if not self.eventFabric:
			return lines
		if anchor not in lines:
			raise Exception('MCU.vhd emitter: EVFAB tap anchor "' + anchor.strip()
				+ '" not found in the ' + instKey + ' instance region')
		at = lines.index(anchor)
		return lines[:at + 1] + self.emitEvfabTaps(instKey) + lines[at + 1:]

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
		present, Hi-Z otherwise. P6.0-2 are NFC inputs (rf_clk/rf_rx/field_detect);
		P6.3-5 are NFC outputs (rf_txmod/rf_tx_en/afe_en); P6.6/7 are spare plain GPIO
		(the DP-S3 PGOOD/strap DIRECT taps when fieldPower is on; OW0's DQ left P6.6
		for the P4.7 AF2 spread slot at the Stage H re-pin).'''
		af1 = []
		mux = []
		if self.nfc:
			outMap = {
				7: "'0'", 6: "'0'",
				5: 'nfc0_afe_en',
				4: 'nfc0_rf_tx_en',
				3: 'nfc0_rf_txmod',
				2: "'0'", 1: "'0'", 0: "'0'",
			}
			# P6.0-2 are inputs -> AF dir '0' (input); P6.3-5 outputs -> AF dir '1'.
			dirMap = {7: "'0'", 6: "'0'", 5: "'1'", 4: "'1'", 3: "'1'",
				2: "'0'", 1: "'0'", 0: "'0'"}
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

	def nMasters(self):
		'''digperiphs #6: arbiter MASTER count = numHarts (+ 1 for the DMA engine when
		present). The DMA is master index numHarts (the LAST slice). Degenerates to
		numHarts when dma is off (byte-identical default; Argus is unaffected).'''
		return self.nHarts() + (1 if self.dma else 0) + (1 if self.debug else 0)

	def orchHart(self):
		'''CP2: the orchestrator hart's index, or None when there is none. The
		ONE place the index is decided on the emitter side (the dmMasterIndex()
		rule: two independent computations of one index is how the fabric gets
		two masters on one slice).'''
		if not self.orch:
			return None
		n = self.nHarts()
		if self.mgmtHart != n - 1:
			raise Exception('MCU.vhd emitter: managementHart ' + str(self.mgmtHart)
				+ ' must be the LAST hart index (' + str(n - 1) + ') ' + EMDASH
				+ ' pwr_ctrl keeps rows for the gateable tiles 1..N-2 only (CP1 D2)')
		return self.mgmtHart

	def pwrHarts(self):
		'''CP2: the hart count pwr_ctrl sees. The orchestrator has NO power
		domain (no chip-level power intent exists in the centre band), so it is
		excluded HERE AND NOWHERE ELSE — the CLINT, the irq_router, the Debug
		Module and every arbiter master index stay on the full nHarts().'''
		return self.nHarts() - (1 if self.orch else 0)

	def tileTop(self):
		'''Exclusive upper bound of the hart_tile TILE loops (1..tileTop()-1).
		Equals nHarts() without an orchestrator; one less with one, because the
		orchestrator is emitted separately as an orch_tile.'''
		return self.pwrHarts()

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
		# D2: when the DMI ports follow (debug.enable), the LAST a0_N port is no
		# longer the last port in the entity and needs its separator.
		last = ';' if self.debug else ''
		for h in range(1, n):
			lines.append(' ' * 8 + 'a0_' + str(h) + ' : out std_logic_vector(31 downto 0)' + (';' if h != n - 1 else last))
		return lines

	def emitArbFabricDecls(self):
		# digperiphs #6: bus widths follow nMasters = numHarts (+ the DMA engine at
		# index numHarts when present). The hart-tiles comment keeps numHarts-1 (the DMA
		# is NOT a hart tile) — byte-identical when dma is off (nMasters == numHarts).
		n = self.nHarts()
		M = self.nMasters()
		nm1 = str(n - 1)		# hart-tiles range in the comment (unchanged by the DMA)
		Ms = str(M)
		Mm1 = str(M - 1)
		lines = []
		lines.append(self.sigDecl('arb_lrsc', 'std_logic_vector(' + Ms + '*2-1 downto 0);'))
		lines.append(self.sigDecl('arb_scfail', 'std_logic_vector(' + Mm1 + ' downto 0);'))
		lines.append(self.sigDecl('arb_resvvld', 'std_logic_vector(' + Mm1 + ' downto 0);  -- X1 Zawrs: per-master reservation-valid level'))
		lines.append(self.sigDecl('sh_we_raw', 'std_logic_vector(3 downto 0);  -- arbiter s_we, pre resv gating'))
		if self.orch:
			# CP2: the orchestrator is master nHarts-1, so the TILE range stops
			# one short and the orchestrator is named separately (it is not a
			# hart_tile and has no pd_*/clamp row).
			masterComment = (' ' * 8 + '-- arbiter master buses (master 0 = hart 0; masters 1-'
				+ str(self.tileTop() - 1) + ' = hart tiles; master ' + str(self.orchHart())
				+ ' = the orchestrator')
		else:
			masterComment = ' ' * 8 + '-- arbiter master buses (master 0 = hart 0; masters 1-' + nm1 + ' = hart tiles'
		if self.dma:
			masterComment += '; master ' + str(n) + ' = DMA0 engine'
		if self.debug:
			masterComment += '; master ' + str(self.dmMasterIndex()) + ' = dm0 Debug Module'
		masterComment += ').'
		lines.append(masterComment)
		lines.append(' ' * 8 + '-- we = 4 active-high byte-lane strobes per master (M4a).')
		lines.append(' ' * 8 + 'signal arb_req, arb_gnt, arb_done : std_logic_vector(' + Mm1 + ' downto 0);')
		lines.append(' ' * 8 + "-- M8: per-master grant-lock (cores' amo_lock) " + EMDASH + ' pins the arbiter to a')
		lines.append(' ' * 8 + '-- master across its AMO read+write transaction pair (cross-hart AMO')
		lines.append(' ' * 8 + '-- atomicity).')
		lines.append(self.sigDecl('arb_lock', 'std_logic_vector(' + Mm1 + ' downto 0);'))
		lines.append(self.sigDecl('arb_we', 'std_logic_vector(' + Ms + '*4-1 downto 0);'))
		lines.append(self.sigDecl('arb_addr', 'std_logic_vector(' + Ms + '*SH_AW-1 downto 0);'))
		lines.append(self.sigDecl('arb_wdata', 'std_logic_vector(' + Ms + '*32-1 downto 0);'))
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
		# CP2: the power-domain vectors span the GATEABLE tiles only, so an
		# orchestrator shortens them by one (pwrHarts) — it has no pd_* row.
		rng = 'std_logic_vector(' + str(self.pwrHarts() - 1) + ' downto 1);'
		lines = [self.sigDecl(nm, rng) for nm in ('pd_iso_en', 'pd_sleep', 'pd_rstn', 'tile_rstn')]
		# DP-S3: the HOLD-IN-RESET boot gate (pwr0 output, reset '1' = release)
		# and hart 0's folded reset (hart 0 never had a fold before the gate).
		lines.append(self.sigDecl('pgood_rstn', "std_logic := '1';"))
		lines.append(self.sigDecl('hart0_rstn', 'std_logic;'))
		if self.orch:
			o = str(self.orchHart())
			lines.append(' ' * 8 + '-- CP2: the orchestrator takes hart 0\'s reset shape exactly '
				+ '(resetn and the')
			lines.append(' ' * 8 + '-- DP-S3 boot gate) ' + EMDASH + ' it is ALWAYS-ON and has no pd_rstn row.')
			lines.append(self.sigDecl('hart' + o + '_rstn', 'std_logic;'))
		return lines

	def emitTileRawDecls(self):
		# CP2: _raw nets exist to pass the M17 isolation clamps, so they cover
		# the CLAMPED tiles only — the orchestrator drives the arbiter and the
		# a0_N monitor directly, exactly as hart 0 does.
		n = self.tileTop()
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
		# digperiphs #6: sh_master width follows the arbiter master width (masterW =
		# max(2, clog2(nMasters))). 2 bits at the numHarts=4 default; 3 bits when the DMA
		# is present (nMasters=5). Byte-identical when dma is off.
		w = self.masterW()
		return [self.sigDecl('sh_master', 'std_logic_vector(' + str(w - 1) + ' downto 0);')]

	def coreGenericLines(self):
		'''The 24 core ISA/priv generic associations + the D1/D2 debug pair,
		shared VERBATIM by all THREE hart-instance emitters (hart 0, the tiles,
		and the CP2 orchestrator). It is ONE list on purpose: the orchestrator is
		ISA-identical to the tiles by construction (CP1 D5), and three hand-kept
		copies of this block is exactly how one instance silently ends up on a
		different configuration (the F-K7-4 shape).'''
		lines = []
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
		lines.append('            ENABLE_ZFINX      => CORE_ENABLE_ZFINX,')
		lines.append('            -- P0 privileged-architecture scaffolding (P1/P2/P3)')
		lines.append('            ENABLE_TRAPCSR    => CORE_ENABLE_TRAPCSR,')
		lines.append('            ENABLE_UMODE      => CORE_ENABLE_UMODE,')
		lines.append('            ENABLE_PMP        => CORE_ENABLE_PMP,')
		lines.append('            PMP_ENTRIES       => CORE_PMP_ENTRIES,')
		# D1/D2 core-side debug mode.
		#   knob OFF: DEBUG_ENTRY_ADDR is NOT named -- the hart_tile/vesta entity
		#     default (0xBE00) stands, and the three dbg_* PORTS are left
		#     unconnected, sitting at their '0' entity defaults. That is the
		#     bit-identical pre-D1 shape and check_mcu_vhd.py STRICT pins it.
		#   knob ON (D2): DEBUG_ENTRY_ADDR is passed EXPLICITLY as 0x00010780 --
		#     the shared-window debug entry page (R-DD3/R-D2-1(3)), because a
		#     tile's TCM is unreachable from the shared bus and the Debug Module
		#     cannot place code at 0xBE00. The VHDL declaration defaults stay
		#     0xBE00 as the FAIL-SAFE value; this is the override, and it is
		#     emitted by ALL THREE hart emitters -- the half-done-diff trap
		#     (which is precisely why they now share this one list).
		if self.debug:
			lines.append('            ENABLE_DEBUG      => CORE_ENABLE_DEBUG,')
			lines.append('            DEBUG_ENTRY_ADDR  => x"00010780"')
		else:
			lines.append('            ENABLE_DEBUG      => CORE_ENABLE_DEBUG')
		return lines

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
		lines.extend(self.coreGenericLines())
		lines.append('        )')
		lines.append('        port map (')
		lines.append('            clk       => mclk,')
		lines.append('            -- DP-S3: the PGOOD boot gate folds into hart 0 too (hart0_rstn')
		lines.append('            -- = resetn and pgood_rstn; stuck at resetn when the gate is')
		lines.append('            -- unarmed/tied ' + EMDASH + ' see the tile_rstn fold)')
		lines.append('            resetn    => hart0_rstn,')
		lines.append('            sleep     => sleep_cpu,')
		lines.append('            hart_id   => x"00000000",')
		lines.append('            msip_in   => clint_msip(0),')
		lines.append('            mtip_in   => clint_mtip(0),')
		lines.append('            meip_in   => meip(0),')
		if self.debug:
			# D2: hart 0 is on the ALWAYS-ON domain, so its dbg_halted needs no
			# isolation clamp and connects straight to the DM.
			lines.append('            dbg_haltreq      => dbg_haltreq(0),')
			lines.append('            dbg_resethaltreq => dbg_resethaltreq(0),')
			lines.append('            dbg_halted       => dbg_halted(0),')
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

	def dmMasterIndex(self):
		'''D2: the Debug Module's arbiter master slice. The DMA keeps index
		numHarts unconditionally (so a dma-on/debug-off build is byte-identical
		to what it was), and the DM takes the slice after it -- numHarts when the
		DMA is absent, numHarts+1 when it is present. Two masters cannot be
		allocated by two independent nHarts() computations; this is the one
		place the index is decided.'''
		if not self.debug:
			raise Exception('MCU.vhd emitter: dmMasterIndex() with debug off')
		return self.nHarts() + (1 if self.dma else 0)


	def emitDmiPorts(self):
		'''D2: the eight DMI ports on the MCU entity. Emitted ONLY when
		debug.enable -- the OFF build's MCU.vhd carries no trace of the debug
		module at all, which is what check_mcu_vhd.py STRICT enforces.

		The port shape is FROZEN at D2 and D3's JTAG DTM inherits it unchanged:
		the DTM drives exactly these eight nets from TCK through its own toggle
		handshake, so the port is designed once (d2_spec 2). D3 does NOT take
		the ports away from the outside world -- see emitJtagPorts and the
		OR-merge in emitDebugInstance.

		Every INPUT carries a VHDL default. That is not tidiness: MCU.vhd's
		entity is instantiated by riscv_tb.vhd (itself a make-chip product),
		by every chip_top_* netlist and by the gate flows, and an unassociated
		input takes its default while an unassociated output is simply open --
		so adding these ports leaves all of them legal with no edits. It is the
		same trick D1 used on the three hart_tile debug ports.'''
		if not self.debug:
			return []
		return [
			'',
			' ' * 8 + '-- D2 DEBUG MODULE INTERFACE (debug.enable only). abits=7, data=32,',
			' ' * 8 + '-- op: request 01=read 10=write, response 00=success 10=failed',
			' ' * 8 + '-- -- the DTM 41-bit DR arithmetic (2+32+7). One request in flight;',
			' ' * 8 + '-- the handshake is ACK-STYLE (R-D2-4(2)): dmi_req_ready idles LOW and',
			' ' * 8 + '-- pulses for one cycle in response to a presented request -- one accept',
			' ' * 8 + '-- per request -- and exactly one rsp_valid follows each accepted request.',
			' ' * 8 + '-- THERE IS NO "busy" RESPONSE OP. The DM has exactly two op constants',
			' ' * 8 + '-- (00 ok, 10 failed); busy is DTM-LOCAL state -- the 41-bit dmi DR',
			' ' * 8 + '-- captures literal 3 while a transaction is in flight. Corrected at D3',
			' ' * 8 + '-- (d3_spec 3): this comment used to promise a third response op the',
			' ' * 8 + '-- RTL cannot produce, which makes an acceptance check unsatisfiable.',
			' ' * 8 + "dmi_req_valid : in  std_logic := '0';",
			' ' * 8 + 'dmi_req_op    : in  std_logic_vector(1 downto 0) := "00";',
			' ' * 8 + "dmi_req_addr  : in  std_logic_vector(6 downto 0) := (others => '0');",
			' ' * 8 + "dmi_req_data  : in  std_logic_vector(31 downto 0) := (others => '0');",
			' ' * 8 + 'dmi_req_ready : out std_logic;',
			' ' * 8 + 'dmi_rsp_valid : out std_logic;',
			' ' * 8 + 'dmi_rsp_data  : out std_logic_vector(31 downto 0);',
			' ' * 8 + 'dmi_rsp_op    : out std_logic_vector(1 downto 0);',
		]

	def emitJtagPorts(self):
		'''D3: the five JTAG pins on the MCU entity. Same knob, same emission
		rule, same defaulting trick as emitDmiPorts -- and this group is now
		the LAST entity port group, so it carries the no-trailing-`;`
		responsibility that emitDmiPorts used to (probe P1.1: emitA0Ports puts
		a `;` after the last a0_N iff self.debug, and emitDmiPorts now ends in
		one too). A missing or extra separator here is a syntax error in a
		4000-line generated file; it is named in d3_spec 4 for that reason.

		trstn defaults '0' -- TAP HELD IN RESET. That is the fail-safe
		direction (rule 15) and it is what makes the DTM INERT in every bench
		and netlist that does not name these pins: no TCK edges, no requests,
		and the OR-merge below sees a permanently-zero valid.'''
		if not self.debug:
			return []
		return [
			'',
			' ' * 8 + '-- D3 JTAG DEBUG TRANSPORT (debug.enable only). IEEE 1149.1 pins for',
			' ' * 8 + '-- the dtm0 TAP: 5-bit IR, IDCODE/dtmcs/dmi(41)/BYPASS DRs, and the',
			' ' * 8 + '-- TCK<->mclk crossing onto the dmi_* port above (d3_spec 1-2).',
			' ' * 8 + '-- FAIL-SAFE: trstn low = TAP in reset = the whole transport inert, so',
			' ' * 8 + '-- an instantiation that does not connect these pins is unaffected.',
			' ' * 8 + '-- TCK IS ITS OWN CLOCK DOMAIN. It is declared to Genus on the dtm0',
			' ' * 8 + '-- INSTANCE PIN, never on this port: the chip SDC generator deletes',
			' ' * 8 + '-- every [get_ports] line and FATALs if one survives (d3_cdc_spec 5).',
			' ' * 8 + "tck   : in  std_logic := '0';",
			' ' * 8 + "tms   : in  std_logic := '0';",
			' ' * 8 + "tdi   : in  std_logic := '0';",
			' ' * 8 + 'tdo   : out std_logic;',
			' ' * 8 + "trstn : in  std_logic := '0'",
		]

	def emitDebugDecls(self):
		'''D2: the declarative half of the Debug Module hookup.'''
		if not self.debug:
			return []
		n = self.nHarts()
		nm1 = str(n - 1)
		return [
			' ' * 8 + '-- D2 DEBUG MODULE (dm0). Assembly level, one per chip, always-on',
			' ' * 8 + '-- mclk -- never inside a tile, because it must stay reachable while',
			' ' * 8 + '-- any hart is power-gated. Three per-hart wire groups plus a fourth',
			' ' * 8 + '-- that is NOT a tile signal at all:',
			' ' * 8 + '--   dbg_haltreq / dbg_resethaltreq : DM -> tile (no clamp needed;',
			' ' * 8 + '--     they are INPUTS to a gated tile and a gated tile ignores them)',
			' ' * 8 + '--   dbg_halted                     : tile -> DM, and it CROSSES THE',
			' ' * 8 + '--     POWER BOUNDARY, so harts 1..' + nm1 + ' land on dbg_halted_raw and pass',
			' ' * 8 + '--     the M17 isolation clamp like every other tile output. Hart 0',
			' ' * 8 + '--     is on the always-on domain and connects directly.',
			' ' * 8 + '--   dbg_unavail                    : the DM\'s truth-telling input,',
			' ' * 8 + '--     derived from the power-control state BELOW. A clamped',
			' ' * 8 + "--     dbg_halted reads '0', which is indistinguishable from",
			' ' * 8 + '--     "running" -- so unavail is a SEPARATE, deliberate signal and',
			' ' * 8 + '--     the DM consults it BEFORE halted (d2_spec 5).',
			self.sigDecl('dbg_haltreq', 'std_logic_vector(' + nm1 + ' downto 0);'),
			self.sigDecl('dbg_resethaltreq', 'std_logic_vector(' + nm1 + ' downto 0);'),
			self.sigDecl('dbg_halted', 'std_logic_vector(' + nm1 + ' downto 0);'),
			# CP2: only the CLAMPED tiles need a _raw halted wire; hart 0 and
			# the always-on orchestrator connect straight to the DM.
			self.sigDecl('dbg_halted_raw', 'std_logic_vector(' + str(self.tileTop() - 1) + ' downto 1);'),
			self.sigDecl('dbg_unavail', 'std_logic_vector(' + nm1 + ' downto 0);'),
			'',
			' ' * 8 + '-- D3 DMI OR-MERGE (d3_cdc_spec 7). THE CONTRACT, IN ONE SENTENCE:',
			' ' * 8 + '-- the external dmi_* ports are RETAINED and merged with the DTM by',
			' ' * 8 + '-- valid-gated OR-composition -- both request buses reach the one',
			' ' * 8 + '-- Debug Module and its responses are fanned out to BOTH masters --',
			' ' * 8 + '-- so a bench driving the raw port and a debugger driving TCK are',
			' ' * 8 + "-- never simultaneously active by construction: an idle DTM's valid",
			' ' * 8 + '-- is low, which makes the merge transparent.',
			' ' * 8 + '-- WHY IT IS DESIGNED THIS WAY AND NOT TRIPWIRED AROUND: a DTM that',
			' ' * 8 + '-- simply took over the DM inputs would leave every force at the MCU',
			' ' * 8 + '-- formal resolving by NAME while reaching nothing -- silent for the',
			' ' * 8 + '-- VHDL bench that associates them, merely misattributed for the tcl',
			' ' * 8 + '-- harnesses that force them (d3_probe P4.4).',
			self.sigDecl('dm_req_valid', 'std_logic;'),
			self.sigDecl('dm_req_op', 'std_logic_vector(1 downto 0);'),
			self.sigDecl('dm_req_addr', 'std_logic_vector(6 downto 0);'),
			self.sigDecl('dm_req_data', 'std_logic_vector(31 downto 0);'),
			self.sigDecl('dm_req_ready', 'std_logic;'),
			self.sigDecl('dm_rsp_valid', 'std_logic;'),
			self.sigDecl('dm_rsp_data', 'std_logic_vector(31 downto 0);'),
			self.sigDecl('dm_rsp_op', 'std_logic_vector(1 downto 0);'),
			self.sigDecl('dtm_req_valid', 'std_logic;'),
			self.sigDecl('dtm_req_op', 'std_logic_vector(1 downto 0);'),
			self.sigDecl('dtm_req_addr', 'std_logic_vector(6 downto 0);'),
			self.sigDecl('dtm_req_data', 'std_logic_vector(31 downto 0);'),
		]

	def emitDebugInstance(self):
		'''D2: the Debug Module instance + its unavail derivation + the arbiter
		master-slice wiring and the D18-style lrsc/lock ties.'''
		if not self.debug:
			return []
		n = self.nHarts()
		k = self.dmMasterIndex()
		ks = str(k)
		kp1 = str(k + 1)
		lines = [
			'',
			'    -- D2 DEBUG MODULE. dmstatus TRUTH-TELLING against PWRCTRL: a hart is',
			'    -- unavailable when its domain is isolated or it is held in reset.',
			'    -- HART 0 IS NOT IMMUNE -- it has no pd_rstn row, but the DP-S3 boot',
			'    -- gate can hold it in reset through hart0_rstn, and a DM that reported',
			'    -- hart 0 as always-available would lie about exactly the case a',
			'    -- debugger attaches in.',
			"    dbg_unavail(0) <= not hart0_rstn;",
		]
		for h in range(1, self.tileTop()):
			hs = str(h)
			lines.append('    dbg_unavail(' + hs + ') <= pd_iso_en(' + hs
				+ ') or not tile_rstn(' + hs + ');')
		if self.orch:
			# CP2: the orchestrator is debuggable and has no domain to be
			# isolated, so its availability is exactly hart 0's question --
			# is the boot gate holding it in reset?
			o = str(self.orchHart())
			lines.append('    dbg_unavail(' + o + ') <= not hart' + o + '_rstn;')
		lines += [
			'',
			'    dm0: entity work.debug_module',
			'        generic map (ENABLE_DEBUG => CORE_ENABLE_DEBUG, NHARTS => ' + str(n) + ',',
			'                     SH_AW => SH_AW,',
			'                     DATA0_ADDR => x"00010680", FLAGS_ADDR => x"00010700",',
			'                     ENTRY_ADDR => x"00010780")',
			'        port map (',
			'            clk    => mclk,',
			'            resetn => resetn,',
			'            -- D3: the MERGED request bus, not the entity ports (see the',
			'            -- OR-merge below). The RESPONSES are the DM\'s own outputs and',
			'            -- are fanned out to the entity ports AND to dtm0.',
			'            dmi_req_valid => dm_req_valid,',
			'            dmi_req_op    => dm_req_op,',
			'            dmi_req_addr  => dm_req_addr,',
			'            dmi_req_data  => dm_req_data,',
			'            dmi_req_ready => dm_req_ready,',
			'            dmi_rsp_valid => dm_rsp_valid,',
			'            dmi_rsp_data  => dm_rsp_data,',
			'            dmi_rsp_op    => dm_rsp_op,',
			'            dbg_haltreq      => dbg_haltreq,',
			'            dbg_resethaltreq => dbg_resethaltreq,',
			'            dbg_halted       => dbg_halted,',
			'            hart_unavail     => dbg_unavail,',
			'            -- arbiter MASTER port: slice ' + ks + ' of arb_* (depth 0, the DMA shape)',
			'            m_req   => arb_req(' + ks + '),',
			'            m_we    => arb_we(' + str(4 * k + 3) + ' downto ' + str(4 * k) + '),',
			'            m_addr  => arb_addr(' + kp1 + '*SH_AW-1 downto ' + ks + '*SH_AW),',
			'            m_wdata => arb_wdata(' + kp1 + '*32-1 downto ' + ks + '*32),',
			'            m_gnt   => arb_gnt(' + ks + '),',
			'            m_done  => arb_done(' + ks + '),',
			'            m_rdata => arb_rdata);',
			'    -- The DM never does LR/SC and never grant-locks (the D18 DMA argument),',
			'    -- so lrsc/lock are tied here in fabric rather than exported as ports;',
			'    -- arb_scfail(' + ks + ')/arb_resvvld(' + ks + ') are ignored. resv_unit N=nMasters still',
			'    -- keys cur=' + ks + ' on a DM plain write, so a DM write kills matching',
			'    -- reservations and cross-hart LR/SC stays sound across one.',
			'    arb_lrsc(' + str(2 * k + 1) + ' downto ' + str(2 * k) + ') <= "00";',
			"    arb_lock(" + ks + ") <= '0';",
		]
		lines += self.emitJtagInstance()
		return lines

	def emitJtagInstance(self):
		'''D3: the JTAG DTM beside dm0, and the OR-merge that lets the raw
		dmi_* ports and the TAP both reach the one Debug Module.

		THE MERGE IS VALID-GATED, and the external port WINS a simultaneity
		that cannot occur: the DTM's valid is low unless a debugger has
		clocked a dmi Update-DR through TCK, and every bench that forces the
		raw port leaves trstn at its default (TAP in reset). Writing it as a
		select rather than a bitwise OR also keeps an undriven bus from
		merging X into the DM.

		IDCODE is a per-chip CONSTANT chosen by chip identity in generate.py
		(R-DD4(1)), not a schema knob -- there is no configuration in which a
		user should be able to make their chip claim to be another one.'''
		if not self.debug:
			return []
		return [
			'',
			'    -- D3 JTAG DTM (dtm0). Assembly level, beside dm0 -- never inside a',
			'    -- tile: TCK must reach the transport while any hart is power-gated,',
			'    -- and the tile SDC has no clock-to-clock false paths to disturb.',
			'    -- The TCK domain is asynchronous to mclk and crosses on ONE toggle',
			'    -- each way with the payload HELD (the UART flags_cdc_proc idiom);',
			'    -- its mclk-side master is a ONE-SHOT that retires on dmi_req_ready,',
			'    -- because the DM\'s re-capture lockout is a 9-cycle TIMER and a held',
			'    -- request level would earn a second, duplicate accept.',
			'    dtm0: entity work.jtag_dtm',
			'        generic map (ENABLE_DEBUG => CORE_ENABLE_DEBUG,',
			'                     IDCODE      => x"' + self.jtagIdcode() + '",',
			'                     IDLE_CYCLES => ' + str(self.jtagIdleCycles()) + ')',
			'        port map (',
			'            tck    => tck,',
			'            tms    => tms,',
			'            tdi    => tdi,',
			'            tdo    => tdo,',
			'            trstn  => trstn,',
			'            clk    => mclk,',
			'            resetn => resetn,',
			'            dmi_req_valid => dtm_req_valid,',
			'            dmi_req_op    => dtm_req_op,',
			'            dmi_req_addr  => dtm_req_addr,',
			'            dmi_req_data  => dtm_req_data,',
			'            dmi_req_ready => dm_req_ready,',
			'            dmi_rsp_valid => dm_rsp_valid,',
			'            dmi_rsp_data  => dm_rsp_data,',
			'            dmi_rsp_op    => dm_rsp_op);',
			'',
			'    -- THE OR-MERGE ITSELF. Requests: valid-gated OR of the two masters.',
			'    -- Responses: the DM\'s outputs fanned out to the entity ports AND to',
			'    -- dtm0, so an accept or a response is visible to whichever master',
			'    -- issued it -- and to any instrument watching the port.',
			'    dm_req_valid <= dmi_req_valid or dtm_req_valid;',
			"    dm_req_op    <= dmi_req_op   when dmi_req_valid = '1' else dtm_req_op;",
			"    dm_req_addr  <= dmi_req_addr when dmi_req_valid = '1' else dtm_req_addr;",
			"    dm_req_data  <= dmi_req_data when dmi_req_valid = '1' else dtm_req_data;",
			'    dmi_req_ready <= dm_req_ready;',
			'    dmi_rsp_valid <= dm_rsp_valid;',
			'    dmi_rsp_data  <= dm_rsp_data;',
			'    dmi_rsp_op    <= dm_rsp_op;',
		]

	def jtagIdcode(self):
		'''D3: the JTAG IDCODE as eight hex digits, selected by CHIP IDENTITY
		(R-DD4(1) -- USER values, deliberately NOT a schema knob).

		Castalia 0x1CA57EEF / Argus 0x1A265EEF: version 1, partnum
		0xCA57/0xA265, manufid 0x777 (the Spike-precedent deliberately invalid
		JEP106 code -- honest for a non-commercial chip), LSB 1 as 1149.1
		mandates.

		THE DISCRIMINATOR IS DELIBERATELY BOTH: the config's own chipName OR
		numHarts == 18. The acceptance instruments key on the hart count (it
		is the only chip discriminator a harness has in band), and CHIP_NAME
		is a DOCS-ONLY env override -- so a name-only rule would let a
		documentation switch change an RTL constant, and a count-only rule
		would be silent about what it means. Every shipped config agrees under
		both halves.'''
		if self.isArgusFamily():
			return '1A265EEF'
		return '1CA57EEF'

	def isArgusFamily(self):
		name = str(self.chipNameConfigured or '')
		return self.nHarts() == 18 or name.lower().startswith('argus')

	def jtagIdleCycles(self):
		'''D3: dtmcs.idle [14:12], in TCK cycles, and it is TRUTHFUL (Spike
		advertises 0 while enforcing a hidden requirement -- the one behaviour
		d3_cdc_spec 4 says not to copy). The derivation is written out in
		jtag_dtm.vhd's header: 3 TCK cycles of response synchroniser plus the
		mclk round trip (8-10 mclk for a register access, tens more for the
		three PROXIED addresses through mp_arbiter), against the stated
		assumption TCK <= 7.14 MHz with mclk at 24 MHz. 7 covers the worst
		class with a cycle of margin and is the maximum the 3-bit field can
		express, so rounding up costs nothing but debugger throughput.'''
		return 7

	def masterW(self):
		'''mp_arbiter s_master / mutex_bank / irq_router master width (A2: the MW
		generic, default 2 = the Castalia shape). digperiphs #6: sized to nMasters
		(numHarts + the DMA), so enabling the DMA (nMasters=5) grows MW 2->3 across the
		arbiter, mutex_bank and irq_router in lockstep. Degenerates to the numHarts value
		when dma is off (byte-identical default; Argus numHarts=18 -> MW=5 unchanged).'''
		return max(2, _clog2(self.nMasters()))

	def emitArbGeneric(self):
		# A2: MW (s_master width) is emitted only when it differs from the RTL default 2
		# (N=4 byte-identity). digperiphs #6: N and MW follow nMasters — enabling the DMA
		# takes N=>5, MW=>3 (2**MW >= N needs MW=3 at N=5).
		mw = self.masterW()
		return [' ' * 8 + 'generic map (N => ' + str(self.nMasters()) + ', ADDR_WIDTH => SH_AW, DATA_WIDTH => 32'
			+ ('' if mw == 2 else ', MW => ' + str(mw)) + ')']

	def emitResvGeneric(self):
		# digperiphs #6: N follows nMasters so resv_unit's one-hot gnt->cur decode reaches
		# index numHarts (the DMA) — a DMA plain write keys cur=numHarts and kills matching
		# reservations, keeping cross-hart LR/SC sound across a DMA write (D18).
		return [' ' * 8 + 'generic map (N => ' + str(self.nMasters()) + ', ADDR_WIDTH => SH_AW)']

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
		'''Verbatim side-template block, re-running any inner --@GEN:*@ marker
		through the region emitter: the instance blocks carry their own bus
		marker (the main template no longer does) and, since the EVFAB knob,
		their own --@GEN:evfab-taps:<inst>@ marker. Inner markers are resolved
		HERE, so they never enter generateMcuVhd's seen/expected accounting.'''
		if name not in blocks:
			raise Exception('MCU.vhd emitter: ' + sourceName + ' has no block "' + name + '"')
		lines = []
		for line in blocks[name]:
			m = re.match(r'^\s*--@GEN:([A-Za-z0-9:_-]+)@\s*$', line)
			if m:
				lines.extend(self.emitRegion(m.group(1)))
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

	def i2ctMergeDirRows(self, lines):
		'''digperiphs (I2CT, D19 — Fable-owned shared-RTL edit): with I2CT0
		present, the sda0/scl0 DIR-plane rows bind the wired-AND merge scalars
		(sda0_dir_mrg/scl0_dir_mrg, driven next to the i2ct0 instance) so either
		engine's drive-low wins on the shared open-drain pads. Applied to all
		three plane locations (GPIO3 home + GPIO1/GPIO2 relocations). OUT rows
		stay untouched (tied '0' open-drain at the source) and REN rows keep
		I2C0's pull policy. Byte-exact golden text when the knob is off.'''
		if not self.i2ctarget:
			return lines
		out = []
		for l in lines:
			m = re.match(r'^(\s*pnum_\w+_(?:sda0|scl0)\s*=> )((?:sda0|scl0)_dir)(,?)\s*(--.*)$', l)
			if m:
				col = l.index('--')
				body = m.group(1) + m.group(2) + '_mrg' + m.group(3)
				if len(body) + 1 > col:
					l = body + ' ' + m.group(4)
				else:
					l = body.ljust(col) + m.group(4)
			out.append(l)
		return out

	def emitGpio2Af1Planes(self):
		'''The P3 (GPIO2) AF1 relocation-plane aggregates. Dropped I2C1/UART1
		rows degrade to the existing "unassigned" hi-Z idiom (literal pin
		index, since the pnum_gpio2_af1_{sda1,scl1,tx1,rx1} constants are
		gated with their owner). The two knobs gate independently (G1b).
		I2CT0 rebinds the sda0/scl0 DIR rows to the D19 merge (i2ctMergeDirRows).'''
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
		return self.i2ctMergeDirRows(lines)

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
		return self.i2ctMergeDirRows(lines)

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
		return self.i2ctMergeDirRows(lines)

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
		lines.append(ind + '-- DP-S3 3b: bits 6:3 gate the shared bulk-RAM banks shbank0-3')
		lines.append(ind + '-- (per-bank, reset ON; contents LOST on gate ' + EMDASH + ' see SYSTEM.vhd).')
		if self.banks > 4:
			lines.append(ind + '-- Banks 4-' + str(self.banks - 1) + " of this configuration stay hardwired ON (PGEN => '0').")
		lines.append(ind + 'signal ' + 'RAM_Dout'.ljust(17) + ': std_logic_vector(31 downto 0);')
		lines.append(ind + 'signal ' + 'pgen_mem'.ljust(17) + ': std_logic_vector(6 downto 0);')
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
			if b < 4:
				# DP-S3 3b: BLOCKPWR bits 6:3 gate shbank0-3 (reset ON;
				# contents lost on gate). Banks 4+ (Argus 8-bank shape)
				# stay hardwired ON — BLOCKPWR has no bits for them.
				lines.append(ind * 3 + 'PGEN  => pgen_mem(' + str(3 + b) + ')  -- DP-S3 3b: BLOCKPWR SYSSHB' + str(b) + 'OFF')
			else:
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
		array formula ceil(N/8) (RAISES on drift, like the CLINT layout).

		CP2: N here is pwrHarts, NOT numHarts. The orchestrator hart sits
		outside the MTCMOS fabric (CP1 D2 — the centre band has no power
		intent; a gateable-in-RTL orchestrator would be the hw_clint_en
		silicon lie again), so pwr_ctrl keeps rows for the gateable tiles
		only. Consequence, stated because software will meet it: at
		numHarts=5 PWRCR has NO bit 4 and PWRSR has no nibble 4 — the
		orchestrator reads back exactly like hart 0 (0, writes ignored), and
		the harvested-boot PWRCR <- 0xFFFFFFFF gates tiles 1-3 and leaves the
		orchestrator running, which is the wanted semantics.'''
		n = self.pwrHarts()
		nsrw = (n + 7) // 8
		# DP-S3: the register set is PWRCR(0) + PWRSR words 1..ceil(N/8) +
		# PWRWAKE(5)/PWRSTS(6) at FIXED slots — PWRSR must stay below 5 and
		# the description's top slot must be PWRSTS. Cross-checked like the
		# CLINT layout (RAISES on drift).
		if nsrw >= 5:
			raise Exception('MCU.vhd emitter: PWRSR nibble array (ceil(N/8) words) collides '
				+ 'with the DP-S3 PWRWAKE/PWRSTS words 5/6 ' + EMDASH + ' N > 32 unsupported')
		slots = sorted(r.RegisterMemorySlot for r in self.periph('PWRCTRL').Registers)
		expected = [0] + list(range(1, nsrw + 1)) + [5, 6]
		if slots != expected:
			raise Exception('MCU.vhd emitter: PWRCTRL register layout does not match the A2 '
				+ 'PWRSR nibble-array formula + DP-S3 PWRWAKE/PWRSTS (expected slots '
				+ str(expected) + ', got ' + str(slots) + ') '
				+ EMDASH + ' generate.py and pwr_ctrl.vhd must agree')
		gm = 'generic map ('
		if n != 4:
			gm += 'NHARTS => ' + str(n) + ', '
		gm += 'T_SEQ => 4, T_RAIL => 256)'
		if self.fieldpower:
			ties = ('prt6_in(7)', 'prt6_in(6)',
				'nfc0_field_detect' if self.nfc else "'0'")
			tieNote = ('            -- DP-S3 supervision inputs: PGOOD P6.7 + harvested-boot strap'
				, '            -- P6.6 as DIRECT pad taps (always readable ' + EMDASH + ' the gate must work'
				, '            -- before any software runs); field level '
				+ ('from NFC0' if self.nfc else "tied '0' (no NFC)") + '. 2-FF'
				, '            -- synchronized inside pwr_ctrl.')
		else:
			ties = ("'1'", "'0'", "'0'")
			tieNote = ('            -- DP-S3 supervision inputs TIED INERT (peripherals.fieldPower'
				, '            -- off): pgood good / strap NORMAL / no field ' + EMDASH + ' pgood_rstn is'
				, "            -- stuck '1' and the boot gate is a provable no-op.")
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
		lines.append('            pd_rstn   => pd_rstn,')
		for ln in tieNote:
			lines.append(ln)
		lines.append('            pgood_pad    => ' + ties[0] + ',')
		lines.append('            strap_pad    => ' + ties[1] + ',')
		lines.append('            field_detect => ' + ties[2] + ',')
		lines.append('            pgood_rstn   => pgood_rstn')
		lines.append('        );')
		# digperiphs (EVFAB): the T5 tile-wake task
		return self.evfabInsertTaps(lines, '            pd_rstn   => pd_rstn,', 'pwr0')

	def emitTileRstn(self):
		# DP-S3: pgood_rstn (the HOLD-IN-RESET boot gate) folds into EVERY
		# hart's outer reset — the tiles extend the M17 pd_rstn fold and hart 0
		# gains the fold it never had. A held hart issues no sh_req (the M12
		# outer-reset qualification), so the arbiter sees the same bus silence
		# pd_rstn already guarantees. pgood_rstn resets '1' and is stuck there
		# unless a strap/software arms the gate — every normal boot unperturbed.
		lines = ['    tile_rstn(' + str(h) + ') <= resetn and pd_rstn(' + str(h) + ') and pgood_rstn;'
			for h in range(1, self.tileTop())]
		lines.append('    -- DP-S3: hart 0 has no pd_rstn row (always-on domain) ' + EMDASH + ' only the boot gate')
		lines.append('    hart0_rstn <= resetn and pgood_rstn;')
		if self.orch:
			o = str(self.orchHart())
			lines.append('    -- CP2: neither has the orchestrator ' + EMDASH + ' same always-on shape, same fold.')
			lines.append('    hart' + o + '_rstn <= resetn and pgood_rstn;')
		return lines

	def emitIsoClamps(self):
		# CP2: clamps exist per POWER DOMAIN, so the orchestrator (always-on,
		# no domain) has no clamp row — its outputs reach the arbiter and the
		# tb directly, the hart-0 shape.
		n = self.tileTop()
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
			# D2: dbg_halted is the EIGHTH clamped tile output. It must be here or
			# a dark tile's unpowered output propagates into the always-on Debug
			# Module. Clamping it to '0' is necessary and NOT sufficient -- '0' is
			# indistinguishable from "running" -- which is why dbg_unavail exists
			# and why the DM consults it BEFORE halted (d2_spec 5).
			if self.debug:
				rows.append(('dbg_halted(' + hs + ')', 'dbg_halted_raw(' + hs + ')', "'0'", False))
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
		lines.extend(self.coreGenericLines())
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
		if self.debug:
			# D2: dbg_halted leaves a GATEABLE domain, so it lands on _raw and
			# passes the M17 iso clamp with every other tile output.
			lines.append('            dbg_haltreq      => dbg_haltreq(' + hs + '),')
			lines.append('            dbg_resethaltreq => dbg_resethaltreq(' + hs + '),')
			lines.append('            dbg_halted       => dbg_halted_raw(' + hs + '),')
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
		# CP2: hart_tile instances are the GATEABLE tiles only; the
		# orchestrator is an orch_tile emitted by emitOrchInstance (its own
		# --@GEN:orch-instance@ region, immediately below this one).
		lines = []
		for h in range(1, self.tileTop()):
			if h > 1:
				lines.append('')
			lines.extend(self.tileInstance(h))
		return lines

	def emitOrchInstance(self):
		'''CP2 (Castalia-Penta): the ORCHESTRATOR hart — the third hart-instance
		emitter, beside emitHart0Instance and tileInstance. Emits NOTHING when
		the config names no management hart, so check_mcu_vhd.py STRICT sees no
		trace of it at the N=4 default.

		WIRING, and every line of it is a decision:
		  * ENTITY is `orch_tile`, not `hart_tile` (D6) — the soft core needs a
		    module namespace disjoint from the hardened tile netlist. It is a
		    bare wrapper, so the two are behaviourally identical.
		  * POWER/RESET is HART 0's, not the tiles': resetn = hartN_rstn
		    (resetn and the DP-S3 boot gate), NO pwr_ctrl row, NO isolation
		    clamps, sh_* straight onto its arbiter slice, pd_sleep/pd_iso_en
		    strapped '0'. The centre band has no chip-level power intent, so a
		    gateable-in-RTL orchestrator would be a hardware lie (D2).
		  * BOOT/IRQ is the TILES': hart_id = the index, msip/mtip from the
		    CLINT and meip from the router row N, so it parks in the shared ROM
		    and is ignited through the ordinary loader row + msip protocol
		    (D3 — boot mastership stays on hart 0).
		  * sleep '0' and the flash quartet OPEN: the flash/XIP pins belong to
		    hart 0's tile. An orchestrator access >= 0x20000 reads zeros and
		    never stalls, the same "undefined on unmapped" class as a tile.
		  * tcm_pgen '0' / tcm_retn '1': its own TCM is never gated.
		  * trap_flag open (hart 0 owns the GPIO0 trap pin); a0 straight to the
		    a0_N observation port — MONITORED, never the pass/fail gate, which
		    stays hart 0 (D8).'''
		o = self.orchHart()
		if o is None:
			return []
		os_ = str(o)
		lines = ['']
		lines.append('    -- =========================================================================')
		lines.append('    -- CP2 ORCHESTRATOR HART (hart ' + os_ + '). Same core, same ISA, same 24 generic')
		lines.append('    -- associations as the tiles (D5) ' + EMDASH + ' but SOFT logic in the centre band')
		lines.append('    -- instead of a hardened corner macro, so it is instantiated through the')
		lines.append('    -- orch_tile wrapper (D6: no module name may be shared between the tile')
		lines.append('    -- netlist and the orchestrator netlist, or the assembly strip step')
		lines.append('    -- deletes this subtree and gate sim sees two definitions of one module).')
		lines.append('    -- It is ALWAYS-ON: hart 0\'s reset/power wiring, NOT the tiles\' ' + EMDASH + ' no')
		lines.append('    -- pwr_ctrl row, no iso clamps, sh_* direct into arbiter slice ' + os_ + '. Its')
		lines.append('    -- boot is the tiles\': park in the shared ROM, ignited by loader row')
		lines.append('    -- 0x10500+0x10*' + os_ + ' + msip[' + os_ + ']. a0 is OBSERVED only (hart 0 stays the gate).')
		lines.append('    -- =========================================================================')
		lines.append('    hart' + os_ + ': entity work.orch_tile')
		lines.append('        generic map (')
		lines.append('            PC_RST_VAL     => x"00000000",')
		lines.append('            SH_AW          => SH_AW,')
		lines.append('            -- Core ISA features (config-driven, work.MemoryMap; IDENTICAL to')
		lines.append('            -- the tiles by construction ' + EMDASH + ' the orchestrator is not a')
		lines.append('            -- different core, only a differently-implemented one)')
		lines.extend(self.coreGenericLines())
		lines.append('        )')
		lines.append('        port map (')
		lines.append('            clk       => mclk,')
		lines.append('            -- CP2/D2: hart-0-style reset (resetn and the DP-S3 boot gate).')
		lines.append('            -- There is deliberately no pd_rstn term: no power domain exists')
		lines.append('            -- for this hart, so there is nothing to hold it for.')
		lines.append('            resetn    => hart' + os_ + '_rstn,')
		lines.append("            -- No SPI0/XIP behind the orchestrator (D3: the flash quartet is")
		lines.append('            -- physically hart 0\'s), so sleep is strapped and the flash ports')
		lines.append('            -- are left open at their entity defaults.')
		lines.append("            sleep     => '0',")
		lines.append('            hart_id   => x"' + format(o, '08x') + '",')
		lines.append('            msip_in   => clint_msip(' + os_ + '),')
		lines.append('            mtip_in   => clint_mtip(' + os_ + '),')
		lines.append('            meip_in   => meip(' + os_ + '),')
		if self.debug:
			lines.append('            -- D2: always-on domain ' + EMDASH + ' no clamp, straight to the DM.')
			lines.append('            dbg_haltreq      => dbg_haltreq(' + os_ + '),')
			lines.append('            dbg_resethaltreq => dbg_resethaltreq(' + os_ + '),')
			lines.append('            dbg_halted       => dbg_halted(' + os_ + '),')
		lines.append('            sh_req    => arb_req(' + os_ + '),')
		lines.append('            sh_we     => arb_we(' + str(4 * o + 3) + ' downto ' + str(4 * o) + '),')
		lines.append('            sh_addr   => arb_addr(' + str(o + 1) + '*SH_AW-1 downto ' + os_ + '*SH_AW),')
		lines.append('            sh_wdata  => arb_wdata(' + str(o + 1) + '*32-1 downto ' + os_ + '*32),')
		lines.append('            sh_gnt    => arb_gnt(' + os_ + '),')
		lines.append('            sh_done   => arb_done(' + os_ + '),')
		lines.append('            sh_rdata  => arb_rdata,')
		lines.append('            sh_lrsc   => arb_lrsc(' + str(2 * o + 1) + ' downto ' + str(2 * o) + '),')
		lines.append('            sh_scfail => arb_scfail(' + os_ + '),')
		lines.append('            sh_resv_valid => arb_resvvld(' + os_ + '),')
		lines.append('            sh_lock   => arb_lock(' + os_ + '),')
		lines.append('            -- CP2: the orchestrator TCM is never gated (no domain to gate it')
		lines.append('            -- with) and never in retention ' + EMDASH + ' a future knob if that changes.')
		lines.append("            tcm_pgen  => '0',")
		lines.append("            tcm_retn  => '1',")
		lines.append('            -- CP2: MTCMOS controls strapped inactive, EXPLICITLY, per the M14')
		lines.append('            -- netlist-boundary rule (an omitted generic/port default is how a')
		lines.append('            -- silicon bug of the hw_clint_en class gets in).')
		lines.append("            pd_sleep  => '0',")
		lines.append("            pd_iso_en => '0',")
		lines.append('            trap_flag => open,')
		lines.append('            a0        => a0_' + os_)
		lines.append('        );')
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
			lines.append(ind + 'MabMmrA'.ljust(12) + '=> sh_addr(3 downto 0),')
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
		if name == 'orch-instance':
			return self.emitOrchInstance()
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
		if name == 'pwm-decls':
			return self.emitPwmDecls()
		if name == 'pwm-instance':
			return self.emitPwmInstance()
		if name == 'ow-decls':
			return self.emitOwDecls()
		if name == 'ow-instance':
			return self.emitOwInstance()
		if name == 'dmi-ports':
			return self.emitDmiPorts()
		if name == 'jtag-ports':
			return self.emitJtagPorts()
		if name == 'debug-decls':
			return self.emitDebugDecls()
		if name == 'debug-instance':
			return self.emitDebugInstance()
		if name == 'dma-decls':
			return self.emitDmaDecls()
		if name == 'dma-instance':
			return self.emitDmaInstance()
		if name == 'i2ct-decls':
			return self.emitI2ctDecls()
		if name == 'i2ct-instance':
			return self.emitI2ctInstance()
		if name == 'trng-decls':
			return self.emitTrngDecls()
		if name == 'trng-instance':
			return self.emitTrngInstance()
		if name == 'evfab-decls':
			return self.emitEvfabDecls()
		if name == 'evfab-instance':
			return self.emitEvfabInstance()
		if name.startswith('evfab-taps:'):
			return self.emitEvfabTaps(name[len('evfab-taps:'):])
		if name.startswith('evfab-comp:'):
			return self.emitEvfabCompPorts(name[len('evfab-comp:'):])
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
		# digperiphs #5: PWM0 in MUTEX-page (page 2) sub-slot 6 @0x6600
		'pwm-decls', 'pwm-instance',
		# digperiphs #5: OW0 (1-Wire master) in MUTEX-page (page 2) sub-slot 7 @0x6700
		'ow-decls', 'ow-instance',
		# digperiphs #6: DMA0 in MUTEX-page (page 2) sub-slot 8 @0x6800 (+ the arbiter
		# fabric widening emitted through arb-fabric-decls / arb-generic / resv-generic /
		# mutex-instance / irq-router-instance / sh-master-decl)
		'dma-decls', 'dma-instance',
		# D2: the Debug Module -- entity ports, decls, instance. All three
		# emit NOTHING when debug.enable is off. D3 adds the JTAG port group
		# (which becomes the LAST entity port group and so carries the
		# no-trailing-`;` responsibility); the DTM instance and the OR-merge
		# ride the debug-instance marker beside dm0, on the same knob.
		'dmi-ports', 'jtag-ports', 'debug-decls', 'debug-instance',
		# digperiphs (I2CT): I2CT0 in MUTEX-page (page 2) sub-slot 10 @0x6A00
		'i2ct-decls', 'i2ct-instance',
		# digperiphs (TRNG): TRNG0 in MUTEX-page (page 2) sub-slot 9 @0x6900
		'trng-decls', 'trng-instance',
		# digperiphs (EVFAB): EVFAB0 in MUTEX-page (page 2) sub-slot 11 @0x6B00 + the
		# producer/consumer tap port-map lines on the FIXED-template instances (the
		# timer1/npu0 tap markers live inside their side templates, so they are spliced
		# by spliceSideBlock and never appear in the main template's seen set)
		'evfab-decls', 'evfab-instance',
		'evfab-taps:gpio0', 'evfab-taps:uart0', 'evfab-taps:timer0',
		# ... and the matching port declarations in the GPIO/UART/TIMER COMPONENT
		# declarations those four instances bind through
		'evfab-comp:gpio', 'evfab-comp:uart', 'evfab-comp:timer',
		# Mission B: GPIO4/GPIO5 in MUTEX-page (page 2) sub-slots 3/4 @0x6300/0x6400
		'gpio4-decls', 'gpio5-decls', 'gpio4-instance', 'gpio5-instance',
		# A1 N-hart regions
		'a0-ports', 'arb-fabric-decls', 'clint-irq-decls', 'meip-decl', 'pd-decls',
		'tile-raw-decls', 'sh-master-decl', 'hart0-instance', 'arb-generic', 'resv-generic',
		'clint-instance', 'irq-router-instance', 'mutex-instance', 'pwr-instance',
		'tile-rstn', 'iso-clamps', 'tile-instances',
		# CP2 (Castalia-Penta): the orchestrator hart instance. Emits NOTHING
		# without a management hart, so the N=4 golden master is untouched.
		'orch-instance',
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
