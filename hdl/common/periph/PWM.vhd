library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ===========================================================================
-- PWM: buffered PWM generator -- 2 channels (CH0/CH1), software/mask-only
-- fault, period-event tick. Two lean IRQs: irq_fault (vector 115), irq_evt
-- (vector 116). Zero pins -- pwm_out(1 downto 0) rides the AF spread (D20/A7,
-- a chipgen matter only; this entity is unaffected). FROZEN design:
-- ~/vesta_docs/digperiphs/pwm_design.md (decisions D1-D21, orchestrator
-- adjudications A1-A7 -- ALL BINDING; A-rulings override any conflicting Dn
-- prose). Peripheral #5 of the digital-peripherals program, following the
-- RTC precedent (register-file/W1C/sticky-flag shape).
-- -V200X only: NO VHDL-2008 (no to_hstring, no process(all), no unary
-- reduce, no reading of out ports). Every process infers exactly ONE edge of
-- ONE clock (Genus VHDL-601 discipline).
--
-- D1 -- Single free-running engine clock = clk (MCLK at integration); the
-- register file is on ClkMem. At integration clk and ClkMem are the SAME
-- physical mclk net (RTC A2 precedent) -- ONE clock family, so unlike the RTC
-- (a real LFXT domain) this block has NO metastability CDC at all. The
-- prescaler/counter/shadow-commit/comparators/output stage/sticky flags/IRQ
-- combiner live on clk (must run autonomously while the bus is idle); the
-- register file (staging writes, CR, POL, SR read mux, request toggles)
-- lives on ClkMem (gated -- edges only during an access).
--
-- D4 -- NO falling_edge OF ANYTHING (and specifically NO
-- falling_edge(EnMemPeriph)). EnMemPeriph is consumed ONLY as an active-low
-- LEVEL qualifier sampled on rising ClkMem (address decode + write-enable +
-- read-mux gate) -- never a clock, never an edge. PWM has NO EnMemPeriph
-- clock in its SDC and needs neither a combinational-read bridge nor a
-- CAPTURE_CLOCK registered-strobe shim: it registers reads on rising ClkMem
-- over data already in the mclk domain (staging readback + clk-domain
-- flags). The TIMER compare_process unbuffered-compare + reg_sync
-- falling_edge(en_mem) latch is the ANTI-PATTERN this block explicitly
-- rejects (D9 buffers every waveform write instead).
--
-- D6 -- The prescaler is a counter-compare producing a 1-clk TICK ENABLE
-- (psc_tick), NEVER a clock gate and NEVER a generated/divided clock -- the
-- main counter, comparators, and output stage all stay on the single
-- free-running clk, gated only by psc_tick as an ENABLE TERM in D-input
-- logic (RTC/QSPI discipline; explicitly NOT the TIMER ClkGate /
-- ClockMuxGlitchFree path). No clock gates anywhere in this block.
--
-- ------------------------------------------------------------------------
-- DOMAIN MAP (two clocks, both async groups in the SDC; no generated
-- clocks, no lfxt):
--   * clk -- free-running MCLK at integration (D1). Hosts B2 prescaler, B3
--     main counter + shadow->active commit, B4 registered compare + output
--     mux, B5 fault trip + sticky FLTF, B6 sticky PEVF + IRQ combiner. Must
--     free-run so the counter/PEVF/FLTF advance while the bus is idle.
--     Reset via resetn (async, direct -- no reset synchronizer, D15: single
--     clock family, no always-on LFXT domain to protect against).
--   * ClkMem -- GATED bus clock (edges only during an access). Hosts B1:
--     CR, POL (immediate, D11), the PER/DTY0/DTY1 staging regs, and the D2
--     request/clear toggles. Reset via resetn.
--   Because clk and ClkMem are the SAME mclk net at integration (D1), every
--   hand-off below is a REGISTERED level or a single-clock toggle -- kept as
--   clean toggles/held-levels purely for standalone-honesty (single-writer
--   per flag, no glitchy decode, correct even if a block-level bench skews
--   clk vs ClkMem) -- and needs NO 2-FF metastability synchronizer (contrast
--   the RTC's genuine LFXT<->clk crossings).
--
-- CDC / HAND-OFF INVENTORY (the ONLY crossing paths, D2; toggle or held/
-- quasi-static level, single-clock edge-detect, no 2-FF sync, no async FIFO,
-- no async clear crossing a domain):
--   1. Staging -> engine (ClkMem->clk, D9): stage_per/stage_dty0/stage_dty1
--      are held quasi-static levels, sampled by the engine ONLY at the
--      period boundary. False-path / quasi-static.
--   2. CR/POL config (ClkMem->clk): pwmen_r, ch0en_r, ch1en_r, psc_r,
--      flten_r, fltie_r, pevie_r, and the POL pol0_r/pol1_r/safe0_r/safe1_r
--      bits are held quasi-static levels feeding the engine D-logic and the
--      B4 output mux directly (no synchronizer needed -- same clock family).
--   3. Update-pending (ClkMem->clk, D9): each buffered write to PER/DTY0/
--      DTY1 flips upd_req_tgl; the clk domain single-edge-detects the
--      toggle to SET the sticky upd_pending, and CLEARS it at the period
--      boundary in the SAME clk process that owns it (SET wins over CLEAR).
--   4. Fault trigger (ClkMem->clk, D12): a CR[14] FLTTRIG write-1 flips
--      flt_req_tgl (unconditionally -- the write itself is unqualified by
--      FLTEN); the clk domain edge-detects it and sets sticky fltf_flag
--      ONLY if flten_r='1' AT THAT EDGE (the FLTEN gate lives in the clk
--      domain per D2.4, not at the write).
--   5. W1C clears (ClkMem->clk, D2/D14): a lane-0 write of 1 to SR.FLTF/
--      SR.PEVF flips clr_flt_tgl/clr_pev_tgl; the clk domain edge-detects
--      each and CLEARS the owning flag in the SAME process that sets it (no
--      clear-pulse touches the flag from ClkMem). SET wins over a coincident
--      CLEAR.
--   6. Flags/status -> read mux (clk->ClkMem, D2.6): fltf_flag, pevf_flag,
--      upd_pending are clk-domain registered levels read directly by the
--      ClkMem read mux (B1). Held levels.
--   7. IRQs (clk, combinational, D18): irq_fault = fltf_flag and fltie_r;
--      irq_evt = pevf_flag and pevie_r -- never latched.
--
-- Register map (D5; base 0x6600, slot n @ 0x6600 + 4n, decoded off
-- MABPart(7:2)):
--   0 PWM0CR   : [0]PWMEN [1]CH0EN [2]CH1EN [3]CH2EN(rsvd) [4]CH3EN(rsvd)
--                [5]CNTMODE(rsvd) [6]DTEN(rsvd) [7]PEVIE [8]FLTIE
--                [11:9]rsvd [12]FLTEN [13]FLTPOL(rsvd) [14]FLTTRIG(w1,
--                self-clearing command, reads 0) [15]rsvd [19:16]PSC
--                [31:20]rsvd.
--   1 PWM0PER  : [15:0] period modulus, BUFFERED (D9); rd = staging
--                readback; wr = stage + arm UPDF.
--   2 PWM0DTY0 : [15:0] CH0 duty, BUFFERED (D9); rd/wr as PER.
--   3 PWM0DTY1 : [15:0] CH1 duty, BUFFERED (D9); rd/wr as PER.
--   4 PWM0DTY2 : reserved (4-ch bolt-on, D16) -- reads 0, writes ignored.
--   5 PWM0DTY3 : reserved (4-ch bolt-on, D16) -- reads 0, writes ignored.
--   6 PWM0POL  : [0]POL0 [1]POL1 [3:2]rsvd [4]SAFE0 [5]SAFE1 [7:6]rsvd
--                [31:8]rsvd. Immediate, NOT buffered (D11).
--   7 PWM0DT   : reserved (deadtime bolt-on, D16) -- reads 0, writes
--                ignored.
--   8 PWM0SR   : [0]FLTF W1C [1]PEVF W1C [2]UPDF ro [3]DIR(rsvd) ro
--                [31:4]rsvd. Slots >=9 read 0.
-- ===========================================================================

entity PWM is
    port (
        clk         : in  std_logic;                     -- free-running MCLK at integration
                                                         -- (D1: prescaler/counter/compare/
                                                         -- output/flags/IRQ engine)
        resetn      : in  std_logic;                     -- chip reset, active-low (async)
        irq_fault   : out std_logic;                     -- fault IRQ (vector 115)
        irq_evt     : out std_logic;                     -- period-event IRQ (vector 116)
        pwm_out     : out std_logic_vector(1 downto 0);  -- channel outputs (AF-spread pins, D20)
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW select/qualifier (D4:
                                                         -- NEVER a clock)
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0)
    );
end PWM;

architecture behavioral of PWM is

    -- ---- word-slot map (frozen, D5) --------------------------------------
    constant SLOT_CR   : natural := 0;
    constant SLOT_PER  : natural := 1;
    constant SLOT_DTY0 : natural := 2;
    constant SLOT_DTY1 : natural := 3;
    constant SLOT_DTY2 : natural := 4;   -- reserved (4-ch bolt-on, D16)
    constant SLOT_DTY3 : natural := 5;   -- reserved (4-ch bolt-on, D16)
    constant SLOT_POL  : natural := 6;
    constant SLOT_DT   : natural := 7;   -- reserved (deadtime bolt-on, D16)
    constant SLOT_SR   : natural := 8;

    -- ---- B1 register-file storage (ClkMem domain) ------------------------
    signal pwmen_r, ch0en_r, ch1en_r : std_logic;        -- CR[2:0]
    signal pevie_r, fltie_r          : std_logic;        -- CR[7],CR[8]
    signal flten_r                   : std_logic;        -- CR[12]
    signal psc_r        : std_logic_vector(3 downto 0);  -- CR[19:16]
    signal upd_req_tgl  : std_logic;                     -- D2.3 stage-write request toggle
    signal flt_req_tgl  : std_logic;                     -- D2.4 FLTTRIG request toggle
    signal clr_flt_tgl  : std_logic;                     -- D2.5 W1C FLTF request toggle
    signal clr_pev_tgl  : std_logic;                     -- D2.5 W1C PEVF request toggle
    signal stage_per    : std_logic_vector(15 downto 0); -- D9 staging: period
    signal stage_dty0   : std_logic_vector(15 downto 0); -- D9 staging: CH0 duty
    signal stage_dty1   : std_logic_vector(15 downto 0); -- D9 staging: CH1 duty
    signal pol0_r, pol1_r   : std_logic;                 -- POL[1:0], immediate (D11)
    signal safe0_r, safe1_r : std_logic;                 -- POL[5:4], immediate (D11)
    signal pwm_slot     : natural range 0 to 63;         -- decoded word slot

    -- ---- B2 prescaler (clk domain, D6) ------------------------------------
    signal psc_cnt  : std_logic_vector(14 downto 0);     -- 15-bit prescale counter
    signal psc_top  : std_logic_vector(14 downto 0);     -- 2^PSC - 1 (comb decode)
    signal psc_tick : std_logic;                         -- 1-clk tick enable (comb)

    -- ---- B3 counter + shadow commit (clk domain, D7/D9) -------------------
    signal pwm_cnt        : std_logic_vector(15 downto 0); -- main up-counter
    signal per_active      : std_logic_vector(15 downto 0);-- active period modulus
    signal dty0_active     : std_logic_vector(15 downto 0);-- active CH0 duty
    signal dty1_active     : std_logic_vector(15 downto 0);-- active CH1 duty
    signal period_boundary : std_logic;                    -- comb: 1-clk wrap pulse

    -- ---- B4 compare + output stage (clk domain, D8) -----------------------
    signal raw0, raw1               : std_logic;         -- registered raw waveform
    signal disabled0, disabled1     : std_logic;         -- comb disable/fault term
    signal active_drive0, active_drive1 : std_logic;     -- comb raw xor pol

    -- ---- B5/B6 sticky flags + edge-detect (clk domain, D12/D13/D14) -------
    signal upd_req_prev, flt_req_prev : std_logic;       -- single-clock edge-detect regs
    signal clr_flt_prev, clr_pev_prev : std_logic;       -- single-clock edge-detect regs
    signal upd_pending  : std_logic;                     -- SR.UPDF
    signal fltf_flag    : std_logic;                     -- SR.FLTF sticky
    signal pevf_flag    : std_logic;                     -- SR.PEVF sticky

begin

    -- ------------------------- Signal Routing ---------------------------------
    -- slot decode (EnMemPeriph-qualified LEVEL, D4; never an edge).
    pwm_slot <= conv_integer(MABPart) when EnMemPeriph = '0' else 0;

    -- B2 prescaler: psc_top = 2^PSC - 1, decoded directly (no shifter/subtractor
    -- needed -- 2^PSC-1 is exactly PSC ones in the low bits). D6.
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

    -- psc_tick: 1-clk ENABLE term (D6) -- never a clock gate, never generated.
    psc_tick <= '1' when (pwmen_r = '1' and psc_cnt = psc_top) else '0';

    -- period boundary (D7/D9): the psc_tick at which pwm_cnt = per_active is the
    -- wrap -- the ONE instant that commits staging and sets PEVF.
    period_boundary <= '1' when (psc_tick = '1' and pwmen_r = '1' and pwm_cnt = per_active) else '0';

    -- B4 output stage (D8): combinational mux over registered/quasi-static
    -- levels -- same-cycle safe override, xcollapse-safe (not a clock).
    disabled0 <= '1' when (pwmen_r = '0' or ch0en_r = '0' or fltf_flag = '1') else '0';
    disabled1 <= '1' when (pwmen_r = '0' or ch1en_r = '0' or fltf_flag = '1') else '0';
    active_drive0 <= raw0 xor pol0_r;
    active_drive1 <= raw1 xor pol1_r;
    pwm_out(0) <= safe0_r when disabled0 = '1' else active_drive0;
    pwm_out(1) <= safe1_r when disabled1 = '1' else active_drive1;

    -- IRQs (D18): (status and enable), combinational, never latched.
    irq_fault <= fltf_flag and fltie_r;
    irq_evt   <= pevf_flag and pevie_r;

    -- ------------------------- B1: register write (ClkMem) --------------------
    -- Rising ClkMem, EnMemPeriph='0' qualified, per-byte-lane WEn (D4). Buffered
    -- waveform writes (PER/DTY0/DTY1) stage + arm upd_req_tgl (D9); FLTTRIG
    -- (CR[14]) is an unqualified write-1 self-clearing command that flips
    -- flt_req_tgl (the FLTEN gate is applied in the clk domain, D2.4); SR
    -- lane-0 writes of 1 to FLTF/PEVF flip the W1C clear toggles (D2.5). POL is
    -- immediate (D11) -- no toggle. Reset via resetn (bus domain).
    reg_write: process(resetn, ClkMem)
    begin
        if resetn = '0' then
            pwmen_r <= '0'; ch0en_r <= '0'; ch1en_r <= '0';
            pevie_r <= '0'; fltie_r <= '0'; flten_r <= '0';
            psc_r   <= (others => '0');
            upd_req_tgl <= '0';
            flt_req_tgl <= '0';
            clr_flt_tgl <= '0';
            clr_pev_tgl <= '0';
            stage_per  <= (others => '0');
            stage_dty0 <= (others => '0');
            stage_dty1 <= (others => '0');
            pol0_r <= '0'; pol1_r <= '0';
            safe0_r <= '0'; safe1_r <= '0';
        elsif rising_edge(ClkMem) then
            if EnMemPeriph = '0' then
                case pwm_slot is
                    when SLOT_CR =>
                        if WEn(0) = '0' then
                            pwmen_r <= wdata(0);
                            ch0en_r <= wdata(1);
                            ch1en_r <= wdata(2);
                            pevie_r <= wdata(7);
                        end if;
                        if WEn(1) = '0' then
                            fltie_r <= wdata(8);
                            flten_r <= wdata(12);
                            if wdata(14) = '1' then
                                flt_req_tgl <= not flt_req_tgl;   -- self-clearing trip command
                            end if;
                        end if;
                        if WEn(2) = '0' then
                            psc_r <= wdata(19 downto 16);
                        end if;
                    when SLOT_PER =>
                        if WEn(0) = '0' then
                            stage_per(7 downto 0) <= wdata(7 downto 0);
                        end if;
                        if WEn(1) = '0' then
                            stage_per(15 downto 8) <= wdata(15 downto 8);
                        end if;
                        if WEn(0) = '0' or WEn(1) = '0' then
                            upd_req_tgl <= not upd_req_tgl;       -- arm UPDF (D9)
                        end if;
                    when SLOT_DTY0 =>
                        if WEn(0) = '0' then
                            stage_dty0(7 downto 0) <= wdata(7 downto 0);
                        end if;
                        if WEn(1) = '0' then
                            stage_dty0(15 downto 8) <= wdata(15 downto 8);
                        end if;
                        if WEn(0) = '0' or WEn(1) = '0' then
                            upd_req_tgl <= not upd_req_tgl;
                        end if;
                    when SLOT_DTY1 =>
                        if WEn(0) = '0' then
                            stage_dty1(7 downto 0) <= wdata(7 downto 0);
                        end if;
                        if WEn(1) = '0' then
                            stage_dty1(15 downto 8) <= wdata(15 downto 8);
                        end if;
                        if WEn(0) = '0' or WEn(1) = '0' then
                            upd_req_tgl <= not upd_req_tgl;
                        end if;
                    when SLOT_POL =>
                        if WEn(0) = '0' then
                            pol0_r  <= wdata(0);
                            pol1_r  <= wdata(1);
                            safe0_r <= wdata(4);
                            safe1_r <= wdata(5);
                        end if;
                    when SLOT_SR =>
                        -- W1C: writing 1 clears; UPDF/DIR (bits 2/3) are read-only, ignored.
                        if WEn(0) = '0' then
                            if wdata(0) = '1' then clr_flt_tgl <= not clr_flt_tgl; end if;
                            if wdata(1) = '1' then clr_pev_tgl <= not clr_pev_tgl; end if;
                        end if;
                    when others =>
                        null;   -- DTY2/DTY3/DT (slots 4/5/7) writes ignored (D16);
                                -- slots >=9 no effect
                end case;
            end if;
        end if;
    end process;

    -- ------------------------- B1: register read (ClkMem) ---------------------
    -- Registered read mux on rising ClkMem over data ALREADY in the mclk domain
    -- (staging readback, clk-domain sticky flags/upd_pending) -- no pre-latch,
    -- no bridge (D4). Reserved slots/bits and slots >=9 read 0.
    reg_read: process(ClkMem)
    begin
        if rising_edge(ClkMem) then
            case pwm_slot is
                when SLOT_CR =>
                    rdata_out <= (31 downto 20 => '0') & psc_r & '0' & '0' & '0' & flten_r
                                 & "000" & fltie_r & pevie_r & '0' & '0' & '0' & '0'
                                 & ch1en_r & ch0en_r & pwmen_r;
                when SLOT_PER =>
                    rdata_out <= (31 downto 16 => '0') & stage_per;
                when SLOT_DTY0 =>
                    rdata_out <= (31 downto 16 => '0') & stage_dty0;
                when SLOT_DTY1 =>
                    rdata_out <= (31 downto 16 => '0') & stage_dty1;
                when SLOT_POL =>
                    rdata_out <= (31 downto 8 => '0') & '0' & '0' & safe1_r & safe0_r
                                 & '0' & '0' & pol1_r & pol0_r;
                when SLOT_SR =>
                    rdata_out <= (31 downto 4 => '0') & '0' & upd_pending & pevf_flag & fltf_flag;
                when others =>
                    rdata_out <= (others => '0');   -- DTY2/DTY3/DT and slots >=9 read 0
            end case;
        end if;
    end process;

    -- ------------------------- B2: prescaler (clk, D6) -------------------------
    -- Free-running 15-bit counter-compare; reload on PWMEN=0 (clean restart) or
    -- on reaching psc_top. NOT a clock gate/generated clock.
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

    -- ------------------------- B3: counter + shadow commit (clk, D7/D9) --------
    -- 16-bit edge-aligned up-counter, advancing on psc_tick; wraps at per_active
    -- (period_boundary). At EVERY boundary, copy the staging regs into the active
    -- regs unconditionally (idempotent, A6) -- the glitch-free guarantee (D9).
    counter_commit: process(resetn, clk)
    begin
        if resetn = '0' then
            pwm_cnt     <= (others => '0');
            per_active  <= (others => '0');
            dty0_active <= (others => '0');
            dty1_active <= (others => '0');
        elsif rising_edge(clk) then
            if pwmen_r = '0' then
                pwm_cnt <= (others => '0');            -- clean restart on enable (D7)
            elsif psc_tick = '1' then
                if pwm_cnt = per_active then
                    pwm_cnt <= (others => '0');         -- period wrap
                else
                    pwm_cnt <= pwm_cnt + 1;
                end if;
            end if;

            if period_boundary = '1' then
                per_active  <= stage_per;
                dty0_active <= stage_dty0;
                dty1_active <= stage_dty1;
            end if;
        end if;
    end process;

    -- ------------------------- B4: compare stage (clk, D8) ---------------------
    -- Registered raw waveform, updated only on psc_tick (never a bare
    -- combinational compare -- the TIMER runt hazard this block rejects).
    -- D8 ALIGNMENT (orchestrator adjudication after the first bench run): raw is
    -- computed against the NEXT count (post-increment/wrap), so the high run
    -- occupies EXACTLY ticks 0..dty-1 of the period per D8's letter -- not one
    -- tick late as a pre-increment compare gives. At a period boundary the duty
    -- source is the STAGING register (the commit is idempotent, A6, so staged ==
    -- the value being committed) -- the new duty is visible from the very first
    -- tick of the new period, never one period late and never mid-period (D9).
    -- D10 corners (duty=0 / duty>=per+1 / period=0) still fall out with no
    -- special-casing.
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
                    d0 := stage_dty0;                  -- boundary: committed duty (A6)
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

    -- ------------------------- B5/B6: sticky flags (clk, D12/D13/D14) ----------
    -- Single-clock edge-detect (no 2-FF sync -- D2: one clock family, so a
    -- previous-value register is sufficient, unlike the RTC's genuine LFXT<->clk
    -- crossings). SET wins over a coincident CLEAR on every sticky flag.
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

            -- SR.UPDF (D9/D2.3): SET on a staged write, CLEAR at the boundary.
            if upd_req_tgl /= upd_req_prev then
                upd_pending <= '1';
            elsif period_boundary = '1' then
                upd_pending <= '0';
            end if;

            -- SR.FLTF (D12/D14): SET on a FLTTRIG edge gated by flten_r (the FLTEN
            -- gate lives HERE, in the clk domain, D2.4); CLEAR on the W1C edge.
            if (flt_req_tgl /= flt_req_prev) and flten_r = '1' then
                fltf_flag <= '1';
            elsif clr_flt_tgl /= clr_flt_prev then
                fltf_flag <= '0';
            end if;

            -- SR.PEVF (D13/D14): SET at every active period boundary; CLEAR on the
            -- W1C edge.
            if period_boundary = '1' then
                pevf_flag <= '1';
            elsif clr_pev_tgl /= clr_pev_prev then
                pevf_flag <= '0';
            end if;
        end if;
    end process;

end behavioral;

