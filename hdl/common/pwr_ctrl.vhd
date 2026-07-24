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
-- REGISTERS (word offsets in the 256B slot; only addr(3:0) decoded).
-- A2 (Argus) N-hart regrow — at the NHARTS=4 default this is EXACTLY the
-- original M17 map (one PWRSR word):
--   +0x0 PWRCR : bits NHARTS-1:1 RW  GATE[h] — 1 = power-gate tile h,
--                0 = run. Bit 0 RO 0 (hart 0 always-on; writes ignored).
--                The write is qualified by byte-lane 0 only — use full-word
--                stores (sw); the gate bits are treated as ONE field even
--                when NHARTS-1:1 spans byte lanes.
--   +0x4.. PWRSR0..ceil(NHARTS/8)-1 : RO. 4-bit state nibble per hart, 8
--                harts per word: hart h in PWRSR(h/8), nibble
--                (4*(h mod 8)+3 downto 4*(h mod 8)).
--                0=ON  1=ISO (clamping)  2=RSTOFF (reset, rail dying)
--                3=OFF (gated)  4=RAIL (waking, rail settling)
--                5=UNISO (clamp release)   Hart 0 nibble reads 0.
--
-- DP-S3 (field-powered NFC mode) — PGOOD boot gate + wake sources. The two
-- new words sit at FIXED offsets 5/6, above PWRSR's worst case (NSRW <= 4 at
-- NHARTS <= 32), so the map is NHARTS-independent:
--   +0x14 PWRWAKE : RW, reset 0 (NO-OP). Byte-lane-0-qualified like PWRCR.
--                bit 0 GATE_EN    software-arm the boot gate (OR strap-arm)
--                bit 1 RLS_PGOOD  pgood_live is a release condition
--                bit 2 RLS_FIELD  field_live is a release condition (the
--                                 field_detect WAKE source — no IRQ vector)
--                bit 3 SW_RELEASE software-forced release / "proceed"
--                bit 4 REHOLD     re-assert the hold when the release
--                                 condition drops (brownout re-hold); 0 =
--                                 one-shot latched release
--   +0x18 PWRSTS : RO.  bit 0 PGOOD_LIVE (synced pgood_pad)
--                bit 1 FIELD_LIVE (synced field_detect)
--                bit 2 STRAP (latched: 1 = harvested boot — the bootrom
--                      branch bit)   bit 3 STRAP_VALID (sample complete)
--                bit 4 BOOT_HOLD (gate currently holding the harts)
--                bit 5 RLS_LATCHED (one-shot release has latched)
--
-- BOOT GATE (HOLD-IN-RESET, DP-S3 decision): pgood_rstn (reset value '1' =
-- release) is ANDed into EVERY hart's outer reset at the top level (hart 0
-- included — it gains a fold it never had; tiles extend the pd_rstn fold).
-- A held hart issues no sh_req (the M12 outer-reset qualification), so the
-- arbiter sees the same bus silence pd_rstn already guarantees — no new
-- arbiter contract. STRAP POLICY: the strap drives HARDWARE DEFAULTS and
-- the register bits OR-in software overrides — a harvested board self-arms
-- (arm + RLS_PGOOD + REHOLD) with zero software, resolving the
-- chicken-and-egg of the gate holding the very cores that would program it.
-- The strap is sampled ONCE, STRAP_SETTLE mclk after reset release (the gate
-- is released during that window; on a harvested board the ensuing re-hold
-- is a clean M12 cold boot). PGOOD deassert with REHOLD re-holds = cold
-- boot on PGOOD return — the sanctioned cold-gate semantics, honestly
-- modelled by reset in sim. All three pad-side inputs are ASYNC and 2-FF
-- synchronized HERE on the always-on mclk/resetn domain (the NFC's own
-- smclk synchronizers do not cover this path). Ties on a config without the
-- feature (pgood_pad='1', strap_pad='0', field_detect='0') make the whole
-- block a provable NO-OP: pgood_rstn is stuck at '1' and PWRCR/PWRSR are
-- bit-identical to M17.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity pwr_ctrl is
    generic (
        -- A2 (Argus): hart count — tiles 1..NHARTS-1 each get a gate bit,
        -- a sequencer FSM and a pd_* row (hart 0 is always-on, no row).
        -- Default 4 = the Castalia shape; every existing instantiation is
        -- unchanged.
        NHARTS : natural := 4;
        -- sequencing delays in mclk cycles. T_SEQ paces the iso->rst->off
        -- steps (any small value works: the boundary is registered and the
        -- tile is quiesced). T_RAIL is the wake rail-settle budget: it must
        -- cover the HEADBUF SLEEP daisy-chain propagation plus VDD ramp on
        -- the switched rail. 256 mclk @ 24 MHz = ~10.7 us — generous for a
        -- tile-sized domain; revisit against the Innovus rush-current
        -- staging when the switch fabric is characterized (M17 note).
        T_SEQ  : natural := 4;
        T_RAIL : natural := 256;
        -- DP-S3: strap sample delay after reset release, in mclk cycles —
        -- beyond the 2-FF sync, with the pad pull long settled during the
        -- ms-scale POR. The sample is one-shot (a mid-run strap change is
        -- ignored).
        STRAP_SETTLE : natural := 8
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

        -- per-tile MTCMOS controls, harts 1..NHARTS-1 (hart 0 has no row:
        -- always-on).
        -- pd_iso_en : isolation clamp enable (CPF isolation_condition; also
        --             routed into the tile for its A2ISO cells' EN legs).
        -- pd_sleep  : HEAD switch SLEEP, ACTIVE-HIGH = rail OFF (pmk sense).
        -- pd_rstn   : ANDed into the tile's resetn at the top level — the
        --             cold-gate reset that makes wake = M12 boot.
        pd_iso_en : out std_logic_vector(NHARTS-1 downto 1);
        pd_sleep  : out std_logic_vector(NHARTS-1 downto 1);
        pd_rstn   : out std_logic_vector(NHARTS-1 downto 1);

        -- DP-S3 field-powered mode. The pad-side inputs are ASYNC and 2-FF
        -- synchronized inside this block (always-on mclk domain).
        pgood_pad    : in  std_logic;  -- PGOOD supervisor level (P6.7); tie '1' when unused
        strap_pad    : in  std_logic;  -- harvest boot-mode strap (P6.6); tie '0' when unused
        field_detect : in  std_logic;  -- NFC0 field level; tie '0' when NFC absent
        pgood_rstn   : out std_logic   -- active-low boot gate, ANDed into every
                                       -- hart's outer reset. Reset value '1' = release.
    );
end entity;

architecture behav of pwr_ctrl is

    -- A2: PWRSR word count — 8 state nibbles per word (one word at the
    -- Castalia NHARTS=4 default, so the register map is unchanged there)
    constant NSRW : natural := (NHARTS + 7) / 8;

    -- FSM state encodings == the PWRSR nibble values (documented above)
    constant S_ON     : std_logic_vector(3 downto 0) := x"0";
    constant S_ISO    : std_logic_vector(3 downto 0) := x"1";
    constant S_RSTOFF : std_logic_vector(3 downto 0) := x"2";
    constant S_OFF    : std_logic_vector(3 downto 0) := x"3";
    constant S_RAIL   : std_logic_vector(3 downto 0) := x"4";
    constant S_UNISO  : std_logic_vector(3 downto 0) := x"5";

    type state_arr_t is array(1 to NHARTS-1) of std_logic_vector(3 downto 0);
    type cnt_arr_t   is array(1 to NHARTS-1) of natural range 0 to 65535;

    signal state     : state_arr_t;
    signal cnt       : cnt_arr_t;
    signal gate_req  : std_logic_vector(NHARTS-1 downto 1);
    signal iso_r     : std_logic_vector(NHARTS-1 downto 1);
    signal sleep_r   : std_logic_vector(NHARTS-1 downto 1);
    signal rstn_r    : std_logic_vector(NHARTS-1 downto 1);
    signal rdata_reg : std_logic_vector(31 downto 0);

    -- DP-S3: boot-gate / wake-source state (all on the always-on domain).
    -- Register word offsets for the two new words (see header).
    constant W_PWRWAKE : integer := 5;
    constant W_PWRSTS  : integer := 6;
    signal pgood_s1, pgood_s2 : std_logic;   -- 2-FF sync, pgood_pad
    signal field_s1, field_s2 : std_logic;   -- 2-FF sync, field_detect
    signal strap_s1, strap_s2 : std_logic;   -- 2-FF sync, strap_pad
    signal strap_sampled : std_logic;        -- one-shot latched strap ('1' = harvest)
    signal strap_valid   : std_logic;        -- sample complete
    signal strap_cnt     : natural range 0 to 65535;
    signal wake_cr       : std_logic_vector(4 downto 0);  -- PWRWAKE bits 4:0
    signal rls_latch     : std_logic;        -- sticky release (one-shot mode)
    signal boot_hold_r   : std_logic;        -- registered gate state ('1' = hold)

begin

    -- A2 coverage asserts (elaboration-time constants; no hardware): the
    -- PWRCR gate bits must fit one 32-bit word, and PWRCR + the PWRSR array
    -- must fit the 16 decoded words (addr(3:0)).
    assert NHARTS >= 2 and NHARTS <= 32
        report "pwr_ctrl: NHARTS out of range (PWRCR is one 32-bit word)"
        severity failure;
    assert 1 + NSRW <= 16
        report "pwr_ctrl: PWRSR array outgrows the 16-word decode"
        severity failure;
    -- DP-S3: PWRWAKE/PWRSTS sit at fixed words 5/6 — PWRSR must stay below
    assert NSRW < 5
        report "pwr_ctrl: PWRSR array collides with PWRWAKE/PWRSTS (words 5/6)"
        severity failure;

    rdata     <= rdata_reg;
    pd_iso_en <= iso_r;
    pd_sleep  <= sleep_r;
    pd_rstn   <= rstn_r;
    -- DP-S3: registered (glitch-free) boot gate; reset value '1' = release.
    pgood_rstn <= not boot_hold_r;

    pwr_proc: process(clk, resetn)
        -- A2: sr is the concatenated PWRSR word array (hart h's nibble at
        -- 4h, 8 harts per 32-bit word — one word at the NHARTS=4 default)
        variable sr   : std_logic_vector(NSRW*32-1 downto 0);
        variable widx : integer range 0 to 15;
        -- DP-S3 effective-policy terms (strap OR software override)
        variable strap_harvest : std_logic;
        variable eff_arm       : std_logic;
        variable eff_pgood     : std_logic;
        variable eff_field     : std_logic;
        variable eff_rehold    : std_logic;
        variable rls_now       : std_logic;
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
            -- DP-S3: gate released at reset (normal boots unperturbed); a
            -- harvested board self-arms within the strap settle window and
            -- the re-hold is a clean M12 cold boot.
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
            rls_latch     <= '0';
            boot_hold_r   <= '0';
        elsif rising_edge(clk) then

            -- ---- register access (1-cycle registered read) ----
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
                    -- PWRSR0..NSRW-1 at +0x4.. (one word at NHARTS=4)
                    rdata_reg <= sr(32*widx - 1 downto 32*(widx-1));
                elsif widx = W_PWRWAKE then
                    -- DP-S3 PWRWAKE readback
                    rdata_reg(4 downto 0) <= wake_cr;
                elsif widx = W_PWRSTS then
                    -- DP-S3 PWRSTS (RO)
                    rdata_reg(0) <= pgood_s2;
                    rdata_reg(1) <= field_s2;
                    rdata_reg(2) <= strap_sampled;
                    rdata_reg(3) <= strap_valid;
                    rdata_reg(4) <= boot_hold_r;
                    rdata_reg(5) <= rls_latch;
                end if;                        -- reserved words read 0

                -- PWRCR write (qualified by byte lane 0 — the gate bits are
                -- ONE field even when NHARTS-1:1 spans lanes, so software
                -- uses full-word stores; bit 0 — hart 0 — has no storage,
                -- so it can never be gated)
                if widx = 0 and we(0) = '1' then
                    gate_req <= wdata(NHARTS-1 downto 1);
                end if;
                -- DP-S3 PWRWAKE write (byte-lane-0-qualified like PWRCR)
                if widx = W_PWRWAKE and we(0) = '1' then
                    wake_cr <= wdata(4 downto 0);
                end if;
            end if;

            -- ---- per-tile MTCMOS sequencers ----
            for h in 1 to NHARTS-1 loop
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

            -- ---- DP-S3: boot gate + wake sources -------------------------
            -- 2-FF synchronizers (pad-side inputs are async)
            pgood_s1 <= pgood_pad;
            pgood_s2 <= pgood_s1;
            field_s1 <= field_detect;
            field_s2 <= field_s1;
            strap_s1 <= strap_pad;
            strap_s2 <= strap_s1;

            -- one-shot strap sample, STRAP_SETTLE cycles after reset release
            if strap_valid = '0' then
                if strap_cnt = STRAP_SETTLE then
                    strap_sampled <= strap_s2;      -- '1' = harvested boot
                    strap_valid   <= '1';
                else
                    strap_cnt <= strap_cnt + 1;
                end if;
            end if;

            -- strap drives hardware defaults; PWRWAKE bits OR-in software
            -- overrides (a harvested board self-arms with zero software:
            -- arm + wait-on-PGOOD + brownout re-hold)
            strap_harvest := strap_valid and strap_sampled;
            eff_arm    := wake_cr(0) or strap_harvest;      -- GATE_EN
            eff_pgood  := wake_cr(1) or strap_harvest;      -- RLS_PGOOD
            eff_field  := wake_cr(2);                       -- RLS_FIELD
            eff_rehold := wake_cr(4) or strap_harvest;      -- REHOLD

            rls_now := wake_cr(3)                           -- SW_RELEASE
                       or (eff_pgood and pgood_s2)
                       or (eff_field and field_s2);
            rls_latch <= rls_latch or rls_now;

            -- REHOLD=1: hold tracks the live release condition (drop =
            -- re-hold = cold boot on return). REHOLD=0: one-shot — once
            -- released, stays released. With no release source enabled an
            -- armed gate holds until SW_RELEASE (the "prove it holds"
            -- negctrl relies on this).
            if eff_rehold = '1' then
                boot_hold_r <= eff_arm and not rls_now;
            else
                boot_hold_r <= eff_arm and not (rls_latch or rls_now);
            end if;
        end if;
    end process;

end architecture;
