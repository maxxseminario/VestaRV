library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

entity MCU is
   port (

        -- Resetn Pad
        resetn_in	: in	std_logic;	-- '0' <= resetn, '1' <= system running
		resetn_out	: out	std_logic;	-- Don't care
		resetn_dir	: out	std_logic;	-- Must be set to input mode
		resetn_ren	: out	std_logic;	-- Set to enable pullup resistor

        --GPIO0 Connections (SPI0, CLKHFXT, CLKLFXT, TRAP, BOOT)
		prt1_in		    : in	std_logic_vector(7 downto 0);
		prt1_out		: out	std_logic_vector(7 downto 0);
		prt1_dir		: out	std_logic_vector(7 downto 0);
		prt1_ren		: out	std_logic_vector(7 downto 0);

        --GPIO1 Connections (SPI1, UART0, UART1)
		prt2_in		    : in	std_logic_vector(7 downto 0);
		prt2_out		: out	std_logic_vector(7 downto 0);
		prt2_dir		: out	std_logic_vector(7 downto 0);
		prt2_ren		: out	std_logic_vector(7 downto 0);

        --GPIO2 Connections (TIMER0, TIMER1)
		prt3_in		    : in	std_logic_vector(7 downto 0);
		prt3_out		: out	std_logic_vector(7 downto 0);
		prt3_dir		: out	std_logic_vector(7 downto 0);
		prt3_ren		: out	std_logic_vector(7 downto 0);

        --GPIO3 Connections (TBD)
        prt4_in		    : in	std_logic_vector(7 downto 0);
		prt4_out		: out	std_logic_vector(7 downto 0);
		prt4_dir		: out	std_logic_vector(7 downto 0);
		prt4_ren		: out	std_logic_vector(7 downto 0);

        -- AFE Connections
        use_dac_glb_bias : out std_logic;
        en_bias_buf      : out std_logic;
        en_bias_gen      : out std_logic; -- For WideSwingCascBias

        -- Biasing Connections
        BIAS_ADJ		: out	std_logic_vector(5 downto 0);	
        BIAS_DBP		: out	std_logic_vector(13 downto 0);
        BIAS_DBN		: out	std_logic_vector(13 downto 0);
        BIAS_DBPC		: out	std_logic_vector(13 downto 0);
        BIAS_DBNC		: out	std_logic_vector(13 downto 0);

        -- Potentiostat Biases
        BIAS_TC_POT     : out   std_logic_vector(5 downto 0);
        BIAS_LC_POT     : out   std_logic_vector(5 downto 0);
        BIAS_TIA_G_POT  : out   std_logic_vector(16 downto 0); 
        BIAS_REV_POT    : out   std_logic_vector(13 downto 0);

        -- DSADC Biases
        BIAS_TC_DSADC  : out   std_logic_vector(5 downto 0);
        BIAS_LC_DSADC  : out   std_logic_vector(5 downto 0);
        BIAS_RIN_DSADC : out   std_logic_vector(5 downto 0);     
        BIAS_RFB_DSADC : out   std_logic_vector(5 downto 0);   
        BIAS_DSADC_VCM : out   std_logic_vector(13 downto 0);

        -- DSADC Connections
        dsadc_conv_done : in std_logic; 
        dsadc_en        : out std_logic;
        dsadc_clk       : out std_logic;
        dsadc_switch    : out std_logic_vector(2 downto 0);
        dac_en_pot      : out std_logic; 
        adc_ext_in      : out std_logic;
        atp_en          : out std_logic;
        atp_sel         : out std_logic;
        adc_sel         : out std_logic;

        -- SARADC Connections
        saradc_clk      : out std_logic;
        saradc_rdy      : in std_logic;
        saradc_rst      : out std_logic;
        saradc_data     : in std_logic_vector(9 downto 0); 

        -- Testing Purposes Only
        a0  : out std_logic_vector(31 downto 0) 

    ); 
end entity;

architecture behav of MCU is

    component vesta
        generic (
            PC_RST_VAL : std_logic_vector(31 downto 0);
            NUM_IRQS  : natural
        );
        port (
            clk              : in  std_logic;
            resetn           : in  std_logic;
            sleep            : in  std_logic;
            clk_cpu          : out std_logic;

            data_addr        : out std_logic_vector(31 downto 0);
            wen              : out std_logic_vector(3 downto 0);
            write_data       : out std_logic_vector(31 downto 0);
            read_data        : in  std_logic_vector(31 downto 0);
            mask             : in  std_logic_vector(1 downto 0);

            irq_vector      : in  std_logic_vector(NUM_IRQS-1 downto 0);
            irq_priority    : in  std_logic_vector(NUM_IRQS-1 downto 0);
            irq_en          : in  std_logic_vector(NUM_IRQS-1 downto 0);
            irq_recursion_en: in  std_logic;
            isr_ret         : out std_logic;

            trap_flag        : out  std_logic;

            a0               : out std_logic_vector(31 downto 0)

        );
    end component;



    component adddec is
        generic (
            ENABLE_FLASH_EXTENDED_MEM : boolean := false
        );
        port (
            clk               : in  std_logic;
            resetn            : in  std_logic;

            -- CPU interface
            wen               : in  std_logic_vector(3 downto 0);
            data_addr         : in  std_logic_vector(31 downto 0);
            write_word        : in  std_logic_vector(31 downto 0);
            mask              : out std_logic_vector(1 downto 0);
            
            -- Memory Bus 
            write_data        : out std_logic_vector(31 downto 0); 
            read_data         : out std_logic_vector(31 downto 0);
            mem_addr          : out std_logic_vector(11 downto 0);  -- 12 bits for 16KB memory blocks
            addr_periph       : out std_logic_vector(7 downto 2);
            mab_out           : out std_logic_vector(31 downto 0);  -- Full address bus for flash
            wen_fe        : out std_logic_vector(3 downto 0);
            -- wen_mem           : out std_logic_vector(3 downto 0);
            GWEN              : out std_logic;

            -- Memory Control Signals
            mem_en            : out std_logic_vector(2 downto 0); 
            mem_en_periph     : out std_logic_vector(15 downto 0);
            clk_mem           : out std_logic_vector(2 downto 0); 
            clk_periph        : out std_logic_vector(15 downto 0);
            
            -- Flash Extended Memory Signals (when ENABLE_FLASH_EXTENDED_MEM = true)
            mem_en_flash      : out std_logic;
            clk_mem_flash     : out std_logic;
            
            -- Memory Inputs
            mem_dout          : in word_array(0 to 2); 
            periph_dout       : in word_array(0 to 15);
            flash_dout        : in std_logic_vector(31 downto 0)  -- Flash data input
        );
    end component;



    ----------------------------------- Peripherals --------------------------------------------------

    -- SYSTEMx
    component SYSTEM
        generic (
            NUM_IRQS    : natural := 32
        );
        port (
            -- Clock Inputs 
            clk_lfxt_in     : in  std_logic;
            clk_hfxt_in     : in  std_logic;
            clk_dco0_in     : in  std_logic;
            clk_dco1_in     : in  std_logic;

            -- Reset Inputs
            resetn_in       : in  std_logic;
            resetn_por      : in  std_logic;
            resetn_sys      : out std_logic;

            -- Interrupt Signals
            irq             : in  std_logic_vector(NUM_IRQS -1 downto 0); 
            isr_ret         : in  std_logic;
            irq_en          : out std_logic_vector(NUM_IRQS -1 downto 0);
            irq_priority    : out std_logic_vector(NUM_IRQS -1 downto 0);
            irq_recursion_en: out std_logic;
            irq_sys_wdt     : out std_logic;

            -- Memory Bus
            clk_mem         : in  std_logic;
            en_mem          : in  std_logic;
            wen             : in  std_logic_vector(3 downto 0);
            addr_periph     : in  std_logic_vector(7 downto 2);
            write_data      : in  std_logic_vector(31 downto 0);
            read_data       : out std_logic_vector(31 downto 0);

            -- Clock Outputs
            mclk_out        : out std_logic;
            smclk_out       : out std_logic;
            clk_lfxt_out    : out std_logic;
            clk_hfxt_out    : out std_logic;

            -- DCO Signals 
            en_dco0_out        : out std_logic;
            DCO0_BIAS          : out std_logic_vector(11 downto 0);
            en_dco1_out        : out std_logic;
            DCO1_BIAS          : out std_logic_vector(11 downto 0);

            --Memory Power 
            PGEN_mem        : out std_logic_vector(2 downto 0) -- '0' mem on, '1' mem off
        );
    end component;

    --GPIOx
    component GPIO
        generic (
            num_pins        : natural;
            PadOUTPosLogic  : boolean;
            PadDIRPosLogic  : boolean;
            PadRENPosLogic  : boolean;
            RstValPxOUT     : std_logic_vector(31 downto 0) := (others => '0');
            RstValPxDIR     : std_logic_vector(31 downto 0) := (others => '0');
            RstValPxSEL		: std_logic_vector(31 downto 0) := (others => '0');
            RstValPxREN     : std_logic_vector(31 downto 0) := (others => '0')
        );
        port (
            resetn           : in  std_logic;
            irq              : out std_logic_vector(num_pins - 1 downto 0);	-- Interrupt request output signal, active high

            clk_mem         : in  std_logic;
            en              : in  std_logic;
            wen             : in  std_logic_vector(3 downto 0);
            write_data      : in  std_logic_vector(31 downto 0);
            read_data       : out std_logic_vector(31 downto 0);
            addr_periph     : in  std_logic_vector(7 downto 2);

            prt_in          : in  std_logic_vector(num_pins - 1 downto 0);
            prt_out_out     : out std_logic_vector(num_pins - 1 downto 0);
            prt_dir_out     : out std_logic_vector(num_pins - 1 downto 0);
            prt_ren_out     : out std_logic_vector(num_pins - 1 downto 0);

            PxOUT_out		: out	std_logic_vector(num_pins - 1 downto 0);
            PxDIR_out		: out	std_logic_vector(num_pins - 1 downto 0);
            PxREN_out		: out	std_logic_vector(num_pins - 1 downto 0);

            alt_func_out_in		: in	slv(num_pins - 1 downto 0);	
            alt_func_dir_in		: in	slv(num_pins - 1 downto 0);	
            alt_func_ren_in		: in	slv(num_pins - 1 downto 0)	
        );
    end component;

    --SPIx
    component SPI is
        generic
        (
            ENABLE_EXTENDED_MEM : boolean := false  
        );
        port (
            clk         : in  std_logic;
            mclk        : in  std_logic;
            -- clk_cpu     : in  std_logic;
            resetn      : in  std_logic;
            irq_tc      : out std_logic;
            irq_te      : out std_logic;

            clk_mem      : in  std_logic; -- Clock for Memory
            en_mem       : in  std_logic; -- Enable Memory Peripheral
            wen          : in  std_logic_vector(3 downto 0); -- Write Enable for Memory
            write_data   : in  std_logic_vector(31 downto 0); -- Data to Write
            read_data    : out std_logic_vector(31 downto 0); -- Data Read
            addr_periph  : in  std_logic_vector(7 downto 2); -- Peripheral Address

            cs_in        : in  std_logic;

            sck_in       : in  std_logic;
            sck_out      : out std_logic;
            sck_dir      : out std_logic;
            sck_ren      : out std_logic;
            sck_ren_in   : in  std_logic;

            mosi_in      : in  std_logic;
            mosi_out     : out std_logic;
            mosi_dir     : out std_logic;
            mosi_ren     : out std_logic;
            mosi_ren_in  : in  std_logic;

            miso_in      : in  std_logic;
            miso_out     : out std_logic;
            miso_dir     : out std_logic;
            miso_ren     : out std_logic;
            miso_ren_in  : in  std_logic;

            -- Flash Extended Memory Signals (only used when ENABLE_EXTENDED_MEM = true)
            en_mem_flash    : in std_logic;
            clk_mem_flash   : in std_logic;
            mab             : in std_logic_vector(31 downto 0);
            rdata_flash     : out std_logic_vector(31 downto 0);
            disable_clk_cpu : out std_logic;
            
            cs_flash_out    : out std_logic;
            cs_flash_dir    : out std_logic;
            cs_flash_ren    : out std_logic

        );
    end component;

    -- UARTx
    component UART is
        port (
            -- System Signals
            clk          : in  std_logic;    
            resetn       : in  std_logic;    

            -- Interrupt Outputs
            irq_rc      : out std_logic;   
            irq_te      : out std_logic; 
            irq_tc      : out std_logic;  

            -- Memory Bus
            clk_mem     : in  std_logic;
            en_mem      : in  std_logic;
            wen         : in  std_logic_vector(3 downto 0);
            addr_periph : in  std_logic_vector(7 downto 2);
            write_data  : in  word;
            read_data   : out word;

            -- Pad Interface
            TX_OUT      : out std_logic;
            TX_DIR      : out std_logic;
            TX_REN      : out std_logic;

            RX_IN       : in  std_logic;
            RX_OUT      : out std_logic;
            RX_DIR      : out std_logic;
            RX_REN      : out std_logic
        );
    end component;

    -- I2Cx
    component I2C is
        port
        (
            -- System Signals
            smclk			: in	std_logic;	-- Sub-main clock
            resetn			: in	std_logic;	-- System reset

            irq_str 		: out std_logic;
            irq_spr 		: out std_logic;
            irq_msts 		: out std_logic;
            irq_msps 		: out std_logic;
            irq_marb 		: out std_logic;
            irq_mtxe 		: out std_logic;
            irq_mnr 		: out std_logic;
            irq_mxc 		: out std_logic;
            irq_sa 			: out std_logic;
            irq_stxe 		: out std_logic;
            irq_sovf 		: out std_logic;
            irq_snr 		: out std_logic;
            irq_sxc 		: out std_logic;

            -- Memory Bus
            ClkMem			: in	std_logic;
            EnMemPeriph		: in	std_logic;
            WEn				: in	std_logic_vector(3 downto 0);
            MABPart			: in	std_logic_vector(7 downto 2);
            wdata			: in	std_logic_vector(31 downto 0);
            rdata_out		: out	std_logic_vector(31 downto 0);

            -- Pin Inputs/Outputs
            SDA_IN			: in	std_logic;
            SDA_OUT			: out	std_logic;
            SDA_DIR			: out	std_logic;
            SDA_REN_in		: in	std_logic;
            SDA_REN			: out	std_logic;

            SCL_IN			: in	std_logic;
            SCL_OUT			: out	std_logic;
            SCL_DIR			: out	std_logic;
            SCL_REN_in		: in	std_logic;
            SCL_REN			: out	std_logic
        );
    end component;

    -- TIMERx
    component TIMER is
        port (
            -- System Signals
            mclk         : in  std_logic;  -- Main clock
            smclk        : in  std_logic;  -- Sub-main clock
            clk_lfxt     : in  std_logic;  -- Low-frequency crystal clock
            clk_hfxt     : in  std_logic;  -- High-frequency crystal clock
            resetn       : in  std_logic;  -- System resetn 

            -- IRQ Signals
            irq_cap0    : out std_logic;  -- Capture 0 Interrupt
            irq_cap1    : out std_logic;  -- Capture 1 Interrupt
            irq_ovf     : out std_logic;  -- Overflow Interrupt
            irq_cmp0    : out std_logic;  -- Compare 0 Interrupt
            irq_cmp1    : out std_logic;  -- Compare 1 Interrupt
            irq_cmp2    : out std_logic;  -- Compare 2 Interrupt

            -- Memory Bus
            clk_mem      : in  std_logic;
            en_mem       : in  std_logic;
            wen          : in  std_logic_vector(3 downto 0);
            addr_periph  : in  std_logic_vector(7 downto 2);
            write_data   : in  std_logic_vector(31 downto 0);
            read_data    : out std_logic_vector(31 downto 0);

            -- Pad Interface
            cmp0_ren_in : in  std_logic;  -- Timer Compare 0 Pin
            cmp0_out    : out std_logic;
            cmp0_dir    : out std_logic;
            cmp0_ren    : out std_logic;

            cmp1_ren_in : in  std_logic;  -- Timer Compare 1 Pin
            cmp1_out    : out std_logic;
            cmp1_dir    : out std_logic;
            cmp1_ren    : out std_logic;

            cap0_ren_in : in  std_logic;  -- Timer Input Capture 0 Pin
            cap0_ren    : out std_logic;
            cap0_dir    : out std_logic;
            cap0_in     : in  std_logic;  -- Timer Input Capture 0 Pin

            cap1_ren_in : in  std_logic;  -- Timer Input Capture 1 Pin
            cap1_ren    : out std_logic;
            cap1_dir    : out std_logic;
            cap1_in     : in  std_logic   -- Timer Input Capture 1 Pin
        );
    end component;

    -- NPUx
    component NPU is
        generic(
            -- Fixed-Point M and N Bits for inputs, weights, and outputs
            -- Of note, Y bits also control size of accumulator
            X_M_BITS		: integer := 0;
            W_M_BITS		: integer := 3;
            Y_M_BITS		: integer := 3;
            N_BITS			: integer := 15;
            -- RHO to be used with sigmoid approximation
            RHO				: integer := 2
        );
        port(
            -- System Signals
            Clk				: in	std_logic;						-- NPU Main Clock
            ResetN			: in	std_logic;						-- NPU Active-Low Reset

            -- Memory Address Bus to Memory Mapped Registers Signals
            MabMmrA			: in 	std_logic_vector(1 downto 0);	-- MCU To NPU MMR - Address
            MabMmrD			: in	std_logic_vector(31 downto 0);	-- MCU To NPU MMR - Data Input
            MabMmrCLK		: in	std_logic;						-- MCU To NPU MMR - Clock
            MabMmrCEN		: in	std_logic;						-- MCU To NPU MMR - Chip Enable
            MabMmrWEN		: in	std_logic_vector(3 downto 0);	-- MCU To NPU MMR - Write Enable
            MabMmrQ			: out 	std_logic_vector(31 downto 0);	-- MCU To NPU MMR - Data Output

            -- Multiplexed SRAM Signals from MCU
            SramQ_in		: in	std_logic_vector(31 downto 0);	-- MCU To NPU - Data Output
            SramA_in 		: in	std_logic_vector(11 downto 0);	-- SRAM To NPU - Address
            SramD_in 		: in	std_logic_vector(31 downto 0);	-- SRAM To NPU - Data Input
            SramCLK_in 		: in	std_logic;						-- SRAM To NPU - Clock
            SramCEN_in 		: in	std_logic;						-- SRAM To NPU - Chip Enable
            SramGWEN_in 	: in	std_logic;						-- SRAM To NPU - Global Write Enable
            SramWEN_in 		: in	std_logic_vector(3 downto 0);	-- SRAM To NPU - Write Enable
        
            -- NPU to SRAM Interface Signals
            NpuSramA_out		: out	std_logic_vector(11 downto 0);	-- NPU To SRAM - Address 
            NpuSramD_out		: out	std_logic_vector(31 downto 0);	-- NPU To SRAM - Data Input
            NpuSramCLK_out		: out 	std_logic;						-- NPU To SRAM - Clock
            NpuSramCEN_out		: out	std_logic;						-- NPU To SRAM - Chip Enable
            NpuSramGWEN_out		: out 	std_logic;						-- NPU To SRAM - Global Write Enable
            NpuSramWEN_out		: out 	std_logic_vector(3 downto 0);	-- NPU To SRAM - Write Enable

            -- NPU Status Signal
            NpuActive		: out	std_logic						-- NPU Active Signal for Arbitration
        );
    end component;

    -- AFEx
    component AFE is
        port(
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
            en_dsadc_bias   : out std_logic; -- Enables biasing for the DSADC. This signal should be tied high if the DSADC is being used.
            en_pot_re_bias  : out std_logic; -- Enables biasing for the potentiostat. This signal should be tied high if the potentiostat is being used.
            
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
            BIAS_TC_DSADC   : out std_logic_vector(5 downto 0);     -- Bias Current BTS - DSADC
            BIAS_LC_DSADC   : out std_logic_vector(5 downto 0);     -- LC Resistor      - DSADC
            BIAS_RIN_DSADC  : out std_logic_vector(5 downto 0);     -- Input Resistor   - DSADC
            BIAS_RFB_DSADC   : out std_logic_vector(5 downto 0);    -- Feedback Resistor- DSADC
            BIAS_DSADC_VCM   : out std_logic_vector(13 downto 0);   -- DSADC VCM Voltage (DAC)

            -- DSADC Outputs Signals 
            adc_conv_done   : in std_logic;
            adc_en          : out std_logic;
            adc_clk         : out std_logic;
            adc_switch      : out std_logic_vector(2 downto 0);
            adc_ext_in      : out std_logic; -- '1' => adc's input is from potentiostat pad, '0' => external signal
            atp_en          : out std_logic; -- '1' => enable ATP, '0' => disable ATP
            atp_sel         : out std_logic; -- '1' => atp input is from DSADC, '0' => atp input is from Potentiostat
            adc_sel         : out std_logic; -- '1' => adc to use is SARADC, '0' => adc input is from DSADC
            dac_en          : out std_logic -- DAC Enable
        ); 
    end component AFE;

    -- SARADCx
    component SARADC is
        port (
            -- System Signals
            clk          : in  std_logic;  
            resetn       : in  std_logic;  
            irq          : out std_logic;  

            -- Memory Bus (active low enables)
            clk_mem      : in  std_logic;
            en_mem       : in  std_logic;                       
            wen          : in  std_logic_vector(3 downto 0); 
            addr_periph  : in  std_logic_vector(7 downto 2);
            write_data   : in  std_logic_vector(31 downto 0);
            read_data    : out std_logic_vector(31 downto 0);

            -- Digital Test Ports 
            dtp0   : out std_logic;
            dtp1   : out std_logic;

            -- ADC Output Signals 
            adc_sel      : out std_logic; -- '1' => adc's input is from external pad, '0' => internal signal

            -- ADC Connection 
            ADC_ready_i : in std_logic;
            ADC_data_i  : in std_logic_vector(9 downto 0); 
            ADC_reset  : out std_logic;
            ADC_trigger_clock_o : out std_logic
        );
    end component;


    -- MCU Block Level Signal Declarations --------------------------------------

        -- System Signals 
        signal resetn           : std_logic; 
        signal resetn_por       : std_logic;
        signal resetn_sys       : std_logic; 
        signal irq_en           : std_logic_vector(NUM_IRQS-1 downto 0);
        signal irq_priority     : std_logic_vector(NUM_IRQS-1 downto 0);
        signal isr_ret          : std_logic; -- Interrupt Service Routine Return Signal
        signal irq_recursion_en : std_logic; -- Allow Interrupt Recursion
        signal irq_tielow       : std_logic; -- Tielo cell for unused glitch filter inputs 
        signal sleep_cpu        : std_logic;
        signal PGENROM          : std_logic; -- Active low power rom power gating
        signal PGENSRAM         : std_logic; -- Active low power ram power gating
        signal mclk             : std_logic;
        signal smclk            : std_logic;
        signal clk_lfxt         : std_logic; -- Gated lfxt clock from system
        signal clk_hfxt         : std_logic; -- Gated hfxt clock from system
        signal clk_osc_dco0     : std_logic; -- DCO0 Clock directly from oscillator
        signal clk_osc_dco1     : std_logic; -- DCO1 Clock directly from oscillator
        signal clk_cpu          : std_logic; -- Gated cpu clock from system

        -- signal wen_mem        : std_logic_vector(3 downto 0);

        -- IRQ Signal Declarations
        signal irq_sys_wdt      : std_logic;  -- Watchdog Timer Interrupt
        signal irq_gpio0        : std_logic_vector(7 downto 0);  -- GPIO0 Interrupt
        signal irq_gpio1        : std_logic_vector(7 downto 0);  -- GPIO1 Interrupt
        signal irq_gpio2        : std_logic_vector(7 downto 0);  -- GPIO2 Interrupt
        signal irq_gpio3        : std_logic_vector(7 downto 0);  -- GPIO3 Interrupt
        signal irq_spi0_tc      : std_logic;  -- SPI0 Transmission Complete Interrupt
        signal irq_spi0_te      : std_logic;  -- SPI0 Transmission Buffer Empty Interrupt
        signal irq_spi1_tc      : std_logic;  -- SPI1 Transmission Complete Interrupt
        signal irq_spi1_te      : std_logic;  -- SPI1 Transmission Buffer Empty Interrupt
        signal irq_uart0_rc     : std_logic;  -- UART0 Receive Complete Interrupt
        signal irq_uart0_te     : std_logic;  -- UART0 Transmission Buffer Empty Interrupt
        signal irq_uart0_tc     : std_logic;  -- UART0 Transmission Complete Interrupt
        signal irq_tim0_cap0    : std_logic;  -- TIMER0 Capture 0 Interrupt
        signal irq_tim0_cap1    : std_logic;  -- TIMER0 Capture 1 Interrupt
        signal irq_tim0_ovf     : std_logic;  -- TIMER0 Overflow Interrupt
        signal irq_tim0_cmp0    : std_logic;  -- TIMER0 Compare 0 Interrupt
        signal irq_tim0_cmp1    : std_logic;  -- TIMER0 Compare 1 Interrupt
        signal irq_tim0_cmp2    : std_logic;  -- TIMER0 Compare 2 Interrupt
        signal irq_tim1_cap0    : std_logic;  -- TIMER1 Capture 0 Interrupt
        signal irq_tim1_cap1    : std_logic;  -- TIMER1 Capture 1 Interrupt
        signal irq_tim1_ovf     : std_logic;  -- TIMER1 Overflow Interrupt
        signal irq_tim1_cmp0    : std_logic;  -- TIMER1 Compare 0 Interrupt
        signal irq_tim1_cmp1    : std_logic;  -- TIMER1 Compare 1 Interrupt
        signal irq_tim1_cmp2    : std_logic;  -- TIMER1 Compare 2 Interrupt
        signal irq_uart1_rc     : std_logic;  -- UART1 Receive Complete Interrupt
        signal irq_uart1_te     : std_logic;  -- UART1 Transmission Buffer Empty Interrupt
        signal irq_uart1_tc     : std_logic;  -- UART1 Transmission Complete Interrupt
        signal irq_afe0_rc      : std_logic;  -- AFE0 Receive Complete Interrupt
        signal irq_sar0_rc      : std_logic;  -- SARADC0 Conversion Complete Interrupt
        signal irq_i2c0_str    : std_logic;  -- I2C0 Start Received Interrupt
        signal irq_i2c0_spr    : std_logic;  -- I2C0 Stop Received Interrupt
        signal irq_i2c0_msts   : std_logic;  -- I2C0 Master Mode Start Condition Sent Interrupt
        signal irq_i2c0_msps   : std_logic;  -- I2C0 Master Mode Stop Condition Sent Interrupt
        signal irq_i2c0_marb   : std_logic;  -- I2C0 Master Arbitration Lost Interrupt
        signal irq_i2c0_mtxe   : std_logic;  -- I2C0 Master Transmit Empty Interrupt
        signal irq_i2c0_mnr    : std_logic;  -- I2C0 Master Mode NACK Received Interrupt
        signal irq_i2c0_mxc    : std_logic;  -- I2C0 Master Transfer Complete Interrupt
        signal irq_i2c0_sa     : std_logic;  -- I2C0 Slave Address Interrupt
        signal irq_i2c0_stxe   : std_logic;  -- I2C0 Slave Transmit Empty Interrupt
        signal irq_i2c0_sovf   : std_logic;  -- I2C0 Slave Overflow Interrupt
        signal irq_i2c0_snr    : std_logic;  -- I2C0 Slave Mode NACK Received Interrupt
        signal irq_i2c0_sxc    : std_logic;  -- I2C0 Slave Transfer Complete Interrupt
        signal irq_i2c1_str    : std_logic;  -- I2C1 Start Received Interrupt
        signal irq_i2c1_spr    : std_logic;  -- I2C1 Stop Received Interrupt
        signal irq_i2c1_msts   : std_logic;  -- I2C1 Master Mode Start Condition Sent Interrupt
        signal irq_i2c1_msps   : std_logic;  -- I2C1 Master Mode Stop Condition Sent Interrupt
        signal irq_i2c1_marb   : std_logic;  -- I2C1 Master Mode Arbitration Lost Interrupt
        signal irq_i2c1_mtxe   : std_logic;  -- I2C1 Master Mode Transmit Empty Interrupt
        signal irq_i2c1_mnr    : std_logic;  -- I2C1 Master Mode NACK Received Interrupt
        signal irq_i2c1_mxc    : std_logic;  -- I2C1 Master Mode Transfer Complete Interrupt
        signal irq_i2c1_sa     : std_logic;  -- I2C1 Slave Address Interrupt
        signal irq_i2c1_stxe   : std_logic;  -- I2C1 Slave Transmit Empty Interrupt
        signal irq_i2c1_sovf   : std_logic;  -- I2C1 Slave Overflow Interrupt
        signal irq_i2c1_snr    : std_logic;  -- I2C1 Slave Mode NACK Received Interrupt
        signal irq_i2c1_sxc    : std_logic;  -- I2C1 Slave Transfer Complete Interrupt

        signal irq_comb         : std_logic_vector(95 downto 0);
        signal irq_deglitch     : std_logic_vector(NUM_IRQS -1 downto 0);
        signal gf_out           : std_logic_vector(95 downto 0);
        -- signal irq_cat          : std_logic_vector(95 downto NUM_IRQS);


        -- RISCV Core Interface Signals 
        signal read_data        : std_logic_vector(31 downto 0);
        signal write_word       : std_logic_vector(31 downto 0);
        signal data_addr        : std_logic_vector(31 downto 0);
        signal wen_re           : std_logic_vector(3 downto 0);
        signal wen_fe           : std_logic_vector(3 downto 0);
        -- signal inst_retired     : std_logic; -- Instruction Retired Signal from Core
        -- signal mem_access       : std_logic; -- High when memory access is occurring

        -- Memory and RAM Control Signals  
        signal RAM_Dout         : std_logic_vector(31 downto 0);
        signal write_data       : std_logic_vector(31 downto 0);
        signal mask             : std_logic_vector(1 downto 0);
        signal GWEN             : std_logic;
        signal mem_addr         : std_logic_vector(11 downto 0); 
        signal mem_dout         : word_array(0 to 2);
        signal periph_dout      : word_array(0 to 15); 
        signal pgen_mem         : std_logic_vector(2 downto 0);
        signal addr_periph      : std_logic_vector(7 downto 2); 
        signal mem_en           : std_logic_vector(2 downto 0);
        signal mem_en_periph    : std_logic_vector(15 downto 0); 
        signal clk_mem          : std_logic_vector(2 downto 0);
        signal clk_periph       : std_logic_vector(15 downto 0); 
        
        -- Flash Extended Memory Signals
        signal mem_en_flash    : std_logic;
        signal clk_mem_flash   : std_logic;
        signal mab_flash       : std_logic_vector(31 downto 0); 
        signal flash_dout      : std_logic_vector(31 downto 0);
        signal flash_ext_meming: std_logic;
        signal mab_out         : std_logic_vector(31 downto 0); 

        -- NPU0 Signals 
        signal npu0_mux_ram_a       : std_logic_vector(11 downto 0);
        signal npu0_mux_ram_d       : std_logic_vector(31 downto 0);
        signal npu0_mux_ram_cen     : std_logic;
        signal npu0_mux_ram_gwen    : std_logic;
        signal npu0_mux_wen         : std_logic_vector(3 downto 0);
        signal npu0_mux_ram_q       : std_logic_vector(31 downto 0);
        signal npu0_mux_ram_clk     : std_logic;
        signal npu0_active          : std_logic;

        -- DCO Signals 
        signal en_dco0          : std_logic;
        signal en_dco1          : std_logic;
        signal DCO0_BIAS        : std_logic_vector(11 downto 0);
        signal DCO1_BIAS        : std_logic_vector(11 downto 0);
        signal reset_dco       : std_logic; --special reset for DCO to ensure proper startup

    -- GPIO0 Signals (Port 1) ------------------------------------------------------------
        signal p1_out					: std_logic_vector(7 downto 0);
        signal p1_dir					: std_logic_vector(7 downto 0);
        signal p1_ren					: std_logic_vector(7 downto 0);
        signal afunc1_out				: std_logic_vector(7 downto 0); -- Alternate Function Output
        signal afunc1_dir				: std_logic_vector(7 downto 0); -- Alternate Function Direction
        signal afunc1_ren				: std_logic_vector(7 downto 0); -- Alternate Function Resistor Enable

        -- -- P1.0: cs_flash (output only)
        signal cs_flash_in              : std_logic;
        signal cs_flash_ren_in         : std_logic; -- Read Enable for CS 
        -- For extended flash memory support
        signal cs_flash_out				: std_logic;
        signal cs_flash_dir				: std_logic;
        signal cs_flash_ren				: std_logic;

        -- P1.1: miso_flash (input and output)
        signal miso_flash_in			: std_logic;
        signal miso_flash_out			: std_logic;
        signal miso_flash_dir			: std_logic;
        signal miso_flash_ren			: std_logic;
        signal miso_flash_ren_in        : std_logic; -- Read Enable for MISO
        
        -- P1.2: mosoi_flash (output only)
        signal mosi_flash_in			: std_logic;
        signal mosi_flash_out			: std_logic;
        signal mosi_flash_dir			: std_logic;
        signal mosi_flash_ren			: std_logic;
        signal mosi_flash_ren_in        : std_logic; -- Read Enable for MOSI

        -- P1.3: sck_flash (output only)
        signal sck_flash_out		    : std_logic;
        signal sck_flash_dir	        : std_logic;
        signal sck_flash_ren	        : std_logic;
        signal sck_flash_in             : std_logic;
        signal sck_flash_ren_in        : std_logic; -- Read Enable for SCK

        -- P1.4 lfxt (input and output)
        signal lfxt_in              : std_logic;
        signal lfxt_out             : std_logic;
        signal lfxt_dir             : std_logic;
        signal lfxt_ren             : std_logic;
        signal lfxt_ren_in         : std_logic;

        -- P1.5 hfxt (input and output)
        signal hfxt_in              : std_logic;
        signal hfxt_out             : std_logic;
        signal hfxt_dir             : std_logic;
        signal hfxt_ren             : std_logic;
        signal hfxt_ren_in         : std_logic;

        -- P1.6 TRAP (Output Only) 
        signal trap_out             : std_logic;
        signal trap_dir             : std_logic;
        signal trap_ren             : std_logic;
        signal trap_ren_in          : std_logic;


        
        -- P1.7 Boot Mode Select (should be reset to input)



    -- GPIO1 Signals (Port 2) ------------------------------------------------------------
        signal p2_out					: std_logic_vector(7 downto 0);
        signal p2_dir					: std_logic_vector(7 downto 0);
        signal p2_ren					: std_logic_vector(7 downto 0);
        signal afunc2_out				: std_logic_vector(7 downto 0); -- Alternate Function Output
        signal afunc2_dir				: std_logic_vector(7 downto 0); -- Alternate Function Direction
        signal afunc2_ren				: std_logic_vector(7 downto 0); -- Alternate Function Resistor Enable

        -- P2.0: cs1 
        signal cs1_in                : std_logic;
        signal cs1_ren_in           : std_logic;

        -- P2.1: miso1 
        signal miso1_in              : std_logic;
        signal miso1_out             : std_logic;
        signal miso1_dir             : std_logic;
        signal miso1_ren             : std_logic;
        signal miso1_ren_in         : std_logic;

        -- P2.2: mosi1
        signal mosi1_in              : std_logic;
        signal mosi1_out             : std_logic;
        signal mosi1_dir             : std_logic;
        signal mosi1_ren             : std_logic;
        signal mosi1_ren_in         : std_logic;

        -- P2.3: sck1
        signal sck1_in               : std_logic;
        signal sck1_out              : std_logic;
        signal sck1_dir              : std_logic;
        signal sck1_ren              : std_logic;
        signal sck1_ren_in          : std_logic;

        -- P2.4: TX0
        signal tx0_out              : std_logic;
        signal tx0_dir              : std_logic;
        signal tx0_ren              : std_logic;
        signal tx0_ren_in          : std_logic;
        
        -- P2.5: RX0
        signal rx0_in               : std_logic;
        signal rx0_out              : std_logic;
        signal rx0_dir              : std_logic;
        signal rx0_ren              : std_logic;
        signal rx0_ren_in          : std_logic;

        -- P2.6: TX1
        signal tx1_out              : std_logic;
        signal tx1_dir              : std_logic;
        signal tx1_ren              : std_logic;
        signal tx1_ren_in          : std_logic;

        -- P2.7: RX1
        signal rx1_in               : std_logic;
        signal rx1_out              : std_logic;
        signal rx1_dir              : std_logic;
        signal rx1_ren              : std_logic;
        signal rx1_ren_in           : std_logic;
    
    -- GPIO2 Signals (Port 3) ------------------------------------------------------------
        signal p3_out					: std_logic_vector(7 downto 0);
        signal p3_dir					: std_logic_vector(7 downto 0);
        signal p3_ren					: std_logic_vector(7 downto 0);
        signal afunc3_out				: std_logic_vector(7 downto 0); -- Alternate Function Output
        signal afunc3_dir				: std_logic_vector(7 downto 0); -- Alternate Function Direction
        signal afunc3_ren				: std_logic_vector(7 downto 0); -- Alternate Function Resistor Enable

        -- P3.0: T0_CMP0 (output)
        signal t0_cmp0_out           : std_logic;
        signal t0_cmp0_dir           : std_logic;
        signal t0_cmp0_ren           : std_logic;
        signal t0_cmp0_ren_in       : std_logic;

        -- P3.1: T0_CMP1 (output)
        signal t0_cmp1_out           : std_logic;
        signal t0_cmp1_dir           : std_logic;
        signal t0_cmp1_ren           : std_logic;
        signal t0_cmp1_ren_in       : std_logic;

        -- P3.2: T0_CAP0 (input)
        signal t0_cap0_in            : std_logic;
        signal t0_cap0_dir           : std_logic;
        signal t0_cap0_ren           : std_logic;
        signal t0_cap0_ren_in       : std_logic;

        -- P3.3: T0_CAP1 (input and output (double as dtp for SARADC))
        signal t0_cap1_in            : std_logic;
        signal t0_cap1_dir           : std_logic;
        signal t0_cap1_ren           : std_logic;
        signal t0_cap1_ren_in       : std_logic;
        signal t0_cap1_out           : std_logic;


        -- P3.4: T1_CMP0 (output)
        signal t1_cmp0_out           : std_logic;
        signal t1_cmp0_dir           : std_logic;
        signal t1_cmp0_ren           : std_logic;
        signal t1_cmp0_ren_in        : std_logic;

        -- P3.5: T1_CMP1 (output)
        signal t1_cmp1_out           : std_logic;
        signal t1_cmp1_dir           : std_logic;
        signal t1_cmp1_ren           : std_logic;
        signal t1_cmp1_ren_in       : std_logic;

        -- P3.6: T1_CAP0 (input)
        signal t1_cap0_in            : std_logic;
        signal t1_cap0_dir           : std_logic;
        signal t1_cap0_ren           : std_logic;
        signal t1_cap0_ren_in       : std_logic;

        -- P3.7: T1_CAP1 (input and output (double as dtp for SARADC))
        signal t1_cap1_in            : std_logic;
        signal t1_cap1_dir           : std_logic;
        signal t1_cap1_ren           : std_logic;
        signal t1_cap1_ren_in        : std_logic;
        signal t1_cap1_out           : std_logic;


    -- GPIO3 Signals (Port 4) ------------------------------------------------------------
        signal p4_out					: std_logic_vector(7 downto 0);
        signal p4_dir					: std_logic_vector(7 downto 0);
        signal p4_ren					: std_logic_vector(7 downto 0);
        signal afunc4_out				: std_logic_vector(7 downto 0); -- Alternate Function Output
        signal afunc4_dir				: std_logic_vector(7 downto 0); -- Alternate Function Direction
        signal afunc4_ren				: std_logic_vector(7 downto 0); -- Alternate Function Resistor Enable

        -- P4.0: SDA0 (input and output)
        signal sda0_in               : std_logic;
        signal sda0_out              : std_logic;
        signal sda0_dir              : std_logic;
        signal sda0_ren              : std_logic;
        signal sda0_ren_in          : std_logic;

        -- P4.1: SCL0 (input and output)
        signal scl0_in               : std_logic;
        signal scl0_out              : std_logic;
        signal scl0_dir              : std_logic;
        signal scl0_ren              : std_logic;
        signal scl0_ren_in          : std_logic;

        -- P4.2: SDA1 (input and output)
        signal sda1_in               : std_logic;
        signal sda1_out              : std_logic;
        signal sda1_dir              : std_logic;
        signal sda1_ren              : std_logic;
        signal sda1_ren_in          : std_logic;
        
        -- P4.3: SCL1 (input and output)
        signal scl1_in               : std_logic;
        signal scl1_out              : std_logic;
        signal scl1_dir              : std_logic;
        signal scl1_ren              : std_logic;
        signal scl1_ren_in          : std_logic;

        -- P4.4: DTP0 (output only)
        signal dtp0_out               : std_logic;
        signal dtp0_dir               : std_logic;
        signal dtp0_ren               : std_logic;
        signal dtp0_ren_in           : std_logic;

        -- P4.5: DTP1 (output only)
        signal dtp1_out               : std_logic;
        signal dtp1_dir               : std_logic;
        signal dtp1_ren               : std_logic;
        signal dtp1_ren_in           : std_logic;

        -- P4.6: DTP2 (output only)
        signal dtp2_out               : std_logic;
        signal dtp2_dir               : std_logic;
        signal dtp2_ren               : std_logic;
        signal dtp2_ren_in           : std_logic;

        -- P4.7: DTP3 (output only)
        signal dtp3_out               : std_logic;
        signal dtp3_dir               : std_logic;
        signal dtp3_ren               : std_logic;
        signal dtp3_ren_in           : std_logic;
        
begin

    --Signal Routing 
    -- NOTE: These are raw signals going to pads, not configured in the same manner as GPIO dir, ren, and out signals.
    resetn_out <= '1'; -- NA
    resetn_dir <= PAD_DIR_INPUT_LEVEL; -- DO NOT TOUCH - KEEP AT 1 - Must be set to input mode 
    resetn_ren <= PAD_REN_ENABLE_LEVEL; -- Enable pullup resistor

    lfxt_out <= '1'; --NA
    lfxt_dir <= PAD_DIR_INPUT_LEVEL; --input
    lfxt_ren <= PAD_REN_DISABLE_LEVEL; --disable 

    hfxt_out <= '1'; --NA
    hfxt_dir <= PAD_DIR_INPUT_LEVEL; --input
    hfxt_ren <= PAD_REN_DISABLE_LEVEL; --disable

    trap_dir <= PAD_DIR_OUTPUT_LEVEL; --output

    
    -- GPIO0 Connections (SPI0, CLKLFXT, CLKHFXT, TRAP, BOOT) -----------------------------------------
        cs_flash_in <= prt1_in(pnum_gpio0_cs_flash);
        miso_flash_in <= prt1_in(pnum_gpio0_miso); -- MISO is input to core
        mosi_flash_in <= prt1_in(pnum_gpio0_mosi); -- MOSI is output from core
        sck_flash_in <= prt1_in(pnum_gpio0_spi_clk); -- SCK is output from core
        sck_flash_ren_in <= p1_ren(pnum_gpio0_spi_clk); -- SCK read enable
        mosi_flash_ren_in <= p1_ren(pnum_gpio0_mosi); -- MOSI read enable
        miso_flash_ren_in <= p1_ren(pnum_gpio0_miso);
        lfxt_in <= prt1_in(pnum_gpio0_lfxt);
        lfxt_ren_in <= p1_ren(pnum_gpio0_lfxt);
        hfxt_in <= prt1_in(pnum_gpio0_hfxt);
        hfxt_ren_in <= p1_ren(pnum_gpio0_hfxt);
        trap_ren_in <= p1_ren(pnum_gpio0_trap); 


        afunc1_out <= (
            7 => p1_out(7), -- GPIO0 pin 7
            pnum_gpio0_trap => trap_out, -- GPIO0 pin 6
            pnum_gpio0_hfxt => hfxt_out, -- GPIO0 pin 5
            pnum_gpio0_lfxt => lfxt_out, -- GPIO0 pin 4
            pnum_gpio0_spi_clk => sck_flash_out, -- GPIO0 pin 3
            pnum_gpio0_mosi => mosi_flash_out, -- GPIO0 pin 2
            pnum_gpio0_miso => miso_flash_out, -- GPIO0 pin 1
            pnum_gpio0_cs_flash => cs_flash_out -- GPIO0 pin 0
        );

        afunc1_dir <= (
            7 => p1_dir(7),                 -- GPIO0 pin 7
            pnum_gpio0_trap => not trap_dir,        -- GPIO0 pin 6
            pnum_gpio0_hfxt => not hfxt_dir,    -- GPIO0 pin 5 (Invert once more because of configured logic level of GPIO0)
            pnum_gpio0_lfxt => not lfxt_dir,    -- GPIO0 pin 4 (Invert once more because of configured logic level of GPIO0)
            pnum_gpio0_spi_clk => sck_flash_dir, -- GPIO0 pin 3
            pnum_gpio0_mosi => mosi_flash_dir, -- GPIO0 pin 2
            pnum_gpio0_miso => miso_flash_dir, -- GPIO0 pin 1
            pnum_gpio0_cs_flash => cs_flash_dir -- GPIO0 pin 0
        );

        afunc1_ren <= (
            7 => p1_ren(7), -- GPIO0 pin 7
            pnum_gpio0_trap => trap_ren_in, -- GPIO0 pin 6
            pnum_gpio0_hfxt => hfxt_ren, -- GPIO0 pin 5
            pnum_gpio0_lfxt => lfxt_ren, -- GPIO0 pin 4
            pnum_gpio0_spi_clk => sck_flash_ren, -- GPIO0 pin 3
            pnum_gpio0_mosi => mosi_flash_ren, -- GPIO0 pin 2
            pnum_gpio0_miso => miso_flash_ren, -- GPIO0 pin 1
            pnum_gpio0_cs_flash => cs_flash_ren -- GPIO0 pin 0

        );

    -- GPIO1 Connections (SPI1, UART0, UART1) ---------------------------------------
        cs1_in   <= prt2_in(pnum_gpio1_cs1);
        miso1_in <= prt2_in(pnum_gpio1_miso1);
        mosi1_in <= prt2_in(pnum_gpio1_mosi1);
        sck1_in  <= prt2_in(pnum_gpio1_sck1);
        sck1_ren_in <= p2_ren(pnum_gpio1_sck1);
        mosi1_ren_in <= p2_ren(pnum_gpio1_mosi1);
        miso1_ren_in <= p2_ren(pnum_gpio1_miso1);
        -- cs1_ren_in <= p2_ren(pnum_gpio1_cs1);

        -- GPIO1 Connections (UART0)
        tx0_ren_in <= p2_ren(pnum_gpio1_tx0);
        rx0_ren_in <= p2_ren(pnum_gpio1_rx0);
        rx0_in <= prt2_in(pnum_gpio1_rx0);

        -- GPIO1 Connections (UART1)
        tx1_ren_in <= p2_ren(pnum_gpio1_tx1);
        rx1_ren_in <= p2_ren(pnum_gpio1_rx1);
        rx1_in <= prt2_in(pnum_gpio1_rx1);


        afunc2_out <= (
            pnum_gpio1_rx1 => rx1_out,      -- GPIO1 pin 7
            pnum_gpio1_tx1 => tx1_out,      -- GPIO1 pin 6
            pnum_gpio1_rx0 => rx0_out,      -- GPIO1 pin 5
            pnum_gpio1_tx0 => tx0_out,      -- GPIO1 pin 4
            pnum_gpio1_sck1 => sck1_out,    -- GPIO1 pin 3
            pnum_gpio1_mosi1 => mosi1_out,  -- GPIO1 pin 2
            pnum_gpio1_miso1 => miso1_out,  -- GPIO1 pin 1
            0 => p2_out(0)                  -- CS1 line manually toggled with GPIO1
        );
        afunc2_dir <= (
            pnum_gpio1_rx1 => rx1_dir,      -- GPIO1 pin 7
            pnum_gpio1_tx1 => tx1_dir,      -- GPIO1 pin 6
            pnum_gpio1_rx0 => rx0_dir,      -- GPIO1 pin 5
            pnum_gpio1_tx0 => tx0_dir,      -- GPIO1 pin 4
            pnum_gpio1_sck1 => sck1_dir,    -- GPIO1 pin 3
            pnum_gpio1_mosi1 => mosi1_dir,  -- GPIO1 pin 2
            pnum_gpio1_miso1 => miso1_dir,  -- GPIO1 pin 1
            0 => p2_dir(0)
        );
        afunc2_ren <= (
            pnum_gpio1_rx1 => rx1_ren,      -- GPIO1 pin 7
            pnum_gpio1_tx1 => tx1_ren,      -- GPIO1 pin 6
            pnum_gpio1_rx0 => rx0_ren,      -- GPIO1 pin 5
            pnum_gpio1_tx0 => tx0_ren,      -- GPIO1 pin 4
            pnum_gpio1_sck1 => sck1_ren,    -- GPIO1 pin 3
            pnum_gpio1_mosi1 => mosi1_ren,  -- GPIO1 pin 2
            pnum_gpio1_miso1 => miso1_ren,  -- GPIO1 pin 1
            0 => p2_ren(0)
        );

    -- GPIO2 Connections (TIMER0, TIMER1) -------------------------------------------------
        t0_cmp0_ren_in  <= p3_ren(pnum_gpio2_t0_cmp0);
        t0_cmp1_ren_in  <= p3_ren(pnum_gpio2_t0_cmp1);
        t0_cap0_in      <= prt3_in(pnum_gpio2_t0_cap0);
        t0_cap1_in      <= prt3_in(pnum_gpio2_t0_cap1);
        t1_cmp0_ren_in  <= p3_ren(pnum_gpio2_t1_cmp0);
        t1_cmp1_ren_in  <= p3_ren(pnum_gpio2_t1_cmp1);
        t1_cap0_in      <= prt3_in(pnum_gpio2_t1_cap0);
        t1_cap1_in      <= prt3_in(pnum_gpio2_t1_cap1);
        t0_cap0_ren_in  <= p3_ren(pnum_gpio2_t0_cap0);
        t1_cap0_ren_in  <= p3_ren(pnum_gpio2_t1_cap0);
        t0_cap1_ren_in  <= p3_ren(pnum_gpio2_t0_cap1);
        t1_cap1_ren_in  <= p3_ren(pnum_gpio2_t1_cap1);
        

        afunc3_out <= (
            pnum_gpio2_t1_cap1 => t1_cap1_out,                  -- GPIO2 pin 7
            pnum_gpio2_t1_cap0 => p3_out(pnum_gpio2_t1_cap0),   -- GPIO2 pin 6
            pnum_gpio2_t1_cmp1 => t1_cmp1_out,                  -- GPIO2 pin 5
            pnum_gpio2_t1_cmp0 => t1_cmp0_out,                  -- GPIO2 pin 4
            pnum_gpio2_t0_cap1 => t0_cap1_out,                  -- GPIO2 pin 3
            pnum_gpio2_t0_cap0 => p3_out(pnum_gpio2_t0_cap0),   -- GPIO2 pin 2
            pnum_gpio2_t0_cmp1 => t0_cmp1_out,                  -- GPIO2 pin 1
            pnum_gpio2_t0_cmp0 => t0_cmp0_out                   -- GPIO2 pin 0
        );
        afunc3_dir <= (
            pnum_gpio2_t1_cap1 => t1_cap1_dir, -- GPIO2 pin 7
            pnum_gpio2_t1_cap0 => t1_cap0_dir, -- GPIO2 pin 6
            pnum_gpio2_t1_cmp1 => t1_cmp1_dir, -- GPIO2 pin 5
            pnum_gpio2_t1_cmp0 => t1_cmp0_dir, -- GPIO2 pin 4
            pnum_gpio2_t0_cap1 => t0_cap1_dir, -- GPIO2 pin 3
            pnum_gpio2_t0_cap0 => t0_cap0_dir, -- GPIO2 pin 2
            pnum_gpio2_t0_cmp1 => t0_cmp1_dir, -- GPIO2 pin 1
            pnum_gpio2_t0_cmp0 => t0_cmp0_dir  -- GPIO2 pin 0
        );
        afunc3_ren <= (
            pnum_gpio2_t1_cap1 => t1_cap1_ren, -- GPIO2 pin 7
            pnum_gpio2_t1_cap0 => t1_cap0_ren, -- GPIO2 pin 6
            pnum_gpio2_t1_cmp1 => t1_cmp1_ren, -- GPIO2 pin 5
            pnum_gpio2_t1_cmp0 => t1_cmp0_ren, -- GPIO2 pin 4
            pnum_gpio2_t0_cap1 => t0_cap1_ren, -- GPIO2 pin 3
            pnum_gpio2_t0_cap0 => t0_cap0_ren, -- GPIO2 pin 2
            pnum_gpio2_t0_cmp1 => t0_cmp1_ren, -- GPIO2 pin 1
            pnum_gpio2_t0_cmp0 => t0_cmp0_ren  -- GPIO2 pin 0
        );



    -- GPIO3 Connections (I2C0, I2C1, DTP) ------------------------------------------------------------

        dtp0_ren_in <= p4_ren(pnum_gpio3_dtp0);
        dtp1_ren_in <= p4_ren(pnum_gpio3_dtp1);
        dtp2_ren_in <= p4_ren(pnum_gpio3_dtp2);
        dtp3_ren_in <= p4_ren(pnum_gpio3_dtp3);
        sda0_ren_in <= p4_ren(pnum_gpio3_sda0);
        scl0_ren_in <= p4_ren(pnum_gpio3_scl0);
        sda1_ren_in <= p4_ren(pnum_gpio3_sda1);
        scl1_ren_in <= p4_ren(pnum_gpio3_scl1);

        afunc4_out <= (
            pnum_gpio3_dtp3     => dtp3_out,  -- GPIO3 pin 7
            pnum_gpio3_dtp2     => dtp2_out,  -- GPIO3 pin 6
            pnum_gpio3_dtp1     => dtp1_out,  -- GPIO3 pin 5
            pnum_gpio3_dtp0     => dtp0_out,  -- GPIO3 pin 4
            pnum_gpio3_scl1     => scl1_out,  -- GPIO3 pin 3
            pnum_gpio3_sda1     => sda1_out,  -- GPIO3 pin 2
            pnum_gpio3_scl0     => scl0_out,  -- GPIO3 pin 1
            pnum_gpio3_sda0     => sda0_out   -- GPIO3 pin 0
        );
        afunc4_dir <= (
            pnum_gpio3_dtp3 => dtp3_dir,      -- GPIO3 pin 7
            pnum_gpio3_dtp2 => dtp2_dir,      -- GPIO3 pin 6
            pnum_gpio3_dtp1 => dtp1_dir,      -- GPIO3 pin 5
            pnum_gpio3_dtp0 => dtp0_dir,      -- GPIO3 pin 4
            pnum_gpio3_scl1 => scl1_dir,      -- GPIO3 pin 3
            pnum_gpio3_sda1 => sda1_dir,      -- GPIO3 pin 2
            pnum_gpio3_scl0 => scl0_dir,      -- GPIO3 pin 1
            pnum_gpio3_sda0 => sda0_dir       -- GPIO3 pin 0
        );
        afunc4_ren <= (
            pnum_gpio3_dtp3 => dtp3_ren,      -- GPIO3 pin 7
            pnum_gpio3_dtp2 => dtp2_ren,      -- GPIO3 pin 6
            pnum_gpio3_dtp1 => dtp1_ren,      -- GPIO3 pin 5
            pnum_gpio3_dtp0 => dtp0_ren,      -- GPIO3 pin 4
            pnum_gpio3_scl1 => scl1_ren,      -- GPIO3 pin 3
            pnum_gpio3_sda1 => sda1_ren,      -- GPIO3 pin 2
            pnum_gpio3_scl0 => scl0_ren,      -- GPIO3 pin 1
            pnum_gpio3_sda0 => sda0_ren       -- GPIO3 pin 0
        );


    -- =============================================================================
    -- IRQ Signal Assignments
    -- =============================================================================
        irq_comb <= (
            IRQB_SYS_WDT    => irq_sys_wdt,
            IRQB_GPIO0_B0   => irq_gpio0(0),
            IRQB_GPIO0_B1   => irq_gpio0(1),
            IRQB_GPIO0_B2   => irq_gpio0(2),
            IRQB_GPIO0_B3   => irq_gpio0(3),
            IRQB_GPIO0_B4   => irq_gpio0(4),
            IRQB_GPIO0_B5   => irq_gpio0(5),
            IRQB_GPIO0_B6   => irq_gpio0(6),
            IRQB_GPIO0_B7   => irq_gpio0(7),
            IRQB_SPI0_TC    => irq_spi0_tc,
            IRQB_SPI0_TE    => irq_spi0_te,
            IRQB_SPI1_TC    => irq_spi1_tc,
            IRQB_SPI1_TE    => irq_spi1_te,
            IRQB_UART0_RC   => irq_uart0_rc,
            IRQB_UART0_TE   => irq_uart0_te,
            IRQB_UART0_TC   => irq_uart0_tc,
            IRQB_TIM0_CAP0  => irq_tim0_cap0,
            IRQB_TIM0_CAP1  => irq_tim0_cap1,
            IRQB_TIM0_OVF   => irq_tim0_ovf,
            IRQB_TIM0_CMP0  => irq_tim0_cmp0,
            IRQB_TIM0_CMP1  => irq_tim0_cmp1,
            IRQB_TIM0_CMP2  => irq_tim0_cmp2,
            IRQB_TIM1_CAP0  => irq_tim1_cap0,
            IRQB_TIM1_CAP1  => irq_tim1_cap1,
            IRQB_TIM1_OVF   => irq_tim1_ovf,
            IRQB_TIM1_CMP0  => irq_tim1_cmp0,
            IRQB_TIM1_CMP1  => irq_tim1_cmp1,
            IRQB_TIM1_CMP2  => irq_tim1_cmp2,
            IRQB_GPIO1_B0   => irq_gpio1(0),
            IRQB_GPIO1_B1   => irq_gpio1(1),
            IRQB_GPIO1_B2   => irq_gpio1(2),
            IRQB_GPIO1_B3   => irq_gpio1(3),
            IRQB_GPIO1_B4   => irq_gpio1(4),
            IRQB_GPIO1_B5   => irq_gpio1(5),
            IRQB_GPIO1_B6   => irq_gpio1(6),
            IRQB_GPIO1_B7   => irq_gpio1(7),
            IRQB_GPIO2_B0   => irq_gpio2(0),
            IRQB_GPIO2_B1   => irq_gpio2(1),
            IRQB_GPIO2_B2   => irq_gpio2(2),
            IRQB_GPIO2_B3   => irq_gpio2(3),
            IRQB_GPIO2_B4   => irq_gpio2(4),
            IRQB_GPIO2_B5   => irq_gpio2(5),
            IRQB_GPIO2_B6   => irq_gpio2(6),
            IRQB_GPIO2_B7   => irq_gpio2(7),
            IRQB_GPIO3_B0   => irq_gpio3(0),
            IRQB_GPIO3_B1   => irq_gpio3(1),
            IRQB_GPIO3_B2   => irq_gpio3(2),
            IRQB_GPIO3_B3   => irq_gpio3(3),
            IRQB_GPIO3_B4   => irq_gpio3(4),
            IRQB_GPIO3_B5   => irq_gpio3(5),
            IRQB_GPIO3_B6   => irq_gpio3(6),
            IRQB_GPIO3_B7   => irq_gpio3(7),
            IRQB_UART1_RC   => irq_uart1_rc,
            IRQB_UART1_TE   => irq_uart1_te,
            IRQB_UART1_TC   => irq_uart1_tc,
            IRQB_AFE0_RC    => irq_afe0_rc,
            IRQB_SAR0_RC    => irq_sar0_rc,
            IRQB_I2C0_STR   => irq_i2c0_str,
            IRQB_I2C0_spr   => irq_i2c0_spr,
            IRQB_I2C0_msts  => irq_i2c0_msts,
            IRQB_I2C0_msps  => irq_i2c0_msps,
            IRQB_I2C0_marb  => irq_i2c0_marb,
            IRQB_I2C0_mtxe  => irq_i2c0_mtxe,
            IRQB_I2C0_mnr   => irq_i2c0_mnr,
            IRQB_I2C0_mxc   => irq_i2c0_mxc,
            IRQB_I2C0_sa    => irq_i2c0_sa,
            IRQB_I2C0_stxe  => irq_i2c0_stxe,
            IRQB_I2C0_sovf  => irq_i2c0_sovf,
            IRQB_I2C0_snr   => irq_i2c0_snr,
            IRQB_I2C0_sxc   => irq_i2c0_sxc,
            IRQB_I2C1_STR   => irq_i2c1_str,
            IRQB_I2C1_spr   => irq_i2c1_spr,
            IRQB_I2C1_msts  => irq_i2c1_msts,
            IRQB_I2C1_msps  => irq_i2c1_msps,
            IRQB_I2C1_marb  => irq_i2c1_marb,
            IRQB_I2C1_mtxe  => irq_i2c1_mtxe,
            IRQB_I2C1_mnr   => irq_i2c1_mnr,
            IRQB_I2C1_mxc   => irq_i2c1_mxc,
            IRQB_I2C1_sa    => irq_i2c1_sa,
            IRQB_I2C1_stxe  => irq_i2c1_stxe,
            IRQB_I2C1_sovf  => irq_i2c1_sovf,
            IRQB_I2C1_snr   => irq_i2c1_snr,
            IRQB_I2C1_sxc   => irq_i2c1_sxc,
            others          => irq_tielow
        );



    -- =============================================================================
    -- Component Instantiations
    -- =============================================================================
    sleep_cpu <= npu0_active or flash_ext_meming; -- Sleep when either NPU is active or external flash memory access is occurring
    core: vesta 
        generic map (
            PC_RST_VAL     => x"00000000",
            NUM_IRQS       => NUM_IRQS 
        )
        port map (
            clk         => mclk,
            resetn      => resetn,
            sleep       => sleep_cpu,
            clk_cpu     => clk_cpu,

            data_addr    => data_addr, 
            wen          => wen_re,
            write_data   => write_word,
            read_data    => read_data,
            mask         => mask, 

            irq_vector   => irq_deglitch,
            irq_priority => irq_priority,
            irq_recursion_en => irq_recursion_en,
            irq_en       => irq_en,
            isr_ret      => isr_ret,

            trap_flag    => trap_out,

            a0           => a0

    );

    -- System Peripheral 
    system0: SYSTEM
        generic map (
            NUM_IRQS => NUM_IRQS 
        )
        port map (
            clk_lfxt_in   => lfxt_in,
            clk_hfxt_in   => hfxt_in,
            clk_dco0_in   => clk_osc_dco0,
            clk_dco1_in   => clk_osc_dco1,

            resetn_in      => resetn_in,
            resetn_por     => resetn_por,
            resetn_sys     => resetn, 

            irq           => irq_deglitch,
            isr_ret       => isr_ret,
            irq_en        => irq_en,
            irq_priority  => irq_priority,
            irq_recursion_en => irq_recursion_en,
            irq_sys_wdt   => irq_sys_wdt,

            clk_mem       => clk_periph(PeriphSlotSystem0),
            en_mem        => mem_en_periph(PeriphSlotSystem0),
            wen           => wen_fe,
            addr_periph   => addr_periph,
            write_data    => write_data,
            read_data     => periph_dout(PeriphSlotSystem0),

            mclk_out      => mclk,
            smclk_out     => smclk,
            clk_lfxt_out  => clk_lfxt,
            clk_hfxt_out  => clk_hfxt,

            en_dco0_out   => en_dco0,
            DCO0_BIAS     => DCO0_BIAS,

            en_dco1_out   => en_dco1,
            DCO1_BIAS     => DCO1_BIAS,

            PGEN_mem      => pgen_mem
    );


    adddec0: adddec
        generic map (
            ENABLE_FLASH_EXTENDED_MEM => true
        )
        port map (
            clk             => clk_cpu,
            resetn          => resetn,

            wen             => wen_re,
            data_addr       => data_addr,
            write_word      => write_word,
            mask            => mask,
        
            write_data      => write_data,
            read_data       => read_data,
            mem_addr        => mem_addr, 
            addr_periph     => addr_periph(7 downto 2),
            mab_out         => mab_flash, 
            wen_fe          => wen_fe,
            GWEN            => GWEN,

            mem_en          => mem_en,
            mem_en_periph   => mem_en_periph,
            clk_mem         => clk_mem,
            clk_periph      => clk_periph,

            mem_en_flash    => mem_en_flash,
            clk_mem_flash   => clk_mem_flash,

            mem_dout       => mem_dout,
            periph_dout    => periph_dout,
            flash_dout     => flash_dout   
    );

    -- GPIO0 (SPI0, CLKLFXT, CLKHFXT, TRAP, BOOT)
    gpio0: GPIO
        generic map (
            num_pins        => 8,
            PadOUTPosLogic  => true, -- Configured such that setting PxOUT to '1' will drive the output of the pad HIGH
            PadDIRPosLogic  => false, -- Configured such that setting PxDIR to '1' will set the pad to OUTPUT mode
            PadRENPosLogic  => false, -- Configured such that setting PxREN to '1' will enable the pad pullup/pulldown resistor
            RstValPxOUT     => RstValP1OUT,
            RstValPxDIR     => RstValP1DIR, 
            RstValPxSEL		=> RstValP1SEL,
            RstValPxREN     => RstValP1REN
        )
        port map (
            resetn           => resetn, 
            irq              => irq_gpio0,

            clk_mem         => clk_periph(PeriphSlotGPIO0), 
            en              => mem_en_periph(PeriphSlotGPIO0), 
            wen             => wen_fe, 
            write_data      => write_data, 
            read_data       => periph_dout(PeriphSlotGPIO0), 
            addr_periph     => addr_periph, 

            prt_in          => prt1_in,
            prt_out_out     => prt1_out,
            prt_dir_out     => prt1_dir,
            prt_ren_out     => prt1_ren, 

            -- Register Outputs
            PxOUT_out		=> p1_out,
            PxDIR_out		=> p1_dir,
            PxREN_out		=> p1_ren,

            alt_func_out_in	=>	afunc1_out,
            alt_func_dir_in	=>	afunc1_dir,
            alt_func_ren_in	=>	afunc1_ren	
    );

    -- GPIO1 (SPI1, UART0, UART1)
    gpio1: GPIO 
        generic map (
            num_pins        => 8,
            PadOUTPosLogic  => true, -- Configured such that setting PxOUT to '1' will drive the output of the pad HIGH
            PadDIRPosLogic  => false, -- Configured such that setting PxDIR to '1' will set the pad to OUTPUT mode
            PadRENPosLogic  => false, -- Configured such that setting PxREN to '1' will enable the pad pullup/pulldown resistor
            RstValPxOUT     => RstValP2OUT,
            RstValPxDIR     => RstValP2DIR,  -- Pins default to output
            RstValPxSEL		=> RstValP2SEL,
            RstValPxREN     => RstValP2REN
        )
        port map (
            resetn           => resetn,
            irq              => irq_gpio1,

            clk_mem         => clk_periph(PeriphSlotGPIO1), 
            en              => mem_en_periph(PeriphSlotGPIO1), 
            wen             => wen_fe, 
            write_data      => write_data, 
            read_data       => periph_dout(PeriphSlotGPIO1), 
            addr_periph     => addr_periph, 

            prt_in          => prt2_in,
            prt_out_out     => prt2_out,
            prt_dir_out     => prt2_dir,
            prt_ren_out     => prt2_ren,

            -- Register Outputs
            PxOUT_out		=> p2_out,
            PxDIR_out		=> p2_dir,
            PxREN_out		=> p2_ren,

            alt_func_out_in	=>	afunc2_out,
            alt_func_dir_in	=>	afunc2_dir,
            alt_func_ren_in	=>	afunc2_ren	
    );

    -- GPIO2 (TIMER0, TIMER1)
    gpio2: GPIO 
        generic map (
            num_pins        => 8,
            PadOUTPosLogic  => true, -- Configured such that setting PxOUT to '1' will drive the output of the pad HIGH
            PadDIRPosLogic  => false, -- Configured such that setting PxDIR to '1' will set the pad to OUTPUT mode
            PadRENPosLogic  => false, -- Configured such that setting PxREN to '1' will enable the pad pullup/pulldown resistor
            RstValPxOUT     => RstValP3OUT,
            RstValPxDIR     => RstValP3DIR,  -- Pins default to output
            RstValPxSEL		=> RstValP3SEL,
            RstValPxREN     => RstValP3REN
        )
        port map (
            resetn           => resetn, 
            irq              => irq_gpio2,

            clk_mem         => clk_periph(PeriphSlotGPIO2), 
            en              => mem_en_periph(PeriphSlotGPIO2), 
            wen             => wen_fe, 
            write_data      => write_data, 
            read_data       => periph_dout(PeriphSlotGPIO2), 
            addr_periph     => addr_periph, 

            prt_in          => prt3_in,
            prt_out_out     => prt3_out,
            prt_dir_out     => prt3_dir,
            prt_ren_out     => prt3_ren,

            -- Register Outputs
            PxOUT_out		=> p3_out,
            PxDIR_out		=> p3_dir,
            PxREN_out		=> p3_ren,

            alt_func_out_in	=>	afunc3_out,
            alt_func_dir_in	=>	afunc3_dir,
            alt_func_ren_in	=>	afunc3_ren	
    );

    -- GPIO3 (I2C0, I2C1, DTP)
    gpio3: GPIO 
        generic map (
            num_pins        => 8,
            PadOUTPosLogic  => true, -- Configured such that setting PxOUT to '1' will drive the output of the pad HIGH
            PadDIRPosLogic  => false, -- Configured such that setting PxDIR to '1' will set the pad to OUTPUT mode
            PadRENPosLogic  => false, -- Configured such that setting PxREN to '1' will enable the pad pullup/pulldown resistor
            RstValPxOUT     => RstValP4OUT,
            RstValPxDIR     => RstValP4DIR,  -- Pins default to output
            RstValPxSEL		=> RstValP4SEL,
            RstValPxREN     => RstValP4REN
        )
        port map (
            resetn          => resetn, 
            irq             => irq_gpio3,

            clk_mem         => clk_periph(PeriphSlotGPIO3),
            en              => mem_en_periph(PeriphSlotGPIO3),
            wen             => wen_fe, 
            write_data      => write_data, 
            read_data       => periph_dout(PeriphSlotGPIO3), 
            addr_periph     => addr_periph, 

            prt_in          => prt4_in,
            prt_out_out     => prt4_out,
            prt_dir_out     => prt4_dir,
            prt_ren_out     => prt4_ren,

            -- Register Outputs
            PxOUT_out		=> p4_out,
            PxDIR_out		=> p4_dir,
            PxREN_out		=> p4_ren,

            alt_func_out_in	=>	afunc4_out,
            alt_func_dir_in	=>	afunc4_dir,
            alt_func_ren_in	=>	afunc4_ren	
    );

    spi0: SPI
        generic map (
            ENABLE_EXTENDED_MEM => true
        )
        port map (
            clk             => smclk,
            mclk            => mclk,
            resetn          => resetn,
            irq_tc          => irq_spi0_tc,
            irq_te          => irq_spi0_te,

            clk_mem         => clk_periph(PeriphSlotSPI0),
            en_mem          => mem_en_periph(PeriphSlotSPI0),
            wen             => wen_fe,
            write_data      => write_data,
            read_data       => periph_dout(PeriphSlotSPI0),
            addr_periph     => addr_periph,

            cs_in       => cs_flash_in,

            sck_in      => sck_flash_in,
            sck_out     => sck_flash_out,
            sck_dir     => sck_flash_dir,
            sck_ren     => sck_flash_ren,
            sck_ren_in  => sck_flash_ren_in,

            mosi_in     => mosi_flash_in,
            mosi_out    => mosi_flash_out,
            mosi_dir    => mosi_flash_dir,
            mosi_ren    => mosi_flash_ren,
            mosi_ren_in => mosi_flash_ren_in,

            miso_in     => miso_flash_in,
            miso_out    => miso_flash_out,
            miso_dir    => miso_flash_dir,
            miso_ren    => miso_flash_ren,
            miso_ren_in => miso_flash_ren_in,

            en_mem_flash    => mem_en_flash,
            clk_mem_flash   => clk_mem_flash,
            mab             => mab_flash,
            rdata_flash      => flash_dout,
            disable_clk_cpu => flash_ext_meming,

            cs_flash_out   => cs_flash_out,
            cs_flash_dir   => cs_flash_dir,
            cs_flash_ren   => cs_flash_ren


        );

    spi1: SPI
        generic map (
            ENABLE_EXTENDED_MEM => false
        )
        port map (

            clk             => smclk,
            mclk            => mclk,
            resetn          => resetn,
            irq_tc          => irq_spi1_tc,
            irq_te          => irq_spi1_te,

            clk_mem         => clk_periph(PeriphSlotSPI1),
            en_mem          => mem_en_periph(PeriphSlotSPI1),
            wen             => wen_fe,
            write_data      => write_data,
            read_data       => periph_dout(PeriphSlotSPI1),
            addr_periph     => addr_periph,

            cs_in       => cs1_in,

            sck_in      => sck1_in,
            sck_out     => sck1_out,
            sck_dir     => sck1_dir,
            sck_ren     => sck1_ren,
            sck_ren_in  => sck1_ren_in,

            mosi_in     => mosi1_in,
            mosi_out    => mosi1_out,
            mosi_dir    => mosi1_dir,
            mosi_ren    => mosi1_ren,
            mosi_ren_in => mosi1_ren_in,

            miso_in     => miso1_in,
            miso_out    => miso1_out,
            miso_dir    => miso1_dir,
            miso_ren    => miso1_ren,
            miso_ren_in => miso1_ren_in, 

            en_mem_flash    => '1', 
            clk_mem_flash   => '1',
            mab             => (others => '1'),
            rdata_flash     => open,
            disable_clk_cpu => open,
            
            cs_flash_out   => open,
            cs_flash_dir   => open,
            cs_flash_ren   => open

    );

    uart0: UART
        port map (
            -- System Signals
            clk         => smclk,
            resetn       => resetn,
            
            -- Interrupt Signals
            irq_rc       => irq_uart0_rc,
            irq_te       => irq_uart0_te,
            irq_tc       => irq_uart0_tc,

            -- Memory Bus
            clk_mem     => clk_periph(PeriphSlotUART0), 
            en_mem      => mem_en_periph(PeriphSlotUART0),
            wen         => wen_fe,
            addr_periph => addr_periph,
            write_data  => write_data,
            read_data   => periph_dout(PeriphSlotUART0),

            -- Pad Interface
            TX_OUT      => tx0_out,
            TX_DIR      => tx0_dir,
            TX_REN      => tx0_ren,

            RX_IN       => rx0_in,
            RX_OUT      => rx0_out,
            RX_DIR      => rx0_dir,
            RX_REN      => rx0_ren
    );

    uart1: UART
        port map (
            -- System Signals
            clk         => smclk,
            resetn       => resetn,

            -- Interrupt Signals
            irq_rc       => irq_uart1_rc,
            irq_te       => irq_uart1_te,
            irq_tc       => irq_uart1_tc,

            -- Memory Bus
            clk_mem     => clk_periph(PeriphSlotUART1), 
            en_mem      => mem_en_periph(PeriphSlotUART1),
            wen         => wen_fe,
            addr_periph => addr_periph,
            write_data  => write_data,
            read_data   => periph_dout(PeriphSlotUART1),

            -- Pad Interface
            TX_OUT      => tx1_out,
            TX_DIR      => tx1_dir,
            TX_REN      => tx1_ren,

            RX_IN       => rx1_in,
            RX_OUT      => rx1_out,
            RX_DIR      => rx1_dir,
            RX_REN      => rx1_ren
    );

    i2c0: I2C
        port map
        (
            -- System Signals
            smclk			=> smclk,	
            resetn			=> resetn,	

            irq_str			=> irq_i2c0_str,
            irq_spr			=> irq_i2c0_spr,
            irq_msts		=> irq_i2c0_msts,
            irq_msps		=> irq_i2c0_msps,
            irq_marb		=> irq_i2c0_marb,
            irq_mtxe		=> irq_i2c0_mtxe,
            irq_mnr			=> irq_i2c0_mnr,
            irq_mxc			=> irq_i2c0_mxc,
            irq_sa			=> irq_i2c0_sa,
            irq_stxe		=> irq_i2c0_stxe,
            irq_sovf		=> irq_i2c0_sovf,
            irq_snr			=> irq_i2c0_snr,
            irq_sxc			=> irq_i2c0_sxc,
            
            -- Memory Bus
            ClkMem			=> clk_periph(PeriphSlotI2C0),
            EnMemPeriph		=> mem_en_periph(PeriphSlotI2C0),
            WEn				=> wen_fe,
            MABPart			=> addr_periph,
            wdata			=> write_data,
            rdata_out		=> periph_dout(PeriphSlotI2C0),
            
            -- Pin Inputs/Outputs
            SCL_IN			=> scl0_in,
            SCL_OUT			=> scl0_out,
            SCL_DIR			=> scl0_dir,
            SCL_REN_in		=> scl0_ren_in,
            SCL_REN			=> scl0_ren,
            
            SDA_IN			=> sda0_in,
            SDA_OUT			=> sda0_out,
            SDA_DIR			=> sda0_dir,
            SDA_REN_in		=> sda0_ren_in,
            SDA_REN			=> sda0_ren
	);

    i2c1: I2C
        port map
        (
            -- System Signals
            smclk			=> smclk,	
            resetn			=> resetn,	

            irq_str			=> irq_i2c1_str,
            irq_spr			=> irq_i2c1_spr,
            irq_msts		=> irq_i2c1_msts,
            irq_msps		=> irq_i2c1_msps,
            irq_marb		=> irq_i2c1_marb,
            irq_mtxe		=> irq_i2c1_mtxe,
            irq_mnr			=> irq_i2c1_mnr,
            irq_mxc			=> irq_i2c1_mxc,
            irq_sa			=> irq_i2c1_sa,
            irq_stxe		=> irq_i2c1_stxe,
            irq_sovf		=> irq_i2c1_sovf,
            irq_snr			=> irq_i2c1_snr,
            irq_sxc			=> irq_i2c1_sxc,
            
            -- Memory Bus
            ClkMem			=> clk_periph(PeriphSlotI2C1),
            EnMemPeriph		=> mem_en_periph(PeriphSlotI2C1),
            WEn				=> wen_fe,
            MABPart			=> addr_periph,
            wdata			=> write_data,
            rdata_out		=> periph_dout(PeriphSlotI2C1),

            -- Pin Inputs/Outputs
            SCL_IN			=> scl1_in,
            SCL_OUT			=> scl1_out,
            SCL_DIR			=> scl1_dir,
            SCL_REN_in		=> scl1_ren_in,
            SCL_REN			=> scl1_ren,
            
            SDA_IN			=> sda1_in,
            SDA_OUT			=> sda1_out,
            SDA_DIR			=> sda1_dir,
            SDA_REN_in		=> sda1_ren_in,
            SDA_REN			=> sda1_ren
	);

    timer0 : TIMER
        port map (
            -- System Signals
            mclk         => mclk,
            smclk        => smclk,
            clk_lfxt     => clk_lfxt,
            clk_hfxt     => clk_hfxt,
            resetn       => resetn,

            -- IRQ Signals  
            irq_cap0     => irq_tim0_cap0,
            irq_cap1     => irq_tim0_cap1,
            irq_ovf      => irq_tim0_ovf,
            irq_cmp0     => irq_tim0_cmp0,
            irq_cmp1     => irq_tim0_cmp1,
            irq_cmp2     => irq_tim0_cmp2,

            -- Memory Bus
            clk_mem      => clk_periph(PeriphSlotTIMER0),
            en_mem       => mem_en_periph(PeriphSlotTIMER0),
            wen          => wen_fe,
            addr_periph  => addr_periph,
            write_data   => write_data,
            read_data    => periph_dout(PeriphSlotTIMER0),

            -- Pad Interface
            cmp0_ren_in  => t0_cmp0_ren_in,
            cmp0_out     => t0_cmp0_out,
            cmp0_dir     => t0_cmp0_dir,
            cmp0_ren     => t0_cmp0_ren,

            cmp1_ren_in  => t0_cmp1_ren_in,
            cmp1_out     => t0_cmp1_out,
            cmp1_dir     => t0_cmp1_dir,
            cmp1_ren     => t0_cmp1_ren,

            cap0_ren_in  => t0_cap0_ren_in,
            cap0_ren     => t0_cap0_ren,
            cap0_dir     => t0_cap0_dir,
            cap0_in      => t0_cap0_in,

            cap1_ren_in  => t0_cap1_ren_in,
            cap1_ren     => t0_cap1_ren,
            cap1_dir     => t0_cap1_dir,
            cap1_in      => t0_cap1_in
    );

    timer1 : TIMER
        port map (
            -- System Signals
            mclk         => mclk,
            smclk        => smclk,
            clk_lfxt     => clk_lfxt,
            clk_hfxt     => clk_hfxt,
            resetn       => resetn,

            -- IRQ Signals  
            irq_cap0     => irq_tim1_cap0,
            irq_cap1     => irq_tim1_cap1,
            irq_ovf      => irq_tim1_ovf,
            irq_cmp0     => irq_tim1_cmp0,
            irq_cmp1     => irq_tim1_cmp1,
            irq_cmp2     => irq_tim1_cmp2,

            -- Memory Bus
            clk_mem      => clk_periph(PeriphSlotTIMER1),
            en_mem       => mem_en_periph(PeriphSlotTIMER1),
            wen          => wen_fe,
            addr_periph  => addr_periph,
            write_data   => write_data,
            read_data    => periph_dout(PeriphSlotTIMER1),

            -- Pad Interface
            cmp0_ren_in  => t1_cmp0_ren_in,
            cmp0_out     => t1_cmp0_out,
            cmp0_dir     => t1_cmp0_dir,
            cmp0_ren     => t1_cmp0_ren,

            cmp1_ren_in  => t1_cmp1_ren_in,
            cmp1_out     => t1_cmp1_out,
            cmp1_dir     => t1_cmp1_dir,
            cmp1_ren     => t1_cmp1_ren,

            cap0_ren_in  => t1_cap0_ren_in,
            cap0_ren     => t1_cap0_ren,
            cap0_dir     => t1_cap0_dir,
            cap0_in      => t1_cap0_in,

            cap1_ren_in  => t1_cap1_ren_in,
            cap1_ren     => t1_cap1_ren,
            cap1_dir     => t1_cap1_dir,
            cap1_in      => t1_cap1_in
    );

    npu0: entity work.NPU
        generic map(
            X_M_BITS => 0,
            W_M_BITS => 7,
            Y_M_BITS => 7,
            N_BITS   => 24,
            RHO      => 2
        )
        port map (
            -- System Signals
            clk         => mclk,  
            resetn      => resetn,

            -- Memory Bus Signals 
            MabMmrA     => addr_periph(3 downto 2), 
            MabMmrD     => write_data,
            MabMmrCLK   => clk_periph(PeriphSlotNPU0),
            MabMmrCEN   => '0',
            MabMmrWEN   => wen_fe,
            MabMmrQ     => periph_dout(PeriphSlotNPU0),

            -- MUXed SRAM Inputs (connect directly to address decoder outputs)
            SramQ_in      => mem_dout(2),
            SramA_in      => mem_addr,
            SramD_in      => write_data,
            SramCLK_in    => clk_mem(2),
            SramCEN_in    => mem_en(2),
            SramGWEN_in   => GWEN,
            SramWEN_in    => wen_fe,

            -- SRAM Interface (connect directly to SRAM blocks without going through address decoder)
            NpuSramA_out    => npu0_mux_ram_a,
            NpuSramD_out    => npu0_mux_ram_d,
            NpuSramCLK_out  => npu0_mux_ram_clk,
            NpuSramCEN_out  => npu0_mux_ram_cen,
            NpuSramGWEN_out => npu0_mux_ram_gwen,
            NpuSramWEN_out  => npu0_mux_wen,

            NpuActive       => npu0_active -- Make irq
    );

    afe0: entity work.AFE
        port map (
            clk         => smclk,
            resetn      => resetn,
            irq         => irq_afe0_rc, 

            clk_mem     => clk_periph(PeriphSlotAFE0),
            en_mem      => mem_en_periph(PeriphSlotAFE0),
            wen         => wen_fe, 
            addr_periph => addr_periph,
            write_data  => write_data,
            read_data   => periph_dout(PeriphSlotAFE0),

            dtp0_ren_in  => dtp0_ren_in,
            dtp0_ren     => dtp0_ren,
            dtp0_dir     => dtp0_dir,
            dtp0_out     => dtp0_out,

            dtp1_ren_in  => dtp1_ren_in,
            dtp1_ren     => dtp1_ren,
            dtp1_dir     => dtp1_dir,
            dtp1_out     => dtp1_out,

            dtp2_ren_in  => dtp2_ren_in,
            dtp2_ren     => dtp2_ren,
            dtp2_dir     => dtp2_dir,
            dtp2_out     => dtp2_out,

            dtp3_ren_in  => dtp3_ren_in,
            dtp3_ren     => dtp3_ren,
            dtp3_dir     => dtp3_dir,
            dtp3_out     => dtp3_out,

            --Bias Signals 
            use_bias_dac => use_dac_glb_bias,
            en_bias_buf  => en_bias_buf,
            en_bias_gen  => en_bias_gen,

            -- Central Bias Generator
            BIAS_ADJ    => BIAS_ADJ,
            BIAS_DBP    => BIAS_DBP,
            BIAS_DBN    => BIAS_DBN,
            BIAS_DBPC   => BIAS_DBPC,
            BIAS_DBNC   => BIAS_DBNC,

            -- TIA Biases
            BIAS_TC_POT     => BIAS_TC_POT,
            BIAS_LC_POT     => BIAS_LC_POT,
            BIAS_TIA_G_POT  => BIAS_TIA_G_POT,
            BIAS_REV_POT    => BIAS_REV_POT,

            -- DSADC Biases
            BIAS_TC_DSADC  => BIAS_TC_DSADC,
            BIAS_LC_DSADC  => BIAS_LC_DSADC,
            BIAS_RIN_DSADC => BIAS_RIN_DSADC,
            BIAS_RFB_DSADC => BIAS_RFB_DSADC,
            BIAS_DSADC_VCM => BIAS_DSADC_VCM,

            -- DSADC Output Signals 
            adc_conv_done   => dsadc_conv_done,
            adc_en          => dsadc_en,
            adc_clk         => dsadc_clk,
            adc_switch      => dsadc_switch,
            adc_ext_in      => adc_ext_in,  -- '1' => adc's input is from potentiostat pad, '0' => external signal
            atp_en          => atp_en,      -- '1' => ATP is enabled, '0' => ATP is disabled
            atp_sel         => atp_sel,     -- '1' => ATP to use is DSADC, '0' => ATP is Potentiostat
            adc_sel         => adc_sel,     -- '1' => adc to use is SARADC, '0' => adc input is from DSADC
            dac_en          => dac_en_pot
        );

    saradc0: entity work.SARADC
        port map (
            clk         => smclk,
            resetn      => resetn,

            irq         => irq_sar0_rc,

            clk_mem     => clk_periph(PeriphSlotSARADC0),
            en_mem      => mem_en_periph(PeriphSlotSARADC0),
            wen         => wen_fe,
            addr_periph => addr_periph,
            write_data  => write_data,
            read_data   => periph_dout(PeriphSlotSARADC0),

            dtp0         => t0_cap1_out, -- Alternate Function as DTP
            dtp1         => t1_cap1_out, -- Alternate Function as DTP

            ADC_ready_i     => saradc_rdy,
            ADC_data_i      => saradc_data,
            ADC_reset       => saradc_rst,
            ADC_trigger_clock_o =>saradc_clk
    );

    -- =============================================================================
    -- Memory Blocks
    -- =============================================================================
    rom0: entity work.rom_hvt_pg
        port map (
            Q    => mem_dout(0),
            CLK  => clk_mem(0),
            CEN  => mem_en(0),
            A    => mem_addr, 
            EMA  => "000",
            PGEN => pgen_mem(0)
    );


    ram0: entity work.sram1p16k_hvt_pg
        port map (
            Q     => mem_dout(1),
            CLK   => clk_mem(1),
            CEN   => mem_en(1),
            WEN   => wen_fe,
            A     => mem_addr,
            D     => write_data,
            EMA   => "000",
            GWEN  => GWEN,
            RETN  => '1',
            PGEN  => pgen_mem(1)
    );

    -- NPU SRAM Interface
    ram1: entity work.sram1p16k_hvt_pg
        port map (
            Q     => mem_dout(2),
            CLK   => npu0_mux_ram_clk,
            CEN   => npu0_mux_ram_cen,
            WEN   => npu0_mux_wen,
            A     => npu0_mux_ram_a,
            D     => npu0_mux_ram_d,
            EMA   => "000",
            GWEN  => npu0_mux_ram_gwen,
            RETN  => '1',
            PGEN  => pgen_mem(2)
    );


    -- =============================================================================
    -- Abstract Blocks 
    -- =============================================================================

    -- Power-on resetn Circuit
	por: entity work.PowerOnResetCheng
        port map
        (
            resetn_in	=> resetn_in,
            resetn_out	=> resetn_por
	);

    -- Glitch Filter for IRQ signals
    irq_gf0 : entity work.GlitchFilter
        port map
        (
            IrqGlitchy		=> irq_comb(31 downto 0),
            IrqDeglitched	=> gf_out(31 downto 0)
	);
    irq_gf1 : entity work.GlitchFilter
        port map
        (
            IrqGlitchy		=> irq_comb(63 downto 32),
            IrqDeglitched	=> gf_out(63 downto 32)
	);
    irq_gf2 : entity work.GlitchFilter
        port map
        (
            IrqGlitchy		=> irq_comb(95 downto 64),
            IrqDeglitched	=> gf_out(95 downto 64)
	);
    irq_deglitch <= gf_out(NUM_IRQS-1 downto 0);

    -- This tie-low cell is instantiated because, for some reason, Genus won't route tie cells to any of the analog blocks, instead directly connecting the pins to VSS (or VDD)
	-- This tie-low cell buries a constant 0 one level down in the hierarchy, which tricks Genus into using an actual tie-low cell from the standard cell library and connecting it to all the constant '0' inputs to the glitch filter
	-- WARNING: The fan-out for the tie cell should be checked
	IrqGlitchyZeroTieLow: entity work.TieLow
	port map
	(
		Zero	=> irq_tielow
	);



    -- Current Starved Oscillators for MCLK and SMCLK
    reset_dco <= not resetn_por;  -- DCO reset is active high
	dco0: entity work.OscillatorCurrentStarved
	port map
	(
		Reset	=> reset_dco,
		En		=> en_dco0,
		Freq	=> DCO0_BIAS,
		ClkOut	=> clk_osc_dco0
	);

	dco1: entity work.OscillatorCurrentStarved
	port map
	(
		Reset	=> reset_dco,
		En		=> en_dco1,
		Freq	=> DCO1_BIAS,
		ClkOut	=> clk_osc_dco1
	);


end architecture behav;



