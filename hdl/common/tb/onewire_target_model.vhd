-------------------------------------------------------------------------------
-- onewire_target_model.vhd
-------------------------------------------------------------------------------
-- Generic-configured behavioral 1-Wire TARGET (DS18B20/iButton-class)
-- responder for the OneWire master peripheral testbench (tb/OneWire_tb.vhd).
-- Mirrors i3c_target_model.vhd's role: the TB tells it, per launched op, the
-- exact shape to expect (RESET / write-N-bits / read-N-bits, the speed under
-- test, its presence/absence, a read-pattern byte, a stuck-low/short
-- injection, and a timing-corruption self-test flag) via cfg_* inputs held
-- stable across ONE launched OW0CMD operation.
--
-- PULSE-WIDTH REFERENCE POINT: this model watches `mon_dir`, bound directly
-- to the DUT's OW_DQ_DIR port (a normal, architecturally-frozen D3 port, not
-- an internal signal -- the exact analogue of I3C_tb.vhd wiring dut_sda_dir
-- into its bus-resolution logic). Since OW_DQ_OUT is fixed '0' (D11), DIR='1'
-- IS the pad's entire drive-low action; DIR's rising/falling edges are
-- therefore an exact, unambiguous measurement of the master's own driven-low
-- interval, including during READ slots where this model may ALSO be driving
-- the shared net afterward (measuring off the resolved multi-driver bus
-- would be ambiguous there; measuring the DUT's own drive-enable port is
-- not). This is a deliberate, documented design choice -- see the bench
-- author's report for the checker-independence discussion.
--
-- CHECKER INDEPENDENCE (mandatory): every expected window this model checks
-- against is a tick-count constant from the FROZEN design-doc D7/A1 Maxim
-- table (onewire_bfm_pkg), multiplied by `cfg_tick_period` -- a value the TB
-- computes from ITS OWN OW0DIV programming (OneWire_tb.vhd leaves OW0DIV at
-- its POR default 0, so cfg_tick_period = one bench `clk` period). This model
-- NEVER reads OneWire.vhd's internal divider, FSM state, or registers.
--
-- PROTOCOL MODEL (own read of D7/D9/D11/D12, since OneWire.vhd does not exist
-- yet to validate cycle-level behavior against -- ASSUMPTIONS flagged):
--   * RESET (cfg_op=OW_OP_RESET, 1 pulse): on the master's release (mon_dir
--     1->0), checks the low duration against the tRSTL window, then either
--     answers presence (cfg_present, immediate drive + a computed hold, D7
--     tPRES-derived), goes stuck-low after a computed onset (cfg_stuck_low,
--     the A5 SHORT-wins scenario), or does nothing (no-device -> NOPRES).
--   * WRITE (cfg_op=OW_OP_WRBIT/WRBYTE, 1/8 pulses): on each release,
--     classifies the low duration as bit 1 (short, tW1L-class) or bit 0
--     (long, tW0L-class) via OW_WBIT_THRESH_*, checks it against the
--     matching window, and shifts it LSB-first into obs_wbyte (D9).
--   * READ (cfg_op=OW_OP_RDBIT/RDBYTE, 1/8 pulses): on each release, checks
--     the master's OWN initiating low pulse against the tRL window (measured
--     BEFORE this model drives anything for that slot, so it is never
--     contaminated by this model's own drive), then, for a pattern bit '0'
--     (LSB-first, D9), extends the low drive for a computed hold (D7
--     tMSR/tSLOT-derived) so the master samples '0'; a pattern bit '1' is
--     communicated by simply not driving (weak 'H' pull carries it high).
--
-- Bus ownership: dq_oe follows the qspi_flash_model/i3c_target_model io_oe
-- convention ('1' = this model drives dq_out onto the shared net). dq_out is
-- permanently '0' (open-drain-only, mirroring D11 -- this model never drives
-- DQ high, only releases it to the bench's weak 'H' pull).
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.onewire_bfm_pkg.all;

entity OneWire_target_model is
    port (
        -- pulse-width reference: the DUT's own OW_DQ_DIR port (see header)
        mon_dir : in std_logic;

        -- this model's drive onto the shared DQ net ('1' on dq_oe = drives dq_out)
        dq_out : out std_logic := '0';
        dq_oe  : out std_logic := '0';

        -- per-operation configuration, held stable by the TB across one
        -- launched OW0CMD op (armed by a cfg_arm strobe just before launch)
        cfg_op             : in std_logic_vector(2 downto 0) := OW_OP_RESET;
        cfg_ods            : in std_logic                    := '0';     -- 0=STD, 1=OD (mirrors CR.ODS, TB-known)
        cfg_present        : in boolean                       := true;   -- answer presence on RESET
        cfg_stuck_low      : in boolean                       := false;  -- delayed-onset stuck/short (A5 test)
        cfg_rd_pattern     : in std_logic_vector(7 downto 0)  := x"A5";  -- READ source byte, LSB-first
        cfg_tick_period    : in time                          := 20 ns;  -- TB's OWN tick period (never a DUT read)
        cfg_corrupt_window : in boolean                       := false;  -- self-test: forces the next viol flag high
        cfg_arm            : in std_logic                     := '0';    -- rising-edge strobe: (re)arm for cfg_op

        -- observations (valid/held from the op's last edge until the next arm)
        obs_wbyte     : out std_logic_vector(7 downto 0) := (others => '0');  -- captured write bits, LSB-first
        obs_wbits     : out natural                       := 0;               -- bits captured (op progress/sanity)
        obs_viol_rstl : out std_logic                     := '0';             -- reset-low pulse outside its window
        obs_viol_w0l  : out std_logic                     := '0';             -- write-0 low pulse outside its window
        obs_viol_w1l  : out std_logic                     := '0';             -- write-1 low pulse outside its window
        obs_viol_rl   : out std_logic                     := '0'              -- read-initiate low pulse outside its window
    );
end entity OneWire_target_model;

architecture behavioral of OneWire_target_model is

    -- mode encoding: 0=idle/unarmed, 1=RESET, 2=WRITE, 3=READ
    constant M_IDLE  : natural := 0;
    constant M_RESET : natural := 1;
    constant M_WRITE : natural := 2;
    constant M_READ  : natural := 3;

begin

    -- DQ_OUT is fixed '0' (open-drain only, D11 mirror): only dq_oe toggles.
    dq_out <= '0';

    resp : process (mon_dir, cfg_arm)
        variable mode     : natural := M_IDLE;
        variable nbits    : natural := 0;
        variable bit_idx  : natural := 0;
        variable t_fall   : time    := 0 ns;
        variable low_dur  : time    := 0 ns;
        variable wbyte    : std_logic_vector(7 downto 0) := (others => '0');

        -- captured-at-arm config snapshot (quasi-static across one op, like
        -- the DUT's own D8 latch-at-launch descriptor)
        variable ods_v     : std_logic := '0';
        variable present_v : boolean   := true;
        variable stuck_v   : boolean   := false;
        variable pattern_v : std_logic_vector(7 downto 0) := (others => '0');
        variable corrupt_v : boolean   := false;
        variable tickp     : time      := 20 ns;

        variable bitv               : std_logic;
        variable thresh, phold      : time;
        variable rhold, sdelay      : time;
    begin
        ------------------------------------------------------------------
        -- ARM: capture the TB's config for the upcoming op, reset per-op
        -- state, and release any drive left over from a prior op (a new
        -- signal assignment on dq_oe here cancels any pending scheduled
        -- transaction from a previous presence/stuck/read-hold waveform --
        -- there is only one driver on dq_oe, this process).
        ------------------------------------------------------------------
        if cfg_arm'event and to_X01(cfg_arm) = '1' then
            case cfg_op is
                when OW_OP_RESET  => mode := M_RESET; nbits := 1;
                when OW_OP_WRBIT  => mode := M_WRITE; nbits := 1;
                when OW_OP_WRBYTE => mode := M_WRITE; nbits := 8;
                when OW_OP_RDBIT  => mode := M_READ;  nbits := 1;
                when OW_OP_RDBYTE => mode := M_READ;  nbits := 8;
                when others       => mode := M_IDLE;  nbits := 0;
            end case;
            bit_idx    := 0;
            wbyte      := (others => '0');
            ods_v      := cfg_ods;
            present_v  := cfg_present;
            stuck_v    := cfg_stuck_low;
            pattern_v  := cfg_rd_pattern;
            corrupt_v  := cfg_corrupt_window;
            tickp      := cfg_tick_period;
            obs_wbyte     <= (others => '0');
            obs_wbits     <= 0;
            obs_viol_rstl <= '0';
            obs_viol_w0l  <= '0';
            obs_viol_w1l  <= '0';
            obs_viol_rl   <= '0';
            dq_oe <= '0';

        ------------------------------------------------------------------
        -- mon_dir RISING (0->1): master starts driving DQ low. Just note the
        -- start time -- every decision happens on the matching release.
        ------------------------------------------------------------------
        elsif mon_dir'event and to_X01(mon_dir) = '1' then
            t_fall := now;

        ------------------------------------------------------------------
        -- mon_dir FALLING (1->0): master releases. low_dur is the master's
        -- OWN driven-low interval (uncontaminated by this model's own drive,
        -- which never starts before this point -- see the file header).
        ------------------------------------------------------------------
        elsif mon_dir'event and to_X01(mon_dir) = '0' then
            low_dur := now - t_fall;

            case mode is

                when M_RESET =>
                    if ods_v = '0' then
                        obs_viol_rstl <= ow_win_violation(low_dur, OW_T_RSTL_STD_MIN,
                                             OW_T_RSTL_STD_MAX, tickp, corrupt_v);
                    else
                        obs_viol_rstl <= ow_win_violation(low_dur, OW_T_RSTL_OD_MIN,
                                             OW_T_RSTL_OD_MAX, tickp, corrupt_v);
                    end if;

                    if stuck_v then
                        if ods_v = '0' then sdelay := OW_STUCK_DELAY_STD * tickp;
                        else                sdelay := OW_STUCK_DELAY_OD * tickp; end if;
                        dq_oe <= '1' after sdelay;   -- onset after tPRES closes, before tRSTH ends (A5)
                    elsif present_v then
                        if ods_v = '0' then phold := OW_PRES_HOLD_STD * tickp;
                        else                phold := OW_PRES_HOLD_OD * tickp; end if;
                        dq_oe <= '1', '0' after phold;   -- immediate presence pulse, timed release
                    end if;
                    mode := M_IDLE;   -- RESET is a single pulse; op consumed

                when M_WRITE =>
                    if ods_v = '0' then thresh := OW_WBIT_THRESH_STD * tickp;
                    else                thresh := OW_WBIT_THRESH_OD * tickp; end if;

                    if low_dur <= thresh then
                        bitv := '1';
                        if ods_v = '0' then
                            obs_viol_w1l <= ow_win_violation(low_dur, OW_T_W1L_STD_MIN,
                                               OW_T_W1L_STD_MAX, tickp, corrupt_v);
                        else
                            obs_viol_w1l <= ow_win_violation(low_dur, OW_T_W1L_OD_MIN,
                                               OW_T_W1L_OD_MAX, tickp, corrupt_v);
                        end if;
                    else
                        bitv := '0';
                        if ods_v = '0' then
                            obs_viol_w0l <= ow_win_violation(low_dur, OW_T_W0L_STD_MIN,
                                               OW_T_W0L_STD_MAX, tickp, corrupt_v);
                        else
                            obs_viol_w0l <= ow_win_violation(low_dur, OW_T_W0L_OD_MIN,
                                               OW_T_W0L_OD_MAX, tickp, corrupt_v);
                        end if;
                    end if;

                    wbyte(bit_idx) := bitv;             -- LSB-first assembly (D9)
                    bit_idx := bit_idx + 1;
                    if bit_idx = nbits then
                        obs_wbyte <= wbyte;
                        obs_wbits <= nbits;
                        mode := M_IDLE;
                    end if;

                when M_READ =>
                    if ods_v = '0' then
                        obs_viol_rl <= ow_win_violation(low_dur, OW_T_RL_STD_MIN,
                                           OW_T_RL_STD_MAX, tickp, corrupt_v);
                    else
                        obs_viol_rl <= ow_win_violation(low_dur, OW_T_RL_OD_MIN,
                                           OW_T_RL_OD_MAX, tickp, corrupt_v);
                    end if;

                    if pattern_v(bit_idx) = '0' then
                        if ods_v = '0' then rhold := OW_RD_HOLD_STD * tickp;
                        else                rhold := OW_RD_HOLD_OD * tickp; end if;
                        dq_oe <= '1', '0' after rhold;  -- extend low to communicate a 0
                    end if;                             -- bit=1: release (weak 'H' carries it high)
                    bit_idx := bit_idx + 1;
                    if bit_idx = nbits then
                        mode := M_IDLE;
                    end if;

                when others => null;

            end case;
        end if;
    end process resp;

end architecture behavioral;
