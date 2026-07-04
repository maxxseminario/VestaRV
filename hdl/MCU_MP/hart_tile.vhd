-- =============================================================================
-- hart_tile.vhd  (M3b)
-- =============================================================================
-- One self-contained hart with PRIVATE memory: a vesta core + its own address
-- decoder + private ROM + private RAM0 (0x8000) + private RAM1 (0xC000).
--
-- This is the "private per-hart memory" building block for the 4-hart MCU_MP.
-- Each tile replicates the *unchanged* single-core core<->adddec<->ROM/RAM path,
-- so there is NO cross-hart grant-switching hazard on the fetch/load pipeline
-- (see ~/vesta_docs/multicore_plan.md, "GRANT-SWITCHING HAZARD").
--
-- For M3b, harts 1-3 boot directly from preloaded RAM (PC_RST_VAL = 0x8200,
-- RAM0/RAM1 preloaded via INIT_FILE) with NO SPI/flash boot, and they do NOT
-- touch peripherals -- so the decoder's peripheral- and flash-facing buses are
-- tied off internally here.
--
-- M3c.4: the tile is a REAL master of the MCU-level shared-RAM window
-- (0x10000-0x13FFF, region 4, behind mp_arbiter on the free-running mclk).
-- This replicates hart 0's proven M3c wiring (see MCU.vhd + the M3c.3
-- post-mortem in ~/vesta_docs/multicore_plan.md):
--   * sh_sel   = EXACT 18-bit decode of 0x10000-0x13FFF (complement of the
--                >=0x14000 extended-flash decode; a bits-16:14-only decode
--                aliases higher addresses back into the window - bug 2).
--   * sh_acked = one-shot handshake flop on MCLK (the stall source must run
--                free; a hart gated off can't clock its own release).
--   * sh_dphase= sh_sel registered on the tile's own gated clk_cpu - BY
--                DESIGN: vesta's unified bus uses read_data as the INSTRUCTION
--                during decode, and data_addr/sh_sel derive combinationally
--                from it, so a raw-sh_sel read-data mux is a zero-delay
--                oscillation (bug 4). The registered select is '1' exactly
--                during the MEMORY_WAIT data phase. Shared window is DATA-only.
--   * mem_ready = (not sh_sel) or sh_acked - freezes the core (clk_cpu gate)
--                for the whole arbiter transaction, inside the EXECUTE cycle.
-- M4a: sh_we carries the 4 byte-lane strobes (active-high), so sub-word
-- shared stores (sb/sh) work — write_word is lane-positioned by the core.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;
use work.constants.all;      -- word, word_array
use work.MemoryMap.all;      -- NUM_IRQS

entity hart_tile is
    generic (
        HARTID         : natural := 1;
        PC_RST_VAL     : std_logic_vector(31 downto 0) := x"00008200";
        RAM0_INIT_FILE : string := "";   -- 0x8000-0xBFFF preload image (first 4096 words of build .rcf)
        RAM1_INIT_FILE : string := "";   -- 0xC000-0xFFFF preload image (next 4096 words)
        SH_AW          : natural := 12   -- shared-window word-address width (must match mp_arbiter)
    );
    port (
        clk       : in  std_logic;   -- free-running mclk
        resetn    : in  std_logic;
        sleep     : in  std_logic;

        -- M5b: per-hart CLINT level interrupts (mclk domain -- same domain as
        -- this vesta's free-running clk, and its irq_handler clocks on clk, so
        -- msip/mtip can wake a hart whose gated clk_cpu is OFF in SLEEPING).
        -- Tiles have no SYSTEM peripheral to program irq_en, so exactly these
        -- two irq_vector slots (IRQB_CLINT_MSIP / IRQB_CLINT_MTIP) are
        -- hardwired ENABLED below; every other IRQ stays masked.
        msip_in   : in  std_logic := '0';
        mtip_in   : in  std_logic := '0';

        -- M7a: shared-peripheral IRQ fan-out. irq_ext carries the SAME
        -- deglitched peripheral IRQ levels hart 0's SYSTEM sees (mclk-domain
        -- fan-out of irq_deglitch in MCU.vhd); its CLINT slots 83/84 are
        -- IGNORED here — this hart's own msip_in/mtip_in override them.
        -- irq_en_ext is this hart's row of the shared-window irq_router
        -- (0x13900): software routes a peripheral IRQ to this hart by setting
        -- its slot bit. Both default to all-zeros = pre-M7a behavior.
        irq_ext    : in std_logic_vector(NUM_IRQS-1 downto 0) := (others => '0');
        irq_en_ext : in std_logic_vector(NUM_IRQS-1 downto 0) := (others => '0');

        -- M3c.4: shared-window master port -> one mp_arbiter master slice in
        -- MCU.vhd. req/we/addr/wdata out; gnt/done/rdata back. req is held
        -- until done (1-cycle pulse); addr/wdata are stable across the wait
        -- because the core's clk_cpu is gated off while stalled.
        sh_req    : out std_logic;
        sh_we     : out std_logic_vector(3 downto 0);  -- active-high byte-lane strobes (M4a)
        sh_addr   : out std_logic_vector(SH_AW-1 downto 0);
        sh_wdata  : out std_logic_vector(31 downto 0);
        sh_gnt    : in  std_logic := '0';
        sh_done   : in  std_logic := '0';
        sh_rdata  : in  std_logic_vector(31 downto 0) := (others => '0');
        -- M4b: global LR/SC — txn tag out ("01" LR read / "10" SC write
        -- attempt), resv_unit SC verdict in (valid with sh_done; latched here)
        sh_lrsc   : out std_logic_vector(1 downto 0);
        sh_scfail : in  std_logic := '0';
        -- M8: grant-lock request to mp_arbiter — the core's amo_lock, high
        -- for the whole AMO read-modify-write flow so the arbiter pins the
        -- grant to this hart between the AMO's read and write transactions.
        sh_lock   : out std_logic;

        trap_flag : out std_logic;
        a0        : out std_logic_vector(31 downto 0)
    );
end entity;

architecture behav of hart_tile is

    -- vesta core (matches hdl/MCU_MP/MCU.vhd component decl)
    component vesta
        generic (
            PC_RST_VAL : std_logic_vector(31 downto 0);
            NUM_IRQS  : natural;
            HARTID    : natural := 0
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
            mem_ready        : in  std_logic := '1';

            lr_sc_bus        : out std_logic_vector(1 downto 0);
            sc_fail_ext      : in  std_logic := '0';
            amo_lock         : out std_logic;

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

            wen               : in  std_logic_vector(3 downto 0);
            data_addr         : in  std_logic_vector(31 downto 0);
            write_word        : in  std_logic_vector(31 downto 0);
            mask              : out std_logic_vector(1 downto 0);

            write_data        : out std_logic_vector(31 downto 0);
            read_data         : out std_logic_vector(31 downto 0);
            mem_addr          : out std_logic_vector(11 downto 0);
            addr_periph       : out std_logic_vector(7 downto 2);
            mab_out           : out std_logic_vector(31 downto 0);
            wen_fe            : out std_logic_vector(3 downto 0);
            GWEN              : out std_logic;

            mem_en            : out std_logic_vector(2 downto 0);
            mem_en_periph     : out std_logic_vector(15 downto 0);
            clk_mem           : out std_logic_vector(2 downto 0);
            clk_periph        : out std_logic_vector(15 downto 0);

            mem_en_flash      : out std_logic;
            clk_mem_flash     : out std_logic;

            mem_dout          : in word_array(0 to 2);
            periph_dout       : in word_array(0 to 15);
            flash_dout        : in std_logic_vector(31 downto 0)
        );
    end component;

    -- constant tie-offs
    constant zero_word   : std_logic_vector(31 downto 0)        := (others => '0');
    constant zero_irq    : std_logic_vector(NUM_IRQS-1 downto 0) := (others => '0');
    constant zero_periph : word_array(0 to 15)                  := (others => (others => '0'));

    -- M5b: the two CLINT slots are ALWAYS enabled in a tile (no SYSTEM
    -- peripheral here to program them); M7a ORs in the software-routed
    -- shared-peripheral enables from the irq_router (irq_en_ext).
    constant tile_irq_hw_en : std_logic_vector(NUM_IRQS-1 downto 0) :=
        (IRQB_CLINT_MSIP => '1', IRQB_CLINT_MTIP => '1', others => '0');
    signal tile_irq_en   : std_logic_vector(NUM_IRQS-1 downto 0);

    -- M5b/M7a: per-hart CLINT + routed peripheral levels into this core's vector
    signal tile_irq_vec  : std_logic_vector(NUM_IRQS-1 downto 0);

    -- core <-> adddec private bus
    signal clk_cpu     : std_logic;
    signal data_addr   : std_logic_vector(31 downto 0);
    signal wen_re      : std_logic_vector(3 downto 0);
    signal write_word  : std_logic_vector(31 downto 0);
    signal read_data   : std_logic_vector(31 downto 0);
    signal mask        : std_logic_vector(1 downto 0);

    -- adddec <-> private memory bus
    signal write_data  : std_logic_vector(31 downto 0);
    signal mem_addr    : std_logic_vector(11 downto 0);
    signal addr_periph : std_logic_vector(7 downto 2);
    signal wen_fe      : std_logic_vector(3 downto 0);
    signal GWEN        : std_logic;
    signal mem_en      : std_logic_vector(2 downto 0);
    signal clk_mem     : std_logic_vector(2 downto 0);
    signal mem_dout    : word_array(0 to 2);

    -- unused decoder outputs (peripheral / flash side, tied off for M3b)
    signal mem_en_periph : std_logic_vector(15 downto 0);
    signal clk_periph    : std_logic_vector(15 downto 0);
    signal mem_en_flash  : std_logic;
    signal clk_mem_flash : std_logic;
    signal mab_out       : std_logic_vector(31 downto 0);

    -- M3c.4: shared-window master state (mirror of hart 0's wiring in MCU.vhd)
    signal sh_sel         : std_logic;
    signal sh_dphase      : std_logic := '0';  -- clk_cpu-domain: shared access in data phase
    signal sh_acked       : std_logic := '0';
    signal sh_acked_we    : std_logic_vector(3 downto 0) := (others => '0'); -- lanes of the acked txn (M4b)
    signal sh_ack_ok      : std_logic;          -- ack valid FOR THE CURRENT ACCESS TYPE
    signal sh_we_lanes    : std_logic_vector(3 downto 0);
    signal sh_rdata_reg   : std_logic_vector(31 downto 0) := (others => '0');
    signal sh_scfail_reg  : std_logic := '0';   -- resv_unit SC verdict, latched at done (M4b)
    signal core_read_data : std_logic_vector(31 downto 0);
    signal mem_ready_sh   : std_logic;
    signal lr_sc_bus      : std_logic_vector(1 downto 0);

begin

    -- M7a: vector = the fanned-out deglitched peripheral levels, with the two
    -- CLINT slots overridden by THIS hart's own msip/mtip (irq_ext carries
    -- hart 0's CLINT bits there — never consume them). Enables = hardwired
    -- CLINT slots OR the software-routed row from the irq_router.
    tile_irq_proc: process(irq_ext, msip_in, mtip_in)
    begin
        tile_irq_vec <= irq_ext;
        tile_irq_vec(IRQB_CLINT_MSIP) <= msip_in;
        tile_irq_vec(IRQB_CLINT_MTIP) <= mtip_in;
    end process;

    tile_irq_en <= irq_en_ext or tile_irq_hw_en;

    core: vesta
        generic map (
            PC_RST_VAL => PC_RST_VAL,
            NUM_IRQS   => NUM_IRQS,
            HARTID     => HARTID
        )
        port map (
            clk         => clk,
            resetn      => resetn,
            sleep       => sleep,
            clk_cpu     => clk_cpu,

            data_addr    => data_addr,
            wen          => wen_re,
            write_data   => write_word,
            read_data    => core_read_data, -- adddec data, or shared-window data in the data phase
            mask         => mask,
            mem_ready    => mem_ready_sh,   -- '1' except during a shared-window transaction

            lr_sc_bus    => lr_sc_bus,
            sc_fail_ext  => sh_scfail_reg,
            amo_lock     => sh_lock,

            irq_vector       => tile_irq_vec,
            irq_priority     => zero_irq,
            irq_en           => tile_irq_en,
            irq_recursion_en => '0',
            isr_ret          => open,

            trap_flag    => trap_flag,
            a0           => a0
        );

    adddec0: adddec
        generic map (
            ENABLE_FLASH_EXTENDED_MEM => false
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
            addr_periph     => addr_periph,
            mab_out         => mab_out,
            wen_fe          => wen_fe,
            GWEN            => GWEN,

            mem_en          => mem_en,
            mem_en_periph   => mem_en_periph,
            clk_mem         => clk_mem,
            clk_periph      => clk_periph,

            mem_en_flash    => mem_en_flash,
            clk_mem_flash   => clk_mem_flash,

            mem_dout       => mem_dout,
            periph_dout    => zero_periph,
            flash_dout     => zero_word
        );

    -- =========================================================================
    -- M3c.4: shared-window master (hart 0's proven M3c wiring, tile-internal).
    -- See the header comment for the design rationale of every piece.
    -- =========================================================================
    -- EXACT decode of 0x10000-0x13FFF (data_addr(31:14) = 4). adddec (flash
    -- disabled here) asserts no memory/peripheral enable for region 4, same as
    -- hart 0's <0x14000 carve-out.
    sh_sel <= '1' when data_addr(31 downto 14) = "000000000000000100" else '0';

    -- one-shot handshake on the FREE-RUNNING clk (mclk): request until this
    -- access completes (done), then hold off re-request until the core steps
    -- off the shared address (clk_cpu is gated while stalled, so
    -- data_addr/wen/write_word are stable across the wait).
    --
    -- M4b: the ack additionally remembers the LANE STROBES of the completed
    -- txn (sh_acked_we) and only satisfies an access with the SAME strobes
    -- (sh_ack_ok, combinational). WHY: an SC keeps data_addr on the shared
    -- address across two back-to-back accesses with different types — a read
    -- in EXECUTE, then the conditional WRITE in SC_CHECK. With an
    -- address-only ack the write would never issue (silently lost SC). The
    -- lane change drops sh_ack_ok inside the SC_CHECK cycle => the core
    -- re-stalls and the write runs as a fresh arbiter transaction.
    sh_handshake: process(clk, resetn)
    begin
        if resetn = '0' then
            sh_acked      <= '0';
            sh_acked_we   <= (others => '0');
            sh_rdata_reg  <= (others => '0');
            sh_scfail_reg <= '0';
        elsif rising_edge(clk) then
            if sh_sel = '0' then
                sh_acked      <= '0';
                sh_scfail_reg <= '0';
            elsif sh_done = '1' then
                sh_acked      <= '1';
                sh_acked_we   <= sh_we_lanes;
                sh_rdata_reg  <= sh_rdata;   -- capture shared read data
                sh_scfail_reg <= sh_scfail;  -- capture resv_unit SC verdict
            end if;
        end if;
    end process;

    -- wen is ACTIVE-LOW per byte lane; arbiter we is active-high per lane (M4a).
    -- write_word is lane-positioned by the core's store extender => sb/sh work.
    sh_we_lanes <= (not wen_re) when sh_sel = '1' else (others => '0');
    sh_we       <= sh_we_lanes;

    sh_ack_ok <= '1' when sh_acked = '1' and sh_acked_we = sh_we_lanes else '0';

    sh_req   <= sh_sel and not sh_ack_ok;
    sh_addr  <= data_addr(SH_AW+1 downto 2);
    sh_wdata <= write_word;
    sh_lrsc  <= lr_sc_bus when sh_sel = '1' else "00";

    -- back-pressure into the core (identity while sh_sel='0')
    mem_ready_sh <= (not sh_sel) or sh_ack_ok;

    -- Read-data mux, DATA-PHASE ONLY, select registered on the tile's own gated
    -- clk_cpu — BY DESIGN (bug 4: a raw-sh_sel mux on read_data oscillates,
    -- because read_data is the instruction during decode). sh_dphase is '1'
    -- exactly during the MEMORY_WAIT cycle, where read_data is consumed as
    -- LOAD DATA and the instruction comes from the held instr_curr_prev.
    sh_dphase_reg: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            sh_dphase <= '0';
        elsif rising_edge(clk_cpu) then
            sh_dphase <= sh_sel;
        end if;
    end process;

    core_read_data <= sh_rdata_reg when sh_dphase = '1' else read_data;

    -- Private ROM (0x0000). Never fetched in M3b (harts boot at 0x8200 in RAM0),
    -- present only to satisfy the decoder's mem_dout(0) region.
    rom0: entity work.rom_hvt_pg
        port map (
            Q    => mem_dout(0),
            CLK  => clk_mem(0),
            CEN  => mem_en(0),
            A    => mem_addr,
            EMA  => "000",
            PGEN => '0'
        );

    -- Private RAM0 (0x8000-0xBFFF): code + IVT, preloaded from RAM0_INIT_FILE.
    ram0: entity work.sram1p16k_hvt_pg
        generic map (
            INIT_FILE => RAM0_INIT_FILE
        )
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
            PGEN  => '0'
        );

    -- Private RAM1 (0xC000-0xFFFF): stack + ISR vectors + data, preloaded from
    -- RAM1_INIT_FILE. Plain (no NPU mux) -- harts 1-3 have no NPU in M3b.
    ram1: entity work.sram1p16k_hvt_pg
        generic map (
            INIT_FILE => RAM1_INIT_FILE
        )
        port map (
            Q     => mem_dout(2),
            CLK   => clk_mem(2),
            CEN   => mem_en(2),
            WEN   => wen_fe,
            A     => mem_addr,
            D     => write_data,
            EMA   => "000",
            GWEN  => GWEN,
            RETN  => '1',
            PGEN  => '0'
        );

end architecture;
