library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use work.constants.all;
use work.MemoryMap.all;

entity AFE_tb is
end entity;

architecture sim of AFE_tb is

    -- Standalone bench for the AFE peripheral: writes every BIAS register over the peripheral bus and checks the exported bias outputs, then runs one single-shot ADC conversion.

    -- DUT bus and control signals.
    signal clk, clk_mem     : std_logic := '0';
    signal resetn           : std_logic := '0';
    signal irq              : std_logic;

    signal en_mem           : std_logic := '1';  -- Peripheral chip select, active low.
    signal wen              : std_logic_vector(3 downto 0) := (others => '1');
    signal addr_periph      : std_logic_vector(7 downto 2) := (others => '0');
    signal write_data       : std_logic_vector(31 downto 0) := (others => '0');
    signal read_data        : std_logic_vector(31 downto 0);

    -- Four digital test pins: input value plus the pin's ren/dir/out drive from the AFE.
    signal dtp0_ren_in : std_logic;
    signal dtp0_ren    : std_logic;
    signal dtp0_dir    : std_logic;
    signal dtp0_out    : std_logic;

    signal dtp1_ren_in : std_logic;
    signal dtp1_ren    : std_logic;
    signal dtp1_dir    : std_logic;
    signal dtp1_out    : std_logic;

    signal dtp2_ren_in : std_logic;
    signal dtp2_ren    : std_logic;
    signal dtp2_dir    : std_logic;
    signal dtp2_out    : std_logic;

    signal dtp3_ren_in : std_logic;
    signal dtp3_ren    : std_logic;
    signal dtp3_dir    : std_logic;
    signal dtp3_out    : std_logic;

    -- Analog front-end interface: comparator return plus the ADC/test-path controls.
    signal cmp_out          : std_logic := '0';
    signal adc_clk, adc_en          : std_logic;
    signal adc_switch       : std_logic_vector(2 downto 0);
    signal adc_ext_in, atp_en, atp_sel, adc_sel, dac_en : std_logic;

    -- Bias outputs observed by the checks below.
    signal use_bias_dac, en_bias_buf, en_bias_gen : std_logic;
    signal BIAS_ADJ        : std_logic_vector(5 downto 0);
    signal BIAS_DBP        : std_logic_vector(13 downto 0);
    signal BIAS_DBN        : std_logic_vector(13 downto 0);
    signal BIAS_DBPC       : std_logic_vector(13 downto 0);
    signal BIAS_DBNC       : std_logic_vector(13 downto 0);
    signal BIAS_TC_POT     : std_logic_vector(5 downto 0);
    signal BIAS_LC_POT     : std_logic_vector(5 downto 0);
    signal BIAS_TIA_G_POT  : std_logic_vector(16 downto 0);
    signal BIAS_REV_POT    : std_logic_vector(13 downto 0);
    signal BIAS_TC_DSADC   : std_logic_vector(5 downto 0);
    signal BIAS_LC_DSADC   : std_logic_vector(5 downto 0);
    signal BIAS_RIN_DSADC  : std_logic_vector(5 downto 0);
    signal BIAS_RFB_DSADC  : std_logic_vector(5 downto 0);
    signal BIAS_DSADC_VCM  : std_logic_vector(13 downto 0);

begin
    -------------------------------------------------------------------
    -- Clock generation.
    -------------------------------------------------------------------
    clk     <= not clk after 25 ns;   -- 40 MHz core clock.
    clk_mem <= clk when en_mem = '0'; -- Register clock is gated by the chip select.

    -------------------------------------------------------------------
    -- DUT instantiation.
    -------------------------------------------------------------------
    dut: entity work.AFE
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

            dtp0_ren_in => dtp0_ren_in,
            dtp0_ren    => dtp0_ren,
            dtp0_dir    => dtp0_dir,
            dtp0_out    => dtp0_out,
            dtp1_ren_in => dtp1_ren_in,
            dtp1_ren    => dtp1_ren,
            dtp1_dir    => dtp1_dir,
            dtp1_out    => dtp1_out,
            dtp2_ren_in => dtp2_ren_in,
            dtp2_ren    => dtp2_ren,
            dtp2_dir    => dtp2_dir,
            dtp2_out    => dtp2_out,
            dtp3_ren_in => dtp3_ren_in,
            dtp3_ren    => dtp3_ren,
            dtp3_dir    => dtp3_dir,
            dtp3_out    => dtp3_out,

            use_bias_dac => use_bias_dac,
            en_bias_buf  => en_bias_buf,
            en_bias_gen  => en_bias_gen,
            BIAS_ADJ    => BIAS_ADJ, 
            BIAS_DBP    => BIAS_DBP,
            BIAS_DBN    => BIAS_DBN,
            BIAS_DBPC   => BIAS_DBPC,
            BIAS_DBNC   => BIAS_DBNC,
            BIAS_TC_POT => BIAS_TC_POT,
            BIAS_LC_POT => BIAS_LC_POT,
            BIAS_TIA_G_POT => BIAS_TIA_G_POT,
            BIAS_REV_POT => BIAS_REV_POT,
            BIAS_TC_DSADC => BIAS_TC_DSADC,
            BIAS_LC_DSADC => BIAS_LC_DSADC,
            BIAS_RIN_DSADC => BIAS_RIN_DSADC,
            BIAS_RFB_DSADC => BIAS_RFB_DSADC,
            BIAS_DSADC_VCM => BIAS_DSADC_VCM,

            adc_conv_done => cmp_out,
            adc_en        => adc_en,
            adc_clk       => adc_clk,
            adc_switch    => adc_switch,
            adc_ext_in    => adc_ext_in,
            atp_en        => atp_en,
            atp_sel       => atp_sel,
            adc_sel       => adc_sel,
	    dac_en	  => dac_en
        );

    -------------------------------------------------------------------
    -- Stimulus: reset, register writes with read-back checks, then one ADC conversion.
    -------------------------------------------------------------------
    stim_proc: process
    begin
	dtp0_ren_in <= '0';
	dtp1_ren_in <= '0';
	dtp2_ren_in <= '0';
	dtp3_ren_in <= '0';
        -- Apply reset.
        resetn <= '0';
        wait for 100 ns;
        resetn <= '1';

	-- Program the test-pin routing register TPR.
	-- Map: dtp0=data_rdy_if (1), dtp1=ovf_if (2), dtp2=adc_done (3), dtp3=adc_active (0).
	wait until falling_edge(clk);
	en_mem <= '0';
	addr_periph <= std_logic_vector(to_unsigned(RegSlotAFE_TPR, 6));
	wen <= "1000"; 
	write_data(19 downto 0) <= '0' & x"5" & '0' & x"6" & '0' & x"7" & '0' & x"8";
	wait until rising_edge(clk_mem);

	wen <= (others=>'1');
	wait until falling_edge(clk);
	en_mem <= '1';

	----------------------------------------------------------------
        -- Test the single-bit bias enables via BIAS_CR.
        ----------------------------------------------------------------
	wait until falling_edge(clk);
        en_mem <= '0';
        wen <= "1110";  -- Write the low byte only, wen is active low per lane.
        addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_CR, 6));
        write_data(4 downto 2) <= "101";  -- use_bias_dac=1, en_bias_buf=0, en_bias_gen=1.
        wait until rising_edge(clk_mem);

        wen <= (others => '1');
	wait until falling_edge(clk);
	en_mem <= '1';

	wait for 40 ns;
        assert use_bias_dac   = '1' report "use_bias_dac mismatch" severity error;
        assert en_bias_buf    = '0' report "en_bias_buf mismatch" severity error;
        assert en_bias_gen    = '1' report "en_bias_gen mismatch" severity error;

        wait for 100 ns;

        ----------------------------------------------------------------
        -- Test the 6-bit and 8-bit BIAS registers: write, then check the exported value.
        ----------------------------------------------------------------
        -- BIAS_TC_POT
	wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1110";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_TC_POT, 6));
        write_data(5 downto 0) <= "101010";
        wait until rising_edge(clk_mem);

        wen <= (others => '1');
	wait until falling_edge(clk);
	en_mem <= '1';

	wait for 40 ns;
        assert BIAS_TC_POT = "101010" report "BIAS_TC_POT mismatch" severity error;

        wait for 100 ns;

        -- BIAS_LC_POT
	wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1110";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_LC_POT, 6));
        write_data(5 downto 0) <= "111000";
        wait until rising_edge(clk_mem);

        wen <= (others => '1');
	wait until falling_edge(clk);
	en_mem <= '1'; 

	wait for 40 ns;
        assert BIAS_LC_POT = "111000" report "BIAS_LC_POT mismatch" severity error;

        wait for 100 ns;

        -- BIAS_TC_DSADC
	wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1110";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_TC_DSADC, 6));
        write_data(5 downto 0) <= "100111";
        wait until rising_edge(clk_mem);

        wen <= (others => '1');
	wait until falling_edge(clk);
	en_mem <= '1'; 

	wait for 40 ns;
        assert BIAS_TC_DSADC = "100111" report "BIAS_TC_DSADC mismatch" severity error;

        wait for 100 ns;

        -- BIAS_LC_DSADC
	wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1110";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_LC_DSADC, 6));
        write_data(5 downto 0) <= "010101";
        wait until rising_edge(clk_mem);

        wen <= (others => '1');
	wait until falling_edge(clk);
	en_mem <= '1'; 

	wait for 40 ns;
        assert BIAS_LC_DSADC = "010101" report "BIAS_LC_DSADC mismatch" severity error;

        wait for 100 ns;

        -- BIAS_RIN_DSADC
	wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1110";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_RIN_DSADC, 6));
        write_data(5 downto 0) <= "111100";
        wait until rising_edge(clk_mem);

        wen <= (others => '1');
	wait until falling_edge(clk);
	en_mem <= '1'; 

	wait for 40 ns;
        assert BIAS_RIN_DSADC = "111100" report "BIAS_RIN_DSADC mismatch" severity error;

        wait for 100 ns;

        -- BIAS_RFB_DSADC
	wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1110";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_RFB_DSADC, 6));
        write_data(5 downto 0) <= "000111";
        wait until rising_edge(clk_mem);

        wen <= (others => '1');
	wait until falling_edge(clk);
	en_mem <= '1'; 

	wait for 40 ns;
        assert BIAS_RFB_DSADC = "000111" report "BIAS_RFB_DSADC mismatch" severity error;

        wait for 100 ns;

        -- BIAS_ADJ (6-bit)
	wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1110";
        addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_ADJ, 6));
        write_data(5 downto 0) <= "110011";
        wait until rising_edge(clk_mem);

        wen <= (others => '1');
	wait until falling_edge(clk);
	en_mem <= '1'; 
	
	wait for 40 ns;
        assert BIAS_ADJ = "110011" report "BIAS_ADJ mismatch" severity error;

        wait for 100 ns;

        -- ----------------------------------------------------------------
        -- -- Test 14-bit / 16-bit BIAS registers
        -- ----------------------------------------------------------------
        -- -- BIAS_TIA_G_POT------------------------
	-- wait until falling_edge(clk);
        -- en_mem <= '0'; wen <= "1100";
	-- addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_TIA_G_POT, 6));
        -- write_data(15 downto 0) <= x"1234";
        -- wait until rising_edge(clk_mem); 
	
	-- wen <= (others => '1'); 
	-- wait until falling_edge(clk);
	-- en_mem <= '1';

	-- wait for 40 ns;
        -- assert BIAS_TIA_G_POT = x"1234" report "BIAS_TIA_G_POT mismatch" severity error;

        -- wait for 100 ns;

        -- BIAS_REV_POT: 14-bit register, written as two byte lanes.
	wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1100";
	addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_REV_POT, 6));
        write_data(13 downto 0) <= ("101010" & x"34");
        wait until rising_edge(clk_mem); 

	wen <= (others => '1'); 
	wait until falling_edge(clk);
	en_mem <= '1';

	wait for 40 ns;
        assert BIAS_REV_POT = ("101010" & x"34") report "BIAS_REV_POT mismatch" severity error;

        wait for 100 ns;

	-- BIAS_DSADC_VCM
	wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1100";
	addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_DSADC_VCM, 6));
        write_data(13 downto 0) <= ("101010" & x"34");
        wait until rising_edge(clk_mem); 

	wen <= (others => '1'); 
	wait until falling_edge(clk);
	en_mem <= '1';

	wait for 40 ns;
        assert BIAS_DSADC_VCM = ("101010" & x"34") report "BIAS_DSADC_VCM mismatch" severity error;

        wait for 100 ns;

	-- BIAS_DBP
	wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1100";
	addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_DBP, 6));
        write_data(13 downto 0) <= ("101010" & x"34");
        wait until rising_edge(clk_mem); 

	wen <= (others => '1'); 
	wait until falling_edge(clk);
	en_mem <= '1';

	wait for 40 ns;
        assert BIAS_DBP = ("101010" & x"34") report "BIAS_DBP mismatch" severity error;

        wait for 100 ns;
	
	-- BIAS_DBPC
	wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1100"; 
	addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_DBPC, 6));
        write_data(13 downto 0) <= ("101010" & x"34");
        wait until rising_edge(clk_mem); 

	wen <= (others => '1'); 
	wait until falling_edge(clk);
	en_mem <= '1';

        wait for 40 ns;
        assert BIAS_DBPC = ("101010" & x"34") report "BIAS_DBPC mismatch" severity error;

        wait for 100 ns;

	-- BIAS_DBN
        wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1100"; 
	addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_DBN, 6));
        write_data(13 downto 0) <= ("101010" & x"34");
        wait until rising_edge(clk_mem); 

	wen <= (others => '1'); 
	wait until falling_edge(clk);
	en_mem <= '1';

        wait for 40 ns;
        assert BIAS_DBN = ("101010" & x"34") report "BIAS_DBN mismatch" severity error;

        wait for 100 ns;

	-- BIAS_DBNC
        wait until falling_edge(clk);
        en_mem <= '0'; wen <= "1100"; 
	addr_periph <= std_logic_vector(to_unsigned(RegSlotBIAS_DBNC, 6));
        write_data(13 downto 0) <= ("101010" & x"34");
        wait until rising_edge(clk_mem); 

	wen <= (others => '1'); 
	wait until falling_edge(clk);
	en_mem <= '1';

        wait for 40 ns;
        assert BIAS_DBNC = ("101010" & x"34") report "BIAS_DBNC mismatch" severity error;

        wait for 100 ns;

        -- Kick off an ADC conversion.
	-- AFE_CR sets adc_en = afe_en = adc_data_rdy_ie = adc_ext_in = atp_en = atp_sel = '1'.
	-- It also sets adc_ramp_num = 0xFFF (4095).
	wait until falling_edge(clk);
	en_mem <= '0'; wen <= "1000";
	addr_periph <= std_logic_vector(to_unsigned(RegSlotAFE_CR, 6));
	write_data(23 downto 0) <= x"3FF70F";
	wait until rising_edge(clk_mem);

	wen <= (others => '1');
	wait until falling_edge(clk);
	en_mem <= '1';

	-- Start the single-shot conversion: any write to AFE_ADC_VAL triggers it.
	wait until falling_edge(clk);
	en_mem <= '0'; wen <= "1110"; 
	addr_periph <= std_logic_vector(to_unsigned(RegSlotAFE_ADC_VAL, 6));
	write_data  <= (others => '0');
	wait until rising_edge(clk_mem);

	wen <= (others => '1');
	wait until falling_edge(clk);
	en_mem <= '1';


        -- Simulate the comparator flagging the end of deintegration.
        wait for 90 us;
        cmp_out <= '1';
        wait for 60 ns;
        cmp_out <= '0';

	-- Read the conversion result back.
	wait until falling_edge(clk);
	en_mem      <= '0';
	addr_periph <= std_logic_vector(to_unsigned(RegSlotAFE_ADC_VAL, 6));
	wait until rising_edge(clk_mem);

	wen <= (others => '1');
	wait until falling_edge(clk);
	en_mem <= '1';

	report "ADC result (dec) = " &
	  integer'image(to_integer(unsigned(read_data(11 downto 0)))) severity note;

	

	-- Let the interrupt stay asserted for a while before clearing it.
	wait for 3 us;

	-- Clear the data-ready flag in AFE_SR so the next conversion can run.
	wait until falling_edge(clk);
	en_mem <= '0'; wen <= "1110";
	addr_periph <= std_logic_vector(to_unsigned(RegSlotAFE_SR, 6));
	write_data <= (others=>'0'); write_data(1) <= '1';
	wait until rising_edge(clk_mem);

	wen <= (others=>'1');
	wait until falling_edge(clk);
	en_mem <= '1'; 


	
        wait for 10 us;
        assert false report "Simulation complete" severity failure;

    end process;

end architecture;

