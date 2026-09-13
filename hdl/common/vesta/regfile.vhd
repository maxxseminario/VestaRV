-- VestaRV: 32-entry architectural register file
-- Two asynchronous read ports and one synchronous write port. x0 is never written, so it reads 0 for the life of the design.
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

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
        a0:   out STD_LOGIC_VECTOR(XLEN-1 downto 0)      -- Test export of x10, watched by the testbench only
    );
end entity regfile;

architecture behav of regfile is
    type reg_array is array (0 to 31) of std_logic_vector(XLEN-1 downto 0);
    signal registers: reg_array := (others => (others => '0'));

begin
    -- Synchronous write port.
    process(clk)
    begin
        if resetn = '0' then
            registers <= (others => (others => '0')); -- Clear the whole file on reset
        elsif rising_edge(clk) then
            -- Write only when we3 is asserted AND the destination is not x0, which stays hardwired to 0.
            if we3 = '1' and a3 /= "00000" then
                    registers(to_integer(unsigned(a3))) <= wd3;
            end if;
        end if;
    end process;

    -- Asynchronous read ports.
    rd1 <= registers(to_integer(unsigned(a1)));
    rd2 <= registers(to_integer(unsigned(a2)));

    -- Export a0 (x10) for the testbench pass/fail check.
    a0 <=registers(10);

end architecture behav;