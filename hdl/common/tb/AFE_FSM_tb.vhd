-- AFE_FSM_tb: directed bench for the dual-slope AFE conversion FSM.
-- It runs two conversions: one ended by the comparator (cmp_out) and one left to time out, so both exit paths are exercised.
-- There is no self-checking here; read done, count, sw and result_latch in the waveform.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AFE_FSM_tb is
end entity;

architecture sim of AFE_FSM_tb is

    -- DUT ports
    signal clk        : std_logic := '0';
    signal rst        : std_logic := '0';
    signal start      : std_logic := '0';
    signal enable     : std_logic := '0';
    signal cmp_out    : std_logic := '0';
    signal cycle_set  : std_logic_vector(11 downto 0) := (others => '0');

    signal clk_adc    : std_logic;
    signal count      : std_logic_vector(11 downto 0);
    signal sw         : std_logic_vector(3 downto 1);
    signal done       : std_logic;
    signal result_latch : std_logic_vector(11 downto 0);

    -- Clock period
    constant CLK_PERIOD : time := 40 ns; -- 25 MHz

begin

    -- Clock generator: free-running 25 MHz that stops at 300 us so the run ends on its own.
    clk_process : process
    begin
        while now < 300 us loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
    end process;

    -- DUT instantiation.
    dut: entity work.AFE_FSM
    port map (
        clk          => clk,
        rst          => rst,
        start        => start,
        enable       => enable,
        cmp_out      => cmp_out,
        cycle_set    => cycle_set,
        clk_adc      => clk_adc,
        count        => count,
        sw           => sw,
        done         => done,
        result_latch => result_latch
    );

    -- Stimulus: two conversions, the first ended by the comparator and the second by timeout.
    stim_proc: process
    begin
        -- Initial reset
        rst <= '1';
        enable <= '0';
        wait for 100 ns;
        rst <= '0';
        enable <= '1';

        -- Configure integration cycles
        cycle_set <= std_logic_vector(to_unsigned(2047, 12)); -- 2047 counts, an 11-bit integration window
        wait for 100 ns;

        -- Trigger start
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        -- Let the FSM work through RESET and INTEGRATE.
        wait for 90 us;

        -- Pulse cmp_out to emulate the comparator ending deintegration.
        cmp_out <= '1';
        wait for CLK_PERIOD;
        cmp_out <= '0';

        -- Settle time to observe done and the latched result.
        wait for 500 ns;

        -- Second conversion, with a shorter integration window and no comparator event.
        cycle_set <= std_logic_vector(to_unsigned(1023, 12));
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

	-- Let the FSM reach its timeout instead.
        wait for 90 us;

        -- Nothing further to drive; the clock stops on its own.
        wait;
    end process;

end architecture;

