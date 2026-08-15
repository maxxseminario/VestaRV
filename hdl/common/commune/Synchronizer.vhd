-- Two-flop clock-domain-crossing synchronizer for a single bit.
-- Sync1 is the first stage and may still be metastable; only Sync2 is safe to use as data.
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
		DIn			: in	sl;   -- asynchronous input
		Sync1		: out	sl;   -- first stage, may be metastable, useful only for edge detection
		Sync2		: out	sl    -- second stage, safe to use
	);
end Synchronizer;

architecture behavioral of Synchronizer is
	
	-- Stage 1 stores the INVERTED input and stage 2 re-inverts it, so both outputs leave reset at '0'.
	signal Sync1_internal	: sl;
	signal Sync2_internal	: sl;
	
begin

	-- Two-stage shift register with asynchronous reset.
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
	
	-- Undo the stage-1 inversion on the way out.
	Sync1 <= not Sync1_internal;
	Sync2 <= Sync2_internal;

end behavioral;