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
	-- Default uses CRC16_CDMA2000 standard (polynomial = 0xC857, initial CRC value = 0xFFFF, no final XOR (= 0x0000), no data reflection, no output reflection)
	-- You need to feed the initial value into CrcOld manually
	-- Does not support input data reflection
	-- Does not support output data reflection
	-- Does not support final output XOR
begin

	process (CrcOld, DataIn)
		variable LFSR	: std_logic_vector(15 downto 0);
	begin
		LFSR := (CrcOld(15 downto 8) xor DataIn) & CrcOld(7 downto 0);

		for i in 0 to 7 loop
			if LFSR(15) = '1' then
				LFSR := (LFSR(14 downto 0) & '0') xor POLYNOMIAL;
			else
				LFSR := (LFSR(14 downto 0) & '0');
			end if;
		end loop;

		CrcOut <= LFSR;
	end process;

end behavioral;