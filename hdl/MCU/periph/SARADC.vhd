library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

entity SARADC is

    port (
        clk          : in  std_logic;  
        resetn       : in  std_logic;  
        irq          : out std_logic;  

        -- Memory Bus
        clk_mem      : in  std_logic;
        en_mem       : in  std_logic;                       
        wen          : in  std_logic_vector(3 downto 0); 
        addr_periph  : in  std_logic_vector(7 downto 2);
        write_data   : in  std_logic_vector(31 downto 0);
        read_data    : out std_logic_vector(31 downto 0);

        -- Digital Test Ports 
        dtp0   : out std_logic;
        dtp1   : out std_logic;

        -- ADC Connection 
        ADC_ready_i : in std_logic;
        ADC_data_i  : in std_logic_vector(9 downto 0); 
        ADC_reset   : out std_logic;
        ADC_trigger_clock_o : out std_logic
    );
end SARADC;

architecture rtl of SARADC is

    signal reset_i : std_logic;

    -- Register definitions
    signal SARADC_CR    	: std_logic_vector(8 downto 0);
    signal SARADC_SR    	: std_logic_vector(3 downto 0);
    signal SARADC_SR_ltch	: std_logic_vector(3 downto 0);
    signal SARADC_DATA  	: std_logic_vector(9 downto 0);
    signal SARADC_TPR 		: std_logic_vector(7 downto 0);

    -- Sync clock signals
    signal ADC_sync_clock : std_logic;

     ---------------------------------------------------------------------------------------------------------
    -- signal ADC_sync_clock_active : std_logic;
    -- signal ADC_sync_clock_active_synced0 : std_logic;
    -- signal ADC_sync_clock_active_synced1 : std_logic;
     ---------------------------------------------------------------------------------------------------------

    signal ADC_sync_clock_phase_shift_reg : std_logic_vector(15 downto 0);
    signal ADC_sync_clock_clear_phase : std_logic;
    signal ADC_sync_clock_sample_phase : std_logic;
    signal ADC_sync_clock_conversion_phase : std_logic;

     ---------------------------------------------------------------------------------------------------------
    --signal ADC_sync_clock_activation_allowed : std_logic;
     ---------------------------------------------------------------------------------------------------------

    signal ADC_sync_sample_step_counter : std_logic_vector(3 downto 0);

    -- Debug signals
    signal ADC_debug : std_logic_vector(15 downto 0);
    signal debug_mode                   : std_logic;
    signal dtp0_sel : std_logic_vector(3 downto 0);
    signal dtp1_sel : std_logic_vector(3 downto 0);

    -- Signal routing from control register TODO

    -- signal active_channel               : std_logic_vector(4 downto 0);
    ---------------------------------------------------------------------------------------------------------
    --signal external_trigger_clock_mode  : std_logic; --TODO: What is this ? Check.
    ---------------------------------------------------------------------------------------------------------
    signal adc_sync_init_sample_step    : std_logic_vector(3 downto 0); --changed from pulse width 
    signal adc_en                       : std_logic;
    signal adc_data_valid_ie            : std_logic;
    signal adc_cont_meas		: std_logic;

    -- Signal routing for status register
    signal conversion_busy : std_logic;
    signal conv_busy : std_logic;
    signal adc_ovf_if: std_logic;

    -- Signal routing for output register
    signal adc_data_out : std_logic_vector(9 downto 0);
    signal adc_data_valid : std_logic;

    -- ADC control signals
    signal ADC_ready_ltched : std_logic;
    signal ADC_ready : std_logic;
    signal ADC_data : std_logic_vector(9 downto 0);

    -- Memory interface signals
    signal en_addr_periph : integer;
    signal adc_ready_prev : std_logic;

    -- Clear Signals
   signal clr_data_valid, clr_adc_ovf_if : std_logic;


begin

    -- Convert active low reset to active high to jive with Zhilis setup
    reset_i <= not resetn;

    -- Register Signal Routing 
    -- SARADC_CR
    adc_reset                       <= '1' when reset_i = '1' 
                                        else SARADC_CR(0);  --TODO: This could be done more elegently, but manual reset for now.
                                        
    adc_sync_init_sample_step       <= SARADC_CR(4 downto 1); 
    ---------------------------------------------------------------------------------------------------------   
    --external_trigger_clock_mode     <= SARADC_CR(13);    
    ---------------------------------------------------------------------------------------------------------          
    adc_en                          <= SARADC_CR(5);                                 
    debug_mode                      <= SARADC_CR(6);  
    adc_data_valid_ie               <= SARADC_CR(7);   
    adc_cont_meas		            <= SARADC_CR(8);
                                     

    -- SARADC_SR
    SARADC_SR <= (
	0 => conv_busy,
	1 => adc_data_valid,
	2 => adc_ovf_if,
	3 => ADC_ready
    );

    reg_sync: process(en_mem, SARADC_SR_ltch, SARADC_SR,reset_i)
    begin
	if reset_i = '1' then
	    SARADC_SR_ltch <= (others => '0');
	elsif falling_edge(en_mem) then
	    SARADC_SR_ltch <= not SARADC_SR;
	end if;
    end process;
                 
    -- SARADC_DATA
    SARADC_DATA(9 downto 0) <= adc_data_out;                                                         

    -- ADC_ready <= ADC_ready_i;
    ADC_data <= ADC_data_i;
    
    -- Generate IRQ when ADC data is ready and valid
    irq <= '1' when (adc_data_valid = '1' and adc_data_valid_ie = '1') else '0';

    -- ADC data capture logic & Interrupt flags
    ADC_Data_Capture : process (clk, reset_i, clr_data_valid, clr_adc_ovf_if, ADC_ready)
    begin
        if reset_i = '1' then
            adc_ready_prev <= '0';
            adc_data_out <= (others => '0');
            adc_data_valid <= '0';
            adc_ovf_if <= '0';
            ADC_ready_ltched <= '0';
            ADC_ready <= '0';
        elsif rising_edge(clk) then
            adc_ready_prev <= ADC_ready;
            ADC_ready_ltched <= ADC_ready;
            ADC_ready <= ADC_ready_i;

            -- Capture data on rising edge of ADC_ready
            if ADC_ready = '1' and adc_ready_prev = '0' then
                -- If data_valid is already set, overflow
                if adc_data_valid = '1' then
                    adc_ovf_if <= '1';
                end if;
                
                -- Always capture latest ADC data
                adc_data_out <= ADC_data;
                adc_data_valid <= '1';
            end if;

            
        end if;
	if clr_data_valid = '1' then
            adc_data_valid <= '0';
        end if;

        if clr_adc_ovf_if = '1' then
            adc_ovf_if <= '0';
        end if;
    end process;

    -- Debug test ports
    dtp0_sel <= SARADC_TPR(3 downto 0);
    dtp1_sel <= SARADC_TPR(7 downto 4);

    dtp0 <= ADC_debug(slv2uint(dtp0_sel)) when debug_mode = '1' else '0';
    dtp1 <= ADC_debug(slv2uint(dtp1_sel)) when debug_mode = '1' else '0';

    ADC_debug <= (
	15 => '0',
	14 => '0',
	13 => '0',
	12 => clr_data_valid,
	11 => clr_adc_ovf_if,
	10 => adc_data_valid,
        9 => adc_ovf_if,
        8 => conv_busy,
        7 => ADC_ready,
        6 => adc_cont_meas,
        5 => adc_data_valid_ie,
        4 => adc_en,
        3 => adc_sync_init_sample_step(3),
        2 => adc_sync_init_sample_step(2),
        1 => adc_sync_init_sample_step(1),
        0 => adc_sync_init_sample_step(0)
    );

    
    -- Shift register and count down.
    Sync_Clock_Step : process (reset_i, adc_en, clk)
    begin
        if (reset_i = '1') or (adc_en = '0') then
            ADC_sync_sample_step_counter <= adc_sync_init_sample_step;
            ADC_sync_clock_phase_shift_reg <= "1000000000000000";
            ADC_sync_clock_conversion_phase <= '0';
            conv_busy <= '0';
        elsif falling_edge(clk) then
            if (ADC_sync_clock_sample_phase = '1') and (ADC_sync_sample_step_counter /= "0000") then
                -- sample countdown during sample phase
                ADC_sync_sample_step_counter <= std_logic_vector(unsigned(ADC_sync_sample_step_counter) - 1);
            elsif (ADC_sync_clock_phase_shift_reg(0) /= '1') then 
                -- shift right until the 1 reaches end and then wait to be reset
                ADC_sync_clock_phase_shift_reg(14 downto 0) <= ADC_sync_clock_phase_shift_reg(15 downto 1);
                ADC_sync_clock_phase_shift_reg(15) <= '0';
		conv_busy <= '1';
	    elsif (ADC_sync_clock_phase_shift_reg(0) = '1') then
		-- End of conversion
		conv_busy <= '0';
		if adc_cont_meas = '1' then
		    --reload for cont operation
		    ADC_sync_clock_phase_shift_reg <= "1000000000000000";
		    ADC_sync_sample_step_counter <= adc_sync_init_sample_step;
		end if;
            end if;

            -- Generate conversion flag
            if (ADC_sync_clock_phase_shift_reg(11) = '1') then
                ADC_sync_clock_conversion_phase <= '1';
            elsif (ADC_sync_clock_phase_shift_reg(1) = '1') then
                ADC_sync_clock_conversion_phase <= '0';
            end if;
        end if;
    end process;

    -- Phase Flags
    ADC_sync_clock_clear_phase <= ADC_sync_clock_phase_shift_reg(14);
    ADC_sync_clock_sample_phase <= ADC_sync_clock_phase_shift_reg(12);

    -- Clock waveform generation
    ADC_sync_clock <= ADC_sync_clock_clear_phase or ADC_sync_clock_sample_phase or (ADC_sync_clock_conversion_phase and clk);
    ADC_trigger_clock_o <= ADC_sync_clock;

    -- =============================================================================
    -- Memory-Mapped Register Interface
    -- =============================================================================
    en_addr_periph <= slv2uint(addr_periph) when en_mem = '0' else 0;

    -- Register Write Process 
    write_proc: process(resetn, clk_mem, reset_i, en_mem)
    begin

        if reset_i = '1' then
            --Register Resets
            SARADC_CR <= (others => '0');  -- Default: all off
	        SARADC_TPR <= (others => '0');

        elsif rising_edge(clk_mem) then
            if en_mem = '0' then
                case en_addr_periph is
                    when RegSlotSARADC_CR =>
                        if wen(0) = '0' then
                            SARADC_CR(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            SARADC_CR(SARADC_CR'high downto 8) <= write_data(SARADC_CR'high downto 8);
                        end if;
		    when RegSlotSARADC_SR =>
			if wen(0) = '0' then
			    if write_data(1) = '1' then
				clr_data_valid <= '1';
			    end if;
			    if write_data(2) = '1' then
				clr_adc_ovf_if <= '1';
			    end if;
			end if;
		    when RegSlotSARADC_TPR => 
			if wen(0) = '0' then
			    SARADC_TPR(7 downto 0) <= write_data(7 downto 0);
			end if;
			if wen(1) =  '0' then	
			    SARADC_TPR(SARADC_TPR'high downto 8) <= write_data(SARADC_TPR'high downto 8);
			end if;
                    when others =>
                        null;
                end case;
            end if;
        end if;

        if resetn = '0' or en_mem = '1' then
            clr_data_valid <= '0';
            clr_adc_ovf_if <= '0';
        end if;
    end process;

        -- Register Read Process 
    read_proc: process(clk_mem)
    begin
        if rising_edge(clk_mem) then

            case en_addr_periph is
                when RegSlotSARADC_CR =>
                    read_data <= (31 downto SARADC_CR'high + 1 => '0') & SARADC_CR;
                when RegSlotSARADC_SR =>
                    read_data <= (31 downto SARADC_SR'high + 1 => '0') & (not SARADC_SR_ltch);
                when RegSlotSARADC_DATA =>
                    read_data <= (31 downto SARADC_DATA'high + 1 => '0') & SARADC_DATA;
		when RegSlotSARADC_TPR =>
		    read_data <= (31 downto SARADC_TPR'high + 1 => '0') & SARADC_TPR;
                when others =>
                    read_data <= (others => '0');
            end case;
        end if;
    end process;

end architecture;
