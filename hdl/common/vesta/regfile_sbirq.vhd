-- VestaRV: 32-entry architectural register file, shadow-bank IRQ variant
-- Two asynchronous read ports, one synchronous write port, and a side channel that reads and writes the stack pointer (x2) directly.
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

entity regfile is
    port (
        clk:  in  STD_LOGIC;
        resetn:  in  STD_LOGIC;
        we3:  in  STD_LOGIC;                        -- Write enable for the write port
        a1:   in  STD_LOGIC_VECTOR(4 downto 0);     -- Read address 1
        a2:   in  STD_LOGIC_VECTOR(4 downto 0);     -- Read address 2
        a3:   in  STD_LOGIC_VECTOR(4 downto 0);     -- Write address
        wd3:  in  STD_LOGIC_VECTOR(XLEN-1 downto 0);    -- Write data
        rd1:  out STD_LOGIC_VECTOR(XLEN-1 downto 0);    -- Read data 1
        rd2:  out STD_LOGIC_VECTOR(XLEN-1 downto 0);     -- Read data 2

        sp_in : in std_logic_vector(XLEN-1 downto 0); -- New stack pointer value on irq_save
        sp_out : out std_logic_vector(XLEN-1 downto 0); -- Current stack pointer value on irq_restore
        sp_write : in std_logic; -- Write strobe for the new stack pointer value

        -- Test export: a0 is the pass/fail word the testbench watches.
        a0: out std_logic_vector(XLEN-1 downto 0)

    );
end entity regfile;

-- TODO: drop the physical x0 entry from the array, since it is hardwired to 0.

architecture behav of regfile is
    type reg_array is array (0 to 31) of std_logic_vector(XLEN-1 downto 0);
    signal registers: reg_array;
    signal reg_context: reg_array;
    signal clk_irq : std_logic;

begin

    -- Synchronous write port, plus the stack-pointer side channel.
    reg_wr: process(clk, resetn)
    begin
        if resetn = '0' then
            registers <= (others => (others => '0')); -- Clear the whole file on reset
        elsif rising_edge(clk) then


            -- Write only when we3 is asserted AND the destination is not x0, which stays hardwired to 0.
            if we3 = '1' and a3 /= "00000" then
                registers(0) <= (others => '0');
                registers(slv2uint(a3)) <= wd3;
            end if;

            if sp_write = '1' then
                registers(2) <= sp_in; -- Update the stack pointer (x2) from the side channel
            end if;


        end if;
    end process;

    -- IRQ handling

    

    -- Asynchronous read ports.
    rd1 <= registers(slv2uint(a1));
    rd2 <= registers(slv2uint(a2));
    sp_out <= registers(2); -- Current stack pointer (x2)

    -- Export a0 (x10) for the testbench pass/fail check.
    a0 <=registers(10);

end architecture behav;

