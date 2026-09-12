-- VestaRV: real-time clock
-- 32.768 kHz always-on wall clock with a one-shot alarm and a recurring periodic tick, behind one combined IRQ (vector 114).
-- Three clocks: ungated lfxt_in (counter, alarm, tick, commit apply), free-running clk (LFXT-into-bus synchronizers, sticky flags, IRQ) and gated ClkMem (one work.periph_regs instance driven by rtc_regs_pkg's tables, hdl/common/regs/REGFILE.md). clk must free-run so ALMF, TICKF and irq_rtc set with no bus access in flight; lfxt_in is always on and neither firmware nor PWRCTRL can stop it.
-- Every domain hand-off is a toggle or a held quasi-static level: no async clear crosses a domain, and no clock is gated, divided or generated here.
-- SEC and SUB read one coherent snapshot of the same instant; a SEC write commits the staged SEC/SUB pair atomically, with SR.SYNC busy meanwhile.
-- EnMemPeriph is an active-low level qualifier, never a clock and never an edge.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- Word slots, field ranges, resets and implemented-bit masks: generated from hdl/common/regs/rdl/rtc.rdl.
use work.rtc_regs_pkg.all;



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

    -- ---- register file (ClkMem domain) -----------------------------------
    -- CR and the four staging words are periph_regs storage, read out of regs_q;
    -- SEC and SUB read the coherent counter snapshot instead (RDTHRU), and SR
    -- holds no flop here at all.
    signal regs_q      : reg_arr_t;                        -- the stored words
    signal hw_rd_s     : reg_arr_t;                        -- read source for SEC, SUB and SR
    signal acc_s       : std_logic_vector(0 to NWORDS-1);  -- combinational: this slot is addressed now
    signal wen_eff     : std_logic_vector(3 downto 0);     -- see the instance below
    signal sec_rd, sub_rd, sr_rd : std_logic_vector(31 downto 0);

    signal stage_sub   : std_logic_vector(14 downto 0);  -- staging: subseconds
    signal stage_per   : std_logic_vector(15 downto 0);  -- staging + PER readback
    signal commit_mask : std_logic_vector(2 downto 0);   -- [0]time{sec,sub} [1]alm [2]per
    signal wr_req_tgl  : std_logic;                      -- write-commit request toggle
    signal clr_alm_tgl : std_logic;                      -- W1C ALMF request toggle
    signal clr_tick_tgl: std_logic;                      -- W1C TICKF request toggle

    -- ---- CR field taps (combinational; quasi-static) ---------------------
    signal rtcen_cr, almen_cr, ticken_cr : std_logic;    -- engine enables, crossed into lfxt
    signal almie, tickie                 : std_logic;    -- IRQ enables, stay in the mclk domain

    -- ---- clk (mclk ref) domain: synchronizers + sticky flags -------------
    signal cap_s2, cap_prev              : std_logic;    -- cap_tgl sync q + edge
    signal cap_sync_d, cap_sync_q        : std_logic_vector(0 downto 0);
    signal snap_sync   : std_logic_vector(46 downto 0);  -- bus-domain snapshot
    signal wrack_c2                      : std_logic;     -- wr_ack into clk
    signal wrack_sync_d, wrack_sync_q    : std_logic_vector(0 downto 0);
    signal sync_busy   : std_logic;                      -- SR.SYNC (held level)
    -- The four event/W1C toggles cross into clk in ONE work.sync: bit 3 alm, 2 tick, 1 clr_alm, 0 clr_tick. The *_prev edge flops stay local.
    signal evt_sync_d, evt_sync_q        : std_logic_vector(3 downto 0);
    signal almt_c2, almt_prev            : std_logic;    -- alm_tgl sync q + edge
    signal tickt_c2, tickt_prev          : std_logic;    -- tick_tgl sync q + edge
    signal clra_c2, clra_prev            : std_logic;    -- W1C ALMF sync q + edge
    signal clrt_c2, clrt_prev            : std_logic;    -- W1C TICKF sync q + edge
    signal almf_flag, tickf_flag         : std_logic;    -- mclk-domain sticky flags

    -- ---- reset sync plus the bus-into-LFXT enable syncs (lfxt domain) ----
    signal rtc_lfxt_rstn                 : std_logic;    -- reset synchronizer q
    signal rst_sync_d, rst_sync_q        : std_logic_vector(0 downto 0);
    -- RTCEN/ALMEN/TICKEN cross into lfxt in ONE work.sync: bit 2 RTCEN, 1 ALMEN, 0 TICKEN.
    signal en_sync_d, en_sync_q          : std_logic_vector(2 downto 0);
    signal rtcen_sync                    : std_logic;    -- RTCEN into lfxt
    signal almen_sync                    : std_logic;    -- ALMEN into lfxt
    signal ticken_sync                   : std_logic;    -- TICKEN into lfxt

    -- ---- wall clock (lfxt domain) ----------------------------------------
    signal sec_cnt     : std_logic_vector(31 downto 0);  -- seconds (carry of sub_cnt)
    signal sub_cnt     : std_logic_vector(14 downto 0);  -- subsecond prescaler 0..32767
    signal snap_lfxt   : std_logic_vector(46 downto 0);  -- double-buffer hold reg
    signal cap_tgl     : std_logic;                      -- snapshot toggle

    -- ---- write-commit apply (lfxt domain) --------------------------------
    signal wrreq_s2, wrreq_prev          : std_logic;    -- wr_req into lfxt, sync q + edge
    signal wrreq_sync_d, wrreq_sync_q    : std_logic_vector(0 downto 0);
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
    rtcen_cr  <= regs_q(SLOT_CR)(RTCEN_LSB);
    almen_cr  <= regs_q(SLOT_CR)(RTCALMEN_LSB);
    ticken_cr <= regs_q(SLOT_CR)(RTCTICKEN_LSB);
    almie     <= regs_q(SLOT_CR)(RTCALMIE_LSB);
    tickie    <= regs_q(SLOT_CR)(RTCTICKIE_LSB);

    -- The two narrow staging words, sliced out of their stored words.
    stage_sub <= regs_q(SLOT_SUB)(RTCSUB_MSB downto RTCSUB_LSB);
    stage_per <= regs_q(SLOT_PER)(RTCPER_MSB downto RTCPER_LSB);

    -- SR.SYNC (BUSY): the RAW request toggle compared against the synced ack.
    -- Keep it raw, so SYNC is visible to the very next SR read after a committing write with no blind window.
    sync_busy <= '1' when (wr_req_tgl /= wrack_c2) else '0';

    -- irq_rtc: status and enable, combinational, never latched.
    irq_rtc   <= (almf_flag and almie) or (tickf_flag and tickie);

    -- The words this block owns rather than stores: the coherent SEC/SUB snapshot
    -- already synchronized into the bus domain, and the status word.
    sec_rd <= snap_sync(snap_sync'high downto RTCSUB_MSB + 1);
    sub_rd <= (31 downto RTCSUB_MSB + 1 => '0') & snap_sync(RTCSUB_MSB downto 0);
    sr_rd  <= (31 downto RTCTICKF_MSB + 1 => '0') & tickf_flag & almf_flag & sync_busy;

    hw_rd_s <= (SLOT_SEC => sec_rd,
                SLOT_SUB => sub_rd,
                SLOT_SR  => sr_rd,
                others   => (others => '0'));

    /* EVERY write in this block is qualified on lane 0: the hand-written decode
       tested WEn(0) = '0' in all six of its arms and ignored a write that did
       not enable byte 0, whatever the other three lanes said. periph_regs has no
       per-word write qualifier, so the qualifier is applied to the lane vector
       instead: an access that does not enable lane 0 is handed to the register
       file as a read, which is exactly what it was. */
    wen_eff <= WEn when WEn(0) = '0' else "1111";

    -- RDTHRU is SEC and SUB: their storage is the write staging pair while the
    -- read is the counter's coherent snapshot. WIDEWR is SEC, SUB, ALM and PER:
    -- a qualifying write replaces the whole word rather than merging per lane,
    -- which with wen_eff above is byte for byte `stage_x <= wdata`. CR merges per
    -- lane, and its five implemented bits are all inside lane 0, so the two are
    -- the same thing there.
    -- STROBE_HOLD is left at false and no strobe is used: every action a write
    -- triggers here is a toggle taken on the ClkMem edge of the write itself,
    -- through acc_hit, because SR.SYNC must be visible to the very next SR read
    -- and a registered strobe would defer the request by an edge.
    u_regs: entity work.periph_regs
        generic map (
            NWORDS      => NWORDS,
            RSTVAL      => RSTVAL,
            IMPL        => IMPL,
            W1C         => W1C,
            WOSET       => WOSET,
            WOT         => WOT,
            PULSE       => PULSE,
            RCLR        => RCLR,
            HWOWN       => HWOWN,
            RDTHRU      => "0110000",
            WIDEWR      => "0111100")
        port map (
            ClkMem      => ClkMem,
            resetn      => resetn,
            EnMemPeriph => EnMemPeriph,
            WEn         => wen_eff,
            MABPart     => MABPart,
            wdata       => wdata,
            rdata_out   => rdata_out,
            regs        => regs_q,
            hw_rd       => hw_rd_s,
            acc_hit     => acc_s,
            rd_strobe   => open,
            wr_strobe   => open,
            wr_pulse    => open,
            w1c_hit     => open,
            woset_hit   => open,
            wot_hit     => open,
            rd_clr      => open);

    /* ------------------------- commit and W1C requests (ClkMem) ---------------
       Rising ClkMem, on the same edge as the write that causes it, off the
       register file's combinational acc_hit and this block's own WEn(0).
       A SEC, ALM or PER write marks commit_mask and flips wr_req_tgl; a SUB write
       stages only and is committed by the following SEC write. SR.SYNC is the raw
       request toggle against the synced ack, so the request must not slip an edge. */
    req_proc: process(resetn, ClkMem)
    begin
        if resetn = '0' then
            commit_mask  <= (others => '0');
            wr_req_tgl   <= '0';
            clr_alm_tgl  <= '0';
            clr_tick_tgl <= '0';
        elsif rising_edge(ClkMem) then
            if WEn(0) = '0' then
                if acc_s(SLOT_SEC) = '1' then
                    commit_mask <= "001";
                    wr_req_tgl  <= not wr_req_tgl;
                elsif acc_s(SLOT_ALM) = '1' then
                    commit_mask <= "010";
                    wr_req_tgl  <= not wr_req_tgl;
                elsif acc_s(SLOT_PER) = '1' then
                    commit_mask <= "100";
                    wr_req_tgl  <= not wr_req_tgl;
                elsif acc_s(SLOT_SR) = '1' then
                    -- W1C: writing a 1 clears; SYNC is read-only and ignored.
                    if wdata(RTCALMF_LSB)  = '1' then clr_alm_tgl  <= not clr_alm_tgl;  end if;
                    if wdata(RTCTICKF_LSB) = '1' then clr_tick_tgl <= not clr_tick_tgl; end if;
                end if;
            end if;
        end if;
    end process;

    /* ------------------------- clk (mclk ref) CDC -----------------------------
       Free-running clk hosts every LFXT-into-bus synchronizer plus the sticky flags, so ALMF/TICKF and irq_rtc set autonomously while the bus is idle.
       A metastable sample can only DELAY a flag or snapshot by one clk edge. */
    -- Read side: cap_tgl into clk, edge-detected in clk_cdc, then snap_lfxt is sampled into snap_sync.
    -- snap_lfxt settles about 1 lfxt period before its toggle crosses (data before flag), so the multi-bit sample is glitch-free.
    cap_sync_d(0) <= cap_tgl;
    u_sync_cap_tgl : entity work.sync
        generic map (WIDTH => 1, DEPTH => 2)
        port map (clk => clk, areset => resetn, d => cap_sync_d, q => cap_sync_q);
    cap_s2 <= cap_sync_q(0);

    -- Write handshake: the ack toggle into clk; sync_busy compares it against the raw wr_req_tgl.
    wrack_sync_d(0) <= wr_ack_tgl;
    u_sync_wr_ack_tgl : entity work.sync
        generic map (WIDTH => 1, DEPTH => 2)
        port map (clk => clk, areset => resetn, d => wrack_sync_d, q => wrack_sync_q);
    wrack_c2 <= wrack_sync_q(0);

    -- Event toggles from lfxt and W1C request toggles from ClkMem: four independent lines in one chain, each edge-detected in clk_cdc.
    evt_sync_d <= alm_tgl & tick_tgl & clr_alm_tgl & clr_tick_tgl;
    u_sync_evt_tgl : entity work.sync
        generic map (WIDTH => 4, DEPTH => 2)
        port map (clk => clk, areset => resetn, d => evt_sync_d, q => evt_sync_q);
    almt_c2  <= evt_sync_q(3);
    tickt_c2 <= evt_sync_q(2);
    clra_c2  <= evt_sync_q(1);
    clrt_c2  <= evt_sync_q(0);

    clk_cdc: process(resetn, clk)
    begin
        if resetn = '0' then
            cap_prev <= '0';
            snap_sync <= (others => '0');
            almt_prev <= '0';
            tickt_prev <= '0';
            clra_prev <= '0';
            clrt_prev <= '0';
            almf_flag <= '0'; tickf_flag <= '0';
        elsif rising_edge(clk) then
            cap_prev <= cap_s2;
            if cap_s2 /= cap_prev then
                snap_sync <= snap_lfxt;
            end if;

            -- Edge-detect flops for the four synchronized toggles.
            almt_prev  <= almt_c2;
            tickt_prev <= tickt_c2;
            clra_prev  <= clra_c2;
            clrt_prev  <= clrt_c2;

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
    rst_sync_d(0) <= '1';
    u_sync_rtc_lfxt_rstn : entity work.sync
        generic map (WIDTH => 1, DEPTH => 2)
        port map (clk => lfxt_in, areset => resetn, d => rst_sync_d, q => rst_sync_q);
    rtc_lfxt_rstn <= rst_sync_q(0);

    /* ------------------------- Bus into LFXT: enable held-level syncs ---------
       RTCEN/ALMEN/TICKEN cross as held levels, 2-FF synchronized on lfxt_in.
       They gate the D-input logic of the counter, compare and tick engines, never a clock. */
    en_sync_d <= rtcen_cr & almen_cr & ticken_cr;
    u_sync_en_cr : entity work.sync
        generic map (WIDTH => 3, DEPTH => 2)
        port map (clk => lfxt_in, areset => rtc_lfxt_rstn, d => en_sync_d, q => en_sync_q);
    rtcen_sync  <= en_sync_q(2);
    almen_sync  <= en_sync_q(1);
    ticken_sync <= en_sync_q(0);

    /* ------------------------- Bus into LFXT: write-commit apply --------------
       2-FF wr_req_tgl into lfxt, then edge-detect it to form wr_apply, a 1-lfxt pulse; wr_ack_tgl flips on that same edge to hand the acknowledge back.
       The wall-clock, alarm and tick engines co-sample wr_apply with the quasi-static commit_mask and stage_* to load atomically. */
    wrreq_sync_d(0) <= wr_req_tgl;
    u_sync_wr_req_tgl : entity work.sync
        generic map (WIDTH => 1, DEPTH => 2)
        port map (clk => lfxt_in, areset => rtc_lfxt_rstn, d => wrreq_sync_d, q => wrreq_sync_q);
    wrreq_s2 <= wrreq_sync_q(0);

    wrsync: process(rtc_lfxt_rstn, lfxt_in)
    begin
        if rtc_lfxt_rstn = '0' then
            wrreq_prev <= '0';
            wr_ack_tgl <= '0';
        elsif rising_edge(lfxt_in) then
            wrreq_prev <= wrreq_s2;
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
                nsec := regs_q(SLOT_SEC);             -- atomic set-time load (priority)
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
                alm_live <= regs_q(SLOT_ALM);
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
