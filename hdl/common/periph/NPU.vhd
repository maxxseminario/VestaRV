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


/* Fixed-point neural-network peripheral: MLP, CONV1D, XNOR/popcount and GEMM datapaths, selected by NPUCR.MODE.
   Fixed-point widths and the sigmoid RHO are generics; mode, shape, activation and the staging-RAM buffer addresses come from the MMRs.
   NPUSR bit 0 THINKDONE sets on the completion pulse (once per THINK), sticky, W1C by writing '1', set-dominant on a same-cycle collision.
   ThinkDoneIrq is THINKDONE and NPUCR.TDIE, one flop on the free-running Clk, NOT NpuClk, whose gate is off between THINKs.
   CONSTRAINT: MabMmrCLK and Clk must be the SAME clock, because the W1C decode is sampled on Clk. */
entity NPU is
    generic(
		-- Fixed-point M and N bits for inputs, weights and outputs; the Y bits also size the accumulator.
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
		ThinkDoneIrq	: out	std_logic;						-- Think-Done IRQ (registered level, irq_router source 120)

		-- Event-fabric task: a one-mclk pulse that starts a THINK on the pre-programmed descriptor.
		-- The fabric taps NpuActive for busy, so no separate busy port is needed.
		task_think		: in	std_logic := '0'
    );
end NPU;

architecture behavioral of NPU is
	----- Constants
	-- Memory Assert/Deassert Constants (Active Low)
	constant MEM_ASSERT			: std_logic	:= '0';	
	constant MEM_DEASSERT		: std_logic	:= '1';


	/* --- Memory Mapped Registers & Bits
	   NPUCR also carries MODE [22:20] (0 = MLP, the reset default) and ACTF [25:23] (activation select).
	   MMR word offsets: NPUCFG1 at 5 and NPUCFG2 at 6 (per-mode configuration); offsets 7-15 are reserved and read 0. */
	signal NPUCR		: std_logic_vector(25 downto 0);		-- NPU Control Register
		signal NPUBEN	: std_logic;								-- NPU Bias Input Enable Bit (Enabled For First Layer)
		signal NPUAEN	: std_logic;								-- NPU Activation Function Enable Bit (Disabled for Last Layer)
		signal NPUTHINK	: std_logic;								-- NPU Start/Status Bit
		signal TDIE		: std_logic;								-- NPU Think-Done Interrupt Enable Bit (NPUCR.19)
		signal NPUNI	: std_logic_vector(7 downto 0);			-- NPU # Of Inputs
		signal NPUNN	: std_logic_vector(7 downto 0);			-- NPU # Of Neurons/Outputs
	signal NPUCFG1		: std_logic_vector(31 downto 0);		-- NPU Mode Config Word 1 (per-mode)
	signal NPUCFG2		: std_logic_vector(15 downto 0);		-- NPU Mode Config Word 2 (per-mode; bits 31:16 read 0)
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
	signal NpuSramWEN	: std_logic_vector(3 downto 0);			-- MCU To NPU DP SRAM - Write Enable		(Combinational)

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
	signal Decision		: std_logic_vector(N_BITS downto 0); 	-- Decision Signal (Output Of Activation Function)
	signal MabMmrAInt	: natural range 0 to 63;			-- MMR word offset as an integer (0 when the block is not selected)
	signal NpuMuxSel	: std_logic;							-- SRAM-port mux select = NPUTHINK registered on Clk

	/* --- CONV1D mode -----
	   Run shadows, latched at NPU_BEGIN: a mid-THINK MODE or CFG write is benign, since the in-flight run keys off these frozen copies.
	   mode_run resets to 0 (MLP) so every conv term below is dead at reset and in mode 0. */
	constant MODE_CONV	: std_logic_vector(2 downto 0) := "001";
	signal mode_run		: std_logic_vector(2 downto 0);			-- MODE shadow (0 = MLP)
	signal S_run		: unsigned(3 downto 0);					-- stride shadow  (CFG1 3:0)
	signal D_run		: unsigned(3 downto 0);					-- dilation shadow (CFG1 7:4)
	signal L_run		: unsigned(15 downto 0);				-- in-length shadow (CFG1 23:8)
	signal Cin_m1_run	: unsigned(2 downto 0);					-- Cin-1 shadow (CFG1 26:24)
	signal Lout_run		: unsigned(15 downto 0);				-- out-length shadow (CFG2 15:0)
	-- Conv walkers, multiplier-free: input addr = IVSAR + cL + jS + kD.
	-- CurrXIndex doubles as k (tap), CurrYIndex as f (filter).
	signal conv_c		: unsigned(2 downto 0);					-- channel c (0..Cin-1)
	signal conv_j		: unsigned(15 downto 0);				-- output j within filter (0..Lout-1)
	signal kD			: unsigned(11 downto 0);				-- running k*D
	signal cL			: unsigned(11 downto 0);				-- running c*L
	signal jS			: unsigned(11 downto 0);				-- running j*S
	signal conv_yptr	: unsigned(11 downto 0);				-- flat output write pointer
	signal filter_base	: unsigned(11 downto 0);				-- current filter's weight-block base

	/* --- XNOR/popcount mode -----
	   Addressing is exactly the MLP walk: CurrXIndex is the packed-word counter, CurrYIndex the neuron, and CurrWAddr's running +1 lands on each neuron-major weight block with no reload.
	   Only the NpuSramD override and the MacClkEn gate are shared with the other modes, and both are inert in modes 0/1. */
	constant MODE_XNOR	: std_logic_vector(2 downto 0) := "010";
	signal xnor_aw		: std_logic_vector(31 downto 0);		-- packed activation word (GET_INPUT capture)
	signal xnor_ww		: std_logic_vector(31 downto 0);		-- packed weight word (GET_WEIGHT capture)
	signal thresh_run	: std_logic_vector(31 downto 0);		-- THRESH shadow (CFG1, signed)
	signal K_run		: unsigned(12 downto 0);				-- exact K shadow (CFG2 12:0)
	signal last_mask_run: std_logic_vector(31 downto 0);		-- tail mask for the LAST word
	signal pop_acc		: unsigned(12 downto 0);				-- per-neuron popcount accumulator
	signal xnor_outword	: std_logic_vector(31 downto 0);		-- +-1.0 Q7.24 result (lives from MAC to SET_OUTPUT)
	-- combinational cloud
	signal xnor_masked	: std_logic_vector(31 downto 0);		-- tail-masked per-bit XNOR
	signal xnor_pop6	: unsigned(5 downto 0);					-- popcount of the current word (0..32)
	signal xnor_total	: unsigned(13 downto 0);				-- pop_acc + current word (comb, never exceeds K)
	signal xnor_value	: signed(31 downto 0);					-- 2*pop_total - K
	signal xnor_fireword: std_logic_vector(31 downto 0);		-- +1.0 / -1.0 select
	signal mlp_conv_sramd : std_logic_vector(31 downto 0);		-- the NPUAEN write-data select

	/* --- GEMM mode -----
	   GEMM is M chained MLP THINKs: the n-loop is the neuron loop (CurrYIndex, bound NPUNN=N-1), the k-loop is the input loop (CurrXIndex, bound NPUNI=K-1), and m is the outer row loop (M-1 = NPUCFG1[7:0], latched at BEGIN).
	   B is column-major, so the weight walk stays a running +1 across abutting columns and reloads to the CONSTANT WVSAR once per row. */
	constant MODE_GEMM	: std_logic_vector(2 downto 0) := "011";
	signal M_m1_run		: unsigned(7 downto 0);					-- M-1 shadow (CFG1 7:0)
	signal gemm_m		: unsigned(7 downto 0);					-- output row m (0..M-1)
	signal mK			: unsigned(11 downto 0);				-- running m*K = input row base
	signal gemm_yptr	: unsigned(11 downto 0);				-- flat C write pointer (row-major)

	/* --- ACTF activation mux -----
	   Every activation is a shift-and-add wrapper around the ONE combinational FPSigmoid, selected BELOW the XNOR NpuSramD override (mode 2 never reads it).
	   NPUAEN stays the master enable (AEN=0 is passthrough, ACTF don't-care), and actf_run=0 collapses act_out to the plain Decision arm with sig_in = AccOutLtchd. */
	constant ACTF_SIG	: std_logic_vector(2 downto 0) := "000";	-- sigmoid
	constant ACTF_RELU	: std_logic_vector(2 downto 0) := "001";
	constant ACTF_TANH	: std_logic_vector(2 downto 0) := "010";	-- 2*sigma(2x)-1
	constant ACTF_CLAMP	: std_logic_vector(2 downto 0) := "011";	-- hardtanh to [-1,1)
	constant ACTF_EXP	: std_logic_vector(2 downto 0) := "100";	-- exp-approx = 2*sigma(x)
	signal actf_run		: std_logic_vector(2 downto 0);			-- ACTF shadow (latched at BEGIN)
	signal sig_in		: std_logic_vector((Y_M_BITS+N_BITS) downto 0);	-- FPSigmoid X input
	signal tanh_pre		: std_logic_vector((Y_M_BITS+N_BITS) downto 0);	-- SATURATING 2x
	signal tanh_q		: signed((N_BITS+2) downto 0);			-- 2*sigma(2x) - 1, headroom
	signal clamp_q		: signed(N_BITS downto 0);				-- saturated Q0.N slice
	signal sig_word		: std_logic_vector(31 downto 0);		-- AEN=1 sigmoid arm
	signal relu_word	: std_logic_vector(31 downto 0);
	signal tanh_word	: std_logic_vector(31 downto 0);
	signal clamp_word	: std_logic_vector(31 downto 0);
	signal exp_word		: std_logic_vector(31 downto 0);
	signal act_out		: std_logic_vector(31 downto 0);		-- ACTF-selected activated word

	-- A plain loop sum; synthesis infers the compressor tree.
	function popcount32(v : std_logic_vector(31 downto 0)) return unsigned is
		variable a : unsigned(5 downto 0);
	begin
		a := (others => '0');
		for i in v'range loop
			if v(i) = '1' then a := a + 1; end if;
		end loop;
		return a;
	end popcount32;

	-- Tail mask from K mod 32 (CFG2 4:0).
	-- Kmod=0 means a 32-aligned last word with every bit real, so the mask is all-ones; otherwise only the low Kmod bits count.
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

	/* --------------------------------------------
	   --- Muxed SRAM Memory Bus Multiplexer ------
	   --------------------------------------------
	   The select is NPUTHINK REGISTERED on the free-running Clk (NpuMuxSel), never raw NPUTHINK: any hart can set THINK while the CPU owning this SRAM port has an access in flight, and switching on the raw bit would eat it.
	   NpuActive drives the owner CPU's sleep and is the raw bit ORed with the delayed one, so the CPU stops one full cycle BEFORE the port switches to the NPU and resumes one full cycle AFTER it switches back. */
	NpuSramA_out 	<= SramA_in when (NpuMuxSel = '0') else NpuSramA;
	NpuSramD_out 	<= SramD_in when (NpuMuxSel = '0') else NpuSramD;
	NpuSramCLK_out 	<= SramCLK_in when (NpuMuxSel = '0') else NpuSramCLK;
	NpuSramCEN_out 	<= SramCEN_in when (NpuMuxSel = '0') else NpuSramCEN;
	NpuSramGWEN_out <= SramGWEN_in when (NpuMuxSel = '0') else NpuSramGWEN;
	NpuSramWEN_out 	<= SramWEN_in when (NpuMuxSel = '0') else NpuSramWEN;

	-- SRAM port select: NPUTHINK delayed by one free-running Clk edge.
	NPU_MUXSEL_REG: process(Clk, ResetN)
	begin
		if (ResetN = '0') then
			NpuMuxSel <= '0';
		elsif (rising_edge(Clk)) then
			NpuMuxSel <= NPUTHINK;
		end if;
	end process;

	/* -----------------------------------
	   --- Component Instantiations ------
	   -----------------------------------
	   NPU Clock Gate */
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
		X			=> sig_in,	-- AccOutLtchd for every ACTF except tanh, which pre-saturates 2x
		Y			=> Decision
	);

	/* ------------------------------------
	   --- NPU Internal Functionality -----
	   ------------------------------------
	   Raw ORed with delayed, so the owner CPU sleeps from the THINK write until one cycle AFTER the SRAM port has switched back. */
	NpuActive <= NPUTHINK or NpuMuxSel;

	-- Think-done flag and registered IRQ level, on the FREE-RUNNING Clk: the gated NpuClk stops between THINKs, so a NpuClk flop could not take the W1C reliably.
	-- NpuDone is one NpuClk pulse with edges aligned to Clk and is sampled exactly once per THINK; its assignment is last, so a W1C landing on the completion edge never loses a completion.
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
			-- Conv shadows and walkers all reset; mode_run=0 keeps every conv term dead until a CONV THINK latches it.
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
			-- XNOR shadows and registers all reset.
			xnor_aw		<= (others => '0');
			xnor_ww		<= (others => '0');
			thresh_run	<= (others => '0');
			K_run		<= (others => '0');
			last_mask_run <= (others => '0');
			pop_acc		<= (others => '0');
			xnor_outword <= (others => '0');
			-- GEMM shadow and walkers all reset.
			M_m1_run	<= (others => '0');
			gemm_m		<= (others => '0');
			mK			<= (others => '0');
			gemm_yptr	<= (others => '0');
			-- ACTF shadow reset.
			actf_run	<= (others => '0');
		elsif (rising_edge(NpuClk)) then	-- Rising-Edge NPU FSM
			case NpuState is
				when NPU_BEGIN =>
					-- 1 cycle runtime: set every signal to its start-of-THINK value.
					MemReady	<= '0';
					NpuDone		<= '0';
					BiasDone	<= '0';
					AccResetN	<= '0';
					CurrXIndex	<= (others =>'0');
					CurrYIndex	<= (others =>'0');
					CurrWAddr	<= unsigned(NPUWVSAR);
					-- Latch the run shadows (mode, activation and conv shape) at the first NpuClk edge of every THINK, and reset the walkers.
					mode_run	<= NPUCR(22 downto 20);
					actf_run	<= NPUCR(25 downto 23);
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
					-- XNOR run shadows (dead in modes 0/1).
					thresh_run	<= NPUCFG1;
					K_run		<= unsigned(NPUCFG2(12 downto 0));
					last_mask_run <= tail_mask(NPUCFG2(4 downto 0));
					pop_acc		<= (others => '0');
					-- GEMM run shadow and walker resets (dead in modes 0/1/2).
					M_m1_run	<= unsigned(NPUCFG1(7 downto 0));
					gemm_m		<= (others => '0');
					mK			<= (others => '0');
					gemm_yptr	<= unsigned(NPUOVSAR);
					-- Conv with Lout=0 produces zero outputs and finishes immediately: it never hangs and never touches the RAM.
					if ((NPUCR(22 downto 20) = MODE_CONV) and (unsigned(NPUCFG2) = 0)) then
						NpuState	<= NPU_FINISH;
					else
						NpuState	<= NPU_GET_WEIGHT;
					end if;
				when NPU_GET_WEIGHT =>
					-- 2 cycle runtime: the SRAM was enabled and the weight address set last cycle, so this cycle is the fetch (MemReady = 0).
					-- Next cycle the weight is on SRAM Q, so MemReady is set to 1.
					if MemReady = '0' then
						MemReady <= '1';
					else
						-- Ensure Accumulator is no longer resetting
						AccResetN	<= '1';
						-- Get Weight From SRAM
						CurrW		<= SramQ_in((W_M_BITS + N_BITS) downto 0);
						xnor_ww		<= SramQ_in;	-- full-width packed capture for XNOR
						-- Weight address will be incremented after MAC
						-- Update State
						if ((NPUBEN = '1') and (BiasDone = '0')) then
							-- Bias weight: CurrX is forced to 1 and no input fetch is needed, so skip straight to NPU_MAC.
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
					-- 2 cycle runtime: the SRAM was enabled and the input address set last cycle, so this cycle is the fetch (MemReady = 0).
					-- Next cycle the input is on SRAM Q, so MemReady is set to 1.
					if MemReady = '0' then
						MemReady <= '1';
					else
						-- Get Input From SRAM
						CurrX		<= SramQ_in((X_M_BITS + N_BITS) downto 0);
						xnor_aw		<= SramQ_in;	-- full-width packed capture for XNOR
						-- Input index will be incremented after MAC
						-- Update state: time to MAC.
						NpuState	<= NPU_MAC;
						-- Reset MemReady Signal
						MemReady	<= '0';
					end if;
				when NPU_MAC =>
					-- 1 cycle runtime: input, weight and MacClk were all set up last cycle, so the result is now latched in the accumulator.
					-- On the last MAC of a neuron the accumulator output is latched and fed to the activation.
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
					-- XNOR accumulate and decision (dead in modes 0/1).
					-- pop_acc registers this word's count on this edge, so the NeuronDone decision uses the COMBINATIONAL total (pop_acc plus this word), namely xnor_fireword, latched with the same lifetime as AccOutLtchd.
					if (mode_run = MODE_XNOR) then
						pop_acc <= pop_acc + xnor_pop6;
						if (NeuronDone = '1') then
							xnor_outword <= xnor_fireword;
						end if;
					end if;
					if ((NPUBEN = '1') and (BiasDone = '0')) then
						-- The bias term was just accumulated, so flag it done.
						BiasDone	<= '1';
					else
						-- Bias is either not enabled or already completed, so advance the input index.
						CurrXIndex	<= CurrXIndex + 1;
						-- Conv tap and channel walk (dead in MLP).
						-- At the channel boundary (k = K-1) the tap index wraps and, unless this was the last channel (where SET_OUTPUT resets everything), c advances with its running c*L stride.
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
					-- 1 cycle runtime: AccOutLtchd and the output address were set last cycle and the activation has settled, so the SRAM takes the write now.
					-- The FSM then moves on to the next weight or to finish, so MemReady returns to 0.
					if (mode_run = MODE_CONV) then
						-- Conv output bookkeeping: within a filter the weight block is REUSED, so CurrWAddr reloads to filter_base and the bias is re-fetched per output.
						-- At the filter boundary CurrWAddr sits one past the block, so loading filter_base from it snapshots the next filter's base with no multiply.
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
					elsif (mode_run = MODE_GEMM) then
						-- Row-major C via the running flat pointer; within a row CurrWAddr keeps its running +1 across the abutting column-major B columns, with no per-column reload.
						-- At the row boundary it reloads to the CONSTANT WVSAR (B is reused across rows) and the input row base mK advances by K = NPUNI+1.
						gemm_yptr	<= gemm_yptr + 1;
						if (CurrYIndex = unsigned(NPUNN)) then
							CurrYIndex	<= (others => '0');
							if (gemm_m = M_m1_run) then
								NpuState	<= NPU_FINISH;
							else
								gemm_m		<= gemm_m + 1;
								mK			<= mK + ("0000" & unsigned(NPUNI)) + 1;
								CurrWAddr	<= unsigned(NPUWVSAR);
								NpuState	<= NPU_GET_WEIGHT;
							end if;
						else
							CurrYIndex	<= CurrYIndex + 1;
							NpuState	<= NPU_GET_WEIGHT;
						end if;
					else
						-- MLP path
						if (CurrYIndex = unsigned(NPUNN)) then
							-- If all neurons done go to finish state
							NpuState	<= NPU_FINISH;
						else
							-- Otherwise keep chugging
							NpuState	<= NPU_GET_WEIGHT;
						end if;
						CurrYIndex	<= CurrYIndex + 1;
					end if;
					-- Reset state for the next neuron in every mode; pop_acc is XNOR-only and no other mode reads it.
					BiasDone	<= '0';
					CurrXIndex	<= (others => '0');
					pop_acc		<= (others => '0');
					-- Reset Accumulator
					AccResetN	<= '0';
					-- Reset MemReady Signal
					MemReady <= '0';
				when NPU_FINISH =>
					-- 2 cycle runtime: the first cycle sets NpuDone, which clears NPUTHINK.
					-- The second cycle clears NpuDone and returns to NPU_BEGIN; without it a new THINK would be cleared immediately.
					if (NpuDone = '0') then
						NpuDone		<= '1';
					else
						NpuDone		<= '0';
						NpuState	<= NPU_BEGIN;
					end if;
			end case;
		end if;
	end process NPU_FSM_SEQ;
	-- NPU SRAM chip enable: CEN switches on falling NpuClk edges, since a combinational CEN on NpuState and MemReady violates timing.
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
					-- Assert for the fetch cycle, release once the weight is on Q.
					if (MemReady = '0')  then
						NpuSramCEN	<= MEM_ASSERT;
					else
						NpuSramCEN	<= MEM_DEASSERT;
					end if ;
				when NPU_GET_INPUT =>
					-- Assert for the fetch cycle, release once the input is on Q.
					if (MemReady = '0')  then
						NpuSramCEN	<= MEM_ASSERT;
					else
						NpuSramCEN	<= MEM_DEASSERT;
					end if;
				when NPU_MAC =>
					NpuSramCEN	<= MEM_DEASSERT;
				when NPU_SET_OUTPUT =>
					-- Assert for the write cycle; NPU_MAC set MemReady on entry.
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
	-- The FPMac accumulator clock is gated OFF in XNOR mode: that datapath never reads MacOut, and letting the accumulate-feedback loop churn every MAC cycle wastes the energy this mode exists to save.
	-- The added term is vacuously true in modes 0/1.
	MacClkEn	<=	'1'	when ((NpuState = NPU_MAC) and (mode_run /= MODE_XNOR)) 	else
					'0';

	/* Combinational NPU Signals
	   Conv takes the multiplier-free 4-input add IVSAR + c*L + j*S + k*D for the input and a flat running pointer for the output; GEMM takes IVSAR + m*K + k (mK is the running row base) and a flat row-major pointer.
	   Modes 0 and 2 fall through to the plain MLP else arms. */
	CurrXAddr	<= (unsigned(NPUIVSAR) + cL + jS + kD) when (mode_run = MODE_CONV) else
				   (unsigned(NPUIVSAR) + mK + ("0000" & CurrXIndex)) when (mode_run = MODE_GEMM) else
				   (unsigned(NPUIVSAR) + CurrXIndex);
	CurrYAddr	<= conv_yptr when (mode_run = MODE_CONV) else
				   gemm_yptr when (mode_run = MODE_GEMM) else
				   (unsigned(NPUOVSAR) + CurrYIndex);
	-- In conv one output is complete only on the LAST channel's last tap; the added term is vacuously true in MLP.
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
	/* Activation cloud: all combinational on the SET_OUTPUT write path, with one full NpuClk cycle to settle.
	   Encoding contract: sigmoid and exp are non-negative and ZERO-extended, tanh and clamp are signed and SIGN-extended (a zero-extended negative would read as a huge positive word), and ReLU keeps the full passthrough shape.
	   The tanh pre-shift MUST SATURATE, because a plain drop-MSB shift sign-flips for |x| in the top half of the accumulator range and lands FPSigmoid in the wrong out-of-range branch; it only ever acts for |x| >= 2^(Y_M_BITS-1), deep inside the saturated zone, so tanh's active region is untouched. */
	tanh_pre	<= AccOutLtchd((Y_M_BITS+N_BITS-1) downto 0) & '0'
					when (AccOutLtchd(Y_M_BITS+N_BITS) = AccOutLtchd(Y_M_BITS+N_BITS-1)) else
				   '0' & ((Y_M_BITS+N_BITS-1) downto 0 => '1')
					when (AccOutLtchd(Y_M_BITS+N_BITS) = '0') else
				   '1' & ((Y_M_BITS+N_BITS-1) downto 0 => '0');
	sig_in		<= tanh_pre when (actf_run = ACTF_TANH) else AccOutLtchd;
	-- The AEN=1 arm: the zero-extended sigmoid word.
	sig_word	<= (31 downto (N_BITS+1) => '0') & Decision;
	-- ReLU: sign mux on the accumulator, full Q(Y_M).(N) passthrough shape.
	relu_word	<= (31 downto (Y_M_BITS+N_BITS+1) => '0') & AccOutLtchd
					when (AccOutLtchd(Y_M_BITS+N_BITS) = '0') else
				   (others => '0');
	-- tanh = 2*sigma(2x) - 1: exact double then subtract 1.0, sign-extended.
	tanh_q		<= signed('0' & Decision & '0') - to_signed(2**N_BITS, N_BITS+3);
	tanh_word	<= std_logic_vector(resize(tanh_q, 32));
	-- clamp/hardtanh: saturate Q(Y_M).(N) down to Q0.(N), sign-extended.
	-- In [-1,1) iff the integer bits are pure sign extension.
	clamp_q		<= to_signed(2**N_BITS - 1, N_BITS+1)
					when ((AccOutLtchd(Y_M_BITS+N_BITS) = '0') and
						  (unsigned(AccOutLtchd((Y_M_BITS+N_BITS-1) downto N_BITS)) /= 0)) else
				   to_signed(-(2**N_BITS), N_BITS+1)
					when ((AccOutLtchd(Y_M_BITS+N_BITS) = '1') and
						  (unsigned(not AccOutLtchd((Y_M_BITS+N_BITS-1) downto N_BITS)) /= 0)) else
				   signed(AccOutLtchd(N_BITS downto 0));
	clamp_word	<= std_logic_vector(resize(clamp_q, 32));
	-- exp-approx = 2*sigma(x), Q1.(N) in [0,2), zero-extended.
	-- Decision's top bit is structurally '0' (sigma < 1.0 always), so the double is just the low N bits shifted left one.
	exp_word	<= (31 downto (N_BITS+1) => '0') & Decision((N_BITS-1) downto 0) & '0';
	-- The ACTF select; reserved codes 5-7 act as sigmoid.
	-- The choices are string LITERALS because array constants are not locally static in VHDL-93; the ACTF_* constants above serve the conditional tests only.
	with actf_run select
		act_out		<= sig_word		when "000",		-- ACTF_SIG
					   relu_word	when "001",		-- ACTF_RELU
					   tanh_word	when "010",		-- ACTF_TANH
					   clamp_word	when "011",		-- ACTF_CLAMP
					   exp_word		when "100",		-- ACTF_EXP
					   sig_word		when others;	-- reserved 5-7 + metavalues
	-- The outer select keeps the 3-arm NPUAEN shape, so arm '1' and the metavalue OTHERS arm both take the activated word.
	-- At actf_run=0 act_out is sig_word, i.e. the plain Decision arm.
	with NPUAEN	select																	-- NPU SRAM D (Data Input) Selection (MLP/CONV/GEMM)
		mlp_conv_sramd	<= 	act_out												when '1', 	-- Activation Function Enabled (ACTF-selected)
						(31 downto (Y_M_BITS+N_BITS+1) => '0') & AccOutLtchd	when '0', 	-- Pass Through
						act_out												when others;-- Assumed Activation Function Enabled
	-- In XNOR mode the write data is the +-1.0 decision word; the other modes take the NPUAEN select.
	NpuSramD	<= xnor_outword when (mode_run = MODE_XNOR) else mlp_conv_sramd;

	-- XNOR combinational cloud: tail-masked XNOR, then popcount, then running total, then 2*pop - K, then a signed compare against THRESH, then the +-1.0 Q7.24 literal.
	-- The literal is exact at the MCU generics and is deliberately NOT to_sfixed: the input-side to_sfixed(1) quirk must not touch the output encoding.
	xnor_masked	<= (xnor_aw xnor xnor_ww) and last_mask_run when (CurrXIndex = unsigned(NPUNI)) else
				   (xnor_aw xnor xnor_ww);
	xnor_pop6	<= popcount32(xnor_masked);
	xnor_total	<= resize(pop_acc, 14) + resize(xnor_pop6, 14);
	xnor_value	<= signed(resize(xnor_total & '0', 32)) - signed(resize(K_run, 32));
	xnor_fireword <= x"01000000" when (xnor_value >= signed(thresh_run)) else x"FF000000";

	/* ------------------------------------------
	   --- Memory Mapped Register Interface -----
	   ------------------------------------------
	   --- Memory Mapped Register - Bit-Field Mapping
	   NPUCR(25 downto 0) also holds ACTF [25:23] and MODE [22:20], which the sequencer and activation muxes tap directly. */
	TDIE		<= NPUCR(19);
	NPUBEN		<= NPUCR(18);
	NPUAEN		<= NPUCR(17);
	-- NPUTHINK	<= NPUCR(16);
	NPUNI		<= NPUCR(15 downto 8);
	NPUNN		<= NPUCR(7 downto 0);
	-- NPUIVSAR, NPUWVSAR and NPUOVSAR are 12-bit registers of their own and need no bit routing.

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
						-- NPUTHINK is a separate flop, so byte lane 2 splits around bit 16.
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
						-- Only 16 bits are implemented, so the upper two byte lanes are dropped.
						if MabMmrWEN(0) = MEM_ASSERT then NPUCFG2(7 downto 0) <= MabMmrD(7 downto 0); end if;
						if MabMmrWEN(1) = MEM_ASSERT then NPUCFG2(15 downto 8) <= MabMmrD(15 downto 8); end if;
						if MabMmrWEN(2) = MEM_ASSERT then null; end if;
						if MabMmrWEN(3) = MEM_ASSERT then null; end if;
					when MmrAddrNPUIVSAR =>
						-- 12-bit staging-RAM word index; the upper two byte lanes are dropped (same for WVSAR and OVSAR below).
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
						-- Reserved word offsets 7-15: writes are ignored.
						null;
				end case;
			end if;

			/* Event-fabric THINK start: pulse-only, OUTSIDE the CEN qualifier so it fires with the bus idle, and AFTER the register case so a task wins a coincident NPUCR write of bit 16.
			   The trailing NpuDone and reset clear below still wins over BOTH paths, and a task THINK is otherwise indistinguishable from a register THINK.
			   SOFTWARE CONTRACT: no hart touches the staging RAM 0xC000-0xFFFF while a fabric THINK may fire. */
			if task_think = '1' then
				NPUTHINK <= '1';
			end if;
		end if;

		if (NpuDone = '1') or (resetn = '0') then
			-- Clear NPUTHINK to indicate the NPU is done.
			-- NPUCR(16) <= '0';
			NPUTHINK	<= '0';
		end if;
	end process MMR_WRITE;

	/* --- MMR Reads
	   NPUTHINK is a separate flop (set from MabMmrD(16), cleared by NpuDone), so it must be re-inserted at bit 16 of the NPUCR readback.
	   Otherwise bit 16 reads the dead NPUCR(16) and nothing can observe NPUTHINK falling when the NPU finishes. */
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


