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
use work.periph_tb_pkg.all;

/* -----------------------------------------------------------------------------
   NPU_pack_tb.vhd : packed-operand bench for NPUCR.NPUWPK (bit 26) and NPUCR.NPUXPK (bit 27).
   Instantiated at the MCU/chip generics (X_M=0, W_M=7, Y_M=7, N=24, RHO=2), i.e. the silicon configuration, where the unpacked input is Q0.24 (25 bits) and the unpacked weight is Q7.24 (32 bits).

   METHOD: DIFFERENTIAL, no golden files.  Every case is run TWICE over the same numbers -- once with both mode bits clear over one-element-per-word staging, once with the bits under test set over the packed staging -- and the two output vectors must be BIT-IDENTICAL.
   That is a fair demand only because the test data is chosen to be EXACTLY representable in both formats: each input is a 16-bit Q0.15 value scaled to Q0.24 (low 9 bits zero) and each weight a 16-bit Q3.12 value scaled to Q7.24 (low 12 bits zero).  Any addressing, half-select, sign-extension or scaling error in the packed path therefore shows up as a mismatch, with no rounding noise to hide behind.
   Magnitudes are bounded to +-0.5 (inputs) and +-4.0 (weights) so no accumulator saturates: a saturating case would compare equal for the wrong reason.

   COVERAGE: the packed walkers are exercised in every mode that has one -- MLP (odd input count, so neurons restart mid-word), MLP with NPUBEN (odd 1+K weight block, so each neuron's block starts in the other half), MLP with the activation on, GEMM (odd K, so each A row base straddles), CONV1D (per-filter weight-block reload plus the channel/tap/stride walkers, odd 1+Cin*K block) -- plus XNOR, which must IGNORE both bits, plus the NPUCR readback of the two new bits and a re-check that NPUTHINK still reads back at bit 16.
   NEGCTRL=0 is a clean run whose ALL-PASS banner needs a zero error tally; NEGCTRL=1 perturbs exactly one packed weight half in the wpk-only MLP case, which reaches exactly one neuron, so its banner needs a tally of exactly 1.
   ----------------------------------------------------------------------------- */
entity NPU_pack_tb is
	generic (
		NEGCTRL : integer := 0
	);
end NPU_pack_tb;

architecture testbench of NPU_pack_tb is
	----- Clock Information
	-- 25 MHz / 40 ns: the rate the NPU netlist is closed at, kept here so this bench can be re-run against the gate netlist unchanged.
	constant CLK_FREQ   : integer 	:= 25e6;
	constant CLK_PERIOD : time		:= 1 sec / CLK_FREQ;
	constant CLK_DELAY	: time 		:= CLK_PERIOD/2;

	----- Constants
	constant MEM_ASSERT			: std_logic	:= '0';
	constant MEM_DEASSERT		: std_logic	:= '1';
	-- Memory address bus constants, defined locally rather than pulling in work.MemoryMap.
	constant MmrAddrNPUCR		: natural	:= 0;
	constant MmrAddrNPUIVSAR	: natural	:= 1;
	constant MmrAddrNPUWVSAR	: natural	:= 2;
	constant MmrAddrNPUOVSAR	: natural	:= 3;
	constant MmrAddrNPUSR		: natural	:= 4;
	constant MmrAddrNPUCFG1		: natural	:= 5;
	constant MmrAddrNPUCFG2		: natural	:= 6;

	-- FROZEN MCU/chip generics.
	constant X_M_BITS					: integer := 0;
	constant W_M_BITS					: integer := 7;
	constant Y_M_BITS					: integer := 7;
	constant N_BITS						: integer := 24;
	constant RHO						: integer := 2;

	-- Scale factors from the packed formats to the datapath formats: the SAME shifts the RTL applies when it widens a packed half.
	constant XPK_SCALE					: integer := 2**(N_BITS - 15);	-- Q0.15  -> Q0.24
	constant WPK_SCALE					: integer := 2**(N_BITS - 12);	-- Q3.12  -> Q7.24

	-- Staging-RAM layout (word indices).  Unpacked and packed copies of the same vectors live side by side so one case can run both ways with no re-staging in between.
	constant IX_U		: natural := 0;			-- inputs, one element per word
	constant IX_P		: natural := 256;		-- inputs, two per word
	constant IW_U		: natural := 512;		-- weights, one element per word
	constant IW_P		: natural := 1536;		-- weights, two per word
	constant OY_REF		: natural := 2048;		-- reference (unpacked) outputs
	constant OY_DUT		: natural := 2304;		-- packed-run outputs

	constant THINK_POLL_MAX				: natural := 200000;

	----- NPU Port Signals
	signal Clk			: std_logic;
	signal ResetN		: std_logic;
	signal MabMmrA		: std_logic_vector(3 downto 0)
							:= (others => '0');
	signal MabMmrD		: std_logic_vector(31 downto 0)
							:= (others => '0');
	signal MabMmrCLK	: std_logic;
	signal MabMmrCEN	: std_logic := MEM_DEASSERT;
	signal MabMmrWEN	: std_logic_vector(3 downto 0)
							:= (others => MEM_DEASSERT);
	signal MabMmrQ		: std_logic_vector(31 downto 0);
	signal NpuSramQ		: std_logic_vector(31 downto 0);
	signal NpuActive	: std_logic;
	signal ThinkDoneIrq	: std_logic;

	signal NpuSramA_out	: std_logic_vector(11 downto 0);
	signal NpuSramD_out	: std_logic_vector(31 downto 0);
	signal NpuSramCLK_out	: std_logic;
	signal NpuSramCEN_out	: std_logic;
	signal NpuSramGWEN_out	: std_logic;
	signal NpuSramWEN_out	: std_logic_vector(3 downto 0);
	----- MCU to SRAM Interface Signals (Testbench controlled)
	signal MabSramA		: std_logic_vector(11 downto 0)
							:= (others => '0');
	signal MabSramD		: std_logic_vector(31 downto 0)
							:= (others => '0');
	signal MabSramCLK	: std_logic;
	signal MabSramCEN	: std_logic := MEM_DEASSERT;
	signal MabSramGWEN	: std_logic := MEM_DEASSERT;
	signal MabSramWEN	: std_logic_vector(3 downto 0)
							:= (others => MEM_DEASSERT);
	signal MabSramPGEN	: std_logic := '0';
	signal MabSramQ		: std_logic_vector(31 downto 0);
	signal SramClkEn	: std_logic;

	shared variable sb : scoreboard;

begin
	----- Component Instantiations
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

		MabMmrA		=> MabMmrA,
		MabMmrD		=> MabMmrD,
		MabMmrCLK	=> MabMmrCLK,
		MabMmrCEN	=> MabMmrCEN,
		MabMmrWEN	=> MabMmrWEN,
		MabMmrQ		=> MabMmrQ,

		SramQ_in	=> NpuSramQ,
		SramA_in 	=> MabSramA,
		SramD_in 	=> MabSramD,
		SramCLK_in 	=> MabSramCLK,
		SramCEN_in 	=> MabSramCEN,
		SramGWEN_in => MabSramGWEN,
		SramWEN_in 	=> MabSramWEN,

		NpuSramA_out	=> NpuSramA_out,
		NpuSramD_out	=> NpuSramD_out,
		NpuSramCLK_out	=> NpuSramCLK_out,
		NpuSramCEN_out	=> NpuSramCEN_out,
		NpuSramGWEN_out	=> NpuSramGWEN_out,
		NpuSramWEN_out	=> NpuSramWEN_out,

		NpuActive	=> NpuActive,
		ThinkDoneIrq	=> ThinkDoneIrq
	);

	-- SRAM Clock Gate
	SRAM_CLK_CG: entity work.ClkGate
	port map(
		ClkIn	=> Clk,
		En		=> SramClkEn,
		ClkOut	=> MabSramCLK
	);

	-- Single-Port SRAM Instantiation (the NPU staging RAM)
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

	SramClkEn <= '1' when (MabSramCEN = MEM_ASSERT) else '0';
	MabSramQ  <= NpuSramQ;

	-- Clock Process
	CLK_PROCESS: process
	begin
		Clk	<= '0';
		wait for CLK_DELAY;
		Clk	<= '1';
		wait for CLK_DELAY;
	end process CLK_PROCESS;
	MabMmrCLK	<= Clk;

	-- Main Test Simulation Process
	SIM_PROCESS: process
		type int_array is array (natural range <>) of integer;

		variable rd			: std_logic_vector(31 downto 0);
		-- Packed 16-bit test operands, as plain signed integers.  The unpacked copies are these times XPK_SCALE / WPK_SCALE, so every value is exact in both layouts.
		variable xs			: int_array(0 to 63);
		variable ws			: int_array(0 to 63);
		variable lfsr		: std_logic_vector(31 downto 0) := x"ACE1BEEF";

		/* Signed decimal image of a word.  NOT periph_tb_pkg's img(), which converts through UNSIGNED and hits INTEGER'HIGH -- aborting the run -- on any word with bit 31 set; these outputs are signed Q7.24 and are negative about half the time. */
		function simg(v : std_logic_vector) return string is
		begin
			for i in v'range loop
				if (v(i) /= '0') and (v(i) /= '1') then
					return "X";
				end if;
			end loop;
			return integer'image(to_integer(signed(v)));
		end function;

		-- to_sl: integer 0/1 to std_logic, for packing the single-bit NPUCR fields.
		function to_sl(v : integer) return std_logic is
		begin
			if v = 0 then return '0'; else return '1'; end if;
		end function;

		/* One step of a maximal-length 32-bit LFSR, sixteen shifts at a time so consecutive draws are uncorrelated.
		   Deliberately NOT an integer LCG: a 32-bit multiply overflows VHDL's INTEGER and aborts the run. */
		procedure step_lfsr(variable r : inout std_logic_vector(31 downto 0)) is
			variable fb : std_logic;
		begin
			for i in 1 to 16 loop
				fb := r(31) xor r(21) xor r(1) xor r(0);
				r  := r(30 downto 0) & fb;
			end loop;
		end procedure;

		/* A pseudo-random packed operand with a magnitude FLOOR.
		   The floor matters: a near-zero weight makes its neuron insensitive to that weight, which would let a packing bug pass unnoticed, and it is also what makes the negative control's single perturbation guaranteed-visible.
		   Magnitude lands in [2048, 16383], i.e. +-0.5 for a Q0.15 input and +-4.0 for a Q3.12 weight. */
		procedure rand_operand(variable r : inout std_logic_vector(31 downto 0);
		                       result     : out integer) is
			variable m : integer;
		begin
			step_lfsr(r);
			m := to_integer(unsigned(r(13 downto 0)));
			if m < 2048 then
				m := m + 2048;
			end if;
			if r(20) = '1' then
				m := -m;
			end if;
			result := m;
		end procedure;

		----- MMR primitives (falling-edge idiom, identical to the other NPU benches) -----
		procedure mmr_write(addr : natural; data : std_logic_vector(31 downto 0)) is
		begin
			wait until falling_edge(MabMmrCLK);
			MabMmrA   <= std_logic_vector(to_unsigned(addr, 4));
			MabMmrD   <= data;
			MabMmrWEN <= (others => MEM_ASSERT);
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN <= MEM_ASSERT;
			wait until falling_edge(MabMmrCLK);
			MabMmrCEN <= MEM_DEASSERT;
			MabMmrWEN <= (others => MEM_DEASSERT);
		end procedure;

		procedure mmr_read(addr : natural; result : out std_logic_vector(31 downto 0)) is
		begin
			wait until falling_edge(MabMmrCLK);
			MabMmrA   <= std_logic_vector(to_unsigned(addr, 4));
			MabMmrCEN <= MEM_ASSERT;
			wait until falling_edge(MabMmrCLK);
			wait until falling_edge(MabMmrCLK);
			result := MabMmrQ;
			MabMmrCEN <= MEM_DEASSERT;
		end procedure;

		/* SRAM primitives (backdoor MCU-side access).
		   MabSramCLK is a GATED clock: it only toggles once MabSramCEN is already asserted, so a burst must open CEN off the FREE-RUNNING Clk and wait on MabSramCLK only after that. */
		procedure sram_burst_start is
		begin
			wait until falling_edge(Clk);
			MabSramCEN <= MEM_ASSERT;
			wait until falling_edge(MabSramCLK);
		end procedure;

		procedure sram_burst_stop is
		begin
			MabSramWEN <= (others => MEM_DEASSERT);
			MabSramCEN <= MEM_DEASSERT;
		end procedure;

		procedure sram_write_word(addr : natural; data : std_logic_vector(31 downto 0)) is
		begin
			MabSramA <= std_logic_vector(to_unsigned(addr, 12));
			MabSramD <= data;
			wait until falling_edge(MabSramCLK);
			MabSramGWEN <= MEM_ASSERT;
			wait until falling_edge(MabSramCLK);
			MabSramGWEN <= MEM_DEASSERT;
		end procedure;

		procedure sram_read_word(addr : natural; result : out std_logic_vector(31 downto 0)) is
		begin
			MabSramA <= std_logic_vector(to_unsigned(addr, 12));
			wait until falling_edge(MabSramCLK);
			wait until falling_edge(MabSramCLK);
			result := MabSramQ;
		end procedure;

		-- One NPUCR word.  The two new bits ride byte lane 3 with ACTF, which is why the lane-3 write in the RTL had to widen from 25:24 to 27:24.
		function cr_word(mode, ben, aen, actf, think, wpk, xpk, ni_m1, nn_m1 : integer)
			return std_logic_vector is
		begin
			return "0000" &									-- 31:28 unimplemented, read 0
			       to_sl(xpk) &								-- 27 NPUXPK
			       to_sl(wpk) &								-- 26 NPUWPK
			       std_logic_vector(to_unsigned(actf, 3)) &	-- 25:23 ACTF
			       std_logic_vector(to_unsigned(mode, 3)) &	-- 22:20 MODE
			       '0' &									-- 19 TDIE
			       to_sl(ben) &								-- 18 BEN
			       to_sl(aen) &								-- 17 AEN
			       to_sl(think) &							-- 16 THINK
			       std_logic_vector(to_unsigned(ni_m1, 8)) &-- 15:8 NI
			       std_logic_vector(to_unsigned(nn_m1, 8));	-- 7:0  NN
		end function;

		-- Bounded poll of NPUCR bit 16 (THINK).  Bit 16 is the NPUTHINK flop re-inserted into the readback; if that re-insertion ever regressed, every case here would time out rather than silently pass.
		procedure think_poll(bound : natural; ok : out boolean) is
			variable i : natural := 0;
		begin
			ok := false;
			MabMmrCEN <= MEM_ASSERT;
			MabMmrA   <= std_logic_vector(to_unsigned(MmrAddrNPUCR, 4));
			wait until falling_edge(MabMmrCLK);
			while i < bound loop
				if to_X01(MabMmrQ(16)) = '0' then
					ok := true;
					exit;
				end if;
				wait until falling_edge(MabMmrCLK);
				i := i + 1;
			end loop;
			MabMmrCEN <= MEM_DEASSERT;
		end procedure;

		-- Program the address registers, the per-mode config words and NPUCR (with THINK), then wait for completion.
		procedure run_think(tag : string;
		                    mode, ben, aen, actf, wpk, xpk : integer;
		                    ni_m1, nn_m1 : integer;
		                    cfg1, cfg2 : std_logic_vector(31 downto 0);
		                    ivsar, wvsar, ovsar : natural) is
			variable poll_ok : boolean;
		begin
			mmr_write(MmrAddrNPUIVSAR, (31 downto 12 => '0') & std_logic_vector(to_unsigned(ivsar, 12)));
			mmr_write(MmrAddrNPUWVSAR, (31 downto 12 => '0') & std_logic_vector(to_unsigned(wvsar, 12)));
			mmr_write(MmrAddrNPUOVSAR, (31 downto 12 => '0') & std_logic_vector(to_unsigned(ovsar, 12)));
			mmr_write(MmrAddrNPUCFG1, cfg1);
			mmr_write(MmrAddrNPUCFG2, cfg2);
			mmr_write(MmrAddrNPUCR, cr_word(mode, ben, aen, actf, 1, wpk, xpk, ni_m1, nn_m1));
			think_poll(THINK_POLL_MAX, poll_ok);
			sb.check_true(tag & ": THINK completes within " & integer'image(THINK_POLL_MAX) &
			              "-cycle bound", poll_ok);
		end procedure;

		/* Stage nx inputs and nw weights in BOTH layouts.
		   corrupt_w >= 0 perturbs that one weight ELEMENT in the PACKED copy only (bit 12 of the 16-bit half, i.e. exactly 1.0 in Q3.12) and leaves the unpacked copy alone -- the negative control. */
		procedure stage_operands(nx, nw : natural; corrupt_w : integer) is
			variable lo, hi : std_logic_vector(15 downto 0);
			variable h		: std_logic_vector(15 downto 0);
		begin
			sram_burst_start;
			MabSramWEN <= (others => MEM_ASSERT);

			-- Inputs: one Q0.24 element per word, then two Q0.15 elements per word.
			for i in 0 to nx - 1 loop
				sram_write_word(IX_U + i, std_logic_vector(to_signed(xs(i) * XPK_SCALE, 32)));
			end loop;
			for i in 0 to ((nx + 1) / 2) - 1 loop
				lo := std_logic_vector(to_signed(xs(2*i), 16));
				if (2*i + 1) < nx then
					hi := std_logic_vector(to_signed(xs(2*i + 1), 16));
				else
					hi := (others => '0');
				end if;
				sram_write_word(IX_P + i, hi & lo);
			end loop;

			-- Weights: one Q7.24 element per word, then two Q3.12 elements per word.
			for j in 0 to nw - 1 loop
				sram_write_word(IW_U + j, std_logic_vector(to_signed(ws(j) * WPK_SCALE, 32)));
			end loop;
			for j in 0 to ((nw + 1) / 2) - 1 loop
				lo := std_logic_vector(to_signed(ws(2*j), 16));
				if (2*j + 1) < nw then
					hi := std_logic_vector(to_signed(ws(2*j + 1), 16));
				else
					hi := (others => '0');
				end if;
				if corrupt_w >= 0 then
					if corrupt_w = 2*j then
						h := lo; h(12) := not h(12); lo := h;
					elsif corrupt_w = (2*j + 1) then
						h := hi; h(12) := not h(12); hi := h;
					end if;
				end if;
				sram_write_word(IW_P + j, hi & lo);
			end loop;
			sram_burst_stop;
		end procedure;

		/* One differential case: run unpacked into OY_REF, run packed into OY_DUT, demand equality on nout words.
		   Also demands that the reference is not identically zero, so a DUT that wrote nothing (or wrote zeros) cannot pass vacuously. */
		procedure run_case(case_name : string;
		                   mode, ben, aen, actf : integer;
		                   ni_m1, nn_m1 : integer;
		                   cfg1, cfg2 : std_logic_vector(31 downto 0);
		                   nx, nw, nout : natural;
		                   use_wpk, use_xpk : integer;
		                   corrupt_w : integer := -1) is
			variable ref_w, dut_w : std_logic_vector(31 downto 0);
			variable any_nonzero  : boolean := false;
			variable iv, wv       : natural;
		begin
			report "[NPU_PACK_TB] === case: " & case_name &
			       "  (WPK=" & integer'image(use_wpk) &
			       " XPK=" & integer'image(use_xpk) & ") ===" severity note;

			stage_operands(nx, nw, corrupt_w);

			-- Reference leg: both bits CLEAR, one element per word.
			run_think(case_name & "/ref", mode, ben, aen, actf, 0, 0,
			          ni_m1, nn_m1, cfg1, cfg2, IX_U, IW_U, OY_REF);

			-- Device leg: the bits under test, over the packed copies of the same numbers.
			if use_xpk = 1 then iv := IX_P; else iv := IX_U; end if;
			if use_wpk = 1 then wv := IW_P; else wv := IW_U; end if;
			run_think(case_name & "/pack", mode, ben, aen, actf, use_wpk, use_xpk,
			          ni_m1, nn_m1, cfg1, cfg2, iv, wv, OY_DUT);

			sram_burst_start;
			for i in 0 to nout - 1 loop
				sram_read_word(OY_REF + i, ref_w);
				sram_read_word(OY_DUT + i, dut_w);
				if ref_w /= x"00000000" then
					any_nonzero := true;
				end if;
				sb.check_true(case_name & ": output " & integer'image(i) &
				              " packed == unpacked (ref=" & simg(ref_w) &
				              ", pack=" & simg(dut_w) & ")",
				              dut_w = ref_w);
			end loop;
			sram_burst_stop;
			sb.check_true(case_name & ": reference output vector is not identically zero",
			              any_nonzero);
		end procedure;

		variable cfg1_v, cfg2_v : std_logic_vector(31 downto 0);
		variable ref_w, dut_w   : std_logic_vector(31 downto 0);
		variable corrupt_idx    : integer := -1;
	begin
		----- Reset NPU -----
		report "[NPU_PACK_TB] Starting NPU packed-operand testbench (NEGCTRL=" &
		       integer'image(NEGCTRL) & ")..." severity note;
		ResetN <= '0';
		wait for 1 us;
		wait until falling_edge(Clk);
		ResetN <= '1';
		MabSramPGEN <= '0';
		wait for 1 us;
		report "[NPU_PACK_TB] Reset complete." severity note;

		/* Negative control: perturb weight ELEMENT 0 of the packed copy only.  Weights are neuron-major, so element 0 belongs to neuron 0 alone and exactly one of mlp_wpk's five outputs can move.
		   The perturbation is bit 12 of the Q3.12 half, i.e. exactly 1.0, and rand_operand's magnitude floor guarantees the paired input is at least 0.0625, so the accumulator shift is far larger than a rounding step and cannot vanish. */
		if NEGCTRL = 1 then
			corrupt_idx := 0;
		else
			corrupt_idx := -1;
		end if;

		-- Deterministic operand set, generated once and reused by every case.
		for i in xs'range loop
			rand_operand(lfsr, xs(i));
		end loop;
		for j in ws'range loop
			rand_operand(lfsr, ws(j));
		end loop;

		/* --------------------------------------------------------------
		   NPUCR readback: the two new bits must be readable, the bits above them must still read 0, and NPUTHINK must still appear at bit 16.
		   That last check is a standing regression guard: NPUTHINK is a separate flop re-inserted into the readback word, and widening that word is exactly the edit that could drop it again.
		   -------------------------------------------------------------- */
		report "[NPU_PACK_TB] === NPUCR readback ===" severity note;
		mmr_write(MmrAddrNPUCR, cr_word(0, 0, 0, 0, 0, 1, 1, 16#5A#, 16#3C#));
		mmr_read(MmrAddrNPUCR, rd);
		sb.check_bit("NPUCR.NPUWPK (26) reads back set", to_X01(rd(26)), '1');
		sb.check_bit("NPUCR.NPUXPK (27) reads back set", to_X01(rd(27)), '1');
		sb.check_slv("NPUCR bits 31:28 still read 0", rd(31 downto 28), "0000");
		sb.check_bit("NPUCR.NPUTHINK (16) reads 0 with no THINK pending", to_X01(rd(16)), '0');
		sb.check_slv("NPUCR.NPUNI/NPUNN survive the widened lane-3 write", rd(15 downto 0),
		             x"5A3C");
		mmr_write(MmrAddrNPUCR, cr_word(0, 0, 0, 0, 0, 0, 0, 0, 0));
		mmr_read(MmrAddrNPUCR, rd);
		sb.check_slv("NPUCR pack bits clear again", rd(27 downto 26), "00");

		/* --------------------------------------------------------------
		   MLP, K=7 (ODD): the input walk crosses packed-word boundaries inside a neuron and restarts at element 0 for the next neuron, so a walker that packed the ADDRESS rather than the ELEMENT index would drift on the second neuron.
		   -------------------------------------------------------------- */
		cfg1_v := (others => '0');
		cfg2_v := (others => '0');
		run_case("mlp_xpk", 0, 0, 0, 0, 6, 4, cfg1_v, cfg2_v, 7, 35, 5, 0, 1);
		run_case("mlp_wpk", 0, 0, 0, 0, 6, 4, cfg1_v, cfg2_v, 7, 35, 5, 1, 0,
		         corrupt_w => corrupt_idx);
		run_case("mlp_both", 0, 0, 0, 0, 6, 4, cfg1_v, cfg2_v, 7, 35, 5, 1, 1);

		/* --------------------------------------------------------------
		   MLP with NPUBEN: each neuron's weight block is 1+K = 5 elements, an ODD count, so neuron n's block starts in the low half for even n and the high half for odd n.
		   The bias element is fetched from the weight stream with no input fetch, which is the one place the two walkers advance at different rates.
		   -------------------------------------------------------------- */
		run_case("mlp_ben", 0, 1, 0, 0, 3, 2, cfg1_v, cfg2_v, 4, 15, 3, 1, 1);

		-- Activation on (sigmoid): proves the packed operands reach the activation path unchanged.
		run_case("mlp_aen_sig", 0, 0, 1, 0, 6, 4, cfg1_v, cfg2_v, 7, 35, 5, 1, 1);
		-- ReLU, whose output word shape differs from the sigmoid's.
		run_case("mlp_aen_relu", 0, 0, 1, 1, 6, 4, cfg1_v, cfg2_v, 7, 35, 5, 1, 1);

		/* --------------------------------------------------------------
		   GEMM, M=3 x K=3 x N=2 with an ODD K: the input row base mK advances by 3 elements per row, so rows 0/1/2 start in the low, high and low halves respectively -- the straddle a word-domain row pointer could not express.
		   The weight walk reloads to element 0 of the B block once per row.
		   -------------------------------------------------------------- */
		cfg1_v := std_logic_vector(to_unsigned(2, 32));		-- M-1
		cfg2_v := (others => '0');
		run_case("gemm_odd_k", 3, 0, 0, 0, 2, 1, cfg1_v, cfg2_v, 9, 6, 6, 1, 1);

		/* --------------------------------------------------------------
		   CONV1D: Cin=2, L=8, taps K=3, S=1, D=1, Lout=6, Cout=2, bias on.
		   This is the walker-heavy case: the input address is the four-term sum IVSAR + c*L + j*S + k*D (all in the ELEMENT domain under packing), and the weight offset RELOADS to the filter base for every output j, then snapshots the next filter's base at the filter boundary.  The per-filter block is 1 + Cin*K = 7 elements, ODD, so filter 1 starts in the other half.
		   -------------------------------------------------------------- */
		cfg1_v := std_logic_vector(to_unsigned(1, 8)) &		-- 31:24 Cin-1
		          std_logic_vector(to_unsigned(8, 16)) &	-- 23:8  L
		          x"1" &									-- 7:4   D
		          x"1";										-- 3:0   S
		cfg2_v := std_logic_vector(to_unsigned(6, 32));		-- Lout
		run_case("conv_c2", 1, 1, 0, 0, 2, 1, cfg1_v, cfg2_v, 16, 14, 12, 1, 1);

		/* --------------------------------------------------------------
		   XNOR must IGNORE both bits: it already packs 32 one-bit operands per word and walks whole words, so the run shadows are forced off for MODE 2.
		   Same problem run with the bits clear and with both set; the two output vectors must agree.
		   K=40 over 2 words per neuron (NPUNI=1), 3 neurons, THRESH=0.
		   -------------------------------------------------------------- */
		report "[NPU_PACK_TB] === case: xnor_bits_inert ===" severity note;
		sram_burst_start;
		MabSramWEN <= (others => MEM_ASSERT);
		sram_write_word(IX_U + 0, x"A5A5F0F0");
		sram_write_word(IX_U + 1, x"000000C3");
		sram_write_word(IW_U + 0, x"A5A50F0F");
		sram_write_word(IW_U + 1, x"0000003C");
		sram_write_word(IW_U + 2, x"FFFFFFFF");
		sram_write_word(IW_U + 3, x"000000FF");
		sram_write_word(IW_U + 4, x"00000000");
		sram_write_word(IW_U + 5, x"00000000");
		sram_burst_stop;
		cfg1_v := (others => '0');							-- THRESH = 0
		cfg2_v := std_logic_vector(to_unsigned(40, 32));	-- K = 40
		run_think("xnor/bits-clear", 2, 0, 0, 0, 0, 0, 1, 2, cfg1_v, cfg2_v,
		          IX_U, IW_U, OY_REF);
		run_think("xnor/bits-set",   2, 0, 0, 0, 1, 1, 1, 2, cfg1_v, cfg2_v,
		          IX_U, IW_U, OY_DUT);
		sram_burst_start;
		for i in 0 to 2 loop
			sram_read_word(OY_REF + i, ref_w);
			sram_read_word(OY_DUT + i, dut_w);
			sb.check_true("xnor_bits_inert: output " & integer'image(i) &
			              " unaffected by NPUWPK/NPUXPK (clear=" & simg(ref_w) &
			              ", set=" & simg(dut_w) & ")", dut_w = ref_w);
			sb.check_true("xnor_bits_inert: output " & integer'image(i) &
			              " is a +-1.0 decision word",
			              (ref_w = x"01000000") or (ref_w = x"FF000000"));
		end loop;
		sram_burst_stop;

		----- Final verdict -----
		wait for 1 us;
		report "[NPU_PACK_TB] All groups complete (" & integer'image(sb.errors) &
		       " check(s) failed)." severity note;

		if NEGCTRL = 0 then
			if sb.errors = 0 then
				report LF & LF &
					"    ##################################################" & LF &
					"    ##                                              ##" & LF &
					"    ##   NPU PACK TB:  ALL CHECKS PASSED             ##" & LF &
					"    ##                                              ##" & LF &
					"    ##################################################" & LF
					severity note;
			else
				report LF & LF &
					"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
					"    !!   NPU PACK TB FAIL: " & integer'image(sb.errors) &
					       " CHECK(S) FAILED" & LF &
					"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
					severity warning;
			end if;
		else
			-- Negative control: exactly one packed weight half was perturbed, and weights are neuron-major, so exactly one of mlp_wpk's five outputs must disagree.
			if sb.errors = 1 then
				report LF & LF &
					"    ##################################################" & LF &
					"    ##   NPU PACK TB NEGCTRL-PASS (exactly 1 expected fail)" & LF &
					"    ##################################################" & LF
					severity note;
			else
				report LF & LF &
					"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
					"    !!   NPU PACK TB NEGCTRL-FAIL: expected EXACTLY 1 failure, got " &
					       integer'image(sb.errors) & LF &
					"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
					severity warning;
			end if;
		end if;

		stop;
		wait;
	end process SIM_PROCESS;
end testbench;
