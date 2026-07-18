-------------------------------------------------------------------------------
-- SPI_flash_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the SPI peripheral's EXTENDED-MEMORY
-- (SPI-flash XIP) path -- hdl/common/periph/SPI.vhd built with
-- ENABLE_EXTENDED_MEM = true, wired to the AT45DB021E behavioral flash model
-- (hdl/common/tb/serial_flash.vhd). The RISC-V core is NOT in this bench: the
-- testbench itself plays the role of the tile's adddec, driving the flash
-- request interface (en_mem_flash / clk_mem_flash / mab) and consuming
-- rdata_flash / disable_clk_cpu exactly the way adddec.vhd does for a
-- data_addr >= 0x20000 access.
--
-- What it exercises (none of which the ISA/behavioral regressions touch, since
-- those tests run entirely from TCM and never fetch across the XIP boundary):
--
--   * The deep-power-down wake-up handshake: the flash model boots asleep and
--     only honours reads after a correctly CS-framed 0xAB (resume) opcode +
--     tRDPD (35 us). The bench issues that wake as a normal 8-bit master
--     transfer (spi_fen = 0), then waits on the model's `awake` output.
--   * The XIP read FSM: on a flash request it drives CS low, streams opcode
--     0x0B (Continuous Array Read, High-Frequency), a 24-bit address =
--     mab(23:0)+SPIxFOS, a dummy byte, then clocks a 32-bit word back.
--   * SPIxFOS (flash address offset register): programmed to 0xFE0000 so a
--     realistic XIP address 0x20000+4*i maps to flash word i (0x020000 +
--     0xFE0000 wraps to 0x000000 in the 24-bit adder).
--   * The 32-bit read data alignment (SPIxCR rx-swap-bytes + MSB-first + 32-bit
--     length) that turns the MISO byte stream back into the stored little-
--     endian word, checked against a known flash image.
--   * disable_clk_cpu asserting for the duration of every access (the core
--     stall) and returning low when the word is ready.
--
-- Flash image: ../rcf/spiflash_xiptest_a.rcf (32 binary chars per line, one
-- 32-bit word MSB-first). Word i == expected XIP read at 0x20000+4*i.
--
-- Support: tb/periph_tb_pkg.vhd (scoreboard + register-bus BFM). The register
-- bus contract (en_mem/wen active-low, gated clk_mem) is the same as SPI_tb.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.constants.all;
use work.MemoryMap.all;
use work.periph_tb_pkg.all;

entity SPI_flash_tb is
end entity SPI_flash_tb;

architecture sim of SPI_flash_tb is

    constant SM_PERIOD : time := 100 ns;    -- smclk period (SPI core + baud)
    constant MC_PERIOD : time :=  40 ns;    -- mclk period (flash-clear synchronizer)

    -- clocks / reset
    signal smclk   : std_logic := '0';
    signal mclk    : std_logic := '0';
    signal clk_mem : std_logic := '0';
    signal resetn  : std_logic := '1';      -- starts HIGH so the 1->0 edge below
                                            -- gives serial_flash a clean mem_reset

    -- interrupts (observed, not central here)
    signal irq_tc, irq_te : std_logic;

    -- register bus (BFM record + observed read_data)
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal read_data : std_logic_vector(31 downto 0);

    -- SPI pads
    signal cs_in    : std_logic := '1';
    signal sck_out, sck_dir, sck_ren : std_logic;
    signal sck_ren_in : std_logic := '0';
    signal mosi_out, mosi_dir, mosi_ren : std_logic;
    signal mosi_ren_in : std_logic := '0';
    signal miso_in  : std_logic := '0';
    signal miso_out, miso_dir, miso_ren : std_logic;
    signal miso_ren_in : std_logic := '0';

    -- SPI-flash XIP request interface (this bench == adddec)
    signal en_mem_flash     : std_logic := '1';   -- active-low request
    signal en_clk_mem_flash : std_logic;
    signal clk_mem_flash    : std_logic;
    signal mab              : std_logic_vector(31 downto 0) := (others => '0');
    signal rdata_flash      : std_logic_vector(31 downto 0);
    signal disable_clk_cpu  : std_logic;

    -- SPI-flash chip-select (driven by the FSM during XIP)
    signal cs_flash_out, cs_flash_dir, cs_flash_ren : std_logic;

    -- flash model pins
    signal flash_csb   : std_logic;
    signal tb_flash_csn : std_logic := '1';   -- TB-driven CS for the wake frame
    signal flash_miso  : std_logic;
    signal flash_awake : std_logic;
    signal mem_reset   : std_logic;

    -- expected image (mirror of the .rcf, word i == addr 0x20000+4*i)
    type img_t is array (natural range <>) of std_logic_vector(31 downto 0);
    constant IMG : img_t := (
        0 => x"03020100", 1 => x"07060504", 2 => x"DEADBEEF", 3 => x"CAFEBABE",
        4 => x"A5A5A5A5", 5 => x"5A5A5A5A", 6 => x"FFFF0000", 7 => x"0000FFFF",
        8 => x"12345678", 9 => x"9ABCDEF0");

    constant XIP_BASE : unsigned(31 downto 0) := x"00020000";
    constant FOS_VAL  : std_logic_vector(31 downto 0) := x"00FE0000";

    shared variable sb : scoreboard;

begin

    ----------------------------------------------------------------------------
    -- clock / reset infrastructure
    ----------------------------------------------------------------------------
    smclk   <= not smclk after SM_PERIOD / 2;
    mclk    <= not mclk  after MC_PERIOD / 2;
    clk_mem <= smclk when pbus.en_mem = '0' else '0';

    -- serial_flash reloads its image on the RISING edge of mem_reset; resetn
    -- starts HIGH and drops to '0' in the stimulus, so mem_reset (= not resetn)
    -- sees a clean 0->1 edge while the DUT is held in reset.
    mem_reset <= not resetn;

    -- flash SCK/MOSI come from the SPI master; MISO goes back into the core.
    miso_in <= flash_miso;

    -- Flash CS: during the wake frame (spi_fen=0) the FSM parks cs_flash_out
    -- high, and the TB pulls tb_flash_csn low to frame the 0xAB. During XIP the
    -- TB releases tb_flash_csn high and the FSM's cs_flash_out owns the pin.
    -- Wired-AND (active-low): either driver can select the device.
    flash_csb <= cs_flash_out and tb_flash_csn;

    -- clk_mem_flash: mirror adddec.vhd exactly (glitch-free gate off `not smclk`,
    -- enabled while a flash request is asserted).
    en_clk_mem_flash <= '1' when en_mem_flash = '0' else '0';
    cg_flash : entity work.ClkGate
        port map (ClkIn => not smclk, En => en_clk_mem_flash, ClkOut => clk_mem_flash);

    ----------------------------------------------------------------------------
    -- DUT: SPI with the extended-memory (flash XIP) path compiled in
    ----------------------------------------------------------------------------
    dut : entity work.SPI
        generic map ( ENABLE_EXTENDED_MEM => true )
        port map (
            clk         => smclk,
            mclk        => mclk,
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
            sck_in      => '0',
            sck_out     => sck_out,
            sck_dir     => sck_dir,
            sck_ren     => sck_ren,
            sck_ren_in  => sck_ren_in,
            mosi_in     => '0',
            mosi_out    => mosi_out,
            mosi_dir    => mosi_dir,
            mosi_ren    => mosi_ren,
            mosi_ren_in => mosi_ren_in,
            miso_in     => miso_in,
            miso_out    => miso_out,
            miso_dir    => miso_dir,
            miso_ren    => miso_ren,
            miso_ren_in => miso_ren_in,
            en_mem_flash    => en_mem_flash,
            clk_mem_flash   => clk_mem_flash,
            mab             => mab,
            rdata_flash     => rdata_flash,
            disable_clk_cpu => disable_clk_cpu,
            cs_flash_out    => cs_flash_out,
            cs_flash_dir    => cs_flash_dir,
            cs_flash_ren    => cs_flash_ren
        );

    ----------------------------------------------------------------------------
    -- AT45DB021E behavioral flash model
    ----------------------------------------------------------------------------
    flash : entity work.serial_flash
        generic map (
            ProgramAddress       => 16#0000#,
            RamSizeBytes         => 16#400#,     -- 256 words
            SwapBytesIn32BitWord => false
        )
        port map (
            CSb           => flash_csb,
            SPCLK         => sck_out,
            MOSI          => mosi_out,
            MISO          => flash_miso,
            mem_reset     => mem_reset,
            awake         => flash_awake,
            RAM_FILE_PATH => "../rcf/spiflash_xiptest_a.rcf"
        );

    ----------------------------------------------------------------------------
    -- stimulus
    ----------------------------------------------------------------------------
    stim_proc : process
        variable rdw : std_logic_vector(31 downto 0);

        -- Poll the master status register until BUSY clears (bounded).
        procedure wait_master_done is
            variable s : std_logic_vector(31 downto 0);
            variable guard : natural := 0;
        begin
            loop
                bus_read(smclk, pbus, read_data, RegSlotSPIxSR, s);
                exit when s(2) = '0';
                guard := guard + 1;
                exit when guard > 500;
            end loop;
        end procedure;

        -- One XIP read: present a flash address the way adddec does, wait for the
        -- access to start (disable_clk_cpu high) and finish (low), sample the
        -- word. `started` reports whether the stall actually asserted.
        procedure xip_read(addr    : in  unsigned(31 downto 0);
                           result  : out std_logic_vector(31 downto 0);
                           started : out boolean) is
            variable guard : natural := 0;
        begin
            mab          <= std_logic_vector(addr);
            en_mem_flash <= '0';
            -- wait until the XIP engine asserts the core stall
            guard := 0; started := false;
            loop
                wait until rising_edge(mclk);
                if disable_clk_cpu = '1' then started := true; exit; end if;
                guard := guard + 1;
                exit when guard > 200000;
            end loop;
            -- wait until the word has been clocked in and the stall releases
            guard := 0;
            loop
                wait until rising_edge(mclk);
                exit when disable_clk_cpu = '0';
                guard := guard + 1;
                exit when guard > 200000;
            end loop;
            result := rdata_flash;
            en_mem_flash <= '1';
            wait for 20 * SM_PERIOD;   -- let the FSM settle back to CS-high/idle
        end procedure;

        variable started : boolean;
    begin
        ----------------------------------------------------------------
        -- Reset (drops resetn 1->0 to trigger the flash image load)
        ----------------------------------------------------------------
        resetn       <= '1';
        pbus         <= PERIPH_BUS_IDLE;
        en_mem_flash <= '1';
        tb_flash_csn <= '1';
        cs_in        <= '1';
        wait for 4 * SM_PERIOD;
        resetn <= '0';                 -- assert reset + load flash image
        wait for 4 * SM_PERIOD;
        resetn <= '1';
        wait for 4 * SM_PERIOD;

        ----------------------------------------------------------------
        -- GROUP 1: flash boots ASLEEP; XIP before wake returns no data
        ----------------------------------------------------------------
        report "=== GROUP 1: pre-wake (deep power-down) ===" severity note;
        sb.check_bit("flash asleep at reset", flash_awake, '0');

        ----------------------------------------------------------------
        -- GROUP 2: wake-up handshake (0xAB, CS-framed, as a normal transfer)
        ----------------------------------------------------------------
        report "=== GROUP 2: deep-power-down wake-up ===" severity note;

        -- normal 8-bit master, MSB-first, mode 0 (spi_fen = 0)
        bus_write(smclk, pbus, RegSlotSPIxCR, x"000000C0");
        tb_flash_csn <= '0';                              -- frame the opcode
        wait for 2 * SM_PERIOD;
        bus_write(smclk, pbus, RegSlotSPIxTX, x"000000AB"); -- resume opcode
        wait_master_done;
        wait for 2 * SM_PERIOD;
        tb_flash_csn <= '1';                              -- CS rising => wake takes effect
        bus_write(smclk, pbus, RegSlotSPIxCR, x"00000000"); -- park SPI

        -- tRDPD: model asserts `awake` 35 us after the CS rising edge
        wait until flash_awake = '1' for 60 us;
        sb.check_bit("flash awake after 0xAB + tRDPD", flash_awake, '1');

        ----------------------------------------------------------------
        -- GROUP 3: configure the XIP engine
        ----------------------------------------------------------------
        report "=== GROUP 3: enable XIP ===" severity note;

        -- SPIxFOS so that XIP 0x20000 -> flash word 0
        bus_write(smclk, pbus, RegSlotSPIxFOS, FOS_VAL);
        bus_read(smclk, pbus, read_data, RegSlotSPIxFOS, rdw);
        sb.check_slv("SPIxFOS readback", rdw(23 downto 0), FOS_VAL(23 downto 0));

        -- CR: spi_fen(19)=1, rx_swap(16)=1, en(7)=1, msb(6)=1, dl(3:2)=32-bit,
        -- master, mode 0.  This alignment turns the flash MISO byte stream back
        -- into the stored little-endian word.
        bus_write(smclk, pbus, RegSlotSPIxCR, x"000900C8");
        sb.check_bit("no XIP stall while idle", disable_clk_cpu, '0');

        ----------------------------------------------------------------
        -- GROUP 4: XIP reads across the known image
        ----------------------------------------------------------------
        report "=== GROUP 4: XIP reads ===" severity note;

        for i in IMG'range loop
            xip_read(XIP_BASE + to_unsigned(4 * i, 32), rdw, started);
            sb.check_true("XIP stall asserted for word " & integer'image(i), started);
            sb.check_slv("XIP read 0x2000" & integer'image(i) & " == image", rdw, IMG(i));
        end loop;

        ----------------------------------------------------------------
        -- GROUP 5: re-read is deterministic (word 2 again)
        ----------------------------------------------------------------
        report "=== GROUP 5: deterministic re-read ===" severity note;
        xip_read(XIP_BASE + to_unsigned(8, 32), rdw, started);
        sb.check_slv("XIP re-read word 2 stable", rdw, IMG(2));

        ----------------------------------------------------------------
        -- GROUP 6: non-zero-offset scan (out-of-order addresses)
        ----------------------------------------------------------------
        report "=== GROUP 6: out-of-order reads ===" severity note;
        xip_read(XIP_BASE + to_unsigned(4 * 5, 32), rdw, started);
        sb.check_slv("XIP read word 5 (out of order)", rdw, IMG(5));
        xip_read(XIP_BASE + to_unsigned(4 * 3, 32), rdw, started);
        sb.check_slv("XIP read word 3 (out of order)", rdw, IMG(3));
        xip_read(XIP_BASE + to_unsigned(4 * 9, 32), rdw, started);
        sb.check_slv("XIP read word 9 (out of order)", rdw, IMG(9));

        ----------------------------------------------------------------
        -- Final verdict
        ----------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("SPI FLASH XIP TB");
        stop;
        wait;
    end process;

end architecture sim;
