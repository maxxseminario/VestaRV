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
   NPU_actf_tb.vhd: ACTF activation-mux bench (NPUCR.MODE=0/MLP, ACTF = NPUCR(25:23)) at the chip generics (X_M=0, W_M=7, Y_M=7, N=24, RHO=2).
   MLP mode with NI=0 and BEN=0 makes each neuron a single MAC tap acc = X_HALF * w_neuron, so the golden generator can stage any exact Q7.24 accumulator by picking w_neuron = 2*target.
   Cases are driven from golden files npu_actf_<case>_{cfg,in,w,exp}.txt, symlinked into the run directory.
   cfg header order is fixed: NI NN BEN AEN ACTF IVSAR WVSAR OVSAR; in.txt is NI+1 Q0.24 words, w.txt is (NN+1)*(NI+1+BEN) Q7.24 words, exp.txt is NN+1 post-activation words (raw accumulator when AEN=0).
   NEGCTRL=0 runs clean and banners ALL-PASS on 0 errors; NEGCTRL=1 corrupts one expected value in the final case and banners on exactly 1.
   ----------------------------------------------------------------------------- */
entity NPU_actf_tb is
	generic (
		NEGCTRL : integer := 0
	);
end NPU_actf_tb;

architecture testbench of NPU_actf_tb is
	----- Clock Information
	-- 25 MHz / 40 ns matches the NPU synthesis close and its SDF; do not raise it.
	constant CLK_FREQ   : integer 	:= 25e6;                 -- 25 MHz
	constant CLK_PERIOD : time		:= 1 sec / CLK_FREQ;     -- 40 ns
	constant CLK_DELAY	: time 		:= CLK_PERIOD/2;

	----- Constants
	constant MEM_ASSERT			: std_logic	:= '0';
	constant MEM_DEASSERT		: std_logic	:= '1';
	-- MMR address constants, mirrored from MemoryMap.vhd rather than pulling that package in here.
	constant MmrAddrNPUCR		: natural	:= 0;
	constant MmrAddrNPUIVSAR	: natural	:= 1;
	constant MmrAddrNPUWVSAR	: natural	:= 2;
	constant MmrAddrNPUOVSAR	: natural	:= 3;
	constant MmrAddrNPUSR		: natural	:= 4;
	constant MmrAddrNPUCFG1		: natural	:= 5;
	constant MmrAddrNPUCFG2		: natural	:= 6;
	constant MmrAddrNPUCFG3		: natural	:= 7;	-- no storage; always reads 0

	-- Chip generics, not the NPU entity's own bench defaults: they must match the golden generator's fixed-point encoding.
	constant X_M_BITS					: integer := 0;
    constant W_M_BITS					: integer := 7;
    constant Y_M_BITS					: integer := 7;
	constant N_BITS						: integer := 24;
	constant RHO						: integer := 2;

	-- Bounded poll ceiling, deliberately generous: T = 1 + NN*(5*NI + 3*B + 1) + 2, so with NI=B=0 the largest case needs 10 cycles.
	constant THINK_POLL_MAX				: natural := 500;

    ----- NPU Port Signals
    signal Clk			: std_logic;
    signal ResetN		: std_logic;
	signal  MabMmrA		: std_logic_vector(3 downto 0)
							:= (others => '0');
    signal MabMmrD		: std_logic_vector(31 downto 0)
								:= (others => '0');
    signal MabMmrCLK	: std_logic;
    signal MabMmrCEN	: std_logic := MEM_DEASSERT;
    signal MabMmrWEN	: std_logic_vector(3 downto 0)
							:= (others => MEM_DEASSERT);
    signal MabMmrQ		: std_logic_vector(31 downto 0);
    signal NpuSramA		: std_logic_vector(11 downto 0);
    signal NpuSramD		: std_logic_vector(31 downto 0);
    signal NpuSramCLK	: std_logic;
    signal NpuSramCEN	: std_logic;
    signal NpuSramGWEN	: std_logic;
    signal NpuSramWEN	: std_logic_vector(3 downto 0);
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
    -- NPU instantiation without internal SRAM, at the chip generics.
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

    -- Open the MCU-side SRAM clock gate only while CEN is asserted, and mirror the RAM read data back to the MCU port.
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
		variable rd			: std_logic_vector(31 downto 0);
		variable ln			: line;
		variable ival		: integer;

		-- has_x: definedness check, hand-written with no Is_X dependency so it compiles under -V200X.
		function has_x(v : std_logic_vector) return boolean is
		begin
			for i in v'range loop
				if (v(i) = 'X') or (v(i) = 'U') or (v(i) = 'Z') or
				   (v(i) = 'W') or (v(i) = '-') then
					return true;
				end if;
			end loop;
			return false;
		end function;

		-- to_sl: integer flag to a single bit, 0 gives '0' and anything else gives '1'.
		function to_sl(v : integer) return std_logic is
		begin
			if v = 0 then return '0'; else return '1'; end if;
		end function;

		----- MMR primitives, all transitions on the falling MMR clock edge -----
		-- mmr_write: one MMR register write.
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

		-- mmr_read: one MMR register read; Q is sampled two falling edges after CEN asserts.
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

		/* --- SRAM primitives: backdoor MCU-side access -----
		   MabSramCLK is a GATED clock that only toggles once CEN is asserted, so a burst opens the gate first, clocks every word, and closes it at the end.
		   sram_burst_start: open the gate and land on the first gated clock edge. */
		procedure sram_burst_start is
		begin
			wait until falling_edge(Clk);
			MabSramCEN <= MEM_ASSERT;
			wait until falling_edge(MabSramCLK);
		end procedure;

		-- sram_burst_stop: release the write enables and close the gate.
		procedure sram_burst_stop is
		begin
			MabSramWEN <= (others => MEM_DEASSERT);
			MabSramCEN <= MEM_DEASSERT;
		end procedure;

		-- sram_write_word: one word, assuming a burst is already open (CEN asserted, WEN set as the caller wants).
		procedure sram_write_word(addr : natural; data : std_logic_vector(31 downto 0)) is
		begin
			MabSramA <= std_logic_vector(to_unsigned(addr, 12));
			MabSramD <= data;
			wait until falling_edge(MabSramCLK);
			MabSramGWEN <= MEM_ASSERT;
			wait until falling_edge(MabSramCLK);
			MabSramGWEN <= MEM_DEASSERT;
		end procedure;

		-- sram_read_word: one word out of an already-open burst; Q is valid on the second gated edge.
		procedure sram_read_word(addr : natural; result : out std_logic_vector(31 downto 0)) is
		begin
			MabSramA <= std_logic_vector(to_unsigned(addr, 12));
			wait until falling_edge(MabSramCLK);
			wait until falling_edge(MabSramCLK);
			result := MabSramQ;
		end procedure;

		-- think_start: pokes IVSAR/WVSAR/OVSAR/NPUCR for one case, with MODE=MLP, THINK=1 and NI/NN/BEN/AEN/ACTF as given.
		procedure think_start(ni, nn, ben, aen, actf, ivsar, wvsar, ovsar : integer) is
			variable cr : std_logic_vector(31 downto 0);
		begin
			mmr_write(MmrAddrNPUIVSAR, (31 downto 12 => '0') & std_logic_vector(to_unsigned(ivsar, 12)));
			mmr_write(MmrAddrNPUWVSAR, (31 downto 12 => '0') & std_logic_vector(to_unsigned(wvsar, 12)));
			mmr_write(MmrAddrNPUOVSAR, (31 downto 12 => '0') & std_logic_vector(to_unsigned(ovsar, 12)));

			cr := std_logic_vector(to_unsigned(0, 6)) &          -- 31:26 unused
			      std_logic_vector(to_unsigned(actf, 3)) &       -- 25:23 ACTF
			      "000" &                                       -- 22:20 MODE=MLP
			      '0' &                                         -- 19 TDIE
			      to_sl(ben) &                                  -- 18 BEN
			      to_sl(aen) &                                  -- 17 AEN
			      '1' &                                         -- 16 THINK
			      std_logic_vector(to_unsigned(ni, 8)) &        -- 15:8 NI
			      std_logic_vector(to_unsigned(nn, 8));         -- 7:0  NN
			mmr_write(MmrAddrNPUCR, cr);
		end procedure;

		-- think_poll: bounded poll of NPUCR bit16 (THINK).
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

		-- run_actf_case: loads npu_actf_<case_name>_{cfg,in,w,exp}.txt, runs the THINK, and compares every output.
		--   check_no_x : also assert each output is fully defined; corrupt_mid : corrupt the mid-position expected value ((NN+1)/2); force_actf : a value >= 0 overrides the cfg file's ACTF.
		procedure run_actf_case(case_name     : string;
		                        check_no_x    : boolean := false;
		                        corrupt_mid   : boolean := false;
		                        force_actf    : integer := -1) is
			file cfg_f : text;
			file in_f  : text;
			file w_f   : text;
			file exp_f : text;
			variable ni_v, nn_v : integer;
			variable ben_v, aen_v, actf_v, actf_use : integer;
			variable ivsar_v, wvsar_v, ovsar_v : integer;
			variable addr    : integer;
			variable exp_val : integer;
			variable act_val : integer;
			variable outc    : integer;
			variable mid_idx : integer;
			variable poll_ok : boolean;
		begin
			report "[NPU_ACTF_TB] === case: " & case_name & " ===" severity note;

			file_open(cfg_f, "npu_actf_" & case_name & "_cfg.txt", read_mode);
			readline(cfg_f, ln); read(ln, ni_v);
			readline(cfg_f, ln); read(ln, nn_v);
			readline(cfg_f, ln); read(ln, ben_v);
			readline(cfg_f, ln); read(ln, aen_v);
			readline(cfg_f, ln); read(ln, actf_v);
			readline(cfg_f, ln); read(ln, ivsar_v);
			readline(cfg_f, ln); read(ln, wvsar_v);
			readline(cfg_f, ln); read(ln, ovsar_v);
			file_close(cfg_f);

			if force_actf >= 0 then
				actf_use := force_actf;
			else
				actf_use := actf_v;
			end if;

			mid_idx := (nn_v + 1) / 2;

			report "  NI=" & integer'image(ni_v) & " NN=" & integer'image(nn_v) &
			       " BEN=" & integer'image(ben_v) & " AEN=" & integer'image(aen_v) &
			       " ACTF=" & integer'image(actf_use) &
			       " IVSAR=" & integer'image(ivsar_v) & " WVSAR=" & integer'image(wvsar_v) &
			       " OVSAR=" & integer'image(ovsar_v) severity note;

			-- load X input(s) + weights in ONE SRAM burst
			sram_burst_start;
			MabSramWEN <= (others => MEM_ASSERT);

			file_open(in_f, "npu_actf_" & case_name & "_in.txt", read_mode);
			addr := ivsar_v;
			while not endfile(in_f) loop
				readline(in_f, ln);
				read(ln, ival);
				sram_write_word(addr, std_logic_vector(to_signed(ival, 32)));
				addr := addr + 1;
			end loop;
			file_close(in_f);

			file_open(w_f, "npu_actf_" & case_name & "_w.txt", read_mode);
			addr := wvsar_v;
			while not endfile(w_f) loop
				readline(w_f, ln);
				read(ln, ival);
				sram_write_word(addr, std_logic_vector(to_signed(ival, 32)));
				addr := addr + 1;
			end loop;
			file_close(w_f);
			sram_burst_stop;

			think_start(ni_v, nn_v, ben_v, aen_v, actf_use, ivsar_v, wvsar_v, ovsar_v);
			think_poll(THINK_POLL_MAX, poll_ok);
			sb.check_true(case_name & ": THINK completes within " &
			              integer'image(THINK_POLL_MAX) & "-cycle bound", poll_ok);

			-- compare outputs (flat neuron order)
			file_open(exp_f, "npu_actf_" & case_name & "_exp.txt", read_mode);
			outc := 0;
			sram_burst_start;
			while not endfile(exp_f) loop
				readline(exp_f, ln);
				read(ln, exp_val);
				if corrupt_mid and (outc = mid_idx) then
					report "  NEGCTRL=1: deliberately corrupting expected output " &
					       integer'image(outc) & " (" & integer'image(exp_val) &
					       " -> " & integer'image(exp_val + 1) &
					       ") -- the comparison below MUST fail." severity warning;
					exp_val := exp_val + 1;
				end if;
				sram_read_word(ovsar_v + outc, rd);
				act_val := to_integer(signed(rd));
				if check_no_x then
					sb.check_true(case_name & ": output " & integer'image(outc) &
					              " fully defined (no X/U/Z/W/-)", not has_x(rd));
				end if;
				sb.check_true(case_name & ": output " & integer'image(outc) &
				              " match (exp=" & integer'image(exp_val) &
				              ", act=" & integer'image(act_val) & ")",
				              act_val = exp_val);
				outc := outc + 1;
			end loop;
			sram_burst_stop;
			file_close(exp_f);
			report "  compared " & integer'image(outc) & " output(s)." severity note;
		end procedure;

	begin
		----- Reset NPU -----
		report "[NPU_ACTF_TB] Starting NPU ACTF testbench (NEGCTRL=" &
		       integer'image(NEGCTRL) & ")..." severity note;
		ResetN <= '0';
		wait for 1 us;
		wait until falling_edge(Clk);
		ResetN <= '1';
		MabSramPGEN <= '0';
		wait for 1 us;
		report "[NPU_ACTF_TB] Reset complete." severity note;

		/* --------------------------------------------------------------
		   sigregress runs first after reset with no CFG pokes ahead of it, so its definedness check proves actf_run and the act_out/relu/tanh/clamp/exp nets cannot drive X on the SRAM interface out of cold reset.
		   It is also the ACTF=0 mux-collapse compatibility anchor; keep it first.
		   -------------------------------------------------------------- */
		run_actf_case("sigregress", check_no_x => true);

		/* --------------------------------------------------------------
		   NPUCR ACTF-field readback smoke: a raw poke with THINK=0 confirms bits 25:23 store and read back exactly.
		   Harmless to any case's correctness, since think_start fully overwrites NPUCR every time.
		   -------------------------------------------------------------- */
		report "[NPU_ACTF_TB] === NPUCR ACTF-field readback ===" severity note;
		mmr_write(MmrAddrNPUCR,
		          std_logic_vector(to_unsigned(0, 6)) &   -- 31:26 unused
		          "110" &                                 -- 25:23 ACTF probe = 6 (reserved)
		          "000" &                                 -- 22:20 MODE=MLP
		          "0000" &                                -- 19 TDIE, 18 BEN, 17 AEN, 16 THINK=0 (no launch)
		          std_logic_vector(to_unsigned(0, 8)) &   -- 15:8 NI
		          std_logic_vector(to_unsigned(0, 8)));   -- 7:0 NN
		mmr_read(MmrAddrNPUCR, rd);
		sb.check_slv("NPUCR ACTF field readback (bits 25:23, THINK=0 no launch)",
		             rd(25 downto 23), "110");

		/* --------------------------------------------------------------
		   Remaining groups: ordinary file-driven cases.
		   -------------------------------------------------------------- */
		run_actf_case("relu");
		run_actf_case("tanh");
		run_actf_case("clamp");
		run_actf_case("expa");

		-- Reserved ACTF codes 5 and 7 must both produce the same sigmoid golden.
		run_actf_case("reserved");
		run_actf_case("reserved", force_actf => 7);

		-- AEN=0 is the activation master disable: with ACTF swept 0 to 4 the output must stay the raw accumulator.
		run_actf_case("aen0", force_actf => 0);
		run_actf_case("aen0", force_actf => 1);
		run_actf_case("aen0", force_actf => 2);
		run_actf_case("aen0", force_actf => 3);
		run_actf_case("aen0", force_actf => 4);

		/* --------------------------------------------------------------
		   Negative control, and it must stay the last action in this process: a rerun of "tanh" whose mid-position expected output is corrupted once when NEGCTRL=1.
		   -------------------------------------------------------------- */
		run_actf_case("tanh", corrupt_mid => (NEGCTRL = 1));

		----- Final verdict: banner polarity depends on NEGCTRL -----
		wait for 1 us;
		report "[NPU_ACTF_TB] All groups complete (" & integer'image(sb.errors) &
		       " check(s) failed)." severity note;

		if NEGCTRL = 0 then
			if sb.errors = 0 then
				report LF & LF &
					"    ##################################################" & LF &
					"    ##                                              ##" & LF &
					"    ##   NPU ACTF TB:  ALL CHECKS PASSED             ##" & LF &
					"    ##                                              ##" & LF &
					"    ##################################################" & LF
					severity note;
			else
				report LF & LF &
					"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
					"    !!                                              !!" & LF &
					"    !!   NPU ACTF TB FAIL: " & integer'image(sb.errors) &
					       " CHECK(S) FAILED" & LF &
					"    !!                                              !!" & LF &
					"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
					severity warning;
			end if;
		else
			if sb.errors = 1 then
				report LF & LF &
					"    ##################################################" & LF &
					"    ##                                              ##" & LF &
					"    ##   NPU ACTF TB NEGCTRL-PASS (exactly 1 expected fail)" & LF &
					"    ##                                              ##" & LF &
					"    ##################################################" & LF
					severity note;
			else
				report LF & LF &
					"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
					"    !!                                              !!" & LF &
					"    !!   NPU ACTF TB NEGCTRL-FAIL: expected EXACTLY 1 failure, got " &
					       integer'image(sb.errors) & LF &
					"    !!                                              !!" & LF &
					"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
					severity warning;
			end if;
		end if;

		stop;
		wait;
	end process SIM_PROCESS;
end testbench;
