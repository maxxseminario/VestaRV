library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.Constants.all;

entity SynchronizerSLV is
	generic
	(
		num_bits	: natural
	);
	port
	(
		Clk			: in	sl;
		resetn		: in	sl;
		DIn			: in	slv(num_bits - 1 downto 0);
		Sync1		: out	slv(num_bits - 1 downto 0);
		Sync2		: out	slv(num_bits - 1 downto 0)
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