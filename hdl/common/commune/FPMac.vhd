----- VHDL Libraries
-- IEEE Standard Libraries
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
-- Synthesizable fixed-point packages (the David Bishop VHDL-2008 fphdl set), compiled into work from the simulator's IEEE_PROPOSED sources.
use work.fixed_float_types.all;
use work.fixed_pkg.all;

-- Fixed-point multiply and accumulate: Y is the fresh sum YAcc + A*B, YAcc is that sum registered on Clk.
entity FPMac is
    generic(
		-- Fixed-point integer (M) and fraction (N) bit counts for the inputs and for the accumulator (the product).
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
	-- The accumulator register is slv, not sfixed: an .sdf file cannot deal with the negative indexes of an sfixed range.
	signal YAccInt		: std_logic_vector((ACC_M_BITS + N_BITS) downto 0);
begin
	----- Combinational Logic -----
	-- MAC logic: multiply A by B, add the held accumulator, resize back to the accumulator format.
	YInt 	<= resize(((to_sfixed(YAccInt, ACC_M_BITS, -N_BITS)) + (to_sfixed(A, A_M_BITS, -N_BITS) * to_sfixed(B, B_M_BITS, -N_BITS))), YInt'high, YInt'low);
	-- Drive the ports from the internal nodes: Y is this cycle's sum, YAcc is the value held in the register.
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