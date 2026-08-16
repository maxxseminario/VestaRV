-------------------------------------------------------------------------------
-- st25r3916_model_tb.vhd
-------------------------------------------------------------------------------
-- Self-checking bench for tb/st25r3916_model.vhd, the ST25R3916 NFC AFE model.
-- The deliverable is the two-directional transparent-mode gate: RF reaches MISO only while transparent, and SPI traffic is refused while transparent; the register and command groups make the positive side credible.
-- nfc_reader_model supplies a real modified-Miller frame for the last group; it owns the ISO-14443A protocol and none of it is duplicated here.
-- SPI master is CPOL = 0 / CPHA = 1, MSB first: MOSI is presented before the rising edge (the model samples on the falling edge) and MISO is sampled at the end of the SCLK high phase.
-- MISO is a tristate pin resolved here to 'Z' when pin_miso_oe is low, so a 'Z' check is a real "the AFE is not driving" result, not X propagation.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.nfc_bfm_pkg.all;

entity st25r3916_model_tb is
    generic (
        -- Negative control: true (the default) checks one deliberately wrong expectation last, so a healthy run reports EXACTLY ONE failure; false gives a clean zero-failure run.
        -- A bare boolean generic override is silently ignored by xmelab (only a *W,EVBBOL warning), so the -gpg value for NEGCTRL must be the quoted literal \"false\" and EVBBOL must be treated as fatal.
        NEGCTRL : boolean := true
    );
end entity st25r3916_model_tb;

architecture sim of st25r3916_model_tb is

    -- SPI master bit timing
    constant TSU  : time := 5 ns;    -- MOSI setup before the rising edge
    constant THI  : time := 20 ns;   -- SCLK high phase
    constant TLO  : time := 20 ns;   -- SCLK low phase
    constant TCS  : time := 40 ns;   -- BSS lead-in / lead-out

    constant RF_HALF   : time    := 25 ns;   -- reader model's compressed rf_clk
    constant LF_HALF_C : time    := 500 ns;  -- compressed 32 kHz LF clock

    -- register addresses exercised here (ST25R3916 space A)
    constant A_IO_CONF1 : natural := 16#00#;
    constant A_OP_CTRL  : natural := 16#02#;
    constant A_MODE     : natural := 16#03#;
    constant A_ISO14443A: natural := 16#05#;
    constant A_AUX      : natural := 16#0A#;
    constant A_MASK_MAIN: natural := 16#16#;
    constant A_IRQ_MAIN : natural := 16#1A#;
    constant A_IC_ID    : natural := 16#3F#;
    constant B_CORR1    : natural := 16#0C#;   -- space B: correlator config 1

    -- ---- pins ------------------------------------------------------------
    signal bss_n : std_logic := '1';
    signal sclk  : std_logic := '0';
    signal mosi  : std_logic := '0';

    signal pin_miso    : std_logic;
    signal pin_miso_oe : std_logic;
    signal miso_net    : std_logic;

    signal pin_mcu_clk : std_logic;
    signal pin_irq     : std_logic;
    signal pin_ext_lm  : std_logic;

    -- ---- RF world --------------------------------------------------------
    signal sig_env   : std_logic;
    signal sig_field : std_logic;
    signal sig_clk   : std_logic;

    signal tb_env    : std_logic := '1';
    signal tb_field  : std_logic := '0';
    signal tb_txen   : std_logic := '0';
    signal sel_reader: std_logic := '0';

    signal rdr_env   : std_logic;
    signal rdr_field : std_logic;
    signal rdr_clk   : std_logic;

    signal loadmod    : std_logic;
    signal loadmod_en : std_logic;

    -- ---- model cfg / obs -------------------------------------------------
    signal cfg_rx_invert      : boolean := false;
    signal cfg_sclk_is_afe_en : boolean := true;
    signal cfg_irq_trigger    : std_logic := '0';
    signal cfg_irq_bits       : std_logic_vector(7 downto 0) := (others => '0');

    signal transparent_mode      : std_logic;
    signal obs_frame_count       : natural;
    signal obs_cmd_count         : natural;
    signal obs_last_cmd          : std_logic_vector(7 downto 0);
    signal obs_last_mode         : std_logic_vector(7 downto 0);
    signal obs_last_addr         : std_logic_vector(5 downto 0);
    signal obs_space_b           : std_logic;
    signal obs_reg_writes        : natural;
    signal obs_reg_reads         : natural;
    signal obs_reject_count      : natural;
    signal obs_fifo_level        : natural;
    signal obs_spi_ignored_edges : natural;
    signal obs_rf_blocked_edges  : natural;

    -- ---- reader model cfg / obs -----------------------------------------
    signal r_field  : std_logic := '0';
    signal r_go     : std_logic := '0';
    signal r_short  : boolean   := false;
    signal r_bytes  : nfc_byte_array(0 to NFC_MAX_BYTES - 1) := (others => (others => '0'));
    signal r_nbytes : natural := 0;

    signal r_busy      : std_logic;
    signal r_txn_count : natural;
    signal r_saw_resp  : std_logic;
    signal r_fdt       : natural;
    signal r_sof_ok    : std_logic;
    signal r_obs_nbytes: natural;
    signal r_obs_bytes : nfc_byte_array(0 to NFC_MAX_BYTES - 1);
    signal r_obs_nbits : natural;
    signal r_first_bit : std_logic;
    signal r_par_ok    : std_logic;
    signal r_crc_ok    : std_logic;

    -- ---- monitors --------------------------------------------------------
    signal miso_edges : natural := 0;
    signal mclk_edges : natural := 0;

    shared variable sb : scoreboard;

begin

    ---------------------------------------------------------------------------
    -- DUT: the ST25R3916 AFE model
    ---------------------------------------------------------------------------
    dut : entity work.st25r3916_model
        generic map (
            LF_HALF    => LF_HALF_C,
            FIFO_DEPTH => 64          -- real part: 512; shrunk for sim speed
        )
        port map (
            pin_bss_n   => bss_n,
            pin_sclk    => sclk,
            pin_mosi    => mosi,
            pin_miso    => pin_miso,
            pin_miso_oe => pin_miso_oe,
            pin_mcu_clk => pin_mcu_clk,
            pin_irq     => pin_irq,
            pin_ext_lm  => pin_ext_lm,

            rf_field_in    => sig_field,
            rf_env_in      => sig_env,
            rf_clk_in      => sig_clk,
            rf_loadmod_out => loadmod,
            rf_loadmod_en  => loadmod_en,
            mcu_rf_tx_en   => tb_txen,

            cfg_rx_invert      => cfg_rx_invert,
            cfg_sclk_is_afe_en => cfg_sclk_is_afe_en,
            cfg_irq_trigger    => cfg_irq_trigger,
            cfg_irq_bits       => cfg_irq_bits,

            transparent_mode      => transparent_mode,
            obs_frame_count       => obs_frame_count,
            obs_cmd_count         => obs_cmd_count,
            obs_last_cmd          => obs_last_cmd,
            obs_last_mode         => obs_last_mode,
            obs_last_addr         => obs_last_addr,
            obs_space_b           => obs_space_b,
            obs_reg_writes        => obs_reg_writes,
            obs_reg_reads         => obs_reg_reads,
            obs_reject_count      => obs_reject_count,
            obs_fifo_level        => obs_fifo_level,
            obs_spi_ignored_edges => obs_spi_ignored_edges,
            obs_rf_blocked_edges  => obs_rf_blocked_edges
        );

    ---------------------------------------------------------------------------
    -- The RF world: nfc_reader_model is the ISO-14443A reader, driven as stimulus only.
    ---------------------------------------------------------------------------
    rdr : entity work.nfc_reader_model
        generic map (RF_HALF => RF_HALF)
        port map (
            rf_clk       => rdr_clk,
            rf_rx        => rdr_env,
            field_detect => rdr_field,
            rf_txmod     => loadmod,
            rf_tx_en     => loadmod_en,

            cfg_field          => r_field,
            cfg_go             => r_go,
            cfg_short          => r_short,
            cfg_bytes          => r_bytes,
            cfg_nbytes         => r_nbytes,
            cfg_partial_bits   => 0,
            cfg_append_crc     => false,
            cfg_corrupt_parity => false,
            cfg_corrupt_crc    => false,
            cfg_resp_parity    => true,
            cfg_etu            => 16,
            cfg_half           => 8,
            cfg_subcdiv        => 2,
            cfg_pause          => 3,

            obs_busy         => r_busy,
            obs_txn_count    => r_txn_count,
            obs_saw_response => r_saw_resp,
            obs_fdt_ticks    => r_fdt,
            obs_sof_ok       => r_sof_ok,
            obs_nbytes       => r_obs_nbytes,
            obs_bytes        => r_obs_bytes,
            obs_nbits        => r_obs_nbits,
            obs_first_bit    => r_first_bit,
            obs_parity_ok    => r_par_ok,
            obs_crc_ok       => r_crc_ok
        );

    -- tristate resolution of the shared MISO wire (house _oe convention)
    miso_net <= pin_miso when pin_miso_oe = '1' else 'Z';

    -- RF source multiplexing: directed levels vs the reader model
    sig_env   <= rdr_env   when sel_reader = '1' else tb_env;
    sig_field <= rdr_field when sel_reader = '1' else tb_field;
    sig_clk   <= rdr_clk;

    ---------------------------------------------------------------------------
    -- Monitors: transition counters the checks sample as before/after deltas.
    ---------------------------------------------------------------------------
    -- counts every transition of the resolved MISO wire
    miso_mon : process (miso_net)
        variable n : natural := 0;
    begin
        if miso_net'event then
            n := n + 1;
            miso_edges <= n;
        end if;
    end process miso_mon;

    -- counts MCU_CLK transitions so the gating checks can compare deltas
    mclk_mon : process (pin_mcu_clk)
        variable n : natural := 0;
    begin
        if pin_mcu_clk'event then
            n := n + 1;
            mclk_edges <= n;
        end if;
    end process mclk_mon;

    ---------------------------------------------------------------------------
    -- STIMULUS: one sequential program, the functional groups run in order and score into sb.
    ---------------------------------------------------------------------------
    stim_proc : process

        variable v, d0, d1, d2 : std_logic_vector(7 downto 0);
        variable dummy         : std_logic_vector(7 downto 0);
        variable n0, n1        : natural;
        variable f0            : natural;
        variable w0            : natural;
        variable neg_val       : std_logic_vector(7 downto 0);
        variable exp_err       : natural;
        variable fr            : nfc_byte_array(0 to NFC_MAX_BYTES - 1);
        variable t0            : natural;
        variable ok            : boolean;

        -- ---- raw SPI master (CPOL=0 / CPHA=1, MSB first) ------------------
        -- start a frame: park SCLK low, then pull BSS low
        procedure spi_open is
        begin
            sclk  <= '0';
            wait for TSU;
            bss_n <= '0';
            wait for TCS;
        end procedure;

        -- end a frame: release BSS high (the model acts on this rising edge)
        procedure spi_close is
        begin
            wait for TCS;
            bss_n <= '1';
            wait for TCS;
        end procedure;

        -- shift one byte in both directions, MSB first
        procedure spi_byte(din : in std_logic_vector(7 downto 0);
                           dout : out std_logic_vector(7 downto 0)) is
            variable acc : std_logic_vector(7 downto 0);
        begin
            for i in 7 downto 0 loop
                mosi <= din(i);
                wait for TSU;
                sclk <= '1';           -- model updates MISO here
                wait for THI;
                acc(i) := to_X01(miso_net);
                sclk <= '0';           -- model samples MOSI here
                wait for TLO;
            end loop;
            dout := acc;
        end procedure;

        -- ---- ST25R3916 SPI operation modes (Table 11) --------------------
        -- single register write: "00" mode prefix, address, one data byte
        procedure reg_wr(a : natural; d : std_logic_vector(7 downto 0)) is
        begin
            spi_open;
            spi_byte("00" & std_logic_vector(to_unsigned(a, 6)), dummy);
            spi_byte(d, dummy);
            spi_close;
        end procedure;

        -- three-byte write from one address, exercising the auto-increment
        procedure reg_wr3(a : natural; da, db, dc : std_logic_vector(7 downto 0)) is
        begin
            spi_open;
            spi_byte("00" & std_logic_vector(to_unsigned(a, 6)), dummy);
            spi_byte(da, dummy);
            spi_byte(db, dummy);
            spi_byte(dc, dummy);
            spi_close;
        end procedure;

        -- single register read: "01" mode prefix, address, one dummy byte clocked out
        procedure reg_rd(a : natural; d : out std_logic_vector(7 downto 0)) is
            variable acc : std_logic_vector(7 downto 0);
        begin
            spi_open;
            spi_byte("01" & std_logic_vector(to_unsigned(a, 6)), acc);
            spi_byte(x"00", acc);
            spi_close;
            d := acc;
        end procedure;

        -- three-byte read from one address, exercising the auto-increment
        procedure reg_rd3(a : natural;
                          da, db, dc : out std_logic_vector(7 downto 0)) is
            variable acc : std_logic_vector(7 downto 0);
        begin
            spi_open;
            spi_byte("01" & std_logic_vector(to_unsigned(a, 6)), acc);
            spi_byte(x"00", acc); da := acc;
            spi_byte(x"00", acc); db := acc;
            spi_byte(x"00", acc); dc := acc;
            spi_close;
        end procedure;

        -- one-byte direct command frame (Table 13)
        procedure direct_cmd(c : std_logic_vector(7 downto 0)) is
        begin
            spi_open;
            spi_byte(c, dummy);
            spi_close;
        end procedure;

        -- space-B access is direct command 0xFB chained ahead of the frame
        procedure regb_wr(a : natural; d : std_logic_vector(7 downto 0)) is
        begin
            spi_open;
            spi_byte(x"FB", dummy);
            spi_byte("00" & std_logic_vector(to_unsigned(a, 6)), dummy);
            spi_byte(d, dummy);
            spi_close;
        end procedure;

        -- space-B register read behind the same 0xFB prefix
        procedure regb_rd(a : natural; d : out std_logic_vector(7 downto 0)) is
            variable acc : std_logic_vector(7 downto 0);
        begin
            spi_open;
            spi_byte(x"FB", acc);
            spi_byte("01" & std_logic_vector(to_unsigned(a, 6)), acc);
            spi_byte(x"00", acc);
            spi_close;
            d := acc;
        end procedure;

        -- FIFO load: 0x80 prefix then three data bytes
        procedure fifo_wr3(da, db, dc : std_logic_vector(7 downto 0)) is
        begin
            spi_open;
            spi_byte(x"80", dummy);
            spi_byte(da, dummy);
            spi_byte(db, dummy);
            spi_byte(dc, dummy);
            spi_close;
        end procedure;

        -- FIFO read: 0x9F prefix then three dummy bytes to clock the data out
        procedure fifo_rd3(da, db, dc : out std_logic_vector(7 downto 0)) is
            variable acc : std_logic_vector(7 downto 0);
        begin
            spi_open;
            spi_byte(x"9F", acc);
            spi_byte(x"00", acc); da := acc;
            spi_byte(x"00", acc); db := acc;
            spi_byte(x"00", acc); dc := acc;
            spi_close;
        end procedure;

        -- ---- reader-model frame launch: bounded wait, never hangs --------
        procedure reader_frame(done_ok : out boolean) is
            variable start_n : natural;
        begin
            start_n := r_txn_count;
            done_ok := false;
            r_go <= '1';
            wait for 200 ns;
            r_go <= '0';
            for i in 1 to 6000 loop
                if r_txn_count /= start_n then
                    done_ok := true;
                    exit;
                end if;
                wait for 100 ns;
            end loop;
        end procedure;

    begin
        wait for 200 ns;

        ----------------------------------------------------------------
        -- G-RST: power-up defaults over a real SPI read
        ----------------------------------------------------------------
        report "=== G-RST: reset defaults ===" severity note;
        sb.check_bit("G-RST: transparent_mode is 0 out of reset", transparent_mode, '0');
        sb.check_bit("G-RST: MISO is tristate with BSS idle high", miso_net, 'Z');

        reg_rd(A_IC_ID, v);
        sb.check_slv("G-RST: IC identity (0x3F) = 0x2A (ic_type 00101 / ic_rev 010)",
                     v, x"2A");
        reg_rd(A_MODE, v);
        sb.check_slv("G-RST: Mode definition (0x03) = 0x08 (om0 default 1)", v, x"08");
        reg_rd(A_OP_CTRL, v);
        sb.check_slv("G-RST: Operation control (0x02) = 0x00", v, x"00");
        reg_rd(A_IO_CONF1, v);
        sb.check_slv("G-RST: IO configuration 1 (0x00) = 0x00", v, x"00");
        sb.check_bit("G-RST: MISO released again after the frame", miso_net, 'Z');
        sb.check_slv("G-RST: last operation-mode byte was a register read of 0x00",
                     obs_last_mode, x"40");

        ----------------------------------------------------------------
        -- G-REG: register write/read round trip + read-only protection
        ----------------------------------------------------------------
        report "=== G-REG: register write / read ===" severity note;
        f0 := obs_frame_count;
        reg_wr(A_AUX, x"5A");
        reg_rd(A_AUX, v);
        sb.check_slv("G-REG: Auxiliary definition (0x0A) round-trips 0x5A", v, x"5A");
        sb.check_slv("G-REG: last decoded register address = 0x0A",
                     obs_last_addr, "001010");
        sb.check_true("G-REG: two more SPI frames completed", obs_frame_count = f0 + 2);

        -- a second, different value proves it is storage and not an echo
        reg_wr(A_ISO14443A, x"A5");
        reg_rd(A_ISO14443A, v);
        sb.check_slv("G-REG: ISO14443A settings (0x05) round-trips 0xA5", v, x"A5");
        reg_rd(A_AUX, v);
        sb.check_slv("G-REG: 0x0A still holds 0x5A (independent storage)", v, x"5A");

        -- read-only address: the write must be refused, the value must stand
        n0 := obs_reject_count;
        reg_wr(A_IC_ID, x"FF");
        sb.check_true("G-REG: write to read-only IC identity is refused",
                      obs_reject_count = n0 + 1);
        reg_rd(A_IC_ID, v);
        sb.check_slv("G-REG: IC identity unchanged after the refused write", v, x"2A");

        ----------------------------------------------------------------
        -- G-AINC: address auto-increment on both write and read
        ----------------------------------------------------------------
        report "=== G-AINC: address auto-increment ===" severity note;
        reg_wr3(A_ISO14443A, x"11", x"22", x"33");   -- 0x05, 0x06, 0x07
        reg_rd3(A_ISO14443A, d0, d1, d2);
        sb.check_slv("G-AINC: 0x05 = 0x11", d0, x"11");
        sb.check_slv("G-AINC: 0x06 = 0x22 (auto-incremented)", d1, x"22");
        sb.check_slv("G-AINC: 0x07 = 0x33 (auto-incremented)", d2, x"33");

        ----------------------------------------------------------------
        -- G-CMD: direct commands (Table 13)
        ----------------------------------------------------------------
        report "=== G-CMD: direct commands ===" severity note;
        n0 := obs_cmd_count;
        direct_cmd(x"D3");                 -- Measure amplitude: accepted, inert
        sb.check_true("G-CMD: direct command counted", obs_cmd_count = n0 + 1);
        sb.check_slv("G-CMD: last direct command byte = 0xD3", obs_last_cmd, x"D3");

        direct_cmd(x"C1");                 -- Set default
        sb.check_slv("G-CMD: last direct command byte = 0xC1 (Set default)",
                     obs_last_cmd, x"C1");
        reg_rd(A_AUX, v);
        sb.check_slv("G-CMD: Set default restored 0x0A to 0x00", v, x"00");
        reg_rd(A_MODE, v);
        sb.check_slv("G-CMD: Set default restored 0x03 to its 0x08 default", v, x"08");
        reg_rd(A_IC_ID, v);
        sb.check_slv("G-CMD: IC identity survives Set default", v, x"2A");

        ----------------------------------------------------------------
        -- G-FIFO: FIFO load/read, and the `en` gate on FIFO operations
        ----------------------------------------------------------------
        report "=== G-FIFO: FIFO load / read + en gate ===" severity note;
        reg_rd(A_OP_CTRL, v);
        sb.check_slv("G-FIFO: en is clear before the gate test", v, x"00");
        n0 := obs_reject_count;
        fifo_wr3(x"DE", x"AD", x"01");
        sb.check_true("G-FIFO: FIFO load refused while en = 0",
                      obs_fifo_level = 0 and obs_reject_count = n0 + 1);

        reg_wr(A_OP_CTRL, x"80");          -- en = 1
        fifo_wr3(x"DE", x"AD", x"01");
        sb.check_true("G-FIFO: three bytes loaded with en = 1", obs_fifo_level = 3);
        fifo_rd3(d0, d1, d2);
        sb.check_slv("G-FIFO: FIFO byte 0 reads back", d0, x"DE");
        sb.check_slv("G-FIFO: FIFO byte 1 reads back", d1, x"AD");
        sb.check_slv("G-FIFO: FIFO byte 2 reads back", d2, x"01");

        fifo_wr3(x"01", x"02", x"03");
        sb.check_true("G-FIFO: FIFO refilled", obs_fifo_level = 3);
        direct_cmd(x"DB");                 -- Clear FIFO
        sb.check_true("G-FIFO: Clear FIFO (0xDB) empties it", obs_fifo_level = 0);

        ----------------------------------------------------------------
        -- G-SPB: register space-B access via the chained 0xFB prefix
        ----------------------------------------------------------------
        report "=== G-SPB: space-B access (0xFB prefix) ===" severity note;
        regb_wr(B_CORR1, x"77");
        regb_rd(B_CORR1, v);
        sb.check_slv("G-SPB: space-B 0x0C round-trips 0x77", v, x"77");
        reg_rd(B_CORR1, v);
        sb.check_slv("G-SPB: SPACE-A 0x0C is a different register (still 0x00)",
                     v, x"00");
        sb.check_bit("G-SPB: the space-B prefix is dropped at the BSS rising edge",
                     obs_space_b, '0');
        n0 := obs_reject_count;
        regb_wr(A_IO_CONF1, x"33");        -- 0x00 does not exist in space B
        sb.check_true("G-SPB: write to a non-existent space-B address is refused",
                      obs_reject_count = n0 + 1);

        ----------------------------------------------------------------
        -- G-IRQ: IRQ pin + read-and-clear interrupt status (Sect. 4.3.1)
        ----------------------------------------------------------------
        report "=== G-IRQ: interrupt pin / read-and-clear ===" severity note;
        cfg_irq_bits    <= x"01";
        cfg_irq_trigger <= '1';
        wait for 100 ns;
        cfg_irq_trigger <= '0';
        wait for 100 ns;
        sb.check_bit("G-IRQ: IRQ pin rises on an unmasked interrupt", pin_irq, '1');
        reg_rd(A_IRQ_MAIN, v);
        sb.check_slv("G-IRQ: Main interrupt register reads the injected bit", v, x"01");
        sb.check_bit("G-IRQ: IRQ pin drops once the status has been read", pin_irq, '0');

        reg_wr(A_MASK_MAIN, x"02");        -- mask bit 1
        cfg_irq_bits    <= x"02";
        cfg_irq_trigger <= '1';
        wait for 100 ns;
        cfg_irq_trigger <= '0';
        wait for 100 ns;
        sb.check_bit("G-IRQ: a MASKED source does not raise the pin", pin_irq, '0');
        reg_rd(A_IRQ_MAIN, v);
        sb.check_slv("G-IRQ: the masked status bit is still readable", v, x"02");
        reg_wr(A_MASK_MAIN, x"00");

        ----------------------------------------------------------------
        -- G-EXTLM: EXT_LM as the field-detector output, gated by en_fd_c
        ----------------------------------------------------------------
        report "=== G-EXTLM: field detector output ===" severity note;
        tb_field <= '1';
        wait for 100 ns;
        sb.check_bit("G-EXTLM: no field-detect output while en_fd_c = 00",
                     pin_ext_lm, '0');
        reg_wr(A_OP_CTRL, x"83");          -- en + en_fd_c = 11 (automatic)
        wait for 100 ns;
        sb.check_bit("G-EXTLM: field-detect output live once en_fd_c /= 00",
                     pin_ext_lm, '1');
        tb_field <= '0';
        wait for 100 ns;
        sb.check_bit("G-EXTLM: follows the field going away", pin_ext_lm, '0');
        tb_field <= '1';
        wait for 100 ns;

        ----------------------------------------------------------------
        -- G-CLK: MCU_CLK gating (out_cl / lf_clk_off / en)
        ----------------------------------------------------------------
        report "=== G-CLK: MCU_CLK output gating ===" severity note;
        n0 := mclk_edges;
        wait for 2 us;
        n1 := mclk_edges;
        sb.check_true("G-CLK: carrier clock present on MCU_CLK with en = 1", n1 > n0);

        reg_wr(A_IO_CONF1, x"06");         -- out_cl<1:0> = 11 disables the output
        wait for 500 ns;
        n0 := mclk_edges;
        wait for 2 us;
        sb.check_true("G-CLK: out_cl = 11 holds MCU_CLK permanently low",
                      mclk_edges = n0);
        sb.check_bit("G-CLK: MCU_CLK level is low when disabled", pin_mcu_clk, '0');

        reg_wr(A_IO_CONF1, x"00");         -- re-enable
        reg_wr(A_OP_CTRL, x"03");          -- en = 0 (keep en_fd_c) selects the LF clock
        wait for 500 ns;
        n0 := mclk_edges;
        wait for 4 us;
        sb.check_true("G-CLK: 32 kHz LF clock appears on MCU_CLK while en = 0",
                      mclk_edges > n0);
        reg_wr(A_IO_CONF1, x"01");         -- lf_clk_off = 1
        wait for 500 ns;
        n0 := mclk_edges;
        wait for 4 us;
        sb.check_true("G-CLK: lf_clk_off suppresses the LF clock", mclk_edges = n0);
        reg_wr(A_IO_CONF1, x"00");

        ----------------------------------------------------------------
        -- G-GATE-RF (a): RF must NOT pass while the part is NOT transparent
        ----------------------------------------------------------------
        report "=== G-GATE-RF(a): RF blocked in normal mode ===" severity note;
        reg_wr(A_OP_CTRL, x"C3");          -- en + rx_en + en_fd_c = 11
        sclk <= '0';
        wait for 100 ns;
        n0 := obs_rf_blocked_edges;
        w0 := miso_edges;
        for i in 1 to 4 loop
            tb_env <= '0'; wait for 200 ns;
            tb_env <= '1'; wait for 200 ns;
        end loop;
        sb.check_true("G-GATE-RF(a): every envelope edge is counted as BLOCKED",
                      obs_rf_blocked_edges = n0 + 8);
        sb.check_true("G-GATE-RF(a): MISO never moved (no RF leaked through)",
                      miso_edges = w0);
        sb.check_bit("G-GATE-RF(a): MISO is still tristate", miso_net, 'Z');
        sb.check_bit("G-GATE-RF(a): no load modulation is driven either",
                     loadmod, '0');

        ----------------------------------------------------------------
        -- G-TP: entering transparent mode (0xDC + the BSS rising edge)
        ----------------------------------------------------------------
        report "=== G-TP: transparent-mode entry ===" severity note;
        -- with en = 0 the command must be refused (Table 13 operation mode "en")
        reg_wr(A_OP_CTRL, x"00");
        n0 := obs_reject_count;
        direct_cmd(x"DC");
        sb.check_bit("G-TP: 0xDC with en = 0 does NOT enter transparent mode",
                     transparent_mode, '0');
        sb.check_true("G-TP: the refused 0xDC is counted as a rejection",
                      obs_reject_count = n0 + 1);

        reg_wr(A_OP_CTRL, x"C3");          -- en + rx_en + en_fd_c
        spi_open;
        spi_byte(x"DC", dummy);
        sb.check_bit("G-TP: mid-frame the part is still in normal SPI mode",
                     transparent_mode, '0');
        wait for TCS;
        bss_n <= '1';
        wait for TCS;
        sb.check_bit("G-TP: transparent mode engages on the BSS RISING edge",
                     transparent_mode, '1');
        sb.check_bit("G-TP: MISO is actively driven in transparent mode",
                     pin_miso_oe, '1');

        ----------------------------------------------------------------
        -- G-TP-RF: with the mode engaged the RF path is live
        ----------------------------------------------------------------
        report "=== G-TP-RF: RF pass-through while transparent ===" severity note;
        sclk <= '1';                       -- SCLK is the receiver enable now
        wait for 100 ns;
        tb_env <= '1'; wait for 200 ns;
        sb.check_bit("G-TP-RF: no-pause envelope reaches MISO", miso_net, '1');
        tb_env <= '0'; wait for 200 ns;
        sb.check_bit("G-TP-RF: a carrier pause reaches MISO", miso_net, '0');
        sb.check_bit("G-TP-RF: the IRQ pin carries the second demod tap",
                     pin_irq, '0');
        n0 := obs_rf_blocked_edges;
        tb_env <= '1'; wait for 200 ns;
        sb.check_bit("G-TP-RF: envelope returns to idle on MISO", miso_net, '1');
        sb.check_true("G-TP-RF: passed edges are NOT counted as blocked",
                      obs_rf_blocked_edges = n0);

        -- transmit side: MOSI drives the load modulator
        mosi <= '1'; wait for 100 ns;
        sb.check_bit("G-TP-RF: MOSI drives the load modulator", loadmod, '1');
        mosi <= '0'; wait for 100 ns;
        sb.check_bit("G-TP-RF: load modulator follows MOSI low", loadmod, '0');
        tb_txen <= '1'; wait for 100 ns;
        sb.check_bit("G-TP-RF: the transmit window opens toward the reader",
                     loadmod_en, '1');
        tb_txen <= '0'; wait for 100 ns;

        -- SCLK is the receiver enable in transparent mode
        sclk <= '0'; wait for 100 ns;
        tb_env <= '0'; wait for 200 ns;
        sb.check_bit("G-TP-RF: receiver disabled (SCLK low) parks MISO at idle",
                     miso_net, '1');
        sclk <= '1'; wait for 200 ns;
        sb.check_bit("G-TP-RF: re-enabling the receiver restores the envelope",
                     miso_net, '0');
        tb_env <= '1'; wait for 200 ns;

        ----------------------------------------------------------------
        -- G-GATE-SPI: SPI is DEAD while transparent (the second negative)
        ----------------------------------------------------------------
        report "=== G-GATE-SPI: SPI refused while transparent ===" severity note;
        f0 := obs_frame_count;
        w0 := obs_reg_writes;
        n0 := obs_spi_ignored_edges;
        -- a would-be "write 0xFF to 0x0A" wiggled onto SCLK/MOSI with BSS HIGH
        for i in 1 to 16 loop
            mosi <= '1';
            wait for TSU;
            sclk <= '0';
            wait for TLO;
            sclk <= '1';
            wait for THI;
        end loop;
        mosi <= '0';
        wait for 100 ns;
        sb.check_bit("G-GATE-SPI: still transparent after the SPI wiggle",
                     transparent_mode, '1');
        sb.check_true("G-GATE-SPI: no SPI frame was completed",
                      obs_frame_count = f0);
        sb.check_true("G-GATE-SPI: no register was written",
                      obs_reg_writes = w0);
        sb.check_true("G-GATE-SPI: the ignored SCLK edges were counted",
                      obs_spi_ignored_edges >= n0 + 32);
        reg_rd(A_AUX, v);                  -- this ALSO exits transparent mode
        sb.check_slv("G-GATE-SPI: 0x0A is untouched by the refused traffic",
                     v, x"00");

        ----------------------------------------------------------------
        -- G-EXIT: any BSS falling edge silently drops transparent mode
        ----------------------------------------------------------------
        report "=== G-EXIT: leaving transparent mode ===" severity note;
        sb.check_bit("G-EXIT: the read above already left transparent mode",
                     transparent_mode, '0');

        -- re-enter, then prove the exit lands on the BSS falling edge and the causing frame still parses as ordinary SPI
        direct_cmd(x"DC");
        sb.check_bit("G-EXIT: re-entered transparent mode", transparent_mode, '1');
        sclk <= '0';
        wait for TSU;
        bss_n <= '0';
        wait for TCS;
        sb.check_bit("G-EXIT: transparent mode drops on the BSS FALLING edge",
                     transparent_mode, '0');
        spi_byte("01" & std_logic_vector(to_unsigned(A_IC_ID, 6)), v);
        spi_byte(x"00", v);
        spi_close;
        sb.check_slv("G-EXIT: the exiting frame is parsed as a normal SPI read",
                     v, x"2A");
        sb.check_bit("G-EXIT: MISO released again after the exiting frame",
                     miso_net, 'Z');

        ----------------------------------------------------------------
        -- G-GATE-RF (b): after the exit, RF is blocked again
        ----------------------------------------------------------------
        report "=== G-GATE-RF(b): RF blocked again after the exit ===" severity note;
        n0 := obs_rf_blocked_edges;
        w0 := miso_edges;
        for i in 1 to 3 loop
            tb_env <= '0'; wait for 200 ns;
            tb_env <= '1'; wait for 200 ns;
        end loop;
        sb.check_true("G-GATE-RF(b): envelope edges blocked again",
                      obs_rf_blocked_edges = n0 + 6);
        sb.check_true("G-GATE-RF(b): MISO stayed put", miso_edges = w0);

        ----------------------------------------------------------------
        -- G-RDR: the reader drives a real modified-Miller REQA short frame; the AFE must relay it to MISO only while transparent.
        ----------------------------------------------------------------
        report "=== G-RDR: composition with nfc_reader_model ===" severity note;
        sel_reader <= '1';
        r_field    <= '1';
        tb_txen    <= '1';                 -- bench-only response-window trigger
        fr := (others => (others => '0'));
        fr(0)    := x"26";                 -- REQA
        r_bytes  <= fr;
        r_short  <= true;
        r_nbytes <= 1;
        wait for 1 us;
        sb.check_bit("G-RDR: the reader's field reaches EXT_LM", pin_ext_lm, '1');

        -- (b1) NOT transparent: the Miller frame must not reach MISO
        sb.check_bit("G-RDR: starting in normal SPI mode", transparent_mode, '0');
        w0 := miso_edges;
        n0 := obs_rf_blocked_edges;
        reader_frame(ok);
        sb.check_true("G-RDR: reader frame completed (bounded)", ok);
        sb.check_true("G-RDR: NOT transparent -> the Miller frame never reached MISO",
                      miso_edges = w0);
        sb.check_true("G-RDR: its envelope edges were counted as blocked",
                      obs_rf_blocked_edges > n0);

        -- (b2) transparent: the same frame must come through
        reg_wr(A_OP_CTRL, x"C3");
        direct_cmd(x"DC");
        sclk <= '1';                       -- receiver enable
        wait for 500 ns;
        sb.check_bit("G-RDR: transparent mode engaged for the second frame",
                     transparent_mode, '1');
        w0 := miso_edges;
        reader_frame(ok);
        sb.check_true("G-RDR: second reader frame completed (bounded)", ok);
        sb.check_true("G-RDR: transparent -> the Miller pauses DID reach MISO",
                      miso_edges > w0);

        sel_reader <= '0';
        tb_txen    <= '0';
        r_field    <= '0';
        sclk       <= '0';
        wait for 500 ns;

        ----------------------------------------------------------------
        -- GROUP-NEG: negative control, always last: one deliberately wrong expectation proves the scoreboard can fail.
        ----------------------------------------------------------------
        if NEGCTRL then
            report "=== GROUP-NEG: NEGATIVE CONTROL ===" severity note;
            reg_rd(A_IC_ID, neg_val);
            sb.check_slv("NEGATIVE CONTROL: wrong expected IC identity (must FAIL)",
                         neg_val, std_logic_vector(unsigned(neg_val) + 1));
        else
            report "=== GROUP-NEG: SKIPPED (NEGCTRL = false) ===" severity note;
        end if;

        ----------------------------------------------------------------
        -- Final verdict: sb.errors must be exactly 1 with NEGCTRL on, 0 with it off.
        ----------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("ST25R3916 MODEL TB");

        if NEGCTRL then
            exp_err := 1;
        else
            exp_err := 0;
        end if;

        if sb.errors = exp_err then
            if NEGCTRL then
                report LF & LF &
                    "    ##################################################" & LF &
                    "    ##   ST25R3916_TB PASS (1 expected negative-control failure)" & LF &
                    "    ##   ST25R3916 MODEL TB:  ALL CHECKS PASSED" & LF &
                    "    ##################################################" & LF
                    severity note;
            else
                report LF & LF &
                    "    ##################################################" & LF &
                    "    ##   ST25R3916_TB PASS (NEGCTRL disabled, 0 failures)" & LF &
                    "    ##   ST25R3916 MODEL TB:  ALL CHECKS PASSED" & LF &
                    "    ##################################################" & LF
                    severity note;
            end if;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   ST25R3916_TB FAIL (expected exactly " &
                integer'image(exp_err) & " failure(s), got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        stop;
        wait;
    end process stim_proc;

end architecture sim;
