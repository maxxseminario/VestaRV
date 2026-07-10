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


        -- Testing Purposes Only
        a0  : out std_logic_vector(31 downto 0);

        --@GEN:a0-ports@

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
        --@GEN:irq-signal-decls@

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
        --@GEN:arb-fabric-decls@
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
        --@GEN:clint-irq-decls@
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
        --@GEN:tile-irq-en-flat-decl@
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
        --@GEN:pd-decls@
        -- M17 isolation: the tile outputs land on these _raw nets and are
        -- AND-clamped LOW onto the arbiter/observation buses by pd_iso_en —
        -- the EXPLICIT always-on-side isolation cells (electrically the
        -- same structure as the pmk A2ISO: an AND on AO power with the
        -- possibly-floating tile pin on one input). Clamp-low == the
        -- boundary registers' reset values, so a clamped master looks
        -- exactly like a reset one to the arbiter (no M5a-class hazard).
        --@GEN:tile-raw-decls@
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
        --@GEN:sh-master-decl@
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
        afunc1_all_out <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc1_out;
        afunc1_all_dir <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc1_dir;
        afunc1_all_ren <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc1_ren;

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
        -- Multi-AF input routing: a relocated function reads its alternate pad
        -- when that pin's PxAFS field selects the function's plane (keyed on
        -- PxAFS only — peripheral inputs stay always-visible, like the direct
        -- taps they replace); otherwise it reads its home pad. The peripheral
        -- ren_in (user pull preference) follows the same selection.
        tx0_ren_in <= p3_ren(pnum_gpio2_af1_tx0)
                      when p3_afs((3 * pnum_gpio2_af1_tx0) + 2 downto 3 * pnum_gpio2_af1_tx0) = "001"
                      else p2_ren(pnum_gpio1_tx0);
        rx0_ren_in <= p3_ren(pnum_gpio2_af1_rx0)
                      when p3_afs((3 * pnum_gpio2_af1_rx0) + 2 downto 3 * pnum_gpio2_af1_rx0) = "001"
                      else p2_ren(pnum_gpio1_rx0);
        rx0_in <= prt3_in(pnum_gpio2_af1_rx0)
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
        -- I2C0 relocation on P2.6/7 (the UART1 pins). P2.4/5 have no AF1.
        afunc2_af1_out <= (
            pnum_gpio1_af1_scl0 => scl0_out,        -- GPIO1 pin 7
            pnum_gpio1_af1_sda0 => sda0_out,        -- GPIO1 pin 6
            5 => '0',                               -- GPIO1 pin 5: unassigned (hi-Z input)
            4 => '0',                               -- GPIO1 pin 4: unassigned (hi-Z input)
            pnum_gpio1_af1_t1_cmp1 => t1_cmp1_out,  -- GPIO1 pin 3
            pnum_gpio1_af1_t1_cmp0 => t1_cmp0_out,  -- GPIO1 pin 2
            pnum_gpio1_af1_t0_cmp1 => t0_cmp1_out,  -- GPIO1 pin 1
            pnum_gpio1_af1_t0_cmp0 => t0_cmp0_out   -- GPIO1 pin 0
        );
        afunc2_af1_dir <= (
            pnum_gpio1_af1_scl0 => scl0_dir,        -- GPIO1 pin 7
            pnum_gpio1_af1_sda0 => sda0_dir,        -- GPIO1 pin 6
            5 => '0',                               -- GPIO1 pin 5: unassigned (input)
            4 => '0',                               -- GPIO1 pin 4: unassigned (input)
            pnum_gpio1_af1_t1_cmp1 => t1_cmp1_dir,  -- GPIO1 pin 3
            pnum_gpio1_af1_t1_cmp0 => t1_cmp0_dir,  -- GPIO1 pin 2
            pnum_gpio1_af1_t0_cmp1 => t0_cmp1_dir,  -- GPIO1 pin 1
            pnum_gpio1_af1_t0_cmp0 => t0_cmp0_dir   -- GPIO1 pin 0
        );
        afunc2_af1_ren <= (
            pnum_gpio1_af1_scl0 => scl0_ren,        -- GPIO1 pin 7
            pnum_gpio1_af1_sda0 => sda0_ren,        -- GPIO1 pin 6
            5 => '0',                               -- GPIO1 pin 5: unassigned (pull disabled)
            4 => '0',                               -- GPIO1 pin 4: unassigned (pull disabled)
            pnum_gpio1_af1_t1_cmp1 => t1_cmp1_ren,  -- GPIO1 pin 3
            pnum_gpio1_af1_t1_cmp0 => t1_cmp0_ren,  -- GPIO1 pin 2
            pnum_gpio1_af1_t0_cmp1 => t0_cmp1_ren,  -- GPIO1 pin 1
            pnum_gpio1_af1_t0_cmp0 => t0_cmp0_ren   -- GPIO1 pin 0
        );

        -- Flattened AF planes (7 downto 2 unassigned)
        afunc2_all_out <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc2_af1_out & afunc2_out;
        afunc2_all_dir <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc2_af1_dir & afunc2_dir;
        afunc2_all_ren <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc2_af1_ren & afunc2_ren;

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
        -- UART0 relocation on P3.4/5. P3.6/7 have no AF1.
        afunc3_af1_out <= (
            7 => '0',                           -- GPIO2 pin 7: unassigned (hi-Z input)
            6 => '0',                           -- GPIO2 pin 6: unassigned (hi-Z input)
            pnum_gpio2_af1_rx0  => rx0_out,     -- GPIO2 pin 5
            pnum_gpio2_af1_tx0  => tx0_out,     -- GPIO2 pin 4
            pnum_gpio2_af1_scl1 => scl1_out,    -- GPIO2 pin 3
            pnum_gpio2_af1_sda1 => sda1_out,    -- GPIO2 pin 2
            pnum_gpio2_af1_rx1  => rx1_out,     -- GPIO2 pin 1
            pnum_gpio2_af1_tx1  => tx1_out      -- GPIO2 pin 0
        );
        afunc3_af1_dir <= (
            7 => '0',                           -- GPIO2 pin 7: unassigned (input)
            6 => '0',                           -- GPIO2 pin 6: unassigned (input)
            pnum_gpio2_af1_rx0  => rx0_dir,     -- GPIO2 pin 5
            pnum_gpio2_af1_tx0  => tx0_dir,     -- GPIO2 pin 4
            pnum_gpio2_af1_scl1 => scl1_dir,    -- GPIO2 pin 3
            pnum_gpio2_af1_sda1 => sda1_dir,    -- GPIO2 pin 2
            pnum_gpio2_af1_rx1  => rx1_dir,     -- GPIO2 pin 1
            pnum_gpio2_af1_tx1  => tx1_dir      -- GPIO2 pin 0
        );
        afunc3_af1_ren <= (
            7 => '0',                           -- GPIO2 pin 7: unassigned (pull disabled)
            6 => '0',                           -- GPIO2 pin 6: unassigned (pull disabled)
            pnum_gpio2_af1_rx0  => rx0_ren,     -- GPIO2 pin 5
            pnum_gpio2_af1_tx0  => tx0_ren,     -- GPIO2 pin 4
            pnum_gpio2_af1_scl1 => scl1_ren,    -- GPIO2 pin 3
            pnum_gpio2_af1_sda1 => sda1_ren,    -- GPIO2 pin 2
            pnum_gpio2_af1_rx1  => rx1_ren,     -- GPIO2 pin 1
            pnum_gpio2_af1_tx1  => tx1_ren      -- GPIO2 pin 0
        );

        -- Flattened AF planes (7 downto 2 unassigned)
        afunc3_all_out <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc3_af1_out & afunc3_out;
        afunc3_all_dir <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc3_af1_dir & afunc3_dir;
        afunc3_all_ren <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc3_af1_ren & afunc3_ren;



    -- GPIO3 Connections (I2C0, I2C1, DTP) ------------------------------------------------------------

        -- Resistor Enables (I2C0 relocates to P2.6/7, I2C1 to P3.2/3 — the
        -- peripheral ren_in follows the same AF selection as the inputs below)
        sda0_ren_in <= p2_ren(pnum_gpio1_af1_sda0)
                       when p2_afs((3 * pnum_gpio1_af1_sda0) + 2 downto 3 * pnum_gpio1_af1_sda0) = "001"
                       else p4_ren(pnum_gpio3_sda0);
        scl0_ren_in <= p2_ren(pnum_gpio1_af1_scl0)
                       when p2_afs((3 * pnum_gpio1_af1_scl0) + 2 downto 3 * pnum_gpio1_af1_scl0) = "001"
                       else p4_ren(pnum_gpio3_scl0);
        sda1_ren_in <= p3_ren(pnum_gpio2_af1_sda1)
                       when p3_afs((3 * pnum_gpio2_af1_sda1) + 2 downto 3 * pnum_gpio2_af1_sda1) = "001"
                       else p4_ren(pnum_gpio3_sda1);
        scl1_ren_in <= p3_ren(pnum_gpio2_af1_scl1)
                       when p3_afs((3 * pnum_gpio2_af1_scl1) + 2 downto 3 * pnum_gpio2_af1_scl1) = "001"
                       else p4_ren(pnum_gpio3_scl1);

        -- Inputs (relocated pad wins, home pad is the default)
        sda0_in <= prt2_in(pnum_gpio1_af1_sda0)
                   when p2_afs((3 * pnum_gpio1_af1_sda0) + 2 downto 3 * pnum_gpio1_af1_sda0) = "001"
                   else prt4_in(pnum_gpio3_sda0);
        scl0_in <= prt2_in(pnum_gpio1_af1_scl0)
                   when p2_afs((3 * pnum_gpio1_af1_scl0) + 2 downto 3 * pnum_gpio1_af1_scl0) = "001"
                   else prt4_in(pnum_gpio3_scl0);
        sda1_in <= prt3_in(pnum_gpio2_af1_sda1)
                   when p3_afs((3 * pnum_gpio2_af1_sda1) + 2 downto 3 * pnum_gpio2_af1_sda1) = "001"
                   else prt4_in(pnum_gpio3_sda1);
        scl1_in <= prt3_in(pnum_gpio2_af1_scl1)
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
        afunc4_all_out <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc4_af1_out & afunc4_out;
        afunc4_all_dir <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc4_af1_dir & afunc4_dir;
        afunc4_all_ren <= afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc_none & afunc4_af1_ren & afunc4_ren;


    -- =============================================================================
    -- IRQ Signal Assignments
    -- =============================================================================
        --@GEN:irq-comb@



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

    --@GEN:hart0-instance@

    mp_arb0: entity work.mp_arbiter
        --@GEN:arb-generic@
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
        --@GEN:resv-generic@
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
    --@GEN:shslv-subdecode@

    --@GEN:shslv-rd-sel@

    --@GEN:rdata-bridge@

    --@GEN:sh-rdata-mux@

    --@GEN:polarity-shims@

    --@GEN:clint-instance@

    --@GEN:irq-router-instance@

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

    -- M17: the cold-gate reset — a gated (or waking) tile is held in reset,
    -- which is also what keeps it bus-silent at the arbiter (sh_req is
    -- qualified by the tile's resetn since M12).
    --@GEN:tile-rstn@

    -- M17 isolation clamps (see the _raw signal comment): every outbound
    -- tile signal is forced to its reset value while pd_iso_en(h) is high,
    -- so the arbiter and the tb never sample a floating pin of a dark
    -- domain. These gates synthesize into the ALWAYS-ON control plane.
    --@GEN:iso-clamps@

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
    --@GEN:tile-instances@

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

            --@GEN:bus:system0@

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

            --@GEN:bus:gpio0@

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

            --@GEN:bus:gpio1@

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

            --@GEN:bus:gpio2@

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

            --@GEN:bus:gpio3@

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

            --@GEN:bus:spi0@

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

            --@GEN:bus:spi1@

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

            --@GEN:bus:uart0@

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

            --@GEN:bus:uart1@

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
            
            --@GEN:bus:i2c0@
            
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
            
            --@GEN:bus:i2c1@

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

            --@GEN:bus:timer0@

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

            --@GEN:bus:timer1@

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

            --@GEN:bus:npu0@

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



