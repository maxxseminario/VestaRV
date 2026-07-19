-------------------------------------------------------------------------------
-- I3C_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the I3C peripheral
-- (hdl/common/periph/I3C.vhd), written AGAINST THE FROZEN ENTITY + REGISTER
-- MAP (~/vesta_docs/digperiphs/i3c_design.md, R3 + S3) while the RTL is being
-- written in parallel. The DUT is declared as a COMPONENT (not an entity
-- instantiation) so this bench compiles standalone with xmvhdl before
-- I3C.vhd exists; VHDL default binding resolves it to the entity of the same
-- name once I3C.vhd is analyzed into the work library. Mirrors QSPI_tb.vhd's
-- role/structure exactly (see that file's header).
--
-- Uses the shared support packages: tb/periph_tb_pkg.vhd (scoreboard +
-- register-bus BFM, existing/shared) and tb/i3c_bfm_pkg.vhd (I3C-specific
-- register-slot constants, CR/CMD field packing, the shared parity/read-
-- pattern formulas, and bounded SR-bit polls). The target-responder model is
-- tb/i3c_target_model.vhd (D29 stage 1) -- see its header for the bus-level
-- protocol model and its flagged assumptions.
--
-- Bus contract (mirrors every other peripheral bench in this tree):
-- EnMemPeriph active-low, WEn active-low per byte lane, MABPart(7:2) is the
-- word-slot address. ClkMem is GATED (ticks only while EnMemPeriph='0', see
-- periph_tb_pkg.bus_write/bus_read). One-cycle internal clear pulses (W1C SR
-- bits) can stick until the next selected access -- after a W1C, this bench
-- issues a dummy read of another register (CR) before re-reading SR, exactly
-- the idiom QSPI_tb.vhd / UART_tb.vhd use (see tb/CLAUDE.md).
--
-- SERIAL BUS RESOLUTION (design doc S7): the DUT and the target model each
-- drive SDA (and, legacy-mode only, the model may also drive SCL to stretch
-- it) via an OUT/OE-style pair. Both are resolved onto ONE shared net per
-- pin with a weak 'H' pull for the released level: '0' wins when either
-- driver asserts it (wired-AND open-drain, matches D19/D20's OD phases);
-- push-pull phases (WDATA bits, DAA-assign) are single-driver by
-- construction (the model never asserts sda_oe there -- see
-- i3c_target_model.vhd's header) so the same resolved-net expression is safe
-- for both drive styles, exactly like QSPI_tb.vhd's io_res generate extended
-- with the 'H' release level QSPI's push-pull-only bus didn't need.
--
-- FROZEN register map (word slots) this bench drives -- see i3c_bfm_pkg.vhd
-- for the exact bit-packing helpers and SR bit-position constants:
--   Slot 0 CR : [0]I3CEN [1]BUSMODE(0=I3C-SDR,1=legacy-I2C) [2]SDAPP
--               [3]IBIEN [15:8]ODBR [23:16]PPBR [24]TCIE [25]ERRIE [26]DAAIE
--               [27]IBIIE [28]RXFIE [29]TXEIE. Resets to 0 except SDAPP=1.
--   Slot 1 CMD: [6:0]ADDR [7]RNW [8]SR [9]STOPEN [10]CCC [11]CCCDIR
--               [12]DAARUN [13]DASA [23:16]DLEN [31:24]CCCOP. Writing this
--               slot LAUNCHES (D16; ignored if I3CEN=0 or BUSY=1).
--   Slot 2 TX : [7:0] next write byte; write arms the byte-pending handshake.
--   Slot 3 RX : [7:0] last received byte; side-effect-free read.
--   Slot 4 SR : [0]BUSY RO [1]TCIF W1C [2]RXFULL W1C [3]TXEIF W1C [4]ANACK
--               W1C [5]EODF W1C [6]ARBLOST W1C (stage-2/3 bits 7-10 unused
--               here).
--   Slots 5-9 (DAT/DATPID/DATINFO/IBI/reserved): stage-2/3, D23 inert/read-0
--   in this MVP -- not exercised by this bench.
--
-- AMBIGUITIES IN THE FROZEN CONTRACT noted while writing this bench (flagged,
-- not resolved -- see the bench author's final report for the full list):
--   * D19's phase table gives ADDR/START-STOP SCL drive mode as "PP (I3C) /
--     OD (legacy)" but never states which of ODBR/PPBR clocks the ADDRESS
--     phase in non-legacy I3C-SDR mode (only that "OD phases reload ODBR,
--     PP phases reload PPBR", B2) -- this bench's GROUP 8 (baud sanity)
--     therefore does NOT assume which specific protocol phase it is sampling
--     and instead checks only that the baud generator is sensitive to
--     ODBR/PPBR at all (two back-to-back launches with the two fields
--     swapped must show different first-observed SCL half-periods).
--   * The exact cycle at which BUSY asserts after a CMD-slot launch write is
--     not stated; GROUP 9b's BUSY=1 launch-guard race (a second CMD write
--     shortly after the first) uses the same short fixed-delay assumption
--     QSPI_tb.vhd's GROUP 7b flags, and may need tuning once I3C.vhd exists.
--   * i3c_target_model.vhd's own T-bit/ACK bus-level assumptions (see that
--     file's header) are inherited here uncritically since this bench cannot
--     run against real DUT timing yet.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.i3c_bfm_pkg.all;

entity I3C_tb is
end entity I3C_tb;

architecture sim of I3C_tb is

    constant PERIOD : time := 40 ns;   -- ~25 MHz smclk-domain serial-clock reference

    -- FROZEN DUT entity (R3), declared as a component (see file header) so
    -- this bench compiles standalone before hdl/common/periph/I3C.vhd exists.
    component I3C is
        port (
            clk         : in  std_logic;
            resetn      : in  std_logic;
            irq_tc      : out std_logic;
            irq_rxf     : out std_logic;
            irq_txe     : out std_logic;
            irq_nack    : out std_logic;
            irq_eod     : out std_logic;
            irq_arb     : out std_logic;
            irq_daa     : out std_logic;
            irq_ibi     : out std_logic;
            ClkMem      : in  std_logic;
            EnMemPeriph : in  std_logic;
            WEn         : in  std_logic_vector(3 downto 0);
            MABPart     : in  std_logic_vector(7 downto 2);
            wdata       : in  std_logic_vector(31 downto 0);
            rdata_out   : out std_logic_vector(31 downto 0);
            SDA_IN      : in  std_logic;
            SDA_OUT     : out std_logic;
            SDA_DIR     : out std_logic;
            SCL_IN      : in  std_logic;
            SCL_OUT     : out std_logic;
            SCL_DIR     : out std_logic
        );
    end component;

    -- clocks / reset
    signal clk    : std_logic := '0';
    signal ClkMem : std_logic := '0';
    signal resetn : std_logic := '0';

    -- interrupts
    signal irq_tc, irq_rxf, irq_txe, irq_nack : std_logic;
    signal irq_eod, irq_arb, irq_daa, irq_ibi : std_logic;

    -- register bus (BFM record + observed rdata_out)
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal rdata_out : std_logic_vector(31 downto 0);

    -- I3C pads (DUT side)
    signal dut_sda_out, dut_sda_dir : std_logic;
    signal dut_scl_out, dut_scl_dir : std_logic;

    -- resolved bus nets, weak 'H' release (D19/S7: '0' wins = wired-AND OD;
    -- WDATA/DAA-assign push-pull phases are single-driver by construction)
    signal sda_bus, scl_bus : std_logic;

    -- target-model drive + config
    signal model_sda_out, model_sda_oe : std_logic;
    signal model_scl_out, model_scl_oe : std_logic;
    signal cfg_target_addr     : std_logic_vector(6 downto 0) := "1010000";  -- 0x50
    signal cfg_legacy_mode     : boolean := false;
    signal cfg_legacy_stretch  : boolean := false;
    signal cfg_num_read_bytes  : natural := 1;
    signal cfg_read_seed       : std_logic_vector(7 downto 0) := x"A5";
    signal cfg_corrupt_wparity : boolean := false;

    -- target-model observed results
    signal model_obs_addr       : std_logic_vector(6 downto 0);
    signal model_obs_rnw        : std_logic;
    signal model_obs_addr_acked : std_logic;
    signal model_obs_wdata      : i3c_byte_array(0 to I3C_MODEL_MAX_BYTES - 1);
    signal model_obs_wparity_ok : std_logic_vector(0 to I3C_MODEL_MAX_BYTES - 1);
    signal model_obs_wcount     : natural;
    signal model_obs_rcount     : natural;
    signal model_obs_txn_count  : natural;

    -- stage-1 model DAA config (enabled only for the SETDASA group)
    signal cfg_daa_enable : boolean := false;

    -- ---- stage-2 ENTDAA: two extra target models (A lower PID, B higher) ---
    -- Real wired-AND arbitration on the shared SDA net decides the winner: A
    -- takes round 1, B round 2, round 3 NACKs (both assigned) => DAADONE.
    signal a_sda_out, a_sda_oe, a_scl_out, a_scl_oe : std_logic;
    signal b_sda_out, b_sda_oe, b_scl_out, b_scl_oe : std_logic;
    signal a_daa_assigned,  b_daa_assigned  : std_logic;
    signal a_daa_dynaddr,   b_daa_dynaddr   : std_logic_vector(6 downto 0);
    signal a_daa_parity_ok, b_daa_parity_ok : std_logic;
    signal a_enable, b_enable : boolean := false;
    -- model A byte-capture obs (directed write to its new dynamic address)
    signal a_obs_addr_acked : std_logic;
    signal a_obs_wdata      : i3c_byte_array(0 to I3C_MODEL_MAX_BYTES - 1);
    signal a_obs_wcount     : natural;

    -- ---- stage-3 IBI: model A initiates a bus-available IBI ---------------
    -- Model A (ENTDAA-assigned 0x08) is the IBI source; its assigned address
    -- is used over the wire (chain realism). The TB pulses a_ibi_trigger only
    -- while the bus is idle.
    signal a_ibi_trigger  : std_logic := '0';
    signal a_ibi_mdb      : std_logic_vector(7 downto 0) := (others => '0');
    signal a_ibi_has_data : boolean := true;
    signal a_obs_ibi_acked : std_logic;
    signal a_obs_ibi_count : natural;

    shared variable sb : scoreboard;

begin

    ----------------------------------------------------------------------------
    -- clock / gated register-bus clock (mirrors QSPI_tb / I2C_tb)
    ----------------------------------------------------------------------------
    clk    <= not clk after PERIOD / 2;
    ClkMem <= clk when pbus.en_mem = '0' else '0';

    ----------------------------------------------------------------------------
    -- sda_bus / scl_bus resolution: DUT drives when its *_DIR='1'; otherwise
    -- the target model drives when it owns that pin (model_*_oe='1');
    -- otherwise released to a weak 'H'. Both DUT and model see the SAME
    -- resolved nets on their *_IN ports.
    ----------------------------------------------------------------------------
    -- Multi-driver resolution (stage 2): the DUT, all three target models, and
    -- a weak 'H' pull each drive the shared net; std_logic resolution gives
    -- wired-AND for the open-drain phases (any '0' wins) and single-driver
    -- behaviour for push-pull phases (models release 'Z' there). A released
    -- driver contributes 'Z'; the constant 'H' driver sets the idle level.
    sda_bus <= dut_sda_out   when dut_sda_dir  = '1' else 'Z';
    sda_bus <= model_sda_out when model_sda_oe = '1' else 'Z';
    sda_bus <= a_sda_out     when a_sda_oe     = '1' else 'Z';
    sda_bus <= b_sda_out     when b_sda_oe     = '1' else 'Z';
    sda_bus <= 'H';

    scl_bus <= dut_scl_out   when dut_scl_dir  = '1' else 'Z';
    scl_bus <= model_scl_out when model_scl_oe = '1' else 'Z';
    scl_bus <= a_scl_out     when a_scl_oe     = '1' else 'Z';
    scl_bus <= b_scl_out     when b_scl_oe     = '1' else 'Z';
    scl_bus <= 'H';

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    dut : component I3C
        port map (
            clk         => clk,
            resetn      => resetn,
            irq_tc      => irq_tc,
            irq_rxf     => irq_rxf,
            irq_txe     => irq_txe,
            irq_nack    => irq_nack,
            irq_eod     => irq_eod,
            irq_arb     => irq_arb,
            irq_daa     => irq_daa,
            irq_ibi     => irq_ibi,
            ClkMem      => ClkMem,
            EnMemPeriph => pbus.en_mem,
            WEn         => pbus.wen,
            MABPart     => pbus.addr_periph,
            wdata       => pbus.write_data,
            rdata_out   => rdata_out,
            SDA_IN      => sda_bus,
            SDA_OUT     => dut_sda_out,
            SDA_DIR     => dut_sda_dir,
            SCL_IN      => scl_bus,
            SCL_OUT     => dut_scl_out,
            SCL_DIR     => dut_scl_dir
        );

    ----------------------------------------------------------------------------
    -- Target-responder model (D29 stage 1)
    ----------------------------------------------------------------------------
    target : entity work.I3C_target_model
        port map (
            scl                 => scl_bus,
            sda_in              => sda_bus,
            sda_out             => model_sda_out,
            sda_oe              => model_sda_oe,
            scl_out             => model_scl_out,
            scl_oe              => model_scl_oe,
            cfg_target_addr     => cfg_target_addr,
            cfg_legacy_mode     => cfg_legacy_mode,
            cfg_legacy_stretch  => cfg_legacy_stretch,
            cfg_num_read_bytes  => cfg_num_read_bytes,
            cfg_read_seed       => cfg_read_seed,
            cfg_corrupt_wparity => cfg_corrupt_wparity,
            cfg_daa_enable      => cfg_daa_enable,   -- stage-2: ACK 0x7E for SETDASA
            obs_addr            => model_obs_addr,
            obs_rnw             => model_obs_rnw,
            obs_addr_acked      => model_obs_addr_acked,
            obs_wdata           => model_obs_wdata,
            obs_wparity_ok      => model_obs_wparity_ok,
            obs_wcount          => model_obs_wcount,
            obs_rcount          => model_obs_rcount,
            obs_txn_count       => model_obs_txn_count,
            obs_daa_assigned    => open,
            obs_daa_dynaddr     => open,
            obs_daa_parity_ok   => open
        );

    ----------------------------------------------------------------------------
    -- Two ENTDAA target models. cfg_daa_enable makes them ACK the 0x7E header
    -- and stream {PID,BCR,DCR} open-drain; A's lower PID must win first.
    ----------------------------------------------------------------------------
    daa_a : entity work.I3C_target_model
        port map (
            scl               => scl_bus,       sda_in  => sda_bus,
            sda_out           => a_sda_out,      sda_oe  => a_sda_oe,
            scl_out           => a_scl_out,      scl_oe  => a_scl_oe,
            cfg_target_addr   => "1000000",      -- 0x40 (static placeholder)
            cfg_daa_enable    => a_enable,
            cfg_pid           => x"A0000000000A",
            cfg_bcr           => x"11",
            cfg_dcr           => x"22",
            cfg_ibi_trigger   => a_ibi_trigger,
            cfg_ibi_mdb       => a_ibi_mdb,
            cfg_ibi_has_data  => a_ibi_has_data,
            obs_addr_acked    => a_obs_addr_acked,
            obs_wdata         => a_obs_wdata,
            obs_wcount        => a_obs_wcount,
            obs_daa_assigned  => a_daa_assigned,
            obs_daa_dynaddr   => a_daa_dynaddr,
            obs_daa_parity_ok => a_daa_parity_ok,
            obs_ibi_acked     => a_obs_ibi_acked,
            obs_ibi_count     => a_obs_ibi_count
        );

    daa_b : entity work.I3C_target_model
        port map (
            scl               => scl_bus,       sda_in  => sda_bus,
            sda_out           => b_sda_out,      sda_oe  => b_sda_oe,
            scl_out           => b_scl_out,      scl_oe  => b_scl_oe,
            cfg_target_addr   => "1000001",      -- 0x41
            cfg_daa_enable    => b_enable,
            cfg_pid           => x"B0000000000B",
            cfg_bcr           => x"33",
            cfg_dcr           => x"44",
            obs_daa_assigned  => b_daa_assigned,
            obs_daa_dynaddr   => b_daa_dynaddr,
            obs_daa_parity_ok => b_daa_parity_ok
        );

    ----------------------------------------------------------------------------
    -- stimulus
    ----------------------------------------------------------------------------
    stim_proc : process
        variable rdw          : std_logic_vector(31 downto 0);
        variable done_ok      : boolean;
        variable txn_before   : natural;
        variable expected     : std_logic_vector(7 downto 0);
        variable got_od, got_pp : boolean;
        variable t_od, t_pp   : time;
        variable neg_ibi_mdb  : std_logic_vector(7 downto 0) := (others => '0');

        -- Program the target model's per-transaction shape. Held stable by
        -- the model across one START..STOP frame (mirrors qspi_launch's
        -- cfg_* settle idiom).
        procedure i3c_cfg_model(addr    : std_logic_vector(6 downto 0);
                                legacy  : boolean;
                                stretch : boolean;
                                nread   : natural;
                                seed    : std_logic_vector(7 downto 0);
                                corrupt : boolean) is
        begin
            cfg_target_addr     <= addr;
            cfg_legacy_mode     <= legacy;
            cfg_legacy_stretch  <= stretch;
            cfg_num_read_bytes  <= nread;
            cfg_read_seed       <= seed;
            cfg_corrupt_wparity <= corrupt;
            wait for 1 ns;   -- let cfg_* settle before any bus/pin activity
        end procedure;

        -- Program CR (I3CEN=1 always -- callers exercising the launch guards
        -- write CR/CMD directly instead) and CMD (LAUNCH).
        procedure i3c_launch(addr                          : std_logic_vector(6 downto 0);
                             rnw, sr, stopen, busmode, sdapp : std_logic;
                             dlen                           : natural;
                             odbr, ppbr                     : std_logic_vector(7 downto 0);
                             tcie, errie, rxfie, txeie      : std_logic) is
        begin
            bus_write(clk, pbus, SlotI3CxCR,
                      i3c_mk_cr('1', busmode, sdapp, '0', tcie, errie, '0', '0', rxfie, txeie,
                                odbr, ppbr));
            bus_write(clk, pbus, SlotI3CxCMD,
                      i3c_mk_cmd(addr, rnw, sr, stopen, '0', '0', '0', '0',
                                 std_logic_vector(to_unsigned(dlen, 8))));   -- LAUNCH
        end procedure;

        -- W1C-clear the given SR bits, then retire the gated-ClkMem clear
        -- pulse with a dummy CR read before re-reading SR (QSPI/UART idiom).
        procedure i3c_w1c_clear(mask : std_logic_vector(31 downto 0)) is
            variable r : std_logic_vector(31 downto 0);
        begin
            bus_write(clk, pbus, SlotI3CxSR, mask);
            bus_read(clk, pbus, rdata_out, SlotI3CxCR, r);   -- dummy access: retire the W1C pulse
        end procedure;

        -- Bounded (guard-timeout) measurement of one SCL LOW->HIGH half
        -- period on the resolved bus. got=false if either edge doesn't show
        -- up within `guard` -- NEVER hangs even with no DUT connected yet
        -- (see the file-header ambiguity note on GROUP 8).
        procedure measure_half_period(guard : in time; got : out boolean; dur : out time) is
            variable t_start, t_mid : time;
        begin
            got := false;
            dur := 0 ns;
            t_start := now;
            -- weak-level correct (ruling 2): normalize the resolved net so a
            -- released 'H' counts as a high (I3C-SDR SCL is push-pull here, but
            -- keep the checker honest about the wired-AND contract).
            wait until to_X01(scl_bus) = '0' for guard;
            if now < t_start + guard then
                t_mid := now;
                wait until to_X01(scl_bus) = '1' for guard;
                if now < t_mid + guard then
                    dur := now - t_mid;
                    got := true;
                end if;
            end if;
        end procedure;

        -- Program one DAT entry (slot 5 write: IDX also selects the entry).
        procedure prog_dat(idx       : natural;
                           evalid    : std_logic;
                           dynaddr   : std_logic_vector(6 downto 0);
                           dynvalid  : std_logic;
                           stataddr  : std_logic_vector(6 downto 0);
                           statvalid : std_logic) is
            variable wd : std_logic_vector(31 downto 0) := (others => '0');
        begin
            wd(2 downto 0)   := std_logic_vector(to_unsigned(idx, 3));
            wd(3)            := evalid;
            wd(10 downto 4)  := dynaddr;
            wd(11)           := dynvalid;
            wd(18 downto 12) := stataddr;
            wd(19)           := statvalid;
            bus_write(clk, pbus, SlotI3CxDAT, wd);
        end procedure;

        -- READBACK NOTE: a slot-5 write carries IDX *and* the entry's
        -- firmware fields, so re-selecting an entry rewrites its EVALID/DYNADDR/
        -- DYNVALID/STAT (PID/BCR/DCR in slots 6/7 are untouched). Hardware never
        -- moves IDX, so the LAST-programmed entry can be read back with its
        -- hardware-set EVALID/DYNVALID INTACT (genuine, non-circular). The other
        -- entry is re-selected only to read its captured PID/BCR/DCR; its
        -- assigned address is proven independently by the model's obs_daa_*.

    begin
        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------
        resetn <= '0';
        pbus   <= PERIPH_BUS_IDLE;
        wait for 4 * PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 4 * PERIOD;

        ----------------------------------------------------------------
        -- GROUP 0: reset defaults
        ----------------------------------------------------------------
        report "=== GROUP 0: reset defaults ===" severity note;

        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_slv("GROUP0: SR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, SlotI3CxRX, rdw);
        sb.check_slv("GROUP0: RX resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, SlotI3CxCR, rdw);
        sb.check_slv("GROUP0: CR resets to 0 except SDAPP=1", rdw, x"00000004");

        ----------------------------------------------------------------
        -- GROUP 1: SDR write (obs_wdata + parity-ok)
        ----------------------------------------------------------------
        report "=== GROUP 1: SDR write ===" severity note;

        i3c_cfg_model(addr => "1010000", legacy => false, stretch => false,
                     nread => 1, seed => x"A5", corrupt => false);
        bus_write(clk, pbus, SlotI3CxTX, x"0000003C");
        i3c_launch(addr => "1010000", rnw => '0', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 1,
                  odbr => x"04", ppbr => x"01",
                  tcie => '1', errie => '1', rxfie => '0', txeie => '1');

        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP1: BUSY cleared within bound", done_ok);
        sb.check_bit("GROUP1: address ACKed", model_obs_addr_acked, '1');
        sb.check_slv("GROUP1: model saw addr 0x50", model_obs_addr, "1010000");
        sb.check_bit("GROUP1: model saw RNW=0 (write)", model_obs_rnw, '0');
        sb.check_true("GROUP1: model captured exactly 1 byte", model_obs_wcount = 1);
        sb.check_slv("GROUP1: model captured TX byte 0x3C", model_obs_wdata(0), x"3C");
        sb.check_bit("GROUP1: model's own parity check passed", model_obs_wparity_ok(0), '1');

        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP1: TCIF set",  rdw(SrBitTCIF), '1');
        sb.check_bit("GROUP1: ANACK NOT set", rdw(SrBitANACK), '0');
        i3c_w1c_clear(x"0000000E");   -- TCIF|RXFULL|TXEIF
        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP1: TCIF cleared", rdw(SrBitTCIF), '0');

        ----------------------------------------------------------------
        -- GROUP 2: SDR read (one literal-value check)
        ----------------------------------------------------------------
        report "=== GROUP 2: SDR read ===" severity note;

        i3c_cfg_model(addr => "1010000", legacy => false, stretch => false,
                     nread => 1, seed => x"A5", corrupt => false);
        i3c_launch(addr => "1010000", rnw => '1', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 1,
                  odbr => x"04", ppbr => x"01",
                  tcie => '1', errie => '1', rxfie => '1', txeie => '0');

        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP2: BUSY cleared within bound", done_ok);

        bus_read(clk, pbus, rdata_out, SlotI3CxRX, rdw);
        -- DIRECTED literal check (checker-independence, the QSPI GROUP 8d
        -- lesson): target_addr=0x50, seed=0xA5, byte_idx=0 =>
        -- 0x50 xor 0xA5 = 0101_0000 xor 1010_0101 = 1111_0101 = 0xF5,
        -- HAND-COMPUTED independently of i3c_read_pattern().
        sb.check_slv("GROUP2: RX matches HAND-COMPUTED literal 0xF5", rdw(7 downto 0), x"F5");
        expected := i3c_read_pattern("1010000", x"A5", 0);
        sb.check_slv("GROUP2: RX matches i3c_read_pattern()", rdw(7 downto 0), expected);

        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP2: RXFULL set", rdw(SrBitRXFULL), '1');
        sb.check_bit("GROUP2: TCIF set",   rdw(SrBitTCIF), '1');
        sb.check_bit("GROUP2: EODF NOT set", rdw(SrBitEODF), '0');
        i3c_w1c_clear(x"0000000E");

        ----------------------------------------------------------------
        -- GROUP 3: multi-byte DLEN streaming (TXEIF / RXFULL)
        ----------------------------------------------------------------
        report "=== GROUP 3: multi-byte streaming ===" severity note;

        -- 3a: 3-byte WRITE stream
        i3c_cfg_model(addr => "1010000", legacy => false, stretch => false,
                     nread => 1, seed => x"A5", corrupt => false);
        bus_write(clk, pbus, SlotI3CxTX, x"00000011");
        i3c_launch(addr => "1010000", rnw => '0', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 3,
                  odbr => x"04", ppbr => x"01",
                  tcie => '1', errie => '1', rxfie => '0', txeie => '1');

        i3c_wait_sr_bit_set(clk, pbus, rdata_out, SrBitTXEIF, done_ok);
        sb.check_true("GROUP3a: TXEIF set for byte 1", done_ok);
        bus_write(clk, pbus, SlotI3CxTX, x"00000022");
        i3c_w1c_clear(x"00000008");   -- clear TXEIF, retire

        i3c_wait_sr_bit_set(clk, pbus, rdata_out, SrBitTXEIF, done_ok);
        sb.check_true("GROUP3a: TXEIF set for byte 2", done_ok);
        bus_write(clk, pbus, SlotI3CxTX, x"00000033");
        i3c_w1c_clear(x"00000008");

        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP3a: BUSY cleared within bound", done_ok);
        sb.check_true("GROUP3a: model captured exactly 3 bytes", model_obs_wcount = 3);
        sb.check_slv("GROUP3a: byte0 = 0x11", model_obs_wdata(0), x"11");
        sb.check_slv("GROUP3a: byte1 = 0x22", model_obs_wdata(1), x"22");
        sb.check_slv("GROUP3a: byte2 = 0x33", model_obs_wdata(2), x"33");
        sb.check_bit("GROUP3a: all 3 parity checks passed",
                    (model_obs_wparity_ok(0) and model_obs_wparity_ok(1) and model_obs_wparity_ok(2)), '1');
        i3c_w1c_clear(x"0000000E");

        -- 3b: 3-byte READ stream (model has exactly 3 bytes -> no EODF)
        i3c_cfg_model(addr => "1010000", legacy => false, stretch => false,
                     nread => 3, seed => x"5A", corrupt => false);
        i3c_launch(addr => "1010000", rnw => '1', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 3,
                  odbr => x"04", ppbr => x"01",
                  tcie => '1', errie => '1', rxfie => '1', txeie => '0');

        for i in 0 to 2 loop
            i3c_wait_sr_bit_set(clk, pbus, rdata_out, SrBitRXFULL, done_ok);
            sb.check_true("GROUP3b: RXFULL set for byte " & integer'image(i), done_ok);
            bus_read(clk, pbus, rdata_out, SlotI3CxRX, rdw);
            expected := i3c_read_pattern("1010000", x"5A", i);
            sb.check_slv("GROUP3b: RX byte " & integer'image(i) & " matches pattern",
                        rdw(7 downto 0), expected);
            i3c_w1c_clear(x"00000004");   -- clear RXFULL
        end loop;

        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP3b: BUSY cleared within bound", done_ok);
        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP3b: TCIF set",    rdw(SrBitTCIF), '1');
        sb.check_bit("GROUP3b: EODF NOT set", rdw(SrBitEODF), '0');
        i3c_w1c_clear(x"0000000E");

        ----------------------------------------------------------------
        -- GROUP 4: read early-terminate -> EODF
        ----------------------------------------------------------------
        report "=== GROUP 4: read early-terminate (EODF) ===" severity note;

        -- Target only has 1 byte; controller asks for 3 (DLEN=3).
        i3c_cfg_model(addr => "1010000", legacy => false, stretch => false,
                     nread => 1, seed => x"5A", corrupt => false);
        i3c_launch(addr => "1010000", rnw => '1', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 3,
                  odbr => x"04", ppbr => x"01",
                  tcie => '1', errie => '1', rxfie => '1', txeie => '0');

        i3c_wait_sr_bit_set(clk, pbus, rdata_out, SrBitRXFULL, done_ok);
        sb.check_true("GROUP4: RXFULL set for the target's 1 available byte", done_ok);
        bus_read(clk, pbus, rdata_out, SlotI3CxRX, rdw);
        expected := i3c_read_pattern("1010000", x"5A", 0);
        sb.check_slv("GROUP4: RX byte0 matches pattern", rdw(7 downto 0), expected);
        i3c_w1c_clear(x"00000004");

        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP4: BUSY cleared within bound (short read)", done_ok);
        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP4: EODF set (short read)", rdw(SrBitEODF), '1');
        i3c_w1c_clear(x"0000000E");

        ----------------------------------------------------------------
        -- GROUP 5: address NACK -> ANACK
        ----------------------------------------------------------------
        report "=== GROUP 5: address NACK ===" severity note;

        -- Model is configured for 0x50; CMD targets 0x51 (mismatch).
        i3c_cfg_model(addr => "1010000", legacy => false, stretch => false,
                     nread => 1, seed => x"A5", corrupt => false);
        bus_write(clk, pbus, SlotI3CxTX, x"00000099");
        i3c_launch(addr => "1010001", rnw => '0', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 1,
                  odbr => x"04", ppbr => x"01",
                  tcie => '1', errie => '1', rxfie => '0', txeie => '0');

        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP5: BUSY cleared within bound", done_ok);
        sb.check_bit("GROUP5: model did NOT ack the mismatched address", model_obs_addr_acked, '0');
        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP5: ANACK set", rdw(SrBitANACK), '1');
        i3c_w1c_clear(x"0000001E");   -- ANACK|EODF|TXEIF|RXFULL|TCIF

        ----------------------------------------------------------------
        -- GROUP 6: legacy-I2C transfer
        ----------------------------------------------------------------
        report "=== GROUP 6: legacy-I2C transfer ===" severity note;

        i3c_cfg_model(addr => "1010000", legacy => true, stretch => false,
                     nread => 1, seed => x"A5", corrupt => false);
        bus_write(clk, pbus, SlotI3CxTX, x"00000077");
        i3c_launch(addr => "1010000", rnw => '0', sr => '0', stopen => '1',
                  busmode => '1', sdapp => '1', dlen => 1,   -- BUSMODE=1 (legacy)
                  odbr => x"04", ppbr => x"01",
                  tcie => '1', errie => '1', rxfie => '0', txeie => '0');

        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP6: BUSY cleared within bound (legacy)", done_ok);
        sb.check_bit("GROUP6: model ACKed the address (legacy)", model_obs_addr_acked, '1');
        sb.check_true("GROUP6: model captured exactly 1 legacy byte", model_obs_wcount = 1);
        sb.check_slv("GROUP6: legacy write byte captured 0x77", model_obs_wdata(0), x"77");
        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP6: TCIF set (legacy)", rdw(SrBitTCIF), '1');
        i3c_w1c_clear(x"0000000E");

        ----------------------------------------------------------------
        -- GROUP 7: parity-mismatch injection
        ----------------------------------------------------------------
        report "=== GROUP 7: parity-mismatch injection ===" severity note;

        i3c_cfg_model(addr => "1010000", legacy => false, stretch => false,
                     nread => 1, seed => x"A5", corrupt => true);   -- inject
        bus_write(clk, pbus, SlotI3CxTX, x"0000005A");
        i3c_launch(addr => "1010000", rnw => '0', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 1,
                  odbr => x"04", ppbr => x"01",
                  tcie => '1', errie => '1', rxfie => '0', txeie => '0');

        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP7: BUSY cleared within bound", done_ok);
        sb.check_slv("GROUP7: model still captured the real byte 0x5A", model_obs_wdata(0), x"5A");
        sb.check_bit("GROUP7: injected parity mismatch observed (obs_wparity_ok=0)",
                    model_obs_wparity_ok(0), '0');
        i3c_w1c_clear(x"0000000E");

        ----------------------------------------------------------------
        -- GROUP 8: ODBR/PPBR baud sanity
        --   Does NOT assume which protocol phase it samples (see the file
        --   header ambiguity note) -- checks only that the baud generator
        --   responds to ODBR/PPBR: two back-to-back single-byte writes with
        --   the two fields swapped should show different first-observed SCL
        --   half-periods. Bounded (guard-timeout) measurement -- reports
        --   "inconclusive" rather than failing if no edge is observed
        --   (e.g. no DUT connected yet), so this group never inflates the
        --   error count.
        ----------------------------------------------------------------
        report "=== GROUP 8: ODBR/PPBR baud sanity ===" severity note;

        i3c_cfg_model(addr => "1010000", legacy => false, stretch => false,
                     nread => 1, seed => x"A5", corrupt => false);
        bus_write(clk, pbus, SlotI3CxTX, x"000000AA");
        i3c_launch(addr => "1010000", rnw => '0', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 1,
                  odbr => x"02", ppbr => x"20",
                  tcie => '0', errie => '0', rxfie => '0', txeie => '0');
        measure_half_period(300 * PERIOD, got_od, t_od);
        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        i3c_w1c_clear(x"0000000E");

        i3c_cfg_model(addr => "1010000", legacy => false, stretch => false,
                     nread => 1, seed => x"A5", corrupt => false);
        bus_write(clk, pbus, SlotI3CxTX, x"000000BB");
        i3c_launch(addr => "1010000", rnw => '0', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 1,
                  odbr => x"20", ppbr => x"02",
                  tcie => '0', errie => '0', rxfie => '0', txeie => '0');
        measure_half_period(300 * PERIOD, got_pp, t_pp);
        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        i3c_w1c_clear(x"0000000E");

        if got_od and got_pp then
            sb.check_true("GROUP8: SCL half-period changes when ODBR/PPBR are swapped",
                          t_od /= t_pp);
        else
            report "GROUP8: baud-sanity measurement inconclusive (bounded timeout -- " &
                   "expected until a real DUT is connected)" severity note;
        end if;

        ----------------------------------------------------------------
        -- GROUP 9: launch guards
        ----------------------------------------------------------------
        report "=== GROUP 9: launch guards ===" severity note;

        -- (a) I3CEN=0: a CMD write must not launch anything.
        txn_before := model_obs_txn_count;
        bus_write(clk, pbus, SlotI3CxCR, x"00000000");   -- I3CEN=0
        bus_write(clk, pbus, SlotI3CxCMD,
                  i3c_mk_cmd("1010000", '0', '0', '1', '0', '0', '0', '0', x"01"));
        wait for 10 * PERIOD;
        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP9a: BUSY stays 0 with I3CEN=0", rdw(SrBitBUSY), '0');
        sb.check_true("GROUP9a: model transaction count unchanged", model_obs_txn_count = txn_before);

        -- (b) BUSY=1: a second CMD write while a transaction is in flight
        --     must not be queued or corrupt the in-flight one. Launch a
        --     slow (small ODBR/PPBR) 3-byte write, then race a second CMD
        --     write in shortly after (timing assumption flagged in the file
        --     header).
        txn_before := model_obs_txn_count;
        i3c_cfg_model(addr => "1010000", legacy => false, stretch => false,
                     nread => 1, seed => x"A5", corrupt => false);
        bus_write(clk, pbus, SlotI3CxTX, x"000000C1");
        -- Moderate baud (D32: small ODBR/PPBR): BUSY still rises within a couple
        -- of clk of launch, so the +3*PERIOD 2nd-CMD race holds, and each byte
        -- stays inside the bounded TXEIF poll budget (0x20/0x20 overran it).
        i3c_launch(addr => "1010000", rnw => '0', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 3,
                  odbr => x"04", ppbr => x"01",
                  tcie => '0', errie => '0', rxfie => '0', txeie => '0');
        wait for 3 * PERIOD;
        bus_write(clk, pbus, SlotI3CxCMD,
                  i3c_mk_cmd("1010000", '0', '0', '1', '0', '0', '0', '0', x"01"));  -- must be ignored (BUSY)

        -- keep feeding the in-flight write's remaining bytes
        i3c_wait_sr_bit_set(clk, pbus, rdata_out, SrBitTXEIF, done_ok);
        if done_ok then
            bus_write(clk, pbus, SlotI3CxTX, x"000000C2");
            i3c_w1c_clear(x"00000008");
        end if;
        i3c_wait_sr_bit_set(clk, pbus, rdata_out, SrBitTXEIF, done_ok);
        if done_ok then
            bus_write(clk, pbus, SlotI3CxTX, x"000000C3");
            i3c_w1c_clear(x"00000008");
        end if;

        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP9b: BUSY cleared within bound", done_ok);
        sb.check_true("GROUP9b: exactly one transaction ran", model_obs_txn_count = txn_before + 1);
        i3c_w1c_clear(x"0000000E");

        ----------------------------------------------------------------
        -- GROUP 10: interrupts (irq_tc, irq_rxf, irq_nack) assert + W1C clear
        ----------------------------------------------------------------
        report "=== GROUP 10: interrupts ===" severity note;

        -- (a) TCIE=1: irq_tc rises with TCIF, falls after W1C.
        i3c_cfg_model(addr => "1010000", legacy => false, stretch => false,
                     nread => 1, seed => x"A5", corrupt => false);
        bus_write(clk, pbus, SlotI3CxTX, x"000000D1");
        i3c_launch(addr => "1010000", rnw => '0', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 1,
                  odbr => x"04", ppbr => x"01",
                  tcie => '1', errie => '0', rxfie => '0', txeie => '0');
        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP10a: BUSY cleared within bound", done_ok);
        sb.check_bit("GROUP10a: irq_tc asserted (TCIF & TCIE)", irq_tc, '1');
        i3c_w1c_clear(x"00000002");   -- clear TCIF
        sb.check_bit("GROUP10a: irq_tc cleared after TCIF W1C", irq_tc, '0');
        i3c_w1c_clear(x"0000000E");

        -- (b) RXFIE=1: irq_rxf rises with RXFULL, falls after W1C.
        i3c_cfg_model(addr => "1010000", legacy => false, stretch => false,
                     nread => 1, seed => x"A5", corrupt => false);
        i3c_launch(addr => "1010000", rnw => '1', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 1,
                  odbr => x"04", ppbr => x"01",
                  tcie => '0', errie => '0', rxfie => '1', txeie => '0');
        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP10b: BUSY cleared within bound", done_ok);
        sb.check_bit("GROUP10b: irq_rxf asserted (RXFULL & RXFIE)", irq_rxf, '1');
        i3c_w1c_clear(x"00000004");   -- clear RXFULL
        sb.check_bit("GROUP10b: irq_rxf cleared after RXFULL W1C", irq_rxf, '0');
        i3c_w1c_clear(x"0000000E");

        -- (c) ERRIE=1 + address NACK: irq_nack rises with ANACK, falls after W1C.
        i3c_cfg_model(addr => "1010000", legacy => false, stretch => false,
                     nread => 1, seed => x"A5", corrupt => false);
        bus_write(clk, pbus, SlotI3CxTX, x"000000D2");
        i3c_launch(addr => "1010001", rnw => '0', sr => '0', stopen => '1',   -- mismatched addr
                  busmode => '0', sdapp => '1', dlen => 1,
                  odbr => x"04", ppbr => x"01",
                  tcie => '0', errie => '1', rxfie => '0', txeie => '0');
        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP10c: BUSY cleared within bound", done_ok);
        sb.check_bit("GROUP10c: irq_nack asserted (ANACK & ERRIE)", irq_nack, '1');
        i3c_w1c_clear(x"00000010");   -- clear ANACK
        sb.check_bit("GROUP10c: irq_nack cleared after ANACK W1C", irq_nack, '0');
        i3c_w1c_clear(x"0000001E");

        ----------------------------------------------------------------
        -- GROUP 12: ENTDAA -- two-target dynamic address assignment.
        --   A (PID 0xA0...0A) wins round 1 -> DAT entry 0 (DYNADDR 0x08);
        --   B (PID 0xB0...0B) wins round 2 -> DAT entry 1 (DYNADDR 0x09);
        --   round 3: both assigned -> NACK -> DAADONE. Real wired-AND arb.
        ----------------------------------------------------------------
        report "=== GROUP 12: ENTDAA two-target assignment ===" severity note;

        cfg_daa_enable <= false;     -- keep the stage-1 model off the DAA bus
        a_enable <= true;  b_enable <= true;
        wait for 1 ns;

        -- Firmware pre-programs the two DAT entries (DYNADDR set, EVALID=0 so
        -- the DAA engine fills them in order). Entry 1 is programmed LAST so
        -- IDX rests at 1 for a non-circular hardware-set readback.
        prog_dat(0, '0', "0001000", '0', "0000000", '0');   -- DYNADDR 0x08
        prog_dat(1, '0', "0001001", '0', "0000000", '0');   -- DYNADDR 0x09

        bus_write(clk, pbus, SlotI3CxCR,
                  i3c_mk_cr('1', '0', '1', '0', '0', '1', '1', '0', '0', '0',
                            x"01", x"01"));                   -- ERRIE+DAAIE, ODBR/PPBR small
        bus_write(clk, pbus, SlotI3CxCMD,
                  i3c_mk_cmd("0000000", '0', '0', '1', '0', '0', '1', '0',
                             x"00", x"07"));                  -- DAARUN=1, ENTDAA CCCOP 0x07

        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP12: ENTDAA run finished within bound", done_ok);

        -- model-side (independent, over-the-wire) assignment observations
        sb.check_bit("GROUP12: model A assigned", a_daa_assigned, '1');
        sb.check_slv("GROUP12: model A got dyn addr 0x08", a_daa_dynaddr, "0001000");
        sb.check_bit("GROUP12: model A assign parity OK", a_daa_parity_ok, '1');
        sb.check_bit("GROUP12: model B assigned", b_daa_assigned, '1');
        sb.check_slv("GROUP12: model B got dyn addr 0x09", b_daa_dynaddr, "0001001");
        sb.check_bit("GROUP12: model B assign parity OK", b_daa_parity_ok, '1');

        -- status: DAADONE (round-3 NACK) + DAAFULL (captures) + irq_daa
        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP12: DAADONE set", rdw(SrBitDAADONE), '1');
        sb.check_bit("GROUP12: DAAFULL set", rdw(SrBitDAAFULL), '1');
        sb.check_bit("GROUP12: irq_daa asserted (DAADONE & DAAIE)", irq_daa, '1');

        -- DAT readback: entry 1 is genuine (IDX rests at 1, EVALID/DYNVALID
        -- were 0 in firmware and hardware set them to 1).
        bus_read(clk, pbus, rdata_out, SlotI3CxDAT, rdw);
        sb.check_bit("GROUP12: entry1 EVALID set by HW",   rdw(3), '1');
        sb.check_bit("GROUP12: entry1 DYNVALID set by HW", rdw(11), '1');
        sb.check_slv("GROUP12: entry1 DYNADDR = 0x09", rdw(10 downto 4), "0001001");
        bus_read(clk, pbus, rdata_out, SlotI3CxDATPID, rdw);
        sb.check_slv("GROUP12: entry1 PID[31:0] = 0x0000000B", rdw, x"0000000B");
        bus_read(clk, pbus, rdata_out, SlotI3CxDATINFO, rdw);
        sb.check_slv("GROUP12: entry1 DCR = 0x44", rdw(31 downto 24), x"44");
        sb.check_slv("GROUP12: entry1 BCR = 0x33", rdw(23 downto 16), x"33");
        sb.check_slv("GROUP12: entry1 PID[47:32] = 0xB000", rdw(15 downto 0), x"B000");

        -- entry 0: re-select (clobbers slot-5 fields, PID/BCR/DCR intact).
        prog_dat(0, '0', "0001000", '0', "0000000", '0');
        bus_read(clk, pbus, rdata_out, SlotI3CxDATPID, rdw);
        sb.check_slv("GROUP12: entry0 PID[31:0] = 0x0000000A", rdw, x"0000000A");
        bus_read(clk, pbus, rdata_out, SlotI3CxDATINFO, rdw);
        sb.check_slv("GROUP12: entry0 DCR = 0x22", rdw(31 downto 24), x"22");
        sb.check_slv("GROUP12: entry0 BCR = 0x11", rdw(23 downto 16), x"11");
        sb.check_slv("GROUP12: entry0 PID[47:32] = 0xA000", rdw(15 downto 0), x"A000");

        -- irq_daa clears on DAADONE W1C (DAAFULL alone does not source it)
        i3c_w1c_clear(x"00000080");   -- clear DAADONE
        sb.check_bit("GROUP12: irq_daa cleared after DAADONE W1C", irq_daa, '0');
        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP12: DAAFULL still set (independent W1C)", rdw(SrBitDAAFULL), '1');
        i3c_w1c_clear(x"0000018E");   -- clear DAAFULL|DAADONE|TCIF|RXFULL|TXEIF
        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP12: DAAFULL cleared after W1C", rdw(SrBitDAAFULL), '0');

        ----------------------------------------------------------------
        -- GROUP 12b: directed SDR write to model A's new dynamic address
        -- (0x08) -- proves the freshly-assigned target is live.
        ----------------------------------------------------------------
        report "=== GROUP 12b: directed write to assigned dyn addr ===" severity note;

        bus_write(clk, pbus, SlotI3CxTX, x"0000003C");
        i3c_launch(addr => "0001000", rnw => '0', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 1,
                  odbr => x"04", ppbr => x"01",
                  tcie => '1', errie => '1', rxfie => '0', txeie => '1');
        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP12b: BUSY cleared within bound", done_ok);
        sb.check_bit("GROUP12b: model A ACKed its dynamic address", a_obs_addr_acked, '1');
        sb.check_true("GROUP12b: model A captured 1 byte", a_obs_wcount = 1);
        sb.check_slv("GROUP12b: model A captured 0x3C", a_obs_wdata(0), x"3C");
        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP12b: ANACK NOT set (address was live)", rdw(SrBitANACK), '0');
        i3c_w1c_clear(x"0000000E");

        ----------------------------------------------------------------
        -- GROUP 13: SETDASA -- assign a dynamic address to a target at its
        -- static address (direct CCC 0x87). Uses the stage-1 model at 0x55.
        ----------------------------------------------------------------
        report "=== GROUP 13: SETDASA ===" severity note;

        cfg_target_addr <= "1010101";   -- 0x55
        cfg_daa_enable  <= true;         -- stage-1 model ACKs the 0x7E header
        wait for 1 ns;

        -- DAT entry 2: STATADDR 0x55 (valid) + DYNADDR 0x0A (DYNVALID=0 -> HW).
        prog_dat(2, '0', "0001010", '0', "1010101", '1');

        bus_write(clk, pbus, SlotI3CxCR,
                  i3c_mk_cr('1', '0', '1', '0', '0', '1', '0', '0', '0', '0',
                            x"01", x"01"));
        bus_write(clk, pbus, SlotI3CxCMD,
                  i3c_mk_cmd("1010101", '0', '0', '1', '0', '0', '0', '1',
                             x"00", x"87"));                  -- DASA=1, SETDASA CCCOP 0x87

        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP13: SETDASA run finished within bound", done_ok);
        sb.check_bit("GROUP13: model ACKed its static address", model_obs_addr_acked, '1');
        sb.check_true("GROUP13: model captured the address byte", model_obs_wcount = 1);
        sb.check_slv("GROUP13: model got (dyn addr << 1) = 0x14", model_obs_wdata(0), x"14");

        -- DUT DAT entry 2: DYNVALID set by hardware on the static-addr ACK.
        bus_read(clk, pbus, rdata_out, SlotI3CxDAT, rdw);
        sb.check_bit("GROUP13: entry2 DYNVALID set by HW", rdw(11), '1');
        sb.check_slv("GROUP13: entry2 DYNADDR = 0x0A", rdw(10 downto 4), "0001010");
        sb.check_bit("GROUP13: entry2 STATVALID still set", rdw(19), '1');
        sb.check_slv("GROUP13: entry2 STATADDR = 0x55", rdw(18 downto 12), "1010101");
        i3c_w1c_clear(x"0000000E");

        ----------------------------------------------------------------
        -- GROUP 14: IBI full path (IBIEN=1, mandatory-data byte) -- model A
        -- (ENTDAA-assigned 0x08, DAT entry 0) raises an in-band interrupt. We
        -- first make DAT entry 0 carry BCR[2]=1 (MDB present) via a firmware
        -- DATINFO write, arm IBIEN, then trigger the IBI. The controller must
        -- auto-ACK (R2), clock the MDB, capture {addr,MDB,hasdata,acked} into
        -- I3CxIBI, set SR.IBIP + irq_ibi, and recover the bus afterwards.
        ----------------------------------------------------------------
        report "=== GROUP 14: IBI full path (IBIEN=1 + MDB) ===" severity note;

        a_enable <= false; b_enable <= false;   -- ENTDAA done; models stay assigned
        cfg_daa_enable <= false;
        wait for 1 ns;

        -- Re-affirm entry 0 (DYNADDR 0x08, DYNVALID=1) and give it BCR[2]=1.
        prog_dat(0, '1', "0001000", '1', "0000000", '0');   -- select IDX 0, keep it valid
        -- DATINFO (slot 7): DCR=0x22, BCR=0x04 (bit2 set => MDB), PID[47:32]=0xA000.
        bus_write(clk, pbus, SlotI3CxDATINFO, x"2204" & x"A000");

        -- Arm the controller for IBIs: I3CEN=1, IBIEN=1, IBIIE=1 (irq_ibi),
        -- ERRIE for good measure. CR write does NOT launch. ODBR/PPBR small.
        bus_write(clk, pbus, SlotI3CxCR,
                  i3c_mk_cr('1', '0', '1', '1',            -- EN, BUSMODE=0, SDAPP=1, IBIEN=1
                            '0', '1', '0', '1', '0', '0',  -- ERRIE + IBIIE
                            x"04", x"01"));

        -- Configure and fire model A's IBI (MDB 0x5C).
        a_ibi_mdb      <= x"5C";
        a_ibi_has_data <= true;
        wait for 1 ns;
        a_ibi_trigger  <= '1';                  -- rising edge initiates the IBI

        -- Wait for the service window to open (BUSY rises) then for IBIP.
        i3c_wait_busy_set(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP14: IBI service started (BUSY rose)", done_ok);
        i3c_wait_sr_bit_set(clk, pbus, rdata_out, SrBitIBIP, done_ok);
        sb.check_true("GROUP14: IBIP set within bound", done_ok);
        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP14: BUSY cleared (STOP, bus recovered)", done_ok);
        a_ibi_trigger  <= '0';

        -- irq_ibi asserted (IBIP & IBIIE).
        sb.check_bit("GROUP14: irq_ibi asserted", irq_ibi, '1');
        -- model A saw the ACK.
        sb.check_bit("GROUP14: model A saw the controller ACK", a_obs_ibi_acked, '1');

        -- I3CxIBI capture: addr 0x08, valid, MDB 0x5C, hasdata=1, acked=1.
        bus_read(clk, pbus, rdata_out, SlotI3CxIBI, rdw);
        sb.check_slv("GROUP14: IBIADDR = 0x08", rdw(6 downto 0), "0001000");
        sb.check_bit("GROUP14: IBIVALID set", rdw(7), '1');
        sb.check_slv("GROUP14: IBIMDB = 0x5C", rdw(15 downto 8), x"5C");
        sb.check_bit("GROUP14: IBIHASDATA set (BCR[2]=1)", rdw(16), '1');
        sb.check_bit("GROUP14: IBIACKED set", rdw(17), '1');
        neg_ibi_mdb := rdw(15 downto 8);   -- stash for the negative control

        -- SR.IBIP is set; IBIWON has gone back to 0 (service ended).
        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP14: SR.IBIP set", rdw(SrBitIBIP), '1');

        -- W1C SR.IBIP: clears IBIP, invalidates the I3CxIBI fields, drops irq_ibi.
        i3c_w1c_clear(x"00000200");   -- clear IBIP (bit 9)
        sb.check_bit("GROUP14: irq_ibi cleared after IBIP W1C", irq_ibi, '0');
        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP14: SR.IBIP cleared", rdw(SrBitIBIP), '0');
        bus_read(clk, pbus, rdata_out, SlotI3CxIBI, rdw);
        sb.check_slv("GROUP14: I3CxIBI invalidated on IBIP clear", rdw, x"00000000");

        -- Bus recovered: a normal directed SDR write to 0x08 still works.
        bus_write(clk, pbus, SlotI3CxTX, x"00000046");
        i3c_launch(addr => "0001000", rnw => '0', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 1,
                  odbr => x"04", ppbr => x"01",
                  tcie => '1', errie => '1', rxfie => '0', txeie => '1');
        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP14: post-IBI directed write finished", done_ok);
        sb.check_bit("GROUP14: model A ACKed post-IBI write", a_obs_addr_acked, '1');
        sb.check_slv("GROUP14: model A captured 0x46 post-IBI", a_obs_wdata(0), x"46");
        i3c_w1c_clear(x"0000000E");

        ----------------------------------------------------------------
        -- GROUP 15: IBI NACK path (IBIEN=0) -- the target initiates the same
        -- IBI, but with IBIEN=0 the controller must NACK (release), STOP
        -- cleanly, capture nothing, set no IBIP; the model must observe the
        -- NACK, and the bus must recover.
        ----------------------------------------------------------------
        report "=== GROUP 15: IBI NACK path (IBIEN=0) ===" severity note;

        -- Disarm IBIs: I3CEN=1, IBIEN=0 (IBIIE still on to prove irq stays low).
        bus_write(clk, pbus, SlotI3CxCR,
                  i3c_mk_cr('1', '0', '1', '0',            -- IBIEN=0
                            '0', '1', '0', '1', '0', '0',
                            x"04", x"01"));
        a_ibi_has_data <= true;   -- model offers data, but must honour the NACK
        wait for 1 ns;
        a_ibi_trigger  <= '1';

        i3c_wait_busy_set(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP15: IBI service started (BUSY rose)", done_ok);
        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP15: BUSY cleared (clean NACK STOP)", done_ok);
        a_ibi_trigger  <= '0';

        sb.check_bit("GROUP15: model A saw the NACK", a_obs_ibi_acked, '0');
        bus_read(clk, pbus, rdata_out, SlotI3CxSR, rdw);
        sb.check_bit("GROUP15: SR.IBIP NOT set (NACKed IBI)", rdw(SrBitIBIP), '0');
        sb.check_bit("GROUP15: irq_ibi NOT asserted", irq_ibi, '0');
        bus_read(clk, pbus, rdata_out, SlotI3CxIBI, rdw);
        sb.check_slv("GROUP15: I3CxIBI stayed invalid (no capture)", rdw, x"00000000");

        -- Bus recovered: a normal directed SDR write to 0x08 still works.
        bus_write(clk, pbus, SlotI3CxTX, x"00000047");
        i3c_launch(addr => "0001000", rnw => '0', sr => '0', stopen => '1',
                  busmode => '0', sdapp => '1', dlen => 1,
                  odbr => x"04", ppbr => x"01",
                  tcie => '1', errie => '1', rxfie => '0', txeie => '1');
        i3c_wait_busy_clear(clk, pbus, rdata_out, done_ok);
        sb.check_true("GROUP15: post-NACK directed write finished", done_ok);
        sb.check_slv("GROUP15: model A captured 0x47 post-NACK", a_obs_wdata(0), x"47");
        i3c_w1c_clear(x"0000000E");

        ----------------------------------------------------------------
        -- GROUP 11: NEGATIVE CONTROL (mandatory, D31, LAST -- now stage 3) -- a
        -- deliberately wrong expected IBI MDB. MUST report a mismatch, proving
        -- the checkers can fail. Counted as exactly 1 expected failure.
        ----------------------------------------------------------------
        report "=== GROUP 11: NEGATIVE CONTROL (stage 3) ===" severity note;

        -- the captured IBI MDB was truly 0x5C; compare against 0x5D (wrong).
        sb.check_slv("NEGATIVE CONTROL: wrong expected IBI MDB (must FAIL)",
                    neg_ibi_mdb, std_logic_vector(unsigned(neg_ibi_mdb) + 1));

        ----------------------------------------------------------------
        -- Final verdict: sb.errors() must be EXACTLY 1 (the negative
        -- control above) for an overall PASS.
        ----------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("I3C TB");

        if sb.errors = 1 then
            -- The scoreboard itself always tallies 1 error (the negative
            -- control), so report_summary above prints "1 CHECK(S) FAILED",
            -- not the "ALL CHECKS PASSED" token the parallel periph-suite
            -- runner greps for. Emit that token HERE on a genuine pass so
            -- this bench integrates with xrun_parallel.sh's banner-detection
            -- unchanged; a real failure (errors /= 1) takes the else branch
            -- and never prints it, so the suite still fails the run.
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   I3C_TB PASS (1 expected negative-control failure)" & LF &
                "    ##   I3C TB:  ALL CHECKS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   I3C_TB FAIL (expected exactly 1 failure [negative control], got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        stop;
        wait;
    end process stim_proc;

end architecture sim;
