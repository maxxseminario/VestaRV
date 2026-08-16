/* Behavioral stand-in for the PowerOnResetCheng analog macro, for simulation only.
   The real macro holds resetn_out low until the supply has risen; there is no supply to watch in a digital sim, so the model is a straight pass-through and the testbench owns the reset shape.
   Never compile this file into a synthesis or P&R flow: those must bind the real macro. */

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
	-- Pass the external reset straight through, with no POR delay modelled.
	resetn_out <= resetn_in;
end behavioral;