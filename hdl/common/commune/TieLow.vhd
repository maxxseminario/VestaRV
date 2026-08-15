library ieee;
use ieee.std_logic_1164.all;


-- Constant logic-0 source used to tie off unused inputs.
entity TieLow is
	port
	(
		Zero	: out	std_logic	-- Always driven low.
	);
end TieLow;

architecture behavioral of TieLow is
	
begin

	Zero <= '0';

end behavioral;