library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity pulse_extender is
    Port ( 
        clk : in STD_LOGIC;
        resetn : in STD_LOGIC;
        x : in STD_LOGIC;    -- input pulse, active low
        y : out STD_LOGIC    -- x stretched by one clock cycle, active low
    );
end pulse_extender;

-- Stretches a low pulse by one clock cycle, glitch free.

architecture Behavioral of pulse_extender is
    signal in_delayed : STD_LOGIC;
begin
    process(clk, resetn)   -- one-cycle history of x
    begin
        if resetn = '0' then
            in_delayed <= '1';  -- x is active low, so the delay register resets high
        elsif rising_edge(clk) then
            in_delayed <= x;
        end if;
    end process;
    
    -- Combinational output: low while either this cycle or the previous one is low.
    y <= x AND in_delayed;
    
end Behavioral;