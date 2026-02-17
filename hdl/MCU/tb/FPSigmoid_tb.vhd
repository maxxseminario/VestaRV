----- VHDL Libraries
-- IEEE Standard Libraries
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
-- Standard library text io
use std.textio.all;
library work;

-- Tesbench for FPSigmoid.vhd. Given generics, this testbench will run every possible input
-- through FPSigmoid.vhd. It will compare the produced outputs with the expected (integer)  
-- outputs located in "sig_approx_fp.txt" (should be palced in simulation director), generated 
--  from FPSigmoid_test.m. If all outputs match the expected, test will pass.
entity FPSigmoid_tb is
end FPSigmoid_tb;

architecture test of FPSigmoid_tb is
	----- Constants
	-- FPSigmoid generics - these should be the same as the default generics set in FPSigmoid.vhd
	constant	X_M_BITS	: integer := 3;
	constant	XY_N_BITS	: integer := 15;
	constant	RHO			: integer := 2;
	
	----- DUT (FPSigmoid) Port Signals
	signal 		X    		: std_logic_vector((X_M_BITS + XY_N_BITS) downto 0);
	signal		X_int 		: integer := -(2**(X_M_BITS + XY_N_BITS -1));
	signal 		Y    		: std_logic_vector(XY_N_BITS downto 0);
	signal		Y_int 		: integer;
begin
    -- DUT (FPSigmoid) instantiation
	-- Generics are set as defualt values set in FPSigmoid.vhd
    DUT: entity work.FPSigmoid 
        port map    (
			X		=> X,
			Y		=> Y
        );

	-- Simulation Process
    SIM_PROCESS: process
		----- Process Variables & Constants
		constant XMin 				: integer := -(2**(X_M_BITS+XY_N_BITS));	
		constant XMax 				: integer := ((2**(X_M_BITS+XY_N_BITS))-1);	
		variable Ysw 				: integer;
		variable Yhw				: integer;
		----- I/O
		-- Expected (integer) outputs of approximation from MATLAB
		file y_sw_file				: text open read_mode is "sig_approx_fp.txt";
		variable y_sw_file_line		: line;
    begin
		-- Loop through and test all possible input/output pairs
		for XCurr in XMin to XMax loop
			readline(y_sw_file, y_sw_file_line);
			read(y_sw_file_line, Ysw);
			X <= std_logic_vector(to_signed(XCurr, X'length));
			wait for 10 ns;
			Yhw := to_integer(signed(Y));
			if (Ysw /= Yhw) then
				report "ERROR: For X = " & integer'image(XCurr) & ", outputs do not match! Y HW = "
						& integer'image(Yhw) & 	"Y SW = " & integer'image(Ysw)
						severity error;
			end if;
		end loop;
		file_close(y_sw_file);
        report "Test Passed! SW & HW outputs matched for all possible inputs!" severity error;
    end process;
end test;