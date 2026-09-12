-- VestaRV: EVFAB testbench
-- Small self-checking bench for the event/trigger fabric, written for the periph_regs migration (report R12e): EVFAB is analysed and elaborated by //opensource_sim/mcu:mcu_elaborate but is instantiated in no tracked configuration, so before this bench its register file had no oracle at all.
-- Scope is deliberately the register file and ONE path through the crossbar: reset values, the CAP constant, a channel-config word including the lane-0 write rule and the ENR read-only mirror, the CHENSET/CHENCLR aliases, and the MODE SELECT -- one pulse-mode event and one toggle-mode event driving a task through a configured channel, with the CR.EN gate and the FIRED/EVSTAT stickies.
-- ClkMem is tied to clk, which is the integration contract the RTL header states ("ClkMem's edges are a subset of clk's at the same phase"); the action path needs clk to keep running while the bus is deselected.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.constants.all;
use work.periph_tb_pkg.all;
use work.evfab_regs_pkg.all;

entity EVFAB_tb is
end entity EVFAB_tb;

architecture sim of EVFAB_tb is

    constant PERIOD : time    := 20 ns;
    constant N_CH   : natural := 8;
    constant N_EV   : natural := 16;
    constant N_TASK : natural := 10;

    -- The DUT's own defaults, restated so the bench can pick a P-mode and a
    -- T-mode event line by name rather than by memory.
    constant MODE_TGL : std_logic_vector(31 downto 0) := X"00000370";  -- events 4,5,6,8,9
    constant MODE_LVL : std_logic_vector(31 downto 0) := X"00002000";  -- event 13
    constant EV_P     : natural := 1;    -- in neither mask: pulse pass-through
    constant EV_T     : natural := 4;    -- in TGL: one pulse per flip

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    signal pbus      : periph_bus_t := PERIPH_BUS_IDLE;
    signal rdata_out : std_logic_vector(31 downto 0);

    signal irq_evfab  : std_logic;
    signal ev_in      : std_logic_vector(N_EV-1 downto 0)   := (others => '0');
    signal gpio0_evin : std_logic_vector(7 downto 0)        := (others => '0');
    signal task_busy  : std_logic_vector(N_TASK-1 downto 0) := (others => '0');
    signal task_pulse : std_logic_vector(N_TASK-1 downto 0);

    -- Pulse observer: task_pulse is a registered ONE-clk pulse, so the stimulus
    -- cannot sample it directly. task_seen accumulates, clr_seen retires.
    signal task_seen : std_logic_vector(N_TASK-1 downto 0) := (others => '0');
    signal clr_seen  : std_logic := '0';
    signal wide_seen : std_logic := '0';   -- task_pulse high on two edges running

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

begin

    clk <= not clk after PERIOD / 2 when not tb_done else '0';

    dut : entity work.EVFAB
        generic map (
            N_CH => N_CH, N_EV => N_EV, N_TASK => N_TASK, EV_GPIO_IDX => 15,
            EV_MODE_TGL => MODE_TGL, EV_MODE_LVL => MODE_LVL, VER => 1)
        port map (
            clk => clk, resetn => resetn, irq_evfab => irq_evfab,
            ClkMem => clk, EnMemPeriph => pbus.en_mem, WEn => pbus.wen,
            MABPart => pbus.addr_periph, wdata => pbus.write_data,
            rdata_out => rdata_out,
            ev_in => ev_in, gpio0_evin => gpio0_evin,
            task_busy => task_busy, task_pulse => task_pulse);

    observer : process(clk)
        variable prev : std_logic_vector(N_TASK-1 downto 0) := (others => '0');
    begin
        if rising_edge(clk) then
            if (prev and task_pulse) /= (prev'range => '0') then
                wide_seen <= '1';
            end if;
            prev := task_pulse;
            if clr_seen = '1' then
                task_seen <= (others => '0');
                wide_seen <= '0';
            else
                task_seen <= task_seen or task_pulse;
            end if;
        end if;
    end process;

    watchdog : process
    begin
        wait for 500 us;
        if not tb_done then
            report LF & "    !!   EVFAB_TB FAIL (WATCHDOG TIMEOUT)" & LF severity warning;
            stop;
        end if;
        wait;
    end process;

    stim : process
        variable rdw : std_logic_vector(31 downto 0);

        -- periph_tb_pkg.bus_write always asserts all four lanes; EVFAB takes a
        -- write only with lane 0 enabled and then writes the whole word, so both
        -- halves of that rule need a lane-aware writer.
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

        procedure arm_observer is
        begin
            clr_seen <= '1';
            wait until clk = '1';
            wait until clk = '1';
            clr_seen <= '0';
            wait until clk = '1';
        end procedure;

    begin
        resetn <= '0';
        wait for 4 * PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 4 * PERIOD;

        -- GROUP 1: reset values, the capability constant and the reserved words.
        report "=== GROUP 1: reset, CAP, reserved words ===" severity note;
        bus_read(clk, pbus, rdata_out, SLOT_CR, rdw);
        sb.check_slv("CR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, SLOT_CHEN, rdw);
        sb.check_slv("CHEN resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, SLOT_GPIOMASK, rdw);
        sb.check_slv("GPIOMASK resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, SLOT_SR, rdw);
        sb.check_slv("SR resets to 0", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, SLOT_CAP, rdw);
        sb.check_slv("CAP is the VER/N_TASK/N_EV/N_CH constant", rdw, x"010A1008");
        bus_read(clk, pbus, rdata_out, SLOT_CH0CFG, rdw);
        sb.check_slv("CH0CFG resets to 0", rdw, x"00000000");
        bus_write(clk, pbus, 12, x"FFFFFFFF");
        bus_read(clk, pbus, rdata_out, 12, rdw);
        sb.check_slv("a reserved word reads 0 and ignores writes", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, SLOT_CHTRIG, rdw);
        sb.check_slv("CHTRIG is an action slot and reads 0", rdw, x"00000000");
        sb.check_bit("irq_evfab is vectorless", irq_evfab, '0');

        -- GROUP 2: one channel-config word, the lane-0 write rule and the ENR mirror.
        report "=== GROUP 2: CH0CFG, lanes and the ENR mirror ===" severity note;
        bus_write(clk, pbus, SLOT_CH0CFG, x"00000301");   -- EVSEL=1, TASKSEL=3
        bus_read(clk, pbus, rdata_out, SLOT_CH0CFG, rdw);
        sb.check_slv("CH0CFG write/readback, ENR clear while the channel is off",
                     rdw, x"00000301");
        bus_write(clk, pbus, SLOT_CHEN, x"00000001");
        bus_read(clk, pbus, rdata_out, SLOT_CH0CFG, rdw);
        sb.check_slv("CH0CFG bit 31 mirrors CHEN(0)", rdw, x"80000301");
        bus_write_lanes(SLOT_CH0CFG, "1110", x"00000502");
        bus_read(clk, pbus, rdata_out, SLOT_CH0CFG, rdw);
        sb.check_slv("a LANE 0 write moves TASKSEL at 11:8 as well as EVSEL",
                     rdw, x"80000502");
        bus_write_lanes(SLOT_CH0CFG, "1101", x"00000000");
        bus_read(clk, pbus, rdata_out, SLOT_CH0CFG, rdw);
        sb.check_slv("a write WITHOUT lane 0 changes nothing", rdw, x"80000502");
        bus_write(clk, pbus, SLOT_CH0CFG, x"FFFFFFFF");
        bus_read(clk, pbus, rdata_out, SLOT_CH0CFG, rdw);
        sb.check_slv("CH0CFG drops the reserved bits", rdw, x"80000F1F");
        bus_write(clk, pbus, SLOT_CHEN, x"00000000");

        -- GROUP 3: the CHENSET / CHENCLR aliases of CHEN.
        report "=== GROUP 3: CHENSET / CHENCLR aliases ===" severity note;
        bus_write(clk, pbus, SLOT_CHENSET, x"0000000F");
        bus_read(clk, pbus, rdata_out, SLOT_CHEN, rdw);
        sb.check_slv("CHENSET sets the bits a 1 was written to", rdw, x"0000000F");
        bus_read(clk, pbus, rdata_out, SLOT_CHENSET, rdw);
        sb.check_slv("CHENSET mirrors CHEN", rdw, x"0000000F");
        bus_write(clk, pbus, SLOT_CHENSET, x"00000000");
        bus_read(clk, pbus, rdata_out, SLOT_CHEN, rdw);
        sb.check_slv("a 0 written to CHENSET is a no-op", rdw, x"0000000F");
        bus_write(clk, pbus, SLOT_CHENCLR, x"00000005");
        bus_read(clk, pbus, rdata_out, SLOT_CHEN, rdw);
        sb.check_slv("CHENCLR clears the bits a 1 was written to", rdw, x"0000000A");
        bus_read(clk, pbus, rdata_out, SLOT_CHENCLR, rdw);
        sb.check_slv("CHENCLR mirrors CHEN", rdw, x"0000000A");
        bus_write_lanes(SLOT_CHENSET, "1101", x"000000FF");
        bus_read(clk, pbus, rdata_out, SLOT_CHEN, rdw);
        sb.check_slv("an alias write without lane 0 changes nothing", rdw, x"0000000A");
        bus_write(clk, pbus, SLOT_CHEN, x"00000000");

        -- GROUP 4: mode select. A P-mode event passes through, a T-mode event
        -- fires once per flip, and both reach the configured task only while the
        -- channel is armed.
        report "=== GROUP 4: mode select through the crossbar ===" severity note;
        bus_write(clk, pbus, SLOT_CH0CFG, x"00000300" or
                  std_logic_vector(to_unsigned(EV_P, 32)));   -- EVSEL=EV_P, TASKSEL=3
        bus_write(clk, pbus, SLOT_CH0CFG + 1, x"00000500" or
                  std_logic_vector(to_unsigned(EV_T, 32)));   -- EVSEL=EV_T, TASKSEL=5
        bus_write(clk, pbus, SLOT_CHEN, x"00000003");
        bus_write(clk, pbus, SLOT_CR,   x"00000001");         -- EN

        -- P mode: ev_in is a one-clk pulse and passes straight through.
        arm_observer;
        wait until clk = '0';
        ev_in(EV_P) <= '1';
        wait until clk = '0';
        ev_in(EV_P) <= '0';
        wait for 4 * PERIOD;
        sb.check_bit("P-mode event fires its task", task_seen(3), '1');
        sb.check_bit("and no other task", task_seen(5), '0');
        sb.check_bit("task_pulse is one clk wide", wide_seen, '0');
        bus_read(clk, pbus, rdata_out, SLOT_FIRED, rdw);
        sb.check_slv("FIRED records the channel", rdw, x"00000001");
        bus_read(clk, pbus, rdata_out, SLOT_EVSTAT, rdw);
        sb.check_slv("EVSTAT records the event line", rdw,
                     std_logic_vector(to_unsigned(2 ** EV_P, 32)));
        bus_read(clk, pbus, rdata_out, SLOT_SR, rdw);
        sb.check_bit("SR.FIREDIF is the OR of FIRED", rdw(EVFFIREDIF_LSB), '1');

        -- The write-1 clears live in the clk domain; give the action path its
        -- three clk edges of latency before reading back.
        bus_write(clk, pbus, SLOT_FIRED,  x"000000FF");
        bus_write(clk, pbus, SLOT_EVSTAT, x"0000FFFF");
        wait for 6 * PERIOD;
        bus_read(clk, pbus, rdata_out, SLOT_FIRED, rdw);
        sb.check_slv("a written 1 retires FIRED", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, SLOT_EVSTAT, rdw);
        sb.check_slv("a written 1 retires EVSTAT", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, SLOT_SR, rdw);
        sb.check_slv("SR follows them down", rdw, x"00000000");

        -- T mode: one pulse per FLIP, so a held level fires on the way up and
        -- again on the way down.
        arm_observer;
        wait until clk = '0';
        ev_in(EV_T) <= '1';
        wait for 4 * PERIOD;
        sb.check_bit("T-mode event fires on the rising flip", task_seen(5), '1');
        arm_observer;
        wait until clk = '0';
        ev_in(EV_T) <= '0';
        wait for 4 * PERIOD;
        sb.check_bit("T-mode event fires again on the falling flip", task_seen(5), '1');

        -- CR.EN is the global kill: the event is still RECORDED, because EVSTAT
        -- is upstream of the gate, but no task fires.
        bus_write(clk, pbus, SLOT_FIRED,  x"000000FF");
        bus_write(clk, pbus, SLOT_EVSTAT, x"0000FFFF");
        bus_write(clk, pbus, SLOT_CR, x"00000000");
        wait for 6 * PERIOD;
        arm_observer;
        wait until clk = '0';
        ev_in(EV_P) <= '1';
        wait until clk = '0';
        ev_in(EV_P) <= '0';
        wait for 4 * PERIOD;
        sb.check_bit("CR.EN = 0 stops the task", task_seen(3), '0');
        bus_read(clk, pbus, rdata_out, SLOT_FIRED, rdw);
        sb.check_slv("and stops FIRED", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, SLOT_EVSTAT, rdw);
        sb.check_slv("but EVSTAT still records, being upstream of the gate", rdw,
                     std_logic_vector(to_unsigned(2 ** EV_P, 32)));

        -- GROUP 5: the two ACTION slots, CHTRIG and EVTRIG. Neither holds storage
        -- (both are sw=w, so IMPL gives them none: hdl/common/regs/REGFILE.md, "A
        -- write-only field holds nothing"); each is decoded from the raw bus word
        -- in the clk domain, so this group is the proof that the consumer still
        -- fires with the flops gone.
        report "=== GROUP 5: CHTRIG / EVTRIG injection ===" severity note;
        bus_write(clk, pbus, SLOT_CR, x"00000001");          -- re-enable
        bus_write(clk, pbus, SLOT_FIRED,  x"000000FF");
        bus_write(clk, pbus, SLOT_EVSTAT, x"0000FFFF");
        wait for 6 * PERIOD;

        arm_observer;
        bus_write(clk, pbus, SLOT_CHTRIG, x"00000001");      -- inject on channel 0
        wait for 6 * PERIOD;
        sb.check_bit("CHTRIG injects a firing on channel 0's task", task_seen(3), '1');
        sb.check_bit("and on no other task", task_seen(5), '0');
        bus_read(clk, pbus, rdata_out, SLOT_FIRED, rdw);
        sb.check_slv("an injected firing is recorded in FIRED", rdw, x"00000001");
        bus_read(clk, pbus, rdata_out, SLOT_EVSTAT, rdw);
        sb.check_slv("and no event line is claimed to have occurred", rdw, x"00000000");
        bus_read(clk, pbus, rdata_out, SLOT_CHTRIG, rdw);
        sb.check_slv("CHTRIG still reads 0 with no storage behind it", rdw, x"00000000");

        bus_write(clk, pbus, SLOT_FIRED, x"000000FF");
        wait for 6 * PERIOD;
        arm_observer;
        bus_write(clk, pbus, SLOT_EVTRIG,
                  std_logic_vector(to_unsigned(2 ** EV_P, 32)));   -- inject event EV_P
        wait for 6 * PERIOD;
        sb.check_bit("EVTRIG injects the event into the crossbar", task_seen(3), '1');
        bus_read(clk, pbus, rdata_out, SLOT_EVSTAT, rdw);
        sb.check_slv("and EVSTAT records it as a real occurrence", rdw,
                     std_logic_vector(to_unsigned(2 ** EV_P, 32)));
        bus_read(clk, pbus, rdata_out, SLOT_EVTRIG, rdw);
        sb.check_slv("EVTRIG still reads 0 with no storage behind it", rdw, x"00000000");

        wait for 4 * PERIOD;
        sb.report_summary("EVFAB TB");
        tb_done <= true;
        stop;
        wait;
    end process stim;

end architecture sim;
