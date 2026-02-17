library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use STD.standard.all;
use STD.textio.all;
use STD.textio;

entity rom_hvt_pg is
	generic
	(
		AddressBits	: integer range 1 to 32 := 12	-- Corresponds to 2^AddressBits total words (or 2^(AddressBits + 2) bytes)
	);
	port
	(
		Q		: out	std_logic_vector(31 downto 0);
		CLK		: in	std_logic;
		CEN		: in	std_logic;
		A		: in	std_logic_vector(AddressBits - 1 downto 0);
		EMA		: in	std_logic_vector(2 downto 0);
		PGEN	: in	std_logic
	);
end rom_hvt_pg;

architecture Behavioral of rom_hvt_pg is
	type memoryt is array (0 to 2**AddressBits - 1) of STD_LOGIC_VECTOR(31 downto 0);
	signal mem : memoryt;
	signal AdrLat : STD_LOGIC_VECTOR (AddressBits - 1 downto 0);
begin
	read_file: process	-- read file (one time at start of simulation)
		file ROM_File : TEXT open READ_MODE is "/home/mseminario2/chips/myshkin/ip/rom_hvt_pg/rom_hvt_pg_verilog.rcf";	-- Expects a symlink in the simulation run directory
		variable ROM_File_line : LINE;
		variable i : integer;
		variable GOOD : boolean;
		variable data : BIT_VECTOR(31 downto 0);
		variable STD_Data : STD_LOGIC_VECTOR(31 downto 0);
	begin
		i := 0;
		loop
			exit when endfile(ROM_File);
			readline(ROM_File, ROM_File_line);

			read(ROM_File_line, data, GOOD);
			for j in 31 downto 0 loop
				if data(j) = '1' then
					STD_Data(j) := '1';
				else
					STD_Data(j) := '0';
				end if;
			end loop;
			mem(i) <= STD_Data;
			i := i + 1;
		end loop;
		wait; -- one shot at time zero,
	end process read_file;

	Q <= mem(conv_integer(AdrLat)) when PGEN = '0' else (others => 'X');
	process(CLK)
	begin
		if rising_edge(CLK) then
			if CEN = '0' then
				AdrLat <= A;
			end if;
		end if;
	end process;
end Behavioral;


