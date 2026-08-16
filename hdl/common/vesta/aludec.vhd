-- aludec.vhd
-- ALU control decoder: turns the main decoder's ALU_op class plus the instruction's funct3 and funct7 bit 5 into the ALU's 5-bit operation code.
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use work.constants.all;
use IEEE.NUMERIC_STD.all;

entity aludec is
   port(
       opb5:           in    STD_LOGIC; -- opcode bit 5: set for R-type, clear for I-type
       funct3:         in    STD_LOGIC_VECTOR(2 downto 0); -- selects which operation to run for R-type instructions
       funct7b5:       in    STD_LOGIC; -- set for R-type and I-type subtract and arithmetic shift
       ALU_op:          in    STD_LOGIC_VECTOR(1 downto 0); -- ALU class from the main decoder, for non-R-type instructions
       ALU_control:     out   STD_LOGIC_VECTOR(4 downto 0)
   );
end aludec;

architecture behave of aludec is
    signal RtypeSub: STD_LOGIC;
begin
    RtypeSub <= funct7b5 and opb5; -- Set for an R-type subtract

    -- Combinational decode of the ALU operation.
    process(opb5, funct3, funct7b5, ALU_op, RtypeSub) begin
        case ALU_op is
            -- Address or offset arithmetic: loads, stores, jumps.
            when "00" =>
                ALU_control <= "00000"; -- addition
            -- B-type: the branch comparison the ALU must perform.
            when "01" =>
                case funct3(2 downto 1) is  -- top two funct3 bits pick the comparison
                    when BEQ_TOP_FN3 =>
                        ALU_control <= "00001";    --subtraction
                    when BCOMP_TOP_FN3 =>
                        ALU_control <= "00101"; -- slt
                    when BCOMPU_TOP_FN3 =>
                        ALU_control <= "01001"; -- sltu
                    when others =>
                        -- Unknown encoding: ALU_control is left unassigned, a don't-care.
                end case;
            -- LUI: pass the immediate straight through.
            when "11" =>
                ALU_control <= "01010"; -- pass b, used by lui
            -- R-type and I-type ALU operations, decoded from funct3.
            when others =>
                case funct3 is
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
                        -- funct7 bit 5 selects arithmetic over logical, and it is tested directly rather than through RtypeSub so that SRAI is covered too.
                        if funct7b5 = '1' then
                            ALU_control <= "01000"; -- sra
                        else
                            ALU_control <= "00111"; -- srl
                        end if;
                    when OR_FN3 =>
                        ALU_control <= "00011"; -- or, ori
                    when AND_FN3 =>
                        ALU_control <= "00010"; -- and, andi
                    when others =>
                        -- Unknown encoding: ALU_control is left unassigned, a don't-care.
                end case;
        end case;
    end process;
end behave;
