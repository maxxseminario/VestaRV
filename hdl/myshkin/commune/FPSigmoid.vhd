----- VHDL Libraries
-- IEEE Standard Libraries
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
-- Synthesizable Fixed Point libraries created by David Bishop for VHDL 2008
-- User Guide: https://freemodelfoundry.com/fphdl/Fixed_ug.pdf
-- Repository: https://github.com/FPHDL/fphdl/blob/master/fixed_pkg_c.vhdl / https://github.com/ghdl/ghdl/blob/master/libraries/ieee2008/fixed_generic_pkg-body.vhdl
-- The library files here were pulled from following path: /opt/cadence/XCELIUM2009/tools/xcelium/files/IEEE_PROPOSED.src
use work.fixed_float_types.all;
use work.fixed_pkg.all;

-- Combinational fixed-point Sigmoid Approximator based off: 
	-- B. Cyganek and K. Socha, “Computationally efficient methods
	-- of approximations of the s-shape functions for image processing
	-- and computer graphics tasks,” IPC, vol. 16, no. 1–2, p. 19–28,
	-- Jan. 2011. [Online]. Available: http://dx.doi.org/10.2478/v10248-012-0002-6
entity FPSigmoid is
	generic(
		-- Fixed-Point M and N Bits for input and output. (Output assumed to have 0 M bits as results is 0-1)
		-- X_M_BITS should be at least RHO
		X_M_BITS		: integer := 3;
		XY_N_BITS		: integer := 15;
		RHO				: integer := 2
	);
	port(
		X				: in std_logic_vector((X_M_BITS + XY_N_BITS) downto 0);
		Y				: out std_logic_vector((XY_N_BITS) downto 0)
	);
end FPSigmoid;

architecture behavioral of FPSigmoid is
	signal XSignBit		: std_logic;
	signal XOutOfRangeF	: std_ulogic;
	signal XDomain	: std_logic_vector(1 downto 0);
	signal XSFixed		: sfixed(X_M_BITS downto (-XY_N_BITS));
	signal XAbs			: sfixed((X_M_BITS + 1) downto (-XY_N_BITS));
	signal XInRange		: sfixed(RHO downto (-XY_N_BITS));
	signal YInt1		: sfixed(0 downto (-XY_N_BITS));
	signal YInt2		: sfixed(1 downto (-XY_N_BITS*2));
	signal YInt3		: sfixed(0 downto (-XY_N_BITS));
	signal YOutTemp		: sfixed(0 downto (-XY_N_BITS));
begin
	----- Combinatoinal Simgoid Approximation Logic
	-- Sigmoid approximation calculations
	XSFixed			<= to_sfixed(X, XSFixed'high, XSFixed'low);
	XSignBit		<= XSFixed(XSFixed'high);
	XAbs			<= abs(XSFixed);
	XOutOfRangeF	<= or_reduce(XAbs((XAbs'high) downto (RHO)));
	XInRange		<= resize(XAbs, XInRange'high, XInRange'low);
	YInt1			<= resize(scalb(XInRange, (-RHO)) + to_sfixed(-1, 0, -(XY_N_BITS+RHO)), YInt1'high, YInt1'low);
	YInt2			<= YInt1 * YInt1;
	YInt3			<= resize((scalb(YInt2, -1)), YInt3'high, YInt3'low);
	-- Selecting correct piecewise domain output based on input value
	XDomain	<= XSignBit & XOutOfRangeF;
	with XDomain select
		YOutTemp	<=	to_sfixed(0, YOutTemp'high, YOutTemp'low)														when "11", -- Negative & Out of Range
						YInt3																							when "10", -- Negative & In Range
						resize((to_sfixed(1, (YOutTemp'high+1), YOutTemp'low) - YInt3), YOutTemp'high, YOutTemp'low)	when "00", -- Positive & In Range
						to_sfixed(1, YOutTemp'high, YOutTemp'low)														when "01", -- Positive & Out of Range
						to_sfixed(0, YOutTemp'high, YOutTemp'low)														when others;
	-- Setting output
	Y	<= to_slv(YOutTemp);
end behavioral;