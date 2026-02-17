-- library IEEE;
-- use IEEE.STD_LOGIC_1164.ALL;
-- use IEEE.NUMERIC_STD.ALL;
-- use work.constants.all;

-- entity c_dec is
--     port ( 
--         resetn        : in  std_logic;
--         instr_in      : in  std_logic_vector(31 downto 0);  -- Instruction word fetched from memory
--         instr_out     : out std_logic_vector(31 downto 0);  -- 32-bit decompressed or original instruction
--         is_compressed : out std_logic                       -- '1' if input was compressed
--     );
-- end c_dec;

-- architecture rtl of c_dec is

--     -- Helper function to check if 16-bit instruction is compressed
--     function is_16bit_compressed(instr16 : std_logic_vector(15 downto 0)) return boolean is
--     begin
--         return (instr16(1 downto 0) /= "11");
--     end function;
    
--     -- Helper function for decompression
--     function decompress_instr(instr16 : std_logic_vector(15 downto 0)) return std_logic_vector is
--         variable dec : std_logic_vector(31 downto 0) := (others => '0');
--         variable opcode_var : std_logic_vector(1 downto 0);
--         variable funct3_var : std_logic_vector(2 downto 0);
--         variable rd, rs1, rs2 : std_logic_vector(4 downto 0);
--         variable nzimm : std_logic_vector(11 downto 0);
--         variable uimm : std_logic_vector(11 downto 0);
--         variable shamt : std_logic_vector(4 downto 0);
--         variable rs1p, rs2p, rdp: std_logic_vector(2 downto 0);
--         variable xrs1p, xrs2p, xrdp: std_logic_vector(4 downto 0);
--         variable bimm_hi : std_logic_vector(6 downto 0);
--         variable bimm_lo : std_logic_vector(4 downto 0);
--         variable jimm : std_logic_vector(20 downto 0);
--         variable jimm_temp : std_logic_vector(11 downto 0);
--     begin
--         opcode_var := instr16(1 downto 0);
--         funct3_var := instr16(15 downto 13);
        
--         case opcode_var is
--             -- Quadrant 0: C.ADDI4SPN, C.LW, C.SW
--             when "00" =>
--                 case funct3_var is
--                     -- C.ADDI4SPN -> addi rd', x2, nzuimm
--                     when "000" =>
--                         rdp := instr16(4 downto 2);
--                         xrdp := "01" & rdp;
--                         nzimm := "00" & instr16(10 downto 7) & instr16(12 downto 11) & instr16(5) & instr16(6) & "00";
--                         if nzimm = x"000" then
--                             dec := x"00000013"; -- NOP
--                         else
--                             dec(6 downto 0)   := "0010011"; -- ADDI opcode
--                             dec(11 downto 7)  := xrdp;      -- rd
--                             dec(14 downto 12) := "000";     -- funct3
--                             dec(19 downto 15) := "00010";   -- rs1 = x2 (SP)
--                             dec(31 downto 20) := nzimm;     -- immediate
--                         end if;
--                     -- C.LW -> lw rd', offset(rs1')
--                     when "010" =>
--                         rs1p := instr16(9 downto 7);
--                         xrs1p := "01" & rs1p;
--                         rdp := instr16(4 downto 2);
--                         xrdp := "01" & rdp;
--                         uimm := "00000" & instr16(5) & instr16(12 downto 10) & instr16(6) & "00";
--                         dec(6 downto 0)   := "0000011"; -- LW opcode
--                         dec(11 downto 7)  := xrdp;      -- rd
--                         dec(14 downto 12) := "010";     -- funct3 (LW)
--                         dec(19 downto 15) := xrs1p;     -- rs1
--                         dec(31 downto 20) := uimm;      -- immediate
--                     -- C.SW -> sw rs2', offset(rs1')
--                     when "110" =>
--                         rs1p := instr16(9 downto 7);
--                         xrs1p := "01" & rs1p;
--                         rs2p := instr16(4 downto 2);
--                         xrs2p := "01" & rs2p;
--                         uimm := "00000" & instr16(5) & instr16(12 downto 10) & instr16(6) & "00";
--                         dec(6 downto 0)   := "0100011"; -- SW opcode
--                         dec(11 downto 7)  := uimm(4 downto 0);  -- imm[4:0]
--                         dec(14 downto 12) := "010";     -- funct3 (SW)
--                         dec(19 downto 15) := xrs1p;     -- rs1
--                         dec(24 downto 20) := xrs2p;     -- rs2
--                         dec(31 downto 25) := uimm(11 downto 5); -- imm[11:5]
--                     when others =>
--                         dec := x"00000013"; -- NOP
--                 end case;

--             -- Quadrant 1
--             when "01" =>
--                 case funct3_var is
--                     -- C.ADDI / C.NOP -> addi rd, rd, nzimm
--                     when "000" =>
--                         rd := instr16(11 downto 7);
--                         nzimm := (others => instr16(12)); -- Sign extend
--                         nzimm(5 downto 0) := instr16(12) & instr16(6 downto 2);
--                         if rd = "00000" and nzimm = x"000" then
--                             dec := x"00000013"; -- NOP
--                         else
--                             dec(6 downto 0)   := "0010011"; -- ADDI opcode
--                             dec(11 downto 7)  := rd;        -- rd
--                             dec(14 downto 12) := "000";     -- funct3
--                             dec(19 downto 15) := rd;        -- rs1 = rd
--                             dec(31 downto 20) := nzimm;     -- immediate
--                         end if;
--                     -- C.JAL -> jal x1, offset (RV32 only)
--                     when "001" =>
--                         jimm_temp(11) := instr16(12);  -- imm[11]
--                         jimm_temp(4)  := instr16(11);  -- imm[4]
--                         jimm_temp(9)  := instr16(10);  -- imm[9]
--                         jimm_temp(8)  := instr16(9);   -- imm[8]
--                         jimm_temp(10) := instr16(8);   -- imm[10]
--                         jimm_temp(6)  := instr16(7);   -- imm[6]
--                         jimm_temp(7)  := instr16(6);   -- imm[7]
--                         jimm_temp(3)  := instr16(5);   -- imm[3]
--                         jimm_temp(2)  := instr16(4);   -- imm[2]
--                         jimm_temp(1)  := instr16(3);   -- imm[1]
--                         jimm_temp(5)  := instr16(2);   -- imm[5]
--                         jimm_temp(0)  := '0';           -- imm[0] always 0
                        
--                         jimm := (others => jimm_temp(11));
--                         jimm(11 downto 0) := jimm_temp;
                        
--                         dec(6 downto 0)   := "1101111"; -- JAL opcode
--                         dec(11 downto 7)  := "00001";   -- rd = x1
--                         dec(31)           := jimm(20);   -- imm[20] = sign bit
--                         dec(30 downto 21) := jimm(10 downto 1);  -- imm[10:1]
--                         dec(20)           := jimm(11);   -- imm[11]
--                         dec(19 downto 12) := jimm(19 downto 12); -- imm[19:12]
--                     -- C.LI -> addi rd, x0, imm
--                     when "010" =>
--                         rd := instr16(11 downto 7);
--                         nzimm := (others => instr16(12)); -- Sign extend
--                         nzimm(5 downto 0) := instr16(12) & instr16(6 downto 2);
--                         dec(6 downto 0)   := "0010011"; -- ADDI opcode
--                         dec(11 downto 7)  := rd;        -- rd
--                         dec(14 downto 12) := "000";     -- funct3
--                         dec(19 downto 15) := "00000";   -- rs1 = x0
--                         dec(31 downto 20) := nzimm;     -- immediate
--                     -- C.ADDI16SP / C.LUI
--                     when "011" =>
--                         rd := instr16(11 downto 7);
--                         if rd = "00010" then
--                             -- C.ADDI16SP -> addi x2, x2, nzimm
--                             nzimm := (others => instr16(12)); -- Sign extend
--                             nzimm(8 downto 4) := instr16(4 downto 3) & instr16(5) & instr16(2) & instr16(6);
--                             nzimm(3 downto 0) := "0000";
--                             dec(6 downto 0)   := "0010011"; -- ADDI opcode
--                             dec(11 downto 7)  := "00010";   -- rd = x2
--                             dec(14 downto 12) := "000";     -- funct3
--                             dec(19 downto 15) := "00010";   -- rs1 = x2
--                             dec(31 downto 20) := nzimm;     -- immediate
--                         elsif rd /= "00000" then
--                             -- C.LUI -> lui rd, imm
--                             dec(6 downto 0)   := "0110111"; -- LUI opcode
--                             dec(11 downto 7)  := rd;        -- rd
--                             dec(17 downto 12) := instr16(12) & instr16(6 downto 2); -- nzimm[17:12]
--                             dec(31 downto 18) := (others => instr16(12)); -- Sign extend bit 12
--                         else
--                             dec := x"00000013"; -- NOP
--                         end if;
--                     -- C.SRLI, C.SRAI, C.ANDI, C.SUB, C.XOR, C.OR, C.AND
--                     when "100" =>
--                         if instr16(11 downto 10) = "00" then -- C.SRLI
--                             rs1p := instr16(9 downto 7);
--                             xrs1p := "01" & rs1p;
--                             nzimm := (others => instr16(12)); -- Sign extend
--                             nzimm(5 downto 0) := instr16(12) & instr16(6 downto 2);
--                             dec(6 downto 0)   := "0010011"; -- SRLI opcode
--                             dec(11 downto 7)  := xrs1p;     -- rd
--                             dec(14 downto 12) := "101";     -- funct3 for SRLI
--                             dec(19 downto 15) := xrs1p;     -- rs1
--                             dec(31 downto 20) := nzimm; 
--                         elsif instr16(11 downto 10) = "01" then -- C.SRAI
--                             rs1p := instr16(9 downto 7);
--                             xrs1p := "01" & rs1p;
--                             shamt := instr16(6 downto 2);  -- 5-bit shift amount
--                             dec(6 downto 0)   := "0010011"; -- SRAI opcode
--                             dec(11 downto 7)  := xrs1p;     -- rd
--                             dec(14 downto 12) := "101";     -- funct3 for SRAI
--                             dec(19 downto 15) := xrs1p;     -- rs1
--                             dec(24 downto 20) := shamt;     -- shamt (5 bits)
--                             dec(30)           := '1';       -- SRA (arithmetic shift)
--                             dec(31)           := '0';
--                         elsif instr16(11 downto 10) = "10" then
--                             rs1p := instr16(9 downto 7);
--                             xrs1p := "01" & rs1p;
--                             nzimm := (others => instr16(12)); -- Sign extend
--                             nzimm(5 downto 0) := instr16(12) & instr16(6 downto 2);
--                             dec(6 downto 0)   := "0010011"; -- ANDI opcode
--                             dec(11 downto 7)  := xrs1p;     -- rd
--                             dec(14 downto 12) := "111";     -- funct3
--                             dec(19 downto 15) := xrs1p;     -- rs1
--                             dec(31 downto 20) := nzimm;     -- immediate
--                         elsif instr16(11) = '1' then
--                             rs1p := instr16(9 downto 7);
--                             xrs1p := "01" & rs1p;
--                             rs2p := instr16(4 downto 2);
--                             xrs2p := "01" & rs2p;
--                             case instr16(6 downto 5) is
--                                 when "00" => -- C.SUB -> sub rd', rd', rs2'
--                                     dec(6 downto 0)   := "0110011"; -- SUB opcode
--                                     dec(11 downto 7)  := xrs1p;     -- rd
--                                     dec(14 downto 12) := "000";     -- funct3
--                                     dec(19 downto 15) := xrs1p;     -- rs1
--                                     dec(24 downto 20) := xrs2p;     -- rs2
--                                     dec(30)           := '1';       -- SUB (not ADD)
--                                 when "01" => -- C.XOR -> xor rd', rd', rs2'
--                                     dec(6 downto 0)   := "0110011"; -- XOR opcode
--                                     dec(11 downto 7)  := xrs1p;     -- rd
--                                     dec(14 downto 12) := "100";     -- funct3
--                                     dec(19 downto 15) := xrs1p;     -- rs1
--                                     dec(24 downto 20) := xrs2p;     -- rs2
--                                 when "10" => -- C.OR -> or rd', rd', rs2'
--                                     dec(6 downto 0)   := "0110011"; -- OR opcode
--                                     dec(11 downto 7)  := xrs1p;     -- rd
--                                     dec(14 downto 12) := "110";     -- funct3
--                                     dec(19 downto 15) := xrs1p;     -- rs1
--                                     dec(24 downto 20) := xrs2p;     -- rs2
--                                 when "11" => -- C.AND -> and rd', rd', rs2'
--                                     dec(6 downto 0)   := "0110011"; -- AND opcode
--                                     dec(11 downto 7)  := xrs1p;     -- rd
--                                     dec(14 downto 12) := "111";     -- funct3
--                                     dec(19 downto 15) := xrs1p;     -- rs1
--                                     dec(24 downto 20) := xrs2p;     -- rs2
--                                 when others =>
--                                     dec := x"00000013"; -- NOP
--                             end case;
--                         else
--                             dec := x"00000013"; -- NOP
--                         end if;
--                     -- C.J -> jal x0, offset 
--                     when "101" => 
--                         jimm_temp(11) := instr16(12);  -- imm[11]
--                         jimm_temp(4)  := instr16(11);  -- imm[4]
--                         jimm_temp(9)  := instr16(10);  -- imm[9]
--                         jimm_temp(8)  := instr16(9);   -- imm[8]
--                         jimm_temp(10) := instr16(8);   -- imm[10]
--                         jimm_temp(6)  := instr16(7);   -- imm[6]
--                         jimm_temp(7)  := instr16(6);   -- imm[7]
--                         jimm_temp(3)  := instr16(5);   -- imm[3]
--                         jimm_temp(2)  := instr16(4);   -- imm[2]
--                         jimm_temp(1)  := instr16(3);   -- imm[1]
--                         jimm_temp(5)  := instr16(2);   -- imm[5]
--                         jimm_temp(0)  := '0';           -- imm[0] always 0
                        
--                         jimm := (others => jimm_temp(11));
--                         jimm(11 downto 0) := jimm_temp;
                        
--                         dec(6 downto 0)   := "1101111"; -- JAL opcode
--                         dec(11 downto 7)  := "00000";   -- rd = x0 for C.J
--                         dec(31)           := jimm(20);   -- imm[20] = sign bit
--                         dec(30 downto 21) := jimm(10 downto 1);  -- imm[10:1]
--                         dec(20)           := jimm(11);   -- imm[11]
--                         dec(19 downto 12) := jimm(19 downto 12); -- imm[19:12]
--                     -- C.BEQZ -> beq rs1', x0, offset
--                     when "110" =>
--                         rs1p := instr16(9 downto 7);
--                         xrs1p := "01" & rs1p;
--                         bimm_hi := instr16(12) & instr16(6 downto 5) & instr16(2) & "000";
--                         bimm_lo := instr16(11 downto 10) & instr16(4 downto 3) & '0';
--                         dec(6 downto 0)   := "1100011"; -- BEQ opcode
--                         dec(11 downto 7)  := bimm_lo;   -- imm[4:1|11]
--                         dec(14 downto 12) := "000";     -- funct3 (BEQ)
--                         dec(19 downto 15) := xrs1p;     -- rs1
--                         dec(24 downto 20) := "00000";   -- rs2 = x0
--                         dec(31 downto 25) := bimm_hi;   -- imm[12|10:5]
--                     -- C.BNEZ -> bne rs1', x0, offset
--                     when "111" =>
--                         rs1p := instr16(9 downto 7);
--                         xrs1p := "01" & rs1p;
--                         bimm_hi := instr16(12) & instr16(6 downto 5) & instr16(2) & "000";
--                         bimm_lo := instr16(11 downto 10) & instr16(4 downto 3) & '0';
--                         dec(6 downto 0)   := "1100011"; -- BNE opcode
--                         dec(11 downto 7)  := bimm_lo;   -- imm[4:1|11]
--                         dec(14 downto 12) := "001";     -- funct3 (BNE)
--                         dec(19 downto 15) := xrs1p;     -- rs1
--                         dec(24 downto 20) := "00000";   -- rs2 = x0
--                         dec(31 downto 25) := bimm_hi;   -- imm[12|10:5]
--                     when others =>
--                         dec := x"00000013"; -- NOP
--                 end case;

--             -- Quadrant 2
--             when "10" =>
--                 case funct3_var is
--                     -- C.SLLI -> slli rd, rd, shamt
--                     when "000" =>
--                         rd := instr16(11 downto 7);
--                         shamt := instr16(6 downto 2);
--                         if rd /= "00000" then
--                             dec(6 downto 0)   := "0010011"; -- SLLI opcode
--                             dec(11 downto 7)  := rd;        -- rd
--                             dec(14 downto 12) := "001";     -- funct3
--                             dec(19 downto 15) := rd;        -- rs1 = rd
--                             dec(25 downto 20) := instr16(12) & shamt;     -- shamt
--                         else
--                             dec := x"00000013"; -- NOP
--                         end if;
--                     -- C.LWSP -> lw rd, offset(x2)
--                     when "010" =>
--                         rd := instr16(11 downto 7);
--                         if rd /= "00000" then
--                             uimm := "0000" & instr16(3 downto 2) & instr16(12) & instr16(6 downto 4) & "00";
--                             dec(6 downto 0)   := "0000011"; -- LW opcode
--                             dec(11 downto 7)  := rd;        -- rd
--                             dec(14 downto 12) := "010";     -- funct3 (LW)
--                             dec(19 downto 15) := "00010";   -- rs1 = x2 (SP)
--                             dec(31 downto 20) := uimm;      -- immediate
--                         else
--                             dec := x"00000013"; -- NOP
--                         end if;
--                     -- C.MV, C.JR, C.ADD, C.JALR, C.EBREAK
--                     when "100" =>
--                         rd := instr16(11 downto 7);
--                         rs2 := instr16(6 downto 2);
--                         if instr16(12) = '0' then
--                             if rs2 /= "00000" then
--                                 -- C.MV -> add rd, x0, rs2
--                                 dec(6 downto 0)   := "0110011"; -- ADD opcode
--                                 dec(11 downto 7)  := rd;        -- rd
--                                 dec(14 downto 12) := "000";     -- funct3
--                                 dec(19 downto 15) := "00000";   -- rs1 = x0
--                                 dec(24 downto 20) := rs2;       -- rs2
--                             elsif rd /= "00000" then
--                                 -- C.JR -> jalr x0, 0(rd)
--                                 dec(6 downto 0)   := "1100111"; -- JALR opcode
--                                 dec(11 downto 7)  := "00000";   -- rd = x0
--                                 dec(14 downto 12) := "000";     -- funct3
--                                 dec(19 downto 15) := rd;        -- rs1
--                                 dec(31 downto 20) := x"000";    -- immediate = 0
--                             else
--                                 dec := x"00000013"; -- NOP
--                             end if;
--                         else
--                             if rs2 /= "00000" then
--                                 -- C.ADD -> add rd, rd, rs2
--                                 dec(6 downto 0)   := "0110011"; -- ADD opcode
--                                 dec(11 downto 7)  := rd;        -- rd
--                                 dec(14 downto 12) := "000";     -- funct3
--                                 dec(19 downto 15) := rd;        -- rs1 = rd
--                                 dec(24 downto 20) := rs2;       -- rs2
--                             elsif rd /= "00000" then
--                                 -- C.JALR -> jalr x1, 0(rd)
--                                 dec(6 downto 0)   := "1100111"; -- JALR opcode
--                                 dec(11 downto 7)  := "00001";   -- rd = x1
--                                 dec(14 downto 12) := "000";     -- funct3
--                                 dec(19 downto 15) := rd;        -- rs1
--                                 dec(31 downto 20) := x"000";    -- immediate = 0
--                             else
--                                 -- C.EBREAK
--                                 dec := x"00100073"; -- EBREAK
--                             end if;
--                         end if;
--                     -- C.SWSP -> sw rs2, offset(x2)
--                     when "110" =>
--                         rs2 := instr16(6 downto 2);
--                         uimm := "0000" & instr16(8 downto 7) & instr16(12 downto 9) & "00";
--                         dec(6 downto 0)   := "0100011"; -- SW opcode
--                         dec(11 downto 7)  := uimm(4 downto 0);  -- imm[4:0]
--                         dec(14 downto 12) := "010";     -- funct3 (SW)
--                         dec(19 downto 15) := "00010";   -- rs1 = x2 (SP)
--                         dec(24 downto 20) := rs2;       -- rs2
--                         dec(31 downto 25) := uimm(11 downto 5); -- imm[11:5]
--                     when others =>
--                         dec := x"00000013"; -- NOP
--                 end case;
            
--             -- Invalid compressed instruction (should not happen)
--             when others =>
--                 dec := x"00000013"; -- NOP
--         end case;
        
--         return dec;
--     end function;

--     -- Internal signals
--     signal instr16_lower : std_logic_vector(15 downto 0);
--     signal is_compressed_int : std_logic;
    
-- begin

--     -- Extract lower 16 bits
--     instr16_lower <= instr_in(15 downto 0);
    
--     -- Check if instruction is compressed
--     is_compressed_int <= '1' when is_16bit_compressed(instr16_lower) else '0';
    
--     -- Main output assignment
--     instr_out <= nop when resetn = '0' else
--                  instr_in when is_compressed_int = '0' else
--                  decompress_instr(instr16_lower);
    
--     -- Is compressed output
--     is_compressed <= '0' when resetn = '0' else
--                      is_compressed_int;

-- end rtl;





library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.constants.all;


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
        variable instr16_lower : std_logic_vector(15 downto 0);
        variable is_compressed_var : std_logic := '0';
        variable dec : std_logic_vector(31 downto 0) := (others => '0');
        -- (other local variables for decompression, as before)
        variable opcode_var : std_logic_vector(1 downto 0);
        variable funct3_var : std_logic_vector(2 downto 0);
        variable rd, rs1, rs2 : std_logic_vector(4 downto 0);
        variable nzimm : std_logic_vector(11 downto 0);
        variable uimm : std_logic_vector(11 downto 0);
        variable shamt : std_logic_vector(4 downto 0);
        variable rs1p, rs2p, rdp: std_logic_vector(2 downto 0);
        variable xrs1p, xrs2p, xrdp: std_logic_vector(4 downto 0);
        variable bimm_hi : std_logic_vector(6 downto 0);
        variable bimm_lo : std_logic_vector(4 downto 0);
        variable jimm : std_logic_vector(20 downto 0);
        variable jimm_temp : std_logic_vector(11 downto 0);
    begin
        -- Initialize all outputs
        dec := (others => '0');
        is_compressed_var := '1';
        
        if resetn = '0' then
            instr_out <= (others => '0');
            is_compressed <= '0';
        else
            instr16_lower := instr_in(15 downto 0);
            instr16_lower := instr16_lower;

            if is_16bit_compressed(instr16_lower) then
                is_compressed_var := '1';
                -- Compressed instruction - decompress the 16-bit instruction
                -- Extract fields directly from instr16_lower
                opcode_var := instr16_lower(1 downto 0);
                funct3_var := instr16_lower(15 downto 13);
                
                case opcode_var is
                -- Quadrant 0: C.ADDI4SPN, C.LW, C.SW
                when "00" =>
                    case funct3_var is
                    -- C.ADDI4SPN -> addi rd', x2, nzuimm
                    when "000" =>
                        rdp := instr16_lower(4 downto 2);
                        xrdp := "01" & rdp;
                        -- nzuimm[9:2] = {instr[10:7], instr[12:11], instr[5], instr[6]}
                        nzimm := "00" & instr16_lower(10 downto 7) & instr16_lower(12 downto 11) & instr16_lower(5) & instr16_lower(6) & "00";
                        if nzimm = x"000" then
                            dec := x"00000013"; -- NOP (addi x0, x0, 0)
                        else
                            dec(6 downto 0)   := "0010011"; -- ADDI opcode
                            dec(11 downto 7)  := xrdp;      -- rd
                            dec(14 downto 12) := "000";     -- funct3
                            dec(19 downto 15) := "00010";   -- rs1 = x2 (SP)
                            dec(31 downto 20) := nzimm;     -- immediate
                        end if;
                    -- C.LW -> lw rd', offset(rs1')
                    when "010" =>
                        rs1p := instr16_lower(9 downto 7);
                        xrs1p := "01" & rs1p;
                        rdp := instr16_lower(4 downto 2);
                        xrdp := "01" & rdp;
                        -- uimm[6:2] = {instr[5], instr[12:10], instr[6]}
                        uimm := "00000" & instr16_lower(5) & instr16_lower(12 downto 10) & instr16_lower(6) & "00";
                        dec(6 downto 0)   := "0000011"; -- LW opcode
                        dec(11 downto 7)  := xrdp;      -- rd
                        dec(14 downto 12) := "010";     -- funct3 (LW)
                        dec(19 downto 15) := xrs1p;     -- rs1
                        dec(31 downto 20) := uimm;      -- immediate
                    -- C.SW -> sw rs2', offset(rs1')
                    when "110" =>
                        rs1p := instr16_lower(9 downto 7);
                        xrs1p := "01" & rs1p;
                        rs2p := instr16_lower(4 downto 2);
                        xrs2p := "01" & rs2p;
                        -- uimm[6:2] = {instr[5], instr[12:10], instr[6]}
                        uimm := "00000" & instr16_lower(5) & instr16_lower(12 downto 10) & instr16_lower(6) & "00";
                        dec(6 downto 0)   := "0100011"; -- SW opcode
                        dec(11 downto 7)  := uimm(4 downto 0);  -- imm[4:0]
                        dec(14 downto 12) := "010";     -- funct3 (SW)
                        dec(19 downto 15) := xrs1p;     -- rs1
                        dec(24 downto 20) := xrs2p;     -- rs2
                        dec(31 downto 25) := uimm(11 downto 5); -- imm[11:5]
                    when others =>
                        dec := x"00000013"; -- NOP
                    end case;

                -- Quadrant 1
                when "01" =>
                    case funct3_var is
                    -- C.ADDI / C.NOP -> addi rd, rd, nzimm
                    when "000" =>
                        rd := instr16_lower(11 downto 7);
                        nzimm := (others => instr16_lower(12)); -- Sign extend
                        nzimm(5 downto 0) := instr16_lower(12) & instr16_lower(6 downto 2);
                        if rd = "00000" and nzimm = x"000" then
                            dec := x"00000013"; -- NOP
                        else
                            dec(6 downto 0)   := "0010011"; -- ADDI opcode
                            dec(11 downto 7)  := rd;        -- rd
                            dec(14 downto 12) := "000";     -- funct3
                            dec(19 downto 15) := rd;        -- rs1 = rd
                            dec(31 downto 20) := nzimm;     -- immediate
                        end if;
                    -- C.JAL -> jal x1, offset (RV32 only)
                    when "001" =>
                        -- C.JAL immediate field construction according to spec:
                        -- imm[11|4|9:8|10|6|7|3:1|5] from instr[12|11|10:9|8|7|6|5:3|2]
                        jimm_temp(11) := instr16_lower(12);  -- imm[11]
                        jimm_temp(4)  := instr16_lower(11);  -- imm[4]
                        jimm_temp(9)  := instr16_lower(10);  -- imm[9]
                        jimm_temp(8)  := instr16_lower(9);   -- imm[8]
                        jimm_temp(10) := instr16_lower(8);   -- imm[10]
                        jimm_temp(6)  := instr16_lower(7);   -- imm[6]
                        jimm_temp(7)  := instr16_lower(6);   -- imm[7]
                        jimm_temp(3)  := instr16_lower(5);   -- imm[3]
                        jimm_temp(2)  := instr16_lower(4);   -- imm[2]
                        jimm_temp(1)  := instr16_lower(3);   -- imm[1]
                        jimm_temp(5)  := instr16_lower(2);   -- imm[5]
                        jimm_temp(0)  := '0';                  -- imm[0] always 0
                        
                        -- Sign extend to 21 bits
                        jimm := (others => jimm_temp(11));
                        jimm(11 downto 0) := jimm_temp;
                        
                        dec(6 downto 0)   := "1101111"; -- JAL opcode
                        dec(11 downto 7)  := "00001";   -- rd = x1
                        dec(31)           := jimm(20);   -- imm[20] = sign bit
                        dec(30 downto 21) := jimm(10 downto 1);  -- imm[10:1]
                        dec(20)           := jimm(11);   -- imm[11]
                        dec(19 downto 12) := jimm(19 downto 12); -- imm[19:12]
                        
                    -- C.LI -> addi rd, x0, imm
                    when "010" =>
                        rd := instr16_lower(11 downto 7);
                        nzimm := (others => instr16_lower(12)); -- Sign extend
                        nzimm(5 downto 0) := instr16_lower(12) & instr16_lower(6 downto 2);
                        dec(6 downto 0)   := "0010011"; -- ADDI opcode
                        dec(11 downto 7)  := rd;        -- rd
                        dec(14 downto 12) := "000";     -- funct3
                        dec(19 downto 15) := "00000";   -- rs1 = x0
                        dec(31 downto 20) := nzimm;     -- immediate
                    -- C.ADDI16SP / C.LUI
                    when "011" =>
                        rd := instr16_lower(11 downto 7);
                        if rd = "00010" then
                            -- C.ADDI16SP -> addi x2, x2, nzimm
                            nzimm := (others => instr16_lower(12)); -- Sign extend
                            nzimm(8 downto 4) := instr16_lower(4 downto 3) & instr16_lower(5) & instr16_lower(2) & instr16_lower(6);
                            nzimm(3 downto 0) := "0000";
                            dec(6 downto 0)   := "0010011"; -- ADDI opcode
                            dec(11 downto 7)  := "00010";   -- rd = x2
                            dec(14 downto 12) := "000";     -- funct3
                            dec(19 downto 15) := "00010";   -- rs1 = x2
                            dec(31 downto 20) := nzimm;     -- immediate
                        elsif rd /= "00000" then
                            -- C.LUI -> lui rd, imm
                            -- C.LUI provides nzimm[17:12] from instr[12,6:2]
                            -- For LUI instruction, this becomes immediate[31:12] with proper sign extension
                            dec(6 downto 0)   := "0110111"; -- LUI opcode
                            dec(11 downto 7)  := rd;        -- rd
                            -- Build the 20-bit immediate for bits [31:12]
                            -- nzimm[17:12] goes to immediate[17:12], then sign extend to fill [31:18]
                            dec(17 downto 12) := instr16_lower(12) & instr16_lower(6 downto 2); -- nzimm[17:12]
                            dec(31 downto 18) := (others => instr16_lower(12)); -- Sign extend bit 12
                        else
                            dec := x"00000013"; -- NOP
                        end if;

                    -- C.SRLI, C.SRAI, C.ANDI, C.SUB, C.XOR, C.OR, C.AND
                    when "100" =>
                        if instr16_lower(11 downto 10) = "00" then -- C.SRLI
                            rs1p := instr16_lower(9 downto 7);
                            xrs1p := "01" & rs1p;
                            -- shamt := instr16_lower(6 downto 2);  -- 5-bit shift amount
                            nzimm := (others => instr16_lower(12)); -- Sign extend
                            nzimm(5 downto 0) := instr16_lower(12) & instr16_lower(6 downto 2);
                            dec(6 downto 0)   := "0010011"; -- SRLI opcode
                            dec(11 downto 7)  := xrs1p;     -- rd
                            dec(14 downto 12) := "101";     -- funct3 for SRLI
                            dec(19 downto 15) := xrs1p;     -- rs1
                            -- dec(24 downto 20) := nzimm;     -- shamt (5 bits)
                            -- dec(30)           := '0';       -- SRL (not SRA)
                            -- dec(31)           := '0';
                            dec(31 downto 20) := nzimm; 
                            
                        elsif instr16_lower(11 downto 10) = "01" then -- C.SRAI
                            rs1p := instr16_lower(9 downto 7);
                            xrs1p := "01" & rs1p;
                            shamt := instr16_lower(6 downto 2);  -- 5-bit shift amount
                            dec(6 downto 0)   := "0010011"; -- SRAI opcode
                            dec(11 downto 7)  := xrs1p;     -- rd
                            dec(14 downto 12) := "101";     -- funct3 for SRAI
                            dec(19 downto 15) := xrs1p;     -- rs1
                            dec(24 downto 20) := shamt;     -- shamt (5 bits)
                            dec(30)           := '1';       -- SRA (arithmetic shift)
                            dec(31)           := '0';
                        elsif instr16_lower(11 downto 10) = "10" then
                            rs1p := instr16_lower(9 downto 7);
                            xrs1p := "01" & rs1p;
                            nzimm := (others => instr16_lower(12)); -- Sign extend
                            nzimm(5 downto 0) := instr16_lower(12) & instr16_lower(6 downto 2);
                            dec(6 downto 0)   := "0010011"; -- ANDI opcode
                            dec(11 downto 7)  := xrs1p;     -- rd
                            dec(14 downto 12) := "111";     -- funct3
                            dec(19 downto 15) := xrs1p;     -- rs1
                            dec(31 downto 20) := nzimm;     -- immediate
                        elsif instr16_lower(11) = '1' then
                            rs1p := instr16_lower(9 downto 7);
                            xrs1p := "01" & rs1p;
                            rs2p := instr16_lower(4 downto 2);
                            xrs2p := "01" & rs2p;
                            case instr16_lower(6 downto 5) is
                                when "00" => -- C.SUB -> sub rd', rd', rs2'
                                    dec(6 downto 0)   := "0110011"; -- SUB opcode
                                    dec(11 downto 7)  := xrs1p;     -- rd
                                    dec(14 downto 12) := "000";     -- funct3
                                    dec(19 downto 15) := xrs1p;     -- rs1
                                    dec(24 downto 20) := xrs2p;     -- rs2
                                    dec(30)           := '1';       -- SUB (not ADD)
                                when "01" => -- C.XOR -> xor rd', rd', rs2'
                                    dec(6 downto 0)   := "0110011"; -- XOR opcode
                                    dec(11 downto 7)  := xrs1p;     -- rd
                                    dec(14 downto 12) := "100";     -- funct3
                                    dec(19 downto 15) := xrs1p;     -- rs1
                                    dec(24 downto 20) := xrs2p;     -- rs2
                                when "10" => -- C.OR -> or rd', rd', rs2'
                                    dec(6 downto 0)   := "0110011"; -- OR opcode
                                    dec(11 downto 7)  := xrs1p;     -- rd
                                    dec(14 downto 12) := "110";     -- funct3
                                    dec(19 downto 15) := xrs1p;     -- rs1
                                    dec(24 downto 20) := xrs2p;     -- rs2
                                when "11" => -- C.AND -> and rd', rd', rs2'
                                    dec(6 downto 0)   := "0110011"; -- AND opcode
                                    dec(11 downto 7)  := xrs1p;     -- rd
                                    dec(14 downto 12) := "111";     -- funct3
                                    dec(19 downto 15) := xrs1p;     -- rs1
                                    dec(24 downto 20) := xrs2p;     -- rs2
                                when others =>
                                    dec := x"00000013"; -- NOP
                            end case;
                        else
                            dec := x"00000013"; -- NOP
                        end if;
                    -- C.J -> jal x0, offset 
                    when "101" => 
                        -- C.J immediate field construction (same as C.JAL but rd=x0):
                        -- imm[11|4|9:8|10|6|7|3:1|5] from instr[12|11|10:9|8|7|6|5:3|2]
                        jimm_temp(11) := instr16_lower(12);  -- imm[11]
                        jimm_temp(4)  := instr16_lower(11);  -- imm[4]
                        jimm_temp(9)  := instr16_lower(10);  -- imm[9]
                        jimm_temp(8)  := instr16_lower(9);   -- imm[8]
                        jimm_temp(10) := instr16_lower(8);   -- imm[10]
                        jimm_temp(6)  := instr16_lower(7);   -- imm[6]
                        jimm_temp(7)  := instr16_lower(6);   -- imm[7]
                        jimm_temp(3)  := instr16_lower(5);   -- imm[3]
                        jimm_temp(2)  := instr16_lower(4);   -- imm[2]
                        jimm_temp(1)  := instr16_lower(3);   -- imm[1]
                        jimm_temp(5)  := instr16_lower(2);   -- imm[5]
                        jimm_temp(0)  := '0';                  -- imm[0] always 0
                        
                        -- Sign extend to 21 bits
                        jimm := (others => jimm_temp(11));
                        jimm(11 downto 0) := jimm_temp;
                        
                        dec(6 downto 0)   := "1101111"; -- JAL opcode
                        dec(11 downto 7)  := "00000";   -- rd = x0 for C.J
                        dec(31)           := jimm(20);   -- imm[20] = sign bit
                        dec(30 downto 21) := jimm(10 downto 1);  -- imm[10:1]
                        dec(20)           := jimm(11);   -- imm[11]
                        dec(19 downto 12) := jimm(19 downto 12); -- imm[19:12]
                        
                    -- C.BEQZ -> beq rs1', x0, offset
                    when "110" =>
                        rs1p := instr16_lower(9 downto 7);
                        xrs1p := "01" & rs1p;
                        bimm_hi := instr16_lower(12) & instr16_lower(6 downto 5) & instr16_lower(2) & "000";
                        bimm_lo := instr16_lower(11 downto 10) & instr16_lower(4 downto 3) & '0';
                        dec(6 downto 0)   := "1100011"; -- BEQ opcode
                        dec(11 downto 7)  := bimm_lo;   -- imm[4:1|11]
                        dec(14 downto 12) := "000";     -- funct3 (BEQ)
                        dec(19 downto 15) := xrs1p;     -- rs1
                        dec(24 downto 20) := "00000";   -- rs2 = x0
                        dec(31 downto 25) := bimm_hi;   -- imm[12|10:5]
                    -- C.BNEZ -> bne rs1', x0, offset
                    when "111" =>
                        rs1p := instr16_lower(9 downto 7);
                        xrs1p := "01" & rs1p;
                        bimm_hi := instr16_lower(12) & instr16_lower(6 downto 5) & instr16_lower(2) & "000";
                        bimm_lo := instr16_lower(11 downto 10) & instr16_lower(4 downto 3) & '0';
                        dec(6 downto 0)   := "1100011"; -- BNE opcode
                        dec(11 downto 7)  := bimm_lo;   -- imm[4:1|11]
                        dec(14 downto 12) := "001";     -- funct3 (BNE)
                        dec(19 downto 15) := xrs1p;     -- rs1
                        dec(24 downto 20) := "00000";   -- rs2 = x0
                        dec(31 downto 25) := bimm_hi;   -- imm[12|10:5]
                    when others =>
                        dec := x"00000013"; -- NOP
                    end case;

                -- Quadrant 2
                when "10" =>
                    case funct3_var is
                    -- C.SLLI -> slli rd, rd, shamt
                    when "000" =>
                        rd := instr16_lower(11 downto 7);
                        shamt := instr16_lower(6 downto 2);
                        if rd /= "00000" then
                            dec(6 downto 0)   := "0010011"; -- SLLI opcode
                            dec(11 downto 7)  := rd;        -- rd
                            dec(14 downto 12) := "001";     -- funct3
                            dec(19 downto 15) := rd;        -- rs1 = rd
                            dec(25 downto 20) := instr16_lower(12) & shamt;     -- shamt
                        else
                            dec := x"00000013"; -- NOP
                        end if;
                    -- C.LWSP -> lw rd, offset(x2)
                    when "010" =>
                        rd := instr16_lower(11 downto 7);
                        if rd /= "00000" then
                            uimm := "0000" & instr16_lower(3 downto 2) & instr16_lower(12) & instr16_lower(6 downto 4) & "00";
                            dec(6 downto 0)   := "0000011"; -- LW opcode
                            dec(11 downto 7)  := rd;        -- rd
                            dec(14 downto 12) := "010";     -- funct3 (LW)
                            dec(19 downto 15) := "00010";   -- rs1 = x2 (SP)
                            dec(31 downto 20) := uimm;      -- immediate
                        else
                            dec := x"00000013"; -- NOP
                        end if;
                    -- C.MV, C.JR, C.ADD, C.JALR, C.EBREAK
                    when "100" =>
                        rd := instr16_lower(11 downto 7);
                        rs2 := instr16_lower(6 downto 2);
                        if instr16_lower(12) = '0' then
                            if rs2 /= "00000" then
                                -- C.MV -> add rd, x0, rs2
                                dec(6 downto 0)   := "0110011"; -- ADD opcode
                                dec(11 downto 7)  := rd;        -- rd
                                dec(14 downto 12) := "000";     -- funct3
                                dec(19 downto 15) := "00000";   -- rs1 = x0
                                dec(24 downto 20) := rs2;       -- rs2
                            elsif rd /= "00000" then
                                -- C.JR -> jalr x0, 0(rd)
                                dec(6 downto 0)   := "1100111"; -- JALR opcode
                                dec(11 downto 7)  := "00000";   -- rd = x0
                                dec(14 downto 12) := "000";     -- funct3
                                dec(19 downto 15) := rd;        -- rs1
                                dec(31 downto 20) := x"000";    -- immediate = 0
                            else
                                dec := x"00000013"; -- NOP
                            end if;
                        else
                            if rs2 /= "00000" then
                                -- C.ADD -> add rd, rd, rs2
                                dec(6 downto 0)   := "0110011"; -- ADD opcode
                                dec(11 downto 7)  := rd;        -- rd
                                dec(14 downto 12) := "000";     -- funct3
                                dec(19 downto 15) := rd;        -- rs1 = rd
                                dec(24 downto 20) := rs2;       -- rs2
                            elsif rd /= "00000" then
                                -- C.JALR -> jalr x1, 0(rd)
                                dec(6 downto 0)   := "1100111"; -- JALR opcode
                                dec(11 downto 7)  := "00001";   -- rd = x1
                                dec(14 downto 12) := "000";     -- funct3
                                dec(19 downto 15) := rd;        -- rs1
                                dec(31 downto 20) := x"000";    -- immediate = 0
                            else
                                -- C.EBREAK
                                dec := x"00100073"; -- EBREAK
                            end if;
                        end if;
                    -- C.SWSP -> sw rs2, offset(x2)
                    when "110" =>
                        rs2 := instr16_lower(6 downto 2);
                        uimm := "0000" & instr16_lower(8 downto 7) & instr16_lower(12 downto 9) & "00";
                        dec(6 downto 0)   := "0100011"; -- SW opcode
                        dec(11 downto 7)  := uimm(4 downto 0);  -- imm[4:0]
                        dec(14 downto 12) := "010";     -- funct3 (SW)
                        dec(19 downto 15) := "00010";   -- rs1 = x2 (SP)
                        dec(24 downto 20) := rs2;       -- rs2
                        dec(31 downto 25) := uimm(11 downto 5); -- imm[11:5]
                    when others =>
                        dec := x"00000013"; -- NOP
                    end case;
                
                -- Invalid compressed instruction (should not happen)
                when others =>
                    dec := x"00000013"; -- NOP
                end case;
            else
                is_compressed_var := '0';
                -- hwrd_req_var := '0';
                dec := instr_in; -- Uncompressed instruction - pass through the full 32-bit instruction
            end if;
            
            -- Assign outputs
            instr_out <= dec;
            -- hwrd_req <= -- hwrd_req_var;
            is_compressed <= is_compressed_var;
        end if;
    end process decompress_proc;

end rtl;


