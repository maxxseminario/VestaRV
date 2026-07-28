-------------------------------------------------------------------------------
-- ptx30w_model_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for tb/ptx30w_model.vhd, the behavioural
-- model of the Renesas PTX30W NFC wireless-charging listener (datasheet
-- R35DS0090EU0102 Rev.1.02). Read the model's header first: it lists what is
-- and is not modelled and flags every protocol assumption.
--
-- The bench plays the Castalia side: it is the I2C MASTER (Castalia's I2C0,
-- chip pins 37/38) talking to the PTX30W target at its default address 0x4B,
-- and it watches the dedicated IRQ pin the way a Castalia GPIO would. It also
-- plays the two roles that are NOT on the wire: the analog environment (RF
-- field, harvested power, loads, NTC) and the NFC poller on the far side of the
-- Transparent Data Channel.
--
-- CHECKER INDEPENDENCE. The I2C master here is bit-banged from the bench's own
-- SCL_HALF constant; nothing in its timing is derived from the model. The HIP
-- frames are built and parsed byte by byte against the datasheet's own field
-- layout (4.8.3.1), and the CRC_B used to check the model's CRC is computed by
-- this bench's OWN independent implementation (crc_b_tb below) -- it is not the
-- model's function.
--
-- BUS RESOLUTION. SCL and SDA are single resolved nets with a weak 'H' pull-up.
-- Both the master (m_*_oe) and the model (its sda_oe/scl_oe) are open drain and
-- only ever pull low; '0' wins, otherwise the 'H' pull-up does. Every sample is
-- normalised through to_X01 so a released 'H' reads as '1'.
--
-- GROUPS
--   G-STBY   4.8.4 standby: the first addressed transfer with no RF field is
--            address-NACKed and arms the 100 ms wake window; the retry is ACKed.
--   G-ADDR   wrong 7-bit address is NACKed; the right one is ACKed.
--   G-RSS    HIP Read System Status round trip with full framing checks
--            (LEN, FCB opcode echo, the Table 18 status block, N-padding,
--            N=0 rejected with no response).
--   G-CRC    the optional FCB.CRC field, both directions, plus a deliberately
--            corrupted command CRC -> no response and NAK 0x03 recorded.
--   G-IRQ    WMSG(NSC_GET_PARAM) raises IRQ; RML reports the length; RMSG reads
--            it back and drops IRQ; a short RMSG leaves the message pending.
--   G-NSC    the Table 17 RD parameter block agrees with the model's own
--            reported state, and the ADC codes decode back to the rails.
--   G-TDCP   poller -> host: a 70-byte poller message chunks 63 + 7 through the
--            64-byte TDC_BUF_POL with the buffer-free handshake (Figure 10).
--   G-TDCL   host -> poller: 70 bytes as two NSC_DATA_MSGs, with the
--            buffer-full NAK 0x05 and the NSC_DATA_ACK flow control (4.8.2.5.2).
--   G-PWR    rising RF power walks the charger TCM -> CCM -> CVM -> completed
--            and raises vdmcu_good; the 50 mA IVDMCU limit and the VDDC
--            brownout are exercised.
--   G-RST    HIP System Reset with RAK returns an ACK frame and clears state.
--   G-NEG    the mandatory negative control (exactly one deliberate failure).
--
-- Expected verdict line: "PTX30W_TB PASS (1 expected negative-control failure)".
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.ptx30w_pkg.all;

entity ptx30w_model_tb is
    generic (
        NEGCTRL : boolean := true   -- mandatory negative control (see G-NEG)
    );
end entity ptx30w_model_tb;

architecture sim of ptx30w_model_tb is

    ---------------------------------------------------------------------------
    -- Bench-owned timing (never derived from the model)
    ---------------------------------------------------------------------------
    constant SCL_HALF : time := 500 ns;                       -- 1 MHz, the 3.4 fCLK_I2C max
    constant PWR_TICK : time := 20 us;                        -- must match the DUT generic
    constant DEV_ADDR : std_logic_vector(6 downto 0) := "1001011";  -- 0x4B

    ---------------------------------------------------------------------------
    -- Resolved open-drain bus
    ---------------------------------------------------------------------------
    signal sda, scl : std_logic;
    signal m_sda_oe : std_logic := '0';
    signal m_scl_oe : std_logic := '0';
    signal d_sda_oe, d_scl_oe, d_sda_out, d_scl_out : std_logic;

    ---------------------------------------------------------------------------
    -- Device pins
    ---------------------------------------------------------------------------
    signal irq     : std_logic;
    signal gpo0_oe : std_logic;
    signal gpo1_oe : std_logic;
    signal sm_n    : std_logic := '1';

    ---------------------------------------------------------------------------
    -- Bench-driven environment (BENCH ABSTRACTION, see the model header)
    ---------------------------------------------------------------------------
    signal rf_field     : boolean := false;
    signal rf_mw        : natural := 0;
    signal vddc_load    : natural := 0;
    signal vdmcu_load   : natural := 0;
    signal vdmcu_ext    : natural := 0;
    -- 690 mV = the datasheet's own example thermistor (10 kohm, beta 3435,
    -- 4.4.2) at 25 C against the 69 uA INTC source: comfortably inside the
    -- normal band, between VNTC_HOT_SET (377 mV) and VNTC_COLD_SET (1175 mV).
    signal ntc_v        : natural := 690;
    signal tj           : natural := 25;
    signal bat_conn     : boolean := true;
    signal poller_ctl   : std_logic := '0';

    ---------------------------------------------------------------------------
    -- Reported state
    ---------------------------------------------------------------------------
    signal vdmcu_good : std_logic;
    signal vdmcu_mv   : natural;
    signal vddc_mv    : natural;
    signal vbat_mv    : natural;
    signal ibat_ua    : natural;
    signal chg_state  : natural;
    signal ntc_state  : natural;
    signal err_state  : natural;
    signal bod_reset  : std_logic;
    signal shipping   : std_logic;

    ---------------------------------------------------------------------------
    -- TDC poller-side stimulus / observation
    ---------------------------------------------------------------------------
    signal pol_go    : std_logic := '0';
    signal pol_len   : natural := 0;
    signal pol_data  : ptx_msg_t := (others => (others => '0'));
    signal lis_rd_go : std_logic := '0';
    signal lis_valid : std_logic;
    signal lis_len   : natural;
    signal lis_data  : ptx_buf64_t;
    signal lis_msgs  : natural;

    signal obs_frames    : natural;
    signal obs_last_nak  : std_logic_vector(7 downto 0);
    signal obs_addr_nack : natural;
    signal obs_msg_out   : natural;

    shared variable sb : scoreboard;

    ---------------------------------------------------------------------------
    -- Independent CRC_B (ISO/IEC 14443-3 Type B), written from the standard,
    -- NOT shared with the model's ptx_crc_b.
    ---------------------------------------------------------------------------
    function crc_b_tb(d : ptx_byte_array; n : natural) return std_logic_vector is
        variable r : unsigned(15 downto 0) := x"FFFF";
        variable b : unsigned(15 downto 0);
    begin
        for i in 0 to n - 1 loop
            b := x"00" & unsigned(d(i));
            r := r xor b;
            for k in 1 to 8 loop
                if r(0) = '1' then
                    r := shift_right(r, 1) xor x"8408";
                else
                    r := shift_right(r, 1);
                end if;
            end loop;
        end loop;
        return std_logic_vector(not r);
    end function;

    function u8(n : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(n mod 256, 8));
    end function;

    function to_nat(v : std_logic_vector) return natural is
    begin
        return to_integer(unsigned(v));
    end function;

begin

    ---------------------------------------------------------------------------
    -- Wired-AND bus with a weak pull-up (the board's I2C pull-ups).
    ---------------------------------------------------------------------------
    sda <= '0' when (m_sda_oe = '1' or d_sda_oe = '1') else 'H';
    scl <= '0' when (m_scl_oe = '1' or d_scl_oe = '1') else 'H';

    ---------------------------------------------------------------------------
    -- DUT. The battery capacity and power tick are scaled DOWN from the
    -- physical defaults so a full trickle -> CC -> CV -> done charge fits in a
    -- simulation (the model header flags this as ASSUMPTION A10).
    ---------------------------------------------------------------------------
    dut : entity work.ptx30w_model
        generic map (
            G_I2C_ADDR      => DEV_ADDR,
            G_STANDBY_EN    => true,
            G_WAKE_HOLD     => 100 ms,
            G_PWR_TICK      => PWR_TICK,
            G_BAT_CAP_MAH   => 0.0005,
            G_VBAT_INIT_MV  => 2800,
            G_CV_DECAY      => 0.97,
            G_VDMCU_MODE    => "10"        -- 3.3 V MCU LDO output
        )
        port map (
            scl     => scl,
            sda_in  => sda,
            sda_out => d_sda_out,
            sda_oe  => d_sda_oe,
            scl_out => d_scl_out,
            scl_oe  => d_scl_oe,
            irq     => irq,
            gpo0_oe => gpo0_oe,
            gpo1_oe => gpo1_oe,
            sm_n    => sm_n,

            rf_field_present => rf_field,
            rf_available_mw  => rf_mw,
            vddc_load_ma     => vddc_load,
            vdmcu_load_ma    => vdmcu_load,
            vdmcu_ext_mv     => vdmcu_ext,
            ntc_mv           => ntc_v,
            tj_degc          => tj,
            bat_connected    => bat_conn,
            gpo_poller_ctl   => poller_ctl,

            vdmcu_good   => vdmcu_good,
            vdmcu_mv     => vdmcu_mv,
            vddc_mv      => vddc_mv,
            vbat_mv      => vbat_mv,
            ibat_ua      => ibat_ua,
            charge_state => chg_state,
            ntc_state    => ntc_state,
            error_state  => err_state,
            bod_reset    => bod_reset,
            shipping     => shipping,

            tdc_pol_go    => pol_go,
            tdc_pol_len   => pol_len,
            tdc_pol_data  => pol_data,
            tdc_lis_rd_go => lis_rd_go,
            obs_lis_valid => lis_valid,
            obs_lis_len   => lis_len,
            obs_lis_data  => lis_data,
            obs_lis_msgs  => lis_msgs,

            obs_frames    => obs_frames,
            obs_last_nak  => obs_last_nak,
            obs_addr_nack => obs_addr_nack,
            obs_msg_out   => obs_msg_out
        );


    ---------------------------------------------------------------------------
    stim : process

        ----------------------------------------------------------------
        -- I2C master primitives. All open drain: pull low or release.
        ----------------------------------------------------------------
        procedure sda_low is begin m_sda_oe <= '1'; end procedure;
        procedure sda_rel is begin m_sda_oe <= '0'; end procedure;
        procedure scl_low is begin m_scl_oe <= '1'; end procedure;
        procedure scl_rel is begin m_scl_oe <= '0'; end procedure;

        procedure i2c_start is
        begin
            sda_rel; scl_rel; wait for SCL_HALF;
            sda_low;          wait for SCL_HALF;
            scl_low;          wait for SCL_HALF;
        end procedure;

        procedure i2c_rstart is    -- bus left with SCL held low
        begin
            sda_rel;          wait for SCL_HALF;
            scl_rel;          wait for SCL_HALF;
            sda_low;          wait for SCL_HALF;
            scl_low;          wait for SCL_HALF;
        end procedure;

        procedure i2c_stop is
        begin
            sda_low;          wait for SCL_HALF;
            scl_rel;          wait for SCL_HALF;
            sda_rel;          wait for SCL_HALF;
        end procedure;

        -- Drive one bit the MASTER sources.
        procedure wr_bit(b : std_logic) is
        begin
            if b = '1' then sda_rel; else sda_low; end if;
            wait for SCL_HALF;
            scl_rel;
            wait for SCL_HALF;
            scl_low;
        end procedure;

        -- Sample one bit the TARGET sources.
        procedure rd_bit(b : out std_logic) is
        begin
            sda_rel;
            wait for SCL_HALF;
            scl_rel;
            wait for SCL_HALF / 2;
            b := to_X01(sda);
            wait for SCL_HALF / 2;
            scl_low;
        end procedure;

        procedure wr_byte(d : std_logic_vector(7 downto 0); ack : out std_logic) is
            variable a : std_logic;
        begin
            for i in 7 downto 0 loop wr_bit(d(i)); end loop;
            rd_bit(a);
            ack := not a;      -- bus low in the ACK slot = ACK
        end procedure;

        procedure rd_byte(d : out std_logic_vector(7 downto 0)) is
            variable v : std_logic_vector(7 downto 0);
            variable b : std_logic;
        begin
            for i in 7 downto 0 loop
                rd_bit(b);
                v(i) := b;
            end loop;
            d := v;
        end procedure;

        -- Master's ACK/NACK on a byte it has just read.
        procedure send_ack(a : std_logic) is
        begin
            wr_bit(not a);     -- a='1' -> drive low = ACK
        end procedure;

        -- Address phase only; leaves the bus with SCL low so the caller can
        -- carry on, repeated-START, or STOP.
        procedure addr_phase(a : std_logic_vector(6 downto 0);
                             rnw : std_logic; ack : out std_logic) is
        begin
            wr_byte(a & rnw, ack);
        end procedure;

        ----------------------------------------------------------------
        -- HIP layer (4.8.3.1). Frame on the wire = LEN(2, MSB first) |
        -- FCB | payload | optional CRC. No SOF byte over I2C: the I2C
        -- START is the SOF (see the worked examples of 4.8.4.1).
        ----------------------------------------------------------------
        -- Send a command frame. Leaves the bus held (SCL low) when
        -- with_stop is false so a repeated START can follow.
        procedure hip_cmd(op        : natural;
                          rak       : boolean;
                          use_crc   : boolean;
                          payload   : ptx_msg_t;
                          plen      : natural;
                          corrupt   : boolean;
                          with_stop : boolean;
                          addr_ack  : out std_logic) is
            variable frame : ptx_msg_t := (others => (others => '0'));
            variable flen  : natural;
            variable lenf  : natural;
            variable fcb   : std_logic_vector(7 downto 0);
            variable c     : std_logic_vector(15 downto 0);
            variable a     : std_logic;
        begin
            fcb := u8(op * 16);
            if rak     then fcb(2) := '1'; end if;
            if use_crc then fcb(1) := '1'; end if;

            lenf := 1 + plen;                       -- FCB + payload
            if use_crc then lenf := lenf + 2; end if;
            frame(0) := u8(lenf / 256);
            frame(1) := u8(lenf mod 256);
            frame(2) := fcb;
            for i in 0 to plen - 1 loop
                frame(3 + i) := payload(i);
            end loop;
            flen := 3 + plen;
            if use_crc then
                c := crc_b_tb(frame, flen);
                if corrupt then c := c xor x"0001"; end if;
                frame(flen)     := c(7 downto 0);   -- CRC_B, LSB byte first
                frame(flen + 1) := c(15 downto 8);
                flen := flen + 2;
            end if;

            i2c_start;
            addr_phase(DEV_ADDR, '0', a);
            addr_ack := a;
            if a = '1' then
                for i in 0 to flen - 1 loop
                    wr_byte(frame(i), a);
                end loop;
            end if;
            if with_stop then
                i2c_stop;
            end if;
        end procedure;

        -- Read a response frame: 2 LEN bytes then LEN more, ACKing every byte
        -- except the last (a master that ACKs its final read byte would leave
        -- the target driving and the STOP would never be seen). `sr` selects a
        -- repeated START (bus already held) vs a fresh START.
        procedure hip_resp(sr   : boolean;
                           resp : out ptx_msg_t;
                           rlen : out natural;
                           aack : out std_logic) is
            variable r : ptx_msg_t := (others => (others => '0'));
            variable a : std_logic;
            variable b : std_logic_vector(7 downto 0);
            variable n : natural;
        begin
            if sr then i2c_rstart; else i2c_start; end if;
            addr_phase(DEV_ADDR, '1', a);
            aack := a;
            if a = '0' then
                i2c_stop;
                resp := r;
                rlen := 0;
                return;
            end if;
            rd_byte(b); r(0) := b; send_ack('1');
            rd_byte(b); r(1) := b;
            n := to_nat(r(0)) * 256 + to_nat(r(1));
            if n = 0 then
                send_ack('0');
                i2c_stop;
                resp := r;
                rlen := 0;
                return;
            end if;
            send_ack('1');
            for i in 0 to n - 1 loop
                rd_byte(b);
                r(2 + i) := b;
                if i = n - 1 then send_ack('0'); else send_ack('1'); end if;
            end loop;
            i2c_stop;
            resp := r;
            rlen := n;
        end procedure;

        ----------------------------------------------------------------
        -- Convenience wrappers used by several groups
        ----------------------------------------------------------------
        variable pay  : ptx_msg_t := (others => (others => '0'));
        variable resp : ptx_msg_t := (others => (others => '0'));
        variable rlen : natural := 0;
        variable aack : std_logic;
        variable ack  : std_logic;
        variable c16  : std_logic_vector(15 downto 0);
        variable n    : natural := 0;
        variable neg_val : std_logic_vector(7 downto 0) := x"00";

        -- Send an NSC command inside a WMSG (4.8.2: input buffer address 0),
        -- with no RAK so no HIP response is produced.
        procedure nsc_send(msg : ptx_msg_t; mlen : natural; aok : out std_logic) is
            variable p : ptx_msg_t := (others => (others => '0'));
        begin
            p(0) := x"00";                     -- ADDR = input buffer 0
            for i in 0 to mlen - 1 loop
                p(1 + i) := msg(i);
            end loop;
            hip_cmd(PTX_OP_WMSG, false, false, p, mlen + 1, false, true, aok);
        end procedure;

        -- The 4.8.2 receive sequence: RML for the length, then RMSG for the
        -- message. Returns the NSC message payload (i.e. the RMSG response with
        -- LEN and FCB stripped).
        procedure nsc_recv(msg : out ptx_msg_t; mlen : out natural) is
            variable p  : ptx_msg_t := (others => (others => '0'));
            variable r  : ptx_msg_t := (others => (others => '0'));
            variable rl : natural;
            variable a  : std_logic;
            variable ml : natural;
            variable m  : ptx_msg_t := (others => (others => '0'));
        begin
            -- RML: no payload
            hip_cmd(PTX_OP_RML, false, false, p, 0, false, false, a);
            hip_resp(true, r, rl, a);
            ml := to_nat(r(3)) * 256 + to_nat(r(4));
            if ml = 0 then
                msg  := m;
                mlen := 0;
                return;
            end if;
            -- RMSG: N = the whole message
            p(0) := u8(ml / 256);
            p(1) := u8(ml mod 256);
            hip_cmd(PTX_OP_RMSG, false, false, p, 2, false, false, a);
            hip_resp(true, r, rl, a);
            for i in 0 to ml - 1 loop
                m(i) := r(3 + i);
            end loop;
            msg  := m;
            mlen := ml;
        end procedure;

    begin
        report "=== ptx30w_model_tb start ===" severity note;
        wait for 2 us;

        ------------------------------------------------------------------
        -- G-STBY: 4.8.4 standby. With no RF field the part is supplied from
        -- the battery and is in standby; the FIRST addressed transfer is
        -- address-NACKed but wakes it for at least 100 ms.
        ------------------------------------------------------------------
        report "=== G-STBY: standby address NACK + wake window ===" severity note;
        i2c_start;
        addr_phase(DEV_ADDR, '0', ack);
        i2c_stop;
        sb.check_bit("G-STBY: first address in standby is NACKed (4.8.4)", ack, '0');
        sb.check_true("G-STBY: the NACK was counted by the model",
                      obs_addr_nack = 1);

        wait for 20 us;
        i2c_start;
        addr_phase(DEV_ADDR, '0', ack);
        i2c_stop;
        sb.check_bit("G-STBY: retry inside the 100 ms wake window is ACKed", ack, '1');

        ------------------------------------------------------------------
        -- G-ADDR: 7-bit address match. From here on the RF field is present,
        -- so the part is always in normal mode (4.8.4 / section 4).
        ------------------------------------------------------------------
        report "=== G-ADDR: I2C address match / NACK ===" severity note;
        rf_field <= true;
        rf_mw    <= 0;
        wait for 4 * PWR_TICK;

        i2c_start;
        addr_phase("0101010", '0', ack);       -- 0x2A, not ours
        i2c_stop;
        sb.check_bit("G-ADDR: wrong 7-bit address is NACKed", ack, '0');

        i2c_start;
        addr_phase(DEV_ADDR, '0', ack);
        i2c_stop;
        sb.check_bit("G-ADDR: address 0x4B (I2C_ADDR default) is ACKed", ack, '1');

        i2c_start;
        addr_phase(DEV_ADDR, '1', ack);        -- read direction
        i2c_stop;
        sb.check_bit("G-ADDR: address 0x4B with RnW=1 is ACKed", ack, '1');

        ------------------------------------------------------------------
        -- G-RSS: Read System Status (4.8.3.6.2, Table 18) -- the reference
        -- HIP round trip of Figure 33: S,AW,00,02,20,14,Sr,AR,00,15,20,...
        ------------------------------------------------------------------
        report "=== G-RSS: HIP Read System Status round trip ===" severity note;
        pay(0) := x"14";                        -- N = 20 bytes, exactly Figure 33
        hip_cmd(PTX_OP_RSS, false, false, pay, 1, false, false, aack);
        sb.check_bit("G-RSS: command address phase ACKed", aack, '1');
        hip_resp(true, resp, rlen, aack);

        sb.check_true("G-RSS: response LEN = 1 (FCB) + N = 21", rlen = 21);
        sb.check_slv("G-RSS: response FCB echoes OPCODE 0x2, RAK=0, CRC=0",
                     resp(2), x"20");
        sb.check_slv("G-RSS: status[0] = ACK/NAK of the previous command = 0x00",
                     resp(3), PTX_NAK_NONE);
        sb.check_slv("G-RSS: status[1] = HW_VERSION", resp(4), x"30");
        sb.check_slv("G-RSS: status[2:3] = FW_VERSION MSB first (hi)",
                     resp(5), x"14");
        sb.check_slv("G-RSS: status[2:3] = FW_VERSION MSB first (lo)",
                     resp(6), x"8B");
        sb.check_slv("G-RSS: status[4] = DIE_INFO[0]", resp(7), x"D0");
        sb.check_slv("G-RSS: status[19] = DIE_INFO[15]", resp(22), x"DF");
        neg_val := resp(4);                     -- stashed for the negative control

        -- N = 21 returns the whole Table 18 block including OEM_VALID_FLAG.
        pay(0) := x"15";
        hip_cmd(PTX_OP_RSS, false, false, pay, 1, false, false, aack);
        hip_resp(true, resp, rlen, aack);
        sb.check_true("G-RSS: N=21 gives LEN=22", rlen = 22);
        sb.check_slv("G-RSS: status[20] = OEM_VALID_FLAG = 1", resp(23), x"01");

        -- N larger than the status block is 0x00-padded at the back (4.8.3.6.2).
        pay(0) := x"18";                        -- N = 24
        hip_cmd(PTX_OP_RSS, false, false, pay, 1, false, false, aack);
        hip_resp(true, resp, rlen, aack);
        sb.check_true("G-RSS: N=24 gives LEN=25", rlen = 25);
        sb.check_slv("G-RSS: padding byte 21 is 0x00", resp(24), x"00");
        sb.check_slv("G-RSS: padding byte 23 is 0x00", resp(26), x"00");

        -- N = 0 is an invalid parameter: NO response, NAK 0x04 stored.
        pay(0) := x"00";
        hip_cmd(PTX_OP_RSS, false, false, pay, 1, false, true, aack);
        wait for 5 us;
        sb.check_slv("G-RSS: N=0 stores NAK 0x04 (invalid parameter)",
                     obs_last_nak, PTX_NAK_PARAM);
        pay(0) := x"01";
        hip_cmd(PTX_OP_RSS, false, false, pay, 1, false, false, aack);
        hip_resp(true, resp, rlen, aack);
        sb.check_slv("G-RSS: the stored NAK is readable as status[0]",
                     resp(3), PTX_NAK_PARAM);

        -- An unknown opcode is NAK 0x01 (Table 22) with no response.
        hip_cmd(16#5#, false, false, pay, 0, false, true, aack);
        wait for 5 us;
        sb.check_slv("G-RSS: unknown OPCODE stores NAK 0x01 (invalid command)",
                     obs_last_nak, PTX_NAK_CMD);

        -- A LEN that does not match the bytes actually sent is NAK 0x02. Built
        -- by hand: LEN says 4 but only FCB is sent.
        i2c_start;
        addr_phase(DEV_ADDR, '0', ack);
        wr_byte(x"00", ack);
        wr_byte(x"04", ack);                    -- LEN = 4
        wr_byte(x"20", ack);                    -- FCB only
        i2c_stop;
        wait for 5 us;
        sb.check_slv("G-RSS: short frame stores NAK 0x02 (invalid length)",
                     obs_last_nak, PTX_NAK_LEN);

        ------------------------------------------------------------------
        -- G-CRC: the optional FCB.CRC field (4.8.3.1), CRC_B over LEN+FCB+
        -- payload, checked against this bench's own implementation.
        ------------------------------------------------------------------
        report "=== G-CRC: FCB.CRC frames ===" severity note;
        pay(0) := x"04";                        -- N = 4
        hip_cmd(PTX_OP_RSS, false, true, pay, 1, false, false, aack);
        hip_resp(true, resp, rlen, aack);
        sb.check_true("G-CRC: response LEN = 1 FCB + 4 payload + 2 CRC = 7",
                      rlen = 7);
        sb.check_slv("G-CRC: response FCB has the CRC bit set", resp(2), x"22");
        c16 := crc_b_tb(resp, rlen);            -- LEN + FCB + payload = rlen bytes
        sb.check_slv("G-CRC: response CRC_B low byte matches an independent CRC",
                     resp(rlen), c16(7 downto 0));
        sb.check_slv("G-CRC: response CRC_B high byte matches",
                     resp(rlen + 1), c16(15 downto 8));

        -- Corrupted command CRC: no response, NAK 0x03 recorded (Table 22).
        pay(0) := x"04";
        hip_cmd(PTX_OP_RSS, false, true, pay, 1, true, true, aack);
        wait for 5 us;
        sb.check_slv("G-CRC: corrupted command CRC stores NAK 0x03",
                     obs_last_nak, PTX_NAK_CRC);

        ------------------------------------------------------------------
        -- G-IRQ: the 4.8.2 receive sequence. A WMSG carrying an NSC command
        -- produces a response in the output buffer, IRQ rises, RML gives the
        -- length, RMSG reads it and IRQ falls.
        ------------------------------------------------------------------
        report "=== G-IRQ: IRQ assert / RML / RMSG / IRQ clear ===" severity note;
        sb.check_bit("G-IRQ: IRQ idle low before any message", irq, '0');

        pay(0) := PTX_NSC_GET_PARAM;
        nsc_send(pay, 1, ack);
        sb.check_bit("G-IRQ: WMSG address phase ACKed", ack, '1');
        wait for 5 us;
        sb.check_bit("G-IRQ: IRQ asserted once a message is pending", irq, '1');
        sb.check_slv("G-IRQ: WMSG with RAK=0 produced no NAK",
                     obs_last_nak, PTX_NAK_NONE);

        -- RML (4.8.3.6.4): response is FCB + ML(2, MSB first) => LEN 3.
        hip_cmd(PTX_OP_RML, false, false, pay, 0, false, false, aack);
        hip_resp(true, resp, rlen, aack);
        sb.check_true("G-IRQ: RML response LEN = 3", rlen = 3);
        sb.check_slv("G-IRQ: RML response FCB echoes OPCODE 0x9", resp(2), x"90");
        n := to_nat(resp(3)) * 256 + to_nat(resp(4));
        sb.check_true("G-IRQ: RML reports ML = 10 for NSC_GET_PARAM_RSP "
                      & "(Figure 36 shows RML=0x0A)", n = 10);
        sb.check_bit("G-IRQ: IRQ still asserted after RML", irq, '1');

        -- A SHORT RMSG (N < ML) must leave the message pending (ASSUMPTION A3).
        pay(0) := x"00"; pay(1) := x"04";
        hip_cmd(PTX_OP_RMSG, false, false, pay, 2, false, false, aack);
        hip_resp(true, resp, rlen, aack);
        sb.check_true("G-IRQ: short RMSG N=4 gives LEN=5", rlen = 5);
        sb.check_bit("G-IRQ: IRQ stays asserted after a short RMSG", irq, '1');

        -- Full RMSG retires the message and drops IRQ.
        pay(0) := x"00"; pay(1) := x"0A";
        hip_cmd(PTX_OP_RMSG, false, false, pay, 2, false, false, aack);
        hip_resp(true, resp, rlen, aack);
        sb.check_true("G-IRQ: full RMSG N=10 gives LEN=11", rlen = 11);
        sb.check_slv("G-IRQ: RMSG response FCB echoes OPCODE 0x8", resp(2), x"80");
        wait for 5 us;
        sb.check_bit("G-IRQ: IRQ clears once the message is read", irq, '0');
        sb.check_true("G-IRQ: model counted one delivered message",
                      obs_msg_out = 1);

        -- With nothing pending RML must report 0 (4.8.3.6.4).
        hip_cmd(PTX_OP_RML, false, false, pay, 0, false, false, aack);
        hip_resp(true, resp, rlen, aack);
        n := to_nat(resp(3)) * 256 + to_nat(resp(4));
        sb.check_true("G-IRQ: RML reports ML = 0 with nothing pending", n = 0);

        ------------------------------------------------------------------
        -- G-NSC: NSC_GET_PARAM_RSP contents (Table 17) vs the model's own
        -- reported state, and the 4.8.1 ADC decode.
        ------------------------------------------------------------------
        report "=== G-NSC: NSC_GET_PARAM RD parameter block ===" severity note;
        pay(0) := PTX_NSC_GET_PARAM;
        nsc_send(pay, 1, ack);
        wait for 5 us;
        nsc_recv(resp, rlen);
        sb.check_true("G-NSC: NSC_GET_PARAM_RSP is 10 bytes", rlen = 10);
        sb.check_slv("G-NSC: byte 0 = opcode 0x03", resp(0), PTX_NSC_GET_PARAM);
        sb.check_slv("G-NSC: byte 1 = EC 0x00 (no error)", resp(1), PTX_EC_NONE);
        sb.check_slv("G-NSC: RD#1 BC_ENABLE = 1 (OEM default)", resp(2), x"01");
        sb.check_slv("G-NSC: RD#2 RFF_STATUS = 1 (field on)", resp(3), x"01");
        sb.check_true("G-NSC: RD#4 BC_STATUS agrees with charge_state",
                      to_nat(resp(5)) = chg_state);
        sb.check_true("G-NSC: RD#5 VDBAT_ADC_VAL decodes to vbat_mv within 1 LSB "
                      & "(V = 12.5 mV * code + 2.4 V, 4.8.1)",
                      abs(((to_nat(resp(6)) * 125) / 10 + 2400) - vbat_mv) <= 13);
        sb.check_true("G-NSC: RD#6 VDDC_ADC_VAL decodes to vddc_mv within 1 LSB",
                      abs(((to_nat(resp(7)) * 125) / 10 + 2400) - vddc_mv) <= 13);
        sb.check_slv("G-NSC: RD#7 NTC_STATUS = 0x00 (normal range)",
                     resp(8), x"00");
        sb.check_true("G-NSC: RD#8 WLCP_CONNECTED is non-zero with a field present",
                      to_nat(resp(9)) /= 0);

        -- NSC_SET_PARAM (4.8.2.2): two parameters then EoC. Response {0x02, EC}.
        pay(0) := PTX_NSC_SET_PARAM;
        pay(1) := u8(PTX_ID_ICHG);  pay(2) := x"32";   -- ICHG code 0x32 ~ 100 mA
        pay(3) := u8(PTX_ID_VTERM); pay(4) := x"11";   -- VTERM code 0x11 = 4.18 V
        pay(5) := x"00";                               -- EoC
        nsc_send(pay, 6, ack);
        wait for 5 us;
        nsc_recv(resp, rlen);
        sb.check_true("G-NSC: NSC_SET_PARAM_RSP is 2 bytes", rlen = 2);
        sb.check_slv("G-NSC: SET_PARAM response opcode 0x02", resp(0), PTX_NSC_SET_PARAM);
        sb.check_slv("G-NSC: SET_PARAM EC = 0x00", resp(1), PTX_EC_NONE);

        -- An unknown WR parameter ID is EC 0x02 (Table 20).
        pay(0) := PTX_NSC_SET_PARAM;
        pay(1) := x"7E"; pay(2) := x"00";
        pay(3) := x"00";
        nsc_send(pay, 4, ack);
        wait for 5 us;
        nsc_recv(resp, rlen);
        sb.check_slv("G-NSC: unknown WR parameter ID gives EC 0x02",
                     resp(1), PTX_EC_PARAM);

        ------------------------------------------------------------------
        -- G-TDCP: poller -> host. 70 bytes into TDC_BUF_POL. Because the
        -- buffer is 64 bytes (H1 + 63 data) it must chunk 63 + 7, and the
        -- second chunk may only appear after the host has read the first
        -- (4.6.2.1 steps 17/18/22/23, Figure 10).
        ------------------------------------------------------------------
        report "=== G-TDCP: TDC poller -> host, 70 bytes, chunked ===" severity note;
        for i in 0 to 69 loop
            pol_data(i) <= u8(16#40# + i);
        end loop;
        pol_len <= 70;
        wait for 1 us;
        pol_go <= '1';
        wait for 1 us;
        pol_go <= '0';
        wait for 5 us;

        sb.check_bit("G-TDCP: IRQ asserted for the first poller chunk", irq, '1');
        nsc_recv(resp, rlen);
        sb.check_true("G-TDCP: chunk 1 is 1 header + 63 data bytes", rlen = 64);
        sb.check_slv("G-TDCP: chunk 1 header is NSC_DATA_MSG with length 63",
                     resp(0), x"BF");           -- "10" & 111111b
        sb.check_slv("G-TDCP: chunk 1 data[0]", resp(1), x"40");
        sb.check_slv("G-TDCP: chunk 1 data[62]", resp(63), x"7E");

        wait for 5 us;
        sb.check_bit("G-TDCP: IRQ re-asserts for the second chunk once the "
                     & "buffer is free (4.6.2.1 step 18)", irq, '1');
        nsc_recv(resp, rlen);
        sb.check_true("G-TDCP: chunk 2 is 1 header + 7 data bytes", rlen = 8);
        sb.check_slv("G-TDCP: chunk 2 header is NSC_DATA_MSG with length 7",
                     resp(0), x"87");
        sb.check_slv("G-TDCP: chunk 2 data[0] continues the stream", resp(1), x"7F");
        sb.check_slv("G-TDCP: chunk 2 data[6] is the last byte", resp(7), x"85");
        wait for 5 us;
        sb.check_bit("G-TDCP: IRQ clears when the whole message is delivered",
                     irq, '0');

        ------------------------------------------------------------------
        -- G-TDCL: host -> poller. Same 70 bytes the other way: two
        -- NSC_DATA_MSGs of 63 + 7, with TDC_BUF_LIS[0][7] as the full flag,
        -- the HIP "write buffer full" NAK 0x05, and the NSC_DATA_ACK flow
        -- control of 4.8.2.5.2 / 4.6.2.3.
        ------------------------------------------------------------------
        report "=== G-TDCL: TDC host -> poller, chunking + flow control ===" severity note;
        pay(0) := x"BF";                        -- NSC_DATA_MSG, length 63
        for i in 0 to 62 loop
            pay(1 + i) := u8(16#A0# + i);
        end loop;
        nsc_send(pay, 64, ack);
        wait for 5 us;
        sb.check_bit("G-TDCL: TDC_BUF_LIS[0][7] set after the host write",
                     lis_valid, '1');
        sb.check_true("G-TDCL: TDC_BUF_LIS holds 63 payload bytes", lis_len = 63);
        sb.check_slv("G-TDCL: TDC_BUF_LIS[0] is H1 = 0x80 | 63", lis_data(0), x"BF");
        sb.check_slv("G-TDCL: TDC_BUF_LIS[1] = first payload byte",
                     lis_data(1), x"A0");
        sb.check_slv("G-TDCL: TDC_BUF_LIS[63] = last payload byte",
                     lis_data(63), x"DE");
        sb.check_bit("G-TDCL: no NSC_DATA_ACK yet (poller has not read)", irq, '0');

        -- A second data message before the poller has read is "write buffer
        -- full", NAK 0x05 (4.8.3.6.3).
        pay(0) := x"87";
        for i in 0 to 6 loop
            pay(1 + i) := u8(16#E0# + i);
        end loop;
        nsc_send(pay, 8, ack);
        wait for 5 us;
        sb.check_slv("G-TDCL: second data WMSG into a full buffer -> NAK 0x05",
                     obs_last_nak, PTX_NAK_FULL);
        sb.check_true("G-TDCL: the rejected message did not overwrite the buffer",
                      lis_len = 63);

        -- The poller reads TDC_BUF_LIS: bit 7 clears and the listener sends the
        -- host an NSC_DATA_ACK (4.6.2.3 steps 5 and 6).
        lis_rd_go <= '1';
        wait for 1 us;
        lis_rd_go <= '0';
        wait for 5 us;
        sb.check_bit("G-TDCL: TDC_BUF_LIS[0][7] cleared after the poller read",
                     lis_valid, '0');
        sb.check_bit("G-TDCL: NSC_DATA_ACK pending -> IRQ", irq, '1');
        nsc_recv(resp, rlen);
        sb.check_true("G-TDCL: NSC_DATA_ACK is a single byte", rlen = 1);
        sb.check_slv("G-TDCL: NSC_DATA_ACK = opcode 10b with length 0 (Figure 24)",
                     resp(0), x"80");

        -- Now the second chunk is accepted.
        pay(0) := x"87";
        for i in 0 to 6 loop
            pay(1 + i) := u8(16#E0# + i);
        end loop;
        nsc_send(pay, 8, ack);
        wait for 5 us;
        sb.check_slv("G-TDCL: second chunk accepted after the ACK (no NAK)",
                     obs_last_nak, PTX_NAK_NONE);
        sb.check_true("G-TDCL: TDC_BUF_LIS now holds the 7-byte tail",
                      lis_len = 7);
        sb.check_slv("G-TDCL: tail byte 0", lis_data(1), x"E0");
        sb.check_slv("G-TDCL: tail byte 6", lis_data(7), x"E6");
        lis_rd_go <= '1';
        wait for 1 us;
        lis_rd_go <= '0';
        wait for 5 us;
        sb.check_true("G-TDCL: two listener->poller messages completed",
                      lis_msgs = 2);
        nsc_recv(resp, rlen);
        sb.check_slv("G-TDCL: second NSC_DATA_ACK", resp(0), x"80");

        ------------------------------------------------------------------
        -- G-PWR: rails and charger. Thresholds are the model's decode of the
        -- 4.8.1 tables: ICHG code 0x32 -> 1.96*50+1.92 = 99.92 mA,
        -- ITRICKLE = 10% = 9.99 mA, VTRICKLE (BC_VTRK_CTRL 0b000) = 3.00 V,
        -- VTERM (BC_VTERM_CTRL 0x11) = 4.18 V, ITERM (BC_ITERM_CTRL 0x0E)
        -- = 19.12 mA. BC_ICHG_CTRL/BC_VTERM_CTRL were set in G-NSC.
        ------------------------------------------------------------------
        report "=== G-PWR: LDO + charger phase walk ===" severity note;

        -- 1. Power-limited trickle: 30 mW at a ~3.6 V VDDC is ~8.3 mA, less
        --    than the 10 mA trickle target, so the charge current is capped by
        --    the harvest (4.5.1 "the battery is charged with residual current").
        rf_mw <= 30;
        wait for 20 * PWR_TICK;
        sb.check_true("G-PWR: BC_STATUS = 1 (Trickle Charge Mode) below VTRICKLE",
                      chg_state = PTX_BC_TCM);
        sb.check_true("G-PWR: trickle charge current is HARVEST limited (< 10 mA)",
                      ibat_ua > 5000 and ibat_ua < 9990);
        sb.check_bit("G-PWR: vdmcu_good high, 3.3 V LDO out of dropout",
                     vdmcu_good, '1');
        sb.check_true("G-PWR: VDMCU sits at its 3.3 V target", vdmcu_mv = 3300);

        -- 2. Plenty of power: the charger now runs at its programmed trickle
        --    current, 10% of ICHG (4.4).
        rf_mw <= 800;
        wait for 20 * PWR_TICK;
        sb.check_true("G-PWR: with 800 mW the trickle current is the programmed "
                      & "10% of ICHG (~9.99 mA)",
                      ibat_ua > 9000 and ibat_ua < 11000);

        -- 3. Trickle -> constant current at VTRICKLE = 3.00 V.
        wait until chg_state = PTX_BC_CCM for 60 ms;
        sb.check_true("G-PWR: charger reached Constant Current Mode (BC_STATUS=2)",
                      chg_state = PTX_BC_CCM);
        sb.check_true("G-PWR: VDBAT crossed VTRICKLE = 3.00 V", vbat_mv >= 3000);
        wait for 4 * PWR_TICK;
        sb.check_true("G-PWR: CC current is the programmed ICHG (~99.9 mA)",
                      ibat_ua > 95000 and ibat_ua < 105000);

        -- 4. Constant current -> constant voltage at VTERM = 4.18 V.
        wait until chg_state = PTX_BC_CVM for 60 ms;
        sb.check_true("G-PWR: charger reached Constant Voltage Mode (BC_STATUS=3)",
                      chg_state = PTX_BC_CVM);
        sb.check_true("G-PWR: VDBAT is held at VTERM = 4.18 V",
                      vbat_mv >= 4150 and vbat_mv <= 4200);

        -- 5. Constant voltage -> charging completed when I falls below ITERM.
        wait until chg_state = PTX_BC_DONE for 20 ms;
        sb.check_true("G-PWR: charging completed (BC_STATUS=4)",
                      chg_state = PTX_BC_DONE);
        sb.check_true("G-PWR: no charge current once terminated", ibat_ua = 0);

        -- The host can see all of that over NSC_GET_PARAM.
        pay(0) := PTX_NSC_GET_PARAM;
        nsc_send(pay, 1, ack);
        wait for 5 us;
        nsc_recv(resp, rlen);
        sb.check_slv("G-PWR: NSC_GET_PARAM reports BC_STATUS = 4",
                     resp(5), x"04");

        ------------------------------------------------------------------
        -- G-NTC: the 3.4 NTC monitor thresholds and their hysteresis
        -- (VNTC_*_SET / VNTC_*_RESET). NTC pin voltage FALLS as the cell
        -- heats up (constant 69 uA INTC into the thermistor).
        ------------------------------------------------------------------
        report "=== G-NTC: NTC thresholds and hysteresis ===" severity note;
        ntc_v <= 240;                            -- below VNTC_EHOT_SET (247 mV)
        wait for 4 * PWR_TICK;
        sb.check_true("G-NTC: NTC_STATUS = 0x0C (eHot) below VNTC_EHOT_SET",
                      ntc_state = PTX_NTC_EHOT);
        sb.check_true("G-NTC: ERROR_STATUS = 0x08 (battery temperature error)",
                      err_state = PTX_ERR_BATTEMP);

        ntc_v <= 280;                            -- inside the eHot hysteresis band
        wait for 4 * PWR_TICK;
        sb.check_true("G-NTC: eHot HOLDS between VNTC_EHOT_SET and "
                      & "VNTC_EHOT_RESET (305 mV)", ntc_state = PTX_NTC_EHOT);

        ntc_v <= 330;                            -- above EHOT_RESET, below HOT_SET
        wait for 4 * PWR_TICK;
        sb.check_true("G-NTC: eHot resets above 305 mV, Hot still set",
                      ntc_state = PTX_NTC_HOT);

        ntc_v <= 1800;                           -- above VNTC_ECOLD_SET (1785 mV)
        wait for 4 * PWR_TICK;
        sb.check_true("G-NTC: NTC_STATUS = 0x03 (eCold) above VNTC_ECOLD_SET",
                      ntc_state = PTX_NTC_ECOLD);

        ntc_v <= 690;                            -- back to the normal band
        wait for 4 * PWR_TICK;
        sb.check_true("G-NTC: NTC_STATUS back to 0x00 (normal)",
                      ntc_state = PTX_NTC_NORMAL);
        -- ERROR_STATUS is "cleared when read using the Host interface" (4.8.1):
        -- read it once and confirm the second read comes back clean.
        pay(0) := PTX_NSC_GET_PARAM;
        nsc_send(pay, 1, ack);
        wait for 5 us;
        nsc_recv(resp, rlen);
        sb.check_slv("G-NTC: ERROR_STATUS still latched on the first read",
                     resp(4), u8(PTX_ERR_BATTEMP));
        wait for 4 * PWR_TICK;
        pay(0) := PTX_NSC_GET_PARAM;
        nsc_send(pay, 1, ack);
        wait for 5 us;
        nsc_recv(resp, rlen);
        sb.check_slv("G-NTC: ERROR_STATUS cleared by the read (4.8.1)",
                     resp(4), u8(PTX_ERR_NONE));

        -- 6. IVDMCU limit (3.4): above 50 mA the LDO folds back and
        --    vdmcu_good drops.
        vdmcu_load <= 60;
        wait for 4 * PWR_TICK;
        sb.check_bit("G-PWR: vdmcu_good drops above the 50 mA IVDMCU limit",
                     vdmcu_good, '0');
        sb.check_true("G-PWR: VDMCU folds back below its target",
                      vdmcu_mv < 3300);
        vdmcu_load <= 0;
        wait for 4 * PWR_TICK;
        sb.check_bit("G-PWR: vdmcu_good recovers when the load is removed",
                     vdmcu_good, '1');

        -- 7. VDDC brownout (3.4): no field and no battery collapses VDDC,
        --    the BOD asserts and the I2C target stops answering.
        rf_field  <= false;
        bat_conn  <= false;
        vddc_load <= 5;
        wait for 8 * PWR_TICK;
        sb.check_bit("G-PWR: VDDC brownout asserted with no field and no battery",
                     bod_reset, '1');
        sb.check_bit("G-PWR: vdmcu_good is low in brownout", vdmcu_good, '0');
        i2c_start;
        addr_phase(DEV_ADDR, '0', ack);
        i2c_stop;
        sb.check_bit("G-PWR: I2C target does not answer while held in BOD reset",
                     ack, '0');

        bat_conn  <= true;
        vddc_load <= 0;
        rf_field  <= true;
        wait for 8 * PWR_TICK;
        sb.check_bit("G-PWR: BOD released once VDDC recovers", bod_reset, '0');

        ------------------------------------------------------------------
        -- G-RST: HIP System Reset (4.8.3.6.1). DFYS must be 0x01; with
        -- FCB.RAK set the device answers with the 4.8.3.4 acknowledge frame.
        ------------------------------------------------------------------
        report "=== G-RST: HIP System Reset ===" severity note;
        pay(0) := x"02";                        -- invalid DFYS
        hip_cmd(PTX_OP_RST, true, false, pay, 1, false, true, aack);
        wait for 5 us;
        sb.check_slv("G-RST: DFYS other than 0x01 stores NAK 0x04",
                     obs_last_nak, PTX_NAK_PARAM);

        pay(0) := x"01";
        hip_cmd(PTX_OP_RST, true, false, pay, 1, false, false, aack);
        hip_resp(true, resp, rlen, aack);
        sb.check_true("G-RST: acknowledge frame LEN = 2 (FCB + ACK)", rlen = 2);
        sb.check_slv("G-RST: acknowledge FCB has RAK set (4.8.3.4)",
                     resp(2), x"14");
        sb.check_slv("G-RST: ACK value is 0x00", resp(3), x"00");
        wait for 5 us;
        sb.check_bit("G-RST: reset cleared any pending message (IRQ low)",
                     irq, '0');
        sb.check_bit("G-RST: reset cleared TDC_BUF_LIS", lis_valid, '0');

        ------------------------------------------------------------------
        -- G-NEG: NEGATIVE CONTROL (mandatory, LAST). One deliberately wrong
        -- expectation, so a passing run proves the scoreboard can fail.
        ------------------------------------------------------------------
        report "=== G-NEG: NEGATIVE CONTROL ===" severity note;
        if NEGCTRL then
            sb.check_slv("NEGATIVE CONTROL: wrong expected HW_VERSION (must FAIL)",
                         neg_val, std_logic_vector(unsigned(neg_val) + 1));
        end if;

        ------------------------------------------------------------------
        -- Verdict: exactly one failure, the negative control.
        ------------------------------------------------------------------
        wait for 2 us;
        sb.report_summary("PTX30W TB");

        if (NEGCTRL and sb.errors = 1) or ((not NEGCTRL) and sb.errors = 0) then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   PTX30W_TB PASS (1 expected negative-control failure)" & LF &
                "    ##   PTX30W TB:  ALL CHECKS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   PTX30W_TB FAIL (expected exactly 1 failure "
                & "[negative control], got " & integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        stop;
        wait;
    end process stim;

end architecture sim;
