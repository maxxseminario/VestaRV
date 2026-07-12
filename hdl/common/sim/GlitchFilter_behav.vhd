library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.Constants.all;

entity GlitchFilter is
	port
	(
		IrqGlitchy		: in	std_logic_vector(31 downto 0);
		IrqDeglitched	: out	std_logic_vector(31 downto 0)
	);
end GlitchFilter;

architecture behavioral of GlitchFilter is
	constant minPulseWidth : time := 2 ns;
begin
	IrqDeglitched <= IrqGlitchy;
end behavioral;