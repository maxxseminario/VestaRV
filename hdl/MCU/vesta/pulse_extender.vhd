library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity pulse_extender is
    Port ( 
        clk : in STD_LOGIC;
        resetn : in STD_LOGIC;
        x : in STD_LOGIC;
        y : out STD_LOGIC
    );
end pulse_extender;

-- Stretches low pulse by one clock cycle without glitches

architecture Behavioral of pulse_extender is
    signal in_delayed : STD_LOGIC;
begin
    process(clk, resetn)
    begin
        if resetn = '0' then
            in_delayed <= '1';  -- Assuming active-low signal
        elsif rising_edge(clk) then
            in_delayed <= x;
        end if;
    end process;
    
    -- Combinatorial logic - extends the low pulse
    y <= x AND in_delayed;
    
end Behavioral;