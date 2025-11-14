library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
-- use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.ALL;
use work.MemoryMap.all;

entity adddec is
    generic (
        ENABLE_FLASH_EXTENDED_MEM : boolean := false
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

begin

    -- Memory map:
    -- ROM0 - 0x00000 - 0x03FFF (16KB)
    -- MMR  - 0x04000 - 0x07FFF (~16KB) Peripherals
    -- RAM0 - 0x08000 - 0x0BFFF (16KB)  
    -- RAM1 - 0x0C000 - 0x0FFFF (16KB)
    -- Extended Memory (Flash): 0x10000 and above (when ENABLE_FLASH_EXTENDED_MEM = true)

    -- Extract address fields
    mem_region_sel      <= data_addr(16 downto 14);
    periph_addr_nat     <= slv2uint(data_addr(11 downto 8));
    mem_sel_periph_nat  <= slv2uint(not mem_sel_periph_int);
    
    -- Pass full address bus for flash
    -- mab_out <= data_addr;
    
    -- Determine if this is a flash access
    -- Flash memory is accessed when address is >= 0x10000 (bit 16 or higher is set)
    gen_flash_detect: if ENABLE_FLASH_EXTENDED_MEM generate
        is_flash_access <= '1' when unsigned(data_addr) >= x"00010000" else '0';
    end generate;
    
    gen_no_flash_detect: if not ENABLE_FLASH_EXTENDED_MEM generate
        is_flash_access <= '0';
    end generate;

    -- Memory enable generation
    process(mem_region_sel, periph_addr_nat, is_flash_access)
    begin
        -- Initialize all enables to inactive
        mem_en_sig <= (others => '1');
        mem_en_periph_sig <= (others => '1');
        mem_en_flash_sig <= '1';
        
        if is_flash_access = '1' then
            -- Flash memory access
            mem_en_flash_sig <= '0';
        else
            -- Normal memory map
            -- ROM : 0x00000 - 0x03FFF (bits 16:14 = 000) 
            -- MMR : 0x04000 - 0x07FFF (bits 16:14 = 001)
            -- RAM0: 0x08000 - 0x0BFFF (bits 16:14 = 010)
            -- RAM1: 0x0C000 - 0x0FFFF (bits 16:14 = 011)
            
            case mem_region_sel is
                when "000" =>
                    mem_en_sig(MemSlotROM) <= '0';
                when "001" =>
                    -- Peripherals
                    case periph_addr_nat is
                        when PeriphSlotGPIO0   => mem_en_periph_sig(PeriphSlotGPIO0)   <= '0';
                        when PeriphSlotGPIO1   => mem_en_periph_sig(PeriphSlotGPIO1)   <= '0';
                        when PeriphSlotGPIO2   => mem_en_periph_sig(PeriphSlotGPIO2)   <= '0';
                        when PeriphSlotGPIO3   => mem_en_periph_sig(PeriphSlotGPIO3)   <= '0';
                        when PeriphSlotSPI0    => mem_en_periph_sig(PeriphSlotSPI0)    <= '0';
                        when PeriphSlotSPI1    => mem_en_periph_sig(PeriphSlotSPI1)    <= '0';
                        when PeriphSlotUART0   => mem_en_periph_sig(PeriphSlotUART0)   <= '0';
                        when PeriphSlotUART1   => mem_en_periph_sig(PeriphSlotUART1)   <= '0';
                        when PeriphSlotTIMER0  => mem_en_periph_sig(PeriphSlotTIMER0)  <= '0';
                        when PeriphSlotTIMER1  => mem_en_periph_sig(PeriphSlotTIMER1)  <= '0';
                        when PeriphSlotSystem0 => mem_en_periph_sig(PeriphSlotSystem0) <= '0';
                        when PeriphSlotNPU0    => mem_en_periph_sig(PeriphSlotNPU0)    <= '0';
                        when PeriphSlotAFE0    => mem_en_periph_sig(PeriphSlotAFE0)    <= '0';
                        when PeriphSlotSARADC0 => mem_en_periph_sig(PeriphSlotSARADC0) <= '0';
                        when PeriphSlotI2C0    => mem_en_periph_sig(PeriphSlotI2C0)    <= '0';
                        when PeriphSlotI2C1    => mem_en_periph_sig(PeriphSlotI2C1)    <= '0';
                        when others => null;
                    end case;
                when "010" =>
                    mem_en_sig(MemSlotRAM0) <= '0';
                when "011" =>
                    mem_en_sig(MemSlotRAM1) <= '0';
                when others =>
                    null;
            end case;
        end if;
    end process;

    -- Falling edge sensitive register for memory signals
    process(clk)
    begin
        if falling_edge(clk) then
            mem_en <= mem_en_sig;
            mem_en_periph <= mem_en_periph_sig;
            mab_out <= data_addr;
            mem_addr    <= data_addr(13 downto 2); 
            addr_periph <= data_addr(7 downto 2);
            mask        <= data_addr(1 downto 0);
            wen_fe <= wen;
        end if;
    end process;

    

    -- Rising edge sensitive register for memory select
    process(clk)
    begin
       if rising_edge(clk) then
            mem_sel_int <= mem_en_sig;
            mem_sel_periph_int <= mem_en_periph_sig;
            if ENABLE_FLASH_EXTENDED_MEM then
                mem_sel_flash_int <= mem_en_flash_sig;
                flash_dout_reg <= flash_dout;
            end if;
        end if;
    end process;

    -- Output buffer selection using combinational assignments
    gen_flash_mux: if ENABLE_FLASH_EXTENDED_MEM generate
        out_buff <= nop                              when resetn = '0' else
                    flash_dout_reg                   when mem_sel_flash_int = '0' else  -- Flash
                    mem_dout(MemSlotROM)             when mem_sel_int = "110" else  -- ROM
                    mem_dout(MemSlotRAM0)            when mem_sel_int = "101" else  -- RAM0
                    mem_dout(MemSlotRAM1)            when mem_sel_int = "011" else  -- RAM1
                    periph_dout(PeriphSlotGPIO0)     when mem_sel_int = "111" and mem_sel_periph_nat = GPIO0_MASK else
                    periph_dout(PeriphSlotGPIO1)     when mem_sel_int = "111" and mem_sel_periph_nat = GPIO1_MASK else
                    periph_dout(PeriphSlotGPIO2)     when mem_sel_int = "111" and mem_sel_periph_nat = GPIO2_MASK else
                    periph_dout(PeriphSlotGPIO3)     when mem_sel_int = "111" and mem_sel_periph_nat = GPIO3_MASK else
                    periph_dout(PeriphSlotSPI0)      when mem_sel_int = "111" and mem_sel_periph_nat = SPI0_MASK else
                    periph_dout(PeriphSlotSPI1)      when mem_sel_int = "111" and mem_sel_periph_nat = SPI1_MASK else
                    periph_dout(PeriphSlotUART0)     when mem_sel_int = "111" and mem_sel_periph_nat = UART0_MASK else
                    periph_dout(PeriphSlotUART1)     when mem_sel_int = "111" and mem_sel_periph_nat = UART1_MASK else
                    periph_dout(PeriphSlotTIMER0)    when mem_sel_int = "111" and mem_sel_periph_nat = TIMER0_MASK else
                    periph_dout(PeriphSlotTIMER1)    when mem_sel_int = "111" and mem_sel_periph_nat = TIMER1_MASK else
                    periph_dout(PeriphSlotSystem0)   when mem_sel_int = "111" and mem_sel_periph_nat = SYSTEM0_MASK else
                    periph_dout(PeriphSlotNPU0)      when mem_sel_int = "111" and mem_sel_periph_nat = NPU0_MASK else
                    periph_dout(PeriphSlotAFE0)      when mem_sel_int = "111" and mem_sel_periph_nat = AFE0_MASK else
                    periph_dout(PeriphSlotSARADC0)   when mem_sel_int = "111" and mem_sel_periph_nat = SARADC0_MASK else
                    periph_dout(PeriphSlotI2C0)      when mem_sel_int = "111" and mem_sel_periph_nat = I2C0_MASK else
                    periph_dout(PeriphSlotI2C1)      when mem_sel_int = "111" and mem_sel_periph_nat = I2C1_MASK else
                    (others => '1');  
    end generate;

    gen_no_flash_mux: if not ENABLE_FLASH_EXTENDED_MEM generate
        out_buff <= nop                              when resetn = '0' else
                    mem_dout(MemSlotROM)             when mem_sel_int = "110" else  -- ROM
                    mem_dout(MemSlotRAM0)            when mem_sel_int = "101" else  -- RAM0
                    mem_dout(MemSlotRAM1)            when mem_sel_int = "011" else  -- RAM1
                    periph_dout(PeriphSlotGPIO0)     when mem_sel_int = "111" and mem_sel_periph_nat = GPIO0_MASK else
                    periph_dout(PeriphSlotGPIO1)     when mem_sel_int = "111" and mem_sel_periph_nat = GPIO1_MASK else
                    periph_dout(PeriphSlotGPIO2)     when mem_sel_int = "111" and mem_sel_periph_nat = GPIO2_MASK else
                    periph_dout(PeriphSlotGPIO3)     when mem_sel_int = "111" and mem_sel_periph_nat = GPIO3_MASK else
                    periph_dout(PeriphSlotSPI0)      when mem_sel_int = "111" and mem_sel_periph_nat = SPI0_MASK else
                    periph_dout(PeriphSlotSPI1)      when mem_sel_int = "111" and mem_sel_periph_nat = SPI1_MASK else
                    periph_dout(PeriphSlotUART0)     when mem_sel_int = "111" and mem_sel_periph_nat = UART0_MASK else
                    periph_dout(PeriphSlotUART1)     when mem_sel_int = "111" and mem_sel_periph_nat = UART1_MASK else
                    periph_dout(PeriphSlotTIMER0)    when mem_sel_int = "111" and mem_sel_periph_nat = TIMER0_MASK else
                    periph_dout(PeriphSlotTIMER1)    when mem_sel_int = "111" and mem_sel_periph_nat = TIMER1_MASK else
                    periph_dout(PeriphSlotSystem0)   when mem_sel_int = "111" and mem_sel_periph_nat = SYSTEM0_MASK else
                    periph_dout(PeriphSlotNPU0)      when mem_sel_int = "111" and mem_sel_periph_nat = NPU0_MASK else
                    periph_dout(PeriphSlotAFE0)      when mem_sel_int = "111" and mem_sel_periph_nat = AFE0_MASK else
                    periph_dout(PeriphSlotSARADC0)   when mem_sel_int = "111" and mem_sel_periph_nat = SARADC0_MASK else
                    periph_dout(PeriphSlotI2C0)      when mem_sel_int = "111" and mem_sel_periph_nat = I2C0_MASK else
                    periph_dout(PeriphSlotI2C1)      when mem_sel_int = "111" and mem_sel_periph_nat = I2C1_MASK else
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


    -- Memory control process from memory_subsystem
    mem_cntrl: process(clk)
    begin
        if falling_edge(clk) then
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
    GWEN        <= '0' when (wen_fe /= "1111") else '1'; 
    read_data   <= out_buff;
    
    

end Behavioral;

