-- VestaRV: FPGA stand-in for the power-of-two clock divider
-- The ASIC cell in hdl/common/commune/ClkDivPower2.vhd is a ripple chain of gated stages: an input ClkGate, a counter clocked by it, a fabric mux over the counter bits, and an output ClkGate. Three of those four nets are clocks, and two of them are clocks nothing outside the cell can constrain.
-- This version is the same divider written the way the brief asks for: ONE enable-qualified counter on the undivided clock, and one clock buffer. ClkOut carries a rising edge once every 2^DivSel cycles of ClkIn, so a consumer that counts rising edges sees the identical edge rate; what it no longer sees is a 50 per cent duty cycle. I2C0 is the only consumer in the tree (I2C.vhd:354 -> ClkMaster), its master FSM reads ClkMaster only as `rising_edge`, and it derives SCL by toggling on those edges, so SCL frequency and duty are unchanged.
-- Cost: 1 global clock buffer instead of 3 clock nets per instance.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.Constants.all;

entity ClkDivPower2 is
	generic
	(
		-- Number of bits in DivSel, so there are 2^nbits selections and a maximum division of 2^(2^nbits - 1). The generic list is the ASIC cell's verbatim: this file replaces that one in a file list.
		nbits	: natural range 1 to 32
	);
	port
	(
		resetn	: in	sl;
		En		: in	sl;
		ClkIn	: in	sl;
		DivSel	: in	slv(nbits - 1 downto 0);
		ClkOut	: out	sl
	);
end ClkDivPower2;

architecture fpga of ClkDivPower2 is

	-- The ASIC cell's chain is 2^nbits stages with stage 0 being the undivided clock, so the deepest real division needs 2^nbits - 1 counter bits.
	constant CntWidth	: natural := 2**nbits - 1;

	signal Cnt		: unsigned(CntWidth - 1 downto 0) := (others => '0');
	signal Mask		: unsigned(CntWidth downto 0);   -- 2^DivSel - 1, one bit wider so the top selection does not overflow
	signal Tick		: sl;
	signal GateEn	: sl;

begin

	-- Divide by 2^DivSel: let one cycle in 2^DivSel through. DivSel = 0 gives an all-zero mask, so every cycle passes and the divider is a wire, which is the ASIC cell's stage 0.
	Mask <= shift_left(to_unsigned(1, CntWidth + 1), to_integer(unsigned(DivSel))) - 1;
	Tick <= '1' when (Cnt and Mask(CntWidth - 1 downto 0)) = 0 else '0';
	GateEn <= En and Tick;

	-- Parked at zero while disabled, so the first cycle after an enable is a tick and the first output edge is a clean rise, as in the ASIC cell's preload.
	process (resetn, En, ClkIn)
	begin
		if resetn = '0' or En = '0' then
			Cnt <= (others => '0');
		elsif rising_edge(ClkIn) then
			Cnt <= Cnt + 1;
		end if;
	end process;

	-- The one clock buffer. The enable is already stable a full cycle before the edge it qualifies, and ClkBufEn samples it away from that edge as well.
	out_gate : entity work.ClkBufEn
		port map
		(
			ClkIn  => ClkIn,
			En     => GateEn,
			ClkOut => ClkOut
		);

end fpga;
