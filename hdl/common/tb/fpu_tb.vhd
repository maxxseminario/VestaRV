-- =============================================================================
-- fpu_tb.vhd  (X4 Zfinx, Stage 2a)  -- self-checking unit testbench
-- =============================================================================
-- Drives fpu.vhd (multi-cycle) and fpu_simple.vhd (combinational) against
-- reference vectors produced by fpu_vec_gen.c (correction C4: x86 SSE single
-- precision + glibc fmaf). Reads $VECFILE (default ../fpu_vectors.txt), checks
-- BOTH result and flags on EVERY vector, verifies per-op done-latency and that
-- fpu_done/result hold stable until the next start. FAILS BOUNDED with a named
-- mismatch report; never hangs (per-vector done watchdog).
--
-- PASS banner (grepped by run_fpu.sh): "ALL CHECKS PASSED".
-- Compile: -V200X (no VHDL-2008).
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use STD.TEXTIO.all;

entity fpu_tb is
    generic (
        VECFILE  : string  := "fpu_vectors.txt";
        MAX_SHOW : integer := 50            -- max mismatch lines to print
    );
end entity;

architecture tb of fpu_tb is
    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    -- multi-cycle FPU
    signal fpu_start : std_logic := '0';
    signal fp_op     : std_logic_vector(3 downto 0) := (others => '0');
    signal rm        : std_logic_vector(2 downto 0) := (others => '0');
    signal fp_a, fp_b, fp_c : std_logic_vector(31 downto 0) := (others => '0');
    signal fpu_done  : std_logic;
    signal fp_result : std_logic_vector(31 downto 0);
    signal fp_flags  : std_logic_vector(4 downto 0);

    -- combinational FPU
    signal fp_s_op   : std_logic_vector(3 downto 0) := (others => '0');
    signal fp_s_a, fp_s_b : std_logic_vector(31 downto 0) := (others => '0');
    signal fp_s_result : std_logic_vector(31 downto 0);
    signal fp_s_flags  : std_logic_vector(4 downto 0);

    signal sim_done : boolean := false;

    -- op names for reports
    type name_arr is array(0 to 12) of string(1 to 10);
    constant MNAMES : name_arr := (
        "FADD      ","FSUB      ","FMUL      ","FDIV      ","FSQRT     ",
        "FMADD     ","FMSUB     ","FNMSUB    ","FNMADD    ","FCVT_W_S  ",
        "FCVT_WU_S ","FCVT_S_W  ","FCVT_S_WU ");
    type sname_arr is array(0 to 8) of string(1 to 8);
    constant SNAMES : sname_arr := (
        "FSGNJ   ","FSGNJN  ","FSGNJX  ","FEQ     ","FLT     ",
        "FLE     ","FMIN    ","FMAX    ","FCLASS  ");

    type int13  is array(0 to 12) of integer;
    type bool13 is array(0 to 12) of boolean;

    function hexc(c : character) return integer is
    begin
        case c is
            when '0' => return 0;  when '1' => return 1;  when '2' => return 2;
            when '3' => return 3;  when '4' => return 4;  when '5' => return 5;
            when '6' => return 6;  when '7' => return 7;  when '8' => return 8;
            when '9' => return 9;  when 'A' | 'a' => return 10;
            when 'B' | 'b' => return 11; when 'C' | 'c' => return 12;
            when 'D' | 'd' => return 13; when 'E' | 'e' => return 14;
            when 'F' | 'f' => return 15; when others => return 0;
        end case;
    end function;

    function hex8(s : string(1 to 8)) return std_logic_vector is
        variable v : unsigned(31 downto 0) := (others => '0');
    begin
        for i in 1 to 8 loop
            v := shift_left(v, 4) or to_unsigned(hexc(s(i)), 32);
        end loop;
        return std_logic_vector(v);
    end function;

    function hex2(s : string(1 to 2)) return std_logic_vector is
        variable v : unsigned(7 downto 0);
    begin
        v := to_unsigned(hexc(s(1)) * 16 + hexc(s(2)), 8);
        return std_logic_vector(v);
    end function;

    function dec2(s : string(1 to 2)) return integer is
    begin
        return hexc(s(1)) * 10 + hexc(s(2));   -- fields are 00..12 decimal
    end function;

    function hx(v : std_logic_vector) return string is
        constant HD : string(1 to 16) := "0123456789ABCDEF";
        constant ND : integer := (v'length + 3) / 4;
        variable u : unsigned(ND*4-1 downto 0) := resize(unsigned(v), ND*4);
        variable r : string(1 to ND);
        variable nib : integer;
    begin
        for i in 1 to ND loop
            nib := to_integer(u((ND-i)*4+3 downto (ND-i)*4));
            r(i) := HD(nib+1);
        end loop;
        return r;
    end function;

    component fpu is
        port (
            clk       : in  std_logic;
            resetn    : in  std_logic;
            fpu_start : in  std_logic;
            fp_op     : in  std_logic_vector(3 downto 0);
            rm        : in  std_logic_vector(2 downto 0);
            fp_a      : in  std_logic_vector(31 downto 0);
            fp_b      : in  std_logic_vector(31 downto 0);
            fp_c      : in  std_logic_vector(31 downto 0);
            fpu_done  : out std_logic;
            fp_result : out std_logic_vector(31 downto 0);
            fp_flags  : out std_logic_vector(4 downto 0)
        );
    end component;

    component fpu_simple is
        port (
            fp_s_op     : in  std_logic_vector(3 downto 0);
            fp_s_a      : in  std_logic_vector(31 downto 0);
            fp_s_b      : in  std_logic_vector(31 downto 0);
            fp_s_result : out std_logic_vector(31 downto 0);
            fp_s_flags  : out std_logic_vector(4 downto 0)
        );
    end component;

begin

    dut_multi : fpu
        port map (clk, resetn, fpu_start, fp_op, rm, fp_a, fp_b, fp_c,
                  fpu_done, fp_result, fp_flags);

    dut_simple : fpu_simple
        port map (fp_s_op, fp_s_a, fp_s_b, fp_s_result, fp_s_flags);

    -- clock
    clkgen : process
    begin
        while not sim_done loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    stim : process
        file vf         : text;
        variable fstatus: file_open_status;
        variable L      : line;
        variable kc, rc, sp : character;
        variable op2, fh    : string(1 to 2);
        variable ah, bh, chs, rh : string(1 to 8);
        variable kind, opv, rmv : integer;
        variable av, bv, cv, expv : std_logic_vector(31 downto 0);
        variable expf   : std_logic_vector(4 downto 0);
        variable gotv   : std_logic_vector(31 downto 0);
        variable gotf   : std_logic_vector(4 downto 0);
        variable stabv  : std_logic_vector(31 downto 0);
        variable cyc    : integer;
        variable nvec, nfail : integer := 0;
        variable shown  : integer := 0;
        variable cmin, cmax : int13  := (others => 0);
        variable cinit  : bool13 := (others => false);
        variable ok     : boolean;
    begin
        file_open(fstatus, vf, VECFILE, READ_MODE);
        if fstatus /= OPEN_OK then
            report "FPU_TB: cannot open vector file '" & VECFILE & "'" severity failure;
        end if;

        -- reset
        resetn <= '0';
        wait for 23 ns;
        resetn <= '1';
        wait until rising_edge(clk);

        while not endfile(vf) loop
            readline(vf, L);
            read(L, kc); read(L, sp);
            read(L, op2); read(L, sp);
            read(L, rc); read(L, sp);
            read(L, ah); read(L, sp);
            read(L, bh); read(L, sp);
            read(L, chs); read(L, sp);
            read(L, rh); read(L, sp);
            read(L, fh);

            kind := hexc(kc);
            opv  := dec2(op2);
            rmv  := hexc(rc);
            av   := hex8(ah);
            bv   := hex8(bh);
            cv   := hex8(chs);
            expv := hex8(rh);
            expf := hex2(fh)(4 downto 0);
            nvec := nvec + 1;

            if kind = 1 then
                ------------------------------------------------ combinational
                fp_s_op <= std_logic_vector(to_unsigned(opv, 4));
                fp_s_a  <= av;
                fp_s_b  <= bv;
                wait for 2 ns;
                gotv := fp_s_result;
                gotf := fp_s_flags;
                ok := (gotv = expv) and (gotf = expf);
                if not ok then
                    nfail := nfail + 1;
                    if shown < MAX_SHOW then
                        shown := shown + 1;
                        report "MISMATCH simple " & SNAMES(opv) &
                               " a=" & hx(av) & " b=" & hx(bv) &
                               " exp=" & hx(expv) & "/" & hx(expf) &
                               " got=" & hx(gotv) & "/" & hx(gotf) severity warning;
                    end if;
                end if;

            else
                ------------------------------------------------ multi-cycle
                fp_op <= std_logic_vector(to_unsigned(opv, 4));
                rm    <= std_logic_vector(to_unsigned(rmv, 3));
                fp_a  <= av; fp_b <= bv; fp_c <= cv;
                fpu_start <= '0';
                wait until rising_edge(clk);
                fpu_start <= '1';
                cyc := 0;
                loop
                    wait until rising_edge(clk);
                    cyc := cyc + 1;
                    exit when fpu_done = '1';
                    if cyc > 400 then
                        report "TIMEOUT multi " & MNAMES(opv) & " (no done)" severity failure;
                        exit;
                    end if;
                end loop;
                gotv := fp_result;
                gotf := fp_flags;
                fpu_start <= '0';
                -- stability: result must hold after done, before next start
                wait until rising_edge(clk);
                stabv := fp_result;
                wait until rising_edge(clk);

                -- per-op cycle bookkeeping
                if not cinit(opv) then
                    cmin(opv) := cyc; cmax(opv) := cyc; cinit(opv) := true;
                else
                    if cyc < cmin(opv) then cmin(opv) := cyc; end if;
                    if cyc > cmax(opv) then cmax(opv) := cyc; end if;
                end if;

                ok := (gotv = expv) and (gotf = expf) and (stabv = gotv);
                if not ok then
                    nfail := nfail + 1;
                    if shown < MAX_SHOW then
                        shown := shown + 1;
                        report "MISMATCH multi " & MNAMES(opv) & " rm=" & integer'image(rmv) &
                               " a=" & hx(av) & " b=" & hx(bv) & " c=" & hx(cv) &
                               " exp=" & hx(expv) & "/" & hx(expf) &
                               " got=" & hx(gotv) & "/" & hx(gotf) &
                               " cyc=" & integer'image(cyc) severity warning;
                    end if;
                end if;
            end if;
        end loop;

        file_close(vf);

        -- per-op done-latency table + bound check
        report "---- per-op done-latency (clk edges start->done) ----";
        for i in 0 to 12 loop
            if cinit(i) then
                report "  " & MNAMES(i) & " min=" & integer'image(cmin(i)) &
                       " max=" & integer'image(cmax(i));
                if cmax(i) > 80 then
                    report "  latency bound exceeded for " & MNAMES(i) severity warning;
                    nfail := nfail + 1;
                end if;
            end if;
        end loop;

        report "FPU_TB: vectors=" & integer'image(nvec) &
               " failures=" & integer'image(nfail);
        if nfail = 0 then
            report "ALL CHECKS PASSED";
        else
            report "CHECKS FAILED: " & integer'image(nfail) & " mismatches" severity warning;
        end if;

        sim_done <= true;
        wait for 20 ns;
        assert nfail = 0 report "fpu_tb FAILED" severity failure;
        wait;
    end process;

end tb;
