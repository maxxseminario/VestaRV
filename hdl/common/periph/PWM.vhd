-- VestaRV: PWM generator
-- Buffered 2-channel generator with a software fault trip and a period-event tick: pwm_out(1 downto 0), irq_fault (vector 115), irq_evt (vector 116).
-- The engine (prescaler, counter, compare, output stage, sticky flags) runs on the free-running clk and the register file on the gated ClkMem. They are the same mclk net at integration, so every hand-off is a held level or a single-clock toggle and needs no synchronizer.
-- PER and the duty registers are buffered: a read returns the staging readback, a write stages the value and arms UPDF. POL and SAFE are immediate.
-- EnMemPeriph is an active-low level qualifier, never a clock and never an edge; the prescaler makes a tick enable, never a clock gate.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- Word slots, field ranges, resets and implemented-bit masks, and the periph_regs
-- tables the bus side is an instance of: generated from hdl/common/regs/rdl/pwm.rdl.
use work.pwm_regs_pkg.all;



entity PWM is
    port (
        clk         : in  std_logic;                     -- free-running engine clock (MCLK at integration)
        resetn      : in  std_logic;                     -- chip reset, active-low (async)
        irq_fault   : out std_logic;                     -- fault IRQ (vector 115)
        irq_evt     : out std_logic;                     -- period-event IRQ (vector 116)
        pwm_out     : out std_logic_vector(1 downto 0);  -- channel outputs
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW select/qualifier, never a clock
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0); -- bus write data
        rdata_out   : out std_logic_vector(31 downto 0); -- registered read data (ClkMem domain)

        -- Event-fabric taps: pre-mask SET conditions, NEVER the post-IE irq_* lines.
        -- The defaults keep instantiations without the fabric compiling unchanged.
        evt_period   : out std_logic;                    -- period-boundary event
        evt_fault    : out std_logic;                    -- FLTF set-condition event
        task_flttrig : in  std_logic := '0'              -- fabric force-trip, ORed into the FLTF SET term, still FLTEN-gated
    );
end PWM;

architecture behavioral of PWM is

    /* ---- register file (ClkMem domain) -----------------------------------
       The bus side is one work.periph_regs instance driven by pwm_regs_pkg's
       tables; see hdl/common/regs/REGFILE.md. The fourteen per-field flops this
       block used to keep are now the IMPL bits of four stored words -- PWMxCR,
       PWMxPER, PWMxDTY0/1 and PWMxPOL -- sliced back out below. PWMxSR holds no
       flop there: the engine owns FLTF, PEVF and UPDF and they reach the read
       mux through hw_rd; PWMxDTY2/3 and PWMxDT are reserved and read 0. */
    signal regs_q   : reg_arr_t;                         -- the stored words
    signal hw_rd_s  : reg_arr_t;                         -- read source for everything else
    signal acc_s    : std_logic_vector(0 to NWORDS-1);   -- combinational: this slot, now
    signal sr_rd    : std_logic_vector(31 downto 0);
    signal wr_stage : std_logic;                         -- a PER/DTY0/DTY1 write, this access

    -- Field taps out of the stored words, quasi-static.
    signal pwmen_r, ch0en_r, ch1en_r : std_logic;        -- CR.PWMEN/CH0EN/CH1EN
    signal pevie_r, fltie_r          : std_logic;        -- CR.PEVIE/FLTIE
    signal flten_r                   : std_logic;        -- CR.FLTEN
    signal psc_r        : std_logic_vector(3 downto 0);  -- CR.PSC
    signal stage_per    : std_logic_vector(15 downto 0); -- staging: period
    signal stage_dty0   : std_logic_vector(15 downto 0); -- staging: CH0 duty
    signal stage_dty1   : std_logic_vector(15 downto 0); -- staging: CH1 duty
    signal pol0_r, pol1_r   : std_logic;                 -- POL.POL0/POL1, immediate
    signal safe0_r, safe1_r : std_logic;                 -- POL.SAFE0/SAFE1, immediate

    -- Request toggles into the clk domain; these are all that is left of the
    -- old register-write process.
    signal upd_req_tgl  : std_logic;                     -- stage-write request toggle
    signal flt_req_tgl  : std_logic;                     -- FLTTRIG request toggle
    signal clr_flt_tgl  : std_logic;                     -- W1C FLTF request toggle
    signal clr_pev_tgl  : std_logic;                     -- W1C PEVF request toggle

    -- ---- prescaler (clk domain) -------------------------------------------
    signal psc_cnt  : std_logic_vector(14 downto 0);     -- 15-bit prescale counter
    signal psc_top  : std_logic_vector(14 downto 0);     -- 2^PSC - 1 (comb decode)
    signal psc_tick : std_logic;                         -- 1-clk tick enable (comb)

    -- ---- counter + shadow commit (clk domain) -----------------------------
    signal pwm_cnt        : std_logic_vector(15 downto 0); -- main up-counter
    signal per_active      : std_logic_vector(15 downto 0);-- active period modulus
    signal dty0_active     : std_logic_vector(15 downto 0);-- active CH0 duty
    signal dty1_active     : std_logic_vector(15 downto 0);-- active CH1 duty
    signal period_boundary : std_logic;                    -- comb: 1-clk wrap pulse

    -- ---- compare + output stage (clk domain) ------------------------------
    signal raw0, raw1               : std_logic;         -- registered raw waveform
    signal disabled0, disabled1     : std_logic;         -- comb disable/fault term
    signal active_drive0, active_drive1 : std_logic;     -- comb raw xor pol

    -- ---- sticky flags + edge-detect (clk domain) --------------------------
    signal upd_req_prev, flt_req_prev : std_logic;       -- single-clock edge-detect regs
    signal clr_flt_prev, clr_pev_prev : std_logic;       -- single-clock edge-detect regs
    signal upd_pending  : std_logic;                     -- SR.UPDF
    signal fltf_flag    : std_logic;                     -- SR.FLTF sticky
    signal flt_set      : std_logic;                     -- comb: the fault SET condition (FLTTRIG edge or fabric task, FLTEN-gated), also the fault event tap
    signal pevf_flag    : std_logic;                     -- SR.PEVF sticky

begin

    -- ------------------------- Signal Routing ---------------------------------
    -- Field taps out of the register file. The positions are pwm_regs_pkg's, so
    -- no bit literal in this file describes a register.
    pwmen_r  <= regs_q(SLOT_CR)(PWMEN_LSB);
    ch0en_r  <= regs_q(SLOT_CR)(CH0EN_LSB);
    ch1en_r  <= regs_q(SLOT_CR)(CH1EN_LSB);
    pevie_r  <= regs_q(SLOT_CR)(PEVIE_LSB);
    fltie_r  <= regs_q(SLOT_CR)(FLTIE_LSB);
    flten_r  <= regs_q(SLOT_CR)(FLTEN_LSB);
    psc_r    <= regs_q(SLOT_CR)(PSC_MSB downto PSC_LSB);
    stage_per  <= regs_q(SLOT_PER)(PWMPER_MSB downto PWMPER_LSB);
    stage_dty0 <= regs_q(SLOT_DTY0)(PWMDTY0_MSB downto PWMDTY0_LSB);
    stage_dty1 <= regs_q(SLOT_DTY1)(PWMDTY1_MSB downto PWMDTY1_LSB);
    pol0_r   <= regs_q(SLOT_POL)(POL0_LSB);
    pol1_r   <= regs_q(SLOT_POL)(POL1_LSB);
    safe0_r  <= regs_q(SLOT_POL)(SAFE0_LSB);
    safe1_r  <= regs_q(SLOT_POL)(SAFE1_LSB);

    -- Prescaler top: psc_top = 2^PSC - 1, decoded directly.
    -- No shifter or subtractor is needed because 2^PSC-1 is exactly PSC ones in the low bits.
    with psc_r select psc_top <=
        "000000000000000" when "0000",   -- /1     top=0
        "000000000000001" when "0001",   -- /2     top=1
        "000000000000011" when "0010",   -- /4     top=3
        "000000000000111" when "0011",   -- /8     top=7
        "000000000001111" when "0100",   -- /16
        "000000000011111" when "0101",   -- /32
        "000000000111111" when "0110",   -- /64
        "000000001111111" when "0111",   -- /128
        "000000011111111" when "1000",   -- /256
        "000000111111111" when "1001",   -- /512
        "000001111111111" when "1010",   -- /1024
        "000011111111111" when "1011",   -- /2048
        "000111111111111" when "1100",   -- /4096
        "001111111111111" when "1101",   -- /8192
        "011111111111111" when "1110",   -- /16384
        "111111111111111" when others;   -- /32768 ("1111")

    -- psc_tick: 1-clk ENABLE term, never a clock gate and never a generated clock.
    psc_tick <= '1' when (pwmen_r = '1' and psc_cnt = psc_top) else '0';

    -- Period boundary: the psc_tick at which pwm_cnt = per_active is the wrap.
    -- That is the ONE instant that commits staging and sets PEVF.
    period_boundary <= '1' when (psc_tick = '1' and pwmen_r = '1' and pwm_cnt = per_active) else '0';

    -- Output stage: combinational mux over registered/quasi-static levels.
    -- Gives a same-cycle safe override and stays xcollapse-safe, since it is not a clock.
    disabled0 <= '1' when (pwmen_r = '0' or ch0en_r = '0' or fltf_flag = '1') else '0';
    disabled1 <= '1' when (pwmen_r = '0' or ch1en_r = '0' or fltf_flag = '1') else '0';
    active_drive0 <= raw0 xor pol0_r;
    active_drive1 <= raw1 xor pol1_r;
    pwm_out(0) <= safe0_r when disabled0 = '1' else active_drive0;
    pwm_out(1) <= safe1_r when disabled1 = '1' else active_drive1;

    -- IRQs: status and enable, combinational, never latched.
    irq_fault <= fltf_flag and fltie_r;
    irq_evt   <= pevf_flag and pevie_r;

    -- Event-fabric producer taps: the SET conditions themselves, pre-IE.
    -- flt_set is both used by the flag process and exported, so a task-tripped fault fires the event exactly like a register-tripped one.
    flt_set <= '1' when (((flt_req_tgl /= flt_req_prev) or task_flttrig = '1')
                         and flten_r = '1') else '0';
    evt_period <= period_boundary;
    evt_fault  <= flt_set;

    /* ------------------------- register file (ClkMem) -------------------------
       One periph_regs instance replaces the case decode, the byte-lane merge,
       the reset branch and the registered read mux. PWMxPER/DTY0/DTY1 are the
       STAGING words: the module holds them and a read returns them, exactly as
       the staging flops did, and the engine commits them at the next period
       boundary.

       No WIDEWR and no RDTHRU. The decode this replaces already merged per byte
       lane (CR takes its enables from lane 0, FLTIE/FLTEN/FLTTRIG from lane 1
       and PSC from lane 2; PER and the duties take each half from its own lane),
       which is what the module does by default. STROBE_HOLD is immaterial and
       left false, because this block uses no registered strobe; see below. */
    hw_rd_s <= (SLOT_SR => sr_rd, others => (others => '0'));

    -- PWMxSR: FLTF, PEVF and UPDF are clk-domain levels, read raw. DIR (bit 3)
    -- is reserved and reads 0.
    sr_rd <= (31 downto UPDF_MSB + 1 => '0') & upd_pending & pevf_flag & fltf_flag;

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
            STROBE_HOLD => false)
        port map (
            ClkMem      => ClkMem,
            resetn      => resetn,
            EnMemPeriph => EnMemPeriph,
            WEn         => WEn,
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

    /* A write to any of the three buffered waveform words, this access.

       Every hook below takes the COMBINATIONAL acc_hit and not the module's
       registered wr_strobe / wr_pulse / w1c_hit, and the reason is the gated bus
       clock: ClkMem is gated by EnMemPeriph here, so one bus access presents
       exactly ONE rising ClkMem edge and the next edge belongs to the NEXT
       access. A strobe flop SET on the access edge is therefore sampled a whole
       bus access late by a ClkMem-synchronous consumer, and STROBE_HOLD = true
       only retires it asynchronously at deselect, before any edge can see it at
       all. acc_hit reproduces the old decode's condition exactly and the request
       toggles flip on the edge the write does. */
    wr_stage <= '1' when ((acc_s(SLOT_PER) = '1' or acc_s(SLOT_DTY0) = '1'
                           or acc_s(SLOT_DTY1) = '1')
                          and (WEn(0) = '0' or WEn(1) = '0')) else '0';

    /* ------------------------- request toggles (ClkMem) -----------------------
       What is left of the old register-write process: the UPDF arm, the
       FLTTRIG self-clearing trip command (PWMxCR.FLTTRIG is `singlepulse`, so it
       stores nothing and is not in IMPL) and the two SR write-1-to-clear arms.
       The FLTEN gate stays in the clk domain, not at the write. */
    reg_req: process(resetn, ClkMem)
    begin
        if resetn = '0' then
            upd_req_tgl <= '0';
            flt_req_tgl <= '0';
            clr_flt_tgl <= '0';
            clr_pev_tgl <= '0';
        elsif rising_edge(ClkMem) then
            if wr_stage = '1' then
                upd_req_tgl <= not upd_req_tgl;           -- arm UPDF
            end if;
            if acc_s(SLOT_CR) = '1' and WEn(1) = '0'
               and wdata(FLTTRIG_LSB) = '1' then
                flt_req_tgl <= not flt_req_tgl;           -- self-clearing trip command
            end if;
            if acc_s(SLOT_SR) = '1' and WEn(0) = '0' then
                -- W1C: UPDF (bit 2) and DIR (bit 3) are read-only, ignored.
                if wdata(FLTF_LSB) = '1' then clr_flt_tgl <= not clr_flt_tgl; end if;
                if wdata(PEVF_LSB) = '1' then clr_pev_tgl <= not clr_pev_tgl; end if;
            end if;
        end if;
    end process reg_req;

    /* ------------------------- prescaler (clk) --------------------------------
       Free-running 15-bit counter-compare, reloading on PWMEN=0 (clean restart) or on reaching psc_top.
       NOT a clock gate and not a generated clock. */
    prescaler: process(resetn, clk)
    begin
        if resetn = '0' then
            psc_cnt <= (others => '0');
        elsif rising_edge(clk) then
            if pwmen_r = '0' then
                psc_cnt <= (others => '0');
            elsif psc_cnt = psc_top then
                psc_cnt <= (others => '0');
            else
                psc_cnt <= psc_cnt + 1;
            end if;
        end if;
    end process;

    /* ------------------------- counter + shadow commit (clk) ------------------
       16-bit edge-aligned up-counter advancing on psc_tick, wrapping at per_active (period_boundary).
       Every boundary copies the staging regs into the active regs unconditionally; that idempotent commit is the glitch-free guarantee. */
    counter_commit: process(resetn, clk)
    begin
        if resetn = '0' then
            pwm_cnt     <= (others => '0');
            per_active  <= (others => '0');
            dty0_active <= (others => '0');
            dty1_active <= (others => '0');
        elsif rising_edge(clk) then
            if pwmen_r = '0' then
                pwm_cnt <= (others => '0');            -- clean restart on enable
            elsif psc_tick = '1' then
                if pwm_cnt = per_active then
                    pwm_cnt <= (others => '0');         -- period wrap
                else
                    pwm_cnt <= pwm_cnt + 1;
                end if;
            end if;

            -- Shadow commit: idempotent, so a boundary with no pending write is harmless.
            if period_boundary = '1' then
                per_active  <= stage_per;
                dty0_active <= stage_dty0;
                dty1_active <= stage_dty1;
            end if;
        end if;
    end process;

    /* ------------------------- compare stage (clk) ----------------------------
       Registered raw waveform updated only on psc_tick (a bare combinational compare would emit runts), compared against the NEXT count so the high run occupies exactly ticks 0 to dty-1 and the corners duty=0, duty at or above per+1 and period=0 need no special-casing.
       At a boundary the duty source is the staging register, so a new duty is visible from the first tick of the new period, never one period late and never mid-period. */
    compare_stage: process(resetn, clk)
        variable next_cnt : std_logic_vector(15 downto 0);
        variable d0, d1   : std_logic_vector(15 downto 0);
    begin
        if resetn = '0' then
            raw0 <= '0';
            raw1 <= '0';
        elsif rising_edge(clk) then
            if pwmen_r = '0' then
                raw0 <= '0';
                raw1 <= '0';
            elsif psc_tick = '1' then
                if pwm_cnt = per_active then
                    next_cnt := (others => '0');       -- wrap: first tick of new period
                else
                    next_cnt := pwm_cnt + 1;
                end if;
                if period_boundary = '1' then
                    d0 := stage_dty0;                  -- boundary: committed duty
                    d1 := stage_dty1;
                else
                    d0 := dty0_active;
                    d1 := dty1_active;
                end if;
                if next_cnt < d0 then raw0 <= '1'; else raw0 <= '0'; end if;
                if next_cnt < d1 then raw1 <= '1'; else raw1 <= '0'; end if;
            end if;
        end if;
    end process;

    /* ------------------------- sticky flags (clk) -----------------------------
       Single-clock edge-detect on the request toggles: one clock family, so a previous-value register is sufficient and no 2-FF sync is needed.
       SET wins over a coincident CLEAR on every sticky flag. */
    flags: process(resetn, clk)
    begin
        if resetn = '0' then
            upd_req_prev <= '0'; flt_req_prev <= '0';
            clr_flt_prev <= '0'; clr_pev_prev <= '0';
            upd_pending  <= '0';
            fltf_flag    <= '0';
            pevf_flag    <= '0';
        elsif rising_edge(clk) then
            upd_req_prev <= upd_req_tgl;
            flt_req_prev <= flt_req_tgl;
            clr_flt_prev <= clr_flt_tgl;
            clr_pev_prev <= clr_pev_tgl;

            -- SR.UPDF: SET on a staged write, CLEAR at the boundary.
            if upd_req_tgl /= upd_req_prev then
                upd_pending <= '1';
            elsif period_boundary = '1' then
                upd_pending <= '0';
            end if;

            -- SR.FLTF: SET on flt_set (FLTTRIG edge or fabric task, FLTEN-gated here in the clk domain), CLEAR on the W1C edge.
            if flt_set = '1' then
                fltf_flag <= '1';
            elsif clr_flt_tgl /= clr_flt_prev then
                fltf_flag <= '0';
            end if;

            -- SR.PEVF: SET at every active period boundary, CLEAR on the W1C edge.
            if period_boundary = '1' then
                pevf_flag <= '1';
            elsif clr_pev_tgl /= clr_pev_prev then
                pevf_flag <= '0';
            end if;
        end if;
    end process;

end behavioral;

