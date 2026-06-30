-------------------------------------------------------------------------------
-- SPI_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the SPI peripheral
-- (hdl/MCU/periph/SPI.vhd) in its BASE configuration (ENABLE_EXTENDED_MEM =
-- false). The SPI-flash extended-memory path is intentionally NOT exercised
-- here; it gets its own bench later, so the flash ports are tied off inactive.
--
-- Coverage: register read/write, master-mode transfers at 8/16/32-bit data
-- lengths verified by MISO<-MOSI loopback (TX echoes back into RX), MSB-/LSB-
-- first ordering, CPOL idle level, the busy/TC/TE status flags and their
-- interrupt lines + clear paths, and a basic slave-mode receive.
--
-- Clocking: one free-running clock (smclk) drives both the SPI core (port clk)
-- and the gated register bus (clk_mem = smclk while en_mem='0'). The master's
-- SCK comes from the internal baud divider; SCBR=0 gives the fastest rate.
--
-- Bus contract (see tb/CLAUDE.md): en_mem active-low, wen active-low per byte
-- lane, SR/RX read a snapshot latched on the falling edge of en_mem; reading
-- the RX slot also clears the transmit-complete flag.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.constants.all;
use work.MemoryMap.all;

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

    -- register bus
    signal en_mem      : std_logic := '1';
    signal wen         : std_logic_vector(3 downto 0) := (others => '1');
    signal write_data  : word := (others => '0');
    signal read_data   : word;
    signal addr_periph : std_logic_vector(7 downto 2) := (others => '0');

    -- SPI pins
    signal cs_in    : std_logic := '1';
    signal sck_in   : std_logic := '0';
    signal sck_out, sck_dir, sck_ren : std_logic;
    signal sck_ren_in : std_logic := '0';
    signal mosi_in  : std_logic := '0';
    signal mosi_out, mosi_dir, mosi_ren : std_logic;
    signal mosi_ren_in : std_logic := '0';
    signal miso_in  : std_logic := '0';
    signal miso_out, miso_dir, miso_ren : std_logic;
    signal miso_ren_in : std_logic := '0';

    -- loopback control: when '1', MISO mirrors MOSI (master talks to itself)
    signal mloop    : std_logic := '0';
    signal miso_drv : std_logic := '0';

    -- flash ports (tied off; ENABLE_EXTENDED_MEM=false)
    signal rdata_flash     : word;
    signal disable_clk_cpu : std_logic;
    signal cs_flash_out, cs_flash_dir, cs_flash_ren : std_logic;

    function img(v : std_logic_vector) return string is
    begin
        if is_x(v) then return "X";
        else return integer'image(to_integer(unsigned(v))); end if;
    end function;

begin

    smclk   <= not smclk after PERIOD / 2;
    clk_mem <= smclk when en_mem = '0' else '0';

    -- MISO loopback for master tests
    miso_in <= mosi_out when mloop = '1' else miso_drv;

    dut : entity work.SPI
        generic map ( ENABLE_EXTENDED_MEM => false )
        port map (
            clk         => smclk,
            mclk        => '0',
            resetn      => resetn,
            irq_tc      => irq_tc,
            irq_te      => irq_te,
            clk_mem     => clk_mem,
            en_mem      => en_mem,
            wen         => wen,
            write_data  => write_data,
            read_data   => read_data,
            addr_periph => addr_periph,
            cs_in       => cs_in,
            sck_in      => sck_in,
            sck_out     => sck_out,
            sck_dir     => sck_dir,
            sck_ren     => sck_ren,
            sck_ren_in  => sck_ren_in,
            mosi_in     => mosi_in,
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

    stim_proc : process

        variable error_count : natural := 0;
        variable rdw         : word;

        procedure check_slv(tag : in string;
                            got : in std_logic_vector;
                            exp : in std_logic_vector) is
        begin
            if got = exp then
                report "PASS: " & tag severity note;
            else
                error_count := error_count + 1;
                assert false
                    report "FAIL: " & tag &
                           " (expected " & img(exp) & ", got " & img(got) & ")"
                    severity warning;
            end if;
        end procedure;

        procedure check_bit(tag : in string;
                            got : in std_logic;
                            exp : in std_logic) is
        begin
            if got = exp then
                report "PASS: " & tag severity note;
            else
                error_count := error_count + 1;
                assert false
                    report "FAIL: " & tag &
                           " (expected " & std_logic'image(exp) &
                           ", got " & std_logic'image(got) & ")"
                    severity warning;
            end if;
        end procedure;

        procedure bus_write(slot : in natural;
                            data : in std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(smclk);
            addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            write_data  <= data;
            wen         <= (others => '0');
            en_mem      <= '0';
            wait until rising_edge(smclk);
            wait until falling_edge(smclk);
            en_mem      <= '1';
            wen         <= (others => '1');
        end procedure;

        procedure bus_read(slot : in natural;
                           data : out std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(smclk);
            addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            en_mem      <= '0';
            wait until rising_edge(smclk);
            wait until falling_edge(smclk);
            data := read_data;
            en_mem      <= '1';
        end procedure;

        -- Poll the status register until the master clears BUSY (bounded).
        procedure wait_master_done is
            variable s : word;
            variable guard : natural := 0;
        begin
            loop
                bus_read(RegSlotSPIxSR, s);
                exit when s(2) = '0';
                guard := guard + 1;
                exit when guard > 200;
            end loop;
        end procedure;

        -- Drive one byte into the slave, LSB first, sampling on SCK falling.
        procedure slave_send_byte(d : in std_logic_vector(7 downto 0)) is
        begin
            for i in 0 to 7 loop
                mosi_in <= d(i);
                wait for SCK_HALF;
                sck_in  <= '1';        -- leading edge (slave shifts out)
                wait for SCK_HALF;
                sck_in  <= '0';        -- trailing edge (slave samples MOSI)
                wait for SCK_HALF;     -- hold MOSI past the edge (avoid sample race)
            end loop;
        end procedure;

    begin
        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------
        resetn <= '0';
        en_mem <= '1';
        wen    <= (others => '1');
        cs_in  <= '1';
        sck_in <= '0';
        mloop  <= '0';
        wait for 4 * PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 4 * PERIOD;

        ----------------------------------------------------------------
        -- GROUP 1: reset / defaults / pad directions
        ----------------------------------------------------------------
        report "=== GROUP 1: reset & defaults ===" severity note;

        bus_read(RegSlotSPIxCR, rdw);
        check_slv("CR resets to 0", rdw(19 downto 0), (19 downto 0 => '0'));
        bus_read(RegSlotSPIxSR, rdw);
        check_slv("SR resets to 0", rdw(2 downto 0), "000");
        bus_read(RegSlotSPIxTX, rdw);
        check_slv("TX resets to 0", rdw, x"00000000");

        check_bit("master drives SCK dir", sck_dir, '1');   -- spi_mode=0
        check_bit("master drives MOSI dir", mosi_dir, '1');
        check_bit("MISO tri-stated (master)", miso_dir, '0');
        check_bit("irq_tc low at reset", irq_tc, '0');
        check_bit("irq_te low at reset", irq_te, '0');

        sck_ren_in <= '1'; mosi_ren_in <= '1'; miso_ren_in <= '1';
        wait for 1 ns;
        check_bit("sck_ren passthrough",  sck_ren,  '1');
        check_bit("mosi_ren passthrough", mosi_ren, '1');
        check_bit("miso_ren passthrough", miso_ren, '1');
        sck_ren_in <= '0'; mosi_ren_in <= '0'; miso_ren_in <= '0';

        ----------------------------------------------------------------
        -- GROUP 2: control register read/write
        ----------------------------------------------------------------
        report "=== GROUP 2: control register ===" severity note;

        bus_write(RegSlotSPIxCR, x"000ABCDE");
        bus_read(RegSlotSPIxCR, rdw);
        check_slv("CR 20-bit readback", rdw(19 downto 0), x"ABCDE");
        check_slv("CR upper bits read 0", rdw(31 downto 20), x"000");
        bus_write(RegSlotSPIxCR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 3: master 8-bit transfer (loopback)
        ----------------------------------------------------------------
        report "=== GROUP 3: master 8-bit ===" severity note;

        mloop <= '1';
        bus_write(RegSlotSPIxCR, x"00000080");           -- en, master, 8-bit, mode0, LSB, br=0
        check_bit("SCK idles low (CPOL=0)", sck_out, '0');

        bus_write(RegSlotSPIxTX, x"000000A5");           -- start transfer of 0xA5
        bus_read(RegSlotSPIxSR, rdw);
        check_bit("busy asserted during transfer", rdw(2), '1');

        wait_master_done;
        bus_read(RegSlotSPIxSR, rdw);
        check_bit("TX-complete flag set",  rdw(1), '1');
        check_bit("TX-empty flag set",     rdw(0), '1');
        check_bit("busy cleared at end",   rdw(2), '0');
        bus_read(RegSlotSPIxTX, rdw);
        check_slv("TX readback 0xA5", rdw(7 downto 0), x"A5");
        bus_read(RegSlotSPIxRX, rdw);
        check_slv("RX == TX via loopback (0xA5)", rdw(7 downto 0), x"A5");

        ----------------------------------------------------------------
        -- GROUP 4: master 16-bit and 32-bit transfers (loopback)
        ----------------------------------------------------------------
        report "=== GROUP 4: master 16/32-bit ===" severity note;

        bus_write(RegSlotSPIxCR, x"00000084");           -- 16-bit
        bus_write(RegSlotSPIxTX, x"00001234");
        wait_master_done;
        bus_read(RegSlotSPIxRX, rdw);
        check_slv("RX == TX 16-bit (0x1234)", rdw(15 downto 0), x"1234");

        bus_write(RegSlotSPIxCR, x"00000088");           -- 32-bit
        bus_write(RegSlotSPIxTX, x"DEADBEEF");
        wait_master_done;
        bus_read(RegSlotSPIxRX, rdw);
        check_slv("RX == TX 32-bit (0xDEADBEEF)", rdw, x"DEADBEEF");

        ----------------------------------------------------------------
        -- GROUP 5: MSB-first ordering (loopback should still echo)
        ----------------------------------------------------------------
        report "=== GROUP 5: MSB-first ===" severity note;

        bus_write(RegSlotSPIxCR, x"000000C0");           -- en, master, 8-bit, MSB-first
        bus_write(RegSlotSPIxTX, x"0000005A");
        wait_master_done;
        bus_read(RegSlotSPIxRX, rdw);
        check_slv("RX == TX MSB-first (0x5A)", rdw(7 downto 0), x"5A");

        ----------------------------------------------------------------
        -- GROUP 6: CPOL idle level
        ----------------------------------------------------------------
        report "=== GROUP 6: CPOL ===" severity note;

        bus_write(RegSlotSPIxCR, x"00000082");           -- en, master, CPOL=1
        wait for 4 * PERIOD;
        check_bit("SCK idles high (CPOL=1)", sck_out, '1');
        bus_write(RegSlotSPIxCR, x"00000080");           -- back to CPOL=0
        wait for 4 * PERIOD;
        check_bit("SCK idles low (CPOL=0)", sck_out, '0');

        ----------------------------------------------------------------
        -- GROUP 7: interrupt lines + flag clearing
        ----------------------------------------------------------------
        report "=== GROUP 7: interrupts ===" severity note;

        bus_write(RegSlotSPIxCR, x"000000B0");           -- en, master, 8-bit, TCIE+TEIE
        bus_write(RegSlotSPIxTX, x"00000077");
        wait_master_done;
        check_bit("irq_tc asserted (TCIF & TCIE)", irq_tc, '1');
        check_bit("irq_te asserted (TEIF & TEIE)", irq_te, '1');

        bus_read(RegSlotSPIxRX, rdw);                    -- reading RX clears TC flag
        check_bit("irq_tc cleared by RX read", irq_tc, '0');

        bus_write(RegSlotSPIxSR, x"00000001");           -- write bit0 clears TE flag
        bus_read(RegSlotSPIxSR, rdw);
        check_bit("TX-empty flag cleared", rdw(0), '0');
        check_bit("irq_te cleared", irq_te, '0');

        bus_write(RegSlotSPIxCR, x"00000000");
        mloop <= '0';

        ----------------------------------------------------------------
        -- GROUP 8: slave-mode receive
        ----------------------------------------------------------------
        report "=== GROUP 8: slave receive ===" severity note;

        cs_in <= '1';
        bus_write(RegSlotSPIxCR, x"00040080");           -- en, slave, 8-bit, mode0, LSB
        check_bit("MISO dir input while deselected", miso_dir, '0');

        cs_in <= '0';                                    -- select slave
        wait for PERIOD;
        bus_read(RegSlotSPIxSR, rdw);
        check_bit("slave busy while CS low", rdw(2), '1');
        check_bit("MISO driven while selected", miso_dir, '1');

        slave_send_byte(x"3C");
        bus_read(RegSlotSPIxSR, rdw);
        check_bit("slave TX-complete flag set", rdw(1), '1');
        bus_read(RegSlotSPIxRX, rdw);
        check_slv("slave received 0x3C", rdw(7 downto 0), x"3C");

        cs_in <= '1';                                    -- deselect
        wait for PERIOD;
        bus_read(RegSlotSPIxSR, rdw);
        check_bit("slave not busy while CS high", rdw(2), '0');
        bus_write(RegSlotSPIxCR, x"00000000");

        ----------------------------------------------------------------
        -- Final verdict
        ----------------------------------------------------------------
        wait for 1 us;
        if error_count = 0 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##                                              ##" & LF &
                "    ##         SPI TB:  ALL CHECKS PASSED           ##" & LF &
                "    ##                                              ##" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!                                              !!" & LF &
                "    !!    SPI TB:  " & integer'image(error_count) &
                       " CHECK(S) FAILED" & LF &
                "    !!                                              !!" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        stop;
        wait;
    end process;

end architecture sim;
