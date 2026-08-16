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

-------------------------------------------------------------------------------
-- NPU_xnor_tb.vhd: XNOR/popcount mode (NPUCR.MODE=2) bench for the NPU plus its staging-RAM model.
-- Runs at the chip generics (X_M=0, W_M=7, Y_M=7, N=24, RHO=2); the +/-1.0 output words are exact only there.
-- Cases are driven from golden files npu_xnor_<case>_{cfg,in,w,exp}.txt, symlinked into the run directory.
-- cfg header order is fixed: K N THRESH IVSAR WVSAR OVSAR; NW = ceil(K/32) is derived, not a header field.
-- NEGCTRL=0 runs clean and banners ALL-PASS on 0 errors; NEGCTRL=1 corrupts one expected value and banners on exactly 1.
-------------------------------------------------------------------------------
entity NPU_xnor_tb is
	generic (
		NEGCTRL : integer := 0
	);
end NPU_xnor_tb;

architecture testbench of NPU_xnor_tb is
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

	-- Chip generics, not the NPU entity's own Q0.15/Q3.15 defaults: the golden +/-1.0 word encoding only holds here.
	constant X_M_BITS					: integer := 0;
    constant W_M_BITS					: integer := 7;
    constant Y_M_BITS					: integer := 7;
	constant N_BITS						: integer := 24;
	constant RHO						: integer := 2;

	-- Bounded poll ceiling: the worst case is about 1539 NpuClk cycles, and this stays far short of the tb watchdog.
	constant THINK_POLL_MAX				: natural := 20000;

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

		-- parse_u32: decimal string into a raw 32-bit vector via a 64-bit accumulator; the packed in/w words reach 2**32-1 and would overflow a std.textio read into INTEGER.
		-- Must be a procedure, not a function: VHDL forbids an access type (line) as a function formal parameter.
		procedure parse_u32(variable l_in : in line; result : out std_logic_vector(31 downto 0)) is
			variable acc : unsigned(63 downto 0) := (others => '0');
			variable neg : boolean := false;
			variable ch  : character;
		begin
			for i in l_in.all'range loop
				ch := l_in.all(i);
				if ch = '-' then
					neg := true;
				elsif ch >= '0' and ch <= '9' then
					-- unsigned "*" returns a double-width result, so resize back to 64 before the "+"; every intermediate stays far below 2**64.
					acc := resize(acc * to_unsigned(10, 64), 64) +
					       to_unsigned(character'pos(ch) - character'pos('0'), 64);
				end if;
			end loop;
			if neg then
				result := std_logic_vector(-signed(acc(31 downto 0)));
			else
				result := std_logic_vector(acc(31 downto 0));
			end if;
		end procedure;

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

		----- SRAM primitives: backdoor MCU-side access -----
		-- MabSramCLK is gated by MabSramCEN, so a burst must assert CEN off the free-running Clk, then wait on MabSramCLK edges per word, and only deassert CEN at the end.
		-- sram_burst_start: open the gate and land on the first gated clock edge.
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

		-- think_start: pokes IVSAR/WVSAR/OVSAR/NPUCFG1(THRESH)/NPUCFG2(K)/NPUCR for one case, deriving NW = ceil(K/32).
		-- NPUCR gets MODE=XNOR, THINK=1, NI=NW-1, NN=N-1, with BEN=AEN=ACTF=TDIE=0 per the firmware contract.
		procedure think_start(k, n, thresh, ivsar, wvsar, ovsar : integer) is
			variable cr : std_logic_vector(31 downto 0);
			variable nw : integer;
		begin
			nw := (k + 31) / 32;

			mmr_write(MmrAddrNPUIVSAR, (31 downto 12 => '0') & std_logic_vector(to_unsigned(ivsar, 12)));
			mmr_write(MmrAddrNPUWVSAR, (31 downto 12 => '0') & std_logic_vector(to_unsigned(wvsar, 12)));
			mmr_write(MmrAddrNPUOVSAR, (31 downto 12 => '0') & std_logic_vector(to_unsigned(ovsar, 12)));

			mmr_write(MmrAddrNPUCFG1, std_logic_vector(to_signed(thresh, 32)));
			mmr_write(MmrAddrNPUCFG2, (31 downto 16 => '0') & std_logic_vector(to_unsigned(k, 16)));

			cr := std_logic_vector(to_unsigned(0, 6)) &          -- 31:26 unused
			      std_logic_vector(to_unsigned(0, 3)) &          -- 25:23 ACTF=0
			      "010" &                                        -- 22:20 MODE=XNOR
			      '0' &                                          -- 19 TDIE
			      '0' &                                          -- 18 BEN=0
			      '0' &                                          -- 17 AEN=0
			      '1' &                                          -- 16 THINK
			      std_logic_vector(to_unsigned(nw - 1, 8)) &     -- 15:8 NI = NW-1
			      std_logic_vector(to_unsigned(n - 1, 8));       -- 7:0  NN = N-1
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

		-- run_xnor_case: loads npu_xnor_<case_name>_{cfg,in,w,exp}.txt, runs the THINK, and compares every output.
		--   corrupt_first : deliberately wrong first expected value; check_no_x : also assert each output is fully defined.
		procedure run_xnor_case(case_name     : string;
		                        corrupt_first : boolean := false;
		                        check_no_x    : boolean := false) is
			file cfg_f : text;
			file in_f  : text;
			file w_f   : text;
			file exp_f : text;
			variable k_v, n_v, thresh_v, ivsar_v, wvsar_v, ovsar_v : integer;
			variable nw_v    : integer;
			variable addr    : integer;
			variable exp_val : integer;
			variable act_val : integer;
			variable outc    : integer;
			variable poll_ok : boolean;
			variable wv      : std_logic_vector(31 downto 0);
		begin
			report "[NPU_XNOR_TB] === case: " & case_name & " ===" severity note;

			file_open(cfg_f, "npu_xnor_" & case_name & "_cfg.txt", read_mode);
			readline(cfg_f, ln); read(ln, k_v);
			readline(cfg_f, ln); read(ln, n_v);
			readline(cfg_f, ln); read(ln, thresh_v);
			readline(cfg_f, ln); read(ln, ivsar_v);
			readline(cfg_f, ln); read(ln, wvsar_v);
			readline(cfg_f, ln); read(ln, ovsar_v);
			file_close(cfg_f);

			nw_v := (k_v + 31) / 32;

			report "  K=" & integer'image(k_v) & " N=" & integer'image(n_v) &
			       " THRESH=" & integer'image(thresh_v) & " NW=" & integer'image(nw_v) &
			       " IVSAR=" & integer'image(ivsar_v) & " WVSAR=" & integer'image(wvsar_v) &
			       " OVSAR=" & integer'image(ovsar_v) severity note;

			-- load activations + weights in ONE SRAM burst
			sram_burst_start;
			MabSramWEN <= (others => MEM_ASSERT);

			file_open(in_f, "npu_xnor_" & case_name & "_in.txt", read_mode);
			addr := ivsar_v;
			while not endfile(in_f) loop
				readline(in_f, ln);
				parse_u32(ln, wv);
				sram_write_word(addr, wv);
				addr := addr + 1;
			end loop;
			file_close(in_f);

			file_open(w_f, "npu_xnor_" & case_name & "_w.txt", read_mode);
			addr := wvsar_v;
			while not endfile(w_f) loop
				readline(w_f, ln);
				parse_u32(ln, wv);
				sram_write_word(addr, wv);
				addr := addr + 1;
			end loop;
			file_close(w_f);
			sram_burst_stop;

			think_start(k_v, n_v, thresh_v, ivsar_v, wvsar_v, ovsar_v);
			think_poll(THINK_POLL_MAX, poll_ok);
			sb.check_true(case_name & ": THINK completes within " &
			              integer'image(THINK_POLL_MAX) & "-cycle bound", poll_ok);

			-- compare outputs (flat neuron order n=0..N-1)
			file_open(exp_f, "npu_xnor_" & case_name & "_exp.txt", read_mode);
			outc := 0;
			sram_burst_start;
			while not endfile(exp_f) loop
				readline(exp_f, ln);
				read(ln, exp_val);
				if corrupt_first and (outc = 0) then
					report "  NEGCTRL=1: deliberately corrupting expected output 0 (" &
					       integer'image(exp_val) & " -> " & integer'image(exp_val + 1) &
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
		report "[NPU_XNOR_TB] Starting NPU XNOR testbench (NEGCTRL=" &
		       integer'image(NEGCTRL) & ")..." severity note;
		ResetN <= '0';
		wait for 1 us;
		wait until falling_edge(Clk);
		ResetN <= '1';
		MabSramPGEN <= '0';
		wait for 1 us;
		report "[NPU_XNOR_TB] Reset complete." severity note;

		----------------------------------------------------------------
		-- Base case runs first after reset with no CFG pokes ahead of it, so its definedness check proves the XNOR registers cannot drive X on the SRAM interface out of cold reset.
		-- Keep it first; it is also the invocation NEGCTRL=1 corrupts.
		----------------------------------------------------------------
		run_xnor_case("base", corrupt_first => (NEGCTRL = 1), check_no_x => true);

		----------------------------------------------------------------
		-- NPUCFG1(THRESH)/NPUCFG2(K) readback smoke: the contract is an exact full write/read.
		----------------------------------------------------------------
		report "[NPU_XNOR_TB] === NPUCFG1/NPUCFG2 readback ===" severity note;
		mmr_write(MmrAddrNPUCFG1, std_logic_vector(to_signed(-12345, 32)));
		mmr_read(MmrAddrNPUCFG1, rd);
		sb.check_slv("NPUCFG1 readback exact (THRESH write/read)", rd,
		             std_logic_vector(to_signed(-12345, 32)));

		mmr_write(MmrAddrNPUCFG2, std_logic_vector(to_unsigned(4096, 32)));
		mmr_read(MmrAddrNPUCFG2, rd);
		sb.check_slv("NPUCFG2 readback (K=4096 exact, full 16-bit write/read)", rd,
		             std_logic_vector(to_unsigned(4096, 32)));

		----------------------------------------------------------------
		-- Remaining groups: ordinary file-driven cases.
		----------------------------------------------------------------
		run_xnor_case("tail40");
		run_xnor_case("tail40_tailalt");
		run_xnor_case("tail33");
		run_xnor_case("tie");
		run_xnor_case("tie_offlattice");
		run_xnor_case("extremes_k1");
		run_xnor_case("extremes_k4096");
		run_xnor_case("extremes_n256");
		run_xnor_case("neuronorder");

		----- Final verdict: banner polarity depends on NEGCTRL -----
		wait for 1 us;
		report "[NPU_XNOR_TB] All groups complete (" & integer'image(sb.errors) &
		       " check(s) failed)." severity note;

		if NEGCTRL = 0 then
			if sb.errors = 0 then
				report LF & LF &
					"    ##################################################" & LF &
					"    ##                                              ##" & LF &
					"    ##   NPU XNOR TB:  ALL CHECKS PASSED             ##" & LF &
					"    ##                                              ##" & LF &
					"    ##################################################" & LF
					severity note;
			else
				report LF & LF &
					"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
					"    !!                                              !!" & LF &
					"    !!   NPU XNOR TB FAIL: " & integer'image(sb.errors) &
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
					"    ##   NPU XNOR TB NEGCTRL-PASS (exactly 1 expected fail)" & LF &
					"    ##                                              ##" & LF &
					"    ##################################################" & LF
					severity note;
			else
				report LF & LF &
					"    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
					"    !!                                              !!" & LF &
					"    !!   NPU XNOR TB NEGCTRL-FAIL: expected EXACTLY 1 failure, got " &
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
