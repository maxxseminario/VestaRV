library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

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

        -- -- IRQ
        -- irq_save: in std_logic;     --should only be high for one clock cycle 
        -- irq_restore: in std_logic; --should only be high for one clock cycle 
        -- pc : in std_logic_vector(31 downto 0); --current program counter (for saving to ra on irq_save)
        -- q0 : out std_logic_vector(31 downto 0); --irq ra

        sp_in : in std_logic_vector(31 downto 0); -- New stack pointer value on irq_save
        sp_out : out std_logic_vector(31 downto 0); -- Current stack pointer value on irq_restore
        sp_write : in std_logic; -- Signal to write new stack pointer value

        -- Testing
        a0: out std_logic_vector(31 downto 0)

    );
end entity regfile;

-- TODO: Remove Register zero (x0) from register file (hardwired to 0)

architecture behav of regfile is
    type reg_array is array (0 to 31) of std_logic_vector(31 downto 0);
    signal registers: reg_array;
    signal reg_context: reg_array;
    signal clk_irq : std_logic;

begin

    -- Register write process
    reg_wr: process(clk, resetn)
    begin
        if resetn = '0' then
            registers <= (others => (others => '0')); -- Reset all registers
        elsif rising_edge(clk) then


            -- Only write if we3 is enabled AND a3 is NOT zero (x0)
            if we3 = '1' and a3 /= "00000" then
                registers(0) <= (others => '0');
                registers(slv2uint(a3)) <= wd3;
            end if;

            if sp_write = '1' then
                registers(2) <= sp_in; -- Update stack pointer (x2)
            end if;


        end if;
    end process;

    -------- IRQ handling -------

    

    -- Asynchronous read
    rd1 <= registers(slv2uint(a1));
    rd2 <= registers(slv2uint(a2));
    sp_out <= registers(2); -- Output current stack pointer (x2)

    --output a0 for testing
    a0 <=registers(10);

end architecture behav;

