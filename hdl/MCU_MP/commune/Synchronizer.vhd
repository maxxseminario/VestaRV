library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.Constants.all;

entity Synchronizer is
	port
	(
		Clk			: in	sl;
		resetn		: in	sl;
		DIn			: in	sl;
		Sync1		: out	sl;
		Sync2		: out	sl
	);
end Synchronizer;

architecture behavioral of Synchronizer is
	
	signal Sync1_internal	: sl;
	signal Sync2_internal	: sl;
	
begin

	process (resetn, Clk) is
	begin
		if resetn = '0' then
			Sync1_internal <= '1';
			Sync2_internal <= '0';
		elsif rising_edge(Clk) then
			Sync1_internal <= not DIn;
			Sync2_internal <= not Sync1_internal;
		end if;
	end process;
	
	Sync1 <= not Sync1_internal;
	Sync2 <= Sync2_internal;

end behavioral;