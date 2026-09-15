-- VestaRV: FPGA stand-in for the glitch-free clock multiplexer
-- The ASIC cell in hdl/common/sim/ClockMuxGlitchFree.vhd is a break-before-make mux built from three ARM cells per slice: two synchronizing flip-flops, a delay flip-flop and a PREICG gate, ALL CLOCKED BY THAT SLICE'S OWN ClkIn. On an FPGA that structure is what makes the clock budget fail, because every input becomes a clock net whether it is selected or not. SYSTEM.vhd feeds the two divider muxes from fourteen ripple-counter taps, and the ASIC mux turns all fourteen into flop clock pins for a design that can only ever run one of them.
-- This version puts the interlock in fabric and the multiplexing in ONE clock buffer: the select is registered on the reference slice's clock, decoded one-hot, and used to AND-OR the inputs into a single ClkBuf. The fourteen taps become ordinary data nets and the instance costs one global buffer instead of CLK_COUNT clock nets.
--
-- WHAT IS LOST, stated once and not hedged: this mux is NOT glitch-free across asynchronous sources. The registered select changes on a reference-clock edge, so an unrelated input that happens to be high at that instant contributes a runt to ClkOut.
--   * The two DIVIDER muxes are safe as drawn: every ClkIn is a tap of ClkIn(0), the taps settle on ClkIn(0) edges and the select register samples on the opposite phase to the tap counter, so the switch lands where all inputs are stable.
--   * The three SOURCE muxes (SYSTEM's smclk and mclk source muxes, TIMER's) select between genuinely asynchronous oscillators, and a source switch there can emit one short pulse. On this target a clock-source change must be made with the consumers held in reset. hdl/fpga/README.md carries this alongside the other things these cells do not model.
-- A break-before-make mux out of BUFGMUX_CTRL would cost CLK_COUNT-1 buffers, which is 7 for each divider mux and 21 buffers for the five instances in fpga_default: the whole budget, to protect a switch the software model already forbids at speed.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Port widths come from generics rather than being unconstrained, and the generic list is the ASIC cell's verbatim: this file replaces that one in a file list, so the two entities must be interchangeable.
entity ClockMuxGlitchFree is
	generic
	(
		CLK_COUNT	: natural;
		SEL_WIDTH	: natural;
		CLK_DEFAULT	: natural
	);
	port
	(
		resetn	: in	std_logic;
		Sel		: in	std_logic_vector(SEL_WIDTH-1 downto 0);
		ClkIn	: in	std_logic_vector(CLK_COUNT-1 downto 0);
		ClkEn	: out	std_logic_vector(CLK_COUNT-1 downto 0);
		ClkOut	: out	std_logic
	);
end ClockMuxGlitchFree;

architecture fpga of ClockMuxGlitchFree is

	-- One-hot vector with bit n set, used for the reset value of the select register.
	function OneHot(n : natural; w : natural) return std_logic_vector is
		variable r : std_logic_vector(w-1 downto 0) := (others => '0');
	begin
		r(n) := '1';
		return r;
	end function;

	constant SelReset	: std_logic_vector(CLK_COUNT-1 downto 0) := OneHot(CLK_DEFAULT, CLK_COUNT);

	signal RefClk	: std_logic;                                    -- the slice whose clock times the select change
	signal SelReq	: std_logic_vector(CLK_COUNT-1 downto 0);       -- combinational one-hot decode of Sel
	signal SelQ		: std_logic_vector(CLK_COUNT-1 downto 0) := SelReset;
	signal SelQQ	: std_logic_vector(CLK_COUNT-1 downto 0) := SelReset;
	signal Muxed	: std_logic;

begin

	-- The default slice is the one running out of reset, so it is the slice that is guaranteed to be clocking when a select change arrives. For the divider muxes it is also the undivided clock every other input is derived from.
	RefClk <= ClkIn(CLK_DEFAULT);

	-- Clock source select decoder: one-hot SelReq from the binary Sel input. An out-of-range code parks on the default rather than indexing off the end, which the ASIC cell does not guard because its Sel width always matches its slice count.
	process (Sel)
		variable idx : natural;
	begin
		SelReq <= (others => '0');
		idx := to_integer(unsigned(Sel));
		if idx < CLK_COUNT then
			SelReq(idx) <= '1';
		else
			SelReq(CLK_DEFAULT) <= '1';
		end if;
	end process;

	-- Two stages, so a select written in the bus domain is resynchronized before it reaches the mux and a metastable first stage cannot steer the AND-OR tree.
	process (resetn, RefClk)
	begin
		if resetn = '0' then
			SelQ  <= SelReset;
			SelQQ <= SelReset;
		elsif rising_edge(RefClk) then
			SelQ  <= SelReq;
			SelQQ <= SelQ;
		end if;
	end process;

	-- Enable a given source while it is requested OR while it is still the one being multiplexed out, which is the ASIC cell's `En or EnQQQ` and is what keeps the outgoing clock alive until the mux has left it.
	ClkEn <= SelReq or SelQQ;

	-- One-hot AND-OR: at most one term is ever live, so this is a mux.
	process (SelQQ, ClkIn)
		variable acc : std_logic;
	begin
		acc := '0';
		for i in 0 to CLK_COUNT-1 loop
			acc := acc or (SelQQ(i) and ClkIn(i));
		end loop;
		Muxed <= acc;
	end process;

	-- The single point where a fabric-driven clock enters the global clock network. This instance is what an XDC writes CLOCK_DEDICATED_ROUTE and create_generated_clock against.
	ob : entity work.ClkBuf
		port map
		(
			ClkIn  => Muxed,
			ClkOut => ClkOut
		);

end fpga;
