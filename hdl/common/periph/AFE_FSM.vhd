/* =============================================================================
   AFE_FSM.vhd: dual-slope ADC control for the analog front end.
   =============================================================================
   Three entities live here: dual_slope_fsm2 is the conversion FSM, counter_upd is the shared up/down cycle counter it drives, and AFE_FSM is the top level that gates the converter clock and wires the two together.
   One conversion resets the integrator, integrates for cycle_set clocks, then de-integrates until the comparator trips; the counter value at that moment IS the result.
   ============================================================================= */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use IEEE.NUMERIC_STD.ALL;

-- The conversion FSM: sequences the integrator switches and the counter, and latches the de-integration count as the result.
entity dual_slope_fsm2 is
    Port (
        clk         : in  std_logic;
        rst         : in  std_logic;
        start       : in  std_logic;
        enable      : in  std_logic;
        cmp_out     : in  std_logic;
        count       : in  std_logic_vector(11 downto 0);
	    cycleSet    : in std_logic_vector(11 downto 0);
        init_val    : out std_logic_vector(11 downto 0);
        mode        : out std_logic;
        set         : out std_logic;
        counter_en  : out std_logic;
        sw1, sw2, sw3 : out std_logic;
        done        : out std_logic;
	    result_latch: out std_logic_vector(11 downto 0);
	    busy	    : out std_logic
    );
end dual_slope_fsm2;

architecture Behavioral of dual_slope_fsm2 is

    -- One conversion runs IDLE, reset, integrate, de-integrate, store, back to IDLE.
    -- The _PRE states preload the counter for the phase the following _WAIT state times.
    type state_type is (
        IDLE, RESET_PRE, RESET_WAIT,
        INTEGRATE_PRE, INTEGRATE_WAIT,
        DEINTEGRATE_WAIT,
        STORE
    );

    signal state, next_state : state_type;
    constant RESET_CYCLES : std_logic_vector(11 downto 0) := std_logic_vector(to_unsigned(74, 12));   -- integrator reset length
    constant DEINT_TIMEOUT : std_logic_vector(11 downto 0) := std_logic_vector(to_unsigned(0, 12));   -- de-integration floor

    signal counter_en_reg : std_logic;

begin

    counter_en <= counter_en_reg; -- registered counter enable, exported as-is
    
    -- Busy for the whole conversion: any state other than IDLE, and never during reset.
    busy <= '0' when rst = '1' else '1' when state /= IDLE else '0';
    
    -- State register and counter-enable tracking; dropping enable parks the FSM in IDLE.
    -- The counter runs through both _PRE states and both timed _WAIT states, and through de-integration until the comparator trips or the count reaches zero.
    process(clk, rst)
    begin
        if rst = '1' then
            state <= IDLE;
            counter_en_reg <= '0';  
        elsif rising_edge(clk) then
            if enable = '1' then
                state <= next_state;
                -- Counter enable for the state we are about to enter.
                if next_state = RESET_PRE or next_state = RESET_WAIT or
                   next_state = INTEGRATE_PRE or next_state = INTEGRATE_WAIT or
                   (next_state = DEINTEGRATE_WAIT and cmp_out = '0' and count /= 0) then
                    counter_en_reg <= '1';
                else
                    counter_en_reg <= '0';
                end if;
            else
                state <= IDLE;
                counter_en_reg <= '0';
            end if;
        end if;
    end process;


    -- Combinational next-state and output logic; every output is defaulted first, so each arm only names what it drives.
    process(state, start, count, cmp_out,rst, cycleSet)
    begin
	if rst = '1' then
	    result_latch <= (others => '0');
	    sw1 <= '0'; sw2 <= '0'; sw3 <= '0';
            set <= '0'; mode <= '0';
            init_val <= (others => '0');
            done <= '0';
	    next_state <= IDLE;
	else
        -- Default outputs
		sw1 <= '0'; sw2 <= '0'; sw3 <= '0';
		set <= '0'; mode <= '0';
		init_val <= (others => '0');
		done <= '0';
		next_state <= state;


		case state is

		    when IDLE =>   -- idle: outputs parked, waiting for a start request
		        if start = '1' then
		            next_state <= RESET_PRE;
		        end if;

		    when RESET_PRE =>   -- load the counter with zero for the integrator reset
		        set <= '1';
		        init_val <= (others => '0');
		        mode <= '0';
		        next_state <= RESET_WAIT;

		    when RESET_WAIT =>   -- sw1 shorts the integrator for RESET_CYCLES counts
		        sw1 <= '1';
		        mode <= '0';
		        if count = RESET_CYCLES then
		            next_state <= INTEGRATE_PRE;
		        end if;

		    when INTEGRATE_PRE =>   -- restart the counter from zero for the integrate phase
		        set <= '1';
		        init_val <= (others => '0');
		        mode <= '0';
		        next_state <= INTEGRATE_WAIT;

		    when INTEGRATE_WAIT =>   -- sw2 integrates the input for cycleSet counts, then preload cycleSet and count down
		        sw2 <= '1';
		        mode <= '0';
		        if count = cycleSet then
		            set <= '1';
		            init_val <= cycleSet;
		            mode <= '1';
		            next_state <= DEINTEGRATE_WAIT;
		        end if;
		    
		    when DEINTEGRATE_WAIT =>   -- sw3 ramps back down until the comparator trips, or the counter reaches one
	    		sw3 <= '1';
	    		mode <= '1';
	    		if cmp_out = '1' then
			    next_state <= STORE;
	    		elsif count = std_logic_vector(to_unsigned(1, 12)) then
			    next_state <= STORE;
	    		end if;

		    when STORE =>   -- latch the remaining count as the conversion result and pulse done
		        done <= '1';
			    result_latch <= count;
		        next_state <= IDLE;

            -- Catch-all so the FSM cannot latch on an unreachable encoding.
            when others =>
                next_state <= IDLE;

		end case;
	   end if;
    end process;

end Behavioral;





library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

-- The conversion counter: counts up while mode is '0' and down while mode is '1', loads init_val on set, and holds while enable is low.
entity counter_upd is
    Port(
        clk, rst, mode, set, enable : in STD_LOGIC;
        init_val : in STD_LOGIC_VECTOR(11 downto 0);
        count : out STD_LOGIC_VECTOR(11 downto 0)
    );
end;

architecture behav of counter_upd is
    signal count_reg : STD_LOGIC_VECTOR(11 downto 0);
begin

    -- Load, count and hold in one process; reset and the enable hold are asynchronous.
    process(clk, rst, enable)
    begin
        if rst = '1' then
            count_reg <= (others => '0');

        elsif enable = '0' then
            -- no change to count_reg (acts like a hold)
            null;

        elsif rising_edge(clk) then
            if set = '1' then
                count_reg <= init_val;
            elsif mode = '0' then
                count_reg <= count_reg + 1;
            else
                count_reg <= count_reg - 1;
            end if;
        end if;
    end process;

    count <= count_reg;

end architecture;


-- TOP LEVEL FSM FOR AFE ---------------------------------------
-- Gates the converter clock with enable, then runs the FSM and the counter from that gated clock so a disabled AFE costs no toggles.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;


entity AFE_FSM is
    port (
        -- Inputs from MCU
        clk         : in  std_logic;
        rst         : in  std_logic;
        start       : in  std_logic;
        enable      : in  std_logic;

        -- Inputs from AFE
        cmp_out     : in  std_logic;
        cycle_set   : in  std_logic_vector(11 downto 0);

        -- Outputs to MCU and AFE
	--TODO: is clk_adc needed as a port or just a signal to connect clkGate to FSM & Counter??
        clk_adc       : inout std_logic; 
        count         : inout  std_logic_vector(11 downto 0);
        sw            : out std_logic_vector(3 downto 1);
        done          : out std_logic;
        result_latch  : out std_logic_vector(11 downto 0);
	busy	      : out std_logic
    );
end AFE_FSM;

architecture Behavioral of AFE_FSM is


    signal init_val : std_logic_vector(11 downto 0);
    signal mode : std_logic;
    signal set : std_logic;
    signal counter_en : std_logic;


begin

    -- Converter clock, gated by enable.
    cg_dsadc: entity work.ClkGate
    port map
    (
        ClkIn   => clk,
        En      => enable,
        ClkOut  => clk_adc
    );

    -- The conversion FSM: switches out to the AFE, counter controls back into the counter below.
    fsm: entity work.dual_slope_fsm2
    port map ( 
        clk => clk_adc,
        rst => rst,

        start => start,
        enable => enable,
        cmp_out => cmp_out,
        count => count,
        cycleSet => cycle_set,
        init_val => init_val,
        mode => mode,
        set => set,
        counter_en => counter_en,
        sw1 => sw(1),
        sw2 => sw(2),
        sw3 => sw(3),
        done => done,
        result_latch => result_latch,
	busy => busy
    );


    -- The shared cycle counter, enabled only during the phases the FSM times.
    counter: entity work.counter_upd
    port map (
        clk => clk_adc,
        rst => rst,

        mode => mode,
        set => set,

        enable => counter_en,
        init_val => init_val,
        count => count
    );


end Behavioral;
