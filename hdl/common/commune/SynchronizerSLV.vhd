-- Vector wrapper around the two-flop Synchronizer: one independent synchronizer per bit.
-- Per-bit synchronization gives no guarantee that the bits arrive in the same clock cycle, so use this only for signals whose bits are independent, never for a multi-bit value that must stay coherent.
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.Constants.all;

entity SynchronizerSLV is
	generic
	(
		num_bits	: natural   -- width of the vector to synchronize
	);
	port
	(
		Clk			: in	sl;
		resetn		: in	sl;
		DIn			: in	slv(num_bits - 1 downto 0);   -- asynchronous input vector
		Sync1		: out	slv(num_bits - 1 downto 0);   -- after the first flop, metastable, for edge detection only
		Sync2		: out	slv(num_bits - 1 downto 0)    -- after the second flop, safe to use
	);
end SynchronizerSLV;

architecture behavioral of SynchronizerSLV is
	
	component Synchronizer is
		port
		(
			Clk			: in	sl;
			resetn		: in	sl;
			DIn			: in	sl;
			Sync1		: out	sl;
			Sync2		: out	sl
		);
	end component;
	
begin

	-- One two-flop synchronizer per bit.
	SyncGen : for i in 0 to num_bits - 1 generate
	begin
		Sync : Synchronizer
		port map
		(
			Clk			=> Clk,
			resetn		=> resetn,
			DIn			=> DIn(i),
			Sync1		=> Sync1(i),
			Sync2		=> Sync2(i)
		);
	end generate;

end behavioral;