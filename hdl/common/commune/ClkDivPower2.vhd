/* Power-of-two clock divider.
   A ripple counter of gated stages provides every division from 1 to 2^(2^nbits - 1), and DivSel picks which stage reaches the output.
   Both the input and the output run through ClkGate cells so the divider starts and stops without glitching. */
library ieee;
use ieee.std_logic_1164.all;
library work;
use work.Constants.all;

entity ClkDivPower2 is
	generic
	(
		-- Number of bits in DivSel, so there are 2^nbits selections and the same number of flip flops in the clock-stage chain.
		nbits	: natural range 1 to 32	-- Maximum clock division is 2^(2^nbits - 1).
	);
	port
	(
		resetn	: in	sl;
		En		: in	sl;
		ClkIn	: in	sl;
		DivSel	: in	slv(nbits - 1 downto 0);
		ClkOut	: out	sl
	);
end ClkDivPower2;

architecture behavioral of ClkDivPower2 is

	signal EnLat			: sl;   -- En held one divided cycle, so the chain keeps clocking through the last stage
	signal Clk				: sl;   -- gated input clock, stage 0 of the chain
	signal EnClk			: sl;   -- enable for the input gate
	signal ClkStagesFF		: slv(2**nbits - 1 downto 0);   -- ripple-counter flops, one per division stage
	signal ClkStages		: slv(2**nbits - 1 downto 0);   -- counter bits with the gated input clock spliced in as stage 0
	signal ClkDivided		: sl;   -- the selected stage
	signal DivSelInteger	: integer range 0 to 2**nbits - 1;   -- DivSel as an index into ClkStages

begin
	
	-- EnLat keeps the counter clocked for one extra divided cycle after En drops, so the output finishes low.
	EnClk <= (En or EnLat) and resetn;
	DivSelInteger <= slv2uint(DivSel);
	
	-- Gate the incoming clock: this is the counter's clock and also the divide-by-1 stage.
	CG0: entity work.ClkGate
	port map
	(
		ClkIn	=> ClkIn,
		En		=> EnClk,
		ClkOut	=> Clk
	);

	-- Ripple counter that generates the divided stages.
	process (resetn, EnClk, Clk, DivSelInteger)
	begin
		-- Parked: preload the counter so the selected stage starts low and the first output edge is a clean rise.
		if EnClk = '0' then
			ClkStagesFF <= (others => '1');
			ClkStagesFF(DivSelInteger) <= '0';
		elsif rising_edge(Clk) then
			EnLat <= En;
			if En = '1' then
				ClkStagesFF(ClkStagesFF'high downto 1) <= uint2slv(slv2uint(ClkStagesFF(ClkStagesFF'high downto 1)) + 1, 2**nbits - 1);
			end if;
		end if;

		-- Asynchronous reset of the enable latch.
		if resetn = '0' then
			EnLat <= '0';
		end if;
	end process;

	-- Stage 0 is the gated input clock itself, so DivSel = 0 means divide by 1.
	ClkStages <= ClkStagesFF(ClkStagesFF'high downto 1) & Clk;
	ClkDivided <= ClkStages(DivSelInteger);

	-- Gate the selected stage on the way out so a disabled divider parks its output.
	CG1: entity work.ClkGate
	port map
	(
		ClkIn	=> ClkDivided,
		En		=> En,
		ClkOut	=> ClkOut
	);

end behavioral;