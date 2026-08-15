----- VHDL Libraries
-- IEEE Standard Libraries
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
-- Standard libraries
library std;
use std.standard.all;
use std.textio.all;
use std.env.all;
library work;
-- Synthesizable Fixed Point libraries created by David Bishop for VHDL 2008
use work.fixed_float_types.all;
use work.fixed_pkg.all;

-- Testbench for NPU.vhd with the SRAM instantiated separately, alongside the NPU.
-- The network under test is y = 2x^2 + 1 over x = [-1,1], one hidden layer of 5 neurons.
-- The bench resets the NPU, then loads SRAM with inputs and weights (both integers) from "npu_fp_inputs.txt" and "npu_fp_weights.txt" respectively, which must be present in the simulation directory.
-- Both input files can be generated with FPMLPNN_test.m.
-- The memory mapped registers are configured for the first layer and the NPU is run over every test point.
-- The registers are then reconfigured for the second layer and the NPU is run over every test point again.
-- Finally the outputs are read back from SRAM and written to "npu_actual_fp_outputs.txt".
entity NPU_tb is
	generic (
		-- DP-SG think-done IRQ negative control (npu_irq_spec.md, house rule).
		-- 0 = clean run, the only PASS-eligible mode.
		-- 1 = deliberately SKIP the W1C clear write in the IRQ-c phase but still CHECK for the cleared flag and IRQ.
		-- The flag and IRQ then stay asserted, so that check must FAIL, proving the check itself is load-bearing both ways.
		NEGCTRL : integer := 0
	);
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
	constant MmrAddrNPUSR		: natural	:= 4;	-- DP-SG think-done IRQ NPUSR (npu_irq_spec.md)
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
	signal  MabMmrA		: std_logic_vector(3 downto 0)
							:= (others => '0');	    		-- MCU To NPU MMR - Address (4b widen, P4.1 family CFG words)
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
    -- NPU Interrupt Signal (DP-SG think-done IRQ, npu_irq_spec.md, irq_router source 120)
    signal ThinkDoneIrq	: std_logic;						-- Think-Done IRQ (registered level on Clk)
    -- EVFAB task port (event_fabric_spec.md, 2026-07-24): a one-MabMmrCLK pulse that starts a THINK exactly like a register write of NPUCR bit 16.
    signal task_think	: std_logic := '0';					-- EVFAB task pulse (MabMmrCLK domain)

	-- SRAM Input Signals (MUXed by NPU)
	signal NpuSramA_out	: std_logic_vector(11 downto 0);	-- NPU To SRAM - Address (to SRAM)
    signal NpuSramD_out	: std_logic_vector(31 downto 0);	-- NPU To SRAM - Data Input
    signal NpuSramCLK_out	: std_logic;					-- NPU To SRAM - Clock
    signal NpuSramCEN_out	: std_logic;					-- NPU To SRAM - Chip Enable
    signal NpuSramGWEN_out	: std_logic;					-- NPU To SRAM - Global Write Enable
    signal NpuSramWEN_out	: std_logic_vector(3 downto 0);	-- NPU To SRAM - Write Enable
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

		-- Status
        NpuActive	=> NpuActive,
		-- Interrupt (DP-SG think-done IRQ, npu_irq_spec.md)
        ThinkDoneIrq	=> ThinkDoneIrq,
		-- EVFAB task port (event_fabric_spec.md, 2026-07-24)
        task_think	=> task_think
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
    -- Superseded: the NPU now muxes the two SRAM ports itself (Sram*_in in, NpuSram*_out out), so the testbench-side arbitration below stays disabled.
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

	-- Free-running testbench clock at CLK_FREQ with a 50 percent duty cycle.
	CLK_PROCESS: process
	begin
		Clk	<= '0';
		wait for CLK_DELAY;
		Clk	<= '1';
		wait for CLK_DELAY;
	end process CLK_PROCESS;
	-- Both MCU-side interface clocks are the same free-running Clk.
	MabMmrCLK	<= Clk;
	MabSramCLK	<= Clk;

	-- Main stimulus process: load SRAM, run both layers, self-check the outputs, then run the IRQ and EVFAB phases.
	SIM_PROCESS: process
		----- I/O
		-- NPU Inputs File I/O (File must be in simulation directory or symlinked)
		file x_file				: text open read_mode is "npu_fp_inputs.txt";
		variable x_file_line	: line;
		-- NPU Weights File I/O (File must be in simulation directory or symlinked)
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
		variable weight_count	: integer := 0;
		----- Process Variables & Constants
		constant layer_loop	: integer 	:= 201;
		variable x_address		: integer 	:= 0;
		variable y_address		: integer 	:= 256;
		variable error_count	: integer 	:= 0;	-- self-checking mismatch tally
		-- DP-SG think-done IRQ test phase (npu_irq_spec.md, vector 120)
		variable irq_error_count	: integer	:= 0;	-- IRQ-phase mismatch tally
		variable think_poll_i		: integer	:= 0;	-- bounded THINK-completion poll counter
		constant THINK_POLL_MAX		: integer	:= 4096;	-- bounded poll ceiling (never an unbounded wait)
		-- EVFAB task_think phase (event_fabric_spec.md, 2026-07-24)
		variable evfab_error_count	: integer	:= 0;	-- EVFAB-phase mismatch tally
		variable evfab_poll_i		: integer	:= 0;	-- bounded THINK-completion poll counter (own copy)
		variable reg_launch_val		: integer	:= 0;	-- register-launched THINK output (reference)
		variable task_launch_val	: integer	:= 0;	-- task-launched THINK output (compared)
		variable task_launch_val2	: integer	:= 0;	-- re-read after the pulse-consumed check
	begin
		----- Reset NPU
		report "[NPU_TB] Starting NPU testbench simulation..." severity note;
		ResetN		<= '0';
		wait for 1 us;
		wait until falling_edge(Clk);
		ResetN		<= '1';
		MabSramPGEN	<= '0';
		wait for 1 us;
		report "[NPU_TB] Reset complete." severity note;

		----- Write Inputs and Weights to RAM
		-- Write NPU inputs to Single-Port SRAM (via MCU interface)
		report "[NPU_TB] Loading inputs to SRAM..." severity note;
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
			if (ram_address mod 25 = 0) then
				report "[NPU_TB] Inputs loaded: " & integer'image(ram_address) & " (SRAM addr " & integer'image(ram_address - 1) & ")." severity note;
			end if;
		end loop LOAD_X_LOOP;
		file_close(x_file);
		report "[NPU_TB] Inputs loaded to SRAM." severity note;
		wait for (5*clk_period);

		-- Write NPU weights to Single-Port SRAM (via MCU interface)
		report "[NPU_TB] Loading weights to SRAM..." severity note;
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
			weight_count := weight_count + 1;
			report "[NPU_TB] Weight " & integer'image(weight_count) & " loaded (value=" & integer'image(data) & ", SRAM addr " & integer'image(ram_address - 1) & ")." severity note;
		end loop LOAD_W_LOOP;
		file_close(w_file);
		report "[NPU_TB] Weights loaded to SRAM. Total weights: " & integer'image(weight_count) & "." severity note;
		wait for (5*clk_period);
		MabSramWEN	<= (others => MEM_DEASSERT);
		MabSramCEN	<= MEM_DEASSERT;

		----- Initialize Memory Mapped Register Values For First Layer
		report "[NPU_TB] Configuring MMRs for Layer 1..." severity note;
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
		report "[NPU_TB] Starting Layer 1 inference loop (" & integer'image(layer_loop) & " points)..." severity note;
		LAYER_1_LOOP: for i in 1 to layer_loop loop
			report "[NPU_TB] Layer 1: Point " & integer'image(i) & "/" & integer'image(layer_loop) & " - configuring MMRs." severity note;
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
			report "[NPU_TB] Layer 1: Point " & integer'image(i) & "/" & integer'image(layer_loop) & " - NPU activated, waiting for completion..." severity note;

			-- Wait for NPU THINK to complete (wait for it to go low)
			MabMmrCEN	<= MEM_ASSERT;
			MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
			wait until falling_edge(MabMmrCLK);
			wait until falling_edge(MabMmrQ(16));
			MabMmrCEN	<= MEM_DEASSERT;
			wait until falling_edge(MabMmrCLK);
			report "[NPU_TB] Layer 1: Point " & integer'image(i) & "/" & integer'image(layer_loop) & " - complete." severity note;
			-- Advance the input and output vector addresses for the next test point.
			x_address	:= x_address + 1;
			y_address	:= y_address + 5;
		end loop LAYER_1_LOOP;
		report "[NPU_TB] Layer 1 complete." severity note;


		----- Initialize Memory Mapped Register Values For Second Layer
		report "[NPU_TB] Configuring MMRs for Layer 2..." severity note;
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
		report "[NPU_TB] Starting Layer 2 inference loop (" & integer'image(layer_loop) & " points)..." severity note;
		x_address	:= 256;
		y_address	:= 0;
		LAYER_2_LOOP: for i in 1 to layer_loop loop
			report "[NPU_TB] Layer 2: Point " & integer'image(i) & "/" & integer'image(layer_loop) & " - configuring MMRs." severity note;
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
			report "[NPU_TB] Layer 2: Point " & integer'image(i) & "/" & integer'image(layer_loop) & " - NPU activated, waiting for completion..." severity note;

			-- Wait for NPU THINK to complete (wait for it to go low)
			MabMmrCEN	<= MEM_ASSERT;
			MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
			wait until falling_edge(MabMmrCLK);
			wait until falling_edge(MabMmrQ(16));
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN	<= MEM_DEASSERT;
			report "[NPU_TB] Layer 2: Point " & integer'image(i) & "/" & integer'image(layer_loop) & " - complete." severity note;
			-- Advance the input and output vector addresses for the next test point.
			x_address	:= x_address + 5;
			y_address	:= y_address + 1;
		end loop LAYER_2_LOOP;
		report "[NPU_TB] Layer 2 complete." severity note;

		----- Both layers are done: extract the output values and compare them against the MATLAB reference.
		report "[NPU_TB] Extracting output values from SRAM..." severity note;
		-- Read NPU outputs from Single-Port SRAM (via MCU interface)
		MabSramCEN	<= MEM_ASSERT;
		ram_address	:= 0;
		GET_Y_LOOP: for i in 1 to layer_loop loop
			wait until falling_edge(MabSramCLK);
			MabSramA	<= std_logic_vector(to_unsigned(ram_address, MabSramA'length));
			wait until falling_edge(MabSramCLK);
			readline(y_exp_file, y_exp_file_line);
			read(y_exp_file_line, data);
			-- Self-checking: tally mismatches as warnings rather than halting, so the whole output vector is compared and one banner reports the verdict.
			if (data /= to_integer(signed(MabSramQ((Y_M_BITS + N_BITS) downto 0)))) then
				error_count := error_count + 1;
				report "FAIL: point " & integer'image(i) & " output mismatch (Y_HW = "
						& integer'image(to_integer(signed(MabSramQ((Y_M_BITS + N_BITS) downto 0)))) & ", Y_SW = " & integer'image(data) & ")"
						severity warning;
			end if;
			write(y_out_file_line, to_integer(signed(MabSramQ((Y_M_BITS + N_BITS) downto 0))), left, 18);
			writeline(y_out_file, y_out_file_line);
			ram_address	:= ram_address + 1;
			if (i mod 25 = 0) or (i = layer_loop) then
				report "[NPU_TB] Outputs extracted: " & integer'image(i) & "/" & integer'image(layer_loop) & "." severity note;
			end if;
		end loop GET_Y_LOOP;
		wait until falling_edge(MabSramCLK);
		file_close(y_out_file);
		file_close(y_exp_file);
		wait for (5*clk_period);

		----------------------------------------------------------------------
		----- DP-SG Think-Done IRQ Test Phase (npu_irq_spec.md, vector 120) --
		----- NPUSR @ MmrAddrNPUSR=4 (THINKDONE, sticky W1C); NPUCR.19=TDIE --
		----------------------------------------------------------------------
		report "[NPU_TB] Starting NPU IRQ test phase (NEGCTRL=" & integer'image(NEGCTRL) & ")..." severity note;

		-- IRQ-a: after the two inference layers above, THINKDONE is sticky-set from the last completed THINK and nobody has touched NPUSR yet, so it must read 1.
		-- TDIE (NPUCR.19) is still 0 (reset default, and every Layer-1/2 CR write above explicitly wrote it 0), so the registered IRQ level must read 0. That is IE gating, way 1.
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUSR, MabMmrA'length));
		MabMmrWEN	<= (others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		wait until falling_edge(MabMmrCLK);
		if to_X01(MabMmrQ(0)) /= '1' then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-a): NPUSR.THINKDONE expected 1 after the Layer-2 THINK completions, read '"
					& std_logic'image(to_X01(MabMmrQ(0))) & "'" severity warning;
		end if;
		if to_X01(ThinkDoneIrq) /= '0' then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-a): ThinkDoneIrq expected 0 (TDIE=0 gates it off), read '"
					& std_logic'image(to_X01(ThinkDoneIrq)) & "'" severity warning;
		end if;
		MabMmrCEN	<= MEM_DEASSERT;
		report "[NPU_TB] IRQ-a: THINKDONE=1 / ThinkDoneIrq=0 (TDIE=0) OK." severity note;

		-- IRQ-b: set TDIE (NPUCR.19).
		-- WEN(2) gangs TDIE/NPUBEN/NPUAEN/NPUTHINK into one byte lane (see NPU.vhd MMR_WRITE), so supply the Layer-2 tail values for NPUBEN/NPUAEN ('0'/'0') and NPUTHINK='0' to make this a pure TDIE set that preserves every other CR field.
		-- WEN(0) and WEN(1) stay deasserted, so NPUNI and NPUNN are left completely untouched.
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		MabMmrD		<= (31 downto 20 => '0')	&
						'1'						&		-- TDIE = 1
						'0'						&		-- NPUBEN (Layer-2 tail value, preserved)
						'0'						&		-- NPUAEN (Layer-2 tail value, preserved)
						'0'						&		-- NPUTHINK = 0 (do not start a THINK here)
						(15 downto 0 => '0');
		MabMmrWEN	<= (2 => MEM_ASSERT, others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrWEN	<= (others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_DEASSERT;
		-- Registered level, one output flop: sample within 2 Clk (bounded).
		for k in 1 to 2 loop
			wait until rising_edge(Clk);
		end loop;
		if to_X01(ThinkDoneIrq) /= '1' then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-b): ThinkDoneIrq expected 1 within 2 Clk of TDIE=1 (THINKDONE already 1), read '"
					& std_logic'image(to_X01(ThinkDoneIrq)) & "'" severity warning;
		end if;
		report "[NPU_TB] IRQ-b: TDIE=1 -> ThinkDoneIrq=1 within 2 Clk OK." severity note;

		-- IRQ-c: W1C semantics of NPUSR.
		-- A write of 0 must be IGNORED, leaving flag and IRQ asserted; a write of 1 clears the flag and drops the IRQ within 2 Clk.
		-- NEGCTRL=1 skips the clearing write below while the checks still expect flag and IRQ cleared, so those checks must then FAIL.
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUSR, MabMmrA'length));
		MabMmrD		<= (31 downto 1 => '0') & '0';
		MabMmrWEN	<= (0 => MEM_ASSERT, others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrWEN	<= (others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_DEASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUSR, MabMmrA'length));
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		wait until falling_edge(MabMmrCLK);
		if to_X01(MabMmrQ(0)) /= '1' then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-c): NPUSR.THINKDONE expected to STAY 1 after a write-0 (W1C ignores 0), read '"
					& std_logic'image(to_X01(MabMmrQ(0))) & "'" severity warning;
		end if;
		if to_X01(ThinkDoneIrq) /= '1' then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-c): ThinkDoneIrq expected to STAY 1 after a write-0 to NPUSR, read '"
					& std_logic'image(to_X01(ThinkDoneIrq)) & "'" severity warning;
		end if;
		MabMmrCEN	<= MEM_DEASSERT;
		report "[NPU_TB] IRQ-c(write-0): flag/IRQ unaffected OK." severity note;

		-- The W1C clear write itself, skipped in the negative control so the checks that follow are forced to fail.
		if (NEGCTRL /= 1) then
			wait until falling_edge(MabMmrCLK);
			MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUSR, MabMmrA'length));
			MabMmrD		<= (31 downto 1 => '0') & '1';
			MabMmrWEN	<= (0 => MEM_ASSERT, others => MEM_DEASSERT);
			MabMmrCEN	<= MEM_ASSERT;
			wait until falling_edge(MabMmrCLK);
			MabMmrWEN	<= (others => MEM_DEASSERT);
			MabMmrCEN	<= MEM_DEASSERT;
		else
			report "[NPU_TB] NEGCTRL=1: deliberately SKIPPING the W1C clear write (IRQ-c) -- flag/IRQ must stay asserted and the checks below must FAIL." severity warning;
		end if;
		for k in 1 to 2 loop
			wait until rising_edge(Clk);
		end loop;
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUSR, MabMmrA'length));
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		wait until falling_edge(MabMmrCLK);
		if to_X01(MabMmrQ(0)) /= '0' then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-c): NPUSR.THINKDONE expected 0 after the W1C write, read '"
					& std_logic'image(to_X01(MabMmrQ(0))) & "'" severity warning;
		end if;
		if to_X01(ThinkDoneIrq) /= '0' then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-c): ThinkDoneIrq expected 0 within 2 Clk of the W1C write, read '"
					& std_logic'image(to_X01(ThinkDoneIrq)) & "'" severity warning;
		end if;
		MabMmrCEN	<= MEM_DEASSERT;
		report "[NPU_TB] IRQ-c(W1C write-1): flag/IRQ cleared check complete." severity note;

		-- IRQ-d: a second, short 1-input/1-neuron pass-through THINK, reusing the Layer-1 input already staged at SRAM addr 0 and a Layer-1 weight already staged at addr 2048.
		-- Its output is parked at addr 3000, well clear of every address the inference passes above read or wrote.
		-- TDIE is still 1 from IRQ-b (the W1C write does not touch it), so the IRQ must fire again exactly once.
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUIVSAR, MabMmrA'length));
		MabMmrWEN	<= (others => MEM_ASSERT);
		MabMmrD		<= (31 downto 12 => '0') & std_logic_vector(to_unsigned(0, 12));
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_DEASSERT;

		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUWVSAR, MabMmrA'length));
		MabMmrD		<= (31 downto 12 => '0') & std_logic_vector(to_unsigned(2048, 12));
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_DEASSERT;

		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUOVSAR, MabMmrA'length));
		MabMmrD		<= (31 downto 12 => '0') & std_logic_vector(to_unsigned(3000, 12));
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_DEASSERT;

		-- NPU Control Register: 1 input (NPUNI=0), 1 neuron (NPUNN=0), no bias, no activation (pass-through), TDIE preserved at 1, THINK=1.
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		MabMmrD		<=	(31 downto 20 => '0')					&
						'1'										&		-- TDIE preserved = 1
						'0'										&		-- NPUBEN disabled
						'0'										&		-- NPUAEN disabled (pass-through)
						'1'										&		-- Activate NPU
						std_logic_vector(to_unsigned(0, 8))		&		-- NPU # Of Inputs = 1 (0+1)
						std_logic_vector(to_unsigned(0, 8));			-- NPU # Of Neurons = 1 (0+1)
		MabMmrWEN	<= (others => MEM_ASSERT);
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrWEN	<= (others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_DEASSERT;

		-- Bounded poll for completion (never an unbounded "wait until").
		think_poll_i := 0;
		MabMmrCEN	<= MEM_ASSERT;
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		wait until falling_edge(MabMmrCLK);
		while (to_X01(MabMmrQ(16)) = '1') and (think_poll_i < THINK_POLL_MAX) loop
			wait until falling_edge(MabMmrCLK);
			think_poll_i := think_poll_i + 1;
		end loop;
		MabMmrCEN	<= MEM_DEASSERT;
		if think_poll_i >= THINK_POLL_MAX then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-d): 2nd THINK did not complete within " & integer'image(THINK_POLL_MAX) &
					" bounded poll cycles" severity warning;
		end if;

		-- 4 Clk, not 2: the bounded MabMmrCLK falling-edge poll above can see NPUTHINK clear up to 1 cycle later than the original bench's `wait until falling_edge(MabMmrQ(16))` idiom would, because that waits on the SIGNAL's own edge while polling on fixed clock edges can catch it a cycle late.
		-- That slack sits ON TOP of the real 2-cycle NpuDone then THINKDONE then ThinkDoneIrqQ pipeline (THINKDONE_SEQ reads last cycle's NpuDone/THINKDONE, never the same-edge value).
		-- Traced with xmsim `value` probes on NPU_INST:{NpuDone,THINKDONE,ThinkDoneIrqQ}: NpuDone pulses on cycle N, THINKDONE reads 1 at N+1, ThinkDoneIrqQ reads 1 at N+2.
		-- A fixed 2-cycle wait from our poll's (up to 1-cycle-late) exit therefore landed exactly 1 cycle short.
		for k in 1 to 4 loop
			wait until rising_edge(Clk);
		end loop;
		if to_X01(ThinkDoneIrq) /= '1' then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-d): ThinkDoneIrq expected 1 after the 2nd THINK completed (TDIE still 1), read '"
					& std_logic'image(to_X01(ThinkDoneIrq)) & "'" severity warning;
		end if;
		report "[NPU_TB] IRQ-d: 2nd THINK fired ThinkDoneIrq again OK." severity note;

		-- W1C-clear, then prove the fires-exactly-once-per-THINK property: with no new THINK the level must STAY 0 for 50 Clk cycles.
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUSR, MabMmrA'length));
		MabMmrD		<= (31 downto 1 => '0') & '1';
		MabMmrWEN	<= (0 => MEM_ASSERT, others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrWEN	<= (others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_DEASSERT;
		for k in 1 to 2 loop
			wait until rising_edge(Clk);
		end loop;
		if to_X01(ThinkDoneIrq) /= '0' then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-d): ThinkDoneIrq expected 0 within 2 Clk of the W1C clear, read '"
					& std_logic'image(to_X01(ThinkDoneIrq)) & "'" severity warning;
		end if;
		for k in 1 to 50 loop
			wait until rising_edge(Clk);
			if to_X01(ThinkDoneIrq) /= '0' then
				irq_error_count := irq_error_count + 1;
				report "FAIL(IRQ-d): ThinkDoneIrq re-asserted at cycle " & integer'image(k) &
						" with no new THINK -- IRQ must fire exactly once per THINK" severity warning;
				exit;
			end if;
		end loop;
		report "[NPU_TB] IRQ-d: once-per-THINK property holds (50 Clk quiet check) OK." severity note;

		-- IRQ-e: a third short THINK (same pass-through config) re-arms THINKDONE and fires the IRQ once more, TDIE still being 1.
		-- Clearing TDIE must then drop the IRQ immediately while NPUSR.THINKDONE keeps reading 1. That is IE gating, way 2: the flag is TDIE-independent.
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		MabMmrD		<=	(31 downto 20 => '0')					&
						'1'										&		-- TDIE preserved = 1
						'0'										&
						'0'										&
						'1'										&		-- Activate NPU
						std_logic_vector(to_unsigned(0, 8))		&
						std_logic_vector(to_unsigned(0, 8));
		MabMmrWEN	<= (others => MEM_ASSERT);
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrWEN	<= (others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_DEASSERT;

		think_poll_i := 0;
		MabMmrCEN	<= MEM_ASSERT;
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		wait until falling_edge(MabMmrCLK);
		while (to_X01(MabMmrQ(16)) = '1') and (think_poll_i < THINK_POLL_MAX) loop
			wait until falling_edge(MabMmrCLK);
			think_poll_i := think_poll_i + 1;
		end loop;
		MabMmrCEN	<= MEM_DEASSERT;
		if think_poll_i >= THINK_POLL_MAX then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-e): 3rd THINK did not complete within " & integer'image(THINK_POLL_MAX) &
					" bounded poll cycles" severity warning;
		end if;

		-- 4 Clk margin, on the same poll-phase plus 2-cycle pipeline reasoning as IRQ-d above.
		for k in 1 to 4 loop
			wait until rising_edge(Clk);
		end loop;
		if to_X01(ThinkDoneIrq) /= '1' then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-e): ThinkDoneIrq expected 1 after the 3rd THINK completed, read '"
					& std_logic'image(to_X01(ThinkDoneIrq)) & "'" severity warning;
		end if;

		-- Clear TDIE only, through the WEN(2) lane with NPUBEN/NPUAEN/NPUTHINK all 0.
		-- NPUSR must not be touched here: THINKDONE has to stay sticky-1.
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		MabMmrD		<= (31 downto 20 => '0') & '0' & '0' & '0' & '0' & (15 downto 0 => '0');
		MabMmrWEN	<= (2 => MEM_ASSERT, others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrWEN	<= (others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_DEASSERT;
		for k in 1 to 2 loop
			wait until rising_edge(Clk);
		end loop;
		if to_X01(ThinkDoneIrq) /= '0' then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-e): ThinkDoneIrq expected 0 within 2 Clk of clearing TDIE, read '"
					& std_logic'image(to_X01(ThinkDoneIrq)) & "'" severity warning;
		end if;
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUSR, MabMmrA'length));
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		wait until falling_edge(MabMmrCLK);
		if to_X01(MabMmrQ(0)) /= '1' then
			irq_error_count := irq_error_count + 1;
			report "FAIL(IRQ-e): NPUSR.THINKDONE expected to STAY 1 after clearing TDIE (flag is TDIE-independent), read '"
					& std_logic'image(to_X01(MabMmrQ(0))) & "'" severity warning;
		end if;
		MabMmrCEN	<= MEM_DEASSERT;
		report "[NPU_TB] IRQ-e: clearing TDIE drops ThinkDoneIrq while THINKDONE stays 1 (IE gating way 2) OK." severity note;

		report "[NPU_TB] NPU IRQ test phase complete (" & integer'image(irq_error_count) & " check(s) failed)." severity note;

		----- IRQ Phase Verdict -----
		if irq_error_count = 0 then
			report LF & LF &
				"    ##################################################" & LF &
				"    ##                                              ##" & LF &
				"    ##       NPU IRQ TESTS PASSED                   ##" & LF &
				"    ##                                              ##" & LF &
				"    ##################################################" & LF
				severity note;
		else
			report LF & LF &
				"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
				"    !!                                              !!" & LF &
				"    !!    NPU IRQ TESTS FAILED: " & integer'image(irq_error_count) &
					   " CHECK(S) FAILED" & LF &
				"    !!                                              !!" & LF &
				"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
				severity warning;
		end if;
		error_count := error_count + irq_error_count;

		----------------------------------------------------------------------
		----- EVFAB task_think Test Phase (event_fabric_spec.md, 2026-07-24) -
		----- Fabric task port: one-MabMmrCLK pulse starts a THINK exactly  --
		----- like an NPUCR bit-16 register write, outside CEN, after the   --
		----- register case (task wins a coincident write); the trailing   --
		----- NpuDone/reset clear still wins over both paths.               --
		----------------------------------------------------------------------
		report "[NPU_TB] Starting EVFAB task_think test phase..." severity note;

		-- Reuse the exact pass-through descriptor already proven by IRQ-d/e: IVSAR=0 (Layer-1 x[0] still staged), WVSAR=2048 (Layer-1 w[0] still staged), NI=0 (1 input), NN=0 (1 neuron), no bias, no activation.
		-- EVFAB-a: launch via the REGISTER path (bit 16) to a fresh output address (3100) to establish the reference value.
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUIVSAR, MabMmrA'length));
		MabMmrWEN	<= (others => MEM_ASSERT);
		MabMmrD		<= (31 downto 12 => '0') & std_logic_vector(to_unsigned(0, 12));
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_DEASSERT;

		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUWVSAR, MabMmrA'length));
		MabMmrD		<= (31 downto 12 => '0') & std_logic_vector(to_unsigned(2048, 12));
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_DEASSERT;

		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUOVSAR, MabMmrA'length));
		MabMmrD		<= (31 downto 12 => '0') & std_logic_vector(to_unsigned(3100, 12));
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_DEASSERT;

		-- Register-launched THINK (NPUCR bit 16 = 1 via a normal write).
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		MabMmrD		<=	(31 downto 20 => '0')					&
						'0'										&		-- TDIE = 0
						'0'										&		-- NPUBEN disabled
						'0'										&		-- NPUAEN disabled (pass-through)
						'1'										&		-- Activate NPU (register path)
						std_logic_vector(to_unsigned(0, 8))		&		-- NI = 1 (0+1)
						std_logic_vector(to_unsigned(0, 8));			-- NN = 1 (0+1)
		MabMmrWEN	<= (others => MEM_ASSERT);
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrWEN	<= (others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_DEASSERT;

		evfab_poll_i := 0;
		MabMmrCEN	<= MEM_ASSERT;
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		wait until falling_edge(MabMmrCLK);
		while (to_X01(MabMmrQ(16)) = '1') and (evfab_poll_i < THINK_POLL_MAX) loop
			wait until falling_edge(MabMmrCLK);
			evfab_poll_i := evfab_poll_i + 1;
		end loop;
		MabMmrCEN	<= MEM_DEASSERT;
		if evfab_poll_i >= THINK_POLL_MAX then
			evfab_error_count := evfab_error_count + 1;
			report "FAIL(EVFAB-a): register-launched reference THINK did not complete within " &
					integer'image(THINK_POLL_MAX) & " bounded poll cycles" severity warning;
		end if;

		-- Read the reference (register-launched) output.
		MabSramCEN	<= MEM_ASSERT;
		wait until falling_edge(MabSramCLK);
		MabSramA	<= std_logic_vector(to_unsigned(3100, MabSramA'length));
		wait until falling_edge(MabSramCLK);
		reg_launch_val := to_integer(signed(MabSramQ((Y_M_BITS + N_BITS) downto 0)));
		report "[NPU_TB] EVFAB-a: register-launched reference value = " & integer'image(reg_launch_val) & "." severity note;

		-- EVFAB-b: retarget OVSAR only, to a fresh address, leaving NPUCR alone so this write cannot disturb NPUTHINK (WEN(2) stays deasserted).
		-- Then launch the SAME descriptor with a single task_think pulse on MabMmrCLK instead of a register write.
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUOVSAR, MabMmrA'length));
		MabMmrWEN	<= (others => MEM_ASSERT);
		MabMmrD		<= (31 downto 12 => '0') & std_logic_vector(to_unsigned(3110, 12));
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrWEN	<= (others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_DEASSERT;

		-- One-MabMmrCLK task_think pulse, with CEN left DEASSERTED throughout to prove the task path acts outside the CEN qualifier.
		wait until falling_edge(MabMmrCLK);
		task_think	<= '1';
		wait until falling_edge(MabMmrCLK);
		task_think	<= '0';
		report "[NPU_TB] EVFAB-b: task_think pulsed for one MabMmrCLK (CEN deasserted throughout)." severity note;

		-- EVFAB-c (NpuActive check): sample within a couple of Clk of the pulse.
		-- NPUCR bit 16 must read 1, meaning the task started the THINK exactly like a register write, and NpuActive must read 1, the busy level the fabric consumes (no new busy port was added).
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		if to_X01(MabMmrQ(16)) /= '1' then
			evfab_error_count := evfab_error_count + 1;
			report "FAIL(EVFAB-c): NPUCR bit 16 expected 1 shortly after the task_think pulse (task-started THINK running), read '"
					& std_logic'image(to_X01(MabMmrQ(16))) & "'" severity warning;
		end if;
		if to_X01(NpuActive) /= '1' then
			evfab_error_count := evfab_error_count + 1;
			report "FAIL(EVFAB-c): NpuActive expected 1 while the task-started THINK is running, read '"
					& std_logic'image(to_X01(NpuActive)) & "'" severity warning;
		end if;
		MabMmrCEN	<= MEM_DEASSERT;
		report "[NPU_TB] EVFAB-c: NPUCR.16=1 / NpuActive=1 during the task-started THINK OK." severity note;

		-- Poll to completion (bounded), then confirm the trailing clear and that NpuActive drops.
		evfab_poll_i := 0;
		MabMmrCEN	<= MEM_ASSERT;
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		wait until falling_edge(MabMmrCLK);
		while (to_X01(MabMmrQ(16)) = '1') and (evfab_poll_i < THINK_POLL_MAX) loop
			wait until falling_edge(MabMmrCLK);
			evfab_poll_i := evfab_poll_i + 1;
		end loop;
		MabMmrCEN	<= MEM_DEASSERT;
		if evfab_poll_i >= THINK_POLL_MAX then
			evfab_error_count := evfab_error_count + 1;
			report "FAIL(EVFAB-b): task-started THINK did not complete within " &
					integer'image(THINK_POLL_MAX) & " bounded poll cycles" severity warning;
		end if;

		for k in 1 to 4 loop
			wait until rising_edge(Clk);
		end loop;
		if to_X01(NpuActive) /= '0' then
			evfab_error_count := evfab_error_count + 1;
			report "FAIL(EVFAB-c): NpuActive expected 0 after the task-started THINK completed, read '"
					& std_logic'image(to_X01(NpuActive)) & "'" severity warning;
		end if;
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		if to_X01(MabMmrQ(16)) /= '0' then
			evfab_error_count := evfab_error_count + 1;
			report "FAIL(EVFAB-b): NPUCR bit 16 expected 0 after the task-started THINK completed (trailing clear), read '"
					& std_logic'image(to_X01(MabMmrQ(16))) & "'" severity warning;
		end if;
		MabMmrCEN	<= MEM_DEASSERT;

		-- EVFAB-b verdict: the task-started output must match the register-launched reference exactly, same descriptor and same inputs and weights.
		MabSramCEN	<= MEM_ASSERT;
		wait until falling_edge(MabSramCLK);
		MabSramA	<= std_logic_vector(to_unsigned(3110, MabSramA'length));
		wait until falling_edge(MabSramCLK);
		task_launch_val := to_integer(signed(MabSramQ((Y_M_BITS + N_BITS) downto 0)));
		if task_launch_val /= reg_launch_val then
			evfab_error_count := evfab_error_count + 1;
			report "FAIL(EVFAB-b): task-launched THINK output mismatch (task = " &
					integer'image(task_launch_val) & ", register-launched reference = " &
					integer'image(reg_launch_val) & ")" severity warning;
		end if;
		report "[NPU_TB] EVFAB-b: task-launched value = " & integer'image(task_launch_val) &
				" (register-launched reference = " & integer'image(reg_launch_val) & ") OK." severity note;

		-- EVFAB-d (pulse-only contract): the pulse must be consumed exactly once.
		-- Confirm no second THINK auto-started, with a bounded quiet poll where bit 16 stays 0, and that the output is unchanged on a re-read.
		for k in 1 to 50 loop
			wait until rising_edge(Clk);
			if (k mod 10) = 0 then
				wait until falling_edge(MabMmrCLK);
				MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
				MabMmrCEN	<= MEM_ASSERT;
				wait until falling_edge(MabMmrCLK);
				if to_X01(MabMmrQ(16)) /= '0' then
					evfab_error_count := evfab_error_count + 1;
					report "FAIL(EVFAB-d): NPUCR bit 16 re-asserted at quiet-check " & integer'image(k) &
							" -- the task_think pulse must be consumed exactly once" severity warning;
				end if;
				MabMmrCEN	<= MEM_DEASSERT;
			end if;
		end loop;
		MabSramCEN	<= MEM_ASSERT;
		wait until falling_edge(MabSramCLK);
		MabSramA	<= std_logic_vector(to_unsigned(3110, MabSramA'length));
		wait until falling_edge(MabSramCLK);
		task_launch_val2 := to_integer(signed(MabSramQ((Y_M_BITS + N_BITS) downto 0)));
		if task_launch_val2 /= task_launch_val then
			evfab_error_count := evfab_error_count + 1;
			report "FAIL(EVFAB-d): task-launched output changed after the pulse-only quiet check (was " &
					integer'image(task_launch_val) & ", now " & integer'image(task_launch_val2) & ")" severity warning;
		end if;
		report "[NPU_TB] EVFAB-d: pulse consumed exactly once (50 Clk quiet check), output stable OK." severity note;

		-- EVFAB-e: a coincident register write and task pulse on the same MabMmrCLK edge.
		-- The register write carries NPUCR bit 16 = 0, so it does NOT ask for a THINK by itself, while task_think fires on the SAME edge.
		-- Task processing sits AFTER the register case in the same clocked process, so the task path wins the coincidence and a THINK must start whatever the register write's bit 16 carried.
		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUOVSAR, MabMmrA'length));
		MabMmrWEN	<= (others => MEM_ASSERT);
		MabMmrD		<= (31 downto 12 => '0') & std_logic_vector(to_unsigned(3120, 12));
		wait until falling_edge(MabMmrCLK);
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		MabMmrWEN	<= (others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_DEASSERT;

		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		MabMmrD		<=	(31 downto 20 => '0')					&
						'0'										&		-- TDIE = 0
						'0'										&		-- NPUBEN disabled
						'0'										&		-- NPUAEN disabled
						'0'										&		-- THINK = 0 in the coincident WRITE (task must still win)
						std_logic_vector(to_unsigned(0, 8))		&
						std_logic_vector(to_unsigned(0, 8));
		MabMmrWEN	<= (others => MEM_ASSERT);
		MabMmrCEN	<= MEM_ASSERT;
		task_think	<= '1';						-- same edge as the register write above
		wait until falling_edge(MabMmrCLK);
		MabMmrWEN	<= (others => MEM_DEASSERT);
		MabMmrCEN	<= MEM_DEASSERT;
		task_think	<= '0';

		wait until falling_edge(MabMmrCLK);
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		MabMmrCEN	<= MEM_ASSERT;
		wait until falling_edge(MabMmrCLK);
		if to_X01(MabMmrQ(16)) /= '1' then
			evfab_error_count := evfab_error_count + 1;
			report "FAIL(EVFAB-e): NPUCR bit 16 expected 1 after a coincident register-write(bit16=0)+task_think pulse (task must win), read '"
					& std_logic'image(to_X01(MabMmrQ(16))) & "'" severity warning;
		end if;
		MabMmrCEN	<= MEM_DEASSERT;
		report "[NPU_TB] EVFAB-e: coincident NPUCR write (bit16=0) + task_think pulse still started a THINK OK." severity note;

		-- Drain this THINK (bounded) so the bench ends idle.
		evfab_poll_i := 0;
		MabMmrCEN	<= MEM_ASSERT;
		MabMmrA		<= std_logic_vector(to_unsigned(MmrAddrNPUCR, MabMmrA'length));
		wait until falling_edge(MabMmrCLK);
		while (to_X01(MabMmrQ(16)) = '1') and (evfab_poll_i < THINK_POLL_MAX) loop
			wait until falling_edge(MabMmrCLK);
			evfab_poll_i := evfab_poll_i + 1;
		end loop;
		MabMmrCEN	<= MEM_DEASSERT;
		if evfab_poll_i >= THINK_POLL_MAX then
			evfab_error_count := evfab_error_count + 1;
			report "FAIL(EVFAB-e): coincident-launched THINK did not complete within " &
					integer'image(THINK_POLL_MAX) & " bounded poll cycles" severity warning;
		end if;

		report "[NPU_TB] EVFAB task_think test phase complete (" & integer'image(evfab_error_count) & " check(s) failed)." severity note;

		----- EVFAB Phase Verdict -----
		if evfab_error_count = 0 then
			report LF & LF &
				"    ##################################################" & LF &
				"    ##                                              ##" & LF &
				"    ##       NPU EVFAB TASK_THINK TESTS PASSED      ##" & LF &
				"    ##                                              ##" & LF &
				"    ##################################################" & LF
				severity note;
		else
			report LF & LF &
				"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
				"    !!                                              !!" & LF &
				"    !!    NPU EVFAB TASK_THINK TESTS FAILED: " & integer'image(evfab_error_count) &
					   " CHECK(S) FAILED" & LF &
				"    !!                                              !!" & LF &
				"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
				severity warning;
		end if;
		error_count := error_count + evfab_error_count;

		----- Final verdict -----
		if error_count = 0 then
			report LF & LF &
				"    ##################################################" & LF &
				"    ##                                              ##" & LF &
				"    ##         NPU TB:  ALL CHECKS PASSED           ##" & LF &
				"    ##                                              ##" & LF &
				"    ##################################################" & LF
				severity note;
		else
			report LF & LF &
				"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
				"    !!                                              !!" & LF &
				"    !!    NPU TB:  " & integer'image(error_count) &
					   " CHECK(S) FAILED" & LF &
				"    !!                                              !!" & LF &
				"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
				severity warning;
		end if;

		stop;
		wait;
	end process SIM_PROCESS;
end testbench;
