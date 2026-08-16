-- =============================================================================
-- irq_router_tb.vhd: unit proof for the PLIC-lite irq_router: routing rows, registered meip reduction, CLAIM and COMPLETE semantics, status words and the WDT hooks.
-- It drives the slave port with the arbiter's bus contract: en is a one-cycle strobe, we is active-high lanes, master is the granted index, and the registered read is valid the cycle after the strobe; the arbiter serializes whole transactions, so back-to-back strobes with different master values ARE the "simultaneous claim" case.
-- Self-checking, printing ALL CHECKS PASSED or CHECKS FAILED, over: reset no-op, row R/W with lane merge and top-EN-word masking, dead rows, a routed level raising meip only on routed harts, exactly-once multi-hart claim with the 0xFFFFFFFF sentinel, complete re-pending a still-high level and owner-unqualified recovery, lowest-ID priority, the PEND and INSVC status words including the word-3 pair 519 and 523, CLINT sources 83 and 84 never reaching meip, and the WDT reduction plus its one-cycle COMPLETE(0) pulse.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity irq_router_tb is
    generic (
        NHARTS   : natural := 4;
        NUM_SRCS : natural := 85;
        MW       : natural := 2
    );
end entity;

architecture tb of irq_router_tb is

    constant CLK_PERIOD : time := 40 ns;   -- About 24 MHz, matching mclk.

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    signal en     : std_logic := '0';
    signal we     : std_logic_vector(3 downto 0) := (others => '0');
    signal addr   : std_logic_vector(9 downto 0) := (others => '0');
    signal wdata  : std_logic_vector(31 downto 0) := (others => '0');
    signal rdata  : std_logic_vector(31 downto 0);
    signal master : std_logic_vector(MW-1 downto 0) := (others => '0');

    signal irq_in : std_logic_vector(NUM_SRCS-1 downto 0) := (others => '0');
    signal meip   : std_logic_vector(NHARTS-1 downto 0);

    signal wdt_routed   : std_logic;
    signal wdt_complete : std_logic;

    signal done : boolean := false;

    constant W_CLAIM : natural := 512;
    constant SENTINEL : std_logic_vector(31 downto 0) := (others => '1');

    -- NUM_SRCS-generic shape facts, mirroring the DUT's own constants.
    constant NUM_EN_WORDS : natural := (NUM_SRCS + 31) / 32;
    constant TOP_LIVE     : natural := NUM_SRCS - 32*(NUM_EN_WORDS-1);
    -- Word-3 probe source: the top source, used only when NUM_SRCS is over 96.
    constant SRC_X : natural := NUM_SRCS - 1;
    constant BX    : natural := SRC_X mod 32;

    signal fails : integer := 0;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done else '0';

    dut: entity work.irq_router
        generic map (NHARTS => NHARTS, NUM_SRCS => NUM_SRCS, MW => MW)
        port map (
            clk          => clk,
            resetn       => resetn,
            en           => en,
            we           => we,
            addr         => addr,
            wdata        => wdata,
            rdata        => rdata,
            master       => master,
            irq_in       => irq_in,
            meip_out     => meip,
            wdt_routed   => wdt_routed,
            wdt_complete => wdt_complete
        );

    -- Single stimulus thread: walks the numbered checks in order and tallies failures.
    stim: process
        variable rd : std_logic_vector(31 downto 0);
        variable saw_pulse : boolean;

        -- Advance n rising clock edges.
        procedure tick(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        -- Read: a one-cycle strobe, with the registered result sampled the cycle after it.
        procedure bus_read(waddr : natural; mst : natural;
                           variable v : out std_logic_vector(31 downto 0)) is
        begin
            wait until rising_edge(clk);
            en     <= '1';
            we     <= "0000";
            addr   <= conv_std_logic_vector(waddr, 10);
            master <= conv_std_logic_vector(mst, MW);
            wait until rising_edge(clk);
            en <= '0';
            wait until rising_edge(clk);
            v := rdata;
        end procedure;

        -- Write: same one-cycle strobe, with the byte lanes carried in we.
        procedure bus_write(waddr : natural; mst : natural;
                            v : std_logic_vector(31 downto 0);
                            lanes : std_logic_vector(3 downto 0)) is
        begin
            wait until rising_edge(clk);
            en     <= '1';
            we     <= lanes;
            addr   <= conv_std_logic_vector(waddr, 10);
            wdata  <= v;
            master <= conv_std_logic_vector(mst, MW);
            wait until rising_edge(clk);
            en <= '0';
            we <= "0000";
            wait until rising_edge(clk);
        end procedure;

        -- Scoreboard: report and tally a failed condition, leave a passing one silent.
        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                fails <= fails + 1;
                report "CHECK FAILED: " & msg severity error;
                wait for 0 ns;  -- Let the fails increment land before the next check reads it.
            end if;
        end procedure;

        variable rd32 : std_logic_vector(31 downto 0);
        variable enx  : std_logic_vector(31 downto 0);
    begin
        -- Reset the DUT, then let it settle before the first access.
        resetn <= '0';
        tick(4);
        resetn <= '1';
        tick(2);

        -- 1. Reset state: every row reads 0 and no meip is asserted. -----------
        check(meip = conv_std_logic_vector(0, NHARTS), "reset: meip not all-0");
        bus_read(0, 0, rd32);
        check(rd32 = x"00000000", "reset: H0ENL not 0");

        -- 2. Row read/write, lane merge, top-EN-word masking and the reserved word.
        bus_write(4*3 + 0, 0, x"DEADBEEF", "1111");           -- H3ENL
        bus_read(4*3 + 0, 1, rd32);
        check(rd32 = x"DEADBEEF", "H3ENL readback");
        bus_write(4*3 + 0, 0, x"115500AA", "0011");           -- Lane-merge the low half only.
        bus_read(4*3 + 0, 0, rd32);
        check(rd32 = x"DEAD00AA", "H3ENL lane merge");
        -- Top enable word: only the low TOP_LIVE bits are live, and the rest are masked in storage.
        bus_write(4*3 + (NUM_EN_WORDS-1), 0, x"FFFFFFFF", "1111");
        bus_read(4*3 + (NUM_EN_WORDS-1), 0, rd32);
        if TOP_LIVE < 32 then
            check(conv_integer(rd32(31 downto TOP_LIVE)) = 0,
                  "top EN word dead bits not masked (storage)");
        end if;
        if NUM_EN_WORDS < 4 then
            bus_read(4*3 + 3, 0, rd32);
            check(rd32 = x"00000000", "reserved row word not 0");
        end if;
        bus_write(4*3 + 0, 0, x"00000000", "1111");           -- Clean up row 3.
        bus_write(4*3 + (NUM_EN_WORDS-1), 0, x"00000000", "1111");

        -- 3. Dead row at index NHARTS, which is out of range in every shape. ---
        bus_write(4*NHARTS + 0, 0, x"FFFFFFFF", "1111");
        bus_read(4*NHARTS + 0, 0, rd32);
        check(rd32 = x"00000000", "dead row not 0");

        -- 4. A routed level raises meip on that hart and no other. ------------
        bus_write(4*1 + 0, 0, x"00000020", "1111");           -- H1ENL: source 5.
        irq_in(5) <= '1';
        tick(3);
        check(meip(1) = '1', "meip(1) did not rise");
        check(meip(0) = '0' and meip(2) = '0' and meip(3) = '0',
              "unrouted meip rose");

        -- 5. Multi-hart routing, then exactly-once claim. ---------------------
        bus_write(4*2 + 0, 0, x"00000020", "1111");           -- H2ENL: source 5 as well.
        tick(3);
        check(meip(2) = '1', "meip(2) did not rise (multi-route)");
        bus_read(W_CLAIM, 2, rd32);                            -- Hart 2 claims.
        check(rd32 = x"00000005", "claim(hart2) /= 5");
        tick(2);
        check(meip(1) = '0' and meip(2) = '0',
              "in_service did not mask meip on all harts");
        bus_read(W_CLAIM, 1, rd32);                            -- Hart 1 finds nothing left.
        check(rd32 = SENTINEL, "second claim not sentinel");

        -- 6. Complete: re-pends while the level is high, is owner-unqualified, and treats the sentinel as a no-op.
        bus_write(W_CLAIM, 0, SENTINEL, "1111");               -- Completing the sentinel must do nothing.
        tick(2);
        check(meip(1) = '0', "sentinel complete had an effect");
        bus_write(W_CLAIM, 1, x"00000005", "1111");            -- Hart 1 completes hart 2's claim.
        tick(3);
        check(meip(1) = '1' and meip(2) = '1',
              "re-pend after complete-with-level-high failed");
        irq_in(5) <= '0';                                      -- The ISR has cleared the source level.
        tick(3);
        check(meip(1) = '0' and meip(2) = '0', "meip stuck after level drop");

        -- 7. Lowest-ID priority among pending sources. -------------------------
        bus_write(4*0 + 0, 0, x"00000408", "1111");            -- H0ENL: sources 3 and 10.
        irq_in(3)  <= '1';
        irq_in(10) <= '1';
        tick(3);
        check(meip(0) = '1', "meip(0) did not rise");
        bus_read(W_CLAIM, 0, rd32);
        check(rd32 = x"00000003", "priority: first claim /= 3");
        bus_read(W_CLAIM, 0, rd32);
        check(rd32 = x"0000000A", "priority: second claim /= 10");

        -- 8. Status words: PENDL tracks the levels, INSVCL the claims. ----------
        bus_read(516, 0, rd32);                                 -- PENDL
        check(rd32(3) = '1' and rd32(10) = '1', "PENDL levels wrong");
        bus_read(520, 0, rd32);                                 -- INSVCL
        check(rd32(3) = '1' and rd32(10) = '1', "INSVCL flags wrong");
        irq_in(3)  <= '0';
        irq_in(10) <= '0';
        bus_write(W_CLAIM, 0, x"00000003", "1111");
        bus_write(W_CLAIM, 0, x"0000000A", "1111");
        bus_read(520, 0, rd32);
        check(rd32 = x"00000000", "INSVCL not cleared after completes");
        bus_write(4*0 + 0, 0, x"00000000", "1111");             -- Clean row 0.

        -- 8b. PENDX and INSVCX, words 519 and 523. ----------------------------
        if NUM_SRCS > 96 then
            -- Full walk of a word-3 source, SRC_X = NUM_SRCS-1, on hart 0.
            bus_read(519, 0, rd32);
            check(rd32 = x"00000000", "PENDX not 0 while idle");
            enx := (others => '0');
            enx(BX) := '1';
            bus_write(4*0 + 3, 0, enx, "1111");                 -- H0ENX: route SRC_X to hart 0.
            irq_in(SRC_X) <= '1';
            tick(3);
            check(meip(0) = '1', "meip(0) did not rise for word-3 source");
            bus_read(519, 0, rd32);
            check(rd32(BX) = '1', "PENDX bit not set");
            bus_read(523, 0, rd32);
            check(rd32 = x"00000000", "INSVCX set before claim");
            bus_read(W_CLAIM, 0, rd32);
            check(rd32 = conv_std_logic_vector(SRC_X, 32), "claim /= word-3 source");
            bus_read(523, 0, rd32);
            check(rd32(BX) = '1', "INSVCX bit not set after claim");
            irq_in(SRC_X) <= '0';                               -- The ISR clears the source level.
            bus_write(W_CLAIM, 0, conv_std_logic_vector(SRC_X, 32), "1111");
            bus_read(523, 0, rd32);
            check(rd32 = x"00000000", "INSVCX not cleared after complete");
            bus_read(519, 0, rd32);
            check(rd32 = x"00000000", "PENDX not 0 after level drop");
            bus_write(4*0 + 3, 0, x"00000000", "1111");         -- Clean H0ENX.
        else
            -- Additive safety: a 3-EN-word shape must read both X words as 0.
            bus_read(519, 0, rd32);
            check(rd32 = x"00000000", "PENDX not 0 at NUM_SRCS <= 96");
            bus_read(523, 0, rd32);
            check(rd32 = x"00000000", "INSVCX not 0 at NUM_SRCS <= 96");
        end if;

        -- 9. CLINT sources never reach meip, even when routed. ------------------
        bus_write(4*1 + 2, 0, x"00180000", "1111");             -- H1ENU bits 19 and 20, i.e. sources 83 and 84.
        irq_in(83) <= '1';
        irq_in(84) <= '1';
        tick(3);
        check(meip(1) = '0', "CLINT source leaked into meip");
        irq_in(83) <= '0';
        irq_in(84) <= '0';
        bus_write(4*1 + 2, 0, x"00000000", "1111");

        -- 10. WDT hooks: the wdt_routed reduction and the COMPLETE(0) pulse. -----
        check(wdt_routed = '0', "wdt_routed high with source 0 unrouted");
        bus_write(4*2 + 0, 0, x"00000001", "1111");             -- H2ENL: source 0, the WDT.
        tick(1);
        check(wdt_routed = '1', "wdt_routed did not rise");
        irq_in(0) <= '1';
        tick(3);
        check(meip(2) = '1', "WDT source did not deliver");
        bus_read(W_CLAIM, 2, rd32);
        check(rd32 = x"00000000", "WDT claim /= 0");
        irq_in(0) <= '0';
        -- A COMPLETE of source 0 must pulse wdt_complete for exactly one cycle, so the write is driven inline and the pulse width is watched.
        saw_pulse := false;
        wait until rising_edge(clk);
        en     <= '1';
        we     <= "1111";
        addr   <= conv_std_logic_vector(W_CLAIM, 10);
        wdata  <= x"00000000";
        master <= conv_std_logic_vector(2, MW);
        wait until rising_edge(clk);
        en <= '0';
        we <= "0000";
        for i in 1 to 4 loop
            wait until rising_edge(clk);
            if wdt_complete = '1' then
                if saw_pulse then
                    check(false, "wdt_complete longer than one cycle");
                end if;
                saw_pulse := true;
            end if;
        end loop;
        check(saw_pulse, "no wdt_complete pulse on COMPLETE(0)");
        bus_write(4*2 + 0, 0, x"00000000", "1111");
        tick(1);
        check(wdt_routed = '0', "wdt_routed did not fall");

        -- Verdict: report the tally and stop the clock. -------------------------
        tick(2);
        if fails = 0 then
            report "ALL CHECKS PASSED" severity note;
        else
            report "CHECKS FAILED: " & integer'image(fails) severity error;
        end if;
        done <= true;
        wait;
    end process;

end architecture;
