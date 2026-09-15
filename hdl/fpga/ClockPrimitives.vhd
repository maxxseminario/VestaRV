-- VestaRV: FPGA clock-buffer primitives, entity declarations
-- Two cells stand between every clock-generation entity in hdl/fpga/ and the fabric: ClkBufEn, a clock buffer with a glitch-free enable, and ClkBuf, a plain clock buffer.
-- Nothing in hdl/common/ knows they exist. They are here so that ClkGate, ClockMuxGlitchFree and ClkDivPower2 each say WHAT they need of the clock network and not WHICH vendor cell provides it.
-- The architectures live in two files, ClockPrimitives_generic.vhd and ClockPrimitives_xilinx.vhd, and hdl/fpga/README.md's one rule applies to them exactly as it applies to hdl/common/sim/ versus hdl/fpga/: EXACTLY ONE of the two may appear in any file list.

library ieee;
use ieee.std_logic_1164.all;

-- Clock buffer with an enable. En is sampled away from the active edge, so ClkOut passes a high phase whole or not at all and never emits a runt.
-- Maps onto BUFGCE on a 7-series part; the portable architecture builds the same behaviour out of a falling-edge flip-flop and an AND.
entity ClkBufEn is
	port
	(
		ClkIn	: in	std_logic;
		En		: in	std_logic;
		ClkOut	: out	std_logic
	);
end ClkBufEn;

library ieee;
use ieee.std_logic_1164.all;

-- Plain clock buffer. It exists to name the one place a fabric-driven clock enters the global clock network, which is where CLOCK_DEDICATED_ROUTE and the generated-clock constraint have to be written.
-- Maps onto BUFG; the portable architecture is a wire.
entity ClkBuf is
	port
	(
		ClkIn	: in	std_logic;
		ClkOut	: out	std_logic
	);
end ClkBuf;
