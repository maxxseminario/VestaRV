----- VHDL Libraries
-- IEEE Standard Libraries
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.constants.all;
use work.MemoryMap.all;
-- Synthesizable Fixed Point libraries created by David Bishop for VHDL 2008 (Compatible with '93)
use work.fixed_float_types.all;
use work.fixed_pkg.all;


-- Fixed-Point Hardware MLPNN implementation for use as peripheral. 
	-- Hardware Configuration:	Fractional & Integer bits set at instantiation
	--							RHO of sigmoid approximation set at instantiation
	-- Software Configuration:	Enabling/Disabling Bias (NPUBEN)
	--							Enabling/Disabling Activation Function (NPUAEN)
	--							Number of inputs (NPUNI + 1)
	--							Number of neurons/outputs (NPUNN + 1)
	--							Starting NPU (NPUTHINK)
	--							SRAM Start Address For Inputs (NPUIVSAR)
	--							SRAM Weight Address For Inputs (NPUWVSAR)
	--							SRAM Output Address For Inputs (NPUOVSAR)
entity NPU is
    generic(
		-- Fixed-Point M and N Bits for inputs, weights, and outputs
		-- Of note, Y bits also control size of accumulator
    	X_M_BITS		: integer := 0;
        W_M_BITS		: integer := 3;
        Y_M_BITS		: integer := 3;
		N_BITS			: integer := 15;
		-- RHO to be used with sigmoid approximation
		RHO				: integer := 2
    );
    port(
		-- System Signals
        Clk				: in	std_logic;					-- NPU Main Clock
        ResetN			: in	std_logic;					-- NPU Active-Low Reset

		-- Memory Address Bus to Memory Mapped Registers Signals
		MabMmrA			: in 	std_logic_vector(1 downto 0);	-- MCU To NPU MMR - Address
		MabMmrD			: in	std_logic_vector(31 downto 0);	-- MCU To NPU MMR - Data Input
		MabMmrCLK		: in	std_logic;						-- MCU To NPU MMR - Clock
		MabMmrCEN		: in	std_logic;						-- MCU To NPU MMR - Chip Enable
		MabMmrWEN		: in	std_logic_vector(3 downto 0);	-- MCU To NPU MMR - Write Enable
		MabMmrQ			: out 	std_logic_vector(31 downto 0);	-- MCU To NPU MMR - Data Output

		-- Multiplexed SRAM Signals from MCU
		SramQ_in		: in	std_logic_vector(31 downto 0);	-- MCU To NPU - Data Output
		SramA_in 		: in	std_logic_vector(11 downto 0);	-- SRAM To NPU - Address
		SramD_in 		: in	std_logic_vector(31 downto 0);	-- SRAM To NPU - Data Input
		SramCLK_in 		: in	std_logic;						-- SRAM To NPU - Clock
		SramCEN_in 		: in	std_logic;						-- SRAM To NPU - Chip Enable
		SramGWEN_in 	: in	std_logic;						-- SRAM To NPU - Global Write Enable
		SramWEN_in 		: in	std_logic_vector(3 downto 0);	-- SRAM To NPU - Write Enable
	
		-- NPU to SRAM Interface Signals
		NpuSramA_out		: out	std_logic_vector(11 downto 0);	-- NPU To SRAM - Address 
		NpuSramD_out		: out	std_logic_vector(31 downto 0);	-- NPU To SRAM - Data Input
		NpuSramCLK_out		: out 	std_logic;						-- NPU To SRAM - Clock
		NpuSramCEN_out		: out	std_logic;						-- NPU To SRAM - Chip Enable
		NpuSramGWEN_out		: out 	std_logic;						-- NPU To SRAM - Global Write Enable
		NpuSramWEN_out		: out 	std_logic_vector(3 downto 0);	-- NPU To SRAM - Write Enable
		-- NPU Status Signal
		NpuActive		: out	std_logic						-- NPU Active Signal for Arbitration
    );
end NPU;

architecture behavioral of NPU is
	----- Constants
	-- Memory Assert/Deassert Constants (Active Low)
	constant MEM_ASSERT			: std_logic	:= '0';	
	constant MEM_DEASSERT		: std_logic	:= '1';


	----- Memory Mapped Registers & Bits
	signal NPUCR		: std_logic_vector(18 downto 0);		-- NPU Control Register
		signal NPUBEN	: std_logic;								-- NPU Bias Input Enable Bit (Enabled For First Layer)
		signal NPUAEN	: std_logic;								-- NPU Activation Function Enable Bit (Disabled for Last Layer)
		signal NPUTHINK	: std_logic;								-- NPU Start/Status Bit
		signal NPUNI	: std_logic_vector(7 downto 0);			-- NPU # Of Inputs
		signal NPUNN	: std_logic_vector(7 downto 0);			-- NPU # Of Neurons/Outputs
	signal NPUIVSAR		: std_logic_vector(11 downto 0);		-- NPU Input Vector Start Address Register
	signal NPUWVSAR		: std_logic_vector(11 downto 0);		-- NPU Weight Vector Start Address Register
	signal NPUOVSAR		: std_logic_vector(11 downto 0);		-- NPU Output Vector Start Address Register

	-- NPU to SRAM (Output) Signals 
	signal NpuSramA		: std_logic_vector(11 downto 0);		-- NPU To NPU DP SRAM - Address 			(Combinational)
	signal NpuSramD		: std_logic_vector(31 downto 0);		-- MCU To NPU DP SRAM - Data Inputs			(Combinational)
	signal NpuSramCLK	: std_logic;							-- MCU To NPU DP SRAM - Clock				(Combinational)
	signal NpuSramCEN	: std_logic;							-- MCU To NPU DP SRAM - Chip Enable 		(Flip-Flop)
	signal NpuSramGWEN	: std_logic;							-- MCU To NPU DP SRAM - Global Write Enable	(Combinational)
	signal NpuSramWEN	: std_logic_vector(3 downto 0);			-- MCU To NPU DP SRAM - Write Enable		(Conbinational)

	----- NPU Internal Signals
	-- Registers & Flip Flops
	type npu_state_type is (NPU_BEGIN, NPU_GET_INPUT, 				
							NPU_GET_WEIGHT, NPU_MAC, 
							NPU_SET_OUTPUT, NPU_FINISH);		-- NPU FSM State Types

	signal NpuState		: npu_state_type;						-- NPU FSM State
	signal CurrX 		: std_logic_vector
							((X_M_BITS + N_BITS) downto 0);		-- Current Input
	signal CurrXIndex	: unsigned(7 downto 0);					-- Current Input's Index (0-255)
	signal CurrW		: std_logic_vector
							((W_M_BITS + N_BITS) downto 0);		-- Current Weight
	signal CurrWAddr	: unsigned(11 downto 0);				-- Current Weight's Address (0-4095)
	signal CurrYIndex	: unsigned(7 downto 0);					-- Current Outputs's Index (0-255)
	signal AccOutLtchd	: std_logic_vector
							((Y_M_BITS+N_BITS) downto 0);		-- M & Accumulator Output Latched
	signal BiasDone		: std_logic;							-- Bias Done For Current Neuron Flag Signal
	signal NpuDone		: std_logic;							-- NPU Done Flag Signal
	signal MemReady		: std_logic;							-- SRAM Ready For Read/Write Flag Signal
	signal AccResetN	: std_logic;							-- MAC Active Low Reset Signal
	-- Combinational Signals
	signal NpuClk		: std_logic; 							-- Internal NPU Clock
	signal NpuClkEn		: std_logic; 							-- Internal NPU Clock Enable
	signal MacClk		: std_logic; 							-- Internal MAC Clock
	signal MacClkEn		: std_logic; 							-- Internal MAC Clock
	signal SramClkEn	: std_logic; 							-- SRAM's Clock Enable
	signal NeuronDone	: std_logic;							-- Current Neuron Done Flag Signal
	signal CurrXAddr	: unsigned(11 downto 0);				-- Current Input's Address (0-4095)
	signal CurrYAddr	: unsigned(11 downto 0);				-- Current Output's Address (0-4095)
	signal MacOut 		: std_logic_vector
			((Y_M_BITS+N_BITS) downto 0);						-- MAC Combinational Output
	signal Decision		: std_logic_vector(N_BITS downto 0); 	-- Decision Signal (Output Of Activation Fucntion)	
	signal MabMmrAInt	: natural range 0 to 63;

begin

	----------------------------------------------
	----- Muxed SRAM Memory Bus Multiplexer ------
	----------------------------------------------
	NpuSramA_out 	<= SramA_in when (NPUTHINK = '0') else NpuSramA; 
	NpuSramD_out 	<= SramD_in when (NPUTHINK = '0') else NpuSramD;
	NpuSramCLK_out 	<= SramCLK_in when (NPUTHINK = '0') else NpuSramCLK;
	NpuSramCEN_out 	<= SramCEN_in when (NPUTHINK = '0') else NpuSramCEN;
	NpuSramGWEN_out <= SramGWEN_in when (NPUTHINK = '0') else NpuSramGWEN;
	NpuSramWEN_out 	<= SramWEN_in when (NPUTHINK = '0') else NpuSramWEN;

	-------------------------------------
	----- Component Instantiations ------
	-------------------------------------
	-- NPU Clock Gate
	NPU_CLK_CG: entity work.ClkGate
	port map(
		ClkIn	=> Clk,
		En		=> NpuClkEn,
		ClkOut	=> NpuClk
	);
	-- MAC Clock Gate (Controls when MAC Accumulates)
	MAC_CLK_CG: entity work.ClkGate
	port map(
		ClkIn	=> Clk,
		En		=> MacClkEn,
		ClkOut	=> MacClk
	);
	-- SRAM Clock Gate
	SRAM_CLK_CG: entity work.ClkGate
	port map(
		ClkIn	=> Clk,
		En		=> SramClkEn,
		ClkOut	=> NpuSramCLK
	);
	-- Fixed-Point Multiply & Accumulate Instantiation
	NPU_FPMAC: entity work.FPMac
	generic map(
		A_M_BITS	=> X_M_BITS,
        B_M_BITS	=> W_M_BITS,
		ACC_M_BITS	=> Y_M_BITS,
		N_BITS	=> N_BITS
	)
	port map(
		Clk			=> MacClk,
		ResetN		=> AccResetN,
		A 			=> CurrX,
		B 			=> CurrW,
		Y			=> MacOut,
		YAcc		=> open
	);
	-- Fixed-Point Sigmoid Approximator Instantiation
	NPU_FPSIGMOID: entity work.FPSigmoid
	generic map(
		X_M_BITS	=> Y_M_BITS,
		XY_N_BITS	=> N_BITS,
		RHO			=> RHO
	)
	port map(
		X			=> AccOutLtchd,
		Y			=> Decision
	);

	--------------------------------------
	----- NPU Internal Functionality -----
	--------------------------------------
	NpuActive <= NPUTHINK;

	
	----- Sequential Logic
	-- NPU Control FSM
	NPU_FSM_SEQ: process(NpuClk, ResetN)
	begin
		if (ResetN = '0') then				-- Asynchronous Active-Low Reset
			-- Signals reset initial values
			NpuState <= NPU_BEGIN;
			MemReady	<= '0';
			NpuDone		<= '0';
			BiasDone	<= '0';
			AccResetN	<= '0';
			CurrWAddr	<= unsigned(NPUWVSAR);
			CurrXIndex	<= (others =>'0');
			CurrYIndex	<= (others =>'0');
		elsif (rising_edge(NpuClk)) then	-- Rising-Edge NPU FSM
			case NpuState is
				when NPU_BEGIN =>
					-- 1 Cycle Runtime
					-- Set all signals to proper values
					MemReady	<= '0';
					NpuDone		<= '0';
					BiasDone	<= '0';
					AccResetN	<= '0';
					CurrXIndex	<= (others =>'0');
					CurrYIndex	<= (others =>'0');
					CurrWAddr	<= unsigned(NPUWVSAR);
					NpuState	<= NPU_GET_WEIGHT;
				when NPU_GET_WEIGHT =>
					-- 2 Cycle Runtime
					-- SRAM was enabled and current Weight Address was set last clock cycle.
					-- This clock cycle SRAM will fetch weight from memory thus MemReady = 0.
					-- Next clock cycle weight will be present on SRAM Q thus MemReady is set to 1.
					if MemReady = '0' then
						MemReady <= '1';
					else
						-- Ensure Accumulator is no longer resetting
						AccResetN	<= '1';
						-- Get Weight From SRAM
						CurrW		<= SramQ_in((W_M_BITS + N_BITS) downto 0);
						-- Weight address will be incremented after MAC
						-- Update State
						if ((NPUBEN = '1') and (BiasDone = '0')) then
							-- If Bias is enabled but not been completed this is bias weight, CurrX will be set to 1.
							-- No need to get weight from SRAM so can skip straight to NPU_MAC.
							CurrX		<= to_slv(to_sfixed(1, X_M_BITS, -N_BITS));
							NpuState	<= NPU_MAC;			
						else
							-- Not a bias weight, so input must be fetched from SRAM before MAC
							NpuState	<= NPU_GET_INPUT;
						end if;
						-- Reset MemReady Signal
						MemReady	<= '0';
					end if;
				when NPU_GET_INPUT =>
					-- 2 Cycle Runtime
					-- SRAM was enabled and current input address was set last clock cycle.
					-- This clock cycle SRAM will fetch input from memory thus MemReady = 0.
					-- Next clock cycle input will be present on SRAM Q thus MemReady is set to 1.
					if MemReady = '0' then
						MemReady <= '1';
					else
						-- Get Input From SRAM
						CurrX		<= SramQ_in((X_M_BITS + N_BITS) downto 0);
						-- Input index will be incremented after MAC
						-- Update State - Time to MAC (~￣3￣)~
						NpuState	<= NPU_MAC;
						-- Reset MemReady Signal
						MemReady	<= '0';
					end if;
				when NPU_MAC =>
					-- 1 Cycle Runtime
					-- After last clock cycle the input and weight should have both been set...
					-- properly for the MAC. MAC Clk was also enabled and this clock cycle the 
					-- result would have been ready and latched in accumulator. If moving on to save
					-- ouput, then accumalator output is latched and fed to sigmoid approximator.
					if ((NeuronDone = '1')) then
						-- Neuron Done update state
						AccOutLtchd	<= MacOut;
						NpuState	<= NPU_SET_OUTPUT;
						MemReady	<= '1'; -- Memory is ready for writing
					else
						-- Neuron Not Done update state
						NpuState	<= NPU_GET_WEIGHT;
						MemReady	<= '0'; -- Memory not ready for read
					end if;
					if ((NPUBEN = '1') and (BiasDone = '0')) then
						-- Bias was enabled and just got calculated and added to the accumulator.
						-- Set Flag that Bias is completed
						BiasDone	<= '1';
					else
						-- Bias is either not enabled or already completed so increase input index.
						CurrXIndex	<= CurrXIndex + 1;
					end if;
					-- Update weight address for next iteration
					CurrWAddr	<= CurrWAddr + 1;
				when NPU_SET_OUTPUT =>
					-- 1 Cycle Runtime
					-- After last clock cycle MAC output was lached into AccOutLtchd and Decision should be calculated by now.
					-- SRAM was enabled and current output address was also set last clock cycle.
					-- This clock cycle SRAM will write output to SRAM and will move to either getting next weight or finishing...
					-- thus MemReady = 0.
					if (CurrYIndex = unsigned(NPUNN)) then
						-- If all neurons done go to finish state
						NpuState	<= NPU_FINISH;
					else
						-- Otherwise keep chugging
						NpuState	<= NPU_GET_WEIGHT;
					end if;
					-- Reset states for next neuron
					BiasDone	<= '0';
					CurrXIndex	<= (others => '0');
					CurrYIndex	<= CurrYIndex + 1;
					-- Reset Accumulator
					AccResetN	<= '0';
					-- Reset MemReady Signal
					MemReady <= '0';
				when NPU_FINISH =>
					-- 2 Cycle Runtime
					-- NpuDone gets set to 1  on first cycle indicating NPU Finished. As soon as this happens NPUTHINK is reset.
					-- Next cycle NpuDone is reset and FSM state is returned to NPU_BEGIN. Without second cycle, NPUTHINK would 
					-- be reset immediately upon next cycle.
					if (NpuDone = '0') then
						NpuDone		<= '1';
					else
						NpuDone		<= '0';
						NpuState	<= NPU_BEGIN;
					end if;
			end case;
		end if;
	end process NPU_FSM_SEQ;
	-- NPU SRAM Chip Enable Control
	-- Signal use to be controlled by combinational logic of NpuState and MemReady but this produced timing violations
	-- This was implemented for cleaner control. CEN is now asserted/deasserted on falling edges when necessary.
	NPU_RAM_SEQ: process(NpuClk, ResetN)
	begin
		if (ResetN = '0') then
			-- If reset, deassert
			NpuSramCEN	<= MEM_DEASSERT;
		elsif (falling_edge(NpuClk)) then
			case NpuState is
				when NPU_BEGIN =>
					NpuSramCEN	<= MEM_DEASSERT;
				when NPU_GET_WEIGHT =>
					if (MemReady = '0')  then
						NpuSramCEN	<= MEM_ASSERT;
					else
						NpuSramCEN	<= MEM_DEASSERT;
					end if ;
				when NPU_GET_INPUT =>
					if (MemReady = '0')  then
						NpuSramCEN	<= MEM_ASSERT;
					else
						NpuSramCEN	<= MEM_DEASSERT;
					end if;
				when NPU_MAC =>
					NpuSramCEN	<= MEM_DEASSERT;
				when NPU_SET_OUTPUT =>
					if (MemReady = '1')  then
						NpuSramCEN	<= MEM_ASSERT;
					else
						NpuSramCEN	<= MEM_DEASSERT;
					end if;
				when NPU_FINISH =>	
					NpuSramCEN	<= MEM_DEASSERT;
			end case;
		end if;
	end process NPU_RAM_SEQ;

	----- Combinational Logic
	-- Clock Gate Enables
	NpuClkEn 	<=	NpuThink or NpuDone;
	MacClkEn	<=	'1'	when (NpuState = NPU_MAC) 	else
					'0';

	-- Combinational NPU Signals
	CurrXAddr	<= unsigned(NPUIVSAR) + CurrXIndex;
	CurrYAddr	<= unsigned(NPUOVSAR) + CurrYIndex;
	NeuronDone	<= 	'1' when ( (CurrXIndex = unsigned(NPUNI)) and ((BiasDone = '1') or (NPUBEN = '0')) )	else
					'0';

	-- NPU to SRAM Interface
	SramClkEn		<=	'1' when (NpuSramCEN = MEM_ASSERT) else '0';					-- SRAM Clock Gate Enable 		
	NpuSramGWEN		<=	MEM_ASSERT when (NpuState = NPU_SET_OUTPUT) else
						MEM_DEASSERT;													-- NPU SRAM Global Write Enable Selection
	NpuSramWEN		<=	(others => MEM_ASSERT) when (NpuState = NPU_SET_OUTPUT) else
						(others => MEM_DEASSERT);										-- NPU SRAM Write Enable Selection
	with NpuState select																-- NPU SRAM Address Selection
		NpuSramA	<=	std_logic_vector(CurrWAddr)	when NPU_GET_WEIGHT,					
						std_logic_vector(CurrXAddr) when NPU_GET_INPUT,
						std_logic_vector(CurrYAddr) when NPU_SET_OUTPUT,
		(others => '-')	when others;
	with NPUAEN	select																	-- NPU SRAM D (Data Input) Selection
		NpuSramD	<= 	(31 downto (N_BITS+1) => '0') & Decision				when '1', 	-- Activation Function Enabled
						(31 downto (Y_M_BITS+N_BITS+1) => '0') & AccOutLtchd	when '0', 	-- Pass Through
						(31 downto (N_BITS+1) => '0') & Decision				when others;-- Assumed Activation Function Enabled

	--------------------------------------------
	----- Memory Mapped Register Interface -----
	--------------------------------------------
	----- Memory Mapped Register - Bit-Field Mapping
	-- NPUCR(18 downto 0)
	NPUBEN		<= NPUCR(18);
	NPUAEN		<= NPUCR(17);
	-- NPUTHINK	<= NPUCR(16);
	NPUNI		<= NPUCR(15 downto 8);
	NPUNN		<= NPUCR(7 downto 0);
	-- NPUIVSAR(11 downto 0) (No Routing Needed)
	-- NPUWVSAR(11 downto 0) (No Routing Needed)
	-- NPUOVSAR(11 downto 0) (No Routing Needed)

	----- MMR Writes
	MabMmrAInt	<= to_integer(unsigned(MabMmrA)) when (MabMmrCEN = MEM_ASSERT) else
				   0;
	MMR_WRITE: process(ResetN, MabMmrCLK, NpuDone)
	begin
		if (ResetN = '0') then
			-- Set MMRs To Default State
			NPUCR		<= (others => '0');
			NPUIVSAR	<= (others => '0');
			NPUWVSAR	<= (others => '0');
			NPUOVSAR	<= (others => '0');
		elsif (rising_edge(MabMmrCLK)) then
			if (MabMmrCEN = MEM_ASSERT) then
				case MabMmrAInt is
					when MmrAddrNPUCR =>
						if MabMmrWEN(0) = MEM_ASSERT then NPUCR(7 downto 0) <= MabMmrD(7 downto 0); end if;
						if MabMmrWEN(1) = MEM_ASSERT then NPUCR(15 downto 8) <= MabMmrD(15 downto 8); end if;
						if MabMmrWEN(2) = MEM_ASSERT then 
							NPUCR(18 downto 17) <= MabMmrD(18 downto 17); 
							NPUTHINK <= MabMmrD(16);
						end if;
						if MabMmrWEN(3) = MEM_ASSERT then null; end if;
					when MmrAddrNPUIVSAR =>
						if MabMmrWEN(0) = MEM_ASSERT then NPUIVSAR(7 downto 0) <= MabMmrD(7 downto 0); end if;
						if MabMmrWEN(1) = MEM_ASSERT then NPUIVSAR(11 downto 8) <= MabMmrD(11 downto 8); end if;
						if MabMmrWEN(2) = MEM_ASSERT then null; end if;
						if MabMmrWEN(3) = MEM_ASSERT then null; end if;
					when MmrAddrNPUWVSAR =>
						if MabMmrWEN(0) = MEM_ASSERT then NPUWVSAR(7 downto 0) <= MabMmrD(7 downto 0); end if;
						if MabMmrWEN(1) = MEM_ASSERT then NPUWVSAR(11 downto 8) <= MabMmrD(11 downto 8); end if;
						if MabMmrWEN(2) = MEM_ASSERT then null; end if;
						if MabMmrWEN(3) = MEM_ASSERT then null; end if;
					when MmrAddrNPUOVSAR =>
						if MabMmrWEN(0) = MEM_ASSERT then NPUOVSAR(7 downto 0) <= MabMmrD(7 downto 0); end if;
						if MabMmrWEN(1) = MEM_ASSERT then NPUOVSAR(11 downto 8) <= MabMmrD(11 downto 8); end if;
						if MabMmrWEN(2) = MEM_ASSERT then null; end if;
						if MabMmrWEN(3) = MEM_ASSERT then null; end if;
					when others =>
						null;
				end case;
			end if;
		end if;

		if (NpuDone = '1') or (resetn = '0') then
			-- Unset NNTHINK to indcate that NPU is done
			-- NPUCR(16) <= '0';
			NPUTHINK	<= '0';
		end if;
	end process MMR_WRITE;

	----- MMR Reads
	with MabMmrAInt select 
		MabMmrQ <=	(31 downto 19 => '0') & NPUCR		when MmrAddrNPUCR,
					(31 downto 12 => '0') & NPUIVSAR	when MmrAddrNPUIVSAR,
					(31 downto 12 => '0') & NPUWVSAR	when MmrAddrNPUWVSAR,
					(31 downto 12 => '0') & NPUOVSAR	when MmrAddrNPUOVSAR,
					(others => '0')						when others;

end behavioral;


