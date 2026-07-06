-- MCU.vhd
-- Castalia MCU top-level integration layer (4 harts, MCU_MP)
-- Golden-master templated from the verified hdl/MCU_MP/MCU.vhd: the fixed
-- 	boilerplate comes from hdl_templates/MCU.template.vhd; the description-
-- 	driven sections are generated from python/generate.py
-- Generated on 2026/07/06 at 15:29:25 with the generate.py chip generator
-- WARNING: Do not edit or modify this file!
-- 	Edit hdl_templates/MCU.template.vhd (fixed regions) or python/generate.py
-- 	+ python/mcu_vhd.py (generated regions), then re-run make chip

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

        --GPIO3 Connections (I2C0, I2C1, DTPs)
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
        a0  : out std_logic_vector(31 downto 0);

        -- M3b: per-hart pass/fail observation (a0 of the 3 private-memory harts)
        a0_1 : out std_logic_vector(31 downto 0);
        a0_2 : out std_logic_vector(31 downto 0);
        a0_3 : out std_logic_vector(31 downto 0)

    );
end entity;

architecture behav of MCU is

    -- M13 TILE EXTRACTION: the vesta core, its adddec and its private TCM no
    -- longer appear inline here — hart 0 is now the SAME hart_tile entity as
    -- harts 1-3 (hdl/MCU_MP/hart_tile.vhd), and the four tile instances are
    -- STRUCTURALLY IDENTICAL (one netlist -> one hardened tile in M14).
    -- Every per-instance difference is wiring only: hart_id (mhartid port),
    -- hart 0's flash/XIP + sleep hookup to SPI0, the IRQ enable/priority
    -- source (SYSTEM0 on hart 0, irq_router row + hardwired CLINT slots on
    -- tiles) and the TCM PGEN (BLOCKPWR on hart 0). The vesta and adddec
    -- component declarations went with the inline hart-0 machinery.

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
        generic (
            default_SAD	: std_logic_vector(6 downto 0) := (others => '0')	-- The default slave address for this I2C peripheral
        );
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
        -- M13: clk_cpu / boot_fetched / resetn_core and the M2 wait-injector
        -- back-pressure (core_mem_ready) are tile-internal now; wait_inj0 is
        -- RETIRED (M10 proved the protocol's latency tolerance, the M12 boot
        -- fetch exercises it every run).

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


        -- M13: the RISCV core interface signals (read_data/write_word/
        -- data_addr/wen_*) moved into hart_tile with the core.

        -- M3c.2: shared window behind mp_arbiter on mclk. M5b widened SH_AW
        -- 8 -> 12 (whole pre-M11 region 4). M11 memory-map rework: SH_AW
        -- 12 -> 15 — the arbiter word address now covers ALL of
        -- 0x00000-0x1FFFF (word addr = data_addr(16:2)) and the slave
        -- sub-decode selects on s_addr(14:12):
        --   000 = boot ROM 0x0-0x3FFF (M12: THE shared boot ROM — one
        --         rom_hvt_pg, read-only slave; all four harts reset here)
        --   001 = peripheral window 0x4000-0x7FFF (page 0 = 16 x 256B slots
        --         at the LEGACY slot numbering, page 1 = CLINT @0x5000,
        --         page 2 = MUTEX bank @0x6000, page 3 = IRQ router @0x7000)
        --   010 = dead (TCM region — tile-private, never arrives here)
        --   011 = NPU staging RAM 0xC000-0xFFFF (one sram1p16k, NPU-muxed)
        --   1xx = shared bulk RAM 0x10000-0x1FFFF (4 x sram1p16k banks,
        --         bank = s_addr(13:12))
        constant SH_AW : natural := 15;                -- shared-window word-address width
        -- M13: the hart-0 master-side handshake state (sh_sel/sh_acked/
        -- sh_rdata_reg/sh_rdata_cpu/...) moved into hart_tile — all four
        -- masters now carry identical tile-internal copies of it.
        -- M4b: global LR/SC reservation unit
        signal arb_lrsc         : std_logic_vector(4*2-1 downto 0);
        signal arb_scfail       : std_logic_vector(3 downto 0);
        signal sh_we_raw        : std_logic_vector(3 downto 0);  -- arbiter s_we, pre resv gating
        -- arbiter master buses (master 0 = hart 0; masters 1-3 = hart tiles).
        -- we = 4 active-high byte-lane strobes per master (M4a).
        signal arb_req, arb_gnt, arb_done : std_logic_vector(3 downto 0);
        -- M8: per-master grant-lock (cores' amo_lock) — pins the arbiter to a
        -- master across its AMO read+write transaction pair (cross-hart AMO
        -- atomicity).
        signal arb_lock         : std_logic_vector(3 downto 0);
        signal arb_we           : std_logic_vector(4*4-1 downto 0);
        signal arb_addr         : std_logic_vector(4*SH_AW-1 downto 0);
        signal arb_wdata        : std_logic_vector(4*32-1 downto 0);
        signal arb_rdata        : std_logic_vector(31 downto 0);
        -- arbiter <-> shared slave side (RAM + CLINT sub-decoded below, M5b)
        signal sh_en            : std_logic;
        signal sh_we            : std_logic_vector(3 downto 0);
        signal sh_addr          : std_logic_vector(SH_AW-1 downto 0);
        signal sh_wdata         : std_logic_vector(31 downto 0);
        -- M11 slave fabric: page select on s_addr(14:12) (see the SH_AW
        -- comment above for the map). The peripheral window sub-decodes on
        -- s_addr(11:10) into 4 pages; page 0 = 16 x 256B slots at the LEGACY
        -- 0x4000 slot numbering (slot = s_addr(9:6)) — every peripheral is
        -- back at its original Myshkin address, now shared by all 4 harts.
        signal shslv_rom_sel    : std_logic;   -- 000 -> shared boot ROM 0x0-0x3FFF (M12)
        signal shslv_perwin_sel : std_logic;   -- 001 -> peripheral window 0x4000-0x7FFF
        signal shslv_pg0_sel    : std_logic;   -- window page 0 -> the 16 slots
        signal shslv_npuram_sel : std_logic;   -- 011 -> NPU staging RAM 0xC000-0xFFFF
        signal shslv_bank0_sel  : std_logic;   -- 100 -> bulk RAM bank 0 (0x10000)
        signal shslv_bank1_sel  : std_logic;   -- 101 -> bulk RAM bank 1 (0x14000)
        signal shslv_bank2_sel  : std_logic;   -- 110 -> bulk RAM bank 2 (0x18000)
        signal shslv_bank3_sel  : std_logic;   -- 111 -> bulk RAM bank 3 (0x1C000)
        signal shslv_rom_en     : std_logic;
        signal shslv_npuram_en  : std_logic;
        signal shslv_bank0_en   : std_logic;
        signal shslv_bank1_en   : std_logic;
        signal shslv_bank2_en   : std_logic;
        signal shslv_bank3_en   : std_logic;
        signal shslv_rd_rom     : std_logic := '0'; -- registered: last access was the boot ROM
        signal shslv_rd_npuram  : std_logic := '0'; -- registered: last access was the NPU RAM
        signal shslv_rd_bank0   : std_logic := '0';
        signal shslv_rd_bank1   : std_logic := '0';
        signal shslv_rd_bank2   : std_logic := '0';
        signal shslv_rd_bank3   : std_logic := '0';
        -- boot ROM + bulk RAM banks + NPU staging RAM are hard macros: their
        -- Q is the 1-cycle registered read the arbiter's slave model
        -- expects, so the macro output IS the rdata (no extra register).
        -- Enables/WEN are ACTIVE-LOW at the macro — shims below.
        signal rom_q            : std_logic_vector(31 downto 0);
        signal bank0_q          : std_logic_vector(31 downto 0);
        signal bank1_q          : std_logic_vector(31 downto 0);
        signal bank2_q          : std_logic_vector(31 downto 0);
        signal bank3_q          : std_logic_vector(31 downto 0);
        signal npuram_q         : std_logic_vector(31 downto 0);
        signal rom_cen_n        : std_logic;
        signal npuram_cen_n     : std_logic;
        signal bank0_cen_n      : std_logic;
        signal bank1_cen_n      : std_logic;
        signal bank2_cen_n      : std_logic;
        signal bank3_cen_n      : std_logic;
        signal shmem_gwen_n     : std_logic;   -- shared-macro global write enable (active-low)
        -- M5b: real CLINT (M11: peripheral-window page 1 @0x5000)
        signal shslv_clint_sel  : std_logic;
        signal shslv_clint_en   : std_logic;
        signal shslv_rd_clint   : std_logic := '0'; -- registered: last access was CLINT
        signal sh_rdata_mux     : std_logic_vector(31 downto 0); -- into arbiter s_rdata
        signal clint_rdata      : std_logic_vector(31 downto 0);
        signal clint_msip       : std_logic_vector(3 downto 0);
        signal clint_mtip       : std_logic_vector(3 downto 0);
        -- M6: shared UART0 (console) — M11: window slot 4 @0x4400 (its
        -- ORIGINAL private address, live again for all 4 harts)
        signal shslv_uart0_sel  : std_logic;
        signal shslv_uart0_en   : std_logic;
        signal shslv_rd_uart0   : std_logic := '0'; -- registered: last access was UART0
        signal uart0_sh_en_n    : std_logic;   -- UART bus is active-LOW en/wen
        signal sh_wen_n   : std_logic_vector(3 downto 0);
        signal uart0_sh_rdata   : std_logic_vector(31 downto 0);
        -- M7a: irq_router, the tile IRQ fan-out (M11: window page 3 @0x7000)
        signal shslv_irtr_sel   : std_logic;
        signal shslv_irtr_en    : std_logic;
        signal shslv_rd_irtr    : std_logic := '0'; -- registered: last access was irq_router
        signal irtr_rdata       : std_logic_vector(31 downto 0);
        signal tile_irq_en_flat : std_logic_vector(4*NUM_IRQS-1 downto 0);
        -- M7b movers: TIMER0/1 + GPIO1/2/3 (M11: window slots 6/7/1/8/13)
        signal shslv_tim0_sel,  shslv_tim0_en   : std_logic;
        signal shslv_tim1_sel,  shslv_tim1_en   : std_logic;
        signal shslv_gpio1_sel, shslv_gpio1_en  : std_logic;
        signal shslv_gpio2_sel, shslv_gpio2_en  : std_logic;
        signal shslv_gpio3_sel, shslv_gpio3_en  : std_logic;
        signal shslv_rd_tim0    : std_logic := '0';
        signal shslv_rd_tim1    : std_logic := '0';
        signal shslv_rd_gpio1   : std_logic := '0';
        signal shslv_rd_gpio2   : std_logic := '0';
        signal shslv_rd_gpio3   : std_logic := '0';
        signal tim0_sh_en_n     : std_logic;   -- periph buses are active-LOW en/wen
        signal tim1_sh_en_n     : std_logic;
        signal gpio1_sh_en_n    : std_logic;
        signal gpio2_sh_en_n    : std_logic;
        signal gpio3_sh_en_n    : std_logic;
        signal tim0_sh_rdata    : std_logic_vector(31 downto 0);
        signal tim1_sh_rdata    : std_logic_vector(31 downto 0);
        signal gpio1_sh_rdata   : std_logic_vector(31 downto 0);
        signal gpio2_sh_rdata   : std_logic_vector(31 downto 0);
        signal gpio3_sh_rdata   : std_logic_vector(31 downto 0);
        -- M7c movers: SPI1 + UART1 (M11: window slots 3/5)
        signal shslv_spi1_sel,  shslv_spi1_en   : std_logic;
        signal shslv_uart1_sel, shslv_uart1_en  : std_logic;
        signal shslv_rd_spi1    : std_logic := '0';
        signal shslv_rd_uart1   : std_logic := '0';
        signal spi1_sh_en_n     : std_logic;
        signal uart1_sh_en_n    : std_logic;
        signal spi1_sh_rdata    : std_logic_vector(31 downto 0);
        signal uart1_sh_rdata   : std_logic_vector(31 downto 0);
        -- M7c.2 movers: I2C0/I2C1 (M11: window slots 14/15). I2C's register
        -- READ is COMBINATIONAL (rdata_out collapses to register 0 the moment
        -- EnMemPeriph deasserts), so the bridge REGISTERS it at the
        -- LATCH->DATA edge (i2c*_sh_rdata below) — reproducing exactly the
        -- old adddec timing the I2C.vhd comment assumes ("EnMemPeriph has a
        -- leading edge exactly one clock cycle before rdata latches").
        signal shslv_i2c0_sel,  shslv_i2c0_en   : std_logic;
        signal shslv_i2c1_sel,  shslv_i2c1_en   : std_logic;
        signal shslv_rd_i2c0    : std_logic := '0';
        signal shslv_rd_i2c1    : std_logic := '0';
        signal i2c0_sh_en_n     : std_logic;
        signal i2c1_sh_en_n     : std_logic;
        signal i2c0_sh_rdata_c  : std_logic_vector(31 downto 0); -- combinational, from the instance
        signal i2c1_sh_rdata_c  : std_logic_vector(31 downto 0);
        signal i2c0_sh_rdata    : std_logic_vector(31 downto 0) := (others => '0'); -- bridge-registered
        signal i2c1_sh_rdata    : std_logic_vector(31 downto 0) := (others => '0');
        -- M7d mover: NPU register bus (M11: window slot 10 @0x4A00). Its MMR
        -- read is COMBINATIONAL like I2C's -> same bridge register. The NPU's
        -- DATA now lives in the shared NPU staging RAM at 0xC000 (bank above)
        -- — the SRAM-port mux is fed by the slave fabric, and hart 0 no
        -- longer sleeps during THINK (the staging RAM is not its private
        -- memory any more; "don't touch 0xC000-0xFFFF during a THINK" is a
        -- software contract, poll NPUCR bit 16).
        signal shslv_npu_sel,   shslv_npu_en    : std_logic;
        signal shslv_rd_npu     : std_logic := '0';
        signal npu_sh_en_n      : std_logic;
        signal npu_sh_rdata_c   : std_logic_vector(31 downto 0); -- combinational, from the instance
        signal npu_sh_rdata     : std_logic_vector(31 downto 0) := (others => '0'); -- bridge-registered
        -- M11 movers: the last five private peripherals join the window —
        -- SYSTEM0 (slot 9 @0x4900), GPIO0 (slot 0 @0x4000), SPI0 (slot 2
        -- @0x4200), SARADC0 (slot 11 @0x4B00), AFE0 (slot 12 @0x4C00). All
        -- five register their reads on clk_mem (M11 audit) -> plain polarity
        -- shims, no bridge. The private peripheral page is GONE — hart 0's
        -- adddec no longer decodes region 001 at all. NOTE the SYSTEM0
        -- clock-reconfig contract: SYS_CLK_CR/SYS_CLK_DIV_CR reconfigure
        -- MCLK ITSELF; reconfiguring while other masters have in-flight
        -- shared transactions is a SOFTWARE contract violation (management
        -- hart quiesces the others first — the glitch-free muxes keep the
        -- domain safe, but smclk-domain peripherals mid-frame are not).
        signal shslv_sys_sel,   shslv_sys_en    : std_logic;
        signal shslv_gpio0_sel, shslv_gpio0_en  : std_logic;
        signal shslv_spi0_sel,  shslv_spi0_en   : std_logic;
        signal shslv_sar_sel,   shslv_sar_en    : std_logic;
        signal shslv_afe_sel,   shslv_afe_en    : std_logic;
        signal shslv_rd_sys     : std_logic := '0';
        signal shslv_rd_gpio0   : std_logic := '0';
        signal shslv_rd_spi0    : std_logic := '0';
        signal shslv_rd_sar     : std_logic := '0';
        signal shslv_rd_afe     : std_logic := '0';
        signal sys_sh_en_n      : std_logic;
        signal gpio0_sh_en_n    : std_logic;
        signal spi0_sh_en_n     : std_logic;
        signal sar_sh_en_n      : std_logic;
        signal afe_sh_en_n      : std_logic;
        signal sys_sh_rdata     : std_logic_vector(31 downto 0);
        signal gpio0_sh_rdata   : std_logic_vector(31 downto 0);
        signal spi0_sh_rdata    : std_logic_vector(31 downto 0);
        signal sar_sh_rdata     : std_logic_vector(31 downto 0);
        signal afe_sh_rdata     : std_logic_vector(31 downto 0);
        -- M7c LOCKING: HW mutex bank (M11: window page 2 @0x6000). READ =
        -- atomic return-old-and-claim, WRITE 0 = release; atomic because the
        -- arbiter serializes whole transactions. sh_master is the arbiter's
        -- granted-master index (mp_arbiter s_master port) — attributes the
        -- claim-read to a hart. Registered read, resv-gated we (contract).
        signal shslv_mtx_sel,   shslv_mtx_en    : std_logic;
        signal shslv_rd_mtx     : std_logic := '0';
        signal mtx_rdata        : std_logic_vector(31 downto 0);
        signal sh_master        : std_logic_vector(1 downto 0);
        -- signal inst_retired     : std_logic; -- Instruction Retired Signal from Core
        -- signal mem_access       : std_logic; -- High when memory access is occurring

        -- Memory and RAM Control Signals
        -- (M13: hart 0's adddec<->TCM bus moved into hart_tile; pgen_mem
        -- stays — SYSTEM0's BLOCKPWR gates rom0 (0), hart 0's TCM via the
        -- tile's tcm_pgen port (1) and npuram0 (2).)
        signal RAM_Dout         : std_logic_vector(31 downto 0);
        signal pgen_mem         : std_logic_vector(2 downto 0);

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

        -- Resistor Enables
        dtp0_ren_in <= p4_ren(pnum_gpio3_dtp0);
        dtp1_ren_in <= p4_ren(pnum_gpio3_dtp1);
        dtp2_ren_in <= p4_ren(pnum_gpio3_dtp2);
        dtp3_ren_in <= p4_ren(pnum_gpio3_dtp3);
        sda0_ren_in <= p4_ren(pnum_gpio3_sda0);
        scl0_ren_in <= p4_ren(pnum_gpio3_scl0);
        sda1_ren_in <= p4_ren(pnum_gpio3_sda1);
        scl1_ren_in <= p4_ren(pnum_gpio3_scl1);

        -- Inputs
        sda0_in <= prt4_in(pnum_gpio3_sda0);
        scl0_in <= prt4_in(pnum_gpio3_scl0);
        sda1_in <= prt4_in(pnum_gpio3_sda1);
        scl1_in <= prt4_in(pnum_gpio3_scl1);

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
            -- M5b: hart 0's CLINT levels (harts 1-3 get theirs via tile ports)
            IRQB_CLINT_MSIP => clint_msip(0),
            IRQB_CLINT_MTIP => clint_mtip(0),
            others          => irq_tielow
        );



    -- =============================================================================
    -- Component Instantiations
    -- =============================================================================
    -- M11: npu0_active no longer sleeps hart 0 — the NPU's vectors live in
    -- the SHARED staging RAM at 0xC000 (an arbiter slave), not in hart 0's
    -- private RAM1 (retired). The sleep existed to keep hart 0's un-stallable
    -- private RAM1 accesses from colliding with the NPU's port mux; shared
    -- accesses have arbiter back-pressure and "no 0xC000-0xFFFF access during
    -- a THINK" is the software contract (poll NPUCR bit 16, shnpu.S).
    sleep_cpu <= flash_ext_meming; -- Sleep while an external flash memory access is occurring

    -- =========================================================================
    -- M13 TILE EXTRACTION: hart 0 is the SAME hart_tile as harts 1-3 — the
    -- inline core/adddec/TCM/shared-window machinery that used to live here
    -- (and that hart_tile mirrored since M3c) is folded into the tile. The
    -- M12 wait-for-boot-fetch reset release, the M4b/M10 qualified ack, the
    -- M10 clk_cpu-staged consumption register and the M9b nop-force all
    -- live in hart_tile.vhd now — see the rationale there. Hart 0's
    -- remaining specials are pure WIRING on the identical tile:
    --   * sleep + flash ports -> SPI0 (XIP; tiles have no SPI0 behind them),
    --   * irq_en_ext/irq_prio_ext/irq_recursion_en/isr_ret -> SYSTEM0
    --     (hw_clint_en='0': SYS_IRQ_EN's reset-all-masked semantics kept;
    --     tiles hardwire CLINT slots 83/84 instead and take the router row),
    --   * tcm_pgen -> pgen_mem(1) (BLOCKPWR RAM gating),
    --   * trap_flag -> the GPIO0 trap pin; a0 -> the tb pass/fail gate.
    -- The M2 wait_inj0 stall exerciser is RETIRED (M10 proved latency
    -- insensitivity at boundary depths 0/1/2; the boot fetch through the
    -- arbiter exercises the stall path on every run).
    -- =========================================================================
    hart0: entity work.hart_tile
        generic map (
            PC_RST_VAL     => x"00000000",
            SH_AW          => SH_AW
        )
        port map (
            clk       => mclk,
            resetn    => resetn,
            sleep     => sleep_cpu,
            hart_id   => x"00000000",
            msip_in   => clint_msip(0),
            mtip_in   => clint_mtip(0),
            irq_ext    => irq_deglitch,
            irq_en_ext => irq_en,
            irq_prio_ext     => irq_priority,
            irq_recursion_en => irq_recursion_en,
            isr_ret          => isr_ret,
            hw_clint_en      => '0',
            flash_mem_en  => mem_en_flash,
            flash_clk_mem => clk_mem_flash,
            flash_mab     => mab_flash,
            flash_dout    => flash_dout,
            sh_req    => arb_req(0),
            sh_we     => arb_we(3 downto 0),
            sh_addr   => arb_addr(SH_AW-1 downto 0),
            sh_wdata  => arb_wdata(31 downto 0),
            sh_gnt    => arb_gnt(0),
            sh_done   => arb_done(0),
            sh_rdata  => arb_rdata,
            sh_lrsc   => arb_lrsc(1 downto 0),
            sh_scfail => arb_scfail(0),
            sh_lock   => arb_lock(0),
            tcm_pgen  => pgen_mem(1),
            trap_flag => trap_out,
            a0        => a0
        );

    mp_arb0: entity work.mp_arbiter
        generic map (N => 4, ADDR_WIDTH => SH_AW, DATA_WIDTH => 32)
        port map (
            clk    => mclk,
            resetn => resetn,
            req    => arb_req,
            we     => arb_we,
            addr   => arb_addr,
            wdata  => arb_wdata,
            lock   => arb_lock,   -- M8: grant-locking (AMO RMW atomicity)
            gnt    => arb_gnt,
            done   => arb_done,
            rdata  => arb_rdata,
            s_en    => sh_en,
            s_master => sh_master,
            s_we    => sh_we_raw,
            s_addr  => sh_addr,
            s_wdata => sh_wdata,
            s_rdata => sh_rdata_mux
        );

    -- M4b: global LR/SC reservation unit — snoops every granted shared txn,
    -- places reservations on LR reads, kills them on writes, adjudicates SC
    -- writes IN THE ARBITER'S SERIALIZATION ORDER (a dead SC's write is
    -- suppressed via sh_we and its fail verdict returns with done). This is
    -- what makes cross-hart LR/SC sound: two harts SC-ing the same word both
    -- pass their core-LOCAL checks, and only this unit can order them.
    resv0: entity work.resv_unit
        generic map (N => 4, ADDR_WIDTH => SH_AW)
        port map (
            clk        => mclk,
            resetn     => resetn,
            lr_sc      => arb_lrsc,
            gnt        => arb_gnt,
            s_en       => sh_en,
            s_we       => sh_we_raw,
            s_addr     => sh_addr,
            s_we_gated => sh_we,
            sc_fail    => arb_scfail
        );

    -- =========================================================================
    -- M5b/M11/M12: slave-side sub-decode of the shared window. The arbiter
    -- serializes ALL masters onto ONE slave port; the 15-bit word address
    -- then selects which physical slave this transaction hits (s_addr(14:12)
    -- pages, see the SH_AW comment):
    --   0x00000-0x03FFF -> THE shared boot ROM (M12: one rom_hvt_pg,
    --                      read-only — writes complete but are discarded)
    --   0x04000-0x07FFF -> peripheral window: page 0 = 16 x 256B slots at
    --                      the LEGACY slot numbering (every peripheral back
    --                      at its Myshkin address, shared by all 4 harts),
    --                      page 1 = CLINT, page 2 = MUTEX, page 3 = router
    --   0x0C000-0x0FFFF -> NPU staging RAM (sram1p16k, NPU-port-muxed)
    --   0x10000-0x1FFFF -> bulk RAM banks 0-3 (4 x sram1p16k)
    --   everything else -> no slave (reads return 0)
    -- Every slave obeys the same 1-cycle registered-read contract (the SRAM
    -- macros natively; peripherals via their clk_mem-registered reads), so
    -- the arbiter's IDLE->LATCH->DATA timing is untouched; the shslv_rd_*
    -- selects are registered at the access cycle and steer s_rdata during
    -- DATA. resv_unit still snoops every transaction (its s_we_gated drives
    -- ALL slaves: a suppressed SC write must not touch a peripheral either).
    -- =========================================================================
    -- M11/M12: page select on s_addr(14:12). Page 000 is the shared boot
    -- ROM (M12 — the single rom_hvt_pg all four harts reset into);
    -- 010 is the TCM region (tile-private, never arrives here).
    shslv_rom_sel    <= '1' when sh_addr(14 downto 12) = "000" else '0';
    shslv_perwin_sel <= '1' when sh_addr(14 downto 12) = "001" else '0';
    shslv_npuram_sel <= '1' when sh_addr(14 downto 12) = "011" else '0';
    shslv_bank0_sel  <= '1' when sh_addr(14 downto 12) = "100" else '0';
    shslv_bank1_sel  <= '1' when sh_addr(14 downto 12) = "101" else '0';
    shslv_bank2_sel  <= '1' when sh_addr(14 downto 12) = "110" else '0';
    shslv_bank3_sel  <= '1' when sh_addr(14 downto 12) = "111" else '0';
    -- peripheral-window pages on sh_addr(11:10): page 0 = the 16 slots,
    -- page 1 = CLINT, page 2 = MUTEX bank, page 3 = IRQ router
    shslv_pg0_sel    <= shslv_perwin_sel when sh_addr(11 downto 10) = "00" else '0';
    shslv_clint_sel  <= shslv_perwin_sel when sh_addr(11 downto 10) = "01" else '0';
    shslv_mtx_sel    <= shslv_perwin_sel when sh_addr(11 downto 10) = "10" else '0';
    shslv_irtr_sel   <= shslv_perwin_sel when sh_addr(11 downto 10) = "11" else '0';
    -- page-0 slots (slot = sh_addr(9:6)) at the LEGACY 0x4000 numbering —
    -- every peripheral back at its original Myshkin address, shared by
    -- all 4 harts
    shslv_gpio0_sel  <= shslv_pg0_sel when sh_addr(9 downto 6) = "0000" else '0';
    shslv_gpio1_sel  <= shslv_pg0_sel when sh_addr(9 downto 6) = "0001" else '0';
    shslv_spi0_sel   <= shslv_pg0_sel when sh_addr(9 downto 6) = "0010" else '0';
    shslv_spi1_sel   <= shslv_pg0_sel when sh_addr(9 downto 6) = "0011" else '0';
    shslv_uart0_sel  <= shslv_pg0_sel when sh_addr(9 downto 6) = "0100" else '0';
    shslv_uart1_sel  <= shslv_pg0_sel when sh_addr(9 downto 6) = "0101" else '0';
    shslv_tim0_sel   <= shslv_pg0_sel when sh_addr(9 downto 6) = "0110" else '0';
    shslv_tim1_sel   <= shslv_pg0_sel when sh_addr(9 downto 6) = "0111" else '0';
    shslv_gpio2_sel  <= shslv_pg0_sel when sh_addr(9 downto 6) = "1000" else '0';
    shslv_sys_sel    <= shslv_pg0_sel when sh_addr(9 downto 6) = "1001" else '0';
    shslv_npu_sel    <= shslv_pg0_sel when sh_addr(9 downto 6) = "1010" else '0';
    shslv_sar_sel    <= shslv_pg0_sel when sh_addr(9 downto 6) = "1011" else '0';
    shslv_afe_sel    <= shslv_pg0_sel when sh_addr(9 downto 6) = "1100" else '0';
    shslv_gpio3_sel  <= shslv_pg0_sel when sh_addr(9 downto 6) = "1101" else '0';
    shslv_i2c0_sel   <= shslv_pg0_sel when sh_addr(9 downto 6) = "1110" else '0';
    shslv_i2c1_sel   <= shslv_pg0_sel when sh_addr(9 downto 6) = "1111" else '0';
    shslv_rom_en     <= sh_en and shslv_rom_sel;
    shslv_npuram_en  <= sh_en and shslv_npuram_sel;
    shslv_bank0_en   <= sh_en and shslv_bank0_sel;
    shslv_bank1_en   <= sh_en and shslv_bank1_sel;
    shslv_bank2_en   <= sh_en and shslv_bank2_sel;
    shslv_bank3_en   <= sh_en and shslv_bank3_sel;
    shslv_clint_en   <= sh_en and shslv_clint_sel;
    shslv_mtx_en     <= sh_en and shslv_mtx_sel;
    shslv_irtr_en    <= sh_en and shslv_irtr_sel;
    shslv_gpio0_en   <= sh_en and shslv_gpio0_sel;
    shslv_gpio1_en   <= sh_en and shslv_gpio1_sel;
    shslv_spi0_en    <= sh_en and shslv_spi0_sel;
    shslv_spi1_en    <= sh_en and shslv_spi1_sel;
    shslv_uart0_en   <= sh_en and shslv_uart0_sel;
    shslv_uart1_en   <= sh_en and shslv_uart1_sel;
    shslv_tim0_en    <= sh_en and shslv_tim0_sel;
    shslv_tim1_en    <= sh_en and shslv_tim1_sel;
    shslv_gpio2_en   <= sh_en and shslv_gpio2_sel;
    shslv_sys_en     <= sh_en and shslv_sys_sel;
    shslv_npu_en     <= sh_en and shslv_npu_sel;
    shslv_sar_en     <= sh_en and shslv_sar_sel;
    shslv_afe_en     <= sh_en and shslv_afe_sel;
    shslv_gpio3_en   <= sh_en and shslv_gpio3_sel;
    shslv_i2c0_en    <= sh_en and shslv_i2c0_sel;
    shslv_i2c1_en    <= sh_en and shslv_i2c1_sel;

    shslv_rd_sel: process(mclk, resetn)
    begin
        if resetn = '0' then
            shslv_rd_rom     <= '0';
            shslv_rd_npuram  <= '0';
            shslv_rd_bank0   <= '0';
            shslv_rd_bank1   <= '0';
            shslv_rd_bank2   <= '0';
            shslv_rd_bank3   <= '0';
            shslv_rd_clint   <= '0';
            shslv_rd_mtx     <= '0';
            shslv_rd_irtr    <= '0';
            shslv_rd_gpio0   <= '0';
            shslv_rd_gpio1   <= '0';
            shslv_rd_spi0    <= '0';
            shslv_rd_spi1    <= '0';
            shslv_rd_uart0   <= '0';
            shslv_rd_uart1   <= '0';
            shslv_rd_tim0    <= '0';
            shslv_rd_tim1    <= '0';
            shslv_rd_gpio2   <= '0';
            shslv_rd_sys     <= '0';
            shslv_rd_npu     <= '0';
            shslv_rd_sar     <= '0';
            shslv_rd_afe     <= '0';
            shslv_rd_gpio3   <= '0';
            shslv_rd_i2c0    <= '0';
            shslv_rd_i2c1    <= '0';
        elsif rising_edge(mclk) then
            if sh_en = '1' then
                shslv_rd_rom     <= shslv_rom_sel;
                shslv_rd_npuram  <= shslv_npuram_sel;
                shslv_rd_bank0   <= shslv_bank0_sel;
                shslv_rd_bank1   <= shslv_bank1_sel;
                shslv_rd_bank2   <= shslv_bank2_sel;
                shslv_rd_bank3   <= shslv_bank3_sel;
                shslv_rd_clint   <= shslv_clint_sel;
                shslv_rd_mtx     <= shslv_mtx_sel;
                shslv_rd_irtr    <= shslv_irtr_sel;
                shslv_rd_gpio0   <= shslv_gpio0_sel;
                shslv_rd_gpio1   <= shslv_gpio1_sel;
                shslv_rd_spi0    <= shslv_spi0_sel;
                shslv_rd_spi1    <= shslv_spi1_sel;
                shslv_rd_uart0   <= shslv_uart0_sel;
                shslv_rd_uart1   <= shslv_uart1_sel;
                shslv_rd_tim0    <= shslv_tim0_sel;
                shslv_rd_tim1    <= shslv_tim1_sel;
                shslv_rd_gpio2   <= shslv_gpio2_sel;
                shslv_rd_sys     <= shslv_sys_sel;
                shslv_rd_npu     <= shslv_npu_sel;
                shslv_rd_sar     <= shslv_sar_sel;
                shslv_rd_afe     <= shslv_afe_sel;
                shslv_rd_gpio3   <= shslv_gpio3_sel;
                shslv_rd_i2c0    <= shslv_i2c0_sel;
                shslv_rd_i2c1    <= shslv_i2c1_sel;
            end if;
        end if;
    end process;

    -- M7c.2: I2C read-bridge registers — capture the I2C's COMBINATIONAL
    -- rdata at the LATCH->DATA edge (while its one-cycle en strobe is high
    -- and MABPart still selects the addressed register), so the arbiter's
    -- end-of-DATA capture sees the right value. Every other slave registers
    -- its own read; I2C.vhd's collapses to register 0 when en deasserts.
    i2c_rdata_bridge: process(mclk, resetn)
    begin
        if resetn = '0' then
            i2c0_sh_rdata <= (others => '0');
            i2c1_sh_rdata <= (others => '0');
            npu_sh_rdata  <= (others => '0');
        elsif rising_edge(mclk) then
            if shslv_i2c0_en = '1' then
                i2c0_sh_rdata <= i2c0_sh_rdata_c;
            end if;
            if shslv_i2c1_en = '1' then
                i2c1_sh_rdata <= i2c1_sh_rdata_c;
            end if;
            -- M7d: NPU's MabMmrQ is combinational too (same rule)
            if shslv_npu_en = '1' then
                npu_sh_rdata <= npu_sh_rdata_c;
            end if;
        end if;
    end process;

    sh_rdata_mux <= rom_q          when shslv_rd_rom     = '1' else
                    npuram_q       when shslv_rd_npuram  = '1' else
                    bank0_q        when shslv_rd_bank0   = '1' else
                    bank1_q        when shslv_rd_bank1   = '1' else
                    bank2_q        when shslv_rd_bank2   = '1' else
                    bank3_q        when shslv_rd_bank3   = '1' else
                    clint_rdata    when shslv_rd_clint   = '1' else
                    mtx_rdata      when shslv_rd_mtx     = '1' else
                    irtr_rdata     when shslv_rd_irtr    = '1' else
                    gpio0_sh_rdata when shslv_rd_gpio0   = '1' else
                    gpio1_sh_rdata when shslv_rd_gpio1   = '1' else
                    spi0_sh_rdata  when shslv_rd_spi0    = '1' else
                    spi1_sh_rdata  when shslv_rd_spi1    = '1' else
                    uart0_sh_rdata when shslv_rd_uart0   = '1' else
                    uart1_sh_rdata when shslv_rd_uart1   = '1' else
                    tim0_sh_rdata  when shslv_rd_tim0    = '1' else
                    tim1_sh_rdata  when shslv_rd_tim1    = '1' else
                    gpio2_sh_rdata when shslv_rd_gpio2   = '1' else
                    sys_sh_rdata   when shslv_rd_sys     = '1' else
                    npu_sh_rdata   when shslv_rd_npu     = '1' else
                    sar_sh_rdata   when shslv_rd_sar     = '1' else
                    afe_sh_rdata   when shslv_rd_afe     = '1' else
                    gpio3_sh_rdata when shslv_rd_gpio3   = '1' else
                    i2c0_sh_rdata  when shslv_rd_i2c0    = '1' else
                    i2c1_sh_rdata  when shslv_rd_i2c1    = '1' else
                    (others => '0');  -- no slave (TCM page, unmapped)

    -- M6: bridge the arbiter slave port onto UART0's adddec-style register bus.
    -- UART.vhd already obeys the 1-cycle registered-read contract
    -- (reg_read_proc) and qualifies every write by en_mem='0', so the bridge is
    -- pure polarity/width adaptation: en_mem is the active-LOW one-cycle access
    -- strobe, wen the active-LOW byte lanes (from the resv-GATED sh_we — a
    -- suppressed SC write must not touch the UART), and clk_mem is the
    -- free-running mclk (the gated-clock "stuck clear-pulse" behaviour of the
    -- old private periph bus disappears: clr_* become true one-cycle pulses,
    -- consumed asynchronously by the TX/RX FSMs).
    uart0_sh_en_n  <= not shslv_uart0_en;
    sh_wen_n <= not sh_we;

    -- M7b: same polarity shim for the moved TIMER/GPIO blocks (active-LOW
    -- one-cycle en strobes; they share sh_wen_n's active-low lanes —
    -- all from the resv-GATED sh_we, so a suppressed SC write can't touch
    -- any shared peripheral). clk_mem = free-running mclk everywhere; the
    -- M7b audit found TIMER and GPIO both already en-qualify every write and
    -- register every read (UART-class movers) — their un-en-qualified logic
    -- (timer core, pin IRQ flags) runs on its OWN muxed/pin clocks, not
    -- clk_mem, so the gated->free-running change is invariant for them.
    tim0_sh_en_n  <= not shslv_tim0_en;
    tim1_sh_en_n  <= not shslv_tim1_en;
    gpio1_sh_en_n <= not shslv_gpio1_en;
    gpio2_sh_en_n <= not shslv_gpio2_en;
    gpio3_sh_en_n <= not shslv_gpio3_en;
    -- M7c: SPI1 + UART1 (audited clean; SPI1's flash FSM is compiled out by
    -- ENABLE_EXTENDED_MEM=false, and its baud core runs on smclk — the
    -- SYS_CLK_CR=0 rule applies to SPI software too)
    spi1_sh_en_n  <= not shslv_spi1_en;
    uart1_sh_en_n <= not shslv_uart1_en;
    -- M7c.2: I2C0/I2C1 (combinational read handled by i2c_rdata_bridge above;
    -- writes/snapshot-latches audit clean — single en-qualified ClkMem
    -- process, core FSMs on smclk/pin edges)
    i2c0_sh_en_n  <= not shslv_i2c0_en;
    i2c1_sh_en_n  <= not shslv_i2c1_en;
    -- M7d: NPU register bus (MabMmrCEN was HARDWIRED '0' on the old gated
    -- bus — the clk_periph pulse was the only write qualifier; on the
    -- free-running mclk this strobe IS the qualifier)
    npu_sh_en_n   <= not shslv_npu_en;
    -- M11: the last five private peripherals join the window (the private
    -- peripheral page is GONE). Audited: all five register their reads on
    -- clk_mem — UART-class movers, plain shims, no bridge. SYSTEM0 note:
    -- SYS_CLK_CR/SYS_CLK_DIV_CR reconfigure MCLK ITSELF — reconfiguring
    -- with other masters mid-transaction is a software-contract violation
    -- (management hart quiesces the others first).
    sys_sh_en_n   <= not shslv_sys_en;
    gpio0_sh_en_n <= not shslv_gpio0_en;
    spi0_sh_en_n  <= not shslv_spi0_en;
    sar_sh_en_n   <= not shslv_sar_en;
    afe_sh_en_n   <= not shslv_afe_en;

    clint0: entity work.clint
        generic map (NHARTS => 4)
        port map (
            clk    => mclk,
            resetn => resetn,
            en     => shslv_clint_en,
            we     => sh_we,
            addr   => sh_addr(3 downto 0),
            wdata  => sh_wdata,
            rdata  => clint_rdata,
            msip   => clint_msip,
            mtip   => clint_mtip
        );

    -- M7a: tile IRQ fan-out — per-hart peripheral-IRQ enable rows, written by
    -- any hart through the arbiter (resv-gated sh_we, like the CLINT). Rows
    -- 1-3 feed the tiles' irq_en_ext; row 0 exists for symmetry but hart 0's
    -- enables stay with SYSTEM0 (the management monarch). Resets all-masked,
    -- so this block is a provable NO-OP until software routes an IRQ.
    irtr0: entity work.irq_router
        generic map (NHARTS => 4, NUM_IRQS => NUM_IRQS)
        port map (
            clk        => mclk,
            resetn     => resetn,
            en         => shslv_irtr_en,
            we         => sh_we,
            addr       => sh_addr(3 downto 0),
            wdata      => sh_wdata,
            rdata      => irtr_rdata,
            irq_en_out => tile_irq_en_flat
        );

    -- M7c LOCKING: HW mutex bank @0x13000 (page-3 slot 0). READ = atomic
    -- return-old-and-claim (1-instruction acquire; the arbiter's whole-txn
    -- serialization IS the atomicity), WRITE 0 = release. sh_master tells it
    -- WHICH hart's claim-read this is. Resets all-free -> provable NO-OP.
    -- ADVISORY by design decision: no bus-enforced locking (no core bus-error
    -- path; stall-until-release would be a deadlock generator).
    mtx0: entity work.mutex_bank
        generic map (NMUTEX => 16)
        port map (
            clk    => mclk,
            resetn => resetn,
            en     => shslv_mtx_en,
            we     => sh_we,
            addr   => sh_addr(3 downto 0),
            wdata  => sh_wdata,
            master => sh_master,
            rdata  => mtx_rdata
        );

    -- =========================================================================
    -- M11: shared bulk RAM = 4 x sram1p16k macros (64 KB, 0x10000-0x1FFFF),
    -- replacing the M3c 256-word behavioral array. The macro IS the arbiter's
    -- slave model: CEN sampled with the address at the s_en cycle's ending
    -- edge, Q valid the next cycle (1-cycle registered read). Enables/WEN are
    -- ACTIVE-LOW at the macro — inverted from the arbiter's active-high
    -- strobes; WEN comes from the resv-GATED sh_we (a suppressed SC write
    -- must not touch memory), per-byte lanes (M4a). No INIT: power-up
    -- contents are undefined on silicon — the write-before-read contract
    -- (mailbox zeroing) is an M12 bootrom obligation; behavioral models
    -- zero-fill, the gate flow deposits zeros.
    -- =========================================================================
    bank0_cen_n  <= not shslv_bank0_en;
    bank1_cen_n  <= not shslv_bank1_en;
    bank2_cen_n  <= not shslv_bank2_en;
    bank3_cen_n  <= not shslv_bank3_en;
    npuram_cen_n <= not shslv_npuram_en;
    rom_cen_n    <= not shslv_rom_en;   -- M12: shared boot ROM (read-only, no WEN)
    shmem_gwen_n <= '0' when sh_we /= "0000" else '1';

    shbank0: entity work.sram1p16k_hvt_pg
        port map (
            Q     => bank0_q,
            CLK   => mclk,
            CEN   => bank0_cen_n,
            WEN   => sh_wen_n,
            A     => sh_addr(11 downto 0),
            D     => sh_wdata,
            EMA   => "000",
            GWEN  => shmem_gwen_n,
            RETN  => '1',
            PGEN  => '0'
        );

    shbank1: entity work.sram1p16k_hvt_pg
        port map (
            Q     => bank1_q,
            CLK   => mclk,
            CEN   => bank1_cen_n,
            WEN   => sh_wen_n,
            A     => sh_addr(11 downto 0),
            D     => sh_wdata,
            EMA   => "000",
            GWEN  => shmem_gwen_n,
            RETN  => '1',
            PGEN  => '0'
        );

    shbank2: entity work.sram1p16k_hvt_pg
        port map (
            Q     => bank2_q,
            CLK   => mclk,
            CEN   => bank2_cen_n,
            WEN   => sh_wen_n,
            A     => sh_addr(11 downto 0),
            D     => sh_wdata,
            EMA   => "000",
            GWEN  => shmem_gwen_n,
            RETN  => '1',
            PGEN  => '0'
        );

    shbank3: entity work.sram1p16k_hvt_pg
        port map (
            Q     => bank3_q,
            CLK   => mclk,
            CEN   => bank3_cen_n,
            WEN   => sh_wen_n,
            A     => sh_addr(11 downto 0),
            D     => sh_wdata,
            EMA   => "000",
            GWEN  => shmem_gwen_n,
            RETN  => '1',
            PGEN  => '0'
        );

    -- M3b: harts 1-3 as PRIVATE-MEMORY tiles (hdl/MCU_MP/hart_tile.vhd). Each
    -- tile is a full vesta + its own adddec + private TCM (RAM0, 0x8000).
    -- M12: tiles reset to PC 0x0 like hart 0 and fetch the SHARED boot ROM
    -- through the arbiter — the M3b-M11 preloaded-TCM boot (PC_RST_VAL
    -- 0x8200 + RAM0_INIT_FILE image) is retired; the bootrom's mhartid
    -- dispatch parks them (WFI) until hart 0 loads/ignites them via the
    -- CLINT msip + boot-mailbox protocol. Distinct hart_id per core (M13: a
    -- PORT — all four tile instances are one identical netlist). No
    -- cross-hart hazard (each tile is unchanged single-core logic). M11
    -- retired the tiles' dead boot ROMs and private RAM1s (0xC000 = the
    -- shared NPU staging RAM now).
    --
    -- M3c.4: each tile is now also a REAL arbiter master (1-3) of the shared
    -- window — its sh_* port maps straight onto that master's slice
    -- of the flattened arb_* buses. Each hart's a0 is brought out (a0_1/2/3);
    -- the tb latches pass AND fail, so a post-PASS corruption still fails
    -- the run. M13: sleep/flash/tcm_pgen and the SYSTEM0-side IRQ ports ride
    -- their entity defaults here — only hart 0 wires them.
    hart1: entity work.hart_tile
        generic map (
            PC_RST_VAL     => x"00000000",
            SH_AW          => SH_AW
        )
        port map (
            clk       => mclk,
            resetn    => resetn,
            sleep     => '0',
            hart_id   => x"00000001",
            msip_in   => clint_msip(1),
            mtip_in   => clint_mtip(1),
            -- M7a: deglitched peripheral levels fan out to every tile; the
            -- tile's row of the irq_router gates them (slots 83/84 are
            -- overridden/hardwired inside the tile)
            irq_ext    => irq_deglitch,
            irq_en_ext => tile_irq_en_flat(2*NUM_IRQS-1 downto 1*NUM_IRQS),
            sh_req    => arb_req(1),
            sh_we     => arb_we(7 downto 4),
            sh_addr   => arb_addr(2*SH_AW-1 downto SH_AW),
            sh_wdata  => arb_wdata(2*32-1 downto 32),
            sh_gnt    => arb_gnt(1),
            sh_done   => arb_done(1),
            sh_rdata  => arb_rdata,
            sh_lrsc   => arb_lrsc(3 downto 2),
            sh_scfail => arb_scfail(1),
            sh_lock   => arb_lock(1),
            trap_flag => open,
            a0        => a0_1
        );

    hart2: entity work.hart_tile
        generic map (
            PC_RST_VAL     => x"00000000",
            SH_AW          => SH_AW
        )
        port map (
            clk       => mclk,
            resetn    => resetn,
            sleep     => '0',
            hart_id   => x"00000002",
            msip_in   => clint_msip(2),
            mtip_in   => clint_mtip(2),
            irq_ext    => irq_deglitch,
            irq_en_ext => tile_irq_en_flat(3*NUM_IRQS-1 downto 2*NUM_IRQS),
            sh_req    => arb_req(2),
            sh_we     => arb_we(11 downto 8),
            sh_addr   => arb_addr(3*SH_AW-1 downto 2*SH_AW),
            sh_wdata  => arb_wdata(3*32-1 downto 2*32),
            sh_gnt    => arb_gnt(2),
            sh_done   => arb_done(2),
            sh_rdata  => arb_rdata,
            sh_lrsc   => arb_lrsc(5 downto 4),
            sh_scfail => arb_scfail(2),
            sh_lock   => arb_lock(2),
            trap_flag => open,
            a0        => a0_2
        );

    hart3: entity work.hart_tile
        generic map (
            PC_RST_VAL     => x"00000000",
            SH_AW          => SH_AW
        )
        port map (
            clk       => mclk,
            resetn    => resetn,
            sleep     => '0',
            hart_id   => x"00000003",
            msip_in   => clint_msip(3),
            mtip_in   => clint_mtip(3),
            irq_ext    => irq_deglitch,
            irq_en_ext => tile_irq_en_flat(4*NUM_IRQS-1 downto 3*NUM_IRQS),
            sh_req    => arb_req(3),
            sh_we     => arb_we(15 downto 12),
            sh_addr   => arb_addr(4*SH_AW-1 downto 3*SH_AW),
            sh_wdata  => arb_wdata(4*32-1 downto 3*32),
            sh_gnt    => arb_gnt(3),
            sh_done   => arb_done(3),
            sh_rdata  => arb_rdata,
            sh_lrsc   => arb_lrsc(7 downto 6),
            sh_scfail => arb_scfail(3),
            sh_lock   => arb_lock(3),
            trap_flag => open,
            a0        => a0_3
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

            -- Memory Bus (arbiter slave side, M11 — window slot 9 @0x04900)
            clk_mem       => mclk,
            en_mem        => sys_sh_en_n,
            wen           => sh_wen_n,
            addr_periph   => sh_addr(5 downto 0),
            write_data    => sh_wdata,
            read_data     => sys_sh_rdata,

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

    -- M13: hart 0's adddec moved into the hart0 tile (its >=0x20000
    -- extended-flash decode drives the tile's flash ports, wired to SPI0
    -- above; the M11-dead private peripheral bus is tied off inside).

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

            -- Memory Bus (arbiter slave side, M11 — window slot 0 @0x04000)
            clk_mem         => mclk,
            en              => gpio0_sh_en_n,
            wen             => sh_wen_n,
            write_data      => sh_wdata,
            read_data       => gpio0_sh_rdata,
            addr_periph     => sh_addr(5 downto 0),

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
    -- M7b: register bus moved onto the mp_arbiter (page-3 slot 1 @0x13100,
    -- all 4 harts); pads/alt-func/IRQ wiring unchanged. Old 0x4100 reads 0.
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

            clk_mem         => mclk,
            en              => gpio1_sh_en_n,
            wen             => sh_wen_n,
            write_data      => sh_wdata,
            read_data       => gpio1_sh_rdata,
            addr_periph     => sh_addr(5 downto 0),

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

            clk_mem         => mclk,
            en              => gpio2_sh_en_n,
            wen             => sh_wen_n,
            write_data      => sh_wdata,
            read_data       => gpio2_sh_rdata,
            addr_periph     => sh_addr(5 downto 0),

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

            clk_mem         => mclk,
            en              => gpio3_sh_en_n,
            wen             => sh_wen_n,
            write_data      => sh_wdata,
            read_data       => gpio3_sh_rdata,
            addr_periph     => sh_addr(5 downto 0),

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

            -- Memory Bus (arbiter slave side, M11 — window slot 2 @0x04200)
            clk_mem         => mclk,
            en_mem          => spi0_sh_en_n,
            wen             => sh_wen_n,
            write_data      => sh_wdata,
            read_data       => spi0_sh_rdata,
            addr_periph     => sh_addr(5 downto 0),

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

            -- Memory Bus (arbiter slave side, M7c — window slot 3 @0x04300)
            clk_mem         => mclk,
            en_mem          => spi1_sh_en_n,
            wen             => sh_wen_n,
            write_data      => sh_wdata,
            read_data       => spi1_sh_rdata,
            addr_periph     => sh_addr(5 downto 0),

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

    -- M6: UART0 is the SHARED console UART on the mp_arbiter slave port (all
    -- 4 harts). M11 moved its window from 0x12000 back to its ORIGINAL 0x4400
    -- slot in the shared peripheral window. Core clock (smclk), pads and IRQ
    -- wiring (-> hart 0's SYSTEM only) are unchanged.
    uart0: UART
        port map (
            -- System Signals
            clk         => smclk,
            resetn       => resetn,

            -- Interrupt Signals
            irq_rc       => irq_uart0_rc,
            irq_te       => irq_uart0_te,
            irq_tc       => irq_uart0_tc,

            -- Memory Bus (arbiter slave side, M6 — window slot 4 @0x04400)
            clk_mem     => mclk,
            en_mem      => uart0_sh_en_n,
            wen         => sh_wen_n,
            addr_periph => sh_addr(5 downto 0),
            write_data  => sh_wdata,
            read_data   => uart0_sh_rdata,

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

            -- Memory Bus (arbiter slave side, M7c — window slot 5 @0x04500)
            clk_mem     => mclk,
            en_mem      => uart1_sh_en_n,
            wen         => sh_wen_n,
            addr_periph => sh_addr(5 downto 0),
            write_data  => sh_wdata,
            read_data   => uart1_sh_rdata,

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
        generic map (
            default_SAD => i2c0_default_SAD
        )
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
            
            -- Memory Bus (arbiter slave side, M7c.2 — window slot 14 @0x04E00;
            -- rdata_out is COMBINATIONAL, registered by i2c_rdata_bridge)
            ClkMem			=> mclk,
            EnMemPeriph		=> i2c0_sh_en_n,
            WEn				=> sh_wen_n,
            MABPart			=> sh_addr(5 downto 0),
            wdata			=> sh_wdata,
            rdata_out		=> i2c0_sh_rdata_c,
            
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
        generic map (
            default_SAD => i2c1_default_SAD
        )
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
            
            -- Memory Bus (arbiter slave side, M7c.2 — window slot 15 @0x04F00;
            -- rdata_out is COMBINATIONAL, registered by i2c_rdata_bridge)
            ClkMem			=> mclk,
            EnMemPeriph		=> i2c1_sh_en_n,
            WEn				=> sh_wen_n,
            MABPart			=> sh_addr(5 downto 0),
            wdata			=> sh_wdata,
            rdata_out		=> i2c1_sh_rdata_c,

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

            -- Memory Bus (arbiter slave side, M7b — window slot 6 @0x04600)
            clk_mem      => mclk,
            en_mem       => tim0_sh_en_n,
            wen          => sh_wen_n,
            addr_periph  => sh_addr(5 downto 0),
            write_data   => sh_wdata,
            read_data    => tim0_sh_rdata,

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

            -- Memory Bus (arbiter slave side, M7b — window slot 7 @0x04700)
            clk_mem      => mclk,
            en_mem       => tim1_sh_en_n,
            wen          => sh_wen_n,
            addr_periph  => sh_addr(5 downto 0),
            write_data   => sh_wdata,
            read_data    => tim1_sh_rdata,

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

            -- Memory Bus Signals (arbiter slave side, M7d — window slot 10
            -- @0x04A00; MabMmrQ is COMBINATIONAL, registered by the bridge)
            MabMmrA     => sh_addr(1 downto 0),
            MabMmrD     => sh_wdata,
            MabMmrCLK   => mclk,
            MabMmrCEN   => npu_sh_en_n,
            MabMmrWEN   => sh_wen_n,
            MabMmrQ     => npu_sh_rdata_c,

            -- MUXed SRAM Inputs — M11: the staging RAM's bus side is the
            -- ARBITER SLAVE fabric (0xC000-0xFFFF page), not hart 0's adddec:
            -- any hart stages vectors through the shared window. Active-low
            -- strobes shimmed exactly like the bulk RAM banks.
            SramQ_in      => npuram_q,
            SramA_in      => sh_addr(11 downto 0),
            SramD_in      => sh_wdata,
            SramCLK_in    => mclk,
            SramCEN_in    => npuram_cen_n,
            SramGWEN_in   => shmem_gwen_n,
            SramWEN_in    => sh_wen_n,

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

            -- Memory Bus (arbiter slave side, M11 — window slot 12 @0x04C00)
            clk_mem     => mclk,
            en_mem      => afe_sh_en_n,
            wen         => sh_wen_n,
            addr_periph => sh_addr(5 downto 0),
            write_data  => sh_wdata,
            read_data   => afe_sh_rdata,

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

            -- Memory Bus (arbiter slave side, M11 — window slot 11 @0x04B00)
            clk_mem     => mclk,
            en_mem      => sar_sh_en_n,
            wen         => sh_wen_n,
            addr_periph => sh_addr(5 downto 0),
            write_data  => sh_wdata,
            read_data   => sar_sh_rdata,

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
    -- M12: THE shared boot ROM (page 000, 0x0-0x3FFF) — hart 0's private
    -- boot ROM promoted to an ARBITER SLAVE, like the bulk banks: CEN
    -- sampled with the address at the s_en cycle's ending edge on the
    -- free-running mclk, Q valid the next cycle (the macro IS the 1-cycle
    -- registered read). Read-only: no WEN pin — a write transaction to this
    -- page completes at the arbiter but is discarded. All four harts reset
    -- to PC 0x0 and fetch their first instruction from here through the
    -- arbiter (see hart_tile.vhd's core_rst_stretch). BLOCKPWR's ROMOFF bit
    -- keeps gating the macro (pgen_mem(0)).
    rom0: entity work.rom_hvt_pg
        port map (
            Q    => rom_q,
            CLK  => mclk,
            CEN  => rom_cen_n,
            A    => sh_addr(11 downto 0),
            EMA  => "000",
            PGEN => pgen_mem(0)
    );

    -- M13: hart 0's TCM macro (ram0) moved into the hart0 tile with its
    -- adddec — BLOCKPWR's RAMOFF gating survives via the tile's tcm_pgen
    -- port (pgen_mem(1), wired at the hart0 instance).

    -- M11: NPU staging RAM @0xC000-0xFFFF (hart 0's retired private RAM1
    -- macro, promoted to an ARBITER SLAVE). The NPU's internal port mux
    -- (NpuMuxSel) still owns these pins: bus side = the shared-slave fabric
    -- (see the NPU instance's Sram*_in), NPU side during a THINK. Q feeds
    -- both the slave read mux (npuram_q) and the NPU's SramQ_in. BLOCKPWR's
    -- RAM1OFF bit keeps gating this macro (pgen_mem(2)).
    npuram0: entity work.sram1p16k_hvt_pg
        port map (
            Q     => npuram_q,
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



