library IEEE;
use IEEE.STD_LOGIC_1164.all;

entity extend is
    port(
        instr  : in  STD_LOGIC_VECTOR(31 downto 7);
        imm_src : in  STD_LOGIC_VECTOR(2 downto 0);
        imm_ext : out STD_LOGIC_VECTOR(31 downto 0)
    );
end entity;

architecture behave of extend is
begin
    process(instr, imm_src)
    begin
        case imm_src is
            -- I-type
            when "000" =>
                imm_ext <= (31 downto 12 => instr(31)) & instr(31 downto 20);
                --Check if SRAI, fix imm -TODO: Check why I put this in origionally
                -- if instr(30) = '1' and instr(14 downto 12) = "101" then --SRAI operation
                --     imm_ext(10) <= '0';
                -- end if;
            -- S-types (stores)
            when "001" =>
                imm_ext <= (31 downto 12 => instr(31)) & instr(31 downto 25) & instr(11 downto 7);
            -- B-type (branches)
            when "010" =>
                imm_ext <= (31 downto 12 => instr(31)) & instr(7) & instr(30 downto 25) & instr(11 downto 8) & '0';
            -- J-type (jal)
            when "011" =>
                imm_ext <= (31 downto 20 => instr(31)) & instr(19 downto 12) & instr(20) & instr(30 downto 21) & '0';
            -- U-type
            when "100" =>
                imm_ext <= instr(31 downto 12) & x"000"; --bitshifted by 12
            when others =>
                imm_ext <= (31 downto 0 => '-');
        end case;
    end process;
end architecture;
