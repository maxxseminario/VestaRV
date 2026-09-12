-- VestaRV: SPI testbench
-- standalone self-checking testbench for the SPI peripheral in its base configuration (ENABLE_EXTENDED_MEM = false), with the flash-side ports tied off inactive.
-- Coverage: register read/write, master transfers at 8/16/32 bits checked by MISO-driven-from-MOSI loopback, MSB-first and LSB-first ordering, CPOL idle level, busy/TC/TE flags with their interrupt lines and clear paths, and a basic slave-mode receive.
-- Support packages: periph_tb_pkg (scoreboard and register-bus BFM) and spi_bfm_pkg (external-master byte driver).
-- One free-running smclk drives both the SPI core and the gated register bus (clk_mem is smclk while en_mem is low).
-- Bus contract: en_mem and the per-lane wen are active-low, SR and RX return a snapshot latched on the falling edge of en_mem, and reading RX also clears the transmit-complete flag.

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
    constant SCK_HALF : time := 250 ns;     -- slave-drive SCK half period

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

    shared variable sb : scoreboard;

begin

    smclk   <= not smclk after PERIOD / 2;

    -- Register-bus clock runs only while the peripheral is selected (en_mem is active-low)
    clk_mem <= smclk when pbus.en_mem = '0' else '0';

    -- MISO loopback for master tests
    miso_in <= mosi_out when mloop = '1' else miso_drv;

    -- DUT in base configuration; the flash-side ports are held inactive
    dut : entity work.SPI
        generic map ( ENABLE_EXTENDED_MEM => false )
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

        -- Final verdict
        wait for 1 us;
        sb.report_summary("SPI TB");
        stop;
        wait;
    end process;

end architecture sim;
