library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

/* PWM: buffered 2-channel generator with a software fault trip and a period-event tick.
   Interface: pwm_out(1 downto 0) channel outputs, irq_fault (vector 115), irq_evt (vector 116).
   The engine (prescaler, counter, compare, output stage, sticky flags) runs on the free-running clk; the register file runs on the gated bus clock ClkMem.
   clk and ClkMem are the same mclk net at integration, so every hand-off is a held level or a single-clock toggle and needs no 2-FF synchronizer.
   EnMemPeriph is an active-low level qualifier only, never a clock and never an edge; the prescaler makes a tick enable, never a clock gate. */

/* Register map (base 0x6600, slot n at 0x6600 + 4n, decoded off MABPart(7:2)):
     0 PWM0CR   : [0]PWMEN [1]CH0EN [2]CH1EN [7]PEVIE [8]FLTIE [12]FLTEN
                  [14]FLTTRIG (w1, self-clearing command, reads 0) [19:16]PSC;
                  all other bits reserved.
     1 PWM0PER  : [15:0] period modulus, BUFFERED; read returns the staging
                  readback, write stages the value and arms UPDF.
     2 PWM0DTY0 : [15:0] CH0 duty, BUFFERED; read/write as PER.
     3 PWM0DTY1 : [15:0] CH1 duty, BUFFERED; read/write as PER.
     4 PWM0DTY2 : reserved (4-channel bolt-on): reads 0, writes ignored.
     5 PWM0DTY3 : reserved (4-channel bolt-on): reads 0, writes ignored.
     6 PWM0POL  : [0]POL0 [1]POL1 [4]SAFE0 [5]SAFE1, immediate, NOT buffered.
     7 PWM0DT   : reserved (deadtime bolt-on): reads 0, writes ignored.
     8 PWM0SR   : [0]FLTF W1C [1]PEVF W1C [2]UPDF ro. Slots 9 and above read 0. */

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

    -- ---- word-slot map ---------------------------------------------------
    constant SLOT_CR   : natural := 0;
    constant SLOT_PER  : natural := 1;
    constant SLOT_DTY0 : natural := 2;
    constant SLOT_DTY1 : natural := 3;
    constant SLOT_DTY2 : natural := 4;   -- reserved (4-channel bolt-on)
    constant SLOT_DTY3 : natural := 5;   -- reserved (4-channel bolt-on)
    constant SLOT_POL  : natural := 6;
    constant SLOT_DT   : natural := 7;   -- reserved (deadtime bolt-on)
    constant SLOT_SR   : natural := 8;

    -- ---- register-file storage (ClkMem domain) ---------------------------
    signal pwmen_r, ch0en_r, ch1en_r : std_logic;        -- CR[2:0]
    signal pevie_r, fltie_r          : std_logic;        -- CR[7],CR[8]
    signal flten_r                   : std_logic;        -- CR[12]
    signal psc_r        : std_logic_vector(3 downto 0);  -- CR[19:16]
    signal upd_req_tgl  : std_logic;                     -- stage-write request toggle
    signal flt_req_tgl  : std_logic;                     -- FLTTRIG request toggle
    signal clr_flt_tgl  : std_logic;                     -- W1C FLTF request toggle
    signal clr_pev_tgl  : std_logic;                     -- W1C PEVF request toggle
    signal stage_per    : std_logic_vector(15 downto 0); -- staging: period
    signal stage_dty0   : std_logic_vector(15 downto 0); -- staging: CH0 duty
    signal stage_dty1   : std_logic_vector(15 downto 0); -- staging: CH1 duty
    signal pol0_r, pol1_r   : std_logic;                 -- POL[1:0], immediate
    signal safe0_r, safe1_r : std_logic;                 -- POL[5:4], immediate
    signal pwm_slot     : natural range 0 to 63;         -- decoded word slot

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
    -- slot decode: EnMemPeriph-qualified level, never an edge.
    pwm_slot <= conv_integer(MABPart) when EnMemPeriph = '0' else 0;

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

    /* ------------------------- register write (ClkMem) ------------------------
       Rising ClkMem, qualified by EnMemPeriph='0', per byte lane via WEn: buffered waveform writes (PER/DTY0/DTY1) only stage the value and arm upd_req_tgl, while POL is immediate.
       FLTTRIG (CR[14]) and the SR W1C bits flip request toggles; the FLTEN gate is applied in the clk domain, not at the write. */
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
                        -- Control: enables and IE bits in lane 0/1, prescale in lane 2.
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
                        -- Period modulus: staged only, committed at the next boundary.
                        if WEn(0) = '0' then
                            stage_per(7 downto 0) <= wdata(7 downto 0);
                        end if;
                        if WEn(1) = '0' then
                            stage_per(15 downto 8) <= wdata(15 downto 8);
                        end if;
                        if WEn(0) = '0' or WEn(1) = '0' then
                            upd_req_tgl <= not upd_req_tgl;       -- arm UPDF
                        end if;
                    when SLOT_DTY0 =>
                        -- CH0 duty: staged like PER, same UPDF arming.
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
                        -- CH1 duty: staged like PER, same UPDF arming.
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
                        -- Polarity and safe-state bits: immediate, never staged.
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
                        null;   -- reserved slots 4/5/7 and slots 9 and above: writes ignored
                end case;
            end if;
        end if;
    end process;

    /* ------------------------- register read (ClkMem) -------------------------
       Registered read mux on rising ClkMem over data already in the mclk domain, so no pre-latch and no read bridge is needed.
       Reserved slots and bits, and slots 9 and above, read 0. */
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
                    rdata_out <= (others => '0');   -- reserved and out-of-range slots read 0
            end case;
        end if;
    end process;

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

