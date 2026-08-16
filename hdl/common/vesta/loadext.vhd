-- loadext.vhd
-- Load-data alignment and extension: picks the addressed byte or halfword out of the 32-bit word and sign- or zero-extends it according to funct3.
-- The byte-select mask is latched on the rising edge because the data phase arrives one cycle after the address.
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.constants.all;

entity loadext is
    port (
        clk        : in STD_LOGIC;
        funct3     : in  STD_LOGIC_VECTOR(2 downto 0);   -- load width and signedness
        mask       : in  STD_LOGIC_VECTOR(1 downto 0);   -- byte offset within the addressed word
        read_data   : in  STD_LOGIC_VECTOR(XLEN-1 downto 0);
        extended_data : out STD_LOGIC_VECTOR(XLEN-1 downto 0)
    );
end loadext;

architecture Behavioral of loadext is
    signal byte_data   : STD_LOGIC_VECTOR(7 downto 0);
    signal half_data   : STD_LOGIC_VECTOR(15 downto 0);
    signal mask_latched: STD_LOGIC_VECTOR(1 downto 0);
    -- signal mask_intermediate : STD_LOGIC_VECTOR(1 downto 0);
begin


    -- latch_mask_int: process(clk) 
    -- begin
    --     if falling_edge(clk) then 
    --         mask_intermediate <= mask;
    --     end if;
    -- end process;

    -- Hold the byte offset from the address phase so it lines up with the returning data.
    latch_mask: process(clk) 
    begin
        if rising_edge(clk) then 
            -- mask_latched <= mask_intermediate;
            mask_latched <= mask;
        end if;
    end process;

    -- Select the addressed byte lane.
    with mask_latched select
        byte_data <= read_data(7 downto 0)   when "00",
                     read_data(15 downto 8)  when "01",
                     read_data(23 downto 16) when "10",
                     read_data(31 downto 24) when "11",
                     (others => '0')        when others;

    -- Select the addressed halfword; only the upper mask bit matters.
    half_data <= read_data(15 downto 0) when mask_latched(1) = '0' else
                 read_data(31 downto 16);

    -- Pick the width and extension the load asked for.
    with funct3 select
        extended_data <= 
            -- LB: load byte, sign-extended
            (XLEN-1 downto 8 => byte_data(7)) & byte_data when "000",
            -- LH: load halfword, sign-extended
            (XLEN-1 downto 16 => half_data(15)) & half_data when "001",
            -- LW: load word, no extension needed
            read_data when "010",
            -- LBU: load byte, zero-extended
            (XLEN-1 downto 8 => '0') & byte_data when "100",
            -- LHU: load halfword, zero-extended
            (XLEN-1 downto 16 => '0') & half_data when "101",
            -- Any other funct3 passes the raw word through.
            -- x"00000000" when others;
            read_data when others;
end Behavioral;
