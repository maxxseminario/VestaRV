-- VestaRV: pin multiplexer for the spare digital pads
-- NPADS bidirectional pads pmx0..pmx(NPADS-1), each taking one function out of a PER-PAD menu of at most MAXMENU entries selected by a 4-bit register nibble. The dedicated pads of every other block are untouched: this entity owns the pmx pads and nothing else.
-- A select nibble of 0 is DISABLED and is the reset value, so an unconfigured pad comes out of reset with its driver off and its pull resistor disabled rather than fighting whatever is wired to it. A code above the pad's own menu length, or above MAXMENU, reads back as written but is treated as DISABLED, so a pad can never be pointed at a function it does not carry.
-- The menu is a GENERIC, not a table in here: slot j of pad i is bit j*NPADS+i of the slot_* vectors, exactly as GPIO flattens its alternate-function planes, and the four policy vectors say what that slot's function does with the pad. The emitter in platform/common/python/mcu_vhd.py builds the vectors from the chip configuration, so this entity knows no function names.
-- Output-enable policy per function, from the generics: POL_INONLY never drives (a receiver), POL_OD drives low only and releases the pad for the external pull-up (I2C), and otherwise the function's own slot_oen_in decides (push-pull for a transmitter, direction-controlled for a GPIO mirror or a QSPI data line).
-- Input path: slot_in_out carries the pad level back to the selected function RAW, unsynchronised, because a serial input that crosses a clock domain is synchronised by the peripheral that receives it and a second chain here would only add latency. The only synchroniser in this block is the one feeding the PMXIN readback.
-- No data signal reaches a flop clock pin: clk_mem is the one clock, and the pads reach flops only through u_sync_pmx_in's D inputs.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.constants.all;
-- Word offsets, field ranges, resets and the periph_regs tables: generated from hdl/common/regs/rdl/pinmux.rdl.
use work.pinmux_regs_pkg.all;

entity PINMUX is
	generic
	(
		-- Pads this instance owns, pmx0 .. pmx(NPADS-1).
		NPADS			:		natural;

		-- Menu depth: the largest select code any pad accepts. The select field is
		-- four bits, so 15 is the ceiling; 8 is what the generator uses.
		MAXMENU			:		natural := 8;

		-- Menu LENGTH per pad, one nibble per pad (pad i at bits 4i+3 downto 4i).
		-- A select code above its pad's nibble is treated as DISABLED, which is how
		-- a pad whose menu is shorter than MAXMENU refuses the empty slots. Left at
		-- its default every pad carries the full menu.
		MENU_LEN		:		std_logic_vector := "";

		-- Per-slot function policy, flattened slot-major: slot j of pad i at bit
		-- j*NPADS+i, the same packing GPIO uses for its alternate-function planes.
		POL_INONLY		:		std_logic_vector := "";	-- the function never drives the pad (a receiver)
		POL_OD			:		std_logic_vector := "";	-- open drain: drive low only, release for the external pull-up
		POL_REN			:		std_logic_vector := "";	-- the function wants the pad's pull resistor enabled
		SLOT_IDLE		:		std_logic_vector := "";	-- what the function sees while no pad selects it

		-- Pad logic levels. The register bits are always in positive logic; these
		-- say what the pad library's terminals mean.
		PadOUTPosLogic	:		boolean := true;	-- True if driving the pad's O terminal high makes the pad output a logic high level.
		PadOENPosLogic	:		boolean := true;	-- True if driving the pad's OEN terminal high ENABLES the pad's output driver.
		PadRENPosLogic	:		boolean := true		-- True if driving the pad's REN terminal high enables the pad's pullup/pulldown resistor.
	);
	port
	(
		resetn			: in	std_logic;	-- Reset signal, active low.

		-- Memory bus.
		clk_mem			: in	std_logic;	-- Register clock, free-running.
		en				: in	std_logic;	-- Peripheral select, active low.
		wen				: in	std_logic_vector(3 downto 0);	-- Byte-lane write enables, active low.
		write_data		: in	std_logic_vector(31 downto 0);
		read_data		: out	std_logic_vector(31 downto 0);
		addr_periph		: in	std_logic_vector(7 downto 2);

		-- Pad library interface, one bit per pmx pad.
		pmx_in			: in	std_logic_vector(NPADS - 1 downto 0);	-- Pad input levels (the pad's I terminal).
		pmx_out_out		: out	std_logic_vector(NPADS - 1 downto 0);	-- Pad output levels (the pad's O terminal).
		pmx_oen_out		: out	std_logic_vector(NPADS - 1 downto 0);	-- Pad output enables (the pad's OEN terminal).
		pmx_ren_out		: out	std_logic_vector(NPADS - 1 downto 0);	-- Pad pull-resistor enables (the pad's REN terminal).

		-- The menu, flattened slot-major: slot j of pad i at bit j*NPADS+i.
		slot_out_in		: in	std_logic_vector(NPADS * MAXMENU - 1 downto 0);	-- Each slot function's desired output level.
		slot_oen_in		: in	std_logic_vector(NPADS * MAXMENU - 1 downto 0);	-- Each slot function's desired output enable, active high.
		slot_ren_in		: in	std_logic_vector(NPADS * MAXMENU - 1 downto 0);	-- Each slot function's desired pull-resistor enable.
		slot_in_out		: out	std_logic_vector(NPADS * MAXMENU - 1 downto 0);	-- The pad level returned to the selected slot, SLOT_IDLE elsewhere.

		-- Register output, so the SoC can see the selection it wired.
		PMXSEL_out		: out	std_logic_vector(4 * NPADS - 1 downto 0)
	);
end PINMUX;

architecture behavioral of PINMUX is

	-- The word layout, the same arithmetic the package's NWORDS function uses.
	-- PMXCAP is the one register at a fixed address, so it is the only word the
	-- package can name; the two variable-count groups sit above it.
	constant NINW	: natural := (NPADS + 31) / 32;		-- PMXIN words
	constant NSELW	: natural := (NPADS + 7) / 8;		-- PMXCFG words
	constant W_PMXIN0	: natural := W_PMXCAP + 1;
	constant W_PMXCFG0	: natural := W_PMXIN0 + NINW;

	constant NW		: natural := NWORDS(NPADS);
	subtype  reg_arr_t is word_array(0 to NW - 1);

	constant PMX_REV : natural := 1;	-- the PMXREV this block reports

	signal regs_q	: reg_arr_t;	-- PMXCFG storage; PMXCAP and PMXIN hold no flop here
	signal hw_rd_s	: reg_arr_t;	-- the read source for PMXCAP and the PMXIN words

	signal pmx_in_s2	: std_logic_vector(NPADS - 1 downto 0);	-- pmx_in after the house synchroniser, in the clk_mem domain
	signal sel			: std_logic_vector(4 * NPADS - 1 downto 0);	-- the select nibbles, pad i at bits 4i+3 downto 4i

	-- A generic vector left at its default is the null vector; normalise it to
	-- the width this entity indexes, with a stated fill for the absent case.
	-- POSITIONAL, leftmost to leftmost, whatever the caller's bounds, which is what
	-- hdl/common/sync.vhd's normRst does and for the same reason: a bare bit-string
	-- literal binds with ASCENDING bounds, so "100" must still mean bit 2 set.
	function normSlots(v : std_logic_vector; fill : std_logic) return std_logic_vector is
		variable r : std_logic_vector(NPADS * MAXMENU - 1 downto 0) := (others => fill);
	begin
		if v'length = NPADS * MAXMENU then
			r := v;
		end if;
		return r;
	end function;

	-- MENU_LEN defaults to the full menu on every pad, which is what a
	-- configuration that lists MAXMENU functions for each pad would pass.
	function normMenuLen(v : std_logic_vector) return std_logic_vector is
		variable r : std_logic_vector(4 * NPADS - 1 downto 0) := (others => '0');
	begin
		if v'length = 4 * NPADS then
			r := v;
		else
			for p in 0 to NPADS - 1 loop
				r((4 * p) + 3 downto 4 * p) := std_logic_vector(to_unsigned(MAXMENU, 4));
			end loop;
		end if;
		return r;
	end function;

	constant MENU_LEN_N	: std_logic_vector(4 * NPADS - 1 downto 0) := normMenuLen(MENU_LEN);
	constant INONLY_N	: std_logic_vector(NPADS * MAXMENU - 1 downto 0) := normSlots(POL_INONLY, '0');
	constant OD_N		: std_logic_vector(NPADS * MAXMENU - 1 downto 0) := normSlots(POL_OD, '0');
	constant PREN_N		: std_logic_vector(NPADS * MAXMENU - 1 downto 0) := normSlots(POL_REN, '0');
	-- An unlisted idle is '1': a released open-drain wire and an idle UART line
	-- both read high, and a receiver handed a constant '0' would see a start bit
	-- for as long as no pad selected it.
	constant IDLE_N		: std_logic_vector(NPADS * MAXMENU - 1 downto 0) := normSlots(SLOT_IDLE, '1');

	-- PMXCAP: the three numbers firmware reads instead of compiling in a copy of
	-- the configuration. Every bit is a constant, so the word is driven through
	-- hw_rd and holds no flop.
	function capWord return word is
		variable r : word := (others => '0');
	begin
		r(PMXNPADS_MSB downto PMXNPADS_LSB) := std_logic_vector(to_unsigned(NPADS, PMXNPADS_MSB - PMXNPADS_LSB + 1));
		r(PMXMENU_MSB  downto PMXMENU_LSB)  := std_logic_vector(to_unsigned(MAXMENU, PMXMENU_MSB - PMXMENU_LSB + 1));
		r(PMXREV_MSB   downto PMXREV_LSB)   := std_logic_vector(to_unsigned(PMX_REV, PMXREV_MSB - PMXREV_LSB + 1));
		return r;
	end function;

	constant CAP_WORD : word := capWord;

begin

	PMXSEL_out <= sel;

	-- The select field is four bits, which bounds the menu at 15, and PMXNPADS is
	-- eight bits, which bounds the ring at 255. periph_regs decodes a 64-word
	-- window and NW is 1 + ceil(NPADS/32) + ceil(NPADS/8), which is 41 at 255, so
	-- the pad count is the only bound that needs saying.
	assert NPADS >= 1 and NPADS <= 255
		report "PINMUX: NPADS must be 1 to 255 (PMXCAP.PMXNPADS is eight bits)"
		severity failure;
	assert MAXMENU >= 1 and MAXMENU <= 15
		report "PINMUX: MAXMENU must be 1 to 15 (a select field is one nibble)"
		severity failure;

	-- The nibble-per-pad packing is the description's, not a literal: PMXSEL0 and
	-- PMXSEL1 are adjacent nibbles of PMXCFG0, so the stride below is four.
	assert PMXSEL1_LSB - PMXSEL0_LSB = 4 and PMXSEL0_LSB = 0
		report "PINMUX: pinmux.rdl no longer packs one four-bit select field per pad"
		severity failure;

	-- The select nibbles, cut out of the PMXCFG words. Pad p is nibble p mod 8 of
	-- word W_PMXCFG0 + p/8, so a byte-lane write reconfigures exactly two pads.
	gen_sel: for p in 0 to NPADS - 1 generate
		sel((4 * p) + 3 downto 4 * p) <=
			regs_q(W_PMXCFG0 + (p / 8))((4 * (p mod 8)) + 3 downto 4 * (p mod 8));
	end generate;

	-- THE PAD MUX.
	-- One pass over the pads: decode the nibble, refuse a code the pad's menu does
	-- not reach, then apply the selected slot's policy. A refused or zero code
	-- leaves the pad high-Z with its pull disabled, which is the reset state.
	pad_mux: process(sel, slot_out_in, slot_oen_in, slot_ren_in, pmx_in)
		variable code	: natural range 0 to 15;
		variable len	: natural range 0 to 15;
		variable j		: natural range 0 to 15;
		variable b		: natural;
		variable o		: std_logic;
		variable oe		: std_logic;
		variable ren	: std_logic;
		variable live	: boolean;
	begin
		for p in 0 to NPADS - 1 loop
			code := to_integer(unsigned(sel((4 * p) + 3 downto 4 * p)));
			len  := to_integer(unsigned(MENU_LEN_N((4 * p) + 3 downto 4 * p)));
			live := (code >= 1) and (code <= len) and (code <= MAXMENU);

			-- Slot index of the selected function, clamped so the index below is
			-- in range even while the code is refused and the result discarded.
			if live then
				j := code - 1;
			else
				j := 0;
			end if;
			b := (j * NPADS) + p;

			o   := '0';
			oe  := '0';
			ren := '0';

			if live then
				ren := slot_ren_in(b) or PREN_N(b);
				if INONLY_N(b) = '1' then
					-- A receiver: the pad stays an input whatever the function drives.
					o  := '0';
					oe := '0';
				elsif OD_N(b) = '1' then
					-- Open drain: drive low on a '0', release on a '1'. The function's
					-- own output enable is not consulted, because the data IS the
					-- enable on a wired-AND bus.
					o  := '0';
					oe := not slot_out_in(b);
				else
					o  := slot_out_in(b);
					oe := slot_oen_in(b);
				end if;
			end if;

			-- Drive the pad, inverting where the pad terminal uses negative logic.
			if PadOUTPosLogic then
				pmx_out_out(p) <= o;
			else
				pmx_out_out(p) <= not o;
			end if;

			if PadOENPosLogic then
				pmx_oen_out(p) <= oe;
			else
				pmx_oen_out(p) <= not oe;
			end if;

			if PadRENPosLogic then
				pmx_ren_out(p) <= ren;
			else
				pmx_ren_out(p) <= not ren;
			end if;

			-- The input path back to the menu. The selected slot sees the pad RAW;
			-- every other slot of this pad sees its idle level, so a function no pad
			-- selects is not held at a spurious level.
			for k in 0 to MAXMENU - 1 loop
				if live and k = j then
					slot_in_out((k * NPADS) + p) <= pmx_in(p);
				else
					slot_in_out((k * NPADS) + p) <= IDLE_N((k * NPADS) + p);
				end if;
			end loop;
		end loop;
	end process;

	-- The pad NEVER reaches a clock pin, and the readback is a flop's value and
	-- not the live pad: pmx_in crosses into clk_mem through the house
	-- synchroniser, so PMXIN is the pad as it was two clk_mem edges before the
	-- access. A pulse shorter than one clk_mem period is not captured, which is
	-- what a readback register is for and not a receiver. The FUNCTIONAL input
	-- path above does not pass through here.
	u_sync_pmx_in : entity work.sync
		generic map (WIDTH => NPADS, DEPTH => 2)
		port map (clk => clk_mem, areset => resetn, d => pmx_in, q => pmx_in_s2);

	-- Register Memory Interface ----------
	-- One periph_regs instance carrying pinmux_regs_pkg's tables, which are
	-- functions of NPADS because the register SET is (hdl/common/regs/REGFILE.md,
	-- "A register set that is a function of a generic").
	-- STROBE_HOLD is FALSE and no strobe is consumed: this block has no command
	-- word. Every select nibble is plain storage and takes effect combinationally.
	u_regs: entity work.periph_regs
		generic map (
			NWORDS      => NW,
			RSTVAL      => RSTVAL(NPADS),
			IMPL        => IMPL(NPADS),
			W1C         => W1C(NPADS),
			WOSET       => WOSET(NPADS),
			WOT         => WOT(NPADS),
			PULSE       => PULSE(NPADS),
			RCLR        => RCLR(NPADS),
			HWOWN       => HWOWN(NPADS),
			STROBE_HOLD => false)
		port map (
			ClkMem      => clk_mem,
			resetn      => resetn,
			EnMemPeriph => en,
			WEn         => wen,
			MABPart     => addr_periph,
			wdata       => write_data,
			rdata_out   => read_data,
			regs        => regs_q,
			hw_rd       => hw_rd_s,
			acc_hit     => open,
			rd_hit      => open,
			wr_hit      => open,
			rd_strobe   => open,
			wr_strobe   => open,
			wr_pulse    => open,
			w1c_hit     => open,
			woset_hit   => open,
			wot_hit     => open,
			rd_clr      => open);

	-- The words that hold no flop here. PMXCAP is three constants; each PMXIN word
	-- is 32 bits of the synchronised pad vector, and the bits above the pad count
	-- read 0, which is what the description says they do.
	read_src: process(pmx_in_s2)
		variable lo : natural;
	begin
		hw_rd_s <= (others => (others => '0'));
		hw_rd_s(W_PMXCAP) <= CAP_WORD;
		for k in 0 to NINW - 1 loop
			lo := 32 * k;
			for b in 0 to 31 loop
				if lo + b <= NPADS - 1 then
					hw_rd_s(W_PMXIN0 + k)(b) <= pmx_in_s2(lo + b);
				end if;
			end loop;
		end loop;
	end process;

end behavioral;
