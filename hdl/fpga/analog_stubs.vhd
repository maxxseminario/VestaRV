/* FPGA stand-ins for the analog macros the MCU instantiates at its top level.
   None of these blocks has an FPGA counterpart, so each one is reduced to the smallest synthesizable behaviour that keeps the digital design running.
   The simulation models in hdl/common/sim/ are not usable here: the oscillator drives a clock from wait-for-time statements, and the reset and filter models carry simulation-only wording that is worth restating in synthesis terms. */

library ieee;
use ieee.std_logic_1164.all;

/* The real macro suppresses interrupt pulses narrower than its rejection width, which is an analog property of the cell.
   The entity has no clock port, so no digital filter can be built behind this interface; a synchronizer would need one.
   Interrupt inputs therefore arrive unfiltered and unsynchronized, exactly as they do in simulation, and any metastability hardening has to happen in the pad logic of the top level that instantiates the MCU. */
entity GlitchFilter is
	port
	(
		IrqGlitchy		: in	std_logic_vector(31 downto 0);
		IrqDeglitched	: out	std_logic_vector(31 downto 0)
	);
end GlitchFilter;

architecture fpga of GlitchFilter is
begin
	IrqDeglitched <= IrqGlitchy;
end fpga;


library ieee;
use ieee.std_logic_1164.all;
library work;
use work.Constants.all;

/* The real macro holds resetn_out low until the supply has risen past its trip point.
   An FPGA is already configured and running by the time this logic exists, so there is no supply ramp to watch and the external reset is passed straight through.
   The top level owns the reset shape: hold resetn asserted for long enough after configuration that every clock domain has seen edges, and release it synchronously. */
entity PowerOnResetCheng is
	port
	(
		resetn_in	: in	sl;
		resetn_out	: out	sl
	);
end PowerOnResetCheng;

architecture fpga of PowerOnResetCheng is
begin
	resetn_out <= resetn_in;
end fpga;


library ieee;
use ieee.std_logic_1164.all;
library work;
use work.Constants.all;

/* The current-starved ring oscillator is a free-running analog clock source, and this interface gives it no reference to divide, so the FPGA build cannot produce one.
   The output is tied low, which is safe for the boot path: SYS_CLK_CR resets to all zeros, and that selects clk_hfxt for both MCLK and SMCLK while leaving dco0_on and dco1_on clear.
   The chip therefore comes out of reset on the HFXT pad, which on this target is the board oscillator, and never observes the DCO.
   Firmware that writes a DCO code into SYS_CLK_CR(1 downto 0) or SYS_CLK_CR(3 downto 2) will stop the clock it is running on and hang the FPGA; the boot ROM does not do this, and neither should anything built on top of it here. */
entity OscillatorCurrentStarved is
	port
	(
		Reset	: in	sl;
		En		: in	sl;
		Freq	: in	slv(11 downto 0);
		ClkOut	: out	sl
	);
end OscillatorCurrentStarved;

architecture fpga of OscillatorCurrentStarved is
begin
	ClkOut <= '0';
end fpga;


library ieee;
use ieee.std_logic_1164.all;
library work;
use work.Constants.all;

-- The same oscillator stub under the second name the design instantiates.
entity DCO is
	port
	(
		Reset	: in	sl;
		En		: in	sl;
		Freq	: in	slv(11 downto 0);
		ClkOut	: out	sl
	);
end DCO;

architecture fpga of DCO is
begin
	ClkOut <= '0';
end fpga;
