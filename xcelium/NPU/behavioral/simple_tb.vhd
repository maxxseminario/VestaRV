library ieee;
use ieee.std_logic_1164.all;
library std;
use std.textio.all;

entity simple_tb is
end simple_tb;

architecture test of simple_tb is
    signal clk : std_logic := '0';
begin
    clk <= not clk after 5 ns;

    process
        variable i : integer;
    begin
        report "SIMPLE_TB: started" severity note;
        wait for 10 ns;
        report "SIMPLE_TB: 10 ns passed" severity note;
        for i in 1 to 10 loop
            wait for 100 ns;
            report "SIMPLE_TB: loop iteration " & integer'image(i) & "/10" severity note;
        end loop;
        report "SIMPLE_TB: done - all 10 iterations complete" severity note;
        assert false report "SIMPLE_TB: simulation stop" severity failure;
        wait;
    end process;
end test;
