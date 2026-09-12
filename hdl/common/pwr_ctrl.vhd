-- VestaRV: power controller
-- Arbiter slave at page-0 slot 11 (0x4B00) holding one gate-request bit per tile hart, plus a per-tile FSM driving the tile's MTCMOS controls in the only legal order. GATE (PWRCR bit h := 1) is iso_en=1, then rstn=0, then sleep=1; WAKE (bit h := 0) is sleep=0, then T_RAIL settle, then iso_en=0, then rstn=1.
-- Hart 0, the management hart owning SPI boot, the console and the CLINT, is ALWAYS-ON: its PWRCR bit reads 0 and ignores writes, and its tile instance ties the pd_* ports inactive at the top level.
-- Cold gate, NO RETENTION: a gated tile loses all state, and pd_rstn accompanies the power sequence on BOTH edges, so the domain is held in reset while unpowered and while its rail ramps; on wake the tile re-runs the ROM boot and the management hart relaunches it. Software must gate only a parked or quiesced tile: a violation cannot deadlock the hardware but destroys the tile's in-flight work. A gate request taken mid-sequence completes the sequence first, and PWRSR shows the state.
-- Reset values EQUAL the clamp values: the tile's outbound boundary registers reset to 0 and sh_req is qualified by the tile's resetn, so a reset-held tile is bus-silent, exactly like the isolation clamp the arbiter sees when the domain is really off. Reset is therefore the honest sim model of the power cycle; the HEAD switch fabric and the CPF-inserted boundary clamps do the electrical work.
-- Field-power boot gate: pgood_rstn, reset '1' meaning release, is ANDed into EVERY hart's outer reset at the top level, hart 0 included; tying pgood_pad = '1', strap_pad = '0' and field_detect = '0' makes the whole gate a no-op. Bus is active-high one-cycle en, four resv-gated byte lanes, 1-cycle registered read on free-running mclk, and it resets all-ON, so the block is a no-op until software sets a PWRCR bit.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
library work;
use work.Constants.all;   -- word_array, the one shared array-of-word type
-- Word offsets, field ranges, resets and the periph_regs tables: generated from hdl/common/regs/rdl/pwr_ctrl.rdl.
-- The tables are FUNCTIONS of NHARTS, not constants, because the register set is: see hdl/common/regs/REGFILE.md.
use work.pwr_ctrl_regs_pkg.all;

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
        -- The high index is FLOORED AT 1 so the range is never null.
        -- At NHARTS = 1 there are no gateable rows and NHARTS-1 downto 1 would be 0 downto 1, an empty range.
        -- That is legal VHDL and it simulates, but Genus rejects a PORT with an empty range outright (CDFG-235), so a single-hart chip could elaborate and boot and still not synthesize.
        -- maximum() is the VHDL-2008 std.standard function and both toolchains here read 2008 (ghdl --std=08, genus hdl_vhdl_read_version 2008); for every NHARTS >= 2 it returns NHARTS-1 and the width is unchanged.
        pd_iso_en : out std_logic_vector(maximum(NHARTS-1, 1) downto 1);
        pd_sleep  : out std_logic_vector(maximum(NHARTS-1, 1) downto 1);
        pd_rstn   : out std_logic_vector(maximum(NHARTS-1, 1) downto 1);

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

    /* PD_HI is the per-tile-row high index, FLOORED AT 1 so the range is never null.
       At NHARTS = 1 there are no gateable rows and NHARTS-1 downto 1 is an empty range: legal VHDL that SIMULATES, which is why the single-hart chip elaborates and boots, but synthesis rejects it two separate ways. A PORT with an empty range is refused outright (Genus CDFG-235), and an `others` aggregate assigned to an empty-range target leaves the tool unable to infer the aggregate's bounds (CDFG-252).
       For every NHARTS >= 2 PD_HI is exactly NHARTS-1, so every declaration below is unchanged on every multi-hart configuration. maximum() is the VHDL-2008 std.standard function and both toolchains here read 2008.
       EVERY per-tile-row object below carries PD_HI, including the PWRCR gate_req and TASKWKM task_wkm vectors and the rdata_reg/wdata slices they exchange bits with, because Genus cannot bound a null slice of a constant either and a half-floored block does not elaborate.
       Since the register file became periph_regs (report P4) the floor costs nothing software can see: the IMPL table is `bitRun(NHARTS-1, 1)`, which is EMPTY at NHARTS = 1, so PWRCR bit 1 and TASKWKM bit 1 hold no flop and read back reserved zero as the register map says. PD_HI survives only as the slice bound the pd_* ports and the per-tile arrays need. */
    constant PD_HI : natural := maximum(NHARTS-1, 1);

    -- FSM state encodings, identical to the PWRSR nibble values documented above.
    constant S_ON     : std_logic_vector(3 downto 0) := x"0";
    constant S_ISO    : std_logic_vector(3 downto 0) := x"1";
    constant S_RSTOFF : std_logic_vector(3 downto 0) := x"2";
    constant S_OFF    : std_logic_vector(3 downto 0) := x"3";
    constant S_RAIL   : std_logic_vector(3 downto 0) := x"4";
    constant S_UNISO  : std_logic_vector(3 downto 0) := x"5";

    -- One sequencer state and one delay counter per gateable tile.
    type state_arr_t is array(1 to PD_HI) of std_logic_vector(3 downto 0);
    type cnt_arr_t   is array(1 to PD_HI) of natural range 0 to 65535;

    -- The bus side is one periph_regs instance carrying pwr_ctrl_regs_pkg's tables;
    -- see hdl/common/regs/REGFILE.md. What is left in this file is the sequencers,
    -- the strap sampler and the boot gate.
    constant NW : natural := NWORDS(NHARTS);
    subtype  reg_arr_t is word_array(0 to NW-1);
    signal regs_q    : reg_arr_t;                        -- PWRCR, PWRWAKE and TASKWKM storage
    signal hw_rd_s   : reg_arr_t;                        -- PWRSR and PWRSTS, which hold no flop here
    signal hw_clr_s  : reg_arr_t;                        -- the event fabric's task-wake clear on PWRCR
    signal inhib_s   : std_logic_vector(0 to NW-1);      -- every write in this block is byte-lane-0 qualified
    signal sr_words  : reg_arr_t;                        -- the PWRSR nibble words, assembled from state
    signal en_n      : std_logic;                        -- the module's select and lanes are ACTIVE LOW
    signal wen_n     : std_logic_vector(3 downto 0);
    signal mab       : std_logic_vector(7 downto 2);     -- the 4-bit word offset in the module's 6-bit slot

    signal state     : state_arr_t;
    signal cnt       : cnt_arr_t;
    signal gate_req  : std_logic_vector(PD_HI downto 1);   -- PWRCR gate bits.
    -- These three carry the SAME floor as the pd_* ports they drive, so the assignments stay width-exact at NHARTS = 1.
    -- At NHARTS = 1 the reset branch drives them and the per-tile loops (1 to NHARTS-1) never run, so the floored bit is a constant that synthesis folds away rather than an undriven register.
    signal iso_r     : std_logic_vector(PD_HI downto 1);   -- Registered pd_iso_en.
    signal sleep_r   : std_logic_vector(PD_HI downto 1);   -- Registered pd_sleep.
    signal rstn_r    : std_logic_vector(PD_HI downto 1);   -- Registered pd_rstn.

    -- Boot-gate and wake-source state, all on the always-on domain; word offsets as in the header map.
    -- The three async pad inputs cross into mclk through one work.sync instance; bit 2 is pgood, bit 1 field, bit 0 strap, and PAD_RST keeps the boot gate released out of reset.
    -- PAD_RST carries explicit downto bounds on purpose: sync normalises RST_VAL from v'low upward, so a bare string literal, whose bounds are ascending, would land reversed.
    constant PAD_RST : std_logic_vector(2 downto 0) := "100";
    signal pad_sync_d : std_logic_vector(2 downto 0);
    signal pad_sync_q : std_logic_vector(2 downto 0);
    signal pgood_s2 : std_logic;   -- Synchronized pgood_pad.
    signal field_s2 : std_logic;   -- Synchronized field_detect.
    signal strap_s2 : std_logic;   -- Synchronized strap_pad.
    signal strap_sampled : std_logic;        -- One-shot latched strap ('1' = harvest).
    signal strap_valid   : std_logic;        -- Strap sample complete.
    signal strap_cnt     : natural range 0 to 65535;   -- Counts out STRAP_SETTLE.
    signal wake_cr       : std_logic_vector(4 downto 0);  -- PWRWAKE bits 4:0, read out of the register file.
    signal task_wkm      : std_logic_vector(PD_HI downto 1);  -- Task-wake mask, likewise.
    signal rls_latch     : std_logic;        -- Sticky release, one-shot mode.
    signal boot_hold_r   : std_logic;        -- Registered gate state ('1' = hold).

begin

    -- Coverage asserts on elaboration-time constants, so no hardware is built.
    -- The PWRCR gate bits must fit one 32-bit word, and PWRCR plus the PWRSR array must fit the eight decoded words of the register file.
    -- NHARTS = 1 IS LEGAL and is the single-hart MCU_hart shape: there are no gateable tiles, so every per-tile object here is a null range and every per-tile loop runs zero times.
    -- The block is still instantiated at NHARTS = 1 because the FIELD-POWER BOOT GATE above it (PWRWAKE, PWRSTS, pgood_rstn) is not per-tile hardware and every configuration has it.
    -- PWRCR then degenerates to its reserved always-on bit 0, and PWRSR0 to the all-zero hart-0 nibble, which is what the register map says a single-hart chip has.
    assert NHARTS >= 1 and NHARTS <= 32
        report "pwr_ctrl: NHARTS out of range (PWRCR is one 32-bit word)"
        severity failure;
    assert 1 + NSRW <= NW
        report "pwr_ctrl: PWRSR array outgrows the register file"
        severity failure;
    -- PWRWAKE and PWRSTS sit at fixed words 5 and 6, so PWRSR must stay below them.
    assert NSRW < 5
        report "pwr_ctrl: PWRSR array collides with PWRWAKE/PWRSTS (words 5/6)"
        severity failure;

    -- Registered outputs straight out to the MTCMOS controls; rdata comes out of
    -- the register file below.
    pd_iso_en <= iso_r;
    pd_sleep  <= sleep_r;
    pd_rstn   <= rstn_r;
    -- Registered, glitch-free boot gate; reset value '1' releases.
    pgood_rstn <= not boot_hold_r;

    -- ---- Register file -------------------------------------------------------
    -- The eight-word decode, the byte-lane merge and the one-cycle registered read
    -- are periph_regs', driven by the tables pwr_ctrl_regs_pkg builds from NHARTS.
    -- This block's bus is ACTIVE HIGH (arbiter slave), the module's is active low.
    -- Every write here is byte-lane-0 qualified and writes the WHOLE field even
    -- where the gate mask spans lanes (argus, 18 harts), which is WIDEWR on the
    -- three written words plus wr_inhibit off lane 0: WIDEWR widens the write to
    -- 32 bits and the inhibit refuses a write that lane 0 does not carry, which
    -- together are `if widx = 0 and we(0) = '1' then gate_req <= wdata(...)`.
    en_n    <= not en;
    wen_n   <= not we;
    mab     <= "00" & addr;
    inhib_s <= (others => not we(0));

    -- PWRSR is one read-only 4-bit state nibble per hart, 8 harts to a word, at
    -- words 1 .. NSRW; every other word above PWRCR reads 0 or its own storage.
    sr_proc: process(state)
    begin
        sr_words <= (others => (others => '0'));
        for h in 1 to NHARTS-1 loop
            sr_words(1 + h/8)(4*(h mod 8) + 3 downto 4*(h mod 8)) <= state(h);
        end loop;
    end process;

    rd_proc: process(sr_words, pgood_s2, field_s2, strap_sampled, strap_valid,
                     boot_hold_r, rls_latch)
    begin
        hw_rd_s <= (others => (others => '0'));
        for w in 1 to NSRW loop
            hw_rd_s(w) <= sr_words(w);
        end loop;
        hw_rd_s(W_PWRSTS)(PWPGOODLIV_LSB)  <= pgood_s2;
        hw_rd_s(W_PWRSTS)(PWFIELDLIV_LSB)  <= field_s2;
        hw_rd_s(W_PWRSTS)(PWSTRAP_LSB)     <= strap_sampled;
        hw_rd_s(W_PWRSTS)(PWSTRAPVLD_LSB)  <= strap_valid;
        hw_rd_s(W_PWRSTS)(PWBOOTHOLD_LSB)  <= boot_hold_r;
        hw_rd_s(W_PWRSTS)(PWRRLSLATCH_LSB) <= rls_latch;
    end process;

    -- The event fabric's task-wake tap CLEARS the gate bits TASKWKM selects. It is
    -- a hook and not a write, so periph_regs resolves it AFTER a coincident CPU
    -- write, which is the order the hand-written process had.
    clr_proc: process(task_wake, task_wkm)
    begin
        hw_clr_s <= (others => (others => '0'));
        if task_wake = '1' then
            hw_clr_s(PWRCR_WORD)(PD_HI downto 1) <= task_wkm;
        end if;
    end process;

    u_regs: entity work.periph_regs
        generic map (
            NWORDS      => NW,
            RSTVAL      => RSTVAL(NHARTS),
            IMPL        => IMPL(NHARTS),
            W1C         => W1C(NHARTS),
            WOSET       => WOSET(NHARTS),
            WOT         => WOT(NHARTS),
            PULSE       => PULSE(NHARTS),
            RCLR        => RCLR(NHARTS),
            HWOWN       => HWOWN(NHARTS),
            WIDEWR      => "10000101")
        port map (
            ClkMem      => clk,
            resetn      => resetn,
            EnMemPeriph => en_n,
            WEn         => wen_n,
            MABPart     => mab,
            wdata       => wdata,
            rdata_out   => rdata,
            regs        => regs_q,
            wr_inhibit  => inhib_s,
            hw_rd       => hw_rd_s,
            hw_clr      => hw_clr_s,
            acc_hit     => open,
            rd_hit      => open,
            wr_hit      => open,
            rd_strobe   => open,
            wr_strobe   => open,
            wr_pulse    => open,
            w1c_hit     => open,
            woset_hit   => open,
            wot_hit     => open,
            rd_clr      => open);

    -- The three stored words, sliced out for the datapath. No bit literal survives.
    gate_req <= regs_q(PWRCR_WORD)(PD_HI downto 1);
    task_wkm <= regs_q(W_TASKWKM)(PD_HI downto 1);
    wake_cr  <= regs_q(W_PWRWAKE)(PWREHOLD_MSB downto PWGATEEN_LSB);

    -- Boot-gate wake sources: the pad-side inputs are asynchronous to mclk, so all three cross through the house synchroniser.
    pad_sync_d <= pgood_pad & field_detect & strap_pad;
    u_sync_pads : entity work.sync
        generic map (WIDTH => 3, DEPTH => 2, RST_VAL => PAD_RST)
        port map (clk => clk, areset => resetn, d => pad_sync_d, q => pad_sync_q);
    pgood_s2 <= pad_sync_q(2);
    field_s2 <= pad_sync_q(1);
    strap_s2 <= pad_sync_q(0);

    -- Per-tile MTCMOS sequencers, the strap sampler and the boot gate, all on mclk.
    -- The register file is the periph_regs instance above.
    pwr_proc: process(clk, resetn)
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
            -- PWRCR, PWRWAKE and TASKWKM reset inside periph_regs, on the RSTVAL table.
            iso_r     <= (others => '0');
            sleep_r   <= (others => '0');
            rstn_r    <= (others => '1');
            state     <= (others => S_ON);
            cnt       <= (others => 0);
            -- The boot gate is released at reset so normal boots are unperturbed (RST_VAL on u_sync_pads).
            -- A harvested board self-arms within the strap settle window, and the re-hold is a clean cold boot.
            strap_sampled <= '0';
            strap_valid   <= '0';
            strap_cnt     <= 0;
            rls_latch     <= '0';
            boot_hold_r   <= '0';
        elsif rising_edge(clk) then

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
