-- VestaRV: SKEL testbench
-- Standalone, self-checking bench for the skeleton peripheral, on the shared
-- periph_tb_pkg bus BFM and scoreboard. It covers what every peripheral bench must:
-- reset values, byte-lane merging, an unimplemented bit reading 0, the GO command strobe,
-- the hardware-set DONE flag and its write-1-to-clear, and one negative control.
-- clk_mem free-runs because SKEL consumes wr_pulse with STROBE_HOLD false.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.skel_regs_pkg.all;

entity SKEL_tb is
end entity SKEL_tb;

architecture sim of SKEL_tb is

    constant PERIOD : time := 20 ns;

    -- The DUT is a component so this bench compiles standalone; default binding
    -- resolves it once SKEL.vhd is analyzed into work.
    component SKEL is
        port (
            clk_mem     : in  std_logic;
            resetn      : in  std_logic;
            en_mem      : in  std_logic;
            wen         : in  std_logic_vector(3 downto 0);
            addr_periph : in  std_logic_vector(7 downto 2);
            write_data  : in  std_logic_vector(31 downto 0);
            read_data   : out std_logic_vector(31 downto 0);
            irq         : out std_logic
        );
    end component;

    signal clk       : std_logic := '0';
    signal clk_mem   : std_logic;
    signal resetn    : std_logic := '0';
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal read_data : std_logic_vector(31 downto 0);
    signal irq       : std_logic;
    signal tb_done   : boolean := false;

    shared variable sb : scoreboard;

begin

    clk     <= not clk after PERIOD / 2;
    clk_mem <= clk;

    dut : component SKEL
        port map (
            clk_mem     => clk_mem,
            resetn      => resetn,
            en_mem      => pbus.en_mem,
            wen         => pbus.wen,
            addr_periph => pbus.addr_periph,
            write_data  => pbus.write_data,
            read_data   => read_data,
            irq         => irq
        );

    -- Abort with a FAIL banner if the stimulus ever hangs.
    watchdog : process
    begin
        wait for 20 ms;
        if not tb_done then
            report LF & "    !!   SKEL_TB FAIL (WATCHDOG TIMEOUT -- stimulus never finished)" & LF
                severity warning;
            stop;
        end if;
        wait;
    end process;

    stim_proc : process
        variable rdw : std_logic_vector(31 downto 0);
        variable ok  : boolean;

        procedure reset_pulse is
        begin
            resetn <= '0';
            pbus   <= PERIPH_BUS_IDLE;
            wait for 6 * PERIOD;
            wait for 1 ns;
            resetn <= '1';
            wait for 4 * PERIOD;
        end procedure;

        -- bus_write with the byte lanes chosen by the caller: periph_tb_pkg's own
        -- procedure always drives all four. Lanes are active low, lane i covering
        -- bits 8*i+7 downto 8*i.
        procedure bus_write_lane(slot : in natural;
                                 lanes : in std_logic_vector(3 downto 0);
                                 data : in std_logic_vector(31 downto 0)) is
        begin
            wait until clk = '0';
            pbus.addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            pbus.write_data  <= data;
            pbus.wen         <= lanes;
            pbus.en_mem      <= '0';
            wait until clk = '1';
            wait until clk = '0';
            pbus.en_mem <= '1';
            pbus.wen    <= (others => '1');
        end procedure;

        -- Bounded poll of SKELxSR.DONE. A bench never waits a fixed number of
        -- edges for a datapath it does not own the clock of.
        procedure poll_done(guard : in natural; ok : out boolean) is
            variable v : std_logic_vector(31 downto 0);
        begin
            ok := false;
            for i in 1 to guard loop
                bus_read(clk, pbus, read_data, SLOT_SR, v);
                if v(DONE_LSB) = '1' then
                    ok := true;
                    return;
                end if;
            end loop;
        end procedure;

    begin
        report "=== GROUP 1: RESET VALUES ===" severity note;
        reset_pulse;
        bus_read(clk, pbus, read_data, SLOT_CR, rdw);
        sb.check_slv("SKELxCR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, read_data, SLOT_SR, rdw);
        sb.check_slv("SKELxSR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, read_data, SLOT_DR, rdw);
        sb.check_slv("SKELxDR resets to 0", rdw, x"00000000");
        sb.check_bit("irq low out of reset", irq, '0');

        report "=== GROUP 2: STORAGE AND BYTE LANES ===" severity note;
        bus_write(clk, pbus, SLOT_DR, x"A5A5A5A5");
        bus_read(clk, pbus, read_data, SLOT_DR, rdw);
        sb.check_slv("SKELxDR stores a four-lane write", rdw, x"A5A5A5A5");
        bus_write_lane(SLOT_DR, "1011", x"11223344");
        bus_read(clk, pbus, read_data, SLOT_DR, rdw);
        sb.check_slv("lane 2 alone writes bits 23:16", rdw, x"A522A5A5");
        bus_write_lane(SLOT_DR, "1110", x"000000FF");
        bus_read(clk, pbus, read_data, SLOT_DR, rdw);
        sb.check_slv("lane 0 alone writes bits 7:0", rdw, x"A522A5FF");

        -- SKELxCR implements one bit. GO is sw = w and holds nothing, so an
        -- all-ones write reads back as EN alone.
        bus_write(clk, pbus, SLOT_CR, x"FFFFFFFF");
        bus_read(clk, pbus, read_data, SLOT_CR, rdw);
        sb.check_slv("SKELxCR reads only its implemented bit", rdw, x"00000001");

        report "=== GROUP 3: COMMAND STROBE ===" severity note;
        reset_pulse;
        bus_write(clk, pbus, SLOT_CR, x"00000001");   -- EN, no GO
        bus_read(clk, pbus, read_data, SLOT_SR, rdw);
        sb.check_slv("EN alone starts nothing", rdw, x"00000000");
        bus_write(clk, pbus, SLOT_CR, x"00000003");   -- EN + GO
        bus_read(clk, pbus, read_data, SLOT_SR, rdw);
        sb.check_slv("BUSY is set while the pass runs", rdw, x"00000002");
        poll_done(20, ok);
        sb.check_true("DONE is set when the pass finishes", ok);
        bus_read(clk, pbus, read_data, SLOT_SR, rdw);
        sb.check_slv("BUSY is clear once DONE is set", rdw, x"00000001");
        sb.check_bit("irq follows DONE", irq, '1');

        report "=== GROUP 4: WRITE-1-TO-CLEAR ===" severity note;
        bus_write(clk, pbus, SLOT_SR, x"00000001");
        bus_read(clk, pbus, read_data, SLOT_SR, rdw);
        sb.check_slv("a 1 written to DONE clears it", rdw, x"00000000");
        bus_write(clk, pbus, SLOT_CR, x"00000003");
        poll_done(20, ok);
        sb.check_true("DONE sets again on the next pass", ok);
        bus_write(clk, pbus, SLOT_SR, x"00000002");   -- a 1 on BUSY, which is not W1C
        bus_read(clk, pbus, read_data, SLOT_SR, rdw);
        sb.check_slv("a write misses the bits outside W1C", rdw, x"00000001");
        bus_write(clk, pbus, SLOT_SR, x"00000001");

        report "=== GROUP 5: THE ENABLE GUARD ===" severity note;
        bus_write(clk, pbus, SLOT_CR, x"00000000");   -- EN clear
        bus_write(clk, pbus, SLOT_CR, x"00000002");   -- GO with EN clear
        for i in 1 to 20 loop
            wait until clk = '1';
        end loop;
        bus_read(clk, pbus, read_data, SLOT_SR, rdw);
        sb.check_slv("GO with EN clear starts nothing", rdw, x"00000000");

        -- GROUP G-NEG: NEGATIVE CONTROL (mandatory, LAST).
        -- Exactly ONE deliberately wrong expected value, so the scoreboard proves it can fail.
        -- periph_tb_pkg.img converts through to_integer, so an expected word must stay below 0x80000000.
        report "=== GROUP G-NEG: NEGATIVE CONTROL ===" severity note;
        bus_read(clk, pbus, read_data, SLOT_DR, rdw);
        sb.check_slv("NEGATIVE CONTROL: wrong expected SKELxDR (must FAIL)", rdw, x"0BADF00D");

        wait for 1 us;
        sb.report_summary("SKEL TB");

        if sb.errors = 1 then
            report LF & "    ##   SKEL_TB PASS (1 expected negative-control failure)" & LF
                severity note;
        else
            report LF & "    !!   SKEL_TB FAIL (expected exactly 1 failure [negative control], got "
                & integer'image(sb.errors) & ")" & LF
                severity warning;
        end if;

        tb_done <= true;
        stop;
        wait;
    end process stim_proc;

end architecture sim;
