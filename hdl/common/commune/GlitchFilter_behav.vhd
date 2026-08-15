-- =============================================================================
-- GlitchFilter_behav.vhd
-- =============================================================================
-- Behavioral stand-in for the analog GlitchFilter macro on the 32 IRQ lines.
-- The real cell swallows pulses narrower than minPulseWidth; simulation does not model that, so this architecture is a straight pass-through.
-- minPulseWidth is kept here as the documented filter width of the macro.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.Constants.all;

entity GlitchFilter is
	port
	(
		IrqGlitchy		: in	std_logic_vector(31 downto 0);
		IrqDeglitched	: out	std_logic_vector(31 downto 0)
	);
end GlitchFilter;

architecture behavioral of GlitchFilter is
	constant minPulseWidth : time := 2 ns;   -- documented filter width of the real macro
begin
	-- Pass-through: no filtering is modelled behaviorally.
	IrqDeglitched <= IrqGlitchy;
end behavioral;