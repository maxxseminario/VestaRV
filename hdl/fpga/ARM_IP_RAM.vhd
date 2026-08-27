/* FPGA stand-ins for the single-port SRAM macros, written so Vivado infers block RAM.
   The simulation model in hdl/common/sim/ARM_IP_RAM.vhd is close to synthesizable already, but it clears the whole array asynchronously while PGEN is high.
   No block RAM can do that, so a tool given that model builds the memory out of distributed RAM and flip-flops instead, and a design with 64 KiB of shared memory and an 8 KiB tile memory does not fit that way on a small part.
   Dropping the PGEN clear is the whole difference. */

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use std.textio.all;

entity ARM_IP_RAM is
	generic
	(
		AddressBits		: integer range 1 to 32 := 12;	-- 2**AddressBits words of 32 bits
		DefaultBitValue	: std_logic := '0';				-- power-up value of every bit
		INIT_FILE		: string := ""					-- optional .rcf preload, empty means fill with DefaultBitValue
	);
	port
	(
		Q		: out	std_logic_vector(31 downto 0);
		CLK		: in	std_logic;
		CEN		: in	std_logic;
		WEN		: in	std_logic_vector(3 downto 0);
		A		: in	std_logic_vector(AddressBits - 1 downto 0);
		D		: in	std_logic_vector(31 downto 0);
		EMA		: in	std_logic_vector(2 downto 0);
		GWEN	: in	std_logic;
		RETN	: in	std_logic;
		PGEN	: in	std_logic
	);
end ARM_IP_RAM;

architecture fpga of ARM_IP_RAM is

	type memoryt is array (0 to 2**AddressBits - 1) of std_logic_vector(31 downto 0);

	-- Same loader and same image format as the ROM model, so a preloaded RAM and a ROM cannot drift apart in how they read a file.
	impure function init_mem(fname : string) return memoryt is
		variable m		: memoryt := (others => (others => DefaultBitValue));
		file f			: text;
		variable status	: file_open_status;
		variable l		: line;
		variable bv		: bit_vector(31 downto 0);
		variable i		: integer := 0;
	begin
		if fname = "" then
			return m;
		end if;
		file_open(status, f, fname, read_mode);
		if status /= open_ok then
			report "ARM_IP_RAM: could not open INIT_FILE '" & fname & "'" severity warning;
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

	signal mem : memoryt := init_mem(INIT_FILE);
	signal AdrLat : std_logic_vector(AddressBits - 1 downto 0) := (others => '0');

begin

	/* RETN and PGEN are ignored, and EMA has no meaning outside the compiled macro.
	   Retention and power gating are properties of the silicon macro; on this target the contents survive whatever the power controller asks for, so firmware that powers a bank down and expects it to come back cleared will see stale data instead.
	   That difference is worth knowing before trusting a MEMPWRCR sequence measured here. */
	Q <= mem(conv_integer(AdrLat));

	-- Registered address with byte-wide write enables, which is the shape Vivado maps onto a byte-write-enabled block RAM.
	process (CLK)
	begin
		if rising_edge(CLK) then
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

end fpga;


library ieee;
use ieee.std_logic_1164.all;
library work;

-- 4096 x 32, the macro the four shared memory banks instantiate.
entity sram1p16k_hvt_pg is
	generic
	(
		INIT_FILE : string := ""
	);
	port
	(
		Q		: out	std_logic_vector(31 downto 0);
		CLK		: in	std_logic;
		CEN		: in	std_logic;
		WEN		: in	std_logic_vector(3 downto 0);
		A		: in	std_logic_vector(11 downto 0);
		D		: in	std_logic_vector(31 downto 0);
		EMA		: in	std_logic_vector(2 downto 0);
		GWEN	: in	std_logic;
		RETN	: in	std_logic;
		PGEN	: in	std_logic
	);
end sram1p16k_hvt_pg;

architecture fpga of sram1p16k_hvt_pg is
begin
	RAM: entity work.ARM_IP_RAM
	generic map
	(
		AddressBits	=> 12,
		INIT_FILE	=> INIT_FILE
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
end fpga;


library ieee;
use ieee.std_logic_1164.all;
library work;

-- 2048 x 32, the macro a hart tile instantiates for its TCM at the default tcmSizePerHart.
entity sram1p8k_hvt_pg is
	port
	(
		Q		: out	std_logic_vector(31 downto 0);
		CLK		: in	std_logic;
		CEN		: in	std_logic;
		WEN		: in	std_logic_vector(3 downto 0);
		A		: in	std_logic_vector(10 downto 0);
		D		: in	std_logic_vector(31 downto 0);
		EMA		: in	std_logic_vector(2 downto 0);
		GWEN	: in	std_logic;
		RETN	: in	std_logic;
		PGEN	: in	std_logic
	);
end sram1p8k_hvt_pg;

architecture fpga of sram1p8k_hvt_pg is
begin
	RAM: entity work.ARM_IP_RAM
	generic map
	(
		AddressBits		=> 11,
		DefaultBitValue	=> '0'
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
end fpga;
