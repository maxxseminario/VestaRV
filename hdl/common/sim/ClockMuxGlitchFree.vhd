library ieee;
use ieee.std_logic_1164.all;

entity DFFSQ is
	port
	(
		D	: in	std_logic;
		CK	: in	std_logic;
		SN	: in	std_logic;
		Q	: out	std_logic
	);
end DFFSQ;

architecture behavioral of DFFSQ is
	signal Q_internal	: std_logic := '1';
begin
	process (SN, CK)
	begin
		if SN = '0' then
			Q_internal <= '1';
		elsif rising_edge(CK) then
			Q_internal <= D;
		end if;
	end process;
	Q <= Q_internal;
end behavioral;

library ieee;
use ieee.std_logic_1164.all;

entity DFFRPQ is
	port
	(
		D	: in	std_logic;
		CK	: in	std_logic;
		R	: in	std_logic;
		Q	: out	std_logic
	);
end DFFRPQ;

architecture behavioral of DFFRPQ is
	signal Q_internal	: std_logic := '0';
begin
	process (R, CK)
	begin
		if R = '1' then
			Q_internal <= '0';
		elsif rising_edge(CK) then
			Q_internal <= D;
		end if;
	end process;
	Q <= Q_internal;
end behavioral;

library ieee;
use ieee.std_logic_1164.all;

entity PREICG is
	port
	(
		E	: in	std_logic;
		SE	: in	std_logic;
		CK	: in	std_logic;
		ECK	: out	std_logic
	);
end PREICG;

architecture behavioral of PREICG is
	signal ClkSync : std_logic := '0';
begin
	process (SE, CK)
	begin
		if SE = '1' then
			ClkSync <= '1';
		elsif CK = '0' then
			ClkSync <= E;
		end if;
	end process;
	ECK <= ClkSync and CK;
end behavioral;

-- Based on the design from https://www.valpont.com/2x1-and-nx1-glitch-free-clock-switching/pst/

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

-- For the TSMC cmn65gp process using the ARM standard cell library tsmc65_hvt_sc_adv10

-- This was originally set up with unconstrained ports, but NCVHDL assumed the
-- inputs were in ascending bit order while Sel was in descending bit order.
-- To avoid confusion in a critical block , explicit generic parameters are now
-- used.
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

architecture behavioral of ClockMuxGlitchFree is

	signal ClkSel	: std_logic_vector(CLK_COUNT-1 downto 0);
	signal En		: std_logic_vector(CLK_COUNT-1 downto 0);
	signal EnQ		: std_logic_vector(CLK_COUNT-1 downto 0);
	--signal EnQN		: std_logic_vector(CLK_COUNT-1 downto 0);
	signal EnQQ		: std_logic_vector(CLK_COUNT-1 downto 0);
	--signal EnQQN	: std_logic_vector(CLK_COUNT-1 downto 0);
	signal EnQQQ	: std_logic_vector(CLK_COUNT-1 downto 0);
	signal EnQQQN	: std_logic_vector(CLK_COUNT-1 downto 0);
	signal ClkGated	: std_logic_vector(CLK_COUNT-1 downto 0);
	signal resetp	: std_logic;

	component DFFSQ
		port
		(
			D	: in	std_logic;
			CK	: in	std_logic;
			SN	: in	std_logic;
			Q	: out	std_logic
		);
	end component;

	component DFFRPQ
		port
		(
			D	: in	std_logic;
			CK	: in	std_logic;
			R	: in	std_logic;
			Q	: out	std_logic
		);
	end component;

	component PREICG
		port
		(
			E	: in	std_logic;
			SE	: in	std_logic;
			CK	: in	std_logic;
			ECK	: out	std_logic
		);
	end component;

begin
	
	-- Reset positive logic line
	resetp <= not resetn;
	
	-- All synchronization slice outputs are ORed together to get final clock.
	-- This used VHDL 2008 syntax.
	ClkOut <= or_reduce(ClkGated);

	-- Enable a given clock if it is selected or if its enable signal hasn't
	-- cleared the synchronization DFF chain.
	ClkEn <= En or EnQQQ;

	-- Create enable signals based on enabled status of all clock outputs.  AND
	-- together the "not enabled" signals of all other slices with this slice's
	-- "enable" signal.
	process (ClkSel, EnQQQN)
		variable temp : std_logic;
	begin
		for i in 0 to CLK_COUNT-1 loop
			temp := '1';
			for j in 0 to CLK_COUNT-1 loop
				if j /= i then
					temp := temp and EnQQQN(j);
				end if;
			end loop;
			En(i) <= ClkSel(i) and temp;
		end loop;
	end process;

	-- Create clock source select decoder.
	process (Sel)
	begin
		ClkSel <= (others=>'0');
		ClkSel(to_integer(unsigned(Sel))) <= '1';
	end process;

	-- Generate inverted outputs of all DFFs
	--EnQN   <= not EnQ;
	--EnQQN  <= not EnQQ;
	EnQQQN <= not EnQQQ;

	-- Generate the synchronization slices.  The default slice is selected/set
	-- on reset, while the other slices are deselected/reset on reset.  Note
	-- the ARM 65 nm cells are not entirely symmetric between set/reset.  Set
	-- is active low while reset is active high.

	MuxGen: for i in 0 to CLK_COUNT-1 generate

		DefaultSlice: if i = CLK_DEFAULT generate

			SYNCDFF0: DFFSQ
			port map
			(
				D  => En(i),
				CK => ClkIn(i),
				SN => resetn,
				Q  => EnQ(i)
			);

			SYNCDFF1: DFFSQ
			port map
			(
				D  => EnQ(i),
				CK => ClkIn(i),
				SN => resetn,
				Q  => EnQQ(i)
			);

			-- This delays the enable signal by one clock, which ensures that the
			-- current clock is no longer oscillating when the next clock is
			-- enabled.  This overcomes the small 1/2 cycle lag between the
			-- enabling being deasserted and the clock gate stopping oscillation.
			-- This also keep the chip-level oscillator powered long enough to
			-- drive the clock mux.

			DLYDFF0: DFFSQ
			port map
			(
				D  => EnQQ(i),
				CK => ClkIn(i),
				SN => resetn,
				Q  => EnQQQ(i)
			);

		end generate;

		OtherSlice: if i /= CLK_DEFAULT generate

			SYNCDFF0: DFFRPQ
			port map
			(
				D  => En(i),
				CK => ClkIn(i),
				R  => resetp,
				Q  => EnQ(i)
			);

			SYNCDFF1: DFFRPQ
			port map
			(
				D  => EnQ(i),
				CK => ClkIn(i),
				R  => resetp,
				Q  => EnQQ(i)
			);

			-- This delays the enable signal by one clock, which ensures that the
			-- current clock is no longer oscillating when the next clock is
			-- enabled.  This overcomes the small 1/2 cycle lag between the
			-- enabling being deasserted and the clock gate stopping oscillation.
			-- This also keeps the chip-level oscillator powered long enough to
			-- drive the clock mux.

			DLYDFF0: DFFRPQ
			port map
			(
				D  => EnQQ(i),
				CK => ClkIn(i),
				R  => resetp,
				Q  => EnQQQ(i)
			);

		end generate;

		CG1: PREICG
		port map
		(
			E   => EnQQ(i),
			SE  => '0',
			CK  => ClkIn(i),
			ECK => ClkGated(i)
		);

	end generate;

end behavioral;
