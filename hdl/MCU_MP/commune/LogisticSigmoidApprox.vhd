library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
library work;
use work.Constants.all;

entity LogisticSigmoidApprox is
	port
	(
		InputQ16_15	: in	slv(31 downto 0);
		OutputQ0_15	: out	slv(15 downto 0)
	);
end LogisticSigmoidApprox;

architecture behavioral of LogisticSigmoidApprox is
	signal NegativeInput	: slv(31 downto 0);
	signal InputIsNegative	: sl;
	signal OutOfRangeTest	: slv(30 downto 17);
	signal OutOfRange		: sl;
	signal Sel				: slv(1 downto 0);
	signal OutputInteger	: integer range 0 to 32767;
	
	--signal X	: slv(16 downto 0);	-- 17-bit unsigned integer. Range = [0, 131071]
	--signal a	: slv(14 downto 0);	-- 15-bit unsigned integer. Range = [0, 32767]
	--signal b	: slv(29 downto 0);	-- 30-bit unsigned integer. Range = [0, 1073741823]
	--signal Z	: slv(14 downto 0);	-- 15-bit unsigned integer. Range = [0, 32767]

	signal X	: slv(16 downto 0);	-- 17-bit unsigned integer. Range = [0, 131071]
	signal a	: integer range 0 to 32767;	-- 15-bit unsigned integer. Range = [0, 32767]
	signal b	: integer range 16383 to 1073692672;	-- 30-bit unsigned integer. Range = [0, 1073741823]
	signal Z	: integer range 0 to 32767;	-- 15-bit unsigned integer. Range = [0, 32767]

begin
	
	InputIsNegative <= InputQ16_15(31);	-- '0' when InputQ16_15 is positive; '1' when negative
	NegativeInput <= int2slv(-slv2int(InputQ16_15), 32);
	OutOfRangeTest <= InputQ16_15(30 downto 17) when InputIsNegative = '0' else NegativeInput(30 downto 17);
	OutOfRange <= or_reduct(OutOfRangeTest);	-- '0' if -131071 (~= -4) <= InputQ16_15 <= +131071 (~= +4); '1' otherwise
	X <= InputQ16_15(16 downto 0) when InputIsNegative = '0' else NegativeInput(16 downto 0);
	
	a <= 32767 - slv2uint(X(16 downto 2));	-- a = 32767 - (X >> 2). Range: [0, 32767]
	b <= (a * a) + 16383;	-- b = (a * a) + 16384. Range: [16384, 1073692672]
	Z <= slv2uint(uint2slv(b, 31)(30 downto 16));	-- Z = b >> 16. Range: [0, 32767]
	
	Sel <= InputIsNegative & OutOfRange;
	with Sel select OutputInteger <=
		32767 - Z	when "00",		-- Positive, in range. Returns 32767 - LogSigZ(InputQ16_15)
		32767		when "01",		-- Positive, out of range. Returns 32767 (~= +1)
		Z			when "10",		-- Negative, in range. Returns LogSigZ(-InputQ16_15)
		0			when others;	-- Negative, out of range. Returns 0

	OutputQ0_15 <= "0" & uint2slv(OutputInteger, 15);

end behavioral;
