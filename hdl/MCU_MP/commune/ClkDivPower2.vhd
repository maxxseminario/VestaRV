library ieee;
use ieee.std_logic_1164.all;
library work;
use work.Constants.all;

entity ClkDivPower2 is
	generic
	(
		nbits	: natural range 1 to 32	-- Number of bits in DivSel. Number of selections is 2^nbits (also the number of flip flops in the clock stages chain). Max clock division is 2^(2^nbits - 1) .
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

	signal EnLat			: sl;
	signal Clk				: sl;
	signal EnClk			: sl;
	signal ClkStagesFF		: slv(2**nbits - 1 downto 0);
	signal ClkStages		: slv(2**nbits - 1 downto 0);
	signal ClkDivided		: sl;
	signal DivSelInteger	: integer range 0 to 2**nbits - 1;

begin
	
	EnClk <= (En or EnLat) and resetn;
	DivSelInteger <= slv2uint(DivSel);
	
	CG0: entity work.ClkGate
	port map
	(
		ClkIn	=> ClkIn,
		En		=> EnClk,
		ClkOut	=> Clk
	);

	process (resetn, EnClk, Clk, DivSelInteger)
	begin
		if EnClk = '0' then
			ClkStagesFF <= (others => '1');
			ClkStagesFF(DivSelInteger) <= '0';
		elsif rising_edge(Clk) then
			EnLat <= En;
			if En = '1' then
				ClkStagesFF(ClkStagesFF'high downto 1) <= uint2slv(slv2uint(ClkStagesFF(ClkStagesFF'high downto 1)) + 1, 2**nbits - 1);
			end if;
		end if;

		if resetn = '0' then
			EnLat <= '0';
		end if;
	end process;

	ClkStages <= ClkStagesFF(ClkStagesFF'high downto 1) & Clk;
	ClkDivided <= ClkStages(DivSelInteger);

	CG1: entity work.ClkGate
	port map
	(
		ClkIn	=> ClkDivided,
		En		=> En,
		ClkOut	=> ClkOut
	);

end behavioral;