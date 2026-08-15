-- Behavioral stand-in for the analog GlitchFilter macro.
-- Simulation only: the real macro suppresses IRQ pulses narrower than minPulseWidth.
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.Constants.all;

entity GlitchFilter is
	port
	(
		IrqGlitchy		: in	std_logic_vector(31 downto 0);	-- raw IRQ lines from the pads
		IrqDeglitched	: out	std_logic_vector(31 downto 0)	-- filtered IRQ lines to the core
	);
end GlitchFilter;

architecture behavioral of GlitchFilter is
	constant minPulseWidth : time := 2 ns;	-- documents the macro's rejection width; unused by this model
begin
	-- This model is a pass-through: no filtering is modelled, so IRQ timing is ideal in simulation.
	IrqDeglitched <= IrqGlitchy;
end behavioral;