/* -----------------------------------------------------------------------------
   SARADC.vhd: memory-mapped controller for the off-die 10-bit SAR ADC: it generates the trigger clock, latches ADC_data_i on the rising edge of ADC_ready_i (a capture into a still-full result sets overflow), and raises irq while data is valid and its enable bit is set.
   The trigger clock is a 16-bit one-hot shift register clocked on the falling edge of clk: bit 14 is the clear phase, bit 12 the sample phase stretched by the SARADC_CR sample-step countdown, and bits 11 down to 1 the conversion phase; the combined waveform is registered once more before leaving the block to keep the shift-register bit off a long output path.
   Registers: SARADC_CR control, SARADC_SR status (stored inverted in SARADC_SR_ltch, re-inverted on read, data-valid and overflow are write-1-to-clear), SARADC_DATA result, SARADC_TPR debug test-port select.
   ----------------------------------------------------------------------------- */

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

        -- Peripheral register bus, clocked by the gated clk_mem.
        clk_mem      : in  std_logic;
        en_mem       : in  std_logic;                       
        wen          : in  std_logic_vector(3 downto 0); 
        addr_periph  : in  std_logic_vector(7 downto 2);
        write_data   : in  std_logic_vector(31 downto 0);
        read_data    : out std_logic_vector(31 downto 0);

        -- Digital test ports, each muxed out of ADC_debug by SARADC_TPR while debug_mode is set. 
        dtp0   : out std_logic;
        dtp1   : out std_logic;

        -- Connection to the off-die ADC macro. 
        ADC_ready_i : in std_logic;
        ADC_data_i  : in std_logic_vector(9 downto 0); 
        ADC_reset   : out std_logic;
        ADC_trigger_clock_o : out std_logic
    );
end SARADC;

architecture rtl of SARADC is

    signal reset_i : std_logic;

    -- Register storage; SARADC_SR_ltch holds the status word inverted.
    signal SARADC_CR    	: std_logic_vector(8 downto 0);
    signal SARADC_SR    	: std_logic_vector(3 downto 0);
    signal SARADC_SR_ltch	: std_logic_vector(3 downto 0);
    signal SARADC_DATA  	: std_logic_vector(9 downto 0);
    signal SARADC_TPR 		: std_logic_vector(7 downto 0);

    -- Sync clock signals: the phase shift register and the phase flags decoded from it.
    signal ADC_sync_clock : std_logic;

    signal ADC_sync_clock_phase_shift_reg : std_logic_vector(15 downto 0);
    signal ADC_sync_clock_clear_phase : std_logic;
    signal ADC_sync_clock_sample_phase : std_logic;
    signal ADC_sync_clock_conversion_phase : std_logic;

    signal ADC_sync_sample_step_counter : std_logic_vector(3 downto 0);

    -- Debug observation bus and its test-port selects.
    signal ADC_debug : std_logic_vector(15 downto 0);
    signal debug_mode                   : std_logic;
    signal dtp0_sel : std_logic_vector(3 downto 0);
    signal dtp1_sel : std_logic_vector(3 downto 0);

    -- Signal routing from the control register. TODO
    signal adc_sync_init_sample_step    : std_logic_vector(3 downto 0); -- Reload value for the sample-phase countdown.
    signal adc_en                       : std_logic;
    signal adc_data_valid_ie            : std_logic;
    signal adc_cont_meas		: std_logic;

    -- Signal routing for the status register.
    signal conversion_busy : std_logic;
    signal conv_busy : std_logic;
    signal adc_ovf_if: std_logic;

    -- Signal routing for the result register.
    signal adc_data_out : std_logic_vector(9 downto 0);
    signal adc_data_valid : std_logic;

    -- Synchronized copies of the ADC macro's handshake and data.
    signal ADC_ready_ltched : std_logic;
    signal ADC_ready : std_logic;
    signal ADC_data : std_logic_vector(9 downto 0);

    -- Decoded register slot, plus the delayed ADC_ready used for edge detection.
    signal en_addr_periph : integer;
    signal adc_ready_prev : std_logic;

    -- Write-1-to-clear strobes raised by a SARADC_SR write.
   signal clr_data_valid, clr_adc_ovf_if : std_logic;

    -- Registered trigger clock, keeping the hold-critical path off ADC_sync_clock_phase_shift_reg(14).
    signal adc_sync_clock_reg : std_logic;

begin

    -- The ADC macro takes an active-high reset.
    reset_i <= not resetn;

    -- SARADC_CR fields, unpacked onto their named signals.
    adc_reset                       <= '1' when reset_i = '1' 
                                        else SARADC_CR(0);  -- TODO: this could be done more elegantly, but it is a manual reset for now.
                                        
    adc_sync_init_sample_step       <= SARADC_CR(4 downto 1); 
    adc_en                          <= SARADC_CR(5);                                 
    debug_mode                      <= SARADC_CR(6);  
    adc_data_valid_ie               <= SARADC_CR(7);   
    adc_cont_meas		            <= SARADC_CR(8);
                                     

    -- SARADC_SR is assembled from the live flags, then latched inverted for readback.
    SARADC_SR <= (
	0 => conv_busy,
	1 => adc_data_valid,
	2 => adc_ovf_if,
	3 => ADC_ready
    );

    -- Snapshot the status flags, inverted, on the falling edge of the peripheral select so a read returns the state at access time.
    reg_sync: process(en_mem, SARADC_SR_ltch, SARADC_SR,reset_i)
    begin
	if reset_i = '1' then
	    SARADC_SR_ltch <= (others => '0');
	elsif falling_edge(en_mem) then
	    SARADC_SR_ltch <= not SARADC_SR;
	end if;
    end process;
                 
    -- SARADC_DATA always mirrors the last captured conversion result.
    SARADC_DATA(9 downto 0) <= adc_data_out;                                                         

    ADC_data <= ADC_data_i;
    
    -- Raise the IRQ level while a captured result is valid and its interrupt enable is set.
    irq <= '1' when (adc_data_valid = '1' and adc_data_valid_ie = '1') else '0';

    -- ADC data capture and its flags: ADC_ready_i is resynchronized here, and the register-bus clear strobes win over a same-cycle set.
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

            -- Capture data on the rising edge of ADC_ready.
            if ADC_ready = '1' and adc_ready_prev = '0' then
                -- A capture over a result software has not read yet is an overflow.
                if adc_data_valid = '1' then
                    adc_ovf_if <= '1';
                end if;
                
                -- Always take the newest sample, overflow or not.
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

    -- Debug test ports: SARADC_TPR picks one ADC_debug bit per pin, and both pins read '0' unless debug_mode is set.
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

    
    -- Conversion sequencer: the one-hot phase shift register plus the sample-step countdown that stretches the sample phase.
    -- Held in its reload state while adc_en is low, and self-reloading each pass when continuous measurement is enabled.
    Sync_Clock_Step : process (reset_i, adc_en, clk)
    begin
        if (reset_i = '1') or (adc_en = '0') then
            ADC_sync_sample_step_counter <= adc_sync_init_sample_step;
            ADC_sync_clock_phase_shift_reg <= "1000000000000000";
            ADC_sync_clock_conversion_phase <= '0';
            conv_busy <= '0';
        elsif falling_edge(clk) then
            if (ADC_sync_clock_sample_phase = '1') and (ADC_sync_sample_step_counter /= "0000") then
                -- Hold the sample phase and count down the remaining sample steps.
                ADC_sync_sample_step_counter <= std_logic_vector(unsigned(ADC_sync_sample_step_counter) - 1);
            elsif (ADC_sync_clock_phase_shift_reg(0) /= '1') then 
                -- Shift right until the one reaches bit 0, then wait to be reloaded.
                ADC_sync_clock_phase_shift_reg(14 downto 0) <= ADC_sync_clock_phase_shift_reg(15 downto 1);
                ADC_sync_clock_phase_shift_reg(15) <= '0';
            conv_busy <= '1';
            elsif (ADC_sync_clock_phase_shift_reg(0) = '1') then
            -- End of conversion.
            conv_busy <= '0';
                if adc_cont_meas = '1' then
                    -- Reload for continuous operation.
                    ADC_sync_clock_phase_shift_reg <= "1000000000000000";
                    ADC_sync_sample_step_counter <= adc_sync_init_sample_step;
                end if;
            end if;
            -- Conversion phase spans shift-register bit 11 down to bit 1.
            if (ADC_sync_clock_phase_shift_reg(11) = '1') then
                ADC_sync_clock_conversion_phase <= '1';
            elsif (ADC_sync_clock_phase_shift_reg(1) = '1') then
                ADC_sync_clock_conversion_phase <= '0';
            end if;
        end if;
    end process;



    -- Phase flags decoded straight off the shift register.
    ADC_sync_clock_clear_phase <= ADC_sync_clock_phase_shift_reg(14);
    ADC_sync_clock_sample_phase <= ADC_sync_clock_phase_shift_reg(12);

    -- Clock waveform generation.
    ADC_trigger_clock_o <= ADC_sync_clock;

    -- Register the waveform here: ADC_sync_clock_clear_phase comes combinationally off shift-register bit 14, so driving ADC_trigger_clock_o directly is a long path from a register bit to an output and violates hold.
    Clock_Output_Register: process(clk, reset_i)
    begin
        if reset_i = '1' then
            ADC_sync_clock_reg <= '0';
        elsif rising_edge(clk) then
            ADC_sync_clock_reg <= ADC_sync_clock_clear_phase or ADC_sync_clock_sample_phase or (ADC_sync_clock_conversion_phase and clk);
        end if;
    end process;
    ADC_sync_clock <= ADC_sync_clock_reg;

    -- Memory-mapped register interface.
    en_addr_periph <= slv2uint(addr_periph) when en_mem = '0' else 0;

    -- Register writes, byte-lane qualified by the active-low wen.
    -- A SARADC_SR write stores nothing: it only raises the clr_* strobes, dropped again as soon as the select deasserts.
    write_proc: process(resetn, clk_mem, reset_i, en_mem)
    begin

        if reset_i = '1' then
            -- Register resets.
            SARADC_CR <= (others => '0');  -- Default: everything off.
	        SARADC_TPR <= (others => '0');

        elsif rising_edge(clk_mem) then
            if en_mem = '0' then
                case en_addr_periph is
                    -- Control register: lane 0 carries bits 7:0, lane 1 the remaining top bit.
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
                    -- Every other slot in this peripheral's window is read-only or unimplemented.
                    when others =>
                        null;
                end case;
            end if;
        end if;

        -- The clear strobes are one-access pulses: drop them on reset or as soon as the peripheral is deselected.
        if resetn = '0' or en_mem = '1' then
            clr_data_valid <= '0';
            clr_adc_ovf_if <= '0';
        end if;
    end process;

        -- Registered reads: one clk_mem cycle of latency, zero-extended to 32 bits.
        -- SARADC_SR comes from the inverted latch and is inverted back on the way out.
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
                -- Unmapped slots read as zero.
                when others =>
                    read_data <= (others => '0');
            end case;
        end if;
    end process;

end architecture;
