-- VestaRV: FPGA clock-buffer primitives, Xilinx 7-series architectures
-- Each architecture instantiates the UNISIM cell by name through a locally declared component, so the file analyzes with no `library unisim` and Vivado still binds the real primitive.
-- Pair file: ClockPrimitives_generic.vhd. EXACTLY ONE of the two may appear in any file list. Vivado takes this one; GHDL cannot, because it has no cell to bind BUFGCE and BUFG to.
-- Each instance consumes one of the 32 BUFGCTRL sites on an Artix-7. hdl/fpga/README.md's clock-net table is the budget, and it is the reason ClockMuxGlitchFree and ClkDivPower2 have FPGA architectures at all.

library ieee;
use ieee.std_logic_1164.all;

architecture xilinx of ClkBufEn is

	-- Global clock buffer with a clock enable. CE is captured inside the primitive away from the active edge, so the output is runt-free by construction.
	component BUFGCE
		port
		(
			O	: out	std_ulogic;
			CE	: in	std_ulogic;
			I	: in	std_ulogic
		);
	end component;

begin

	buf : BUFGCE
		port map
		(
			O  => ClkOut,
			CE => En,
			I  => ClkIn
		);

end xilinx;

library ieee;
use ieee.std_logic_1164.all;

architecture xilinx of ClkBuf is

	component BUFG
		port
		(
			O	: out	std_ulogic;
			I	: in	std_ulogic
		);
	end component;

begin

	buf : BUFG
		port map
		(
			O => ClkOut,
			I => ClkIn
		);

end xilinx;
