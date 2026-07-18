library IEEE;
use IEEE.STD_LOGIC_1164.all;
use work.constants.all;
use IEEE.NUMERIC_STD.all;

entity aludec is
   port(
       opb5:           in    STD_LOGIC;
       funct3:         in    STD_LOGIC_VECTOR(2 downto 0); --states which funct to execute for R Type instructions
       funct7b5:       in    STD_LOGIC; --TRUE for R and I type subtractions
       ALU_op:          in    STD_LOGIC_VECTOR(1 downto 0); --used for ALU control for non-R-type instructions
       ALU_control:     out   STD_LOGIC_VECTOR(4 downto 0)
   );
end aludec;

architecture behave of aludec is
    signal RtypeSub: STD_LOGIC;
begin
    RtypeSub <= funct7b5 and opb5; -- TRUE for R–type subtract

    process(opb5, funct3, funct7b5, ALU_op, RtypeSub) begin
        case ALU_op is
            when "00" =>
                ALU_control <= "00000"; -- addition
            when "01" =>    --B-type instruction
                case funct3(2 downto 1) is  -- R–type or I–type ALU
                    when BEQ_TOP_FN3 =>
                        ALU_control <= "00001";    --subtraction
                    when BCOMP_TOP_FN3 =>
                        ALU_control <= "00101"; -- slt
                    when BCOMPU_TOP_FN3 =>
                        ALU_control <= "01001"; -- sltu
                    when others =>
                        -- ALU_control <= "----"; -- unknown
                end case;
            when "11" =>
                ALU_control <= "01010"; --pass b (for lui)
            when others =>
                case funct3 is  -- R–type or I–type ALU
                    when ADD_FN3 =>
                        if RtypeSub = '1' then
                            ALU_control <= "00001"; -- sub
                        else
                            ALU_control <= "00000"; -- add, addi
                        end if;
                    when SLL_FN3 =>
                        ALU_control <= "00110"; -- sll
                    when SLT_FN3 =>
                        ALU_control <= "00101"; -- slt, slti
                    when SLTU_FN3 =>
                        ALU_control <= "01001"; -- sltu, sltui
                    when XOR_FN3 =>
                        ALU_control <= "00100"; -- xor
                    when SRL_FN3 =>
                        if funct7b5 = '1' then  --indicating sub for R and I type (Note, maybe RtypeSub ... want to include SRAI as well )
                            ALU_control <= "01000"; -- sra
                        else
                            ALU_control <= "00111"; -- srl
                        end if;
                    when OR_FN3 =>
                        ALU_control <= "00011"; -- or, ori
                    when AND_FN3 =>
                        ALU_control <= "00010"; -- and, andi
                    when others =>
                        -- ALU_control <= "----"; -- unknown
                end case;
        end case;
    end process;
end behave;
