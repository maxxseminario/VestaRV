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
-- The shared window writes the FULL word (no byte lanes yet - M4 TODO);
-- sub-word shared stores are unsupported.
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
        SH_AW          : natural := 8    -- shared-window word-address width (must match mp_arbiter)
    );
    port (
        clk       : in  std_logic;   -- free-running mclk
        resetn    : in  std_logic;
        sleep     : in  std_logic;

        -- M3c.4: shared-window master port -> one mp_arbiter master slice in
        -- MCU.vhd. req/we/addr/wdata out; gnt/done/rdata back. req is held
        -- until done (1-cycle pulse); addr/wdata are stable across the wait
        -- because the core's clk_cpu is gated off while stalled.
        sh_req    : out std_logic;
        sh_we     : out std_logic;
        sh_addr   : out std_logic_vector(SH_AW-1 downto 0);
        sh_wdata  : out std_logic_vector(31 downto 0);
        sh_gnt    : in  std_logic := '0';
        sh_done   : in  std_logic := '0';
        sh_rdata  : in  std_logic_vector(31 downto 0) := (others => '0');

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
    signal sh_rdata_reg   : std_logic_vector(31 downto 0) := (others => '0');
    signal core_read_data : std_logic_vector(31 downto 0);
    signal mem_ready_sh   : std_logic;

begin

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

            irq_vector       => zero_irq,
            irq_priority     => zero_irq,
            irq_en           => zero_irq,
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
    sh_handshake: process(clk, resetn)
    begin
        if resetn = '0' then
            sh_acked     <= '0';
            sh_rdata_reg <= (others => '0');
        elsif rising_edge(clk) then
            if sh_sel = '0' then
                sh_acked <= '0';
            elsif sh_done = '1' then
                sh_acked     <= '1';
                sh_rdata_reg <= sh_rdata;   -- capture shared read data
            end if;
        end if;
    end process;

    sh_req <= sh_sel and not sh_acked;
    -- wen is ACTIVE-LOW per byte lane; arbiter we is active-high => write when
    -- ANY lane is enabled. FULL-word writes only (no byte lanes yet - M4 TODO).
    sh_we  <= sh_sel and not (wen_re(0) and wen_re(1) and wen_re(2) and wen_re(3));
    sh_addr  <= data_addr(SH_AW+1 downto 2);
    sh_wdata <= write_word;

    -- back-pressure into the core (identity while sh_sel='0')
    mem_ready_sh <= (not sh_sel) or sh_acked;

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
