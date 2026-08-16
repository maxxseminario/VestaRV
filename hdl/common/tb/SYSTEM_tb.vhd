-------------------------------------------------------------------------------
-- SYSTEM_tb.vhd: self-checking testbench for the SYSTEM clock/reset/WDT/CRC controller, built on tb/periph_tb_pkg.vhd (scoreboard, register-bus BFM, crc16_byte).
-- SYSTEM generates its own synchronous reset (resetn_sys) from clk_hfxt_in via mclk, so clk_hfxt_in must run from t=0 and the register bus is only exercised once resetn_sys has deasserted.
-- Coverage: reset defaults, register R/W and pad routing (PGEN_mem, DCO bias/en), reserved IRQ slots, CRC16, watchdog and its interrupt line, clock activity/divider/source mux.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.constants.all;
use work.MemoryMap.all;
use work.periph_tb_pkg.all;

entity SYSTEM_tb is
end entity SYSTEM_tb;

architecture sim of SYSTEM_tb is

    constant PERIOD : time := 100 ns;   -- reference clock (hfxt + memory bus)

    -- reference / oscillator clocks
    signal clk          : std_logic := '0';   -- reference (drives hfxt + bus)
    signal clk_lfxt_in  : std_logic := '0';
    signal clk_dco0_in  : std_logic := '0';
    signal clk_dco1_in  : std_logic := '0';

    -- resets / misc inputs
    signal resetn_in    : std_logic := '1';
    signal resetn_por   : std_logic := '0';
    signal resetn_sys   : std_logic;

    -- WDT level output plus the router "source-0 routed" hook; wdt_irq_complete stays at its port default '0'.
    signal irq_sys_wdt      : std_logic;
    signal wdt_irq_routed   : std_logic := '0';

    -- register bus: BFM record, observed read_data, gated clk_mem.
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal clk_mem   : std_logic := '0';
    signal read_data : std_logic_vector(31 downto 0);

    -- clock outputs
    signal mclk_out, smclk_out, clk_lfxt_out, clk_hfxt_out : std_logic;

    -- DCO / power outputs
    signal en_dco0_out, en_dco1_out : std_logic;
    signal DCO0_BIAS, DCO1_BIAS     : std_logic_vector(11 downto 0);
    signal PGEN_mem                 : std_logic_vector(6 downto 0);  -- bits 6:3 are shbank0-3.

    -- edge counters for clock-output activity checks
    signal cnt_mclk  : natural := 0;
    signal cnt_smclk : natural := 0;
    signal cnt_hfxt  : natural := 0;
    signal cnt_lfxt  : natural := 0;
    signal cnt_ref   : natural := 0;

    shared variable sb : scoreboard;

begin

    -- Reference clock and oscillators, all free-running from t=0.
    clk         <= not clk         after PERIOD / 2;
    clk_lfxt_in <= not clk_lfxt_in after 160 ns;   -- slow crystal
    clk_dco0_in <= not clk_dco0_in after 70 ns;
    clk_dco1_in <= not clk_dco1_in after 90 ns;

    -- Gated memory-bus clock: ticks only while the peripheral is selected.
    clk_mem <= clk when pbus.en_mem = '0' else '0';

    -- Edge counters, one per clock output, used by the clock-activity checks.
    process(mclk_out)     begin if rising_edge(mclk_out)     then cnt_mclk  <= cnt_mclk  + 1; end if; end process;
    process(smclk_out)    begin if rising_edge(smclk_out)    then cnt_smclk <= cnt_smclk + 1; end if; end process;
    process(clk_hfxt_out) begin if rising_edge(clk_hfxt_out) then cnt_hfxt  <= cnt_hfxt  + 1; end if; end process;
    process(clk_lfxt_out) begin if rising_edge(clk_lfxt_out) then cnt_lfxt  <= cnt_lfxt  + 1; end if; end process;
    process(clk)          begin if rising_edge(clk)          then cnt_ref   <= cnt_ref   + 1; end if; end process;

    dut : entity work.SYSTEM
        port map (
            clk_lfxt_in => clk_lfxt_in, clk_hfxt_in => clk,
            clk_dco0_in => clk_dco0_in, clk_dco1_in => clk_dco1_in,
            resetn_in => resetn_in, resetn_por => resetn_por, resetn_sys => resetn_sys,
            irq_sys_wdt => irq_sys_wdt,
            wdt_irq_routed => wdt_irq_routed,
            -- wdt_irq_complete is left at its port default '0'.
            clk_mem => clk_mem, en_mem => pbus.en_mem, wen => pbus.wen,
            addr_periph => pbus.addr_periph, write_data => pbus.write_data, read_data => read_data,
            mclk_out => mclk_out, smclk_out => smclk_out,
            clk_lfxt_out => clk_lfxt_out, clk_hfxt_out => clk_hfxt_out,
            en_dco0_out => en_dco0_out, DCO0_BIAS => DCO0_BIAS,
            en_dco1_out => en_dco1_out, DCO1_BIAS => DCO1_BIAS,
            PGEN_mem => PGEN_mem
        );

    -- Single stimulus thread: releases reset, then walks the numbered check groups in order.
    stim_proc : process
        variable rdw        : std_logic_vector(31 downto 0);
        variable crc        : std_logic_vector(15 downto 0);
        variable v1, v2, r1, r2 : natural;
    begin
        -- Hold resetn_por low while the clock primes the glitch-free muxes, then release and let resetn_sys propagate.
        resetn_por <= '0';
        pbus <= PERIPH_BUS_IDLE;
        wait for 10 * PERIOD;
        resetn_por <= '1';
        wait for 10 * PERIOD;

        -- GROUP 1: reset and defaults.
        report "=== GROUP 1: reset & defaults ===" severity note;

        sb.check_bit("resetn_sys deasserted after reset", resetn_sys, '1');

        bus_read(clk, pbus, read_data, RegSlotSYS_CLK_CR, rdw);
        sb.check_slv("SYS_CLK_CR resets to 0", rdw(8 downto 0), (8 downto 0 => '0'));
        bus_read(clk, pbus, read_data, RegSlotSYS_CLK_DIV_CR, rdw);
        sb.check_slv("SYS_CLK_DIV_CR resets to 0", rdw(5 downto 0), (5 downto 0 => '0'));
        bus_read(clk, pbus, read_data, RegSlotSYS_BLOCK_PWR, rdw);
        sb.check_slv("SYS_BLOCK_PWR resets to 0", rdw(2 downto 0), "000");
        bus_read(clk, pbus, read_data, RegSlotSYS_WDT_CR, rdw);
        sb.check_slv("SYS_WDT_CR resets to 0", rdw(7 downto 0), x"00");
        bus_read(clk, pbus, read_data, RegSlotSYS_WDT_SR, rdw);
        sb.check_slv("SYS_WDT_SR resets to 0", rdw(1 downto 0), "00");
        bus_read(clk, pbus, read_data, RegSlotSYS_WDT_VAL, rdw);
        sb.check_slv("SYS_WDT_VAL resets to 0 (wdt off)", rdw(23 downto 0), (23 downto 0 => '0'));
        bus_read(clk, pbus, read_data, RegSlotDCO0_BIAS, rdw);
        sb.check_slv("SYS DCO0_BIAS reg = default 0x800", rdw(11 downto 0), x"800");
        bus_read(clk, pbus, read_data, RegSlotDCO1_BIAS, rdw);
        sb.check_slv("SYS DCO1_BIAS reg = default 0x800", rdw(11 downto 0), x"800");

        -- Outputs driven straight from the reset values of their registers.
        sb.check_slv("DCO0_BIAS pad = default 0x800", DCO0_BIAS, x"800");
        sb.check_slv("DCO1_BIAS pad = default 0x800", DCO1_BIAS, x"800");
        sb.check_slv("PGEN_mem = 0 at reset (all on)", PGEN_mem, "000");
        sb.check_bit("irq_sys_wdt low at reset (wdt_ie=0)", irq_sys_wdt, '0');

        -- GROUP 2: register read/write and pad routing.
        report "=== GROUP 2: register R/W ===" severity note;

        -- CLK_CR: keep mclk_sel(1:0)=00 so the reference clock survives.
        bus_write(clk, pbus, RegSlotSYS_CLK_CR, x"000001FC");
        bus_read(clk, pbus, read_data, RegSlotSYS_CLK_CR, rdw);
        sb.check_slv("SYS_CLK_CR 9-bit readback", rdw(8 downto 0), '1' & x"FC");
        bus_write(clk, pbus, RegSlotSYS_CLK_CR, x"00000000");

        -- CLK_DIV_CR: 6-bit readback, then restore the reset value.
        bus_write(clk, pbus, RegSlotSYS_CLK_DIV_CR, x"0000002A");
        bus_read(clk, pbus, read_data, RegSlotSYS_CLK_DIV_CR, rdw);
        sb.check_slv("SYS_CLK_DIV_CR 6-bit readback", rdw(5 downto 0), "101010");
        bus_write(clk, pbus, RegSlotSYS_CLK_DIV_CR, x"00000000");

        -- BLOCK_PWR drives PGEN_mem (ram_off and rom_off).
        bus_write(clk, pbus, RegSlotSYS_BLOCK_PWR, x"00000005");        -- ram_off=10, rom_off=1
        bus_read(clk, pbus, read_data, RegSlotSYS_BLOCK_PWR, rdw);
        sb.check_slv("SYS_BLOCK_PWR readback", rdw(2 downto 0), "101");
        sb.check_slv("PGEN_mem tracks BLOCK_PWR", PGEN_mem, "101");
        bus_write(clk, pbus, RegSlotSYS_BLOCK_PWR, x"00000000");
        sb.check_slv("PGEN_mem back to 0", PGEN_mem, "000");

        -- DCO bias registers, and the dco_on bits that drive en_dco*_out.
        bus_write(clk, pbus, RegSlotDCO0_BIAS, x"00000ABC");
        bus_read(clk, pbus, read_data, RegSlotDCO0_BIAS, rdw);
        sb.check_slv("DCO0_BIAS 12-bit readback", rdw(11 downto 0), x"ABC");
        sb.check_slv("DCO0_BIAS pad tracks reg", DCO0_BIAS, x"ABC");
        bus_write(clk, pbus, RegSlotDCO1_BIAS, x"00000DEF");
        bus_read(clk, pbus, read_data, RegSlotDCO1_BIAS, rdw);
        sb.check_slv("DCO1_BIAS 12-bit readback", rdw(11 downto 0), x"DEF");
        sb.check_slv("DCO1_BIAS pad tracks reg", DCO1_BIAS, x"DEF");

        bus_write(clk, pbus, RegSlotSYS_CLK_CR, x"00000180");           -- dco0_on(7)+dco1_on(8)
        sb.check_bit("en_dco0_out set when dco0_on", en_dco0_out, '1');
        sb.check_bit("en_dco1_out set when dco1_on", en_dco1_out, '1');
        bus_write(clk, pbus, RegSlotSYS_CLK_CR, x"00000000");
        sb.check_bit("en_dco0_out clears", en_dco0_out, '0');
        sb.check_bit("en_dco1_out clears", en_dco1_out, '0');

        -- GROUP 3: slots 5-11 are reserved gaps, reads return 0 and writes are ignored; slot 5 stands in for the block.
        report "=== GROUP 3: retired IRQ register slots ===" severity note;

        bus_write(clk, pbus, 5, x"FFFFFFFF");
        bus_read(clk, pbus, read_data, 5, rdw);
        sb.check_slv("retired slot 5 reads 0 and ignores writes", rdw, x"00000000");

        -- GROUP 4: CRC16 engine.
        -- Writing SYS_CRC_STATE sets first_crc_flag, then bytes go through SYS_CRC_DATA and the accumulated state is compared.
        report "=== GROUP 4: CRC16 ===" severity note;

        bus_write(clk, pbus, RegSlotSYS_CRC_STATE, x"0000FFFF");        -- initial value
        crc := x"FFFF";
        bus_write(clk, pbus, RegSlotSYS_CRC_DATA, x"00000012"); crc := crc16_byte(x"12", crc);
        bus_write(clk, pbus, RegSlotSYS_CRC_DATA, x"00000034"); crc := crc16_byte(x"34", crc);
        bus_write(clk, pbus, RegSlotSYS_CRC_DATA, x"00000056"); crc := crc16_byte(x"56", crc);
        bus_read(clk, pbus, read_data, RegSlotSYS_CRC_STATE, rdw);
        sb.check_slv("CRC16 over {12,34,56} matches model", rdw(15 downto 0), crc);

        -- GROUP 5: watchdog timer.
        report "=== GROUP 5: watchdog ===" severity note;

        -- (a) WDT_CR write is password-locked, so a bare write is ignored.
        bus_write(clk, pbus, RegSlotSYS_WDT_CR, x"000000FC");
        bus_read(clk, pbus, read_data, RegSlotSYS_WDT_CR, rdw);
        sb.check_slv("WDT_CR write blocked while locked", rdw(7 downto 0), x"00");

        -- (b) Unlock, then write WDT_CR within the 64-cycle window.
        -- cdiv=5 watches WDT_VAL(5), which rises at count 32 and re-rises only every 64 counts, wide enough to see the flag set then cleared.
        bus_write(clk, pbus, RegSlotSYS_WDT_PASS, WDT_UNLCK_PASSWD);
        bus_write(clk, pbus, RegSlotSYS_WDT_CR, x"00000094");           -- wdt_en=1, cdiv=5, ie=0
        bus_read(clk, pbus, read_data, RegSlotSYS_WDT_CR, rdw);
        sb.check_slv("WDT_CR written after unlock", rdw(7 downto 0), x"94");

        -- (c) The counter runs while the WDT is enabled.
        bus_read(clk, pbus, read_data, RegSlotSYS_WDT_VAL, rdw);
        v1 := to_integer(unsigned(rdw(23 downto 0)));
        wait for 40 * PERIOD;
        bus_read(clk, pbus, read_data, RegSlotSYS_WDT_VAL, rdw);
        v2 := to_integer(unsigned(rdw(23 downto 0)));
        sb.check_true("WDT counter increments while enabled", v2 > v1);

        -- (d) Timeout sets wdt_if (SR bit 1) once WDT_VAL(5) has risen, i.e. count above 32.
        bus_read(clk, pbus, read_data, RegSlotSYS_WDT_SR, rdw);
        sb.check_bit("WDT timeout sets wdt_if (SR bit1)", rdw(1), '1');

        -- (e) Clear the interrupt flag by writing SR bit 1, held so the clear pulse overlaps a WDT-clock edge.
        bus_write_hold(clk, pbus, RegSlotSYS_WDT_SR, x"00000002", 3);
        bus_read(clk, pbus, read_data, RegSlotSYS_WDT_SR, rdw);
        sb.check_bit("wdt_if cleared via SR write", rdw(1), '0');

        -- (f) Clear the counter with the WDT clear password.
        bus_read(clk, pbus, read_data, RegSlotSYS_WDT_VAL, rdw);
        v1 := to_integer(unsigned(rdw(23 downto 0)));
        bus_write(clk, pbus, RegSlotSYS_WDT_PASS, WDT_CLR_PASSWD);
        bus_read(clk, pbus, read_data, RegSlotSYS_WDT_VAL, rdw);
        v2 := to_integer(unsigned(rdw(23 downto 0)));
        sb.check_true("WDT clear password resets counter", v2 < v1);

        -- Disable the WDT again, unlocking first.
        bus_write(clk, pbus, RegSlotSYS_WDT_PASS, WDT_UNLCK_PASSWD);
        bus_write(clk, pbus, RegSlotSYS_WDT_CR, x"00000000");

        -- GROUP 5b: watchdog interrupt line, irq_sys_wdt = wdt_if AND wdt_ie.
        -- With ie=1 and the router asserting wdt_irq_routed, a timeout must raise the level instead of resetting: resetn_wdt holds high while the IRQ is routed and not yet completed.
        report "=== GROUP 5b: watchdog IRQ line ===" severity note;

        wdt_irq_routed <= '1';                       -- The router has source 0 routed.
        sb.check_bit("irq_sys_wdt low before WDT enable", irq_sys_wdt, '0');

        -- Enable the WDT with interrupts on: en=1, cdiv=5, ie=1, i.e. 0x96.
        bus_write(clk, pbus, RegSlotSYS_WDT_PASS, WDT_UNLCK_PASSWD);
        bus_write(clk, pbus, RegSlotSYS_WDT_CR, x"00000096");
        sb.check_bit("irq_sys_wdt still low right after enable (no timeout yet)", irq_sys_wdt, '0');

        -- Let WDT_VAL(5) rise (count above 32) so wdt_if sets with no reset, since the IRQ is routed and has no EOI yet.
        wait for 60 * PERIOD;
        bus_read(clk, pbus, read_data, RegSlotSYS_WDT_SR, rdw);
        sb.check_bit("WDT timeout sets wdt_if with ie=1 (SR bit1)", rdw(1), '1');
        sb.check_bit("resetn_sys held (routed WDT does not reset)", resetn_sys, '1');
        sb.check_bit("irq_sys_wdt ASSERTS on timeout (wdt_if AND wdt_ie)", irq_sys_wdt, '1');

        -- Clearing wdt_if by an SR write-1 drops the interrupt line.
        bus_write_hold(clk, pbus, RegSlotSYS_WDT_SR, x"00000002", 3);
        sb.check_bit("irq_sys_wdt drops after wdt_if cleared", irq_sys_wdt, '0');

        -- Disable the WDT and un-route its source.
        bus_write(clk, pbus, RegSlotSYS_WDT_PASS, WDT_UNLCK_PASSWD);
        bus_write(clk, pbus, RegSlotSYS_WDT_CR, x"00000000");
        wdt_irq_routed <= '0';

        -- GROUP 6: clock tree activity.
        report "=== GROUP 6: clocks ===" severity note;

        -- All four clock outputs should be toggling at the reset defaults.
        v1 := cnt_mclk;  r1 := cnt_smclk;
        v2 := cnt_hfxt;  r2 := cnt_lfxt;
        wait for 60 * PERIOD;
        sb.check_true("mclk_out toggling",     cnt_mclk  > v1);
        sb.check_true("smclk_out toggling",    cnt_smclk > r1);
        sb.check_true("clk_hfxt_out toggling", cnt_hfxt  > v2);
        sb.check_true("clk_lfxt_out toggling", cnt_lfxt  > r2);

        -- mclk divide-by-2 (mclk_div = CLK_DIV_CR(2:0) = 001): mclk edges over a window should be about half the reference edges over the same window.
        bus_write(clk, pbus, RegSlotSYS_CLK_DIV_CR, x"00000001");
        wait for 20 * PERIOD;                                 -- Let the divider settle.
        v1 := cnt_mclk; r1 := cnt_ref;
        wait for 200 * PERIOD;
        v2 := cnt_mclk - v1;   r2 := cnt_ref - r1;
        sb.check_true("mclk divide-by-2 halves edge rate", abs(r2 - 2*v2) <= 4);
        bus_write(clk, pbus, RegSlotSYS_CLK_DIV_CR, x"00000000");

        -- Switch the mclk source to dco0 (mclk_sel=10) and confirm it keeps ticking.
        v1 := cnt_mclk;
        bus_write(clk, pbus, RegSlotSYS_CLK_CR, x"00000002");           -- mclk_sel = dco0
        wait for 60 * PERIOD;
        sb.check_true("mclk still toggles on dco0 source", cnt_mclk > v1);
        bus_write(clk, pbus, RegSlotSYS_CLK_CR, x"00000000");           -- Back to hfxt.

        -- Final verdict: settle, print the scoreboard summary, then stop.
        wait for 1 us;
        sb.report_summary("SYSTEM TB");
        stop;
        wait;
    end process;

end architecture sim;
