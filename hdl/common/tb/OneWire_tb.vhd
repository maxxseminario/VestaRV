-------------------------------------------------------------------------------
-- OneWire_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the 1-Wire master peripheral (hdl/common/periph/OneWire.vhd), written AGAINST THE FROZEN ENTITY + REGISTER MAP (~/vesta_docs/digperiphs/onewire_design.md, D1-D16 + orchestrator A1-A5) while the RTL is written in parallel.
-- The DUT is declared as a COMPONENT, not an entity instantiation, so this bench compiles standalone with xmvhdl before OneWire.vhd exists: the I3C_tb/RTC_tb discipline.
-- VHDL default binding resolves it to the entity of the same name once OneWire.vhd is analyzed into the work library.
--
-- Uses periph_tb_pkg.vhd (scoreboard + register-bus BFM), onewire_bfm_pkg.vhd (slot/CR/CMD/SR constants, ow_mk_cmd/ow_mk_cr packers, the bounded SR polls ow_wait_busy_clear/ow_wait_flag, and the D7/A1 timing-window constants), and onewire_target_model.vhd (the 1-Wire target responder + timing checker).
--
-- ONE clock family (design doc D1/D2): clk, bound to MCLK at integration, hosts the whole protocol engine; ClkMem is the gated bus clock, driven clk when b.en_mem = '0' else '0' exactly like RTC_tb/NFC_tb/I3C_tb.
-- There is no second (lfxt-class) domain here, unlike RTC.
--
-- COMPRESSION: the bench programs OW0DIV itself to OW0DIV_VAL after the G0 reset-default checks, so one tick is OW0DIV_VAL+1 clk periods (see that constant's own comment for why it must stay non-zero).
-- The target model's cfg_tick_period is TICKP throughout, never re-derived per group.
-- A full standard reset (the D7/A1-doubled FSM count: 960 tRSTL + 140 tPRES + 1 sample + 960 tRSTH ~= 2061 ticks) is therefore ~165 us of sim time, and the whole suite (all groups, both speeds) stays well inside the 20 ms watchdog.
--
-- PULSE-WIDTH MEASUREMENT: the target model times the master's driven-low pulses off dut_dq_dir (the DUT's own OW_DQ_DIR port, wired to the model's mon_dir input) rather than off the resolved multi-driver DQ net.
-- See onewire_target_model.vhd's header for why: READ slots are ambiguous once the model itself may also be driving.
-- OW_DQ_DIR is an ordinary, frozen D3 port (the pad-drive-enable), not an internal signal.
--
-- BUS RESOLUTION (design doc "Bench plan"): the DUT drives dq_bus low via OW_DQ_DIR (OW_DQ_OUT is fixed '0', D11), the model drives via its own dq_oe/dq_out, and a weak 'H' pull idles the net high (open-drain wired-AND).
-- That is the exact I3C_tb.vhd sda_bus/scl_bus pattern, extended with the "H" release level QSPI's push-pull-only bus did not need.
--
-- DEVIATIONS and scope notes, flagged rather than silently resolved (the bench author's final report has the full list):
--   * The design doc's Stage-1 self-check also lists "launch ignored while BUSY" (a second CMD write attempted mid-transaction).
--     This bench proves "launch ignored while OWEN=0" (G1, content always captured, D8) but does NOT additionally exercise the while-BUSY leg: verifying it robustly from outside requires inferring a negative ("nothing happened") from indirect side effects and was judged lower-value than the explicit OWEN=0 leg for a first bench pass.
--     Flagged for the RTL author or a follow-up bench revision.
--   * G6's SHORT leg uses the target model's cfg_stuck_low (delayed-onset stuck-low, timed to land after the tPRES sample window closes but before tRSTH's recovery check) to hit exactly the ADJUDICATION A5 scenario ("SHORT wins", NOPRES suppressed).
--     A bus stuck low from t=0 would instead read PRES=1 at the sample point per the literal D12 rule, a different and less interesting corner.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.onewire_bfm_pkg.all;

entity OneWire_tb is
end entity OneWire_tb;

architecture sim of OneWire_tb is

    constant PERIOD : time := 20 ns;   -- clk / bus reference (free-running ref, D2)

    -- COMPRESSION divisor: must stay small (fast bench) but NON-ZERO.
    -- At OW0DIV=0 one tick is one clk, so the DUT's fixed 2-FF DQ synchronizer (D10, 2 clk) costs a full 2 ticks, a gross distortion of the silicon ratio (at OW0DIV=11 one tick is 12 clk and the sync is ~0.17 tick).
    -- At that distortion an OVERDRIVE read samples tMSR=3 ticks BEFORE the master's own tRL=2-tick drive-low has even cleared the synchronizer, so every OD read bit reads the master's own low (0).
    -- OW0DIV=3 keeps one tick at 4 clk (sync = 0.5 tick, sub-tick like silicon) while a full STD reset (~2060 ticks) is still only ~165 us, so the whole suite stays well under the 20 ms watchdog.
    -- cfg_tick_period tracks this so every model window scales transparently.
    constant OW0DIV_VAL : natural := 3;
    constant TICKP      : time    := (OW0DIV_VAL + 1) * PERIOD;

    -- FROZEN DUT entity (design doc D3), declared as a component so the bench compiles standalone before hdl/common/periph/OneWire.vhd exists.
    component OneWire is
        port (
            clk         : in  std_logic;
            resetn      : in  std_logic;
            irq_ow      : out std_logic;
            ClkMem      : in  std_logic;
            EnMemPeriph : in  std_logic;
            WEn         : in  std_logic_vector(3 downto 0);
            MABPart     : in  std_logic_vector(7 downto 2);
            wdata       : in  std_logic_vector(31 downto 0);
            rdata_out   : out std_logic_vector(31 downto 0);
            OW_DQ_IN    : in  std_logic;
            OW_DQ_OUT   : out std_logic;
            OW_DQ_DIR   : out std_logic
        );
    end component;

    component OneWire_target_model is
        port (
            mon_dir            : in  std_logic;
            dq_out             : out std_logic := '0';
            dq_oe              : out std_logic := '0';
            cfg_op             : in  std_logic_vector(2 downto 0) := OW_OP_RESET;
            cfg_ods            : in  std_logic                    := '0';
            cfg_present        : in  boolean                       := true;
            cfg_stuck_low      : in  boolean                       := false;
            cfg_rd_pattern     : in  std_logic_vector(7 downto 0)  := x"A5";
            cfg_tick_period    : in  time                          := 20 ns;
            cfg_corrupt_window : in  boolean                       := false;
            cfg_arm            : in  std_logic                     := '0';
            obs_wbyte     : out std_logic_vector(7 downto 0) := (others => '0');
            obs_wbits     : out natural                       := 0;
            obs_viol_rstl : out std_logic                     := '0';
            obs_viol_w0l  : out std_logic                     := '0';
            obs_viol_w1l  : out std_logic                     := '0';
            obs_viol_rl   : out std_logic                     := '0'
        );
    end component;

    -- Clocks and reset.
    signal clk    : std_logic := '0';
    signal ClkMem : std_logic := '0';
    signal resetn : std_logic := '0';

    -- Interrupt output.
    signal irq_ow : std_logic;

    -- Register bus.
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal rdata_out : std_logic_vector(31 downto 0);

    -- DQ pad (DUT side) plus the resolved shared net.
    signal dut_dq_out, dut_dq_dir : std_logic;
    signal dq_bus                 : std_logic;
    signal dq_bus_x01             : std_logic;   -- resolved net, to_X01-normalized (design doc bench plan)

    -- Target-model drive plus its per-operation config.
    signal model_dq_out, model_dq_oe : std_logic;
    signal cfg_op             : std_logic_vector(2 downto 0) := OW_OP_RESET;
    signal cfg_ods            : std_logic                    := '0';
    signal cfg_present        : boolean                       := true;
    signal cfg_stuck_low      : boolean                       := false;
    signal cfg_rd_pattern     : std_logic_vector(7 downto 0)  := x"A5";
    signal cfg_corrupt_window : boolean                       := false;
    signal cfg_arm            : std_logic                     := '0';

    -- Target-model observations.
    signal obs_wbyte     : std_logic_vector(7 downto 0);
    signal obs_wbits     : natural;
    signal obs_viol_rstl : std_logic;
    signal obs_viol_w0l  : std_logic;
    signal obs_viol_w1l  : std_logic;
    signal obs_viol_rl   : std_logic;

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

begin

    ----------------------------------------------------------------------------
    -- Free-running clock and the gated register-bus clock (mirrors RTC_tb / NFC_tb / I3C_tb).
    ----------------------------------------------------------------------------
    clk    <= not clk after PERIOD / 2;
    ClkMem <= clk when pbus.en_mem = '0' else '0';

    ----------------------------------------------------------------------------
    -- dq_bus resolution: the DUT drives when OW_DQ_DIR='1' (OW_DQ_OUT is fixed '0', D11), the model drives when its own dq_oe='1', otherwise a weak 'H' pull holds the net (open-drain wired-AND: any '0' wins).
    -- This is the I3C_tb.vhd pattern.
    ----------------------------------------------------------------------------
    dq_bus <= dut_dq_out   when dut_dq_dir = '1' else 'Z';
    dq_bus <= model_dq_out when model_dq_oe = '1' else 'Z';
    dq_bus <= 'H';
    -- The DUT samples the resolved node to_X01-normalized (design doc bench plan: "The DUT's OW_DQ_IN is the resolved node, to_X01-sampled").
    -- Without this the idle weak-'H' pull is stored verbatim into the DUT's rx_shift ('H' converts to a numeric 1 but fails an exact std_logic '1' compare).
    dq_bus_x01 <= to_X01(dq_bus);

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    dut : component OneWire
        port map (
            clk         => clk,
            resetn      => resetn,
            irq_ow      => irq_ow,
            ClkMem      => ClkMem,
            EnMemPeriph => pbus.en_mem,
            WEn         => pbus.wen,
            MABPart     => pbus.addr_periph,
            wdata       => pbus.write_data,
            rdata_out   => rdata_out,
            OW_DQ_IN    => dq_bus_x01,
            OW_DQ_OUT   => dut_dq_out,
            OW_DQ_DIR   => dut_dq_dir
        );

    ----------------------------------------------------------------------------
    -- 1-Wire target model: the pulse-width reference is the DUT's own OW_DQ_DIR (mon_dir), NOT the resolved bus (see the file header and the model header).
    ----------------------------------------------------------------------------
    model : component OneWire_target_model
        port map (
            mon_dir            => dut_dq_dir,
            dq_out              => model_dq_out,
            dq_oe               => model_dq_oe,
            cfg_op              => cfg_op,
            cfg_ods             => cfg_ods,
            cfg_present         => cfg_present,
            cfg_stuck_low       => cfg_stuck_low,
            cfg_rd_pattern      => cfg_rd_pattern,
            cfg_tick_period     => TICKP,
            cfg_corrupt_window  => cfg_corrupt_window,
            cfg_arm             => cfg_arm,
            obs_wbyte     => obs_wbyte,
            obs_wbits     => obs_wbits,
            obs_viol_rstl => obs_viol_rstl,
            obs_viol_w0l  => obs_viol_w0l,
            obs_viol_w1l  => obs_viol_w1l,
            obs_viol_rl   => obs_viol_rl
        );

    ----------------------------------------------------------------------------
    -- Watchdog: abort with a FAIL banner if the stimulus ever hangs.
    -- The expected sim time is a small fraction of this budget (see the COMPRESSION note in the file header), so it fires only on a true hang.
    ----------------------------------------------------------------------------
    watchdog : process
    begin
        wait for 20 ms;
        if not tb_done then
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   ONEWIRE_TB FAIL (WATCHDOG TIMEOUT -- stimulus never finished)" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
            stop;
        end if;
        wait;
    end process;

    ----------------------------------------------------------------------------
    -- Stimulus and checks: one thread, groups G0 through G-NEG in order.
    ----------------------------------------------------------------------------
    stim_proc : process
        variable rdw     : std_logic_vector(31 downto 0);
        variable ok      : boolean;

        -- Re-arm the target model for the operation about to be launched.
        -- The configuration is held stable until the next arm (D8 latch-at-launch precedent).
        procedure ow_arm(op      : std_logic_vector(2 downto 0);
                         ods      : std_logic;
                         present  : boolean;
                         stuck    : boolean;
                         pattern  : std_logic_vector(7 downto 0);
                         corrupt  : boolean) is
        begin
            cfg_op             <= op;
            cfg_ods            <= ods;
            cfg_present        <= present;
            cfg_stuck_low      <= stuck;
            cfg_rd_pattern     <= pattern;
            cfg_corrupt_window <= corrupt;
            wait for 2 ns;
            cfg_arm <= '1';
            wait for 2 ns;
            cfg_arm <= '0';
            wait for 2 ns;
        end procedure;

        -- Launch: a single OW0CMD lane-0 write (D8).
        procedure ow_launch(op : std_logic_vector(2 downto 0); bitval : std_logic) is
        begin
            bus_write(clk, pbus, OW_SLOT_CMD, ow_mk_cmd(op, bitval));
        end procedure;

        -- Program OW0CR: enable, overdrive select and the two interrupt enables.
        procedure ow_set_cr(owen, ods, tcie, errie : std_logic) is
        begin
            bus_write(clk, pbus, OW_SLOT_CR, ow_mk_cr(owen, ods, '0', tcie, errie));
        end procedure;

        -- W1C the given SR mask, then wait out the clr_*_tgl 2-FF sync and edge detect (D12) before the caller relies on the flag being clear.
        procedure ow_w1c(mask : std_logic_vector(31 downto 0)) is
        begin
            bus_write(clk, pbus, OW_SLOT_SR, mask);
            wait for 4 * PERIOD;
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

        ------------------------------------------------------------------
        -- GROUP G0: reset defaults (design doc G0).
        ------------------------------------------------------------------
        report "=== GROUP G0: reset defaults ===" severity note;
        bus_read(clk, pbus, rdata_out, OW_SLOT_CR, rdw);
        sb.check_slv("G0: CR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, OW_SLOT_SR, rdw);
        sb.check_slv("G0: SR resets to 0 (BUSY/TCIF/PRES/NOPRES/SHORT)", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, OW_SLOT_RX, rdw);
        sb.check_slv("G0: RX resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, OW_SLOT_DIV, rdw);
        sb.check_slv("G0: DIV resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, OW_SLOT_SPU, rdw);
        sb.check_slv("G0: SPU (reserved) reads 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, 7, rdw);
        sb.check_slv("G0: slot 7 reads 0", rdw, x"00000000");
        sb.check_bit("G0: irq_ow = 0 out of reset", to_X01(irq_ow), '0');

        -- Program the compression divisor (see the OW0DIV_VAL comment).
        -- Done AFTER the G0 reset-default checks, which verify DIV powers up at 0, and before any protocol op, so every tick below is OW0DIV_VAL+1 clk and the DUT's 2-FF DQ sync stays sub-tick (silicon-faithful) even in OD.
        bus_write(clk, pbus, OW_SLOT_DIV, std_logic_vector(to_unsigned(OW0DIV_VAL, 32)));

        ------------------------------------------------------------------
        -- GROUP G1: reset / presence (design doc G1).
        -- Also proves the D8 launch-suppress contract: content always captured, launch (BUSY) suppressed while OWEN=0.
        ------------------------------------------------------------------
        report "=== GROUP G1: reset / presence ===" severity note;

        -- OWEN=0: launch a distinctive WRBIT(1) command; the content is captured but nothing launches, so no BUSY and no bus activity.
        ow_set_cr('0', '0', '0', '0');
        ow_launch(OW_OP_WRBIT, '1');
        wait for 4 * PERIOD;
        bus_read(clk, pbus, rdata_out, OW_SLOT_SR, rdw);
        sb.check_bit("G1: launch suppressed while OWEN=0 (BUSY stays 0)",
                     to_X01(rdw(OW_SR_BUSY)), '0');
        bus_read(clk, pbus, rdata_out, OW_SLOT_CMD, rdw);
        sb.check_slv("G1: OW0CMD content always captured even when OWEN=0 (D8)",
                     rdw, ow_mk_cmd(OW_OP_WRBIT, '1'));

        -- Enable the master, then RESET with the model present.
        ow_set_cr('1', '0', '0', '0');
        ow_arm(OW_OP_RESET, '0', true, false, x"00", false);
        ow_launch(OW_OP_RESET, '0');
        wait for 2 * PERIOD;
        bus_read(clk, pbus, rdata_out, OW_SLOT_SR, rdw);
        sb.check_bit("G1: BUSY asserts shortly after launch", to_X01(rdw(OW_SR_BUSY)), '1');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G1: BUSY clears (bounded wait)", ok);
        bus_read(clk, pbus, rdata_out, OW_SLOT_SR, rdw);
        sb.check_bit("G1: PRES=1 with the model present", to_X01(rdw(OW_SR_PRES)), '1');
        sb.check_bit("G1: NOPRES=0 with the model present", to_X01(rdw(OW_SR_NOPRES)), '0');
        sb.check_bit("G1: SHORT=0 (clean reset)", to_X01(rdw(OW_SR_SHORT)), '0');
        sb.check_bit("G1: TCIF=1 at completion", to_X01(rdw(OW_SR_TCIF)), '1');
        sb.check_bit("G1: model observed an in-window tRSTL pulse (STD)",
                     to_X01(obs_viol_rstl), '0');
        ow_w1c(x"00000002");   -- W1C TCIF

        -- RESET with the model absent (no device).
        ow_arm(OW_OP_RESET, '0', false, false, x"00", false);
        ow_launch(OW_OP_RESET, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G1: BUSY clears (no-device leg)", ok);
        bus_read(clk, pbus, rdata_out, OW_SLOT_SR, rdw);
        sb.check_bit("G1: PRES=0 with no device", to_X01(rdw(OW_SR_PRES)), '0');
        sb.check_bit("G1: NOPRES=1 with no device", to_X01(rdw(OW_SR_NOPRES)), '1');
        sb.check_bit("G1: TCIF=1 at completion (no-device leg)", to_X01(rdw(OW_SR_TCIF)), '1');
        ow_w1c(x"0000000A");   -- W1C TCIF|NOPRES

        ------------------------------------------------------------------
        -- GROUP G2: write byte (design doc G2).
        -- The asymmetric byte 0x0F proves LSB-first order: a reversed capture would read back 0xF0.
        ------------------------------------------------------------------
        report "=== GROUP G2: write byte ===" severity note;
        bus_write(clk, pbus, OW_SLOT_TX, x"0000000F");
        ow_arm(OW_OP_WRBYTE, '0', true, false, x"00", false);
        ow_launch(OW_OP_WRBYTE, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G2: BUSY clears after WRBYTE", ok);
        sb.check_slv("G2: model captured 0x0F, LSB-first order (asymmetric byte)",
                     obs_wbyte, x"0F");
        sb.check_true("G2: model captured all 8 bits", obs_wbits = 8);
        sb.check_bit("G2: every write-0 pulse in the standard window", to_X01(obs_viol_w0l), '0');
        sb.check_bit("G2: every write-1 pulse in the standard window", to_X01(obs_viol_w1l), '0');
        bus_read(clk, pbus, rdata_out, OW_SLOT_SR, rdw);
        sb.check_bit("G2: TCIF=1 at completion", to_X01(rdw(OW_SR_TCIF)), '1');
        ow_w1c(x"00000002");

        ------------------------------------------------------------------
        -- GROUP G3: read byte (design doc G3).
        -- The asymmetric pattern 0x3C proves LSB-first assembly.
        ------------------------------------------------------------------
        report "=== GROUP G3: read byte ===" severity note;
        ow_arm(OW_OP_RDBYTE, '0', true, false, x"3C", false);
        ow_launch(OW_OP_RDBYTE, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G3: BUSY clears after RDBYTE", ok);
        bus_read(clk, pbus, rdata_out, OW_SLOT_RX, rdw);
        sb.check_slv("G3: RX = model's driven pattern 0x3C, LSB-first assembly",
                     rdw(7 downto 0), x"3C");
        bus_read(clk, pbus, rdata_out, OW_SLOT_SR, rdw);
        sb.check_bit("G3: TCIF=1 at completion", to_X01(rdw(OW_SR_TCIF)), '1');
        ow_w1c(x"00000002");

        ------------------------------------------------------------------
        -- GROUP G4: bit ops (design doc G4).
        ------------------------------------------------------------------
        report "=== GROUP G4: bit ops ===" severity note;

        -- WRBIT 0 then WRBIT 1.
        ow_arm(OW_OP_WRBIT, '0', true, false, x"00", false);
        ow_launch(OW_OP_WRBIT, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G4: BUSY clears after WRBIT(0)", ok);
        sb.check_bit("G4: model sees WRBIT value 0 (tW0L-class pulse)", to_X01(obs_wbyte(0)), '0');
        sb.check_bit("G4: WRBIT(0) pulse in the standard tW0L window", to_X01(obs_viol_w0l), '0');
        ow_w1c(x"00000002");

        ow_arm(OW_OP_WRBIT, '0', true, false, x"00", false);
        ow_launch(OW_OP_WRBIT, '1');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G4: BUSY clears after WRBIT(1)", ok);
        sb.check_bit("G4: model sees WRBIT value 1 (tW1L-class pulse)", to_X01(obs_wbyte(0)), '1');
        sb.check_bit("G4: WRBIT(1) pulse in the standard tW1L window", to_X01(obs_viol_w1l), '0');
        ow_w1c(x"00000002");

        -- RDBIT against a 0 pattern then a 1 pattern.
        ow_arm(OW_OP_RDBIT, '0', true, false, x"00", false);
        ow_launch(OW_OP_RDBIT, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G4: BUSY clears after RDBIT (pattern 0)", ok);
        bus_read(clk, pbus, rdata_out, OW_SLOT_RX, rdw);
        sb.check_bit("G4: RDBIT result 0", to_X01(rdw(0)), '0');
        ow_w1c(x"00000002");

        ow_arm(OW_OP_RDBIT, '0', true, false, x"01", false);
        ow_launch(OW_OP_RDBIT, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G4: BUSY clears after RDBIT (pattern 1)", ok);
        bus_read(clk, pbus, rdata_out, OW_SLOT_RX, rdw);
        sb.check_bit("G4: RDBIT result 1", to_X01(rdw(0)), '1');
        ow_w1c(x"00000002");

        ------------------------------------------------------------------
        -- GROUP G5: overdrive re-run (design doc G5).
        ------------------------------------------------------------------
        report "=== GROUP G5: overdrive re-run ===" severity note;
        ow_set_cr('1', '1', '0', '0');   -- ODS=1, latched at the next launch (D7)

        ow_arm(OW_OP_RESET, '1', true, false, x"00", false);
        ow_launch(OW_OP_RESET, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G5: BUSY clears after OD RESET", ok);
        bus_read(clk, pbus, rdata_out, OW_SLOT_SR, rdw);
        sb.check_bit("G5: OD RESET: PRES=1 with the model present", to_X01(rdw(OW_SR_PRES)), '1');
        sb.check_bit("G5: OD RESET: tRSTL pulse in the OD window", to_X01(obs_viol_rstl), '0');
        ow_w1c(x"00000002");

        bus_write(clk, pbus, OW_SLOT_TX, x"000000A5");
        ow_arm(OW_OP_WRBYTE, '1', true, false, x"00", false);
        ow_launch(OW_OP_WRBYTE, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G5: BUSY clears after OD WRBYTE", ok);
        sb.check_slv("G5: OD WRBYTE: model captured 0xA5", obs_wbyte, x"A5");
        sb.check_bit("G5: OD WRBYTE: write-0 pulses in the OD window", to_X01(obs_viol_w0l), '0');
        sb.check_bit("G5: OD WRBYTE: write-1 pulses in the OD window", to_X01(obs_viol_w1l), '0');
        ow_w1c(x"00000002");

        ow_arm(OW_OP_RDBYTE, '1', true, false, x"5A", false);
        ow_launch(OW_OP_RDBYTE, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G5: BUSY clears after OD RDBYTE", ok);
        bus_read(clk, pbus, rdata_out, OW_SLOT_RX, rdw);
        sb.check_slv("G5: OD RDBYTE: RX = model's pattern 0x5A", rdw(7 downto 0), x"5A");
        sb.check_bit("G5: OD RDBYTE: read-initiate pulses in the OD window", to_X01(obs_viol_rl), '0');
        ow_w1c(x"00000002");

        ow_set_cr('1', '0', '0', '0');   -- back to STD for the remaining groups

        ------------------------------------------------------------------
        -- GROUP G6: error / short (design doc G6, ADJUDICATION A5).
        ------------------------------------------------------------------
        report "=== GROUP G6: error / short ===" severity note;

        -- SHORT (A5): onset after the tPRES sample window closes but before tRSTH's recovery check, so SHORT sets and NOPRES is suppressed.
        ow_arm(OW_OP_RESET, '0', false, true, x"00", false);
        ow_launch(OW_OP_RESET, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G6: BUSY clears despite the stuck bus (fixed-tick FSM)", ok);
        bus_read(clk, pbus, rdata_out, OW_SLOT_SR, rdw);
        sb.check_bit("G6: SHORT=1 (bus never returns high, A5)", to_X01(rdw(OW_SR_SHORT)), '1');
        sb.check_bit("G6: NOPRES=0 -- SHORT wins, NOPRES suppressed (A5)",
                     to_X01(rdw(OW_SR_NOPRES)), '0');
        sb.check_bit("G6: TCIF=1 at completion (SHORT leg)", to_X01(rdw(OW_SR_TCIF)), '1');
        ow_w1c(x"00000012");   -- W1C TCIF|SHORT

        -- Corrupt-window self-test: proves the model's checker flag path fires, using a genuinely in-spec pulse that is deliberately mis-flagged.
        ow_arm(OW_OP_RESET, '0', true, false, x"00", true);
        ow_launch(OW_OP_RESET, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        sb.check_true("G6: BUSY clears after the corrupt-window RESET", ok);
        sb.check_bit("G6: model timing checker fires under the corrupt-window self-test",
                     to_X01(obs_viol_rstl), '1');
        bus_read(clk, pbus, rdata_out, OW_SLOT_SR, rdw);
        sb.check_bit("G6: the DUT's own SHORT stays clear (only the model's checker was corrupted)",
                     to_X01(rdw(OW_SR_SHORT)), '0');
        ow_w1c(x"00000002");

        ------------------------------------------------------------------
        -- GROUP G7: IRQ demux / W1C (design doc G7).
        -- irq_ow = (TCIF & TCIE) or ((NOPRES|SHORT) & ERRIE), combinational (D13).
        ------------------------------------------------------------------
        report "=== GROUP G7: IRQ demux / W1C ===" severity note;

        -- TCIE only.
        ow_set_cr('1', '0', '1', '0');
        ow_arm(OW_OP_RESET, '0', true, false, x"00", false);
        ow_launch(OW_OP_RESET, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        wait for 2 * PERIOD;
        sb.check_bit("G7: irq_ow asserts (TCIF & TCIE)", to_X01(irq_ow), '1');
        ow_w1c(x"00000002");
        wait for 2 * PERIOD;
        sb.check_bit("G7: irq_ow drops after W1C TCIF", to_X01(irq_ow), '0');

        -- ERRIE only.
        ow_set_cr('1', '0', '0', '1');
        ow_arm(OW_OP_RESET, '0', false, false, x"00", false);
        ow_launch(OW_OP_RESET, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        wait for 2 * PERIOD;
        sb.check_bit("G7: irq_ow asserts (NOPRES & ERRIE)", to_X01(irq_ow), '1');
        ow_w1c(x"0000000A");   -- W1C TCIF|NOPRES
        wait for 2 * PERIOD;
        sb.check_bit("G7: irq_ow drops after clearing NOPRES", to_X01(irq_ow), '0');

        -- Both TCIF and an error pending together: irq drops only when BOTH clear.
        ow_set_cr('1', '0', '1', '1');
        ow_arm(OW_OP_RESET, '0', false, false, x"00", false);
        ow_launch(OW_OP_RESET, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        wait for 2 * PERIOD;
        sb.check_bit("G7: irq_ow high with TCIF and NOPRES both pending", to_X01(irq_ow), '1');
        ow_w1c(x"00000002");   -- W1C TCIF only
        wait for 2 * PERIOD;
        sb.check_bit("G7: irq_ow still high (NOPRES & ERRIE remains)", to_X01(irq_ow), '1');
        ow_w1c(x"00000008");   -- W1C NOPRES
        wait for 2 * PERIOD;
        sb.check_bit("G7: irq_ow drops only once both sources are cleared", to_X01(irq_ow), '0');

        -- Both IE=0: flags pending but masked.
        ow_set_cr('1', '0', '0', '0');
        ow_arm(OW_OP_RESET, '0', false, false, x"00", false);
        ow_launch(OW_OP_RESET, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        bus_read(clk, pbus, rdata_out, OW_SLOT_SR, rdw);
        sb.check_bit("G7: TCIF pending under IE=0", to_X01(rdw(OW_SR_TCIF)), '1');
        sb.check_bit("G7: NOPRES pending under IE=0", to_X01(rdw(OW_SR_NOPRES)), '1');
        wait for 2 * PERIOD;
        sb.check_bit("G7: irq_ow stays low with both flags pending but both IE=0",
                     to_X01(irq_ow), '0');
        ow_w1c(x"0000000A");

        ------------------------------------------------------------------
        -- GROUP G-NEG: NEGATIVE CONTROL (mandatory, LAST).
        -- Exactly ONE deliberately-wrong expected value: PRES at the wrong polarity after a clean, present RESET (the design doc's own suggested example).
        ------------------------------------------------------------------
        report "=== GROUP G-NEG: NEGATIVE CONTROL ===" severity note;
        ow_set_cr('1', '0', '0', '0');
        ow_arm(OW_OP_RESET, '0', true, false, x"00", false);
        ow_launch(OW_OP_RESET, '0');
        ow_wait_busy_clear(clk, pbus, rdata_out, ok);
        bus_read(clk, pbus, rdata_out, OW_SLOT_SR, rdw);
        sb.check_bit("NEGATIVE CONTROL: wrong expected PRES polarity (must FAIL)",
                     to_X01(rdw(OW_SR_PRES)), '0');
        ow_w1c(x"00000002");

        ------------------------------------------------------------------
        -- Final verdict: sb.errors must be EXACTLY 1 (the negative control).
        ------------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("ONEWIRE TB");

        if sb.errors = 1 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   ONEWIRE_TB PASS (1 expected negative-control failure)" & LF &
                "    ##   ONEWIRE TB:  ALL CHECKS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   ONEWIRE_TB FAIL (expected exactly 1 failure [negative control], got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        tb_done <= true;
        stop;
        wait;
    end process stim_proc;

end architecture sim;
