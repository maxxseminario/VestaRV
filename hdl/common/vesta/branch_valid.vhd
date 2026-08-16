/* branch_valid.vhd
   Branch-condition evaluator: decides from funct3 and the ALU's Zero flag whether the branch is taken.
   The main decoder points the ALU at subtract for equality branches and at slt or sltu for the ordered ones, so every condition reduces to Zero or its inverse. */
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use work.constants.all;
use IEEE.NUMERIC_STD.all;

entity branch_valid is
   port(
       Zero:           in    STD_LOGIC; -- high when the ALU output is 0
       funct3:         in    STD_LOGIC_VECTOR(2 downto 0);   -- branch condition encoding
       brnch_cond_met:   out   STD_LOGIC   -- high when the branch is taken
   );
end branch_valid;

architecture behave of branch_valid is
    
begin

    -- Combinational condition decode.
    process(Zero, funct3) begin
        case funct3 is
            -- BEQ: taken when the difference is zero.
            when "000" => 
                brnch_cond_met <= Zero;
            -- BGE: the signed slt returned 0, so rs1 is not less than rs2.
            when "101" => 
                brnch_cond_met <= Zero;
            -- BGEU: the unsigned sltu returned 0, so rs1 is not below rs2.
            when "111" => 
                brnch_cond_met <= Zero;
            -- BNE: taken when the difference is nonzero.
            when "001" => 
                brnch_cond_met <= not Zero; 
            -- BLT: the signed slt returned 1.
            when "100" => 
                brnch_cond_met <= not Zero;
            -- BLTU: the unsigned sltu returned 1.
            when "110" => 
                brnch_cond_met <= not Zero; 
            -- Reserved funct3 encodings never branch.
            when others =>
                brnch_cond_met <= '0';    
        end case;
    end process;
end behave;
