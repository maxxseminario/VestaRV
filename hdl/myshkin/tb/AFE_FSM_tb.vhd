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

    -------------------------------------------------------------------
    -- Clock generator
    -------------------------------------------------------------------
    clk_process : process
    begin
        while now < 300 us loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
    end process;

    -------------------------------------------------------------------
    -- DUT instantiation
    -------------------------------------------------------------------
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

    -------------------------------------------------------------------
    -- Stimulus
    -------------------------------------------------------------------
    stim_proc: process
    begin
        -- Initial reset
        rst <= '1';
        enable <= '0';
        wait for 100 ns;
        rst <= '0';
        enable <= '1';

        -- Configure integration cycles
        cycle_set <= std_logic_vector(to_unsigned(2047, 12)); -- e.g. 11 bits
        wait for 100 ns;

        -- Trigger start
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

        -- Let FSM go through RESET + INTEGRATE
        wait for 90 us;

        -- Toggle cmp_out to emulate comparator triggering end of deintegration
        cmp_out <= '1';
        wait for CLK_PERIOD;
        cmp_out <= '0';

        -- Observe done + result latch
        wait for 500 ns;

        -- Another conversion
        cycle_set <= std_logic_vector(to_unsigned(1023, 12));
        start <= '1';
        wait for CLK_PERIOD;
        start <= '0';

	-- Let FSM timeout
        wait for 90 us;

        -- Finish simulation
        wait;
    end process;

end architecture;

