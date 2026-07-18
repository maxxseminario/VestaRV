library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.Constants.all;

entity OscillatorCurrentStarved is
	port
	(
		Reset	: in	sl;
		En		: in	sl;
		Freq	: in	slv(11 downto 0);
		ClkOut	: out	sl
	);
end OscillatorCurrentStarved;

architecture behavioral of OscillatorCurrentStarved is
	constant freqPerIncrement : integer := 29300;
	
	signal ClkDCO		: sl;
	signal EnClkDCO		: sl;
	signal ClkDCODelay	: time := (0.5 sec) / (1 * freqPerIncrement);
begin
	
	ProcClkDCODelay: process(Freq)
	begin
		ClkDCODelay <= (0.5 sec) / ((slv2uint(Freq) + 1) * freqPerIncrement);
	end process;
	
	ProcClkDCO: process
	begin
		ClkDCO <= '0';
		wait for ClkDCODelay;
		ClkDCO <= '1';
		wait for ClkDCODelay;
	end process;

	EnClkDCO <= En and (not Reset);

	CG0: entity work.ClkGate
	port map
	(
		ClkIn	=> ClkDCO,
		En		=> EnClkDCO,
		ClkOut	=> ClkOut
	);
end behavioral;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.Constants.all;

entity DCO is
	port
	(
		Reset	: in	sl;
		En		: in	sl;
		Freq	: in	slv(11 downto 0);
		ClkOut	: out	sl
	);
end DCO;

architecture behavioral of DCO is
	constant freqPerIncrement : integer := 29300;
	
	signal ClkDCO		: sl;
	signal EnClkDCO		: sl;
	signal ClkDCODelay	: time := (0.5 sec) / (1 * freqPerIncrement);
begin
	
	ProcClkDCODelay: process(Freq)
	begin
		ClkDCODelay <= (0.5 sec) / ((slv2uint(Freq) + 1) * freqPerIncrement);
	end process;
	
	ProcClkDCO: process
	begin
		ClkDCO <= '0';
		wait for ClkDCODelay;
		ClkDCO <= '1';
		wait for ClkDCODelay;
	end process;

	EnClkDCO <= En and (not Reset);

	CG0: entity work.ClkGate
	port map
	(
		ClkIn	=> ClkDCO,
		En		=> EnClkDCO,
		ClkOut	=> ClkOut
	);
end behavioral;
