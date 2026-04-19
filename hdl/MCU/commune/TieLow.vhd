library ieee;
use ieee.std_logic_1164.all;


entity TieLow is
	port
	(
		Zero	: out	std_logic
	);
end TieLow;

architecture behavioral of TieLow is
	
begin

	Zero <= '0';

end behavioral;