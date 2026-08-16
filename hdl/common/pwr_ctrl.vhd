-- POWER CONTROLLER for the switchable hart-tile domains: an arbiter slave at page-0 slot 11 (0x4B00) holding one gate-request bit per tile hart plus a per-tile FSM that drives the tile's MTCMOS controls in the only legal order.
-- GATE (PWRCR bit h := 1) is iso_en=1, then rstn=0, then sleep=1 (rail off); WAKE (bit h := 0) is sleep=0, then T_RAIL settle, then iso_en=0, then rstn=1.
-- Hart 0, the management hart owning SPI boot, the console and the CLINT, is ALWAYS-ON: its PWRCR bit reads 0 and ignores writes, and its tile instance ties the pd_* ports inactive at the top level.
-- COLD-GATE CONTRACT, no retention: a gated tile loses ALL state and pd_rstn accompanies the power sequence on BOTH edges, so the domain is held in reset while unpowered and while its rail ramps; on wake the tile re-runs the ROM boot and the management hart relaunches it.
-- Bus contract: active-high one-cycle en strobe, 4 active-high byte-lane strobes we (resv-gated in MCU.vhd), 1-cycle registered read, free-running mclk; it resets all-ON, so the block is a NO-OP until software sets a PWRCR bit.

-- SOFTWARE CONTRACT: gate only a PARKED or otherwise quiesced tile; a violation cannot deadlock the hardware (a clamped or reset req is a released req to the wait-for-release arbiter, and a pinned AMO lock drops the same way) but destroys the tile's in-flight work.
-- A gate request taken mid-sequence completes the sequence and only then honors the new request: no mid-sequence aborts, and PWRSR shows the state.

-- Reset values EQUAL the clamp values: the tile's outbound boundary registers reset to 0 and sh_req is qualified by the tile's resetn, so a reset-held tile is bus-silent, exactly like the isolation clamp-0 the arbiter sees when the domain is really off.
-- Reset is therefore the honest sim model of the power cycle; electrically the HEAD switch fabric and the isolation boundary clamps inserted by the CPF flow do the real work.

-- REGISTERS (word offsets in the 256B slot; only addr(3:0) decoded):
--   +0x0   PWRCR    RW  bits NHARTS-1:1 GATE[h], 1 = power-gate tile h, 0 = run; bit 0 RO 0 (hart 0). Byte-lane-0-qualified, so use full-word stores; the gate bits are ONE field even when they span lanes.
--   +0x4.. PWRSR0..ceil(NHARTS/8)-1  RO  4-bit state nibble per hart, 8 harts per word: hart h in PWRSR(h/8) at (4*(h mod 8)+3 downto 4*(h mod 8)). 0=ON 1=ISO 2=RSTOFF 3=OFF 4=RAIL 5=UNISO; hart 0 nibble reads 0.
--   +0x14  PWRWAKE  RW  reset 0: bit 0 GATE_EN (arm the boot gate), 1 RLS_PGOOD, 2 RLS_FIELD, 3 SW_RELEASE, 4 REHOLD (re-hold on a release-condition drop; 0 = one-shot latched release). Byte-lane-0-qualified.
--   +0x18  PWRSTS   RO  bit 0 PGOOD_LIVE, 1 FIELD_LIVE, 2 STRAP (1 = harvested boot), 3 STRAP_VALID, 4 BOOT_HOLD, 5 RLS_LATCHED.
--   +0x1C  TASKWKM  RW  event-fabric task-wake mask, one bit per gateable tile.
-- PWRWAKE, PWRSTS and TASKWKM sit at FIXED words 5/6/7, above PWRSR's worst case (NSRW <= 4 at NHARTS <= 32), so the map is NHARTS-independent.

-- FIELD-POWER BOOT GATE (hold-in-reset): pgood_rstn, reset value '1' meaning release, is ANDed into EVERY hart's outer reset at the top level, hart 0 included.
-- A held hart issues no sh_req, so the arbiter sees the bus silence pd_rstn already guarantees; tying pgood_pad='1', strap_pad='0' and field_detect='0' makes the whole gate a NO-OP.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity pwr_ctrl is
    generic (
        -- Hart count: tiles 1..NHARTS-1 each get a gate bit, a sequencer FSM and a pd_* row; hart 0 is always-on and has no row.
        NHARTS : natural := 4;
        -- T_SEQ paces the iso, then reset, then off steps in mclk cycles; any small value works, since the boundary is registered and the tile is quiesced.
        -- T_RAIL is the wake rail-settle budget and must cover the HEADBUF SLEEP daisy-chain propagation plus VDD ramp on the switched rail; 256 mclk at 24 MHz is ~10.7 us.
        T_SEQ  : natural := 4;
        T_RAIL : natural := 256;
        -- Strap sample delay after reset release, in mclk cycles, beyond the 2-FF sync and with the pad pull long settled during the ms-scale POR.
        -- The sample is one-shot, so a mid-run strap change is ignored.
        STRAP_SETTLE : natural := 8
    );
    port (
        clk    : in  std_logic;   -- Free-running mclk.
        resetn : in  std_logic;   -- Chip reset, active low.

        -- Slave port behind mp_arbiter: enables active-high, we resv-gated.
        en     : in  std_logic;
        we     : in  std_logic_vector(3 downto 0);
        addr   : in  std_logic_vector(3 downto 0);   -- Word offset within the slot.
        wdata  : in  std_logic_vector(31 downto 0);
        rdata  : out std_logic_vector(31 downto 0);

        -- Per-tile MTCMOS controls, harts 1..NHARTS-1; hart 0 has no row because it is always-on.
        -- pd_iso_en is the isolation clamp enable, also routed into the tile for its isolation cells' EN legs; pd_sleep is HEAD switch SLEEP, ACTIVE-HIGH meaning rail OFF; pd_rstn is the cold-gate reset ANDed into the tile's resetn at the top level.
        pd_iso_en : out std_logic_vector(NHARTS-1 downto 1);
        pd_sleep  : out std_logic_vector(NHARTS-1 downto 1);
        pd_rstn   : out std_logic_vector(NHARTS-1 downto 1);

        -- Field-powered-mode pads: ASYNC inputs, 2-FF synchronized inside this block on the always-on mclk domain.
        pgood_pad    : in  std_logic;  -- PGOOD supervisor level (P6.7); tie '1' when unused.
        strap_pad    : in  std_logic;  -- Harvest boot-mode strap (P6.6); tie '0' when unused.
        field_detect : in  std_logic;  -- NFC0 field level; tie '0' when NFC absent.
        pgood_rstn   : out std_logic;  -- Active-low boot gate, ANDed into every
                                       -- hart's outer reset. Reset value '1' releases.

        -- Event-fabric tap: a one-mclk pulse clearing the gate_req bits selected by the W_TASKWKM mask, acting per bit AFTER the bus writes so a coincident PWRCR write merges and the task wins its own bits.
        -- The MTCMOS FSM sequences rail-up as for any register-cleared gate, and the tap NEVER touches the boot-gate release logic.
        task_wake    : in  std_logic := '0'
    );
end entity;

architecture behav of pwr_ctrl is

    -- PWRSR word count, 8 state nibbles per word.
    constant NSRW : natural := (NHARTS + 7) / 8;

    -- FSM state encodings, identical to the PWRSR nibble values documented above.
    constant S_ON     : std_logic_vector(3 downto 0) := x"0";
    constant S_ISO    : std_logic_vector(3 downto 0) := x"1";
    constant S_RSTOFF : std_logic_vector(3 downto 0) := x"2";
    constant S_OFF    : std_logic_vector(3 downto 0) := x"3";
    constant S_RAIL   : std_logic_vector(3 downto 0) := x"4";
    constant S_UNISO  : std_logic_vector(3 downto 0) := x"5";

    -- One sequencer state and one delay counter per gateable tile.
    type state_arr_t is array(1 to NHARTS-1) of std_logic_vector(3 downto 0);
    type cnt_arr_t   is array(1 to NHARTS-1) of natural range 0 to 65535;

    signal state     : state_arr_t;
    signal cnt       : cnt_arr_t;
    signal gate_req  : std_logic_vector(NHARTS-1 downto 1);   -- PWRCR gate bits.
    signal iso_r     : std_logic_vector(NHARTS-1 downto 1);   -- Registered pd_iso_en.
    signal sleep_r   : std_logic_vector(NHARTS-1 downto 1);   -- Registered pd_sleep.
    signal rstn_r    : std_logic_vector(NHARTS-1 downto 1);   -- Registered pd_rstn.
    signal rdata_reg : std_logic_vector(31 downto 0);         -- One-cycle registered read.

    -- Boot-gate and wake-source state, all on the always-on domain; word offsets as in the header map.
    constant W_PWRWAKE : integer := 5;
    constant W_PWRSTS  : integer := 6;
    constant W_TASKWKM : integer := 7;   -- Event-fabric task-wake mask.
    signal pgood_s1, pgood_s2 : std_logic;   -- 2-FF sync, pgood_pad.
    signal field_s1, field_s2 : std_logic;   -- 2-FF sync, field_detect.
    signal strap_s1, strap_s2 : std_logic;   -- 2-FF sync, strap_pad.
    signal strap_sampled : std_logic;        -- One-shot latched strap ('1' = harvest).
    signal strap_valid   : std_logic;        -- Strap sample complete.
    signal strap_cnt     : natural range 0 to 65535;   -- Counts out STRAP_SETTLE.
    signal wake_cr       : std_logic_vector(4 downto 0);  -- PWRWAKE bits 4:0.
    signal task_wkm      : std_logic_vector(NHARTS-1 downto 1);  -- Task-wake mask.
    signal rls_latch     : std_logic;        -- Sticky release, one-shot mode.
    signal boot_hold_r   : std_logic;        -- Registered gate state ('1' = hold).

begin

    -- Coverage asserts on elaboration-time constants, so no hardware is built.
    -- The PWRCR gate bits must fit one 32-bit word, and PWRCR plus the PWRSR array must fit the 16 decoded words of addr(3:0).
    assert NHARTS >= 2 and NHARTS <= 32
        report "pwr_ctrl: NHARTS out of range (PWRCR is one 32-bit word)"
        severity failure;
    assert 1 + NSRW <= 16
        report "pwr_ctrl: PWRSR array outgrows the 16-word decode"
        severity failure;
    -- PWRWAKE and PWRSTS sit at fixed words 5 and 6, so PWRSR must stay below them.
    assert NSRW < 5
        report "pwr_ctrl: PWRSR array collides with PWRWAKE/PWRSTS (words 5/6)"
        severity failure;

    -- Registered outputs straight out to the bus and the MTCMOS controls.
    rdata     <= rdata_reg;
    pd_iso_en <= iso_r;
    pd_sleep  <= sleep_r;
    pd_rstn   <= rstn_r;
    -- Registered, glitch-free boot gate; reset value '1' releases.
    pgood_rstn <= not boot_hold_r;

    -- Register file, per-tile MTCMOS sequencers and the boot gate, all on mclk.
    pwr_proc: process(clk, resetn)
        -- sr is the concatenated PWRSR word array, hart h's nibble at 4h, 8 harts per 32-bit word.
        variable sr   : std_logic_vector(NSRW*32-1 downto 0);
        variable widx : integer range 0 to 15;   -- Decoded word offset.
        -- Effective-policy terms: strap ORed with the software override.
        variable strap_harvest : std_logic;
        variable eff_arm       : std_logic;
        variable eff_pgood     : std_logic;
        variable eff_field     : std_logic;
        variable eff_rehold    : std_logic;
        variable rls_now       : std_logic;
    begin
        if resetn = '0' then
            -- Reset leaves every tile ON: iso off, switches on, reset released.
            -- Chip boot is untouched and the block is a provable NO-OP until software gates a tile.
            gate_req  <= (others => '0');
            iso_r     <= (others => '0');
            sleep_r   <= (others => '0');
            rstn_r    <= (others => '1');
            state     <= (others => S_ON);
            cnt       <= (others => 0);
            rdata_reg <= (others => '0');
            -- The boot gate is released at reset so normal boots are unperturbed.
            -- A harvested board self-arms within the strap settle window, and the re-hold is a clean cold boot.
            pgood_s1      <= '1';
            pgood_s2      <= '1';
            field_s1      <= '0';
            field_s2      <= '0';
            strap_s1      <= '0';
            strap_s2      <= '0';
            strap_sampled <= '0';
            strap_valid   <= '0';
            strap_cnt     <= 0;
            wake_cr       <= (others => '0');
            task_wkm      <= (others => '0');   -- Task-wake is inert out of reset.
            rls_latch     <= '0';
            boot_hold_r   <= '0';
        elsif rising_edge(clk) then

            -- Register access, with a one-cycle registered read.
            if en = '1' then
                sr := (others => '0');
                for h in 1 to NHARTS-1 loop
                    sr(4*h + 3 downto 4*h) := state(h);
                end loop;

                widx := conv_integer(addr);
                rdata_reg <= (others => '0');
                if widx = 0 then
                    rdata_reg(NHARTS-1 downto 1) <= gate_req;
                elsif widx <= NSRW then
                    -- PWRSR0..NSRW-1 from +0x4 up.
                    rdata_reg <= sr(32*widx - 1 downto 32*(widx-1));
                elsif widx = W_TASKWKM then
                    rdata_reg(NHARTS-1 downto 1) <= task_wkm;
                elsif widx = W_PWRWAKE then
                    -- PWRWAKE readback.
                    rdata_reg(4 downto 0) <= wake_cr;
                elsif widx = W_PWRSTS then
                    -- PWRSTS, read-only.
                    rdata_reg(0) <= pgood_s2;
                    rdata_reg(1) <= field_s2;
                    rdata_reg(2) <= strap_sampled;
                    rdata_reg(3) <= strap_valid;
                    rdata_reg(4) <= boot_hold_r;
                    rdata_reg(5) <= rls_latch;
                end if;                        -- Reserved words read 0.

                -- PWRCR write, qualified by byte lane 0.
                -- The gate bits are ONE field even when NHARTS-1:1 spans lanes, so software uses full-word stores; bit 0, hart 0, has no storage and can never be gated.
                if widx = 0 and we(0) = '1' then
                    gate_req <= wdata(NHARTS-1 downto 1);
                end if;
                -- PWRWAKE write, byte-lane-0-qualified like PWRCR.
                if widx = W_PWRWAKE and we(0) = '1' then
                    wake_cr <= wdata(4 downto 0);
                end if;
                -- Task-wake mask write, byte-lane-0-qualified like PWRCR.
                if widx = W_TASKWKM and we(0) = '1' then
                    task_wkm <= wdata(NHARTS-1 downto 1);
                end if;
            end if;

            -- Task wake sits OUTSIDE the bus qualifier so it fires with the bus idle, and acts per bit AFTER the writes above: the CPU lands the word, then the task clears its masked bits.
            -- FSM rail-up sequencing is identical to a register-cleared gate.
            if task_wake = '1' then
                for h in 1 to NHARTS-1 loop
                    if task_wkm(h) = '1' then
                        gate_req(h) <= '0';
                    end if;
                end loop;
            end if;

            -- Per-tile MTCMOS sequencers, one FSM per gateable tile.
            for h in 1 to NHARTS-1 loop
                case state(h) is

                    when S_ON =>                    -- Running: iso=0 slp=0 rstn=1. A gate request starts the clamp step.
                        if gate_req(h) = '1' then
                            iso_r(h) <= '1';
                            cnt(h)   <= T_SEQ;
                            state(h) <= S_ISO;
                        end if;

                    when S_ISO =>                   -- Clamps settling, then drop the tile reset.
                        if cnt(h) = 0 then
                            rstn_r(h) <= '0';
                            cnt(h)    <= T_SEQ;
                            state(h)  <= S_RSTOFF;
                        else
                            cnt(h) <= cnt(h) - 1;
                        end if;

                    when S_RSTOFF =>                -- Reset held, then open the HEAD switches.
                        if cnt(h) = 0 then
                            sleep_r(h) <= '1';
                            state(h)   <= S_OFF;
                        else
                            cnt(h) <= cnt(h) - 1;
                        end if;

                    when S_OFF =>                   -- Gated: iso=1 slp=1 rstn=0. Clearing the gate bit starts the rail-up.
                        if gate_req(h) = '0' then
                            sleep_r(h) <= '0';
                            cnt(h)     <= T_RAIL;
                            state(h)   <= S_RAIL;
                        end if;

                    when S_RAIL =>                  -- Rail ramping under reset for T_RAIL, then release the clamps.
                        if cnt(h) = 0 then
                            iso_r(h) <= '0';
                            cnt(h)   <= T_SEQ;
                            state(h) <= S_UNISO;
                        else
                            cnt(h) <= cnt(h) - 1;
                        end if;

                    when S_UNISO =>                 -- Clamps released, tile still in reset.
                        if cnt(h) = 0 then
                            rstn_r(h) <= '1';       -- Tile cold-boots from the shared ROM.
                            state(h)  <= S_ON;
                        else
                            cnt(h) <= cnt(h) - 1;
                        end if;

                    when others =>
                        state(h) <= S_ON;           -- Unreachable; recover to the safe state.

                end case;
            end loop;

            -- Boot-gate wake sources: 2-FF synchronizers, since the pad-side inputs are async.
            pgood_s1 <= pgood_pad;
            pgood_s2 <= pgood_s1;
            field_s1 <= field_detect;
            field_s2 <= field_s1;
            strap_s1 <= strap_pad;
            strap_s2 <= strap_s1;

            -- One-shot strap sample, STRAP_SETTLE cycles after reset release.
            if strap_valid = '0' then
                if strap_cnt = STRAP_SETTLE then
                    strap_sampled <= strap_s2;      -- '1' means a harvested boot.
                    strap_valid   <= '1';
                else
                    strap_cnt <= strap_cnt + 1;
                end if;
            end if;

            -- The strap drives hardware defaults and the PWRWAKE bits OR-in software overrides.
            -- A harvested board self-arms with zero software: arm, wait on PGOOD, brownout re-hold.
            strap_harvest := strap_valid and strap_sampled;
            eff_arm    := wake_cr(0) or strap_harvest;      -- GATE_EN
            eff_pgood  := wake_cr(1) or strap_harvest;      -- RLS_PGOOD
            eff_field  := wake_cr(2);                       -- RLS_FIELD
            eff_rehold := wake_cr(4) or strap_harvest;      -- REHOLD

            rls_now := wake_cr(3)                           -- SW_RELEASE
                       or (eff_pgood and pgood_s2)
                       or (eff_field and field_s2);
            rls_latch <= rls_latch or rls_now;

            -- With REHOLD=1 the hold tracks the live release condition, so a drop re-holds and gives a cold boot on return; with REHOLD=0 the release is one-shot.
            -- With no release source enabled an armed gate holds until SW_RELEASE.
            if eff_rehold = '1' then
                boot_hold_r <= eff_arm and not rls_now;
            else
                boot_hold_r <= eff_arm and not (rls_latch or rls_now);
            end if;
        end if;
    end process;

end architecture;
