-- VestaRV: board clock source, any oscillator in, 24 MHz out
-- VIVADO ONLY. This file is NOT in any GHDL file list and not under hdl/: it instantiates MMCME2_BASE, which has no model here, and it belongs to a board port rather than to the chip. The out-of-context synthesis run does not use it either, because that run's top is MCU and MCU has no place to put an MMCM.
--
-- WHY 24 MHz AND NOT THE BOARD CRYSTAL. Every bench in the tree models HFXT at 24 MHz and the firmware's UART divisors are written against that number, so a board whose oscillator is 100 MHz has to divide down before the pad rather than re-derive the baud table. SYS_CLK_CR resets to zero, which selects clk_hfxt for both MCLK and SMCLK, so this output is what the whole chip runs on out of reset.
--
-- WIRING. ClkOut goes to MCU's prt1_in(5), which is GPIO0 P1.5, the HFXT pad; there is no dedicated clock port on MCU. Locked is the board reset qualifier: hold MCU's resetn_in low until it is high, or the core starts fetching before the clock is stable.
-- One MMCM does not come out of the 32 BUFGCTRL budget; its CLKOUT0 buffer does.

library ieee;
use ieee.std_logic_1164.all;

entity FpgaClkSource24 is
	generic
	(
		-- Board oscillator period in nanoseconds, and the MMCM's own multiply/divide. The VCO must land between 600 MHz and 1200 MHz on a -1 Artix-7: ClkInPeriod = 10.0 with Mult = 12.0 and DivIn = 1 gives 1200 MHz, and DivOut = 50 gives 24 MHz.
		ClkInPeriod	: real		:= 10.0;
		Mult		: real		:= 12.0;
		DivIn		: integer	:= 1;
		DivOut		: integer	:= 50
	);
	port
	(
		ClkIn	: in	std_logic;	-- board oscillator
		Resetn	: in	std_logic;	-- active low, from the board
		ClkOut	: out	std_logic;	-- 24 MHz, to MCU's prt1_in(5)
		Locked	: out	std_logic	-- hold MCU's resetn_in low until this is high
	);
end FpgaClkSource24;

architecture xilinx of FpgaClkSource24 is

	component MMCME2_BASE
		generic
		(
			CLKIN1_PERIOD		: real;
			CLKFBOUT_MULT_F		: real;
			DIVCLK_DIVIDE		: integer;
			CLKOUT0_DIVIDE_F	: real
		);
		port
		(
			CLKIN1		: in	std_ulogic;
			CLKFBIN		: in	std_ulogic;
			CLKFBOUT	: out	std_ulogic;
			CLKOUT0		: out	std_ulogic;
			LOCKED		: out	std_ulogic;
			PWRDWN		: in	std_ulogic;
			RST			: in	std_ulogic
		);
	end component;

	component BUFG
		port
		(
			O	: out	std_ulogic;
			I	: in	std_ulogic
		);
	end component;

	signal fb_out	: std_logic;
	signal fb_in	: std_logic;
	signal clk_raw	: std_logic;

begin

	mmcm : MMCME2_BASE
		generic map
		(
			CLKIN1_PERIOD    => ClkInPeriod,
			CLKFBOUT_MULT_F  => Mult,
			DIVCLK_DIVIDE    => DivIn,
			CLKOUT0_DIVIDE_F => real(DivOut)
		)
		port map
		(
			CLKIN1   => ClkIn,
			CLKFBIN  => fb_in,
			CLKFBOUT => fb_out,
			CLKOUT0  => clk_raw,
			LOCKED   => Locked,
			PWRDWN   => '0',
			RST      => not Resetn
		);

	-- The feedback path is buffered so the MMCM compensates for the clock network delay rather than for a bare wire.
	fb_buf : BUFG
		port map
		(
			O => fb_in,
			I => fb_out
		);

	out_buf : BUFG
		port map
		(
			O => ClkOut,
			I => clk_raw
		);

end xilinx;
