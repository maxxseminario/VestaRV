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
	--							Think-Done Interrupt Enable (NPUCR.TDIE, bit 19)
	--							Datapath Mode Select (NPUCR.MODE, bits 22:20 — P4.1 family; 0 = legacy MLP)
	--							Activation Select (NPUCR.ACTF, bits 25:23 — only 0 = sigmoid until P4.4)
	--							Per-Mode Config Words (NPUCFG1 @5, NPUCFG2 @6; offsets 7-15 reserved read-0)
	--							SRAM Start Address For Inputs (NPUIVSAR)
	--							SRAM Weight Address For Inputs (NPUWVSAR)
	--							SRAM Output Address For Inputs (NPUOVSAR)
	--
	-- DP-SG think-done IRQ (2026-07-22, npu_irq_spec.md — irq_router source 120):
	-- NPUSR (MmrAddrNPUSR=4) bit 0 THINKDONE sets on the NpuDone completion pulse
	-- (once per THINK), sticky, W1C via a bit-0 write of '1' (set-dominant on a
	-- same-cycle set/W1C collision). ThinkDoneIrq = THINKDONE and TDIE, one output
	-- flop on the free-running Clk (NOT NpuClk — the gate is off between THINKs).
	-- CONSTRAINT: MabMmrCLK and Clk must be the SAME clock (true in MCU_MP: both
	-- mclk) — the W1C decode is sampled on Clk. Reset default TDIE=0 keeps legacy
	-- polling firmware unaffected; the staging-RAM contract (poll NPUCR.16 before
	-- touching 0xC000+) is unchanged by the IRQ.
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
		MabMmrA			: in 	std_logic_vector(3 downto 0);	-- MCU To NPU MMR - Address
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
		NpuActive		: out	std_logic;						-- NPU Active Signal for Arbitration
		-- NPU Interrupt Signal
		ThinkDoneIrq	: out	std_logic						-- Think-Done IRQ (registered level, irq_router source 120)
    );
end NPU;

architecture behavioral of NPU is
	----- Constants
	-- Memory Assert/Deassert Constants (Active Low)
	constant MEM_ASSERT			: std_logic	:= '0';	
	constant MEM_DEASSERT		: std_logic	:= '1';


	----- Memory Mapped Registers & Bits
	-- P4.1 (npu_family_spec.md, 2026-07-23): NPUCR grows the family fields
	-- MODE [22:20] (0 = legacy MLP, reset default) and ACTF [25:23]
	-- (activation select; only 0 = sigmoid is implemented until P4.4), and the
	-- MMR bus widens 3->4 bits: NPUCFG1/NPUCFG2 land at word offsets 5/6
	-- (per-mode configuration), offsets 7-15 are reserved and read 0. The
	-- reset-0 register image is byte-behavior-identical to the legacy MLP
	-- block (the shnpu.S compatibility gate).
	signal NPUCR		: std_logic_vector(25 downto 0);		-- NPU Control Register
		signal NPUBEN	: std_logic;								-- NPU Bias Input Enable Bit (Enabled For First Layer)
		signal NPUAEN	: std_logic;								-- NPU Activation Function Enable Bit (Disabled for Last Layer)
		signal NPUTHINK	: std_logic;								-- NPU Start/Status Bit
		signal TDIE		: std_logic;								-- NPU Think-Done Interrupt Enable Bit (NPUCR.19)
		signal NPUNI	: std_logic_vector(7 downto 0);			-- NPU # Of Inputs
		signal NPUNN	: std_logic_vector(7 downto 0);			-- NPU # Of Neurons/Outputs
	signal NPUCFG1		: std_logic_vector(31 downto 0);		-- NPU Mode Config Word 1 (per-mode, P4.1)
	signal NPUCFG2		: std_logic_vector(15 downto 0);		-- NPU Mode Config Word 2 (per-mode, P4.1; bits 31:16 read 0)
	signal NPUIVSAR		: std_logic_vector(11 downto 0);		-- NPU Input Vector Start Address Register
	signal NPUWVSAR		: std_logic_vector(11 downto 0);		-- NPU Weight Vector Start Address Register
	signal NPUOVSAR		: std_logic_vector(11 downto 0);		-- NPU Output Vector Start Address Register
	signal THINKDONE	: std_logic;							-- NPUSR.0 Think-Done Flag (sticky, W1C, set-dominant)
	signal ThinkDoneIrqQ: std_logic;							-- Registered IRQ level (THINKDONE and TDIE)

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
	signal NpuMuxSel	: std_logic;							-- SRAM-port mux select = NPUTHINK registered on Clk (M7d)

	----- P4.1 CONV1D mode (npu_conv_design.md D1/D2/D4/D5) -----
	-- Run shadows, latched at NPU_BEGIN (D4): a mid-THINK MODE/CFG write is
	-- benign — the in-flight run keys off these frozen copies. mode_run resets
	-- to 0 (MLP) so every conv term below is dead at reset and in mode 0.
	constant MODE_CONV	: std_logic_vector(2 downto 0) := "001";
	signal mode_run		: std_logic_vector(2 downto 0);			-- MODE shadow (0 = MLP legacy)
	signal S_run		: unsigned(3 downto 0);					-- stride shadow  (CFG1 3:0)
	signal D_run		: unsigned(3 downto 0);					-- dilation shadow (CFG1 7:4)
	signal L_run		: unsigned(15 downto 0);				-- in-length shadow (CFG1 23:8)
	signal Cin_m1_run	: unsigned(2 downto 0);					-- Cin-1 shadow (CFG1 26:24)
	signal Lout_run		: unsigned(15 downto 0);				-- out-length shadow (CFG2 15:0)
	-- Conv walkers (D2, multiplier-free): input addr = IVSAR + cL + jS + kD.
	-- CurrXIndex doubles as k (tap), CurrYIndex as f (filter).
	signal conv_c		: unsigned(2 downto 0);					-- channel c (0..Cin-1)
	signal conv_j		: unsigned(15 downto 0);				-- output j within filter (0..Lout-1)
	signal kD			: unsigned(11 downto 0);				-- running k*D
	signal cL			: unsigned(11 downto 0);				-- running c*L
	signal jS			: unsigned(11 downto 0);				-- running j*S
	signal conv_yptr	: unsigned(11 downto 0);				-- flat output write pointer
	signal filter_base	: unsigned(11 downto 0);				-- current filter's weight-block base

	----- P4.2 XNOR/popcount mode (npu_xnor_design.md D1-D6) -----
	-- Addressing is byte-for-byte the as-built MLP walk (the KEY FINDING):
	-- CurrXIndex = packed-word counter, CurrYIndex = neuron, CurrWAddr's
	-- running +1 lands on each neuron-major weight block with no reload.
	-- Everything below is additive-to-new-registers; the only shared-
	-- expression edits are the NpuSramD override (D1 tp1) and the
	-- adjudicated MacClkEn gate (D2 overrule) — both vacuously
	-- as-built in modes 0/1.
	constant MODE_XNOR	: std_logic_vector(2 downto 0) := "010";
	signal xnor_aw		: std_logic_vector(31 downto 0);		-- packed activation word (GET_INPUT capture)
	signal xnor_ww		: std_logic_vector(31 downto 0);		-- packed weight word (GET_WEIGHT capture)
	signal thresh_run	: std_logic_vector(31 downto 0);		-- THRESH shadow (CFG1, signed)
	signal K_run		: unsigned(12 downto 0);				-- exact K shadow (CFG2 12:0)
	signal last_mask_run: std_logic_vector(31 downto 0);		-- tail mask for the LAST word (D3)
	signal pop_acc		: unsigned(12 downto 0);				-- per-neuron popcount accumulator
	signal xnor_outword	: std_logic_vector(31 downto 0);		-- +-1.0 Q7.24 result (MAC->SET_OUTPUT lifetime)
	-- combinational cloud (D2/D3/D4)
	signal xnor_masked	: std_logic_vector(31 downto 0);		-- tail-masked per-bit XNOR
	signal xnor_pop6	: unsigned(5 downto 0);					-- popcount of the current word (0..32)
	signal xnor_total	: unsigned(13 downto 0);				-- pop_acc + current word (comb, <= K)
	signal xnor_value	: signed(31 downto 0);					-- 2*pop_total - K
	signal xnor_fireword: std_logic_vector(31 downto 0);		-- +1.0 / -1.0 select
	signal mlp_conv_sramd : std_logic_vector(31 downto 0);		-- the as-built NPUAEN write-data select

	-- D2: plain loop-sum — Genus infers the ~6-level compressor tree.
	function popcount32(v : std_logic_vector(31 downto 0)) return unsigned is
		variable a : unsigned(5 downto 0);
	begin
		a := (others => '0');
		for i in v'range loop
			if v(i) = '1' then a := a + 1; end if;
		end loop;
		return a;
	end popcount32;

	-- D3: tail mask from K mod 32 (CFG2 4:0). Kmod=0 = a 32-aligned last
	-- word, every bit real -> all-ones; else only the low Kmod bits count.
	function tail_mask(kmod : std_logic_vector(4 downto 0)) return std_logic_vector is
		variable m : std_logic_vector(31 downto 0);
		variable n : integer;
	begin
		n := to_integer(unsigned(kmod));
		if n = 0 then
			m := (others => '1');
		else
			for i in 0 to 31 loop
				if i < n then m(i) := '1'; else m(i) := '0'; end if;
			end loop;
		end if;
		return m;
	end tail_mask;

begin

	----------------------------------------------
	----- Muxed SRAM Memory Bus Multiplexer ------
	----------------------------------------------
	-- M7d: the select is NPUTHINK REGISTERED on the free-running Clk
	-- (NpuMuxSel), not raw NPUTHINK. With the MMRs behind the multi-hart
	-- arbiter, ANY hart can set THINK at an mclk edge where the CPU that owns
	-- this SRAM port has an access in flight; switching the port on the raw
	-- bit could eat that access (corrupted load / dropped store). NpuActive
	-- (-> the owner CPU's sleep) is raw-OR-delayed, so the CPU is stopped one
	-- full cycle BEFORE the port switches to the NPU and resumes one full
	-- cycle AFTER it switches back; the NPU FSM's first SRAM access is
	-- several NpuClk cycles after THINK, well past the switch.
	NpuSramA_out 	<= SramA_in when (NpuMuxSel = '0') else NpuSramA;
	NpuSramD_out 	<= SramD_in when (NpuMuxSel = '0') else NpuSramD;
	NpuSramCLK_out 	<= SramCLK_in when (NpuMuxSel = '0') else NpuSramCLK;
	NpuSramCEN_out 	<= SramCEN_in when (NpuMuxSel = '0') else NpuSramCEN;
	NpuSramGWEN_out <= SramGWEN_in when (NpuMuxSel = '0') else NpuSramGWEN;
	NpuSramWEN_out 	<= SramWEN_in when (NpuMuxSel = '0') else NpuSramWEN;

	NPU_MUXSEL_REG: process(Clk, ResetN)
	begin
		if (ResetN = '0') then
			NpuMuxSel <= '0';
		elsif (rising_edge(Clk)) then
			NpuMuxSel <= NPUTHINK;
		end if;
	end process;

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
	-- M7d: raw OR delayed — the owner CPU sleeps from the THINK write until
	-- one cycle AFTER the SRAM port has switched back (see mux comment)
	NpuActive <= NPUTHINK or NpuMuxSel;

	-- DP-SG think-done flag + registered IRQ level. Lives on the FREE-RUNNING
	-- Clk, not NpuClk: the gated clock stops between THINKs, so a NpuClk flop
	-- could never take the W1C reliably. NpuDone is registered on NpuClk (edges
	-- aligned with Clk, and NpuClkEn = NpuThink or NpuDone keeps the gate open
	-- through the pulse), so this process samples it exactly once per THINK.
	-- Set-dominant: the NpuDone assignment is last, so a W1C landing on the
	-- exact completion edge keeps the flag (a completion is never lost).
	THINKDONE_SEQ: process(Clk, ResetN)
	begin
		if (ResetN = '0') then
			THINKDONE		<= '0';
			ThinkDoneIrqQ	<= '0';
		elsif (rising_edge(Clk)) then
			if ((MabMmrCEN = MEM_ASSERT) and (MabMmrAInt = MmrAddrNPUSR) and
				(MabMmrWEN(0) = MEM_ASSERT) and (MabMmrD(0) = '1')) then
				THINKDONE	<= '0';
			end if;
			if (NpuDone = '1') then
				THINKDONE	<= '1';
			end if;
			ThinkDoneIrqQ	<= THINKDONE and TDIE;
		end if;
	end process THINKDONE_SEQ;
	ThinkDoneIrq <= ThinkDoneIrqQ;

	
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
			-- P4.1: conv shadows/walkers all reset (X-collapse discipline);
			-- mode_run=0 keeps every conv term dead until a CONV THINK latches it
			mode_run	<= (others => '0');
			S_run		<= (others => '0');
			D_run		<= (others => '0');
			L_run		<= (others => '0');
			Cin_m1_run	<= (others => '0');
			Lout_run	<= (others => '0');
			conv_c		<= (others => '0');
			conv_j		<= (others => '0');
			kD			<= (others => '0');
			cL			<= (others => '0');
			jS			<= (others => '0');
			conv_yptr	<= (others => '0');
			filter_base	<= (others => '0');
			-- P4.2: XNOR shadows/registers all reset (X-collapse discipline)
			xnor_aw		<= (others => '0');
			xnor_ww		<= (others => '0');
			thresh_run	<= (others => '0');
			K_run		<= (others => '0');
			last_mask_run <= (others => '0');
			pop_acc		<= (others => '0');
			xnor_outword <= (others => '0');
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
					-- P4.1 D4: latch the run shadows (mode + conv shape) at the
					-- first NpuClk edge of every THINK; D2: reset the walkers.
					mode_run	<= NPUCR(22 downto 20);
					S_run		<= unsigned(NPUCFG1(3 downto 0));
					D_run		<= unsigned(NPUCFG1(7 downto 4));
					L_run		<= unsigned(NPUCFG1(23 downto 8));
					Cin_m1_run	<= unsigned(NPUCFG1(26 downto 24));
					Lout_run	<= unsigned(NPUCFG2);
					conv_c		<= (others => '0');
					conv_j		<= (others => '0');
					kD			<= (others => '0');
					cL			<= (others => '0');
					jS			<= (others => '0');
					conv_yptr	<= unsigned(NPUOVSAR);
					filter_base	<= unsigned(NPUWVSAR);
					-- P4.2 D5: XNOR run shadows (additive; dead in modes 0/1)
					thresh_run	<= NPUCFG1;
					K_run		<= unsigned(NPUCFG2(12 downto 0));
					last_mask_run <= tail_mask(NPUCFG2(4 downto 0));
					pop_acc		<= (others => '0');
					-- D10 G3 (FROZEN): conv with Lout=0 = zero outputs,
					-- immediate done — never hangs, never touches the RAM.
					if ((NPUCR(22 downto 20) = MODE_CONV) and (unsigned(NPUCFG2) = 0)) then
						NpuState	<= NPU_FINISH;
					else
						NpuState	<= NPU_GET_WEIGHT;
					end if;
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
						xnor_ww		<= SramQ_in;	-- P4.2: full-width packed capture (additive)
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
						xnor_aw		<= SramQ_in;	-- P4.2: full-width packed capture (additive)
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
					-- P4.2 D2/D4: XNOR accumulate + decision (dead in modes
					-- 0/1). pop_acc registers this word's count on this edge;
					-- the NeuronDone decision therefore uses the COMBINATIONAL
					-- total (pop_acc + this word) — xnor_fireword — latched
					-- with the same lifetime as AccOutLtchd.
					if (mode_run = MODE_XNOR) then
						pop_acc <= pop_acc + xnor_pop6;
						if (NeuronDone = '1') then
							xnor_outword <= xnor_fireword;
						end if;
					end if;
					if ((NPUBEN = '1') and (BiasDone = '0')) then
						-- Bias was enabled and just got calculated and added to the accumulator.
						-- Set Flag that Bias is completed
						BiasDone	<= '1';
					else
						-- Bias is either not enabled or already completed so increase input index.
						CurrXIndex	<= CurrXIndex + 1;
						-- P4.1 D2: conv tap/channel walk (dead in MLP). At the
						-- channel boundary (k = K-1) the tap index wraps and,
						-- unless this was the last channel (NeuronDone case —
						-- SET_OUTPUT resets everything), c advances with its
						-- running c*L stride.
						if (mode_run = MODE_CONV) then
							kD			<= kD + D_run;
							if (CurrXIndex = unsigned(NPUNI)) then
								CurrXIndex	<= (others => '0');
								kD			<= (others => '0');
								if (conv_c /= Cin_m1_run) then
									conv_c	<= conv_c + 1;
									cL		<= cL + L_run(11 downto 0);
								end if;
							end if;
						end if;
					end if;
					-- Update weight address for next iteration
					CurrWAddr	<= CurrWAddr + 1;
				when NPU_SET_OUTPUT =>
					-- 1 Cycle Runtime
					-- After last clock cycle MAC output was lached into AccOutLtchd and Decision should be calculated by now.
					-- SRAM was enabled and current output address was also set last clock cycle.
					-- This clock cycle SRAM will write output to SRAM and will move to either getting next weight or finishing...
					-- thus MemReady = 0.
					if (mode_run = MODE_CONV) then
						-- P4.1 D1/D2/D5: conv output bookkeeping. Within a
						-- filter the weight block is REUSED: reload CurrWAddr
						-- to filter_base (bias re-fetched per output, D5). At
						-- the filter boundary CurrWAddr sits one past the
						-- block, so filter_base <= CurrWAddr snapshots the
						-- next filter's base with no multiply (D2).
						conv_yptr	<= conv_yptr + 1;
						conv_c		<= (others => '0');
						cL			<= (others => '0');
						if (conv_j /= (Lout_run - 1)) then
							conv_j		<= conv_j + 1;
							jS			<= jS + S_run;
							CurrWAddr	<= filter_base;
							NpuState	<= NPU_GET_WEIGHT;
						else
							conv_j		<= (others => '0');
							jS			<= (others => '0');
							filter_base	<= CurrWAddr;
							CurrYIndex	<= CurrYIndex + 1;
							if (CurrYIndex = unsigned(NPUNN)) then
								NpuState	<= NPU_FINISH;
							else
								NpuState	<= NPU_GET_WEIGHT;
							end if;
						end if;
					else
						-- as-built MLP path (unchanged behavior)
						if (CurrYIndex = unsigned(NPUNN)) then
							-- If all neurons done go to finish state
							NpuState	<= NPU_FINISH;
						else
							-- Otherwise keep chugging
							NpuState	<= NPU_GET_WEIGHT;
						end if;
						CurrYIndex	<= CurrYIndex + 1;
					end if;
					-- Reset states for next neuron (all modes; pop_acc is a
					-- P4.2-only register no other mode reads — additive)
					BiasDone	<= '0';
					CurrXIndex	<= (others => '0');
					pop_acc		<= (others => '0');
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
	-- P4.2 D2 (adjudicated overrule): the FPMac accumulator clock is gated
	-- OFF in XNOR mode — the mode's datapath never reads MacOut, and letting
	-- the multiplier's accumulate-feedback loop churn garbage every MAC
	-- cycle wastes the exact energy this mode exists to save. The added term
	-- is vacuously true in modes 0/1 (as-built behavior bit-identical).
	MacClkEn	<=	'1'	when ((NpuState = NPU_MAC) and (mode_run /= MODE_XNOR)) 	else
					'0';

	-- Combinational NPU Signals
	-- P4.1 D2: 2-way mode muxes. In conv the input address is the
	-- multiplier-free 4-input add IVSAR + c*L + j*S + k*D (running registers)
	-- and the output address is the flat running pointer; in MLP (mode_run=0,
	-- also the reset state) both collapse to the as-built expressions.
	CurrXAddr	<= (unsigned(NPUIVSAR) + cL + jS + kD) when (mode_run = MODE_CONV) else
				   (unsigned(NPUIVSAR) + CurrXIndex);
	CurrYAddr	<= conv_yptr when (mode_run = MODE_CONV) else
				   (unsigned(NPUOVSAR) + CurrYIndex);
	-- P4.1 D1 touch point 2: in conv the accumulation for one output is done
	-- only on the LAST channel's last tap — the added term is vacuously true
	-- in MLP.
	NeuronDone	<= 	'1' when ( (CurrXIndex = unsigned(NPUNI)) and ((BiasDone = '1') or (NPUBEN = '0'))
						and ((mode_run /= MODE_CONV) or (conv_c = Cin_m1_run)) )	else
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
	with NPUAEN	select																	-- NPU SRAM D (Data Input) Selection (MLP/CONV)
		mlp_conv_sramd	<= 	(31 downto (N_BITS+1) => '0') & Decision				when '1', 	-- Activation Function Enabled
						(31 downto (Y_M_BITS+N_BITS+1) => '0') & AccOutLtchd	when '0', 	-- Pass Through
						(31 downto (N_BITS+1) => '0') & Decision				when others;-- Assumed Activation Function Enabled
	-- P4.2 D1 touch point 1 (the ONE shared-expression edit): in XNOR mode
	-- the write data is the +-1.0 decision word; in modes 0/1 the else arm
	-- is the as-built NPUAEN select, bit-identical.
	NpuSramD	<= xnor_outword when (mode_run = MODE_XNOR) else mlp_conv_sramd;

	-- P4.2 D2/D3/D4 combinational cloud: tail-masked XNOR -> popcount ->
	-- running total -> 2*pop - K -> signed >= THRESH -> +-1.0 Q7.24 literal
	-- (exact at the MCU generics; deliberately NOT to_sfixed — the input-side
	-- to_sfixed(1) quirk must not touch the output encoding).
	xnor_masked	<= (xnor_aw xnor xnor_ww) and last_mask_run when (CurrXIndex = unsigned(NPUNI)) else
				   (xnor_aw xnor xnor_ww);
	xnor_pop6	<= popcount32(xnor_masked);
	xnor_total	<= resize(pop_acc, 14) + resize(xnor_pop6, 14);
	xnor_value	<= signed(resize(xnor_total & '0', 32)) - signed(resize(K_run, 32));
	xnor_fireword <= x"01000000" when (xnor_value >= signed(thresh_run)) else x"FF000000";

	--------------------------------------------
	----- Memory Mapped Register Interface -----
	--------------------------------------------
	----- Memory Mapped Register - Bit-Field Mapping
	-- NPUCR(25 downto 0) — [25:23] ACTF and [22:20] MODE are stored here
	-- (P4.1); the sequencer/activation muxes tap them where each mode lands.
	TDIE		<= NPUCR(19);
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
			NPUCFG1		<= (others => '0');
			NPUCFG2		<= (others => '0');
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
							NPUCR(23 downto 17) <= MabMmrD(23 downto 17);
							NPUTHINK <= MabMmrD(16);
						end if;
						if MabMmrWEN(3) = MEM_ASSERT then NPUCR(25 downto 24) <= MabMmrD(25 downto 24); end if;
					when MmrAddrNPUCFG1 =>
						if MabMmrWEN(0) = MEM_ASSERT then NPUCFG1(7 downto 0) <= MabMmrD(7 downto 0); end if;
						if MabMmrWEN(1) = MEM_ASSERT then NPUCFG1(15 downto 8) <= MabMmrD(15 downto 8); end if;
						if MabMmrWEN(2) = MEM_ASSERT then NPUCFG1(23 downto 16) <= MabMmrD(23 downto 16); end if;
						if MabMmrWEN(3) = MEM_ASSERT then NPUCFG1(31 downto 24) <= MabMmrD(31 downto 24); end if;
					when MmrAddrNPUCFG2 =>
						if MabMmrWEN(0) = MEM_ASSERT then NPUCFG2(7 downto 0) <= MabMmrD(7 downto 0); end if;
						if MabMmrWEN(1) = MEM_ASSERT then NPUCFG2(15 downto 8) <= MabMmrD(15 downto 8); end if;
						if MabMmrWEN(2) = MEM_ASSERT then null; end if;
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
	-- NPUTHINK is stored separately from NPUCR (set from MabMmrD(16), cleared by
	-- NpuDone) so it must be re-inserted at bit 16 of the NPUCR readback -- else
	-- bit 16 reads the dead NPUCR(16) and software (and the TB) can never observe
	-- the NPU finishing (NPUTHINK 1->0).
	with MabMmrAInt select
		MabMmrQ <=	(31 downto 26 => '0') & NPUCR(25 downto 17) & NPUTHINK & NPUCR(15 downto 0)	when MmrAddrNPUCR,
					(31 downto 12 => '0') & NPUIVSAR	when MmrAddrNPUIVSAR,
					(31 downto 12 => '0') & NPUWVSAR	when MmrAddrNPUWVSAR,
					(31 downto 12 => '0') & NPUOVSAR	when MmrAddrNPUOVSAR,
					(31 downto 1  => '0') & THINKDONE	when MmrAddrNPUSR,
					NPUCFG1								when MmrAddrNPUCFG1,
					(31 downto 16 => '0') & NPUCFG2		when MmrAddrNPUCFG2,
					(others => '0')						when others;

end behavioral;


