-------------------------------------------------------------------------------
-- SYSTEM_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the SYSTEM peripheral
-- (hdl/MCU/periph/SYSTEM.vhd) -- the clock/reset/IRQ/WDT/CRC controller.
--
-- Unlike the other peripheral benches, SYSTEM generates its OWN synchronous
-- reset (resetn_sys) from clk_hfxt_in via mclk, so the bench must feed a live
-- clk_hfxt_in from t=0 and only exercise the register bus once resetn_sys has
-- deasserted.  The memory-bus clock (clk_mem) is gated from the same reference
-- clock, exactly as the SoC gates each peripheral's clk_periph by its select.
--
-- Coverage:
--   * reset defaults (CLK_CR, CLK_DIV_CR, BLOCK_PWR, WDT_CR/SR/VAL, IRQ_EN/PRI,
--     DCO0/1_BIAS) and reset-derived outputs (PGEN_mem, irq_priority, irq_sys_wdt)
--   * R/W of every writable register + byte-lane behaviour
--   * register->pad routing: BLOCK_PWR->PGEN_mem, DCO bias + dco_on->en_dco*_out
--   * IRQ mask: SYS_IRQ_EN->irq_en gated by the global enable (SYS_IRQ_CR(0)),
--     SYS_IRQ_PRI->irq_priority, SYS_IRQ_CR(1)->irq_recursion_en
--   * CRC16 engine: feed bytes, compare SYS_CRC_STATE against a software model
--   * watchdog: password lock, unlock+write, counter run, clear-by-password,
--     timeout interrupt flag (wdt_if) + SR clear path
--   * clock tree: mclk/smclk/hfxt/lfxt outputs toggle, mclk divider, source mux
--
-- Bus contract (see tb/CLAUDE.md): en_mem active-low, wen active-low per byte
-- lane, clk_mem gated (only ticks while en_mem='0').
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.constants.all;
use work.MemoryMap.all;

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
    signal isr_ret      : std_logic := '0';
    signal irq          : std_logic_vector(NUM_IRQS-1 downto 0) := (others => '0');

    -- interrupt mask outputs (SoC uses NUM_IRQS = 83: L/M/U 32-bit words)
    signal irq_en           : std_logic_vector(NUM_IRQS-1 downto 0);
    signal irq_priority     : std_logic_vector(NUM_IRQS-1 downto 0);
    signal irq_recursion_en : std_logic;
    signal irq_sys_wdt      : std_logic;

    -- register bus
    signal en_mem      : std_logic := '1';
    signal clk_mem     : std_logic := '0';
    signal wen         : std_logic_vector(3 downto 0) := (others => '1');
    signal addr_periph : std_logic_vector(7 downto 2) := (others => '0');
    signal write_data  : std_logic_vector(31 downto 0) := (others => '0');
    signal read_data   : std_logic_vector(31 downto 0);

    -- clock outputs
    signal mclk_out, smclk_out, clk_lfxt_out, clk_hfxt_out : std_logic;

    -- DCO / power outputs
    signal en_dco0_out, en_dco1_out : std_logic;
    signal DCO0_BIAS, DCO1_BIAS     : std_logic_vector(11 downto 0);
    signal PGEN_mem                 : std_logic_vector(2 downto 0);

    -- edge counters for clock-output activity checks
    signal cnt_mclk  : natural := 0;
    signal cnt_smclk : natural := 0;
    signal cnt_hfxt  : natural := 0;
    signal cnt_lfxt  : natural := 0;
    signal cnt_ref   : natural := 0;

    function img(v : std_logic_vector) return string is
    begin
        if is_x(v) then return "X";
        else return integer'image(to_integer(unsigned(v))); end if;
    end function;

    -- Software mirror of commune/CRC16.vhd (POLYNOMIAL 0xC857, MSB-first, no
    -- reflection, no final xor). Feeds one byte, returns the updated CRC.
    function crc16_byte(d : std_logic_vector(7 downto 0);
                        crc_old : std_logic_vector(15 downto 0))
        return std_logic_vector is
        variable lfsr : std_logic_vector(15 downto 0);
        constant poly : std_logic_vector(15 downto 0) := x"C857";
    begin
        lfsr := (crc_old(15 downto 8) xor d) & crc_old(7 downto 0);
        for i in 0 to 7 loop
            if lfsr(15) = '1' then
                lfsr := (lfsr(14 downto 0) & '0') xor poly;
            else
                lfsr := (lfsr(14 downto 0) & '0');
            end if;
        end loop;
        return lfsr;
    end function;

begin

    -- reference clock + oscillators (all free-running from t=0)
    clk         <= not clk         after PERIOD / 2;
    clk_lfxt_in <= not clk_lfxt_in after 160 ns;   -- slow crystal
    clk_dco0_in <= not clk_dco0_in after 70 ns;
    clk_dco1_in <= not clk_dco1_in after 90 ns;

    -- gated memory-bus clock: ticks only while the peripheral is selected
    clk_mem <= clk when en_mem = '0' else '0';

    -- clock-output edge counters
    process(mclk_out)     begin if rising_edge(mclk_out)     then cnt_mclk  <= cnt_mclk  + 1; end if; end process;
    process(smclk_out)    begin if rising_edge(smclk_out)    then cnt_smclk <= cnt_smclk + 1; end if; end process;
    process(clk_hfxt_out) begin if rising_edge(clk_hfxt_out) then cnt_hfxt  <= cnt_hfxt  + 1; end if; end process;
    process(clk_lfxt_out) begin if rising_edge(clk_lfxt_out) then cnt_lfxt  <= cnt_lfxt  + 1; end if; end process;
    process(clk)          begin if rising_edge(clk)          then cnt_ref   <= cnt_ref   + 1; end if; end process;

    dut : entity work.SYSTEM
        generic map ( NUM_IRQS => NUM_IRQS )
        port map (
            clk_lfxt_in => clk_lfxt_in, clk_hfxt_in => clk,
            clk_dco0_in => clk_dco0_in, clk_dco1_in => clk_dco1_in,
            resetn_in => resetn_in, resetn_por => resetn_por, resetn_sys => resetn_sys,
            irq => irq, isr_ret => isr_ret,
            irq_en => irq_en, irq_priority => irq_priority,
            irq_recursion_en => irq_recursion_en, irq_sys_wdt => irq_sys_wdt,
            clk_mem => clk_mem, en_mem => en_mem, wen => wen,
            addr_periph => addr_periph, write_data => write_data, read_data => read_data,
            mclk_out => mclk_out, smclk_out => smclk_out,
            clk_lfxt_out => clk_lfxt_out, clk_hfxt_out => clk_hfxt_out,
            en_dco0_out => en_dco0_out, DCO0_BIAS => DCO0_BIAS,
            en_dco1_out => en_dco1_out, DCO1_BIAS => DCO1_BIAS,
            PGEN_mem => PGEN_mem
        );

    stim_proc : process

        variable error_count : natural := 0;
        variable rdw         : std_logic_vector(31 downto 0);
        variable crc         : std_logic_vector(15 downto 0);
        variable v1, v2, r1, r2 : natural;

        procedure check_slv(tag : in string;
                            got : in std_logic_vector; exp : in std_logic_vector) is
        begin
            if got = exp then report "PASS: " & tag severity note;
            else
                error_count := error_count + 1;
                assert false report "FAIL: " & tag &
                    " (expected " & img(exp) & ", got " & img(got) & ")"
                    severity warning;
            end if;
        end procedure;

        procedure check_bit(tag : in string; got : in std_logic; exp : in std_logic) is
        begin
            if got = exp then report "PASS: " & tag severity note;
            else
                error_count := error_count + 1;
                assert false report "FAIL: " & tag &
                    " (expected " & std_logic'image(exp) &
                    ", got " & std_logic'image(got) & ")" severity warning;
            end if;
        end procedure;

        procedure check_true(tag : in string; cond : in boolean) is
        begin
            if cond then report "PASS: " & tag severity note;
            else
                error_count := error_count + 1;
                assert false report "FAIL: " & tag severity warning;
            end if;
        end procedure;

        procedure bus_write(slot : in natural; data : in std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(clk);
            addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            write_data  <= data;
            wen         <= (others => '0');
            en_mem      <= '0';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            en_mem <= '1';
            wen    <= (others => '1');
        end procedure;

        procedure bus_read(slot : in natural; data : out std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(clk);
            addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            en_mem      <= '0';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            data   := read_data;
            en_mem <= '1';
        end procedure;

        -- Multi-cycle write: holds the select low across `ncyc` bus clocks.
        -- Needed to clear WDT flags, whose clear pulse is consumed
        -- synchronously by clk_wdt and must overlap a WDT-clock rising edge
        -- distinct from the edge that raises the pulse.
        procedure bus_write_hold(slot : in natural;
                                 data : in std_logic_vector(31 downto 0);
                                 ncyc : in natural) is
        begin
            wait until falling_edge(clk);
            addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            write_data  <= data;
            wen         <= (others => '0');
            en_mem      <= '0';
            for i in 1 to ncyc loop
                wait until rising_edge(clk);
            end loop;
            wait until falling_edge(clk);
            en_mem <= '1';
            wen    <= (others => '1');
        end procedure;

    begin
        ----------------------------------------------------------------
        -- Reset. resetn_sys is generated internally from mclk, so hold
        -- resetn_por low while the clock primes the glitch-free muxes,
        -- then release and wait for resetn_sys to propagate.
        ----------------------------------------------------------------
        resetn_por <= '0';
        en_mem <= '1'; wen <= (others => '1');
        wait for 10 * PERIOD;
        resetn_por <= '1';
        wait for 10 * PERIOD;

        ----------------------------------------------------------------
        -- GROUP 1: reset & defaults
        ----------------------------------------------------------------
        report "=== GROUP 1: reset & defaults ===" severity note;

        check_bit("resetn_sys deasserted after reset", resetn_sys, '1');

        bus_read(RegSlotSYS_CLK_CR, rdw);
        check_slv("SYS_CLK_CR resets to 0", rdw(8 downto 0), (8 downto 0 => '0'));
        bus_read(RegSlotSYS_CLK_DIV_CR, rdw);
        check_slv("SYS_CLK_DIV_CR resets to 0", rdw(5 downto 0), (5 downto 0 => '0'));
        bus_read(RegSlotSYS_BLOCK_PWR, rdw);
        check_slv("SYS_BLOCK_PWR resets to 0", rdw(2 downto 0), "000");
        bus_read(RegSlotSYS_WDT_CR, rdw);
        check_slv("SYS_WDT_CR resets to 0", rdw(7 downto 0), x"00");
        bus_read(RegSlotSYS_WDT_SR, rdw);
        check_slv("SYS_WDT_SR resets to 0", rdw(1 downto 0), "00");
        bus_read(RegSlotSYS_WDT_VAL, rdw);
        check_slv("SYS_WDT_VAL resets to 0 (wdt off)", rdw(23 downto 0), (23 downto 0 => '0'));
        bus_read(RegSlotSYS_IRQ_ENL, rdw);
        check_slv("SYS_IRQ_EN resets to 0", rdw, x"00000000");
        bus_read(RegSlotSYS_IRQ_PRIL, rdw);
        check_slv("SYS_IRQ_PRI resets to 0", rdw, x"00000000");
        bus_read(RegSlotDCO0_BIAS, rdw);
        check_slv("SYS DCO0_BIAS reg = default 0x800", rdw(11 downto 0), x"800");
        bus_read(RegSlotDCO1_BIAS, rdw);
        check_slv("SYS DCO1_BIAS reg = default 0x800", rdw(11 downto 0), x"800");

        -- reset-derived outputs
        check_slv("DCO0_BIAS pad = default 0x800", DCO0_BIAS, x"800");
        check_slv("DCO1_BIAS pad = default 0x800", DCO1_BIAS, x"800");
        check_slv("PGEN_mem = 0 at reset (all on)", PGEN_mem, "000");
        check_slv("irq_priority = 0 at reset", irq_priority, (NUM_IRQS-1 downto 0 => '0'));
        check_bit("irq_sys_wdt hardwired 0", irq_sys_wdt, '0');

        ----------------------------------------------------------------
        -- GROUP 2: register read/write + pad routing
        ----------------------------------------------------------------
        report "=== GROUP 2: register R/W ===" severity note;

        -- CLK_CR: keep mclk_sel(1:0)=00 so the reference clock survives.
        bus_write(RegSlotSYS_CLK_CR, x"000001FC");
        bus_read(RegSlotSYS_CLK_CR, rdw);
        check_slv("SYS_CLK_CR 9-bit readback", rdw(8 downto 0), '1' & x"FC");
        bus_write(RegSlotSYS_CLK_CR, x"00000000");

        -- CLK_DIV_CR
        bus_write(RegSlotSYS_CLK_DIV_CR, x"0000002A");
        bus_read(RegSlotSYS_CLK_DIV_CR, rdw);
        check_slv("SYS_CLK_DIV_CR 6-bit readback", rdw(5 downto 0), "101010");
        bus_write(RegSlotSYS_CLK_DIV_CR, x"00000000");

        -- BLOCK_PWR -> PGEN_mem (ram_off & rom_off)
        bus_write(RegSlotSYS_BLOCK_PWR, x"00000005");        -- ram_off=10, rom_off=1
        bus_read(RegSlotSYS_BLOCK_PWR, rdw);
        check_slv("SYS_BLOCK_PWR readback", rdw(2 downto 0), "101");
        check_slv("PGEN_mem tracks BLOCK_PWR", PGEN_mem, "101");
        bus_write(RegSlotSYS_BLOCK_PWR, x"00000000");
        check_slv("PGEN_mem back to 0", PGEN_mem, "000");

        -- DCO bias registers + dco_on -> en_dco*_out
        bus_write(RegSlotDCO0_BIAS, x"00000ABC");
        bus_read(RegSlotDCO0_BIAS, rdw);
        check_slv("DCO0_BIAS 12-bit readback", rdw(11 downto 0), x"ABC");
        check_slv("DCO0_BIAS pad tracks reg", DCO0_BIAS, x"ABC");
        bus_write(RegSlotDCO1_BIAS, x"00000DEF");
        bus_read(RegSlotDCO1_BIAS, rdw);
        check_slv("DCO1_BIAS 12-bit readback", rdw(11 downto 0), x"DEF");
        check_slv("DCO1_BIAS pad tracks reg", DCO1_BIAS, x"DEF");

        bus_write(RegSlotSYS_CLK_CR, x"00000180");           -- dco0_on(7)+dco1_on(8)
        check_bit("en_dco0_out set when dco0_on", en_dco0_out, '1');
        check_bit("en_dco1_out set when dco1_on", en_dco1_out, '1');
        bus_write(RegSlotSYS_CLK_CR, x"00000000");
        check_bit("en_dco0_out clears", en_dco0_out, '0');
        check_bit("en_dco1_out clears", en_dco1_out, '0');

        ----------------------------------------------------------------
        -- GROUP 3: interrupt mask registers + global enable gating
        ----------------------------------------------------------------
        report "=== GROUP 3: IRQ mask / enable ===" severity note;

        -- lower and middle IRQ-enable words (L = bits 31:0, M = bits 63:32)
        bus_write(RegSlotSYS_IRQ_ENL, x"DEADBEEF");
        bus_read(RegSlotSYS_IRQ_ENL, rdw);
        check_slv("SYS_IRQ_EN L-word readback", rdw, x"DEADBEEF");
        bus_write(RegSlotSYS_IRQ_ENM, x"CAFEF00D");
        bus_read(RegSlotSYS_IRQ_ENM, rdw);
        check_slv("SYS_IRQ_EN M-word readback", rdw, x"CAFEF00D");

        -- global enable off (IRQ_CR(0)=0): irq_en output must be masked to 0
        bus_write(RegSlotSYS_IRQ_CR, x"00000000");
        check_slv("irq_en gated to 0 when global IRQ off", irq_en, (NUM_IRQS-1 downto 0 => '0'));

        -- global enable on: irq_en passes the mask through (check L + M words)
        bus_write(RegSlotSYS_IRQ_CR, x"00000001");
        check_slv("irq_en L passes mask when global IRQ on", irq_en(31 downto 0),  x"DEADBEEF");
        check_slv("irq_en M passes mask when global IRQ on", irq_en(63 downto 32), x"CAFEF00D");

        -- recursion enable is IRQ_CR(1)
        bus_write(RegSlotSYS_IRQ_CR, x"00000002");
        check_bit("irq_recursion_en set from IRQ_CR(1)", irq_recursion_en, '1');
        check_slv("irq_en gated again (global off)", irq_en(31 downto 0), x"00000000");
        bus_write(RegSlotSYS_IRQ_CR, x"00000001");
        check_bit("irq_recursion_en clears", irq_recursion_en, '0');

        -- priority mask -> irq_priority pad
        bus_write(RegSlotSYS_IRQ_PRIL, x"12345678");
        bus_read(RegSlotSYS_IRQ_PRIL, rdw);
        check_slv("SYS_IRQ_PRI readback", rdw, x"12345678");
        check_slv("irq_priority pad tracks reg", irq_priority(31 downto 0), x"12345678");

        -- tidy up
        bus_write(RegSlotSYS_IRQ_ENL, x"00000000");
        bus_write(RegSlotSYS_IRQ_ENM, x"00000000");
        bus_write(RegSlotSYS_IRQ_PRIL, x"00000000");
        bus_write(RegSlotSYS_IRQ_CR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 4: CRC16 engine
        --   Init by writing SYS_CRC_STATE (sets first_crc_flag), then feed
        --   bytes through SYS_CRC_DATA and compare the accumulated state.
        ----------------------------------------------------------------
        report "=== GROUP 4: CRC16 ===" severity note;

        bus_write(RegSlotSYS_CRC_STATE, x"0000FFFF");        -- initial value
        crc := x"FFFF";
        bus_write(RegSlotSYS_CRC_DATA, x"00000012"); crc := crc16_byte(x"12", crc);
        bus_write(RegSlotSYS_CRC_DATA, x"00000034"); crc := crc16_byte(x"34", crc);
        bus_write(RegSlotSYS_CRC_DATA, x"00000056"); crc := crc16_byte(x"56", crc);
        bus_read(RegSlotSYS_CRC_STATE, rdw);
        check_slv("CRC16 over {12,34,56} matches model", rdw(15 downto 0), crc);

        ----------------------------------------------------------------
        -- GROUP 5: watchdog timer
        ----------------------------------------------------------------
        report "=== GROUP 5: watchdog ===" severity note;

        -- (a) WDT_CR write is password-locked: a bare write is ignored
        bus_write(RegSlotSYS_WDT_CR, x"000000FC");
        bus_read(RegSlotSYS_WDT_CR, rdw);
        check_slv("WDT_CR write blocked while locked", rdw(7 downto 0), x"00");

        -- (b) unlock, then write WDT_CR within the 64-cycle window.
        --     cdiv=5 -> watched bit is WDT_VAL(5), which rises at count 32 and
        --     only re-rises every 64 counts, giving a wide window to observe
        --     the flag set and then cleared before it re-asserts.
        bus_write(RegSlotSYS_WDT_PASS, WDT_UNLCK_PASSWD);
        bus_write(RegSlotSYS_WDT_CR, x"00000094");           -- wdt_en=1, cdiv=5, ie=0
        bus_read(RegSlotSYS_WDT_CR, rdw);
        check_slv("WDT_CR written after unlock", rdw(7 downto 0), x"94");

        -- (c) counter runs while enabled
        bus_read(RegSlotSYS_WDT_VAL, rdw);
        v1 := to_integer(unsigned(rdw(23 downto 0)));
        wait for 40 * PERIOD;
        bus_read(RegSlotSYS_WDT_VAL, rdw);
        v2 := to_integer(unsigned(rdw(23 downto 0)));
        check_true("WDT counter increments while enabled", v2 > v1);

        -- (d) timeout sets wdt_if (SR bit 1): WDT_VAL(5) has risen (count>32)
        bus_read(RegSlotSYS_WDT_SR, rdw);
        check_bit("WDT timeout sets wdt_if (SR bit1)", rdw(1), '1');

        -- (e) clear the interrupt flag by writing SR bit1 (held access so the
        --     clear pulse overlaps a WDT-clock edge)
        bus_write_hold(RegSlotSYS_WDT_SR, x"00000002", 3);
        bus_read(RegSlotSYS_WDT_SR, rdw);
        check_bit("wdt_if cleared via SR write", rdw(1), '0');

        -- (f) clear the counter with the WDT clear password
        bus_read(RegSlotSYS_WDT_VAL, rdw);
        v1 := to_integer(unsigned(rdw(23 downto 0)));
        bus_write(RegSlotSYS_WDT_PASS, WDT_CLR_PASSWD);
        bus_read(RegSlotSYS_WDT_VAL, rdw);
        v2 := to_integer(unsigned(rdw(23 downto 0)));
        check_true("WDT clear password resets counter", v2 < v1);

        -- disable the WDT again (unlock first)
        bus_write(RegSlotSYS_WDT_PASS, WDT_UNLCK_PASSWD);
        bus_write(RegSlotSYS_WDT_CR, x"00000000");

        ----------------------------------------------------------------
        -- GROUP 6: clock tree activity
        ----------------------------------------------------------------
        report "=== GROUP 6: clocks ===" severity note;

        -- all four clock outputs should be toggling at reset defaults
        v1 := cnt_mclk;  r1 := cnt_smclk;
        v2 := cnt_hfxt;  r2 := cnt_lfxt;
        wait for 60 * PERIOD;
        check_true("mclk_out toggling",     cnt_mclk  > v1);
        check_true("smclk_out toggling",    cnt_smclk > r1);
        check_true("clk_hfxt_out toggling", cnt_hfxt  > v2);
        check_true("clk_lfxt_out toggling", cnt_lfxt  > r2);

        -- mclk divide-by-2 (mclk_div = CLK_DIV_CR(2:0) = 001): mclk edges over a
        -- window should be ~half the reference edges over the same window.
        bus_write(RegSlotSYS_CLK_DIV_CR, x"00000001");
        wait for 20 * PERIOD;                                 -- let divider settle
        v1 := cnt_mclk; r1 := cnt_ref;
        wait for 200 * PERIOD;
        v2 := cnt_mclk - v1;   r2 := cnt_ref - r1;
        check_true("mclk divide-by-2 halves edge rate", abs(r2 - 2*v2) <= 4);
        bus_write(RegSlotSYS_CLK_DIV_CR, x"00000000");

        -- switch mclk source to dco0 (mclk_sel=10) and confirm it keeps ticking
        v1 := cnt_mclk;
        bus_write(RegSlotSYS_CLK_CR, x"00000002");           -- mclk_sel = dco0
        wait for 60 * PERIOD;
        check_true("mclk still toggles on dco0 source", cnt_mclk > v1);
        bus_write(RegSlotSYS_CLK_CR, x"00000000");           -- back to hfxt

        ----------------------------------------------------------------
        -- Final verdict
        ----------------------------------------------------------------
        wait for 1 us;
        if error_count = 0 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##                                              ##" & LF &
                "    ##       SYSTEM TB:  ALL CHECKS PASSED          ##" & LF &
                "    ##                                              ##" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!                                              !!" & LF &
                "    !!    SYSTEM TB:  " & integer'image(error_count) &
                       " CHECK(S) FAILED" & LF &
                "    !!                                              !!" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        stop;
        wait;
    end process;

end architecture sim;
