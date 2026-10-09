-- VestaRV: FPGA bring-up bench, boot from SPI flash (config/fpga_default.json)
-- Boots the FPGA file set (hdl/fpga/ clock, memory and analog stand-ins) out of the real mask-ROM image with BOOT (P1.7) HIGH, so the ROM takes the SPI flash path: wake the flash, stream the payload into the TCM, power the flash down and jump to it.
-- FLASH_IMAGE names the flashed image (29 characters, staged at the runfiles root); EXPECT is what it must do once entered:
--   a0      a0 = 0xCAFEBABE, the ISA-test pass label (the default payload, rv32ui-p-simple; on a board, watch the a0 port)
--   gpio    P3.0 switches to an output (blinky, slowblink)
--   toggle  P3.0 switches to an output and toggles (gpiotoggle)
--   loop    the core is still inside the image 100 us after entry, with no trap (looptest)
--   trap    the core runs past the entry instruction, then traps (traptest)
-- Entered means hart 0's PC reached PROG_BASE_ADDR 0x8200, the address the ROM jumps to.
-- Every edge on the flash bus and every pass/fail condition is reported with its simulation time, so a logic-analyzer capture on the board can be read against this run.
-- The ROM reads "rom.rcf" from the working directory (hdl/fpga/ARM_IP_ROM.vhd) and the flash model reads a 29-character path; //:fpga_bringup_rom_rcf and //:fpga_bringup_flash_rcf stage both at the runfiles root.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

entity fpga_flash_boot_tb is
    generic (
        FLASH_IMAGE : string := "fpga_bringup_flashpayload.rcf";
        EXPECT      : string := "a0"
    );
end fpga_flash_boot_tb;

architecture behavior of fpga_flash_boot_tb is

    constant clk_hfxt_delay : time := (0.5 sec) / 24000000;	-- 24 MHz
    constant clk_lfxt_delay : time := (0.5 sec) / 32768;	-- 32.768 kHz
    constant clk_hfxt_period : time := clk_hfxt_delay * 2;
    constant clk_lfxt_period : time := clk_lfxt_delay * 2;

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
    signal Entered		: boolean := false;
    signal Progressed	: boolean := false;	-- PC left 0x8200: the image's own code ran
    signal P3_0_DIR		: std_logic;	-- GPIO2 pin 0 direction, '0' = output (PadDIRPosLogic false)
    signal P3_0_OUT		: std_logic;	-- GPIO2 pin 0 output value

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
    P3_0_DIR <= prt3_dir(pnum_gpio2_t0_cmp0);
    P3_0_OUT <= prt3_out(pnum_gpio2_t0_cmp0);

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
        if EXPECT = "trap" then
            report "TIMELINE TRAP pin (P1.6) asserted";
        else
            report "Error: TRAP pin (P1.6) asserted: the core took a terminal trap" severity error;
        end if;
        TrapSeen <= true;
        wait;
    end process;

    -- Failure: a UART start bit. TX0 idles high from reset, so the monitor shows itself by transmitting: TX falls.
    ProcMonitor: process
    begin
        wait until reset_released;
        if to_X01(TX0) /= '1' then
            wait until to_X01(TX0) = '1';
        end if;
        wait until to_X01(TX0) = '0';
        report "Error: UART0 TX sent a start bit: the ROM fell back to the Forth monitor instead of booting the flash image" severity error;
        MonitorSeen <= true;
        wait;
    end process;

    -- Entry: hart 0's PC reaches PROG_BASE_ADDR, where the boot ROM hands over to the image.
    ProcEntry: process
        alias core_pc is << signal .fpga_flash_boot_tb.dut.hart0.core.pc : std_logic_vector(31 downto 0) >>;
    begin
        wait until reset_released;
        wait until core_pc = x"00008200";
        report "TIMELINE image entered at 0x8200";
        Entered <= true;
        wait until core_pc /= x"00008200" or TrapSeen;
        Progressed <= core_pc /= x"00008200" and not TrapSeen;
        wait;
    end process;

    -- The verdict, per EXPECT.
    ProcVerdict: process
        alias core_pc is << signal .fpga_flash_boot_tb.dut.hart0.core.pc : std_logic_vector(31 downto 0) >>;
        variable ok : boolean := false;
        procedure fail(msg : string) is
        begin
            report "Error: " & msg severity error;
            report "===== FPGA FLASH BOOT FAILED =====" severity failure;
        end procedure;
    begin
        assert FLASH_IMAGE'length = 29 report "FLASH_IMAGE must be 29 characters (serial_flash.vhd)" severity failure;
        wait until reset_released;
        if EXPECT = "a0" then
            wait until a0 = x"CAFEBABE" or TrapSeen or MonitorSeen;
            ok := a0 = x"CAFEBABE";
            if ok then report "TIMELINE payload passed: a0 = 0xCAFEBABE"; end if;
        else
            wait until Entered or TrapSeen or MonitorSeen;
            if not Entered then fail("the image was never entered"); end if;
            if EXPECT = "gpio" or EXPECT = "toggle" then
                wait until P3_0_DIR = '0' or TrapSeen or MonitorSeen;
                ok := P3_0_DIR = '0';
                if ok then report "TIMELINE P3.0 switched to output"; end if;
                if ok and EXPECT = "toggle" then
                    wait until P3_0_OUT'event or TrapSeen for 1 ms;
                    wait until P3_0_OUT'event or TrapSeen for 1 ms;
                    ok := P3_0_OUT'event and not TrapSeen;
                    if ok then report "TIMELINE P3.0 toggling"; end if;
                end if;
            elsif EXPECT = "loop" then
                wait until TrapSeen or MonitorSeen for 100 us;
                ok := not (TrapSeen or MonitorSeen) and unsigned(core_pc) >= 16#8200# and unsigned(core_pc) < 16#8400#;
                if ok then report "TIMELINE still in the image after 100 us, pc = 0x" & to_hstring(core_pc); end if;
            elsif EXPECT = "trap" then
                wait until TrapSeen or MonitorSeen for 100 us;
                ok := TrapSeen and Progressed and not MonitorSeen;
                if TrapSeen and not Progressed then report "Error: trapped at the entry instruction itself, not in the image's code" severity error; end if;
            else
                fail("unknown EXPECT value: " & EXPECT);
            end if;
        end if;
        wait for 10 * clk_hfxt_period;
        if not ok or MonitorSeen or (TrapSeen and EXPECT /= "trap") then
            fail("expected behaviour not observed: " & EXPECT);
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
