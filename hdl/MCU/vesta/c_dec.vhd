library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity c_dec is
    port ( 
        resetn        : in  std_logic;
        instr_in      : in  std_logic_vector(31 downto 0);  -- Instruction word fetched from memory
        instr_out     : out std_logic_vector(31 downto 0);  -- 32-bit decompressed or original instruction
        is_compressed : out std_logic                       -- '1' if input was compressed
    );
end c_dec;

architecture rtl of c_dec is

    -- Helper function to check if 16-bit instruction is compressed
    function is_16bit_compressed(instr16 : std_logic_vector(15 downto 0)) return boolean is
    begin
        return (instr16(1 downto 0) /= "11");
    end function;

begin

    decompress_proc: process(instr_in, resetn)
        variable instr16 : std_logic_vector(15 downto 0);
        variable is_compressed_var : std_logic;
        variable dec : std_logic_vector(31 downto 0);
        
        -- Field extraction variables
        variable opcode : std_logic_vector(1 downto 0);
        variable funct3 : std_logic_vector(2 downto 0);
        variable funct2 : std_logic_vector(1 downto 0);
        variable funct4 : std_logic_vector(3 downto 0);
        variable funct6 : std_logic_vector(5 downto 0);
        
        variable rd, rs1, rs2 : std_logic_vector(4 downto 0);
        variable rd_p, rs1_p, rs2_p : std_logic_vector(2 downto 0);
        
        -- Immediate construction helpers
        variable imm_sign : std_logic;
        variable imm : std_logic_vector(31 downto 0);
        
    begin
        -- Initialize outputs
        dec := (others => '0');
        is_compressed_var := '0';
        
        if resetn = '0' then
            instr_out <= (others => '0');
            is_compressed <= '0';
        else
            instr16 := instr_in(15 downto 0);
            
            if is_16bit_compressed(instr16) then
                is_compressed_var := '1';
                
                -- Extract opcode and funct3
                opcode := instr16(1 downto 0);
                funct3 := instr16(15 downto 13);
                
                case opcode is
                    -- ========== QUADRANT 0 (00) ==========
                    when "00" =>
                        case funct3 is
                            -- C.ADDI4SPN -> addi rd', sp, nzuimm[9:2]
                            when "000" =>
                                rd_p := instr16(4 downto 2);
                                rd := "01" & rd_p;  -- x8-x15
                                
                                -- nzuimm[9:2] = inst[10:7,12:11,5,6]
                                imm := (others => '0');
                                imm(9 downto 6) := instr16(10 downto 7);
                                imm(5 downto 4) := instr16(12 downto 11);
                                imm(3) := instr16(5);
                                imm(2) := instr16(6);
                                -- imm[1:0] = 00 (implicit)
                                
                                if unsigned(imm(9 downto 0)) = 0 then
                                    -- Reserved instruction (all zeros)
                                    dec := (others => '0');
                                else
                                    -- ADDI rd', sp, nzuimm
                                    dec(6 downto 0)   := "0010011";  -- ADDI
                                    dec(11 downto 7)  := rd;
                                    dec(14 downto 12) := "000";      -- funct3
                                    dec(19 downto 15) := "00010";    -- sp (x2)
                                    dec(31 downto 20) := imm(11 downto 0);
                                end if;
                                
                            -- C.LW -> lw rd', offset[6:2](rs1')
                            when "010" =>
                                rd_p := instr16(4 downto 2);
                                rs1_p := instr16(9 downto 7);
                                rd := "01" & rd_p;   -- x8-x15
                                rs1 := "01" & rs1_p; -- x8-x15
                                
                                -- offset[6:2] = inst[5,12:10,6]
                                imm := (others => '0');
                                imm(6) := instr16(5);
                                imm(5 downto 3) := instr16(12 downto 10);
                                imm(2) := instr16(6);
                                -- imm[1:0] = 00 (implicit)
                                
                                -- LW rd', offset(rs1')
                                dec(6 downto 0)   := "0000011";  -- LW
                                dec(11 downto 7)  := rd;
                                dec(14 downto 12) := "010";      -- funct3
                                dec(19 downto 15) := rs1;
                                dec(31 downto 20) := imm(11 downto 0);
                                
                            -- C.SW -> sw rs2', offset[6:2](rs1')
                            when "110" =>
                                rs1_p := instr16(9 downto 7);
                                rs2_p := instr16(4 downto 2);
                                rs1 := "01" & rs1_p; -- x8-x15
                                rs2 := "01" & rs2_p; -- x8-x15
                                
                                -- offset[6:2] = inst[5,12:10,6]
                                imm := (others => '0');
                                imm(6) := instr16(5);
                                imm(5 downto 3) := instr16(12 downto 10);
                                imm(2) := instr16(6);
                                -- imm[1:0] = 00 (implicit)
                                
                                -- SW rs2', offset(rs1')
                                dec(6 downto 0)   := "0100011";  -- SW
                                dec(11 downto 7)  := imm(4 downto 0);
                                dec(14 downto 12) := "010";      -- funct3
                                dec(19 downto 15) := rs1;
                                dec(24 downto 20) := rs2;
                                dec(31 downto 25) := imm(11 downto 5);
                                
                            when others =>
                                dec := (others => '0');  -- Reserved
                        end case;
                        
                    -- ========== QUADRANT 1 (01) ==========
                    when "01" =>
                        case funct3 is
                            -- C.NOP / C.ADDI -> addi rd, rd, nzimm[5:0]
                            when "000" =>
                                rd := instr16(11 downto 7);
                                
                                -- nzimm[5:0] = inst[12,6:2]
                                imm_sign := instr16(12);
                                imm := (others => imm_sign);
                                imm(5) := instr16(12);
                                imm(4 downto 0) := instr16(6 downto 2);
                                
                                -- ADDI rd, rd, nzimm
                                dec(6 downto 0)   := "0010011";  -- ADDI
                                dec(11 downto 7)  := rd;
                                dec(14 downto 12) := "000";      -- funct3
                                dec(19 downto 15) := rd;
                                dec(31 downto 20) := imm(11 downto 0);
                                
                            -- C.JAL -> jal x1, offset[11:1] (RV32 only)
                            when "001" =>
                                -- offset[11|4|9:8|10|6|7|3:1|5] = inst[12|11|10:9|8|7|6|5:3|2]
                                imm_sign := instr16(12);
                                imm := (others => imm_sign);
                                imm(11) := instr16(12);
                                imm(10) := instr16(8);
                                imm(9 downto 8) := instr16(10 downto 9);
                                imm(7) := instr16(6);
                                imm(6) := instr16(7);
                                imm(5) := instr16(2);
                                imm(4) := instr16(11);
                                imm(3 downto 1) := instr16(5 downto 3);
                                -- imm(0) = 0 (implicit)
                                
                                -- JAL x1, offset
                                dec(6 downto 0)   := "1101111";  -- JAL
                                dec(11 downto 7)  := "00001";    -- x1
                                dec(19 downto 12) := imm(19 downto 12);
                                dec(20)           := imm(11);
                                dec(30 downto 21) := imm(10 downto 1);
                                dec(31)           := imm(20);
                                
                            -- C.LI -> addi rd, x0, imm[5:0]
                            when "010" =>
                                rd := instr16(11 downto 7);
                                
                                -- imm[5:0] = inst[12,6:2]
                                imm_sign := instr16(12);
                                imm := (others => imm_sign);
                                imm(5) := instr16(12);
                                imm(4 downto 0) := instr16(6 downto 2);
                                
                                -- ADDI rd, x0, imm
                                dec(6 downto 0)   := "0010011";  -- ADDI
                                dec(11 downto 7)  := rd;
                                dec(14 downto 12) := "000";      -- funct3
                                dec(19 downto 15) := "00000";    -- x0
                                dec(31 downto 20) := imm(11 downto 0);
                                
                            -- C.ADDI16SP / C.LUI
                            when "011" =>
                                rd := instr16(11 downto 7);
                                
                                if rd = "00010" then
                                    -- C.ADDI16SP -> addi sp, sp, nzimm[9:4]
                                    -- nzimm[9|4|6|8:7|5] = inst[12|6|5|4:3|2]
                                    imm_sign := instr16(12);
                                    imm := (others => imm_sign);
                                    imm(9) := instr16(12);
                                    imm(8 downto 7) := instr16(4 downto 3);
                                    imm(6) := instr16(5);
                                    imm(5) := instr16(2);
                                    imm(4) := instr16(6);
                                    -- imm[3:0] = 0000 (implicit)
                                    
                                    if unsigned(imm(9 downto 4)) = 0 then
                                        dec := (others => '0');  -- Reserved
                                    else
                                        -- ADDI sp, sp, nzimm
                                        dec(6 downto 0)   := "0010011";  -- ADDI
                                        dec(11 downto 7)  := "00010";    -- sp
                                        dec(14 downto 12) := "000";      -- funct3
                                        dec(19 downto 15) := "00010";    -- sp
                                        dec(31 downto 20) := imm(11 downto 0);
                                    end if;
                                else
                                    -- C.LUI -> lui rd, nzimm[17:12]
                                    -- nzimm[17|16:12] = inst[12|6:2]
                                    imm_sign := instr16(12);
                                    imm := (others => imm_sign);
                                    imm(17) := instr16(12);
                                    imm(16 downto 12) := instr16(6 downto 2);
                                    
                                    if rd = "00000" or unsigned(imm(17 downto 12)) = 0 then
                                        dec := (others => '0');  -- Reserved
                                    else
                                        -- LUI rd, imm
                                        dec(6 downto 0)   := "0110111";  -- LUI
                                        dec(11 downto 7)  := rd;
                                        dec(31 downto 12) := imm(31 downto 12);
                                    end if;
                                end if;
                                
                            -- ALU operations
                            when "100" =>
                                funct2 := instr16(11 downto 10);
                                rs1_p := instr16(9 downto 7);
                                rs1 := "01" & rs1_p;  -- x8-x15
                                
                                case funct2 is
                                    -- C.SRLI -> srli rd', rd', shamt[5:0]
                                    when "00" =>
                                        -- shamt[5:0] = inst[12,6:2]
                                        imm := (others => '0');
                                        imm(5) := instr16(12);
                                        imm(4 downto 0) := instr16(6 downto 2);
                                        
                                        -- SRLI rd', rd', shamt
                                        dec(6 downto 0)   := "0010011";  -- SRLI
                                        dec(11 downto 7)  := rs1;
                                        dec(14 downto 12) := "101";      -- funct3
                                        dec(19 downto 15) := rs1;
                                        dec(24 downto 20) := imm(4 downto 0);
                                        dec(31 downto 25) := "0000000";
                                        
                                    -- C.SRAI -> srai rd', rd', shamt[5:0]
                                    when "01" =>
                                        -- shamt[5:0] = inst[12,6:2]
                                        imm := (others => '0');
                                        imm(5) := instr16(12);
                                        imm(4 downto 0) := instr16(6 downto 2);
                                        
                                        -- SRAI rd', rd', shamt
                                        dec(6 downto 0)   := "0010011";  -- SRAI
                                        dec(11 downto 7)  := rs1;
                                        dec(14 downto 12) := "101";      -- funct3
                                        dec(19 downto 15) := rs1;
                                        dec(24 downto 20) := imm(4 downto 0);
                                        dec(31 downto 25) := "0100000";
                                        
                                    -- C.ANDI -> andi rd', rd', imm[5:0]
                                    when "10" =>
                                        -- imm[5:0] = inst[12,6:2]
                                        imm_sign := instr16(12);
                                        imm := (others => imm_sign);
                                        imm(5) := instr16(12);
                                        imm(4 downto 0) := instr16(6 downto 2);
                                        
                                        -- ANDI rd', rd', imm
                                        dec(6 downto 0)   := "0010011";  -- ANDI
                                        dec(11 downto 7)  := rs1;
                                        dec(14 downto 12) := "111";      -- funct3
                                        dec(19 downto 15) := rs1;
                                        dec(31 downto 20) := imm(11 downto 0);
                                        
                                    -- Register-Register operations
                                    when "11" =>
                                        funct6 := instr16(15 downto 10);
                                        rs2_p := instr16(4 downto 2);
                                        rs2 := "01" & rs2_p;  -- x8-x15
                                        
                                        case instr16(6 downto 5) is
                                            -- C.SUB -> sub rd', rd', rs2'
                                            when "00" =>
                                                dec(6 downto 0)   := "0110011";  -- SUB
                                                dec(11 downto 7)  := rs1;
                                                dec(14 downto 12) := "000";
                                                dec(19 downto 15) := rs1;
                                                dec(24 downto 20) := rs2;
                                                dec(31 downto 25) := "0100000";
                                                
                                            -- C.XOR -> xor rd', rd', rs2'
                                            when "01" =>
                                                dec(6 downto 0)   := "0110011";  -- XOR
                                                dec(11 downto 7)  := rs1;
                                                dec(14 downto 12) := "100";
                                                dec(19 downto 15) := rs1;
                                                dec(24 downto 20) := rs2;
                                                dec(31 downto 25) := "0000000";
                                                
                                            -- C.OR -> or rd', rd', rs2'
                                            when "10" =>
                                                dec(6 downto 0)   := "0110011";  -- OR
                                                dec(11 downto 7)  := rs1;
                                                dec(14 downto 12) := "110";
                                                dec(19 downto 15) := rs1;
                                                dec(24 downto 20) := rs2;
                                                dec(31 downto 25) := "0000000";
                                                
                                            -- C.AND -> and rd', rd', rs2'
                                            when "11" =>
                                                dec(6 downto 0)   := "0110011";  -- AND
                                                dec(11 downto 7)  := rs1;
                                                dec(14 downto 12) := "111";
                                                dec(19 downto 15) := rs1;
                                                dec(24 downto 20) := rs2;
                                                dec(31 downto 25) := "0000000";
                                                
                                            when others =>
                                                dec := (others => '0');
                                        end case;
                                        
                                    when others =>
                                        dec := (others => '0');
                                end case;
                                
                            -- C.J -> jal x0, offset[11:1]
                            when "101" =>
                                -- offset[11|4|9:8|10|6|7|3:1|5] = inst[12|11|10:9|8|7|6|5:3|2]
                                imm_sign := instr16(12);
                                imm := (others => imm_sign);
                                imm(11) := instr16(12);
                                imm(10) := instr16(8);
                                imm(9 downto 8) := instr16(10 downto 9);
                                imm(7) := instr16(6);
                                imm(6) := instr16(7);
                                imm(5) := instr16(2);
                                imm(4) := instr16(11);
                                imm(3 downto 1) := instr16(5 downto 3);
                                -- imm(0) = 0 (implicit)
                                
                                -- JAL x0, offset
                                dec(6 downto 0)   := "1101111";  -- JAL
                                dec(11 downto 7)  := "00000";    -- x0
                                dec(19 downto 12) := imm(19 downto 12);
                                dec(20)           := imm(11);
                                dec(30 downto 21) := imm(10 downto 1);
                                dec(31)           := imm(20);
                                
                            -- C.BEQZ -> beq rs1', x0, offset[8:1]
                            when "110" =>
                                rs1_p := instr16(9 downto 7);
                                rs1 := "01" & rs1_p;  -- x8-x15
                                
                                -- offset[8|4:3|7:6|2:1|5] = inst[12|11:10|6:5|4:3|2]
                                imm_sign := instr16(12);
                                imm := (others => imm_sign);
                                imm(8) := instr16(12);
                                imm(7 downto 6) := instr16(6 downto 5);
                                imm(5) := instr16(2);
                                imm(4 downto 3) := instr16(11 downto 10);
                                imm(2 downto 1) := instr16(4 downto 3);
                                -- imm(0) = 0 (implicit)
                                
                                -- BEQ rs1', x0, offset
                                dec(6 downto 0)   := "1100011";  -- BEQ
                                dec(7)            := imm(11);
                                dec(11 downto 8)  := imm(4 downto 1);
                                dec(14 downto 12) := "000";
                                dec(19 downto 15) := rs1;
                                dec(24 downto 20) := "00000";    -- x0
                                dec(30 downto 25) := imm(10 downto 5);
                                dec(31)           := imm(12);
                                
                            -- C.BNEZ -> bne rs1', x0, offset[8:1]
                            when "111" =>
                                rs1_p := instr16(9 downto 7);
                                rs1 := "01" & rs1_p;  -- x8-x15
                                
                                -- offset[8|4:3|7:6|2:1|5] = inst[12|11:10|6:5|4:3|2]
                                imm_sign := instr16(12);
                                imm := (others => imm_sign);
                                imm(8) := instr16(12);
                                imm(7 downto 6) := instr16(6 downto 5);
                                imm(5) := instr16(2);
                                imm(4 downto 3) := instr16(11 downto 10);
                                imm(2 downto 1) := instr16(4 downto 3);
                                -- imm(0) = 0 (implicit)
                                
                                -- BNE rs1', x0, offset
                                dec(6 downto 0)   := "1100011";  -- BNE
                                dec(7)            := imm(11);
                                dec(11 downto 8)  := imm(4 downto 1);
                                dec(14 downto 12) := "001";
                                dec(19 downto 15) := rs1;
                                dec(24 downto 20) := "00000";    -- x0
                                dec(30 downto 25) := imm(10 downto 5);
                                dec(31)           := imm(12);
                                
                            when others =>
                                dec := (others => '0');
                        end case;
                        
                    -- ========== QUADRANT 2 (10) ==========
                    when "10" =>
                        case funct3 is
                            -- C.SLLI -> slli rd, rd, shamt[5:0]
                            when "000" =>
                                rd := instr16(11 downto 7);
                                
                                -- shamt[5:0] = inst[12,6:2]
                                imm := (others => '0');
                                imm(5) := instr16(12);
                                imm(4 downto 0) := instr16(6 downto 2);
                                
                                -- SLLI rd, rd, shamt
                                dec(6 downto 0)   := "0010011";  -- SLLI
                                dec(11 downto 7)  := rd;
                                dec(14 downto 12) := "001";
                                dec(19 downto 15) := rd;
                                dec(24 downto 20) := imm(4 downto 0);
                                dec(31 downto 25) := "0000000";
                                
                            -- C.LWSP -> lw rd, offset[7:2](sp)
                            when "010" =>
                                rd := instr16(11 downto 7);
                                
                                -- offset[7:2] = inst[3:2|12|6:4]
                                imm := (others => '0');
                                imm(7 downto 6) := instr16(3 downto 2);
                                imm(5) := instr16(12);
                                imm(4 downto 2) := instr16(6 downto 4);
                                -- imm[1:0] = 00 (implicit)
                                
                                if rd = "00000" then
                                    dec := (others => '0');  -- Reserved
                                else
                                    -- LW rd, offset(sp)
                                    dec(6 downto 0)   := "0000011";  -- LW
                                    dec(11 downto 7)  := rd;
                                    dec(14 downto 12) := "010";
                                    dec(19 downto 15) := "00010";    -- sp
                                    dec(31 downto 20) := imm(11 downto 0);
                                end if;
                                
                            -- C.JR / C.MV / C.EBREAK / C.JALR / C.ADD
                            when "100" =>
                                rd := instr16(11 downto 7);
                                rs2 := instr16(6 downto 2);
                                
                                if instr16(12) = '0' then
                                    if rs2 = "00000" then
                                        -- C.JR -> jalr x0, 0(rs1)
                                        if rd = "00000" then
                                            dec := (others => '0');  -- Reserved
                                        else
                                            dec(6 downto 0)   := "1100111";  -- JALR
                                            dec(11 downto 7)  := "00000";    -- x0
                                            dec(14 downto 12) := "000";
                                            dec(19 downto 15) := rd;         -- rs1
                                            dec(31 downto 20) := (others => '0');
                                        end if;
                                    else
                                        -- C.MV -> add rd, x0, rs2
                                        dec(6 downto 0)   := "0110011";  -- ADD
                                        dec(11 downto 7)  := rd;
                                        dec(14 downto 12) := "000";
                                        dec(19 downto 15) := "00000";    -- x0
                                        dec(24 downto 20) := rs2;
                                        dec(31 downto 25) := "0000000";
                                    end if;
                                else
                                    if rd = "00000" and rs2 = "00000" then
                                        -- C.EBREAK
                                        dec := x"00100073";
                                    elsif rs2 = "00000" then
                                        -- C.JALR -> jalr x1, 0(rs1)
                                        dec(6 downto 0)   := "1100111";  -- JALR
                                        dec(11 downto 7)  := "00001";    -- x1
                                        dec(14 downto 12) := "000";
                                        dec(19 downto 15) := rd;         -- rs1
                                        dec(31 downto 20) := (others => '0');
                                    else
                                        -- C.ADD -> add rd, rd, rs2
                                        dec(6 downto 0)   := "0110011";  -- ADD
                                        dec(11 downto 7)  := rd;
                                        dec(14 downto 12) := "000";
                                        dec(19 downto 15) := rd;
                                        dec(24 downto 20) := rs2;
                                        dec(31 downto 25) := "0000000";
                                    end if;
                                end if;
                                
                            -- C.SWSP -> sw rs2, offset[7:2](sp)
                            when "110" =>
                                rs2 := instr16(6 downto 2);
                                
                                -- offset[7:2] = inst[8:7|12:9]
                                imm := (others => '0');
                                imm(7 downto 6) := instr16(8 downto 7);
                                imm(5 downto 2) := instr16(12 downto 9);
                                -- imm[1:0] = 00 (implicit)
                                
                                -- SW rs2, offset(sp)
                                dec(6 downto 0)   := "0100011";  -- SW
                                dec(11 downto 7)  := imm(4 downto 0);
                                dec(14 downto 12) := "010";
                                dec(19 downto 15) := "00010";    -- sp
                                dec(24 downto 20) := rs2;
                                dec(31 downto 25) := imm(11 downto 5);
                                
                            when others =>
                                dec := (others => '0');
                        end case;
                        
                    when others =>
                        dec := (others => '0');
                end case;
                
            else
                -- Not compressed - pass through
                is_compressed_var := '0';
                dec := instr_in;
            end if;
            
            -- Assign outputs
            instr_out <= dec;
            is_compressed <= is_compressed_var;
        end if;
    end process decompress_proc;

end rtl;