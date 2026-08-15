library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.constants.all;

entity store_ext is
    port (
        funct3     : in  STD_LOGIC_VECTOR(2 downto 0);
        read_data   : in  STD_LOGIC_VECTOR(XLEN-1 downto 0);
        extended_data : out STD_LOGIC_VECTOR(XLEN-1 downto 0)
    );
end store_ext;

architecture Behavioral of store_ext is
    signal byte_data   : STD_LOGIC_VECTOR(7 downto 0);
    signal half_data   : STD_LOGIC_VECTOR(15 downto 0);
begin

    byte_data <= read_data(7 downto 0);
    half_data <= read_data(15 downto 0);

    -- Replicate the store data across the bus so the byte lanes select the slice.
    -- The active-low WEn lanes pick which copy actually lands in memory.
    with funct3 select
        extended_data <=
            byte_data & byte_data & byte_data & byte_data when "000", -- SB: byte copied into all four lanes
            half_data & half_data when "001", -- SH: halfword copied into both halves
            read_data when others; -- SW and anything else: pass the word through unchanged
end Behavioral;
