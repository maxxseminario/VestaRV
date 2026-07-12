-- =============================================================================
-- irq_sys_tb.vhd  -- self-checking testbench for the MP interrupt system
-- =============================================================================
-- Unit-level coverage for the two shared-window interrupt-delivery blocks,
-- neither of which had a standalone testbench before (both were covered only
-- indirectly through the full-system ISA tests shclint/shirq/shtimer):
--
--   clint.vhd      (M5b)  -- per-hart msip IPIs + 64-bit mtime/mtimecmp mtip
--   irq_router.vhd (M7a)  -- per-hart peripheral-IRQ enable rows (fan-out)
--
-- Both DUTs sit behind mp_arbiter in the real system; the arbiter has its own
-- testbench (mp_arbiter_tb), so here the tb drives each slave port directly
-- with the shared bus contract: active-high en one-cycle strobe, 4 active-high
-- byte-lane strobes, 1-cycle registered read (address at T, rdata at T+1).
--
-- Checks:
--   * reset state       -- msip/mtip low, mtimecmp all-ones, router all-masked
--                          (the router must be a provable NO-OP out of reset)
--   * msip IPIs         -- per-hart set/clear, bit-0/lane-0-only write decode
--   * mtime             -- free-runs, lo/hi writable, lane-merge
--   * mtimecmp/mtip     -- level fires not-before/at the programmed count;
--                          ISR clear contract (advance cmp -> level drops);
--                          lo-write with hi still at reset all-ones must NOT
--                          fire; TRUE 64-bit compare across the 2^32 boundary
--                          (a lo-word-only compare fails the not-before check)
--   * router registers  -- per-row L/M/U read/write, reserved word dead,
--                          lane-merge, row isolation, irq_en_out flattening
--   * ENU packing guard -- router ENU is CONTIGUOUS both ways (bits 84:64 =
--                          word bits 20:0) -- deliberately NOT SYSTEM0's
--                          SYS_IRQ_ENU write-packing quirk; this check burns
--                          anyone who "fixes" it to match
--   * integration       -- replicates hart_tile.vhd's gating (own msip/mtip
--                          override slots 83/84; row OR'd with the hardwired
--                          CLINT enables) and proves: a routed peripheral IRQ
--                          reaches exactly the routed hart, un-routing masks
--                          it again, and msip wakes a hart whose router row is
--                          all-zero (CLINT slots cannot be masked).
--
-- PASS banner: "ALL CHECKS PASSED" (grepped by run_irq_sys.sh).
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;
use work.MemoryMap.NUM_IRQS;
use work.MemoryMap.IRQB_CLINT_MSIP;
use work.MemoryMap.IRQB_CLINT_MTIP;
use work.MemoryMap.IRQB_TIM0_CMP2;

entity irq_sys_tb is
end entity;

architecture tb of irq_sys_tb is

    constant NHARTS     : natural := 4;
    constant CLK_PERIOD : time    := 10 ns;

    subtype word_t is std_logic_vector(31 downto 0);
    subtype vec_t  is std_logic_vector(NUM_IRQS-1 downto 0);

    constant ZERO_VEC : vec_t := (others => '0');

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

    -- irq_router slave port
    signal r_en       : std_logic := '0';
    signal r_we       : std_logic_vector(3 downto 0) := (others => '0');
    signal r_addr     : std_logic_vector(3 downto 0) := (others => '0');
    signal r_wdata    : word_t := (others => '0');
    signal r_rdata    : word_t;
    signal irq_en_out : std_logic_vector(NHARTS*NUM_IRQS-1 downto 0);

    -- hart h's row of the router fan-out (normalized to 84 downto 0)
    function router_row(flat : std_logic_vector; h : natural) return vec_t is
        variable r : vec_t;
    begin
        r := flat((h+1)*NUM_IRQS-1 downto h*NUM_IRQS);
        return r;
    end function;

    -- hart_tile.vhd's gating, replicated: the tile overrides irq_vector slots
    -- 83/84 with its OWN msip/mtip and enables (router row OR hardwired CLINT
    -- slots). What the core's irq_handler sees pending is vec AND en.
    function tile_pending(vec    : vec_t;
                          row    : vec_t;
                          msip_h : std_logic;
                          mtip_h : std_logic) return vec_t is
        variable v, en : vec_t;
    begin
        v := vec;
        v(IRQB_CLINT_MSIP) := msip_h;
        v(IRQB_CLINT_MTIP) := mtip_h;
        en := row;
        en(IRQB_CLINT_MSIP) := '1';   -- tile_irq_hw_en
        en(IRQB_CLINT_MTIP) := '1';
        return v and en;
    end function;

    -- expected 85-bit vector with a single bit set
    function one_bit(b : natural) return vec_t is
        variable v : vec_t := (others => '0');
    begin
        v(b) := '1';
        return v;
    end function;

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

    dut_router: entity work.irq_router
        generic map (NHARTS => NHARTS, NUM_IRQS => NUM_IRQS)
        port map (
            clk        => clk,
            resetn     => resetn,
            en         => r_en,
            we         => r_we,
            addr       => r_addr,
            wdata      => r_wdata,
            rdata      => r_rdata,
            irq_en_out => irq_en_out
        );

    -- 100ms-class watchdog scaled down: this whole tb is a few thousand
    -- cycles; anything past 1 ms of sim time is a hang.
    watchdog: process
    begin
        wait for 1 ms;
        if not test_done then
            report "WATCHDOG: testbench did not finish" severity failure;
        end if;
        wait;
    end process;

    -- ------------------------------------------------------------------------
    -- single stimulus + checker process
    -- ------------------------------------------------------------------------
    stim: process
        variable errs : natural := 0;
        variable rd   : word_t;
        variable t1   : word_t;
        variable exp  : vec_t;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errs := errs + 1;
                report "CHECK FAILED: " & msg severity error;
            end if;
        end procedure;

        -- CLINT access (bus contract: en strobed for exactly one clk)
        procedure cwr(a : natural; d : word_t;
                      lanes : std_logic_vector(3 downto 0)) is
        begin
            c_en <= '1'; c_we <= lanes;
            c_addr <= conv_std_logic_vector(a, 4); c_wdata <= d;
            wait until rising_edge(clk);
            c_en <= '0'; c_we <= (others => '0');
        end procedure;

        procedure crd(a : natural; d : out word_t) is
        begin
            c_en <= '1'; c_we <= (others => '0');
            c_addr <= conv_std_logic_vector(a, 4);
            wait until rising_edge(clk);          -- address accepted at T
            c_en <= '0';
            wait until rising_edge(clk);          -- rdata valid at T+1
            d := c_rdata;
        end procedure;

        -- irq_router access
        procedure rwr(a : natural; d : word_t;
                      lanes : std_logic_vector(3 downto 0)) is
        begin
            r_en <= '1'; r_we <= lanes;
            r_addr <= conv_std_logic_vector(a, 4); r_wdata <= d;
            wait until rising_edge(clk);
            r_en <= '0'; r_we <= (others => '0');
        end procedure;

        procedure rrd(a : natural; d : out word_t) is
        begin
            r_en <= '1'; r_we <= (others => '0');
            r_addr <= conv_std_logic_vector(a, 4);
            wait until rising_edge(clk);
            r_en <= '0';
            wait until rising_edge(clk);
            d := r_rdata;
        end procedure;

        procedure wait_cycles(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        -- poll mtip(h) for a level with a bounded budget (must trip well
        -- inside the tb watchdog -- same rule as the software tests)
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
        check(irq_en_out = (irq_en_out'range => '0'),
              "A: irq_en_out not all-masked out of reset (router must be a NO-OP)");

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
        cwr(6, x"FFFFFFFF", "1111");   -- reserved writes must be dead
        crd(6, rd);  check(rd = x"00000000", "A: CLINT reserved word 6 took a write");

        for w in 0 to 15 loop
            rrd(w, rd);
            check(rd = x"00000000",
                  "A: router word " & integer'image(w) & " not 0 at reset");
        end loop;

        -- ==================================================================
        report "PHASE B: CLINT msip IPIs";
        -- ==================================================================
        cwr(CA_MSIP0 + 2, x"00000001", "1111");        -- IPI to hart 2
        wait_cycles(1);
        check(msip = "0100", "B: msip[2]=1 did not raise exactly msip(2)");
        crd(CA_MSIP0 + 2, rd);
        check(rd = x"00000001", "B: msip[2] readback not exactly bit 0");

        -- msip is bit 0 / lane 0 ONLY: a write missing lane 0 must be dead
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

        -- lane-merge byte 1 only; byte 0 keeps ticking from a small value,
        -- so the upper three bytes must read back exactly AA 00 00
        cwr(CA_MTIME_LO, x"0000AA00", "0010");
        crd(CA_MTIME_LO, rd);
        check((rd and x"FFFFFF00") = x"0000AA00",
              "C: mtime lo lane-merge clobbered other lanes");

        -- ==================================================================
        report "PHASE D: mtimecmp / mtip levels";
        -- ==================================================================
        -- D1: program hart 1 ~300 ticks out; not-before, fires, ISR-clears
        cwr(CA_MTIME_LO, x"00000000", "1111");
        cwr(CA_MTIME_HI, x"00000000", "1111");
        cwr(CA_CMP0_LO + 2*1,     x"0000012C", "1111");  -- lo first: hi still
        cwr(CA_CMP0_LO + 2*1 + 1, x"00000000", "1111");  -- all-ones = safe
        crd(CA_CMP0_LO + 2*1, rd);
        check(rd = x"0000012C", "D1: mtimecmp[1] lo readback");
        check(mtip = "0000", "D1: mtip fired at arming time");
        wait_cycles(200);
        check(mtip(1) = '0', "D1: mtip(1) fired ~100 ticks EARLY");
        wait_mtip(1, '1', 200, "D1: mtip(1) never fired");
        check(mtip(0) = '0' and mtip(2) = '0' and mtip(3) = '0',
              "D1: mtip cross-hart leak");
        -- ISR contract: advancing mtimecmp clears the level
        cwr(CA_CMP0_LO + 2*1 + 1, x"00010000", "1111");
        wait_cycles(4);
        check(mtip(1) = '0', "D1: advancing mtimecmp[1] did not clear mtip(1)");

        -- D2: reset-all-ones contract -- writing ONLY the lo word must not
        -- fire (hi is still FFFFFFFF); writing hi=0 then fires immediately
        cwr(CA_CMP0_LO + 2*3, x"00000000", "1111");
        wait_cycles(20);
        check(mtip(3) = '0', "D2: mtip(3) fired with cmp hi still all-ones");
        cwr(CA_CMP0_LO + 2*3 + 1, x"00000000", "1111");
        wait_mtip(3, '1', 10, "D2: mtip(3) did not fire with cmp=0");
        cwr(CA_CMP0_LO + 2*3,     x"FFFFFFFF", "1111");  -- park hart 3 again
        cwr(CA_CMP0_LO + 2*3 + 1, x"FFFFFFFF", "1111");
        wait_cycles(4);
        check(mtip(3) = '0', "D2: mtip(3) stuck after re-parking cmp");

        -- D3: TRUE 64-bit compare across the 2^32 boundary. mtime starts at
        -- 0x0_FFFFFF00, cmp[0] = 0x1_00000080 (~0x180 ticks out). A lo-only
        -- compare fires ~immediately (FFFFFFxx >= 00000080) and dies on the
        -- 64-cycle not-before check; the 256-cycle check sits just PAST the
        -- boundary (mtime ~0x1_00000010) and must still be low.
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
        report "PHASE E: irq_router registers + fan-out";
        -- ==================================================================
        -- E1: hart 1 row, full L/M/U write + readback + flattening
        rwr(4*1 + 0, x"DEADBEEF", "1111");   -- H1ENL
        rwr(4*1 + 1, x"12345678", "1111");   -- H1ENM
        rwr(4*1 + 2, x"001FFFFF", "1111");   -- H1ENU (bits 20:0 live)
        rrd(4*1 + 0, rd);  check(rd = x"DEADBEEF", "E1: H1ENL readback");
        rrd(4*1 + 1, rd);  check(rd = x"12345678", "E1: H1ENM readback");
        rrd(4*1 + 2, rd);  check(rd = x"001FFFFF", "E1: H1ENU readback");

        exp(31 downto  0) := x"DEADBEEF";
        exp(63 downto 32) := x"12345678";
        exp(84 downto 64) := (others => '1');
        check(router_row(irq_en_out, 1) = exp, "E1: hart 1 fan-out flattening");
        check(router_row(irq_en_out, 0) = ZERO_VEC and
              router_row(irq_en_out, 2) = ZERO_VEC and
              router_row(irq_en_out, 3) = ZERO_VEC,
              "E1: write to row 1 leaked into another row");

        -- E2: reserved word (wsub=3) reads 0 and swallows writes
        rrd(4*1 + 3, rd);  check(rd = x"00000000", "E2: reserved word not 0");
        rwr(4*1 + 3, x"FFFFFFFF", "1111");
        rrd(4*1 + 3, rd);  check(rd = x"00000000", "E2: reserved word took a write");
        rrd(4*1 + 0, rd);  check(rd = x"DEADBEEF", "E2: reserved write hit H1ENL");

        -- E3: lane-merged write (row 2, lane 1 only)
        rwr(4*2 + 0, x"0000AB00", "0010");
        rrd(4*2 + 0, rd);
        check(rd = x"0000AB00", "E3: H2ENL lane-merge");
        check(router_row(irq_en_out, 2)(15 downto 8) = x"AB",
              "E3: lane-merged byte not on the fan-out");

        -- E4: ENU CONTIGUOUS packing guard (NOT the SYS_IRQ_ENU quirk).
        -- Word bit 19 -> irq bit 83 (msip slot), word bit 20 -> irq bit 84.
        rwr(4*3 + 2, x"00180000", "1111");
        wait_cycles(1);
        check(router_row(irq_en_out, 3)(IRQB_CLINT_MSIP) = '1' and
              router_row(irq_en_out, 3)(IRQB_CLINT_MTIP) = '1',
              "E4: ENU bits 20:19 must land on irq slots 84:83 (contiguous)");
        check(router_row(irq_en_out, 3)(82) = '0' and
              router_row(irq_en_out, 3)(64) = '0',
              "E4: ENU packing smeared into other slots");

        -- E5: row 0 exists (symmetry/debug) even though MCU.vhd leaves it unwired
        rwr(4*0 + 0, x"00000001", "1111");
        rrd(4*0 + 0, rd);  check(rd = x"00000001", "E5: row 0 not writable");
        rwr(4*0 + 0, x"00000000", "1111");

        -- clear everything written so phase F starts from all-masked
        rwr(4*1 + 0, x"00000000", "1111");
        rwr(4*1 + 1, x"00000000", "1111");
        rwr(4*1 + 2, x"00000000", "1111");
        rwr(4*2 + 0, x"00000000", "1111");
        rwr(4*3 + 2, x"00000000", "1111");
        wait_cycles(1);
        check(irq_en_out = (irq_en_out'range => '0'),
              "E: fan-out not all-masked after clears");

        -- ==================================================================
        report "PHASE F: integrated routing (hart_tile gating equation)";
        -- ==================================================================
        -- A shared TIMER0 compare IRQ is pending at the deglitcher output;
        -- hart 2 owns TIMER0 and routes the IRQ to itself. hart_tile's
        -- gating is replicated in tile_pending() above.

        -- F1: pending but unrouted -> NO hart sees it
        for h in 0 to NHARTS-1 loop
            check(tile_pending(one_bit(IRQB_TIM0_CMP2),
                               router_row(irq_en_out, h),
                               msip(h), mtip(h)) = ZERO_VEC,
                  "F1: unrouted peripheral IRQ pending at hart " & integer'image(h));
        end loop;

        -- F2: route slot IRQB_TIM0_CMP2 (=21, ENL word) to hart 2 only
        rwr(4*2 + 0, one_bit(IRQB_TIM0_CMP2)(31 downto 0), "1111");
        wait_cycles(1);
        check(tile_pending(one_bit(IRQB_TIM0_CMP2),
                           router_row(irq_en_out, 2),
                           msip(2), mtip(2)) = one_bit(IRQB_TIM0_CMP2),
              "F2: routed IRQ not pending at hart 2");
        check(tile_pending(one_bit(IRQB_TIM0_CMP2),
                           router_row(irq_en_out, 1),
                           msip(1), mtip(1)) = ZERO_VEC and
              tile_pending(one_bit(IRQB_TIM0_CMP2),
                           router_row(irq_en_out, 3),
                           msip(3), mtip(3)) = ZERO_VEC,
              "F2: routed IRQ leaked to a hart it was not routed to");

        -- F3: msip through an ALL-ZERO router row -- the tile's hardwired
        -- CLINT enables are OR'd over the row, so the IPI must get through
        cwr(CA_MSIP0 + 3, x"00000001", "1111");
        wait_cycles(1);
        check(tile_pending(ZERO_VEC,
                           router_row(irq_en_out, 3),
                           msip(3), mtip(3)) = one_bit(IRQB_CLINT_MSIP),
              "F3: msip masked by an all-zero router row (hardwired OR broken)");
        cwr(CA_MSIP0 + 3, x"00000000", "1111");

        -- F4: un-route (ISR handing the peripheral back) -> pending drops
        -- even though the peripheral level is still high
        rwr(4*2 + 0, x"00000000", "1111");
        wait_cycles(1);
        check(tile_pending(one_bit(IRQB_TIM0_CMP2),
                           router_row(irq_en_out, 2),
                           msip(2), mtip(2)) = ZERO_VEC,
              "F4: un-routed IRQ still pending at hart 2");

        -- ==================================================================
        -- scoreboard / banner
        -- ==================================================================
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
