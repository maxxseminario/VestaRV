-- VestaRV: FPGA bring-up bench through the generated board top level (fpga_top.vhd)
-- The board view of :fpga_flash_boot: the flash model on p0_0..p0_3, BOOT (p0_7) high, 24 MHz on clk_hfxt, and the verdict on pass_led, the pin a board puts an LED on.
-- Every pin carries a weak pull-down, so a pin fpga_top fails to drive or release reads 'L' rather than a value the bench supplies.
-- Fails on the TRAP pin (p0_6), or on a UART start bit on TX0 (p1_4): TX idles high from reset, and only the ROM's Forth monitor transmits.
library ieee;
use ieee.std_logic_1164.all;

entity fpga_top_flash_boot_tb is
end fpga_top_flash_boot_tb;

architecture behavior of fpga_top_flash_boot_tb is

    constant clk_hfxt_period : time := (1 sec) / 24000000;
    constant clk_lfxt_period : time := (1 sec) / 32768;
    constant FLASH_IMAGE     : string(1 to 29) := "fpga_bringup_flashpayload.rcf";

    signal clk_hfxt, clk_lfxt : std_logic := '0';
    signal resetn   : std_logic := '1';
    signal pass_led : std_logic;

    signal p0_0, p0_1, p0_2, p0_3, p0_6, p0_7 : std_logic := 'L';
    signal p1_0, p1_1, p1_2, p1_3, p1_4, p1_5, p1_6, p1_7 : std_logic := 'L';
    signal p2_0, p2_1, p2_2, p2_3, p2_4, p2_5, p2_6, p2_7 : std_logic := 'L';
    signal p3_0, p3_1, p3_2, p3_3, p3_4, p3_5, p3_6, p3_7 : std_logic := 'L';

    signal flash_reset, flash_awake : std_logic;
    signal released : boolean := false;
    signal MonitorSeen : boolean := false;

begin

    clk_hfxt <= not clk_hfxt after clk_hfxt_period / 2;
    clk_lfxt <= not clk_lfxt after clk_lfxt_period / 2;

    -- Weak pulls: the bench's own driver on every pin is 'L'. BOOT is strapped high.
    p0_0 <= 'L'; p0_1 <= 'L'; p0_2 <= 'L'; p0_3 <= 'L'; p0_6 <= 'L'; p0_7 <= '1';
    p1_0 <= 'L'; p1_1 <= 'L'; p1_2 <= 'L'; p1_3 <= 'L'; p1_4 <= 'L'; p1_5 <= 'H'; p1_6 <= 'L'; p1_7 <= 'L';
    p2_0 <= 'L'; p2_1 <= 'L'; p2_2 <= 'L'; p2_3 <= 'L'; p2_4 <= 'L'; p2_5 <= 'L'; p2_6 <= 'L'; p2_7 <= 'L';
    p3_0 <= 'L'; p3_1 <= 'L'; p3_2 <= 'L'; p3_3 <= 'L'; p3_4 <= 'L'; p3_5 <= 'L'; p3_6 <= 'L'; p3_7 <= 'L';

    dut: entity work.fpga_top
        port map (
            clk_hfxt => clk_hfxt, clk_lfxt => clk_lfxt, resetn => resetn, pass_led => pass_led,
            p0_0 => p0_0, p0_1 => p0_1, p0_2 => p0_2, p0_3 => p0_3, p0_6 => p0_6, p0_7 => p0_7,
            p1_0 => p1_0, p1_1 => p1_1, p1_2 => p1_2, p1_3 => p1_3, p1_4 => p1_4, p1_5 => p1_5, p1_6 => p1_6, p1_7 => p1_7,
            p2_0 => p2_0, p2_1 => p2_1, p2_2 => p2_2, p2_3 => p2_3, p2_4 => p2_4, p2_5 => p2_5, p2_6 => p2_6, p2_7 => p2_7,
            p3_0 => p3_0, p3_1 => p3_1, p3_2 => p3_2, p3_3 => p3_3, p3_4 => p3_4, p3_5 => p3_5, p3_6 => p3_6, p3_7 => p3_7
        );

    flash_reset <= not resetn;
    flash: entity work.serial_flash
        generic map (
            ProgramAddress       => 16#0000#,
            RamSizeBytes         => 16#8100#,
            SwapBytesIn32BitWord => false
        )
        port map (
            CSb => p0_0, SPCLK => p0_3, MOSI => p0_2, MISO => p0_1,
            mem_reset => flash_reset, awake => flash_awake, RAM_FILE_PATH => FLASH_IMAGE
        );

    -- Reset is pulsed from '1', as asic_default_boot_tb does: serial_flash.vhd loads its image on
    -- the RISING edge of mem_reset, which a reset held from time zero never produces.
    ProcReset: process
    begin
        wait for 1 us;
        resetn <= '0';
        wait for 100 us;
        wait until rising_edge(clk_hfxt);
        resetn <= '1';
        released <= true;
        wait;
    end process;

    -- A UART start bit: TX falls after it has idled high.
    ProcMonitor: process
    begin
        wait until released;
        if to_X01(p1_4) /= '1' then
            wait until to_X01(p1_4) = '1';
        end if;
        wait until to_X01(p1_4) = '0';
        report "Error: UART0 TX (p1_4) sent a start bit: the ROM fell back to the Forth monitor" severity error;
        MonitorSeen <= true;
        wait;
    end process;

    ProcVerdict: process
    begin
        wait until released;
        wait until pass_led = '1' or to_X01(p0_6) = '1' or MonitorSeen;
        if to_X01(p0_6) = '1' then
            report "Error: TRAP pin (p0_6) asserted" severity error;
        end if;
        if pass_led /= '1' then
            report "===== FPGA TOP FLASH BOOT FAILED =====" severity failure;
        end if;
        report "TIMELINE pass_led on";
        report "===== FPGA TOP FLASH BOOT PASSED =====";
        wait;
    end process;

end behavior;
