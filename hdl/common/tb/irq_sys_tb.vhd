/* =============================================================================
   irq_sys_tb.vhd: self-checking unit testbench for clint.vhd, the per-hart msip IPIs plus the 64-bit mtime/mtimecmp mtip levels.
   The CLINT sits behind mp_arbiter in the real system, so here the tb drives its slave port directly with the shared-bus contract: a one-cycle active-high en strobe, four active-high byte-lane strobes, and a registered read with the address at T and rdata at T+1.
   Checks: reset state (msip/mtip low, mtimecmp all-ones); msip set/clear with bit-0, lane-0-only write decode; mtime free-running, lo/hi writable, lane-merge; mtip not before and at the programmed count, the ISR clear contract, a lo-only write that must not fire, and a true 64-bit compare across the 2^32 boundary.
   The interrupt router is a separate DUT with its own testbench, irq_router_tb.vhd.
   The runner script greps the pass banner "ALL CHECKS PASSED".
   ============================================================================= */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity irq_sys_tb is
end entity;

architecture tb of irq_sys_tb is

    constant NHARTS     : natural := 4;
    constant CLK_PERIOD : time    := 10 ns;

    subtype word_t is std_logic_vector(31 downto 0);

    -- CLINT word map (clint.vhd)
    constant CA_MSIP0    : natural := 0;   -- +h for hart h
    constant CA_MTIME_LO : natural := 4;
    constant CA_MTIME_HI : natural := 5;
    constant CA_CMP0_LO  : natural := 8;   -- +2h for hart h

    signal clk        : std_logic := '0';
    signal resetn     : std_logic := '0';
    signal stop_clock : boolean   := false;
    signal test_done  : boolean   := false;

    -- clint slave port
    signal c_en    : std_logic := '0';
    signal c_we    : std_logic_vector(3 downto 0) := (others => '0');
    signal c_addr  : std_logic_vector(3 downto 0) := (others => '0');
    signal c_wdata : word_t := (others => '0');
    signal c_rdata : word_t;
    signal msip    : std_logic_vector(NHARTS-1 downto 0);
    signal mtip    : std_logic_vector(NHARTS-1 downto 0);

begin

    clk_gen: process
    begin
        while not stop_clock loop
            clk <= '0'; wait for CLK_PERIOD/2;
            clk <= '1'; wait for CLK_PERIOD/2;
        end loop;
        wait;
    end process;

    resetn <= '0', '1' after 5*CLK_PERIOD;

    dut_clint: entity work.clint
        generic map (NHARTS => NHARTS)
        port map (
            clk    => clk,
            resetn => resetn,
            en     => c_en,
            we     => c_we,
            addr   => c_addr,
            wdata  => c_wdata,
            rdata  => c_rdata,
            msip   => msip,
            mtip   => mtip
        );

    -- The whole tb is a few thousand cycles, so anything past 1 ms of sim time is a hang
    watchdog: process
    begin
        wait for 1 ms;
        if not test_done then
            report "WATCHDOG: testbench did not finish" severity failure;
        end if;
        wait;
    end process;

    -- ------------------------------------------------------------------------
    -- Single stimulus and checker process: phases A to D, then the banner
    stim: process
        variable errs : natural := 0;
        variable rd   : word_t;
        variable t1   : word_t;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errs := errs + 1;
                report "CHECK FAILED: " & msg severity error;
            end if;
        end procedure;

        -- CLINT write; bus contract is en strobed for exactly one clk
        procedure cwr(a : natural; d : word_t;
                      lanes : std_logic_vector(3 downto 0)) is
        begin
            c_en <= '1'; c_we <= lanes;
            c_addr <= conv_std_logic_vector(a, 4); c_wdata <= d;
            wait until rising_edge(clk);
            c_en <= '0'; c_we <= (others => '0');
        end procedure;

        -- CLINT read: address accepted at T, registered data back at T+1
        procedure crd(a : natural; d : out word_t) is
        begin
            c_en <= '1'; c_we <= (others => '0');
            c_addr <= conv_std_logic_vector(a, 4);
            wait until rising_edge(clk);          -- address accepted at T
            c_en <= '0';
            wait until rising_edge(clk);          -- rdata valid at T+1
            d := c_rdata;
        end procedure;

        procedure wait_cycles(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        -- Poll mtip(h) for a level; the budget must trip well inside the tb watchdog
        procedure wait_mtip(h : natural; val : std_logic;
                            budget : natural; msg : string) is
            variable n : natural := 0;
        begin
            while mtip(h) /= val and n < budget loop
                wait until rising_edge(clk);
                n := n + 1;
            end loop;
            check(mtip(h) = val, msg);
        end procedure;

    begin
        wait until resetn = '1';
        wait until rising_edge(clk);

        -- ==================================================================
        report "PHASE A: reset state";
        -- ==================================================================
        check(msip = "0000", "A: msip not all-low out of reset");
        check(mtip = "0000", "A: mtip not all-low out of reset");

        for h in 0 to NHARTS-1 loop
            crd(CA_MSIP0 + h, rd);
            check(rd = x"00000000",
                  "A: msip[" & integer'image(h) & "] readback not 0");
            crd(CA_CMP0_LO + 2*h, rd);
            check(rd = x"FFFFFFFF",
                  "A: mtimecmp[" & integer'image(h) & "] lo not all-ones at reset");
            crd(CA_CMP0_LO + 2*h + 1, rd);
            check(rd = x"FFFFFFFF",
                  "A: mtimecmp[" & integer'image(h) & "] hi not all-ones at reset");
        end loop;

        crd(CA_MTIME_LO, t1);
        crd(CA_MTIME_LO, rd);
        check(rd > t1, "A: mtime lo not free-running");

        crd(6, rd);  check(rd = x"00000000", "A: CLINT reserved word 6 not 0");
        crd(7, rd);  check(rd = x"00000000", "A: CLINT reserved word 7 not 0");
        cwr(6, x"FFFFFFFF", "1111");   -- Writes to reserved words must be dead
        crd(6, rd);  check(rd = x"00000000", "A: CLINT reserved word 6 took a write");

        -- ==================================================================
        report "PHASE B: CLINT msip IPIs";
        -- ==================================================================
        cwr(CA_MSIP0 + 2, x"00000001", "1111");        -- IPI to hart 2
        wait_cycles(1);
        check(msip = "0100", "B: msip[2]=1 did not raise exactly msip(2)");
        crd(CA_MSIP0 + 2, rd);
        check(rd = x"00000001", "B: msip[2] readback not exactly bit 0");

        -- msip is bit 0 in lane 0 ONLY, so a write missing lane 0 must be dead
        cwr(CA_MSIP0 + 1, x"00000001", "1110");
        wait_cycles(1);
        check(msip(1) = '0', "B: msip[1] set by a write with lane 0 off");

        cwr(CA_MSIP0 + 0, x"00000001", "1111");        -- second IPI, hart 0
        wait_cycles(1);
        check(msip = "0101", "B: msip(0)+msip(2) expected");

        cwr(CA_MSIP0 + 2, x"00000000", "1111");        -- ISR clears the level
        wait_cycles(1);
        check(msip = "0001", "B: clearing msip[2] disturbed other harts");
        cwr(CA_MSIP0 + 0, x"00000000", "1111");
        wait_cycles(1);
        check(msip = "0000", "B: msip not all-clear after clears");

        -- ==================================================================
        report "PHASE C: mtime write + lane-merge";
        -- ==================================================================
        cwr(CA_MTIME_LO, x"00000100", "1111");
        cwr(CA_MTIME_HI, x"00000000", "1111");
        crd(CA_MTIME_LO, rd);
        check(rd >= x"00000100" and rd < x"00000120",
              "C: mtime lo not near the written value");
        crd(CA_MTIME_HI, rd);
        check(rd = x"00000000", "C: mtime hi not 0 after write");

        -- Lane-merge byte 1 only; byte 0 keeps ticking from a small value, so the upper three bytes must read back exactly AA 00 00.
        cwr(CA_MTIME_LO, x"0000AA00", "0010");
        crd(CA_MTIME_LO, rd);
        check((rd and x"FFFFFF00") = x"0000AA00",
              "C: mtime lo lane-merge clobbered other lanes");

        -- ==================================================================
        report "PHASE D: mtimecmp / mtip levels";
        -- ==================================================================
        -- D1: program hart 1 about 300 ticks out, then check not-before, fires, and the ISR clear
        cwr(CA_MTIME_LO, x"00000000", "1111");
        cwr(CA_MTIME_HI, x"00000000", "1111");
        cwr(CA_CMP0_LO + 2*1,     x"0000012C", "1111");  -- lo first; hi is still all-ones
        cwr(CA_CMP0_LO + 2*1 + 1, x"00000000", "1111");  -- so arming this way cannot fire early
        crd(CA_CMP0_LO + 2*1, rd);
        check(rd = x"0000012C", "D1: mtimecmp[1] lo readback");
        check(mtip = "0000", "D1: mtip fired at arming time");
        wait_cycles(200);
        check(mtip(1) = '0', "D1: mtip(1) fired ~100 ticks EARLY");
        wait_mtip(1, '1', 200, "D1: mtip(1) never fired");
        check(mtip(0) = '0' and mtip(2) = '0' and mtip(3) = '0',
              "D1: mtip cross-hart leak");
        -- ISR contract: advancing mtimecmp clears the pending level
        cwr(CA_CMP0_LO + 2*1 + 1, x"00010000", "1111");
        wait_cycles(4);
        check(mtip(1) = '0', "D1: advancing mtimecmp[1] did not clear mtip(1)");

        -- D2: reset-all-ones contract, writing ONLY the lo word must not fire because hi is still FFFFFFFF, and writing hi=0 then fires immediately.
        cwr(CA_CMP0_LO + 2*3, x"00000000", "1111");
        wait_cycles(20);
        check(mtip(3) = '0', "D2: mtip(3) fired with cmp hi still all-ones");
        cwr(CA_CMP0_LO + 2*3 + 1, x"00000000", "1111");
        wait_mtip(3, '1', 10, "D2: mtip(3) did not fire with cmp=0");
        cwr(CA_CMP0_LO + 2*3,     x"FFFFFFFF", "1111");  -- park hart 3 again
        cwr(CA_CMP0_LO + 2*3 + 1, x"FFFFFFFF", "1111");
        wait_cycles(4);
        check(mtip(3) = '0', "D2: mtip(3) stuck after re-parking cmp");

        -- D3: TRUE 64-bit compare across the 2^32 boundary, with mtime starting at 0x0_FFFFFF00 and cmp[0] at 0x1_00000080, roughly 0x180 ticks out.
        -- A lo-only compare fires almost immediately (FFFFFFxx is already >= 00000080) and dies on the 64-cycle not-before check; the 256-cycle check sits just past the boundary, where mtip must still be low.
        cwr(CA_MTIME_LO, x"FFFFFF00", "1111");
        cwr(CA_MTIME_HI, x"00000000", "1111");
        cwr(CA_CMP0_LO + 2*0,     x"00000080", "1111");
        cwr(CA_CMP0_LO + 2*0 + 1, x"00000001", "1111");
        wait_cycles(64);
        check(mtip(0) = '0', "D3: mtip(0) fired early (lo-word-only compare?)");
        wait_cycles(192);
        check(mtip(0) = '0', "D3: mtip(0) fired early just past the 2^32 boundary");
        wait_mtip(0, '1', 300, "D3: mtip(0) never fired across the boundary");
        cwr(CA_CMP0_LO + 2*0,     x"FFFFFFFF", "1111");
        cwr(CA_CMP0_LO + 2*0 + 1, x"FFFFFFFF", "1111");
        wait_cycles(4);
        check(mtip = "0000", "D3: mtip not all-clear after cleanup");

        -- ==================================================================
        -- Scoreboard and PASS banner
        wait_cycles(4);
        if errs = 0 then
            report "ALL CHECKS PASSED" severity note;
        else
            report "CHECKS FAILED: " & integer'image(errs) & " check(s)"
                severity failure;
        end if;

        test_done  <= true;
        stop_clock <= true;
        wait;
    end process;

end architecture;
