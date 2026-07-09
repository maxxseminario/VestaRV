-- =============================================================================
-- pwr_ctrl.vhd  (M17 — MTCMOS power gating, cold-gate pilot)
-- =============================================================================
-- POWER CONTROLLER for the switchable hart-tile domains: a tiny arbiter slave
-- (page-0 slot 11 = 0x4B00, the slot SARADC0 vacated in the digital-only
-- respin) holding one gate-request bit per tile hart plus a per-tile
-- sequencing FSM that drives the tile's MTCMOS controls in the only legal
-- order. Hart 0 (management hart: SPI boot, console, CLINT owner) is
-- ALWAYS-ON — its PWRCR bit reads 0 and ignores writes; its tile instance
-- ties the pd_* ports inactive at the top level.
--
--   GATE  (PWRCR bit h := 1):  iso_en=1  ->  rstn=0  ->  sleep=1 (rail off)
--   WAKE  (PWRCR bit h := 0):  sleep=0 -> T_RAIL settle -> iso_en=0 -> rstn=1
--
-- COLD-GATE CONTRACT (M17a design decision, no retention): a gated tile
-- loses ALL state. pd_rstn accompanies the power sequence on BOTH edges —
-- the domain is held in reset while unpowered and while its rail ramps, so
-- on wake the tile simply re-runs the M12 single-ROM boot (fetch PC 0x0
-- through the arbiter, mhartid dispatch, WFI park) and the management hart
-- relaunches it through the bootrom loader rows (0x10400+0x10*h) + msip.
-- Functionally, reset IS the honest sim model of the power cycle (behavioral
-- and SDF sims are not power-aware); electrically the HEAD switch fabric and
-- the A2ISO boundary clamps inserted by the CPF flow do the real work.
--
-- WHY reset-values == clamp values MATTERS: the tile's outbound boundary
-- registers all reset to 0 and sh_req is qualified by the tile's resetn
-- (hart_tile.vhd M12/M13), so a reset-held tile is bus-silent — identical to
-- the A2ISO clamp-0 the arbiter sees when the domain is really off. No
-- arbiter IDLE-sample hazard (M5a class) in either representation.
--
-- SOFTWARE CONTRACT: gate only a PARKED (or otherwise quiesced) tile — like
-- the SYS_CLK_CR reconfig rule, the management hart is responsible for
-- knowing the tile has no work in flight. The hardware still cannot
-- deadlock if this is violated (a clamped/reset req is a released req to
-- the wait-for-release arbiter; a pinned AMO lock drops the same way), but
-- the tile's in-flight work is destroyed — that is what cold-gating means.
-- A gate request taken mid-sequence completes the sequence and only then
-- honors the new request (no mid-sequence aborts; PWRSR shows the state).
--
-- BUS CONTRACT (same as mutex_bank/clint/irq_router): active-high en
-- one-cycle strobe, 4 active-high byte-lane strobes we (resv-GATED in
-- MCU.vhd), 1-cycle registered read, free-running mclk. Resets all-ON ->
-- the block is a provable NO-OP until software sets a PWRCR bit.
--
-- REGISTERS (word offsets in the 256B slot; only addr(3:0) decoded):
--   +0x0 PWRCR : bits 3:1 RW  GATE[h] — 1 = power-gate tile h, 0 = run.
--                bit  0   RO  0 (hart 0 always-on; writes ignored).
--   +0x4 PWRSR : RO. 4-bit state nibble per hart: PWRSR(4h+3 downto 4h).
--                0=ON  1=ISO (clamping)  2=RSTOFF (reset, rail dying)
--                3=OFF (gated)  4=RAIL (waking, rail settling)
--                5=UNISO (clamp release)   Hart 0 nibble reads 0.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity pwr_ctrl is
    generic (
        -- sequencing delays in mclk cycles. T_SEQ paces the iso->rst->off
        -- steps (any small value works: the boundary is registered and the
        -- tile is quiesced). T_RAIL is the wake rail-settle budget: it must
        -- cover the HEADBUF SLEEP daisy-chain propagation plus VDD ramp on
        -- the switched rail. 256 mclk @ 24 MHz = ~10.7 us — generous for a
        -- tile-sized domain; revisit against the Innovus rush-current
        -- staging when the switch fabric is characterized (M17 note).
        T_SEQ  : natural := 4;
        T_RAIL : natural := 256
    );
    port (
        clk    : in  std_logic;   -- free-running mclk
        resetn : in  std_logic;

        -- slave port (behind mp_arbiter; enables active-high, we resv-gated)
        en     : in  std_logic;
        we     : in  std_logic_vector(3 downto 0);
        addr   : in  std_logic_vector(3 downto 0);   -- word offset within slot
        wdata  : in  std_logic_vector(31 downto 0);
        rdata  : out std_logic_vector(31 downto 0);

        -- per-tile MTCMOS controls, harts 1-3 (hart 0 has no row: always-on).
        -- pd_iso_en : isolation clamp enable (CPF isolation_condition; also
        --             routed into the tile for its A2ISO cells' EN legs).
        -- pd_sleep  : HEAD switch SLEEP, ACTIVE-HIGH = rail OFF (pmk sense).
        -- pd_rstn   : ANDed into the tile's resetn at the top level — the
        --             cold-gate reset that makes wake = M12 boot.
        pd_iso_en : out std_logic_vector(3 downto 1);
        pd_sleep  : out std_logic_vector(3 downto 1);
        pd_rstn   : out std_logic_vector(3 downto 1)
    );
end entity;

architecture behav of pwr_ctrl is

    -- FSM state encodings == the PWRSR nibble values (documented above)
    constant S_ON     : std_logic_vector(3 downto 0) := x"0";
    constant S_ISO    : std_logic_vector(3 downto 0) := x"1";
    constant S_RSTOFF : std_logic_vector(3 downto 0) := x"2";
    constant S_OFF    : std_logic_vector(3 downto 0) := x"3";
    constant S_RAIL   : std_logic_vector(3 downto 0) := x"4";
    constant S_UNISO  : std_logic_vector(3 downto 0) := x"5";

    type state_arr_t is array(1 to 3) of std_logic_vector(3 downto 0);
    type cnt_arr_t   is array(1 to 3) of natural range 0 to 65535;

    signal state     : state_arr_t;
    signal cnt       : cnt_arr_t;
    signal gate_req  : std_logic_vector(3 downto 1);
    signal iso_r     : std_logic_vector(3 downto 1);
    signal sleep_r   : std_logic_vector(3 downto 1);
    signal rstn_r    : std_logic_vector(3 downto 1);
    signal rdata_reg : std_logic_vector(31 downto 0);

begin

    rdata     <= rdata_reg;
    pd_iso_en <= iso_r;
    pd_sleep  <= sleep_r;
    pd_rstn   <= rstn_r;

    pwr_proc: process(clk, resetn)
        variable sr : std_logic_vector(31 downto 0);
    begin
        if resetn = '0' then
            -- reset = every tile ON (iso off, switches on, reset released):
            -- chip boot is untouched, the block is a provable NO-OP until
            -- software gates a tile.
            gate_req  <= (others => '0');
            iso_r     <= (others => '0');
            sleep_r   <= (others => '0');
            rstn_r    <= (others => '1');
            state     <= (others => S_ON);
            cnt       <= (others => 0);
            rdata_reg <= (others => '0');
        elsif rising_edge(clk) then

            -- ---- register access (1-cycle registered read) ----
            if en = '1' then
                sr := (others => '0');
                for h in 1 to 3 loop
                    sr(4*h + 3 downto 4*h) := state(h);
                end loop;

                rdata_reg <= (others => '0');
                case addr is
                    when x"0"   => rdata_reg(3 downto 1) <= gate_req;
                    when x"1"   => rdata_reg <= sr;
                    when others => null;   -- reserved words read 0
                end case;

                -- PWRCR write (byte lane 0 carries all the bits; bit 0 —
                -- hart 0 — has no storage, so it can never be gated)
                if addr = x"0" and we(0) = '1' then
                    gate_req <= wdata(3 downto 1);
                end if;
            end if;

            -- ---- per-tile MTCMOS sequencers ----
            for h in 1 to 3 loop
                case state(h) is

                    when S_ON =>                    -- iso=0 slp=0 rstn=1
                        if gate_req(h) = '1' then
                            iso_r(h) <= '1';
                            cnt(h)   <= T_SEQ;
                            state(h) <= S_ISO;
                        end if;

                    when S_ISO =>                   -- clamps settling
                        if cnt(h) = 0 then
                            rstn_r(h) <= '0';
                            cnt(h)    <= T_SEQ;
                            state(h)  <= S_RSTOFF;
                        else
                            cnt(h) <= cnt(h) - 1;
                        end if;

                    when S_RSTOFF =>                -- reset held, open switches
                        if cnt(h) = 0 then
                            sleep_r(h) <= '1';
                            state(h)   <= S_OFF;
                        else
                            cnt(h) <= cnt(h) - 1;
                        end if;

                    when S_OFF =>                   -- gated: iso=1 slp=1 rstn=0
                        if gate_req(h) = '0' then
                            sleep_r(h) <= '0';
                            cnt(h)     <= T_RAIL;
                            state(h)   <= S_RAIL;
                        end if;

                    when S_RAIL =>                  -- rail ramping under reset
                        if cnt(h) = 0 then
                            iso_r(h) <= '0';
                            cnt(h)   <= T_SEQ;
                            state(h) <= S_UNISO;
                        else
                            cnt(h) <= cnt(h) - 1;
                        end if;

                    when S_UNISO =>                 -- clamps released, still reset
                        if cnt(h) = 0 then
                            rstn_r(h) <= '1';       -- tile cold-boots (M12 ROM)
                            state(h)  <= S_ON;
                        else
                            cnt(h) <= cnt(h) - 1;
                        end if;

                    when others =>
                        state(h) <= S_ON;           -- unreachable; recover safe

                end case;
            end loop;
        end if;
    end process;

end architecture;
