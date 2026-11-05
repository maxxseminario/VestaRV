-- verification/perf_mp: non-intrusive measurement monitor for the multi-hart Castalia behavioral sim.
-- Compiled -V200X; Xcelium 20.09 accepts external names but not as alias targets, hence the copy signals; it reads RTL signals and, when STALL_D > 0, forces mp_arbiter's slave-stall
-- input to inject a KNOWN test-side delay (the negative control). No RTL file is edited.
--
-- All sampling is on the FALLING edge of mclk, so every signal has settled for the cycle opened by the last rising edge
-- and delta-races between the gated clocks and this process cannot matter. "cycle n" = the n-th mclk cycle since time 0.
--
-- Output file perf_mon.log, one record per line:
--   W <cyc> <master> <byteaddr-hex> <data-hex>                    store to the print window 0x1F000-0x1FFFF
--   S <hart> <txn> <wait_sum> <wait_max>                          per-hart arbiter stats since last dump (req rise -> done)
--   L <hart> <t_level> <t_entry> <t_isr> <pc_at_level-hex> <src>  one interrupt
-- Interrupt record: t_level = first cycle the level is high at the hart's port (clint_msip/clint_mtip/meip, the tile
-- boundary), t_entry = first cycle of the entry state (hpm_ev_trap), t_isr = cycle the instruction at ISR_ADDR retires.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity perf_mon is
    generic (
        ISR_ADDR : std_logic_vector(31 downto 0) := x"00009100";
        STALL_D  : natural := 0;                         -- extra LATCH cycles per shared-RAM transaction (negative control)
        LOGNAME  : string := "perf_mon.log"
    );
end entity;

architecture sim of perf_mon is
    constant NH : natural := 5;
    type slv32_arr is array (0 to NH-1) of std_logic_vector(31 downto 0);



    signal mclk : std_logic;
    signal sh_en : std_logic;
    signal sh_addr : std_logic_vector(15 downto 0);
    signal sh_we : std_logic_vector(3 downto 0);
    signal sh_wdata : std_logic_vector(31 downto 0);
    signal sh_master : std_logic_vector(2 downto 0);
    signal arb_req : std_logic_vector(6 downto 0);
    signal arb_done : std_logic_vector(6 downto 0);
    signal c_msip : std_logic_vector(4 downto 0);
    signal c_mtip : std_logic_vector(4 downto 0);
    signal c_meip : std_logic_vector(4 downto 0);
    signal pc0 : std_logic_vector(31 downto 0);
    signal pc1 : std_logic_vector(31 downto 0);
    signal pc2 : std_logic_vector(31 downto 0);
    signal pc3 : std_logic_vector(31 downto 0);
    signal pc4 : std_logic_vector(31 downto 0);
    signal rt0 : std_logic;
    signal rt1 : std_logic;
    signal rt2 : std_logic;
    signal rt3 : std_logic;
    signal rt4 : std_logic;
    signal tr0 : std_logic;
    signal tr1 : std_logic;
    signal tr2 : std_logic;
    signal tr3 : std_logic;
    signal tr4 : std_logic;

    file logf : text;
    file hbf : text;

    function hex(v : std_logic_vector) return string is
        constant HEXC : string(1 to 16) := "0123456789abcdef";
        constant N : natural := (v'length + 3) / 4;
        variable x : std_logic_vector(N*4-1 downto 0) := (others => '0');
        variable r : string(1 to N);
        variable d : natural;
    begin
        x(v'length-1 downto 0) := v;
        for i in 0 to N-1 loop
            if is_x(x(i*4+3 downto i*4)) then
                r(N-i) := 'x';
            else
                d := to_integer(unsigned(x(i*4+3 downto i*4)));
                r(N-i) := HEXC(d+1);
            end if;
        end loop;
        return r;
    end function;
begin
    mclk <= << signal .perf_top.uut.dut.mclk : std_logic >>;
    sh_en <= << signal .perf_top.uut.dut.sh_en : std_logic >>;
    sh_addr <= << signal .perf_top.uut.dut.sh_addr : std_logic_vector(15 downto 0) >>;
    sh_we <= << signal .perf_top.uut.dut.sh_we_raw : std_logic_vector(3 downto 0) >>;
    sh_wdata <= << signal .perf_top.uut.dut.sh_wdata : std_logic_vector(31 downto 0) >>;
    sh_master <= << signal .perf_top.uut.dut.sh_master : std_logic_vector(2 downto 0) >>;
    arb_req <= << signal .perf_top.uut.dut.arb_req : std_logic_vector(6 downto 0) >>;
    arb_done <= << signal .perf_top.uut.dut.arb_done : std_logic_vector(6 downto 0) >>;
    c_msip <= << signal .perf_top.uut.dut.clint_msip : std_logic_vector(4 downto 0) >>;
    c_mtip <= << signal .perf_top.uut.dut.clint_mtip : std_logic_vector(4 downto 0) >>;
    c_meip <= << signal .perf_top.uut.dut.meip : std_logic_vector(4 downto 0) >>;
    pc0 <= << signal .perf_top.uut.dut.hart0.tile.core.pc : std_logic_vector(31 downto 0) >>;
    pc1 <= << signal .perf_top.uut.dut.hart1.core.pc : std_logic_vector(31 downto 0) >>;
    pc2 <= << signal .perf_top.uut.dut.hart2.core.pc : std_logic_vector(31 downto 0) >>;
    pc3 <= << signal .perf_top.uut.dut.hart3.core.pc : std_logic_vector(31 downto 0) >>;
    pc4 <= << signal .perf_top.uut.dut.hart4.core.pc : std_logic_vector(31 downto 0) >>;
    rt0 <= << signal .perf_top.uut.dut.hart0.tile.core.inst_retired : std_logic >>;
    rt1 <= << signal .perf_top.uut.dut.hart1.core.inst_retired : std_logic >>;
    rt2 <= << signal .perf_top.uut.dut.hart2.core.inst_retired : std_logic >>;
    rt3 <= << signal .perf_top.uut.dut.hart3.core.inst_retired : std_logic >>;
    rt4 <= << signal .perf_top.uut.dut.hart4.core.inst_retired : std_logic >>;
    tr0 <= << signal .perf_top.uut.dut.hart0.tile.core.hpm_ev_trap : std_logic >>;
    tr1 <= << signal .perf_top.uut.dut.hart1.core.hpm_ev_trap : std_logic >>;
    tr2 <= << signal .perf_top.uut.dut.hart2.core.hpm_ev_trap : std_logic >>;
    tr3 <= << signal .perf_top.uut.dut.hart3.core.hpm_ev_trap : std_logic >>;
    tr4 <= << signal .perf_top.uut.dut.hart4.core.hpm_ev_trap : std_logic >>;

    main: process
        variable l : line;
        variable cyc : integer := 0;
        type int_arr is array (0 to NH-1) of integer;
        variable txn, wsum, wmax, wcur, ret : int_arr := (others => 0);
        variable inreq, req_d : std_logic_vector(NH-1 downto 0) := (others => '0');
        variable lvl, lvl_d : std_logic_vector(NH-1 downto 0) := (others => '0');
        variable open_i : std_logic_vector(NH-1 downto 0) := (others => '0');
        variable t_lvl, t_ent : int_arr := (others => 0);
        variable seen_ent : std_logic_vector(NH-1 downto 0) := (others => '0');
        variable pcs : slv32_arr;
        variable pc_l : slv32_arr;
        variable src : string(1 to NH);
        variable rt, tr : std_logic_vector(NH-1 downto 0);
        variable stall_left : integer := 0;
        variable forcing : boolean := false;
    begin
        file_open(logf, LOGNAME, write_mode);
        loop
            wait until falling_edge(mclk);
            cyc := cyc + 1;
            pcs := (pc0, pc1, pc2, pc3, pc4);
            rt := rt4 & rt3 & rt2 & rt1 & rt0;
            -- Heartbeat: retires per hart, so a long run is told from a hang by the subject's own progress, not by time.
            for h in 0 to NH-1 loop
                if rt(h) = '1' then ret(h) := ret(h) + 1; end if;
            end loop;
            if cyc mod 4000000 = 0 then
                -- Open/append/close each time: xmsim buffers its log and TEXTIO files for tens of minutes, and a buffered
                -- heartbeat is indistinguishable from a hang.
                file_open(hbf, "heartbeat.log", append_mode);
                write(l, cyc); write(l, string'(" "));
                for h in 0 to NH-1 loop write(l, ret(h)); write(l, string'(" ")); end loop;
                writeline(hbf, l);
                file_close(hbf);
            end if;
            tr := tr4 & tr3 & tr2 & tr1 & tr0;

            -- Negative control: hold the arbiter in LATCH for STALL_D extra rising edges on each shared-RAM access.
            -- sh_addr word index 0x4000-0x7FFF = bytes 0x10000-0x1FFFF, the shared bulk RAM.
            if STALL_D > 0 then
                if sh_en = '1' and sh_addr(15 downto 14) = "01" then
                    stall_left := STALL_D;
                end if;
                if stall_left > 0 then
                    if not forcing then << signal .perf_top.uut.dut.tcmw_stall : std_logic >> <= force '1'; forcing := true; end if;
                    stall_left := stall_left - 1;
                elsif forcing then
                    << signal .perf_top.uut.dut.tcmw_stall : std_logic >> <= release; forcing := false;
                end if;
            end if;

            -- print window 0x1F000-0x1FFFF = word 0x7C00-0x7FFF
            if sh_en = '1' and sh_we /= "0000" and sh_addr(15 downto 10) = "011111" then
                write(l, string'("W ")); write(l, cyc); write(l, string'(" "));
                write(l, to_integer(unsigned(sh_master))); write(l, string'(" "));
                write(l, hex(sh_addr & "00")); write(l, string'(" ")); write(l, hex(sh_wdata));
                writeline(logf, l);
                -- word 0x7FFF (0x1FFFC): dump and clear the arbiter stats
                if sh_addr = x"7FFF" then
                    for h in 0 to NH-1 loop
                        write(l, string'("S ")); write(l, h); write(l, string'(" ")); write(l, txn(h));
                        write(l, string'(" ")); write(l, wsum(h)); write(l, string'(" ")); write(l, wmax(h));
                        writeline(logf, l);
                        txn(h) := 0; wsum(h) := 0; wmax(h) := 0;
                    end loop;
                end if;
            end if;

            for h in 0 to NH-1 loop
                -- arbiter wait per transaction: cycles req is high up to and including done
                if arb_req(h) = '1' and req_d(h) = '0' and inreq(h) = '0' then
                    inreq(h) := '1'; wcur(h) := 0;
                end if;
                if inreq(h) = '1' then
                    wcur(h) := wcur(h) + 1;
                    if arb_done(h) = '1' then
                        txn(h) := txn(h) + 1; wsum(h) := wsum(h) + wcur(h);
                        if wcur(h) > wmax(h) then wmax(h) := wcur(h); end if;
                        inreq(h) := '0';
                    end if;
                end if;

                req_d(h) := arb_req(h);
                -- interrupt latency
                lvl(h) := c_msip(h) or c_mtip(h) or c_meip(h);
                if lvl(h) = '1' and lvl_d(h) = '0' and open_i(h) = '0' then
                    open_i(h) := '1'; t_lvl(h) := cyc; pc_l(h) := pcs(h); seen_ent(h) := '0';
                    if c_mtip(h) = '1' then src(h+1) := 't';
                    elsif c_msip(h) = '1' then src(h+1) := 's';
                    else src(h+1) := 'e'; end if;
                end if;
                lvl_d(h) := lvl(h);
                -- A level that drops with no retire at ISR_ADDR was not ours (the boot ROM's msip ignite): forget it.
                if lvl(h) = '0' then open_i(h) := '0'; end if;
                if open_i(h) = '1' then
                    if tr(h) = '1' and seen_ent(h) = '0' then
                        seen_ent(h) := '1'; t_ent(h) := cyc;
                    end if;
                    if rt(h) = '1' and pcs(h) = ISR_ADDR then
                        write(l, string'("L ")); write(l, h); write(l, string'(" ")); write(l, t_lvl(h));
                        write(l, string'(" ")); write(l, t_ent(h)); write(l, string'(" ")); write(l, cyc);
                        write(l, string'(" ")); write(l, hex(pc_l(h))); write(l, string'(" ")); write(l, src(h+1));
                        writeline(logf, l);
                        open_i(h) := '0';
                    end if;
                end if;
            end loop;
        end loop;
    end process;
end architecture;
