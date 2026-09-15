-- VestaRV: FPGA clock-buffer primitives, vendor-neutral architectures
-- This is the half of the pair that GHDL analyzes and that any non-Xilinx flow synthesizes. It names no vendor cell, so it elaborates with no library beyond ieee.
-- Pair file: ClockPrimitives_xilinx.vhd. EXACTLY ONE of the two may appear in any file list; compile both and the tool binds whichever architecture it analyzed last.

library ieee;
use ieee.std_logic_1164.all;

-- The enable is sampled on the falling edge, so it is stable well before the next rising edge and the gate passes a high phase whole or not at all. This is the behaviour BUFGCE gives in hardware.
architecture inferred of ClkBufEn is

	signal EnReg : std_logic := '0';

begin

	process (ClkIn)
	begin
		if falling_edge(ClkIn) then
			EnReg <= En;
		end if;
	end process;

	ClkOut <= EnReg and ClkIn;

end inferred;

library ieee;
use ieee.std_logic_1164.all;

-- A buffer is a wire until a tool is asked to put it on a dedicated clock network.
architecture inferred of ClkBuf is
begin

	ClkOut <= ClkIn;

end inferred;
