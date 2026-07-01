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

-- For simulation and FPGA design ONLY

architecture behavioral of ClkGate is

	signal ClkSync : std_logic;

begin
	
	process (ClkIn, En)
	begin
		if ClkIn = '0' then
			ClkSync <= En;
		end if;
	end process;
	
	ClkOut <= ClkSync and ClkIn;
	
end behavioral;
