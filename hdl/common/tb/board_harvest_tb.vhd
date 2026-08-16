-------------------------------------------------------------------------------
-- board_harvest_tb.vhd
-- Board-level bench for the harvested field-power / NFC path: field on, NTAG 5 harvests, the supercap charges, PGOOD (pin 69, P6.7) releases the boot gate, the chip cold-boots the harvested ROM path and serves an NFC Type-2 READ, then field off, re-hold, field back, cold re-boot.
-- DUT is the wound-configuration MCU booting from the real shared ROM image; no firmware is downloaded on the harvested path, only the bootrom's harvested branch runs.
-- Every check is EXTERNALLY OBSERVABLE (package pins, board-model ports, tb edge counters) because VHDL hierarchical references are unavailable under -V200X.
-- The bench does NOT claim NFC service is lost during brownout: the boot gate folds only the hart resets and VDD collapse is not modelled, so the re-hold is proven by the cold-re-boot PWRSTS payload delta instead.
-- NEGCTRL true selects the disarmed-board negative control; a bare boolean generic override is silently ignored by xmelab (EVBBOL warning only), so the literal must be QUOTED in the -generic argument.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.nfc_bfm_pkg.all;
use work.tb_defs.all;

entity board_harvest_tb is
    generic (
        -- 29-char fixed-width TEST_FILE as in riscv_tb; only the NEGCTRL SPI-boot leg consumes it.
        TEST_FILE : string(1 to 29) := "../rcf/xxxxrv32ui-p-shpwr.rcf";

        -- false = the full harvested run, true = the disarmed-board negative control.
        -- Must be overridden with a QUOTED literal or xmelab silently ignores it.
        NEGCTRL : boolean := false
    );
end entity board_harvest_tb;

architecture sim of board_harvest_tb is

    ---------------------------------------------------------------------
    -- DUT component: the wound-configuration MCU
    ---------------------------------------------------------------------
    component MCU
        port (
            resetn_in  : in  std_logic;
            resetn_out : out std_logic;
            resetn_dir : out std_logic;
            resetn_ren : out std_logic;

            prt1_in  : in  std_logic_vector(7 downto 0);
            prt1_out : out std_logic_vector(7 downto 0);
            prt1_dir : out std_logic_vector(7 downto 0);
            prt1_ren : out std_logic_vector(7 downto 0);

            prt2_in  : in  std_logic_vector(7 downto 0);
            prt2_out : out std_logic_vector(7 downto 0);
            prt2_dir : out std_logic_vector(7 downto 0);
            prt2_ren : out std_logic_vector(7 downto 0);

            prt3_in  : in  std_logic_vector(7 downto 0);
            prt3_out : out std_logic_vector(7 downto 0);
            prt3_dir : out std_logic_vector(7 downto 0);
            prt3_ren : out std_logic_vector(7 downto 0);

            prt4_in  : in  std_logic_vector(7 downto 0);
            prt4_out : out std_logic_vector(7 downto 0);
            prt4_dir : out std_logic_vector(7 downto 0);
            prt4_ren : out std_logic_vector(7 downto 0);

            prt5_in  : in  std_logic_vector(7 downto 0);
            prt5_out : out std_logic_vector(7 downto 0);
            prt5_dir : out std_logic_vector(7 downto 0);
            prt5_ren : out std_logic_vector(7 downto 0);

            prt6_in  : in  std_logic_vector(7 downto 0);
            prt6_out : out std_logic_vector(7 downto 0);
            prt6_dir : out std_logic_vector(7 downto 0);
            prt6_ren : out std_logic_vector(7 downto 0);

            a0   : out std_logic_vector(31 downto 0);
            a0_1 : out std_logic_vector(31 downto 0);
            a0_2 : out std_logic_vector(31 downto 0);
            a0_3 : out std_logic_vector(31 downto 0)
        );
    end component;

    component serial_flash is
        generic (
            ProgramAddress       : natural;
            RamSizeBytes         : natural;
            SwapBytesIn32BitWord : boolean
        );
        port (
            CSb           : in  std_logic;
            SPCLK         : in  std_logic;
            MOSI          : in  std_logic;
            MISO          : out std_logic;
            mem_reset     : in  std_logic;
            awake         : out std_logic;
            RAM_FILE_PATH : in  string
        );
    end component;

    ---------------------------------------------------------------------
    -- GPIO0 pin numbering, mirroring MemoryMap.vhd's pnum_gpio0_*, kept local so this bench need not use work.MemoryMap.
    ---------------------------------------------------------------------
    constant P_CS_FLASH : natural := 0;
    constant P_MISO     : natural := 1;
    constant P_MOSI     : natural := 2;
    constant P_SPI_CLK  : natural := 3;
    constant P_LFXT     : natural := 4;
    constant P_HFXT     : natural := 5;
    constant P_BOOT     : natural := 7;

    ---------------------------------------------------------------------
    -- clocks / reset
    ---------------------------------------------------------------------
    constant CLK_PERIOD      : time := 40 ns;
    constant clk_hfxt_period : time := (1.0 sec) / 24000000;   -- 24 MHz
    constant clk_lfxt_period : time := (1.0 sec) / 32768;      -- 32.768 kHz

    signal clk_hfxt : std_logic := '0';
    signal clk_lfxt : std_logic := '0';
    signal resetn   : std_logic := '0';

    ---------------------------------------------------------------------
    -- pins
    ---------------------------------------------------------------------
    signal resetn_pad : std_logic;
    signal resetn_in, resetn_out, resetn_dir, resetn_ren : std_logic;

    signal prt1, prt2, prt3, prt4 : std_logic_vector(7 downto 0);

    signal prt1_in, prt1_out, prt1_dir, prt1_ren : std_logic_vector(7 downto 0);
    signal prt2_in, prt2_out, prt2_dir, prt2_ren : std_logic_vector(7 downto 0);
    signal prt3_in, prt3_out, prt3_dir, prt3_ren : std_logic_vector(7 downto 0);
    signal prt4_in, prt4_out, prt4_dir, prt4_ren : std_logic_vector(7 downto 0);
    signal prt5_in, prt5_out, prt5_dir, prt5_ren : std_logic_vector(7 downto 0);
    signal prt6_in, prt6_out, prt6_dir, prt6_ren : std_logic_vector(7 downto 0);

    signal a0, a0_1, a0_2, a0_3 : std_logic_vector(31 downto 0);

    -- riscv_tb's pass/fail contract labels (a0 watch words)
    constant PASS_LABEL : std_logic_vector(31 downto 0) := x"CAFEBABE";
    constant FAIL_LABEL : std_logic_vector(31 downto 0) := x"DEADBEEF";

    ---------------------------------------------------------------------
    -- SPI serial flash (only the NEGCTRL leg boots from it)
    ---------------------------------------------------------------------
    signal spi_clk, spi_cs, spi_mosi, spi_miso : std_logic;
    signal flash_awake     : std_logic := '0';
    signal cs_flash        : std_logic;
    signal boot_done_flag  : std_logic;
    signal ram_file_name   : string(1 to 29) := TEST_FILE;
    -- board-level observable: how many times the flash chip select has fallen.
    signal cs_fall_cnt     : natural := 0;

    ---------------------------------------------------------------------
    -- THE FIELD: one tb signal feeds the reader model, the tag's rf_field and the chip's field_detect pin.
    ---------------------------------------------------------------------
    signal field_on : std_logic := '0';

    ---------------------------------------------------------------------
    -- NTAG 5 (I2C slave on the P4 bus) + the tb-side factory I2C master
    ---------------------------------------------------------------------
    constant TQ_I2C   : time := 250 ns;                          -- quarter bit: compressed 1 MHz factory I2C
    constant T_PROG   : time := 20 us;                           -- compressed EEPROM programming cycle
    constant DEV_ADDR : std_logic_vector(6 downto 0) := "1010100";  -- 54h

    type u8_arr is array (natural range <>) of std_logic_vector(7 downto 0);

    signal m_sda_oe, m_scl_oe : std_logic := '0';    -- factory master drive
    signal d_sda_out, d_sda_oe : std_logic;          -- ntag5 drive
    signal d_scl_out, d_scl_oe : std_logic;
    signal d_ed_oe             : std_logic;
    signal ed_n                : std_logic;

    signal eh_enabled, eh_vout_on, eh_vout_rfu_v : std_logic;
    signal eh_vout_mv : natural;
    signal eh_iout_ua : natural;

    signal obs_variant_ok  : std_logic;
    signal obs_addr_acked  : std_logic;
    signal obs_last_block  : natural;
    signal obs_nack_count  : natural;
    signal obs_txn_count_i : natural;
    signal obs_last_addr   : std_logic_vector(6 downto 0);
    signal obs_last_rnw    : std_logic;
    signal obs_wbyte_count : natural;
    signal obs_rbyte_count : natural;
    signal obs_sram_ready  : std_logic;
    signal obs_pt_dir      : std_logic;
    signal obs_eep_busy    : std_logic;

    ---------------------------------------------------------------------
    -- harvester / supercap / supervisor
    ---------------------------------------------------------------------
    signal vin_mv, iin_ua           : natural := 0;
    signal load_ua, load_aux_ua     : natural := 0;
    signal vstor_mv                 : natural;
    signal vout_mv, vout_aux_mv     : natural;
    signal vbat_ok                  : std_logic;
    signal vbat_ok_mv               : natural;
    signal cold_start, charging     : std_logic;
    signal ov, uv, ilim             : std_logic;
    signal e_in_uj, e_load_uj, e_stor_uj : natural;

    signal pgood      : std_logic;
    signal pg_rise    : natural := 0;
    signal pg_fall    : natural := 0;
    signal hart_awake : std_logic := '0';

    ---------------------------------------------------------------------
    -- NFC reader (PCD) model
    ---------------------------------------------------------------------
    constant RF_HALF : time := 25 ns;   -- reader's compressed carrier-derived clock
    -- NFCxTIM reset profile (ETU=128, SUBCDIV=8): the bootrom never programs TIM, so the reader model must match it.
    constant C_ETU     : natural := 128;
    constant C_HALF    : natural := 64;
    constant C_SUBCDIV : natural := 8;
    constant C_PAUSE   : natural := 24;

    -- ROM-provisioned tag identity
    constant UID_W : std_logic_vector(31 downto 0) := x"C0FFEE01";
    constant UID0  : std_logic_vector(7 downto 0)  := x"01";
    constant UID1  : std_logic_vector(7 downto 0)  := x"EE";
    constant UID2  : std_logic_vector(7 downto 0)  := x"FF";
    constant UID3  : std_logic_vector(7 downto 0)  := x"C0";
    constant BCCV  : std_logic_vector(7 downto 0)  := UID0 xor UID1 xor UID2 xor UID3;
    constant SAKV  : std_logic_vector(7 downto 0)  := x"00";

    -- PWRSTS snapshot bytes the bootrom publishes as NFC payload byte 2, first boot and cold re-boot.
    constant PWRSTS_BOOT1 : std_logic_vector(7 downto 0) := x"2D";
    constant PWRSTS_BOOT2 : std_logic_vector(7 downto 0) := x"2F";

    signal rf_clk_w, rf_rx_w, field_detect_w : std_logic;
    signal rf_txmod_w, rf_tx_en_w, afe_en_w  : std_logic;

    signal cfg_field          : std_logic := '0';
    signal cfg_go             : std_logic := '0';
    signal cfg_short          : boolean   := false;
    signal cfg_bytes          : nfc_byte_array(0 to NFC_MAX_BYTES - 1) := (others => (others => '0'));
    signal cfg_nbytes         : natural := 0;
    signal cfg_partial_bits   : natural := 0;
    signal cfg_append_crc     : boolean := false;
    signal cfg_corrupt_parity : boolean := false;
    signal cfg_corrupt_crc    : boolean := false;
    signal cfg_resp_parity    : boolean := true;

    signal obs_busy         : std_logic;
    signal obs_txn_count    : natural;
    signal obs_saw_response : std_logic;
    signal obs_fdt_ticks    : natural;
    signal obs_sof_ok       : std_logic;
    signal obs_nbytes       : natural;
    signal obs_bytes        : nfc_byte_array(0 to NFC_MAX_BYTES - 1);
    signal obs_nbits        : natural;
    signal obs_first_bit    : std_logic;
    signal obs_parity_ok    : std_logic;
    signal obs_crc_ok       : std_logic;

    shared variable sb : scoreboard;

    ---------------------------------------------------------------------
    -- bit-banged I2C MASTER (the board programmer, not the chip): every cell is entered and left with SCL LOW.
    --   cell order: set SDA, tq, release SCL, tq, sample, tq, pull SCL, tq
    ---------------------------------------------------------------------
    -- Park the bus: release both open-drain drivers and settle for one quarter bit.
    procedure i2c_idle(signal sdao : out std_logic;
                       signal sclo : out std_logic;
                       tq : in time) is
    begin
        sdao <= '0';
        sclo <= '0';
        wait for tq;
    end procedure;

    -- START condition: release both lines, pull SDA low while SCL is still high, then pull SCL low.
    procedure i2c_start(signal sdao : out std_logic;
                        signal sclo : out std_logic;
                        tq : in time) is
    begin
        sdao <= '0'; sclo <= '0'; wait for tq;
        sdao <= '1';               wait for tq;
        sclo <= '1';               wait for tq;
    end procedure;

    -- STOP condition: hold SDA low, release SCL, then release SDA while SCL is high, and leave the bus idle.
    procedure i2c_stop(signal sdao : out std_logic;
                       signal sclo : out std_logic;
                       tq : in time) is
    begin
        sdao <= '1'; wait for tq;
        sclo <= '0'; wait for tq;
        sdao <= '0'; wait for tq;
                     wait for tq;
    end procedure;

    -- Write one byte MSB first, then sample the ninth cell; ack is true when the slave pulled SDA low.
    procedure i2c_wbyte(signal sdao : out std_logic;
                        signal sclo : out std_logic;
                        signal sdai : in  std_logic;
                        tq   : in  time;
                        b    : in  std_logic_vector(7 downto 0);
                        ack  : out boolean) is
    begin
        for i in 7 downto 0 loop
            if b(i) = '0' then sdao <= '1'; else sdao <= '0'; end if;
            wait for tq;
            sclo <= '0'; wait for tq;
                         wait for tq;
            sclo <= '1'; wait for tq;
        end loop;
        sdao <= '0';    wait for tq;
        sclo <= '0';    wait for tq;
        ack := (to_X01(sdai) = '0');
                        wait for tq;
        sclo <= '1';    wait for tq;
    end procedure;

    -- Read one byte MSB first, then drive ACK when ack is true or leave the line released for a NACK.
    procedure i2c_rbyte(signal sdao : out std_logic;
                        signal sclo : out std_logic;
                        signal sdai : in  std_logic;
                        tq   : in  time;
                        ack  : in  boolean;
                        b    : out std_logic_vector(7 downto 0)) is
        variable v : std_logic_vector(7 downto 0) := (others => '0');
    begin
        sdao <= '0';
        for i in 7 downto 0 loop
            wait for tq;
            sclo <= '0'; wait for tq;
            v(i) := to_X01(sdai);
                         wait for tq;
            sclo <= '1'; wait for tq;
        end loop;
        if ack then sdao <= '1'; else sdao <= '0'; end if;
        wait for tq;
        sclo <= '0'; wait for tq;
                     wait for tq;
        sclo <= '1'; wait for tq;
        sdao <= '0';
        b := v;
    end procedure;

    -- One write frame: START, the device address with the write bit, then every data byte, then STOP.
    -- nack_idx returns the index of the first byte the slave did not ACK, or -1 when the whole frame was ACKed.
    procedure i2c_write_frame(signal sdao : out std_logic;
                              signal sclo : out std_logic;
                              signal sdai : in  std_logic;
                              tq       : in  time;
                              data     : in  u8_arr;
                              addr_ack : out boolean;
                              nack_idx : out integer) is
        variable a  : boolean;
        variable ni : integer := -1;
    begin
        i2c_start(sdao, sclo, tq);
        i2c_wbyte(sdao, sclo, sdai, tq, DEV_ADDR & '0', a);
        addr_ack := a;
        if a then
            for k in data'range loop
                i2c_wbyte(sdao, sclo, sdai, tq, data(k), a);
                if not a then
                    ni := k;
                    exit;
                end if;
            end loop;
        end if;
        i2c_stop(sdao, sclo, tq);
        nack_idx := ni;
    end procedure;

    -- One read frame: START, the device address with the read bit, then n bytes ACKed except the last, then STOP.
    procedure i2c_read_frame(signal sdao : out std_logic;
                             signal sclo : out std_logic;
                             signal sdai : in  std_logic;
                             tq       : in  time;
                             n        : in  natural;
                             addr_ack : out boolean;
                             d        : out u8_arr) is
        variable a : boolean;
        variable b : std_logic_vector(7 downto 0);
    begin
        i2c_start(sdao, sclo, tq);
        i2c_wbyte(sdao, sclo, sdai, tq, DEV_ADDR & '1', a);
        addr_ack := a;
        if a then
            for k in 0 to n - 1 loop
                i2c_rbyte(sdao, sclo, sdai, tq, (k < n - 1), b);
                d(k) := b;
            end loop;
        end if;
        i2c_stop(sdao, sclo, tq);
    end procedure;

    -- High byte of an NTAG 5 block address (the BL_AD1 byte of a frame).
    function blk_hi(blk : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(blk / 256, 8));
    end function;

    -- Low byte of an NTAG 5 block address (the BL_AD0 byte of a frame).
    function blk_lo(blk : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(blk mod 256, 8));
    end function;

    -- Widen a natural to 16 bits so plain numbers can go through the scoreboard's check_slv.
    function nat16(v : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(v, 16));
    end function;

begin

    ---------------------------------------------------------------------
    -- clocks
    ---------------------------------------------------------------------
    -- 24 MHz crystal oscillator, wired onto GPIO0 P1.5 below.
    ProcClkHFXT : process
    begin
        clk_hfxt <= '0';
        wait for clk_hfxt_period / 2;
        clk_hfxt <= '1';
        wait for clk_hfxt_period / 2;
    end process;

    -- 32.768 kHz crystal oscillator, wired onto GPIO0 P1.4 below.
    ProcClkLFXT : process
    begin
        clk_lfxt <= '0';
        wait for clk_lfxt_period / 2;
        clk_lfxt <= '1';
        wait for clk_lfxt_period / 2;
    end process;

    ---------------------------------------------------------------------
    -- DUT
    ---------------------------------------------------------------------
    dut : MCU
        port map (
            resetn_in  => resetn_in,
            resetn_out => resetn_out,
            resetn_dir => resetn_dir,
            resetn_ren => resetn_ren,

            prt1_in => prt1_in, prt1_out => prt1_out,
            prt1_dir => prt1_dir, prt1_ren => prt1_ren,
            prt2_in => prt2_in, prt2_out => prt2_out,
            prt2_dir => prt2_dir, prt2_ren => prt2_ren,
            prt3_in => prt3_in, prt3_out => prt3_out,
            prt3_dir => prt3_dir, prt3_ren => prt3_ren,
            prt4_in => prt4_in, prt4_out => prt4_out,
            prt4_dir => prt4_dir, prt4_ren => prt4_ren,
            prt5_in => prt5_in, prt5_out => prt5_out,
            prt5_dir => prt5_dir, prt5_ren => prt5_ren,
            prt6_in => prt6_in, prt6_out => prt6_out,
            prt6_dir => prt6_dir, prt6_ren => prt6_ren,

            a0 => a0, a0_1 => a0_1, a0_2 => a0_2, a0_3 => a0_3
        );

    ---------------------------------------------------------------------
    -- Pads, identical to riscv_tb: reset, P1 = SPI flash plus crystals, P2/P3 unused here, P4 = the I2C0 home pads the NTAG 5 hangs on.
    ---------------------------------------------------------------------
    reset_pad : entity work.PDUW16SDGZ_G
        port map (I => resetn_out, OEN => resetn_dir, REN => resetn_ren,
                  PAD => resetn_pad, C => resetn_in);
    resetn_pad <= resetn;

    pad_prt1_gen : for i in 7 downto 0 generate
        pad_p1 : entity work.PDUW16SDGZ_G
            port map (I => prt1_out(i), OEN => prt1_dir(i), REN => prt1_ren(i),
                      PAD => prt1(i), C => prt1_in(i));
    end generate;

    pad_prt2_gen : for i in 7 downto 0 generate
        pad_p2 : entity work.PDUW16SDGZ_G
            port map (I => prt2_out(i), OEN => prt2_dir(i), REN => prt2_ren(i),
                      PAD => prt2(i), C => prt2_in(i));
    end generate;

    pad_prt3_gen : for i in 7 downto 0 generate
        pad_p3 : entity work.PDUW16SDGZ_G
            port map (I => prt3_out(i), OEN => prt3_dir(i), REN => prt3_ren(i),
                      PAD => prt3(i), C => prt3_in(i));
    end generate;

    pad_prt4_gen : for i in 7 downto 0 generate
        pad_p4 : entity work.PDUW16SDGZ_G
            port map (I => prt4_out(i), OEN => prt4_dir(i), REN => prt4_ren(i),
                      PAD => prt4(i), C => prt4_in(i));
    end generate;

    -- crystals into GPIO0
    prt1(P_HFXT) <= clk_hfxt;
    prt1(P_LFXT) <= clk_lfxt;
    -- boot-mode pin, as riscv_tb ('1' = boot from flash)
    prt1(P_BOOT) <= '1' when boot_done_flag = '0' else 'Z';
    prt1(P_MISO) <= spi_miso when flash_awake = '1' else 'Z';

    -- OW0 DQ bench level: weak 'L', same as riscv_tb.
    prt4(7) <= 'L';

    ---------------------------------------------------------------------
    -- SPI serial flash
    ---------------------------------------------------------------------
    spi_clk  <= prt1(P_SPI_CLK);
    spi_cs   <= prt1(P_CS_FLASH);
    spi_mosi <= prt1(P_MOSI);
    cs_flash <= spi_cs when boot_done_flag = '0' else '1';

    -- Boot-done latch as in riscv_tb; serial_flash's awake only falls on a deep-power-down opcode the bootrom never sends, so this flag stays 0 in practice.
    boot_done_proc : process(resetn, flash_awake)
    begin
        if resetn = '0' then
            boot_done_flag <= '0';
        elsif falling_edge(flash_awake) then
            boot_done_flag <= '1';
        end if;
    end process;

    spi_slave_flash : serial_flash
        generic map (
            ProgramAddress       => 16#0000#,
            RamSizeBytes         => 16#8100#,
            SwapBytesIn32BitWord => false
        )
        port map (
            CSb           => cs_flash,
            SPCLK         => spi_clk,
            MOSI          => spi_mosi,
            MISO          => spi_miso,
            mem_reset     => not resetn,
            awake         => flash_awake,
            RAM_FILE_PATH => ram_file_name
        );

    -- Board observable: a falling flash chip select means hart 0 is running the SPI boot path, which must never happen while the boot gate holds.
    -- Anything that is not a hard '0' counts as deselected, so the pad's weak and high-Z idle levels cannot inflate the count.
    cs_mon : process(cs_flash)
        variable prev : std_logic := '1';
    begin
        if to_X01(cs_flash) = '0' then
            if prev /= '0' then
                cs_fall_cnt <= cs_fall_cnt + 1;
            end if;
            prev := '0';
        else
            prev := '1';
        end if;
    end process;

    ---------------------------------------------------------------------
    -- P4 open-drain I2C0 bus: weak 'H' idle, wired-AND of the factory master and the NTAG 5.
    -- The chip is a silent third party here: no firmware runs on the harvested path, so its pads stay inputs.
    ---------------------------------------------------------------------
    prt4(0) <= '0' when (m_sda_oe = '1') or (d_sda_oe = '1' and d_sda_out = '0')
               else 'H';
    prt4(1) <= '0' when (m_scl_oe = '1') or (d_scl_oe = '1' and d_scl_out = '0')
               else 'H';
    ed_n    <= '0' when d_ed_oe = '1' else 'H';

    ntag5 : entity work.ntag5_model
        generic map (
            VARIANT          => "NTP5332",
            I2C_ADDR         => DEV_ADDR,
            EEPROM_PROG_TIME => T_PROG
        )
        port map (
            scl     => prt4(1),
            sda_in  => prt4(0),
            sda_out => d_sda_out,
            sda_oe  => d_sda_oe,
            scl_out => d_scl_out,
            scl_oe  => d_scl_oe,
            ed_n_oe => d_ed_oe,

            rf_field       => field_on,
            rf_power_ok    => field_on,
            rf_write_sram  => '0',
            rf_read_sram   => '0',
            rf_data        => x"00",
            rf_sram_len    => 0,
            rf_disable_i2c => '0',

            eh_enabled    => eh_enabled,
            eh_vout_on    => eh_vout_on,
            eh_vout_mv    => eh_vout_mv,
            eh_iout_ua    => eh_iout_ua,
            eh_vout_rfu_v => eh_vout_rfu_v,

            obs_variant_ok      => obs_variant_ok,
            obs_txn_count       => obs_txn_count_i,
            obs_addr_acked      => obs_addr_acked,
            obs_last_addr       => obs_last_addr,
            obs_last_rnw        => obs_last_rnw,
            obs_last_block      => obs_last_block,
            obs_nack_count      => obs_nack_count,
            obs_wbyte_count     => obs_wbyte_count,
            obs_rbyte_count     => obs_rbyte_count,
            obs_sram_data_ready => obs_sram_ready,
            obs_pt_dir          => obs_pt_dir,
            obs_eep_busy        => obs_eep_busy
        );

    ---------------------------------------------------------------------
    -- The board supply chain: harvester, supercap, two rails, supervisor, then PGOOD on pin 69.
    -- The tag's harvested output feeds the PMIC input directly; the real board's rectifier and input cap are not modelled.
    ---------------------------------------------------------------------
    vin_mv <= eh_vout_mv when to_X01(eh_vout_on) = '1' else 0;
    iin_ua <= eh_iout_ua when to_X01(eh_vout_on) = '1' else 0;

    load_ua     <= 200;                                    -- rail A, 3.3 V I/O keep-alive, uA
    load_aux_ua <= 12300 when hart_awake = '1' else 5450;  -- rail B, 1.0 V core, uA: hart 0 awake vs parked

    pmic : entity work.harvest_supply_model
        generic map (
            TICK_PERIOD => 1 us,     -- small explicit-Euler step, needed at this compressed capacitance
            CAP_UF      => 4.7,      -- stands in for the 1 mF supercap: ~213x time compression, so only ordering, edge counts and threshold crossings are meaningful
            V_INIT_MV   => 0,
            VOUT_A_MV   => 3300,     -- rail A: I/O, bq25570 buck
            VOUT_B_MV   => 1000,     -- rail B: core, companion switcher
            AUX_IS_LDO  => false
        )
        port map (
            enable      => '1',
            vout_en     => '1',
            vin_mv      => vin_mv,
            iin_ua      => iin_ua,
            load_ua     => load_ua,
            load_aux_ua => load_aux_ua,
            vstor_mv    => vstor_mv,
            vout_mv     => vout_mv,
            vout_aux_mv => vout_aux_mv,
            vbat_ok     => vbat_ok,
            vbat_ok_mv  => vbat_ok_mv,
            cold_start  => cold_start,
            charging    => charging,
            ov          => ov,
            uv          => uv,
            ilim        => ilim,
            e_in_uj     => e_in_uj,
            e_load_uj   => e_load_uj,
            e_stor_uj   => e_stor_uj
        );

    supervisor : entity work.supply_supervisor
        generic map (
            V_RISE_MV    => 2000,
            V_HYST_MV    => 100,
            T_ASSERT     => 0 ns,
            T_DEASSERT   => 0 ns,
            VNOISE_MV    => 20,
            NOISE_PERIOD => 10 us,
            ACTIVE_HIGH  => true
        )
        port map (
            vsense_mv => vbat_ok_mv,
            pgood     => pgood
        );

    -- PGOOD edge counters. These two counts carry the whole hold, brownout and re-boot verdict.
    pg_mon : process(pgood)
    begin
        if rising_edge(pgood) then
            pg_rise <= pg_rise + 1;
        elsif falling_edge(pgood) then
            pg_fall <= pg_fall + 1;
        end if;
    end process;

    -- hart 0 counts as awake from the PGOOD release until the harvested boot arms NFC0 (afe_en rises).
    -- On the cold re-boot afe_en is already high, so the awake rate keeps being charged: pessimistic, and the harvester covers it with the field on.
    awake_gen : if not NEGCTRL generate
        awake_proc : process(pgood, afe_en_w)
        begin
            if rising_edge(pgood) then
                hart_awake <= '1';
            end if;
            if rising_edge(afe_en_w) then
                hart_awake <= '0';
            end if;
        end process;
    end generate;
    -- The negative-control leg boots normally off flash, so it is awake throughout.
    awake_neg_gen : if NEGCTRL generate
        hart_awake <= '1';
    end generate;

    ---------------------------------------------------------------------
    -- NFC reader (PCD)
    ---------------------------------------------------------------------
    reader : entity work.nfc_reader_model
        generic map ( RF_HALF => RF_HALF )
        port map (
            rf_clk       => rf_clk_w,
            rf_rx        => rf_rx_w,
            field_detect => field_detect_w,
            rf_txmod     => rf_txmod_w,
            rf_tx_en     => rf_tx_en_w,
            cfg_field          => cfg_field,
            cfg_go             => cfg_go,
            cfg_short          => cfg_short,
            cfg_bytes          => cfg_bytes,
            cfg_nbytes         => cfg_nbytes,
            cfg_partial_bits   => cfg_partial_bits,
            cfg_append_crc     => cfg_append_crc,
            cfg_corrupt_parity => cfg_corrupt_parity,
            cfg_corrupt_crc    => cfg_corrupt_crc,
            cfg_resp_parity    => cfg_resp_parity,
            cfg_etu            => C_ETU,
            cfg_half           => C_HALF,
            cfg_subcdiv        => C_SUBCDIV,
            cfg_pause          => C_PAUSE,
            obs_busy         => obs_busy,
            obs_txn_count    => obs_txn_count,
            obs_saw_response => obs_saw_response,
            obs_fdt_ticks    => obs_fdt_ticks,
            obs_sof_ok       => obs_sof_ok,
            obs_nbytes       => obs_nbytes,
            obs_bytes        => obs_bytes,
            obs_nbits        => obs_nbits,
            obs_first_bit    => obs_first_bit,
            obs_parity_ok    => obs_parity_ok,
            obs_crc_ok       => obs_crc_ok
        );

    -- the field the reader radiates IS the field the tag harvests
    cfg_field <= field_on;

    ---------------------------------------------------------------------
    -- P6 board wiring (the field-power / NFC pin group).
    -- prt6 has no package pad model in this bench, as in riscv_tb: the port bus IS the board net.
    --   P6.7 pin 69  PGOOD         in   from supply_supervisor
    --   P6.6 pin 68  strap         in   from the board tie ('1' harvested, '0' disarmed)
    --   P6.5         afe_en        out  observed by the bench
    --   P6.4         rf_tx_en      out  to the reader
    --   P6.3         rf_txmod      out  to the reader
    --   P6.2         field_detect  in   from the reader
    --   P6.1         rf_rx         in   from the reader
    --   P6.0         rf_clk        in   from the reader
    ---------------------------------------------------------------------
    main_p6_gen : if not NEGCTRL generate
        prt6_in <= pgood & '1' & '0' & '0' & '0'
                   & field_detect_w & rf_rx_w & rf_clk_w;
    end generate;
    neg_p6_gen : if NEGCTRL generate
        -- DISARMED BOARD: strap LOW, PGOOD LOW forever.
        prt6_in <= '0' & '0' & '0' & '0' & '0'
                   & field_detect_w & rf_rx_w & rf_clk_w;
    end generate;

    rf_txmod_w <= prt6_out(3);
    rf_tx_en_w <= prt6_out(4);
    afe_en_w   <= prt6_out(5);

    -- unused ports idle
    prt5_in <= (others => '0');

    ---------------------------------------------------------------------
    -- Global backstop so a bench bug cannot hang a simulator seat.
    -- Every wait in the stimulus is individually bounded, so this must never fire.
    ---------------------------------------------------------------------
    backstop : process
    begin
        wait for 80 ms;
        report "BOARD-HARVEST: FATAL -- global backstop fired (the bench hung)"
            severity failure;
        wait;
    end process;

    ---------------------------------------------------------------------
    -- STIMULUS
    ---------------------------------------------------------------------
    stim : process
        variable aack : boolean;
        variable ni   : integer;
        variable rd1  : u8_arr(0 to 0);
        variable fr   : nfc_byte_array(0 to NFC_MAX_BYTES - 1) := (others => (others => '0'));
        variable txn_tgt : natural := 0;
        variable v_prev, v_now : natural;
        variable mono_ok  : boolean;
        variable ok       : boolean;
        variable file_exists : boolean;
        variable t_pg1, t_boot1, t_pg2 : time;
        variable exp_err : natural;
        variable i       : integer;

        -- write one 4-byte configuration/EEPROM block
        procedure wr_block(blk : in natural;
                           b0, b1, b2, b3 : in std_logic_vector(7 downto 0);
                           aa : out boolean; nn : out integer) is
            variable f : u8_arr(0 to 5);
        begin
            f(0) := blk_hi(blk); f(1) := blk_lo(blk);
            f(2) := b0; f(3) := b1; f(4) := b2; f(5) := b3;
            i2c_write_frame(m_sda_oe, m_scl_oe, prt4(0), TQ_I2C, f, aa, nn);
        end procedure;

        -- set the MEMORY read pointer (BL_AD1/BL_AD0 then STOP)
        procedure set_ptr(blk : in natural; aa : out boolean; nn : out integer) is
            variable f : u8_arr(0 to 1);
        begin
            f(0) := blk_hi(blk); f(1) := blk_lo(blk);
            i2c_write_frame(m_sda_oe, m_scl_oe, prt4(0), TQ_I2C, f, aa, nn);
        end procedure;

        -- Launch one reader transaction and block, bounded, until it ends.
        -- The budget covers the uncompressed NFCxTIM reset profile: a 16-byte AUTOREAD response is ~1.1 ms of air time at ETU=128 x 50 ns.
        procedure do_frame(short : boolean; n : natural; appcrc : boolean;
                           rparity : boolean; partial : natural) is
        begin
            cfg_short          <= short;
            cfg_nbytes         <= n;
            cfg_append_crc     <= appcrc;
            cfg_resp_parity    <= rparity;
            cfg_partial_bits   <= partial;
            cfg_corrupt_parity <= false;
            cfg_corrupt_crc    <= false;
            wait for 1 ns;
            txn_tgt := txn_tgt + 1;
            cfg_go <= '1'; wait for 2 ns; cfg_go <= '0';
            wait until obs_txn_count = txn_tgt for 6 ms;   -- bounded
            if obs_txn_count /= txn_tgt then
                report "BOARD-HARVEST: FATAL -- reader transaction " &
                       integer'image(txn_tgt) & " did not complete inside 6 ms"
                    severity failure;
            end if;
            wait for 2 us;
        end procedure;

        -- Full Type-2 sequence (REQA, anticollision, SELECT, READ) against NFC0's AUTOREAD hardware.
        -- tag names the check group; pwrsts is the PWRSTS byte this boot must have published as payload byte 2.
        procedure serve_sequence(tag : in string;
                                 pwrsts : in std_logic_vector(7 downto 0)) is
            variable f : nfc_byte_array(0 to NFC_MAX_BYTES - 1) := (others => (others => '0'));
        begin
            ----------------------------------------------------------
            -- REQA, expecting an ATQA
            ----------------------------------------------------------
            f := (others => (others => '0'));
            f(0) := x"26";
            cfg_bytes <= f;
            do_frame(true, 1, false, true, 0);
            sb.check_bit(tag & ": tag answered REQA", obs_saw_response, '1');
            sb.check_bit(tag & ": ATQA SOF ok (Manchester D)", obs_sof_ok, '1');
            sb.check_true(tag & ": ATQA is 2 bytes", obs_nbytes = 2);
            sb.check_slv(tag & ": ATQA byte0 = 0x44", obs_bytes(0), x"44");
            sb.check_slv(tag & ": ATQA byte1 = 0x00", obs_bytes(1), x"00");
            sb.check_bit(tag & ": ATQA parity ok", obs_parity_ok, '1');

            ----------------------------------------------------------
            -- anticollision (SEL=0x93, NVB=0x20), expecting UID + BCC
            ----------------------------------------------------------
            f := (others => (others => '0'));
            f(0) := x"93"; f(1) := x"20";
            cfg_bytes <= f;
            do_frame(false, 2, false, true, 0);
            sb.check_bit(tag & ": tag streamed the UID", obs_saw_response, '1');
            sb.check_true(tag & ": UID+BCC = 5 bytes", obs_nbytes = 5);
            sb.check_slv(tag & ": uid0 (ROM default 0xC0FFEE01)", obs_bytes(0), UID0);
            sb.check_slv(tag & ": uid1", obs_bytes(1), UID1);
            sb.check_slv(tag & ": uid2", obs_bytes(2), UID2);
            sb.check_slv(tag & ": uid3", obs_bytes(3), UID3);
            sb.check_slv(tag & ": BCC = uid0^uid1^uid2^uid3", obs_bytes(4), BCCV);
            sb.check_bit(tag & ": UID stream parity ok", obs_parity_ok, '1');

            ----------------------------------------------------------
            -- SELECT (NVB=0x70, UID+BCC+CRC_A), expecting a SAK
            ----------------------------------------------------------
            f := (others => (others => '0'));
            f(0) := x"93"; f(1) := x"70";
            f(2) := UID0; f(3) := UID1; f(4) := UID2; f(5) := UID3; f(6) := BCCV;
            cfg_bytes <= f;
            do_frame(false, 7, true, true, 0);
            sb.check_bit(tag & ": SELECT answered", obs_saw_response, '1');
            sb.check_true(tag & ": SAK+CRC = 3 bytes", obs_nbytes = 3);
            sb.check_slv(tag & ": SAK = 0x00", obs_bytes(0), SAKV);
            sb.check_bit(tag & ": SAK CRC_A ok", obs_crc_ok, '1');

            ----------------------------------------------------------
            -- READ block 0, expecting the ROM-provisioned status record
            ----------------------------------------------------------
            f := (others => (others => '0'));
            f(0) := x"30"; f(1) := x"00";
            cfg_bytes <= f;
            do_frame(false, 2, true, true, 0);
            sb.check_bit(tag & ": READ answered", obs_saw_response, '1');
            sb.check_true(tag & ": 16 payload bytes + CRC_A = 18", obs_nbytes = 18);
            sb.check_slv(tag & ": payload[0] = 'H' (0x48)", obs_bytes(0), x"48");
            sb.check_slv(tag & ": payload[1] = 'V' (0x56)", obs_bytes(1), x"56");
            sb.check_slv(tag & ": payload[2] = PWRSTS snapshot", obs_bytes(2), pwrsts);
            for k in 3 to 15 loop
                sb.check_slv(tag & ": payload[" & integer'image(k) &
                             "] = 0x00 (unwritten window)", obs_bytes(k), x"00");
            end loop;
            sb.check_bit(tag & ": READ response CRC_A ok", obs_crc_ok, '1');
            sb.check_bit(tag & ": READ response parity ok", obs_parity_ok, '1');
        end procedure;

    begin
        report "=== board_harvest_tb: DP-S3 composed board bench ===" severity note;
        report "=== leg: NEGCTRL = " & boolean'image(NEGCTRL) & " ===" severity note;

        m_sda_oe <= '0';
        m_scl_oe <= '0';
        field_on <= '0';

        check_file_exists(TEST_FILE, file_exists);
        if not file_exists then
            report "BOARD-HARVEST: FATAL -- test file not found: " & TEST_FILE
                severity failure;
        end if;

        -- riscv_tb's reset ritual (double reset around the flash image load)
        resetn <= '0';
        wait for 1 * CLK_PERIOD;
        resetn <= '1';
        wait for 5 * CLK_PERIOD;
        ram_file_name <= TEST_FILE;
        wait for CLK_PERIOD;
        resetn <= '0';
        wait for 2.5 * CLK_PERIOD;
        resetn <= '1';
        wait for CLK_PERIOD;

        if NEGCTRL then
            ------------------------------------------------------------
            -- GROUP-NEG: the disarmed board, strap LOW and PGOOD low forever, so pwr_ctrl's gate is never armed and the chip must boot NORMALLY off the SPI flash.
            -- This is the control for G-HOLD: it proves the hold there is strap-driven and not just a reset the bench forgot to release.
            ------------------------------------------------------------
            report "=== GROUP-NEG: NEGATIVE CONTROL (disarmed board) ===" severity note;
            sb.check_bit("GROUP-NEG: PGOOD low (no harvester)", pgood, '0');

            -- Budget: hart 0 zeroes the 0x10000-0x107FF mailbox region (512 shared writes, ~600 us at the reset 24 MHz mclk) before it polls the strap and falls through to the SPI boot, so 5 ms is ~8x the time to the first chip select.
            wait until cs_fall_cnt > 0 for 5 ms;
            sb.check_true("GROUP-NEG: SPI flash chip select fell (boot path runs)",
                          cs_fall_cnt > 0);
            if cs_fall_cnt = 0 then
                report "BOARD-HARVEST: FATAL -- disarmed board never accessed the " &
                       "SPI flash within 5 ms: the chip did NOT boot normally"
                    severity failure;
            end if;
            report "GROUP-NEG: first flash CS fell at " & time'image(now) severity note;

            wait until flash_awake = '1' for 5 ms;
            sb.check_bit("GROUP-NEG: flash model awake (real SPI traffic)",
                         flash_awake, '1');

            -- End state: the downloaded image runs and reaches the pass contract (a0 = 0xCAFEBABE), which needs the whole chain, SPI wake, HFREAD, segment download into the TCM, jump to 0x8200 and execution.
            -- Do not gate on boot_done_flag instead: serial_flash's awake bit only falls on a deep-power-down (B9h) opcode the bootrom never sends, so the flag never sets.
            wait until a0 = PASS_LABEL for 60 ms;
            if a0 /= PASS_LABEL then
                report "BOARD-HARVEST: FATAL -- disarmed board never reached the " &
                       "a0 = 0xCAFEBABE pass contract within 60 ms (a0 = " &
                       img(a0) & ", flash CS falls = " &
                       integer'image(cs_fall_cnt) & ")" severity failure;
            end if;
            report "GROUP-NEG: a0 = CAFEBABE at " & time'image(now) &
                   ", flash CS falls = " & integer'image(cs_fall_cnt) severity note;
            sb.check_slv("GROUP-NEG: downloaded image ran and PASSED (a0=CAFEBABE)",
                         a0, PASS_LABEL);

            sb.check_true("GROUP-NEG: many flash accesses (a real download)",
                          cs_fall_cnt >= 2);
            sb.check_bit("GROUP-NEG: PGOOD still low through the whole boot",
                         pgood, '0');
            sb.check_true("GROUP-NEG: PGOOD never rose", pg_rise = 0);
            sb.check_bit("GROUP-NEG: NFC0 never armed (harvested path not taken)",
                         afe_en_w, '0');
        else
            report "=== GROUP-NEG: SKIPPED (NEGCTRL = false) ===" severity note;

            ------------------------------------------------------------
            -- G-FACTORY: the board programmer (this bench's I2C master) writes the NTAG 5's EH_CONFIG so the fielded board harvests at 3.0 V / 12.5 mA.
            -- No contention: the chip is held, runs no firmware and never drives P4.
            --   EH_CONFIG (config block 103Dh byte 0):
            --     bits 6:4 EH_VOUT_I_SEL = 111b   12.5 mA    contributes 0x70
            --     bit  3   DISABLE_POWER_CHECK = 0           contributes 0x00
            --     bits 2:1 EH_VOUT_V_SEL = 10b    3.0 V      contributes 0x04
            --     bit  0   EH_ENABLE = 1                     contributes 0x01
            --                                            total 0x75
            ------------------------------------------------------------
            report "=== G-FACTORY: NTAG 5 EH provisioning over I2C ===" severity note;
            i2c_idle(m_sda_oe, m_scl_oe, TQ_I2C);
            wait for 5 us;

            sb.check_bit("G-FACTORY: NTAG 5 VARIANT recognized", obs_variant_ok, '1');
            sb.check_bit("G-FACTORY: EH disabled at delivery", eh_enabled, '0');
            sb.check_bit("G-FACTORY: EH VOUT off at delivery", eh_vout_on, '0');

            wr_block(16#103D#, x"75", x"00", x"00", x"00", aack, ni);
            sb.check_true("G-FACTORY: EH_CONFIG frame addressed", aack);
            sb.check_true("G-FACTORY: EH_CONFIG frame fully ACKed", ni = -1);
            sb.check_slv("G-FACTORY: model latched block 103Dh",
                         nat16(obs_last_block), nat16(16#103D#));
            wait for 3 * T_PROG;
            sb.check_bit("G-FACTORY: EEPROM programming cycle finished",
                         obs_eep_busy, '0');

            set_ptr(16#103D#, aack, ni);
            sb.check_true("G-FACTORY: read pointer frame fully ACKed", ni = -1);
            i2c_read_frame(m_sda_oe, m_scl_oe, prt4(0), TQ_I2C, 1, aack, rd1);
            sb.check_true("G-FACTORY: read frame addressed", aack);
            sb.check_slv("G-FACTORY: EH_CONFIG reads back 0x75", rd1(0), x"75");

            sb.check_bit("G-FACTORY: eh_enabled decoded", eh_enabled, '1');
            sb.check_slv("G-FACTORY: EH_VOUT_V_SEL = 3.0 V",
                         nat16(eh_vout_mv), nat16(3000));
            sb.check_slv("G-FACTORY: EH_VOUT_I_SEL = 12.5 mA",
                         nat16(eh_iout_ua), nat16(12500));
            sb.check_bit("G-FACTORY: EH VOUT still off (no field yet)",
                         eh_vout_on, '0');
            sb.check_true("G-FACTORY: no I2C byte was NACKed", obs_nack_count = 0);

            ------------------------------------------------------------
            -- G-HOLD: field off and strap high, so the boot gate holds
            ------------------------------------------------------------
            report "=== G-HOLD: field off, PGOOD low, chip held ===" severity note;
            wait for 50 us;
            sb.check_bit("G-HOLD: PGOOD low", pgood, '0');
            sb.check_true("G-HOLD: PGOOD never rose", pg_rise = 0);
            sb.check_true("G-HOLD: storage node still empty (< 100 mV)",
                          vstor_mv < 100);
            sb.check_slv("G-HOLD: a0 = 0 (no firmware verdict)", a0, x"00000000");
            sb.check_true("G-HOLD: SPI flash never selected (no boot)",
                          cs_fall_cnt = 0);
            sb.check_bit("G-HOLD: flash model never woken", flash_awake, '0');
            sb.check_bit("G-HOLD: NFC0 never armed (afe_en low)", afe_en_w, '0');
            sb.check_slv("G-HOLD: P6 outputs idle (GPIO5 AF never selected)",
                         prt6_out(5 downto 3), "000");

            ------------------------------------------------------------
            -- G-RAMP: the reader arrives
            ------------------------------------------------------------
            report "=== G-RAMP: field on -> harvest -> supercap charges ===" severity note;
            field_on <= '1';
            wait for 20 us;
            sb.check_bit("G-RAMP: NTAG 5 EH VOUT on (field + power ok)",
                         eh_vout_on, '1');
            sb.check_slv("G-RAMP: harvester input = 3.0 V",
                         nat16(vin_mv), nat16(3000));
            sb.check_slv("G-RAMP: harvester input = 12.5 mA",
                         nat16(iin_ua), nat16(12500));
            sb.check_bit("G-RAMP: PMIC charging", charging, '1');
            sb.check_bit("G-RAMP: cold-start circuit engaged", cold_start, '1');

            -- monotonic rise past the 2800 mV VBAT_OK rising threshold
            mono_ok := true;
            v_prev  := vstor_mv;
            i := 0;
            while vstor_mv < 2800 and i < 2000 loop
                wait for 10 us;
                v_now := vstor_mv;
                if v_now < v_prev then
                    mono_ok := false;
                end if;
                v_prev := v_now;
                i := i + 1;
            end loop;
            if vstor_mv < 2800 then
                report "BOARD-HARVEST: FATAL -- VSTOR never reached the 2800 mV " &
                       "VBAT_OK rising threshold within 20 ms (reached " &
                       integer'image(vstor_mv) & " mV)"
                    severity failure;
            end if;
            sb.check_true("G-RAMP: VSTOR rose monotonically", mono_ok);
            sb.check_true("G-RAMP: VSTOR crossed the 2800 mV VBAT_OK threshold",
                          vstor_mv >= 2800);
            sb.check_bit("G-RAMP: PMIC VBAT_OK asserted", vbat_ok, '1');
            sb.check_bit("G-RAMP: cold start finished", cold_start, '0');
            report "G-RAMP: VSTOR = " & integer'image(vstor_mv) & " mV at " &
                   time'image(now) severity note;

            ------------------------------------------------------------
            -- G-BOOT: PGOOD rises exactly once and the chip cold-boots
            ------------------------------------------------------------
            report "=== G-BOOT: PGOOD -> boot-gate release -> harvested boot ===" severity note;
            wait until pgood = '1' for 3 ms;
            if pgood /= '1' then
                report "BOARD-HARVEST: FATAL -- PGOOD did not rise within 3 ms of " &
                       "the VBAT_OK threshold crossing (vbat_ok_mv = " &
                       integer'image(vbat_ok_mv) & " mV)"
                    severity failure;
            end if;
            t_pg1 := now;
            wait for 1 ns;   -- settle: pg_mon's count lands in the next delta
            report "G-BOOT: PGOOD rose at " & time'image(t_pg1) severity note;
            sb.check_true("G-BOOT: exactly ONE PGOOD rising edge", pg_rise = 1);
            sb.check_true("G-BOOT: no PGOOD falling edge yet", pg_fall = 0);

            -- afe_en rising means the bootrom reached NFC0 provisioning, so the harts really left reset and ran the harvested branch.
            wait until afe_en_w = '1' for 5 ms;
            if afe_en_w /= '1' then
                report "BOARD-HARVEST: FATAL -- the chip never armed NFC0 within " &
                       "5 ms of PGOOD: the harvested boot did not run"
                    severity failure;
            end if;
            t_boot1 := now - t_pg1;
            report "G-BOOT: NFC0 armed " & time'image(t_boot1) & " after PGOOD"
                severity note;
            sb.check_bit("G-BOOT: NFC0 armed (afe_en high)", afe_en_w, '1');
            sb.check_true("G-BOOT: still exactly one PGOOD rising edge", pg_rise = 1);
            sb.check_true("G-BOOT: harvested boot took NO SPI flash access",
                          cs_fall_cnt = 0);
            sb.check_bit("G-BOOT: flash model still asleep", flash_awake, '0');
            -- No test firmware ran, so a0 carries neither verdict label.
            -- It is not zero either: the harvested ROM path leaves PERIPH_SYSTEM0_BASE (0x4900) in a0, a fingerprint of that path.
            sb.check_true("G-BOOT: a0 is not the PASS label (no test firmware ran)",
                          a0 /= PASS_LABEL);
            sb.check_true("G-BOOT: a0 is not the FAIL label", a0 /= FAIL_LABEL);
            sb.check_slv("G-BOOT: a0 = SYSTEM0 base (harvested ROM path residue)",
                         a0, x"00004900");
            sb.check_bit("G-BOOT: PGOOD still high", pgood, '1');

            wait for 100 us;   -- let the boot finish parking

            ------------------------------------------------------------
            -- G-SERVE: the reader collects the harvested record.
            -- Expected payload[2] is the PWRSTS byte the bootrom snapshots at its strap poll:
            --   bit0 PGOOD_LIVE  = 1  released
            --   bit1 FIELD_LIVE  = 0  GPIO5 PxAFS is still at reset, so P6.2 is AF0 and nfc0_field_detect is tied low until the harvested branch selects AF1
            --   bit2 STRAP       = 1  harvested board
            --   bit3 STRAP_VALID = 1  poll exit condition
            --   bit4 BOOT_HOLD   = 0  released
            --   bit5 RLS_LATCHED = 1  sticky since release
            --   total 0x2D
            ------------------------------------------------------------
            report "=== G-SERVE: reader <-> NFC0 AUTOREAD ===" severity note;
            serve_sequence("G-SERVE", PWRSTS_BOOT1);

            ------------------------------------------------------------
            -- G-BROWN: the reader leaves
            ------------------------------------------------------------
            report "=== G-BROWN: field off -> drain -> PGOOD falls ===" severity note;
            field_on <= '0';
            wait for 20 us;
            sb.check_bit("G-BROWN: NTAG 5 EH VOUT off", eh_vout_on, '0');
            sb.check_slv("G-BROWN: harvester input collapsed to 0 mV",
                         nat16(vin_mv), nat16(0));
            sb.check_bit("G-BROWN: PMIC no longer charging", charging, '0');
            v_prev := vstor_mv;

            wait until pgood = '0' for 5 ms;
            if pgood /= '0' then
                report "BOARD-HARVEST: FATAL -- PGOOD did not fall within 5 ms of " &
                       "field removal (vstor = " & integer'image(vstor_mv) &
                       " mV, vbat_ok_mv = " & integer'image(vbat_ok_mv) & " mV)"
                    severity failure;
            end if;
            wait for 1 ns;   -- settle: pg_mon's count lands in the next delta
            report "G-BROWN: PGOOD fell at " & time'image(now) & ", VSTOR = " &
                   integer'image(vstor_mv) & " mV" severity note;
            sb.check_true("G-BROWN: VSTOR decayed under the parked load",
                          vstor_mv < v_prev);
            sb.check_true("G-BROWN: exactly ONE PGOOD falling edge", pg_fall = 1);
            sb.check_true("G-BROWN: still exactly one PGOOD rising edge", pg_rise = 1);
            sb.check_bit("G-BROWN: PMIC VBAT_OK deasserted (below 2400 mV)",
                         vbat_ok, '0');
            sb.check_true("G-BROWN: VSTOR below the 2400 mV falling threshold",
                          vstor_mv < 2400);
            -- the chip must NOT restart on its own while held
            sb.check_true("G-BROWN: no SPI flash access during the re-hold",
                          cs_fall_cnt = 0);
            sb.check_true("G-BROWN: a0 still carries no verdict label",
                          a0 /= PASS_LABEL and a0 /= FAIL_LABEL);

            ------------------------------------------------------------
            -- G-RECOVER: the reader comes back
            ------------------------------------------------------------
            report "=== G-RECOVER: field back -> recharge -> cold re-boot ===" severity note;
            field_on <= '1';
            wait for 20 us;
            sb.check_bit("G-RECOVER: EH VOUT back on", eh_vout_on, '1');
            sb.check_bit("G-RECOVER: PMIC charging again", charging, '1');

            wait until pgood = '1' for 10 ms;
            if pgood /= '1' then
                report "BOARD-HARVEST: FATAL -- PGOOD did not rise again within " &
                       "10 ms of the field returning (vstor = " &
                       integer'image(vstor_mv) & " mV)"
                    severity failure;
            end if;
            t_pg2 := now;
            wait for 1 ns;   -- settle: pg_mon's count lands in the next delta
            report "G-RECOVER: PGOOD rose again at " & time'image(t_pg2) severity note;
            sb.check_true("G-RECOVER: exactly TWO PGOOD rising edges", pg_rise = 2);
            sb.check_true("G-RECOVER: still exactly one PGOOD falling edge",
                          pg_fall = 1);

            -- The cold re-boot runs the same ROM path, but SYSTEM0 keeps its state across the hold (the gate folds hart resets only), so mclk is still divided by 8.
            -- The mailbox-zeroing loop therefore takes ~8x the first boot: budget the bounded wait accordingly.
            wait for 10 * t_boot1 + 200 us;
            sb.check_bit("G-RECOVER: PGOOD held through the re-boot", pgood, '1');
            sb.check_true("G-RECOVER: cold re-boot took NO SPI flash access",
                          cs_fall_cnt = 0);
            sb.check_true("G-RECOVER: a0 still carries no verdict label",
                          a0 /= PASS_LABEL and a0 /= FAIL_LABEL);

            ------------------------------------------------------------
            -- The payload delta is the re-hold proof: GPIO5 is already in AF1 because the peripherals were never reset, so the strap poll now sees FIELD_LIVE = 1 and PWRSTS reads 0x2F.
            -- A changed payload is only possible if hart 0 was reset and re-ran the ROM.
            ------------------------------------------------------------
            serve_sequence("G-RECOVER", PWRSTS_BOOT2);
            sb.check_true("G-RECOVER: PWRSTS byte CHANGED vs the first boot " &
                          "(proves a genuine cold re-boot)",
                          PWRSTS_BOOT2 /= PWRSTS_BOOT1);
        end if;

        ------------------------------------------------------------------
        -- verdict
        ------------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("BOARD HARVEST TB");

        exp_err := 0;    -- both legs are real checks; no seeded failure

        if sb.errors = exp_err then
            if NEGCTRL then
                report LF & LF &
                    "    ##################################################" & LF &
                    "    ##   BOARD_HARVEST_TB PASS (NEGCTRL leg, disarmed board)" & LF &
                    "    ##   BOARD HARVEST TB:  ALL CHECKS PASSED" & LF &
                    "    ##################################################" & LF
                    severity note;
            else
                report LF & LF &
                    "    ##################################################" & LF &
                    "    ##   BOARD_HARVEST_TB PASS (main leg, harvested story)" & LF &
                    "    ##   BOARD HARVEST TB:  ALL CHECKS PASSED" & LF &
                    "    ##################################################" & LF
                    severity note;
            end if;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   BOARD_HARVEST_TB FAIL (expected exactly " &
                integer'image(exp_err) & " failure(s), got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        stop;
        wait;
    end process stim;

end architecture sim;
