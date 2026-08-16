library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.ALL;
use work.MemoryMap.all;

entity adddec is
    generic (
        ENABLE_FLASH_EXTENDED_MEM : boolean := false;
        -- Shared-window word-address width, passed down from hart_tile.
        -- The extended-flash decode is the strict complement of the master-side sh_sel window, and the TCM decode is qualified by the same upper bits so a wide window cannot alias onto it.
        SH_AW                     : natural := 15
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
        wen_fe            : out std_logic_vector(3 downto 0);
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
end adddec;

architecture Behavioral of adddec is

    -- Internal signals
    signal out_buff : std_logic_vector(31 downto 0);
    signal mem_en_sig : std_logic_vector(2 downto 0);
    signal mem_en_periph_sig : std_logic_vector(15 downto 0);
    signal mem_en_flash_sig : std_logic;
    signal mem_sel_int : std_logic_vector(2 downto 0);
    signal mem_sel_periph_int : std_logic_vector(15 downto 0);
    signal mem_sel_flash_int : std_logic;
    signal mem_region_sel : std_logic_vector(2 downto 0); 
    signal periph_addr_nat : natural;
    signal mem_sel_periph_nat : natural;
    signal is_flash_access : std_logic;
    signal en_clk_mem_flash : std_logic;
    signal flash_dout_reg : std_logic_vector(31 downto 0);

    -- SH_AW-derived all-zero comparators: FLASH_ZERO spans the bits above the shared window, tcm_upper_zero qualifies the window bits above the region field.
    -- tcm_upper_zero is driven from a generate because below SH_AW=16 its address slice is null and a null slice is illegal.
    constant FLASH_ZERO   : std_logic_vector(31 downto SH_AW+2) := (others => '0');
    constant ZEROS32      : std_logic_vector(31 downto 0) := (others => '0');
    signal tcm_upper_zero : std_logic;

begin

    -- This decoder serves ONLY the hart-private TCM at 0x08000-0x0BFFF (16KB RAM0, one per tile); everything below and above it is the shared window behind the mp_arbiter, claimed by the master-side sh_sel.
    -- Extended flash (when ENABLE_FLASH_EXTENDED_MEM) starts just above the shared window: 0x20000 at SH_AW=15.

    -- Extract the address fields the decode works on.
    mem_region_sel      <= data_addr(16 downto 14);
    periph_addr_nat     <= slv2uint(data_addr(11 downto 8));
    mem_sel_periph_nat  <= slv2uint(not mem_sel_periph_int);

    -- A flash access is any address at or above the top of the shared window, 2^(SH_AW+2): 0x20000 at SH_AW=15, 0x40000 at SH_AW=16.
    -- Keep this the exact complement of the master-side sh_sel regions: two subsystems claiming one address deadlock the core, because SPI0 FlashActive freezes clk_cpu via sleep_cpu while the shared handshake stalls mem_ready.
    gen_flash_detect: if ENABLE_FLASH_EXTENDED_MEM generate
        is_flash_access <= '1' when data_addr(31 downto SH_AW+2) /= FLASH_ZERO else '0';
    end generate;
    
    gen_no_flash_detect: if not ENABLE_FLASH_EXTENDED_MEM generate
        is_flash_access <= '0';
    end generate;

    -- TCM upper-bit qualification: the TCM lives at 0x8000-0xBFFF only, so the window bits above the region field must be zero.
    -- Without it a wide window aliases 0x28000-0x2BFFF (region bits also "010") onto the TCM and double-claims against sh_sel; below SH_AW=16 no such bits exist and the qualifier is statically '1'.
    gen_tcm_qual: if SH_AW >= 16 generate
        tcm_upper_zero <= '1' when data_addr(SH_AW+1 downto 17) = ZEROS32(SH_AW+1 downto 17) else '0';
    end generate;
    gen_tcm_qual_none: if SH_AW < 16 generate
        tcm_upper_zero <= '1';
    end generate;

    -- Memory enable generation
    process(mem_region_sel, periph_addr_nat, is_flash_access, tcm_upper_zero)
    begin
        -- Initialize all enables to inactive
        mem_en_sig <= (others => '1');
        mem_en_periph_sig <= (others => '1');
        mem_en_flash_sig <= '1';

        if is_flash_access = '1' then
            -- Flash memory access
            mem_en_flash_sig <= '0';
        else
            -- Only the private TCM decodes here: 0x08000-0x0BFFF, region bits 16:14 = "010", RAM0.
            -- Regions 000 (boot ROM), 001 (peripheral window), 011 (NPU staging RAM) and 1xx (shared bulk RAM) are claimed by the master-side sh_sel, so no enable asserts here.

            case mem_region_sel is
                when "010" =>
                    -- The private TCM (RAM0), enabled active-low only when the upper window bits are zero.
                    if tcm_upper_zero = '1' then
                        mem_en_sig(MemSlotRAM0) <= '0';
                    end if;
                when others =>
                    -- Every other region is shared or unmapped: nothing decodes locally.
                    null;
            end case;
        end if;
    end process;

    -- Falling-edge register for the memory strobes and addresses, async reset to the INACTIVE values.
    -- Keep the reset arm: unreset staging is X at power-on and the first clock edge drives X through the clock gates onto the RAM CLK/CEN/WEN pins, which corrupts the SRAM arrays chip-wide.
    process(clk, resetn)
    begin
        if resetn = '0' then
            mem_en        <= (others => '1');
            mem_en_periph <= (others => '1');
            mab_out       <= (others => '0');
            mem_addr      <= (others => '0');
            addr_periph   <= (others => '0');
            wen_fe        <= (others => '1');
        elsif falling_edge(clk) then
            mem_en <= mem_en_sig;
            mem_en_periph <= mem_en_periph_sig;
            mab_out <= data_addr;
            mem_addr    <= data_addr(13 downto 2);
            addr_periph <= data_addr(7 downto 2);
            wen_fe <= wen;
        end if;
    end process;

    

    -- Rising-edge register for the memory selects, async reset to deasserted so the read mux falls through to its safe default arm.
    process(clk, resetn)
    begin
        if resetn = '0' then
            mem_sel_int        <= (others => '1');
            mem_sel_periph_int <= (others => '1');
            mem_sel_flash_int  <= '1';
            flash_dout_reg     <= (others => '0');
        elsif rising_edge(clk) then
            mem_sel_int <= mem_en_sig;
            mem_sel_periph_int <= mem_en_periph_sig;
            if ENABLE_FLASH_EXTENDED_MEM then
                mem_sel_flash_int <= mem_en_flash_sig;
                flash_dout_reg <= flash_dout;
            end if;
        end if;
    end process;

    -- Output buffer selection, combinational: only the private TCM and, when enabled, flash are sourced locally.
    -- Shared-region reads fall through to the safe default arm here and are consumed through the master-side sh_rdata_cpu mux instead.
    gen_flash_mux: if ENABLE_FLASH_EXTENDED_MEM generate
        out_buff <= nop                              when resetn = '0' else
                    flash_dout_reg                   when mem_sel_flash_int = '0' else  -- Flash
                    mem_dout(MemSlotRAM0)            when mem_sel_int = "101" else  -- RAM0 (TCM)
                    (others => '1');
    end generate;

    gen_no_flash_mux: if not ENABLE_FLASH_EXTENDED_MEM generate
        out_buff <= nop                              when resetn = '0' else
                    mem_dout(MemSlotRAM0)            when mem_sel_int = "101" else  -- RAM0 (TCM)
                    (others => '1');
    end generate;

    -- Clock Gates for Memory
    gen_cg_mem : for i in 0 to 2 generate
        cg_mem: entity work.ClkGate
            port map (
                ClkIn  => clk,
                En     => not mem_en(i),
                ClkOut => clk_mem(i)
            );
    end generate gen_cg_mem;

    -- Clock Gates for Peripherals
    gen_cg_periph : for i in 0 to 15 generate
        cg_periph: entity work.ClkGate
            port map (
                ClkIn  => clk,
                En     => not mem_en_periph(i),
                ClkOut => clk_periph(i)
            );
    end generate gen_cg_periph;
    
    -- Clock Gate for Flash Memory (if enabled)
    gen_flash_clk: if ENABLE_FLASH_EXTENDED_MEM generate
        en_clk_mem_flash <= '1' when mem_en_flash_sig = '0' else '0';
        mem_en_flash <= mem_en_flash_sig;
        cg_flash: entity work.ClkGate
            port map (
                ClkIn  => not clk,  -- Inverted clock for flash
                En     => en_clk_mem_flash,
                ClkOut => clk_mem_flash
            );
    end generate;
    
    gen_no_flash_clk: if not ENABLE_FLASH_EXTENDED_MEM generate
        mem_en_flash <= '1';  -- Inactive
        clk_mem_flash <= '0';
    end generate;


    -- Per-byte-lane capture of the write data, async reset so the write bus is X-free from power-on.
    mem_cntrl: process(clk, resetn)
    begin
        if resetn = '0' then
            write_data <= (others => '0');
        elsif falling_edge(clk) then
            if wen(0) = '0' then
                write_data(7 downto 0)   <= write_word(7 downto 0);
            end if;
            if wen(1) = '0' then
                write_data(15 downto 8)  <= write_word(15 downto 8);
            end if;
            if wen(2) = '0' then
                write_data(23 downto 16) <= write_word(23 downto 16);
            end if;
            if wen(3) = '0' then
                write_data(31 downto 24) <= write_word(31 downto 24);
            end if;
        end if;
    end process;

    -- Output Assignments
    GWEN        <= '0' when (wen_fe /= "1111") else '1'; -- Falling-edge sensitive: combinational from the fe-registered signals.
    read_data   <= out_buff;
    mask        <= data_addr(1 downto 0); -- Rising-edge sensitive assignment: control signal to the core, not to memory.
    
    

end Behavioral;
