/* FPGA stand-in for the ClkGate technology cell.
   The ASIC flow maps this entity onto an integrated clock-gating cell; the simulation model in hdl/common/sim/ClkGate.vhd builds it from a level-sensitive latch instead.
   Vivado infers a real latch from that model and reports it on every clock path that carries one, so this version captures the enable in a falling-edge flip-flop and gets the same runt-free behaviour out of a primitive the fabric actually has. */

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

	signal EnReg : std_logic := '0';

begin

	-- The enable is sampled on the falling edge, so it is stable well before the next rising edge and the gate passes a high phase whole or not at all.
	process (ClkIn)
	begin
		if falling_edge(ClkIn) then
			EnReg <= En;
		end if;
	end process;

	/* The AND lands in fabric, which means every gated clock in the design becomes a fabric-routed clock net.
	   That is fine at the low clock rates this target runs at.
	   If timing closure starts failing on the gated domains, the fix is a BUFGCE on the few gates that carry real traffic, or converting those consumers to clock enables; do not raise the clock and hope. */
	ClkOut <= EnReg and ClkIn;

end fpga;
