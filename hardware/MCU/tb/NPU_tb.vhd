----- VHDL Libraries
-- IEEE Standard Libraries
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
-- Standard libraries
library std;
use std.standard.all;
use std.textio.all;
library work;
-- Synthesizable Fixed Point libraries created by David Bishop for VHDL 2008
use work.fixed_float_types.all;
use work.fixed_pkg.all;

-- Testbench for NPU.vhd with separate SRAM instantiation. NPU is tested for y=2x^2 + 1 for x = [-1,1] with 1 hidden layer with 5 neurons. 
-- Testbench resets NPU, loads SRAM with inputs and weights (both should be integers) from the "npu_fp_inputs.txt" 
-- and "npu_fp_weights.txt" files, respectively (these should be in simulation directory). These can be generated using 
-- FPMLPNN_test.m. Next, NPU's memory mapped registers will be configured for first layer. NPU is then run for all test 
-- points. Memory mapped registers are then reconfigured for second layer. NPU is then run again for all test points. 
-- Lastly, final outputs are read from SRAM and written to "npu_actual_fp_outputs.txt".
entity NPU_tb is 
end NPU_tb;

architecture testbench of NPU_tb is 
    ----- Clock Information
    constant CLK_FREQ   : integer 	:= 100e6;                -- 100 MHz
    constant CLK_PERIOD : time		:= 1 sec / CLK_FREQ;     -- 10 ns for 100 MHz (may need to increase)
	constant CLK_DELAY	: time 		:= CLK_PERIOD/2;

	----- Constants
	-- Memory Assert/Deassert Constants (Active Low)
	constant MEM_ASSERT			: std_logic	:= '0';	
	constant MEM_DEASSERT		: std_logic	:= '1';
	-- Memory Address Bus Constants
	constant MmrAddrNPUCR		: natural	:= 0;
	constant MmrAddrNPUIVSAR	: natural	:= 1;
	constant MmrAddrNPUWVSAR	: natural	:= 2;
	constant MmrAddrNPUOVSAR	: natural	:= 3;
	-- Generic Defaults Values
	constant X_M_BITS					: integer := 0;
    constant W_M_BITS					: integer := 3;
    constant Y_M_BITS					: integer := 3;
	constant N_BITS						: integer := 15;
	constant RHO						: integer := 2;

    ----- NPU Port Signals
    -- System Signals
    signal Clk			: std_logic;						-- NPU Main Clock
    signal ResetN		: std_logic;						-- NPU Active-Low Reset
    -- Memory Address Bus to Memory Mapped Registers Signals
	signal  MabMmrA		: std_logic_vector(1 downto 0)
							:= (others => '0');	    		-- MCU To NPU MMR - Address
    signal MabMmrD		: std_logic_vector(31 downto 0)		
								:= (others => '0');			-- MCU To NPU MMR - Data Input
    signal MabMmrCLK	: std_logic;						-- MCU To NPU MMR - Clock
    signal MabMmrCEN	: std_logic := MEM_DEASSERT;		-- MCU To NPU MMR - Chip Enable
    signal MabMmrWEN	: std_logic_vector(3 downto 0)
							:= (others => MEM_DEASSERT);	-- MCU To NPU MMR - Write Enable
    signal MabMmrQ		: std_logic_vector(31 downto 0);	-- MCU To NPU MMR - Data Output
    -- NPU to SRAM Interface Signals
    signal NpuSramA		: std_logic_vector(11 downto 0);	-- NPU To SRAM - Address 
    signal NpuSramD		: std_logic_vector(31 downto 0);	-- NPU To SRAM - Data Input
    signal NpuSramCLK	: std_logic;						-- NPU To SRAM - Clock
    signal NpuSramCEN	: std_logic;						-- NPU To SRAM - Chip Enable
    signal NpuSramGWEN	: std_logic;						-- NPU To SRAM - Global Write Enable
    signal NpuSramWEN	: std_logic_vector(3 downto 0);		-- NPU To SRAM - Write Enable
    signal NpuSramQ		: std_logic_vector(31 downto 0);	-- NPU From SRAM - Data Output
    -- NPU Status Signal
    signal NpuActive	: std_logic;						-- NPU Active Signal for Arbitration

	-- SRAM Input Signals (MUXed by NPU)
	signal NpuSramA_out	: std_logic_vector(11 downto 0);	-- NPU To SRAM - Address (to SRAM)
    signal NpuSramD_out	: std_logic_vector(31 downto 0);	-- NPU To SRAM - Data Input
    signal NpuSramCLK_out	: std_logic;					-- NPU To SRAM - Clock
    signal NpuSramCEN_out	: std_logic;					-- NPU To SRAM - Chip Enable
    signal NpuSramGWEN_out	: std_logic;					-- NPU To SRAM - Global Write Enable
    signal NpuSramWEN_out	: std_logic_vector(3 downto 0);	-- NPU To SRAM - Write Enable
    signal NpuSramQ_out	: std_logic_vector(31 downto 0);	-- NPU From SRAM - Data Output

    ----- MCU to SRAM Interface Signals (Testbench controlled)
    signal MabSramA		: std_logic_vector(11 downto 0)
							:= (others => '0');				-- MCU To SRAM - Address 
    signal MabSramD		: std_logic_vector(31 downto 0)
							:= (others => '0');	    		-- MCU To SRAM - Data Inputs
    signal MabSramCLK	: std_logic;						-- MCU To SRAM - Clock
    signal MabSramCEN	: std_logic := MEM_DEASSERT;		-- MCU To SRAM - Chip Enable
    signal MabSramGWEN	: std_logic := MEM_DEASSERT;		-- MCU To SRAM - Global Write Enable
    signal MabSramWEN	: std_logic_vector(3 downto 0) 
							:= (others => MEM_DEASSERT);	-- MCU To SRAM - Write Enable
    signal MabSramPGEN	: std_logic := '0';					-- MCU To SRAM - Power Gating Input
    signal MabSramQ		: std_logic_vector(31 downto 0);	-- MCU From SRAM - Data Outputs

    ----- Arbitrated SRAM Signals (Internal to testbench)
    signal SramA		: std_logic_vector(11 downto 0);	-- Arbitrated SRAM Address
    signal SramD		: std_logic_vector(31 downto 0);	-- Arbitrated SRAM Data Input
    signal SramCLK		: std_logic;						-- Arbitrated SRAM Clock
    signal SramCEN		: std_logic;						-- Arbitrated SRAM Chip Enable
    signal SramGWEN		: std_logic;						-- Arbitrated SRAM Global Write Enable
    signal SramWEN		: std_logic_vector(3 downto 0);		-- Arbitrated SRAM Write Enable
    signal SramQ		: std_logic_vector(31 downto 0);	-- SRAM Data Output
    signal SramClkEn	: std_logic;						-- SRAM Clock Enable

begin
    ----- Component Instantiations
    -- NPU Instantiation (without internal SRAM)
    NPU_INST: entity work.NPU
    generic map(
        X_M_BITS	=> X_M_BITS,
        W_M_BITS	=> W_M_BITS,
        Y_M_BITS	=> Y_M_BITS,
        N_BITS		=> N_BITS,
        RHO			=> RHO
    )
    port map(
        Clk			=> Clk,
        ResetN		=> ResetN,

		-- Memory Mapped Register Interface
        MabMmrA		=> MabMmrA,
        MabMmrD		=> MabMmrD,
        MabMmrCLK	=> MabMmrCLK,
        MabMmrCEN	=> MabMmrCEN,
        MabMmrWEN	=> MabMmrWEN,
        MabMmrQ		=> MabMmrQ,

		-- Multiplexed SRAM Signals from MCU
		SramQ_in	=> NpuSramQ,
		SramA_in 	=> MabSramA,
		SramD_in 	=> MabSramD,
		SramCLK_in 	=> MabSramCLK,
		SramCEN_in 	=> MabSramCEN,
		SramGWEN_in => MabSramGWEN,
		SramWEN_in 	=> MabSramWEN,

		--SRAM Interface
        NpuSramA_out	=> NpuSramA_out,
        NpuSramD_out	=> NpuSramD_out,
        NpuSramCLK_out	=> NpuSramCLK_out,
        NpuSramCEN_out	=> NpuSramCEN_out,
        NpuSramGWEN_out	=> NpuSramGWEN_out,
        NpuSramWEN_out	=> NpuSramWEN_out,
        NpuSramQ_out	=> NpuSramQ_out,

		-- Status
        NpuActive	=> NpuActive
    );

    -- SRAM Clock Gate
    SRAM_CLK_CG: entity work.ClkGate
    port map(
        ClkIn	=> Clk,
        En		=> SramClkEn,
        ClkOut	=> SramCLK
    );

    -- Single-Port SRAM Instantiation
    SRAM_INST: entity work.sram1p16k_hvt_pg 
    port map(
        A		=> NpuSramA_out,
        D		=> NpuSramD_out,
        CLK		=> NpuSramCLK_out,
        CEN		=> NpuSramCEN_out,
        GWEN	=> NpuSramGWEN_out,
        WEN		=> NpuSramWEN_out,
        Q		=> NpuSramQ,
        EMA		=> "000",
        PGEN	=> MabSramPGEN,
        RETN	=> '1'
    );

    ----- SRAM Arbitration Logic (implemented in testbench)
    -- Arbitration: NPU has priority when active, otherwise MCU has access
    -- SramA <= NpuSramA when NpuActive = '1' else MabSramA;
    -- SramD <= NpuSramD when NpuActive = '1' else MabSramD;
    -- SramCEN <= NpuSramCEN when NpuActive = '1' else MabSramCEN;
    -- SramGWEN <= NpuSramGWEN when NpuActive = '1' else MabSramGWEN;
    -- SramWEN <= NpuSramWEN when NpuActive = '1' else MabSramWEN;
    
    -- Clock enable for SRAM
    SramClkEn <= '1' when (SramCEN = MEM_ASSERT) else '0';
    
    -- Output data routing
    -- NpuSramQ <= NpuSramQ;		-- NPU reads from SRAM
    MabSramQ <= NpuSramQ;		-- MCU reads from SRAM (testbench)

	-- Clock Process
	CLK_PROCESS: process
	begin
		Clk	<= '0';
		wait for CLK_DELAY;
		Clk	<= '1';
		wait for CLK_DELAY;
	end process CLK_PROCESS;
	-- Connect all clocks together
	MabMmrCLK	<= Clk;
	MabSramCLK	<= Clk;

	-- Main Test Simulation Process
	SIM_PROCESS: process
		----- I/O 
		-- NPU Inputs File I/O (File must be in simulation directory or symlinked)
		file x_file				: text open read_mode is "npu_fp_inputs.txt";
		variable x_file_line	: line;
		-- NPU Inputs File I/O (File must be in simulation directory or symlinked)
		file w_file				: text open read_mode is "npu_fp_weights.txt";
		variable w_file_line	: line;
		-- NPU Expected Outputs File I/O (From MATLAB. File must be in simulation directory or symlinked)
		file y_exp_file			: text open read_mode is "npu_expected_fp_outputs.txt";
		variable y_exp_file_line: line;
		-- NPU Output File I/O (File will appear in simulation directory)
		file y_out_file			: text open write_mode is "npu_actual_fp_outputs.txt";
		variable y_out_file_line: line;
		-- I/O Variables
		variable data			: integer;
		variable ram_address	: integer := 0;
		----- Process Variables & Constants
		constant layer_loop	: integer 	:= 201;
		variable x_address		: integer 	:= 0;
		variable y_address		: integer 	:= 256;
	begin
		----- Reset NPU
		ResetN		<= '0';
		wait for 1 us;
		wait until falling_edge(Clk);
		ResetN		<= '1';
		MabSramPGEN	<= '0';
		wait for 1 us;

		----- Write Inputs and Weights to RAM
		-- Write NPU inputs to Single-Port SRAM (via MCU interface)
		MabSramCEN	<= MEM_ASSERT;
		MabSramWEN	<= (others => MEM_ASSERT);
		wait until falling_edge(MabSramCLK);
		LOAD_X_LOOP: loop
			exit when endfile(x_file);
			readline(x_file, x_file_line);
			read(x_file_line, data);
			MabSramA	<= std_logic_vector(to_unsigned(ram_address, MabSramA'length));
			MabSramD	<= (31 downto (X_M_BITS+N_BITS+1) => '0') & 
							std_logic_vector(to_signed(data, 16));
			wait until falling_edge(MabSramCLK);
			MabSramGWEN	<= MEM_ASSERT;
			wait until falling_edge(MabSramCLK);
			MabSramGWEN	<= MEM_DEASSERT;
			ram_address	:= ram_address + 1;
		end loop LOAD_X_LOOP;
		file_close(x_file);
		wait for (5*clk_period);

		-- Write NPU weights to Single-Port SRAM (via MCU interface)
		ram_address	:= 2048;
		wait until falling_edge(MabSramCLK);
		LOAD_W_LOOP: loop
			exit when endfile(w_file);
			readline(w_file, w_file_line);
			read(w_file_line, data);
			MabSramA	<= std_logic_vector(to_unsigned(ram_address, MabSramA'length));
			MabSramD	<= (31 downto (W_M_BITS+N_BITS+1) => '0') & 
							std_logic_vector(to_signed(data, 19));
			wait until falling_edge(MabSramCLK);
			MabSramGWEN	<= MEM_ASSERT;
			wait until falling_edge(MabSramCLK);
			MabSramGWEN	<= MEM_DEASSERT;
			ram_address	:= ram_address + 1;
		end loop LOAD_W_LOOP;
		file_close(w_file);
		wait for (5*clk_period);
		MabSramWEN	<= (others => MEM_DEASSERT);
		MabSramCEN	<= MEM_DEASSERT;

		----- Initialize Memory Mapped Register Values For First Layer
		-- NPU Control Register
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		MabMmrWEN	<= (others => MEM_ASSERT);
		MabMmrD		<=	(31 downto 19 => '0') 					&		-- Unused part of register
				   		'1'										&		-- NPU Bias Enabled
						'1'										&		-- NPU Activation Function Enabled
						'0'										&		-- NPU Not Activated Yet
						std_logic_vector(to_unsigned(0, 8))		&		-- NPU # Of Inputs Set To 1 (0+1)
						std_logic_vector(to_unsigned(4, 8));			-- NPU # Of Neurons Set To 5 (4+1)
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_DEASSERT;

		-- NPU Weight Vector Start Address Register
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUWVSAR, MabMmrA'length));
		MabMmrD		<= 	(31 downto 12 => '0') 					&		-- Unused part of register
						std_logic_vector(to_unsigned(2048, 12));			-- Set Weight Vector Start Address to 2048
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_DEASSERT;
		wait until falling_edge(MabMmrCLK);

		----- Loop For First Layer
		LAYER_1_LOOP: for i in 1 to layer_loop loop
			-- Set NPU Input Vector Start Address Register
			wait until falling_edge(MabMmrCLK);
			MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUIVSAR, MabMmrA'length));
			MabMmrWEN	<= (others => MEM_ASSERT);
			MabMmrD		<= 	(31 downto 12 => '0') 					&		-- Unused part of register
							std_logic_vector(to_unsigned(x_address, 12));	-- Set Input Vector Start Address
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN	<= MEM_ASSERT;
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN	<= MEM_DEASSERT;

			-- Set NPU Output Vector Start Address Register
			wait until falling_edge(MabMmrCLK);
			MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUOVSAR, MabMmrA'length));
			MabMmrD		<= 	(31 downto 12 => '0') 					&		-- Unused part of register
							std_logic_vector(to_unsigned(y_address, 12));	-- Set Output Vector Start Address
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN	<= MEM_ASSERT;
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN	<= MEM_DEASSERT;
			
			-- Set NPU THINK
			-- NPU Control Register
			wait until falling_edge(MabMmrCLK);
			MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
			MabMmrD		<=	(31 downto 19 => '0') 					&		-- Unused part of register
							'1'										&		-- NPU Bias Enabled
							'1'										&		-- NPU Activation Function Enabled
							'1'										&		-- Activate NPU
							std_logic_vector(to_unsigned(0, 8))		&		-- NPU # Of Inputs Set To 1 (0+1)
							std_logic_vector(to_unsigned(4, 8));			-- NPU # Of Neurons Set To 5(4+1)
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN	<= MEM_ASSERT;
			wait until falling_edge(MabMmrCLK);
			MabMmrWEN	<= (others => MEM_DEASSERT);
			MabMmrCEN	<= MEM_DEASSERT;
			wait until falling_edge(MabMmrCLK);
			
			-- Wait for NPU THINK to complete (wait for it to go low)
			MabMmrCEN	<= MEM_ASSERT;
			MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
			wait until falling_edge(MabMmrCLK);
			wait until falling_edge(MabMmrQ(16));
			MabMmrCEN	<= MEM_DEASSERT;
			wait until falling_edge(MabMmrCLK);
			--Layer Done
			--Update Address Variables
			x_address	:= x_address + 1;
			y_address	:= y_address + 5;
		end loop LAYER_1_LOOP;

		
		----- Initialize Memory Mapped Register Values For Second Layer
		-- NPU Control Register
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		MabMmrWEN	<= (others => MEM_ASSERT);
		MabMmrD		<=	(31 downto 19 => '0') 					&		-- Unused part of register
				   		'0'										&		-- NPU Bias Disabled
						'0'										&		-- NPU Activation Function Disabled
						'0'										&		-- NPU Not Activated Yet
						std_logic_vector(to_unsigned(4, 8))		&		-- NPU # Of Inputs Set To 5 (4+1)
						std_logic_vector(to_unsigned(0, 8));			-- NPU # Of Neurons Set To 1 (0+1)
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_DEASSERT;

		-- NPU Weight Vector Start Address Register
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUWVSAR, MabMmrA'length));
		MabMmrD		<= 	(31 downto 12 => '0') 					&		-- Unused part of register
						std_logic_vector(to_unsigned(2058, 12));		-- Set Input Vector Start Address to 2058
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_DEASSERT;
		wait until falling_edge(MabMmrCLK);

		----- Loop For Second Layer
		x_address	:= 256;
		y_address	:= 0;
		LAYER_2_LOOP: for i in 1 to layer_loop loop
			-- Set NPU Input Vector Start Address Register
			wait until falling_edge(MabMmrCLK);
			MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUIVSAR, MabMmrA'length));
			MabMmrWEN	<= (others => MEM_ASSERT);
			MabMmrD		<= 	(31 downto 12 => '0') 					&		-- Unused part of register
							std_logic_vector(to_unsigned(x_address, 12));	-- Set Input Vector Start Address
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN	<= MEM_ASSERT;
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN	<= MEM_DEASSERT;

			-- Set NPU Output Vector Start Address Register
			wait until falling_edge(MabMmrCLK);
			MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUOVSAR, MabMmrA'length));
			MabMmrD		<= 	(31 downto 12 => '0') 					&		-- Unused part of register
							std_logic_vector(to_unsigned(y_address, 12));	-- Set Input Vector Start Address
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN	<= MEM_ASSERT;
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN	<= MEM_DEASSERT;
			
			-- Set NPU THINK
			-- NPU Control Register
			wait until falling_edge(MabMmrCLK);
			MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
			MabMmrD		<=	(31 downto 19 => '0') 					&		-- Unused part of register
							'0'										&		-- NPU Bias Disabled
							'0'										&		-- NPU Activation Function Disabled
							'1'										&		-- Activate NPU
							std_logic_vector(to_unsigned(4, 8))		&		-- NPU # Of Inputs Set To 5 (4+1)
							std_logic_vector(to_unsigned(0, 8));			-- NPU # Of Neurons Set To 1 (0+1)
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN	<= MEM_ASSERT;
			wait until falling_edge(MabMmrCLK);
			MabMmrWEN	<= (others => MEM_DEASSERT);
			MabMmrCEN	<= MEM_DEASSERT;
			wait until falling_edge(MabMmrCLK);
			
			-- Wait for NPU THINK to complete (wait for it to go low)
			MabMmrCEN	<= MEM_ASSERT;
			MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
			wait until falling_edge(MabMmrCLK);
			wait until falling_edge(MabMmrQ(16));
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN	<= MEM_DEASSERT;
			--Layer Done
			--Update Address Variables
			x_address	:= x_address + 5;
			y_address	:= y_address + 1;
		end loop LAYER_2_LOOP;

		----- NPU Now DONE!!! Extract Output Values.
		-- Read NPU outputs from Single-Port SRAM (via MCU interface)
		MabSramCEN	<= MEM_ASSERT;
		ram_address	:= 0;
		GET_Y_LOOP: for i in 1 to layer_loop loop
			wait until falling_edge(MabSramCLK);
			MabSramA	<= std_logic_vector(to_unsigned(ram_address, MabSramA'length));
			wait until falling_edge(MabSramCLK);
			readline(y_exp_file, y_exp_file_line);
			read(y_exp_file_line, data);
			if (data /= to_integer(signed(MabSramQ((Y_M_BITS + N_BITS) downto 0)))) then
				report "ERROR: For i = " & integer'image(i) & ", expected and actual outputs do not match! Y HW = "
						& integer'image(to_integer(signed(MabSramQ((Y_M_BITS + N_BITS) downto 0)))) & 	" Y SW = " & integer'image(data)
						severity error;
			end if;
			write(y_out_file_line, to_integer(signed(MabSramQ((Y_M_BITS + N_BITS) downto 0))), left, 18);
			writeline(y_out_file, y_out_file_line);
			ram_address	:= ram_address + 1;
		end loop GET_Y_LOOP;
		wait until falling_edge(MabSramCLK);
		file_close(y_out_file);
		file_close(y_exp_file);
		wait for (5*clk_period);
		----- TEST DONE! -----
		report "Test Passed!" severity error;
		wait;
	end process SIM_PROCESS;
end testbench;

