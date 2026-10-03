-- VestaRV: FPGA bring-up bench, boot from SPI flash (config/fpga_default.json)
-- Boots the FPGA file set (hdl/fpga/ clock, memory and analog stand-ins) out of the real mask-ROM image with BOOT (P1.7) HIGH, so the ROM takes the SPI flash path: wake the flash, stream the payload into the TCM, power the flash down and jump to it.
-- The payload is the rv32ui-p-simple ISA test. Its verdict is the MCU's a0 test port: 0xCAFEBABE is pass. On a board the same port is the observable (an ILA, or a comparator onto an LED).
-- Every edge on the flash bus and every pass/fail condition is reported with its simulation time, so a logic-analyzer capture on the board can be read against this run.
-- The ROM reads "rom.rcf" from the working directory (hdl/fpga/ARM_IP_ROM.vhd) and the flash model reads a 29-character path; //:fpga_bringup_rom_rcf and //:fpga_bringup_flash_rcf stage both at the runfiles root.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

entity fpga_flash_boot_tb is
end fpga_flash_boot_tb;

architecture behavior of fpga_flash_boot_tb is

    constant clk_hfxt_delay : time := (0.5 sec) / 24000000;	-- 24 MHz
    constant clk_lfxt_delay : time := (0.5 sec) / 32768;	-- 32.768 kHz
    constant clk_hfxt_period : time := clk_hfxt_delay * 2;
    constant clk_lfxt_period : time := clk_lfxt_delay * 2;

    constant FLASH_IMAGE : string(1 to 29) := "fpga_bringup_flashpayload.rcf";

    signal clk_hfxt : std_logic := '0';
    signal clk_lfxt : std_logic := '0';

    -- Pad signals, weakly pulled low so undriven pads read a defined level.
    signal resetn_pad : std_logic := '1';
    signal prt1 : std_logic_vector(7 downto 0) := (others => 'L');
    signal prt2 : std_logic_vector(7 downto 0) := (others => 'L');
    signal prt3 : std_logic_vector(7 downto 0) := (others => 'L');
    signal prt4 : std_logic_vector(7 downto 0) := (others => 'L');

    signal prt1_in, prt1_out, prt1_dir, prt1_ren : std_logic_vector(7 downto 0);
    signal prt2_in, prt2_out, prt2_dir, prt2_ren : std_logic_vector(7 downto 0);
    signal prt3_in, prt3_out, prt3_dir, prt3_ren : std_logic_vector(7 downto 0);
    signal prt4_in, prt4_out, prt4_dir, prt4_ren : std_logic_vector(7 downto 0);
    signal prt5_in, prt5_out, prt5_dir, prt5_ren : std_logic_vector(7 downto 0);
    signal prt6_in, prt6_out, prt6_dir, prt6_ren : std_logic_vector(7 downto 0);
    signal resetn_out, resetn_dir, resetn_ren, resetn_in : std_logic;

    signal a0 : std_logic_vector(31 downto 0);

    -- Pad aliases
    signal CS_FLASH		: std_logic;	-- P1.0
    signal MISO0		: std_logic;	-- P1.1
    signal MOSI0		: std_logic;	-- P1.2
    signal SCK0			: std_logic;	-- P1.3
    signal TRAP			: std_logic;	-- P1.6
    signal BOOT			: std_logic := '1';	-- P1.7, '1' = SPI flash
    signal TX0			: std_logic;	-- P2.4

    signal flash_reset	: std_logic;
    signal flash_awake	: std_logic;
    signal reset_released : boolean := false;
    signal TrapSeen		: boolean := false;
    signal MonitorSeen	: boolean := false;

    component MCU
        port (
            resetn_in	: in	std_logic;
            resetn_out	: out	std_logic;
            resetn_dir	: out	std_logic;
            resetn_ren	: out	std_logic;
            prt1_in		: in	std_logic_vector(7 downto 0);
            prt1_out	: out	std_logic_vector(7 downto 0);
            prt1_dir	: out	std_logic_vector(7 downto 0);
            prt1_ren	: out	std_logic_vector(7 downto 0);
            prt2_in		: in	std_logic_vector(7 downto 0);
            prt2_out	: out	std_logic_vector(7 downto 0);
            prt2_dir	: out	std_logic_vector(7 downto 0);
            prt2_ren	: out	std_logic_vector(7 downto 0);
            prt3_in		: in	std_logic_vector(7 downto 0);
            prt3_out	: out	std_logic_vector(7 downto 0);
            prt3_dir	: out	std_logic_vector(7 downto 0);
            prt3_ren	: out	std_logic_vector(7 downto 0);
            prt4_in		: in	std_logic_vector(7 downto 0);
            prt4_out	: out	std_logic_vector(7 downto 0);
            prt4_dir	: out	std_logic_vector(7 downto 0);
            prt4_ren	: out	std_logic_vector(7 downto 0);
            prt5_in		: in	std_logic_vector(7 downto 0);
            prt5_out	: out	std_logic_vector(7 downto 0);
            prt5_dir	: out	std_logic_vector(7 downto 0);
            prt5_ren	: out	std_logic_vector(7 downto 0);
            prt6_in		: in	std_logic_vector(7 downto 0);
            prt6_out	: out	std_logic_vector(7 downto 0);
            prt6_dir	: out	std_logic_vector(7 downto 0);
            prt6_ren	: out	std_logic_vector(7 downto 0);
            a0			: out	std_logic_vector(31 downto 0)
        );
    end component;

begin

    ProcClkHFXT: process
    begin
        clk_hfxt <= '0';
        wait for clk_hfxt_period / 2;
        clk_hfxt <= '1';
        wait for clk_hfxt_period / 2;
    end process;

    ProcClkLFXT: process
    begin
        clk_lfxt <= '0';
        wait for clk_lfxt_period / 2;
        clk_lfxt <= '1';
        wait for clk_lfxt_period / 2;
    end process;

    prt1(pnum_gpio0_hfxt) <= clk_hfxt;
    prt1(pnum_gpio0_lfxt) <= clk_lfxt;
    prt1(pnum_gpio0_boot) <= BOOT;

    CS_FLASH <= prt1(pnum_gpio0_cs_flash);
    prt1(pnum_gpio0_miso) <= MISO0;
    MOSI0 <= prt1(pnum_gpio0_mosi);
    SCK0 <= prt1(pnum_gpio0_spi_clk);
    TRAP <= prt1(pnum_gpio0_trap);
    TX0 <= prt2(pnum_gpio1_tx0);

    -- The AT45DB021E-class model riscv_tb boots every ISA test from. It starts in deep power-down, so the ROM's ABh wake-up is exercised too.
    flash_reset <= not to_X01(resetn_pad);
    flash: entity work.serial_flash
        generic map (
            ProgramAddress       => 16#0000#,
            RamSizeBytes         => 16#8100#,
            SwapBytesIn32BitWord => false
        )
        port map (
            CSb           => CS_FLASH,
            SPCLK         => SCK0,
            MOSI          => MOSI0,
            MISO          => MISO0,
            mem_reset     => flash_reset,
            awake         => flash_awake,
            RAM_FILE_PATH => FLASH_IMAGE
        );

    -- Timeline: every flash chip-select edge and the wake-up, in order, with its time.
    -- Expected sequence: CS low/high (ABh wake), CS low for the whole image read, CS high, CS low/high (B9h power-down), then the jump.
    ProcTimeline: process
        variable n : natural := 0;
    begin
        wait until reset_released;
        report "TIMELINE reset released";
        loop
            wait on CS_FLASH, flash_awake;
            if CS_FLASH'event and to_X01(CS_FLASH) = '0' then
                n := n + 1;
                report "TIMELINE flash CS asserted (#" & integer'image(n) & ")";
            elsif CS_FLASH'event and to_X01(CS_FLASH) = '1' then
                report "TIMELINE flash CS released (#" & integer'image(n) & ")";
            elsif flash_awake'event and flash_awake = '1' then
                report "TIMELINE flash awake (left deep power-down)";
            elsif flash_awake'event and flash_awake = '0' then
                report "TIMELINE flash back in deep power-down";
            end if;
        end loop;
    end process;

    -- Failure: the ROM's terminal trap (bad command word or bad segment address in the image).
    ProcTrap: process
    begin
        wait until reset_released;
        wait until to_X01(TRAP) = '1';
        report "Error: TRAP pin (P1.6) asserted: the core took a terminal trap" severity error;
        TrapSeen <= true;
        wait;
    end process;

    -- Failure: UART0 TX idles high only once the Forth monitor initialises it, which the ROM does when the flash never answers.
    ProcMonitor: process
    begin
        wait until reset_released;
        wait until to_X01(TX0) = '1';
        report "Error: UART0 TX went active: the ROM fell back to the Forth monitor instead of booting the flash image" severity error;
        MonitorSeen <= true;
        wait;
    end process;

    -- The verdict: code loaded from the flash ran to its pass label, which writes 0xCAFEBABE to a0.
    ProcVerdict: process
    begin
        wait until reset_released;
        wait until a0 = x"CAFEBABE" or TrapSeen or MonitorSeen;
        if TrapSeen or MonitorSeen then
            report "===== FPGA FLASH BOOT FAILED =====" severity failure;
        end if;
        report "TIMELINE payload passed: a0 = 0xCAFEBABE";
        wait for 10 * clk_hfxt_period;
        if TrapSeen or MonitorSeen then
            report "===== FPGA FLASH BOOT FAILED =====" severity failure;
        end if;
        report "===== FPGA FLASH BOOT PASSED =====";
        wait;
    end process;

    -- Reset sequence, identical to asic_default_boot_tb's.
    ProcMainTest: process
    begin
        BOOT <= '1';
        resetn_pad <= '1';
        wait for 1 us;
        wait until rising_edge(clk_hfxt);
        wait for clk_hfxt_delay / 2.3;
        resetn_pad <= '0';
        wait for 100 us;
        wait until rising_edge(clk_hfxt);
        wait for clk_hfxt_delay / 2.3;
        resetn_pad <= '1';
        reset_released <= true;
        wait;
    end process;

    dut: MCU
    port map (
        resetn_in => resetn_in, resetn_out => resetn_out, resetn_dir => resetn_dir, resetn_ren => resetn_ren,
        prt1_in => prt1_in, prt1_out => prt1_out, prt1_dir => prt1_dir, prt1_ren => prt1_ren,
        prt2_in => prt2_in, prt2_out => prt2_out, prt2_dir => prt2_dir, prt2_ren => prt2_ren,
        prt3_in => prt3_in, prt3_out => prt3_out, prt3_dir => prt3_dir, prt3_ren => prt3_ren,
        prt4_in => prt4_in, prt4_out => prt4_out, prt4_dir => prt4_dir, prt4_ren => prt4_ren,
        prt5_in => prt5_in, prt5_out => prt5_out, prt5_dir => prt5_dir, prt5_ren => prt5_ren,
        prt6_in => prt6_in, prt6_out => prt6_out, prt6_dir => prt6_dir, prt6_ren => prt6_ren,
        a0 => a0
    );

    -- GPIO4/GPIO5 have no package pads.
    prt5_in <= (others => '0');
    prt6_in <= (others => '0');

    reset_pad: entity work.PDUW16SDGZ_G
    port map (I => resetn_out, OEN => resetn_dir, REN => resetn_ren, PAD => resetn_pad, C => resetn_in);

    pad_prt1_gen: for i in 7 downto 0 generate
        pad_p1: entity work.PDUW16SDGZ_G
        port map (I => prt1_out(i), OEN => prt1_dir(i), REN => prt1_ren(i), PAD => prt1(i), C => prt1_in(i));
    end generate;

    pad_prt2_gen: for i in 7 downto 0 generate
        pad_p2: entity work.PDUW16SDGZ_G
        port map (I => prt2_out(i), OEN => prt2_dir(i), REN => prt2_ren(i), PAD => prt2(i), C => prt2_in(i));
    end generate;

    pad_prt3_gen: for i in 7 downto 0 generate
        pad_p3: entity work.PDUW16SDGZ_G
        port map (I => prt3_out(i), OEN => prt3_dir(i), REN => prt3_ren(i), PAD => prt3(i), C => prt3_in(i));
    end generate;

    pad_prt4_gen: for i in 7 downto 0 generate
        pad_p4: entity work.PDUW16SDGZ_G
        port map (I => prt4_out(i), OEN => prt4_dir(i), REN => prt4_ren(i), PAD => prt4(i), C => prt4_in(i));
    end generate;

end behavior;
