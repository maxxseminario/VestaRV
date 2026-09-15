-- VestaRV: FPGA stand-in for the ClkGate technology cell
-- The ASIC flow maps this entity onto an integrated clock-gating cell, and the simulation model in hdl/common/sim/ClkGate.vhd builds it from a level-sensitive latch. Vivado infers a real latch from that model and reports it on every clock path that carries one, so this version hands the job to ClkBufEn: BUFGCE on a 7-series part, a falling-edge flop and an AND anywhere else.
-- One instance costs one global clock buffer. fpga_default holds 14 live ClkGate instances; hdl/fpga/README.md's clock-net table is the budget they come out of.

library ieee;
use ieee.std_logic_1164.all;

entity ClkGate is
	port
	(
		ClkIn	: in	std_logic;
		En		: in	std_logic;
		ClkOut	: out	std_logic
	);
end ClkGate;

architecture fpga of ClkGate is

begin

	-- ClkBufEn is the only cell in hdl/fpga/ that knows whether this is a BUFGCE or a flop and an AND. See ClockPrimitives.vhd.
	gate : entity work.ClkBufEn
		port map
		(
			ClkIn  => ClkIn,
			En     => En,
			ClkOut => ClkOut
		);

end fpga;
