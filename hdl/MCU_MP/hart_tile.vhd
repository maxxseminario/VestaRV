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
-- tied off internally here. The shared-peripheral bus + arbiter come in M3c;
-- at that point these tie-offs become tile ports feeding mp_arbiter.
--
-- mem_ready is tied '1': private memory never stalls (the arbiter-driven stall
-- only ever applies to the future shared region).
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
        RAM1_INIT_FILE : string := ""    -- 0xC000-0xFFFF preload image (next 4096 words)
    );
    port (
        clk       : in  std_logic;   -- free-running mclk
        resetn    : in  std_logic;
        sleep     : in  std_logic;

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
            read_data    => read_data,
            mask         => mask,
            mem_ready    => '1',            -- private memory never stalls

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
