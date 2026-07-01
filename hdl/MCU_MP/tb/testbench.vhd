library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD_UNSIGNED.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

entity testbench is
end testbench;

architecture test of testbench is
   component MCU
       port (
           clk, reset, CEN: in STD_LOGIC;
           WriteData, DataAdr: out STD_LOGIC_VECTOR(31 downto 0);
           MemWrite: out STD_LOGIC
       );
   end component;

   signal WriteData, DataAdr: STD_LOGIC_VECTOR(31 downto 0);
   signal clk, clkhf, reset, MemWrite, CEN: STD_LOGIC;
   signal check_flag: boolean := false;  -- Flag to control when to perform mem_check

begin
   -- instantiate device to be tested
   dut: MCU
       port map (
           clk => clk,
           reset => reset,
           CEN => CEN,
           WriteData => WriteData,
           DataAdr => DataAdr,
           MemWrite => MemWrite
       );

    CEN <= '0'; --enable chip (active low)

   -- Generate clock with 10 ns period
   clk_gen: process
   begin
        clk <= '1';
        wait for 5 ns; --increase 10x
        clk <= '0';
        wait for 5 ns; --increase 10x
   end process clk_gen;


   -- Generate reset for first two clock cycles
   reset_gen: process
   begin
       reset <= '1';
       wait for 22 ns;
       reset <= '0';
       wait;
   end process reset_gen;

 -- Delay execution of mem_check until after delay
 mem_check_delay: process
 begin
     wait for 1000 ns;
     check_flag <= true;  -- Set flag to true after delay
 end process mem_check_delay;

-- For Behav and Genus
--    -- check that value gets written to address 100 at end of program
--     process(clk) begin
--         if(clk'event and clk = '0' and MemWrite = '1' and check_flag = true) then
--             if( to_integer(DataAdr) = 100 and to_integer(Writedata) = 260) then
--                 report "Simulation Passed!!" severity failure;
--             elsif (DataAdr /= 96) then
--                 report "WriteData: " & integer'image(to_integer(WriteData));
--                 report "DataAdr: " & integer'image(to_integer(DataAdr));
--                 report "MemWrite: " & std_logic'image(MemWrite) ;
--                 report "Simulation failed :(" severity failure;

--             end if;
--         end if;
--     end process;

-- For Behav and Innovus
   -- check that value gets written to address 100 at end of program
    process(clk) begin
        if(clk'event and clk = '1' and MemWrite = '1' and check_flag = true) then
            if( to_integer(DataAdr) = 100 and to_integer(Writedata) = 260) then
                report "WriteData: " & integer'image(to_integer(WriteData));
                report "DataAdr: " & integer'image(to_integer(DataAdr));
                report "MemWrite: " & std_logic'image(MemWrite) ;
                report "Simulation Passed!!" severity failure;
            elsif (DataAdr /= 96) then
                report "WriteData: " & integer'image(to_integer(WriteData));
                report "DataAdr: " & integer'image(to_integer(DataAdr));
                report "MemWrite: " & std_logic'image(MemWrite) ;
                report "Simulation failed :(" severity failure;

            end if;
        end if;
    end process;


end architecture test;
