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

-- Fixed-Point Multiply and Accumulator
entity FPMac is
    generic(
		-- Fixed-Point M and N Bits for inputs and accumulator (product)
        A_M_BITS		: integer;
        B_M_BITS		: integer;
		ACC_M_BITS		: integer;
		N_BITS			: integer
    );
    port(
        Clk				: in    std_logic;
        ResetN			: in    std_logic;
        A				: in    std_logic_vector((A_M_BITS + N_BITS) downto 0);
        B				: in    std_logic_vector((B_M_BITS + N_BITS) downto 0);
		Y				: out	std_logic_vector((ACC_M_BITS + N_BITS) downto 0);
		YAcc			: out	std_logic_vector((ACC_M_BITS + N_BITS) downto 0)
    );
end FPMac;

architecture behavioral of FPMac is
	signal YInt			: sfixed(ACC_M_BITS downto (-N_BITS));
	-- Cannot have register of sfixed type as .sdf file cannot deal with negative indexes.
	signal YAccInt		: std_logic_vector((ACC_M_BITS + N_BITS) downto 0);
begin
	----- Combinational Logic -----
	-- MAC Logic
	YInt 	<= resize(((to_sfixed(YAccInt, ACC_M_BITS, -N_BITS)) + (to_sfixed(A, A_M_BITS, -N_BITS) * to_sfixed(B, B_M_BITS, -N_BITS))), YInt'high, YInt'low);
	-- Tieing internal accumulator outputs to actual outputs
	Y		<= to_slv(YInt);
	YAcc <= YAccInt;

	----- Sequential Logic For Accumulator Latch -----
	MAC_ACC: process (Clk, ResetN)
	begin
		if (ResetN = '0') then			-- Asynchronous active-low reset
			YAccInt <= (others => '0');
		elsif (rising_edge(Clk)) then	-- Rising edge latched accumulator
			YAccInt <= to_slv(YInt);
		end if;
	end process;
end behavioral;