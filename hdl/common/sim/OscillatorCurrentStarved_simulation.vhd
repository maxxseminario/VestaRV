-- Simulation-only behavioral models of the current-starved ring oscillator and the identical DCO wrapper.
-- The real cells are analog macros, so these stand in for them during behavioral runs and must never be synthesized.
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
	-- Frequency step per Freq code, in Hz, so code 0 is the slowest setting.
	constant freqPerIncrement : integer := 29300;
	
	signal ClkDCO		: sl;
	signal EnClkDCO		: sl;
	signal ClkDCODelay	: time := (0.5 sec) / (1 * freqPerIncrement);
begin
	
	-- Translate the Freq code into a half-period delay.
	ProcClkDCODelay: process(Freq)
	begin
		ClkDCODelay <= (0.5 sec) / ((slv2uint(Freq) + 1) * freqPerIncrement);
	end process;
	
	-- Free-running square wave: the oscillator core never stops, only its output gate does.
	ProcClkDCO: process
	begin
		ClkDCO <= '0';
		wait for ClkDCODelay;
		ClkDCO <= '1';
		wait for ClkDCODelay;
	end process;

	-- Reset wins over En, so the output is quiet while the block is held in reset.
	EnClkDCO <= En and (not Reset);

	-- Glitch-free gate on the way out, matching the real cell's enable behaviour.
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

-- DCO is the same oscillator model under the name the rest of the design instantiates.
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
	-- Frequency step per Freq code, in Hz, so code 0 is the slowest setting.
	constant freqPerIncrement : integer := 29300;
	
	signal ClkDCO		: sl;
	signal EnClkDCO		: sl;
	signal ClkDCODelay	: time := (0.5 sec) / (1 * freqPerIncrement);
begin
	
	-- Translate the Freq code into a half-period delay.
	ProcClkDCODelay: process(Freq)
	begin
		ClkDCODelay <= (0.5 sec) / ((slv2uint(Freq) + 1) * freqPerIncrement);
	end process;
	
	-- Free-running square wave: the oscillator core never stops, only its output gate does.
	ProcClkDCO: process
	begin
		ClkDCO <= '0';
		wait for ClkDCODelay;
		ClkDCO <= '1';
		wait for ClkDCODelay;
	end process;

	-- Reset wins over En, so the output is quiet while the block is held in reset.
	EnClkDCO <= En and (not Reset);

	-- Glitch-free gate on the way out, matching the real cell's enable behaviour.
	CG0: entity work.ClkGate
	port map
	(
		ClkIn	=> ClkDCO,
		En		=> EnClkDCO,
		ClkOut	=> ClkOut
	);
end behavioral;
