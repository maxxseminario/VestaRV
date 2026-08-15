-------------------------------------------------------------------------------
-- I2C_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the I2C peripheral (hdl/myshkin/periph/I2C.vhd).
--
-- Uses the shared support packages: tb/periph_tb_pkg.vhd (scoreboard and register-bus BFM) and tb/i2c_bfm_pkg.vhd (I2C external-master driver).
--
-- The SDA/SCL bus is modelled as a real open-drain wired-AND: a line reads '0' when EITHER the DUT drives it (its *_DIR output is '1') or the master BFM pulls it (i2cm.*_low is '1'), and floats to '1' through the pull-up otherwise.
--
-- Coverage: register R/W and reset values, START/STOP detection, slave receive (address and data byte, ACK, flags, SRX capture), slave-not-addressed, interrupt flag/enable/clear, and a master transmit (START, byte, absent-slave NACK, STOP).
--
-- Bus contract: en_mem is active-low, wen is active-low per byte lane, and SR/SRX read a snapshot latched on the falling edge of en_mem.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.constants.all;
use work.MemoryMap.all;
use work.periph_tb_pkg.all;
use work.i2c_bfm_pkg.all;

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

    -- register bus (BFM record + observed rdata_out)
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal rdata_out : std_logic_vector(31 downto 0);

    -- pins
    signal SDA_IN, SDA_OUT, SDA_DIR, SDA_REN : std_logic;
    signal SDA_REN_in : std_logic := '0';
    signal SCL_IN, SCL_OUT, SCL_DIR, SCL_REN : std_logic;
    signal SCL_REN_in : std_logic := '0';

    -- TB-as-master open-drain pulls
    signal i2cm : i2c_master_t := I2C_MASTER_IDLE;

    shared variable sb : scoreboard;

begin

    smclk  <= not smclk after PERIOD / 2;

    -- Register-bus clock runs only while the peripheral is selected (en_mem is active-low)
    ClkMem <= smclk when pbus.en_mem = '0' else '0';

    -- Open-drain wired-AND with pull-up
    SDA_IN <= '0' when (SDA_DIR = '1' or i2cm.sda_low = '1') else '1';
    SCL_IN <= '0' when (SCL_DIR = '1' or i2cm.scl_low = '1') else '1';

    -- DUT with a zero power-on slave address; GROUP 2 programs the real one into AR
    dut : entity work.I2C
        generic map ( default_SAD => "0000000" )
        port map (
            smclk => smclk, resetn => resetn,
            irq_str => irq_str, irq_spr => irq_spr, irq_msts => irq_msts,
            irq_msps => irq_msps, irq_marb => irq_marb, irq_mtxe => irq_mtxe,
            irq_mnr => irq_mnr, irq_mxc => irq_mxc, irq_sa => irq_sa,
            irq_stxe => irq_stxe, irq_sovf => irq_sovf, irq_snr => irq_snr,
            irq_sxc => irq_sxc,
            ClkMem => ClkMem, EnMemPeriph => pbus.en_mem, WEn => pbus.wen,
            MABPart => pbus.addr_periph, wdata => pbus.write_data, rdata_out => rdata_out,
            SDA_IN => SDA_IN, SDA_OUT => SDA_OUT, SDA_DIR => SDA_DIR,
            SDA_REN_in => SDA_REN_in, SDA_REN => SDA_REN,
            SCL_IN => SCL_IN, SCL_OUT => SCL_OUT, SCL_DIR => SCL_DIR,
            SCL_REN_in => SCL_REN_in, SCL_REN => SCL_REN
        );

    -- Directed stimulus: seven check groups, then the scoreboard verdict
    stim_proc : process
        variable rdw    : std_logic_vector(31 downto 0);
        variable ackbit : std_logic;
    begin
        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------
        resetn <= '0';
        pbus <= PERIPH_BUS_IDLE;
        i2cm <= I2C_MASTER_IDLE;
        wait for 4 * PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 4 * PERIOD;

        ----------------------------------------------------------------
        -- GROUP 1: reset / defaults
        ----------------------------------------------------------------
        report "=== GROUP 1: reset & defaults ===" severity note;

        bus_read(smclk, pbus, rdata_out, RegSlotI2CxCR, rdw);
        sb.check_slv("CR resets to 0", rdw(21 downto 0), (21 downto 0 => '0'));
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_slv("SR resets to 0 (idle bus)", rdw(15 downto 0), x"0000");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxAR, rdw);
        sb.check_slv("AR = default_SAD (0)", rdw(6 downto 0), "0000000");

        sb.check_bit("SDA released at reset", SDA_DIR, '0');
        sb.check_bit("SCL released at reset", SCL_DIR, '0');
        sb.check_bit("irq_str low at reset", irq_str, '0');
        sb.check_bit("irq_sa low at reset",  irq_sa,  '0');

        SDA_REN_in <= '1'; SCL_REN_in <= '1';
        wait for 1 ns;
        sb.check_bit("SDA_REN passthrough", SDA_REN, '1');
        sb.check_bit("SCL_REN passthrough", SCL_REN, '1');
        SDA_REN_in <= '0'; SCL_REN_in <= '0';

        ----------------------------------------------------------------
        -- GROUP 2: register read/write
        ----------------------------------------------------------------
        report "=== GROUP 2: register R/W ===" severity note;

        bus_write(smclk, pbus, RegSlotI2CxCR, x"002ABCDE");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxCR, rdw);
        sb.check_slv("CR 22-bit readback", rdw(21 downto 0), "10" & x"ABCDE");
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00000000");

        bus_write(smclk, pbus, RegSlotI2CxCR, x"00200000");           -- MEN=1 (MTX write is MEN-gated)
        bus_write(smclk, pbus, RegSlotI2CxMTX, x"00000099");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxMTX, rdw);
        sb.check_slv("MTX readback", rdw(7 downto 0), x"99");
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00000000");
        bus_write(smclk, pbus, RegSlotI2CxSTX, x"00000066");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSTX, rdw);
        sb.check_slv("STX readback", rdw(7 downto 0), x"66");
        bus_write(smclk, pbus, RegSlotI2CxAR, (31 downto 7 => '0') & SLAVE_ADDR);
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxAR, rdw);
        sb.check_slv("AR readback", rdw(6 downto 0), SLAVE_ADDR);
        bus_write(smclk, pbus, RegSlotI2CxAMR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 3: START / STOP detection
        ----------------------------------------------------------------
        report "=== GROUP 3: START/STOP detection ===" severity note;

        bus_write(smclk, pbus, RegSlotI2CxCR, x"00100000");           -- SEN=1 (enable detectors)
        i2c_start(i2cm, T);
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("START received flag (STR)", rdw(1), '1');
        sb.check_bit("bus state active (BS)",     rdw(15), '1');
        i2c_stop(i2cm, T);
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("STOP received flag (SPR)", rdw(0), '1');
        sb.check_bit("bus state idle (BS)",      rdw(15), '0');
        -- Clear STR and SPR by writing ones back to them
        bus_write(smclk, pbus, RegSlotI2CxSR, x"00000003");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("STR cleared", rdw(1), '0');
        sb.check_bit("SPR cleared", rdw(0), '0');

        ----------------------------------------------------------------
        -- GROUP 4: slave receive (address + data byte)
        ----------------------------------------------------------------
        report "=== GROUP 4: slave receive ===" severity note;

        bus_write(smclk, pbus, RegSlotI2CxAR, (31 downto 7 => '0') & SLAVE_ADDR);
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00100000");           -- SEN=1, ACK (SN=0), no stretch

        i2c_start(i2cm, T);
        i2c_byte(i2cm, SLAVE_ADDR & '0', T);                          -- address + write
        i2c_get_ack(i2cm, SDA_IN, ackbit, T);
        sb.check_bit("slave ACKs its address", ackbit, '0');
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("slave addressed flag (SA)", rdw(12), '1');
        sb.check_bit("slave transmitter mode off (write)", rdw(13), '0');

        i2c_byte(i2cm, x"5A", T);                                     -- data byte
        i2c_get_ack(i2cm, SDA_IN, ackbit, T);
        sb.check_bit("slave ACKs data byte", ackbit, '0');
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("slave transfer complete (SXC)", rdw(8), '1');
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSRX, rdw);
        sb.check_slv("slave received data 0x5A", rdw(7 downto 0), x"5A");
        i2c_stop(i2cm, T);
        -- Clear the slave flags before the next group
        bus_write(smclk, pbus, RegSlotI2CxSR, x"00001100");           -- clears SXC (bit 8) and SA (bit 12)
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 5: slave NOT addressed (wrong address)
        ----------------------------------------------------------------
        report "=== GROUP 5: wrong address ===" severity note;

        bus_write(smclk, pbus, RegSlotI2CxCR, x"00100000");           -- SEN=1
        i2c_start(i2cm, T);
        i2c_byte(i2cm, "1010101" & '0', T);                          -- some other address
        i2c_get_ack(i2cm, SDA_IN, ackbit, T);
        sb.check_bit("no ACK for wrong address", ackbit, '1');
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("SA stays clear for wrong address", rdw(12), '0');
        i2c_stop(i2cm, T);
        bus_write(smclk, pbus, RegSlotI2CxSR, x"00000003");
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 6: interrupt enable / flag / clear
        ----------------------------------------------------------------
        report "=== GROUP 6: interrupts ===" severity note;

        -- STRIE is CR bit 1: enable it, generate a START, and expect irq_str
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00100002");           -- SEN + STRIE
        i2c_start(i2cm, T);
        sb.check_bit("irq_str asserted (STR & STRIE)", irq_str, '1');
        bus_write(smclk, pbus, RegSlotI2CxSR, x"00000002");           -- clear STR (bit1)
        sb.check_bit("irq_str cleared", irq_str, '0');
        i2c_stop(i2cm, T);
        bus_write(smclk, pbus, RegSlotI2CxSR, x"00000003");
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 7: master transmit (START, byte, NACK from empty bus, STOP)
        ----------------------------------------------------------------
        report "=== GROUP 7: master transmit ===" severity note;

        i2cm <= I2C_MASTER_IDLE;                          -- TB stays off the bus
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00200000");           -- MEN=1, MDIV=0
        bus_write(smclk, pbus, RegSlotI2CxFCR, x"00000004");          -- I2CMST: send START
        wait for 40 * PERIOD;
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("master controls bus (MCB)", rdw(14), '1');
        sb.check_bit("master START sent (MSTS)",  rdw(7), '1');

        bus_write(smclk, pbus, RegSlotI2CxMTX, x"000000C3");          -- transmit a byte
        wait for 120 * PERIOD;
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("master transfer complete (MXC)", rdw(2), '1');
        sb.check_bit("master saw NACK (no slave)",     rdw(3), '1');

        bus_write(smclk, pbus, RegSlotI2CxFCR, x"00000002");          -- I2CMSP: send STOP
        wait for 60 * PERIOD;
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("master STOP sent (MSPS)", rdw(6), '1');
        sb.check_bit("master released bus (MCB=0)", rdw(14), '0');
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00000000");

        ----------------------------------------------------------------
        -- Final verdict
        ----------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("I2C TB");
        stop;
        wait;
    end process;

end architecture sim;
