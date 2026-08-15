-- MCU.template.npu.vhd: the NPU-conditional blocks of MCU.template.vhd.
-- A2/Argus: carved out so a config with peripherals.npu=false emits an MCU.vhd with no NPU, no staging RAM and no 0xC000 window.
-- Each block is spliced verbatim at its @GEN marker when the NPU is present.

--@NPUBLOCK:npu-component@
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
            MabMmrA			: in 	std_logic_vector(3 downto 0);	-- MCU To NPU MMR - Address
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
            NpuActive		: out	std_logic;						-- NPU Active Signal for Arbitration
            -- NPU Interrupt Signal
            ThinkDoneIrq	: out	std_logic						-- Think-Done IRQ (registered level, irq_router source 120)
        );
    end component;
--@NPUBLOCK:npu-fabric-decls@
        -- M7d mover: NPU register bus (M11: window slot 10 @0x4A00).
        -- Its MMR read is COMBINATIONAL like I2C's, so it takes the same bridge register.
        -- The NPU's DATA now lives in the shared NPU staging RAM at 0xC000 (bank above): the SRAM-port mux is fed by the slave fabric, and hart 0 no longer sleeps during THINK.
        -- The staging RAM is not hart 0's private memory any more; "don't touch 0xC000-0xFFFF during a THINK" is a software contract, poll NPUCR bit 16.
        signal shslv_npu_sel,   shslv_npu_en    : std_logic;
        signal shslv_rd_npu     : std_logic := '0';
        signal npu_sh_en_n      : std_logic;
        signal npu_sh_rdata_c   : std_logic_vector(31 downto 0); -- combinational, from the instance
        signal npu_sh_rdata     : std_logic_vector(31 downto 0) := (others => '0'); -- bridge-registered
--@NPUBLOCK:npu-mux-decls@
        -- NPU0 Signals 
        signal npu0_mux_ram_a       : std_logic_vector(11 downto 0);
        signal npu0_mux_ram_d       : std_logic_vector(31 downto 0);
        signal npu0_mux_ram_cen     : std_logic;
        signal npu0_mux_ram_gwen    : std_logic;
        signal npu0_mux_wen         : std_logic_vector(3 downto 0);
        signal npu0_mux_ram_q       : std_logic_vector(31 downto 0);
        signal npu0_mux_ram_clk     : std_logic;
        signal npu0_active          : std_logic;
--@NPUBLOCK:npu-sleep-comment@
    -- M11: npu0_active no longer sleeps hart 0, because the NPU's vectors live in the SHARED staging RAM at 0xC000 (an arbiter slave), not in hart 0's retired private RAM1.
    -- The sleep existed to keep hart 0's un-stallable private RAM1 accesses from colliding with the NPU's port mux.
    -- Shared accesses have arbiter back-pressure, and "no 0xC000-0xFFFF access during a THINK" is the software contract (poll NPUCR bit 16, shnpu.S).
--@NPUBLOCK:npu-instance@
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

            -- MUXed SRAM inputs (M11): the staging RAM's bus side is the ARBITER SLAVE fabric (0xC000-0xFFFF page), not hart 0's adddec, so any hart stages vectors through the shared window.
            -- Active-low strobes shimmed exactly like the bulk RAM banks.
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

            NpuActive       => npu0_active,
            --@GEN:evfab-taps:npu0@
            -- DP-SG (2026-07-22): think-done IRQ, irq_router source 120 (registered level in NPU.vhd; W1C via NPUSR.0, IE = NPUCR.19)
            ThinkDoneIrq    => irq_npu0_td
    );
--@NPUBLOCK:npuram-instance@
    -- M11: NPU staging RAM @0xC000-0xFFFF (hart 0's retired private RAM1 macro, promoted to an ARBITER SLAVE).
    -- The NPU's internal port mux (NpuMuxSel) still owns these pins: bus side = the shared-slave fabric (see the NPU instance's Sram*_in), NPU side during a THINK.
    -- Q feeds both the slave read mux (npuram_q) and the NPU's SramQ_in.
    -- BLOCKPWR's RAM1OFF bit keeps gating this macro (pgen_mem(2)).
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
