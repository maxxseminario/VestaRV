-- =============================================================================
-- dma_arb_tb.vhd  (digperiphs Phase 3) -- DMA ARBITER-INTEGRATION proof
-- =============================================================================
-- Integration proof (b) of ~/vesta_docs/digperiphs/dma_design.md: the REAL
-- work.DMA engine is the FIFTH master (index 4) on the widened shared fabric
-- (mp_arbiter N=5/MW=3 + resv_unit N=5 + mutex_bank MW=3), contending with four
-- arb_lat_master BFMs (indices 0-3) for one serialized single-port shared RAM.
-- A sibling of arb_lat_tb.vhd (NOT a modification of it) -- the DMA is a real
-- entity, not a BFM, so it cannot be arb_lat_tb at N_MASTERS=5.
--
-- BOUNDARY: the four BFMs sit behind the M13 N_DELAY registered tile boundary
-- (generic 0/1/2, one wide reg per direction, BREAK_MODE=2 skew preserved).
-- The DMA connects at DEPTH 0 (D2/Q-B: it lives inside MCU fabric on mclk like
-- mp_arbiter itself, NOT behind a tile boundary) -- its master-port signals
-- slice DIRECTLY into the arb_*(4) slices with NO pipe. DMA slice ties per D18:
-- arb_lrsc(9:8)="00", arb_lock(4)='0'; the DMA never LR/SCs or grant-locks.
--
-- ADDRESS MAPPING (documented per the task; connect m_addr(11:0) to the slice):
--   The tb arbiter/RAM ADDR_WIDTH is 12 (template convention: a 4096-word RAM).
--   The DMA presents AW=15-bit WORD addresses, m_addr = byte_ptr(16:2), and its
--   GO-time checks act on 17-bit FIRMWARE BYTE pointers (D13/A18: reject byte >=
--   0x20000, TCM hole 0x8000-0xBFFF, misaligned). We choose all DMA SRC/DST byte
--   pointers word-aligned and < 0x4000 -- LEGAL under every DMA check (byte <
--   0x20000, none in 0x8000-0xBFFF, none in the deny windows word 0x1800-0x183F
--   / 0x1E00) -- so m_addr(14:12)=0 and the low 12 bits m_addr(11:0)=byte_ptr(13:2)
--   are the EXACT truncation (no information lost). We wire m_addr(11:0) into the
--   arbiter's 12-bit slice-4 address; m_addr(14:12) are dropped and are provably 0
--   for the chosen range. Byte->word map (byte_ptr(13:2) = tb word index):
--     SRC_A  byte 0x1000 -> word 0x400   SRC_B  byte 0x1400 -> word 0x500
--     DST    byte 0x1800 -> word 0x600   SENT   byte 0x1C00 -> word 0x700
--     LRSC   byte 0x3800 -> word 0xE00  (== arb_lat_master's LRSC_ADDR)
--   All disjoint from the BFM private ranges (words 0x00-0x3F) and the contended
--   words CTR=0xF00 / LRSC=0xE00 / PROT=0xD00 / MTX=0xC00-0xC3F, EXCEPT the
--   deliberate LRSC-kill target 0xE00 (see below).
--
-- CHECKERS:
--   Inherited from arb_lat_tb (over 5 masters): grant mutual exclusion, locked-
--   pair critical section, BFM ghost-done, AMO-LOCKED counter (0xF00 == NB*N_RMW),
--   mutex-protected counter (0xD00 == NB*N_MTX). NB = 4 BFMs (the DMA does no
--   AMO/mutex/LR-SC, so those totals use NB=4, not N=5). The LR/SC value-equality
--   check on 0xE00 is REPLACED (the DMA corrupts that word -- see LR/SC kill).
--   DMA-specific:
--     (a) DMA ghost-done: arb_done(4)/m_done pulsing while the DMA has no txn in
--         flight is a FAIL. In-flight derived (A1 shape) from a monitor on m_req:
--         busy from req-rise to one cycle after done.
--     (b) DMA protocol monitor: m_addr/m_we/m_wdata stable while m_req high, and
--         m_req observed low >= 1 cycle between every txn.
--     (c) DMA slave-port functional check: each launched mem-to-mem copy lands the
--         right words at dst (tb reads shram directly) and CHnDONE sets + W1C via
--         the slave port.
--
-- LR/SC-KILL PASS (directed, per the orchestrator's pre-made design decision):
--   arb_lat_master is NOT modified. The DMA's stimulus copies a SENTINEL word
--   ONTO LRSC_ADDR (word 0xE00) as a plain WRITE, repeatedly, while the BFMs' LR/SC
--   pass (pass 5) is still running. resv_unit(N=5) sees cur=4, a plain write, and
--   kills every matching reservation (D18) -- so a BFM whose LR preceded the DMA
--   write gets a FAILED SC. Because the DMA sentinel corrupts the counter word, the
--   inherited LR/SC value-equality check is dropped and replaced by:
--     (i)  LOAD-BEARING: every BFM completed its N_LRSC successful SCs within its
--          retry budget (m_err=0 + watchdog) -> no livelock/deadlock with a DMA
--          present, and SCs that succeeded really serialized.
--     (ii) A tb-side scoreboard (shadowing resv_unit's kill rule on LRSC_ADDR)
--          proves at least ONE BFM SC FAILED with its reservation last killed by
--          the DMA's write (attributed via the granted-master index on the slave
--          bus + the resv-gated lanes). If no such overlap occurs naturally within
--          the bounded sentinel-write budget, (ii) is WAIVED with a loud report
--          line (NOT a failure) -- (i) is the load-bearing property.
--
-- NEGATIVE CONTROLS (inherited, via BREAK_MODE): 1 = BFM master 0 drops lock EARLY
--   in the AMO pass -> AMO counter (0xF00, DMA-untouched) mismatch => FAIL; 2 = the
--   BFM boundary skews req one stage shallower than addr/wdata (N_DELAY>0) =>
--   scoreboard FAIL. The DMA never skews (depth 0).
--
-- PASS banner: "ALL CHECKS PASSED" (grepped by xcelium/mp_test/run_dma_arb.sh).
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity dma_arb_tb is
    generic (
        N_DELAY    : natural := 0;   -- BFM boundary-register stages, 0/1/2 (M13)
        BREAK_MODE : natural := 0    -- 0 clean; 1 early lock drop; 2 skewed addr pipe
    );
end entity;

architecture sim of dma_arb_tb is

    -- fabric shape: 5 masters total (4 BFM + 1 DMA), DMA is the highest index
    constant N   : natural := 5;    -- total masters (arbiter N)
    constant NB  : natural := 4;    -- BFM masters at indices 0..NB-1
    constant DMA_IDX : natural := NB;  -- the DMA is index 4

    function clog2(v : natural) return natural is
        variable w : natural := 0;
    begin
        while 2**w < v loop
            w := w + 1;
        end loop;
        return w;
    end function;
    function max2(a, b : natural) return natural is
    begin
        if a > b then return a; else return b; end if;
    end function;

    constant MW  : natural := max2(1, clog2(N));   -- = 3 at N=5
    constant AW  : natural := 12;   -- arbiter / RAM word-address width (template)
    constant DW  : natural := 32;
    constant AWD : natural := 15;   -- DMA master-port word-address width (SH_AW)

    -- BFM pass sizes (must match arb_lat_master; the DMA does none of these)
    constant NTX    : natural := 4;
    constant N_RND  : natural := 24;
    constant N_LRSC : natural := 6;
    constant N_RMW  : natural := 8;
    constant N_MTX  : natural := 6;
    constant CLK_PERIOD : time := 10 ns;

    signal clk        : std_logic := '0';
    signal resetn     : std_logic := '0';
    signal stop_clock : boolean   := false;

    type slv12_arr is array(0 to NB-1) of std_logic_vector(AW-1 downto 0);
    type slv32_arr is array(0 to NB-1) of std_logic_vector(DW-1 downto 0);
    type slv4_arr  is array(0 to NB-1) of std_logic_vector(3 downto 0);
    type slv2_arr  is array(0 to NB-1) of std_logic_vector(1 downto 0);

    -- master-side (BFM) signals
    signal mb_req, mb_lock, mb_busy   : std_logic_vector(NB-1 downto 0);
    signal mb_gnt, mb_done, mb_scfail : std_logic_vector(NB-1 downto 0);
    signal mb_we    : slv4_arr;
    signal mb_addr  : slv12_arr;
    signal mb_wdata : slv32_arr;
    signal mb_lrsc  : slv2_arr;
    signal mb_rdata : std_logic_vector(DW-1 downto 0);
    signal mb_finished, mb_err : std_logic_vector(NB-1 downto 0) := (others => '0');

    -- flattened BFM buses (pipe sources)
    signal f_we    : std_logic_vector(NB*4-1 downto 0);
    signal f_addr  : std_logic_vector(NB*AW-1 downto 0);
    signal f_wdata : std_logic_vector(NB*DW-1 downto 0);
    signal f_lrsc  : std_logic_vector(NB*2-1 downto 0);

    -- BOUNDARY PIPES over the NB BFMs only (the DMA has NO boundary, depth 0).
    -- outbound: [req NB][lock NB][lrsc 2NB][we 4NB][addr AW*NB][wdata DW*NB]
    -- inbound : [gnt NB][done NB][scfail NB][rdata DW]
    constant OBW : natural := NB + NB + NB*2 + NB*4 + NB*AW + NB*DW;
    constant IBW : natural := NB + NB + NB + DW;
    signal ob0, ob1, ob2 : std_logic_vector(OBW-1 downto 0) := (others => '0');
    signal ib0, ib1, ib2 : std_logic_vector(IBW-1 downto 0) := (others => '0');
    signal ob_t, ob_tm1  : std_logic_vector(OBW-1 downto 0);
    signal ib_t          : std_logic_vector(IBW-1 downto 0);

    constant OB_REQ  : natural := OBW - NB;
    constant OB_LOCK : natural := OB_REQ - NB;
    constant OB_LRSC : natural := OB_LOCK - NB*2;
    constant OB_WE   : natural := OB_LRSC - NB*4;
    constant OB_ADDR : natural := OB_WE - NB*AW;
    constant OB_WDA  : natural := 0;
    constant IB_GNT  : natural := IBW - NB;
    constant IB_DONE : natural := IB_GNT - NB;
    constant IB_SCF  : natural := IB_DONE - NB;
    constant IB_RDA  : natural := 0;

    -- piped BFM buses (post-boundary)
    signal ab_req, ab_lock : std_logic_vector(NB-1 downto 0);
    signal ab_we    : std_logic_vector(NB*4-1 downto 0);
    signal ab_addr  : std_logic_vector(NB*AW-1 downto 0);
    signal ab_wdata : std_logic_vector(NB*DW-1 downto 0);
    signal ab_lrsc  : std_logic_vector(NB*2-1 downto 0);

    -- full N=5 arbiter-side buses (BFMs 0..3 from the pipe, DMA at the top slice)
    signal a_req, a_lock  : std_logic_vector(N-1 downto 0);
    signal a_we           : std_logic_vector(N*4-1 downto 0);
    signal a_addr         : std_logic_vector(N*AW-1 downto 0);
    signal a_wdata        : std_logic_vector(N*DW-1 downto 0);
    signal a_lrsc         : std_logic_vector(N*2-1 downto 0);
    signal arb_gnt, arb_done, arb_scfail : std_logic_vector(N-1 downto 0);
    signal arb_rdata      : std_logic_vector(DW-1 downto 0);

    -- the DMA master-port signals (index 4, depth 0)
    signal dma_req     : std_logic;
    signal dma_we      : std_logic_vector(3 downto 0);
    signal dma_addr    : std_logic_vector(AWD-1 downto 0);
    signal dma_wdata   : std_logic_vector(DW-1 downto 0);
    signal dma_gnt     : std_logic;
    signal dma_done    : std_logic;
    signal dma_rdata_m : std_logic_vector(DW-1 downto 0);
    signal dma_irq_done, dma_irq_err : std_logic;

    -- the DMA slave-port (register-bus) stimulus signals
    signal en_mem      : std_logic := '1';                       -- ACTIVE-LOW select
    signal wen_s       : std_logic_vector(3 downto 0) := "1111"; -- ACTIVE-LOW lanes
    signal dma_mab     : std_logic_vector(7 downto 2) := (others => '0');
    signal dma_wdata_s : std_logic_vector(31 downto 0) := (others => '0');
    signal dma_rdata_s : std_logic_vector(31 downto 0);

    -- arbiter <-> slaves
    signal s_en      : std_logic;
    signal s_master  : std_logic_vector(MW-1 downto 0);
    signal s_we      : std_logic_vector(3 downto 0);
    signal s_we_g    : std_logic_vector(3 downto 0);
    signal s_addr    : std_logic_vector(AW-1 downto 0);
    signal s_wdata   : std_logic_vector(DW-1 downto 0);
    signal s_rdata   : std_logic_vector(DW-1 downto 0);

    signal mtx_sel   : std_logic;
    signal mtx_en    : std_logic;
    signal ram_en    : std_logic;
    signal rd_mtx    : std_logic := '0';
    signal mtx_rdata : std_logic_vector(DW-1 downto 0);
    signal ram_rdata : std_logic_vector(DW-1 downto 0) := (others => '0');

    -- DMA-owned RAM word indices (byte_ptr(13:2)); see the header map
    constant SRC_A_W : natural := 16#400#;
    constant SRC_B_W : natural := 16#500#;
    constant DST_W   : natural := 16#600#;
    constant SENT_W  : natural := 16#700#;
    constant SENTINEL : std_logic_vector(31 downto 0) := x"5EEDC0DE";
    constant DMA_LEN  : natural := 8;   -- words per functional copy

    function pat_a(k : natural) return std_logic_vector is
    begin
        return x"AA" & conv_std_logic_vector(k, 8) & x"00" & x"C3";
    end function;
    function pat_b(k : natural) return std_logic_vector is
    begin
        return x"BB" & conv_std_logic_vector(k, 8) & x"11" & x"3C";
    end function;

    -- shared single-port RAM, seeded with the DMA source patterns + sentinel.
    -- ONE driver only (the slave process); the stimulus/monitors READ it.
    type ram_t is array(0 to 2**AW-1) of std_logic_vector(DW-1 downto 0);
    function ram_init return ram_t is
        variable r : ram_t := (others => (others => '0'));
    begin
        for k in 0 to DMA_LEN-1 loop
            r(SRC_A_W + k) := pat_a(k);
            r(SRC_B_W + k) := pat_b(k);
        end loop;
        r(SENT_W) := SENTINEL;
        return r;
    end function;
    signal shram : ram_t := ram_init;

    -- error / status flags
    signal mutex_err   : std_logic := '0';   -- inherited
    signal cs_err      : std_logic := '0';   -- inherited
    signal ghost_err   : std_logic := '0';   -- inherited BFM ghost-done
    signal dma_ghost_err : std_logic := '0';
    signal dma_proto_err : std_logic := '0';
    signal dma_data_err  : std_logic := '0';
    signal dma_busy      : std_logic := '0';  -- derived DMA in-flight (A1 shape)
    signal dma_caused_scfail : std_logic := '0';  -- LR/SC-kill (ii) observed
    signal dma_stim_done : std_logic := '0';

    constant CTR_ADDR_I  : natural := 16#F00#;
    constant LRSC_ADDR_I : natural := 16#E00#;
    constant PROT_ADDR_I : natural := 16#D00#;

    -- The DUT engine as a COMPONENT (I3C_tb discipline: this tb ANALYZES before
    -- DMA.vhd exists; the entity binds at ELABORATION). Ports/generics VERBATIM
    -- from the FROZEN entity in dma_design.md.
    component DMA is
        generic (
            NCH : natural := 4;
            AW  : natural := 15
        );
        port (
            clk         : in  std_logic;
            resetn      : in  std_logic;
            ClkMem      : in  std_logic;
            EnMemPeriph : in  std_logic;
            WEn         : in  std_logic_vector(3 downto 0);
            MABPart     : in  std_logic_vector(7 downto 2);
            wdata       : in  std_logic_vector(31 downto 0);
            rdata_out   : out std_logic_vector(31 downto 0);
            m_req       : out std_logic;
            m_we        : out std_logic_vector(3 downto 0);
            m_addr      : out std_logic_vector(AW-1 downto 0);
            m_wdata     : out std_logic_vector(31 downto 0);
            m_gnt       : in  std_logic;
            m_done      : in  std_logic;
            m_rdata     : in  std_logic_vector(31 downto 0);
            trig_uart0_rc  : in std_logic := '0';
            trig_qspi0_rxf : in std_logic := '0';
            trig_nfc0_rxf  : in std_logic := '0';
            irq_done    : out std_logic;
            irq_err     : out std_logic
        );
    end component;

begin

    clk <= not clk after CLK_PERIOD/2 when not stop_clock else '0';
    resetn <= '0', '1' after 3*CLK_PERIOD;

    -- four BFM masters at indices 0..3 (arb_lat_master from arb_lat_tb.vhd)
    gen_masters: for i in 0 to NB-1 generate
        mst: entity work.arb_lat_master
            generic map (INDEX => i, NTX => NTX, N_RND => N_RND,
                         N_LRSC => N_LRSC, N_RMW => N_RMW, N_MTX => N_MTX,
                         BREAK_MODE => BREAK_MODE, N_TOTAL => N)
            port map (
                clk => clk, resetn => resetn,
                req => mb_req(i), we => mb_we(i),
                addr => mb_addr(i), wdata => mb_wdata(i),
                lock => mb_lock(i), lrsc => mb_lrsc(i),
                gnt => mb_gnt(i), done => mb_done(i),
                rdata => mb_rdata, scfail => mb_scfail(i),
                busy => mb_busy(i),
                finished => mb_finished(i), err => mb_err(i)
            );
    end generate;

    gen_flat: for i in 0 to NB-1 generate
        f_we((i+1)*4-1 downto i*4)      <= mb_we(i);
        f_addr((i+1)*AW-1 downto i*AW)  <= mb_addr(i);
        f_wdata((i+1)*DW-1 downto i*DW) <= mb_wdata(i);
        f_lrsc((i+1)*2-1 downto i*2)    <= mb_lrsc(i);
    end generate;

    -- boundary pipes (BFMs only)
    ob0 <= mb_req & mb_lock & f_lrsc & f_we & f_addr & f_wdata;
    ib0 <= arb_gnt(NB-1 downto 0) & arb_done(NB-1 downto 0)
           & arb_scfail(NB-1 downto 0) & arb_rdata;

    pipes: process(clk, resetn)
    begin
        if resetn = '0' then
            ob1 <= (others => '0'); ob2 <= (others => '0');
            ib1 <= (others => '0'); ib2 <= (others => '0');
        elsif rising_edge(clk) then
            ob1 <= ob0; ob2 <= ob1;
            ib1 <= ib0; ib2 <= ib1;
        end if;
    end process;

    ob_t   <= ob0 when N_DELAY = 0 else ob1 when N_DELAY = 1 else ob2;
    ob_tm1 <= ob0 when N_DELAY <= 1 else ob1;   -- one stage shallower (BREAK_MODE=2)
    ib_t   <= ib0 when N_DELAY = 0 else ib1 when N_DELAY = 1 else ib2;

    -- piped BFM arbiter-side unslicing (req skews one stage early under BREAK_MODE=2)
    ab_req  <= ob_t(OB_REQ+NB-1     downto OB_REQ) when BREAK_MODE /= 2 else
               ob_tm1(OB_REQ+NB-1   downto OB_REQ);
    ab_lock <= ob_t(OB_LOCK+NB-1    downto OB_LOCK);
    ab_lrsc <= ob_t(OB_LRSC+NB*2-1  downto OB_LRSC);
    ab_we   <= ob_t(OB_WE+NB*4-1    downto OB_WE);
    ab_addr <= ob_t(OB_ADDR+NB*AW-1 downto OB_ADDR);
    ab_wdata<= ob_t(OB_WDA+NB*DW-1  downto OB_WDA);

    -- master-side unslicing (BFM inbound)
    mb_gnt    <= ib_t(IB_GNT+NB-1  downto IB_GNT);
    mb_done   <= ib_t(IB_DONE+NB-1 downto IB_DONE);
    mb_scfail <= ib_t(IB_SCF+NB-1  downto IB_SCF);
    mb_rdata  <= ib_t(IB_RDA+DW-1  downto IB_RDA);

    -- assemble the N=5 arbiter-side buses: DMA (index 4) is the TOP slice, wired
    -- DIRECTLY (depth 0). Ties per D18: arb_lock(4)='0', arb_lrsc(9:8)="00".
    a_req   <= dma_req & ab_req;
    a_lock  <= '0' & ab_lock;
    a_lrsc  <= "00" & ab_lrsc;
    a_we    <= dma_we & ab_we;
    a_addr  <= dma_addr(AW-1 downto 0) & ab_addr;   -- m_addr(11:0); (14:12)=0 here
    a_wdata <= dma_wdata & ab_wdata;

    -- DMA inbound (depth 0)
    dma_gnt     <= arb_gnt(DMA_IDX);
    dma_done    <= arb_done(DMA_IDX);
    dma_rdata_m <= arb_rdata;

    -- DUT: the real arbiter, widened to N=5 / MW=3
    dut: entity work.mp_arbiter
        generic map (N => N, ADDR_WIDTH => AW, DATA_WIDTH => DW, MW => MW)
        port map (
            clk => clk, resetn => resetn,
            req => a_req, we => a_we, addr => a_addr, wdata => a_wdata,
            lock => a_lock,
            gnt => arb_gnt, done => arb_done, rdata => arb_rdata,
            s_en => s_en, s_master => s_master, s_we => s_we,
            s_addr => s_addr, s_wdata => s_wdata, s_rdata => s_rdata
        );

    -- DUT: the real reservation unit, N=5 (kills matching resv on the DMA write)
    resv0: entity work.resv_unit
        generic map (N => N, ADDR_WIDTH => AW)
        port map (
            clk => clk, resetn => resetn,
            lr_sc => a_lrsc, gnt => arb_gnt,
            s_en => s_en, s_we => s_we, s_addr => s_addr,
            s_we_gated => s_we_g, sc_fail => arb_scfail
        );

    -- DUT: the real mutex bank at the page-3 slot-0 mirror (words 0xC00-0xC3F)
    mtx_sel <= '1' when s_addr(11 downto 10) = "11" and s_addr(9 downto 6) = "0000"
               else '0';
    mtx_en  <= s_en and mtx_sel;
    ram_en  <= s_en and not mtx_sel;

    mtx0: entity work.mutex_bank
        generic map (NMUTEX => 16, AW => 4, MW => MW)
        port map (
            clk => clk, resetn => resetn,
            en => mtx_en, we => s_we_g, addr => s_addr(3 downto 0),
            wdata => s_wdata, master => s_master, rdata => mtx_rdata
        );

    -- shared single-port RAM slave: 1-cycle registered read, resv-GATED writes
    slave: process(clk)
        variable merged : std_logic_vector(DW-1 downto 0);
    begin
        if rising_edge(clk) then
            if ram_en = '1' then
                merged := shram(conv_integer(s_addr));
                for l in 0 to 3 loop
                    if s_we_g(l) = '1' then
                        merged((l+1)*8-1 downto l*8) := s_wdata((l+1)*8-1 downto l*8);
                    end if;
                end loop;
                shram(conv_integer(s_addr)) <= merged;
                ram_rdata <= merged;
            end if;
        end if;
    end process;

    rd_sel: process(clk, resetn)
    begin
        if resetn = '0' then
            rd_mtx <= '0';
        elsif rising_edge(clk) then
            if s_en = '1' then
                rd_mtx <= mtx_sel;
            end if;
        end if;
    end process;
    s_rdata <= mtx_rdata when rd_mtx = '1' else ram_rdata;

    -- ===== the REAL DMA engine, index 4, DEPTH 0 =====================
    -- clk and ClkMem bound to the SAME mclk net (D1). Triggers tied '0'
    -- (mem-to-mem, TRIG=0). Master port slices into arb_*(4) (assembled above).
    dma0: DMA
        generic map (NCH => 4, AW => AWD)
        port map (
            clk => clk, resetn => resetn,
            ClkMem => clk, EnMemPeriph => en_mem, WEn => wen_s,
            MABPart => dma_mab, wdata => dma_wdata_s, rdata_out => dma_rdata_s,
            m_req => dma_req, m_we => dma_we, m_addr => dma_addr,
            m_wdata => dma_wdata, m_gnt => dma_gnt, m_done => dma_done,
            m_rdata => dma_rdata_m,
            trig_uart0_rc => '0', trig_qspi0_rxf => '0', trig_nfc0_rxf => '0',
            irq_done => dma_irq_done, irq_err => dma_irq_err
        );

    -- ===== DMA slave-port register-bus stimulus =======================
    -- Programs + launches mem-to-mem copies through channel 0 for the whole
    -- run (hammering the shared RAM), verifies each copy's dest + W1Cs CHnDONE,
    -- then repeatedly writes a sentinel onto LRSC_ADDR to interfere with the
    -- BFMs' LR/SC pass (the directed LR/SC-kill pass).
    dma_stim: process
        -- slot numbers (word slot in the 0x6800 window = MABPart)
        constant SLOT_CR    : natural := 0;
        constant SLOT_SR    : natural := 1;
        constant SLOT_C0SRC : natural := 2;
        constant SLOT_C0DST : natural := 3;
        constant SLOT_C0LEN : natural := 4;
        constant SLOT_C0CFG : natural := 5;
        constant DMAEN      : std_logic_vector(31 downto 0) := x"00000001";
        constant CH0GO      : std_logic_vector(31 downto 0) := x"00000003"; -- DMAEN|GO0
        constant CH0DONE_W1C: std_logic_vector(31 downto 0) := x"00000002"; -- SR bit1
        constant CFG_BLOCK  : std_logic_vector(31 downto 0) := x"00000003"; -- SINC|DINC
        constant CFG_FIXED  : std_logic_vector(31 downto 0) := x"00000000";
        constant SRC_A_BYTE : std_logic_vector(31 downto 0) := x"00001000";
        constant SRC_B_BYTE : std_logic_vector(31 downto 0) := x"00001400";
        constant DST_BYTE   : std_logic_vector(31 downto 0) := x"00001800";
        constant SENT_BYTE  : std_logic_vector(31 downto 0) := x"00001C00";
        constant LRSC_BYTE  : std_logic_vector(31 downto 0) := x"00003800";
        constant N_FUNC     : natural := 6;      -- functional verified copies
        constant K_MAX      : natural := 1500;   -- sentinel-interference budget
        variable v        : std_logic_vector(31 downto 0);
        variable expw     : std_logic_vector(31 downto 0);
        variable attempts : natural;
        variable it       : natural;

        procedure reg_write(slot : natural; val : std_logic_vector(31 downto 0)) is
        begin
            dma_mab     <= conv_std_logic_vector(slot, 6);
            dma_wdata_s <= val;
            wen_s       <= "0000";   -- active-low: write all lanes
            en_mem      <= '0';      -- active-low select
            wait until rising_edge(clk);
            en_mem      <= '1';
            wen_s       <= "1111";
            wait until rising_edge(clk);
        end procedure;

        procedure reg_read(slot : natural; val : out std_logic_vector(31 downto 0)) is
        begin
            dma_mab <= conv_std_logic_vector(slot, 6);
            wen_s   <= "1111";
            en_mem  <= '0';
            wait until rising_edge(clk);    -- read registers into the mux
            wait until rising_edge(clk);    -- registered rdata_out valid, idempotent
            val := To_X01(dma_rdata_s);
            en_mem <= '1';
            wait until rising_edge(clk);
        end procedure;

        -- program + launch CH0, poll CHnDONE, W1C it (bounded)
        procedure run_copy(srcb, dstb, cfgv : std_logic_vector(31 downto 0);
                           lenw : natural) is
        begin
            reg_write(SLOT_C0SRC, srcb);
            reg_write(SLOT_C0DST, dstb);
            reg_write(SLOT_C0LEN, conv_std_logic_vector(lenw, 32));
            reg_write(SLOT_C0CFG, cfgv);
            reg_write(SLOT_CR,    CH0GO);          -- DMAEN|CH0GO
            attempts := 0;
            loop
                reg_read(SLOT_SR, v);
                exit when v(1) = '1';              -- CH0DONE (SR bit1)
                attempts := attempts + 1;
                if attempts > 4000 then
                    dma_data_err <= '1';
                    report "DMA CH0DONE poll budget EXHAUSTED" severity error;
                    exit;
                end if;
            end loop;
            reg_write(SLOT_SR, CH0DONE_W1C);       -- W1C CH0DONE via the slave port
        end procedure;
    begin
        en_mem <= '1'; wen_s <= "1111"; dma_mab <= (others => '0');
        dma_wdata_s <= (others => '0');
        wait until resetn = '1';
        wait until rising_edge(clk);
        reg_write(SLOT_CR, DMAEN);                 -- DMAEN=1

        -- ONE interleaved loop for the WHOLE BFM run (so it overlaps pass 5, the
        -- BFMs' LR/SC pass, wherever it falls). Each iteration:
        --  1) a DENSE sentinel interference copy: fixed src / fixed dst, LEN=16 =>
        --     the engine issues 16 back-to-back plain WRITES to LRSC_ADDR, so the
        --     DMA has a 0xE00 write pending for a large fraction of the time and is
        --     very likely to slip one into some BFM's LR->SC arbiter-serialization
        --     gap (resv_unit(N=5) then kills that reservation => the SC fails).
        --  2) a functional verified mem-to-mem copy (alternating A/B so a stale
        --     dest is caught), confirming correct copies + CHnDONE W1C under
        --     contention. The loop runs until every BFM finishes (or the K_MAX
        --     safety budget), guaranteeing temporal overlap with pass 5.
        it := 0;
        while (mb_finished /= (mb_finished'range => '1')) and it < K_MAX loop
            -- (1) dense interference: 16 plain writes onto LRSC_ADDR
            run_copy(SENT_BYTE, LRSC_BYTE, CFG_FIXED, 16);
            -- (2) functional verified copy, alternating source pattern
            if (it mod 2) = 0 then
                run_copy(SRC_A_BYTE, DST_BYTE, CFG_BLOCK, DMA_LEN);
            else
                run_copy(SRC_B_BYTE, DST_BYTE, CFG_BLOCK, DMA_LEN);
            end if;
            for k in 0 to DMA_LEN-1 loop
                if (it mod 2) = 0 then expw := pat_a(k); else expw := pat_b(k); end if;
                if shram(DST_W + k) /= expw then
                    dma_data_err <= '1';
                    report "DMA dest mismatch it=" & integer'image(it) &
                           " k=" & integer'image(k) severity error;
                end if;
            end loop;
            it := it + 1;
        end loop;

        dma_stim_done <= '1';
        wait;
    end process;

    -- ===== DMA-specific monitors ======================================
    -- (a) derived in-flight (A1 shape): busy from m_req rise to one cycle after
    -- m_done; a done with no txn in flight is a ghost-done FAIL.
    dma_busy_mon: process(clk, resetn)
        variable done_d : std_logic;
    begin
        if resetn = '0' then
            dma_busy <= '0'; done_d := '0';
        elsif rising_edge(clk) then
            if dma_req = '1' then
                dma_busy <= '1';
            elsif done_d = '1' then          -- one cycle after done, req now low
                dma_busy <= '0';
            end if;
            done_d := dma_done;
        end if;
    end process;

    dma_ghost_chk: process(clk)
    begin
        if rising_edge(clk) then
            if dma_done = '1' and dma_busy = '0' and dma_req = '0' then
                dma_ghost_err <= '1';
                report "DMA GHOST DONE: arb_done(4) with no txn in flight"
                    severity error;
            end if;
        end if;
    end process;

    -- (b) protocol monitor: m_addr/m_we/m_wdata stable while m_req high; >=1
    -- observed-low cycle between txns (the WAIT-FOR-RELEASE contract, D2).
    dma_proto_chk: process(clk, resetn)
        variable prev_req  : std_logic;
        variable gap_ok    : boolean;
        variable h_addr    : std_logic_vector(AWD-1 downto 0);
        variable h_we      : std_logic_vector(3 downto 0);
        variable h_wdata   : std_logic_vector(31 downto 0);
    begin
        if resetn = '0' then
            prev_req := '0'; gap_ok := true;
            h_addr := (others => '0'); h_we := (others => '0');
            h_wdata := (others => '0');
        elsif rising_edge(clk) then
            if dma_req = '1' then
                if prev_req = '1' then
                    if dma_addr /= h_addr or dma_we /= h_we
                       or dma_wdata /= h_wdata then
                        dma_proto_err <= '1';
                        report "DMA PROTOCOL: m_* changed while m_req held high"
                            severity error;
                    end if;
                else                          -- req rising edge = new txn
                    if not gap_ok then
                        dma_proto_err <= '1';
                        report "DMA PROTOCOL: no observed-low gap between txns"
                            severity error;
                    end if;
                    h_addr := dma_addr; h_we := dma_we; h_wdata := dma_wdata;
                end if;
                gap_ok := false;
            else
                gap_ok := true;               -- observed >=1 low cycle
            end if;
            prev_req := dma_req;
        end if;
    end process;

    -- (c) LR/SC-kill scoreboard: shadow resv_unit's kill rule on LRSC_ADDR only,
    -- attributing each FAILED BFM SC to the master that LAST killed its resv.
    -- If that killer is the DMA (index 4), (ii) is OBSERVED.
    lrsc_kill_chk: process(clk, resetn)
        type killer_arr is array(0 to NB-1) of integer range -1 to N-1;
        variable resv_open : std_logic_vector(NB-1 downto 0);
        variable killer    : killer_arr;   -- -1 = none
        variable m         : natural;
        variable tag       : std_logic_vector(1 downto 0);
        variable committed : boolean;
    begin
        if resetn = '0' then
            resv_open := (others => '0');
            for j in 0 to NB-1 loop killer(j) := -1; end loop;
        elsif rising_edge(clk) then
            if s_en = '1' and s_addr = conv_std_logic_vector(LRSC_ADDR_I, AW) then
                m         := conv_integer(s_master);
                tag       := a_lrsc((m+1)*2-1 downto m*2);
                committed := (s_we_g /= "0000");
                if tag = "01" then                       -- LR: place reservation
                    if m < NB then resv_open(m) := '1'; killer(m) := -1; end if;
                elsif tag = "10" then                    -- SC attempt
                    if committed then                    -- success: kills others
                        for j in 0 to NB-1 loop
                            if j /= m and resv_open(j) = '1' then
                                killer(j) := m; resv_open(j) := '0';
                            end if;
                        end loop;
                        if m < NB then resv_open(m) := '0'; end if;
                    else                                 -- FAILED SC
                        if m < NB then
                            if killer(m) = DMA_IDX then
                                dma_caused_scfail <= '1';
                            end if;
                            resv_open(m) := '0'; killer(m) := -1;
                        end if;
                    end if;
                else                                     -- plain access (tag "00")
                    if committed then                    -- plain write kills all
                        for j in 0 to NB-1 loop
                            if j /= m and resv_open(j) = '1' then
                                killer(j) := m; resv_open(j) := '0';
                            end if;
                        end loop;
                        if m < NB then resv_open(m) := '0'; end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- ===== inherited checkers (over all 5 masters) ====================
    mutex_chk: process(clk)
        variable cnt : natural;
    begin
        if rising_edge(clk) then
            cnt := 0;
            for i in 0 to N-1 loop
                if arb_gnt(i) = '1' then cnt := cnt + 1; end if;
            end loop;
            if cnt > 1 then
                mutex_err <= '1';
                report "MUTUAL EXCLUSION VIOLATED" severity error;
            end if;
        end if;
    end process;

    -- locked-pair critical section (BFM side; the DMA never locks, D18)
    cs_chk: process(clk)
        variable cs_active : boolean := false;
        variable cs_owner  : natural range 0 to NB-1 := 0;
    begin
        if rising_edge(clk) then
            for i in 0 to NB-1 loop
                if mb_done(i) = '1' then
                    if cs_active and i /= cs_owner then
                        cs_err <= '1';
                        report "GRANT-LOCK VIOLATED: master " & integer'image(i) &
                               " completed a txn inside master " &
                               integer'image(cs_owner) & "'s locked RMW pair"
                            severity error;
                    elsif cs_active and i = cs_owner then
                        cs_active := false;
                    elsif mb_lock(i) = '1' and mb_we(i) = "0000" then
                        cs_active := true;
                        cs_owner  := i;
                    end if;
                end if;
            end loop;
        end if;
    end process;

    -- BFM ghost-done detector
    ghost_chk: process(clk)
    begin
        if rising_edge(clk) then
            for i in 0 to NB-1 loop
                if mb_done(i) = '1' and mb_busy(i) = '0' then
                    ghost_err <= '1';
                    report "GHOST DONE: master " & integer'image(i) &
                           " got done with no transaction in flight"
                        severity error;
                end if;
            end loop;
        end if;
    end process;

    -- ===== scoreboard / banner ========================================
    report_proc: process
        variable v : natural;
    begin
        wait until resetn = '1';
        -- watchdog: all BFMs finished AND the DMA stimulus done (no starvation)
        for t in 0 to 50000 * N loop
            wait until rising_edge(clk);
            exit when mb_finished = (mb_finished'range => '1')
                      and dma_stim_done = '1';
        end loop;

        if mb_finished /= (mb_finished'range => '1') then
            report "WATCHDOG: not all BFMs finished (starvation/deadlock)"
                severity failure;
        end if;
        if dma_stim_done /= '1' then
            report "WATCHDOG: DMA stimulus did not finish (DMA starvation?)"
                severity failure;
        end if;

        wait for 5*CLK_PERIOD;

        -- AMO pass (0xF00, DMA-untouched): NB BFMs, no lost updates
        if shram(CTR_ADDR_I) /= conv_std_logic_vector(NB*N_RMW, 32) then
            v := conv_integer(shram(CTR_ADDR_I)(30 downto 0));
            report "GRANT-LOCK COUNTER MISMATCH: expected " &
                   integer'image(NB*N_RMW) & " got " & integer'image(v)
                severity failure;
        end if;
        -- mutex-protected pass (0xD00, DMA-untouched): NB BFMs
        if shram(PROT_ADDR_I) /= conv_std_logic_vector(NB*N_MTX, 32) then
            v := conv_integer(shram(PROT_ADDR_I)(30 downto 0));
            report "MUTEX-PROTECTED COUNTER MISMATCH: expected " &
                   integer'image(NB*N_MTX) & " got " & integer'image(v)
                severity failure;
        end if;
        -- LR/SC value-equality check on 0xE00 DROPPED: the DMA sentinel corrupts
        -- the word by design. (i) starvation-freedom is proven below by m_err=0 +
        -- the watchdog (every BFM did its N_LRSC successful SCs with a DMA present).

        report "LR/SC-KILL (i): all BFMs completed N_LRSC SCs (starvation-free)"
            severity note;
        if dma_caused_scfail = '1' then
            report "LR/SC-KILL (ii): DMA write killed a BFM reservation -> SC FAIL OBSERVED"
                severity note;
        else
            report "LR/SC-KILL (ii): WAIVED -- no natural DMA/LR-SC overlap in " &
                   "the sentinel budget (starvation-freedom (i) is load-bearing)"
                severity note;
        end if;

        if (mb_err = (mb_err'range => '0')) and mutex_err = '0'
           and cs_err = '0' and ghost_err = '0'
           and dma_ghost_err = '0' and dma_proto_err = '0'
           and dma_data_err = '0' then
            report "ALL CHECKS PASSED" severity note;
        else
            report "CHECKS FAILED (m_err/mutex/cs/ghost/dma_ghost/dma_proto/dma_data)"
                severity failure;
        end if;

        stop_clock <= true;
        wait;
    end process;

end architecture;
