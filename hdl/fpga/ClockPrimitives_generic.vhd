-- VestaRV: FPGA clock-buffer primitives, vendor-neutral architectures
-- This is the half of the pair that GHDL analyzes and that any non-Xilinx flow synthesizes. It names no vendor cell, so it elaborates with no library beyond ieee.
-- Pair file: ClockPrimitives_xilinx.vhd. EXACTLY ONE of the two may appear in any file list; compile both and the tool binds whichever architecture it analyzed last.

library ieee;
use ieee.std_logic_1164.all;

-- The enable is captured by a latch that is transparent while ClkIn is low, so the gate passes a high phase whole or not at all. This is the behaviour BUFGCE and the ASIC ICG give: En only has to settle before the rising edge.
-- NOT a falling-edge flop. adddec.vhd launches mem_en on the falling edge of clk, and a flop clocked on that same edge samples the old value, so every TCM clock pulse lands a cycle late and the boot ROM's flash loads into the TCM are lost (//implementations/fpga/bringup:fpga_flash_boot).
-- A non-Xilinx synthesis infers a latch here, which is the cell's function, not an accident.
architecture inferred of ClkBufEn is

	signal EnReg : std_logic := '0';

begin

	process (ClkIn, En)
	begin
		if ClkIn = '0' then
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
