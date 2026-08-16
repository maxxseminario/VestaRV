-- extend.vhd
-- Immediate extractor: gathers the scattered immediate fields of each instruction format and sign-extends them to XLEN.
-- imm_src comes from the main decoder and names the format.
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use work.constants.all;

entity extend is
    port(
        instr  : in  STD_LOGIC_VECTOR(ILEN-1 downto 7);   -- instruction above the opcode field
        imm_src : in  STD_LOGIC_VECTOR(2 downto 0);       -- immediate format select
        imm_ext : out STD_LOGIC_VECTOR(XLEN-1 downto 0)   -- sign-extended immediate
    );
end entity;

architecture behave of extend is
begin
    -- Combinational immediate assembly, one arm per instruction format.
    process(instr, imm_src)
    begin
        case imm_src is
            -- I-type: one contiguous 12-bit field.
            when "000" =>
                imm_ext <= (XLEN-1 downto 12 => instr(31)) & instr(31 downto 20);
                -- SRAI immediate fix-up, disabled. TODO: decide whether it is needed at all.
                -- if instr(30) = '1' and instr(14 downto 12) = "101" then --SRAI operation
                --     imm_ext(10) <= '0';
                -- end if;
            -- S-type stores: the 12-bit field is split across the two register-field gaps.
            when "001" =>
                imm_ext <= (XLEN-1 downto 12 => instr(31)) & instr(31 downto 25) & instr(11 downto 7);
            -- B-type branches: split field, and bit 0 is implicitly zero.
            when "010" =>
                imm_ext <= (XLEN-1 downto 12 => instr(31)) & instr(7) & instr(30 downto 25) & instr(11 downto 8) & '0';
            -- J-type jal: 20-bit split field, again with an implicit zero bit 0.
            when "011" =>
                imm_ext <= (XLEN-1 downto 20 => instr(31)) & instr(19 downto 12) & instr(20) & instr(30 downto 21) & '0';
            -- U-type: the field already sits in the upper 20 bits.
            when "100" =>
                imm_ext <= instr(31 downto 12) & x"000"; -- shifted left by 12
            -- Unused encodings: don't-care, so synthesis can optimize the mux.
            when others =>
                imm_ext <= (XLEN-1 downto 0 => '-');
        end case;
    end process;
end architecture;
