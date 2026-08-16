/* -----------------------------------------------------------------------------
   onewire_target_model.vhd
   -----------------------------------------------------------------------------
   Behavioral 1-Wire target of the DS18B20/iButton class: the responder for the OneWire master peripheral testbench.
   The cfg_* inputs, held stable across one launched OW0CMD operation, select the shape to expect: RESET / write-N-bits / read-N-bits, speed, presence, read pattern, stuck-low injection and a timing-corruption self-test.
   Pulse widths are measured off mon_dir, bound to the DUT's OW_DQ_DIR port: OW_DQ_OUT is fixed '0', so DIR high is the whole drive-low action and its edges bound the master's own driven-low interval even while this model drives the shared net.
   Every expected window is a tick-count constant from onewire_bfm_pkg scaled by cfg_tick_period, which the TB computes from its own OW0DIV programming; this model never reads the DUT's divider, FSM state or registers.
   Open-drain only: dq_out is permanently '0' and dq_oe '1' drives it, so the line rises only when this model releases it to the bench's weak 'H' pull.
   ----------------------------------------------------------------------------- */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.onewire_bfm_pkg.all;

entity OneWire_target_model is
    port (
        -- Pulse-width reference: the DUT's own OW_DQ_DIR port.
        mon_dir : in std_logic;

        -- This model's drive onto the shared DQ net; dq_oe '1' drives dq_out.
        dq_out : out std_logic := '0';
        dq_oe  : out std_logic := '0';

        -- Per-operation configuration, held stable by the TB across one launched OW0CMD op and armed by a cfg_arm strobe just before launch.
        cfg_op             : in std_logic_vector(2 downto 0) := OW_OP_RESET;
        cfg_ods            : in std_logic                    := '0';     -- 0 is standard speed, 1 is overdrive; mirrors CR.ODS, which the TB knows.
        cfg_present        : in boolean                       := true;   -- Answer presence on RESET.
        cfg_stuck_low      : in boolean                       := false;  -- Delayed-onset stuck-low or short.
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

    -- DQ_OUT is fixed '0', open-drain only: only dq_oe toggles.
    dq_out <= '0';

    -- The whole responder: one process driven by the arm strobe and by the two edges of the master's drive-enable.
    resp : process (mon_dir, cfg_arm)
        variable mode     : natural := M_IDLE;
        variable nbits    : natural := 0;
        variable bit_idx  : natural := 0;
        variable t_fall   : time    := 0 ns;
        variable low_dur  : time    := 0 ns;
        variable wbyte    : std_logic_vector(7 downto 0) := (others => '0');

        -- Config snapshot captured at arm, quasi-static across one op.
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
        /* ----------------------------------------------------------------
           ARM: capture the TB's config for the upcoming op, reset the per-op state, and release any drive left over from a prior op.
           Assigning dq_oe here cancels any pending presence, stuck or read-hold waveform, since this process is its only driver.
           ---------------------------------------------------------------- */
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

        /* ----------------------------------------------------------------
           mon_dir RISING: the master starts driving DQ low, so just note the start time.
           Every decision happens on the matching release.
           ---------------------------------------------------------------- */
        elsif mon_dir'event and to_X01(mon_dir) = '1' then
            t_fall := now;

        /* ----------------------------------------------------------------
           mon_dir FALLING: the master releases, so low_dur is its own driven-low interval, uncontaminated by this model's drive, which never starts before this point.
           ---------------------------------------------------------------- */
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
                        dq_oe <= '1' after sdelay;   -- Onset after tPRES closes and before tRSTH ends.
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

                    wbyte(bit_idx) := bitv;             -- LSB-first assembly.
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
