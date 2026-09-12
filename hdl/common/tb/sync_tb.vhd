-- VestaRV: sync testbench
-- Self-checking unit bench for the CDC synchroniser. Four instances cover the generic matrix in one run: WIDTH 1 and 4 against DEPTH 2 and 3, with a non-zero RST_VAL on one of them.
-- The latency claim is graded as EXACTLY DEPTH, not at least DEPTH: q must be unchanged after each of the first DEPTH-1 edges and must equal the new value after edge DEPTH, and the step is applied one bit at a time so a chain that crossed between bits would show on its neighbours.
-- A hand-rolled ONE-flop chain runs off the same d, clk and areset as the DEPTH=2 DUT and is the negative control: the same predicate that passes on the DUT fails on it, which is what makes the latency checks load-bearing rather than tautological.
-- The glitch group states the property a synchroniser actually has. A pulse shorter than one clock period may or may not be sampled, so the bench asserts the weaker true thing -- q takes no value it had not already taken -- plus the strict case, a sub-period pulse laid strictly between two edges, which can never appear on q at all.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.periph_tb_pkg.all;

entity sync_tb is
end entity sync_tb;

architecture sim of sync_tb is

    constant PERIOD : time := 20 ns;
    constant SETTLE : time := 1 ns;    -- sample this far past a rising edge

    -- The non-zero reset value, carried by dut_w4_d2 alone so that a stage
    -- resetting to zero when it should not shows up as a difference between
    -- the two WIDTH=4 instances and not as a silent pass.
    constant RSTV4 : std_logic_vector(3 downto 0) := "1010";

    -- Never driven on d outside the strict glitch check, and unreachable as a
    -- resting value of q anywhere else in the stimulus, so seeing it at all is
    -- proof that a sub-period pulse was captured.
    constant GLITCHV : std_logic_vector(3 downto 0) := "0110";

    signal clk    : std_logic := '0';
    signal areset : std_logic := '0';

    signal d1 : std_logic_vector(0 downto 0) := (others => '0');
    signal d4 : std_logic_vector(3 downto 0) := (others => '0');

    signal q1_d2, q1_d3 : std_logic_vector(0 downto 0);
    signal q4_d2, q4_d3 : std_logic_vector(3 downto 0);
    -- A bare literal RST_VAL binds with ascending bounds; "100" must still set bit 2.
    signal q3_lit : std_logic_vector(2 downto 0);

    -- Negative control: the DEPTH=2 chain with one stage removed.
    signal nc_q : std_logic;

    -- Every value q4_d3 has ever held, indexed by the value itself.
    signal seen : std_logic_vector(0 to 15) := (others => '0');

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

begin

    clk <= not clk after PERIOD / 2 when not tb_done else '0';

    dut_w1_d2 : entity work.sync
        generic map (WIDTH => 1, DEPTH => 2)
        port map (clk => clk, areset => areset, d => d1, q => q1_d2);

    dut_w1_d3 : entity work.sync
        generic map (WIDTH => 1, DEPTH => 3, RST_VAL => "1")
        port map (clk => clk, areset => areset, d => d1, q => q1_d3);

    dut_w4_d2 : entity work.sync
        generic map (WIDTH => 4, DEPTH => 2, RST_VAL => RSTV4)
        port map (clk => clk, areset => areset, d => d4, q => q4_d2);

    dut_w4_d3 : entity work.sync
        generic map (WIDTH => 4, DEPTH => 3)
        port map (clk => clk, areset => areset, d => d4, q => q4_d3);

    dut_w3_lit : entity work.sync
        generic map (WIDTH => 3, DEPTH => 2, RST_VAL => "100")
        port map (clk => clk, areset => areset, d => d4(2 downto 0), q => q3_lit);

    -- The negative control. Identical to dut_w1_d2 in clock, reset and data;
    -- it differs in exactly one thing, the missing second stage.
    negctl : process (clk, areset)
    begin
        if areset = '0' then
            nc_q <= '0';
        elsif rising_edge(clk) then
            nc_q <= d1(0);
        end if;
    end process negctl;

    -- Runs continuously, including through resets and glitches.
    watcher : process (q4_d3)
    begin
        if not is_x(q4_d3) then
            seen(to_integer(unsigned(q4_d3))) <= '1';
        end if;
    end process watcher;

    stim : process

        -- Rising edge, then far enough past it that q has settled.
        procedure edge is
        begin
            wait until rising_edge(clk);
            wait for SETTLE;
        end procedure;

        -- Apply a step on d4 at a falling edge and grade the WIDTH=4 pair.
        -- old_v is what q holds now; new_v is what it must hold after exactly
        -- DEPTH edges and not one edge sooner.
        procedure step4(tag : in string; new_v : in std_logic_vector(3 downto 0)) is
            variable old2 : std_logic_vector(3 downto 0);
            variable old3 : std_logic_vector(3 downto 0);
        begin
            old2 := q4_d2;
            old3 := q4_d3;
            wait until falling_edge(clk);
            d4 <= new_v;

            edge;   -- edge 1
            sb.check_slv(tag & " w4 d2 unchanged at edge 1", q4_d2, old2);
            sb.check_slv(tag & " w4 d3 unchanged at edge 1", q4_d3, old3);

            edge;   -- edge 2: the DEPTH=2 chain arrives here and only here
            sb.check_slv(tag & " w4 d2 arrives at edge 2", q4_d2, new_v);
            sb.check_slv(tag & " w4 d3 unchanged at edge 2", q4_d3, old3);

            edge;   -- edge 3: the DEPTH=3 chain arrives
            sb.check_slv(tag & " w4 d3 arrives at edge 3", q4_d3, new_v);
            sb.check_slv(tag & " w4 d2 holds after arrival", q4_d2, new_v);
        end procedure;

        -- The same grading for the WIDTH=1 pair, with the one-deep negative
        -- control sampled beside them at every edge.
        procedure step1(tag : in string; new_v : in std_logic) is
            variable old2 : std_logic_vector(0 downto 0);
            variable old3 : std_logic_vector(0 downto 0);
            variable nv1  : std_logic_vector(0 downto 0);
        begin
            old2 := q1_d2;
            old3 := q1_d3;
            nv1  := (0 => new_v);
            wait until falling_edge(clk);
            d1(0) <= new_v;

            edge;   -- edge 1
            sb.check_slv(tag & " w1 d2 unchanged at edge 1", q1_d2, old2);
            sb.check_slv(tag & " w1 d3 unchanged at edge 1", q1_d3, old3);
            -- NEGATIVE CONTROL. The predicate graded on the line above is
            -- "unchanged at edge 1"; on a chain with one stage removed it is
            -- false, and this is the check that says so.
            sb.check_true(tag & " NEGCTRL one-deep chain has already moved at edge 1",
                          nc_q = new_v and q1_d2 = old2);

            edge;   -- edge 2
            sb.check_slv(tag & " w1 d2 arrives at edge 2", q1_d2, nv1);
            sb.check_slv(tag & " w1 d3 unchanged at edge 2", q1_d3, old3);

            edge;   -- edge 3
            sb.check_slv(tag & " w1 d3 arrives at edge 3", q1_d3, nv1);
        end procedure;

        -- Settle every chain on the values now on d.
        procedure quiesce is
        begin
            for i in 1 to 5 loop
                edge;
            end loop;
        end procedure;

        variable seen_before : std_logic_vector(0 to 15);
        variable v4          : std_logic_vector(3 downto 0);

    begin

        /* ---- GROUP 1: the reset value, while areset is held --------------
           d is the OPPOSITE of every reset value here, so a stage that failed
           to reset would read as d and not as RST_VAL. */
        d1(0) <= '1';
        d4    <= "1111";
        for i in 1 to 4 loop
            edge;
        end loop;

        sb.check_slv("G1 w1 d2 holds RST_VAL 0 under areset", q1_d2, "0");
        sb.check_slv("G1 w1 d3 holds RST_VAL 1 under areset", q1_d3, "1");
        sb.check_slv("G1 w4 d2 holds RST_VAL 1010 under areset", q4_d2, RSTV4);
        sb.check_slv("G1 w3 literal RST_VAL 100 is positional, bit 2 set", q3_lit, "100");
        sb.check_slv("G1 w4 d3 holds RST_VAL 0000 under areset", q4_d3, "0000");

        /* ---- GROUP 2: release, and the first data takes exactly DEPTH -----
           d has been at its final value throughout, so the only thing moving
           is the reset release. */
        wait until falling_edge(clk);
        areset <= '1';

        edge;   -- edge 1
        sb.check_slv("G2 w1 d2 still RST_VAL at edge 1", q1_d2, "0");
        sb.check_slv("G2 w1 d3 still RST_VAL at edge 1", q1_d3, "1");
        sb.check_slv("G2 w4 d2 still RST_VAL at edge 1", q4_d2, RSTV4);
        sb.check_slv("G2 w4 d3 still RST_VAL at edge 1", q4_d3, "0000");

        edge;   -- edge 2
        sb.check_slv("G2 w1 d2 arrives at edge 2", q1_d2, "1");
        sb.check_slv("G2 w4 d2 arrives at edge 2", q4_d2, "1111");
        sb.check_slv("G2 w1 d3 still RST_VAL at edge 2", q1_d3, "1");
        sb.check_slv("G2 w4 d3 still RST_VAL at edge 2", q4_d3, "0000");

        edge;   -- edge 3
        sb.check_slv("G2 w1 d3 arrives at edge 3", q1_d3, "1");
        sb.check_slv("G2 w4 d3 arrives at edge 3", q4_d3, "1111");

        /* ---- GROUP 3: a step on each bit, one bit at a time ---------------
           Every check in step4 grades the WHOLE vector, so a chain that leaked
           into a neighbouring bit fails on the neighbour, not on the bit that
           moved. Walk up from 0000 setting one bit at a time, then back down
           clearing one at a time, which exercises both edges on all four. */
        d4 <= "0000";
        d1(0) <= '0';
        quiesce;
        sb.check_slv("G3 w4 d2 parked at 0000", q4_d2, "0000");
        sb.check_slv("G3 w4 d3 parked at 0000", q4_d3, "0000");

        v4 := "0000";
        for k in 0 to 3 loop
            v4(k) := '1';
            step4("G3 set bit " & integer'image(k), v4);
        end loop;
        for k in 0 to 3 loop
            v4(k) := '0';
            step4("G3 clear bit " & integer'image(k), v4);
        end loop;

        /* ---- GROUP 4: the WIDTH=1 pair and the negative control ----------- */
        step1("G4 rise", '1');
        step1("G4 fall", '0');

        /* ---- GROUP 5: areset is ASYNCHRONOUS -----------------------------
           Assert it strictly between two edges, with every q at all ones, and
           require the reset value BEFORE the next edge arrives. A synchronous
           reset would still be showing 1111 here. */
        d4 <= "1111";
        d1(0) <= '1';
        quiesce;
        sb.check_slv("G5 w4 d3 loaded with 1111", q4_d3, "1111");

        wait until rising_edge(clk);
        wait for PERIOD / 4;            -- a quarter period short of any edge
        areset <= '0';
        wait for PERIOD / 8;
        sb.check_slv("G5 w1 d2 reset between edges", q1_d2, "0");
        sb.check_slv("G5 w1 d3 reset between edges", q1_d3, "1");
        sb.check_slv("G5 w4 d2 reset between edges", q4_d2, RSTV4);
        sb.check_slv("G5 w4 d3 reset between edges", q4_d3, "0000");

        wait until falling_edge(clk);
        areset <= '1';
        d4 <= "0000";
        d1(0) <= '0';
        quiesce;

        /* ---- GROUP 6: a pulse shorter than one clock period ---------------
           6a is the strict case: the pulse lies wholly between two rising
           edges, so no stage can sample it and GLITCHV must never reach q.
           6b is the general property: pulses laid at eight offsets across the
           period, some of which DO straddle an edge and are legitimately
           captured, may still only produce a value q has already held. */
        seen_before := seen;
        sb.check_true("G6a GLITCHV unseen before the glitch",
                      seen_before(to_integer(unsigned(GLITCHV))) = '0');

        for rep in 1 to 4 loop
            wait until rising_edge(clk);
            wait for PERIOD / 4;
            d4 <= GLITCHV;              -- pulse of PERIOD/4, no edge inside it
            wait for PERIOD / 4;
            d4 <= "0000";
            wait for PERIOD / 4;
            sb.check_slv("G6a w4 d3 undisturbed by the sub-period pulse", q4_d3, "0000");
            sb.check_slv("G6a w4 d2 undisturbed by the sub-period pulse", q4_d2, "0000");
        end loop;
        quiesce;
        sb.check_true("G6a GLITCHV never reached q",
                      seen(to_integer(unsigned(GLITCHV))) = '0');

        -- 6b. d has held 0000 and 1111 already, so both are in seen_before.
        d4 <= "1111";
        quiesce;
        d4 <= "0000";
        quiesce;
        seen_before := seen;

        for off in 0 to 7 loop
            wait until rising_edge(clk);
            wait for (PERIOD * off) / 8;
            d4 <= "1111";
            wait for PERIOD / 8;        -- one eighth of a period, always short
            d4 <= "0000";
            quiesce;
            for v in 0 to 15 loop
                sb.check_true("G6b offset " & integer'image(off)
                              & " produced no new pattern " & integer'image(v),
                              seen(v) = '0' or seen_before(v) = '1');
            end loop;
        end loop;

        /* ---- GROUP 7: the negative control, stated once on its own --------
           Latency measured, not asserted: the two-deep chain and the one-deep
           model are fed the same step and the edge at which each moves is
           recorded. If these were equal the whole bench would be vacuous. */
        d1(0) <= '0';
        quiesce;
        wait until falling_edge(clk);
        d1(0) <= '1';
        edge;
        sb.check_true("G7 NEGCTRL one-deep moved at edge 1, DUT did not",
                      nc_q = '1' and q1_d2 = "0");
        edge;
        sb.check_true("G7 DUT moved at edge 2", q1_d2 = "1");

        sb.report_summary("SYNC_TB");
        tb_done <= true;
        stop;
        wait;

    end process stim;

end architecture sim;
