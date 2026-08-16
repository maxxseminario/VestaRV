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
        resetn_in	: in	std_logic;	-- '0' = reset asserted, '1' = system running
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

        --GPIO4 Connections (QSPI0 / I3C0 pin functions on AF1)
        prt5_in		    : in	std_logic_vector(7 downto 0);
		prt5_out		: out	std_logic_vector(7 downto 0);
		prt5_dir		: out	std_logic_vector(7 downto 0);
		prt5_ren		: out	std_logic_vector(7 downto 0);

        --GPIO5 Connections (NFC0 digital-AFE pin functions on AF1)
        prt6_in		    : in	std_logic_vector(7 downto 0);
		prt6_out		: out	std_logic_vector(7 downto 0);
		prt6_dir		: out	std_logic_vector(7 downto 0);
		prt6_ren		: out	std_logic_vector(7 downto 0);


        -- Testing Purposes Only
        a0  : out std_logic_vector(31 downto 0);

        --@GEN:a0-ports@
        --@GEN:dmi-ports@
        --@GEN:jtag-ports@

    );
end entity;

architecture behav of MCU is

    -- Every hart is the same hart_tile entity (hart_tile.vhd), structurally identical so one netlist hardens them all; per-instance differences are wiring only (hart_id, hart 0's flash/XIP and sleep hookup to SPI0, the TCM PGEN).
    -- The IRQ interface is identical on every hart: msip/mtip from the CLINT plus one meip wire from the irq_router's claim/complete stage.

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

            -- Interrupt Signals: the WDT level source only, since routing and delivery live in the irq_router
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
            PGEN_mem        : out std_logic_vector(6 downto 0) -- '0' mem on, '1' mem off; bits 6:3 are shbank0-3
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
            --@GEN:evfab-comp:gpio@

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

            -- GPIO_NUM_AFS flattened alternate-function planes: plane k, pin i at bit (k * num_pins + i).
            -- Plane 0 = the legacy AF0 functions.
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
            --@GEN:evfab-comp:uart@

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
            --@GEN:evfab-comp:timer@

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

    --@GEN:npu-component@




    -- MCU Block Level Signal Declarations --------------------------------------

        -- System Signals 
        signal resetn           : std_logic;
        signal resetn_por       : std_logic;
        signal resetn_sys       : std_logic;
        -- IRQ delivery is the irq_router's per-hart meip wires (claim/complete), declared further down.
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
        -- clk_cpu, boot_fetched and resetn_core are tile-internal signals and do not appear at this level.

        -- IRQ Signal Declarations
        --@GEN:irq-signal-decls@

        --@GEN:irq-gf-decls@


        -- The core interface and the master-side shared handshake state live inside hart_tile, one identical copy per master.

        --@GEN:sh-window-const@
        -- Global LR/SC reservation unit
        --@GEN:arb-fabric-decls@
        -- Arbiter to shared-slave side (RAM and CLINT sub-decoded below)
        signal sh_en            : std_logic;
        signal sh_we            : std_logic_vector(3 downto 0);
        signal sh_addr          : std_logic_vector(SH_AW-1 downto 0);
        signal sh_wdata         : std_logic_vector(31 downto 0);
        --@GEN:memslv-decls@
        -- CLINT: peripheral-window page 1 at 0x5000
        signal shslv_clint_sel  : std_logic;
        signal shslv_clint_en   : std_logic;
        signal shslv_rd_clint   : std_logic := '0'; -- registered: last access was CLINT
        signal sh_rdata_mux     : std_logic_vector(31 downto 0); -- into arbiter s_rdata
        signal clint_rdata      : std_logic_vector(31 downto 0);
        --@GEN:clint-irq-decls@
        -- Shared console UART0: window slot 4 at 0x4400, live for every hart
        signal shslv_uart0_sel  : std_logic;
        signal shslv_uart0_en   : std_logic;
        signal shslv_rd_uart0   : std_logic := '0'; -- registered: last access was UART0
        signal uart0_sh_en_n    : std_logic;   -- UART bus is active-LOW en/wen
        signal shslv_uart0_en_q : std_logic;   -- falling-mclk registered strobe, the snapshot capture clock
        signal sh_wen_n   : std_logic_vector(3 downto 0);
        signal uart0_sh_rdata   : std_logic_vector(31 downto 0);
        -- irq_router, the per-hart IRQ delivery stage: window page 3 at 0x7000
        signal shslv_irtr_sel   : std_logic;
        signal shslv_irtr_en    : std_logic;
        signal shslv_rd_irtr    : std_logic := '0'; -- registered: last access was irq_router
        signal irtr_rdata       : std_logic_vector(31 downto 0);
        --@GEN:meip-decl@
        -- pwr_ctrl, the MTCMOS power controller, is a native slave in window slot 11 at 0x4B00; hart 0 has no row and is always on by construction.
        -- Its pd_* rows drive the tile power domains: pd_rstn folds into each tile's resetn (cold gate), pd_sleep and pd_iso_en drive the tiles' CPF hook ports (HEAD switch SLEEP chain, A2ISO clamp enable).
        signal shslv_pwr_sel    : std_logic;
        signal shslv_pwr_en     : std_logic;
        signal shslv_rd_pwr     : std_logic := '0'; -- registered: last access was pwr_ctrl
        signal pwr_rdata        : std_logic_vector(31 downto 0);
        --@GEN:pd-decls@
        -- Tile outputs land on these _raw nets and are AND-clamped low onto the arbiter and observation buses by pd_iso_en; those AND gates are the always-on-side isolation cells.
        -- Clamping low matches the boundary registers' reset values, so a clamped master looks exactly like a reset one to the arbiter.
        --@GEN:tile-raw-decls@
        --@GEN:mover-fabric-decls@
        --@GEN:i2c-fabric-decls@
        --@GEN:npu-fabric-decls@
        -- SYSTEM0 (slot 9 at 0x4900), GPIO0 (slot 0 at 0x4000) and SPI0 (slot 2 at 0x4200) are window slaves like everything else; there is no private peripheral page, and all three register their reads on clk_mem, so they take plain polarity shims, no bridge.
        -- SYSTEM0 clock-reconfig contract: SYS_CLK_CR/SYS_CLK_DIV_CR reconfigure MCLK itself, so the management hart must quiesce the other masters first; the glitch-free muxes protect the clock domain, but an smclk-domain peripheral mid-frame is not protected.
        signal shslv_sys_sel,   shslv_sys_en    : std_logic;
        signal shslv_gpio0_sel, shslv_gpio0_en  : std_logic;
        signal shslv_spi0_sel,  shslv_spi0_en   : std_logic;
        signal shslv_rd_sys     : std_logic := '0';
        signal shslv_rd_gpio0   : std_logic := '0';
        signal shslv_rd_spi0    : std_logic := '0';
        signal sys_sh_en_n      : std_logic;
        signal gpio0_sh_en_n    : std_logic;
        signal spi0_sh_en_n     : std_logic;
        signal shslv_spi0_en_q  : std_logic;   -- falling-mclk registered strobe, the snapshot capture clock
        signal sys_sh_rdata     : std_logic_vector(31 downto 0);
        signal gpio0_sh_rdata   : std_logic_vector(31 downto 0);
        signal spi0_sh_rdata    : std_logic_vector(31 downto 0);
        -- Hardware mutex bank, window page 2 at 0x6000: a read atomically returns the old owner and claims, a write of 0 releases, and the arbiter's whole-transaction serialization is what makes it atomic.
        -- sh_master, the arbiter's granted-master index, attributes the claim-read to a hart; the read is registered and the write enable is resv-gated.
        signal shslv_mtx_sel,   shslv_mtx_en    : std_logic;
        signal shslv_rd_mtx     : std_logic := '0';
        signal mtx_rdata        : std_logic_vector(31 downto 0);

        --@GEN:i3c-decls@
        --@GEN:nfc-decls@
        --@GEN:rtc-decls@
        --@GEN:pwm-decls@
        --@GEN:ow-decls@
        --@GEN:dma-decls@
        --@GEN:trng-decls@
        --@GEN:i2ct-decls@
        --@GEN:evfab-decls@
        --@GEN:debug-decls@
        --@GEN:slot12-decls@
        --@GEN:sh-master-decl@
        -- signal inst_retired     : std_logic; -- Instruction Retired Signal from Core
        -- signal mem_access       : std_logic; -- High when memory access is occurring

        -- Memory and RAM Control Signals
        --@GEN:pgen-decls@

        -- Flash Extended Memory Signals
        signal mem_en_flash    : std_logic;
        signal clk_mem_flash   : std_logic;
        signal mab_flash       : std_logic_vector(31 downto 0); 
        signal flash_dout      : std_logic_vector(31 downto 0);
        signal flash_ext_meming: std_logic;
        signal mab_out         : std_logic_vector(31 downto 0); 

        --@GEN:npu-mux-decls@

        -- DCO Signals 
        signal en_dco0          : std_logic;
        signal en_dco1          : std_logic;
        signal DCO0_BIAS        : std_logic_vector(11 downto 0);
        signal DCO1_BIAS        : std_logic_vector(11 downto 0);
        signal reset_dco       : std_logic; --special reset for DCO to ensure proper startup

    -- Multi-AF plumbing (shared by all four ports) ---------------------------------------
        -- Each GPIO port takes GPIO_NUM_AFS flattened alternate-function planes (plane k, pin i at bit k*8+i); the per-plane afuncN_* vectors below are concatenated into afuncN_all_*.
        -- An unassigned plane slice behaves as a high-impedance input: out '0', dir '0' (input), ren '0' (pull disabled), all pre-polarity.
        constant afunc_none				: std_logic_vector(7 downto 0) := (others => '0');

    -- Multi-AF output-function spread planes: shared timer/UART/SPI outputs fanned across all four ports, dormant at reset (PxAFS=0).
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

        -- P1.0: cs_flash (output only)
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

        --@GEN:spi1-pad-decls@

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

        --@GEN:uart1-pad-decls@
    
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


        --@GEN:timer1-pad-decls@


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

        --@GEN:i2c1-pad-decls@

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

    -- GPIO4 / GPIO5 declarative regions -------------------------------------
        --@GEN:gpio4-decls@

        --@GEN:gpio5-decls@

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

        --@GEN:gpio0-af-spread@

    -- GPIO1 Connections (SPI1, UART0, UART1) ---------------------------------------
        --@GEN:spi1-input-taps@

        -- GPIO1 Connections (UART0)
        -- Multi-AF input routing: a relocated function reads its alternate pad when that pin's PxAFS field selects the function's plane, otherwise its home pad; the selection is keyed on PxAFS alone, so peripheral inputs stay always-visible, and ren_in (the user pull preference) follows the same selection.
        -- RX0's second alternate pad is P4.5 at AF2, a spread io slot addressed by literal index and paired with TX0 on P4.4 AF2; fixed priority is that pad, then the AF1 pad, then home.
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

        --@GEN:uart1-input-muxes@


        --@GEN:gpio1-primary-planes@

        --@GEN:gpio1-af1-planes@

        --@GEN:gpio1-af-spread@

    -- GPIO2 Connections (TIMER0, TIMER1) -------------------------------------------------
        --@GEN:gpio2-timer-muxes@


        --@GEN:gpio2-primary-planes@

        --@GEN:gpio2-af1-planes@

        --@GEN:gpio2-af-spread@



    -- GPIO3 Connections (I2C0, I2C1, DTP) ------------------------------------------------------------

        --@GEN:i2c-input-muxes@

        --@GEN:gpio3-primary-planes@

        --@GEN:gpio3-af1-planes@

        --@GEN:gpio3-af-spread@


    -- =============================================================================
    -- IRQ Signal Assignments
    -- =============================================================================
        --@GEN:irq-comb@



    -- =============================================================================
    -- Component Instantiations
    -- =============================================================================
    --@GEN:npu-sleep-comment@
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
            lock   => arb_lock,   -- grant-locking, holds the grant across an AMO's read-modify-write pair
            gnt    => arb_gnt,
            done   => arb_done,
            rdata  => arb_rdata,
            s_en    => sh_en,
            s_master => sh_master,
            s_we    => sh_we_raw,
            s_addr  => sh_addr,
            s_wdata => sh_wdata,
            --@GEN:arb-stall@
            s_rdata => sh_rdata_mux
        );

    -- Global LR/SC reservation unit: it snoops every granted shared transaction, places reservations on LR reads, kills them on writes, and adjudicates SC writes in the arbiter's serialization order (a dead SC's write is suppressed through sh_we and its fail verdict returns with done).
    -- Cross-hart LR/SC depends on it: two harts SC-ing the same word both pass their core-local checks, and only this unit can order them.
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
            sc_fail    => arb_scfail,
            resv_valid_o => arb_resvvld   -- Zawrs: per-master reservation-valid level to the tiles
        );

    -- =========================================================================
    --@GEN:shslv-banner@
    -- =========================================================================
    --@GEN:shslv-subdecode@

    --@GEN:shslv-rd-sel@

    --@GEN:rdata-bridge@

    --@GEN:sh-rdata-mux@

    --@GEN:polarity-shims@

    --@GEN:clint-instance@

    --@GEN:irq-router-instance@

    -- Hardware mutex bank: a read atomically returns the old owner and claims (one-instruction acquire, the arbiter's whole-transaction serialization is the atomicity), a write of 0 releases, and sh_master says whose claim-read it is.
    -- The bank resets all-free, and locking is advisory: there is no bus-enforced hold, because the core has no bus-error path and stalling until release would generate deadlocks.
    --@GEN:mutex-instance@
    --@GEN:i3c-instance@
    --@GEN:nfc-instance@
    --@GEN:rtc-instance@
    --@GEN:pwm-instance@
    --@GEN:ow-instance@
    --@GEN:dma-instance@
    --@GEN:trng-instance@
    --@GEN:i2ct-instance@
    --@GEN:evfab-instance@

    -- MTCMOS power controller, window slot 11 at 0x4B00: one gate bit per tile hart, and a per-tile FSM sequences the domain controls in the only legal order, iso then rst then rail off to gate, rail on then settle then un-iso then un-rst to wake.
    -- pd_rstn folds into the tile's resetn below, so a wake is a cold boot (shared-ROM fetch, WFI park, loader relaunch); the controller resets all-on, and software must gate only parked or quiesced tiles.
    --@GEN:pwr-instance@
    --@GEN:debug-instance@

    --@GEN:slot12-instances@

    -- Cold-gate reset: a gated or waking tile is held in reset, which is also what keeps it bus-silent at the arbiter, since sh_req is qualified by the tile's resetn.
    --@GEN:tile-rstn@

    -- Isolation clamps: every outbound tile signal is forced to its reset value while pd_iso_en(h) is high, so nothing ever samples a floating pin of a dark domain.
    -- These gates synthesize into the always-on control plane.
    --@GEN:iso-clamps@

    --@GEN:shared-ram-banks@

    -- The tile harts: each is a full core plus its own adddec and private TCM (RAM0 at 0x8000), reset to PC 0x0 to fetch the shared boot ROM through the arbiter, where the bootrom's mhartid dispatch parks them in WFI until hart 0 loads and ignites them over CLINT msip and the boot mailboxes.
    -- Each tile is also an arbiter master, its sh_* ports mapping onto that master's slice of the flattened arb_* buses; hart_id is a port, each hart's a0 is brought out for the testbench, and sleep/flash/tcm_pgen ride their entity defaults because only hart 0 wires them.
    --@GEN:tile-instances@
    --@GEN:tcm-apertures@

    -- System Peripheral: on the IRQ side it carries only the WDT level source and its router hooks
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

    -- Hart 0's adddec lives inside its tile: the extended-flash decode above the shared window drives the tile's flash ports, wired to SPI0 above.

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
            --@GEN:evfab-taps:gpio0@

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

    --@GEN:gpio4-instance@

    --@GEN:gpio5-instance@

    -- SPI0 (window slot 2 @0x4200): the boot/XIP flash master, so it is the one SPI built with ENABLE_EXTENDED_MEM
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

    --@GEN:spi1-instance@

    -- UART0 (window slot 4 at 0x4400): the shared console UART, reachable by every hart through the arbiter and clocked from smclk.
    uart0: UART
        port map (
            -- System Signals
            clk         => smclk,
            resetn       => resetn,

            -- Interrupt Signals
            irq_rc       => irq_uart0_rc,
            irq_te       => irq_uart0_te,
            irq_tc       => irq_uart0_tc,
            --@GEN:evfab-taps:uart0@

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

    --@GEN:uart1-instance@

    -- I2C0 (window slot 14 @0x4E00): home pads P4.0/P4.1, combinational read bridged on the slave side
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

    --@GEN:i2c1-instance@

    -- TIMER0 (window slot 6 @0x4600): home compare/capture pads on P3.0-3, clocked from the glitch-free source mux
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
            --@GEN:evfab-taps:timer0@

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

    --@GEN:timer1-instance@

    --@GEN:npu-instance@

    --@GEN:analog-tie-offs@

    -- =============================================================================
    -- Memory Blocks
    -- =============================================================================
    -- The shared boot ROM at 0x0-0x3FFF is an arbiter slave like the bulk banks: every hart resets to PC 0x0 and fetches its first instruction from here, and BLOCKPWR's ROMOFF bit gates the macro through pgen_mem(0).
    -- CEN is sampled with the address at the s_en cycle's ending edge on the free-running mclk and Q is valid the next cycle, so the macro is the one-cycle registered read; with no WEN pin the page is read-only and a write completes at the arbiter and is discarded.
    rom0: entity work.rom_hvt_pg
        port map (
            Q    => rom_q,
            CLK  => mclk,
            CEN  => rom_cen_n,
            A    => sh_addr(11 downto 0),
            EMA  => "000",
            PGEN => pgen_mem(0)
    );

    -- Hart 0's TCM macro lives inside its tile; BLOCKPWR's RAMOFF gating reaches it through the tile's tcm_pgen port, wired to pgen_mem(1) at the hart0 instance.

    --@GEN:npuram-instance@


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

    --@GEN:irq-gf-instances@

    -- Genus will not route tie cells into the analog blocks and connects their pins straight to VSS or VDD, so burying a constant 0 one level down forces a real tie-low cell onto every constant '0' glitch-filter input.
	-- WARNING: check the fan-out of this tie cell.
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



