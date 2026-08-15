-------------------------------------------------------------------------------
-- onewire_target_model.vhd
-------------------------------------------------------------------------------
-- Generic-configured behavioral 1-Wire TARGET of the DS18B20/iButton class, the responder for the OneWire master peripheral testbench (tb/OneWire_tb.vhd).
-- It mirrors i3c_target_model.vhd's role: through cfg_* inputs held stable across ONE launched OW0CMD operation, the TB tells it the exact shape to expect per op.
-- That shape covers RESET / write-N-bits / read-N-bits, the speed under test, the target's presence or absence, a read-pattern byte, a stuck-low or short injection, and a timing-corruption self-test flag.
--
-- PULSE-WIDTH REFERENCE POINT: this model watches `mon_dir`, bound directly to the DUT's OW_DQ_DIR port.
-- That is a normal, architecturally-frozen D3 port and not an internal signal, the exact analogue of I3C_tb.vhd wiring dut_sda_dir into its bus-resolution logic.
-- Since OW_DQ_OUT is fixed '0' (D11), DIR='1' IS the pad's entire drive-low action, so DIR's rising and falling edges are an exact, unambiguous measurement of the master's own driven-low interval.
-- That holds even during READ slots where this model may ALSO be driving the shared net afterward: measuring off the resolved multi-driver bus would be ambiguous there, measuring the DUT's own drive-enable port is not.
-- This is a deliberate, documented design choice; see the bench author's report for the checker-independence discussion.
--
-- CHECKER INDEPENDENCE (mandatory): every expected window this model checks against is a tick-count constant from the FROZEN design-doc D7/A1 Maxim table (onewire_bfm_pkg), multiplied by `cfg_tick_period`.
-- `cfg_tick_period` is a value the TB computes from ITS OWN OW0DIV programming, and OneWire_tb.vhd leaves OW0DIV at its POR default of 0, so one tick is one bench `clk` period.
-- This model NEVER reads OneWire.vhd's internal divider, FSM state, or registers.
--
-- PROTOCOL MODEL, this bench's own read of D7/D9/D11/D12, since OneWire.vhd does not exist yet to validate cycle-level behavior against; ASSUMPTIONS are flagged:
--   * RESET (cfg_op=OW_OP_RESET, 1 pulse): on the master's release, i.e. mon_dir going low, checks the low duration against the tRSTL window.
--     It then either answers presence (cfg_present: drive immediately, hold for a computed time derived from D7 tPRES), goes stuck-low after a computed onset (cfg_stuck_low, the A5 SHORT-wins scenario), or does nothing at all, which is the no-device NOPRES case.
--   * WRITE (cfg_op=OW_OP_WRBIT/WRBYTE, 1 or 8 pulses): on each release, classifies the low duration through OW_WBIT_THRESH_* as bit 1 (short, tW1L class) or bit 0 (long, tW0L class), checks it against the matching window, and shifts it LSB-first into obs_wbyte (D9).
--   * READ (cfg_op=OW_OP_RDBIT/RDBYTE, 1 or 8 pulses): on each release, checks the master's OWN initiating low pulse against the tRL window, measured BEFORE this model drives anything for that slot so it is never contaminated by this model's own drive.
--     For a pattern bit '0' (LSB-first, D9) it then extends the low drive for a computed hold derived from D7 tMSR/tSLOT so the master samples '0'; a pattern bit '1' is communicated by simply not driving, letting the weak 'H' pull carry the line high.
--
-- Bus ownership: dq_oe follows the qspi_flash_model and i3c_target_model io_oe convention, where '1' means this model drives dq_out onto the shared net.
-- dq_out is permanently '0', open-drain only, mirroring D11: this model never drives DQ high, it only releases it to the bench's weak 'H' pull.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.onewire_bfm_pkg.all;

entity OneWire_target_model is
    port (
        -- Pulse-width reference: the DUT's own OW_DQ_DIR port, see the header.
        mon_dir : in std_logic;

        -- This model's drive onto the shared DQ net; dq_oe '1' drives dq_out.
        dq_out : out std_logic := '0';
        dq_oe  : out std_logic := '0';

        -- Per-operation configuration, held stable by the TB across one launched OW0CMD op and armed by a cfg_arm strobe just before launch.
        cfg_op             : in std_logic_vector(2 downto 0) := OW_OP_RESET;
        cfg_ods            : in std_logic                    := '0';     -- 0 is standard speed, 1 is overdrive; mirrors CR.ODS, which the TB knows.
        cfg_present        : in boolean                       := true;   -- Answer presence on RESET.
        cfg_stuck_low      : in boolean                       := false;  -- Delayed-onset stuck-low or short, the A5 test.
        cfg_rd_pattern     : in std_logic_vector(7 downto 0)  := x"A5";  -- READ source byte, LSB-first.
        cfg_tick_period    : in time                          := 20 ns;  -- The TB's OWN tick period, never read from the DUT.
        cfg_corrupt_window : in boolean                       := false;  -- Self-test: forces the next violation flag high.
        cfg_arm            : in std_logic                     := '0';    -- Rising-edge strobe that arms or re-arms for cfg_op.

        -- Observations, held from the op's last edge until the next arm.
        obs_wbyte     : out std_logic_vector(7 downto 0) := (others => '0');  -- Captured write bits, LSB-first.
        obs_wbits     : out natural                       := 0;               -- Bits captured, for op progress and sanity.
        obs_viol_rstl : out std_logic                     := '0';             -- Reset-low pulse outside its window.
        obs_viol_w0l  : out std_logic                     := '0';             -- Write-0 low pulse outside its window.
        obs_viol_w1l  : out std_logic                     := '0';             -- Write-1 low pulse outside its window.
        obs_viol_rl   : out std_logic                     := '0'              -- Read-initiate low pulse outside its window.
    );
end entity OneWire_target_model;

architecture behavioral of OneWire_target_model is

    -- Mode encoding: 0 is idle or unarmed, 1 is RESET, 2 is WRITE, 3 is READ.
    constant M_IDLE  : natural := 0;
    constant M_RESET : natural := 1;
    constant M_WRITE : natural := 2;
    constant M_READ  : natural := 3;

begin

    -- DQ_OUT is fixed '0', open-drain only, mirroring D11: only dq_oe toggles.
    dq_out <= '0';

    -- The whole responder: one process driven by the arm strobe and by the two edges of the master's drive-enable.
    resp : process (mon_dir, cfg_arm)
        variable mode     : natural := M_IDLE;
        variable nbits    : natural := 0;
        variable bit_idx  : natural := 0;
        variable t_fall   : time    := 0 ns;
        variable low_dur  : time    := 0 ns;
        variable wbyte    : std_logic_vector(7 downto 0) := (others => '0');

        -- Config snapshot captured at arm, quasi-static across one op, like the DUT's own D8 latch-at-launch descriptor.
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
        -- ARM: capture the TB's config for the upcoming op, reset the per-op state, and release any drive left over from a prior op.
        -- A new signal assignment on dq_oe here cancels any pending scheduled transaction from a previous presence, stuck or read-hold waveform, since this process is the only driver of dq_oe.
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
        -- mon_dir RISING: the master starts driving DQ low, so just note the start time.
        -- Every decision happens on the matching release.
        ------------------------------------------------------------------
        elsif mon_dir'event and to_X01(mon_dir) = '1' then
            t_fall := now;

        ------------------------------------------------------------------
        -- mon_dir FALLING: the master releases, and low_dur is the master's OWN driven-low interval.
        -- It is uncontaminated by this model's drive, which never starts before this point; see the file header.
        ------------------------------------------------------------------
        elsif mon_dir'event and to_X01(mon_dir) = '0' then
            low_dur := now - t_fall;

            case mode is

                when M_RESET =>     -- Check tRSTL, then answer presence, go stuck-low, or stay silent.
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
                        dq_oe <= '1' after sdelay;   -- Onset after tPRES closes and before tRSTH ends (A5).
                    elsif present_v then
                        if ods_v = '0' then phold := OW_PRES_HOLD_STD * tickp;
                        else                phold := OW_PRES_HOLD_OD * tickp; end if;
                        dq_oe <= '1', '0' after phold;   -- Immediate presence pulse with a timed release.
                    end if;
                    mode := M_IDLE;   -- RESET is a single pulse, so the op is consumed here.

                when M_WRITE =>     -- Classify the low pulse as a 1 or a 0, window-check it, and assemble the byte.
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

                    wbyte(bit_idx) := bitv;             -- LSB-first assembly (D9).
                    bit_idx := bit_idx + 1;
                    if bit_idx = nbits then
                        obs_wbyte <= wbyte;
                        obs_wbits <= nbits;
                        mode := M_IDLE;
                    end if;

                when M_READ =>      -- Window-check the master's initiating pulse, then source the pattern bit.
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
                        dq_oe <= '1', '0' after rhold;  -- Extend the low to communicate a 0.
                    end if;                             -- For a 1, release the line and let the weak 'H' carry it high.
                    bit_idx := bit_idx + 1;
                    if bit_idx = nbits then
                        mode := M_IDLE;
                    end if;

                when others => null;   -- Idle or unarmed: edges are ignored.

            end case;
        end if;
    end process resp;

end architecture behavioral;
