library IEEE;
use IEEE.STD_LOGIC_1164.all;
use work.constants.all;
use IEEE.NUMERIC_STD.all;

entity branch_valid is
   port(
       Zero:           in    STD_LOGIC; -- high if ALU output is 0
       funct3:         in    STD_LOGIC_VECTOR(2 downto 0); 
       brnch_cond_met:   out   STD_LOGIC
   );
end branch_valid;

architecture behave of branch_valid is
    
begin

    process(Zero, funct3) begin
        case funct3 is
            when "000" => 
                brnch_cond_met <= Zero;
            when "101" => 
                brnch_cond_met <= Zero;
            when "111" => 
                brnch_cond_met <= Zero;
            when "001" => 
                brnch_cond_met <= not Zero; 
            when "100" => 
                brnch_cond_met <= not Zero;
            when "110" => 
                brnch_cond_met <= not Zero; 
            when others =>
                brnch_cond_met <= '0';    
        end case;
    end process;
end behave;
