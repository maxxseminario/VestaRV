-- VestaRV: I2C testbench
-- standalone self-checking testbench for the I2C peripheral.
-- Coverage: register read/write and reset values, START/STOP detection, slave receive (address and data byte, ACK, flags, SRX capture), slave-not-addressed, interrupt flag/enable/clear, a master transmit (START, byte, absent-slave NACK, STOP), the same slave receive at the standard-mode clock ratio, repeated START with a slave transmit, clock stretching, and spike rejection.
-- GROUPS 1 to 10 are the COMPATIBILITY GROUP: they pass on the pin-clocked slave and on the oversampled one alike, and were run green on the pin-clocked RTL at these bus ratios before it moved. GROUP 11 is the one case only the oversampled sampler passes.
-- Support packages: periph_tb_pkg (scoreboard and register-bus BFM) and i2c_bfm_pkg (external-master driver).
-- SDA/SCL are modelled as a real open-drain wired-AND: a line reads '0' when either the DUT drives it (its *_DIR output is '1') or the master BFM pulls it (i2cm.*_low is '1'), and floats to '1' through the pull-up otherwise.
-- Bus contract: en_mem and the per-lane wen are active-low, and SR, MRX and SRX return a ClkMem copy sampled on the rising ClkMem edge of the access.
-- ClkMem must FREE-RUN here, as it does in the integration (MCU.vhd wires every peripheral's ClkMem to the ungated mclk): the status and receive words are carried into that domain by work.sync chains a gated clock would starve. The gated form this bench used until 2026-09-15 advanced ClkMem once per access and is not a shape the chip ever presents.

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
    /* I2C bus phase time. The BFM spends three phases per bit (set data, SCL
       high, SCL low), so the peripheral-clock-to-SCL ratio the DUT sees is
       3 * T / PERIOD and the SCL high phase is T.

       T and T_STD are the chip's two supported ratios scaled to this bench's
       10 MHz smclk: 61 is 24 MHz against 400 kHz fast mode, 244 is 24 MHz
       against 100 kHz standard mode. Both clear the minimum ratio of 32 the
       oversampled slave asserts at elaboration. Neither is a whole multiple of
       PERIOD, so the SCL and SDA edges walk through every phase of smclk over a
       byte instead of repeating one alignment.

       They were 400 ns (ratio 12) until 2026-09-15, which is 2 MHz SCL against
       a 24 MHz peripheral clock: faster than I2C defines and faster than any
       sampler can follow. The change is stimulus only, and the unchanged RTL
       was run green at these ratios before the sampler moved. */
    constant T      : time := 2033 ns;  -- fast mode, ratio 61
    constant T_STD  : time := 8117 ns;  -- standard mode, ratio 244

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

    -- Register-bus clock free-runs, as mclk does at the MCU.
    ClkMem <= smclk;

    -- Open-drain wired-AND with pull-up
    SDA_IN <= '0' when (SDA_DIR = '1' or i2cm.sda_low = '1') else '1';
    SCL_IN <= '0' when (SCL_DIR = '1' or i2cm.scl_low = '1') else '1';

    -- DUT with a zero power-on slave address; GROUP 2 programs the real one into AR
    dut : entity work.I2C
        -- PCLK_HZ / SCL_MAX_HZ are this bench's own numbers, not the chip's: smclk
        -- is 10 MHz here and the fastest SCL any group drives is 1 / (3 * T),
        -- which is 164 kHz. They carry the same ratio, 61, that the chip has at
        -- 24 MHz and 400 kHz, so the elaboration assert is graded on the bus the
        -- bench actually drives.
        generic map ( default_SAD => "0000000",
                      PCLK_HZ     => 10000000,
                      SCL_MAX_HZ  => 164000 )
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
        variable rbyte  : std_logic_vector(7 downto 0);

        -- periph_tb_pkg.bus_write always asserts all four lanes, so it cannot
        -- express a byte lane. This is that procedure with the lanes exposed.
        procedure bus_write_lanes(slot  : in natural;
                                  lanes : in std_logic_vector(3 downto 0);
                                  data  : in std_logic_vector(31 downto 0)) is
        begin
            wait until smclk = '0';
            pbus.addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            pbus.write_data  <= data;
            pbus.wen         <= lanes;
            pbus.en_mem      <= '0';
            wait until smclk = '1';
            wait until smclk = '0';
            pbus.en_mem <= '1';
            pbus.wen    <= (others => '1');
        end procedure;
    begin
        -- Reset
        resetn <= '0';
        pbus <= PERIPH_BUS_IDLE;
        i2cm <= I2C_MASTER_IDLE;
        wait for 4 * PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 4 * PERIOD;

        -- GROUP 1: reset / defaults
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

        -- GROUP 2: register read/write
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

        -- GROUP 2b: byte lanes, the implemented-bit mask, and the two words a
        -- write does not simply store. Added before the periph_regs migration
        -- (report R12e): nothing here was covered, and the shared BFM cannot
        -- drive a lane at all.
        report "=== GROUP 2b: lanes, masks and gated writes ===" severity note;

        bus_write(smclk, pbus, RegSlotI2CxCR, x"00000000");
        bus_write_lanes(RegSlotI2CxCR, "1110", x"00FFFFFF");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxCR, rdw);
        sb.check_slv("CR lane 0 alone moves bits 7:0", rdw(21 downto 0),
                     (21 downto 8 => '0') & x"FF");
        bus_write_lanes(RegSlotI2CxCR, "1101", x"00FFFFFF");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxCR, rdw);
        sb.check_slv("CR lane 1 alone moves bits 15:8", rdw(21 downto 0),
                     (21 downto 16 => '0') & x"FFFF");
        bus_write_lanes(RegSlotI2CxCR, "1011", x"00FFFFFF");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxCR, rdw);
        sb.check_slv("CR lane 2 alone moves bits 21:16", rdw(21 downto 0),
                     (21 downto 0 => '1'));
        bus_write_lanes(RegSlotI2CxCR, "0111", x"00000000");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxCR, rdw);
        sb.check_slv("CR lane 3 implements nothing and changes nothing",
                     rdw(21 downto 0), (21 downto 0 => '1'));
        bus_write(smclk, pbus, RegSlotI2CxCR, x"FFFFFFFF");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxCR, rdw);
        sb.check_slv("CR drops the write above bit 21", rdw, x"003FFFFF");
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00000000");

        bus_read(smclk, pbus, rdata_out, RegSlotI2CxFCR, rdw);
        sb.check_slv("FCR is write-1-only and reads 0", rdw, x"00000000");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxMRX, rdw);
        sb.check_slv("MRX reads 0 before any master receive", rdw, x"00000000");

        bus_write(smclk, pbus, RegSlotI2CxAMR, x"FFFFFFFF");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxAMR, rdw);
        sb.check_slv("AMR readback, seven bits wide", rdw, x"0000007F");
        bus_write(smclk, pbus, RegSlotI2CxAMR, x"00000000");

        -- MTX is the one storage word whose write is CONDITIONAL: it lands only
        -- while the master is enabled, because the write also launches a byte.
        bus_write(smclk, pbus, RegSlotI2CxMTX, x"000000A5");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxMTX, rdw);
        sb.check_slv("MTX write is dropped while MEN = 0", rdw(7 downto 0), x"99");

        bus_write(smclk, pbus, RegSlotI2CxSR, x"00001FFF");
        bus_write(smclk, pbus, RegSlotI2CxAR, (31 downto 7 => '0') & SLAVE_ADDR);

        -- GROUP 3: START / STOP detection
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

        -- GROUP 4: slave receive (address + data byte)
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

        -- GROUP 5: slave NOT addressed (wrong address)
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

        -- GROUP 6: interrupt enable / flag / clear
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

        -- GROUP 7: master transmit (START, byte, NACK from empty bus, STOP)
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

        /* GROUP 8: the standard-mode ratio, end to end.
           Same transaction as GROUP 4 at a quarter of the SCL rate, so the
           sampler is graded at both ends of the supported range rather than at
           one. The address mismatch is repeated here too: the ratio is what
           decides whether the seventh bit is sampled in the right SCL phase,
           and a sampler that drifts by one bit ACKs an address it should not. */
        report "=== GROUP 8: slave receive and mismatch, standard-mode ratio ===" severity note;

        bus_write(smclk, pbus, RegSlotI2CxAR, (31 downto 7 => '0') & SLAVE_ADDR);
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00100000");            -- SEN=1

        i2c_start(i2cm, T_STD);
        i2c_byte(i2cm, SLAVE_ADDR & '0', T_STD);
        i2c_get_ack(i2cm, SDA_IN, ackbit, T_STD);
        sb.check_bit("G8 slave ACKs its address at ratio 244", ackbit, '0');
        i2c_byte(i2cm, x"3C", T_STD);
        i2c_get_ack(i2cm, SDA_IN, ackbit, T_STD);
        sb.check_bit("G8 slave ACKs the data byte", ackbit, '0');
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSRX, rdw);
        sb.check_slv("G8 SRX holds 0x3C", rdw(7 downto 0), x"3C");
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("G8 slave transfer complete (SXC)", rdw(8), '1');
        i2c_stop(i2cm, T_STD);
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("G8 STOP received (SPR)", rdw(0), '1');
        sb.check_bit("G8 bus idle after STOP (BS)", rdw(15), '0');
        bus_write(smclk, pbus, RegSlotI2CxSR, x"00001FFF");

        i2c_start(i2cm, T_STD);
        i2c_byte(i2cm, "1010101" & '0', T_STD);
        i2c_get_ack(i2cm, SDA_IN, ackbit, T_STD);
        sb.check_bit("G8 no ACK for the wrong address", ackbit, '1');
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("G8 SA stays clear for the wrong address", rdw(12), '0');
        i2c_stop(i2cm, T_STD);
        bus_write(smclk, pbus, RegSlotI2CxSR, x"00001FFF");
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00000000");

        /* GROUP 9: repeated START and slave transmitter.
           A repeated START arrives with the bus already busy, so it is the one
           START the detector must catch without the bus first going idle, and
           it must reset the slave sequencer mid-transaction. The read phase
           after it then walks the whole slave-transmitter path: address with
           the read bit, ACK, eight bits out of I2CxSTX, master NACK, STOP. */
        report "=== GROUP 9: repeated START and slave transmit ===" severity note;

        bus_write(smclk, pbus, RegSlotI2CxSTX, x"000000A7");
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00100000");            -- SEN=1

        i2c_start(i2cm, T);
        i2c_byte(i2cm, SLAVE_ADDR & '0', T);
        i2c_get_ack(i2cm, SDA_IN, ackbit, T);
        sb.check_bit("G9 address ACK (write phase)", ackbit, '0');
        i2c_byte(i2cm, x"11", T);
        i2c_get_ack(i2cm, SDA_IN, ackbit, T);
        sb.check_bit("G9 data ACK (write phase)", ackbit, '0');
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSRX, rdw);
        sb.check_slv("G9 SRX holds the written byte", rdw(7 downto 0), x"11");
        bus_write(smclk, pbus, RegSlotI2CxSR, x"00001FFF");

        i2c_restart(i2cm, SCL_IN, T);
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("G9 repeated START seen (STR)", rdw(1), '1');
        sb.check_bit("G9 bus still active across the repeated START (BS)", rdw(15), '1');

        i2c_byte(i2cm, SLAVE_ADDR & '1', T);
        i2c_get_ack(i2cm, SDA_IN, ackbit, T);
        sb.check_bit("G9 address ACK (read phase)", ackbit, '0');
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("G9 slave addressed (SA)", rdw(12), '1');
        sb.check_bit("G9 slave transmitter mode (STM)", rdw(13), '1');

        i2c_read_byte(i2cm, SDA_IN, SCL_IN, rbyte, T);
        sb.check_slv("G9 slave transmits I2CxSTX", rbyte, x"A7");
        i2c_put_ack(i2cm, SCL_IN, '1', T);                             -- master NACKs
        i2c_stop(i2cm, T);
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("G9 STOP received after the read (SPR)", rdw(0), '1');
        bus_write(smclk, pbus, RegSlotI2CxSR, x"00001FFF");
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00000000");

        /* GROUP 10: clock stretching.
           With I2CSCS set the slave pulls SCL low for the whole ACK state and
           holds it there until firmware writes I2CSC. The stretch is visible on
           SCL_DIR while the master still has SCL low, and the master's ninth
           clock then waits on the wired-AND, which is what the _st BFM
           procedures add. */
        report "=== GROUP 10: clock stretching ===" severity note;

        bus_write(smclk, pbus, RegSlotI2CxCR, x"00140000");            -- SEN=1, SCS=1
        i2c_start(i2cm, T);
        i2c_byte_st(i2cm, SCL_IN, SLAVE_ADDR & '0', T);
        wait for 4 * PERIOD;
        sb.check_bit("G10 slave stretches SCL in the address ACK state", SCL_DIR, '1');
        bus_write(smclk, pbus, RegSlotI2CxFCR, x"00000008");           -- I2CSC: continue
        wait for 8 * PERIOD;
        sb.check_bit("G10 slave releases SCL after I2CSC", SCL_DIR, '0');
        i2c_get_ack_st(i2cm, SDA_IN, SCL_IN, ackbit, T);
        sb.check_bit("G10 address ACK under stretching", ackbit, '0');

        i2c_byte_st(i2cm, SCL_IN, x"5A", T);
        wait for 4 * PERIOD;
        sb.check_bit("G10 slave stretches SCL in the data ACK state", SCL_DIR, '1');
        bus_write(smclk, pbus, RegSlotI2CxFCR, x"00000008");           -- I2CSC: continue
        wait for 8 * PERIOD;
        i2c_get_ack_st(i2cm, SDA_IN, SCL_IN, ackbit, T);
        sb.check_bit("G10 data ACK under stretching", ackbit, '0');
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSRX, rdw);
        sb.check_slv("G10 SRX holds 0x5A", rdw(7 downto 0), x"5A");
        i2c_stop(i2cm, T);
        bus_write(smclk, pbus, RegSlotI2CxSR, x"00001FFF");
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00000000");

        /* GROUP 11: spike rejection. NOT part of the compatibility group.
           I2C fast mode requires a slave to suppress spikes up to 50 ns
           (UM10204 tSP). The pin-clocked detector cannot: any SDA falling edge
           while SCL is high is a START to it, whatever its width, and a 30 ns
           glitch left the pre-2026-09-15 design with STR set, the bus latched
           busy and the slave sequencer held in its start window with no SCL
           edge coming to retire it. The oversampled sampler passes a level only
           after three agreeing samples, so it rejects anything shorter than two
           peripheral clock periods, which is 83 ns at 24 MHz and 200 ns here.
           This group therefore FAILS on the old RTL by construction. */
        report "=== GROUP 11: spike rejection (new sampler only) ===" severity note;

        bus_write(smclk, pbus, RegSlotI2CxCR, x"00100000");            -- SEN=1
        bus_write(smclk, pbus, RegSlotI2CxSR, x"00001FFF");
        wait for 20 * PERIOD;                                          -- let the clear shadow retire

        i2cm.sda_low <= '1'; wait for 30 ns;                           -- 30 ns SDA spike
        i2cm.sda_low <= '0'; wait for 20 * PERIOD;
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("G11 a 30 ns SDA spike is not a START (STR)", rdw(1), '0');
        sb.check_bit("G11 a 30 ns SDA spike does not claim the bus (BS)", rdw(15), '0');

        i2c_start(i2cm, T);                                            -- a real START still lands
        wait for 8 * PERIOD;
        bus_read(smclk, pbus, rdata_out, RegSlotI2CxSR, rdw);
        sb.check_bit("G11 a real START after the spike still sets STR", rdw(1), '1');
        i2c_stop(i2cm, T);
        bus_write(smclk, pbus, RegSlotI2CxSR, x"00001FFF");
        bus_write(smclk, pbus, RegSlotI2CxCR, x"00000000");

        -- Final verdict
        wait for 1 us;
        sb.report_summary("I2C TB");
        stop;
        wait;
    end process;

end architecture sim;
