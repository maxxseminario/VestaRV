library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.Constants.all;

entity PowerOnResetCheng is
	port
	(
		resetn_in	: in	sl;
		resetn_out	: out	sl
	);
end PowerOnResetCheng;

architecture behavioral of PowerOnResetCheng is
begin
	resetn_out <= resetn_in;
end behavioral;