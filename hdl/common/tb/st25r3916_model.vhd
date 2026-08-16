/* -----------------------------------------------------------------------------
   st25r3916_model.vhd
   -----------------------------------------------------------------------------
   Behavioral model of the off-die ST25R3916 NFC front end that NFC0 talks to: SPI register interface, FIFO, and transparent-mode pin gating.
   The RF protocol itself is not modelled here; tb/nfc_reader_model.vhd carries the ISO-14443A link, and this model duplicates none of it.
   Transparent mode is armed by direct command 0xDC, engages on the BSS rising edge of that same SPI frame, and is silently dropped by the next BSS falling edge.
   In transparent mode the shared pins change meaning: MOSI is Tx modulation in, MISO is the digitized RX out, SCLK is the receiver enable, MCU_CLK is the extracted carrier, EXT_LM is the field detector, IRQ is the ASK demod tap.
   Functional model only (no analog, framing engine, timers, PT_memory or I2C); unmodelled direct commands are accepted and counted, and cfg_* inputs / obs_* outputs are the bench's controls and scoreboard taps.
   ----------------------------------------------------------------------------- */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity st25r3916_model is
    generic (
        -- Half period of the 32 kHz clock the part puts on MCU_CLK while the crystal oscillator is stopped (~15.26 us on the real part, compressed here).
        LF_HALF    : time    := 500 ns;
        -- FIFO depth: 512 bytes on the real part. Shrink for speed.
        FIFO_DEPTH : natural := 512
    );
    port (
        -- SHARED PHYSICAL PINS (MCU side): each carries an SPI role and a transparent-mode role.
        pin_bss_n   : in  std_logic := '1';   -- BSS/NSS, ACTIVE LOW slave select
                                              --   also THE transparent-mode selector
        pin_sclk    : in  std_logic := '0';   -- SPI SCLK | transparent: receiver enable (afe_en)
        pin_mosi    : in  std_logic := '0';   -- SPI MOSI | transparent: Tx modulation in (rf_txmod)
        pin_miso    : out std_logic := '0';   -- SPI MISO | transparent: digitized RX out (rf_rx)
        pin_miso_oe : out std_logic := '0';   -- '1' = this model drives pin_miso
        pin_mcu_clk : out std_logic := '0';   -- MCU_CLK  | transparent: extracted carrier (rf_clk)
        pin_irq     : out std_logic := '0';   -- IRQ      | transparent: 2nd demod tap
        pin_ext_lm  : out std_logic := '0';   -- EXT_LM   | transparent: field detector

        -- ANTENNA / RF-WORLD SIDE (wire these to nfc_reader_model).
        rf_field_in    : in  std_logic := '0';  -- reader field present
        rf_env_in      : in  std_logic := '1';  -- reader's envelope at the antenna
        rf_clk_in      : in  std_logic := '0';  -- carrier-derived clock
        rf_loadmod_out : out std_logic := '0';  -- drives nfc_reader_model.rf_txmod
        rf_loadmod_en  : out std_logic := '0';  -- drives nfc_reader_model.rf_tx_en

        -- BENCH-ONLY: NFC0's rf_tx_en has no ST25R3916 pin (rf_txmod is already OOK-gated), so it is offered here to trigger nfc_reader_model's response-window decode.
        mcu_rf_tx_en   : in  std_logic := '0';

        -- PER-TEST CONFIGURATION (held stable by the bench).
        cfg_rx_invert      : in boolean := false;  -- invert the digitized envelope
        cfg_sclk_is_afe_en : in boolean := true;   -- honour SCLK as receiver enable

        -- A rising edge on cfg_irq_trigger ORs cfg_irq_bits into the Main interrupt register (0x1A), exercising the read-and-clear IRQ contract without an RF engine.
        cfg_irq_trigger    : in std_logic                    := '0';
        cfg_irq_bits       : in std_logic_vector(7 downto 0) := (others => '0');

        -- OBSERVATIONS (held until the next event of the same kind).
        transparent_mode      : out std_logic := '0';   -- THE mode output
        obs_frame_count       : out natural := 0;       -- completed SPI frames (BSS low then high)
        obs_cmd_count         : out natural := 0;       -- direct commands executed
        obs_last_cmd          : out std_logic_vector(7 downto 0) := (others => '0');
        obs_last_mode         : out std_logic_vector(7 downto 0) := (others => '0');
        obs_last_addr         : out std_logic_vector(5 downto 0) := (others => '0');
        obs_space_b           : out std_logic := '0';   -- space-B prefix currently active
        obs_reg_writes        : out natural := 0;       -- register writes COMMITTED
        obs_reg_reads         : out natural := 0;       -- register bytes SOURCED
        obs_reject_count      : out natural := 0;       -- refused writes / refused ops
        obs_fifo_level        : out natural := 0;
        -- The two gating proofs:
        obs_spi_ignored_edges : out natural := 0;       -- SCLK edges ignored while transparent
        obs_rf_blocked_edges  : out natural := 0        -- RF envelope edges NOT passed on
    );
end entity st25r3916_model;


architecture behavioral of st25r3916_model is

    constant NREG : natural := 64;
    type reg_array  is array (0 to NREG - 1) of std_logic_vector(7 downto 0);
    type fifo_array is array (0 to FIFO_DEPTH - 1) of std_logic_vector(7 downto 0);

    -- Named space-A register addresses.
    constant R_IO_CONF1  : natural := 16#00#;
    constant R_IO_CONF2  : natural := 16#01#;
    constant R_OP_CTRL   : natural := 16#02#;
    constant R_MODE      : natural := 16#03#;
    constant R_BIT_RATE  : natural := 16#04#;
    constant R_ISO14443A : natural := 16#05#;
    constant R_STREAM    : natural := 16#09#;
    constant R_AUX       : natural := 16#0A#;
    constant R_MASK_MAIN : natural := 16#16#;
    constant R_IRQ_MAIN  : natural := 16#1A#;
    constant R_IRQ_LAST  : natural := 16#1D#;
    constant R_IC_ID     : natural := 16#3F#;

    -- Direct commands.
    constant CMD_SET_DEFAULT : std_logic_vector(7 downto 0) := x"C1";
    constant CMD_STOP        : std_logic_vector(7 downto 0) := x"C2";
    constant CMD_CLEAR_FIFO  : std_logic_vector(7 downto 0) := x"DB";
    constant CMD_TRANSPARENT : std_logic_vector(7 downto 0) := x"DC";
    constant CMD_SPACE_B     : std_logic_vector(7 downto 0) := x"FB";

    -- SPI operation-mode first bytes.
    constant MB_FIFO_LOAD : std_logic_vector(7 downto 0) := x"80";
    constant MB_FIFO_READ : std_logic_vector(7 downto 0) := x"9F";

    -- SPI frame parser states, kept as naturals so the procedures below can compare them without type games.
    constant ST_MODE   : natural := 0;   -- expecting an operation-mode byte
    constant ST_WDATA  : natural := 1;   -- register write data (auto-increment)
    constant ST_RDATA  : natural := 2;   -- register read data  (auto-increment)
    constant ST_FIFO_W : natural := 3;   -- FIFO load data
    constant ST_FIFO_R : natural := 4;   -- FIFO read data
    constant ST_IGN    : natural := 5;   -- consume the rest of the frame

    -- Level MISO/IRQ are held at when the transparent RX path is gated off: the 14443A "field present, no pause" idle.
    constant RX_IDLE : std_logic := '1';

    -- Published copy of the space-A register file, so the RF-path concurrent assignments below can see en / rx_en / en_fd_c / out_cl / lf_clk_off.
    signal s_regs_a : reg_array := (others => (others => '0'));
    signal s_tp     : std_logic := '0';   -- published transparent-mode flag

    -- MISO sources: the SPI slave output and its enable, and the transparent-mode RX output.
    signal miso_spi    : std_logic := '0';
    signal miso_spi_oe : std_logic := '0';
    signal miso_tp     : std_logic := RX_IDLE;

    -- Register-file taps used by the pin paths.
    signal s_en     : std_logic := '0';                          -- op-control en
    signal s_rx_en  : std_logic := '0';                          -- op-control rx_en
    signal s_fd     : std_logic_vector(1 downto 0) := "00";      -- en_fd_c<1:0>
    signal s_outcl  : std_logic_vector(1 downto 0) := "00";      -- out_cl<1:0>
    signal s_lfoff  : std_logic := '0';                          -- lf_clk_off

    signal rx_gate  : std_logic := '0';     -- transparent RX path open
    signal env_dig  : std_logic := RX_IDLE; -- digitized envelope after the polarity choice
    signal irq_spi  : std_logic := '0';     -- normal-mode IRQ pin level
    signal lf_clk   : std_logic := '0';     -- free-running 32 kHz LF clock

    function to_sl(b : boolean) return std_logic is
    begin
        if b then return '1'; else return '0'; end if;
    end function;

    -- Everything resets to 0x00 except MODE (om0 = 1) and the read-only IC identity byte (ic_type = 00101, ic_rev = 010).
    function defaults_a return reg_array is
        variable r : reg_array := (others => (others => '0'));
    begin
        r(R_MODE)  := x"08";
        r(R_IC_ID) := x"2A";
        return r;
    end function;

    -- Space B has no non-zero reset values, so every byte resets to 0x00.
    function defaults_b return reg_array is
        variable r : reg_array := (others => (others => '0'));
    begin
        return r;
    end function;

    -- Space-A read-only addresses: status, display and measurement registers plus IC identity.
    function is_ro_a(a : natural) return boolean is
    begin
        if a >= 16#1A# and a <= 16#21# then return true; end if;   -- IRQ status, FIFO status, displays
        if a = 16#24# or a = 16#25# then return true; end if;      -- bit-rate detect, ADC out
        if a = 16#2D# or a = 16#2E# then return true; end if;      -- RSSI, gain reduction
        if a = 16#30# or a = 16#31# then return true; end if;      -- cap-sensor display, aux display
        if a = 16#35# or a = 16#36# then return true; end if;      -- amplitude avg / display
        if a = 16#39# or a = 16#3A# then return true; end if;      -- phase avg / display
        if a = 16#3D# or a = 16#3E# then return true; end if;      -- capacitance avg / display
        if a = R_IC_ID then return true; end if;
        return false;
    end function;

    -- Space B is SPARSE: only these addresses exist on the plain ST25R3916.
    function exists_b(a : natural) return boolean is
    begin
        case a is
            when 16#05# | 16#06# | 16#0B# | 16#0C# | 16#0D# | 16#0F# | 16#15# |
                 16#28# | 16#29# | 16#2A# | 16#2B# | 16#2C# |
                 16#30# | 16#31# | 16#32# | 16#33# => return true;
            when others => return false;
        end case;
    end function;

    -- Space-B read-only addresses.
    function is_ro_b(a : natural) return boolean is
    begin
        -- 2B TX driver timing display, 2C regulator display.
        if a = 16#2B# or a = 16#2C# then return true; end if;
        return false;
    end function;

begin

    -- SPI slave, register file and transparent-mode state machine.
    -- CPOL = 0, CPHA = 1: while BSS is low MOSI is sampled on the falling SCLK edge and MISO is updated on the rising edge, MSB first, with bitpos shared by both edges so bitpos = 0 on a rising edge starts a new byte.
    spi_proc : process (pin_bss_n, pin_sclk, cfg_irq_trigger)
        variable rega    : reg_array  := defaults_a;   -- space-A register file
        variable regb    : reg_array  := defaults_b;   -- space-B register file
        variable fifo    : fifo_array := (others => (others => '0'));
        variable fifo_wp : natural := 0;               -- FIFO write pointer
        variable fifo_rp : natural := 0;               -- FIFO read pointer
        variable fifo_lv : natural := 0;               -- FIFO fill level

        variable tp      : std_logic := '0';   -- transparent mode, live value
        variable pend_tp : boolean   := false; -- 0xDC seen, arms on BSS rise
        variable spb     : boolean   := false; -- space-B prefix active

        variable st      : natural := ST_MODE; -- parser state
        variable bitpos  : natural := 0;       -- bit index within the current byte
        variable shift   : std_logic_vector(7 downto 0) := (others => '0');  -- MOSI receive shifter
        variable rdbyte  : std_logic_vector(7 downto 0) := (others => '0');  -- byte currently sourced onto MISO
        variable cur     : natural := 0;       -- auto-incrementing register address

        -- Observation counters, published at the end of every call.
        variable frames  : natural := 0;       -- completed SPI frames
        variable cmds    : natural := 0;       -- direct commands executed
        variable wrs     : natural := 0;       -- register writes committed
        variable rds     : natural := 0;       -- register bytes sourced
        variable rejs    : natural := 0;       -- refused writes and refused operations
        variable ign     : natural := 0;       -- SCLK edges ignored while transparent

        -- Empty the FIFO (Set default, Stop all activities, Clear FIFO).
        procedure fifo_clear is
        begin
            fifo_wp := 0; fifo_rp := 0; fifo_lv := 0;
        end procedure;

        -- Append one byte from a FIFO-load frame.
        procedure fifo_push(d : std_logic_vector(7 downto 0)) is
        begin
            if fifo_wp < FIFO_DEPTH then
                fifo(fifo_wp) := d;
                fifo_wp := fifo_wp + 1;
                fifo_lv := fifo_wp - fifo_rp;
            else
                rejs := rejs + 1;              -- FIFO overflow: data dropped
            end if;
        end procedure;

        -- Source the next byte of a FIFO-read frame.
        procedure fifo_pop(d : out std_logic_vector(7 downto 0)) is
        begin
            if fifo_rp < fifo_wp then
                d := fifo(fifo_rp);
                fifo_rp := fifo_rp + 1;
                fifo_lv := fifo_wp - fifo_rp;
            else
                d := x"00";                    -- an empty FIFO reads 0
            end if;
        end procedure;

        -- Clear the four IRQ status registers and with them the IRQ line.
        procedure irq_clear is
        begin
            for a in R_IRQ_MAIN to R_IRQ_LAST loop
                rega(a) := x"00";
            end loop;
        end procedure;

        -- Commit one register write, or count it as refused: absent and read-only addresses perform no write.
        procedure do_write(a : natural; d : std_logic_vector(7 downto 0)) is
        begin
            if spb then
                if exists_b(a) and not is_ro_b(a) then
                    regb(a) := d; wrs := wrs + 1;
                else
                    rejs := rejs + 1;          -- absent or read-only space-B address
                end if;
            else
                if is_ro_a(a) then
                    rejs := rejs + 1;
                else
                    rega(a) := d; wrs := wrs + 1;
                end if;
            end if;
        end procedure;

        -- Source one register byte for a read frame; absent space-B addresses read 0x00.
        procedure reg_fetch(a : natural; d : out std_logic_vector(7 downto 0)) is
        begin
            if spb then
                if exists_b(a) then d := regb(a); else d := x"00"; end if;
            else
                d := rega(a);
                if a >= R_IRQ_MAIN and a <= R_IRQ_LAST then
                    rega(a) := x"00";          -- IRQ status is read-and-clear
                end if;
            end if;
            rds := rds + 1;
        end procedure;

        -- Execute one direct command; unmodelled commands are still accepted and counted.
        procedure do_cmd(c : std_logic_vector(7 downto 0)) is
        begin
            cmds := cmds + 1;
            obs_last_cmd <= c;
            if c = CMD_SET_DEFAULT then
                rega := defaults_a;            -- back to the power-up state
                regb := defaults_b;
                fifo_clear;
            elsif c = CMD_STOP then
                fifo_clear;                    -- stop all activities
                irq_clear;
            elsif c = CMD_CLEAR_FIFO then
                fifo_clear;
                irq_clear;
            elsif c = CMD_SPACE_B then
                spb := true;                   -- space-B prefix, active until BSS rises
            elsif c = CMD_TRANSPARENT then
                -- Refused unless en is set, and it engages on the BSS rising edge of THIS frame, not now.
                if rega(R_OP_CTRL)(7) = '1' then
                    pend_tp := true;
                else
                    rejs := rejs + 1;
                end if;
                st := ST_IGN;                  -- 0xDC does not chain, so ignore the rest of the frame
            else
                null;                          -- accepted + counted, no effect
            end if;
        end procedure;

        -- Absorb one fully received MOSI byte according to the parser state.
        procedure consume_byte(b : std_logic_vector(7 downto 0)) is
            variable dummy : std_logic_vector(7 downto 0);
        begin
            if st = ST_MODE then
                obs_last_mode <= b;
                if b(7 downto 6) = "00" then                 -- register write
                    cur := to_integer(unsigned(b(5 downto 0)));
                    obs_last_addr <= b(5 downto 0);
                    st := ST_WDATA;
                elsif b(7 downto 6) = "01" then              -- register read
                    cur := to_integer(unsigned(b(5 downto 0)));
                    obs_last_addr <= b(5 downto 0);
                    st := ST_RDATA;
                elsif b = MB_FIFO_LOAD then
                    if rega(R_OP_CTRL)(7) = '1' then         -- FIFO access needs en
                        st := ST_FIFO_W;
                    else
                        st := ST_IGN; rejs := rejs + 1;
                    end if;
                elsif b = MB_FIFO_READ then
                    if rega(R_OP_CTRL)(7) = '1' then
                        st := ST_FIFO_R;
                    else
                        st := ST_IGN; rejs := rejs + 1;
                    end if;
                elsif b(7 downto 6) = "10" then              -- PT_memory: recognized but not modelled
                    st := ST_IGN;
                else                                         -- "11" direct command
                    do_cmd(b);
                    if st /= ST_IGN then
                        st := ST_MODE;                       -- direct-command chaining
                    end if;
                end if;
            elsif st = ST_WDATA then
                do_write(cur, b);
                cur := (cur + 1) mod NREG;                   -- write modes auto-increment
            elsif st = ST_FIFO_W then
                fifo_push(b);
            else
                null;      -- read states / ST_IGN: MOSI bytes are don't-care
            end if;
        end procedure;

    begin
        -- Bench-driven interrupt injection (see cfg_irq_trigger).
        if cfg_irq_trigger'event and to_X01(cfg_irq_trigger) = '1' then
            rega(R_IRQ_MAIN) := rega(R_IRQ_MAIN) or cfg_irq_bits;
        end if;

        if pin_bss_n'event and to_X01(pin_bss_n) = '0' then
            -- BSS FALLING: start of an SPI frame, and the silent exit from transparent mode.
            tp      := '0';
            pend_tp := false;
            spb     := false;
            st      := ST_MODE;
            bitpos  := 0;
            shift   := (others => '0');
            miso_spi_oe <= '0';

        elsif pin_bss_n'event and to_X01(pin_bss_n) = '1' then
            -- BSS RISING: end of the frame, where transparent mode engages if this frame carried 0xDC and where space-B access ends.
            frames := frames + 1;
            if pend_tp then
                tp := '1';
                pend_tp := false;
            end if;
            spb    := false;
            st     := ST_MODE;
            bitpos := 0;
            miso_spi_oe <= '0';

        elsif pin_sclk'event and tp = '1' then
            -- In transparent mode the SPI engine is dead: SCLK is the receiver enable, so every edge is deliberately refused.
            ign := ign + 1;

        elsif pin_sclk'event and to_X01(pin_bss_n) = '0' and to_X01(pin_sclk) = '1' then
            -- SCLK RISING: update MISO.
            if bitpos = 0 then
                if st = ST_RDATA then
                    reg_fetch(cur, rdbyte);
                    cur := (cur + 1) mod NREG;
                elsif st = ST_FIFO_R then
                    fifo_pop(rdbyte);
                else
                    rdbyte := (others => '0');
                end if;
            end if;
            if st = ST_RDATA or st = ST_FIFO_R then
                miso_spi    <= rdbyte(7 - bitpos);
                miso_spi_oe <= '1';
            else
                miso_spi_oe <= '0';   -- MISO tristates when there is no output data
            end if;

        elsif pin_sclk'event and to_X01(pin_bss_n) = '0' and to_X01(pin_sclk) = '0' then
            -- SCLK FALLING: sample MOSI, MSB first.
            shift := shift(6 downto 0) & to_X01(pin_mosi);
            if bitpos = 7 then
                consume_byte(shift);
                bitpos := 0;
            else
                bitpos := bitpos + 1;
            end if;
        end if;

        -- Publish the live state to the observation ports and the pin paths.
        s_regs_a              <= rega;
        s_tp                  <= tp;
        transparent_mode      <= tp;
        obs_frame_count       <= frames;
        obs_cmd_count         <= cmds;
        obs_space_b           <= to_sl(spb);
        obs_reg_writes        <= wrs;
        obs_reg_reads         <= rds;
        obs_reject_count      <= rejs;
        obs_fifo_level        <= fifo_lv;
        obs_spi_ignored_edges <= ign;
    end process spi_proc;

    -- Register-file taps used by the analog/pin paths.
    s_en    <= s_regs_a(R_OP_CTRL)(7);            -- oscillator + regulator enable
    s_rx_en <= s_regs_a(R_OP_CTRL)(6);            -- receiver enable
    s_fd    <= s_regs_a(R_OP_CTRL)(1 downto 0);   -- en_fd_c<1:0>
    s_outcl <= s_regs_a(R_IO_CONF1)(2 downto 1);  -- out_cl<1:0>
    s_lfoff <= s_regs_a(R_IO_CONF1)(0);           -- lf_clk_off

    -- RX path (reader to MCU), live only in transparent mode and only while the receiver is enabled by rx_en and the SCLK receiver-enable line.
    -- Outside transparent mode the envelope is held and never passed on, which is the RF half of the gating contract.
    env_dig <= (not to_X01(rf_env_in)) when cfg_rx_invert else to_X01(rf_env_in);  -- polarity is unspecified by the part, so it is a bench choice

    rx_gate <= '1' when (s_tp = '1' and s_rx_en = '1' and
                         ((not cfg_sclk_is_afe_en) or to_X01(pin_sclk) = '1'))
                    else '0';

    miso_tp <= env_dig when rx_gate = '1' else RX_IDLE;

    -- MISO is the SPI slave output outside transparent mode (tristate unless sourcing read data) and the digitized RX output inside it.
    pin_miso    <= miso_tp when s_tp = '1' else miso_spi;
    pin_miso_oe <= '1'     when s_tp = '1' else miso_spi_oe;

    -- TX path (MCU to reader): MOSI directly drives the modulator, but only in transparent mode and gated by en alone.
    rf_loadmod_out <= to_X01(pin_mosi)     when (s_tp = '1' and s_en = '1') else '0';
    rf_loadmod_en  <= to_X01(mcu_rf_tx_en) when (s_tp = '1' and s_en = '1') else '0';

    -- EXT_LM as the field-detector output, only while the external field detector is enabled via en_fd_c<1:0>; no threshold, hysteresis or debounce is modelled.
    pin_ext_lm <= to_X01(rf_field_in) when s_fd /= "00" else '0';

    -- MCU_CLK: out_cl = 11 holds it low, else it carries the crystal-derived clock when en is set, else the free-running 32 kHz LF clock below unless lf_clk_off suppresses it.
    -- The out_cl dividers are not modelled: rf_clk_in passes through undivided, so this model cannot check divider arithmetic.
    lfgen : process
    begin
        lf_clk <= '0';
        wait for LF_HALF;
        lf_clk <= '1';
        wait for LF_HALF;
    end process lfgen;

    pin_mcu_clk <= '0'               when s_outcl = "11" else
                   to_X01(rf_clk_in) when s_en    = '1'  else
                   lf_clk            when s_lfoff = '0'  else
                   '0';

    -- IRQ pin in normal mode: active high while an unmasked main-interrupt status bit is set, and reading 0x1A clears it.
    -- IRQ pin in transparent mode: the second demodulator tap, modelled as the same digitized envelope as MISO.
    irq_spi <= '1' when (s_regs_a(R_IRQ_MAIN) and (not s_regs_a(R_MASK_MAIN))) /= x"00"
                   else '0';

    pin_irq <= miso_tp when s_tp = '1' else irq_spi;

    -- Gating evidence: count envelope transitions the AFE did NOT forward.
    -- With obs_spi_ignored_edges this makes both directions of the transparent-mode gate observable to a scoreboard.
    blocked_proc : process (rf_env_in)
        variable n : natural := 0;
    begin
        if rf_env_in'event then
            if s_tp = '0' or rx_gate = '0' then
                n := n + 1;
                obs_rf_blocked_edges <= n;
            end if;
        end if;
    end process blocked_proc;

end architecture behavioral;
