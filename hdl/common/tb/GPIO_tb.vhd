/* GPIO_tb: standalone, self-checking bench for the GPIO peripheral, deliberately MINIMAL and TAP-FOCUSED.
   PxSEL/PxAFS alt-function muxing and the PxIE/PxIF edge-interrupt machinery are out of scope here.
   Taps under test: evt_edge_raw, the purely combinational PRE-MASK edge vector prt_in xor PxIES with PxIE NEVER consulted, sampled off the DUT port and never off a DUT internal; task_outset and task_outclr, one-clk_mem pulses that set or clear the PxTASK-selected PxOUT bits OUTSIDE the en gate; and PxTASK itself, an RW register at LOCAL slot 12, one bit per pin, resetting to 0.
   CLR wins a same-cycle set-plus-clear, and a task wins its PxTASK pins over a coincident CPU PxOUT write, since the register write lands first in program order and the task blocks then overwrite only their own pins.
   Compiles into its OWN library, gpio_lib, alongside hdl/common's constants, MemoryMap, ClkGate and GPIO: GPIO.vhd needs MemoryMap.RegSlotPxAFS and GPIO_NUM_AFS, which the MemoryMap shared by the rest of this suite does not carry. */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;
use work.MemoryMap.all;

entity GPIO_tb is
end entity GPIO_tb;

architecture sim of GPIO_tb is

    constant PERIOD   : time    := 20 ns;   -- free-running reference clock
    constant NUM_PINS : natural := 8;

    -- The task-pin slot is a GPIO-local constant, not exported via MemoryMap.vhd, so the bench hardcodes it too.
    constant RegSlotPxTASK : natural := 12;

    -- The DUT is declared as a component so default binding resolves it once GPIO.vhd is analyzed into gpio_lib.
    -- The RTL is owned elsewhere and is never edited from this bench.
    component GPIO is
        generic (
            num_pins       : natural;
            PadOUTPosLogic : boolean;
            PadDIRPosLogic : boolean;
            PadRENPosLogic : boolean;
            RstValPxOUT    : std_logic_vector(31 downto 0) := (others => '0');
            RstValPxDIR    : std_logic_vector(31 downto 0) := (others => '0');
            RstValPxSEL    : std_logic_vector(31 downto 0) := (others => '0');
            RstValPxREN    : std_logic_vector(31 downto 0) := (others => '0');
            RstValPxAFS    : std_logic_vector(31 downto 0) := (others => '0')
        );
        port (
            resetn      : in  std_logic;
            irq         : out std_logic_vector(num_pins - 1 downto 0);

            clk_mem     : in  std_logic;
            en          : in  std_logic;
            wen         : in  std_logic_vector(3 downto 0);
            write_data  : in  std_logic_vector(31 downto 0);
            read_data   : out std_logic_vector(31 downto 0);
            addr_periph : in  std_logic_vector(7 downto 2);

            prt_in      : in  std_logic_vector(num_pins - 1 downto 0);
            prt_out_out : out std_logic_vector(num_pins - 1 downto 0);
            prt_dir_out : out std_logic_vector(num_pins - 1 downto 0);
            prt_ren_out : out std_logic_vector(num_pins - 1 downto 0);

            PxOUT_out   : out std_logic_vector(num_pins - 1 downto 0);
            PxDIR_out   : out std_logic_vector(num_pins - 1 downto 0);
            PxREN_out   : out std_logic_vector(num_pins - 1 downto 0);
            PxSEL_out   : out std_logic_vector(num_pins - 1 downto 0);
            PxAFS_out   : out std_logic_vector(3 * num_pins - 1 downto 0);

            alt_func_out_in : in std_logic_vector(GPIO_NUM_AFS * num_pins - 1 downto 0);
            alt_func_dir_in : in std_logic_vector(GPIO_NUM_AFS * num_pins - 1 downto 0);
            alt_func_ren_in : in std_logic_vector(GPIO_NUM_AFS * num_pins - 1 downto 0);

            evt_edge_raw : out std_logic_vector(num_pins - 1 downto 0);
            task_outset  : in  std_logic := '0';
            task_outclr  : in  std_logic := '0'
        );
    end component;

    -- ---- clocks and reset --------------------------------------------------
    signal clk     : std_logic := '0';
    signal clk_mem : std_logic;   -- free-running, since task_outset/task_outclr act outside en
    signal resetn  : std_logic := '0';

    -- ---- register bus ------------------------------------------------------
    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal read_data : std_logic_vector(31 downto 0);

    -- ---- interrupts and pads -----------------------------------------------
    signal irq         : std_logic_vector(NUM_PINS - 1 downto 0);
    signal prt_in       : std_logic_vector(NUM_PINS - 1 downto 0) := (others => '0');
    signal prt_out_out  : std_logic_vector(NUM_PINS - 1 downto 0);
    signal prt_dir_out  : std_logic_vector(NUM_PINS - 1 downto 0);
    signal prt_ren_out  : std_logic_vector(NUM_PINS - 1 downto 0);

    signal PxOUT_out : std_logic_vector(NUM_PINS - 1 downto 0);
    signal PxDIR_out : std_logic_vector(NUM_PINS - 1 downto 0);
    signal PxREN_out : std_logic_vector(NUM_PINS - 1 downto 0);
    signal PxSEL_out : std_logic_vector(NUM_PINS - 1 downto 0);
    signal PxAFS_out : std_logic_vector(3 * NUM_PINS - 1 downto 0);

    -- Alt-function planes tied to zero: PxSEL is never asserted here, so the AF mux is never exercised.
    signal alt_func_out_in : std_logic_vector(GPIO_NUM_AFS * NUM_PINS - 1 downto 0) := (others => '0');
    signal alt_func_dir_in : std_logic_vector(GPIO_NUM_AFS * NUM_PINS - 1 downto 0) := (others => '0');
    signal alt_func_ren_in : std_logic_vector(GPIO_NUM_AFS * NUM_PINS - 1 downto 0) := (others => '0');

    -- ---- event-fabric taps -------------------------------------------------
    signal evt_edge_raw : std_logic_vector(NUM_PINS - 1 downto 0);
    signal task_outset  : std_logic := '0';   -- tb-driven, default '0'
    signal task_outclr  : std_logic := '0';   -- tb-driven, default '0'

    signal tb_done : boolean := false;

    -- Scoreboard shared by the stimulus process and the final verdict.
    shared variable sb : scoreboard;

begin

    -- One free-running reference drives clk_mem directly, since task pulses must be observed with the bus idle.
    clk     <= not clk after PERIOD / 2;
    clk_mem <= clk;

    -- DUT
    dut : component GPIO
        generic map (
            num_pins       => NUM_PINS,
            PadOUTPosLogic => true,
            PadDIRPosLogic => false,
            PadRENPosLogic => false,
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
            en              => pbus.en_mem,
            wen             => pbus.wen,
            write_data      => pbus.write_data,
            read_data       => read_data,
            addr_periph     => pbus.addr_periph,
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
            alt_func_ren_in => alt_func_ren_in,
            evt_edge_raw    => evt_edge_raw,
            task_outset     => task_outset,
            task_outclr     => task_outclr
        );

    -- Watchdog: abort with a FAIL banner if the stimulus ever hangs.
    watchdog : process
    begin
        wait for 20 ms;
        if not tb_done then
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   GPIO_TB FAIL (WATCHDOG TIMEOUT -- stimulus never finished)" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
            stop;
        end if;
        wait;
    end process;

    -- Stimulus: the groups run in order, with the negative control last.
    stim_proc : process
        variable rdw : std_logic_vector(31 downto 0);

        -- Reset pulse: resetn low for a few PERIODs then back high.
        procedure reset_pulse is
        begin
            resetn      <= '0';
            pbus        <= PERIPH_BUS_IDLE;
            task_outset <= '0';
            task_outclr <= '0';
            prt_in      <= (others => '0');
            wait for 6 * PERIOD;
            wait for 1 ns;
            resetn <= '1';
            wait for 4 * PERIOD;
        end procedure;

        -- Drive sig high across exactly one clk_mem rising edge, then drop it: the one-clk_mem task-pulse idiom.
        procedure pulse1(signal sig : out std_logic) is
        begin
            wait until clk = '0';
            sig <= '1';
            wait until clk = '1';
            wait until clk = '0';
            sig <= '0';
        end procedure;

        -- Pulse task_outset AND task_outclr across the SAME clk_mem rising edge: the "same-cycle set plus clear" corner.
        procedure pulse_both_tasks is
        begin
            wait until clk = '0';
            task_outset <= '1';
            task_outclr <= '1';
            wait until clk = '1';
            wait until clk = '0';
            task_outset <= '0';
            task_outclr <= '0';
        end procedure;

        -- CPU PxOUT write coincident with a task pulse: bus_write's exact timing, with task_outset/task_outclr asserted across the same capture edge.
        procedure coincident_out_write_task(out_word       : std_logic_vector(31 downto 0);
                                             do_set, do_clr : std_logic) is
        begin
            wait until clk = '0';
            pbus.addr_periph <= std_logic_vector(to_unsigned(RegSlotPxOUT, 6));
            pbus.write_data  <= out_word;
            pbus.wen         <= (others => '0');
            pbus.en_mem      <= '0';
            task_outset      <= do_set;
            task_outclr      <= do_clr;
            wait until clk = '1';
            wait until clk = '0';
            pbus.en_mem <= '1';
            pbus.wen    <= (others => '1');
            task_outset <= '0';
            task_outclr <= '0';
        end procedure;

    begin
        -- Reset
        reset_pulse;

        -- GROUP G1: minimal existing-behavior regression, covering PxOUT write and readback, PxDIR, and an input-latch (PxIN) read.
        report "=== GROUP G1: PxOUT / PxDIR / PxIN regression ===" severity note;
        bus_write(clk, pbus, RegSlotPxOUT, x"000000A5");
        bus_read(clk, pbus, read_data, RegSlotPxOUT, rdw);
        sb.check_slv("G1a: PxOUT write/readback (0xA5)", rdw(7 downto 0), x"A5");
        sb.check_slv("G1a: PxOUT_out mirrors PxOUT", PxOUT_out, x"A5");

        bus_write(clk, pbus, RegSlotPxDIR, x"000000C3");
        bus_read(clk, pbus, read_data, RegSlotPxDIR, rdw);
        sb.check_slv("G1b: PxDIR write/readback (0xC3)", rdw(7 downto 0), x"C3");
        sb.check_slv("G1b: PxDIR_out mirrors PxDIR", PxDIR_out, x"C3");

        prt_in <= x"96";
        wait for 2 * PERIOD;
        bus_read(clk, pbus, read_data, RegSlotPxIN, rdw);
        sb.check_slv("G1c: PxIN input-latch read (0x96)", rdw(7 downto 0), x"96");
        prt_in <= (others => '0');
        bus_write(clk, pbus, RegSlotPxOUT, x"00000000");
        wait for 2 * PERIOD;

        -- GROUP G2: PxTASK register, an RW walking-1 at slot 12, reset value 0, plus readback.
        report "=== GROUP G2: PxTASK register (RW walking-1) ===" severity note;
        bus_read(clk, pbus, read_data, RegSlotPxTASK, rdw);
        sb.check_slv("G2a: PxTASK resets to 0", rdw(7 downto 0), x"00");

        for i in 0 to NUM_PINS - 1 loop
            bus_write(clk, pbus, RegSlotPxTASK,
                      std_logic_vector(to_unsigned(2 ** i, 32)));
            bus_read(clk, pbus, read_data, RegSlotPxTASK, rdw);
            sb.check_slv("G2b: PxTASK walking-1 bit " & integer'image(i),
                         rdw(7 downto 0),
                         std_logic_vector(to_unsigned(2 ** i, 8)));
        end loop;
        bus_write(clk, pbus, RegSlotPxTASK, x"00000000");

        -- GROUP G3: task_outset and task_outclr basic operation with PxTASK=0x0F, where set pulses PxOUT(3:0) and clear pulses them back down.
        -- PxOUT(7:4), outside PxTASK, must stay untouched throughout.
        report "=== GROUP G3: task_outset / task_outclr basic ===" severity note;
        bus_write(clk, pbus, RegSlotPxOUT, x"000000B0");   -- preload 7:4 with pattern B, 3:0 cleared
        bus_write(clk, pbus, RegSlotPxTASK, x"0000000F");  -- task owns pins 0-3

        pulse1(task_outset);
        bus_read(clk, pbus, read_data, RegSlotPxOUT, rdw);
        sb.check_slv("G3a: task_outset sets PxOUT(3:0), leaves 7:4 (0xBF)",
                     rdw(7 downto 0), x"BF");

        pulse1(task_outclr);
        bus_read(clk, pbus, read_data, RegSlotPxOUT, rdw);
        sb.check_slv("G3b: task_outclr clears PxOUT(3:0), leaves 7:4 (0xB0)",
                     rdw(7 downto 0), x"B0");

        -- GROUP G4: same-cycle task_outset plus task_outclr, where CLR must win.
        report "=== GROUP G4: same-cycle set+clr -- CLR wins ===" severity note;
        bus_write(clk, pbus, RegSlotPxOUT, x"000000BF");   -- 3:0 pre-set so a no-op clear would be masked
        pulse_both_tasks;
        bus_read(clk, pbus, read_data, RegSlotPxOUT, rdw);
        sb.check_slv("G4: coincident set+clr -> PxOUT(3:0) cleared, 7:4 untouched (0xB0)",
                     rdw(7 downto 0), x"B0");

        -- GROUP G5: coincident CPU PxOUT write and task pulse, where the task wins its PxTASK pins and the CPU value lands on the others.
        -- Both directions, set and clear, are exercised.
        report "=== GROUP G5: coincident CPU write + task pulse ===" severity note;
        bus_write(clk, pbus, RegSlotPxOUT, x"00000000");   -- baseline: all bits clear
        -- The CPU writes PxOUT=0x50 (7:4 = 5, 3:0 = 0) while task_outset pulses on the SAME edge, so 3:0 is forced to 1 by the task and 7:4 keeps the CPU's 5.
        coincident_out_write_task(x"00000050", '1', '0');
        bus_read(clk, pbus, read_data, RegSlotPxOUT, rdw);
        sb.check_slv("G5a: coincident write(0x50)+task_outset -> 0x5F (task wins the set)",
                     rdw(7 downto 0), x"5F");

        -- The CPU writes PxOUT=0xFF while task_outclr pulses on the SAME edge, so 3:0 is forced to 0 by the task and 7:4 keeps the CPU's F.
        coincident_out_write_task(x"000000FF", '0', '1');
        bus_read(clk, pbus, read_data, RegSlotPxOUT, rdw);
        sb.check_slv("G5b: coincident write(0xFF)+task_outclr -> 0xF0 (task wins the clear)",
                     rdw(7 downto 0), x"F0");

        bus_write(clk, pbus, RegSlotPxTASK, x"00000000");  -- release the task mask
        bus_write(clk, pbus, RegSlotPxOUT,  x"00000000");

        -- GROUP G6: evt_edge_raw = prt_in xor PxIES, combinationally and independently of PxIE.
        report "=== GROUP G6: evt_edge_raw (pre-mask edge-select tap) ===" severity note;
        bus_write(clk, pbus, RegSlotPxIES, x"00000000");   -- rising-edge select, all pins
        prt_in <= x"A5";
        wait for 2 * PERIOD;
        sb.check_slv("G6a: evt_edge_raw = prt_in xor PxIES (A5 xor 00 = A5)",
                     evt_edge_raw, x"A5");

        bus_write(clk, pbus, RegSlotPxIES, x"000000FF");   -- falling-edge select, all pins
        wait for 2 * PERIOD;
        sb.check_slv("G6b: evt_edge_raw follows a PxIES change (A5 xor FF = 5A)",
                     evt_edge_raw, x"5A");

        prt_in <= x"3C";
        wait for 2 * PERIOD;
        sb.check_slv("G6c: evt_edge_raw follows a prt_in change (3C xor FF = C3)",
                     evt_edge_raw, x"C3");

        -- Discipline: PxIE is never consulted, so toggling it in either direction leaves evt_edge_raw exactly where it was.
        bus_write(clk, pbus, RegSlotPxIE, x"00000000");    -- all masked
        wait for 2 * PERIOD;
        sb.check_slv("G6d: evt_edge_raw unaffected by PxIE=0x00 (masked)",
                     evt_edge_raw, x"C3");
        bus_write(clk, pbus, RegSlotPxIE, x"000000FF");    -- all enabled
        wait for 2 * PERIOD;
        sb.check_slv("G6e: evt_edge_raw unaffected by PxIE=0xFF (enabled) -- pre-mask by construction",
                     evt_edge_raw, x"C3");

        bus_write(clk, pbus, RegSlotPxIE,  x"00000000");
        bus_write(clk, pbus, RegSlotPxIES, x"00000000");
        prt_in <= (others => '0');
        wait for 2 * PERIOD;

        -- GROUP G-NEG: NEGATIVE CONTROL, mandatory and LAST.
        -- Exactly ONE deliberately wrong expected value, so the scoreboard proves it can fail.
        report "=== GROUP G-NEG: NEGATIVE CONTROL ===" severity note;
        bus_write(clk, pbus, RegSlotPxOUT,  x"00000000");
        bus_write(clk, pbus, RegSlotPxTASK, x"0000000F");
        pulse1(task_outset);
        bus_read(clk, pbus, read_data, RegSlotPxOUT, rdw);
        sb.check_slv("NEGATIVE CONTROL: wrong expected PxOUT after task_outset (must FAIL)",
                     rdw(7 downto 0), x"00");   -- the actual value is 0x0F, so this expectation is deliberately wrong

        -- Final verdict: sb.errors must be EXACTLY 1, the negative control.
        wait for 1 us;
        sb.report_summary("GPIO TB");

        if sb.errors = 1 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##   GPIO_TB PASS (1 expected negative-control failure)" & LF &
                "    ##   GPIO TB:  ALL CHECKS PASSED" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!   GPIO_TB FAIL (expected exactly 1 failure [negative control], got " &
                integer'image(sb.errors) & ")" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        tb_done <= true;
        stop;
        wait;
    end process stim_proc;

end architecture sim;
