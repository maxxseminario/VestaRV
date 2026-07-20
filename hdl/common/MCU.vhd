-- MCU.vhd
-- Castalia MCU top-level integration layer (4 harts, MCU_MP)
-- Golden-master templated from the verified hdl/common/MCU.vhd: the fixed
-- 	boilerplate comes from hdl_templates/MCU.template.vhd; the description-
-- 	driven sections are generated from python/generate.py
-- Generated on 2026/07/20 at 03:57:23 with the generate.py chip generator
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

        --GPIO4 Connections (Mission B: QSPI0 / I3C0 pin functions on AF1)
        prt5_in		    : in	std_logic_vector(7 downto 0);
		prt5_out		: out	std_logic_vector(7 downto 0);
		prt5_dir		: out	std_logic_vector(7 downto 0);
		prt5_ren		: out	std_logic_vector(7 downto 0);

        --GPIO5 Connections (Mission B: NFC0 digital-AFE pin functions on AF1)
        prt6_in		    : in	std_logic_vector(7 downto 0);
		prt6_out		: out	std_logic_vector(7 downto 0);
		prt6_dir		: out	std_logic_vector(7 downto 0);
		prt6_ren		: out	std_logic_vector(7 downto 0);


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
    -- harts 1-3 (hdl/common/hart_tile.vhd), and the four tile instances are
    -- STRUCTURALLY IDENTICAL (one netlist -> one hardened tile in M14).
    -- Every per-instance difference is wiring only: hart_id (mhartid port),
    -- hart 0's flash/XIP + sleep hookup to SPI0 and the TCM PGEN (BLOCKPWR
    -- on hart 0). M19: the IRQ interface is IDENTICAL on every hart —
    -- msip/mtip from the CLINT + one meip wire from the irq_router's
    -- claim/complete stage (SYSTEM0's vectored path is retired). The vesta
    -- and adddec component declarations went with the inline hart-0
    -- machinery.

    ----------------------------------- Peripherals --------------------------------------------------

    -- SYSTEMx
    component SYSTEM
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

            -- Interrupt Signals (M19: WDT only — the vectored controller is
            -- retired; routing/delivery live in the irq_router)
            irq_sys_wdt     : out std_logic;
            wdt_irq_routed   : in  std_logic := '0';
            wdt_irq_complete : in  std_logic := '0';

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
            RstValPxREN     : std_logic_vector(31 downto 0) := (others => '0');
            RstValPxAFS     : std_logic_vector(31 downto 0) := (others => '0')
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
            PxSEL_out		: out	std_logic_vector(num_pins - 1 downto 0);
            PxAFS_out		: out	std_logic_vector(3 * num_pins - 1 downto 0);

            -- GPIO_NUM_AFS flattened alternate-function planes: plane k, pin i
            -- at bit (k * num_pins + i). Plane 0 = the legacy AF0 functions.
            alt_func_out_in		: in	slv(GPIO_NUM_AFS * num_pins - 1 downto 0);
            alt_func_dir_in		: in	slv(GPIO_NUM_AFS * num_pins - 1 downto 0);
            alt_func_ren_in		: in	slv(GPIO_NUM_AFS * num_pins - 1 downto 0)
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




    -- MCU Block Level Signal Declarations --------------------------------------

        -- System Signals 
        signal resetn           : std_logic;
        signal resetn_por       : std_logic;
        signal resetn_sys       : std_logic;
        -- M19: SYSTEM0's vectored IRQ fabric (irq_en/irq_priority/isr_ret/
        -- irq_recursion_en) is RETIRED — delivery is the irq_router's
        -- per-hart meip wires (claim/complete), declared at meip-decl below.
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
        signal irq_gpio4        : std_logic_vector(7 downto 0);  -- GPIO4 Interrupt
        signal irq_gpio5        : std_logic_vector(7 downto 0);  -- GPIO5 Interrupt
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

        signal irq_comb         : std_logic_vector(127 downto 0);
        signal irq_deglitch     : std_logic_vector(NUM_IRQ_SRCS -1 downto 0);
        signal gf_out           : std_logic_vector(127 downto 0);


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
        signal arb_resvvld      : std_logic_vector(3 downto 0);  -- X1 Zawrs: per-master reservation-valid level
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
        signal shslv_uart0_en_q : std_logic;   -- X-fix: falling-mclk registered strobe (snapshot capture clock)
        signal sh_wen_n   : std_logic_vector(3 downto 0);
        signal uart0_sh_rdata   : std_logic_vector(31 downto 0);
        -- M7a: irq_router, the tile IRQ fan-out (M11: window page 3 @0x7000)
        signal shslv_irtr_sel   : std_logic;
        signal shslv_irtr_en    : std_logic;
        signal shslv_rd_irtr    : std_logic := '0'; -- registered: last access was irq_router
        signal irtr_rdata       : std_logic_vector(31 downto 0);
        signal meip             : std_logic_vector(3 downto 0);
        signal wdt_irq_routed   : std_logic;   -- irq_router: source 0 enabled in some row
        signal wdt_irq_complete : std_logic;   -- irq_router: COMPLETE(0) pulse (WDT EOI)
        -- M17: pwr_ctrl, the MTCMOS power controller — a NATIVE slave in
        -- window slot 11 @0x4B00 (vacated by SARADC0). Its pd_* rows drive
        -- the tile power domains: pd_rstn folds into each tile's resetn
        -- (cold-gate: the reset IS what functional sims observe), pd_sleep/
        -- pd_iso_en go to the tiles' CPF-hook ports (HEAD switch SLEEP
        -- chain + A2ISO clamp enable in the physical flow). Hart 0 has no
        -- row: always-on by construction.
        signal shslv_pwr_sel    : std_logic;
        signal shslv_pwr_en     : std_logic;
        signal shslv_rd_pwr     : std_logic := '0'; -- registered: last access was pwr_ctrl
        signal pwr_rdata        : std_logic_vector(31 downto 0);
        signal pd_iso_en        : std_logic_vector(3 downto 1);
        signal pd_sleep         : std_logic_vector(3 downto 1);
        signal pd_rstn          : std_logic_vector(3 downto 1);
        signal tile_rstn        : std_logic_vector(3 downto 1);
        -- M17 isolation: the tile outputs land on these _raw nets and are
        -- AND-clamped LOW onto the arbiter/observation buses by pd_iso_en —
        -- the EXPLICIT always-on-side isolation cells (electrically the
        -- same structure as the pmk A2ISO: an AND on AO power with the
        -- possibly-floating tile pin on one input). Clamp-low == the
        -- boundary registers' reset values, so a clamped master looks
        -- exactly like a reset one to the arbiter (no M5a-class hazard).
        signal tile1_req_raw    : std_logic;
        signal tile2_req_raw    : std_logic;
        signal tile3_req_raw    : std_logic;
        signal tile1_we_raw     : std_logic_vector(3 downto 0);
        signal tile2_we_raw     : std_logic_vector(3 downto 0);
        signal tile3_we_raw     : std_logic_vector(3 downto 0);
        signal tile1_addr_raw   : std_logic_vector(SH_AW-1 downto 0);
        signal tile2_addr_raw   : std_logic_vector(SH_AW-1 downto 0);
        signal tile3_addr_raw   : std_logic_vector(SH_AW-1 downto 0);
        signal tile1_wdata_raw  : std_logic_vector(31 downto 0);
        signal tile2_wdata_raw  : std_logic_vector(31 downto 0);
        signal tile3_wdata_raw  : std_logic_vector(31 downto 0);
        signal tile1_lrsc_raw   : std_logic_vector(1 downto 0);
        signal tile2_lrsc_raw   : std_logic_vector(1 downto 0);
        signal tile3_lrsc_raw   : std_logic_vector(1 downto 0);
        signal tile1_lock_raw   : std_logic;
        signal tile2_lock_raw   : std_logic;
        signal tile3_lock_raw   : std_logic;
        signal a0_1_raw         : std_logic_vector(31 downto 0);
        signal a0_2_raw         : std_logic_vector(31 downto 0);
        signal a0_3_raw         : std_logic_vector(31 downto 0);
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
        signal shslv_tim0_en_q  : std_logic;   -- X-fix: falling-mclk registered strobes
        signal shslv_tim1_en_q  : std_logic;   -- (snapshot capture clocks)
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
        signal shslv_spi1_en_q  : std_logic;   -- X-fix: falling-mclk registered strobes
        signal shslv_uart1_en_q : std_logic;   -- (snapshot capture clocks)
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
        signal shslv_i2c0_en_q  : std_logic;   -- X-fix: falling-mclk registered strobes
        signal shslv_i2c1_en_q  : std_logic;   -- (snapshot capture clocks)
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
        -- M11 movers: the last three private peripherals join the window —
        -- SYSTEM0 (slot 9 @0x4900), GPIO0 (slot 0 @0x4000), SPI0 (slot 2
        -- @0x4200). All
        -- three register their reads on clk_mem (M11 audit) -> plain polarity
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
        signal shslv_rd_sys     : std_logic := '0';
        signal shslv_rd_gpio0   : std_logic := '0';
        signal shslv_rd_spi0    : std_logic := '0';
        signal sys_sh_en_n      : std_logic;
        signal gpio0_sh_en_n    : std_logic;
        signal spi0_sh_en_n     : std_logic;
        signal shslv_spi0_en_q  : std_logic;   -- X-fix: falling-mclk registered strobe (snapshot capture clock)
        signal sys_sh_rdata     : std_logic_vector(31 downto 0);
        signal gpio0_sh_rdata   : std_logic_vector(31 downto 0);
        signal spi0_sh_rdata    : std_logic_vector(31 downto 0);
        -- M7c LOCKING: HW mutex bank (M11: window page 2 @0x6000). READ =
        -- atomic return-old-and-claim, WRITE 0 = release; atomic because the
        -- arbiter serializes whole transactions. sh_master is the arbiter's
        -- granted-master index (mp_arbiter s_master port) — attributes the
        -- claim-read to a hart. Registered read, resv-gated we (contract).
        signal shslv_mtx_sel,   shslv_mtx_en    : std_logic;
        signal shslv_rd_mtx     : std_logic := '0';
        signal mtx_rdata        : std_logic_vector(31 downto 0);

        -- CQ2a: AFE digital register stubs (four 64 B sub-slots of page-0 slot
        -- 12 @0x4C00/40/80/C0) + the shared EIS engine stub (carved from the
        -- IRQ-router page top quarter @0x7C00-0x7FFF). Each is an afe_stub
        -- with an s_master ownership gate; the EIS block is hart-0-only.
        -- Reads are REGISTERED (no bridge). See afe_stub.vhd.
        signal shslv_afe_sel    : std_logic;   -- page-0 slot 12 (0x4C00) hit
        signal shslv_afe0_sel,  shslv_afe0_en  : std_logic;
        signal shslv_afe1_sel,  shslv_afe1_en  : std_logic;
        signal shslv_afe2_sel,  shslv_afe2_en  : std_logic;
        signal shslv_afe3_sel,  shslv_afe3_en  : std_logic;
        signal shslv_eis_sel,   shslv_eis_en   : std_logic;
        signal shslv_rd_afe0    : std_logic := '0';
        signal shslv_rd_afe1    : std_logic := '0';
        signal shslv_rd_afe2    : std_logic := '0';
        signal shslv_rd_afe3    : std_logic := '0';
        signal shslv_rd_eis     : std_logic := '0';
        signal afe0_rdata       : std_logic_vector(31 downto 0);
        signal afe1_rdata       : std_logic_vector(31 downto 0);
        signal afe2_rdata       : std_logic_vector(31 downto 0);
        signal afe3_rdata       : std_logic_vector(31 downto 0);
        signal eis_rdata        : std_logic_vector(31 downto 0);
        -- CQ2a: level IRQ from each stub's IF word. NOT yet routed to the
        -- irq_router (the frozen 85-source map has only 2 reserved slots for 5
        -- needed sources — see the CQ2a report); aggregated here for a clean
        -- future hookup and observability.
        signal afe_eis_irq      : std_logic_vector(4 downto 0);
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

    -- Multi-AF plumbing (shared by all four ports) ---------------------------------------
        -- Each GPIO port takes GPIO_NUM_AFS flattened alternate-function
        -- planes (plane k, pin i at bit k*8+i). The per-plane afuncN_* /
        -- afuncN_afK_* vectors below are concatenated into afuncN_all_*.
        -- An unassigned plane slice behaves as a high-impedance input:
        -- out='0', dir='0' (input), ren='0' (pull disabled) — pre-polarity.
        constant afunc_none				: std_logic_vector(7 downto 0) := (others => '0');

    -- Multi-AF output-function spread planes (v1): shared timer/UART/SPI
    -- outputs fanned across all four ports. Dormant at reset (PxAFS=0).
        -- GPIO0 (port 1) planes AF1-AF7
        signal afunc1_af1_out		: std_logic_vector(7 downto 0);
        signal afunc1_af1_dir		: std_logic_vector(7 downto 0);
        signal afunc1_af1_ren		: std_logic_vector(7 downto 0);
        signal afunc1_af2_out		: std_logic_vector(7 downto 0);
        signal afunc1_af2_dir		: std_logic_vector(7 downto 0);
        signal afunc1_af2_ren		: std_logic_vector(7 downto 0);
        signal afunc1_af3_out		: std_logic_vector(7 downto 0);
        signal afunc1_af3_dir		: std_logic_vector(7 downto 0);
        signal afunc1_af3_ren		: std_logic_vector(7 downto 0);
        signal afunc1_af4_out		: std_logic_vector(7 downto 0);
        signal afunc1_af4_dir		: std_logic_vector(7 downto 0);
        signal afunc1_af4_ren		: std_logic_vector(7 downto 0);
        signal afunc1_af5_out		: std_logic_vector(7 downto 0);
        signal afunc1_af5_dir		: std_logic_vector(7 downto 0);
        signal afunc1_af5_ren		: std_logic_vector(7 downto 0);
        signal afunc1_af6_out		: std_logic_vector(7 downto 0);
        signal afunc1_af6_dir		: std_logic_vector(7 downto 0);
        signal afunc1_af6_ren		: std_logic_vector(7 downto 0);
        signal afunc1_af7_out		: std_logic_vector(7 downto 0);
        signal afunc1_af7_dir		: std_logic_vector(7 downto 0);
        signal afunc1_af7_ren		: std_logic_vector(7 downto 0);
        -- GPIO1 (port 2) planes AF2-AF7
        signal afunc2_af2_out		: std_logic_vector(7 downto 0);
        signal afunc2_af2_dir		: std_logic_vector(7 downto 0);
        signal afunc2_af2_ren		: std_logic_vector(7 downto 0);
        signal afunc2_af3_out		: std_logic_vector(7 downto 0);
        signal afunc2_af3_dir		: std_logic_vector(7 downto 0);
        signal afunc2_af3_ren		: std_logic_vector(7 downto 0);
        signal afunc2_af4_out		: std_logic_vector(7 downto 0);
        signal afunc2_af4_dir		: std_logic_vector(7 downto 0);
        signal afunc2_af4_ren		: std_logic_vector(7 downto 0);
        signal afunc2_af5_out		: std_logic_vector(7 downto 0);
        signal afunc2_af5_dir		: std_logic_vector(7 downto 0);
        signal afunc2_af5_ren		: std_logic_vector(7 downto 0);
        signal afunc2_af6_out		: std_logic_vector(7 downto 0);
        signal afunc2_af6_dir		: std_logic_vector(7 downto 0);
        signal afunc2_af6_ren		: std_logic_vector(7 downto 0);
        signal afunc2_af7_out		: std_logic_vector(7 downto 0);
        signal afunc2_af7_dir		: std_logic_vector(7 downto 0);
        signal afunc2_af7_ren		: std_logic_vector(7 downto 0);
        -- GPIO2 (port 3) planes AF2-AF7
        signal afunc3_af2_out		: std_logic_vector(7 downto 0);
        signal afunc3_af2_dir		: std_logic_vector(7 downto 0);
        signal afunc3_af2_ren		: std_logic_vector(7 downto 0);
        signal afunc3_af3_out		: std_logic_vector(7 downto 0);
        signal afunc3_af3_dir		: std_logic_vector(7 downto 0);
        signal afunc3_af3_ren		: std_logic_vector(7 downto 0);
        signal afunc3_af4_out		: std_logic_vector(7 downto 0);
        signal afunc3_af4_dir		: std_logic_vector(7 downto 0);
        signal afunc3_af4_ren		: std_logic_vector(7 downto 0);
        signal afunc3_af5_out		: std_logic_vector(7 downto 0);
        signal afunc3_af5_dir		: std_logic_vector(7 downto 0);
        signal afunc3_af5_ren		: std_logic_vector(7 downto 0);
        signal afunc3_af6_out		: std_logic_vector(7 downto 0);
        signal afunc3_af6_dir		: std_logic_vector(7 downto 0);
        signal afunc3_af6_ren		: std_logic_vector(7 downto 0);
        signal afunc3_af7_out		: std_logic_vector(7 downto 0);
        signal afunc3_af7_dir		: std_logic_vector(7 downto 0);
        signal afunc3_af7_ren		: std_logic_vector(7 downto 0);
        -- GPIO3 (port 4) planes AF2-AF7
        signal afunc4_af2_out		: std_logic_vector(7 downto 0);
        signal afunc4_af2_dir		: std_logic_vector(7 downto 0);
        signal afunc4_af2_ren		: std_logic_vector(7 downto 0);
        signal afunc4_af3_out		: std_logic_vector(7 downto 0);
        signal afunc4_af3_dir		: std_logic_vector(7 downto 0);
        signal afunc4_af3_ren		: std_logic_vector(7 downto 0);
        signal afunc4_af4_out		: std_logic_vector(7 downto 0);
        signal afunc4_af4_dir		: std_logic_vector(7 downto 0);
        signal afunc4_af4_ren		: std_logic_vector(7 downto 0);
        signal afunc4_af5_out		: std_logic_vector(7 downto 0);
        signal afunc4_af5_dir		: std_logic_vector(7 downto 0);
        signal afunc4_af5_ren		: std_logic_vector(7 downto 0);
        signal afunc4_af6_out		: std_logic_vector(7 downto 0);
        signal afunc4_af6_dir		: std_logic_vector(7 downto 0);
        signal afunc4_af6_ren		: std_logic_vector(7 downto 0);
        signal afunc4_af7_out		: std_logic_vector(7 downto 0);
        signal afunc4_af7_dir		: std_logic_vector(7 downto 0);
        signal afunc4_af7_ren		: std_logic_vector(7 downto 0);


    -- GPIO0 Signals (Port 1) ------------------------------------------------------------
        signal p1_out					: std_logic_vector(7 downto 0);
        signal p1_dir					: std_logic_vector(7 downto 0);
        signal p1_ren					: std_logic_vector(7 downto 0);
        signal afunc1_out				: std_logic_vector(7 downto 0); -- Alternate Function Output (plane 0 = AF0)
        signal afunc1_dir				: std_logic_vector(7 downto 0); -- Alternate Function Direction
        signal afunc1_ren				: std_logic_vector(7 downto 0); -- Alternate Function Resistor Enable
        -- GPIO0 deliberately has no AF1+ functions (flash/clock/boot straps)
        signal afunc1_all_out			: std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal afunc1_all_dir			: std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal afunc1_all_ren			: std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);

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
        signal afunc2_out				: std_logic_vector(7 downto 0); -- Alternate Function Output (plane 0 = AF0)
        signal afunc2_dir				: std_logic_vector(7 downto 0); -- Alternate Function Direction
        signal afunc2_ren				: std_logic_vector(7 downto 0); -- Alternate Function Resistor Enable
        -- AF1 plane: TIMER compare (PWM) relocations on P2.0-3, I2C0 on P2.6/7
        signal afunc2_af1_out			: std_logic_vector(7 downto 0);
        signal afunc2_af1_dir			: std_logic_vector(7 downto 0);
        signal afunc2_af1_ren			: std_logic_vector(7 downto 0);
        signal afunc2_all_out			: std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal afunc2_all_dir			: std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal afunc2_all_ren			: std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal p2_afs					: std_logic_vector(23 downto 0);	-- exported AF select (3 bits per pin), routes relocated inputs

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
        signal afunc3_out				: std_logic_vector(7 downto 0); -- Alternate Function Output (plane 0 = AF0)
        signal afunc3_dir				: std_logic_vector(7 downto 0); -- Alternate Function Direction
        signal afunc3_ren				: std_logic_vector(7 downto 0); -- Alternate Function Resistor Enable
        -- AF1 plane: UART1 on P3.0/1, I2C1 on P3.2/3, UART0 on P3.4/5
        signal afunc3_af1_out			: std_logic_vector(7 downto 0);
        signal afunc3_af1_dir			: std_logic_vector(7 downto 0);
        signal afunc3_af1_ren			: std_logic_vector(7 downto 0);
        signal afunc3_all_out			: std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal afunc3_all_dir			: std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal afunc3_all_ren			: std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal p3_afs					: std_logic_vector(23 downto 0);	-- exported AF select (3 bits per pin), routes relocated inputs

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
        signal afunc4_out				: std_logic_vector(7 downto 0); -- Alternate Function Output (plane 0 = AF0)
        signal afunc4_dir				: std_logic_vector(7 downto 0); -- Alternate Function Direction
        signal afunc4_ren				: std_logic_vector(7 downto 0); -- Alternate Function Resistor Enable
        -- AF1 plane: TIMER capture relocations on P4.0-3, TIMER compares on P4.4-7
        signal afunc4_af1_out			: std_logic_vector(7 downto 0);
        signal afunc4_af1_dir			: std_logic_vector(7 downto 0);
        signal afunc4_af1_ren			: std_logic_vector(7 downto 0);
        signal afunc4_all_out			: std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal afunc4_all_dir			: std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal afunc4_all_ren			: std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal p4_afs					: std_logic_vector(23 downto 0);	-- exported AF select (3 bits per pin), routes relocated inputs

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

        -- P4.5: DTP1 (output only)
        signal dtp1_out               : std_logic;
        signal dtp1_dir               : std_logic;
        signal dtp1_ren               : std_logic;

        -- P4.6: DTP2 (output only)
        signal dtp2_out               : std_logic;
        signal dtp2_dir               : std_logic;
        signal dtp2_ren               : std_logic;

        -- P4.7: DTP3 (output only)
        signal dtp3_out               : std_logic;
        signal dtp3_dir               : std_logic;
        signal dtp3_ren               : std_logic;

    -- GPIO4 / GPIO5 (Mission B) declarative regions -------------------------------------
        -- Mission B: GPIO4 (port 5), MUTEX-page sub-slot 3 @0x6300.
        -- Registered-read native slave with its own active-low en shim (like
        -- I3C0/NFC0). AF0 = plain GPIO on every pin; AF1 carries the QSPI0 (P5.0-5) + I3C0 (P5.6/7)
        -- pin functions when present, Hi-Z otherwise. Per-pin IRQs -> vectors 98-105.
        signal shslv_gpio4_sel, shslv_gpio4_en : std_logic;
        signal shslv_rd_gpio4   : std_logic := '0';
        signal gpio4_sh_rdata   : std_logic_vector(31 downto 0);
        signal gpio4_sh_en_n    : std_logic;
        signal p5_out, p5_dir, p5_ren : std_logic_vector(7 downto 0);
        signal p5_afs           : std_logic_vector(23 downto 0);
        signal afunc5_out, afunc5_dir, afunc5_ren : std_logic_vector(7 downto 0);
        signal afunc5_af1_out, afunc5_af1_dir, afunc5_af1_ren : std_logic_vector(7 downto 0);
        signal afunc5_all_out   : std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal afunc5_all_dir   : std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal afunc5_all_ren   : std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);

        -- Mission B: GPIO5 (port 6), MUTEX-page sub-slot 4 @0x6400.
        -- Registered-read native slave with its own active-low en shim (like
        -- I3C0/NFC0). AF0 = plain GPIO on every pin; AF1 carries the NFC0 digital-AFE (P6.0-5)
        -- pin functions when present, Hi-Z otherwise. Per-pin IRQs -> vectors 106-113.
        signal shslv_gpio5_sel, shslv_gpio5_en : std_logic;
        signal shslv_rd_gpio5   : std_logic := '0';
        signal gpio5_sh_rdata   : std_logic_vector(31 downto 0);
        signal gpio5_sh_en_n    : std_logic;
        signal p6_out, p6_dir, p6_ren : std_logic_vector(7 downto 0);
        signal p6_afs           : std_logic_vector(23 downto 0);
        signal afunc6_out, afunc6_dir, afunc6_ren : std_logic_vector(7 downto 0);
        signal afunc6_af1_out, afunc6_af1_dir, afunc6_af1_ren : std_logic_vector(7 downto 0);
        signal afunc6_all_out   : std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal afunc6_all_dir   : std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);
        signal afunc6_all_ren   : std_logic_vector(GPIO_NUM_AFS * 8 - 1 downto 0);

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

        -- Flattened AF planes (7 downto 1 unassigned, plane 0 = AF0): the
        -- boot/flash/clock port keeps exactly one alternate function per pin.
        -- GPIO0 AF output-function spread: aggregates + 8-plane flatten
        afunc1_af1_out <= (
            7 => mosi1_out,
            6 => sck1_out,
            5 => t1_cmp1_out,
            4 => t1_cmp0_out,
            3 => t0_cmp1_out,
            2 => t0_cmp0_out,
            1 => tx1_out,
            0 => tx0_out
        );
        afunc1_af1_dir <= (
            7 => mosi1_dir,
            6 => sck1_dir,
            5 => t1_cmp1_dir,
            4 => t1_cmp0_dir,
            3 => t0_cmp1_dir,
            2 => t0_cmp0_dir,
            1 => tx1_dir,
            0 => tx0_dir
        );
        afunc1_af1_ren <= (
            7 => mosi1_ren,
            6 => sck1_ren,
            5 => t1_cmp1_ren,
            4 => t1_cmp0_ren,
            3 => t0_cmp1_ren,
            2 => t0_cmp0_ren,
            1 => tx1_ren,
            0 => tx0_ren
        );
        afunc1_af2_out <= (
            7 => tx0_out,
            6 => mosi1_out,
            5 => sck1_out,
            4 => t1_cmp1_out,
            3 => t1_cmp0_out,
            2 => t0_cmp1_out,
            1 => t0_cmp0_out,
            0 => tx1_out
        );
        afunc1_af2_dir <= (
            7 => tx0_dir,
            6 => mosi1_dir,
            5 => sck1_dir,
            4 => t1_cmp1_dir,
            3 => t1_cmp0_dir,
            2 => t0_cmp1_dir,
            1 => t0_cmp0_dir,
            0 => tx1_dir
        );
        afunc1_af2_ren <= (
            7 => tx0_ren,
            6 => mosi1_ren,
            5 => sck1_ren,
            4 => t1_cmp1_ren,
            3 => t1_cmp0_ren,
            2 => t0_cmp1_ren,
            1 => t0_cmp0_ren,
            0 => tx1_ren
        );
        afunc1_af3_out <= (
            7 => tx1_out,
            6 => tx0_out,
            5 => mosi1_out,
            4 => sck1_out,
            3 => t1_cmp1_out,
            2 => t1_cmp0_out,
            1 => t0_cmp1_out,
            0 => t0_cmp0_out
        );
        afunc1_af3_dir <= (
            7 => tx1_dir,
            6 => tx0_dir,
            5 => mosi1_dir,
            4 => sck1_dir,
            3 => t1_cmp1_dir,
            2 => t1_cmp0_dir,
            1 => t0_cmp1_dir,
            0 => t0_cmp0_dir
        );
        afunc1_af3_ren <= (
            7 => tx1_ren,
            6 => tx0_ren,
            5 => mosi1_ren,
            4 => sck1_ren,
            3 => t1_cmp1_ren,
            2 => t1_cmp0_ren,
            1 => t0_cmp1_ren,
            0 => t0_cmp0_ren
        );
        afunc1_af4_out <= (
            7 => t0_cmp0_out,
            6 => tx1_out,
            5 => tx0_out,
            4 => mosi1_out,
            3 => sck1_out,
            2 => t1_cmp1_out,
            1 => t1_cmp0_out,
            0 => t0_cmp1_out
        );
        afunc1_af4_dir <= (
            7 => t0_cmp0_dir,
            6 => tx1_dir,
            5 => tx0_dir,
            4 => mosi1_dir,
            3 => sck1_dir,
            2 => t1_cmp1_dir,
            1 => t1_cmp0_dir,
            0 => t0_cmp1_dir
        );
        afunc1_af4_ren <= (
            7 => t0_cmp0_ren,
            6 => tx1_ren,
            5 => tx0_ren,
            4 => mosi1_ren,
            3 => sck1_ren,
            2 => t1_cmp1_ren,
            1 => t1_cmp0_ren,
            0 => t0_cmp1_ren
        );
        afunc1_af5_out <= (
            7 => t0_cmp1_out,
            6 => t0_cmp0_out,
            5 => tx1_out,
            4 => tx0_out,
            3 => mosi1_out,
            2 => sck1_out,
            1 => t1_cmp1_out,
            0 => t1_cmp0_out
        );
        afunc1_af5_dir <= (
            7 => t0_cmp1_dir,
            6 => t0_cmp0_dir,
            5 => tx1_dir,
            4 => tx0_dir,
            3 => mosi1_dir,
            2 => sck1_dir,
            1 => t1_cmp1_dir,
            0 => t1_cmp0_dir
        );
        afunc1_af5_ren <= (
            7 => t0_cmp1_ren,
            6 => t0_cmp0_ren,
            5 => tx1_ren,
            4 => tx0_ren,
            3 => mosi1_ren,
            2 => sck1_ren,
            1 => t1_cmp1_ren,
            0 => t1_cmp0_ren
        );
        afunc1_af6_out <= (
            7 => t1_cmp0_out,
            6 => t0_cmp1_out,
            5 => t0_cmp0_out,
            4 => tx1_out,
            3 => tx0_out,
            2 => mosi1_out,
            1 => sck1_out,
            0 => t1_cmp1_out
        );
        afunc1_af6_dir <= (
            7 => t1_cmp0_dir,
            6 => t0_cmp1_dir,
            5 => t0_cmp0_dir,
            4 => tx1_dir,
            3 => tx0_dir,
            2 => mosi1_dir,
            1 => sck1_dir,
            0 => t1_cmp1_dir
        );
        afunc1_af6_ren <= (
            7 => t1_cmp0_ren,
            6 => t0_cmp1_ren,
            5 => t0_cmp0_ren,
            4 => tx1_ren,
            3 => tx0_ren,
            2 => mosi1_ren,
            1 => sck1_ren,
            0 => t1_cmp1_ren
        );
        afunc1_af7_out <= (
            7 => t1_cmp1_out,
            6 => t1_cmp0_out,
            5 => t0_cmp1_out,
            4 => t0_cmp0_out,
            3 => tx1_out,
            2 => tx0_out,
            1 => mosi1_out,
            0 => sck1_out
        );
        afunc1_af7_dir <= (
            7 => t1_cmp1_dir,
            6 => t1_cmp0_dir,
            5 => t0_cmp1_dir,
            4 => t0_cmp0_dir,
            3 => tx1_dir,
            2 => tx0_dir,
            1 => mosi1_dir,
            0 => sck1_dir
        );
        afunc1_af7_ren <= (
            7 => t1_cmp1_ren,
            6 => t1_cmp0_ren,
            5 => t0_cmp1_ren,
            4 => t0_cmp0_ren,
            3 => tx1_ren,
            2 => tx0_ren,
            1 => mosi1_ren,
            0 => sck1_ren
        );
        afunc1_all_out <= afunc1_af7_out & afunc1_af6_out & afunc1_af5_out & afunc1_af4_out & afunc1_af3_out & afunc1_af2_out & afunc1_af1_out & afunc1_out;
        afunc1_all_dir <= afunc1_af7_dir & afunc1_af6_dir & afunc1_af5_dir & afunc1_af4_dir & afunc1_af3_dir & afunc1_af2_dir & afunc1_af1_dir & afunc1_dir;
        afunc1_all_ren <= afunc1_af7_ren & afunc1_af6_ren & afunc1_af5_ren & afunc1_af4_ren & afunc1_af3_ren & afunc1_af2_ren & afunc1_af1_ren & afunc1_ren;

    -- GPIO1 Connections (SPI1, UART0, UART1) ---------------------------------------
        cs1_in   <= prt2_in(pnum_gpio1_cs1);
        -- MISO1 relocates to P4.6 (AF7, v2 spread slot — literal index, no pnum;
        -- completes a full SPI1 on P4.4/5/6 at AF7); home pad is the default
        miso1_in <= prt4_in(6)
                    when p4_afs((3 * 6) + 2 downto 3 * 6) = "111"
                    else prt2_in(pnum_gpio1_miso1);
        mosi1_in <= prt2_in(pnum_gpio1_mosi1);
        sck1_in  <= prt2_in(pnum_gpio1_sck1);
        sck1_ren_in <= p2_ren(pnum_gpio1_sck1);
        mosi1_ren_in <= p2_ren(pnum_gpio1_mosi1);
        miso1_ren_in <= p4_ren(6)
                        when p4_afs((3 * 6) + 2 downto 3 * 6) = "111"
                        else p2_ren(pnum_gpio1_miso1);
        -- cs1_ren_in <= p2_ren(pnum_gpio1_cs1);

        -- GPIO1 Connections (UART0)
        -- Multi-AF input routing: a relocated function reads its alternate pad
        -- when that pin's PxAFS field selects the function's plane (keyed on
        -- PxAFS only — peripheral inputs stay always-visible, like the direct
        -- taps they replace); otherwise it reads its home pad. The peripheral
        -- ren_in (user pull preference) follows the same selection. RX0's v2
        -- pad is P4.5 at AF2 (a spread io slot — literal index, no pnum; pairs
        -- with TX0 on P4.4 AF2); fixed priority: v2 pad > AF1 pad > home.
        tx0_ren_in <= p3_ren(pnum_gpio2_af1_tx0)
                      when p3_afs((3 * pnum_gpio2_af1_tx0) + 2 downto 3 * pnum_gpio2_af1_tx0) = "001"
                      else p2_ren(pnum_gpio1_tx0);
        rx0_ren_in <= p4_ren(5)
                      when p4_afs((3 * 5) + 2 downto 3 * 5) = "010"
                      else p3_ren(pnum_gpio2_af1_rx0)
                      when p3_afs((3 * pnum_gpio2_af1_rx0) + 2 downto 3 * pnum_gpio2_af1_rx0) = "001"
                      else p2_ren(pnum_gpio1_rx0);
        rx0_in <= prt4_in(5)
                  when p4_afs((3 * 5) + 2 downto 3 * 5) = "010"
                  else prt3_in(pnum_gpio2_af1_rx0)
                  when p3_afs((3 * pnum_gpio2_af1_rx0) + 2 downto 3 * pnum_gpio2_af1_rx0) = "001"
                  else prt2_in(pnum_gpio1_rx0);

        -- GPIO1 Connections (UART1)
        tx1_ren_in <= p3_ren(pnum_gpio2_af1_tx1)
                      when p3_afs((3 * pnum_gpio2_af1_tx1) + 2 downto 3 * pnum_gpio2_af1_tx1) = "001"
                      else p2_ren(pnum_gpio1_tx1);
        rx1_ren_in <= p3_ren(pnum_gpio2_af1_rx1)
                      when p3_afs((3 * pnum_gpio2_af1_rx1) + 2 downto 3 * pnum_gpio2_af1_rx1) = "001"
                      else p2_ren(pnum_gpio1_rx1);
        rx1_in <= prt3_in(pnum_gpio2_af1_rx1)
                  when p3_afs((3 * pnum_gpio2_af1_rx1) + 2 downto 3 * pnum_gpio2_af1_rx1) = "001"
                  else prt2_in(pnum_gpio1_rx1);


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

        -- AF1 plane: TIMER0/1 compare (PWM) outputs on P2.0-3 (the SPI1 pins),
        -- I2C1 relocation on P2.4/5 (v2), I2C0 relocation on P2.6/7 (the UART1 pins)
        -- — both I2C buses land on this port at AF1.
        afunc2_af1_out <= (
            pnum_gpio1_af1_scl0 => scl0_out,        -- GPIO1 pin 7
            pnum_gpio1_af1_sda0 => sda0_out,        -- GPIO1 pin 6
            pnum_gpio1_af1_scl1 => scl1_out,        -- GPIO1 pin 5
            pnum_gpio1_af1_sda1 => sda1_out,        -- GPIO1 pin 4
            pnum_gpio1_af1_t1_cmp1 => t1_cmp1_out,  -- GPIO1 pin 3
            pnum_gpio1_af1_t1_cmp0 => t1_cmp0_out,  -- GPIO1 pin 2
            pnum_gpio1_af1_t0_cmp1 => t0_cmp1_out,  -- GPIO1 pin 1
            pnum_gpio1_af1_t0_cmp0 => t0_cmp0_out   -- GPIO1 pin 0
        );
        afunc2_af1_dir <= (
            pnum_gpio1_af1_scl0 => scl0_dir,        -- GPIO1 pin 7
            pnum_gpio1_af1_sda0 => sda0_dir,        -- GPIO1 pin 6
            pnum_gpio1_af1_scl1 => scl1_dir,        -- GPIO1 pin 5
            pnum_gpio1_af1_sda1 => sda1_dir,        -- GPIO1 pin 4
            pnum_gpio1_af1_t1_cmp1 => t1_cmp1_dir,  -- GPIO1 pin 3
            pnum_gpio1_af1_t1_cmp0 => t1_cmp0_dir,  -- GPIO1 pin 2
            pnum_gpio1_af1_t0_cmp1 => t0_cmp1_dir,  -- GPIO1 pin 1
            pnum_gpio1_af1_t0_cmp0 => t0_cmp0_dir   -- GPIO1 pin 0
        );
        afunc2_af1_ren <= (
            pnum_gpio1_af1_scl0 => scl0_ren,        -- GPIO1 pin 7
            pnum_gpio1_af1_sda0 => sda0_ren,        -- GPIO1 pin 6
            pnum_gpio1_af1_scl1 => scl1_ren,        -- GPIO1 pin 5
            pnum_gpio1_af1_sda1 => sda1_ren,        -- GPIO1 pin 4
            pnum_gpio1_af1_t1_cmp1 => t1_cmp1_ren,  -- GPIO1 pin 3
            pnum_gpio1_af1_t1_cmp0 => t1_cmp0_ren,  -- GPIO1 pin 2
            pnum_gpio1_af1_t0_cmp1 => t0_cmp1_ren,  -- GPIO1 pin 1
            pnum_gpio1_af1_t0_cmp0 => t0_cmp0_ren   -- GPIO1 pin 0
        );

        -- Flattened AF planes (7 downto 2 unassigned)
        -- GPIO1 AF output-function spread: aggregates + 8-plane flatten
        afunc2_af2_out <= (
            7 => mosi1_out,
            6 => tx0_out,
            5 => t1_cmp1_out,
            4 => sck1_out,
            3 => mosi1_out,
            2 => t1_cmp1_out,
            1 => t0_cmp0_out,
            0 => tx1_out
        );
        afunc2_af2_dir <= (
            7 => mosi1_dir,
            6 => tx0_dir,
            5 => t1_cmp1_dir,
            4 => sck1_dir,
            3 => mosi1_dir,
            2 => t1_cmp1_dir,
            1 => t0_cmp0_dir,
            0 => tx1_dir
        );
        afunc2_af2_ren <= (
            7 => mosi1_ren,
            6 => tx0_ren,
            5 => t1_cmp1_ren,
            4 => sck1_ren,
            3 => mosi1_ren,
            2 => t1_cmp1_ren,
            1 => t0_cmp0_ren,
            0 => tx1_ren
        );
        afunc2_af3_out <= (
            7 => tx0_out,
            6 => t0_cmp0_out,
            5 => sck1_out,
            4 => mosi1_out,
            3 => tx0_out,
            2 => sck1_out,
            1 => t1_cmp0_out,
            0 => t0_cmp1_out
        );
        afunc2_af3_dir <= (
            7 => tx0_dir,
            6 => t0_cmp0_dir,
            5 => sck1_dir,
            4 => mosi1_dir,
            3 => tx0_dir,
            2 => sck1_dir,
            1 => t1_cmp0_dir,
            0 => t0_cmp1_dir
        );
        afunc2_af3_ren <= (
            7 => tx0_ren,
            6 => t0_cmp0_ren,
            5 => sck1_ren,
            4 => mosi1_ren,
            3 => tx0_ren,
            2 => sck1_ren,
            1 => t1_cmp0_ren,
            0 => t0_cmp1_ren
        );
        afunc2_af4_out <= (
            7 => tx1_out,
            6 => t0_cmp1_out,
            5 => mosi1_out,
            4 => tx1_out,
            3 => tx1_out,
            2 => tx0_out,
            1 => t1_cmp1_out,
            0 => t1_cmp0_out
        );
        afunc2_af4_dir <= (
            7 => tx1_dir,
            6 => t0_cmp1_dir,
            5 => mosi1_dir,
            4 => tx1_dir,
            3 => tx1_dir,
            2 => tx0_dir,
            1 => t1_cmp1_dir,
            0 => t1_cmp0_dir
        );
        afunc2_af4_ren <= (
            7 => tx1_ren,
            6 => t0_cmp1_ren,
            5 => mosi1_ren,
            4 => tx1_ren,
            3 => tx1_ren,
            2 => tx0_ren,
            1 => t1_cmp1_ren,
            0 => t1_cmp0_ren
        );
        afunc2_af5_out <= (
            7 => t0_cmp0_out,
            6 => t1_cmp0_out,
            5 => tx0_out,
            4 => t0_cmp0_out,
            3 => t0_cmp0_out,
            2 => tx1_out,
            1 => sck1_out,
            0 => t1_cmp1_out
        );
        afunc2_af5_dir <= (
            7 => t0_cmp0_dir,
            6 => t1_cmp0_dir,
            5 => tx0_dir,
            4 => t0_cmp0_dir,
            3 => t0_cmp0_dir,
            2 => tx1_dir,
            1 => sck1_dir,
            0 => t1_cmp1_dir
        );
        afunc2_af5_ren <= (
            7 => t0_cmp0_ren,
            6 => t1_cmp0_ren,
            5 => tx0_ren,
            4 => t0_cmp0_ren,
            3 => t0_cmp0_ren,
            2 => tx1_ren,
            1 => sck1_ren,
            0 => t1_cmp1_ren
        );
        afunc2_af6_out <= (
            7 => t0_cmp1_out,
            6 => t1_cmp1_out,
            5 => tx1_out,
            4 => t0_cmp1_out,
            3 => t0_cmp1_out,
            2 => t0_cmp0_out,
            1 => mosi1_out,
            0 => sck1_out
        );
        afunc2_af6_dir <= (
            7 => t0_cmp1_dir,
            6 => t1_cmp1_dir,
            5 => tx1_dir,
            4 => t0_cmp1_dir,
            3 => t0_cmp1_dir,
            2 => t0_cmp0_dir,
            1 => mosi1_dir,
            0 => sck1_dir
        );
        afunc2_af6_ren <= (
            7 => t0_cmp1_ren,
            6 => t1_cmp1_ren,
            5 => tx1_ren,
            4 => t0_cmp1_ren,
            3 => t0_cmp1_ren,
            2 => t0_cmp0_ren,
            1 => mosi1_ren,
            0 => sck1_ren
        );
        afunc2_af7_out <= (
            7 => t1_cmp0_out,
            6 => sck1_out,
            5 => t0_cmp0_out,
            4 => t1_cmp0_out,
            3 => t1_cmp0_out,
            2 => t0_cmp1_out,
            1 => tx0_out,
            0 => mosi1_out
        );
        afunc2_af7_dir <= (
            7 => t1_cmp0_dir,
            6 => sck1_dir,
            5 => t0_cmp0_dir,
            4 => t1_cmp0_dir,
            3 => t1_cmp0_dir,
            2 => t0_cmp1_dir,
            1 => tx0_dir,
            0 => mosi1_dir
        );
        afunc2_af7_ren <= (
            7 => t1_cmp0_ren,
            6 => sck1_ren,
            5 => t0_cmp0_ren,
            4 => t1_cmp0_ren,
            3 => t1_cmp0_ren,
            2 => t0_cmp1_ren,
            1 => tx0_ren,
            0 => mosi1_ren
        );
        afunc2_all_out <= afunc2_af7_out & afunc2_af6_out & afunc2_af5_out & afunc2_af4_out & afunc2_af3_out & afunc2_af2_out & afunc2_af1_out & afunc2_out;
        afunc2_all_dir <= afunc2_af7_dir & afunc2_af6_dir & afunc2_af5_dir & afunc2_af4_dir & afunc2_af3_dir & afunc2_af2_dir & afunc2_af1_dir & afunc2_dir;
        afunc2_all_ren <= afunc2_af7_ren & afunc2_af6_ren & afunc2_af5_ren & afunc2_af4_ren & afunc2_af3_ren & afunc2_af2_ren & afunc2_af1_ren & afunc2_ren;

    -- GPIO2 Connections (TIMER0, TIMER1) -------------------------------------------------
        -- Compare (PWM) outputs are available at three locations (home P3.0/1/4/5,
        -- AF1 on P2.0-3, AF1 on P4.4-7): the peripheral ren_in follows the
        -- selection with fixed priority P2 > P4 > home.
        t0_cmp0_ren_in  <= p2_ren(pnum_gpio1_af1_t0_cmp0)
                           when p2_afs((3 * pnum_gpio1_af1_t0_cmp0) + 2 downto 3 * pnum_gpio1_af1_t0_cmp0) = "001"
                           else p4_ren(pnum_gpio3_af1_t0_cmp0)
                           when p4_afs((3 * pnum_gpio3_af1_t0_cmp0) + 2 downto 3 * pnum_gpio3_af1_t0_cmp0) = "001"
                           else p3_ren(pnum_gpio2_t0_cmp0);
        t0_cmp1_ren_in  <= p2_ren(pnum_gpio1_af1_t0_cmp1)
                           when p2_afs((3 * pnum_gpio1_af1_t0_cmp1) + 2 downto 3 * pnum_gpio1_af1_t0_cmp1) = "001"
                           else p4_ren(pnum_gpio3_af1_t0_cmp1)
                           when p4_afs((3 * pnum_gpio3_af1_t0_cmp1) + 2 downto 3 * pnum_gpio3_af1_t0_cmp1) = "001"
                           else p3_ren(pnum_gpio2_t0_cmp1);
        t1_cmp0_ren_in  <= p2_ren(pnum_gpio1_af1_t1_cmp0)
                           when p2_afs((3 * pnum_gpio1_af1_t1_cmp0) + 2 downto 3 * pnum_gpio1_af1_t1_cmp0) = "001"
                           else p4_ren(pnum_gpio3_af1_t1_cmp0)
                           when p4_afs((3 * pnum_gpio3_af1_t1_cmp0) + 2 downto 3 * pnum_gpio3_af1_t1_cmp0) = "001"
                           else p3_ren(pnum_gpio2_t1_cmp0);
        t1_cmp1_ren_in  <= p2_ren(pnum_gpio1_af1_t1_cmp1)
                           when p2_afs((3 * pnum_gpio1_af1_t1_cmp1) + 2 downto 3 * pnum_gpio1_af1_t1_cmp1) = "001"
                           else p4_ren(pnum_gpio3_af1_t1_cmp1)
                           when p4_afs((3 * pnum_gpio3_af1_t1_cmp1) + 2 downto 3 * pnum_gpio3_af1_t1_cmp1) = "001"
                           else p3_ren(pnum_gpio2_t1_cmp1);

        -- Capture inputs relocate to P4.0-3 (AF1); home pads stay the default
        t0_cap0_in      <= prt4_in(pnum_gpio3_af1_t0_cap0)
                           when p4_afs((3 * pnum_gpio3_af1_t0_cap0) + 2 downto 3 * pnum_gpio3_af1_t0_cap0) = "001"
                           else prt3_in(pnum_gpio2_t0_cap0);
        t0_cap1_in      <= prt4_in(pnum_gpio3_af1_t0_cap1)
                           when p4_afs((3 * pnum_gpio3_af1_t0_cap1) + 2 downto 3 * pnum_gpio3_af1_t0_cap1) = "001"
                           else prt3_in(pnum_gpio2_t0_cap1);
        t1_cap0_in      <= prt4_in(pnum_gpio3_af1_t1_cap0)
                           when p4_afs((3 * pnum_gpio3_af1_t1_cap0) + 2 downto 3 * pnum_gpio3_af1_t1_cap0) = "001"
                           else prt3_in(pnum_gpio2_t1_cap0);
        t1_cap1_in      <= prt4_in(pnum_gpio3_af1_t1_cap1)
                           when p4_afs((3 * pnum_gpio3_af1_t1_cap1) + 2 downto 3 * pnum_gpio3_af1_t1_cap1) = "001"
                           else prt3_in(pnum_gpio2_t1_cap1);
        t0_cap0_ren_in  <= p4_ren(pnum_gpio3_af1_t0_cap0)
                           when p4_afs((3 * pnum_gpio3_af1_t0_cap0) + 2 downto 3 * pnum_gpio3_af1_t0_cap0) = "001"
                           else p3_ren(pnum_gpio2_t0_cap0);
        t1_cap0_ren_in  <= p4_ren(pnum_gpio3_af1_t1_cap0)
                           when p4_afs((3 * pnum_gpio3_af1_t1_cap0) + 2 downto 3 * pnum_gpio3_af1_t1_cap0) = "001"
                           else p3_ren(pnum_gpio2_t1_cap0);
        t0_cap1_ren_in  <= p4_ren(pnum_gpio3_af1_t0_cap1)
                           when p4_afs((3 * pnum_gpio3_af1_t0_cap1) + 2 downto 3 * pnum_gpio3_af1_t0_cap1) = "001"
                           else p3_ren(pnum_gpio2_t0_cap1);
        t1_cap1_ren_in  <= p4_ren(pnum_gpio3_af1_t1_cap1)
                           when p4_afs((3 * pnum_gpio3_af1_t1_cap1) + 2 downto 3 * pnum_gpio3_af1_t1_cap1) = "001"
                           else p3_ren(pnum_gpio2_t1_cap1);


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

        -- AF1 plane: UART1 relocation on P3.0/1, I2C1 relocation on P3.2/3,
        -- UART0 relocation on P3.4/5, I2C0 relocation on P3.6/7 (v2) — the
        -- full serial-relocation row (both UARTs + both I2C buses).
        afunc3_af1_out <= (
            pnum_gpio2_af1_scl0 => scl0_out,    -- GPIO2 pin 7
            pnum_gpio2_af1_sda0 => sda0_out,    -- GPIO2 pin 6
            pnum_gpio2_af1_rx0  => rx0_out,     -- GPIO2 pin 5
            pnum_gpio2_af1_tx0  => tx0_out,     -- GPIO2 pin 4
            pnum_gpio2_af1_scl1 => scl1_out,    -- GPIO2 pin 3
            pnum_gpio2_af1_sda1 => sda1_out,    -- GPIO2 pin 2
            pnum_gpio2_af1_rx1  => rx1_out,     -- GPIO2 pin 1
            pnum_gpio2_af1_tx1  => tx1_out      -- GPIO2 pin 0
        );
        afunc3_af1_dir <= (
            pnum_gpio2_af1_scl0 => scl0_dir,    -- GPIO2 pin 7
            pnum_gpio2_af1_sda0 => sda0_dir,    -- GPIO2 pin 6
            pnum_gpio2_af1_rx0  => rx0_dir,     -- GPIO2 pin 5
            pnum_gpio2_af1_tx0  => tx0_dir,     -- GPIO2 pin 4
            pnum_gpio2_af1_scl1 => scl1_dir,    -- GPIO2 pin 3
            pnum_gpio2_af1_sda1 => sda1_dir,    -- GPIO2 pin 2
            pnum_gpio2_af1_rx1  => rx1_dir,     -- GPIO2 pin 1
            pnum_gpio2_af1_tx1  => tx1_dir      -- GPIO2 pin 0
        );
        afunc3_af1_ren <= (
            pnum_gpio2_af1_scl0 => scl0_ren,    -- GPIO2 pin 7
            pnum_gpio2_af1_sda0 => sda0_ren,    -- GPIO2 pin 6
            pnum_gpio2_af1_rx0  => rx0_ren,     -- GPIO2 pin 5
            pnum_gpio2_af1_tx0  => tx0_ren,     -- GPIO2 pin 4
            pnum_gpio2_af1_scl1 => scl1_ren,    -- GPIO2 pin 3
            pnum_gpio2_af1_sda1 => sda1_ren,    -- GPIO2 pin 2
            pnum_gpio2_af1_rx1  => rx1_ren,     -- GPIO2 pin 1
            pnum_gpio2_af1_tx1  => tx1_ren      -- GPIO2 pin 0
        );

        -- Flattened AF planes (7 downto 2 unassigned)
        -- GPIO2 AF output-function spread: aggregates + 8-plane flatten
        afunc3_af2_out <= (
            7 => mosi1_out,
            6 => sck1_out,
            5 => tx0_out,
            4 => t0_cmp1_out,
            3 => t0_cmp1_out,
            2 => t0_cmp0_out,
            1 => t1_cmp0_out,
            0 => sck1_out
        );
        afunc3_af2_dir <= (
            7 => mosi1_dir,
            6 => sck1_dir,
            5 => tx0_dir,
            4 => t0_cmp1_dir,
            3 => t0_cmp1_dir,
            2 => t0_cmp0_dir,
            1 => t1_cmp0_dir,
            0 => sck1_dir
        );
        afunc3_af2_ren <= (
            7 => mosi1_ren,
            6 => sck1_ren,
            5 => tx0_ren,
            4 => t0_cmp1_ren,
            3 => t0_cmp1_ren,
            2 => t0_cmp0_ren,
            1 => t1_cmp0_ren,
            0 => sck1_ren
        );
        afunc3_af3_out <= (
            7 => tx0_out,
            6 => mosi1_out,
            5 => tx1_out,
            4 => t1_cmp1_out,
            3 => t1_cmp0_out,
            2 => t0_cmp1_out,
            1 => t1_cmp1_out,
            0 => mosi1_out
        );
        afunc3_af3_dir <= (
            7 => tx0_dir,
            6 => mosi1_dir,
            5 => tx1_dir,
            4 => t1_cmp1_dir,
            3 => t1_cmp0_dir,
            2 => t0_cmp1_dir,
            1 => t1_cmp1_dir,
            0 => mosi1_dir
        );
        afunc3_af3_ren <= (
            7 => tx0_ren,
            6 => mosi1_ren,
            5 => tx1_ren,
            4 => t1_cmp1_ren,
            3 => t1_cmp0_ren,
            2 => t0_cmp1_ren,
            1 => t1_cmp1_ren,
            0 => mosi1_ren
        );
        afunc3_af4_out <= (
            7 => tx1_out,
            6 => tx0_out,
            5 => t0_cmp0_out,
            4 => sck1_out,
            3 => t1_cmp1_out,
            2 => t1_cmp0_out,
            1 => sck1_out,
            0 => tx0_out
        );
        afunc3_af4_dir <= (
            7 => tx1_dir,
            6 => tx0_dir,
            5 => t0_cmp0_dir,
            4 => sck1_dir,
            3 => t1_cmp1_dir,
            2 => t1_cmp0_dir,
            1 => sck1_dir,
            0 => tx0_dir
        );
        afunc3_af4_ren <= (
            7 => tx1_ren,
            6 => tx0_ren,
            5 => t0_cmp0_ren,
            4 => sck1_ren,
            3 => t1_cmp1_ren,
            2 => t1_cmp0_ren,
            1 => sck1_ren,
            0 => tx0_ren
        );
        afunc3_af5_out <= (
            7 => t0_cmp0_out,
            6 => tx1_out,
            5 => t0_cmp1_out,
            4 => mosi1_out,
            3 => sck1_out,
            2 => t1_cmp1_out,
            1 => mosi1_out,
            0 => t0_cmp1_out
        );
        afunc3_af5_dir <= (
            7 => t0_cmp0_dir,
            6 => tx1_dir,
            5 => t0_cmp1_dir,
            4 => mosi1_dir,
            3 => sck1_dir,
            2 => t1_cmp1_dir,
            1 => mosi1_dir,
            0 => t0_cmp1_dir
        );
        afunc3_af5_ren <= (
            7 => t0_cmp0_ren,
            6 => tx1_ren,
            5 => t0_cmp1_ren,
            4 => mosi1_ren,
            3 => sck1_ren,
            2 => t1_cmp1_ren,
            1 => mosi1_ren,
            0 => t0_cmp1_ren
        );
        afunc3_af6_out <= (
            7 => t0_cmp1_out,
            6 => t0_cmp0_out,
            5 => t1_cmp0_out,
            4 => tx1_out,
            3 => mosi1_out,
            2 => sck1_out,
            1 => tx0_out,
            0 => t1_cmp0_out
        );
        afunc3_af6_dir <= (
            7 => t0_cmp1_dir,
            6 => t0_cmp0_dir,
            5 => t1_cmp0_dir,
            4 => tx1_dir,
            3 => mosi1_dir,
            2 => sck1_dir,
            1 => tx0_dir,
            0 => t1_cmp0_dir
        );
        afunc3_af6_ren <= (
            7 => t0_cmp1_ren,
            6 => t0_cmp0_ren,
            5 => t1_cmp0_ren,
            4 => tx1_ren,
            3 => mosi1_ren,
            2 => sck1_ren,
            1 => tx0_ren,
            0 => t1_cmp0_ren
        );
        afunc3_af7_out <= (
            7 => t1_cmp0_out,
            6 => t0_cmp1_out,
            5 => sck1_out,
            4 => t0_cmp0_out,
            3 => tx0_out,
            2 => mosi1_out,
            1 => tx1_out,
            0 => t1_cmp1_out
        );
        afunc3_af7_dir <= (
            7 => t1_cmp0_dir,
            6 => t0_cmp1_dir,
            5 => sck1_dir,
            4 => t0_cmp0_dir,
            3 => tx0_dir,
            2 => mosi1_dir,
            1 => tx1_dir,
            0 => t1_cmp1_dir
        );
        afunc3_af7_ren <= (
            7 => t1_cmp0_ren,
            6 => t0_cmp1_ren,
            5 => sck1_ren,
            4 => t0_cmp0_ren,
            3 => tx0_ren,
            2 => mosi1_ren,
            1 => tx1_ren,
            0 => t1_cmp1_ren
        );
        afunc3_all_out <= afunc3_af7_out & afunc3_af6_out & afunc3_af5_out & afunc3_af4_out & afunc3_af3_out & afunc3_af2_out & afunc3_af1_out & afunc3_out;
        afunc3_all_dir <= afunc3_af7_dir & afunc3_af6_dir & afunc3_af5_dir & afunc3_af4_dir & afunc3_af3_dir & afunc3_af2_dir & afunc3_af1_dir & afunc3_dir;
        afunc3_all_ren <= afunc3_af7_ren & afunc3_af6_ren & afunc3_af5_ren & afunc3_af4_ren & afunc3_af3_ren & afunc3_af2_ren & afunc3_af1_ren & afunc3_ren;



    -- GPIO3 Connections (I2C0, I2C1, DTP) ------------------------------------------------------------

        -- Resistor Enables (I2C0 relocates to P2.6/7 or P3.6/7 (v2), I2C1 to
        -- P3.2/3 or P2.4/5 (v2) — the peripheral ren_in follows the same AF
        -- selection as the inputs below, fixed priority: v2 pad > AF1 pad > home)
        sda0_ren_in <= p3_ren(pnum_gpio2_af1_sda0)
                       when p3_afs((3 * pnum_gpio2_af1_sda0) + 2 downto 3 * pnum_gpio2_af1_sda0) = "001"
                       else p2_ren(pnum_gpio1_af1_sda0)
                       when p2_afs((3 * pnum_gpio1_af1_sda0) + 2 downto 3 * pnum_gpio1_af1_sda0) = "001"
                       else p4_ren(pnum_gpio3_sda0);
        scl0_ren_in <= p3_ren(pnum_gpio2_af1_scl0)
                       when p3_afs((3 * pnum_gpio2_af1_scl0) + 2 downto 3 * pnum_gpio2_af1_scl0) = "001"
                       else p2_ren(pnum_gpio1_af1_scl0)
                       when p2_afs((3 * pnum_gpio1_af1_scl0) + 2 downto 3 * pnum_gpio1_af1_scl0) = "001"
                       else p4_ren(pnum_gpio3_scl0);
        sda1_ren_in <= p2_ren(pnum_gpio1_af1_sda1)
                       when p2_afs((3 * pnum_gpio1_af1_sda1) + 2 downto 3 * pnum_gpio1_af1_sda1) = "001"
                       else p3_ren(pnum_gpio2_af1_sda1)
                       when p3_afs((3 * pnum_gpio2_af1_sda1) + 2 downto 3 * pnum_gpio2_af1_sda1) = "001"
                       else p4_ren(pnum_gpio3_sda1);
        scl1_ren_in <= p2_ren(pnum_gpio1_af1_scl1)
                       when p2_afs((3 * pnum_gpio1_af1_scl1) + 2 downto 3 * pnum_gpio1_af1_scl1) = "001"
                       else p3_ren(pnum_gpio2_af1_scl1)
                       when p3_afs((3 * pnum_gpio2_af1_scl1) + 2 downto 3 * pnum_gpio2_af1_scl1) = "001"
                       else p4_ren(pnum_gpio3_scl1);

        -- Inputs (relocated pad wins, home pad is the default)
        sda0_in <= prt3_in(pnum_gpio2_af1_sda0)
                   when p3_afs((3 * pnum_gpio2_af1_sda0) + 2 downto 3 * pnum_gpio2_af1_sda0) = "001"
                   else prt2_in(pnum_gpio1_af1_sda0)
                   when p2_afs((3 * pnum_gpio1_af1_sda0) + 2 downto 3 * pnum_gpio1_af1_sda0) = "001"
                   else prt4_in(pnum_gpio3_sda0);
        scl0_in <= prt3_in(pnum_gpio2_af1_scl0)
                   when p3_afs((3 * pnum_gpio2_af1_scl0) + 2 downto 3 * pnum_gpio2_af1_scl0) = "001"
                   else prt2_in(pnum_gpio1_af1_scl0)
                   when p2_afs((3 * pnum_gpio1_af1_scl0) + 2 downto 3 * pnum_gpio1_af1_scl0) = "001"
                   else prt4_in(pnum_gpio3_scl0);
        sda1_in <= prt2_in(pnum_gpio1_af1_sda1)
                   when p2_afs((3 * pnum_gpio1_af1_sda1) + 2 downto 3 * pnum_gpio1_af1_sda1) = "001"
                   else prt3_in(pnum_gpio2_af1_sda1)
                   when p3_afs((3 * pnum_gpio2_af1_sda1) + 2 downto 3 * pnum_gpio2_af1_sda1) = "001"
                   else prt4_in(pnum_gpio3_sda1);
        scl1_in <= prt2_in(pnum_gpio1_af1_scl1)
                   when p2_afs((3 * pnum_gpio1_af1_scl1) + 2 downto 3 * pnum_gpio1_af1_scl1) = "001"
                   else prt3_in(pnum_gpio2_af1_scl1)
                   when p3_afs((3 * pnum_gpio2_af1_scl1) + 2 downto 3 * pnum_gpio2_af1_scl1) = "001"
                   else prt4_in(pnum_gpio3_scl1);

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

        -- AF1 plane: TIMER0/1 capture inputs relocate to P4.0-3 (the I2C pins),
        -- TIMER0/1 compare (PWM) outputs relocate to P4.4-7 (the dead DTP pins).
        -- Captures are inputs: out slice '0', dir/ren from the timer.
        afunc4_af1_out <= (
            pnum_gpio3_af1_t1_cmp1 => t1_cmp1_out,  -- GPIO3 pin 7
            pnum_gpio3_af1_t1_cmp0 => t1_cmp0_out,  -- GPIO3 pin 6
            pnum_gpio3_af1_t0_cmp1 => t0_cmp1_out,  -- GPIO3 pin 5
            pnum_gpio3_af1_t0_cmp0 => t0_cmp0_out,  -- GPIO3 pin 4
            pnum_gpio3_af1_t1_cap1 => '0',          -- GPIO3 pin 3
            pnum_gpio3_af1_t1_cap0 => '0',          -- GPIO3 pin 2
            pnum_gpio3_af1_t0_cap1 => '0',          -- GPIO3 pin 1
            pnum_gpio3_af1_t0_cap0 => '0'           -- GPIO3 pin 0
        );
        afunc4_af1_dir <= (
            pnum_gpio3_af1_t1_cmp1 => t1_cmp1_dir,  -- GPIO3 pin 7
            pnum_gpio3_af1_t1_cmp0 => t1_cmp0_dir,  -- GPIO3 pin 6
            pnum_gpio3_af1_t0_cmp1 => t0_cmp1_dir,  -- GPIO3 pin 5
            pnum_gpio3_af1_t0_cmp0 => t0_cmp0_dir,  -- GPIO3 pin 4
            pnum_gpio3_af1_t1_cap1 => t1_cap1_dir,  -- GPIO3 pin 3
            pnum_gpio3_af1_t1_cap0 => t1_cap0_dir,  -- GPIO3 pin 2
            pnum_gpio3_af1_t0_cap1 => t0_cap1_dir,  -- GPIO3 pin 1
            pnum_gpio3_af1_t0_cap0 => t0_cap0_dir   -- GPIO3 pin 0
        );
        afunc4_af1_ren <= (
            pnum_gpio3_af1_t1_cmp1 => t1_cmp1_ren,  -- GPIO3 pin 7
            pnum_gpio3_af1_t1_cmp0 => t1_cmp0_ren,  -- GPIO3 pin 6
            pnum_gpio3_af1_t0_cmp1 => t0_cmp1_ren,  -- GPIO3 pin 5
            pnum_gpio3_af1_t0_cmp0 => t0_cmp0_ren,  -- GPIO3 pin 4
            pnum_gpio3_af1_t1_cap1 => t1_cap1_ren,  -- GPIO3 pin 3
            pnum_gpio3_af1_t1_cap0 => t1_cap0_ren,  -- GPIO3 pin 2
            pnum_gpio3_af1_t0_cap1 => t0_cap1_ren,  -- GPIO3 pin 1
            pnum_gpio3_af1_t0_cap0 => t0_cap0_ren   -- GPIO3 pin 0
        );

        -- Flattened AF planes (7 downto 2 unassigned)
        -- GPIO3 AF output-function spread: aggregates + 8-plane flatten
        afunc4_af2_out <= (
            7 => t0_cmp1_out,
            6 => t0_cmp0_out,
            5 => rx0_out,
            4 => tx0_out,
            3 => t0_cmp1_out,
            2 => t0_cmp0_out,
            1 => tx1_out,
            0 => tx0_out
        );
        afunc4_af2_dir <= (
            7 => t0_cmp1_dir,
            6 => t0_cmp0_dir,
            5 => rx0_dir,
            4 => tx0_dir,
            3 => t0_cmp1_dir,
            2 => t0_cmp0_dir,
            1 => tx1_dir,
            0 => tx0_dir
        );
        afunc4_af2_ren <= (
            7 => t0_cmp1_ren,
            6 => t0_cmp0_ren,
            5 => rx0_ren,
            4 => tx0_ren,
            3 => t0_cmp1_ren,
            2 => t0_cmp0_ren,
            1 => tx1_ren,
            0 => tx0_ren
        );
        afunc4_af3_out <= (
            7 => t1_cmp0_out,
            6 => t0_cmp1_out,
            5 => t0_cmp0_out,
            4 => tx1_out,
            3 => t1_cmp0_out,
            2 => t0_cmp1_out,
            1 => t0_cmp0_out,
            0 => tx1_out
        );
        afunc4_af3_dir <= (
            7 => t1_cmp0_dir,
            6 => t0_cmp1_dir,
            5 => t0_cmp0_dir,
            4 => tx1_dir,
            3 => t1_cmp0_dir,
            2 => t0_cmp1_dir,
            1 => t0_cmp0_dir,
            0 => tx1_dir
        );
        afunc4_af3_ren <= (
            7 => t1_cmp0_ren,
            6 => t0_cmp1_ren,
            5 => t0_cmp0_ren,
            4 => tx1_ren,
            3 => t1_cmp0_ren,
            2 => t0_cmp1_ren,
            1 => t0_cmp0_ren,
            0 => tx1_ren
        );
        afunc4_af4_out <= (
            7 => sck1_out,
            6 => t1_cmp1_out,
            5 => t1_cmp0_out,
            4 => t0_cmp1_out,
            3 => t1_cmp1_out,
            2 => t1_cmp0_out,
            1 => t0_cmp1_out,
            0 => t0_cmp0_out
        );
        afunc4_af4_dir <= (
            7 => sck1_dir,
            6 => t1_cmp1_dir,
            5 => t1_cmp0_dir,
            4 => t0_cmp1_dir,
            3 => t1_cmp1_dir,
            2 => t1_cmp0_dir,
            1 => t0_cmp1_dir,
            0 => t0_cmp0_dir
        );
        afunc4_af4_ren <= (
            7 => sck1_ren,
            6 => t1_cmp1_ren,
            5 => t1_cmp0_ren,
            4 => t0_cmp1_ren,
            3 => t1_cmp1_ren,
            2 => t1_cmp0_ren,
            1 => t0_cmp1_ren,
            0 => t0_cmp0_ren
        );
        afunc4_af5_out <= (
            7 => mosi1_out,
            6 => sck1_out,
            5 => t1_cmp1_out,
            4 => t1_cmp0_out,
            3 => sck1_out,
            2 => t1_cmp1_out,
            1 => t1_cmp0_out,
            0 => t0_cmp1_out
        );
        afunc4_af5_dir <= (
            7 => mosi1_dir,
            6 => sck1_dir,
            5 => t1_cmp1_dir,
            4 => t1_cmp0_dir,
            3 => sck1_dir,
            2 => t1_cmp1_dir,
            1 => t1_cmp0_dir,
            0 => t0_cmp1_dir
        );
        afunc4_af5_ren <= (
            7 => mosi1_ren,
            6 => sck1_ren,
            5 => t1_cmp1_ren,
            4 => t1_cmp0_ren,
            3 => sck1_ren,
            2 => t1_cmp1_ren,
            1 => t1_cmp0_ren,
            0 => t0_cmp1_ren
        );
        afunc4_af6_out <= (
            7 => tx0_out,
            6 => mosi1_out,
            5 => sck1_out,
            4 => t1_cmp1_out,
            3 => mosi1_out,
            2 => sck1_out,
            1 => t1_cmp1_out,
            0 => t1_cmp0_out
        );
        afunc4_af6_dir <= (
            7 => tx0_dir,
            6 => mosi1_dir,
            5 => sck1_dir,
            4 => t1_cmp1_dir,
            3 => mosi1_dir,
            2 => sck1_dir,
            1 => t1_cmp1_dir,
            0 => t1_cmp0_dir
        );
        afunc4_af6_ren <= (
            7 => tx0_ren,
            6 => mosi1_ren,
            5 => sck1_ren,
            4 => t1_cmp1_ren,
            3 => mosi1_ren,
            2 => sck1_ren,
            1 => t1_cmp1_ren,
            0 => t1_cmp0_ren
        );
        afunc4_af7_out <= (
            7 => tx1_out,
            6 => miso1_out,
            5 => mosi1_out,
            4 => sck1_out,
            3 => tx0_out,
            2 => mosi1_out,
            1 => sck1_out,
            0 => t1_cmp1_out
        );
        afunc4_af7_dir <= (
            7 => tx1_dir,
            6 => miso1_dir,
            5 => mosi1_dir,
            4 => sck1_dir,
            3 => tx0_dir,
            2 => mosi1_dir,
            1 => sck1_dir,
            0 => t1_cmp1_dir
        );
        afunc4_af7_ren <= (
            7 => tx1_ren,
            6 => miso1_ren,
            5 => mosi1_ren,
            4 => sck1_ren,
            3 => tx0_ren,
            2 => mosi1_ren,
            1 => sck1_ren,
            0 => t1_cmp1_ren
        );
        afunc4_all_out <= afunc4_af7_out & afunc4_af6_out & afunc4_af5_out & afunc4_af4_out & afunc4_af3_out & afunc4_af2_out & afunc4_af1_out & afunc4_out;
        afunc4_all_dir <= afunc4_af7_dir & afunc4_af6_dir & afunc4_af5_dir & afunc4_af4_dir & afunc4_af3_dir & afunc4_af2_dir & afunc4_af1_dir & afunc4_dir;
        afunc4_all_ren <= afunc4_af7_ren & afunc4_af6_ren & afunc4_af5_ren & afunc4_af4_ren & afunc4_af3_ren & afunc4_af2_ren & afunc4_af1_ren & afunc4_ren;


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
            IRQB_RSVD55     => afe_eis_irq(0) or afe_eis_irq(1) or afe_eis_irq(2) or afe_eis_irq(3),
            IRQB_RSVD56     => afe_eis_irq(4),
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
            IRQB_GPIO4_B0   => irq_gpio4(0),
            IRQB_GPIO4_B1   => irq_gpio4(1),
            IRQB_GPIO4_B2   => irq_gpio4(2),
            IRQB_GPIO4_B3   => irq_gpio4(3),
            IRQB_GPIO4_B4   => irq_gpio4(4),
            IRQB_GPIO4_B5   => irq_gpio4(5),
            IRQB_GPIO4_B6   => irq_gpio4(6),
            IRQB_GPIO4_B7   => irq_gpio4(7),
            IRQB_GPIO5_B0   => irq_gpio5(0),
            IRQB_GPIO5_B1   => irq_gpio5(1),
            IRQB_GPIO5_B2   => irq_gpio5(2),
            IRQB_GPIO5_B3   => irq_gpio5(3),
            IRQB_GPIO5_B4   => irq_gpio5(4),
            IRQB_GPIO5_B5   => irq_gpio5(5),
            IRQB_GPIO5_B6   => irq_gpio5(6),
            IRQB_GPIO5_B7   => irq_gpio5(7),
            -- M19: the CLINT slots (83/84) fall through to irq_tielow — every
            -- hart gets its own msip/mtip on dedicated wires; the source
            -- vector feeds ONLY the irq_router (meip claim/complete delivery)
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
    --   * tcm_pgen -> pgen_mem(1) (BLOCKPWR RAM gating),
    --   * trap_flag -> the GPIO0 trap pin; a0 -> the tb pass/fail gate.
    -- M19: the IRQ interface is IDENTICAL on every hart — msip/mtip from
    -- the CLINT + this hart's meip row from the irq_router (SYSTEM0's
    -- vectored path and the hw_clint_en strap are retired).
    -- The M2 wait_inj0 stall exerciser is RETIRED (M10 proved latency
    -- insensitivity at boundary depths 0/1/2; the boot fetch through the
    -- arbiter exercises the stall path on every run).
    -- =========================================================================
    hart0: entity work.hart_tile
        generic map (
            PC_RST_VAL     => x"00000000",
            SH_AW          => SH_AW,
            -- Core ISA features (config-driven, work.MemoryMap; MUST be
            -- identical on all four tiles -- one hardened netlist)
            ENABLE_MUL        => CORE_ENABLE_MUL,
            ENABLE_DIV        => CORE_ENABLE_DIV,
            ENABLE_ATOMICS    => CORE_ENABLE_ATOMICS,
            ENABLE_COMPRESSED => CORE_ENABLE_COMPRESSED,
            ENABLE_BITMANIP   => CORE_ENABLE_BITMANIP,
            ENABLE_ZICOND     => CORE_ENABLE_ZICOND,
            ENABLE_ZCB        => CORE_ENABLE_ZCB,
            ENABLE_ZIMOP      => CORE_ENABLE_ZIMOP,
            ENABLE_ZIHINT     => CORE_ENABLE_ZIHINT,
            ENABLE_ZIHPM      => CORE_ENABLE_ZIHPM,
            ENABLE_ZAWRS      => CORE_ENABLE_ZAWRS,
            ENABLE_ZABHA      => CORE_ENABLE_ZABHA,
            ENABLE_ZACAS      => CORE_ENABLE_ZACAS,
            ENABLE_ZICBOZ     => CORE_ENABLE_ZICBOZ,
            ENABLE_ZCMP       => CORE_ENABLE_ZCMP,
            ENABLE_ZCMT       => CORE_ENABLE_ZCMT,
            ENABLE_ZBKB       => CORE_ENABLE_ZBKB,
            ENABLE_ZBKC       => CORE_ENABLE_ZBKC,
            ENABLE_ZBKX       => CORE_ENABLE_ZBKX,
            ENABLE_ZKN        => CORE_ENABLE_ZKN,
            ENABLE_ZFINX      => CORE_ENABLE_ZFINX
        )
        port map (
            clk       => mclk,
            resetn    => resetn,
            sleep     => sleep_cpu,
            hart_id   => x"00000000",
            msip_in   => clint_msip(0),
            mtip_in   => clint_mtip(0),
            meip_in   => meip(0),
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
            sh_resv_valid => arb_resvvld(0),
            sh_lock   => arb_lock(0),
            tcm_pgen  => pgen_mem(1),
            tcm_retn  => '1',
            -- M17: hart 0 is ALWAYS-ON — its domain controls are strapped
            -- inactive (explicit, per the M14 netlist-boundary rule)
            pd_sleep  => '0',
            pd_iso_en => '0',
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
            sc_fail    => arb_scfail,
            resv_valid_o => arb_resvvld   -- X1 Zawrs: per-master reservation-valid level to the tiles
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
    -- Mission B: page-2 (MUTEX/0x6000) carved into 256 B sub-slots on
    -- sh_addr(9:6). Mutex bank = sub-slot 0 (0x6000-0x60FF); I3C0 sub-slot 1
    -- (0x6100), NFC0 sub-slot 2 (0x6200), GPIO4 sub-slot 3 (0x6300), GPIO5
    -- sub-slot 4 (0x6400). Tightening the mutex decode retires the aliased
    -- CLAIM side effect (all 16 mutexes live below 0x6040 = behaviorally safe).
    shslv_mtx_sel    <= shslv_perwin_sel when sh_addr(11 downto 10) = "10" and sh_addr(9 downto 6) = "0000" else '0';
    shslv_gpio4_sel  <= shslv_perwin_sel when sh_addr(11 downto 10) = "10" and sh_addr(9 downto 6) = "0011" else '0';
    shslv_gpio5_sel  <= shslv_perwin_sel when sh_addr(11 downto 10) = "10" and sh_addr(9 downto 6) = "0100" else '0';
    -- CQ2a: page-3 sub-decode — irq_router keeps 0x7000-0x7BFF; the shared
    -- EIS engine stub owns the top quarter 0x7C00-0x7FFF (irq_router ADDR_W=10
    -- decode is inert above word 522, so this removes only never-used aliased space).
    shslv_irtr_sel   <= shslv_perwin_sel when sh_addr(11 downto 10) = "11" and sh_addr(9 downto 8) /= "11" else '0';
    shslv_eis_sel    <= shslv_perwin_sel when sh_addr(11 downto 10) = "11" and sh_addr(9 downto 8) = "11" else '0';
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
    shslv_gpio3_sel  <= shslv_pg0_sel when sh_addr(9 downto 6) = "1101" else '0';
    shslv_i2c0_sel   <= shslv_pg0_sel when sh_addr(9 downto 6) = "1110" else '0';
    shslv_i2c1_sel   <= shslv_pg0_sel when sh_addr(9 downto 6) = "1111" else '0';
    -- M17: the power controller is a NATIVE slave IN a page-0 slot (11,
    -- 0x4B00 — vacated by SARADC0): slot-decoded like the peripherals
    -- above, but it speaks the arbiter protocol directly (no shim).
    shslv_pwr_sel    <= shslv_pg0_sel when sh_addr(9 downto 6) = "1011" else '0';
    -- CQ2a: AFE stubs subdivide page-0 slot 12 (0x4C00) into four 64 B
    -- sub-slots on sh_addr(5:4); the s_master ownership gate is inside afe_stub.
    shslv_afe_sel    <= shslv_pg0_sel when sh_addr(9 downto 6) = "1100" else '0';
    shslv_afe0_sel   <= shslv_afe_sel when sh_addr(5 downto 4) = "00" else '0';
    shslv_afe1_sel   <= shslv_afe_sel when sh_addr(5 downto 4) = "01" else '0';
    shslv_afe2_sel   <= shslv_afe_sel when sh_addr(5 downto 4) = "10" else '0';
    shslv_afe3_sel   <= shslv_afe_sel when sh_addr(5 downto 4) = "11" else '0';
    shslv_rom_en     <= sh_en and shslv_rom_sel;
    shslv_npuram_en  <= sh_en and shslv_npuram_sel;
    shslv_bank0_en   <= sh_en and shslv_bank0_sel;
    shslv_bank1_en   <= sh_en and shslv_bank1_sel;
    shslv_bank2_en   <= sh_en and shslv_bank2_sel;
    shslv_bank3_en   <= sh_en and shslv_bank3_sel;
    shslv_clint_en   <= sh_en and shslv_clint_sel;
    shslv_mtx_en     <= sh_en and shslv_mtx_sel;
    shslv_irtr_en    <= sh_en and shslv_irtr_sel;
    shslv_pwr_en     <= sh_en and shslv_pwr_sel;
    shslv_gpio4_en   <= sh_en and shslv_gpio4_sel;
    shslv_gpio5_en   <= sh_en and shslv_gpio5_sel;
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
    shslv_gpio3_en   <= sh_en and shslv_gpio3_sel;
    shslv_i2c0_en    <= sh_en and shslv_i2c0_sel;
    shslv_i2c1_en    <= sh_en and shslv_i2c1_sel;
    shslv_afe0_en    <= sh_en and shslv_afe0_sel;
    shslv_afe1_en    <= sh_en and shslv_afe1_sel;
    shslv_afe2_en    <= sh_en and shslv_afe2_sel;
    shslv_afe3_en    <= sh_en and shslv_afe3_sel;
    shslv_eis_en     <= sh_en and shslv_eis_sel;

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
            shslv_rd_pwr     <= '0';
            shslv_rd_gpio4   <= '0';
            shslv_rd_gpio5   <= '0';
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
            shslv_rd_gpio3   <= '0';
            shslv_rd_i2c0    <= '0';
            shslv_rd_i2c1    <= '0';
            shslv_rd_afe0    <= '0';
            shslv_rd_afe1    <= '0';
            shslv_rd_afe2    <= '0';
            shslv_rd_afe3    <= '0';
            shslv_rd_eis     <= '0';
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
                shslv_rd_pwr     <= shslv_pwr_sel;
                shslv_rd_gpio4   <= shslv_gpio4_sel;
                shslv_rd_gpio5   <= shslv_gpio5_sel;
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
                shslv_rd_gpio3   <= shslv_gpio3_sel;
                shslv_rd_i2c0    <= shslv_i2c0_sel;
                shslv_rd_i2c1    <= shslv_i2c1_sel;
                shslv_rd_afe0    <= shslv_afe0_sel;
                shslv_rd_afe1    <= shslv_afe1_sel;
                shslv_rd_afe2    <= shslv_afe2_sel;
                shslv_rd_afe3    <= shslv_afe3_sel;
                shslv_rd_eis     <= shslv_eis_sel;
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
                    pwr_rdata      when shslv_rd_pwr     = '1' else
                    gpio4_sh_rdata when shslv_rd_gpio4   = '1' else
                    gpio5_sh_rdata when shslv_rd_gpio5   = '1' else
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
                    gpio3_sh_rdata when shslv_rd_gpio3   = '1' else
                    i2c0_sh_rdata  when shslv_rd_i2c0    = '1' else
                    i2c1_sh_rdata  when shslv_rd_i2c1    = '1' else
                    afe0_rdata     when shslv_rd_afe0    = '1' else
                    afe1_rdata     when shslv_rd_afe1    = '1' else
                    afe2_rdata     when shslv_rd_afe2    = '1' else
                    afe3_rdata     when shslv_rd_afe3    = '1' else
                    eis_rdata      when shslv_rd_eis     = '1' else
                    (others => '0');  -- no slave (TCM page, unmapped)

    -- X-collapse fix (2026-07-20): SPI/UART/TIMER/I2C (and QSPI when
    -- configured) CLOCK their status/RX snapshot registers on en_mem's
    -- FALLING EDGE (the falling_edge(en_mem) idiom inside the
    -- peripherals). sh_en/sh_addr are registered arbiter outputs, so the
    -- combinational en AND decode below glitches only in the skew window
    -- right after each rising mclk edge — and a glitch there is a
    -- spurious capture-clock edge racing its own D (the gate-level
    -- X-collapse; root cause + proof: digperiphs xcollapse_findings).
    -- Those shims therefore take a FALLING-MCLK re-registered strobe:
    -- half a cycle later the decode has long settled, and every other
    -- en_mem consumer samples on rising mclk edges, for which the
    -- registered strobe is indistinguishable from the raw one.
    snapshot_strobe_reg: process(mclk)
    begin
        if falling_edge(mclk) then
            shslv_uart0_en_q <= shslv_uart0_en;
            shslv_tim0_en_q  <= shslv_tim0_en;
            shslv_tim1_en_q  <= shslv_tim1_en;
            shslv_spi1_en_q  <= shslv_spi1_en;
            shslv_uart1_en_q <= shslv_uart1_en;
            shslv_i2c0_en_q  <= shslv_i2c0_en;
            shslv_i2c1_en_q  <= shslv_i2c1_en;
            shslv_spi0_en_q  <= shslv_spi0_en;
        end if;
    end process;

    -- M6: bridge the arbiter slave port onto UART0's adddec-style register bus.
    -- UART.vhd already obeys the 1-cycle registered-read contract
    -- (reg_read_proc) and qualifies every write by en_mem='0', so the bridge is
    -- pure polarity/width adaptation: en_mem is the active-LOW one-cycle access
    -- strobe, wen the active-LOW byte lanes (from the resv-GATED sh_we — a
    -- suppressed SC write must not touch the UART), and clk_mem is the
    -- free-running mclk (the gated-clock "stuck clear-pulse" behaviour of the
    -- old private periph bus disappears: clr_* become true one-cycle pulses,
    -- consumed asynchronously by the TX/RX FSMs).
    uart0_sh_en_n  <= not shslv_uart0_en_q;
    sh_wen_n <= not sh_we;

    -- M7b: same polarity shim for the moved TIMER/GPIO blocks (active-LOW
    -- one-cycle en strobes; they share sh_wen_n's active-low lanes —
    -- all from the resv-GATED sh_we, so a suppressed SC write can't touch
    -- any shared peripheral). clk_mem = free-running mclk everywhere; the
    -- M7b audit found TIMER and GPIO both already en-qualify every write and
    -- register every read (UART-class movers) — their un-en-qualified logic
    -- (timer core, pin IRQ flags) runs on its OWN muxed/pin clocks, not
    -- clk_mem, so the gated->free-running change is invariant for them.
    tim0_sh_en_n  <= not shslv_tim0_en_q;
    tim1_sh_en_n  <= not shslv_tim1_en_q;
    gpio1_sh_en_n <= not shslv_gpio1_en;
    gpio2_sh_en_n <= not shslv_gpio2_en;
    gpio3_sh_en_n <= not shslv_gpio3_en;
    -- M7c: SPI1 + UART1 (audited clean; SPI1's flash FSM is compiled out by
    -- ENABLE_EXTENDED_MEM=false, and its baud core runs on smclk — the
    -- SYS_CLK_CR=0 rule applies to SPI software too)
    spi1_sh_en_n  <= not shslv_spi1_en_q;
    uart1_sh_en_n <= not shslv_uart1_en_q;
    -- M7c.2: I2C0/I2C1 (combinational read handled by i2c_rdata_bridge above;
    -- writes/snapshot-latches audit clean — single en-qualified ClkMem
    -- process, core FSMs on smclk/pin edges)
    i2c0_sh_en_n  <= not shslv_i2c0_en_q;
    i2c1_sh_en_n  <= not shslv_i2c1_en_q;
    -- M7d: NPU register bus (MabMmrCEN was HARDWIRED '0' on the old gated
    -- bus — the clk_periph pulse was the only write qualifier; on the
    -- free-running mclk this strobe IS the qualifier)
    npu_sh_en_n   <= not shslv_npu_en;
    -- M11: the last three private peripherals join the window (the private
    -- peripheral page is GONE). Audited: all five register their reads on
    -- clk_mem — UART-class movers, plain shims, no bridge. SYSTEM0 note:
    -- SYS_CLK_CR/SYS_CLK_DIV_CR reconfigure MCLK ITSELF — reconfiguring
    -- with other masters mid-transaction is a software-contract violation
    -- (management hart quiesces the others first).
    sys_sh_en_n   <= not shslv_sys_en;
    gpio0_sh_en_n <= not shslv_gpio0_en;
    spi0_sh_en_n  <= not shslv_spi0_en_q;

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

    -- M19 PLIC-lite: THE peripheral interrupt controller — per-hart routing
    -- rows (any hart programs any row through the arbiter; resv-gated sh_we
    -- like the CLINT) + CLAIM/COMPLETE delivery @0x7800. The deglitched
    -- source vector TERMINATES here; delivery to harts 0-3 is the one
    -- registered meip wire each (IVT slot 85). sh_master attributes claim
    -- reads (the mutex-bank idiom). Resets all-masked, so this block is a
    -- provable NO-OP until software routes an IRQ. The wdt_* hooks carry
    -- the D2 watchdog contract into SYSTEM0 (source 0's routed/EOI state).
    irtr0: entity work.irq_router
        generic map (NHARTS => 4, NUM_SRCS => NUM_IRQ_SRCS)
        port map (
            clk          => mclk,
            resetn       => resetn,
            en           => shslv_irtr_en,
            we           => sh_we,
            addr         => sh_addr(9 downto 0),
            wdata        => sh_wdata,
            rdata        => irtr_rdata,
            master       => sh_master,
            irq_in       => irq_deglitch,
            meip_out     => meip,
            wdt_routed   => wdt_irq_routed,
            wdt_complete => wdt_irq_complete
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

    -- M17: MTCMOS power controller (window slot 11 @0x4B00, ex-SARADC0).
    -- One gate bit per tile hart; a per-tile FSM sequences the domain
    -- controls in the only legal order (iso -> rst -> rail off; rail on ->
    -- settle -> un-iso -> un-rst). COLD-GATE: pd_rstn folds into the tile's
    -- resetn below, so a wake IS an M12 cold boot (shared-ROM fetch, WFI
    -- park, loader relaunch) — and the reset also makes the functional sims
    -- honest, since reset values equal the A2ISO clamp-0 values on every
    -- outbound tile signal. Resets all-ON -> provable NO-OP until software
    -- gates a tile. Software contract: gate only parked/quiesced tiles.
    pwr0: entity work.pwr_ctrl
        generic map (T_SEQ => 4, T_RAIL => 256)
        port map (
            clk       => mclk,
            resetn    => resetn,
            en        => shslv_pwr_en,
            we        => sh_we,
            addr      => sh_addr(3 downto 0),
            wdata     => sh_wdata,
            rdata     => pwr_rdata,
            pd_iso_en => pd_iso_en,
            pd_sleep  => pd_sleep,
            pd_rstn   => pd_rstn
        );

    -- =========================================================================
    -- CQ2a: AFE digital register stubs + shared EIS engine stub.
    -- Four AFE sites subdivide page-0 slot 12 (0x4C00) into 64 B sub-slots
    -- (sub-slot = sh_addr(5:4)); each answers only for its owner hart OR hart 0
    -- (mp_arbiter s_master gate, inside afe_stub). The EIS engine lives in the
    -- IRQ-router page top quarter (0x7C00-0x7FFF, carved in the sub-decode
    -- above — irq_router's ADDR_W=10 decode is inert there) and is hart-0-only
    -- (OWNER_HART=0). Reads are registered; denied reads return 0, denied
    -- writes drop — no bus error, no stall, no arbiter-contract change. Every
    -- stub resets all-zero -> a provable NO-OP (irq low) until software writes.
    -- =========================================================================
    afe0: entity work.afe_stub
        generic map (OWNER_HART => 0)   -- 0x4C00: hart 0 only
        port map (clk => mclk, resetn => resetn, en => shslv_afe0_en,
            we => sh_we, addr => sh_addr(3 downto 0), wdata => sh_wdata,
            master => sh_master, rdata => afe0_rdata, irq => afe_eis_irq(0));
    afe1: entity work.afe_stub
        generic map (OWNER_HART => 1)   -- 0x4C40: hart 1 or hart 0
        port map (clk => mclk, resetn => resetn, en => shslv_afe1_en,
            we => sh_we, addr => sh_addr(3 downto 0), wdata => sh_wdata,
            master => sh_master, rdata => afe1_rdata, irq => afe_eis_irq(1));
    afe2: entity work.afe_stub
        generic map (OWNER_HART => 2)   -- 0x4C80: hart 2 or hart 0
        port map (clk => mclk, resetn => resetn, en => shslv_afe2_en,
            we => sh_we, addr => sh_addr(3 downto 0), wdata => sh_wdata,
            master => sh_master, rdata => afe2_rdata, irq => afe_eis_irq(2));
    afe3: entity work.afe_stub
        generic map (OWNER_HART => 3)   -- 0x4CC0: hart 3 or hart 0
        port map (clk => mclk, resetn => resetn, en => shslv_afe3_en,
            we => sh_we, addr => sh_addr(3 downto 0), wdata => sh_wdata,
            master => sh_master, rdata => afe3_rdata, irq => afe_eis_irq(3));
    eis0: entity work.afe_stub
        generic map (OWNER_HART => 0)   -- 0x7C00: EIS engine, hart 0 only
        port map (clk => mclk, resetn => resetn, en => shslv_eis_en,
            we => sh_we, addr => sh_addr(3 downto 0), wdata => sh_wdata,
            master => sh_master, rdata => eis_rdata, irq => afe_eis_irq(4));

    -- M17: the cold-gate reset — a gated (or waking) tile is held in reset,
    -- which is also what keeps it bus-silent at the arbiter (sh_req is
    -- qualified by the tile's resetn since M12).
    tile_rstn(1) <= resetn and pd_rstn(1);
    tile_rstn(2) <= resetn and pd_rstn(2);
    tile_rstn(3) <= resetn and pd_rstn(3);

    -- M17 isolation clamps (see the _raw signal comment): every outbound
    -- tile signal is forced to its reset value while pd_iso_en(h) is high,
    -- so the arbiter and the tb never sample a floating pin of a dark
    -- domain. These gates synthesize into the ALWAYS-ON control plane.
    arb_req(1)              <= tile1_req_raw   when pd_iso_en(1) = '0' else '0';
    arb_we(7 downto 4)      <= tile1_we_raw    when pd_iso_en(1) = '0' else (others => '0');
    arb_addr(2*SH_AW-1 downto SH_AW) <= tile1_addr_raw when pd_iso_en(1) = '0' else (others => '0');
    arb_wdata(2*32-1 downto 32)      <= tile1_wdata_raw when pd_iso_en(1) = '0' else (others => '0');
    arb_lrsc(3 downto 2)    <= tile1_lrsc_raw  when pd_iso_en(1) = '0' else "00";
    arb_lock(1)             <= tile1_lock_raw  when pd_iso_en(1) = '0' else '0';
    a0_1                    <= a0_1_raw        when pd_iso_en(1) = '0' else (others => '0');

    arb_req(2)              <= tile2_req_raw   when pd_iso_en(2) = '0' else '0';
    arb_we(11 downto 8)     <= tile2_we_raw    when pd_iso_en(2) = '0' else (others => '0');
    arb_addr(3*SH_AW-1 downto 2*SH_AW) <= tile2_addr_raw when pd_iso_en(2) = '0' else (others => '0');
    arb_wdata(3*32-1 downto 2*32)      <= tile2_wdata_raw when pd_iso_en(2) = '0' else (others => '0');
    arb_lrsc(5 downto 4)    <= tile2_lrsc_raw  when pd_iso_en(2) = '0' else "00";
    arb_lock(2)             <= tile2_lock_raw  when pd_iso_en(2) = '0' else '0';
    a0_2                    <= a0_2_raw        when pd_iso_en(2) = '0' else (others => '0');

    arb_req(3)              <= tile3_req_raw   when pd_iso_en(3) = '0' else '0';
    arb_we(15 downto 12)    <= tile3_we_raw    when pd_iso_en(3) = '0' else (others => '0');
    arb_addr(4*SH_AW-1 downto 3*SH_AW) <= tile3_addr_raw when pd_iso_en(3) = '0' else (others => '0');
    arb_wdata(4*32-1 downto 3*32)      <= tile3_wdata_raw when pd_iso_en(3) = '0' else (others => '0');
    arb_lrsc(7 downto 6)    <= tile3_lrsc_raw  when pd_iso_en(3) = '0' else "00";
    arb_lock(3)             <= tile3_lock_raw  when pd_iso_en(3) = '0' else '0';
    a0_3                    <= a0_3_raw        when pd_iso_en(3) = '0' else (others => '0');

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

    -- M3b: harts 1-3 as PRIVATE-MEMORY tiles (hdl/common/hart_tile.vhd). Each
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
    -- the run. M13: sleep/flash/tcm_pgen ride their entity defaults here —
    -- only hart 0 wires them. M19: the IRQ interface (msip/mtip/meip) is
    -- identical on every hart.
    hart1: entity work.hart_tile
        generic map (
            PC_RST_VAL     => x"00000000",
            SH_AW          => SH_AW,
            -- Core ISA features (config-driven, work.MemoryMap; MUST be
            -- identical on all four tiles -- one hardened netlist)
            ENABLE_MUL        => CORE_ENABLE_MUL,
            ENABLE_DIV        => CORE_ENABLE_DIV,
            ENABLE_ATOMICS    => CORE_ENABLE_ATOMICS,
            ENABLE_COMPRESSED => CORE_ENABLE_COMPRESSED,
            ENABLE_BITMANIP   => CORE_ENABLE_BITMANIP,
            ENABLE_ZICOND     => CORE_ENABLE_ZICOND,
            ENABLE_ZCB        => CORE_ENABLE_ZCB,
            ENABLE_ZIMOP      => CORE_ENABLE_ZIMOP,
            ENABLE_ZIHINT     => CORE_ENABLE_ZIHINT,
            ENABLE_ZIHPM      => CORE_ENABLE_ZIHPM,
            ENABLE_ZAWRS      => CORE_ENABLE_ZAWRS,
            ENABLE_ZABHA      => CORE_ENABLE_ZABHA,
            ENABLE_ZACAS      => CORE_ENABLE_ZACAS,
            ENABLE_ZICBOZ     => CORE_ENABLE_ZICBOZ,
            ENABLE_ZCMP       => CORE_ENABLE_ZCMP,
            ENABLE_ZCMT       => CORE_ENABLE_ZCMT,
            ENABLE_ZBKB       => CORE_ENABLE_ZBKB,
            ENABLE_ZBKC       => CORE_ENABLE_ZBKC,
            ENABLE_ZBKX       => CORE_ENABLE_ZBKX,
            ENABLE_ZKN        => CORE_ENABLE_ZKN,
            ENABLE_ZFINX      => CORE_ENABLE_ZFINX
        )
        port map (
            clk       => mclk,
            -- M17: pwr_ctrl's cold-gate reset folds in (tile_rstn = resetn
            -- and pd_rstn) — a gated/waking tile is held in reset
            resetn    => tile_rstn(1),
            sleep     => '0',
            hart_id   => x"00000001",
            msip_in   => clint_msip(1),
            mtip_in   => clint_mtip(1),
            -- M19: ONE external-IRQ wire per tile — the irq_router's
            -- registered claim/complete output (routing/masking lives in
            -- the router rows; the tile hardwires its three live slots)
            meip_in   => meip(1),
            -- M17: outbound signals land on _raw and pass the iso clamps
            sh_req    => tile1_req_raw,
            sh_we     => tile1_we_raw,
            sh_addr   => tile1_addr_raw,
            sh_wdata  => tile1_wdata_raw,
            sh_gnt    => arb_gnt(1),
            sh_done   => arb_done(1),
            sh_rdata  => arb_rdata,
            sh_lrsc   => tile1_lrsc_raw,
            sh_scfail => arb_scfail(1),
            sh_resv_valid => arb_resvvld(1),
            sh_lock   => tile1_lock_raw,
            -- M17: the tile's TCM macro is on the ALWAYS-ON rail but rides
            -- its own native PGEN power-down whenever the domain gates —
            -- tcm_pgen is a straight wire to ram0's PGEN pin (was '0')
            tcm_pgen  => pd_sleep(1),
            -- PG1 F2: retention strapped OFF from the ALWAYS-ON top (the macro
            -- RETN receiver is AO — an in-tile tie was a dying-rail driver)
            tcm_retn  => '1',
            -- M17: MTCMOS domain controls (CPF hooks; see hart_tile.vhd)
            pd_sleep  => pd_sleep(1),
            pd_iso_en => pd_iso_en(1),
            trap_flag => open,
            a0        => a0_1_raw
        );

    hart2: entity work.hart_tile
        generic map (
            PC_RST_VAL     => x"00000000",
            SH_AW          => SH_AW,
            -- Core ISA features (config-driven, work.MemoryMap; MUST be
            -- identical on all four tiles -- one hardened netlist)
            ENABLE_MUL        => CORE_ENABLE_MUL,
            ENABLE_DIV        => CORE_ENABLE_DIV,
            ENABLE_ATOMICS    => CORE_ENABLE_ATOMICS,
            ENABLE_COMPRESSED => CORE_ENABLE_COMPRESSED,
            ENABLE_BITMANIP   => CORE_ENABLE_BITMANIP,
            ENABLE_ZICOND     => CORE_ENABLE_ZICOND,
            ENABLE_ZCB        => CORE_ENABLE_ZCB,
            ENABLE_ZIMOP      => CORE_ENABLE_ZIMOP,
            ENABLE_ZIHINT     => CORE_ENABLE_ZIHINT,
            ENABLE_ZIHPM      => CORE_ENABLE_ZIHPM,
            ENABLE_ZAWRS      => CORE_ENABLE_ZAWRS,
            ENABLE_ZABHA      => CORE_ENABLE_ZABHA,
            ENABLE_ZACAS      => CORE_ENABLE_ZACAS,
            ENABLE_ZICBOZ     => CORE_ENABLE_ZICBOZ,
            ENABLE_ZCMP       => CORE_ENABLE_ZCMP,
            ENABLE_ZCMT       => CORE_ENABLE_ZCMT,
            ENABLE_ZBKB       => CORE_ENABLE_ZBKB,
            ENABLE_ZBKC       => CORE_ENABLE_ZBKC,
            ENABLE_ZBKX       => CORE_ENABLE_ZBKX,
            ENABLE_ZKN        => CORE_ENABLE_ZKN,
            ENABLE_ZFINX      => CORE_ENABLE_ZFINX
        )
        port map (
            clk       => mclk,
            -- M17: pwr_ctrl's cold-gate reset folds in (tile_rstn = resetn
            -- and pd_rstn) — a gated/waking tile is held in reset
            resetn    => tile_rstn(2),
            sleep     => '0',
            hart_id   => x"00000002",
            msip_in   => clint_msip(2),
            mtip_in   => clint_mtip(2),
            meip_in   => meip(2),
            -- M17: outbound signals land on _raw and pass the iso clamps
            sh_req    => tile2_req_raw,
            sh_we     => tile2_we_raw,
            sh_addr   => tile2_addr_raw,
            sh_wdata  => tile2_wdata_raw,
            sh_gnt    => arb_gnt(2),
            sh_done   => arb_done(2),
            sh_rdata  => arb_rdata,
            sh_lrsc   => tile2_lrsc_raw,
            sh_scfail => arb_scfail(2),
            sh_resv_valid => arb_resvvld(2),
            sh_lock   => tile2_lock_raw,
            -- M17: the tile's TCM macro is on the ALWAYS-ON rail but rides
            -- its own native PGEN power-down whenever the domain gates —
            -- tcm_pgen is a straight wire to ram0's PGEN pin (was '0')
            tcm_pgen  => pd_sleep(2),
            -- PG1 F2: retention strapped OFF from the ALWAYS-ON top (the macro
            -- RETN receiver is AO — an in-tile tie was a dying-rail driver)
            tcm_retn  => '1',
            -- M17: MTCMOS domain controls (CPF hooks; see hart_tile.vhd)
            pd_sleep  => pd_sleep(2),
            pd_iso_en => pd_iso_en(2),
            trap_flag => open,
            a0        => a0_2_raw
        );

    hart3: entity work.hart_tile
        generic map (
            PC_RST_VAL     => x"00000000",
            SH_AW          => SH_AW,
            -- Core ISA features (config-driven, work.MemoryMap; MUST be
            -- identical on all four tiles -- one hardened netlist)
            ENABLE_MUL        => CORE_ENABLE_MUL,
            ENABLE_DIV        => CORE_ENABLE_DIV,
            ENABLE_ATOMICS    => CORE_ENABLE_ATOMICS,
            ENABLE_COMPRESSED => CORE_ENABLE_COMPRESSED,
            ENABLE_BITMANIP   => CORE_ENABLE_BITMANIP,
            ENABLE_ZICOND     => CORE_ENABLE_ZICOND,
            ENABLE_ZCB        => CORE_ENABLE_ZCB,
            ENABLE_ZIMOP      => CORE_ENABLE_ZIMOP,
            ENABLE_ZIHINT     => CORE_ENABLE_ZIHINT,
            ENABLE_ZIHPM      => CORE_ENABLE_ZIHPM,
            ENABLE_ZAWRS      => CORE_ENABLE_ZAWRS,
            ENABLE_ZABHA      => CORE_ENABLE_ZABHA,
            ENABLE_ZACAS      => CORE_ENABLE_ZACAS,
            ENABLE_ZICBOZ     => CORE_ENABLE_ZICBOZ,
            ENABLE_ZCMP       => CORE_ENABLE_ZCMP,
            ENABLE_ZCMT       => CORE_ENABLE_ZCMT,
            ENABLE_ZBKB       => CORE_ENABLE_ZBKB,
            ENABLE_ZBKC       => CORE_ENABLE_ZBKC,
            ENABLE_ZBKX       => CORE_ENABLE_ZBKX,
            ENABLE_ZKN        => CORE_ENABLE_ZKN,
            ENABLE_ZFINX      => CORE_ENABLE_ZFINX
        )
        port map (
            clk       => mclk,
            -- M17: pwr_ctrl's cold-gate reset folds in (tile_rstn = resetn
            -- and pd_rstn) — a gated/waking tile is held in reset
            resetn    => tile_rstn(3),
            sleep     => '0',
            hart_id   => x"00000003",
            msip_in   => clint_msip(3),
            mtip_in   => clint_mtip(3),
            meip_in   => meip(3),
            -- M17: outbound signals land on _raw and pass the iso clamps
            sh_req    => tile3_req_raw,
            sh_we     => tile3_we_raw,
            sh_addr   => tile3_addr_raw,
            sh_wdata  => tile3_wdata_raw,
            sh_gnt    => arb_gnt(3),
            sh_done   => arb_done(3),
            sh_rdata  => arb_rdata,
            sh_lrsc   => tile3_lrsc_raw,
            sh_scfail => arb_scfail(3),
            sh_resv_valid => arb_resvvld(3),
            sh_lock   => tile3_lock_raw,
            -- M17: the tile's TCM macro is on the ALWAYS-ON rail but rides
            -- its own native PGEN power-down whenever the domain gates —
            -- tcm_pgen is a straight wire to ram0's PGEN pin (was '0')
            tcm_pgen  => pd_sleep(3),
            -- PG1 F2: retention strapped OFF from the ALWAYS-ON top (the macro
            -- RETN receiver is AO — an in-tile tie was a dying-rail driver)
            tcm_retn  => '1',
            -- M17: MTCMOS domain controls (CPF hooks; see hart_tile.vhd)
            pd_sleep  => pd_sleep(3),
            pd_iso_en => pd_iso_en(3),
            trap_flag => open,
            a0        => a0_3_raw
        );

    -- System Peripheral (M19: the vectored IRQ controller is retired — only
    -- the WDT level source + the D2 router hooks remain on the IRQ side)
    system0: SYSTEM
        port map (
            clk_lfxt_in   => lfxt_in,
            clk_hfxt_in   => hfxt_in,
            clk_dco0_in   => clk_osc_dco0,
            clk_dco1_in   => clk_osc_dco1,

            resetn_in      => resetn_in,
            resetn_por     => resetn_por,
            resetn_sys     => resetn,

            irq_sys_wdt   => irq_sys_wdt,
            wdt_irq_routed   => wdt_irq_routed,
            wdt_irq_complete => wdt_irq_complete,

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
            RstValPxREN     => RstValP1REN,
            RstValPxAFS     => RstValP1AFS
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
            PxSEL_out		=> open,
            PxAFS_out		=> open,	-- no relocated inputs source from port 1

            alt_func_out_in	=>	afunc1_all_out,
            alt_func_dir_in	=>	afunc1_all_dir,
            alt_func_ren_in	=>	afunc1_all_ren
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
            RstValPxREN     => RstValP2REN,
            RstValPxAFS     => RstValP2AFS
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
            PxSEL_out		=> open,
            PxAFS_out		=> p2_afs,

            alt_func_out_in	=>	afunc2_all_out,
            alt_func_dir_in	=>	afunc2_all_dir,
            alt_func_ren_in	=>	afunc2_all_ren
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
            RstValPxREN     => RstValP3REN,
            RstValPxAFS     => RstValP3AFS
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
            PxSEL_out		=> open,
            PxAFS_out		=> p3_afs,

            alt_func_out_in	=>	afunc3_all_out,
            alt_func_dir_in	=>	afunc3_all_dir,
            alt_func_ren_in	=>	afunc3_all_ren
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
            RstValPxREN     => RstValP4REN,
            RstValPxAFS     => RstValP4AFS
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
            PxSEL_out		=> open,
            PxAFS_out		=> p4_afs,

            alt_func_out_in	=>	afunc4_all_out,
            alt_func_dir_in	=>	afunc4_all_dir,
            alt_func_ren_in	=>	afunc4_all_ren
    );


    -- =========================================================================
    -- GPIO4 (Mission B): general-purpose I/O port 5, MUTEX-page sub-slot 3 @0x6300.
    -- Registered read; own active-low one-cycle en shim. AF0 = plain GPIO; AF1 =
    -- QSPI0/I3C0 pin functions (Hi-Z when absent). Per-pin IRQs -> vectors 98-105.
    -- =========================================================================
    gpio4_sh_en_n <= not shslv_gpio4_en;
    -- AF0 plane = plain-GPIO passthrough (AF0 == GPIO for every pin)
    afunc5_out <= p5_out;
    afunc5_dir <= p5_dir;
    afunc5_ren <= p5_ren;
    -- AF1 plane unused in this configuration (QSPI0/I3C0 absent): Hi-Z.
    afunc5_af1_out <= afunc_none;
    afunc5_af1_dir <= afunc_none;
    afunc5_af1_ren <= afunc_none;
    -- Flatten the 8 AF planes (AF7..AF2 unused = afunc_none, then AF1, AF0)
    afunc5_all_out <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc5_af1_out & afunc5_out;
    afunc5_all_dir <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc5_af1_dir & afunc5_dir;
    afunc5_all_ren <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc5_af1_ren & afunc5_ren;
    gpio4: GPIO
        generic map (
            num_pins        => 8,
            PadOUTPosLogic  => true,
            PadDIRPosLogic  => false,
            PadRENPosLogic  => false,
            RstValPxOUT     => RstValP5OUT,
            RstValPxDIR     => RstValP5DIR,
            RstValPxSEL     => RstValP5SEL,
            RstValPxREN     => RstValP5REN,
            RstValPxAFS     => RstValP5AFS
        )
        port map (
            resetn          => resetn,
            irq             => irq_gpio4,
            clk_mem         => mclk,
            en              => gpio4_sh_en_n,
            wen             => sh_wen_n,
            write_data      => sh_wdata,
            read_data       => gpio4_sh_rdata,
            addr_periph     => sh_addr(5 downto 0),
            prt_in          => prt5_in,
            prt_out_out     => prt5_out,
            prt_dir_out     => prt5_dir,
            prt_ren_out     => prt5_ren,
            PxOUT_out       => p5_out,
            PxDIR_out       => p5_dir,
            PxREN_out       => p5_ren,
            PxSEL_out       => open,
            PxAFS_out       => p5_afs,
            alt_func_out_in => afunc5_all_out,
            alt_func_dir_in => afunc5_all_dir,
            alt_func_ren_in => afunc5_all_ren
    );


    -- =========================================================================
    -- GPIO5 (Mission B): general-purpose I/O port 6, MUTEX-page sub-slot 4 @0x6400.
    -- Registered read; own active-low one-cycle en shim. AF0 = plain GPIO; AF1 =
    -- NFC0 digital-AFE pins (Hi-Z when absent). Per-pin IRQs -> vectors 106-113.
    -- =========================================================================
    gpio5_sh_en_n <= not shslv_gpio5_en;
    -- AF0 plane = plain-GPIO passthrough (AF0 == GPIO for every pin)
    afunc6_out <= p6_out;
    afunc6_dir <= p6_dir;
    afunc6_ren <= p6_ren;
    -- AF1 plane unused in this configuration (NFC0 absent): Hi-Z.
    afunc6_af1_out <= afunc_none;
    afunc6_af1_dir <= afunc_none;
    afunc6_af1_ren <= afunc_none;
    -- Flatten the 8 AF planes (AF7..AF2 unused = afunc_none, then AF1, AF0)
    afunc6_all_out <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc6_af1_out & afunc6_out;
    afunc6_all_dir <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc6_af1_dir & afunc6_dir;
    afunc6_all_ren <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc6_af1_ren & afunc6_ren;
    gpio5: GPIO
        generic map (
            num_pins        => 8,
            PadOUTPosLogic  => true,
            PadDIRPosLogic  => false,
            PadRENPosLogic  => false,
            RstValPxOUT     => RstValP6OUT,
            RstValPxDIR     => RstValP6DIR,
            RstValPxSEL     => RstValP6SEL,
            RstValPxREN     => RstValP6REN,
            RstValPxAFS     => RstValP6AFS
        )
        port map (
            resetn          => resetn,
            irq             => irq_gpio5,
            clk_mem         => mclk,
            en              => gpio5_sh_en_n,
            wen             => sh_wen_n,
            write_data      => sh_wdata,
            read_data       => gpio5_sh_rdata,
            addr_periph     => sh_addr(5 downto 0),
            prt_in          => prt6_in,
            prt_out_out     => prt6_out,
            prt_dir_out     => prt6_dir,
            prt_ren_out     => prt6_ren,
            PxOUT_out       => p6_out,
            PxDIR_out       => p6_dir,
            PxREN_out       => p6_ren,
            PxSEL_out       => open,
            PxAFS_out       => p6_afs,
            alt_func_out_in => afunc6_all_out,
            alt_func_dir_in => afunc6_all_dir,
            alt_func_ren_in => afunc6_all_ren
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

    -- AFE / SARADC removed (digital-only Castalia). Peripheral-window slots
    -- 11/12 (0x4B00/0x4C00) and IRQ vectors 55/56 are reserved gaps (read 0,
    -- tied low). Tie off the GPIO alt-function outputs the two analog blocks
    -- used to drive so those pins act as plain GPIO:
    --   GPIO2 pins 3/7 (T0/T1 CAP1 out, formerly SARADC DTP0/1)
    --   GPIO3 pins 4-7 (formerly AFE DTP0-3)
    t0_cap1_out <= '0';
    t1_cap1_out <= '0';
    dtp0_out <= '0';  dtp0_dir <= '0';  dtp0_ren <= '0';
    dtp1_out <= '0';  dtp1_dir <= '0';  dtp1_ren <= '0';
    dtp2_out <= '0';  dtp2_dir <= '0';  dtp2_ren <= '0';
    dtp3_out <= '0';  dtp3_dir <= '0';  dtp3_ren <= '0';

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
    irq_gf3 : entity work.GlitchFilter
        port map
        (
            IrqGlitchy		=> irq_comb(127 downto 96),
            IrqDeglitched	=> gf_out(127 downto 96)
	);
    irq_deglitch <= gf_out(NUM_IRQ_SRCS-1 downto 0);

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



