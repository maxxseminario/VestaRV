/* FPGA stand-in for the boot ROM macro, built to infer a block RAM initialized from the boot ROM image.
   The simulation model in hdl/common/sim/ARM_IP_ROM.vhd loads its array from a process that runs at time zero, which synthesis cannot do, and it hardcodes an absolute path to the image.
   This version loads the same .rcf file from a constant initializer, which Vivado evaluates during elaboration, and takes the path as a generic so the image can move without editing RTL. */

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use std.textio.all;

entity rom_hvt_pg is
	generic
	(
		AddressBits	: integer range 1 to 32 := 12;	-- 2**AddressBits words of 32 bits
		InitFile	: string := "rom.rcf"			-- one 32-bit binary word per line, line N is word N
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

architecture fpga of rom_hvt_pg is

	type memoryt is array (0 to 2**AddressBits - 1) of std_logic_vector(31 downto 0);

	/* Words past the end of the image read as zero, which is what an unprogrammed word of the fabricated part reads as.
	   A missing file is a warning rather than an error so that a synthesis run still completes and says why the ROM is blank, instead of failing with an elaboration error that names only the function. */
	impure function init_rom(fname : string) return memoryt is
		variable m		: memoryt := (others => (others => '0'));
		file f			: text;
		variable status	: file_open_status;
		variable l		: line;
		variable bv		: bit_vector(31 downto 0);
		variable i		: integer := 0;
	begin
		file_open(status, f, fname, read_mode);
		if status /= open_ok then
			report "rom_hvt_pg: could not open InitFile '" & fname & "', the boot ROM will read as all zeros" severity warning;
			return m;
		end if;
		while (not endfile(f)) and (i < m'length) loop
			readline(f, l);
			read(l, bv);
			m(i) := to_stdlogicvector(bv);
			i := i + 1;
		end loop;
		file_close(f);
		return m;
	end function;

	constant mem : memoryt := init_rom(InitFile);

	signal AdrLat : std_logic_vector(AddressBits - 1 downto 0) := (others => '0');

begin

	/* PGEN is ignored here on purpose.
	   The simulation model drives Q to all 'X' while the macro is power gated, which is how an unpowered macro reads on silicon, but there is nothing to power gate on an FPGA and an 'X' would only propagate into logic that has no way to recover from it. */
	Q <= mem(conv_integer(AdrLat));

	-- Registered address, combinational read: the pattern Vivado maps onto a block RAM with the output taken from the array rather than a second register stage.
	process (CLK)
	begin
		if rising_edge(CLK) then
			if CEN = '0' then
				AdrLat <= A;
			end if;
		end if;
	end process;

end fpga;


library ieee;
use ieee.std_logic_1164.all;

/* The 2048 x 32 boot ROM, the macro the MCU instantiates at rom0.
   The generated MCU.vhd binds this entity with no generic map, so InitFile has to carry a default that resolves for the tool's working directory.
   Pass it explicitly from the top level, or from a synthesis generic, if the image lives anywhere else. */
entity rom2k_hvt_pg is
	generic
	(
		InitFile : string := "rom.rcf"
	);
	port
	(
		Q		: out	std_logic_vector(31 downto 0);
		CLK		: in	std_logic;
		CEN		: in	std_logic;
		A		: in	std_logic_vector(10 downto 0);
		EMA		: in	std_logic_vector(2 downto 0);
		PGEN	: in	std_logic
	);
end rom2k_hvt_pg;

architecture fpga of rom2k_hvt_pg is
begin
	rom: entity work.rom_hvt_pg
		generic map (
			AddressBits	=> 11,
			InitFile	=> InitFile
		)
		port map (
			Q		=> Q,
			CLK		=> CLK,
			CEN		=> CEN,
			A		=> A,
			EMA		=> EMA,
			PGEN	=> PGEN
		);
end fpga;
