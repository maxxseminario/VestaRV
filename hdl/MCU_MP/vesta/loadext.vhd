library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity loadext is
    port (
        clk        : in STD_LOGIC;
        funct3     : in  STD_LOGIC_VECTOR(2 downto 0);
        mask       : in  STD_LOGIC_VECTOR(1 downto 0);
        read_data   : in  STD_LOGIC_VECTOR(31 downto 0);
        extended_data : out STD_LOGIC_VECTOR(31 downto 0)
    );
end loadext;

architecture Behavioral of loadext is
    signal byte_data   : STD_LOGIC_VECTOR(7 downto 0);
    signal half_data   : STD_LOGIC_VECTOR(15 downto 0);
    signal mask_latched: STD_LOGIC_VECTOR(1 downto 0);
    -- signal mask_intermediate : STD_LOGIC_VECTOR(1 downto 0);
begin

    -- This is causing an error post genus - timing. Changed to falling edge

    -- latch_mask_int: process(clk) 
    -- begin
    --     if falling_edge(clk) then 
    --         mask_intermediate <= mask;
    --     end if;
    -- end process;

    latch_mask: process(clk) 
    begin
        if rising_edge(clk) then 
            -- mask_latched <= mask_intermediate;
            mask_latched <= mask;
        end if;
    end process;

    -- Extract byte based on mask
    with mask_latched select
        byte_data <= read_data(7 downto 0)   when "00",
                     read_data(15 downto 8)  when "01",
                     read_data(23 downto 16) when "10",
                     read_data(31 downto 24) when "11",
                     (others => '0')        when others;

    -- Extract halfword based on mask(1)
    half_data <= read_data(15 downto 0) when mask_latched(1) = '0' else
                 read_data(31 downto 16);

    -- Select output based on funct3
    with funct3 select
        extended_data <= 
            -- LB: Load Byte, Sign-Extended
            (31 downto 8 => byte_data(7)) & byte_data when "000",
            -- LH: Load Half-Word, Sign-Extended
            (31 downto 16 => half_data(15)) & half_data when "001",
            -- LW: Load Word (no extension needed)
            read_data when "010",
            -- LBU: Load Byte, Zero-Extended
            (31 downto 8 => '0') & byte_data when "100",
            -- LHU: Load Half-Word, Zero-Extended
            (31 downto 16 => '0') & half_data when "101",
            -- Default case
            -- x"00000000" when others;
            read_data when others;
end Behavioral;
