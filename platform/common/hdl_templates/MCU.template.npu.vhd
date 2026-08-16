-- MCU.template.npu.vhd: the NPU-conditional blocks of MCU.template.vhd.
-- Each block is spliced verbatim at its marker when peripherals.npu is true; without it the emitted MCU.vhd has no NPU, no staging RAM and no 0xC000 window.

--@NPUBLOCK:npu-component@
    -- NPUx
    component NPU is
        generic(
            -- Fixed-point M and N bit widths for inputs, weights and outputs; the Y bits also size the accumulator
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
        -- NPU register bus, window slot 10 at 0x4A00: its MMR read is combinational like I2C's, so it takes the same bridge register.
        -- NPU data lives in the shared staging RAM at 0xC000, whose SRAM-port mux is fed by the slave fabric; software must not touch 0xC000-0xFFFF while a THINK runs (poll NPUCR bit 16).
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
    -- npu0_active does not sleep any hart: the NPU's vectors live in the shared staging RAM at 0xC000, an arbiter slave with back-pressure.
    -- Software contract instead: no access to 0xC000-0xFFFF while a THINK is active, poll NPUCR bit 16.
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

            -- MUXed SRAM inputs: the staging RAM's bus side is the arbiter slave fabric (0xC000-0xFFFF page), so any hart stages vectors through the shared window.
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
            -- Think-done IRQ, irq_router source 120: registered level in NPU.vhd, W1C through NPUSR.0, enabled by NPUCR.19
            ThinkDoneIrq    => irq_npu0_td
    );
--@NPUBLOCK:npuram-instance@
    -- NPU staging RAM at 0xC000-0xFFFF, an arbiter slave; the NPU's port mux (NpuMuxSel) owns these pins, bus side through the shared-slave fabric and NPU side during a THINK.
    -- Q feeds both the slave read mux (npuram_q) and the NPU's SramQ_in; BLOCKPWR's RAM1OFF bit gates the macro through pgen_mem(2).
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
