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
   signal check_flag: boolean := false;  -- Holds mem_check off until the startup delay has elapsed.

begin
   -- Device under test.
   dut: MCU
       port map (
           clk => clk,
           reset => reset,
           CEN => CEN,
           WriteData => WriteData,
           DataAdr => DataAdr,
           MemWrite => MemWrite
       );

    CEN <= '0'; -- Enable the chip; CEN is active low.

   -- Free-running clock, 10 ns period.
   clk_gen: process
   begin
        clk <= '1';
        wait for 5 ns; --increase 10x
        clk <= '0';
        wait for 5 ns; --increase 10x
   end process clk_gen;


   -- Hold reset over the first two clock cycles.
   reset_gen: process
   begin
       reset <= '1';
       wait for 22 ns;
       reset <= '0';
       wait;
   end process reset_gen;

 -- Give the program 1000 ns to run before mem_check is allowed to judge a write.
 mem_check_delay: process
 begin
     wait for 1000 ns;
     check_flag <= true;  -- Release the checker once the delay has expired.
 end process mem_check_delay;

/* For Behav and Innovus
   Pass condition: the program writes 260 to address 100 at the end of the run.
   Address 96 is the expected intermediate store and is ignored; any other write fails the run. */
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
