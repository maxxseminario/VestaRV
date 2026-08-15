library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity ClkGate is
	port
	(
		ClkIn	: in	std_logic;
		En		: in	std_logic;
		ClkOut	: out	std_logic
	);
end ClkGate;

-- Behavioral clock gate: qualifies ClkIn with En without emitting a runt pulse.
-- For simulation and FPGA design ONLY, synthesis infers the technology gating cell.

architecture behavioral of ClkGate is

	signal ClkSync : std_logic;

begin
	
	-- Level-sensitive latch: En is sampled only while ClkIn is low, so it never moves near the active edge.
	process (ClkIn, En)
	begin
		if ClkIn = '0' then
			ClkSync <= En;
		end if;
	end process;
	
	-- Gated output: the latched enable passes the high phase of ClkIn through whole or not at all.
	ClkOut <= ClkSync and ClkIn;
	
end behavioral;
