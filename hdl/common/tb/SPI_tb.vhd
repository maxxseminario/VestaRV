-- VestaRV: SPI testbench
-- standalone self-checking testbench for the SPI peripheral in its base configuration (ENABLE_EXTENDED_MEM = false), with the flash-side ports tied off inactive.
-- Coverage: register read/write, master transfers at 8/16/32 bits checked by MISO-driven-from-MOSI loopback, MSB-first and LSB-first ordering, CPOL idle level, busy/TC/TE flags with their interrupt lines and clear paths, a basic slave-mode receive, a 32-bit slave receive at an asynchronous SCK ratio, and a 32-bit slave TRANSMIT graded on the MISO bits an external master would latch.
-- GROUPS 1 to 11 all pass on the sck_slave-clocked slave and on the oversampled one alike, at the SCK rates this file now drives: the extended bench was run green on the pin-clocked RTL first, and GROUP 11's expected MISO stream is that run's recording.
-- Support packages: periph_tb_pkg (scoreboard and register-bus BFM) and spi_bfm_pkg (external-master byte driver).
-- One free-running smclk drives both the SPI core and the register bus.
-- clk_mem must FREE-RUN here, as it does in the integration: MCU.vhd wires every peripheral's ClkMem to the ungated mclk, and SR and RX are carried into that domain by work.sync chains a gated clock would starve. The gated form this bench used until 2026-09-15 advanced clk_mem once per access and is not a shape the chip ever presents.
-- Bus contract: en_mem and the per-lane wen are active-low, SR and RX return a clk_mem copy captured by periph_regs' read register on the rising clk_mem edge of the access, and reading RX also clears the transmit-complete flag.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.constants.all;
use work.MemoryMap.all;
use work.periph_tb_pkg.all;
use work.spi_bfm_pkg.all;

entity SPI_tb is
end entity SPI_tb;

architecture sim of SPI_tb is

    constant PERIOD   : time := 100 ns;     -- smclk period
    /* Slave SCK phase time. The BFM spends three phases per bit (set MOSI, SCK
       high, SCK low), so one SCK period is 3 * SCK_*, and the phase between the
       leading and the trailing edge -- the window in which the slave must have
       launched MISO -- is one SCK_*.

       Both were shorter until 2026-09-15 (250 ns and 137 ns, the latter 1.4
       smclk periods per phase). The oversampled slave needs four peripheral
       clock periods in that window, so they are now 450 ns and 417 ns, which
       are 4.5 and 4.2. The change is stimulus only: the unchanged RTL was run
       green at these SCK rates before the sampler moved.

       SCK_ASY still shares no common factor with the smclk period, so the
       sck_slave edges walk through every phase of smclk over one word instead
       of repeating one alignment. */
    constant SCK_HALF : time := 450 ns;     -- slave-drive SCK phase, 4.5 smclk periods
    constant SCK_ASY  : time := 417 ns;     -- asynchronous slave-drive SCK phase, 4.17 smclk periods

    -- clocks / reset
    signal smclk    : std_logic := '0';
    signal clk_mem  : std_logic := '0';
    signal resetn   : std_logic := '0';

    -- interrupts
    signal irq_tc, irq_te : std_logic;

    -- register bus (BFM record + observed read_data)
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal read_data : std_logic_vector(31 downto 0);

    -- SPI pins
    signal cs_in    : std_logic := '1';
    signal sck_out, sck_dir, sck_ren : std_logic;
    signal sck_ren_in : std_logic := '0';
    signal mosi_out, mosi_dir, mosi_ren : std_logic;
    signal mosi_ren_in : std_logic := '0';
    signal miso_in  : std_logic := '0';
    signal miso_out, miso_dir, miso_ren : std_logic;
    signal miso_ren_in : std_logic := '0';

    -- TB-as-external-master lines into the DUT slave port (sck_in / mosi_in)
    signal spie : spi_ext_master_t := SPI_EXT_MASTER_IDLE;

    -- loopback control: when '1', MISO mirrors MOSI (master talks to itself)
    signal mloop    : std_logic := '0';
    signal miso_drv : std_logic := '0';

    -- flash ports (tied off; ENABLE_EXTENDED_MEM=false)
    signal rdata_flash     : word;
    signal disable_clk_cpu : std_logic;
    signal cs_flash_out, cs_flash_dir, cs_flash_ren : std_logic;

    -- GROUP 10: sticky record of SPITEIF (through irq_te, i.e. the flag ANDed with SPITEIE) while the monitor is armed. TEIF is a register and stays set once set, so a mid-word set would still be visible on a later bus read; the monitor catches WHEN it set, which a bus read cannot.
    signal teif_mon_en  : std_logic := '0';
    signal teif_mon_hit : std_logic := '0';

    shared variable sb : scoreboard;

begin

    smclk   <= not smclk after PERIOD / 2;

    -- Armed only across the middle of a slave word; irq_te there means SPITEIF set while
    -- the word was still shifting, which is the failure the sck_slave-domain s_gap exists
    -- to prevent.
    teif_mon : process(smclk)
    begin
        if rising_edge(smclk) then
            if teif_mon_en = '0' then
                teif_mon_hit <= '0';
            elsif irq_te = '1' then
                teif_mon_hit <= '1';
            end if;
        end if;
    end process teif_mon;

    -- Register-bus clock free-runs, as mclk does at the MCU.
    clk_mem <= smclk;

    -- MISO loopback for master tests
    miso_in <= mosi_out when mloop = '1' else miso_drv;

    -- DUT in base configuration; the flash-side ports are held inactive
    dut : entity work.SPI
        -- PCLK_HZ / SCK_SLAVE_MAX_HZ are this bench's own numbers. clk is 10 MHz
        -- here, and the tightest MISO launch window any group drives is SCK_ASY,
        -- 417 ns, which is the half period of a 1.2 MHz SCK with an even duty.
        -- The ratio is therefore 8.3 against the minimum of 8, so the elaboration
        -- assert is graded at the limit rather than with slack.
        generic map ( ENABLE_EXTENDED_MEM => false,
                      PCLK_HZ             => 10000000,
                      SCK_SLAVE_MAX_HZ    => 1200000 )
        port map (
            clk         => smclk,
            mclk        => '0',
            resetn      => resetn,
            irq_tc      => irq_tc,
            irq_te      => irq_te,
            clk_mem     => clk_mem,
            en_mem      => pbus.en_mem,
            wen         => pbus.wen,
            write_data  => pbus.write_data,
            read_data   => read_data,
            addr_periph => pbus.addr_periph,
            cs_in       => cs_in,
            sck_in      => spie.sck,
            sck_out     => sck_out,
            sck_dir     => sck_dir,
            sck_ren     => sck_ren,
            sck_ren_in  => sck_ren_in,
            mosi_in     => spie.mosi,
            mosi_out    => mosi_out,
            mosi_dir    => mosi_dir,
            mosi_ren    => mosi_ren,
            mosi_ren_in => mosi_ren_in,
            miso_in     => miso_in,
            miso_out    => miso_out,
            miso_dir    => miso_dir,
            miso_ren    => miso_ren,
            miso_ren_in => miso_ren_in,
            en_mem_flash    => '1',
            clk_mem_flash   => '0',
            mab             => (others => '0'),
            rdata_flash     => rdata_flash,
            disable_clk_cpu => disable_clk_cpu,
            cs_flash_out    => cs_flash_out,
            cs_flash_dir    => cs_flash_dir,
            cs_flash_ren    => cs_flash_ren
        );

    -- Directed stimulus: nine check groups, then the scoreboard verdict
    stim_proc : process
        variable rdw : std_logic_vector(31 downto 0);

        -- GROUP 10 payloads: dense bit patterns, so a word taken one carry early or one
        -- bit misaligned reads back wrong rather than by luck the same.
        type slave_word_arr is array (0 to 1) of std_logic_vector(31 downto 0);
        constant SLAVE_WORDS : slave_word_arr := (x"C3A55A3C", x"0F7E81F0");
        variable sword : std_logic_vector(31 downto 0);

        -- GROUP 11: the word the slave transmits, and the 32 MISO bits an external
        -- master latches for it. SLAVE_TX_MISO is a RECORDING of the pin-clocked
        -- slave at this SCK rate, not a derivation. It comes out equal to the
        -- transmit word because the shift register's reload branch has priority
        -- over its shift branch while the slave counter reads zero, so bit 0 is
        -- held through the first bit period and bit k is presented in period k.
        -- That priority is load-bearing and the oversampled rewrite keeps it.
        constant SLAVE_TX_WORD : std_logic_vector(31 downto 0) := x"5AC33C5A";
        constant SLAVE_TX_MISO : std_logic_vector(31 downto 0) := x"5AC33C5A";
        variable misobit   : std_logic;
        variable miso_seen : std_logic_vector(31 downto 0) := (others => '0');

        -- Poll the status register until the master clears BUSY (bounded).
        procedure wait_master_done is
            variable s : std_logic_vector(31 downto 0);
            variable guard : natural := 0;
        begin
            loop
                bus_read(smclk, pbus, read_data, RegSlotSPIxSR, s);
                exit when s(2) = '0';
                guard := guard + 1;
                exit when guard > 200;
            end loop;
        end procedure;

        -- Write with only SOME byte lanes enabled. periph_tb_pkg.bus_write always
        -- drives all four, so it cannot grade a lane at all; this is the same
        -- access shape with WEn under the caller's control.
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

        -- One 8-bit master transfer in loopback, to arm SPITCIF / SPITEIF.
        procedure arm_flags(d : in std_logic_vector(7 downto 0)) is
        begin
            bus_write(smclk, pbus, RegSlotSPIxTX, x"000000" & d);
            wait_master_done;
        end procedure;

        -- One SCK period driving a single bit into the slave port, the same shape
        -- spi_ext_send_byte uses. GROUP 10 needs bit granularity because it has to stop
        -- one bit short of the word boundary, where SPITEIF is allowed to set.
        procedure spi_ext_send_bit(signal e : inout spi_ext_master_t;
                                   b : in std_logic; half : in time) is
        begin
            e.mosi <= b;   wait for half;
            e.sck  <= '1'; wait for half;   -- leading edge (slave shifts out)
            e.sck  <= '0'; wait for half;   -- trailing edge (slave samples MOSI)
        end procedure;

        -- The same bit, with the MISO sample a real master would take. The slave
        -- launches MISO from the LEADING edge and the master reads it at the
        -- TRAILING edge, so q is what an external master would latch and the check
        -- on it is a check on the launch latency: exactly what oversampling costs.
        procedure spi_ext_xfer_bit(signal e : inout spi_ext_master_t;
                                   b : in std_logic; half : in time;
                                   signal miso : in std_logic;
                                   q : out std_logic) is
        begin
            e.mosi <= b;   wait for half;
            e.sck  <= '1'; wait for half;   -- leading edge (slave shifts out)
            q := miso;                      -- the master samples at the trailing edge
            e.sck  <= '0'; wait for half;   -- trailing edge (slave samples MOSI)
        end procedure;

    begin
        -- Reset
        resetn <= '0';
        pbus   <= PERIPH_BUS_IDLE;
        spie   <= SPI_EXT_MASTER_IDLE;
        cs_in  <= '1';
        mloop  <= '0';
        wait for 4 * PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 4 * PERIOD;

        -- GROUP 1: reset / defaults / pad directions
        report "=== GROUP 1: reset & defaults ===" severity note;

        bus_read(smclk, pbus, read_data, RegSlotSPIxCR, rdw);
        sb.check_slv("CR resets to 0", rdw(19 downto 0), (19 downto 0 => '0'));
        bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
        sb.check_slv("SR resets to 0", rdw(2 downto 0), "000");
        bus_read(smclk, pbus, read_data, RegSlotSPIxTX, rdw);
        sb.check_slv("TX resets to 0", rdw, x"00000000");

        sb.check_bit("master drives SCK dir", sck_dir, '1');   -- spi_mode=0
        sb.check_bit("master drives MOSI dir", mosi_dir, '1');
        sb.check_bit("MISO tri-stated (master)", miso_dir, '0');
        sb.check_bit("irq_tc low at reset", irq_tc, '0');
        sb.check_bit("irq_te low at reset", irq_te, '0');

        sck_ren_in <= '1'; mosi_ren_in <= '1'; miso_ren_in <= '1';
        wait for 1 ns;
        sb.check_bit("sck_ren passthrough",  sck_ren,  '1');
        sb.check_bit("mosi_ren passthrough", mosi_ren, '1');
        sb.check_bit("miso_ren passthrough", miso_ren, '1');
        sck_ren_in <= '0'; mosi_ren_in <= '0'; miso_ren_in <= '0';

        -- GROUP 2: control register read/write
        report "=== GROUP 2: control register ===" severity note;

        bus_write(smclk, pbus, RegSlotSPIxCR, x"000ABCDE");
        bus_read(smclk, pbus, read_data, RegSlotSPIxCR, rdw);
        sb.check_slv("CR 20-bit readback", rdw(19 downto 0), x"ABCDE");
        sb.check_slv("CR upper bits read 0", rdw(31 downto 20), x"000");
        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000000");

        -- GROUP 3: master 8-bit transfer (loopback)
        report "=== GROUP 3: master 8-bit ===" severity note;

        mloop <= '1';
        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000080");   -- en, master, 8-bit, mode0, LSB, br=0
        sb.check_bit("SCK idles low (CPOL=0)", sck_out, '0');

        bus_write(smclk, pbus, RegSlotSPIxTX, x"000000A5");   -- start transfer of 0xA5
        bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
        sb.check_bit("busy asserted during transfer", rdw(2), '1');

        wait_master_done;
        bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
        sb.check_bit("TX-complete flag set",  rdw(1), '1');
        sb.check_bit("TX-empty flag set",     rdw(0), '1');
        sb.check_bit("busy cleared at end",   rdw(2), '0');
        bus_read(smclk, pbus, read_data, RegSlotSPIxTX, rdw);
        sb.check_slv("TX readback 0xA5", rdw(7 downto 0), x"A5");
        bus_read(smclk, pbus, read_data, RegSlotSPIxRX, rdw);
        sb.check_slv("RX == TX via loopback (0xA5)", rdw(7 downto 0), x"A5");

        -- GROUP 4: master 16-bit and 32-bit transfers (loopback)
        report "=== GROUP 4: master 16/32-bit ===" severity note;

        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000084");   -- 16-bit
        bus_write(smclk, pbus, RegSlotSPIxTX, x"00001234");
        wait_master_done;
        bus_read(smclk, pbus, read_data, RegSlotSPIxRX, rdw);
        sb.check_slv("RX == TX 16-bit (0x1234)", rdw(15 downto 0), x"1234");

        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000088");   -- 32-bit
        bus_write(smclk, pbus, RegSlotSPIxTX, x"DEADBEEF");
        wait_master_done;
        bus_read(smclk, pbus, read_data, RegSlotSPIxRX, rdw);
        sb.check_slv("RX == TX 32-bit (0xDEADBEEF)", rdw, x"DEADBEEF");

        -- GROUP 5: MSB-first ordering (loopback should still echo)
        report "=== GROUP 5: MSB-first ===" severity note;

        bus_write(smclk, pbus, RegSlotSPIxCR, x"000000C0");   -- en, master, 8-bit, MSB-first
        bus_write(smclk, pbus, RegSlotSPIxTX, x"0000005A");
        wait_master_done;
        bus_read(smclk, pbus, read_data, RegSlotSPIxRX, rdw);
        sb.check_slv("RX == TX MSB-first (0x5A)", rdw(7 downto 0), x"5A");

        -- GROUP 6: CPOL idle level
        report "=== GROUP 6: CPOL ===" severity note;

        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000082");   -- en, master, CPOL=1
        wait for 4 * PERIOD;
        sb.check_bit("SCK idles high (CPOL=1)", sck_out, '1');
        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000080");   -- back to CPOL=0
        wait for 4 * PERIOD;
        sb.check_bit("SCK idles low (CPOL=0)", sck_out, '0');

        -- GROUP 7: interrupt lines + flag clearing
        report "=== GROUP 7: interrupts ===" severity note;

        bus_write(smclk, pbus, RegSlotSPIxCR, x"000000B0");   -- en, master, 8-bit, TCIE+TEIE
        bus_write(smclk, pbus, RegSlotSPIxTX, x"00000077");
        wait_master_done;
        sb.check_bit("irq_tc asserted (TCIF & TCIE)", irq_tc, '1');
        sb.check_bit("irq_te asserted (TEIF & TEIE)", irq_te, '1');

        bus_read(smclk, pbus, read_data, RegSlotSPIxRX, rdw); -- reading RX clears TC flag
        sb.check_bit("irq_tc cleared by RX read", irq_tc, '0');

        bus_write(smclk, pbus, RegSlotSPIxSR, x"00000001");   -- write bit0 clears TE flag
        bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
        sb.check_bit("TX-empty flag cleared", rdw(0), '0');
        sb.check_bit("irq_te cleared", irq_te, '0');

        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000000");
        mloop <= '0';

        -- GROUP 8: slave-mode receive
        report "=== GROUP 8: slave receive ===" severity note;

        cs_in <= '1';
        bus_write(smclk, pbus, RegSlotSPIxCR, x"00040080");   -- en, slave, 8-bit, mode0, LSB
        sb.check_bit("MISO dir input while deselected", miso_dir, '0');

        cs_in <= '0';                                    -- select slave
        wait for PERIOD;
        bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
        sb.check_bit("slave busy while CS low", rdw(2), '1');
        sb.check_bit("MISO driven while selected", miso_dir, '1');

        spi_ext_send_byte(spie, x"3C", SCK_HALF);
        bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
        sb.check_bit("slave TX-complete flag set", rdw(1), '1');
        bus_read(smclk, pbus, read_data, RegSlotSPIxRX, rdw);
        sb.check_slv("slave received 0x3C", rdw(7 downto 0), x"3C");

        cs_in <= '1';                                    -- deselect
        wait for PERIOD;
        bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
        sb.check_bit("slave not busy while CS high", rdw(2), '0');
        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000000");

        -- GROUP 9: byte lanes, unimplemented bits and the access side effects.
        -- Added 2026-09-11 (R12d) BEFORE the periph_regs migration: bus_write
        -- drives all four lanes, so nothing here had ever graded a lane; nothing
        -- had written a 1 into a bit a register does not implement; nothing had
        -- touched SPIxFOS, which SPI1 must ignore; and the SPITCIF clear had only
        -- ever been exercised by a READ of SPIxRX, not by a write, although the
        -- decode retires it on ANY access to that slot.
        report "=== GROUP 9: lanes, unimplemented bits, access side effects ===" severity note;

        mloop <= '1';
        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000080");   -- en, master, 8-bit, mode0, LSB

        -- SPIxTX is the only 32-bit-wide store here; grade every lane on it.
        arm_flags(x"00");
        bus_write(smclk, pbus, RegSlotSPIxTX, x"00000000");
        wait_master_done;
        bus_write_lanes(RegSlotSPIxTX, "1110", x"FFFFFF11");
        wait_master_done;
        bus_read(smclk, pbus, read_data, RegSlotSPIxTX, rdw);
        sb.check_slv("TX lane 0 alone moves bits 7:0", rdw, x"00000011");
        bus_write_lanes(RegSlotSPIxTX, "1011", x"FF22FFFF");
        wait_master_done;
        bus_read(smclk, pbus, read_data, RegSlotSPIxTX, rdw);
        sb.check_slv("TX lane 2 alone moves bits 23:16", rdw, x"00220011");
        bus_write_lanes(RegSlotSPIxTX, "0111", x"33FFFFFF");
        wait_master_done;
        bus_read(smclk, pbus, read_data, RegSlotSPIxTX, rdw);
        sb.check_slv("TX lane 3 alone moves bits 31:24", rdw, x"33220011");

        -- Writing SPIxRX retires SPITCIF exactly as reading it does.
        arm_flags(x"6B");
        bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
        sb.check_bit("TC flag set before the RX write", rdw(1), '1');
        bus_write(smclk, pbus, RegSlotSPIxRX, x"00000000");
        bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
        sb.check_bit("a WRITE to RX clears the TC flag too", rdw(1), '0');
        bus_read(smclk, pbus, read_data, RegSlotSPIxRX, rdw);
        sb.check_slv("RX is read-only: the write stored nothing", rdw(7 downto 0), x"6B");

        -- The SPIxSR write-1-to-clear arm is lane-0 qualified, and SPIBUSY ignores writes.
        arm_flags(x"7C");
        bus_write_lanes(RegSlotSPIxSR, "1101", x"00000002");
        bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
        sb.check_bit("SR write without lane 0 does not clear TC", rdw(1), '1');
        bus_write_lanes(RegSlotSPIxSR, "1110", x"00000004");
        bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
        sb.check_bit("writing SPIBUSY is inert", rdw(1), '1');
        bus_write_lanes(RegSlotSPIxSR, "1110", x"00000003");
        bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
        sb.check_bit("SR lane-0 write clears TC", rdw(1), '0');
        sb.check_bit("SR lane-0 write clears TE", rdw(0), '0');

        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000000");
        mloop <= '0';

        -- SPIxCR byte lanes and the bits above SPIFEN.
        bus_write_lanes(RegSlotSPIxCR, "1110", x"FFFFFF5A");
        bus_read(smclk, pbus, read_data, RegSlotSPIxCR, rdw);
        sb.check_slv("CR lane 0 alone moves bits 7:0", rdw, x"0000005A");
        bus_write_lanes(RegSlotSPIxCR, "1101", x"FFFFA5FF");
        bus_read(smclk, pbus, read_data, RegSlotSPIxCR, rdw);
        sb.check_slv("CR lane 1 alone moves bits 15:8", rdw, x"0000A55A");
        bus_write_lanes(RegSlotSPIxCR, "1011", x"FFFDFFFF");
        bus_read(smclk, pbus, read_data, RegSlotSPIxCR, rdw);
        sb.check_slv("CR lane 2 moves only bits 19:16", rdw, x"000DA55A");
        bus_write_lanes(RegSlotSPIxCR, "0111", x"FFFFFFFF");
        bus_read(smclk, pbus, read_data, RegSlotSPIxCR, rdw);
        sb.check_slv("CR lane 3 holds no CR bit", rdw, x"000DA55A");
        bus_write(smclk, pbus, RegSlotSPIxCR, x"FFFFFFFF");
        bus_read(smclk, pbus, read_data, RegSlotSPIxCR, rdw);
        sb.check_slv("CR implements exactly bits 19:0", rdw, x"000FFFFF");
        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000000");

        -- SPIxFOS exists on SPI0 only; this DUT is ENABLE_EXTENDED_MEM = false.
        bus_read(smclk, pbus, read_data, RegSlotSPIxFOS, rdw);
        sb.check_slv("FOS reads 0 without extended memory", rdw, x"00000000");
        bus_write(smclk, pbus, RegSlotSPIxFOS, x"00ABCDEF");
        bus_read(smclk, pbus, read_data, RegSlotSPIxFOS, rdw);
        sb.check_slv("FOS still reads 0 after a write", rdw, x"00000000");

        -- A slot past the register set reads 0.
        bus_read(smclk, pbus, read_data, 17, rdw);
        sb.check_slv("an unmapped slot reads 0", rdw, x"00000000");

        /* GROUP 10: 32-bit slave transfers at an asynchronous SCK ratio, grading that
           SPITEIF never sets mid-word.
           SPITEIF means "the transmit shift register may be refilled", and the hardware
           condition for that is the inter-transfer gap. Until W10 the gap was read on
           clk as the combinational zero decode of s_counter, a six-bit BINARY counter
           clocked by the external SCK pad. At a carry the falling bits can reach the
           decode before the rising one (000111 -> 001000 passes through 000000), so a
           clk edge inside that window set the flag in the middle of a word and firmware
           refilled SPIxTX a word early (W5b-2). 8-bit mode never carries; 16-bit mode
           carries once per word and 32-bit twice, so 32-bit is the case to drive.
           The gap is now a flop in the sck_slave domain carried through work.sync, so
           what clk samples is one bit that changes only on an SCK edge.
           SCK_ASY shares no factor with the smclk period, so the 32 sample edges land at
           32 different phases of smclk and the second word starts a further 23 ns off.
           The monitor is armed from one bit into the word to one bit short of its end;
           both the 8 and the 16 and the 24 carries fall inside that window. */
        report "=== GROUP 10: slave 32-bit, async SCK, TEIF never mid-word ===" severity note;

        cs_in <= '1';
        spie  <= SPI_EXT_MASTER_IDLE;
        wait for PERIOD;
        -- en, slave, 32-bit, mode0, LSB-first, TEIE so irq_te mirrors SPITEIF
        bus_write(smclk, pbus, RegSlotSPIxCR, x"00040098");
        cs_in <= '0';
        wait for PERIOD;

        for w in 0 to 1 loop
            sword := SLAVE_WORDS(w);

            -- Bit 0 first: it takes the slave counter off zero, so the gap flag drops
            -- and SPITEIF can be cleared without immediately setting again.
            spi_ext_send_bit(spie, sword(0), SCK_ASY);
            bus_write(smclk, pbus, RegSlotSPIxSR, x"00000001");   -- W1C SPITEIF
            bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
            sb.check_bit("GROUP10 word " & integer'image(w)
                         & ": TEIF cleared one bit into the word", rdw(0), '0');
            sb.check_bit("GROUP10 word " & integer'image(w)
                         & ": irq_te low one bit into the word", irq_te, '0');

            teif_mon_en <= '1';
            wait until smclk = '1';
            wait until smclk = '0';
            for b in 1 to 30 loop
                spi_ext_send_bit(spie, sword(b), SCK_ASY);
            end loop;
            wait until smclk = '1';
            sb.check_bit("GROUP10 word " & integer'image(w)
                         & ": TEIF never set across bits 1 to 30, carries at 8, 16 and 24",
                         teif_mon_hit, '0');
            teif_mon_en <= '0';
            wait until smclk = '0';

            -- The last bit closes the word: the gap opens and SPITEIF is due.
            spi_ext_send_bit(spie, sword(31), SCK_ASY);
            wait for 8 * PERIOD;
            bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
            sb.check_bit("GROUP10 word " & integer'image(w)
                         & ": TEIF set at the end of the word", rdw(0), '1');
            sb.check_bit("GROUP10 word " & integer'image(w)
                         & ": TCIF set at the end of the word", rdw(1), '1');
            bus_read(smclk, pbus, read_data, RegSlotSPIxRX, rdw);
            sb.check_slv("GROUP10 word " & integer'image(w) & ": slave received the word",
                         rdw, sword);
            bus_write(smclk, pbus, RegSlotSPIxSR, x"00000003");   -- retire TEIF and TCIF
            wait for 23 ns;                                       -- shift the next word's phase
        end loop;

        cs_in <= '1';
        wait for PERIOD;
        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000000");

        /* GROUP 11: slave TRANSMIT at the asynchronous SCK ratio.
           Nothing in this bench graded MISO before, and MISO is the half of the
           slave that oversampling puts at risk: the shift register is launched
           from the SCK leading edge and the master reads it at the trailing
           edge, so the slave has one SCK phase to get the bit out. A pin-clocked
           slave launches at the edge; an oversampled one launches two
           synchroniser edges and one edge-decode edge later, which is what fixes
           the maximum slave SCK at an eighth of the peripheral clock rather than
           the quarter the receive path alone would allow.
           The expected MISO stream is the ORACLE: it was recorded from the
           pin-clocked slave at this SCK rate before the sampler moved, and the
           oversampled slave must reproduce it bit for bit. Both words are dense,
           so one bit of slip reads back wrong rather than by luck the same. */
        report "=== GROUP 11: slave transmit, MISO launched from the SCK edge ===" severity note;

        cs_in <= '1';
        spie  <= SPI_EXT_MASTER_IDLE;
        wait for PERIOD;
        bus_write(smclk, pbus, RegSlotSPIxCR, x"00040098");   -- en, slave, 32-bit, mode0, LSB
        bus_write(smclk, pbus, RegSlotSPIxTX, SLAVE_TX_WORD);
        cs_in <= '0';
        wait for PERIOD;

        sword := SLAVE_WORDS(0);
        for b in 0 to 31 loop
            spi_ext_xfer_bit(spie, sword(b), SCK_ASY, miso_out, misobit);
            miso_seen(b) := misobit;
        end loop;
        wait for 8 * PERIOD;

        sb.check_slv("GROUP11: MISO stream matches the transmit word",
                     miso_seen, SLAVE_TX_MISO);
        bus_read(smclk, pbus, read_data, RegSlotSPIxSR, rdw);
        sb.check_bit("GROUP11: TCIF set at the end of the word", rdw(1), '1');
        -- RX last: any access to that slot retires SPITCIF.
        bus_read(smclk, pbus, read_data, RegSlotSPIxRX, rdw);
        sb.check_slv("GROUP11: the same transfer still receives the word", rdw, sword);

        cs_in <= '1';
        wait for PERIOD;
        bus_write(smclk, pbus, RegSlotSPIxSR, x"00000003");
        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000000");

        -- Final verdict
        wait for 1 us;
        sb.report_summary("SPI TB");
        stop;
        wait;
    end process;

end architecture sim;
