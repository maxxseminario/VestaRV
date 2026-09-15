-- VestaRV: GPIO port
-- One parameterised port of num_pins (8, 16 or 32) pins: output, direction, resistor-enable and alternate-function select registers, per-pin edge-select interrupt flags, and a set/clear/toggle alias of PxOUT.
-- The pad polarity generics say what the pad library's OUT/DIR/REN terminals mean; the register bits are always in positive logic.
-- PxAFS is 3 bits per pin and selects one of NUM_AFS alternate-function planes, flattened so plane k, pin i lives at bit (k * num_pins + i).
-- Register reset values arrive as 32-bit generics; on a narrower port only the low num_pins bits are used.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.constants.all;
-- Word offsets, field ranges, resets and implemented-bit masks: generated from hdl/common/regs/rdl/gpio.rdl, which replaces the work.MemoryMap clause (both would make every slot name and every PxAFS<n>_LSB an ambiguous homograph).
-- The plane count that used to come from MemoryMap's NUM_AFS is the NUM_AFS generic below; MCU.vhd passes it.
use work.gpio_regs_pkg.all;

entity GPIO is
	generic
	(
		-- Number of pins.
		num_pins		:		natural;	-- The number of pins on this GPIO port. The register description is the 8-pin port; see the assertion below.

		-- Number of alternate-function planes. This was the work.MemoryMap constant NUM_AFS; it is a generic so this entity can take its slot names from gpio_regs_pkg instead.
		NUM_AFS			:		natural := 8;

		-- Pad logic levels.
		PadOUTPosLogic	:		boolean;	-- True if driving the I/O pad's OUT terminal high makes the pad output a logic high level, false otherwise.
		PadDIRPosLogic	:		boolean;	-- True if driving the I/O pad's DIR terminal high configures the pad as an output, false otherwise.
		PadRENPosLogic	:		boolean;	-- True if driving the I/O pad's REN terminal high enables the pad's pullup/pulldown resistor, false otherwise.

		-- Register reset values, all 32 bits wide: on a narrower port only the LSBs matching the pin count matter (at num_pins = 8, RstVal*(7 downto 0)).
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

        -- Alternate function pin signals: NUM_AFS planes, flattened so plane k, pin i lives at bit (k * num_pins + i).
        -- A pin in alternate mode (PxSEL(i)='1') drives the plane selected by its PxAFS field; plane 0 (AF0) is the plain single alternate function.
		alt_func_out_in		: in	std_logic_vector(NUM_AFS * num_pins - 1 downto 0);	-- The alt functions' desired output signals.
		alt_func_dir_in		: in	std_logic_vector(NUM_AFS * num_pins - 1 downto 0);	-- The alt functions' desired data direction.
		alt_func_ren_in		: in	std_logic_vector(NUM_AFS * num_pins - 1 downto 0);	-- The alt functions' desired resistor enable state.

        -- Event-fabric taps: evt_edge_raw is the PRE-MASK edge-select comb vector (prt_in xor PxIES) and PxIE is NEVER consulted, since GPIO's own IF applies the mask at the set; the fabric does the per-bit 2-FF sync, rising-edge detect and mask selection.
        -- task_outset and task_outclr are one-clk fabric pulses setting or clearing the PxTASK-selected output pins, and CLR wins a same-cycle overlap.
        evt_edge_raw       : out std_logic_vector(num_pins - 1 downto 0);
        task_outset        : in  std_logic := '0';
        task_outclr        : in  std_logic := '0'
    );
end GPIO;

architecture behavioral of GPIO is 

	signal PxOUT	: std_logic_vector(num_pins - 1 downto 0);	-- Output drive register. '0' = low or GND, '1' = high or VDD.
    signal PxDIR	: std_logic_vector(num_pins - 1 downto 0);	-- Pin direction register. '0' = input, '1' = output.
	signal PxSEL	: std_logic_vector(num_pins - 1 downto 0);	-- Peripheral select register. '0' = GPIO, '1' = alternate function.
	signal PxREN	: std_logic_vector(num_pins - 1 downto 0);	-- Resistor enable register. '0' = disabled, '1' = enabled.
	signal PxAFS	: std_logic_vector(3 * num_pins - 1 downto 0);	-- Alternate function select register, 3 bits per pin: which AF plane drives the pad when PxSEL = '1'.

	-- Plane-muxed alternate function signals.
	-- The pin's PxAFS field selects which of the NUM_AFS planes reaches the PxSEL pad mux below.
	signal af_out	: std_logic_vector(num_pins - 1 downto 0);
	signal af_dir	: std_logic_vector(num_pins - 1 downto 0);
	signal af_ren	: std_logic_vector(num_pins - 1 downto 0);
    
    -- Interrupt flag registers.
    signal PxIES    : std_logic_vector(num_pins - 1 downto 0);	-- Interrupt edge select. '0' = low-to-high, '1' = high-to-low.
    signal PxIE     : std_logic_vector(num_pins - 1 downto 0);	-- Interrupt enable. '0' = disabled, '1' = enabled.
    signal PxIF     : std_logic_vector(num_pins - 1 downto 0);	-- Interrupt flag. '0' = no interrupt pending, '1' = interrupt pending.

    signal edge_sel_comb : std_logic_vector(num_pins - 1 downto 0);	-- Edge-select vector, prt_in xor PxIES, exported to the event fabric.
    signal PxTASK      : std_logic_vector(num_pins - 1 downto 0);	-- Task pin-select: which pins task_outset and task_outclr act on.
    signal prt_in_s2 : std_logic_vector(num_pins - 1 downto 0);	-- prt_in after the two-flop synchroniser, in the clk_mem domain.
    signal prt_in_prev : std_logic_vector(num_pins - 1 downto 0);	-- prt_in_s2 delayed one clk_mem, the edge reference.
    signal pin_edge : std_logic_vector(num_pins - 1 downto 0);	-- The PxIES-selected transition between prt_in_s2 and prt_in_prev.
    signal clr_if : std_logic_vector(num_pins - 1 downto 0);	-- Clear interrupt flag signal, active high.

    constant zero_vector : std_logic_vector(num_pins - 1 downto 0) := (others => '0');

    -- The bus side is one periph_regs instance driven by gpio_regs_pkg's tables; see hdl/common/regs/REGFILE.md.
    -- PxOUT is the interesting case in the whole tree: THREE alias words act on
    -- ONE storage word through hooks, which is what WOSET, W1C and WOT exist for.
    signal regs_q     : reg_arr_t;   -- the stored words
    signal hw_rd_s    : reg_arr_t;   -- the read source for the words this module does not store
    signal hw_we_s    : reg_arr_t;
    signal hw_wdata_s : reg_arr_t;
    signal hw_set_s   : reg_arr_t;
    signal hw_clr_s   : reg_arr_t;
    signal w1c_s      : reg_arr_t;   -- a 1 written to PxOUTC or PxIF
    signal woset_s    : reg_arr_t;   -- a 1 written to PxOUTS
    signal wot_s      : reg_arr_t;   -- a 1 written to PxOUTT
    signal task_set   : word;        -- the fabric task, masked to its PxTASK pins
    signal task_clr   : word;

    -- Zero-extend a register field to a bus word.
    function pad(v : std_logic_vector) return word is
        variable r : word := (others => '0');
    begin
        r(v'length - 1 downto 0) := v;
        return r;
    end function;

    -- The five registers whose reset is a GENERIC of this entity rather than a
    -- property of the description; the .rdl cannot say that, so they arrive
    -- through RSTVAL_OR, masked to the implemented bits the table declares.
    -- PxAFS's reset is nibble-packed exactly like its storage image.
    function rstValOr return reg_arr_t is
        variable r : reg_arr_t := (others => (others => '0'));
    begin
        r(RegSlotPxOUT) := RstValPxOUT and IMPL(RegSlotPxOUT);
        r(RegSlotPxDIR) := RstValPxDIR and IMPL(RegSlotPxDIR);
        r(RegSlotPxSEL) := RstValPxSEL and IMPL(RegSlotPxSEL);
        r(RegSlotPxREN) := RstValPxREN and IMPL(RegSlotPxREN);
        r(RegSlotPxAFS) := RstValPxAFS and IMPL(RegSlotPxAFS);
        return r;
    end function;

    constant RSTVAL_OR_GPIO : reg_arr_t := rstValOr;
begin

	PxOUT_out <= PxOUT;
	PxDIR_out <= PxDIR;
	PxREN_out <= PxREN;
	PxSEL_out <= PxSEL;
	PxAFS_out <= PxAFS;

	-- The nibble-per-pin PxAFS register layout only fits 8 pins in one 32-bit register.
	-- Larger ports would need a second AFS register, which is not needed since every port in the SoC is 8 pins.
	-- gpio.rdl describes the EIGHT-pin port, and its implemented-bit masks are
	-- what periph_regs decodes with, so the two agree only at eight. PxAFS is also
	-- the one register wider than the pin count, at a nibble per pin, and eight
	-- nibbles is the whole 32-bit word.
	assert num_pins = 8
		report "GPIO: the register description (hdl/common/regs/rdl/gpio.rdl) is the 8-pin port; num_pins must be 8"
		severity failure;

	-- Alternate-function plane mux: each pin's PxAFS field picks which of the NUM_AFS flattened planes reaches the PxSEL pad mux below.
	af_plane_mux: process(PxAFS, alt_func_out_in, alt_func_dir_in, alt_func_ren_in)
		variable k : natural range 0 to NUM_AFS - 1;
	begin
		for i in 0 to num_pins - 1 loop
			k := to_integer(unsigned(PxAFS((3 * i) + 2 downto 3 * i)));
			af_out(i) <= alt_func_out_in((k * num_pins) + i);
			af_dir(i) <= alt_func_dir_in((k * num_pins) + i);
			af_ren(i) <= alt_func_ren_in((k * num_pins) + i);
		end loop;
	end process;

	-- PxAFS is STORED in the nibble-per-pin readback image, with bit 3 of each
	-- nibble outside IMPL so it stores nothing and reads 0; the 3-bit-per-pin
	-- packing the plane mux and the port want is cut out of it here. The byte
	-- lanes then land where they always did: lane n covers pins 2n and 2n+1.
	gen_afs: for i in 0 to num_pins - 1 generate
		PxAFS((3 * i) + 2 downto 3 * i) <=
			regs_q(RegSlotPxAFS)((4 * i) + 2 downto 4 * i);
	end generate;

	-- The six plain storage registers.
	PxOUT  <= regs_q(RegSlotPxOUT)(num_pins - 1 downto 0);
	PxDIR  <= regs_q(RegSlotPxDIR)(num_pins - 1 downto 0);
	PxSEL  <= regs_q(RegSlotPxSEL)(num_pins - 1 downto 0);
	PxREN  <= regs_q(RegSlotPxREN)(num_pins - 1 downto 0);
	PxIES  <= regs_q(RegSlotPxIES)(num_pins - 1 downto 0);
	PxIE   <= regs_q(RegSlotPxIE)(num_pins - 1 downto 0);
	PxTASK <= regs_q(RegSlotPxTASK)(num_pins - 1 downto 0);

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
    edge_sel_comb <= prt_in xor PxIES;  -- Polarity chosen by the edge select.
    evt_edge_raw <= edge_sel_comb;      -- Raw event-fabric export, pre-mask and pre-sync.

    -- TODO: allow these flags to be polled without interrupts, that is, separate the interrupt enables from the status flags.
    irq <= PxIF; -- The IRQ lines are the interrupt flags themselves.

    -- The pin NEVER reaches a clock pin: prt_in crosses into clk_mem through the
    -- house synchroniser and the edge is detected against a previous-value
    -- register, so an FPGA build infers no clock from a pad and the ASIC flow has
    -- no per-pin gated clock to constrain.
    -- The cost is that an edge narrower than a clk_mem period is not captured and
    -- a flag appears three clk_mem edges after the pin edge. Neither matters for
    -- the wake path: clk_mem is the free-running mclk, which nothing gates.
    u_sync_prt_in : entity work.sync
        generic map (WIDTH => num_pins, DEPTH => 2)
        port map (clk => clk_mem, areset => resetn, d => prt_in, q => prt_in_s2);

    -- PxIES picks which transition of the synchronised pin counts, matching the
    -- event fabric's rising edge of prt_in xor PxIES.
    gen_pin_edge: for i in 0 to num_pins - 1 generate
        pin_edge(i) <= (prt_in_s2(i) and not prt_in_prev(i)) when PxIES(i) = '0'
                  else (prt_in_prev(i) and not prt_in_s2(i));
    end generate;

    -- One flag flop per pin, all on clk_mem. A set coincident with the W1C wins,
    -- as the event fabric's stickies do, so software never loses an edge to its
    -- own clear.
    if_proc: process(clk_mem, resetn)
    begin
        if resetn = '0' then
            prt_in_prev <= (others => '0');
            PxIF        <= (others => '0');
        elsif rising_edge(clk_mem) then
            prt_in_prev <= prt_in_s2;
            for i in 0 to num_pins - 1 loop
                if pin_edge(i) = '1' and PxIE(i) = '1' then
                    PxIF(i) <= '1';
                elsif clr_if(i) = '1' then
                    PxIF(i) <= '0';
                end if;
            end loop;
        end if;
    end process;

    -- Register Memory Interface ----------
    -- One periph_regs instance replaces the slot decode, the byte-lane write case,
    -- the three alias arms, the flag-clear strobe and the registered read mux.
    -- PxOUT is the whole point of the alias hooks: PxOUTS' write-1-to-SET,
    -- PxOUTC's write-1-to-CLEAR and PxOUTT's write-1-to-TOGGLE are three separate
    -- WORDS acting on one storage word, and each arrives here as a mask.
    --
    -- STROBE_HOLD is FALSE: clk_mem free-runs (task_outset and task_outclr act
    -- outside the en gate and need it to), and an alias write must be sampled by
    -- a storage edge AFTER the access, which the one-cycle retirement guarantees
    -- and the held one would not inside a single-edge select window.
    --
    -- The fabric tasks are NOT strobes: they are already one-clk_mem pulses in
    -- this clock domain, so they join the same hw_set / hw_clr masks
    -- combinationally and still land on the edge they arrive, which is what makes
    -- a task win its pins over a coincident CPU write (hardware beats the CPU in
    -- periph_regs' resolution order) and a clear win over a set.
    u_regs: entity work.periph_regs
        generic map (
            NWORDS      => NWORDS,
            RSTVAL      => RSTVAL,
            RSTVAL_OR   => RSTVAL_OR_GPIO,
            IMPL        => IMPL,
            W1C         => W1C,
            WOSET       => WOSET,
            WOT         => WOT,
            PULSE       => PULSE,
            RCLR        => RCLR,
            HWOWN       => HWOWN,
            STROBE_HOLD => false)
        port map (
            ClkMem      => clk_mem,
            resetn      => resetn,
            EnMemPeriph => en,
            WEn         => wen,
            MABPart     => addr_periph,
            wdata       => write_data,
            rdata_out   => read_data,
            regs        => regs_q,
            hw_rd       => hw_rd_s,
            hw_we       => hw_we_s,
            hw_wdata    => hw_wdata_s,
            hw_set      => hw_set_s,
            hw_clr      => hw_clr_s,
            acc_hit     => open,
            rd_strobe   => open,
            wr_strobe   => open,
            wr_pulse    => open,
            w1c_hit     => w1c_s,
            woset_hit   => woset_s,
            wot_hit     => wot_s,
            rd_clr      => open);

    -- The five words that hold no flop here. The three aliases read PxOUT, and
    -- PxOUTC reads it INVERTED, which is what the readback mux has always done.
    -- PxIN and PxIF read clk_mem flops directly: prt_in_s2 is the pin after the
    -- house synchroniser and PxIF is the flag register, both in this domain, so
    -- the word periph_regs' read register captures is one register's value from
    -- one clk_mem edge. PxIN is therefore the pin as it was two clk_mem edges
    -- before the select, where the deleted falling-en latch sampled the raw pad
    -- asynchronously and could return a metastable bit.
    hw_rd_s <= (RegSlotPxIN   => pad(prt_in_s2),
                RegSlotPxOUTS => pad(PxOUT),
                RegSlotPxOUTC => pad(not PxOUT),
                RegSlotPxOUTT => pad(PxOUT),
                RegSlotPxIF   => pad(PxIF),
                others        => (others => '0'));

    -- Consumer tasks: one-clk_mem fabric pulses acting on the PxTASK-selected pins.
    task_set <= pad(PxTASK) when task_outset = '1' else (others => '0');
    task_clr <= pad(PxTASK) when task_outclr = '1' else (others => '0');

    -- The three alias words and the two tasks, onto PxOUT's storage. periph_regs
    -- resolves a coincident access as lane write, then hw_we, then hw_set, then
    -- hw_clr, so a toggle loses to a set, a set loses to a clear, and any of them
    -- beats a CPU write landing on the same edge.
    hw_we_s    <= (RegSlotPxOUT => wot_s(RegSlotPxOUTT), others => (others => '0'));
    hw_wdata_s <= (RegSlotPxOUT => pad(not PxOUT),       others => (others => '0'));
    hw_set_s   <= (RegSlotPxOUT => woset_s(RegSlotPxOUTS) or task_set,
                   others       => (others => '0'));
    hw_clr_s   <= (RegSlotPxOUT => w1c_s(RegSlotPxOUTC) or task_clr,
                   others       => (others => '0'));

    -- PxIF's flops stay here, on clk_mem with the edge detector that sets them,
    -- and periph_regs only reports which flag a 1 was written to.
    clr_if <= w1c_s(RegSlotPxIF)(num_pins - 1 downto 0);

end behavioral;