library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

-- Register | ABI Name | Description
-- ---------+----------+--------------------------------------------------------
-- x0       | zero     | Hardwired to 0 (read-only)
-- x1       | ra       | Return address (for JAL/JALR)
-- x2       | sp       | Stack pointer
-- x3       | gp       | Global pointer (for static data)
-- x4       | tp       | Thread pointer (for TLS)
-- x5–x7    | t0–t2    | Temporary registers
-- x8       | s0/fp    | Saved register / Frame pointer
-- x9       | s1       | Saved register
-- x10–x11  | a0–a1    | Function arguments / return values
-- x12–x17  | a2–a7    | Function arguments
-- x18–x27  | s2–s11   | Saved registers
-- x28–x31  | t3–t6    | Temporary registers

entity regfile is
    port (
        clk:  in  STD_LOGIC;
        resetn:  in  STD_LOGIC;
        we3:  in  STD_LOGIC;                        -- Write enable (for port 3)
        a1:   in  STD_LOGIC_VECTOR(4 downto 0);     -- Read address 1
        a2:   in  STD_LOGIC_VECTOR(4 downto 0);     -- Read address 2
        a3:   in  STD_LOGIC_VECTOR(4 downto 0);     -- Write address
        wd3:  in  STD_LOGIC_VECTOR(31 downto 0);    -- Write data
        rd1:  out STD_LOGIC_VECTOR(31 downto 0);    -- Read data 1
        rd2:  out STD_LOGIC_VECTOR(31 downto 0);     -- Read data 2
        a0:   out STD_LOGIC_VECTOR(31 downto 0)      --for outputting results of tests (tb use only)
    );
end entity regfile;

architecture behav of regfile is
    type reg_array is array (0 to 31) of std_logic_vector(31 downto 0);
    signal registers: reg_array := (others => (others => '0'));

begin
    process(clk)
    begin
        if resetn = '0' then
            registers <= (others => (others => '0')); -- Reset all registers
        elsif rising_edge(clk) then
            -- Only write if we3 is enabled AND a3 is NOT zero (x0)
            if we3 = '1' and a3 /= "00000" then
                    registers(to_integer(unsigned(a3))) <= wd3;
            end if;
        end if;
    end process;

    -- Asynchronous read
    rd1 <= registers(to_integer(unsigned(a1)));
    rd2 <= registers(to_integer(unsigned(a2)));

    --output a0
    a0 <=registers(10);

end architecture behav;