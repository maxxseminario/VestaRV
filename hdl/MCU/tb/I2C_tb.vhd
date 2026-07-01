-------------------------------------------------------------------------------
-- I2C_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the I2C peripheral
-- (hdl/MCU/periph/I2C.vhd).
--
-- The SDA/SCL bus is modelled as a real open-drain wired-AND: a line reads '0'
-- when EITHER the DUT drives it (its *_DIR output = '1') or the testbench pulls
-- it (tb_*_low = '1'), and floats to '1' (pull-up) otherwise.
--
-- Coverage:
--   * register read/write (CR 22-bit byte lanes, MTX/STX/AR/AMR), reset values
--   * START / STOP condition detection (STR/SPR flags, bus-state BS)
--   * slave receive: the TB drives a full transaction (START, address+W, data)
--     as an external master and checks the slave ACKs, latches the address,
--     sets the addressed/complete flags, and captures the data byte in SRX
--   * slave NOT addressed on a non-matching address (no ACK, SA stays clear)
--   * interrupt flag + enable + clear paths
--   * master: issue START, transmit a byte, detect the (absent-slave) NACK,
--     then STOP -- exercises the master FSM, clock divider, and flags
--
-- Bus contract (see tb/CLAUDE.md): EnMemPeriph active-low, WEn active-low per
-- byte lane, SR/SRX read a snapshot latched on the falling edge of EnMemPeriph.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.constants.all;
use work.MemoryMap.all;

entity I2C_tb is
end entity I2C_tb;

architecture sim of I2C_tb is

    constant PERIOD : time := 100 ns;   -- smclk
    constant T      : time := 400 ns;   -- I2C bus phase time (TB-driven master)

    constant SLAVE_ADDR : std_logic_vector(6 downto 0) := "1000010";  -- 0x42

    -- clocks / reset
    signal smclk   : std_logic := '0';
    signal ClkMem  : std_logic := '0';
    signal resetn  : std_logic := '0';

    -- interrupts
    signal irq_str, irq_spr, irq_msts, irq_msps, irq_marb, irq_mtxe, irq_mnr,
           irq_mxc, irq_sa, irq_stxe, irq_sovf, irq_snr, irq_sxc : std_logic;

    -- register bus
    signal EnMemPeriph : std_logic := '1';
    signal WEn         : std_logic_vector(3 downto 0) := (others => '1');
    signal MABPart     : std_logic_vector(7 downto 2) := (others => '0');
    signal wdata       : std_logic_vector(31 downto 0) := (others => '0');
    signal rdata_out   : std_logic_vector(31 downto 0);

    -- pins
    signal SDA_IN, SDA_OUT, SDA_DIR, SDA_REN : std_logic;
    signal SDA_REN_in : std_logic := '0';
    signal SCL_IN, SCL_OUT, SCL_DIR, SCL_REN : std_logic;
    signal SCL_REN_in : std_logic := '0';

    -- testbench open-drain pulls ('1' => actively pull the line low)
    signal tb_sda_low : std_logic := '0';
    signal tb_scl_low : std_logic := '0';

    function img(v : std_logic_vector) return string is
    begin
        if is_x(v) then return "X";
        else return integer'image(to_integer(unsigned(v))); end if;
    end function;

begin

    smclk  <= not smclk after PERIOD / 2;
    ClkMem <= smclk when EnMemPeriph = '0' else '0';

    -- Open-drain wired-AND with pull-up
    SDA_IN <= '0' when (SDA_DIR = '1' or tb_sda_low = '1') else '1';
    SCL_IN <= '0' when (SCL_DIR = '1' or tb_scl_low = '1') else '1';

    dut : entity work.I2C
        generic map ( default_SAD => "0000000" )
        port map (
            smclk => smclk, resetn => resetn,
            irq_str => irq_str, irq_spr => irq_spr, irq_msts => irq_msts,
            irq_msps => irq_msps, irq_marb => irq_marb, irq_mtxe => irq_mtxe,
            irq_mnr => irq_mnr, irq_mxc => irq_mxc, irq_sa => irq_sa,
            irq_stxe => irq_stxe, irq_sovf => irq_sovf, irq_snr => irq_snr,
            irq_sxc => irq_sxc,
            ClkMem => ClkMem, EnMemPeriph => EnMemPeriph, WEn => WEn,
            MABPart => MABPart, wdata => wdata, rdata_out => rdata_out,
            SDA_IN => SDA_IN, SDA_OUT => SDA_OUT, SDA_DIR => SDA_DIR,
            SDA_REN_in => SDA_REN_in, SDA_REN => SDA_REN,
            SCL_IN => SCL_IN, SCL_OUT => SCL_OUT, SCL_DIR => SCL_DIR,
            SCL_REN_in => SCL_REN_in, SCL_REN => SCL_REN
        );

    stim_proc : process

        variable error_count : natural := 0;
        variable rdw         : word;
        variable ackbit      : std_logic;

        procedure check_slv(tag : in string;
                            got : in std_logic_vector; exp : in std_logic_vector) is
        begin
            if got = exp then report "PASS: " & tag severity note;
            else
                error_count := error_count + 1;
                assert false report "FAIL: " & tag &
                    " (expected " & img(exp) & ", got " & img(got) & ")"
                    severity warning;
            end if;
        end procedure;

        procedure check_bit(tag : in string; got : in std_logic; exp : in std_logic) is
        begin
            if got = exp then report "PASS: " & tag severity note;
            else
                error_count := error_count + 1;
                assert false report "FAIL: " & tag &
                    " (expected " & std_logic'image(exp) &
                    ", got " & std_logic'image(got) & ")" severity warning;
            end if;
        end procedure;

        procedure bus_write(slot : in natural; data : in std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(smclk);
            MABPart <= std_logic_vector(to_unsigned(slot, 6));
            wdata   <= data;
            WEn     <= (others => '0');
            EnMemPeriph <= '0';
            wait until rising_edge(smclk);
            wait until falling_edge(smclk);
            EnMemPeriph <= '1';
            WEn     <= (others => '1');
        end procedure;

        procedure bus_read(slot : in natural; data : out std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(smclk);
            MABPart <= std_logic_vector(to_unsigned(slot, 6));
            EnMemPeriph <= '0';
            wait until rising_edge(smclk);
            wait until falling_edge(smclk);
            data := rdata_out;
            EnMemPeriph <= '1';
        end procedure;

        -- ---- TB-as-master I2C bit-bang helpers (open-drain) ----
        procedure scl_hi is begin tb_scl_low <= '0'; end procedure;  -- release (high)
        procedure scl_lo is begin tb_scl_low <= '1'; end procedure;  -- pull low
        procedure sda_set(b : in std_logic) is
        begin
            if b = '1' then tb_sda_low <= '0';   -- release -> high
            else            tb_sda_low <= '1';   -- pull -> low
            end if;
        end procedure;

        procedure i2c_start is
        begin
            -- Bring the bus to a clean idle (both released high), then pulse SCL
            -- low->high once while SDA is high.  That SCL falling edge clears any
            -- stale ClearStartSlaveRX left over from a previous, data-less
            -- transaction (e.g. the START/STOP detect test) -- otherwise the RTL
            -- masks the upcoming START edge (see I2C.vhd ClearStartSlaveRX note).
            -- The pulse is benign: SDA high means no START/STOP is generated, and
            -- the slave FSM is held in reset while the bus is idle (BS = '0').
            sda_set('1'); scl_hi; wait for T;     -- bus idle, both high
            scl_lo;       wait for T;             -- SCL falling edge clears ClearStartSlaveRX
            scl_hi;       wait for T;             -- back to idle, both high
            sda_set('0'); wait for T;             -- SDA falls while SCL high => START
            scl_lo;       wait for T;             -- SCL low
        end procedure;

        procedure i2c_stop is
        begin
            scl_lo; sda_set('0'); wait for T;     -- SCL low, SDA low
            scl_hi; wait for T;                   -- SCL high
            sda_set('1'); wait for T;             -- SDA rises while SCL high => STOP
        end procedure;

        procedure i2c_bit(b : in std_logic) is
        begin
            scl_lo; sda_set(b); wait for T;       -- set data while SCL low
            scl_hi; wait for T;                   -- SCL high (slave samples)
            scl_lo; wait for T;                   -- SCL low (slave shifts)
        end procedure;

        procedure i2c_byte(d : in std_logic_vector(7 downto 0)) is
        begin
            for i in 7 downto 0 loop
                i2c_bit(d(i));                    -- MSB first
            end loop;
        end procedure;

        -- 9th clock: release SDA, let the slave drive ACK, sample it (0 = ACK)
        procedure i2c_get_ack(ack : out std_logic) is
        begin
            scl_lo; sda_set('1'); wait for T;
            scl_hi; wait for T;
            ack := SDA_IN;
            scl_lo; wait for T;
        end procedure;

    begin
        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------
        resetn <= '0';
        EnMemPeriph <= '1';
        WEn <= (others => '1');
        tb_sda_low <= '0'; tb_scl_low <= '0';
        wait for 4 * PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 4 * PERIOD;

        ----------------------------------------------------------------
        -- GROUP 1: reset / defaults
        ----------------------------------------------------------------
        report "=== GROUP 1: reset & defaults ===" severity note;

        bus_read(RegSlotI2CxCR, rdw);
        check_slv("CR resets to 0", rdw(21 downto 0), (21 downto 0 => '0'));
        bus_read(RegSlotI2CxSR, rdw);
        check_slv("SR resets to 0 (idle bus)", rdw(15 downto 0), x"0000");
        bus_read(RegSlotI2CxAR, rdw);
        check_slv("AR = default_SAD (0)", rdw(6 downto 0), "0000000");

        check_bit("SDA released at reset", SDA_DIR, '0');
        check_bit("SCL released at reset", SCL_DIR, '0');
        check_bit("irq_str low at reset", irq_str, '0');
        check_bit("irq_sa low at reset",  irq_sa,  '0');

        SDA_REN_in <= '1'; SCL_REN_in <= '1';
        wait for 1 ns;
        check_bit("SDA_REN passthrough", SDA_REN, '1');
        check_bit("SCL_REN passthrough", SCL_REN, '1');
        SDA_REN_in <= '0'; SCL_REN_in <= '0';

        ----------------------------------------------------------------
        -- GROUP 2: register read/write
        ----------------------------------------------------------------
        report "=== GROUP 2: register R/W ===" severity note;

        bus_write(RegSlotI2CxCR, x"002ABCDE");
        bus_read(RegSlotI2CxCR, rdw);
        check_slv("CR 22-bit readback", rdw(21 downto 0), "10" & x"ABCDE");
        bus_write(RegSlotI2CxCR, x"00000000");

        bus_write(RegSlotI2CxCR, x"00200000");           -- MEN=1 (MTX write is MEN-gated)
        bus_write(RegSlotI2CxMTX, x"00000099");
        bus_read(RegSlotI2CxMTX, rdw);
        check_slv("MTX readback", rdw(7 downto 0), x"99");
        bus_write(RegSlotI2CxCR, x"00000000");
        bus_write(RegSlotI2CxSTX, x"00000066");
        bus_read(RegSlotI2CxSTX, rdw);
        check_slv("STX readback", rdw(7 downto 0), x"66");
        bus_write(RegSlotI2CxAR, (31 downto 7 => '0') & SLAVE_ADDR);
        bus_read(RegSlotI2CxAR, rdw);
        check_slv("AR readback", rdw(6 downto 0), SLAVE_ADDR);
        bus_write(RegSlotI2CxAMR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 3: START / STOP detection
        ----------------------------------------------------------------
        report "=== GROUP 3: START/STOP detection ===" severity note;

        bus_write(RegSlotI2CxCR, x"00100000");           -- SEN=1 (enable detectors)
        i2c_start;
        bus_read(RegSlotI2CxSR, rdw);
        check_bit("START received flag (STR)", rdw(1), '1');
        check_bit("bus state active (BS)",     rdw(15), '1');
        i2c_stop;
        bus_read(RegSlotI2CxSR, rdw);
        check_bit("STOP received flag (SPR)", rdw(0), '1');
        check_bit("bus state idle (BS)",      rdw(15), '0');
        -- clear STR/SPR
        bus_write(RegSlotI2CxSR, x"00000003");
        bus_read(RegSlotI2CxSR, rdw);
        check_bit("STR cleared", rdw(1), '0');
        check_bit("SPR cleared", rdw(0), '0');

        ----------------------------------------------------------------
        -- GROUP 4: slave receive (address + data byte)
        ----------------------------------------------------------------
        report "=== GROUP 4: slave receive ===" severity note;

        bus_write(RegSlotI2CxAR, (31 downto 7 => '0') & SLAVE_ADDR);
        bus_write(RegSlotI2CxCR, x"00100000");           -- SEN=1, ACK (SN=0), no stretch

        i2c_start;
        i2c_byte(SLAVE_ADDR & '0');                      -- address + write
        i2c_get_ack(ackbit);
        check_bit("slave ACKs its address", ackbit, '0');
        bus_read(RegSlotI2CxSR, rdw);
        check_bit("slave addressed flag (SA)", rdw(12), '1');
        check_bit("slave transmitter mode off (write)", rdw(13), '0');

        i2c_byte(x"5A");                                 -- data byte
        i2c_get_ack(ackbit);
        check_bit("slave ACKs data byte", ackbit, '0');
        bus_read(RegSlotI2CxSR, rdw);
        check_bit("slave transfer complete (SXC)", rdw(8), '1');
        bus_read(RegSlotI2CxSRX, rdw);
        check_slv("slave received data 0x5A", rdw(7 downto 0), x"5A");
        i2c_stop;
        -- clear slave flags
        bus_write(RegSlotI2CxSR, x"00001100");           -- clear SXC(8) + SA(12)
        bus_write(RegSlotI2CxCR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 5: slave NOT addressed (wrong address)
        ----------------------------------------------------------------
        report "=== GROUP 5: wrong address ===" severity note;

        bus_write(RegSlotI2CxCR, x"00100000");           -- SEN=1
        i2c_start;
        i2c_byte("1010101" & '0');                       -- some other address
        i2c_get_ack(ackbit);
        check_bit("no ACK for wrong address", ackbit, '1');
        bus_read(RegSlotI2CxSR, rdw);
        check_bit("SA stays clear for wrong address", rdw(12), '0');
        i2c_stop;
        bus_write(RegSlotI2CxSR, x"00000003");
        bus_write(RegSlotI2CxCR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 6: interrupt enable / flag / clear
        ----------------------------------------------------------------
        report "=== GROUP 6: interrupts ===" severity note;

        -- STRIE = CR bit1; enable it, generate a START, expect irq_str
        bus_write(RegSlotI2CxCR, x"00100002");           -- SEN + STRIE
        i2c_start;
        check_bit("irq_str asserted (STR & STRIE)", irq_str, '1');
        bus_write(RegSlotI2CxSR, x"00000002");           -- clear STR (bit1)
        check_bit("irq_str cleared", irq_str, '0');
        i2c_stop;
        bus_write(RegSlotI2CxSR, x"00000003");
        bus_write(RegSlotI2CxCR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 7: master transmit (START, byte, NACK from empty bus, STOP)
        ----------------------------------------------------------------
        report "=== GROUP 7: master transmit ===" severity note;

        tb_sda_low <= '0'; tb_scl_low <= '0';            -- TB stays off the bus
        bus_write(RegSlotI2CxCR, x"00200000");           -- MEN=1, MDIV=0
        bus_write(RegSlotI2CxFCR, x"00000004");          -- I2CMST = send START
        wait for 40 * PERIOD;
        bus_read(RegSlotI2CxSR, rdw);
        check_bit("master controls bus (MCB)", rdw(14), '1');
        check_bit("master START sent (MSTS)",  rdw(7), '1');

        bus_write(RegSlotI2CxMTX, x"000000C3");          -- transmit a byte
        wait for 120 * PERIOD;
        bus_read(RegSlotI2CxSR, rdw);
        check_bit("master transfer complete (MXC)", rdw(2), '1');
        check_bit("master saw NACK (no slave)",     rdw(3), '1');

        bus_write(RegSlotI2CxFCR, x"00000002");          -- I2CMSP = send STOP
        wait for 60 * PERIOD;
        bus_read(RegSlotI2CxSR, rdw);
        check_bit("master STOP sent (MSPS)", rdw(6), '1');
        check_bit("master released bus (MCB=0)", rdw(14), '0');
        bus_write(RegSlotI2CxCR, x"00000000");

        ----------------------------------------------------------------
        -- Final verdict
        ----------------------------------------------------------------
        wait for 1 us;
        if error_count = 0 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##                                              ##" & LF &
                "    ##         I2C TB:  ALL CHECKS PASSED           ##" & LF &
                "    ##                                              ##" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!                                              !!" & LF &
                "    !!    I2C TB:  " & integer'image(error_count) &
                       " CHECK(S) FAILED" & LF &
                "    !!                                              !!" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        stop;
        wait;
    end process;

end architecture sim;
