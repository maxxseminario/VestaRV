-- VestaRV: PINMUX testbench
-- The pin multiplexer at NPADS = 12 and MAXMENU = 4, small enough to drive every pad and every menu slot by hand and still exercise the whole decode: three PMXCFG words of eight nibbles, one PMXIN word, and a four-slot menu per pad.
-- The pad side is the oracle. Every group drives a slot function and a pad level and then grades pmx_out_out / pmx_oen_out / pmx_ren_out and slot_in_out, so the bench proves what the pad does and not merely what the register holds.
-- Pad 0 carries the four policies one per slot: slot 1 push-pull, slot 2 input-only, slot 3 open-drain, slot 4 function-direction-controlled. Pads 1 and 2 carry a short menu, so a code past MENU_LEN must read back and still leave the pad high-Z. Pad 11 is the top nibble of the third PMXCFG word, which is where a packing slip would show.
-- The DUT is a component so default binding resolves it once PINMUX.vhd is analysed.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;

entity PINMUX_tb is
end entity PINMUX_tb;

architecture sim of PINMUX_tb is

    constant PERIOD  : time    := 20 ns;
    constant NPADS   : natural := 12;
    constant MAXMENU : natural := 4;

    -- Word layout at this pad count, the same arithmetic PINMUX.vhd uses.
    constant NINW     : natural := (NPADS + 31) / 32;   -- 1
    constant NSELW    : natural := (NPADS + 7) / 8;     -- 2
    constant W_CAP    : natural := 0;
    constant W_IN0    : natural := 1;
    constant W_CFG0   : natural := 1 + NINW;            -- 2
    constant W_CFG1   : natural := W_CFG0 + 1;          -- 3

    -- Slot-major bit of slot j, pad i, the packing the entity documents.
    function sb_idx(j : natural; i : natural) return natural is
    begin
        return (j * NPADS) + i;
    end function;

    -- One nibble per pad.
    function menuLen(v : natural) return std_logic_vector is
        variable r : std_logic_vector(4 * NPADS - 1 downto 0) := (others => '0');
    begin
        for p in 0 to NPADS - 1 loop
            r((4 * p) + 3 downto 4 * p) := std_logic_vector(to_unsigned(v, 4));
        end loop;
        -- Pad 1 carries two menu entries and pad 2 carries one, so a code past
        -- the pad's own menu has somewhere to be refused.
        r((4 * 1) + 3 downto 4 * 1) := "0010";
        r((4 * 2) + 3 downto 4 * 2) := "0001";
        return r;
    end function;

    -- Policy vectors. Slot 2 (index 1) is input-only on every pad and slot 3
    -- (index 2) is open drain on every pad, so one constant covers the bench.
    function slotMask(j : natural) return std_logic_vector is
        variable r : std_logic_vector(NPADS * MAXMENU - 1 downto 0) := (others => '0');
    begin
        for p in 0 to NPADS - 1 loop
            r(sb_idx(j, p)) := '1';
        end loop;
        return r;
    end function;

    constant MENU_LEN_C : std_logic_vector(4 * NPADS - 1 downto 0) := menuLen(MAXMENU);
    constant INONLY_C   : std_logic_vector(NPADS * MAXMENU - 1 downto 0) := slotMask(1);
    constant OD_C       : std_logic_vector(NPADS * MAXMENU - 1 downto 0) := slotMask(2);
    -- The open-drain slot asks for the pull resistor; nothing else does.
    constant PREN_C     : std_logic_vector(NPADS * MAXMENU - 1 downto 0) := slotMask(2);
    -- Idle high on the two input-bearing slots, low elsewhere, so both
    -- directions of the idle rule are graded.
    constant IDLE_C     : std_logic_vector(NPADS * MAXMENU - 1 downto 0) := slotMask(1) or slotMask(2);

    component PINMUX
        generic
        (
            NPADS          : natural;
            MAXMENU        : natural := 8;
            MENU_LEN       : std_logic_vector := "";
            POL_INONLY     : std_logic_vector := "";
            POL_OD         : std_logic_vector := "";
            POL_REN        : std_logic_vector := "";
            SLOT_IDLE      : std_logic_vector := "";
            PadOUTPosLogic : boolean := true;
            PadOENPosLogic : boolean := true;
            PadRENPosLogic : boolean := true
        );
        port
        (
            resetn      : in  std_logic;
            clk_mem     : in  std_logic;
            en          : in  std_logic;
            wen         : in  std_logic_vector(3 downto 0);
            write_data  : in  std_logic_vector(31 downto 0);
            read_data   : out std_logic_vector(31 downto 0);
            addr_periph : in  std_logic_vector(7 downto 2);
            pmx_in      : in  std_logic_vector(NPADS - 1 downto 0);
            pmx_out_out : out std_logic_vector(NPADS - 1 downto 0);
            pmx_oen_out : out std_logic_vector(NPADS - 1 downto 0);
            pmx_ren_out : out std_logic_vector(NPADS - 1 downto 0);
            slot_out_in : in  std_logic_vector(NPADS * MAXMENU - 1 downto 0);
            slot_oen_in : in  std_logic_vector(NPADS * MAXMENU - 1 downto 0);
            slot_ren_in : in  std_logic_vector(NPADS * MAXMENU - 1 downto 0);
            slot_in_out : out std_logic_vector(NPADS * MAXMENU - 1 downto 0);
            PMXSEL_out  : out std_logic_vector(4 * NPADS - 1 downto 0)
        );
    end component;

    signal clk     : std_logic := '0';
    signal clk_mem : std_logic;
    signal resetn  : std_logic := '0';

    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal read_data : std_logic_vector(31 downto 0);

    signal pmx_in      : std_logic_vector(NPADS - 1 downto 0) := (others => '0');
    signal pmx_out     : std_logic_vector(NPADS - 1 downto 0);
    signal pmx_oen     : std_logic_vector(NPADS - 1 downto 0);
    signal pmx_ren     : std_logic_vector(NPADS - 1 downto 0);
    signal slot_out    : std_logic_vector(NPADS * MAXMENU - 1 downto 0) := (others => '0');
    signal slot_oen    : std_logic_vector(NPADS * MAXMENU - 1 downto 0) := (others => '0');
    signal slot_ren    : std_logic_vector(NPADS * MAXMENU - 1 downto 0) := (others => '0');
    signal slot_in     : std_logic_vector(NPADS * MAXMENU - 1 downto 0);
    signal PMXSEL      : std_logic_vector(4 * NPADS - 1 downto 0);

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

begin

    clk     <= not clk after PERIOD / 2;
    clk_mem <= clk;

    dut : PINMUX
        generic map (
            NPADS          => NPADS,
            MAXMENU        => MAXMENU,
            MENU_LEN       => MENU_LEN_C,
            POL_INONLY     => INONLY_C,
            POL_OD         => OD_C,
            POL_REN        => PREN_C,
            SLOT_IDLE      => IDLE_C,
            PadOUTPosLogic => true,
            PadOENPosLogic => true,
            PadRENPosLogic => true)
        port map (
            resetn      => resetn,
            clk_mem     => clk_mem,
            en          => pbus.en_mem,
            wen         => pbus.wen,
            write_data  => pbus.write_data,
            read_data   => read_data,
            addr_periph => pbus.addr_periph,
            pmx_in      => pmx_in,
            pmx_out_out => pmx_out,
            pmx_oen_out => pmx_oen,
            pmx_ren_out => pmx_ren,
            slot_out_in => slot_out,
            slot_oen_in => slot_oen,
            slot_ren_in => slot_ren,
            slot_in_out => slot_in,
            PMXSEL_out  => PMXSEL);

    -- Watchdog. severity warning, never failure: a failure makes GHDL exit
    -- non-zero and the runner cannot tell a timeout from a graded failure.
    watchdog : process
    begin
        wait for 20 ms;
        if not tb_done then
            report "PINMUX_TB FAIL (WATCHDOG TIMEOUT -- stimulus never finished)"
                severity warning;
            stop;
        end if;
        wait;
    end process watchdog;

    stim_proc : process

        variable rdw : std_logic_vector(31 downto 0);

        procedure reset_pulse is
        begin
            resetn   <= '0';
            pbus     <= PERIPH_BUS_IDLE;
            pmx_in   <= (others => '0');
            slot_out <= (others => '0');
            slot_oen <= (others => '0');
            slot_ren <= (others => '0');
            wait for 6 * PERIOD;
            wait for 1 ns;
            resetn <= '1';
            wait for 4 * PERIOD;
        end procedure;

        -- periph_tb_pkg.bus_write always asserts all four lanes, so it cannot
        -- express a byte lane, and the whole point of a nibble per pad is that
        -- one lane reconfigures exactly two pads.
        procedure bus_write_lanes(slot  : in natural;
                                  lanes : in std_logic_vector(3 downto 0);
                                  data  : in std_logic_vector(31 downto 0)) is
        begin
            wait until clk = '0';
            pbus.addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            pbus.write_data  <= data;
            pbus.wen         <= lanes;
            pbus.en_mem      <= '0';
            wait until clk = '1';
            wait until clk = '0';
            pbus.en_mem <= '1';
            pbus.wen    <= (others => '1');
        end procedure;

        -- Set pad p's select nibble, leaving every other nibble of its word at 0.
        procedure set_sel(pad : in natural; code : in natural) is
            variable w : std_logic_vector(31 downto 0) := (others => '0');
        begin
            w((4 * (pad mod 8)) + 3 downto 4 * (pad mod 8)) :=
                std_logic_vector(to_unsigned(code, 4));
            bus_write(clk, pbus, W_CFG0 + (pad / 8), w);
            wait for 2 * PERIOD;
        end procedure;

        -- Drive one slot function of one pad.
        procedure drive_slot(pad : in natural; j : in natural;
                             o : in std_logic; oe : in std_logic; ren : in std_logic) is
        begin
            slot_out(sb_idx(j, pad)) <= o;
            slot_oen(sb_idx(j, pad)) <= oe;
            slot_ren(sb_idx(j, pad)) <= ren;
            wait for 2 * PERIOD;
        end procedure;

    begin

        -- GROUP G1: RESET DEFAULT. Every pad high-Z, every pull off, every
        -- select nibble 0. This is the whole safety argument of the block.
        report "=== GROUP G1: RESET DEFAULT IS HIGH-Z ===" severity note;
        reset_pulse;

        sb.check_slv("G1 PMXSEL all zero at reset", PMXSEL, (PMXSEL'range => '0'));
        sb.check_slv("G1 pmx_oen deasserted at reset", pmx_oen, (pmx_oen'range => '0'));
        sb.check_slv("G1 pmx_out low at reset", pmx_out, (pmx_out'range => '0'));
        sb.check_slv("G1 pmx_ren off at reset", pmx_ren, (pmx_ren'range => '0'));

        -- Even with every slot function shouting, a zero select leaves the pad alone.
        slot_out <= (others => '1');
        slot_oen <= (others => '1');
        slot_ren <= (others => '1');
        wait for 4 * PERIOD;
        sb.check_slv("G1 pmx_oen still deasserted with every slot driving",
                     pmx_oen, (pmx_oen'range => '0'));
        sb.check_slv("G1 pmx_ren still off with every slot asking",
                     pmx_ren, (pmx_ren'range => '0'));
        slot_out <= (others => '0');
        slot_oen <= (others => '0');
        slot_ren <= (others => '0');
        wait for 2 * PERIOD;

        -- GROUP G2: THE CAPABILITY REGISTER.
        report "=== GROUP G2: PMXCAP ===" severity note;
        bus_read(clk, pbus, read_data, W_CAP, rdw);
        sb.check_slv("G2 PMXCAP.PMXNPADS reads the pad count",
                     rdw(7 downto 0), std_logic_vector(to_unsigned(NPADS, 8)));
        sb.check_slv("G2 PMXCAP.PMXMENU reads the menu depth",
                     rdw(11 downto 8), std_logic_vector(to_unsigned(MAXMENU, 4)));
        sb.check_slv("G2 PMXCAP.PMXREV reads 1",
                     rdw(15 downto 12), x"1");
        sb.check_slv("G2 PMXCAP reserved bits read 0", rdw(31 downto 16), x"0000");

        -- PMXCAP is read-only: a write must not disturb it.
        bus_write(clk, pbus, W_CAP, x"FFFFFFFF");
        bus_read(clk, pbus, read_data, W_CAP, rdw);
        sb.check_slv("G2 PMXCAP ignores a write",
                     rdw(15 downto 0),
                     x"1" & std_logic_vector(to_unsigned(MAXMENU, 4))
                          & std_logic_vector(to_unsigned(NPADS, 8)));

        -- GROUP G3: PUSH-PULL. Slot 1 of pad 0 drives the pad both ways.
        report "=== GROUP G3: PUSH-PULL FUNCTION (SLOT 1) ===" severity note;
        drive_slot(0, 0, '1', '1', '0');
        set_sel(0, 1);
        sb.check_bit("G3 pad 0 drives high", pmx_out(0), '1');
        sb.check_bit("G3 pad 0 output enabled", pmx_oen(0), '1');
        sb.check_bit("G3 pad 0 pull stays off", pmx_ren(0), '0');
        drive_slot(0, 0, '0', '1', '0');
        sb.check_bit("G3 pad 0 follows the function low", pmx_out(0), '0');
        sb.check_bit("G3 pad 0 still enabled", pmx_oen(0), '1');
        -- The function's own enable is honoured on a push-pull slot.
        drive_slot(0, 0, '1', '0', '0');
        sb.check_bit("G3 pad 0 released when the function deasserts its enable",
                     pmx_oen(0), '0');
        -- A neighbour pad must be untouched by any of it.
        sb.check_bit("G3 pad 1 untouched", pmx_oen(1), '0');

        -- The input path: the selected slot sees the pad, the others see idle.
        pmx_in(0) <= '1';
        wait for 2 * PERIOD;
        sb.check_bit("G3 slot 1 of pad 0 sees the pad high", slot_in(sb_idx(0, 0)), '1');
        pmx_in(0) <= '0';
        wait for 2 * PERIOD;
        sb.check_bit("G3 slot 1 of pad 0 sees the pad low", slot_in(sb_idx(0, 0)), '0');
        sb.check_bit("G3 unselected idle-high slot 2 of pad 0 reads 1",
                     slot_in(sb_idx(1, 0)), '1');
        sb.check_bit("G3 unselected idle-low slot 4 of pad 0 reads 0",
                     slot_in(sb_idx(3, 0)), '0');

        -- GROUP G4: INPUT-ONLY. Slot 2 never drives, whatever it asks for.
        report "=== GROUP G4: INPUT-ONLY FUNCTION (SLOT 2) ===" severity note;
        drive_slot(0, 1, '1', '1', '0');
        set_sel(0, 2);
        sb.check_bit("G4 pad 0 never drives on an input-only slot", pmx_oen(0), '0');
        sb.check_bit("G4 pad 0 output held low", pmx_out(0), '0');
        pmx_in(0) <= '1';
        wait for 2 * PERIOD;
        sb.check_bit("G4 slot 2 of pad 0 receives the pad", slot_in(sb_idx(1, 0)), '1');
        sb.check_bit("G4 slot 1 of pad 0 is back to its idle 0", slot_in(sb_idx(0, 0)), '0');
        -- The slot's own resistor request still reaches the pad.
        drive_slot(0, 1, '1', '1', '1');
        sb.check_bit("G4 input-only slot can still ask for the pull", pmx_ren(0), '1');
        drive_slot(0, 1, '1', '1', '0');
        pmx_in(0) <= '0';
        wait for 2 * PERIOD;

        -- GROUP G5: OPEN DRAIN. Slot 3 drives low only and asks for the pull.
        report "=== GROUP G5: OPEN-DRAIN FUNCTION (SLOT 3) ===" severity note;
        drive_slot(0, 2, '1', '0', '0');
        set_sel(0, 3);
        sb.check_bit("G5 pad 0 released on a function 1", pmx_oen(0), '0');
        sb.check_bit("G5 pad 0 pull enabled by policy", pmx_ren(0), '1');
        drive_slot(0, 2, '0', '0', '0');
        sb.check_bit("G5 pad 0 driven on a function 0", pmx_oen(0), '1');
        sb.check_bit("G5 pad 0 drives a low and never a high", pmx_out(0), '0');
        -- The function's own enable is NOT consulted on an open-drain slot: the
        -- data is the enable on a wired-AND bus.
        drive_slot(0, 2, '0', '1', '0');
        sb.check_bit("G5 open drain ignores the function enable", pmx_oen(0), '1');
        drive_slot(0, 2, '1', '1', '0');
        sb.check_bit("G5 open drain still releases on a 1", pmx_oen(0), '0');

        -- GROUP G6: NEGATIVE AND NEGATIVE-LOGIC PADS, and the refused codes.
        report "=== GROUP G6: REFUSED SELECT CODES ===" severity note;
        drive_slot(1, 2, '0', '1', '1');
        drive_slot(1, 3, '1', '1', '1');
        -- Pad 1's MENU_LEN is 2, so code 3 and code 4 are past its menu.
        set_sel(1, 3);
        bus_read(clk, pbus, read_data, W_CFG0, rdw);
        sb.check_slv("G6 a refused code still reads back", rdw(7 downto 4), x"3");
        sb.check_bit("G6 pad 1 stays high-Z on a code past its menu", pmx_oen(1), '0');
        sb.check_bit("G6 pad 1 pull stays off on a refused code", pmx_ren(1), '0');
        sb.check_bit("G6 slot 3 of pad 1 sees its idle, not the pad",
                     slot_in(sb_idx(2, 1)), '1');
        set_sel(1, 4);
        sb.check_bit("G6 pad 1 stays high-Z at code 4 too", pmx_oen(1), '0');
        -- Code 2 is the last entry pad 1 carries, so it must work.
        drive_slot(1, 1, '0', '0', '1');
        set_sel(1, 2);
        sb.check_bit("G6 pad 1 accepts the last code of its menu",
                     pmx_ren(1), '1');
        set_sel(1, 0);
        sb.check_bit("G6 code 0 disables pad 1 again", pmx_ren(1), '0');

        -- Pad 2's menu is one entry long: code 1 works, code 2 does not.
        drive_slot(2, 0, '1', '1', '0');
        drive_slot(2, 1, '1', '1', '1');
        set_sel(2, 1);
        sb.check_bit("G6 pad 2 accepts its only code", pmx_oen(2), '1');
        set_sel(2, 2);
        sb.check_bit("G6 pad 2 refuses code 2", pmx_oen(2), '0');
        set_sel(2, 0);

        -- GROUP G7: THE NIBBLE PACKING AND THE BYTE LANES.
        report "=== GROUP G7: NIBBLE PACKING AND BYTE LANES ===" severity note;
        -- A whole word of codes, then the exported select vector.
        bus_write(clk, pbus, W_CFG0, x"12341234");
        wait for 2 * PERIOD;
        bus_read(clk, pbus, read_data, W_CFG0, rdw);
        sb.check_slv("G7 PMXCFG0 holds every nibble", rdw, x"12341234");
        sb.check_slv("G7 pad 0 nibble is the low nibble of PMXCFG0",
                     PMXSEL(3 downto 0), x"4");
        sb.check_slv("G7 pad 7 nibble is the top nibble of PMXCFG0",
                     PMXSEL((4 * 7) + 3 downto 4 * 7), x"1");
        -- Lane 1 covers pads 2 and 3 and must disturb no other pad.
        bus_write_lanes(W_CFG0, "1101", x"0000AA00");
        wait for 2 * PERIOD;
        bus_read(clk, pbus, read_data, W_CFG0, rdw);
        sb.check_slv("G7 a lane write reconfigures exactly two pads",
                     rdw, x"1234AA34");
        -- Pad 11 is the top nibble of the second select word, the far corner of
        -- the packing.
        bus_write(clk, pbus, W_CFG1, x"0000F000");
        wait for 2 * PERIOD;
        sb.check_slv("G7 pad 11 is nibble 3 of PMXCFG1",
                     PMXSEL((4 * 11) + 3 downto 4 * 11), x"F");
        sb.check_bit("G7 pad 11 is high-Z on the reserved code 15", pmx_oen(11), '0');
        drive_slot(11, 0, '1', '1', '0');
        bus_write(clk, pbus, W_CFG1, x"00001000");
        wait for 2 * PERIOD;
        sb.check_bit("G7 pad 11 takes slot 1 of its own menu", pmx_oen(11), '1');
        sb.check_bit("G7 pad 11 drives the level slot 1 asked for", pmx_out(11), '1');
        -- Clear both select words before the readback group.
        bus_write(clk, pbus, W_CFG0, x"00000000");
        bus_write(clk, pbus, W_CFG1, x"00000000");
        wait for 2 * PERIOD;

        -- GROUP G8: THE PAD READBACK.
        report "=== GROUP G8: PMXIN ===" severity note;
        pmx_in <= "101010101010";
        wait for 6 * PERIOD;   -- two synchroniser edges plus margin
        bus_read(clk, pbus, read_data, W_IN0, rdw);
        sb.check_slv("G8 PMXIN0 reads the pad levels",
                     rdw(NPADS - 1 downto 0), "101010101010");
        sb.check_slv("G8 PMXIN0 bits above the pad count read 0",
                     rdw(31 downto NPADS), (31 downto NPADS => '0'));
        -- The readback is independent of the selection: a disabled pad is still
        -- observable, which is what makes the block debuggable.
        sb.check_slv("G8 every pad is disabled while PMXIN reads them",
                     PMXSEL, (PMXSEL'range => '0'));
        pmx_in <= (others => '0');
        wait for 6 * PERIOD;
        bus_read(clk, pbus, read_data, W_IN0, rdw);
        sb.check_slv("G8 PMXIN0 follows the pads back down", rdw, x"00000000");
        -- PMXIN is read-only.
        bus_write(clk, pbus, W_IN0, x"FFFFFFFF");
        bus_read(clk, pbus, read_data, W_IN0, rdw);
        sb.check_slv("G8 PMXIN0 ignores a write", rdw, x"00000000");

        -- GROUP G9: RESET AGAIN, after the pads have been configured.
        report "=== GROUP G9: RESET RETURNS EVERY PAD TO HIGH-Z ===" severity note;
        drive_slot(5, 0, '1', '1', '1');
        set_sel(5, 1);
        sb.check_bit("G9 pad 5 is driving before the reset", pmx_oen(5), '1');
        reset_pulse;
        sb.check_slv("G9 PMXSEL back to zero", PMXSEL, (PMXSEL'range => '0'));
        sb.check_slv("G9 every pad high-Z again", pmx_oen, (pmx_oen'range => '0'));
        bus_read(clk, pbus, read_data, W_CFG0, rdw);
        sb.check_slv("G9 PMXCFG0 reads 0 after the reset", rdw, x"00000000");

        -- GROUP G-NEG: NEGATIVE CONTROL, mandatory and LAST.
        -- Exactly ONE deliberately wrong expected value, so the scoreboard
        -- proves it can fail.
        report "=== GROUP G-NEG: NEGATIVE CONTROL ===" severity note;
        drive_slot(3, 0, '1', '1', '0');
        set_sel(3, 1);
        sb.check_bit("NEGATIVE CONTROL: wrong expected pmx_oen on a driving pad (must FAIL)",
                     pmx_oen(3), '0');   -- the actual value is '1', so this expectation is deliberately wrong

        -- Final verdict: sb.errors must be EXACTLY 1, the negative control.
        wait for 1 us;
        sb.report_summary("PINMUX TB");

        if sb.errors = 1 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   PINMUX_TB PASS (1 expected negative-control failure)" & LF &
                "    ##   PINMUX TB:  ALL CHECKS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   PINMUX_TB FAIL (expected exactly 1 failure [negative control], got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        tb_done <= true;
        stop;
        wait;
    end process stim_proc;

end architecture sim;
