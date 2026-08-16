library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity CRC16 is
	generic
	(
		POLYNOMIAL	: std_logic_vector(15 downto 0) := X"C857"
	);
	port
	(
		DataIn	: in	std_logic_vector(7 downto 0);
		CrcOld	: in	std_logic_vector(15 downto 0);
		CrcOut	: out	std_logic_vector(15 downto 0)
	);
end CRC16;

architecture behavioral of CRC16 is
	-- Default configuration is the CRC16_CDMA2000 standard: polynomial 0xC857, initial CRC 0xFFFF, final XOR 0x0000, no reflection.
	-- The caller feeds the initial value in through CrcOld; data reflection and a nonzero final XOR are not supported.
begin

	-- Combinational byte-wide CRC step: eight LFSR shifts per input byte.
	process (CrcOld, DataIn)
		variable LFSR	: std_logic_vector(15 downto 0);
	begin
		-- Fold the new byte into the high half of the running CRC.
		LFSR := (CrcOld(15 downto 8) xor DataIn) & CrcOld(7 downto 0);

		for i in 0 to 7 loop
			-- Shift left, and subtract the polynomial whenever the bit shifted out was set.
			if LFSR(15) = '1' then
				LFSR := (LFSR(14 downto 0) & '0') xor POLYNOMIAL;
			else
				LFSR := (LFSR(14 downto 0) & '0');
			end if;
		end loop;

		CrcOut <= LFSR;
	end process;

end behavioral;