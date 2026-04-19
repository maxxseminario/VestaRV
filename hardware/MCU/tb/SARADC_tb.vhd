library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.constants.all;
use work.MemoryMap.all;

entity SARADC_tb is
end entity;

architecture sim of SARADC_tb is

    -- DUT signals
    signal clk, clk_mem : std_logic := '0';
    signal resetn       : std_logic := '0';
    signal irq          : std_logic;

    signal en_mem       : std_logic := '1';  -- inactive high
    signal wen          : std_logic_vector(3 downto 0) := (others => '1');
    signal addr_periph  : std_logic_vector(7 downto 2) := (others => '0');
    signal write_data   : std_logic_vector(31 downto 0) := (others => '0');
    signal read_data    : std_logic_vector(31 downto 0);
    signal dtp0, dtp1	: std_logic;

    -- ADC interface
    signal ADC_ready_i  : std_logic := '0';
    signal ADC_data_i   : std_logic_vector(9 downto 0) := (others => '0');
    signal ADC_reset    : std_logic;
    signal ADC_trigger_clock_o : std_logic;

begin
    -------------------------------------------------------------------
    -- Clock generation
    -------------------------------------------------------------------
    clk <= not clk after 25 ns;   -- 40 MHz
    clk_mem <= clk when en_mem = '0';

    -------------------------------------------------------------------
    -- DUT instantiation
    -------------------------------------------------------------------
    dut: entity work.SARADC
        port map (
            clk         => clk,
            resetn      => resetn,
            irq         => irq,
            clk_mem     => clk_mem,
            en_mem      => en_mem,
            wen         => wen,
            addr_periph => addr_periph,
            write_data  => write_data,
            read_data   => read_data,
            ADC_ready_i => ADC_ready_i,
            ADC_data_i  => ADC_data_i,
            ADC_reset   => ADC_reset,
            ADC_trigger_clock_o => ADC_trigger_clock_o,
	    dtp0 => dtp0,
	    dtp1 => dtp1
        );

    -------------------------------------------------------------------
    -- Stimulus
    -------------------------------------------------------------------
    stim_proc: process
    begin
        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------
        resetn <= '0';
        wait for 20 ns;
	wait for 1 ns;
        resetn <= '1';

        ----------------------------------------------------------------
        -- Set ADC settings via CR (bit8 = continuous meas, bit7 = data_rdy_ie, bits4-1 = sample step, bit0 = adc_reset)
        ----------------------------------------------------------------
        wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1100";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotSARADC_CR, 6));
        write_data(8 downto 0) <= "110001110";  -- set cont_meas = ie = 1, adc_en=0, sample_step=0111, reset=0
        wait until rising_edge(clk_mem);

        wen <= (others=>'1');
        wait until falling_edge(clk);
        en_mem <= '1';



	----------------------------------------------------------------
        -- Start ADC via setting adc_en in CR (bit5 = adc_en)
        ----------------------------------------------------------------
        wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1110";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotSARADC_CR, 6));
        write_data(5) <= '1';  
        wait until rising_edge(clk_mem);

        wen <= (others=>'1');
        wait until falling_edge(clk);
        en_mem <= '1';

        -- Observe ADC_trigger_clock_o running for some time
        wait for 4 us;
       
	----------------------------------------------------------------
        -- Stop ADC via setting adc_en in CR (bit14 = adc_en)
        ----------------------------------------------------------------
        wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1110";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotSARADC_CR, 6));
        write_data(5) <= '0';  
        wait until rising_edge(clk_mem);

        wen <= (others=>'1');
        wait until falling_edge(clk);
        en_mem <= '1';

	wait for 1 us;

        ----------------------------------------------------------------
        -- Simulate first ADC conversion
        ----------------------------------------------------------------
        ADC_data_i <= "0000001010"; -- decimal 10
        ADC_ready_i <= '1';
        wait until rising_edge(clk);
	wait for 1 ns;
        ADC_ready_i <= '0';

        wait for 50 ns;

        -- Read SARADC_DATA
        wait until falling_edge(clk);
        en_mem <= '0';
        addr_periph <= std_logic_vector(to_unsigned(RegSlotSARADC_DATA, 6));
        wait until rising_edge(clk_mem);

        wen <= (others=>'1');
        wait until falling_edge(clk);
        en_mem <= '1';

        ----------------------------------------------------------------
        -- Overflow test: back-to-back conversions without clearing
        ----------------------------------------------------------------
        ADC_data_i <= "0000010101"; -- decimal 21
        ADC_ready_i <= '1';
        wait until rising_edge(clk);
	wait for 1 ns;
        ADC_ready_i <= '0';

        wait for 40 ns;

        ----------------------------------------------------------------
        -- Read SR to check overflow flag
        ----------------------------------------------------------------
        wait until falling_edge(clk);
        en_mem <= '0';
        addr_periph <= std_logic_vector(to_unsigned(RegSlotSARADC_SR, 6));
        wait until rising_edge(clk_mem);

        report "SR after overflow = " & integer'image(to_integer(unsigned(read_data(3 downto 0)))) severity note;

        wen <= (others=>'1');
        wait until falling_edge(clk);
        en_mem <= '1';



	----------------------------------------------------------------
        -- Clear data_valid flag
        ----------------------------------------------------------------
        wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1110";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotSARADC_SR, 6));
        write_data <= (others=>'0');
        write_data(1) <= '1';  -- clear data_valid
        wait until rising_edge(clk_mem);

        wen <= (others=>'1');
        wait until falling_edge(clk);
        en_mem <= '1';

        ----------------------------------------------------------------
        -- Clear overflow flag
        ----------------------------------------------------------------
        wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1110";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotSARADC_SR, 6));
        write_data <= (others=>'0');
        write_data(2) <= '1';  -- clear ovf_if
        wait until rising_edge(clk_mem);

        wen <= (others=>'1');
        wait until falling_edge(clk);
        en_mem <= '1';

        ----------------------------------------------------------------
        -- Disable ADC
	--[8]=cont_meas [7]=ie, [6]=debug, [5]=adc_en, sample_steps[=4..1], reset=[0]
        ----------------------------------------------------------------
        wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1100";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotSARADC_CR, 6));
        write_data(8 downto 0) <= "110001110"; -- disable adc
        wait until rising_edge(clk_mem);

        wen <= (others=>'1');
        wait until falling_edge(clk);
        en_mem <= '1';

        ----------------------------------------------------------------
        -- Enable debug mode (CR bit6 = 1) while keeping previous disable
        ----------------------------------------------------------------
        wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1110";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotSARADC_CR, 6));
        write_data(6) <= '1';  
        wait until rising_edge(clk_mem);
        wen <= (others => '1');
        wait until falling_edge(clk);
        en_mem <= '1';


        ----------------------------------------------------------------
        -- Sweep TPR across all 0..15 for dtp0 and dtp1
        -- dtp0_sel = i, dtp1_sel = 15 - i (just to get variety)
        ----------------------------------------------------------------
        for i in 0 to 15 loop
          wait until falling_edge(clk);
          en_mem <= '0'; wen <= "1110";
          addr_periph <= std_logic_vector(to_unsigned(RegSlotSARADC_TPR, 6));
          write_data(3 downto 0) <= std_logic_vector(to_unsigned(i,4));           -- dtp0_sel
          write_data(7 downto 4) <= std_logic_vector(to_unsigned(15 - i,4));      -- dtp1_sel
          wait until rising_edge(clk_mem);
          wen <= (others => '1');
          wait until falling_edge(clk);
          en_mem <= '1';

          wait for 60 ns; -- allow mux to settle and be visible on the waveform
        end loop;

        

        wait for 500 ns;
        assert false report "Simulation complete" severity failure;
    end process;

end architecture;

