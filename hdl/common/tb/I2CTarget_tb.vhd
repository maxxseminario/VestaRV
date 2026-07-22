-------------------------------------------------------------------------------
-- I2CTarget_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the I2C TARGET peripheral
-- (hdl/common/periph/I2CTarget.vhd), written AGAINST THE FROZEN ENTITY +
-- REGISTER MAP (~/vesta_docs/digperiphs/i2ct_design.md, D1-D20 + adjudicated
-- tensions) while the RTL is being written in parallel. The DUT is declared as
-- a COMPONENT (not an entity instantiation) so this bench compiles standalone
-- with xmvhdl before I2CTarget.vhd exists; VHDL default binding resolves it to
-- the entity of the same name once I2CTarget.vhd is analyzed into work. Mirrors
-- OneWire_tb.vhd / I3C_tb.vhd structurally.
--
-- Uses tb/periph_tb_pkg.vhd (scoreboard + register-bus BFM, shared) and
-- tb/i2ct_bfm_pkg.vhd (slot/CR/SR constants, the i2ct_mk_cr packer, the bounded
-- SR polls, and the checker-independent SCL-timing constants). The bus master
-- is tb/i2c_host_model.vhd -- the role-inverse of i3c_target_model: it drives
-- the whole I2C frame (START/STOP/Sr, address, data, ACK/NACK) and honours the
-- DUT's clock stretch, measuring the DUT's driven ACK/TX levels off the
-- resolved bus at its OWN sample points (checker independence).
--
-- ONE clock family (design doc D1/D2): `clk` (bound to MCLK at integration)
-- hosts the whole target FSM + the SDA/SCL 2-FF synchronizers + the sticky W1C
-- flags + watchdog; `ClkMem` is the gated bus clock, driven `clk when
-- pbus.en_mem='0' else '0'` exactly like OneWire_tb / I3C_tb. No second domain
-- (I2CT0 is mclk, D2 -- unlike the smclk I2C0 host of the wi2ct loopback).
--
-- SCL:clk RATIO = 32:1 (i2ct_bfm_pkg.I2CT_SCL_HALF_TICKS=16, one SCL period =
-- 2*16 = 32 clk). Above the frozen-doc guaranteed floor of 24:1 (D14) and
-- ~8x the 4-clk FSM edge-to-drive latency per half-period, yet fast enough
-- that the whole suite finishes in seconds of wall clock (the 1-MINUTE RULE).
-- PERIOD = 40 ns => ~25 MHz-equivalent clk; one SCL bit = 32*40 ns = 1.28 us.
--
-- OPEN-DRAIN BIDIRECTIONAL BUS (design doc gotcha 10): SDA and SCL each get a
-- weak 'H' pull (NOT the OW "strong 0"); the DUT pulls low via SDA_DIR/SCL_DIR
-- (this entity has NO *_OUT ports -- D19 ties them '0' at MCU, so DUT drive =
-- '0' when *_DIR='1' else 'Z'), the host model pulls low via its own oe, and
-- every sample of the resolved net is to_X01-normalized.
--
-- DEVIATIONS / scope notes (flagged, not silently resolved):
--   * Clock-stretch tests (G3 RX-stretch, G4 TX-stretch) require the TB to
--     service the DUT (read+W1C RXF / load I2CTTX) DURING the stall. The host
--     model exposes obs_wait_scl='1' while blocked on a genuine stretch; the TB
--     launches the segment non-blocking, waits for obs_wait_scl, services the
--     register, then waits for completion. This is the only mid-transaction
--     interleave; every other segment is launch-then-finish.
--   * BUSY-same-cycle TXE cover (D10) is exercised implicitly by the TX-stretch
--     path (TXE asserted -> load -> stretch releases); a standalone
--     write-then-poll-TXE micro-check is not separately staged.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.i2ct_bfm_pkg.all;

entity I2CTarget_tb is
end entity I2CTarget_tb;

architecture sim of I2CTarget_tb is

    constant PERIOD : time := 40 ns;   -- clk reference (~25 MHz-equivalent, D2)

    -- FROZEN DUT entity (design doc D3), declared as a component so the bench
    -- compiles standalone before hdl/common/periph/I2CTarget.vhd exists.
    component I2CTarget is
        port (
            clk         : in  std_logic;
            resetn      : in  std_logic;
            irq_ae      : out std_logic;
            irq_data    : out std_logic;
            ClkMem      : in  std_logic;
            EnMemPeriph : in  std_logic;
            WEn         : in  std_logic_vector(3 downto 0);
            MABPart     : in  std_logic_vector(7 downto 2);
            wdata       : in  std_logic_vector(31 downto 0);
            rdata_out   : out std_logic_vector(31 downto 0);
            SDA_IN      : in  std_logic;
            SDA_DIR     : out std_logic;
            SCL_IN      : in  std_logic;
            SCL_DIR     : out std_logic
        );
    end component;

    component i2c_host_model is
        port (
            scl_in : in std_logic;
            sda_in : in std_logic;
            sda_out : out std_logic := '0';
            sda_oe  : out std_logic := '0';
            scl_out : out std_logic := '0';
            scl_oe  : out std_logic := '0';
            cfg_go          : in std_logic := '0';
            cfg_op          : in natural   := I2CT_OP_XFER;
            cfg_sr          : in boolean   := false;
            cfg_stop        : in boolean   := true;
            cfg_addr        : in std_logic_vector(6 downto 0) := (others => '0');
            cfg_rnw         : in std_logic := '0';
            cfg_nbytes      : in natural   := 0;
            cfg_wdata       : in i2ct_byte_array(0 to I2CT_MODEL_MAX_BYTES-1) := (others => (others => '0'));
            cfg_rd_ack      : in std_logic_vector(0 to I2CT_MODEL_MAX_BYTES-1) := (others => '0');
            cfg_hold        : in natural   := 0;
            cfg_corrupt     : in boolean   := false;
            cfg_tick_period : in time      := 40 ns;
            obs_count     : out natural := 0;
            obs_addr_ack  : out std_logic := '0';
            obs_wr_ack    : out std_logic_vector(0 to I2CT_MODEL_MAX_BYTES-1) := (others => '0');
            obs_rdata     : out i2ct_byte_array(0 to I2CT_MODEL_MAX_BYTES-1) := (others => (others => '0'));
            obs_wait_scl  : out std_logic := '0';
            obs_stretched : out std_logic := '0';
            obs_timeout   : out std_logic := '0';
            obs_viol      : out std_logic := '0'
        );
    end component;

    -- clocks / reset
    signal clk    : std_logic := '0';
    signal ClkMem : std_logic := '0';
    signal resetn : std_logic := '0';

    -- interrupts
    signal irq_ae, irq_data : std_logic;

    -- register bus (BFM record + observed rdata_out)
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal rdata_out : std_logic_vector(31 downto 0);

    -- DUT pad drive-enables (this entity has no *_OUT ports, D19)
    signal dut_sda_dir, dut_scl_dir : std_logic;

    -- host-model open-drain drive
    signal host_sda_out, host_sda_oe : std_logic;
    signal host_scl_out, host_scl_oe : std_logic;

    -- resolved bus nets, weak 'H' release + to_X01 copies fed to DUT/model
    signal sda_bus, scl_bus         : std_logic;
    signal sda_bus_x01, scl_bus_x01 : std_logic;

    -- host-model per-transaction config
    signal cfg_go       : std_logic := '0';
    signal cfg_op       : natural   := I2CT_OP_XFER;
    signal cfg_sr       : boolean   := false;
    signal cfg_stop     : boolean   := true;
    signal cfg_addr     : std_logic_vector(6 downto 0) := (others => '0');
    signal cfg_rnw      : std_logic := '0';
    signal cfg_nbytes   : natural   := 0;
    signal cfg_wdata    : i2ct_byte_array(0 to I2CT_MODEL_MAX_BYTES-1) := (others => (others => '0'));
    signal cfg_rd_ack   : std_logic_vector(0 to I2CT_MODEL_MAX_BYTES-1) := (others => '0');
    signal cfg_hold     : natural   := 0;
    signal cfg_corrupt  : boolean   := false;

    -- host-model observations
    signal obs_count     : natural;
    signal obs_addr_ack  : std_logic;
    signal obs_wr_ack    : std_logic_vector(0 to I2CT_MODEL_MAX_BYTES-1);
    signal obs_rdata     : i2ct_byte_array(0 to I2CT_MODEL_MAX_BYTES-1);
    signal obs_wait_scl  : std_logic;
    signal obs_stretched : std_logic;
    signal obs_timeout   : std_logic;
    signal obs_viol      : std_logic;

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

begin

    ----------------------------------------------------------------------------
    -- clock / gated register-bus clock (mirrors OneWire_tb / I3C_tb)
    ----------------------------------------------------------------------------
    clk    <= not clk after PERIOD / 2;
    ClkMem <= clk when pbus.en_mem = '0' else '0';

    ----------------------------------------------------------------------------
    -- Open-drain bus resolution (design doc bench plan / gotcha 10): the DUT
    -- pulls low via *_DIR (value '0', no *_OUT port -- D19), the host model
    -- pulls low via its own oe, and a weak 'H' idles the net high. Any '0'
    -- wins (wired-AND). Every sample is to_X01-normalized.
    ----------------------------------------------------------------------------
    sda_bus <= '0'          when dut_sda_dir  = '1' else 'Z';
    sda_bus <= host_sda_out when host_sda_oe  = '1' else 'Z';
    sda_bus <= 'H';
    sda_bus_x01 <= to_X01(sda_bus);

    scl_bus <= '0'          when dut_scl_dir  = '1' else 'Z';
    scl_bus <= host_scl_out when host_scl_oe  = '1' else 'Z';
    scl_bus <= 'H';
    scl_bus_x01 <= to_X01(scl_bus);

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    dut : component I2CTarget
        port map (
            clk         => clk,
            resetn      => resetn,
            irq_ae      => irq_ae,
            irq_data    => irq_data,
            ClkMem      => ClkMem,
            EnMemPeriph => pbus.en_mem,
            WEn         => pbus.wen,
            MABPart     => pbus.addr_periph,
            wdata       => pbus.write_data,
            rdata_out   => rdata_out,
            SDA_IN      => sda_bus_x01,
            SDA_DIR     => dut_sda_dir,
            SCL_IN      => scl_bus_x01,
            SCL_DIR     => dut_scl_dir
        );

    ----------------------------------------------------------------------------
    -- Bit-banged I2C controller (master) model
    ----------------------------------------------------------------------------
    host : component i2c_host_model
        port map (
            scl_in => scl_bus_x01,
            sda_in => sda_bus_x01,
            sda_out => host_sda_out,
            sda_oe  => host_sda_oe,
            scl_out => host_scl_out,
            scl_oe  => host_scl_oe,
            cfg_go          => cfg_go,
            cfg_op          => cfg_op,
            cfg_sr          => cfg_sr,
            cfg_stop        => cfg_stop,
            cfg_addr        => cfg_addr,
            cfg_rnw         => cfg_rnw,
            cfg_nbytes      => cfg_nbytes,
            cfg_wdata       => cfg_wdata,
            cfg_rd_ack      => cfg_rd_ack,
            cfg_hold        => cfg_hold,
            cfg_corrupt     => cfg_corrupt,
            cfg_tick_period => PERIOD,
            obs_count     => obs_count,
            obs_addr_ack  => obs_addr_ack,
            obs_wr_ack    => obs_wr_ack,
            obs_rdata     => obs_rdata,
            obs_wait_scl  => obs_wait_scl,
            obs_stretched => obs_stretched,
            obs_timeout   => obs_timeout,
            obs_viol      => obs_viol
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
                "    !!   I2CTARGET_TB FAIL (WATCHDOG TIMEOUT -- stimulus never finished)" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
            stop;
        end if;
        wait;
    end process;

    ----------------------------------------------------------------------------
    -- stimulus
    ----------------------------------------------------------------------------
    stim_proc : process
        constant SAD : std_logic_vector(6 downto 0) := "1010101";  -- 0x55 target address
        variable rdw : std_logic_vector(31 downto 0);
        variable ok  : boolean;
        variable seg : natural := 0;

        procedure set_cr(en, gcen, csen, aeie, dataie : std_logic;
                         sad  : std_logic_vector(6 downto 0);
                         sadm : std_logic_vector(6 downto 0)) is
        begin
            bus_write(clk, pbus, I2CT_SLOT_CR, i2ct_mk_cr(en, gcen, csen, aeie, dataie, sad, sadm));
        end procedure;

        -- W1C the given SR mask; wait out the clr_*_tgl 2-FF sync + edge detect
        -- (D17) before the caller relies on the flag being clear.
        procedure w1c(mask : std_logic_vector(31 downto 0)) is
        begin
            bus_write(clk, pbus, I2CT_SLOT_SR, mask);
            wait for 6 * PERIOD;
        end procedure;

        -- Launch one host-model segment (NON-blocking: returns after the go
        -- pulse so the TB can service a stretch before completion).
        procedure launch(op : natural; sr, stop : boolean;
                         addr : std_logic_vector(6 downto 0);
                         rnw : std_logic; nbytes : natural;
                         corrupt : boolean := false; hold : natural := 0) is
        begin
            cfg_op <= op; cfg_sr <= sr; cfg_stop <= stop;
            cfg_addr <= addr; cfg_rnw <= rnw; cfg_nbytes <= nbytes;
            cfg_corrupt <= corrupt; cfg_hold <= hold;
            wait for 2 ns;
            cfg_go <= '1';
            wait for 2 ns;
            cfg_go <= '0';
            wait for 2 ns;
        end procedure;

        -- Wait (bounded) for the launched segment to complete.
        procedure finish is
            variable g : natural := 0;
        begin
            seg := seg + 1;
            loop
                exit when obs_count = seg;
                wait for PERIOD;
                g := g + 1;
                exit when g > 400000;   -- bounded (never hangs)
            end loop;
        end procedure;

        -- Wait (bounded) until the host model is blocked on a genuine stretch.
        procedure wait_stretch(done_ok : out boolean) is
            variable g : natural := 0;
        begin
            done_ok := false;
            loop
                if to_X01(obs_wait_scl) = '1' then done_ok := true; exit; end if;
                wait for PERIOD;
                g := g + 1;
                exit when g > 400000;
            end loop;
        end procedure;

    begin
        ------------------------------------------------------------------
        -- Reset
        ------------------------------------------------------------------
        resetn <= '0';
        pbus   <= PERIPH_BUS_IDLE;
        cfg_wdata  <= (others => (others => '0'));
        cfg_rd_ack <= (others => '0');
        wait for 12 * PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 8 * PERIOD;

        ------------------------------------------------------------------
        -- GROUP G0: reset defaults
        ------------------------------------------------------------------
        report "=== GROUP G0: reset defaults ===" severity note;
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_CR, rdw);
        sb.check_slv("G0: CR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_slv("G0: SR resets to 0 (BUSY/TM/flags/TXE all 0 at idle)", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_RX, rdw);
        sb.check_slv("G0: RX resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_WDG, rdw);
        sb.check_slv("G0: WDG resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, 5, rdw);
        sb.check_slv("G0: slot 5 (>=5) reads 0", rdw, x"00000000");
        sb.check_bit("G0: irq_ae = 0 out of reset", to_X01(irq_ae), '0');
        sb.check_bit("G0: irq_data = 0 out of reset", to_X01(irq_data), '0');

        ------------------------------------------------------------------
        -- GROUP G1: address match / mask / mismatch
        ------------------------------------------------------------------
        report "=== GROUP G1: address match / mask / mismatch ===" severity note;
        set_cr('1', '0', '0', '0', '0', SAD, "0000000");
        launch(I2CT_OP_XFER, false, true, SAD, '0', 0);
        finish;
        sb.check_bit("G1: exact-match address ACKed", to_X01(obs_addr_ack), '1');
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G1: AMF set on exact match", to_X01(rdw(I2CT_SR_AMF)), '1');
        sb.check_bit("G1: TM=0 (receiver) on write-direction match", to_X01(rdw(I2CT_SR_TM)), '0');
        sb.check_bit("G1: BUSY cleared after STOP", to_X01(rdw(I2CT_SR_BUSY)), '0');
        w1c(x"000007DC");

        set_cr('1', '0', '0', '0', '0', SAD, "0000001");   -- SADM wildcard bit0
        launch(I2CT_OP_XFER, false, true, "1010100", '0', 0);   -- 0x54 differs only in bit0
        finish;
        sb.check_bit("G1: masked (SADM wildcard) match ACKed", to_X01(obs_addr_ack), '1');
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G1: AMF set on masked match", to_X01(rdw(I2CT_SR_AMF)), '1');
        w1c(x"000007DC");

        set_cr('1', '0', '0', '0', '0', SAD, "0000000");
        launch(I2CT_OP_XFER, false, true, "0101010", '0', 0);   -- 0x2A: full mismatch
        finish;
        sb.check_bit("G1: mismatched address NOT ACKed", to_X01(obs_addr_ack), '0');
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G1: AMF stays 0 on mismatch (silent ignore)", to_X01(rdw(I2CT_SR_AMF)), '0');
        w1c(x"000007DC");

        ------------------------------------------------------------------
        -- GROUP G2: general call
        ------------------------------------------------------------------
        report "=== GROUP G2: general call ===" severity note;
        set_cr('1', '1', '0', '0', '0', SAD, "0000000");   -- GCEN=1
        launch(I2CT_OP_XFER, false, true, "0000000", '0', 0);   -- addr 0x00, write
        finish;
        sb.check_bit("G2: general call (0x00 write) ACKed with GCEN=1", to_X01(obs_addr_ack), '1');
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G2: GCF set on general call", to_X01(rdw(I2CT_SR_GCF)), '1');
        sb.check_bit("G2: AMF companion set on general call", to_X01(rdw(I2CT_SR_AMF)), '1');
        w1c(x"000007DC");

        set_cr('1', '0', '0', '0', '0', SAD, "0000000");   -- GCEN=0
        launch(I2CT_OP_XFER, false, true, "0000000", '0', 0);
        finish;
        sb.check_bit("G2: 0x00 ignored with GCEN=0", to_X01(obs_addr_ack), '0');
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G2: GCF stays 0 with GCEN=0", to_X01(rdw(I2CT_SR_GCF)), '0');
        w1c(x"000007DC");

        ------------------------------------------------------------------
        -- GROUP G3: host-write (RX)
        ------------------------------------------------------------------
        report "=== GROUP G3: host-write (RX) ===" severity note;
        set_cr('1', '0', '0', '0', '0', SAD, "0000000");   -- CSEN=0
        cfg_wdata(0) <= x"A5";
        launch(I2CT_OP_XFER, false, true, SAD, '0', 1);
        finish;
        sb.check_bit("G3: written byte ACKed (buffer free)", to_X01(obs_wr_ack(0)), '1');
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G3: RXF set after a received byte", to_X01(rdw(I2CT_SR_RXF)), '1');
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_RX, rdw);
        sb.check_slv("G3: RX = 0xA5", rdw(7 downto 0), x"A5");
        sb.check_bit("G3: host saw a stable ACK sample (obs_viol=0)", to_X01(obs_viol), '0');
        w1c(x"000007DC");

        cfg_wdata(0) <= x"0F";   -- asymmetric: a reversed (LSB-first) capture reads 0xF0
        launch(I2CT_OP_XFER, false, true, SAD, '0', 1);
        finish;
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_RX, rdw);
        sb.check_slv("G3: RX = 0x0F, MSB-first (a reversed capture reads 0xF0)", rdw(7 downto 0), x"0F");
        w1c(x"000007DC");

        cfg_wdata(0) <= x"11"; cfg_wdata(1) <= x"22";
        launch(I2CT_OP_XFER, false, true, SAD, '0', 2);   -- 2 bytes, no read between
        finish;
        sb.check_bit("G3: first byte ACKed", to_X01(obs_wr_ack(0)), '1');
        sb.check_bit("G3: overrun byte auto-NACKed (RXF still set)", to_X01(obs_wr_ack(1)), '0');
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G3: OVF set on overrun", to_X01(rdw(I2CT_SR_OVF)), '1');
        sb.check_bit("G3: NACKF set on auto-NACK", to_X01(rdw(I2CT_SR_NACKF)), '1');
        w1c(x"000007DC");

        set_cr('1', '0', '1', '0', '0', SAD, "0000000");   -- CSEN=1: RX stretch
        cfg_wdata(0) <= x"33";
        launch(I2CT_OP_XFER, false, true, SAD, '0', 1);
        wait_stretch(ok);
        sb.check_true("G3: RX-stretch: host blocked on held SCL (bounded)", ok);
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_RX, rdw);
        sb.check_slv("G3: RX-stretch: RX = 0x33 read during the stall", rdw(7 downto 0), x"33");
        w1c(x"000007DC");   -- W1C RXF frees the buffer -> DUT releases the stretch
        finish;
        sb.check_bit("G3: RX-stretch: a real stretch was observed", to_X01(obs_stretched), '1');
        sb.check_bit("G3: RX-stretch: no bounded-wait timeout", to_X01(obs_timeout), '0');
        w1c(x"000007DC");

        ------------------------------------------------------------------
        -- GROUP G4: host-read (TX)
        ------------------------------------------------------------------
        report "=== GROUP G4: host-read (TX) ===" severity note;
        set_cr('1', '0', '0', '0', '0', SAD, "0000000");   -- CSEN=0
        bus_write(clk, pbus, I2CT_SLOT_TX, x"00000096");    -- asymmetric: reversed shift sends 0x69
        cfg_rd_ack(0) <= '0';                                -- host NACKs the last byte
        launch(I2CT_OP_XFER, false, true, SAD, '1', 1);
        finish;
        sb.check_bit("G4: read address ACKed", to_X01(obs_addr_ack), '1');
        sb.check_slv("G4: read byte = 0x96, MSB-first (a reversed shift sends 0x69)", obs_rdata(0), x"96");
        sb.check_bit("G4: host saw stable TX data (obs_viol=0)", to_X01(obs_viol), '0');
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G4: TM=1 (transmitter) on read-direction match", to_X01(rdw(I2CT_SR_TM)), '1');
        sb.check_bit("G4: NACKF set when host NACKs the last byte", to_X01(rdw(I2CT_SR_NACKF)), '1');
        w1c(x"000007DC");

        set_cr('1', '0', '1', '0', '0', SAD, "0000000");   -- CSEN=1, buffer empty: TX stretch
        cfg_rd_ack(0) <= '0';
        launch(I2CT_OP_XFER, false, true, SAD, '1', 1);
        wait_stretch(ok);
        sb.check_true("G4: TX-stretch: host blocked (stretch-until-loaded)", ok);
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G4: TX-stretch: TXE asserted during the stall", to_X01(rdw(I2CT_SR_TXE)), '1');
        bus_write(clk, pbus, I2CT_SLOT_TX, x"0000005A");    -- load -> DUT releases the stretch
        finish;
        sb.check_slv("G4: TX-stretch: read byte = loaded 0x5A", obs_rdata(0), x"5A");
        sb.check_bit("G4: TX-stretch: a real stretch was observed", to_X01(obs_stretched), '1');
        w1c(x"000007DC");

        set_cr('1', '0', '0', '0', '0', SAD, "0000000");   -- CSEN=0, buffer empty: 0xFF underrun
        cfg_rd_ack(0) <= '0';
        launch(I2CT_OP_XFER, false, true, SAD, '1', 1);
        finish;
        sb.check_slv("G4: CSEN=0 underrun sends 0xFF (SDA released)", obs_rdata(0), x"FF");
        sb.check_bit("G4: CSEN=0 underrun: no stretch", to_X01(obs_stretched), '0');
        w1c(x"000007DC");

        set_cr('1', '0', '1', '0', '0', SAD, "0000000");   -- CSEN=1: host ACK continues then NACK ends
        bus_write(clk, pbus, I2CT_SLOT_TX, x"00000011");    -- byte0 preloaded
        cfg_rd_ack(0) <= '1';                                -- ACK -> continue
        cfg_rd_ack(1) <= '0';                                -- NACK -> last
        launch(I2CT_OP_XFER, false, true, SAD, '1', 2);
        wait_stretch(ok);                                    -- DUT stretches for byte1
        sb.check_true("G4: host-ACK-continue reached the byte1 stretch", ok);
        bus_write(clk, pbus, I2CT_SLOT_TX, x"00000022");    -- byte1
        finish;
        sb.check_slv("G4: byte0 = 0x11 (host ACK continued the read)", obs_rdata(0), x"11");
        sb.check_slv("G4: byte1 = 0x22 (second byte read after ACK)", obs_rdata(1), x"22");
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G4: NACKF set on the final host NACK", to_X01(rdw(I2CT_SR_NACKF)), '1');
        w1c(x"000007DC");

        set_cr('1', '0', '0', '0', '0', SAD, "0000000");   -- host-model checker self-test (positive)
        bus_write(clk, pbus, I2CT_SLOT_TX, x"000000C3");
        cfg_rd_ack(0) <= '0';
        launch(I2CT_OP_XFER, false, true, SAD, '1', 1, corrupt => true);
        finish;
        sb.check_bit("G4: corrupt self-test forces the host checker flag high", to_X01(obs_viol), '1');
        sb.check_slv("G4: corrupt self-test leaves read data correct (0xC3)", obs_rdata(0), x"C3");
        w1c(x"000007DC");

        ------------------------------------------------------------------
        -- GROUP G5: repeated-START (write-address then Sr then read)
        ------------------------------------------------------------------
        report "=== GROUP G5: repeated-START ===" severity note;
        set_cr('1', '0', '0', '0', '0', SAD, "0000000");
        launch(I2CT_OP_XFER, false, false, SAD, '0', 0);   -- segment A: address-only write, bus held
        finish;
        sb.check_bit("G5: segment-A write address ACKed", to_X01(obs_addr_ack), '1');
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G5: BUSY held after segment A (no STOP)", to_X01(rdw(I2CT_SR_BUSY)), '1');
        sb.check_bit("G5: TM=0 during the write phase", to_X01(rdw(I2CT_SR_TM)), '0');
        sb.check_bit("G5: AMF set on segment A", to_X01(rdw(I2CT_SR_AMF)), '1');
        w1c(x"00000004");   -- clear AMF only; keep BUSY

        bus_write(clk, pbus, I2CT_SLOT_TX, x"00000088");    -- preload the read byte
        cfg_rd_ack(0) <= '0';
        launch(I2CT_OP_XFER, true, true, SAD, '1', 1);      -- cfg_sr=true: repeated-START into a read
        finish;
        sb.check_bit("G5: repeated-START re-address ACKed", to_X01(obs_addr_ack), '1');
        sb.check_slv("G5: read byte after Sr = 0x88", obs_rdata(0), x"88");
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G5: RSTARTF set on repeated-START", to_X01(rdw(I2CT_SR_RSTARTF)), '1');
        sb.check_bit("G5: TM flipped to 1 after the Sr read-address", to_X01(rdw(I2CT_SR_TM)), '1');
        sb.check_bit("G5: BUSY cleared after the final STOP", to_X01(rdw(I2CT_SR_BUSY)), '0');
        w1c(x"000007DC");

        ------------------------------------------------------------------
        -- GROUP G6: STOP flag
        ------------------------------------------------------------------
        report "=== GROUP G6: STOP flag ===" severity note;
        set_cr('1', '0', '0', '0', '0', SAD, "0000000");
        launch(I2CT_OP_XFER, false, true, SAD, '0', 0);
        finish;
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G6: STOPF set on clean STOP", to_X01(rdw(I2CT_SR_STOPF)), '1');
        sb.check_bit("G6: BUSY cleared after STOP", to_X01(rdw(I2CT_SR_BUSY)), '0');
        sb.check_bit("G6: SDA released high after STOP", to_X01(sda_bus_x01), '1');
        sb.check_bit("G6: SCL released high after STOP", to_X01(scl_bus_x01), '1');
        w1c(x"000007DC");

        ------------------------------------------------------------------
        -- GROUP G7: watchdog error
        ------------------------------------------------------------------
        report "=== GROUP G7: watchdog error ===" severity note;
        set_cr('1', '0', '0', '0', '0', SAD, "0000000");
        bus_write(clk, pbus, I2CT_SLOT_WDG, x"00000001");   -- WDTO=1 => 256-clk SCL-low timeout
        launch(I2CT_OP_WDOG, false, true, SAD, '0', 0, hold => 600);
        finish;
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G7: ERRF set on SCL-low watchdog timeout", to_X01(rdw(I2CT_SR_ERRF)), '1');
        sb.check_bit("G7: BUSY dropped on watchdog abort", to_X01(rdw(I2CT_SR_BUSY)), '0');
        w1c(x"000007DC");

        bus_write(clk, pbus, I2CT_SLOT_WDG, x"00000000");   -- WDTO=0 disables the watchdog
        launch(I2CT_OP_WDOG, false, true, SAD, '0', 0, hold => 600);
        finish;
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G7: WDTO=0 -> no watchdog trip (ERRF stays 0)", to_X01(rdw(I2CT_SR_ERRF)), '0');
        w1c(x"000007DC");

        ------------------------------------------------------------------
        -- GROUP G8: IRQ demux / W1C
        -- irq_ae = (AMF|GCF|OVF|NACKF|STOPF|RSTARTF|ERRF)&AEIE ; irq_data = (RXF|TXE)&DATAIE (D16)
        ------------------------------------------------------------------
        report "=== GROUP G8: IRQ demux / W1C ===" severity note;
        set_cr('1', '0', '0', '1', '1', SAD, "0000000");   -- AEIE=1, DATAIE=1
        cfg_wdata(0) <= x"44";
        launch(I2CT_OP_XFER, false, true, SAD, '0', 1);
        finish;
        wait for 2 * PERIOD;
        sb.check_bit("G8: irq_ae asserts (AMF|STOPF & AEIE)", to_X01(irq_ae), '1');
        sb.check_bit("G8: irq_data asserts (RXF & DATAIE)", to_X01(irq_data), '1');
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_RX, rdw);
        w1c(x"00000010");   -- W1C RXF (the DATA source)
        wait for 2 * PERIOD;
        sb.check_bit("G8: irq_data drops after W1C RXF", to_X01(irq_data), '0');
        sb.check_bit("G8: irq_ae still high (AE sources remain)", to_X01(irq_ae), '1');
        w1c(x"000007CC");   -- W1C all AE sources
        wait for 2 * PERIOD;
        sb.check_bit("G8: irq_ae drops once all AE sources cleared", to_X01(irq_ae), '0');

        set_cr('1', '0', '0', '1', '1', SAD, "0000000");   -- new event, then mask
        cfg_wdata(0) <= x"55";
        launch(I2CT_OP_XFER, false, true, SAD, '0', 1);
        finish;
        wait for 2 * PERIOD;
        sb.check_bit("G8: irq_ae high before masking", to_X01(irq_ae), '1');
        set_cr('1', '0', '0', '0', '0', SAD, "0000000");   -- AEIE=0, DATAIE=0
        wait for 2 * PERIOD;
        sb.check_bit("G8: irq_ae masked by AEIE=0 (flags still pending)", to_X01(irq_ae), '0');
        sb.check_bit("G8: irq_data masked by DATAIE=0", to_X01(irq_data), '0');
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_SR, rdw);
        sb.check_bit("G8: AMF still pending under the mask", to_X01(rdw(I2CT_SR_AMF)), '1');
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_RX, rdw);
        w1c(x"000007DC");

        ------------------------------------------------------------------
        -- GROUP G-NEG: NEGATIVE CONTROL (mandatory, LAST) -- exactly ONE
        -- deliberately-wrong expected value: expect a wrong RX byte after a
        -- clean, known host write (doc's own suggested example).
        ------------------------------------------------------------------
        report "=== GROUP G-NEG: NEGATIVE CONTROL ===" severity note;
        set_cr('1', '0', '0', '0', '0', SAD, "0000000");
        cfg_wdata(0) <= x"A5";
        launch(I2CT_OP_XFER, false, true, SAD, '0', 1);
        finish;
        bus_read(clk, pbus, rdata_out, I2CT_SLOT_RX, rdw);
        sb.check_slv("NEGATIVE CONTROL: wrong expected RX byte (must FAIL)", rdw(7 downto 0), x"00");
        w1c(x"000007DC");

        ------------------------------------------------------------------
        -- Final verdict: sb.errors must be EXACTLY 1 (the negative control).
        ------------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("I2CTARGET TB");

        if sb.errors = 1 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   I2CTARGET_TB PASS (1 expected negative-control failure)" & LF &
                "    ##   I2CTARGET TB:  ALL CHECKS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   I2CTARGET_TB FAIL (expected exactly 1 failure [negative control], got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        tb_done <= true;
        stop;
        wait;
    end process stim_proc;

end architecture sim;
