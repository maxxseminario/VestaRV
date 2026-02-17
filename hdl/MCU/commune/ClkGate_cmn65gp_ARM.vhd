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

-- For the TSMC cmn65gp process using the ARM standard cell library tsmc65_hvt_sc_adv10

architecture behavioral of ClkGate is
	
	component PREICGX1BA10TH
		port
		(
			E   : in	std_logic;
			SE  : in	std_logic;
			CK  : in	std_logic;
			ECK : out	std_logic
		);
	end component;
	
begin
	
	CG1: PREICGX1BA10TH
	port map
	(
		E   => En,
		SE  => '0',
		CK  => ClkIn,
		ECK => ClkOut
	);
	
end behavioral;
