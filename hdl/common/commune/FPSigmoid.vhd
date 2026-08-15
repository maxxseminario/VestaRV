----- VHDL Libraries
-- IEEE Standard Libraries
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
-- Synthesizable fixed-point libraries created by David Bishop for VHDL 2008.
-- User guide: https://freemodelfoundry.com/fphdl/Fixed_ug.pdf
-- Repository: https://github.com/FPHDL/fphdl/blob/master/fixed_pkg_c.vhdl and https://github.com/ghdl/ghdl/blob/master/libraries/ieee2008/fixed_generic_pkg-body.vhdl
-- The library files used here were pulled from /opt/cadence/XCELIUM2009/tools/xcelium/files/IEEE_PROPOSED.src
use work.fixed_float_types.all;
use work.fixed_pkg.all;

-- Combinational fixed-point sigmoid approximator, based on:
	-- B. Cyganek and K. Socha, "Computationally efficient methods
	-- of approximations of the s-shape functions for image processing
	-- and computer graphics tasks," IPC, vol. 16, no. 1-2, p. 19-28,
	-- Jan. 2011. [Online]. Available: http://dx.doi.org/10.2478/v10248-012-0002-6
entity FPSigmoid is
	generic(
		-- Fixed-point M and N bit counts for the input and output.
		-- The output is assumed to have 0 M bits, since its range is 0 to 1.
		-- X_M_BITS must be at least RHO.
		X_M_BITS		: integer := 3;
		XY_N_BITS		: integer := 15;
		RHO				: integer := 2
	);
	port(
		X				: in std_logic_vector((X_M_BITS + XY_N_BITS) downto 0);   -- signed fixed-point input
		Y				: out std_logic_vector((XY_N_BITS) downto 0)              -- fixed-point sigmoid output in [0,1]
	);
end FPSigmoid;

architecture behavioral of FPSigmoid is
	signal XSignBit		: std_logic;   -- sign of the input
	signal XOutOfRangeF	: std_ulogic;  -- set when |X| lands outside the approximated band
	signal XDomain	: std_logic_vector(1 downto 0);   -- {sign, out-of-range}, the piecewise selector
	signal XSFixed		: sfixed(X_M_BITS downto (-XY_N_BITS));
	signal XAbs			: sfixed((X_M_BITS + 1) downto (-XY_N_BITS));
	signal XInRange		: sfixed(RHO downto (-XY_N_BITS));
	signal YInt1		: sfixed(0 downto (-XY_N_BITS));
	signal YInt2		: sfixed(1 downto (-XY_N_BITS*2));
	signal YInt3		: sfixed(0 downto (-XY_N_BITS));
	signal YOutTemp		: sfixed(0 downto (-XY_N_BITS));
begin
	----- Combinational sigmoid approximation logic
	-- Approximation arithmetic: scale the magnitude, square it, and halve the result.
	XSFixed			<= to_sfixed(X, XSFixed'high, XSFixed'low);
	XSignBit		<= XSFixed(XSFixed'high);
	XAbs			<= abs(XSFixed);
	XOutOfRangeF	<= or_reduce(XAbs((XAbs'high) downto (RHO)));
	XInRange		<= resize(XAbs, XInRange'high, XInRange'low);
	YInt1			<= resize(scalb(XInRange, (-RHO)) + to_sfixed(-1, 0, -(XY_N_BITS+RHO)), YInt1'high, YInt1'low);
	YInt2			<= YInt1 * YInt1;
	YInt3			<= resize((scalb(YInt2, -1)), YInt3'high, YInt3'low);
	-- Pick the piecewise branch from the input's sign and whether it is in range.
	XDomain	<= XSignBit & XOutOfRangeF;
	with XDomain select
		YOutTemp	<=	to_sfixed(0, YOutTemp'high, YOutTemp'low)														when "11", -- negative and out of range: saturate to 0
						YInt3																							when "10", -- negative and in range
						resize((to_sfixed(1, (YOutTemp'high+1), YOutTemp'low) - YInt3), YOutTemp'high, YOutTemp'low)	when "00", -- positive and in range: mirror of the negative branch
						to_sfixed(1, YOutTemp'high, YOutTemp'low)														when "01", -- positive and out of range: saturate to 1
						to_sfixed(0, YOutTemp'high, YOutTemp'low)														when others;
	-- Drive the output word.
	Y	<= to_slv(YOutTemp);
end behavioral;