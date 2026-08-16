library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

/* RTC: 32.768 kHz always-on wall clock with a one-shot alarm and a recurring periodic tick, behind one combined IRQ (vector 114).
   Three clocks: ungated lfxt_in (counter, alarm, tick, commit apply), free-running clk (LFXT-into-bus synchronizers, sticky flags, IRQ), gated ClkMem (register file).
   clk must free-run so ALMF, TICKF and irq_rtc set with no bus access in flight; lfxt_in is always on, and neither firmware nor PWRCTRL can stop it.
   Every domain hand-off is a toggle or a held quasi-static level: no async clear ever crosses a domain, and no clock is gated, divided or generated in this block.
   EnMemPeriph is an active-low level qualifier only, never a clock and never an edge; reads are registered on rising ClkMem over already-synchronized data, so no read bridge is needed. */

/* Register map (base 0x6500, slot n at 0x6500 + 4n, decoded off MABPart(7:2)):
     0 RTC0CR   : [0]RTCEN [1]ALMEN [2]TICKEN [3]ALMIE [4]TICKIE, 31:5 rsvd read 0.
     1 RTC0SEC  : read returns the coherent snapshot snap_sync[46:15]; write stages SEC and
                  commits {SEC,SUB} atomically (SR.SYNC busy), lane-0 qualified.
     2 RTC0SUB  : read returns snap_sync[14:0] zero-extended, the SAME instant as SEC; write
                  stages only and is committed by the following SEC write, lane-0 qualified.
     3 RTC0ALM  : read returns the mclk staging readback (no CDC); write stages and commits ALM.
     4 RTC0PER  : [15:0] reload; read returns the staging readback, write stages and commits PER.
                  Tick every per_live+1 lfxt ticks, so about 2 s maximum interval.
     5 RTC0SR   : [0]SYNC ro, [1]ALMF W1C, [2]TICKF W1C, 31:3 rsvd read 0.
     6 RTC0TRIM : reserved: reads 0, writes ignored. Slots 7 and above read 0. */

entity RTC is
    port (
        clk         : in  std_logic;                     -- free-running fast reference (MCLK at integration): CDC synchronizers, sticky W1C flags, IRQ combiner
        resetn      : in  std_logic;                     -- chip reset, active-low (async)
        lfxt_in     : in  std_logic;                     -- UNGATED 32.768 kHz wall clock
        irq_rtc     : out std_logic;                     -- combined alarm/tick IRQ (vector 114)
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW select/qualifier, never a clock
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0); -- bus write data
        rdata_out   : out std_logic_vector(31 downto 0); -- registered read data (ClkMem domain)

        -- Event-fabric taps: the flags' SET conditions (synchronized event edges), pre-IE, never touched by ALMIE/TICKIE.
        -- Already one-clk pulses in the clk domain.
        evt_alarm   : out std_logic;                     -- alarm event pulse
        evt_tick    : out std_logic                      -- periodic-tick event pulse
    );
end RTC;

architecture behavioral of RTC is

    -- ---- word-slot map ---------------------------------------------------
    constant SLOT_CR   : natural := 0;
    constant SLOT_SEC  : natural := 1;
    constant SLOT_SUB  : natural := 2;
    constant SLOT_ALM  : natural := 3;
    constant SLOT_PER  : natural := 4;
    constant SLOT_SR   : natural := 5;
    constant SLOT_TRIM : natural := 6;

    -- ---- register-file storage (ClkMem domain) ---------------------------
    signal rtc_cr      : std_logic_vector(4 downto 0);   -- RTCEN/ALMEN/TICKEN/ALMIE/TICKIE
    signal stage_sec   : std_logic_vector(31 downto 0);  -- staging: seconds
    signal stage_sub   : std_logic_vector(14 downto 0);  -- staging: subseconds
    signal stage_alm   : std_logic_vector(31 downto 0);  -- staging + ALM readback
    signal stage_per   : std_logic_vector(15 downto 0);  -- staging + PER readback
    signal commit_mask : std_logic_vector(2 downto 0);   -- [0]time{sec,sub} [1]alm [2]per
    signal wr_req_tgl  : std_logic;                      -- write-commit request toggle
    signal clr_alm_tgl : std_logic;                      -- W1C ALMF request toggle
    signal clr_tick_tgl: std_logic;                      -- W1C TICKF request toggle
    signal rtc_slot    : natural range 0 to 63;          -- decoded word slot

    -- ---- CR field taps (combinational; quasi-static) ---------------------
    signal rtcen_cr, almen_cr, ticken_cr : std_logic;    -- engine enables, crossed into lfxt
    signal almie, tickie                 : std_logic;    -- IRQ enables, stay in the mclk domain

    -- ---- clk (mclk ref) domain: synchronizers + sticky flags -------------
    signal cap_s1, cap_s2, cap_prev      : std_logic;    -- cap_tgl sync + edge
    signal snap_sync   : std_logic_vector(46 downto 0);  -- bus-domain snapshot
    signal wrack_c1, wrack_c2            : std_logic;     -- wr_ack into clk
    signal sync_busy   : std_logic;                      -- SR.SYNC (held level)
    signal almt_c1, almt_c2, almt_prev   : std_logic;    -- alm_tgl sync + edge
    signal tickt_c1, tickt_c2, tickt_prev: std_logic;    -- tick_tgl sync + edge
    signal clra_c1, clra_c2, clra_prev   : std_logic;    -- W1C ALMF sync + edge
    signal clrt_c1, clrt_c2, clrt_prev   : std_logic;    -- W1C TICKF sync + edge
    signal almf_flag, tickf_flag         : std_logic;    -- mclk-domain sticky flags

    -- ---- reset sync plus the bus-into-LFXT enable syncs (lfxt domain) ----
    signal rtc_rst_meta, rtc_lfxt_rstn   : std_logic;    -- reset synchronizer
    signal rtcen_s1, rtcen_sync          : std_logic;    -- RTCEN into lfxt
    signal almen_s1, almen_sync          : std_logic;    -- ALMEN into lfxt
    signal ticken_s1, ticken_sync        : std_logic;    -- TICKEN into lfxt

    -- ---- wall clock (lfxt domain) ----------------------------------------
    signal sec_cnt     : std_logic_vector(31 downto 0);  -- seconds (carry of sub_cnt)
    signal sub_cnt     : std_logic_vector(14 downto 0);  -- subsecond prescaler 0..32767
    signal snap_lfxt   : std_logic_vector(46 downto 0);  -- double-buffer hold reg
    signal cap_tgl     : std_logic;                      -- snapshot toggle

    -- ---- write-commit apply (lfxt domain) --------------------------------
    signal wrreq_s1, wrreq_s2, wrreq_prev: std_logic;    -- wr_req into lfxt
    signal wr_apply    : std_logic;                      -- 1-lfxt apply pulse (comb)
    signal wr_ack_tgl  : std_logic;                      -- commit ack toggle

    -- ---- alarm (lfxt domain) ---------------------------------------------
    signal alm_live      : std_logic_vector(31 downto 0);-- live compare value
    signal alm_match_prev: std_logic;                    -- rising-edge detect of match
    signal alm_tgl       : std_logic;                    -- alarm event toggle

    -- ---- periodic tick (lfxt domain) -------------------------------------
    signal per_live    : std_logic_vector(15 downto 0);  -- live reload value
    signal tick_cnt    : std_logic_vector(15 downto 0);  -- down-counter
    signal tick_tgl    : std_logic;                      -- tick event toggle

begin

    -- ------------------------- Signal Routing ---------------------------------
    -- CR field taps, so the engines read named bits rather than slices.
    rtcen_cr  <= rtc_cr(0);
    almen_cr  <= rtc_cr(1);
    ticken_cr <= rtc_cr(2);
    almie     <= rtc_cr(3);
    tickie    <= rtc_cr(4);

    -- SR.SYNC (BUSY): the RAW request toggle compared against the synced ack.
    -- Keep it raw, so SYNC is visible to the very next SR read after a committing write with no blind window.
    sync_busy <= '1' when (wr_req_tgl /= wrack_c2) else '0';

    -- irq_rtc: status and enable, combinational, never latched.
    irq_rtc   <= (almf_flag and almie) or (tickf_flag and tickie);

    -- slot decode: EnMemPeriph-qualified level, never an edge.
    rtc_slot  <= conv_integer(MABPart) when EnMemPeriph = '0' else 0;

    /* ------------------------- register write (ClkMem) ------------------------
       Rising ClkMem, qualified by EnMemPeriph='0'; every commit and the SR W1C require lane 0.
       A committing write stages its value, marks commit_mask and flips wr_req_tgl; a SUB write stages only and is committed by the following SEC write. */
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
                        -- Stage SEC and commit {SEC,SUB} atomically, lane-0 qualified.
                        if WEn(0) = '0' then
                            stage_sec   <= wdata;
                            commit_mask <= "001";
                            wr_req_tgl  <= not wr_req_tgl;
                        end if;
                    when SLOT_SUB =>
                        -- Stage only; the following SEC write is what commits it.
                        if WEn(0) = '0' then
                            stage_sub <= wdata(14 downto 0);
                        end if;
                    when SLOT_ALM =>
                        -- Stage the alarm compare value and request its commit.
                        if WEn(0) = '0' then
                            stage_alm   <= wdata;
                            commit_mask <= "010";
                            wr_req_tgl  <= not wr_req_tgl;
                        end if;
                    when SLOT_PER =>
                        -- Stage the tick reload and request its commit.
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
                        null;   -- TRIM (slot 6) and slots 7 and above: writes ignored
                end case;
            end if;
        end if;
    end process;

    /* ------------------------- register read (ClkMem) -------------------------
       Registered read mux on rising ClkMem over data already synchronized into the bus domain, so no pre-latch and no read bridge.
       Reserved bits, TRIM, and slots 7 and above read 0. */
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
                    rdata_out <= (others => '0');   -- TRIM and out-of-range slots read 0
            end case;
        end if;
    end process;

    /* ------------------------- clk (mclk ref) CDC -----------------------------
       Free-running clk hosts every LFXT-into-bus synchronizer plus the sticky flags, so ALMF/TICKF and irq_rtc set autonomously while the bus is idle.
       A metastable sample can only DELAY a flag or snapshot by one clk edge. */
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
            -- Read side: 2-FF cap_tgl, edge-detect, then sample snap_lfxt into snap_sync.
            -- snap_lfxt settles about 1 lfxt period before its toggle crosses (data before flag), so the multi-bit sample is glitch-free.
            cap_s1 <= cap_tgl; cap_s2 <= cap_s1; cap_prev <= cap_s2;
            if cap_s2 /= cap_prev then
                snap_sync <= snap_lfxt;
            end if;

            -- Write handshake: 2-FF the ack toggle into clk; sync_busy compares it against the raw wr_req_tgl.
            wrack_c1 <= wr_ack_tgl; wrack_c2 <= wrack_c1;

            -- Event toggles: 2-FF and edge-detect each into clk.
            almt_c1  <= alm_tgl;      almt_c2  <= almt_c1;  almt_prev  <= almt_c2;
            tickt_c1 <= tick_tgl;     tickt_c2 <= tickt_c1; tickt_prev <= tickt_c2;
            -- W1C request toggles from ClkMem: 2-FF and edge-detect each into clk.
            clra_c1  <= clr_alm_tgl;  clra_c2  <= clra_c1;  clra_prev  <= clra_c2;
            clrt_c1  <= clr_tick_tgl; clrt_c2  <= clrt_c1;  clrt_prev  <= clrt_c2;

            -- Sticky ALMF: a SET (event edge) WINS over a CLEAR (W1C edge) in the same cycle.
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

    -- Event-fabric producer taps: the same synchronized event edges the sticky flags set from, exported combinationally and pre-IE.
    -- One clk pulse per event, because almt_prev and tickt_prev advance every clk.
    evt_alarm <= '1' when almt_c2 /= almt_prev else '0';
    evt_tick  <= '1' when tickt_c2 /= tickt_prev else '0';

    -- ------------------------- LFXT reset synchronizer ------------------------
    -- ASYNC assert on resetn='0' clears both flops; de-assert is synchronous, clocked by lfxt_in, so the always-on domain leaves reset with no metastable release.
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

    /* ------------------------- Bus into LFXT: enable held-level syncs ---------
       RTCEN/ALMEN/TICKEN cross as held levels, 2-FF synchronized on lfxt_in.
       They gate the D-input logic of the counter, compare and tick engines, never a clock. */
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

    /* ------------------------- Bus into LFXT: write-commit apply --------------
       2-FF wr_req_tgl into lfxt, then edge-detect it to form wr_apply, a 1-lfxt pulse; wr_ack_tgl flips on that same edge to hand the acknowledge back.
       The wall-clock, alarm and tick engines co-sample wr_apply with the quasi-static commit_mask and stage_* to load atomically. */
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

    /* ------------------------- wall clock (lfxt_in) ---------------------------
       One 47-bit counter {sec_cnt(31:0), sub_cnt(14:0)}: sub_cnt wraps at 32768 = 2^15 and sec_cnt is its carry-out, giving exact 1 Hz while rtcen_sync='1'.
       The atomic set-time load takes PRIORITY over the increment on that edge, and snap_lfxt with cap_tgl are written every edge AFTER the increment, so the reader never sees a pre-carry torn value. */
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
            snap_lfxt <= nsec & nsub;                 -- post-increment snapshot
            cap_tgl   <= not cap_tgl;                 -- flag flips WITH the data
        end if;
    end process;

    /* ------------------------- alarm compare (lfxt_in) ------------------------
       Full 32-bit seconds equality, one-shot: the match holds for a whole second, so it is RISING-edge detected and, gated by almen_sync, that edge flips alm_tgl.
       alm_live loads on an ALM commit; firmware re-arms by writing a new ALM that advances past this second. */
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

    /* ------------------------- periodic tick (lfxt_in) ------------------------
       Independent down-counter reloaded from per_live: underflow flips tick_tgl and reloads, giving a tick every per_live+1 lfxt ticks without disturbing the wall-clock prescaler.
       A PER commit loads both the counter and per_live; while ticken_sync='0' the counter is held at per_live, so enabling starts a clean cadence. */
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
                    tick_cnt <= per_live;             -- underflow: reload and fire
                    tick_tgl <= not tick_tgl;
                else
                    tick_cnt <= tick_cnt - 1;
                end if;
            end if;
        end if;
    end process;

end behavioral;
