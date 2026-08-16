-------------------------------------------------------------------------------
-- TRNG_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the TRNG peripheral (hdl/common/periph/TRNG.vhd) and its companion entropy source periph/TrngRoEnsemble_sim.vhd, which is instantiated here as a SIBLING of the DUT and wired through TRNG's genuine ro_enable/ro_sel/ro_sclk/ro_raw ports, never nested inside it.
-- Both are declared as COMPONENTs so this bench compiles standalone with xmvhdl regardless of analysis order; a plain configuration specification binds u_ro to the sim architecture.
-- The stuck-entropy case is driven by a bench-owned override mux (g5_force_en/g5_force_val) on the wire from u_ro into dut, which is -V200X-portable where a hierarchical force or an external name is not.
-- CHECKER INDEPENDENCE: the ref_* model is a clean-room mirror of the 2-FF sync, decimator, 32-bit assembler and consume/pending logic, built only from trng_bfm_pkg constants and this bench's own shadow of what it commanded; it never reads a DUT-internal signal, and health-test/alarm behavior is deliberately not modelled.
-- ONE clock family: clk hosts the whole harvest engine and ClkMem is the gated bus clock, driven `clk when pbus.en_mem='0' else '0'`.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.trng_bfm_pkg.all;

entity TRNG_tb is
    generic ( NRO_G : natural := 8 );   -- {4,8} shape knob; the shape proof re-elaborates this bench at 4
end entity TRNG_tb;

architecture sim of TRNG_tb is

    constant PERIOD : time := 20 ns;   -- clk reference

    -- DUT declared as a component so the bench compiles standalone regardless of when TRNG.vhd is analyzed.
    component TRNG is
        generic ( NRO : natural := 8 );
        port (
            clk         : in  std_logic;
            resetn      : in  std_logic;
            irq_trng    : out std_logic;
            ClkMem      : in  std_logic;
            EnMemPeriph : in  std_logic;
            WEn         : in  std_logic_vector(3 downto 0);
            MABPart     : in  std_logic_vector(7 downto 2);
            wdata       : in  std_logic_vector(31 downto 0);
            rdata_out   : out std_logic_vector(31 downto 0);
            ro_enable   : out std_logic;
            ro_sel      : out std_logic_vector(3 downto 0);
            ro_sclk     : out std_logic;
            ro_raw      : in  std_logic;
            evt_drdy    : out std_logic
        );
    end component;

    -- Companion entropy-source model, instantiated as a sibling of the DUT.
    component TrngRoEnsemble is
        generic ( NRO : natural := 8 );
        port (
            enable : in  std_logic;
            sel    : in  std_logic_vector(3 downto 0);
            sclk   : in  std_logic;
            ro_raw : out std_logic
        );
    end component;

    -- Explicit binding: a plain configuration specification, legal only because u_ro is a direct instantiation of THIS architecture and not nested inside the DUT.
    for u_ro : TrngRoEnsemble use entity work.TrngRoEnsemble(sim);

    -- clocks / reset
    signal clk    : std_logic := '0';
    signal ClkMem : std_logic := '0';
    signal resetn : std_logic := '0';

    -- interrupt
    signal irq_trng : std_logic;

    -- ---- event-fabric producer tap ---------------------------------------
    signal evt_drdy : std_logic;

    -- register bus (BFM record + observed rdata_out)
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal rdata_out : std_logic_vector(31 downto 0);

    -- entropy-source interconnect
    signal ro_enable_w : std_logic;
    signal ro_sel_w    : std_logic_vector(3 downto 0);
    signal ro_sclk_w   : std_logic;
    signal ro_raw_natural : std_logic;   -- u_ro's own output
    signal ro_raw_to_dut  : std_logic;   -- what actually reaches dut.ro_raw

    -- stuck-source override: bench-owned mux on the wire into dut.ro_raw
    signal g5_force_en  : std_logic := '0';
    signal g5_force_val : std_logic := '0';

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

    ---------------------------------------------------------------------------
    -- Reference-replay model: shadow copies of what this bench commanded, driven by set_cr/read_dr below.
    ---------------------------------------------------------------------------
    signal ref_en    : std_logic := '0';
    signal ref_sel   : std_logic_vector(3 downto 0) := (others => '0');
    signal ref_decim : std_logic_vector(3 downto 0) := (others => '0');

    signal ref_lfsr  : std_logic_vector(31 downto 0) := (others => '0');
    signal ref_s1, ref_s2 : std_logic := '0';
    signal ref_sync  : std_logic := '0';

    signal ref_decim_reload : std_logic_vector(15 downto 0) := (others => '0');
    signal ref_samp_cnt     : std_logic_vector(15 downto 0) := (others => '0');
    signal ref_sample_tick  : std_logic := '0';

    signal ref_asm_reg : std_logic_vector(31 downto 0) := (others => '0');
    signal ref_asm_cnt : natural range 0 to 32 := 0;
    signal ref_word       : std_logic_vector(31 downto 0) := (others => '0');
    signal ref_word_valid : std_logic := '0';

    signal ref_dr_read_req      : std_logic := '0';
    signal ref_consume_pending  : std_logic := '0';
    signal ref_consume_tgl      : std_logic := '0';
    signal rc1, rc2, rcprev     : std_logic := '0';
    signal ref_consume_pulse    : std_logic := '0';

begin

    ----------------------------------------------------------------------------
    -- clock / gated register-bus clock
    ----------------------------------------------------------------------------
    clk    <= not clk after PERIOD / 2;
    ClkMem <= clk when pbus.en_mem = '0' else '0';

    -- The value reaching dut.ro_raw is either u_ro's genuine output or the bench-forced constant.
    ro_raw_to_dut <= g5_force_val when g5_force_en = '1' else ro_raw_natural;

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    dut : component TRNG
        generic map ( NRO => NRO_G )
        port map (
            clk         => clk,
            resetn      => resetn,
            irq_trng    => irq_trng,
            ClkMem      => ClkMem,
            EnMemPeriph => pbus.en_mem,
            WEn         => pbus.wen,
            MABPart     => pbus.addr_periph,
            wdata       => pbus.write_data,
            rdata_out   => rdata_out,
            ro_enable   => ro_enable_w,
            ro_sel      => ro_sel_w,
            ro_sclk     => ro_sclk_w,
            ro_raw      => ro_raw_to_dut,
            evt_drdy    => evt_drdy
        );

    ----------------------------------------------------------------------------
    -- Companion entropy-source model
    ----------------------------------------------------------------------------
    u_ro : component TrngRoEnsemble
        generic map ( NRO => NRO_G )
        port map (
            enable => ro_enable_w,
            sel    => ro_sel_w,
            sclk   => ro_sclk_w,
            ro_raw => ro_raw_natural
        );

    ----------------------------------------------------------------------------
    -- Watchdog: abort with a FAIL banner if the stimulus ever hangs.
    ----------------------------------------------------------------------------
    watchdog : process
    begin
        wait for 60 ms;
        if not tb_done then
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   TRNG_TB FAIL (WATCHDOG TIMEOUT -- stimulus never finished)" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
            stop;
        end if;
        wait;
    end process;

    ----------------------------------------------------------------------------
    -- Reference-replay model: a clean-room mirror of the 2-FF sync, decimator, 32-bit assembler and consume/pending logic.
    -- It is driven ONLY by this bench's own shadow signals (ref_en/ref_sel/ref_decim from `set_cr`) and its own record of qualifying DR reads (`ref_dr_read_req` from `read_dr`), never by a DUT-internal signal.
    ----------------------------------------------------------------------------

    -- LFSR mirror: identical recurrence to TrngRoEnsemble_sim.vhd, re-seeded whenever the reference is disabled.
    ref_lfsr_proc: process(ref_en, clk)
    begin
        if ref_en = '0' then
            ref_lfsr <= trng_seed_perturbed(ref_sel);
        elsif rising_edge(clk) then
            ref_lfsr <= trng_ref_lfsr_step(ref_lfsr);
        end if;
    end process ref_lfsr_proc;

    -- 2-FF sync of the reference raw bit.
    ref_cdc: process(resetn, clk)
    begin
        if resetn = '0' then
            ref_s1 <= '0'; ref_s2 <= '0';
        elsif rising_edge(clk) then
            ref_s1 <= ref_lfsr(0); ref_s2 <= ref_s1;
        end if;
    end process ref_cdc;
    ref_sync <= ref_s2;

    -- Decimator reload lookup, identical table to TRNG.vhd.
    ref_decim_lut: process(ref_decim)
    begin
        case ref_decim is
            when "0000" => ref_decim_reload <= x"0000";
            when "0001" => ref_decim_reload <= x"0001";
            when "0010" => ref_decim_reload <= x"0003";
            when "0011" => ref_decim_reload <= x"0007";
            when "0100" => ref_decim_reload <= x"000F";
            when "0101" => ref_decim_reload <= x"001F";
            when "0110" => ref_decim_reload <= x"003F";
            when "0111" => ref_decim_reload <= x"007F";
            when "1000" => ref_decim_reload <= x"00FF";
            when "1001" => ref_decim_reload <= x"01FF";
            when "1010" => ref_decim_reload <= x"03FF";
            when "1011" => ref_decim_reload <= x"07FF";
            when "1100" => ref_decim_reload <= x"0FFF";
            when "1101" => ref_decim_reload <= x"1FFF";
            when "1110" => ref_decim_reload <= x"3FFF";
            when "1111" => ref_decim_reload <= x"7FFF";
            when others => ref_decim_reload <= x"0000";
        end case;
    end process ref_decim_lut;

    -- Sample-rate decimator: counts the reload value down and ticks at zero.
    ref_decimator: process(resetn, clk)
    begin
        if resetn = '0' then
            ref_samp_cnt    <= (others => '0');
            ref_sample_tick <= '0';
        elsif rising_edge(clk) then
            if ref_en = '1' then
                if ref_samp_cnt = x"0000" then
                    ref_samp_cnt    <= ref_decim_reload;
                    ref_sample_tick <= '1';
                else
                    ref_samp_cnt    <= std_logic_vector(unsigned(ref_samp_cnt) - 1);
                    ref_sample_tick <= '0';
                end if;
            else
                ref_samp_cnt    <= ref_decim_reload;
                ref_sample_tick <= '0';
            end if;
        end if;
    end process ref_decimator;

    -- 32-bit assembler, stalling while a completed word is still unconsumed.
    ref_assembler: process(resetn, clk)
    begin
        if resetn = '0' then
            ref_asm_reg    <= (others => '0');
            ref_asm_cnt    <= 0;
            ref_word       <= (others => '0');
            ref_word_valid <= '0';
        elsif rising_edge(clk) then

            if ref_asm_cnt = 32 then
                if ref_word_valid = '0' then
                    ref_word       <= ref_asm_reg;
                    ref_word_valid <= '1';
                    ref_asm_cnt    <= 0;
                end if;
            elsif ref_sample_tick = '1' then
                if ref_asm_cnt = 31 then
                    if ref_word_valid = '0' then
                        ref_word       <= ref_asm_reg(30 downto 0) & ref_sync;
                        ref_word_valid <= '1';
                        ref_asm_cnt    <= 0;
                    else
                        ref_asm_reg <= ref_asm_reg(30 downto 0) & ref_sync;
                        ref_asm_cnt <= 32;
                    end if;
                else
                    ref_asm_reg <= ref_asm_reg(30 downto 0) & ref_sync;
                    ref_asm_cnt <= ref_asm_cnt + 1;
                end if;
            end if;

            if ref_consume_pulse = '1' then
                ref_word_valid <= '0';
            end if;

        end if;
    end process ref_assembler;

    -- A qualifying read raises pending and flips the consume toggle; `read_dr` pulses ref_dr_read_req in lockstep with the real DR read.
    ref_consume_mirror: process(resetn, clk)
    begin
        if resetn = '0' then
            ref_consume_pending <= '0';
            ref_consume_tgl     <= '0';
        elsif rising_edge(clk) then
            if ref_consume_pending = '1' and ref_word_valid = '0' then
                ref_consume_pending <= '0';
            end if;
            if ref_dr_read_req = '1' then
                if ref_word_valid = '1' and ref_consume_pending = '0' then
                    ref_consume_pending <= '1';
                    ref_consume_tgl     <= not ref_consume_tgl;
                end if;
            end if;
        end if;
    end process ref_consume_mirror;

    -- 2-FF sync of the consume toggle plus the edge detect that becomes ref_consume_pulse.
    ref_consume_cdc: process(resetn, clk)
    begin
        if resetn = '0' then
            rc1 <= '0'; rc2 <= '0'; rcprev <= '0';
        elsif rising_edge(clk) then
            rc1 <= ref_consume_tgl; rc2 <= rc1; rcprev <= rc2;
        end if;
    end process ref_consume_cdc;
    ref_consume_pulse <= '1' when (rc2 /= rcprev) else '0';

    ----------------------------------------------------------------------------
    -- stimulus
    ----------------------------------------------------------------------------
    stim_proc : process
        variable rdw, exp_word : std_logic_vector(31 downto 0);
        variable ok            : boolean;
        variable quiet_ok      : boolean;

        -- Write TRNG0CR and advance the reference model's shadow copies in lockstep, at the same cycle alignment as the DUT's own trng_cr commit.
        procedure set_cr(en, drdyie, almie : std_logic;
                         rosel : std_logic_vector(3 downto 0);
                         decim : std_logic_vector(3 downto 0)) is
        begin
            bus_write(clk, pbus, TRNG_SLOT_CR, trng_mk_cr(en, drdyie, almie, rosel, decim));
            ref_en    <= en;
            ref_sel   <= rosel;
            ref_decim <= decim;
        end procedure;

        -- TRNG0HT.RCTC write (bits 7:0; RUNLEN is ro, unaffected).
        procedure write_ht(rctc : std_logic_vector(7 downto 0)) is
        begin
            bus_write(clk, pbus, TRNG_SLOT_HT, (31 downto 8 => '0') & rctc);
        end procedure;

        -- W1C the ALMF bit, then wait out the clr_almf_tgl 2-FF sync and edge detect before the caller relies on the flag being clear.
        procedure w1c_almf is
        begin
            bus_write(clk, pbus, TRNG_SLOT_SR, x"00000002");
            wait for 6 * PERIOD;
        end procedure;

        -- Qualifying DR read, mirrored into the reference model the SAME cycle: ref_dr_read_req is asserted before the rising edge the real bus transaction captures on.
        procedure read_dr(data : out std_logic_vector(31 downto 0)) is
        begin
            wait until clk = '0';
            pbus.addr_periph <= std_logic_vector(to_unsigned(TRNG_SLOT_DR, 6));
            pbus.en_mem      <= '0';
            ref_dr_read_req  <= '1';
            wait until clk = '1';
            wait until clk = '0';
            data := rdata_out;
            pbus.en_mem     <= '1';
            ref_dr_read_req <= '0';
        end procedure;

        -- Full chip-reset pulse, reusable between independent health-test sub-phases.
        -- Only resetn clears the RCT run-length counter and have_prev state, so carrying them across an EN toggle or an ALMF W1C would let a stale high run_len instantly re-trip a later, lower cutoff.
        procedure do_reset is
        begin
            resetn      <= '0';
            pbus        <= PERIPH_BUS_IDLE;
            g5_force_en <= '0';
            ref_en      <= '0';
            wait for 12 * PERIOD;
            wait for 1 ns;
            resetn <= '1';
            wait for 8 * PERIOD;
        end procedure;

    begin
        ------------------------------------------------------------------
        -- Reset
        ------------------------------------------------------------------
        resetn <= '0';
        pbus   <= PERIPH_BUS_IDLE;
        wait for 12 * PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 8 * PERIOD;

        report "=== TRNG_TB: NRO_G = " & integer'image(NRO_G) & " ===" severity note;

        ------------------------------------------------------------------
        -- GROUP G0: reset defaults
        ------------------------------------------------------------------
        report "=== GROUP G0: reset defaults ===" severity note;
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_CR, rdw);
        sb.check_slv("G0: CR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_SR, rdw);
        sb.check_slv("G0: SR resets to 0 (DRDY/ALMF/RUN all 0 at reset)", rdw, x"00000000");
        read_dr(rdw);
        sb.check_slv("G0: DR empty read #1 returns 0", rdw, x"00000000");
        read_dr(rdw);
        sb.check_slv("G0: DR empty read #2 returns 0 (repeatable, no side effect)", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_HT, rdw);
        sb.check_slv("G0: HT resets to 0 (RCTC=0, RUNLEN=0)", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, 4, rdw);
        sb.check_slv("G0: slot 4 (>=4) reads 0", rdw, x"00000000");
        sb.check_bit("G0: irq_trng = 0 out of reset", to_X01(irq_trng), '0');

        ------------------------------------------------------------------
        -- GROUP G1: harvest / DRDY
        ------------------------------------------------------------------
        report "=== GROUP G1: harvest / DRDY ===" severity note;
        set_cr('1', '1', '0', "0000", "0000");   -- EN=1, DRDYIE=1, ALMIE=0, ROSEL=0000 (all rings), DECIM=0
        trng_wait_drdy(clk, pbus, rdata_out, ok);
        sb.check_true("G1: DRDY sets after 32 decimated samples (bounded)", ok);
        sb.check_bit("G1: reference model's word_valid also true (independent timing match)",
                     to_X01(ref_word_valid), '1');
        sb.check_bit("G1: irq_trng asserts (DRDY & DRDYIE)", to_X01(irq_trng), '1');
        exp_word := ref_word;
        read_dr(rdw);
        sb.check_slv("G1: harvested word matches the independent LFSR replay", rdw, exp_word);

        ------------------------------------------------------------------
        -- GROUP G2: read-consume + blind window
        ------------------------------------------------------------------
        report "=== GROUP G2: read-consume + blind window ===" severity note;
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_SR, rdw);
        sb.check_bit("G2: DRDY=0 immediately after the consuming DR read (blind window closed)",
                     to_X01(rdw(TRNG_SR_DRDY)), '0');
        read_dr(rdw);
        sb.check_slv("G2: DR read while DRDY=0 returns 0, no spurious consume", rdw, x"00000000");
        trng_wait_drdy(clk, pbus, rdata_out, ok);
        sb.check_true("G2: next word still assembles after the empty read (bounded)", ok);
        exp_word := ref_word;
        read_dr(rdw);
        sb.check_slv("G2: next word delivered intact (matches replay)", rdw, exp_word);
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_SR, rdw);
        sb.check_bit("G2: DRDY=0 again after the second consume", to_X01(rdw(TRNG_SR_DRDY)), '0');

        ------------------------------------------------------------------
        -- GROUP G3: decimation
        ------------------------------------------------------------------
        report "=== GROUP G3: decimation ===" severity note;
        set_cr('1', '1', '0', "0000", "0001");   -- DECIM=1: one sample every 2 clk
        trng_wait_drdy(clk, pbus, rdata_out, ok);
        sb.check_true("G3: DECIM=1 word assembles (bounded)", ok);
        exp_word := ref_word;
        read_dr(rdw);
        sb.check_slv("G3: DECIM=1 word matches the decimated replay", rdw, exp_word);

        set_cr('1', '1', '0', "0000", "0010");   -- DECIM=2: one sample every 4 clk
        trng_wait_drdy(clk, pbus, rdata_out, ok);
        sb.check_true("G3: DECIM=2 word assembles (bounded)", ok);
        exp_word := ref_word;
        read_dr(rdw);
        sb.check_slv("G3: DECIM=2 word matches the decimated replay", rdw, exp_word);

        ------------------------------------------------------------------
        -- GROUP G4: ROSEL plumbing, a wiring/forwarding check.
        -- A NEW sel only takes effect the next time EN drops then rises again, because the entropy stub perturbs its seed at that transition.
        ------------------------------------------------------------------
        report "=== GROUP G4: ROSEL plumbing ===" severity note;
        set_cr('0', '1', '0', "0000", "0000");   -- EN=0: park, arm a fresh perturbation
        wait for 4 * PERIOD;
        set_cr('1', '1', '0', "0001", "0000");   -- new ROSEL=0001, DECIM back to 0
        trng_wait_drdy(clk, pbus, rdata_out, ok);
        sb.check_true("G4: word assembles under the new ROSEL (bounded)", ok);
        exp_word := ref_word;
        read_dr(rdw);
        sb.check_slv("G4: word matches the replay using the SAME new sel (forwarding proven)",
                     rdw, exp_word);

        ------------------------------------------------------------------
        -- GROUP G5: health alarm / RCT
        ------------------------------------------------------------------
        report "=== GROUP G5: health alarm / RCT ===" severity note;
        -- Clean resetn before each independent sub-phase: only resetn re-arms the RCT run-length counter, so a stale high run_len would instantly re-trip a later, lower cutoff.
        do_reset;
        write_ht(x"08");                          -- RCTC=8: fast trip
        g5_force_en  <= '1';
        g5_force_val <= '0';                      -- stuck raw source (bench override)
        wait for 2 ns;
        set_cr('1', '0', '1', "0000", "0000");    -- EN=1, ALMIE=1, DRDYIE=0 (avoid noise)

        trng_wait_flag(clk, pbus, rdata_out, TRNG_SR_ALMF, '1', ok);
        sb.check_true("G5: ALMF sets on a stuck run reaching RCTC=8 (bounded)", ok);
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_SR, rdw);
        sb.check_bit("G5: RUN drops once ALMF is set (auto-halt)", to_X01(rdw(TRNG_SR_RUN)), '0');
        sb.check_bit("G5: DRDY never asserted (halted before a word could complete)",
                     to_X01(rdw(TRNG_SR_DRDY)), '0');
        sb.check_bit("G5: irq_trng asserts (ALMF & ALMIE)", to_X01(irq_trng), '1');
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_HT, rdw);
        -- "At least", not "equal": the decimator-to-health-test hand-off is a registered pipeline stage, so a sample already in flight when alm_halt takes effect is still counted.
        -- RUNLEN therefore settles at cutoff or cutoff+1, never below cutoff.
        sb.check_true("G5: RUNLEN reached at least the RCTC=8 cutoff before freezing",
                      unsigned(rdw(TRNG_HT_RUNLEN_LO + 5 downto TRNG_HT_RUNLEN_LO)) >= 8);

        -- Release the stuck source AND restore the default cutoff BEFORE clearing ALMF.
        -- The run-length counter still sits at or above the low cutoff, so clearing ALMF while still forced-stuck would resume harvesting for one cycle and immediately re-trip.
        g5_force_en <= '0';
        write_ht(x"00");                          -- RCTC=0 selects the default 32 (safe headroom)
        w1c_almf;
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_SR, rdw);
        sb.check_bit("G5: ALMF clears via W1C", to_X01(rdw(TRNG_SR_ALMF)), '0');
        sb.check_bit("G5: RUN resumes once ALMF clears (EN still 1)", to_X01(rdw(TRNG_SR_RUN)), '1');
        trng_wait_drdy(clk, pbus, rdata_out, ok);
        sb.check_true("G5: harvesting resumes on the next healthy run (bounded)", ok);
        read_dr(rdw);   -- drain, no value check: the reference model does not track across an alarm

        -- The default cutoff (RCTC=0, i.e. 32) is higher than the RCTC=8 override above, so a 10-sample stuck window must NOT trip it while a continuing run does.
        -- Fresh resetn first, for clean run_len/have_prev state.
        do_reset;
        write_ht(x"00");                          -- RCTC=0 selects the default 32
        g5_force_en  <= '1';
        g5_force_val <= '1';
        wait for 2 ns;
        set_cr('1', '0', '1', "0000", "0000");
        wait for 10 * PERIOD;
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_SR, rdw);
        sb.check_bit("G5: RCTC=0(=>32) has NOT tripped after only 10 stuck samples",
                     to_X01(rdw(TRNG_SR_ALMF)), '0');
        trng_wait_flag(clk, pbus, rdata_out, TRNG_SR_ALMF, '1', ok);
        sb.check_true("G5: RCTC=0(=>32) DOES trip once the run reaches 32 (bounded)", ok);

        g5_force_en <= '0';
        w1c_almf;

        ------------------------------------------------------------------
        -- GROUP G6: IRQ demux / W1C
        -- irq_trng = (DRDY & DRDYIE) | (ALMF & ALMIE)
        ------------------------------------------------------------------
        report "=== GROUP G6: IRQ demux / W1C ===" severity note;
        do_reset;
        write_ht(x"00");                          -- default cutoff (real source, low trip risk)
        set_cr('1', '1', '1', "0000", "0000");    -- EN=1, DRDYIE=1, ALMIE=1 (real, unforced source)
        trng_wait_drdy(clk, pbus, rdata_out, ok);
        sb.check_true("G6: a legitimate word arrives from the real source (bounded)", ok);
        -- leave it UNCONSUMED (DRDY stays pending), then force a fast alarm on top of it: the alarm only gates FUTURE samples and never touches an already-completed, unconsumed dr_word.
        write_ht(x"08");
        g5_force_en  <= '1';
        g5_force_val <= '0';
        trng_wait_flag(clk, pbus, rdata_out, TRNG_SR_ALMF, '1', ok);
        sb.check_true("G6: ALMF also sets on top of the pending word (bounded)", ok);
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_SR, rdw);
        sb.check_bit("G6: DRDY still pending (untouched by the alarm)", to_X01(rdw(TRNG_SR_DRDY)), '1');
        sb.check_bit("G6: ALMF pending too", to_X01(rdw(TRNG_SR_ALMF)), '1');
        sb.check_bit("G6: irq_trng high (both sources, both IE)", to_X01(irq_trng), '1');

        -- Release the source and restore the default cutoff BEFORE the W1C, so the clear lasts instead of instantly re-tripping against the stale run_len.
        g5_force_en <= '0';
        write_ht(x"00");
        w1c_almf;
        sb.check_bit("G6: irq_trng still high after W1C ALMF (DRDY source remains)",
                     to_X01(irq_trng), '1');
        read_dr(rdw);
        sb.check_bit("G6: irq_trng drops once the DRDY source is consumed too",
                     to_X01(irq_trng), '0');

        trng_wait_drdy(clk, pbus, rdata_out, ok);
        sb.check_true("G6: a fresh word arrives for the masking check (bounded)", ok);
        set_cr('1', '0', '0', "0000", "0000");    -- DRDYIE=0, ALMIE=0: mask everything
        wait for 2 * PERIOD;
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_SR, rdw);
        sb.check_bit("G6: DRDY still pending under the mask", to_X01(rdw(TRNG_SR_DRDY)), '1');
        sb.check_bit("G6: irq_trng masked by DRDYIE=0/ALMIE=0", to_X01(irq_trng), '0');
        set_cr('1', '1', '0', "0000", "0000");    -- unmask DRDYIE
        wait for 2 * PERIOD;
        sb.check_bit("G6: irq_trng resumes once unmasked", to_X01(irq_trng), '1');
        read_dr(rdw);

        ------------------------------------------------------------------
        -- GROUP G7: NRO shape.
        -- Every group above already ran against the DUT and companion elaborated at NRO_G, and the register map is NRO-invariant, so an all-green run at NRO_G=4 IS the {4,8} shape proof.
        ------------------------------------------------------------------
        report "=== GROUP G7: NRO shape (elaborated at NRO_G) ===" severity note;
        sb.check_true("G7: NRO_G is a proven shape (4 or 8)", (NRO_G = 4) or (NRO_G = 8));

        ------------------------------------------------------------------
        -- GROUP G-EV: event-fabric producer tap. evt_drdy IS the blind-window-corrected DRDY LEVEL, pre-IE, so DRDYIE has zero effect on it, unlike irq_trng which DRDYIE masks.
        -- A held level needs no start/width pulse monitor, so it is checked at the same bus_read(SR) and read_dr settle points the rest of this bench already uses for SR.DRDY.
        ------------------------------------------------------------------
        report "=== GROUP G-EV: EVFAB producer tap (evt_drdy) ===" severity note;
        -- Fresh resetn first: a clean, deterministic starting state for an independent sub-phase.
        do_reset;
        write_ht(x"00");
        sb.check_bit("G-EV a0: evt_drdy = 0 out of reset (no word ready)", to_X01(evt_drdy), '0');

        -- G-EV-a: evt_drdy tracks DRDY exactly at this bench's own SR/DR observation points, rising when a word becomes ready and falling once it is consumed.
        set_cr('1', '1', '0', "0000", "0000");   -- EN=1, DRDYIE=1, ALMIE=0
        trng_wait_drdy(clk, pbus, rdata_out, ok);
        sb.check_true("G-EV a1: word assembles (bounded)", ok);
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_SR, rdw);
        sb.check_bit("G-EV a2: SR.DRDY reads 1", to_X01(rdw(TRNG_SR_DRDY)), '1');
        sb.check_bit("G-EV a3: evt_drdy = 1 at the same observation point SR.DRDY reads 1",
                     to_X01(evt_drdy), '1');
        read_dr(rdw);   -- consuming read
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_SR, rdw);
        sb.check_bit("G-EV a4: SR.DRDY = 0 immediately after the consuming DR read (blind window)",
                     to_X01(rdw(TRNG_SR_DRDY)), '0');
        sb.check_bit("G-EV a5: evt_drdy = 0 at the same post-consume observation point",
                     to_X01(evt_drdy), '0');

        -- G-EV-b: DISCIPLINE CHECK, DRDYIE=0 (and ALMIE=0) has ZERO effect on evt_drdy: the level still rises for a fresh word while irq_trng stays masked low.
        set_cr('1', '0', '0', "0000", "0000");   -- DRDYIE=0, ALMIE=0
        trng_wait_drdy(clk, pbus, rdata_out, ok);
        sb.check_true("G-EV b1: word assembles under DRDYIE=0 (bounded)", ok);
        bus_read(clk, pbus, rdata_out, TRNG_SLOT_SR, rdw);
        sb.check_bit("G-EV b2: SR.DRDY reads 1 even though DRDYIE=0", to_X01(rdw(TRNG_SR_DRDY)), '1');
        sb.check_bit("G-EV b3: evt_drdy = 1 under DRDYIE=0 (pre-IE tap, undisturbed by the mask)",
                     to_X01(evt_drdy), '1');
        sb.check_bit("G-EV b4: irq_trng stays 0 (DRDYIE=0 masks the IRQ, never evt_drdy)",
                     to_X01(irq_trng), '0');

        -- G-EV-c: quiet window, consume the pending word, halt generation (EN=0), and confirm evt_drdy stays 0 throughout a bounded window, with no stray toggles once the source is idle and the word is drained.
        read_dr(rdw);
        set_cr('0', '0', '0', "0000", "0000");   -- EN=0: halt generation
        quiet_ok := true;
        for i in 1 to 40 loop
            wait until rising_edge(clk);
            if to_X01(evt_drdy) /= '0' then
                quiet_ok := false;
            end if;
        end loop;
        sb.check_true("G-EV c1: evt_drdy stays 0 over a bounded 40-clk quiet window "
                     & "(halted, consumed)", quiet_ok);

        ------------------------------------------------------------------
        -- GROUP G-NEG: negative control, always last: exactly ONE deliberately wrong expected value, a wrong entropy word after a clean, known harvest.
        ------------------------------------------------------------------
        report "=== GROUP G-NEG: NEGATIVE CONTROL ===" severity note;
        -- Fresh resetn first: asm_cnt/asm_reg clear only on resetn and not on an EN 0-to-1 toggle, so a clean known harvest needs a reset regardless of where the previous group left the assembler.
        -- ROSEL=0001 rather than the 0000 used elsewhere: the clean-reset sel=0000 word has bit31 set, which overflows periph_tb_pkg's img() helper (integer'image of a value >= 2**31), while sel=0001's word has bit31 clear.
        do_reset;
        write_ht(x"00");
        set_cr('0', '0', '0', "0001", "0000");
        wait for 4 * PERIOD;
        set_cr('1', '1', '0', "0001", "0000");
        trng_wait_drdy(clk, pbus, rdata_out, ok);
        sb.check_true("G-NEG setup: word assembles (bounded)", ok);
        read_dr(rdw);
        sb.check_slv("NEGATIVE CONTROL: wrong expected entropy word (must FAIL)",
                     rdw, x"00000000");

        ------------------------------------------------------------------
        -- Final verdict: sb.errors must be EXACTLY 1 (the negative control).
        ------------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("TRNG TB");

        if sb.errors = 1 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   TRNG_TB PASS (1 expected negative-control failure)" & LF &
                "    ##   TRNG TB:  ALL CHECKS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   TRNG_TB FAIL (expected exactly 1 failure [negative control], got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        tb_done <= true;
        stop;
        wait;
    end process stim_proc;

end architecture sim;
