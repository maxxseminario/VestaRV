library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

entity GPIO is
	generic
	(
		-- Number of pins.
		num_pins		:		natural;	-- The number of pins on this GPIO port. Allowed values: 8, 16 or 32.

		-- Pad logic levels.
		PadOUTPosLogic	:		boolean;	-- True if driving the I/O pad's OUT terminal high makes the pad output a logic high level, false otherwise.
		PadDIRPosLogic	:		boolean;	-- True if driving the I/O pad's DIR terminal high configures the pad as an output, false otherwise.
		PadRENPosLogic	:		boolean;	-- True if driving the I/O pad's REN terminal high enables the pad's pullup/pulldown resistor, false otherwise.

		-- Register reset values.
		-- These are all 32 bits wide, but on a port narrower than 32 bits only the LSBs matching the pin count need real values.
		-- For example, at num_pins = 8 only RstVal*(7 downto 0) matters.
		-- The remaining bits are don't cares but must still be given a value, normally '0'.
		RstValPxOUT		: 		std_logic_vector(31 downto 0) := (others => '0');
		RstValPxDIR		: 		std_logic_vector(31 downto 0) := (others => '0');
		RstValPxSEL		: 		std_logic_vector(31 downto 0) := (others => '0');
		RstValPxREN		: 		std_logic_vector(31 downto 0) := (others => '0');
		RstValPxAFS		: 		std_logic_vector(31 downto 0) := (others => '0')	-- One nibble per pin, low 3 bits used: which alt-function plane the pin selects at reset.
	);
	port
	(
        resetn         : in  std_logic;	-- Reset signal, active low.
        irq            : out std_logic_vector(num_pins - 1 downto 0);	-- Interrupt request outputs, active high, one per pin.

        clk_mem           : in  std_logic;	-- Register clock.
        en            : in  std_logic;	-- Peripheral select, active low in this block.
        wen           : in  std_logic_vector(3 downto 0); -- Byte-lane write enables, active low.
        write_data    : in  std_logic_vector(31 downto 0);	-- Data to write to the GPIO registers.
        read_data     : out std_logic_vector(31 downto 0);	-- Data read from the GPIO registers.
        addr_periph   : in  std_logic_vector(7 downto 2);	-- Peripheral register address.

        -- Pad library interface.
		prt_in			: in	std_logic_vector(num_pins - 1 downto 0);	-- The input signals from the pins.
		prt_out_out		: out	std_logic_vector(num_pins - 1 downto 0);	-- The output signals to the pins.
		prt_dir_out		: out	std_logic_vector(num_pins - 1 downto 0);	-- The data direction assigned to each pin.
		prt_ren_out		: out	std_logic_vector(num_pins - 1 downto 0);	-- The resistor enable state assigned to each pin.

		-- Register outputs.
		PxOUT_out		: out	std_logic_vector(num_pins - 1 downto 0);
		PxDIR_out		: out	std_logic_vector(num_pins - 1 downto 0);
		PxREN_out		: out	std_logic_vector(num_pins - 1 downto 0);
		PxSEL_out		: out	std_logic_vector(num_pins - 1 downto 0);	-- Exported so the SoC can route relocated peripheral INPUTS.
		PxAFS_out		: out	std_logic_vector(3 * num_pins - 1 downto 0);	-- Exported AF select, 3 bits per pin, packed with no reserved nibble bit.

        -- Alternate function pin signals.
        -- GPIO_NUM_AFS planes, flattened: plane k, pin i lives at bit (k * num_pins + i).
        -- Plane 0 (AF0) is the legacy single alternate function; a pin in alternate mode (PxSEL(i)='1') drives the plane selected by its PxAFS field.
		alt_func_out_in		: in	std_logic_vector(GPIO_NUM_AFS * num_pins - 1 downto 0);	-- The alt functions' desired output signals.
		alt_func_dir_in		: in	std_logic_vector(GPIO_NUM_AFS * num_pins - 1 downto 0);	-- The alt functions' desired data direction.
		alt_func_ren_in		: in	std_logic_vector(GPIO_NUM_AFS * num_pins - 1 downto 0);	-- The alt functions' desired resistor enable state.

        -- EVFAB taps (event fabric, event_fabric_spec.md 2026-07-24).
        -- evt_edge_raw is the PRE-MASK edge-select comb vector (prt_in xor PxIES), and PxIE is NEVER consulted.
        -- GPIO's own IF applies the mask at the set, so this raw export is the ONLY discipline-clean tap.
        -- The fabric does the per-bit 2-FF sync, rising-edge detect and EVGPIOMASK selection.
        -- task_outset and task_outclr are one-clk fabric pulses setting or clearing the PxTASK-selected output pins (T7/T8; CLR wins a same-cycle overlap).
        evt_edge_raw       : out std_logic_vector(num_pins - 1 downto 0);
        task_outset        : in  std_logic := '0';
        task_outclr        : in  std_logic := '0'
    );
end GPIO;

architecture behavioral of GPIO is 

	signal PxIN		: std_logic_vector(num_pins - 1 downto 0);	-- Pin read register. '0' = low or GND, '1' = high or VDD.
	signal PxINLat	: std_logic_vector(PxIN'high downto PxIN'low);	-- Latched version of PxIN.
	signal PxOUT	: std_logic_vector(num_pins - 1 downto 0);	-- Output drive register. '0' = low or GND, '1' = high or VDD.
    signal PxDIR	: std_logic_vector(num_pins - 1 downto 0);	-- Pin direction register. '0' = input, '1' = output.
	signal PxSEL	: std_logic_vector(num_pins - 1 downto 0);	-- Peripheral select register. '0' = GPIO, '1' = alternate function.
	signal PxREN	: std_logic_vector(num_pins - 1 downto 0);	-- Resistor enable register. '0' = disabled, '1' = enabled.
	signal PxAFS	: std_logic_vector(3 * num_pins - 1 downto 0);	-- Alternate function select register, 3 bits per pin: which AF plane drives the pad when PxSEL = '1'.
	signal PxAFS_nib : std_logic_vector(31 downto 0);	-- Nibble-per-pin readback image of PxAFS; bit 3 of each nibble is reserved and reads '0'.

	-- Plane-muxed alternate function signals.
	-- The pin's PxAFS field selects which of the GPIO_NUM_AFS planes reaches the PxSEL pad mux below.
	signal af_out	: std_logic_vector(num_pins - 1 downto 0);
	signal af_dir	: std_logic_vector(num_pins - 1 downto 0);
	signal af_ren	: std_logic_vector(num_pins - 1 downto 0);
    
    -- Interrupt flag registers.
    signal PxIES    : std_logic_vector(num_pins - 1 downto 0);	-- Interrupt edge select. '0' = low-to-high, '1' = high-to-low.
    signal PxIE     : std_logic_vector(num_pins - 1 downto 0);	-- Interrupt enable. '0' = disabled, '1' = enabled.
    signal PxIF     : std_logic_vector(num_pins - 1 downto 0);	-- Interrupt flag. '0' = no interrupt pending, '1' = interrupt pending.
    signal PxIF_ltch : std_logic_vector(num_pins - 1 downto 0);	-- Latched version of PxIF.

    signal clk_if_comb : std_logic_vector(num_pins - 1 downto 0);	-- Combinational interrupt flag clock.
    signal PxTASK      : std_logic_vector(num_pins - 1 downto 0);	-- EVFAB task pin-select: which pins task_outset and task_outclr act on.
    -- EVFAB TASKPINS slot, a LOCAL constant in the first free GPIO slot.
    -- The generated MemoryMap.vhd constant and the TRM row land with the chipgen knob, not here.
    constant RegSlotPxTASK : natural := 12;
    signal clk_if : std_logic_vector(num_pins - 1 downto 0);	-- Enabled interrupt flag clock.
    signal clr_if : std_logic_vector(num_pins - 1 downto 0);	-- Clear interrupt flag signal, active high.

    constant zero_vector : std_logic_vector(num_pins - 1 downto 0) := (others => '0');

    signal read_data_buff : std_logic_vector(31 downto 0);	-- Buffer for read data.
    signal en_addr_periph : natural;	-- The peripheral register address being read or written.
begin

    PxIN <= prt_in;
	PxOUT_out <= PxOUT;
	PxDIR_out <= PxDIR;
	PxREN_out <= PxREN;
	PxSEL_out <= PxSEL;
	PxAFS_out <= PxAFS;

	-- The nibble-per-pin PxAFS register layout only fits 8 pins in one 32-bit register.
	-- Larger ports would need a second AFS register, which is not needed since every port in the SoC is 8 pins.
	assert num_pins <= 8
		report "GPIO: PxAFS multi-AF support requires num_pins <= 8 (one nibble per pin in a 32-bit register)"
		severity failure;

	-- Alternate-function plane mux: each pin's PxAFS field picks which of the GPIO_NUM_AFS flattened planes reaches the PxSEL pad mux below.
	af_plane_mux: process(PxAFS, alt_func_out_in, alt_func_dir_in, alt_func_ren_in)
		variable k : natural range 0 to GPIO_NUM_AFS - 1;
	begin
		for i in 0 to num_pins - 1 loop
			k := to_integer(unsigned(PxAFS((3 * i) + 2 downto 3 * i)));
			af_out(i) <= alt_func_out_in((k * num_pins) + i);
			af_dir(i) <= alt_func_dir_in((k * num_pins) + i);
			af_ren(i) <= alt_func_ren_in((k * num_pins) + i);
		end loop;
	end process;

	-- Nibble-per-pin readback image of PxAFS; bit 3 of each nibble is reserved.
	gen_afs_nib: for i in 0 to num_pins - 1 generate
		PxAFS_nib((4 * i) + 2 downto 4 * i) <= PxAFS((3 * i) + 2 downto 3 * i);
		PxAFS_nib((4 * i) + 3) <= '0';
	end generate;
	gen_afs_nib_msbs: if (4 * num_pins) < 32 generate
		PxAFS_nib(31 downto 4 * num_pins) <= (others => '0');
	end generate;

    -- Drive the pads, inverting where the pad terminal uses negative logic.
    gen_port_logic: for i in 0 to num_pins - 1 generate
		gen_prt_out_pos: if PadOUTPosLogic = true generate
			prt_out_out(i) <= PxOUT(i) when PxSEL(i) = '0' else af_out(i);
		end generate;
		gen_prt_out_neg: if PadOUTPosLogic = false generate
			prt_out_out(i) <= not PxOUT(i) when PxSEL(i) = '0' else not af_out(i);
		end generate;

		gen_prt_dir_pos: if PadDIRPosLogic = true generate
			prt_dir_out(i) <= PxDIR(i) when PxSEL(i) = '0' else af_dir(i);
		end generate;

		gen_prt_dir_neg: if PadDIRPosLogic = false generate
			prt_dir_out(i) <= not PxDIR(i) when PxSEL(i) = '0' else not af_dir(i);
		end generate;

		gen_prt_ren_pos: if PadRENPosLogic = true generate
			prt_ren_out(i) <= PxREN(i) when PxSEL(i) = '0' else af_ren(i);
		end generate;
		gen_prt_ren_neg: if PadRENPosLogic = false generate
			prt_ren_out(i) <= not PxREN(i) when PxSEL(i) = '0' else not af_ren(i);
		end generate;
	end generate;


    -- Interrupts.
    clk_if_comb <= prt_in xor PxIES; -- Flag clock, polarity chosen by the edge select.
    evt_edge_raw <= clk_if_comb;     -- EVFAB EV15 raw export, pre-mask and pre-sync.
    -- irq <= '1' when (or PxIF) = '1' else '0';
    -- irq <= '1' when PxIF /= zero_vector else '0'; -- IRQ is high if any interrupt flag is set

    -- TODO: allow these flags to be polled without interrupts, that is, separate the interrupt enables from the status flags.
    irq <= PxIF; -- The IRQ lines are the interrupt flags themselves.

    -- One gated flag clock and one flag flop per pin.
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
                PxIF(i) <= '0'; -- Clear the interrupt flag.
            elsif rising_edge(clk_if(i)) then
                if PxIE(i) = '1' then -- Kept explicit so genus does not optimize the enable away.
                    PxIF(i) <= '1';
                end if;
            end if;
        end process;

    end generate;



    -- Snapshot the pin and flag states at the end of a bus access, inverted for the readback mux.
    pin_reg_sync: process (en, PxIN)
    begin
        if falling_edge(en) then
            PxINLat <= not PxIN;
            PxIF_ltch <= not PxIF; 
        end if;
    end process;

    -- Register write process, plus the EVFAB output tasks.
    reg_write: process(clk_mem, resetn, en)
    begin
        if resetn = '0' then -- Asynchronous reset.
            PxOUT <= RstValPxOUT(num_pins - 1 downto 0);
            PxDIR <= RstValPxDIR(num_pins - 1 downto 0);
            PxSEL <= RstValPxSEL(num_pins - 1 downto 0);
            PxREN <= RstValPxREN(num_pins - 1 downto 0);
            for i in 0 to num_pins - 1 loop -- RstValPxAFS is nibble-packed like the register image.
                PxAFS((3 * i) + 2 downto 3 * i) <= RstValPxAFS((4 * i) + 2 downto 4 * i);
            end loop;
            PxIES <= (others => '0');
            PxIE  <= (others => '0');
            PxTASK <= (others => '0');   -- EVFAB task pin-select is inert out of reset.
        elsif rising_edge(clk_mem) then
            if en = '0' then -- Peripheral selected, active low.
                case en_addr_periph is
                    when RegSlotPxOUT  => -- Output logic level.
                        
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                PxOUT((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8)); 
                            end if;
                        end loop;
                    when RegSlotPxOUTS => -- Set: writing '1' sets the output, writing '0' has no effect.
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                for j in (i * 8) to (i * 8) + 7 loop
                                    if write_data(j) = '1' 
                                        then PxOUT(j) <= '1'; 
                                    end if;
                                end loop;
                            end if;
					    end loop;
                    when RegSlotPxOUTC => -- Clear: writing '1' clears the output, writing '0' has no effect.
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                for j in (i * 8) to (i * 8) + 7 loop
                                    if write_data(j) = '1' then 
                                        PxOUT(j) <= '0'; 
                                    end if;
                                end loop;
                            end if;
                        end loop;
                    when RegSlotPxOUTT => -- Toggle: writing '1' toggles the output, writing '0' has no effect.
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                for j in (i * 8) to (i * 8) + 7 loop
                                    if write_data(j) = '1' then 
                                        PxOUT(j) <= not PxOUT(j); 
                                    end if;
                                end loop;
                            end if;
                        end loop;
                    when RegSlotPxDIR  => -- Pin direction.
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                PxDIR((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8)); 
                            end if;
                        end loop;
                    when RegSlotPxSEL => -- GPIO or alternate function per pin.
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                PxSEL((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8)); 
                            end if;
                        end loop;
                    when RegSlotPxREN  => -- Resistor enable. TODO: confirm the polarity, the note here claims '1' disables and '0' enables the resistor.
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then
                                PxREN((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8));
                            end if;
                        end loop;
                    when RegSlotPxAFS => -- Alternate function select, one nibble per pin: low 3 bits used, nibble bit 3 reserved.
                        for i in 0 to num_pins - 1 loop
                            if wen(i / 2) = '0' then -- Byte lane i/2 covers pins 2i and 2i+1.
                                PxAFS((3 * i) + 2 downto 3 * i) <= write_data((4 * i) + 2 downto 4 * i);
                            end if;
                        end loop;
                    when RegSlotPxIF => -- Interrupt flags.
                        -- Writing a '1' to a flag bit clears that flag.
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                clr_if((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8));
                            end if;
                        end loop;
                    when RegSlotPxIES => -- Interrupt edge select.
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                PxIES((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8)); 
                            end if;
                        end loop;
                    when RegSlotPxIE => -- Interrupt enable.
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then 
                                PxIE((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8)); 
                            end if;
                        end loop;
                    when RegSlotPxTASK => -- EVFAB task pin-select.
                        for i in 0 to (num_pins / 8) - 1 loop
                            if wen(i) = '0' then
                                PxTASK((i * 8) + 7 downto (i * 8)) <= write_data((i * 8) + 7 downto (i * 8));
                            end if;
                        end loop;
                    when others => -- Unmapped slot: the write is ignored.
                        null;
                end case;
            end if;

            -- EVFAB consumer tasks (event fabric, event_fabric_spec.md 2026-07-24): one-clk fabric pulses acting on the PxTASK-selected pins.
            -- They sit OUTSIDE the en gate, since clk_mem free-runs at integration, and AFTER the register case, so a task wins its pins on a coincident CPU write.
            -- CLR is evaluated after SET, so a same-cycle set and clear on an overlapping pin resolves to CLR: the safe direction, matching the TIMER stop-wins rule.
            -- TOGGLE is deliberately NOT offered.
            if task_outset = '1' then
                for j in 0 to num_pins - 1 loop
                    if PxTASK(j) = '1' then PxOUT(j) <= '1'; end if;
                end loop;
            end if;
            if task_outclr = '1' then
                for j in 0 to num_pins - 1 loop
                    if PxTASK(j) = '1' then PxOUT(j) <= '0'; end if;
                end loop;
            end if;
        end if;


        -- The flag-clear strobes last only while the access is live.
        if resetn = '0' or en = '1' then
            clr_if <= (others => '0');
        end if;


    end process;


    

    en_addr_periph <= to_integer(unsigned(addr_periph)); -- Register slot number as an integer.


    -- Register read mux.
    -- TODO: consider rewriting this as a process statement.
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
            PxAFS_nib(num_pins - 1 downto 0)	when RegSlotPxAFS,
            PxTASK			when RegSlotPxTASK,
            (others => '0') when others;


    -- Latch the selected read data onto the bus.
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
		-- PxAFS is the one register wider than the pin count, at a nibble per pin, so its upper readback bits ride the otherwise-zero MSB lanes.
		read_data_buff(31 downto num_pins) <=
			PxAFS_nib(31 downto num_pins) when en_addr_periph = RegSlotPxAFS
			else (others => '0');
	end generate;

end behavioral;