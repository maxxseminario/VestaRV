library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use STD.standard.all;
use STD.textio.all;
use STD.textio;

entity ARM_IP_RAM is
	generic
	(
		AddressBits	: integer range 1 to 32 := 12;	-- Corresponds to 2^AddressBits total words
		DefaultBitValue : std_logic := '0'	-- The default value for every bit in the memory
	);
	port
    (
		Q		: out std_logic_vector(31 downto 0);
		CLK		: in std_logic;
		CEN		: in std_logic;
		WEN		: in std_logic_vector(3 downto 0);
		A		: in std_logic_vector(AddressBits - 1 downto 0);
		D		: in std_logic_vector(31 downto 0);
		EMA		: in std_logic_vector(2 downto 0);
		GWEN	: in std_logic;
		RETN	: in std_logic;
		PGEN	: in std_logic
	);
end ARM_IP_RAM;

architecture behavioral of ARM_IP_RAM is
	type memoryt is array (0 to 2**AddressBits - 1) of std_logic_vector(31 downto 0);
	signal mem : memoryt := (others => (others => DefaultBitValue));
	signal AdrLat : std_logic_vector(AddressBits - 1 downto 0);
begin

	Q <= mem(conv_integer(AdrLat));
	process(PGEN, CLK)
	begin
        if PGEN = '1' then
            mem <= (others => (others => DefaultBitValue));
        elsif rising_edge(CLK) then
			if CEN = '0' then
				AdrLat <= A;
				if GWEN = '0' then
					if WEN(0) = '0' then
						mem(conv_integer(A))(7 downto 0) <= D(7 downto 0);
					end if;
					if WEN(1) = '0' then
						mem(conv_integer(A))(15 downto 8) <= D(15 downto 8);
					end if;
					if WEN(2) = '0' then
						mem(conv_integer(A))(23 downto 16) <= D(23 downto 16);
					end if;
					if WEN(3) = '0' then
						mem(conv_integer(A))(31 downto 24) <= D(31 downto 24);
					end if;
				end if;
			end if;
		end if;
	end process;
end behavioral;


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library work;

entity sram1p16k_hvt_pg is
	port
    (
		Q		: out std_logic_vector(31 downto 0);
		CLK		: in std_logic;
		CEN		: in std_logic;
		WEN		: in std_logic_vector(3 downto 0);
		A		: in std_logic_vector(11 downto 0);
		D		: in std_logic_vector(31 downto 0);
		EMA		: in std_logic_vector(2 downto 0);
		GWEN	: in std_logic;
		RETN	: in std_logic;
		PGEN	: in std_logic
	);
end sram1p16k_hvt_pg;

architecture behavioral of sram1p16k_hvt_pg is
begin
	RAM: entity work.ARM_IP_RAM
	generic map
	(
		AddressBits	=> 12
	)
	port map
	(
		Q		=> Q,
		CLK		=> CLK,
		CEN		=> CEN,
		WEN		=> WEN,
		A		=> A,
		D		=> D,
		EMA		=> EMA,
		GWEN	=> GWEN,
		RETN	=> RETN,
		PGEN	=> PGEN
	);
end behavioral;




library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library work;

entity sram1p1k_hvt_pg is
	port
    (
		Q		: out std_logic_vector(31 downto 0);
		CLK		: in std_logic;
		CEN		: in std_logic;
		WEN		: in std_logic_vector(3 downto 0);
		A		: in std_logic_vector(7 downto 0);
		D		: in std_logic_vector(31 downto 0);
		EMA		: in std_logic_vector(2 downto 0);
		GWEN	: in std_logic;
		RETN	: in std_logic;
		PGEN	: in std_logic
	);
end sram1p1k_hvt_pg;

architecture behavioral of sram1p1k_hvt_pg is
begin
	RAM: entity work.ARM_IP_RAM
	generic map
	(
		AddressBits	=> 8
	)
	port map
	(
		Q		=> Q,
		CLK		=> CLK,
		CEN		=> CEN,
		WEN		=> WEN,
		A		=> A,
		D		=> D,
		EMA		=> EMA,
		GWEN	=> GWEN,
		RETN	=> RETN,
		PGEN	=> PGEN
	);
end behavioral;



library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library work;

entity sram1p4k_hvt_pg is
	port
    (
		Q		: out std_logic_vector(31 downto 0);
		CLK		: in std_logic;
		CEN		: in std_logic;
		WEN		: in std_logic_vector(3 downto 0);
		A		: in std_logic_vector(9 downto 0);
		D		: in std_logic_vector(31 downto 0);
		EMA		: in std_logic_vector(2 downto 0);
		GWEN	: in std_logic;
		RETN	: in std_logic;
		PGEN	: in std_logic
	);
end sram1p4k_hvt_pg;

architecture behavioral of sram1p4k_hvt_pg is
begin
	RAM: entity work.ARM_IP_RAM
	generic map
	(
		AddressBits	=> 10
	)
	port map
	(
		Q		=> Q,
		CLK		=> CLK,
		CEN		=> CEN,
		WEN		=> WEN,
		A		=> A,
		D		=> D,
		EMA		=> EMA,
		GWEN	=> GWEN,
		RETN	=> RETN,
		PGEN	=> PGEN
	);
end behavioral;



library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library work;

entity sram1p8k_hvt_pg is
	port
    (
		Q		: out std_logic_vector(31 downto 0);
		CLK		: in std_logic;
		CEN		: in std_logic;
		WEN		: in std_logic_vector(3 downto 0);
		A		: in std_logic_vector(10 downto 0);
		D		: in std_logic_vector(31 downto 0);
		EMA		: in std_logic_vector(2 downto 0);
		GWEN	: in std_logic;
		RETN	: in std_logic;
		PGEN	: in std_logic
	);
end sram1p8k_hvt_pg;

architecture behavioral of sram1p8k_hvt_pg is
begin
	RAM: entity work.ARM_IP_RAM
	generic map
	(
		AddressBits	=> 11,
		DefaultBitValue => '0'
	)
	port map
	(
		Q		=> Q,
		CLK		=> CLK,
		CEN		=> CEN,
		WEN		=> WEN,
		A		=> A,
		D		=> D,
		EMA		=> EMA,
		GWEN	=> GWEN,
		RETN	=> RETN,
		PGEN	=> PGEN
	);
end behavioral;
