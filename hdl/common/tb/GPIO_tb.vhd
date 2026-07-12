-------------------------------------------------------------------------------
-- GPIO_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the GPIO peripheral
-- (hdl/myshkin/periph/GPIO.vhd), configured like the SoC's GPIO1 port:
--   num_pins = 8, PadOUTPosLogic = true, PadDIRPosLogic = false,
--   PadRENPosLogic = false, all reset values = 0.
--
-- Drives the peripheral register bus + pad inputs directly and checks the
-- register file, the atomic OUT set/clear/toggle aliases, the pad output mux
-- (GPIO vs alternate function) including the DIR/REN logic-level inversion,
-- the PxIN read path, and per-pin edge interrupts. All checks are assertions;
-- failures are warnings (so the whole suite runs) and a final banner reports
-- the verdict before std.env.stop halts the sim.
--
-- Bus contract (shared with the other periph benches; see tb/CLAUDE.md):
--   * en  is ACTIVE-LOW ('0' selects the GPIO)
--   * wen is ACTIVE-LOW per byte lane (only wen(0) used for 8 pins)
--   * clk_mem = clk while en='0' ; writes/reads register on rising_edge
--   * PxIN and PxIF read a snapshot taken on the falling edge of en
--
-- Pad polarity for this configuration (SEL(i)=0 => GPIO, =1 => alt function):
--   prt_out_out =     reg/alt   (PadOUTPosLogic = true)
--   prt_dir_out = not reg/alt   (PadDIRPosLogic = false)
--   prt_ren_out = not reg/alt   (PadRENPosLogic = false)
--
-- Multi-AF (PxAFS): the alt-function inputs carry GPIO_NUM_AFS flattened
-- planes (plane k, pin i at bit k*num_pins+i). When SEL(i)='1' the pin drives
-- the plane selected by its PxAFS field (a nibble per pin, low 3 bits used).
-- Group 7b proves the plane mux, the nibble readback (bit 3 reserved), the
-- byte-lane write masking, and that AFS is a don't-care while SEL(i)='0'.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.constants.all;
use work.MemoryMap.all;

entity GPIO_tb is
end entity GPIO_tb;

architecture sim of GPIO_tb is

    constant NUM_PINS   : natural := 8;
    constant CLK_PERIOD : time    := 50 ns;

    -- Must match the generic map below (used to predict pad outputs)
    constant OUT_POS : boolean := true;
    constant DIR_POS : boolean := false;
    constant REN_POS : boolean := false;

    subtype  pinvec is std_logic_vector(NUM_PINS - 1 downto 0);
    subtype  afvec  is std_logic_vector(GPIO_NUM_AFS * NUM_PINS - 1 downto 0);

    -- TB-side model of the per-pin AF plane selection (mirrors PxAFS)
    type afs_array is array (0 to NUM_PINS - 1) of natural;
    constant AFS_ZERO : afs_array := (others => 0);

    -- DUT bus / system
    signal clk         : std_logic := '0';
    signal clk_mem     : std_logic := '0';
    signal resetn      : std_logic := '0';
    signal irq         : pinvec;

    signal en          : std_logic := '1';                       -- inactive high
    signal wen         : std_logic_vector(3 downto 0) := (others => '1');
    signal addr_periph : std_logic_vector(7 downto 2) := (others => '0');
    signal write_data  : word := (others => '0');
    signal read_data   : word;

    -- Pad library interface
    signal prt_in      : pinvec := (others => '0');
    signal prt_out_out : pinvec;
    signal prt_dir_out : pinvec;
    signal prt_ren_out : pinvec;

    -- Register-value outputs
    signal PxOUT_out   : pinvec;
    signal PxDIR_out   : pinvec;
    signal PxREN_out   : pinvec;
    signal PxSEL_out   : pinvec;
    signal PxAFS_out   : std_logic_vector(3 * NUM_PINS - 1 downto 0);

    -- Alternate-function drivers (GPIO_NUM_AFS flattened planes)
    signal alt_func_out_in : afvec := (others => '0');
    signal alt_func_dir_in : afvec := (others => '0');
    signal alt_func_ren_in : afvec := (others => '0');

    -- Human-readable value for failure messages
    function img(v : std_logic_vector) return string is
    begin
        if is_x(v) then
            return "X";
        else
            return integer'image(to_integer(unsigned(v)));
        end if;
    end function;

    -- Predict a pad output vector from the source register, the alt-function
    -- planes, the SEL mux, the per-pin AF plane selection, and the pad logic
    -- polarity.
    function pad_route(reg : pinvec; alt : afvec; sel : pinvec;
                       afs : afs_array; pos_logic : boolean) return pinvec is
        variable r : pinvec;
    begin
        for i in reg'range loop
            if sel(i) = '0' then
                r(i) := reg(i);
            else
                r(i) := alt((afs(i) * NUM_PINS) + i);
            end if;
            if not pos_logic then
                r(i) := not r(i);
            end if;
        end loop;
        return r;
    end function;

begin

    clk     <= not clk after CLK_PERIOD / 2;
    clk_mem <= clk when en = '0' else '0';

    dut : entity work.GPIO
        generic map (
            num_pins       => NUM_PINS,
            PadOUTPosLogic => OUT_POS,
            PadDIRPosLogic => DIR_POS,
            PadRENPosLogic => REN_POS,
            RstValPxOUT    => (others => '0'),
            RstValPxDIR    => (others => '0'),
            RstValPxSEL    => (others => '0'),
            RstValPxREN    => (others => '0'),
            RstValPxAFS    => (others => '0')
        )
        port map (
            resetn          => resetn,
            irq             => irq,
            clk_mem         => clk_mem,
            en              => en,
            wen             => wen,
            write_data      => write_data,
            read_data       => read_data,
            addr_periph     => addr_periph,
            prt_in          => prt_in,
            prt_out_out     => prt_out_out,
            prt_dir_out     => prt_dir_out,
            prt_ren_out     => prt_ren_out,
            PxOUT_out       => PxOUT_out,
            PxDIR_out       => PxDIR_out,
            PxREN_out       => PxREN_out,
            PxSEL_out       => PxSEL_out,
            PxAFS_out       => PxAFS_out,
            alt_func_out_in => alt_func_out_in,
            alt_func_dir_in => alt_func_dir_in,
            alt_func_ren_in => alt_func_ren_in
        );

    stim_proc : process

        variable error_count : natural := 0;
        variable rdw         : word;

        procedure check_slv(tag : in string;
                            got : in std_logic_vector;
                            exp : in std_logic_vector) is
        begin
            if got = exp then
                report "PASS: " & tag severity note;
            else
                error_count := error_count + 1;
                assert false
                    report "FAIL: " & tag &
                           " (expected " & img(exp) & ", got " & img(got) & ")"
                    severity warning;
            end if;
        end procedure;

        procedure check_bit(tag : in string;
                            got : in std_logic;
                            exp : in std_logic) is
        begin
            if got = exp then
                report "PASS: " & tag severity note;
            else
                error_count := error_count + 1;
                assert false
                    report "FAIL: " & tag &
                           " (expected " & std_logic'image(exp) &
                           ", got " & std_logic'image(got) & ")"
                    severity warning;
            end if;
        end procedure;

        procedure bus_write(slot : in natural;
                            data : in std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(clk);
            addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            write_data  <= data;
            wen         <= (others => '0');
            en          <= '0';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            en          <= '1';
            wen         <= (others => '1');
        end procedure;

        -- write an 8-bit value into the low byte
        procedure bus_write8(slot : in natural; val : in pinvec) is
            variable w : word := (others => '0');
        begin
            w(NUM_PINS - 1 downto 0) := val;
            bus_write(slot, w);
        end procedure;

        procedure bus_read(slot : in natural;
                           data : out std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(clk);
            addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            en          <= '0';                 -- falling edge snapshots PxIN/PxIF
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            data := read_data;
            en          <= '1';
        end procedure;

        -- Verify the three pad outputs against the predicted routing for the
        -- current PxOUT/PxDIR/PxREN, SEL, per-pin AF plane selection, and
        -- alt-function inputs.
        procedure check_pads(tag : in string;
                             pxout, pxdir, pxren, sel : in pinvec;
                             afs : in afs_array := AFS_ZERO) is
        begin
            check_slv(tag & ": prt_out_out",
                      prt_out_out, pad_route(pxout, alt_func_out_in, sel, afs, OUT_POS));
            check_slv(tag & ": prt_dir_out",
                      prt_dir_out, pad_route(pxdir, alt_func_dir_in, sel, afs, DIR_POS));
            check_slv(tag & ": prt_ren_out",
                      prt_ren_out, pad_route(pxren, alt_func_ren_in, sel, afs, REN_POS));
        end procedure;

        -- write with an explicit byte-lane mask (lanes = wen, ACTIVE LOW)
        procedure bus_write_lanes(slot  : in natural;
                                  data  : in std_logic_vector(31 downto 0);
                                  lanes : in std_logic_vector(3 downto 0)) is
        begin
            wait until falling_edge(clk);
            addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            write_data  <= data;
            wen         <= lanes;
            en          <= '0';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            en          <= '1';
            wen         <= (others => '1');
        end procedure;

    begin
        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------
        resetn <= '0';
        en     <= '1';
        wen    <= (others => '1');
        prt_in <= (others => '0');
        wait for 4 * CLK_PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 4 * CLK_PERIOD;

        ----------------------------------------------------------------
        -- GROUP 1: reset / default state
        ----------------------------------------------------------------
        report "=== GROUP 1: reset & defaults ===" severity note;

        check_slv("irq cleared at reset", irq, (NUM_PINS - 1 downto 0 => '0'));

        bus_read(RegSlotPxOUT, rdw);
        check_slv("PxOUT resets to 0", rdw(NUM_PINS - 1 downto 0), x"00");
        bus_read(RegSlotPxDIR, rdw);
        check_slv("PxDIR resets to 0", rdw(NUM_PINS - 1 downto 0), x"00");
        bus_read(RegSlotPxSEL, rdw);
        check_slv("PxSEL resets to 0", rdw(NUM_PINS - 1 downto 0), x"00");
        bus_read(RegSlotPxREN, rdw);
        check_slv("PxREN resets to 0", rdw(NUM_PINS - 1 downto 0), x"00");
        bus_read(RegSlotPxIE, rdw);
        check_slv("PxIE resets to 0", rdw(NUM_PINS - 1 downto 0), x"00");
        bus_read(RegSlotPxIES, rdw);
        check_slv("PxIES resets to 0", rdw(NUM_PINS - 1 downto 0), x"00");
        bus_read(RegSlotPxAFS, rdw);
        check_slv("PxAFS resets to 0", rdw, x"00000000");

        -- With everything 0 and SEL=0: out=0, dir/ren inverted -> all 1
        check_slv("reset PxOUT_out", PxOUT_out, x"00");
        check_pads("reset", x"00", x"00", x"00", x"00");

        ----------------------------------------------------------------
        -- GROUP 2: PxOUT write / read / pad drive
        ----------------------------------------------------------------
        report "=== GROUP 2: PxOUT ===" severity note;

        bus_write8(RegSlotPxOUT, x"A5");
        bus_read(RegSlotPxOUT, rdw);
        check_slv("PxOUT readback 0xA5", rdw(NUM_PINS - 1 downto 0), x"A5");
        check_slv("PxOUT_out mirror 0xA5", PxOUT_out, x"A5");
        check_pads("PxOUT=A5", x"A5", x"00", x"00", x"00");

        ----------------------------------------------------------------
        -- GROUP 3: atomic OUT set / clear / toggle aliases
        ----------------------------------------------------------------
        report "=== GROUP 3: OUT set/clear/toggle ===" severity note;

        bus_write8(RegSlotPxOUT, x"0F");                 -- known base
        bus_write8(RegSlotPxOUTS, x"30");                -- set bits 4,5
        bus_read(RegSlotPxOUT, rdw);
        check_slv("PxOUTS sets bits (0F|30=3F)", rdw(NUM_PINS - 1 downto 0), x"3F");

        bus_write8(RegSlotPxOUTC, x"03");                -- clear bits 0,1
        bus_read(RegSlotPxOUT, rdw);
        check_slv("PxOUTC clears bits (3F&~03=3C)", rdw(NUM_PINS - 1 downto 0), x"3C");

        bus_write8(RegSlotPxOUTT, x"FF");                -- toggle all
        bus_read(RegSlotPxOUT, rdw);
        check_slv("PxOUTT toggles (3C^FF=C3)", rdw(NUM_PINS - 1 downto 0), x"C3");

        -- read-side quirks: OUTS/OUTT read PxOUT, OUTC reads inverted PxOUT
        bus_read(RegSlotPxOUTS, rdw);
        check_slv("PxOUTS reads PxOUT (C3)", rdw(NUM_PINS - 1 downto 0), x"C3");
        bus_read(RegSlotPxOUTT, rdw);
        check_slv("PxOUTT reads PxOUT (C3)", rdw(NUM_PINS - 1 downto 0), x"C3");
        bus_read(RegSlotPxOUTC, rdw);
        check_slv("PxOUTC reads ~PxOUT (3C)", rdw(NUM_PINS - 1 downto 0), x"3C");

        -- restore a clean PxOUT
        bus_write8(RegSlotPxOUT, x"00");

        ----------------------------------------------------------------
        -- GROUP 4: PxDIR (neg-logic pad direction)
        ----------------------------------------------------------------
        report "=== GROUP 4: PxDIR ===" severity note;

        bus_write8(RegSlotPxDIR, x"C3");
        bus_read(RegSlotPxDIR, rdw);
        check_slv("PxDIR readback 0xC3", rdw(NUM_PINS - 1 downto 0), x"C3");
        check_slv("PxDIR_out mirror 0xC3", PxDIR_out, x"C3");
        -- prt_dir_out should be the inverse (neg logic)
        check_slv("prt_dir_out = ~PxDIR (3C)", prt_dir_out, x"3C");
        check_pads("PxDIR=C3", x"00", x"C3", x"00", x"00");
        bus_write8(RegSlotPxDIR, x"00");

        ----------------------------------------------------------------
        -- GROUP 5: PxREN (neg-logic resistor enable)
        ----------------------------------------------------------------
        report "=== GROUP 5: PxREN ===" severity note;

        bus_write8(RegSlotPxREN, x"5A");
        bus_read(RegSlotPxREN, rdw);
        check_slv("PxREN readback 0x5A", rdw(NUM_PINS - 1 downto 0), x"5A");
        check_slv("PxREN_out mirror 0x5A", PxREN_out, x"5A");
        check_slv("prt_ren_out = ~PxREN (A5)", prt_ren_out, x"A5");
        bus_write8(RegSlotPxREN, x"00");

        ----------------------------------------------------------------
        -- GROUP 6: PxIN read path
        ----------------------------------------------------------------
        report "=== GROUP 6: PxIN ===" severity note;

        prt_in <= x"96";
        wait for 2 * CLK_PERIOD;
        bus_read(RegSlotPxIN, rdw);
        check_slv("PxIN reads pin levels 0x96", rdw(NUM_PINS - 1 downto 0), x"96");
        prt_in <= x"69";
        wait for 2 * CLK_PERIOD;
        bus_read(RegSlotPxIN, rdw);
        check_slv("PxIN reads pin levels 0x69", rdw(NUM_PINS - 1 downto 0), x"69");
        prt_in <= (others => '0');
        wait for 2 * CLK_PERIOD;

        ----------------------------------------------------------------
        -- GROUP 7: alternate-function mux (PxSEL)
        ----------------------------------------------------------------
        report "=== GROUP 7: alt-function mux ===" severity note;

        -- Set distinct GPIO-reg values and alt-function values, then prove the
        -- per-pin SEL bit routes each pad to the right source.
        bus_write8(RegSlotPxOUT, x"0F");
        bus_write8(RegSlotPxDIR, x"00");
        bus_write8(RegSlotPxREN, x"00");
        alt_func_out_in(NUM_PINS - 1 downto 0) <= x"A0";   -- plane 0 (AF0)
        alt_func_dir_in(NUM_PINS - 1 downto 0) <= x"50";
        alt_func_ren_in(NUM_PINS - 1 downto 0) <= x"30";
        wait for 2 * CLK_PERIOD;

        -- All GPIO (SEL=0): pads follow Px registers
        bus_write8(RegSlotPxSEL, x"00");
        wait for 2 * CLK_PERIOD;
        check_pads("SEL=00 (all GPIO)", x"0F", x"00", x"00", x"00");

        -- All alt (SEL=FF): pads follow alt-function inputs, Px ignored
        bus_write8(RegSlotPxSEL, x"FF");
        wait for 2 * CLK_PERIOD;
        check_pads("SEL=FF (all alt)", x"0F", x"00", x"00", x"FF");

        -- Mixed: upper nibble alt, lower nibble GPIO
        bus_write8(RegSlotPxSEL, x"F0");
        wait for 2 * CLK_PERIOD;
        check_pads("SEL=F0 (mixed)", x"0F", x"00", x"00", x"F0");

        -- restore GPIO mode
        bus_write8(RegSlotPxSEL, x"00");
        alt_func_out_in <= (others => '0');
        alt_func_dir_in <= (others => '0');
        alt_func_ren_in <= (others => '0');
        bus_write8(RegSlotPxOUT, x"00");

        ----------------------------------------------------------------
        -- GROUP 7b: multi-AF plane mux (PxAFS)
        ----------------------------------------------------------------
        report "=== GROUP 7b: multi-AF plane mux (PxAFS) ===" severity note;

        -- Distinct pattern in every plane so a plane-select error is visible
        alt_func_out_in(7 downto 0)   <= x"01";  -- plane 0 (AF0)
        alt_func_out_in(15 downto 8)  <= x"23";  -- plane 1
        alt_func_out_in(23 downto 16) <= x"45";  -- plane 2
        alt_func_out_in(31 downto 24) <= x"67";  -- plane 3
        alt_func_out_in(39 downto 32) <= x"89";  -- plane 4
        alt_func_out_in(47 downto 40) <= x"AB";  -- plane 5
        alt_func_out_in(55 downto 48) <= x"CD";  -- plane 6
        alt_func_out_in(63 downto 56) <= x"EF";  -- plane 7
        alt_func_dir_in(7 downto 0)   <= x"FE";
        alt_func_dir_in(15 downto 8)  <= x"DC";
        alt_func_dir_in(23 downto 16) <= x"BA";
        alt_func_dir_in(31 downto 24) <= x"98";
        alt_func_dir_in(39 downto 32) <= x"76";
        alt_func_dir_in(47 downto 40) <= x"54";
        alt_func_dir_in(55 downto 48) <= x"32";
        alt_func_dir_in(63 downto 56) <= x"10";
        alt_func_ren_in(7 downto 0)   <= x"11";
        alt_func_ren_in(15 downto 8)  <= x"22";
        alt_func_ren_in(23 downto 16) <= x"44";
        alt_func_ren_in(31 downto 24) <= x"88";
        alt_func_ren_in(39 downto 32) <= x"33";
        alt_func_ren_in(47 downto 40) <= x"66";
        alt_func_ren_in(55 downto 48) <= x"CC";
        alt_func_ren_in(63 downto 56) <= x"99";
        wait for 2 * CLK_PERIOD;

        -- Pin i selects plane i (nibble per pin), readback must match
        bus_write(RegSlotPxAFS, x"76543210");
        bus_read(RegSlotPxAFS, rdw);
        check_slv("PxAFS readback 0x76543210", rdw, x"76543210");
        check_slv("PxAFS_out packed 3-bit export", PxAFS_out,
                  std_logic_vector'("111110101100011010001000"));

        -- AFS is a don't-care while SEL=0: pads still follow the GPIO regs
        bus_write8(RegSlotPxOUT, x"3C");
        check_pads("SEL=00 ignores AFS", x"3C", x"00", x"00", x"00",
                   (0, 1, 2, 3, 4, 5, 6, 7));

        -- All pins alt: pin i must drive plane i
        bus_write8(RegSlotPxSEL, x"FF");
        wait for 2 * CLK_PERIOD;
        check_slv("PxSEL_out export", PxSEL_out, x"FF");
        check_pads("SEL=FF, AFS=(0..7)", x"3C", x"00", x"00", x"FF",
                   (0, 1, 2, 3, 4, 5, 6, 7));

        -- Reversed plane selection, mixed SEL (upper nibble GPIO)
        bus_write(RegSlotPxAFS, x"01234567");
        wait for 2 * CLK_PERIOD;
        check_pads("SEL=0F, AFS=(7..0)", x"3C", x"00", x"00", x"FF",
                   (7, 6, 5, 4, 3, 2, 1, 0));
        bus_write8(RegSlotPxSEL, x"0F");
        wait for 2 * CLK_PERIOD;
        check_pads("SEL=0F mixed, AFS=(7..0)", x"3C", x"00", x"00", x"0F",
                   (7, 6, 5, 4, 3, 2, 1, 0));

        -- Reserved nibble bit 3 reads back 0
        bus_write(RegSlotPxAFS, x"FFFFFFFF");
        bus_read(RegSlotPxAFS, rdw);
        check_slv("PxAFS nibble bit3 reserved (FFFFFFFF -> 77777777)",
                  rdw, x"77777777");

        -- Byte-lane write masking: only lane 1 (pins 2,3) may change
        bus_write_lanes(RegSlotPxAFS, x"00000000", "1101");
        bus_read(RegSlotPxAFS, rdw);
        check_slv("PxAFS byte-lane masked write", rdw, x"77770077");

        -- restore GPIO mode
        bus_write(RegSlotPxAFS, x"00000000");
        bus_write8(RegSlotPxSEL, x"00");
        alt_func_out_in <= (others => '0');
        alt_func_dir_in <= (others => '0');
        alt_func_ren_in <= (others => '0');
        bus_write8(RegSlotPxOUT, x"00");
        wait for 2 * CLK_PERIOD;

        ----------------------------------------------------------------
        -- GROUP 8: rising-edge interrupt (PxIES=0)
        ----------------------------------------------------------------
        report "=== GROUP 8: rising-edge interrupt ===" severity note;

        prt_in <= (others => '0');                       -- idle low
        bus_write8(RegSlotPxIES, x"00");                 -- low-to-high
        bus_write8(RegSlotPxIE,  x"01");                 -- enable pin 0
        wait for 2 * CLK_PERIOD;
        check_bit("no spurious IRQ before edge", irq(0), '0');

        prt_in(0) <= '1';                                -- rising edge on pin 0
        wait for 4 * CLK_PERIOD;
        check_bit("irq(0) set on rising edge", irq(0), '1');
        bus_read(RegSlotPxIF, rdw);
        check_bit("PxIF(0) set on rising edge", rdw(0), '1');

        bus_write8(RegSlotPxIF, x"01");                  -- write 1 clears flag
        wait for 2 * CLK_PERIOD;
        check_bit("irq(0) cleared by PxIF write", irq(0), '0');
        bus_read(RegSlotPxIF, rdw);
        check_bit("PxIF(0) cleared", rdw(0), '0');

        bus_write8(RegSlotPxIE, x"00");                  -- disable
        prt_in <= (others => '0');
        wait for 2 * CLK_PERIOD;

        ----------------------------------------------------------------
        -- GROUP 9: falling-edge interrupt (PxIES=1)
        ----------------------------------------------------------------
        report "=== GROUP 9: falling-edge interrupt ===" severity note;

        prt_in(1) <= '1';                                -- idle high for pin 1
        bus_write8(RegSlotPxIES, x"02");                 -- pin 1 high-to-low
        bus_write8(RegSlotPxIE,  x"02");                 -- enable pin 1
        wait for 2 * CLK_PERIOD;
        check_bit("no spurious IRQ before edge", irq(1), '0');

        prt_in(1) <= '0';                                -- falling edge on pin 1
        wait for 4 * CLK_PERIOD;
        check_bit("irq(1) set on falling edge", irq(1), '1');
        bus_read(RegSlotPxIF, rdw);
        check_bit("PxIF(1) set on falling edge", rdw(1), '1');

        bus_write8(RegSlotPxIF, x"02");                  -- clear
        wait for 2 * CLK_PERIOD;
        check_bit("irq(1) cleared", irq(1), '0');

        bus_write8(RegSlotPxIE, x"00");
        bus_write8(RegSlotPxIES, x"00");
        prt_in <= (others => '0');
        wait for 2 * CLK_PERIOD;

        ----------------------------------------------------------------
        -- GROUP 10: interrupt masking (PxIE=0)
        ----------------------------------------------------------------
        report "=== GROUP 10: interrupt masking ===" severity note;

        bus_write8(RegSlotPxIES, x"00");                 -- rising-edge
        bus_write8(RegSlotPxIE,  x"00");                 -- all disabled
        bus_write8(RegSlotPxIF,  x"FF");                 -- ensure flags clear
        wait for 2 * CLK_PERIOD;
        prt_in(2) <= '1';                                -- edge on a masked pin
        wait for 4 * CLK_PERIOD;
        check_bit("masked pin raises no IRQ", irq(2), '0');
        bus_read(RegSlotPxIF, rdw);
        check_bit("masked pin sets no PxIF", rdw(2), '0');
        prt_in <= (others => '0');

        ----------------------------------------------------------------
        -- Final verdict
        ----------------------------------------------------------------
        wait for 1 us;
        if error_count = 0 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##                                              ##" & LF &
                "    ##        GPIO TB:  ALL CHECKS PASSED           ##" & LF &
                "    ##                                              ##" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!                                              !!" & LF &
                "    !!   GPIO TB:  " & integer'image(error_count) &
                       " CHECK(S) FAILED" & LF &
                "    !!                                              !!" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        stop;
        wait;
    end process;

end architecture sim;
