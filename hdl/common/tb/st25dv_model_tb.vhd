-------------------------------------------------------------------------------
-- st25dv_model_tb.vhd
-------------------------------------------------------------------------------
-- Self-checking testbench for st25dv_model.vhd, the ST25DV64KC dynamic NFC tag model: the BENCH is the I2C controller and the MODEL is the slave.
-- The controller is bit-banged here rather than reusing i2c_host_model.vhd, whose 8-byte segment cap carries neither the 2 address + 17 data byte present-password frame nor a device-select-only ACK probe.
-- SCL, SDA and GPO are open-drain nets with a weak 'H' pull: nobody drives an active high, and every sample of a resolved net is to_X01-normalized.
-- Timing is T_HALF = 500 ns plus a T_Q = 125 ns tail after every SCL falling edge, so SDA never changes in the same delta as an SCL edge (a coincident change parses as START/STOP); one bit is 1.125 us, about 890 kHz.
-- G-NEG is the mandatory negative control, so a healthy run reports EXACTLY ONE failure; the RF/ISO-15693 side, memory-area protection and the FTM watchdog are not modelled and are not proven here.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;

entity st25dv_model_tb is
    generic (
        -- 1 = inject the deliberate wrong expectation; the negative control is always present and this generic only parks it.
        NEGCTRL : integer := 1
    );
end entity st25dv_model_tb;

architecture sim of st25dv_model_tb is

    ---------------------------------------------------------------------------
    -- Bench-local byte container, deliberately not from i2ct_bfm_pkg: that package's I2CT_MODEL_MAX_BYTES=8 shape does not fit these frames.
    type byte_arr is array (natural range <>) of std_logic_vector(7 downto 0);

    constant T_HALF : time := 500 ns;    -- SCL half period
    constant T_Q    : time := 125 ns;    -- post-falling-edge tail (SDA guard)

    -- Device select codes at the factory I2C_CFG.
    constant DS_UW : std_logic_vector(7 downto 0) := x"A6";  -- user/dyn/mailbox write
    constant DS_UR : std_logic_vector(7 downto 0) := x"A7";  -- user/dyn/mailbox read
    constant DS_SW : std_logic_vector(7 downto 0) := x"AE";  -- system write
    constant DS_SR : std_logic_vector(7 downto 0) := x"AF";  -- system read

    -- EEPROM write time for the model instance.
    constant TW_MODEL : time := 5 ms;

    component st25dv_model is
        generic (
            T_W        : time := 5 ms;
            IC_REF_VAL : std_logic_vector(7 downto 0) := x"51";
            IC_REV_VAL : std_logic_vector(7 downto 0) := x"01"
        );
        port (
            resetn : in std_logic := '1';
            vcc_on : in std_logic := '1';
            scl     : in  std_logic;
            sda_in  : in  std_logic;
            sda_out : out std_logic := '0';
            sda_oe  : out std_logic := '0';
            gpo_out : out std_logic := '0';
            gpo_oe  : out std_logic := '0';
            eh_enabled   : out std_logic := '0';
            veh_active   : out std_logic := '0';
            veh_avail_ua : out natural   := 0;
            cfg_veh_ua   : in  natural   := 0;
            rf_field    : in std_logic := '0';
            rf_put_msg  : in std_logic := '0';
            rf_put_len  : in natural   := 0;
            rf_put_seed : in std_logic_vector(7 downto 0) := x"00";
            rf_get_msg  : in std_logic := '0';
            rf_write_ee : in std_logic := '0';
            obs_devsel      : out std_logic_vector(7 downto 0) := (others => '0');
            obs_addr        : out natural   := 0;
            obs_txn_count   : out natural   := 0;
            obs_wcommit     : out natural   := 0;
            obs_devsel_nack : out natural   := 0;
            obs_busy        : out std_logic := '0';
            obs_it_sts      : out std_logic_vector(7 downto 0) := (others => '0');
            obs_mb_ctrl     : out std_logic_vector(7 downto 0) := (others => '0');
            obs_mb_len      : out std_logic_vector(7 downto 0) := (others => '0');
            obs_i2c_sso     : out std_logic := '0';
            obs_rf_off      : out std_logic := '0'
        );
    end component;

    -- Master drive-enables (open drain).
    signal m_scl_oe : std_logic := '0';
    signal m_sda_oe : std_logic := '0';

    -- Model drive-enables.
    signal d_sda_oe : std_logic;
    signal d_gpo_oe : std_logic;
    signal d_sda_out, d_gpo_out : std_logic;

    -- Resolved nets (weak 'H' pull-ups).
    signal scl : std_logic;
    signal sda : std_logic;
    signal gpo : std_logic;

    -- Power and RF stimulus.
    signal resetn      : std_logic := '0';
    signal vcc_on      : std_logic := '1';
    signal rf_field    : std_logic := '0';
    signal rf_put_msg  : std_logic := '0';
    signal rf_put_len  : natural   := 0;
    signal rf_put_seed : std_logic_vector(7 downto 0) := x"00";
    signal rf_get_msg  : std_logic := '0';
    signal rf_write_ee : std_logic := '0';
    signal cfg_veh_ua  : natural   := 250;

    -- Model observations.
    signal eh_enabled   : std_logic;
    signal veh_active   : std_logic;
    signal veh_avail_ua : natural;
    signal obs_devsel      : std_logic_vector(7 downto 0);
    signal obs_addr        : natural;
    signal obs_txn_count   : natural;
    signal obs_wcommit     : natural;
    signal obs_devsel_nack : natural;
    signal obs_busy        : std_logic;
    signal obs_it_sts      : std_logic_vector(7 downto 0);
    signal obs_mb_ctrl     : std_logic_vector(7 downto 0);
    signal obs_mb_len      : std_logic_vector(7 downto 0);
    signal obs_i2c_sso     : std_logic;
    signal obs_rf_off      : std_logic;

    -- GPO edge monitor, checker independence: counts falling edges off the RESOLVED net, never off a model internal.
    signal gpo_rst   : std_logic := '0';
    signal gpo_falls : natural   := 0;

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

begin

    ---------------------------------------------------------------------------
    -- Open-drain wired-AND with weak pull-ups.
    scl <= '0' when m_scl_oe = '1' else 'H';
    sda <= '0' when (m_sda_oe = '1' or d_sda_oe = '1') else 'H';
    gpo <= '0' when d_gpo_oe = '1' else 'H';

    dut : st25dv_model
        generic map (
            T_W        => TW_MODEL,
            IC_REF_VAL => x"51",
            IC_REV_VAL => x"01"
        )
        port map (
            resetn => resetn,
            vcc_on => vcc_on,
            scl     => scl,
            sda_in  => sda,
            sda_out => d_sda_out,
            sda_oe  => d_sda_oe,
            gpo_out => d_gpo_out,
            gpo_oe  => d_gpo_oe,
            eh_enabled   => eh_enabled,
            veh_active   => veh_active,
            veh_avail_ua => veh_avail_ua,
            cfg_veh_ua   => cfg_veh_ua,
            rf_field    => rf_field,
            rf_put_msg  => rf_put_msg,
            rf_put_len  => rf_put_len,
            rf_put_seed => rf_put_seed,
            rf_get_msg  => rf_get_msg,
            rf_write_ee => rf_write_ee,
            obs_devsel      => obs_devsel,
            obs_addr        => obs_addr,
            obs_txn_count   => obs_txn_count,
            obs_wcommit     => obs_wcommit,
            obs_devsel_nack => obs_devsel_nack,
            obs_busy        => obs_busy,
            obs_it_sts      => obs_it_sts,
            obs_mb_ctrl     => obs_mb_ctrl,
            obs_mb_len      => obs_mb_len,
            obs_i2c_sso     => obs_i2c_sso,
            obs_rf_off      => obs_rf_off
        );

    ---------------------------------------------------------------------------
    -- GPO falling-edge monitor: gpo_rst clears the count, every falling edge on the resolved net adds one.
    gpo_mon : process (gpo, gpo_rst)
    begin
        if to_X01(gpo_rst) = '1' then
            gpo_falls <= 0;
        elsif gpo'event and to_X01(gpo) = '0' then
            gpo_falls <= gpo_falls + 1;
        end if;
    end process gpo_mon;

    ---------------------------------------------------------------------------
    -- Stimulus and checks, one thread, groups in order.
    stim : process
        variable ak    : std_logic;
        variable b     : std_logic_vector(7 downto 0);
        variable rd    : byte_arr(0 to 31);
        variable wd    : byte_arr(0 to 31);
        variable pw    : byte_arr(0 to 7);
        variable okv   : boolean;
        variable nk    : natural;
        variable tries : natural;

        -- ---- pin primitives ------------------------------------------------
        procedure scl_rel is begin m_scl_oe <= '0'; end procedure;
        procedure scl_low is begin m_scl_oe <= '1'; end procedure;
        procedure sda_rel is begin m_sda_oe <= '0'; end procedure;
        procedure sda_low is begin m_sda_oe <= '1'; end procedure;

        -- ---- framing -------------------------------------------------------
        procedure i2c_start is
        begin
            sda_rel;  wait for T_Q;      -- bus idle high
            scl_rel;  wait for T_HALF;
            sda_low;  wait for T_HALF;   -- SDA falls while SCL is high, a START
            scl_low;  wait for T_Q;
        end procedure;

        procedure i2c_rstart is
        begin
            -- entered with SCL held low by the master
            sda_rel;  wait for T_HALF;
            scl_rel;  wait for T_HALF;
            sda_low;  wait for T_HALF;   -- repeated START
            scl_low;  wait for T_Q;
        end procedure;

        procedure i2c_stop is
        begin
            sda_low;  wait for T_HALF;   -- SCL low here
            scl_rel;  wait for T_HALF;
            sda_rel;  wait for T_HALF;   -- SDA rises while SCL is high, a STOP
        end procedure;

        -- ---- bit slots -----------------------------------------------------
        procedure wr_bit(v : in std_logic) is
        begin
            if v = '1' then sda_rel; else sda_low; end if;
            wait for T_HALF;             -- setup while SCL low
            scl_rel;  wait for T_HALF;   -- tHIGH
            scl_low;  wait for T_Q;      -- guard: SDA never moves with the edge
        end procedure;

        procedure rd_bit(v : out std_logic) is
        begin
            sda_rel;  wait for T_HALF;   -- release: the slave owns SDA
            scl_rel;  wait for T_HALF/2; -- sample mid-tHIGH
            v := to_X01(sda);
            wait for T_HALF/2;
            scl_low;  wait for T_Q;
        end procedure;

        -- ---- byte slots ----------------------------------------------------
        -- acked = '1' when the SLAVE pulled SDA low in the 9th bit slot.
        procedure wr_byte(d : in std_logic_vector(7 downto 0);
                          acked : out std_logic) is
            variable lv : std_logic;
        begin
            for i in 7 downto 0 loop
                wr_bit(d(i));
            end loop;
            rd_bit(lv);
            acked := not lv;
        end procedure;

        -- do_ack = '1' makes the master ACK (continue), '0' makes it NACK (last byte).
        procedure rd_byte(do_ack : in std_logic;
                          d      : out std_logic_vector(7 downto 0)) is
            variable lv : std_logic;
            variable v  : std_logic_vector(7 downto 0);
        begin
            for i in 7 downto 0 loop
                rd_bit(lv);
                v(i) := lv;
            end loop;
            wr_bit(not do_ack);          -- ACK = drive low
            d := v;
        end procedure;

        -- ---- transactions --------------------------------------------------
        -- Device-select-only ACK probe: a read device select is followed by one consumed byte so the slave releases SDA before the STOP, since a slave still sourcing a data bit makes a STOP impossible.
        procedure dev_probe(dsel : in std_logic_vector(7 downto 0);
                            acked : out boolean) is
            variable a : std_logic;
            variable d : std_logic_vector(7 downto 0);
        begin
            i2c_start;
            wr_byte(dsel, a);
            if a = '1' and dsel(0) = '1' then
                rd_byte('0', d);
            end if;
            i2c_stop;
            acked := (a = '1');
        end procedure;

        -- Byte or sequential write: device select, the 2 address bytes, then n data bytes, counting every NACK seen.
        procedure mem_write(dsel    : in  std_logic_vector(7 downto 0);
                            addr    : in  natural;
                            d       : in  byte_arr;
                            n       : in  natural;
                            all_ack : out boolean;
                            nacks   : out natural) is
            variable a  : std_logic;
            variable c  : natural := 0;
            variable ok : boolean := true;
        begin
            i2c_start;
            wr_byte(dsel, a);
            if a = '0' then ok := false; c := c + 1; end if;
            if a = '1' then
                wr_byte(std_logic_vector(to_unsigned(addr / 256, 8)), a);
                if a = '0' then ok := false; c := c + 1; end if;
                wr_byte(std_logic_vector(to_unsigned(addr mod 256, 8)), a);
                if a = '0' then ok := false; c := c + 1; end if;
                for i in 0 to n - 1 loop
                    wr_byte(d(i), a);
                    if a = '0' then ok := false; c := c + 1; end if;
                end loop;
            end if;
            i2c_stop;
            all_ack := ok;
            nacks   := c;
        end procedure;

        -- Random address read: dummy write of the 2 address bytes, repeated START, read device select, n bytes, master NACKs the last.
        procedure mem_read(dw, dr : in  std_logic_vector(7 downto 0);
                           addr   : in  natural;
                           n      : in  natural;
                           d      : out byte_arr;
                           ok     : out boolean) is
            variable a    : std_logic;
            variable v    : std_logic_vector(7 downto 0);
            variable good : boolean := true;
        begin
            i2c_start;
            wr_byte(dw, a);
            if a = '0' then good := false; end if;
            wr_byte(std_logic_vector(to_unsigned(addr / 256, 8)), a);
            if a = '0' then good := false; end if;
            wr_byte(std_logic_vector(to_unsigned(addr mod 256, 8)), a);
            if a = '0' then good := false; end if;
            i2c_rstart;
            wr_byte(dr, a);
            if a = '0' then good := false; end if;
            for i in 0 to n - 1 loop
                if i = n - 1 then rd_byte('0', v); else rd_byte('1', v); end if;
                d(i) := v;
            end loop;
            i2c_stop;
            ok := good;
        end procedure;

        -- ACK polling of the internal write cycle.
        procedure poll_ready(dsel  : in  std_logic_vector(7 downto 0);
                             maxn  : in  natural;
                             tries : out natural;
                             ok    : out boolean) is
            variable a : std_logic;
            variable c : natural := 0;
        begin
            ok := false;
            loop
                i2c_start;
                wr_byte(dsel, a);
                i2c_stop;
                c := c + 1;
                if a = '1' then ok := true; exit; end if;
                exit when c >= maxn;
            end loop;
            tries := c;
        end procedure;

        -- I2C present/write password command: AEh, 09h, 00h, PWD[8], validation code, PWD[8].
        procedure pwd_cmd(p       : in  byte_arr;
                          code    : in  std_logic_vector(7 downto 0);
                          all_ack : out boolean) is
            variable dat : byte_arr(0 to 31);
            variable c   : natural;
        begin
            for i in 0 to 7 loop dat(i) := p(i); end loop;
            dat(8) := code;
            for i in 0 to 7 loop dat(9 + i) := p(i); end loop;
            mem_write(DS_SW, 16#0900#, dat, 17, all_ack, c);
        end procedure;

        -- Zero the GPO falling-edge counter before a timed observation.
        procedure gpo_mon_reset is
        begin
            gpo_rst <= '1';
            wait for T_Q;
            gpo_rst <= '0';
            wait for T_Q;
        end procedure;

    begin
        ------------------------------------------------------------------
        -- G-INIT: power-on and boot state.
        report "=== GROUP G-INIT: reset / boot ===" severity note;
        resetn <= '0';
        wait for 2 us;
        resetn <= '1';
        wait for 2 us;

        sb.check_bit("G-INIT 1: not busy after boot", to_X01(obs_busy), '0');
        sb.check_bit("G-INIT 2: I2C security session CLOSED after boot", to_X01(obs_i2c_sso), '0');
        sb.check_bit("G-INIT 3: EH_EN = 0 after boot (EH_MODE factory 01h = on demand)",
                     to_X01(eh_enabled), '0');
        sb.check_bit("G-INIT 4: V_EH High-Z after boot", to_X01(veh_active), '0');
        sb.check_bit("G-INIT 5: GPO released (no pending interrupt)", to_X01(gpo), '1');
        sb.check_bit("G-INIT 6: SDA released by the model at idle", to_X01(sda), '1');

        ------------------------------------------------------------------
        -- G-ADDR: both device select codes plus the near misses; the code layout is 1010 E2 E1 E0 R/notW.
        report "=== GROUP G-ADDR: device select codes ===" severity note;

        dev_probe(DS_UW, okv);
        sb.check_true("G-ADDR 1: A6h (user memory / dyn / mailbox, write) ACKs", okv);
        dev_probe(DS_UR, okv);
        sb.check_true("G-ADDR 2: A7h (user memory / dyn / mailbox, read) ACKs", okv);
        dev_probe(DS_SW, okv);
        sb.check_true("G-ADDR 3: AEh (system configuration, write) ACKs", okv);
        dev_probe(DS_SR, okv);
        sb.check_true("G-ADDR 4: AFh (system configuration, read) ACKs", okv);

        dev_probe(x"A2", okv);
        sb.check_true("G-ADDR 5: A2h (E1=0, RFSwitchOff) NACKs -- I2C_RF_SWITCHOFF_EN is 0 at factory",
                      not okv);
        dev_probe(x"A4", okv);
        sb.check_true("G-ADDR 6: A4h (E0=0, wrong chip-enable) NACKs", not okv);
        dev_probe(x"B6", okv);
        sb.check_true("G-ADDR 7: B6h (device code 1011b) NACKs", not okv);
        dev_probe(x"50", okv);
        sb.check_true("G-ADDR 8: 50h (an unrelated EEPROM address) NACKs", not okv);

        ------------------------------------------------------------------
        -- G-SYSRD: read-only device parameter registers; reads need no security session.
        report "=== GROUP G-SYSRD: system read-only registers ===" severity note;

        mem_read(DS_SW, DS_SR, 16#0017#, 1, rd, okv);
        sb.check_slv("G-SYSRD 1: IC_REF (0017h) = 51h for ST25DV64KC", rd(0), x"51");

        mem_read(DS_SW, DS_SR, 16#0016#, 1, rd, okv);
        sb.check_slv("G-SYSRD 2: BLK_SIZE (0016h) = 03h", rd(0), x"03");

        -- Sequential read across two bytes: MEM_SIZE = 07FFh, LSB first.
        mem_read(DS_SW, DS_SR, 16#0014#, 2, rd, okv);
        sb.check_slv("G-SYSRD 3: MEM_SIZE LSB (0014h) = FFh", rd(0), x"FF");
        sb.check_slv("G-SYSRD 4: MEM_SIZE MSB (0015h) = 07h (2048 blocks = 64 Kbit)",
                     rd(1), x"07");

        -- UID bytes 5 to 7 are datasheet-defined: 51h 02h E0h.
        mem_read(DS_SW, DS_SR, 16#001D#, 3, rd, okv);
        sb.check_slv("G-SYSRD 5: UID byte 5 (ST product code) = 51h", rd(0), x"51");
        sb.check_slv("G-SYSRD 6: UID byte 6 (IC mfg code) = 02h", rd(1), x"02");
        sb.check_slv("G-SYSRD 7: UID byte 7 = E0h", rd(2), x"E0");

        -- Factory values of GPO1, GPO2, EH_MODE and FTM.
        mem_read(DS_SW, DS_SR, 16#0000#, 2, rd, okv);
        sb.check_slv("G-SYSRD 8: GPO1 factory = 11h (GPO_EN + FIELD_CHANGE_EN)", rd(0), x"11");
        sb.check_slv("G-SYSRD 9: GPO2 factory = 0Ch (IT_TIME = 011b)", rd(1), x"0C");
        mem_read(DS_SW, DS_SR, 16#0002#, 1, rd, okv);
        sb.check_slv("G-SYSRD 10: EH_MODE factory = 01h (EH on demand)", rd(0), x"01");
        mem_read(DS_SW, DS_SR, 16#000E#, 1, rd, okv);
        sb.check_slv("G-SYSRD 11: I2C_CFG factory = 1Ah (code 1010b, E0=1, RFSW disabled)",
                     rd(0), x"1A");

        ------------------------------------------------------------------
        -- G-PWD: system configuration writes and the security session.
        report "=== GROUP G-PWD: security session / configuration write ===" severity note;

        -- (a) System write with the session CLOSED: device select and both address bytes ACK, the DATA byte is NACKed.
        wd(0) := x"71";
        mem_write(DS_SW, 16#0000#, wd, 1, okv, nk);
        sb.check_true("G-PWD 1: system write with session closed is NACKed", not okv);
        sb.check_true("G-PWD 2: exactly the data byte was NACKed (device select + address ACKed)",
                      nk = 1);
        mem_read(DS_SW, DS_SR, 16#0000#, 1, rd, okv);
        sb.check_slv("G-PWD 3: GPO1 unchanged after the inhibited write", rd(0), x"11");

        -- (b) Present a WRONG password: the session stays closed.
        pw := (others => x"00");
        pw(0) := x"DE";
        pwd_cmd(pw, x"09", okv);
        sb.check_true("G-PWD 4: present-password frame is fully ACKed (17 data bytes)", okv);
        wait for 1 us;
        sb.check_bit("G-PWD 5a: wrong password leaves the session CLOSED (obs)",
                     to_X01(obs_i2c_sso), '0');
        -- I2C_SSO_Dyn is a DYNAMIC register: E2=0 (A6h/A7h), not the system code.
        mem_read(DS_UW, DS_UR, 16#2004#, 1, rd, okv);
        sb.check_slv("G-PWD 5b: I2C_SSO_Dyn (2004h) reads 00h", rd(0), x"00");

        -- (c) Present the FACTORY password (all zeros): the session opens.
        pw := (others => x"00");
        pwd_cmd(pw, x"09", okv);
        sb.check_true("G-PWD 6: present-password frame is fully ACKed", okv);
        wait for 1 us;
        sb.check_bit("G-PWD 7: correct password OPENS the session (obs)",
                     to_X01(obs_i2c_sso), '1');
        mem_read(DS_UW, DS_UR, 16#2004#, 1, rd, okv);
        sb.check_slv("G-PWD 8: I2C_SSO_Dyn (2004h, device select A7h) reads 01h", rd(0), x"01");

        -- (d) Real configuration write: GPO1 = 71h (GPO_EN + FIELD_CHANGE + RF_PUT_MSG + RF_GET_MSG), then poll out the tW write cycle.
        wd(0) := x"71";
        mem_write(DS_SW, 16#0000#, wd, 1, okv, nk);
        sb.check_true("G-PWD 9: system write with session open is ACKed", okv);
        poll_ready(DS_SW, 2000, tries, okv);
        sb.check_true("G-PWD 10: system EEPROM write cycle completes under ACK polling", okv);
        sb.check_true("G-PWD 11: the system write really was busy (>1 poll needed)", tries > 1);
        mem_read(DS_SW, DS_SR, 16#0000#, 1, rd, okv);
        sb.check_slv("G-PWD 12: GPO1 reads back 71h", rd(0), x"71");

        -- (e) A write to a READ-ONLY system register is NACKed even with the session open.
        wd(0) := x"AA";
        mem_write(DS_SW, 16#0017#, wd, 1, okv, nk);
        sb.check_true("G-PWD 13: write to IC_REF (read-only) is NACKed", not okv);
        mem_read(DS_SW, DS_SR, 16#0017#, 1, rd, okv);
        sb.check_slv("G-PWD 14: IC_REF unchanged", rd(0), x"51");

        -- (f) More than ONE byte in the system area is inhibited.
        wd(0) := x"0C"; wd(1) := x"01";
        mem_write(DS_SW, 16#0001#, wd, 2, okv, nk);
        sb.check_true("G-PWD 15: second byte of a system-area sequential write is NACKed",
                      (not okv) and nk = 1);
        poll_ready(DS_SW, 2000, tries, okv);
        mem_read(DS_SW, DS_SR, 16#0001#, 1, rd, okv);
        sb.check_slv("G-PWD 16: GPO2 unchanged (whole write discarded)", rd(0), x"0C");

        ------------------------------------------------------------------
        -- G-EE: user EEPROM write, write cycle and read back.
        report "=== GROUP G-EE: user EEPROM ===" severity note;

        mem_read(DS_UW, DS_UR, 16#0100#, 1, rd, okv);
        sb.check_slv("G-EE 1: virgin user memory reads 00h", rd(0), x"00");

        -- (a) Byte write followed by ACK polling.
        wd(0) := x"5A";
        mem_write(DS_UW, 16#0100#, wd, 1, okv, nk);
        sb.check_true("G-EE 2: user byte write is ACKed", okv);
        -- The device must be UNRESPONSIVE immediately after the STOP.
        dev_probe(DS_UW, okv);
        sb.check_true("G-EE 3: device select NACKs during the internal write cycle", not okv);
        poll_ready(DS_UW, 2000, tries, okv);
        sb.check_true("G-EE 4: write cycle completes under ACK polling", okv);
        sb.check_true("G-EE 5: polling really spanned the tW window (>10 attempts at ~890 kHz)",
                      tries > 10);
        mem_read(DS_UW, DS_UR, 16#0100#, 1, rd, okv);
        sb.check_slv("G-EE 6: byte reads back as 5Ah", rd(0), x"5A");

        -- (b) Sequential write of 4 bytes inside one 16-byte row.
        wd(0) := x"11"; wd(1) := x"22"; wd(2) := x"33"; wd(3) := x"44";
        mem_write(DS_UW, 16#0200#, wd, 4, okv, nk);
        sb.check_true("G-EE 7: 4-byte sequential write is fully ACKed", okv);
        poll_ready(DS_UW, 2000, tries, okv);
        sb.check_true("G-EE 8: sequential write cycle completes", okv);
        mem_read(DS_UW, DS_UR, 16#0200#, 4, rd, okv);
        sb.check_slv("G-EE 9: sequential read byte 0", rd(0), x"11");
        sb.check_slv("G-EE 10: sequential read byte 1", rd(1), x"22");
        sb.check_slv("G-EE 11: sequential read byte 2", rd(2), x"33");
        sb.check_slv("G-EE 12: sequential read byte 3", rd(3), x"44");

        -- (c) A current-address read continues from the internal counter.
        i2c_start;
        wr_byte(DS_UR, ak);
        sb.check_bit("G-EE 13: current-address read device select ACKs", ak, '1');
        rd_byte('0', b);
        i2c_stop;
        sb.check_slv("G-EE 14: current-address read returns 0204h (counter advanced past the 4 bytes)",
                     b, x"00");

        -- (d) An unmapped E2=0 address reads FFh: an unsuccessful read returns all ones.
        mem_read(DS_UW, DS_UR, 16#3000#, 1, rd, okv);
        sb.check_slv("G-EE 15: unmapped address 3000h reads FFh", rd(0), x"FF");

        ------------------------------------------------------------------
        -- G-MB: fast transfer mode mailbox.
        report "=== GROUP G-MB: fast transfer mode mailbox ===" severity note;

        -- (a) MB_EN cannot be set while FTM.MB_MODE is 0.
        wd(0) := x"01";
        mem_write(DS_UW, 16#2006#, wd, 1, okv, nk);
        sb.check_true("G-MB 1: MB_CTRL_Dyn write is ACKed (dynamic register)", okv);
        mem_read(DS_UW, DS_UR, 16#2006#, 1, rd, okv);
        sb.check_slv("G-MB 2: MB_EN stays 0 while FTM.MB_MODE = 0", rd(0), x"00");

        -- (b) Authorize FTM in the system area; this needs the open session.
        wd(0) := x"01";
        mem_write(DS_SW, 16#000D#, wd, 1, okv, nk);
        sb.check_true("G-MB 3: FTM register write is ACKed", okv);
        poll_ready(DS_SW, 2000, tries, okv);
        sb.check_true("G-MB 4: FTM write cycle completes", okv);

        -- (c) Now MB_EN sticks, and it is IMMEDIATE: no tW, no polling.
        wd(0) := x"01";
        mem_write(DS_UW, 16#2006#, wd, 1, okv, nk);
        dev_probe(DS_UW, okv);
        sb.check_true("G-MB 5: dynamic-register write needs NO write cycle (device answers at once)",
                      okv);
        mem_read(DS_UW, DS_UR, 16#2006#, 1, rd, okv);
        sb.check_slv("G-MB 6: MB_CTRL_Dyn = 01h (MB_EN set, mailbox empty)", rd(0), x"01");

        -- (d) With FTM active, user-EEPROM writes are inhibited.
        wd(0) := x"99";
        mem_write(DS_UW, 16#0300#, wd, 1, okv, nk);
        sb.check_true("G-MB 7: user EEPROM write is NACKed while FTM is active",
                      (not okv) and nk = 1);

        -- (e) An RF reader puts an 8-byte message in the mailbox.
        gpo_mon_reset;
        rf_put_len  <= 8;
        rf_put_seed <= x"40";
        wait for 1 us;
        rf_put_msg <= '1';
        wait for 20 us;
        sb.check_bit("G-MB 8: GPO is ASSERTED (low) by the RF_PUT_MSG interrupt",
                     to_X01(gpo), '0');
        sb.check_true("G-MB 9: exactly one GPO falling edge", gpo_falls = 1);
        rf_put_msg <= '0';
        -- IT pulse = 301 us - 3*37.65 us = 188.05 us, well clear by 260 us.
        wait for 260 us;
        sb.check_bit("G-MB 10: GPO pulse has expired (interrupt self-clears)",
                     to_X01(gpo), '1');

        mem_read(DS_UW, DS_UR, 16#2005#, 1, rd, okv);
        sb.check_slv("G-MB 11: IT_STS_Dyn reports RF_PUT_MSG (bit 5)", rd(0), x"20");
        mem_read(DS_UW, DS_UR, 16#2005#, 1, rd, okv);
        sb.check_slv("G-MB 12: IT_STS_Dyn is CLEARED BY READING", rd(0), x"00");

        mem_read(DS_UW, DS_UR, 16#2006#, 1, rd, okv);
        sb.check_slv("G-MB 13: MB_CTRL_Dyn = 85h (MB_EN + RF_PUT_MSG + RF_CURRENT_MSG)",
                     rd(0), x"85");
        mem_read(DS_UW, DS_UR, 16#2007#, 1, rd, okv);
        sb.check_slv("G-MB 14: MB_LEN_Dyn = 07h (message length minus 1)", rd(0), x"07");

        -- (f) Read the message out; RF_PUT_MSG clears at the STOP after the last message byte.
        mem_read(DS_UW, DS_UR, 16#2008#, 8, rd, okv);
        sb.check_slv("G-MB 15: mailbox byte 0", rd(0), x"40");
        sb.check_slv("G-MB 16: mailbox byte 3", rd(3), x"43");
        sb.check_slv("G-MB 17: mailbox byte 7 (last)", rd(7), x"47");
        mem_read(DS_UW, DS_UR, 16#2006#, 1, rd, okv);
        sb.check_slv("G-MB 18: MB_CTRL_Dyn = 81h after the I2C read (RF_PUT_MSG cleared)",
                     rd(0), x"81");

        -- (g) Past the end of the message the mailbox reads FFh, with no rollover.
        mem_read(DS_UW, DS_UR, 16#2010#, 1, rd, okv);
        sb.check_slv("G-MB 19: mailbox read past the message end returns FFh", rd(0), x"FF");

        -- (h) I2C puts a 4-byte message for the RF side.
        wd(0) := x"C0"; wd(1) := x"C1"; wd(2) := x"C2"; wd(3) := x"C3";
        mem_write(DS_UW, 16#2008#, wd, 4, okv, nk);
        sb.check_true("G-MB 20: I2C mailbox write is fully ACKed", okv);
        mem_read(DS_UW, DS_UR, 16#2006#, 1, rd, okv);
        sb.check_slv("G-MB 21: MB_CTRL_Dyn = 43h (HOST_PUT_MSG + HOST_CURRENT_MSG)",
                     rd(0), x"43");
        mem_read(DS_UW, DS_UR, 16#2007#, 1, rd, okv);
        sb.check_slv("G-MB 22: MB_LEN_Dyn = 03h", rd(0), x"03");

        -- (i) The mailbox is now BUSY: a second put is NACKed.
        wd(0) := x"EE";
        mem_write(DS_UW, 16#2008#, wd, 1, okv, nk);
        sb.check_true("G-MB 23: mailbox write while a message is pending is NACKed",
                      (not okv) and nk = 1);

        -- (j) A mailbox write must start at 2008h.
        wd(0) := x"EE";
        mem_write(DS_UW, 16#2009#, wd, 1, okv, nk);
        sb.check_true("G-MB 24: mailbox write not starting at 2008h is NACKed",
                      (not okv) and nk = 1);

        -- (k) The RF side collects the message: HOST_PUT_MSG clears and GPO pulses.
        gpo_mon_reset;
        rf_get_msg <= '1';
        wait for 20 us;
        sb.check_bit("G-MB 25: GPO asserted by the RF_GET_MSG interrupt", to_X01(gpo), '0');
        rf_get_msg <= '0';
        wait for 260 us;
        sb.check_true("G-MB 26: exactly one GPO pulse for RF_GET_MSG", gpo_falls = 1);
        mem_read(DS_UW, DS_UR, 16#2006#, 1, rd, okv);
        sb.check_slv("G-MB 27: MB_CTRL_Dyn = 41h after the RF read (HOST_PUT_MSG cleared)",
                     rd(0), x"41");
        mem_read(DS_UW, DS_UR, 16#2005#, 1, rd, okv);
        sb.check_slv("G-MB 28: IT_STS_Dyn reports RF_GET_MSG (bit 6)", rd(0), x"40");

        -- (l) Turn FTM back off so the EEPROM groups below can write again.
        wd(0) := x"00";
        mem_write(DS_UW, 16#2006#, wd, 1, okv, nk);
        mem_read(DS_UW, DS_UR, 16#2006#, 1, rd, okv);
        sb.check_slv("G-MB 29: MB_CTRL_Dyn = 00h once FTM is disabled", rd(0), x"00");

        ------------------------------------------------------------------
        -- G-GPO: GPO_CTRL_Dyn gating of the interrupt output.
        report "=== GROUP G-GPO: GPO output control ===" severity note;

        -- (a) Field change with the output ENABLED.
        gpo_mon_reset;
        rf_field <= '1';
        wait for 20 us;
        sb.check_bit("G-GPO 1: RF field rising pulses GPO (FIELD_CHANGE_EN)", to_X01(gpo), '0');
        wait for 260 us;
        sb.check_true("G-GPO 2: exactly one GPO pulse", gpo_falls = 1);
        mem_read(DS_UW, DS_UR, 16#2005#, 1, rd, okv);
        sb.check_slv("G-GPO 3: IT_STS_Dyn reports FIELD_RISING (bit 4)", rd(0), x"10");

        -- (b) Disable the GPO PIN via GPO_CTRL_Dyn; events must STILL be recorded in IT_STS_Dyn.
        wd(0) := x"00";
        mem_write(DS_UW, 16#2000#, wd, 1, okv, nk);
        sb.check_true("G-GPO 4: GPO_CTRL_Dyn write is ACKed", okv);
        gpo_mon_reset;
        rf_field <= '0';
        wait for 300 us;
        sb.check_true("G-GPO 5: no GPO pulse while GPO_CTRL_Dyn.GPO_EN = 0", gpo_falls = 0);
        sb.check_bit("G-GPO 6: GPO stays released", to_X01(gpo), '1');
        mem_read(DS_UW, DS_UR, 16#2005#, 1, rd, okv);
        sb.check_slv("G-GPO 7: FIELD_FALLING (bit 3) still recorded in IT_STS_Dyn",
                     rd(0), x"08");

        -- (c) Re-enable the GPO pin.
        wd(0) := x"01";
        mem_write(DS_UW, 16#2000#, wd, 1, okv, nk);
        gpo_mon_reset;
        rf_field <= '1';
        wait for 20 us;
        sb.check_bit("G-GPO 8: GPO pulses again once GPO_CTRL_Dyn.GPO_EN is restored",
                     to_X01(gpo), '0');
        wait for 300 us;

        -- (d) RF_WRITE interrupt source (GPO1 b7): an RF-side EEPROM write.
        wd(0) := x"F1";
        mem_write(DS_SW, 16#0000#, wd, 1, okv, nk);
        poll_ready(DS_SW, 2000, tries, okv);
        sb.check_true("G-GPO 9: GPO1 update (RF_WRITE_EN) completes", okv);
        mem_read(DS_UW, DS_UR, 16#2005#, 1, rd, okv);   -- clear IT_STS_Dyn first
        gpo_mon_reset;
        rf_write_ee <= '1';
        wait for 20 us;
        sb.check_bit("G-GPO 10: RF EEPROM-write interrupt pulses GPO", to_X01(gpo), '0');
        rf_write_ee <= '0';
        wait for 300 us;
        sb.check_true("G-GPO 11: exactly one GPO pulse for RF_WRITE", gpo_falls = 1);
        mem_read(DS_UW, DS_UR, 16#2005#, 1, rd, okv);
        sb.check_slv("G-GPO 12: IT_STS_Dyn reports RF_WRITE (bit 7)", rd(0), x"80");

        -- (e) I2C_WRITE interrupt source (GPO2 b0): fires at the END of the internal write cycle, not at the STOP.
        wd(0) := x"0D";                                  -- IT_TIME=011b + I2C_WRITE_EN
        mem_write(DS_SW, 16#0001#, wd, 1, okv, nk);
        poll_ready(DS_SW, 2000, tries, okv);
        sb.check_true("G-GPO 13: GPO2 update (I2C_WRITE_EN) completes", okv);
        wait for 400 us;                                 -- let that write's own pulse expire
        gpo_mon_reset;
        wd(0) := x"77";
        mem_write(DS_UW, 16#0400#, wd, 1, okv, nk);
        sb.check_true("G-GPO 14: user EEPROM write is ACKed", okv);
        sb.check_true("G-GPO 15: NO GPO pulse at the STOP -- I2C_WRITE fires at completion",
                      gpo_falls = 0);
        poll_ready(DS_UW, 2000, tries, okv);
        wait for 20 us;
        sb.check_true("G-GPO 16: exactly one GPO pulse once the tW window closes",
                      gpo_falls = 1);
        wait for 300 us;
        -- Restore GPO2 so the remaining EEPROM writes do not raise interrupts.
        wd(0) := x"0C";
        mem_write(DS_SW, 16#0001#, wd, 1, okv, nk);
        poll_ready(DS_SW, 2000, tries, okv);
        wait for 400 us;

        ------------------------------------------------------------------
        -- G-EH: energy harvesting.
        -- V_EH has no digital level encoding, so veh_avail_ua only echoes the bench's cfg_veh_ua.
        report "=== GROUP G-EH: energy harvesting ===" severity note;

        -- rf_field is currently '1' but EH_EN is still 0 (EH_MODE = 01h).
        sb.check_bit("G-EH 1: RF field present but EH disabled -> V_EH High-Z",
                     to_X01(veh_active), '0');
        sb.check_true("G-EH 2: no harvested current advertised while High-Z",
                      veh_avail_ua = 0);
        mem_read(DS_UW, DS_UR, 16#2002#, 1, rd, okv);
        sb.check_slv("G-EH 3: EH_CTRL_Dyn = 0Ch (FIELD_ON + VCC_ON, EH_EN/EH_ON = 0)",
                     rd(0), x"0C");

        -- Enable EH on demand through the dynamic register.
        wd(0) := x"01";
        mem_write(DS_UW, 16#2002#, wd, 1, okv, nk);
        sb.check_true("G-EH 4: EH_CTRL_Dyn write is ACKed", okv);
        wait for 1 us;
        sb.check_bit("G-EH 5: EH_EN set -> V_EH delivering (field present)",
                     to_X01(veh_active), '1');
        sb.check_true("G-EH 6: bench-supplied harvested current is advertised",
                      veh_avail_ua = 250);
        mem_read(DS_UW, DS_UR, 16#2002#, 1, rd, okv);
        sb.check_slv("G-EH 7: EH_CTRL_Dyn = 0Fh (EH_EN + EH_ON + FIELD_ON + VCC_ON)",
                     rd(0), x"0F");

        -- Remove the field: V_EH goes High-Z but EH_EN stays set.
        rf_field <= '0';
        wait for 400 us;                    -- let the field-change pulse expire
        sb.check_bit("G-EH 8: no RF field -> V_EH High-Z again", to_X01(veh_active), '0');
        sb.check_bit("G-EH 9: EH_EN is unaffected by the field going away",
                     to_X01(eh_enabled), '1');
        mem_read(DS_UW, DS_UR, 16#2002#, 1, rd, okv);
        sb.check_slv("G-EH 10: EH_CTRL_Dyn = 0Bh (EH_EN + EH_ON + VCC_ON, FIELD_ON clear)",
                     rd(0), x"0B");

        -- EH_MODE = 0 forces EH_EN to 1.
        wd(0) := x"00";
        mem_write(DS_UW, 16#2002#, wd, 1, okv, nk);   -- clear EH_EN first
        wait for 1 us;
        sb.check_bit("G-EH 11: EH_EN cleared through EH_CTRL_Dyn", to_X01(eh_enabled), '0');
        wd(0) := x"00";
        mem_write(DS_SW, 16#0002#, wd, 1, okv, nk);   -- EH_MODE = 0 (needs the session)
        sb.check_true("G-EH 12: EH_MODE write is ACKed", okv);
        poll_ready(DS_SW, 2000, tries, okv);
        sb.check_true("G-EH 13: EH_MODE write cycle completes", okv);
        sb.check_bit("G-EH 14: writing 0 into EH_MODE forces EH_EN to 1",
                     to_X01(eh_enabled), '1');

        -- A fresh boot now enables EH straight away.
        resetn <= '0';
        wait for 2 us;
        resetn <= '1';
        wait for 2 us;
        sb.check_bit("G-EH 15: after POR with EH_MODE = 0, EH_EN is set at boot",
                     to_X01(eh_enabled), '1');
        sb.check_bit("G-EH 16: the security session is closed again by POR",
                     to_X01(obs_i2c_sso), '0');
        mem_read(DS_UW, DS_UR, 16#0100#, 1, rd, okv);
        sb.check_slv("G-EE/POR: user EEPROM is nonvolatile across POR", rd(0), x"5A");

        ------------------------------------------------------------------
        -- G-NEG: mandatory negative control, LAST: exactly ONE deliberately wrong expected value, so a healthy run ends with sb.errors = 1.
        report "=== GROUP G-NEG: NEGATIVE CONTROL ===" severity note;
        mem_read(DS_SW, DS_SR, 16#0017#, 1, rd, okv);
        if NEGCTRL = 1 then
            sb.check_slv("NEGATIVE CONTROL: wrong expected IC_REF (must FAIL)", rd(0), x"00");
        else
            report "NEGCTRL=0: negative control SKIPPED (the run then proves nothing)"
                severity warning;
        end if;

        ------------------------------------------------------------------
        -- Final verdict: sb.errors must be EXACTLY 1, the negative control.
        wait for 2 us;
        sb.report_summary("ST25DV MODEL TB");

        if sb.errors = 1 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   ST25DV_MODEL_TB PASS (1 expected negative-control failure)" & LF &
                "    ##   ST25DV MODEL TB:  ALL CHECKS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   ST25DV_MODEL_TB FAIL (expected exactly 1 failure [negative control], got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        tb_done <= true;
        stop;
        wait;
    end process stim;

end architecture sim;
