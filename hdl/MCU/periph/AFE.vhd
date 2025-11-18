library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

entity AFE is
    port
    (
        -- System Signals
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
        dtp0_ren_in : in std_logic;
        dtp0_ren    : out std_logic;
        dtp0_dir    : out std_logic;
        dtp0_out    : out std_logic;

        dtp1_ren_in : in std_logic;
        dtp1_ren    : out std_logic;
        dtp1_dir    : out std_logic;
        dtp1_out    : out std_logic;

        dtp2_ren_in : in std_logic;
        dtp2_ren    : out std_logic;
        dtp2_dir    : out std_logic;
        dtp2_out    : out std_logic;

        dtp3_ren_in : in std_logic;
        dtp3_ren    : out std_logic;
        dtp3_dir    : out std_logic;
        dtp3_out    : out std_logic;

        -- Bias Signals
	    use_bias_dac	: out	std_logic;	-- Switches between using the bias generator voltages or bias DACs for the global bias voltages. '0' <= Uses bias generator; '1' <= Uses DACs
        en_bias_buf		: out	std_logic;	-- Enables/disables buffers on the internal global bias voltages. '0' <= Disabled; '1' <= Enabled
	    en_bias_gen		: out	std_logic;	-- Enables/disables the internal bias generator. '0' <= Disabled; '1' <= Enabled

        -- Central Bias Generator
        BIAS_ADJ		: out	std_logic_vector(5 downto 0);	-- Internal bias generator adjustment vector. Higher vector codes produce smaller currents. The nominal vector is decimal 37.
	    BIAS_DBP		: out	std_logic_vector(13 downto 0);
        BIAS_DBN		: out	std_logic_vector(13 downto 0);
	    BIAS_DBPC		: out	std_logic_vector(13 downto 0);
	    BIAS_DBNC		: out	std_logic_vector(13 downto 0);

        -- Potentiostat Biases
        BIAS_TC_POT      : out std_logic_vector(5 downto 0);    -- Bias Current BTS - Potentiostat
        BIAS_LC_POT      : out std_logic_vector(5 downto 0);    -- LC Resistor      - Potentiostat
        BIAS_TIA_G_POT   : out  std_logic_vector(16 downto 0);  -- TIA Gain Resistor - Potentiostat
        BIAS_REV_POT     : out std_logic_vector(13 downto 0);   -- Potentiostat Reference Electrode Voltage (DAC)

        -- DSADC Biases
        BIAS_TC_DSADC   : out std_logic_vector(5 downto 0);    -- Bias Current BTS - DSADC
        BIAS_LC_DSADC   : out std_logic_vector(5 downto 0);    -- LC Resistor      - DSADC
        BIAS_RIN_DSADC  : out std_logic_vector(5 downto 0);    -- Input Resistor   - DSADC
        BIAS_RFB_DSADC  : out std_logic_vector(5 downto 0);    -- Feedback Resistor- DSADC
        BIAS_DSADC_VCM  : out std_logic_vector(13 downto 0);   -- DSADC VCM Voltage (DAC)

        -- DSADC Outputs Signals 
        adc_conv_done   : in std_logic;
        adc_en          : out std_logic;
        adc_clk         : out std_logic;
        adc_switch      : out std_logic_vector(2 downto 0);
        adc_ext_in      : out std_logic; -- '1' => adc's input is from potentiostat pad, '0' => external signal
        atp_en          : out std_logic; -- '1' => ATP enabled, '0' => ATP disabled
        atp_sel         : out std_logic; -- '1' => atp input is from DSADC, '0' => atp input is from Potentiostat
        adc_sel         : out std_logic;  -- '1' => adc to use is SARADC, '0' => adc input is from DSADC
        dac_en          : out std_logic   -- '1' => Dac enable for both DSADC VCM and Potentiostat RE Voltage

    );
end AFE;

architecture Behavioral of AFE is

    -- Register Declarations 
    signal AFE_CR          : std_logic_vector(23 downto 0); -- Control Register TODO: Change size
    signal AFE_TPR         : std_logic_vector(19 downto 0); -- Test Port Register (Analog? and Digital)
    signal AFE_SR          : std_logic_vector(3 downto 0); -- Status Register
    signal AFE_SR_ltch     : std_logic_vector(3 downto 0);
    signal AFE_ADC_VAL     : std_logic_vector(11 downto 0); -- ADC Value Register. Writing to this will start a conversion
    signal BIAS_CR         : std_logic_vector(4 downto 0); -- Bias Control Register
    signal DSADC_CNT      : std_logic_vector(11 downto 0); -- Count from DSADC (continually changing)


    -- AFE_CR Bit definitions 
    signal afe_en : std_logic; -- AFE Enable bit
    signal adc_ramp_num : std_logic_vector(11 downto 0); -- Number of periods for ADC ramp
    signal adc_data_rdy_ie : std_logic; -- Data Ready Interrupt Enable bit
    signal adc_cont_meas : std_logic; -- '1' -> ADC Running as fast as possible, '0' -> single measurement

    -- Clear Signals 
    signal clr_adc_data_rdy_if : std_logic;
    signal clr_adc_ovf_if : std_logic;

    -- ADC signals 
    signal adc_start : std_logic; 
    signal adc_val_written : std_logic;
    signal clk_afe : std_logic; 
    
    --AFE_SR Signals 
    signal adc_active : std_logic; -- ADC Active bit
    signal adc_done : std_logic; -- ADC Done bit - high for one cycle when conversion is done
    signal adc_data_rdy_if : std_logic; -- ADC Data Ready bit
    signal adc_ovf_if : std_logic; -- Indicates ADC_VAL has been overwritten.
    
    -- ADC_SR_CLR Signals
    signal clr_adc_data_rdy : std_logic;
    signal clr_adc_ovf : std_logic;
    signal adc_data_read : std_logic;

    -- NOTE: Digital Values from SR can be outputted digitally via dtp
    --AFE_TPR
    signal dtp0_sel : std_logic_vector(4 downto 0); -- Data Test Port 0 Select bits
    signal dtp1_sel : std_logic_vector(4 downto 0); -- Data Test Port 1 Select bits
    signal dtp2_sel : std_logic_vector(4 downto 0); -- Data Test Port 2 Select bits
    signal dtp3_sel : std_logic_vector(4 downto 0); -- Data Test Port 3 Select bits
    signal dtp_vect : std_logic_vector(31 downto 0); -- Data Test Port Vector

    -- Memory Interface Signals
    signal en_addr_periph : natural range 0 to 63; -- Enable Memory Peripheral

    -- Intermediate Reset Signal
    signal rst_int : std_logic;

    -- Output signals that also need to be read
    signal adc_en_int : std_logic; 
    signal adc_clk_int : std_logic;
    signal adc_switch_int : std_logic_vector(2 downto 0);
    signal BIAS_ADJ_int : std_logic_vector(5 downto 0);
    signal BIAS_DBP_int : std_logic_vector(13 downto 0);
    signal BIAS_DBPC_int : std_logic_vector(13 downto 0);
    signal BIAS_DBN_int : std_logic_vector(13 downto 0);
    signal BIAS_DBNC_int : std_logic_vector(13 downto 0);
    signal BIAS_TC_POT_int : std_logic_vector(5 downto 0);
    signal BIAS_LC_POT_int : std_logic_vector(5 downto 0);
    signal BIAS_TIA_G_POT_int : std_logic_vector(16 downto 0);
    signal BIAS_DSADC_VCM_int : std_logic_vector(13 downto 0);
    signal BIAS_REV_POT_int : std_logic_vector(13 downto 0);
    signal BIAS_TC_DSADC_int : std_logic_vector(5 downto 0);
    signal BIAS_LC_DSADC_int : std_logic_vector(5 downto 0);
    signal BIAS_RIN_DSADC_int : std_logic_vector(5 downto 0);
    signal BIAS_RFB_DSADC_int : std_logic_vector(5 downto 0);
    

begin
    
    adc_en <= adc_en_int;
    adc_clk <= adc_clk_int;
    adc_switch <= adc_switch_int;
    BIAS_ADJ <= BIAS_ADJ_int;
    BIAS_DBP <= BIAS_DBP_int;
    BIAS_DBPC <= BIAS_DBPC_int;
    BIAS_DBN <= BIAS_DBN_int;
    BIAS_DBNC <= BIAS_DBNC_int;
    BIAS_TC_POT <= BIAS_TC_POT_int; 
    BIAS_LC_POT <= BIAS_LC_POT_int;
    BIAS_TIA_G_POT <= BIAS_TIA_G_POT_int; 
    BIAS_DSADC_VCM <= BIAS_DSADC_VCM_int; 
    BIAS_REV_POT <= BIAS_REV_POT_int; 
    BIAS_TC_DSADC <= BIAS_TC_DSADC_int; 
    BIAS_LC_DSADC <= BIAS_LC_DSADC_int; 
    BIAS_RIN_DSADC <= BIAS_RIN_DSADC_int; 
    BIAS_RFB_DSADC <= BIAS_RFB_DSADC_int; 


    --AFE_CR Routing 
    adc_ramp_num        <= AFE_CR(23 downto 12);
    adc_sel		        <= AFE_CR(11);
    atp_sel             <= AFE_CR(10);
    atp_en              <= AFE_CR(9);
    adc_ext_in          <= AFE_CR(8);
    adc_cont_meas       <= AFE_CR(4);
    adc_data_rdy_ie     <= AFE_CR(2);
    dac_en		        <= AFE_CR(3);
    afe_en 		        <= AFE_CR(1);
    adc_en_int          <= AFE_CR(0);


    --AFE_SR Routing TODO: Update 
    AFE_SR <= (
        0        => adc_active,
        1        => adc_data_rdy_if,
        2        => adc_ovf_if,
        3        => '0'
    );


    -- BIAS_CR Routing 
    use_bias_dac    <= BIAS_CR(4);
    en_bias_buf     <= BIAS_CR(3);
    en_bias_gen     <= BIAS_CR(2);


    --AFE_DTP Routing 
    dtp0_sel       <= AFE_TPR(4 downto 0);
    dtp1_sel       <= AFE_TPR(9 downto 5);
    dtp2_sel       <= AFE_TPR(14 downto 10);
    dtp3_sel       <= AFE_TPR(19 downto 15);


    -- irq <= '1' when (adc_data_rdy_if  = '1' and adc_data_rdy_ie = '1') else '0';
    irq <= adc_data_rdy_if  and adc_data_rdy_ie;

    dtp0_ren <= dtp0_ren_in;
    dtp1_ren <= dtp1_ren_in;
    dtp2_ren <= dtp2_ren_in;
    dtp3_ren <= dtp3_ren_in;
    dtp0_dir <= '1'; -- output
    dtp1_dir <= '1'; -- output
    dtp2_dir <= '1'; -- output
    dtp3_dir <= '1'; -- output

    -- Intermediate Reset Signal
    rst_int <= not resetn;

    -- =============================================================================
    -- Analog Front End Interface Core 
    -- =============================================================================


    -- Register Synchronization Process
    reg_sync: process(en_mem, AFE_SR_ltch, AFE_SR, rst_int)
    begin
	if rst_int = '1' then
	    AFE_SR_ltch <= (others => '0');
        elsif falling_edge(en_mem) then 
            AFE_SR_ltch <= not AFE_SR; -- Latch Status Register
        end if;
    end process;
    
    cg_clk_afe: entity work.ClkGate
	port map
	(
		ClkIn	=> clk,
		En	    => afe_en,
		ClkOut	=> clk_afe
	);


    -- TODO: Seth's ADC Controller /FSM Here
    adc_fsm: entity work.AFE_FSM
    port map (
        clk => clk_afe,
        rst => rst_int,

        start => adc_start,
        enable => adc_en_int,
        cmp_out => adc_conv_done, 
        cycle_set => adc_ramp_num,
        clk_adc => adc_clk_int, 
        count => DSADC_CNT, --input
        sw => adc_switch_int(2 downto 0),

        done => adc_done, --high for one cycle 
        result_latch => AFE_ADC_VAL(11 downto 0),
	busy => adc_active

    );

    -- If continuous measure mode, then feed clk as adc_start, else only start when adc_val is written to
    adc_start <= '1' when adc_cont_meas = '1' else adc_val_written; 


    -- TODO: Digital Test Port Logic of signals we would like to see on output pins
    dtp_vect <= (
        31 => DSADC_CNT(11),
        30 => DSADC_CNT(10),
        29 => DSADC_CNT(9),
        28 => DSADC_CNT(8),
        27 => DSADC_CNT(7),
        26 => DSADC_CNT(6),
        25 => DSADC_CNT(5),
        24 => DSADC_CNT(4),
        23 => DSADC_CNT(3),
        22 => DSADC_CNT(2),
        21  => DSADC_CNT(1),
        20  => DSADC_CNT(0),
        19 => '0',
        18 => '0',
        17 => '0',
        16 => '0',
        15 => '0',
        14 => '0',
        13 => '0',
        12 => '0',
        11 => '0',
        10 => '0',
        9 =>  '0',
        8 => adc_start,
        7  => adc_switch_int(2),
        6  => adc_switch_int(1),
        5  => adc_switch_int(0),
        4  => adc_clk_int,
        3  => adc_done,
        2  => adc_ovf_if,
        1  => adc_data_rdy_if,
        0  => adc_active
    );

    -- Select which signals in dtp_vect to output
    dtp0_out <= dtp_vect(slv2uint(dtp0_sel));
    dtp1_out <= dtp_vect(slv2uint(dtp1_sel));
    dtp2_out <= dtp_vect(slv2uint(dtp2_sel));
    dtp3_out <= dtp_vect(slv2uint(dtp3_sel));

    -- Interrupt Flag Generation Logic
    adc_rdy_if_gen: process(resetn, adc_done, clr_adc_data_rdy_if, clr_adc_ovf_if, clk)
    begin
        if resetn = '0' then 
            adc_data_rdy_if <= '0';
            adc_ovf_if <= '0';
	elsif rising_edge(clk) then
            if adc_done = '1' then
                if adc_data_rdy_if = '1' then
                    -- Overwriting previous unread data
                    adc_ovf_if <= '1';
                end if;
                adc_data_rdy_if <= '1';
            end if; 
	end if;
	-- Clear Interrupt Flags
	if clr_adc_data_rdy_if = '1' then
            adc_data_rdy_if <= '0';
        end if;
        if clr_adc_ovf_if = '1' then
            adc_ovf_if <= '0';
        end if;
    end process;




    -- =============================================================================
    -- Memory-Mapped Register Interface
    -- =============================================================================
    
    -- Address decoding
    en_addr_periph <= slv2uint(addr_periph) when en_mem = '0' else 0;


    -- Register Write Process 
    reg_write_proc: process(resetn, clk_mem)
    begin

        clr_adc_data_rdy <= '0'; -- default value

        if resetn = '0' then
	        --Register Resets 
            -- AFE_CR              <= x"0FF71F";
            AFE_CR              <= x"000000";
            AFE_TPR             <= (others => '0');
            BIAS_CR             <= "01100";
            BIAS_TC_POT_int     <= "010000";
            BIAS_LC_POT_int     <= "101000";
            BIAS_TIA_G_POT_int  <= (others => '1');
            BIAS_DSADC_VCM_int  <= "10000000000000";
            BIAS_REV_POT_int    <= "00111101011100";
            BIAS_ADJ_int        <= "011000";
            BIAS_DBP_int        <= (others => '0');
            BIAS_DBPC_int       <= (others => '0');
            BIAS_DBNC_int       <= (others => '0');
            BIAS_DBN_int        <= (others => '0');
            BIAS_TC_DSADC_int   <= "110000";
            BIAS_LC_DSADC_int   <= "101000";
            BIAS_RFB_DSADC_int  <= "101111";
            BIAS_RIN_DSADC_int  <= "100011";
	        adc_val_written <= '0';

        elsif rising_edge(clk_mem) then
            
            adc_val_written <= '0';

            -- Handle register writes
            if en_mem = '0' then 
                case en_addr_periph is
                    when RegSlotAFE_CR =>
                        if wen(0) = '0' then
                            AFE_CR(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            AFE_CR(15 downto 8) <= write_data(15 downto 8);
                        end if;
                        if wen(2) = '0' then
                            AFE_CR(AFE_CR'high downto 16) <= write_data(AFE_CR'high downto 16);
                        end if;
                    when RegSlotAFE_TPR =>
                        if wen(0) = '0' then
                            AFE_TPR(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            AFE_TPR(15 downto 8) <= write_data(15 downto 8);
                        end if;
                        if wen(2) = '0' then
                            AFE_TPR(19 downto 16) <= write_data(19 downto 16);
                        end if;
                    when RegSlotAFE_SR =>
                            -- Writing to SR will clear interrupt flags
                            if wen(0) = '0' then
                                -- Bit 0 - ADC active, no clearing neccesary 
                                if write_data(1) = '1' then
                                    clr_adc_data_rdy_if <= '1';
                                end if;
                                if write_data(2) = '1' then
                                    clr_adc_ovf_if <= '1';
                                end if;
                            end if;
                    when RegSlotAFE_ADC_VAL =>
                            -- Writing to ADC_VAL will start a conversion
                            if wen(1 downto 0) /= "11" then
                                if adc_en_int = '1' then
                                    adc_val_written <= '1';
                                end if;
                            end if;
                    when RegSlotBIAS_CR =>
                        if wen(0) = '0' then
                            BIAS_CR(BIAS_CR'high downto 0) <= write_data(BIAS_CR'high downto 0);
                        end if;

                    when RegSlotBIAS_ADJ =>
                        if wen(0) = '0' then 
                            BIAS_ADJ_int(BIAS_ADJ_int'high downto 0) <= write_data(BIAS_ADJ_int'high downto 0);
                        end if;
                    when RegSlotBIAS_DBP =>
                        if wen(0) = '0' then
                            BIAS_DBP_int(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            BIAS_DBP_int(BIAS_DBP_int'high downto 8) <= write_data(BIAS_DBP_int'high downto 8);
                        end if;
                    when RegSlotBIAS_DBPC =>
                        if wen(0) = '0' then
                            BIAS_DBPC_int(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            BIAS_DBPC_int(BIAS_DBPC_int'high downto 8) <= write_data(BIAS_DBPC_int'high downto 8);
                        end if;
                    when RegSlotBIAS_DBNC =>
                        if wen(0) = '0' then
                            BIAS_DBNC_int(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            BIAS_DBNC_int(BIAS_DBNC_int'high downto 8) <= write_data(BIAS_DBNC_int'high downto 8);
                        end if;
                    when RegSlotBIAS_DBN =>
                        if wen(0) = '0' then
                            BIAS_DBN_int(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            BIAS_DBN_int(BIAS_DBN_int'high downto 8) <= write_data(BIAS_DBN_int'high downto 8);
                        end if;
                    when RegSlotBIAS_TC_POT =>
                        if wen(0) = '0' then 
                            BIAS_TC_POT_int(5 downto 0) <= write_data(5 downto 0);
                        end if;
                    when RegSlotBIAS_LC_POT =>
                        if wen(0) = '0' then 
                            BIAS_LC_POT_int(5 downto 0) <= write_data(5 downto 0);
                        end if;
                    when RegSlotBIAS_TIA_G_POT =>
                        if wen(0) = '0' then 
                            BIAS_TIA_G_POT_int(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then 
                            BIAS_TIA_G_POT_int(BIAS_TIA_G_POT_int'high downto 8) <= write_data(BIAS_TIA_G_POT_int'high downto 8);
                        end if;
                    when RegSlotBIAS_DSADC_VCM =>
                        if wen(0) = '0' then
                            BIAS_DSADC_VCM_int(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            BIAS_DSADC_VCM_int(BIAS_DSADC_VCM_int'high downto 8) <= write_data(BIAS_DSADC_VCM_int'high downto 8);
                        end if;
                    when RegSlotBIAS_REV_POT =>
                        if wen(0) = '0' then
                            BIAS_REV_POT_int(7 downto 0) <= write_data(7 downto 0);
                        end if;
                        if wen(1) = '0' then
                            BIAS_REV_POT_int(BIAS_REV_POT_int'high downto 8) <= write_data(BIAS_REV_POT_int'high downto 8);
                        end if;
                    when RegSlotBIAS_TC_DSADC =>
                        if wen(0) = '0' then 
                            BIAS_TC_DSADC_int(5 downto 0) <= write_data(5 downto 0);
                        end if;
                    when RegSlotBIAS_LC_DSADC =>
                        if wen(0) = '0' then 
                            BIAS_LC_DSADC_int(5 downto 0) <= write_data(5 downto 0);
                        end if;
                    when RegSlotBIAS_RIN_DSADC =>
                        if wen(0) = '0' then 
                            BIAS_RIN_DSADC_int(5 downto 0) <= write_data(5 downto 0);
                        end if;
                    when RegSlotBIAS_RFB_DSADC =>
                        if wen(0) = '0' then 
                            BIAS_RFB_DSADC_int(5 downto 0) <= write_data(5 downto 0);
                        end if;
                    when others =>
                        null;
                end case;
            end if;
        end if;


        --Handle clear signals 
        if resetn = '0' or en_mem = '1' then
            clr_adc_ovf <='0';
            clr_adc_data_rdy_if <= '0';
            clr_adc_ovf_if <= '0';
        end if;

    end process;


    -- Register Read Process 
    reg_read_proc: process(clk_mem)
    begin
        if rising_edge(clk_mem) then
            
            case en_addr_periph is
                when RegSlotAFE_CR =>
                    read_data <= (31 downto AFE_CR'high + 1 => '0') & AFE_CR;
                when RegSlotAFE_TPR =>
                    read_data <= (31 downto AFE_TPR'high + 1 => '0') & AFE_TPR;
                when RegSlotAFE_SR =>
                    read_data <= (31 downto AFE_SR'high + 1 => '0') & (not AFE_SR_ltch); -- Return latched version of SR
                when RegSlotAFE_ADC_VAL =>
                    -- ADC Result Read Register
                    read_data <= (31 downto AFE_ADC_VAL'high + 1 => '0') & AFE_ADC_VAL;
                    adc_data_read <= '1'; -- For generating ovf_if
                when RegSlotBIAS_CR =>
                    read_data <= (31 downto BIAS_CR'high + 1 => '0') & BIAS_CR;
                when RegSlotBIAS_ADJ =>
                    read_data <= (31 downto BIAS_ADJ_int'high + 1 => '0') & BIAS_ADJ_int;
                when RegSlotBIAS_DBP =>
                    read_data <= (31 downto BIAS_DBP_int'high + 1 => '0') & BIAS_DBP_int;
                when RegSlotBIAS_DBPC =>
                    read_data <= (31 downto BIAS_DBPC_int'high + 1 => '0') & BIAS_DBPC_int;
                when RegSlotBIAS_DBNC =>
                    read_data <= (31 downto BIAS_DBNC_int'high + 1 => '0') & BIAS_DBNC_int;
                when RegSlotBIAS_DBN =>
                    read_data <= (31 downto BIAS_DBN_int'high + 1 => '0') & BIAS_DBN_int;
                when RegSlotBIAS_TC_POT =>
                    read_data <= (31 downto BIAS_TC_POT_int'high + 1 => '0') & BIAS_TC_POT_int;
                when RegSlotBIAS_LC_POT =>
                    read_data <= (31 downto BIAS_LC_POT_int'high + 1 => '0') & BIAS_LC_POT_int;
                when RegSlotBIAS_TIA_G_POT =>
                    read_data <= (31 downto BIAS_TIA_G_POT_int'high + 1 => '0') & BIAS_TIA_G_POT_int;
                when RegSlotBIAS_DSADC_VCM =>
                    read_data <= (31 downto BIAS_DSADC_VCM_int'high + 1 => '0') & BIAS_DSADC_VCM_int;
                when RegSlotBIAS_REV_POT =>
                    read_data <= (31 downto BIAS_REV_POT_int'high + 1 => '0') & BIAS_REV_POT_int;
                when RegSlotBIAS_TC_DSADC =>
                    read_data <= (31 downto BIAS_TC_DSADC_int'high + 1 => '0') & BIAS_TC_DSADC_int;
                when RegSlotBIAS_LC_DSADC =>
                    read_data <= (31 downto BIAS_LC_DSADC_int'high + 1 => '0') & BIAS_LC_DSADC_int;
                when RegSlotBIAS_RIN_DSADC =>
                    read_data <= (31 downto BIAS_RIN_DSADC_int'high + 1 => '0') & BIAS_RIN_DSADC_int;
                when RegSlotBIAS_RFB_DSADC =>
                    read_data <= (31 downto BIAS_RFB_DSADC_int'high + 1 => '0') & BIAS_RFB_DSADC_int;
                when others =>
                    read_data <= (others => '0'); -- Return zeros for unmapped addresses
            end case;
        end if;
    end process;






end Behavioral;
