library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ===========================================================================
-- RTC: Real-Time Clock -- 32.768 kHz always-on wall clock + one-shot alarm +
-- recurring periodic tick, one combined IRQ (vector 114). Zero pins.
-- FROZEN design: ~/vesta_docs/digperiphs/rtc_design.md (decisions Dn, orchestrator
-- adjudications A1-A4 -- all BINDING). Peripheral #4 of the digital-peripherals
-- program; the FIRST library block designed under the post-X-collapse bus rules.
-- -V200X only: NO VHDL-2008 (no to_hstring, no process(all), no unary reduce, no
-- reading of out ports). Every process infers exactly ONE edge of ONE clock; every
-- synchronizer is single-edge (Genus VHDL-601 discipline).
--
-- D4 -- NO falling_edge OF ANYTHING (and specifically NO falling_edge(EnMemPeriph)).
-- EnMemPeriph is consumed ONLY as an active-low LEVEL qualifier sampled on rising
-- ClkMem (address decode + write-enable + read-mux gate). It is never a clock and
-- never an edge. The RTC has NO EnMemPeriph clock in its SDC (gate note) and needs
-- neither a combinational-read bridge nor a CAPTURE_CLOCK registered-strobe shim --
-- it registers reads on rising ClkMem over data already synchronized into the bus
-- domain (D4/D7/D10). This supersedes rtc_spec.md's pre-fix falling_edge pre-latch
-- prose (orchestrator adjudication A1: the D4 bus contract WINS).
--
-- The RTC instantiates NO clock gates (no ClkGate/ClkDivPower2): the LFXT engines
-- clock on rising_edge(lfxt_in) DIRECTLY, gated only by synchronized enable LEVELS
-- inside the D-input logic -- never by gating a clock, never a raw/cross-domain
-- signal into any clock-gate enable.
--
-- ------------------------------------------------------------------------------
-- DOMAIN MAP (three clocks, all asynchronous groups; no generated clocks):
--   * lfxt_in -- UNGATED 32.768 kHz wall-clock crystal (D1). The 47-bit
--     {sec_cnt,sub_cnt} counter, atomic set-time load, the snap_lfxt/cap_tgl
--     read double-buffer, the alarm compare, the periodic down-counter, the enable
--     synchronizers, the write-commit apply + wr_ack, and the reset synchronizer.
--     Always on: firmware CANNOT stop it (SYS_CLK_CR is irrelevant here, D1) and
--     PWRCTRL cannot gate it. Reset via the rtc_lfxt_rstn 2-FF reset sync (D14).
--   * clk -- free-running fast reference. WIRED TO MCLK at integration (A2; not
--     smclk -- mclk is free-running and cannot be firmware-stopped). Hosts every
--     LFXT->bus synchronizer, the sticky ALMF/TICKF flags, the SR.SYNC busy level,
--     and the IRQ combiner. Must run autonomously while the bus is idle so alarm/
--     tick flags + irq_rtc set with no access in flight (D2/G7). Reset via resetn.
--   * ClkMem -- GATED bus clock (edges only during an access). Hosts the register
--     file: CR, the D8 staging regs + commit_mask + wr_req_tgl, the W1C clear
--     toggles, and the registered read mux. Reset via resetn. (Writes happen only
--     during accesses, so a gated clock suffices -- the TIMER precedent.)
--   At integration clk and ClkMem are the SAME mclk net (A2) so a clk-domain level
--   read by the ClkMem read mux is electrically same-domain; the block is kept
--   standalone-honest anyway -- every clk<->ClkMem hand-off below is a toggle or a
--   held/quasi-static level, never an async clear crossing a domain (the ROOT-2
--   UART defect class): W1C clears happen in the SAME clk process that owns the
--   flag, and the bus requests it only via a toggle.
--
-- CDC CROSSING INVENTORY (the ONLY crossing paths; all toggle / held-level /
-- quasi-static -- no async FIFO):
--   1. READ snapshot  LFXT->clk (D7): every lfxt edge, after the increment, copy
--      the whole {sec_cnt,sub_cnt} into snap_lfxt and flip cap_tgl (SAME edge).
--      clk 2-FFs cap_tgl, edge-detects it, and samples snap_lfxt into snap_sync.
--      Data settled ~1 lfxt period before its flag crosses (data-before-flag).
--   2. snap_sync clk->ClkMem: read by the ClkMem read mux. Coincident nets at
--      integration (A2); snap_sync is quasi-static (updates ~once per lfxt period).
--   3. WRITE commit  ClkMem->LFXT (D8): stage_* + commit_mask co-written with a flip
--      of wr_req_tgl. lfxt 2-FFs wr_req_tgl, edge-detects, and applies the staging
--      per the (stable, co-sampled) commit_mask -- set-time load takes PRIORITY over
--      the increment that edge (TIMER latch_timer_value idiom). Then flips wr_ack_tgl.
--      stage_*/commit_mask are quasi-static (false-path by construction).
--   4. SR.SYNC (BUSY) (D8, literal form -- orchestrator adjudication): sync_busy =
--      (wr_req_tgl /= wr_ack synced-into-clk). The RAW request toggle (ClkMem domain;
--      the same physical mclk as clk at integration, A2) is compared against the
--      2-FF-synced ack, so SYNC asserts in the SAME cycle as the committing write --
--      no blind window for an SR poll issued immediately after the write -- and
--      deasserts only after the LFXT ack has crossed. Held level read by the ClkMem
--      read mux. Every crossing stays a toggle or a held level.
--   5. EVENT  LFXT->clk (D10): the alarm-match rising edge and the tick underflow are
--      each a single-lfxt-tick pulse that FLIPS a toggle (alm_tgl / tick_tgl). clk
--      2-FFs + edge-detects each toggle to SET the sticky ALMF/TICKF -- exactly one
--      clk edge per event regardless of how long the condition holds.
--   6. W1C  ClkMem->clk (D10): a lane-0 write of 1 to ALMF/TICKF flips clr_alm_tgl /
--      clr_tick_tgl (ClkMem). clk 2-FFs + edge-detects each and CLEARS the flag in
--      the SAME process that owns it -- no clear-pulse crosses back to LFXT. SET WINS
--      over a coincident CLEAR (a set arriving the same clk cycle as a W1C survives).
--   7. ENABLES  ClkMem->LFXT (D9): RTCEN/ALMEN/TICKEN cross as held levels, 2-FF
--      synchronized in the LFXT domain (flops clocked by lfxt_in) to gate the
--      counter / compare / tick engines. ALMIE/TICKIE stay mclk-domain (never cross).
--   8. RESET (D14): rtc_lfxt_rstn = 2-FF reset synchronizer, ASYNC assert on
--      resetn='0', SYNC de-assert clocked by lfxt_in. Every LFXT process resets on
--      rtc_lfxt_rstn; the clk/ClkMem processes reset on resetn directly.
--   9. IRQ (D13): irq_rtc = (ALMF and ALMIE) or (TICKF and TICKIE) -- combinational,
--      mclk domain, never latched. IE bits are quasi-static CR bits (no crossing).
--
-- Register map (D5; base 0x6500, slot n @ 0x6500 + 4n, decoded off MABPart(7:2)):
--   0 RTC0CR   : [0]RTCEN [1]ALMEN [2]TICKEN [3]ALMIE [4]TICKIE, 31:5 rsvd read 0.
--   1 RTC0SEC  : rd = coherent snapshot snap_sync[46:15]; wr = stage SEC + commit
--                {SEC,SUB} atomically (SR.SYNC busy) -- lane-0 qualified.
--   2 RTC0SUB  : rd = snap_sync[14:0] zero-extended (SAME instant as SEC); wr = stage
--                only (committed by the following SEC write) -- lane-0 qualified.
--   3 RTC0ALM  : rd = mclk staging readback (no CDC); wr = stage + commit ALM.
--   4 RTC0PER  : [15:0] reload; rd = staging readback; wr = stage + commit PER (A4:
--                16-bit, ~2 s max interval). Tick every per_live+1 lfxt ticks (D12).
--   5 RTC0SR   : [0]SYNC ro, [1]ALMF W1C, [2]TICKF W1C, 31:3 rsvd read 0.
--   6 RTC0TRIM : reserved (D16) -- reads 0, writes ignored. Slots >=7 read 0.
-- ===========================================================================

entity RTC is
    port (
        clk         : in  std_logic;                     -- free-running fast ref: MCLK at
                                                         -- integration (orchestrator adj. A2)
                                                         -- (LFXT->bus CDC synchronizers,
                                                         -- sticky W1C flags, IRQ combiner)
        resetn      : in  std_logic;                     -- chip reset, active-low (async)
        lfxt_in     : in  std_logic;                     -- UNGATED 32.768 kHz wall clock (D1)
        irq_rtc     : out std_logic;                     -- combined alarm/tick IRQ (vector 114)
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW select/qualifier (D4:
                                                         -- NEVER a clock)
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0)
    );
end RTC;

architecture behavioral of RTC is

    -- ---- word-slot map (frozen, D5) --------------------------------------
    constant SLOT_CR   : natural := 0;
    constant SLOT_SEC  : natural := 1;
    constant SLOT_SUB  : natural := 2;
    constant SLOT_ALM  : natural := 3;
    constant SLOT_PER  : natural := 4;
    constant SLOT_SR   : natural := 5;
    constant SLOT_TRIM : natural := 6;

    -- ---- B1 register-file storage (ClkMem domain) ------------------------
    signal rtc_cr      : std_logic_vector(4 downto 0);   -- RTCEN/ALMEN/TICKEN/ALMIE/TICKIE
    signal stage_sec   : std_logic_vector(31 downto 0);  -- D8 staging: seconds
    signal stage_sub   : std_logic_vector(14 downto 0);  -- D8 staging: subseconds
    signal stage_alm   : std_logic_vector(31 downto 0);  -- D8 staging + ALM readback
    signal stage_per   : std_logic_vector(15 downto 0);  -- D8 staging + PER readback (A4)
    signal commit_mask : std_logic_vector(2 downto 0);   -- [0]time{sec,sub} [1]alm [2]per
    signal wr_req_tgl  : std_logic;                      -- write-commit request toggle (D8)
    signal clr_alm_tgl : std_logic;                      -- W1C ALMF request toggle (D10)
    signal clr_tick_tgl: std_logic;                      -- W1C TICKF request toggle (D10)
    signal rtc_slot    : natural range 0 to 63;          -- decoded word slot

    -- ---- CR field taps (combinational; quasi-static) ---------------------
    signal rtcen_cr, almen_cr, ticken_cr : std_logic;
    signal almie, tickie                 : std_logic;

    -- ---- B2 clk (mclk ref) domain: synchronizers + sticky flags ----------
    signal cap_s1, cap_s2, cap_prev      : std_logic;    -- D7 cap_tgl sync + edge
    signal snap_sync   : std_logic_vector(46 downto 0);  -- D7 bus-domain snapshot
    signal wrack_c1, wrack_c2            : std_logic;     -- D8 wr_ack into clk
    signal sync_busy   : std_logic;                      -- SR.SYNC (held level)
    signal almt_c1, almt_c2, almt_prev   : std_logic;    -- D10 alm_tgl sync + edge
    signal tickt_c1, tickt_c2, tickt_prev: std_logic;    -- D10 tick_tgl sync + edge
    signal clra_c1, clra_c2, clra_prev   : std_logic;    -- D10 W1C ALMF sync + edge
    signal clrt_c1, clrt_c2, clrt_prev   : std_logic;    -- D10 W1C TICKF sync + edge
    signal almf_flag, tickf_flag         : std_logic;    -- mclk-domain sticky flags

    -- ---- B6 reset sync + B2->LFXT enable syncs (lfxt domain) -------------
    signal rtc_rst_meta, rtc_lfxt_rstn   : std_logic;    -- D14 reset synchronizer
    signal rtcen_s1, rtcen_sync          : std_logic;    -- D9 RTCEN into lfxt
    signal almen_s1, almen_sync          : std_logic;    -- D9 ALMEN into lfxt
    signal ticken_s1, ticken_sync        : std_logic;    -- D9 TICKEN into lfxt

    -- ---- B3 wall clock (lfxt domain) -------------------------------------
    signal sec_cnt     : std_logic_vector(31 downto 0);  -- D6 seconds (carry of sub_cnt)
    signal sub_cnt     : std_logic_vector(14 downto 0);  -- D6 subsecond prescaler 0..32767
    signal snap_lfxt   : std_logic_vector(46 downto 0);  -- D7 double-buffer hold reg
    signal cap_tgl     : std_logic;                      -- D7 snapshot toggle

    -- ---- write-commit apply (lfxt domain) --------------------------------
    signal wrreq_s1, wrreq_s2, wrreq_prev: std_logic;    -- D8 wr_req into lfxt
    signal wr_apply    : std_logic;                      -- D8 1-lfxt apply pulse (comb)
    signal wr_ack_tgl  : std_logic;                      -- D8 commit ack toggle

    -- ---- B4 alarm (lfxt domain) ------------------------------------------
    signal alm_live      : std_logic_vector(31 downto 0);-- live compare value (D11)
    signal alm_match_prev: std_logic;                    -- rising-edge detect of match
    signal alm_tgl       : std_logic;                    -- alarm event toggle (D10)

    -- ---- B5 periodic tick (lfxt domain) ----------------------------------
    signal per_live    : std_logic_vector(15 downto 0);  -- live reload value (A4/D12)
    signal tick_cnt    : std_logic_vector(15 downto 0);  -- down-counter
    signal tick_tgl    : std_logic;                      -- tick event toggle (D10)

begin

    -- ------------------------- Signal Routing ---------------------------------
    rtcen_cr  <= rtc_cr(0);
    almen_cr  <= rtc_cr(1);
    ticken_cr <= rtc_cr(2);
    almie     <= rtc_cr(3);
    tickie    <= rtc_cr(4);

    -- SR.SYNC (BUSY): both commit toggles observed in the clk domain (D8).
    -- D8 literal form (adjudicated): raw request toggle vs synced ack -- SYNC is
    -- visible to the very next SR read after a committing write (no blind window).
    sync_busy <= '1' when (wr_req_tgl /= wrack_c2) else '0';

    -- irq_rtc = (status and enable), combinational, never latched (D13; QSPI form).
    irq_rtc   <= (almf_flag and almie) or (tickf_flag and tickie);

    -- slot decode (EnMemPeriph-qualified LEVEL, D4; never an edge).
    rtc_slot  <= conv_integer(MABPart) when EnMemPeriph = '0' else 0;

    -- ------------------------- B1: register write (ClkMem) --------------------
    -- Rising ClkMem, EnMemPeriph='0' qualified. SEC/ALM/PER commits and the SR W1C
    -- require lane 0 (WEn(0)='0'); CR honors its lane-0 byte. A committing write
    -- stages its value, marks commit_mask, and FLIPS wr_req_tgl (toggle-CDC, D8).
    -- A SUB write stages only (committed by the following SEC write). SR lane-0
    -- writes of 1 to ALMF/TICKF flip the clr_*_tgl toggles (W1C-CDC, D10). Reset
    -- via resetn (bus domain).
    reg_write: process(resetn, ClkMem)
    begin
        if resetn = '0' then
            rtc_cr       <= (others => '0');
            stage_sec    <= (others => '0');
            stage_sub    <= (others => '0');
            stage_alm    <= (others => '0');
            stage_per    <= (others => '0');
            commit_mask  <= (others => '0');
            wr_req_tgl   <= '0';
            clr_alm_tgl  <= '0';
            clr_tick_tgl <= '0';
        elsif rising_edge(ClkMem) then
            if EnMemPeriph = '0' then
                case rtc_slot is
                    when SLOT_CR =>
                        if WEn(0) = '0' then
                            rtc_cr <= wdata(4 downto 0);      -- bits 31:5 reserved
                        end if;
                    when SLOT_SEC =>
                        -- stage SEC + commit {SEC,SUB} atomically (lane-0 qualified)
                        if WEn(0) = '0' then
                            stage_sec   <= wdata;
                            commit_mask <= "001";
                            wr_req_tgl  <= not wr_req_tgl;
                        end if;
                    when SLOT_SUB =>
                        -- stage only (committed with the following SEC write)
                        if WEn(0) = '0' then
                            stage_sub <= wdata(14 downto 0);
                        end if;
                    when SLOT_ALM =>
                        if WEn(0) = '0' then
                            stage_alm   <= wdata;
                            commit_mask <= "010";
                            wr_req_tgl  <= not wr_req_tgl;
                        end if;
                    when SLOT_PER =>
                        if WEn(0) = '0' then
                            stage_per   <= wdata(15 downto 0);
                            commit_mask <= "100";
                            wr_req_tgl  <= not wr_req_tgl;
                        end if;
                    when SLOT_SR =>
                        -- W1C: writing 1 clears; SYNC (bit 0) is read-only, ignored.
                        if WEn(0) = '0' then
                            if wdata(1) = '1' then clr_alm_tgl  <= not clr_alm_tgl;  end if;
                            if wdata(2) = '1' then clr_tick_tgl <= not clr_tick_tgl; end if;
                        end if;
                    when others =>
                        null;   -- TRIM (slot 6) writes ignored; slots >=7 no effect
                end case;
            end if;
        end if;
    end process;

    -- ------------------------- B1: register read (ClkMem) ---------------------
    -- Registered read mux on rising ClkMem over data ALREADY synchronized into the
    -- bus domain (snap_sync from D7, flags from the clk sticky process, staging
    -- readback). No pre-latch, no bridge (D4). Reserved/TRIM/>=7 read 0.
    reg_read: process(ClkMem)
    begin
        if rising_edge(ClkMem) then
            case rtc_slot is
                when SLOT_CR =>
                    rdata_out <= (31 downto 5 => '0') & rtc_cr;
                when SLOT_SEC =>
                    rdata_out <= snap_sync(46 downto 15);
                when SLOT_SUB =>
                    rdata_out <= (31 downto 15 => '0') & snap_sync(14 downto 0);
                when SLOT_ALM =>
                    rdata_out <= stage_alm;
                when SLOT_PER =>
                    rdata_out <= (31 downto 16 => '0') & stage_per;
                when SLOT_SR =>
                    rdata_out <= (31 downto 3 => '0') & tickf_flag & almf_flag & sync_busy;
                when others =>
                    rdata_out <= (others => '0');   -- TRIM slot 6 and >=7 read 0
            end case;
        end if;
    end process;

    -- ------------------------- B2: clk (mclk ref) CDC -------------------------
    -- Free-running clk hosts every LFXT->bus synchronizer plus the sticky flags, so
    -- ALMF/TICKF and irq_rtc set autonomously while the bus is idle (D2/G7). A
    -- metastable sample only DELAYS a flag/snapshot by one clk edge (the house CDC
    -- safety argument). Reset via resetn. Single edge (rising clk) only.
    clk_cdc: process(resetn, clk)
    begin
        if resetn = '0' then
            cap_s1 <= '0'; cap_s2 <= '0'; cap_prev <= '0';
            snap_sync <= (others => '0');
            wrack_c1 <= '0'; wrack_c2 <= '0';
            almt_c1 <= '0'; almt_c2 <= '0'; almt_prev <= '0';
            tickt_c1 <= '0'; tickt_c2 <= '0'; tickt_prev <= '0';
            clra_c1 <= '0'; clra_c2 <= '0'; clra_prev <= '0';
            clrt_c1 <= '0'; clrt_c2 <= '0'; clrt_prev <= '0';
            almf_flag <= '0'; tickf_flag <= '0';
        elsif rising_edge(clk) then
            -- D7 read-side: 2-FF cap_tgl, edge-detect, sample snap_lfxt -> snap_sync.
            -- snap_lfxt settled ~1 lfxt period before its toggle crossed (data before
            -- flag), so the multi-bit sample is glitch-free.
            cap_s1 <= cap_tgl; cap_s2 <= cap_s1; cap_prev <= cap_s2;
            if cap_s2 /= cap_prev then
                snap_sync <= snap_lfxt;
            end if;

            -- D8 write handshake: 2-FF the ack toggle into clk (sync_busy compares
            -- it against the RAW wr_req_tgl -- D8 literal form, adjudicated).
            wrack_c1 <= wr_ack_tgl; wrack_c2 <= wrack_c1;

            -- D10 event toggles: 2-FF + edge-detect each into clk.
            almt_c1  <= alm_tgl;      almt_c2  <= almt_c1;  almt_prev  <= almt_c2;
            tickt_c1 <= tick_tgl;     tickt_c2 <= tickt_c1; tickt_prev <= tickt_c2;
            -- D10 W1C request toggles from ClkMem: 2-FF + edge-detect each into clk.
            clra_c1  <= clr_alm_tgl;  clra_c2  <= clra_c1;  clra_prev  <= clra_c2;
            clrt_c1  <= clr_tick_tgl; clrt_c2  <= clrt_c1;  clrt_prev  <= clrt_c2;

            -- Sticky ALMF: SET (event edge) WINS over CLEAR (W1C edge) same cycle.
            if (almt_c2 /= almt_prev) then
                almf_flag <= '1';
            elsif (clra_c2 /= clra_prev) then
                almf_flag <= '0';
            end if;
            -- Sticky TICKF: set wins over clear.
            if (tickt_c2 /= tickt_prev) then
                tickf_flag <= '1';
            elsif (clrt_c2 /= clrt_prev) then
                tickf_flag <= '0';
            end if;
        end if;
    end process;

    -- ------------------------- B6: LFXT reset synchronizer (D14) --------------
    -- ASYNC assert on resetn='0' (both flops cleared), SYNC de-assert clocked by
    -- lfxt_in -- the always-on domain leaves reset with no metastable release.
    rst_sync: process(resetn, lfxt_in)
    begin
        if resetn = '0' then
            rtc_rst_meta  <= '0';
            rtc_lfxt_rstn <= '0';
        elsif rising_edge(lfxt_in) then
            rtc_rst_meta  <= '1';
            rtc_lfxt_rstn <= rtc_rst_meta;
        end if;
    end process;

    -- ------------------------- B2->LFXT: enable held-level syncs (D9) ---------
    -- RTCEN/ALMEN/TICKEN cross as held levels, 2-FF synchronized on lfxt_in. They
    -- gate the D-input logic of the counter/compare/tick -- never a clock gate.
    en_sync: process(rtc_lfxt_rstn, lfxt_in)
    begin
        if rtc_lfxt_rstn = '0' then
            rtcen_s1 <= '0'; rtcen_sync <= '0';
            almen_s1 <= '0'; almen_sync <= '0';
            ticken_s1 <= '0'; ticken_sync <= '0';
        elsif rising_edge(lfxt_in) then
            rtcen_s1  <= rtcen_cr;  rtcen_sync  <= rtcen_s1;
            almen_s1  <= almen_cr;  almen_sync  <= almen_s1;
            ticken_s1 <= ticken_cr; ticken_sync <= ticken_s1;
        end if;
    end process;

    -- ------------------------- B2->LFXT: write-commit apply (D8) --------------
    -- 2-FF wr_req_tgl into lfxt + edge-detect -> wr_apply (1-lfxt pulse). On the
    -- same edge that a new request is observed, flip wr_ack_tgl (handshake back).
    -- wr_apply is combinational from the synchronized flops; the B3/B4/B5 engines
    -- co-sample it with the (quasi-static) commit_mask/stage_* to load atomically.
    wrsync: process(rtc_lfxt_rstn, lfxt_in)
    begin
        if rtc_lfxt_rstn = '0' then
            wrreq_s1 <= '0'; wrreq_s2 <= '0'; wrreq_prev <= '0';
            wr_ack_tgl <= '0';
        elsif rising_edge(lfxt_in) then
            wrreq_s1 <= wr_req_tgl; wrreq_s2 <= wrreq_s1; wrreq_prev <= wrreq_s2;
            if wrreq_s2 /= wrreq_prev then
                wr_ack_tgl <= not wr_ack_tgl;
            end if;
        end if;
    end process;
    wr_apply <= '1' when (wrreq_s2 /= wrreq_prev) else '0';

    -- ------------------------- B3: wall clock (lfxt_in, D6/D7/D8) -------------
    -- The 47-bit {sec_cnt(31:0), sub_cnt(14:0)} single binary counter: sub_cnt is a
    -- full 15-bit wrap at 32768 = 2^15, sec_cnt is literally its carry-out, so the
    -- concatenation increments by 1 each lfxt edge (exact 1 Hz). Increment only when
    -- rtcen_sync='1'. The atomic set-time load (commit_mask time bit) takes PRIORITY
    -- over the increment that edge (TIMER latch_timer_value idiom). snap_lfxt +
    -- cap_tgl are written every edge AFTER the increment -- the POST-increment value
    -- (nsec/nsub) is snapped so the reader never sees a pre-carry torn value (D7).
    wallclock: process(rtc_lfxt_rstn, lfxt_in)
        variable nsec : std_logic_vector(31 downto 0);
        variable nsub : std_logic_vector(14 downto 0);
    begin
        if rtc_lfxt_rstn = '0' then
            sec_cnt   <= (others => '0');
            sub_cnt   <= (others => '0');
            snap_lfxt <= (others => '0');
            cap_tgl   <= '0';
        elsif rising_edge(lfxt_in) then
            if wr_apply = '1' and commit_mask(0) = '1' then
                nsec := stage_sec;                    -- atomic set-time load (priority)
                nsub := stage_sub;
            elsif rtcen_sync = '1' then
                if sub_cnt = "111111111111111" then   -- prescaler wrap at 32768
                    nsub := (others => '0');
                    nsec := sec_cnt + 1;              -- carry into seconds
                else
                    nsub := sub_cnt + 1;
                    nsec := sec_cnt;
                end if;
            else
                nsec := sec_cnt;                      -- disabled: hold
                nsub := sub_cnt;
            end if;
            sec_cnt   <= nsec;
            sub_cnt   <= nsub;
            snap_lfxt <= nsec & nsub;                 -- post-increment snapshot (D7)
            cap_tgl   <= not cap_tgl;                 -- flag flips WITH the data
        end if;
    end process;

    -- ------------------------- B4: alarm compare (lfxt_in, D10/D11) -----------
    -- Full 32-bit seconds equality, one-shot. The match (sec_cnt = alm_live) holds
    -- for a whole second, so we RISING-edge detect it; gated by almen_sync, the edge
    -- FLIPS alm_tgl (event-CDC, D10). alm_live loads on an ALM commit (commit_mask
    -- alm bit). Firmware re-arms by writing a new ALM (advancing past this second).
    alarm: process(rtc_lfxt_rstn, lfxt_in)
        variable match_v : std_logic;
    begin
        if rtc_lfxt_rstn = '0' then
            alm_live       <= (others => '0');
            alm_match_prev <= '0';
            alm_tgl        <= '0';
        elsif rising_edge(lfxt_in) then
            if wr_apply = '1' and commit_mask(1) = '1' then
                alm_live <= stage_alm;
            end if;
            if sec_cnt = alm_live then match_v := '1'; else match_v := '0'; end if;
            if match_v = '1' and alm_match_prev = '0' and almen_sync = '1' then
                alm_tgl <= not alm_tgl;               -- one edge per match rise
            end if;
            alm_match_prev <= match_v;                -- tracks even while ALMEN=0
        end if;
    end process;

    -- ------------------------- B5: periodic tick (lfxt_in, D10/D12) -----------
    -- Independent down-counter reloaded from per_live; underflow (tick_cnt=0) FLIPS
    -- tick_tgl (event-CDC, D10) and reloads. Tick period = per_live+1 lfxt ticks.
    -- On a PER commit, load the counter AND per_live from the new value; while
    -- ticken_sync='0', hold the counter at per_live (clean cadence on enable). Does
    -- NOT disturb the wall-clock prescaler (D12).
    tick: process(rtc_lfxt_rstn, lfxt_in)
    begin
        if rtc_lfxt_rstn = '0' then
            per_live <= (others => '0');
            tick_cnt <= (others => '0');
            tick_tgl <= '0';
        elsif rising_edge(lfxt_in) then
            if wr_apply = '1' and commit_mask(2) = '1' then
                per_live <= stage_per;                -- commit new reload
                tick_cnt <= stage_per;                -- restart cadence from it
            elsif ticken_sync = '0' then
                tick_cnt <= per_live;                 -- disabled: hold at reload value
            else
                if tick_cnt = 0 then
                    tick_cnt <= per_live;             -- underflow: reload + fire
                    tick_tgl <= not tick_tgl;
                else
                    tick_cnt <= tick_cnt - 1;
                end if;
            end if;
        end if;
    end process;

end behavioral;
