library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

entity GPIO is
	generic
	(
		-- Number of Pins
		num_pins		:		natural;	-- The number of pins on this GPIO port. Allowed values: 8, 16, or 32
		
		-- Pad Logic Levels
		PadOUTPosLogic	:		boolean;	-- Set to true if setting the I/O pad's OUT terminal to a logic high level will make the pad output a logic high level, otherwise set to false
		PadDIRPosLogic	:		boolean;	-- Set to true if setting the I/O pad's DIR terminal to a logic high level will configure the pad in output mode, otherwise set to false
		PadRENPosLogic	:		boolean;	-- Set to true if setting the I/O pad's REN terminal to a logic high level will enable the pad's pullup/pulldown resistor, otherwise set to false
		
		-- Register Reset Values
		-- While these all must be 32-bits wide, if your GPIO port is smaller than 32-bits, you only need to set the LSB bits that correspond to how many bits you're actually using. For instance, if you set num_pins to 8, you only need to set RstVal*(7 downto 0) with values. All remaining bits (others) are don't cares, but need to be set to something (presumably '0's)
		RstValPxOUT		: 		std_logic_vector(31 downto 0) := (others => '0');
		RstValPxDIR		: 		std_logic_vector(31 downto 0) := (others => '0');
		RstValPxSEL		: 		std_logic_vector(31 downto 0) := (others => '0');	
		RstValPxREN		: 		std_logic_vector(31 downto 0) := (others => '0')
	);
	port
	(
        resetn         : in  std_logic;	-- Reset signal, active high
        irq            : out std_logic_vector(num_pins - 1 downto 0);	-- Interrupt request output signal, active high

        clk_mem           : in  std_logic;	-- Clock signal
        en            : in  std_logic;	-- Enable signal, active high
        wen           : in  std_logic_vector(3 downto 0); --active low
        write_data    : in  std_logic_vector(31 downto 0);	-- Data to write to the GPIO registers
        read_data     : out std_logic_vector(31 downto 0);	-- Data read from the GPIO registers
        addr_periph   : in  std_logic_vector(7 downto 2);	-- Peripheral address 

        -- Pad Library Interface
		prt_in			: in	std_logic_vector(num_pins - 1 downto 0);	-- The input signals from the pins
		prt_out_out		: out	std_logic_vector(num_pins - 1 downto 0);	-- The output signals to the pins
		prt_dir_out		: out	std_logic_vector(num_pins - 1 downto 0);	-- The data direction assigned to the pin
		prt_ren_out		: out	std_logic_vector(num_pins - 1 downto 0);	-- The resistor enable state assigned to the pin

		-- Register Outputs
		PxOUT_out		: out	std_logic_vector(num_pins - 1 downto 0);
		PxDIR_out		: out	std_logic_vector(num_pins - 1 downto 0);
		PxREN_out		: out	std_logic_vector(num_pins - 1 downto 0);

        -- Alternate Function Pin Signals
		alt_func_out_in		: in	std_logic_vector(num_pins - 1 downto 0);	-- The alt func's desired output signals
		alt_func_dir_in		: in	std_logic_vector(num_pins - 1 downto 0);	-- The alt func's desired data direction
		alt_func_ren_in		: in	std_logic_vector(num_pins - 1 downto 0)	-- The alt func's desired resistor enable state

    );
end GPIO;

architecture behavioral of GPIO is 

	signal PxIN		: std_logic_vector(num_pins - 1 downto 0);	-- Pin read register. '0' = low or GND, '1' = high or VDD
	signal PxINLat	: std_logic_vector(PxIN'high downto PxIN'low);	-- Latched version of PxIN
	signal PxOUT	: std_logic_vector(num_pins - 1 downto 0);	-- Output drive register. '0' = low or GND, '1' = high or VDD
    signal PxDIR	: std_logic_vector(num_pins - 1 downto 0);	-- Pin direction register. '0' = input, '1' = output
	signal PxSEL	: std_logic_vector(num_pins - 1 downto 0);	-- Peripheral select register. '0' = GPIO, '1' = alt. function
	signal PxREN	: std_logic_vector(num_pins - 1 downto 0);	-- Resistor enable register. '0' = disabled, '1' = enabled
    
    -- New IF registers 
    signal PxIES    : std_logic_vector(num_pins - 1 downto 0);	-- Interrupt edge select. '0' = low-to-high, '1' = high-to-low
    signal PxIE     : std_logic_vector(num_pins - 1 downto 0);	-- Interrupt enable. '0' = disabled, '1' = enabled
    signal PxIF     : std_logic_vector(num_pins - 1 downto 0);	-- Interrupt flag. '0' = no interrupt pending, '1' = interrupt pending
    signal PxIF_ltch : std_logic_vector(num_pins - 1 downto 0);	-- Latched version of PxIF

    signal clk_if_comb : std_logic_vector(num_pins - 1 downto 0);	-- combinational interrupt flag clock
    signal clk_if : std_logic_vector(num_pins - 1 downto 0);	-- enabled interrupt flag clock
    signal clr_if : std_logic_vector(num_pins - 1 downto 0);	-- Clear interrupt flag signal, active high

    constant zero_vector : std_logic_vector(num_pins - 1 downto 0) := (others => '0');

    signal read_data_buff : std_logic_vector(31 downto 0);	-- Buffer for read data
    signal en_addr_periph : natural;	-- The peripheral address to read/write to
begin

    PxIN <= prt_in;
	PxOUT_out <= PxOUT;
	PxDIR_out <= PxDIR;
	PxREN_out <= PxREN;

    -- Drive outputs with pos/neg logic
    gen_port_logic: for i in 0 to num_pins - 1 generate
		gen_prt_out_pos: if PadOUTPosLogic = true generate
			prt_out_out(i) <= PxOUT(i) when PxSEL(i) = '0' else alt_func_out_in(i);
		end generate;
		gen_prt_out_neg: if PadOUTPosLogic = false generate
			prt_out_out(i) <= not PxOUT(i) when PxSEL(i) = '0' else not alt_func_out_in(i);
		end generate;

		gen_prt_dir_pos: if PadDIRPosLogic = true generate
			prt_dir_out(i) <= PxDIR(i) when PxSEL(i) = '0' else alt_func_dir_in(i);
		end generate;
        
		gen_prt_dir_neg: if PadDIRPosLogic = false generate
			prt_dir_out(i) <= not PxDIR(i) when PxSEL(i) = '0' else not alt_func_dir_in(i);
		end generate;

		gen_prt_ren_pos: if PadRENPosLogic = true generate
			prt_ren_out(i) <= PxREN(i) when PxSEL(i) = '0' else alt_func_ren_in(i);
		end generate;
		gen_prt_ren_neg: if PadRENPosLogic = false generate
			prt_ren_out(i) <= not PxREN(i) when PxSEL(i) = '0' else not alt_func_ren_in(i);
		end generate;
	end generate;


    -- Interrupts 
    clk_if_comb <= prt_in xor PxIES; -- Generate clock with selected edge
    -- irq <= '1' when (or PxIF) = '1' else '0';
    -- irq <= '1' when PxIF /= zero_vector else '0'; -- IRQ is high if any interrupt flag is set

    -- TODO: Enable polling without interrupts of these flags (ie interrupt enables and status flags)
    irq <= PxIF; -- Directly connect IRQ to interrupt flags
    
    gen_if_clks: for i in 0 to num_pins - 1 generate
		CGClkIFG: entity work.ClkGate
		port map
		(
			ClkIn	=> clk_if_comb(i),
			En		=> PxIE(i),
			ClkOut	=> clk_if(i)
		);
    

        if_gen_proc: process(clk_if(i), resetn, clr_if(i))
        begin
            if resetn = '0' or clr_if(i) = '1' then
                PxIF(i) <= '0'; --clear interrupt flag
            elsif rising_edge(clk_if(i)) then
                if PxIE(i) = '1' then -- for genus to not optimize out 
                    PxIF(i) <= '1';
                end if;
            end if;
        end process;

    end generate;



    -- Register synchronization
    pin_reg_sync: process (en, PxIN)
    begin
        if falling_edge(en) then
            PxINLat <= not PxIN;
            PxIF_ltch <= not PxIF; 
        end if;
    end process;

    -- Register write process
    reg_write: process(clk_mem, resetn, en)
    begin
        if resetn = '0' then --asynch reset
            PxOUT <= RstValPxOUT(num_pins - 1 downto 0);
            PxDIR <= RstValPxDIR(num_pins - 1 downto 0);
            PxSEL <= RstValPxSEL(num_pins - 1 downto 0);
            PxREN <= RstValPxREN(num_pins - 1 downto 0);
            PxIES <= (others => '0');
            PxIE  <= (others => '0');
        elsif rising_edge(clk_mem) then
            if en = '0' then --system enabled, active low
                case en_addr_periph is
                    when RegSlotPxOUT  => --output logic level
                        
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                PxOUT((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8)); 
                            end if;
                        end loop;
                    when RegSlotPxOUTS => --set (Writing '1' sets output, writing '0' has no effect)
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                for j in (i * 8) to (i * 8) + 7 loop
                                    if write_data(j) = '1' 
                                        then PxOUT(j) <= '1'; 
                                    end if;
                                end loop;
                            end if;
					    end loop;
                    when RegSlotPxOUTC => --clear (Writing '1' clears output, writing '0' has no effect)
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                for j in (i * 8) to (i * 8) + 7 loop
                                    if write_data(j) = '1' then 
                                        PxOUT(j) <= '0'; 
                                    end if;
                                end loop;
                            end if;
                        end loop;
                    when RegSlotPxOUTT => --toggle (Writing '1' toggles output, writing '0' has no effect)
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                for j in (i * 8) to (i * 8) + 7 loop
                                    if write_data(j) = '1' then 
                                        PxOUT(j) <= not PxOUT(j); 
                                    end if;
                                end loop;
                            end if;
                        end loop;
                    when RegSlotPxDIR  => --direction 
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                PxDIR((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8)); 
                            end if;
                        end loop;
                    when RegSlotPxSEL =>
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                PxSEL((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8)); 
                            end if;
                        end loop;
                    when RegSlotPxREN  => --resistor enable (TODO: Check this: Writing '1' disables res, writing '0' has enables res)
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                PxREN((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8)); 
                            end if;
                        end loop;
                    when RegSlotPxIF => --interrupt flag
                        -- Writing to IF register will clear IFs
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                clr_if((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8));
                            end if;
                        end loop;
                    when RegSlotPxIES =>
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                PxIES((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8)); 
                            end if;
                        end loop;
                    when RegSlotPxIE =>
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                PxIE((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8)); 
                            end if;
                        end loop;
                    when others =>
                        null;
                end case;
            end if;
        end if;


        if resetn = '0' or en = '1' then
            clr_if <= (others => '0');
        end if;


    end process;


    

    en_addr_periph <= to_integer(unsigned(addr_periph)); --integer type


    -- Register Read 
    -- TODO: Look into process statement
    with en_addr_periph select 
        read_data_buff(num_pins - 1 downto 0) <= 
            (not PxINLat)	when RegSlotPxIN,
            PxOUT			when RegSlotPxOUT,
            PxOUT			when RegSlotPxOUTS,
            (not PxOUT)		when RegSlotPxOUTC,
            PxOUT			when RegSlotPxOUTT,
            PxDIR			when RegSlotPxDIR,
            PxREN			when RegSlotPxREN,
            PxSEL			when RegSlotPxSEL,
            (not PxIF_ltch)	when RegSlotPxIF,
            PxIES			when RegSlotPxIES,
            PxIE			when RegSlotPxIE,
            (others => '0') when others;    


    -- Process to latch read data output
    process(clk_mem, resetn, en)
    begin
        if rising_edge(clk_mem) then
            if resetn = '0' then
                read_data <= (others => '0');
            elsif en = '0' then
                read_data <= read_data_buff;
            end if;
        end if;
    end process;


    gen_read_data_MSBs : if num_pins /= 32 generate
		read_data_buff(31 downto num_pins) <= (others => '0');
	end generate;

end behavioral;