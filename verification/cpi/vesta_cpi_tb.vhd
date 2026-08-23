/* CPI-measurement testbench for the `vesta` core, derived from opensource_sim/isa/vesta_isa_tb.vhd.
   It keeps that harness's bus contract exactly (RAM base 0x8000, mem_ready = '1', one cycle of read latency, wen active-LOW per lane) so the numbers describe the core, not a new memory model.
   Two counters run on the free-running clk: every clk rising edge after reset release, and every edge at which the core's own inst_retired strobe is high.
   inst_retired is reached by a VHDL-2008 external name rather than a new port, so the RTL is untouched; it is the SAME signal csr_unit counts minstret on, which makes the instruction count architectural rather than an estimate.
   A magic-address write decodes the benchmarks' existing setStats() hook: value 1 opens the kernel window and value 2 closes it, giving a kernel-only CPI alongside the whole-program one. */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;
use std.env.all;

entity vesta_cpi_tb is
    generic (
        TEST_FILE       : string  := "";
        TEST_NAME       : string  := "";
        CLK_PERIOD_NS   : time    := 10 ns;
        -- Benchmarks run far longer than ISA tests, so the watchdog is much larger than the 300k of the ISA harness.
        WATCHDOG_CYCLES : natural := 200_000_000
    );
end entity vesta_cpi_tb;

architecture sim of vesta_cpi_tb is

    constant RAM_BASE  : unsigned(31 downto 0) := x"00008000";
    constant RAM_WORDS : natural := 16#14000# / 4;  -- 20480

    -- setStats() target. Below RAM_BASE, so it can never alias a real RAM word; the RAM write path is range-guarded for the same reason.
    constant MAGIC_ADDR : unsigned(31 downto 0) := x"00004000";

    signal clk     : std_logic := '0';
    signal resetn  : std_logic := '0';
    signal running : boolean   := true;

    signal data_addr  : std_logic_vector(31 downto 0);
    signal wen        : std_logic_vector(3 downto 0);
    signal write_data : std_logic_vector(31 downto 0);
    signal read_data  : std_logic_vector(31 downto 0);
    signal mask       : std_logic_vector(1 downto 0);

    signal a0        : std_logic_vector(31 downto 0);
    signal trap_flag : std_logic;
    signal clk_cpu   : std_logic;

    type ram_t is array (0 to RAM_WORDS-1) of std_logic_vector(31 downto 0);

    impure function load_rcf return ram_t is
        variable r      : ram_t := (others => (others => '0'));
        file     f      : text;
        variable status : file_open_status;
        variable ln     : line;
        variable bv     : bit_vector(31 downto 0);
        variable idx    : natural := 0;
    begin
        if TEST_FILE = "" then
            return r;
        end if;
        file_open(status, f, TEST_FILE, read_mode);
        if status /= open_ok then
            return r;
        end if;
        while not endfile(f) and idx < RAM_WORDS loop
            readline(f, ln);
            next when ln'length = 0;
            read(ln, bv);
            r(idx) := to_stdlogicvector(bv);
            idx := idx + 1;
        end loop;
        file_close(f);
        return r;
    end function;

    signal ram   : ram_t := load_rcf;
    signal rdata : std_logic_vector(31 downto 0) := (others => '0');

    function ram_idx(addr : std_logic_vector(31 downto 0)) return natural is
        variable a : unsigned(31 downto 0);
    begin
        a := unsigned(addr) - RAM_BASE;
        return to_integer(a(a'high downto 2)) mod RAM_WORDS;
    end function;

    -- In-RAM decode, so a setStats() write outside the window cannot wrap into the image through ram_idx's mod.
    function in_ram(addr : std_logic_vector(31 downto 0)) return boolean is
    begin
        return unsigned(addr) >= RAM_BASE and unsigned(addr) < RAM_BASE + 16#14000#;
    end function;

    -- Kernel-window state, driven by the magic-address decode.
    signal stats_en : std_logic := '0';

begin

    file_guard : process
        file     f  : text;
        variable st : file_open_status;
    begin
        assert TEST_FILE /= ""
            report "vesta_cpi_tb: no TEST_FILE given (pass -gTEST_FILE=<path.rcf>)"
            severity failure;
        file_open(st, f, TEST_FILE, read_mode);
        assert st = open_ok
            report "vesta_cpi_tb: cannot open TEST_FILE '" & TEST_FILE & "'"
            severity failure;
        file_close(f);
        wait;
    end process;

    clk_gen : process
    begin
        while running loop
            clk <= '0';
            wait for CLK_PERIOD_NS / 2;
            clk <= '1';
            wait for CLK_PERIOD_NS / 2;
        end loop;
        wait;
    end process;

    rst_gen : process
    begin
        resetn <= '0';
        wait for CLK_PERIOD_NS * 4;
        wait until falling_edge(clk);
        resetn <= '1';
        wait;
    end process;

    mask <= data_addr(1 downto 0);

    -- Same synchronous 1-cycle RAM as the ISA harness, with the range guard added and the magic address decoded alongside.
    ram_proc : process (clk)
        variable idx : natural;
    begin
        if rising_edge(clk) then
            idx := ram_idx(data_addr);
            -- Only the WRITE path is range-guarded: a setStats() store must not wrap into the image through ram_idx's mod.
            -- The read path stays unguarded, exactly as in the ISA harness, because the one out-of-window access this harness makes is that store and nothing consumes its read data.
            if in_ram(data_addr) then
                if wen(0) = '0' then ram(idx)(7 downto 0)   <= write_data(7 downto 0);   end if;
                if wen(1) = '0' then ram(idx)(15 downto 8)  <= write_data(15 downto 8);  end if;
                if wen(2) = '0' then ram(idx)(23 downto 16) <= write_data(23 downto 16); end if;
                if wen(3) = '0' then ram(idx)(31 downto 24) <= write_data(31 downto 24); end if;
            end if;
            rdata <= ram(idx);

            if unsigned(data_addr) = MAGIC_ADDR and wen /= "1111" then
                if write_data = x"00000001" then
                    stats_en <= '1';
                elsif write_data = x"00000002" then
                    stats_en <= '0';
                end if;
            end if;
        end if;
    end process;

    read_data <= rdata;

    -- Generics mirror opensource_sim/isa/vesta_isa_tb.vhd exactly, so CPI is measured on the same core configuration the ISA regression proves.
    dut : entity work.vesta
        generic map (
            PC_RST_VAL    => x"00008200",
            ENABLE_ZICOND => true,
            ENABLE_ZCB    => true,
            ENABLE_ZIMOP  => true,
            ENABLE_ZIHINT => true,
            ENABLE_ZIHPM  => false,
            ENABLE_ZAWRS  => false,
            ENABLE_ZABHA  => true,
            ENABLE_ZACAS  => true,
            ENABLE_ZICBOZ => true,
            ENABLE_ZCMP   => true,
            ENABLE_ZCMT   => true,
            ENABLE_ZBKB   => true,
            ENABLE_ZBKC   => true,
            ENABLE_ZBKX   => true,
            ENABLE_ZKN    => true,
            ENABLE_ZFINX  => true
        )
        port map (
            clk              => clk,
            resetn           => resetn,
            sleep            => '0',
            clk_cpu          => clk_cpu,
            hart_id          => (others => '0'),

            data_addr        => data_addr,
            wen              => wen,
            write_data       => write_data,
            read_data        => read_data,
            mask             => mask,
            mem_ready        => '1',

            lr_sc_bus        => open,
            sc_fail_ext      => '0',
            amo_lock         => open,

            irq_vector       => (others => '0'),
            irq_priority     => (others => '0'),
            irq_en           => (others => '0'),
            irq_recursion_en => '0',
            isr_ret          => open,

            trap_flag        => trap_flag,
            a0               => a0
        );

    -- The measurement. inst_retired is `retire_now and en_clk_cpu` inside vesta, the exact predicate csr_unit's minstret counts, so instr_total equals what a rdinstret would read.
    -- Cycles are counted on the FREE-RUNNING clk, not the gated clk_cpu, so any cycle the core spends stalled with its clock gated is still charged to CPI.
    meas : process
        alias inst_retired_x is << signal dut.inst_retired : std_logic >>;
        variable cyc_total   : natural := 0;
        variable ins_total   : natural := 0;
        variable cyc_kernel  : natural := 0;
        variable ins_kernel  : natural := 0;
        variable ln          : line;
    begin
        wait until resetn = '1';
        loop
            wait until rising_edge(clk);

            cyc_total := cyc_total + 1;
            if inst_retired_x = '1' then
                ins_total := ins_total + 1;
            end if;

            if stats_en = '1' then
                cyc_kernel := cyc_kernel + 1;
                if inst_retired_x = '1' then
                    ins_kernel := ins_kernel + 1;
                end if;
            end if;

            if a0 = x"CAFEBABE" then
                write(ln, string'("CPIRESULT ") & TEST_NAME
                        & " status=PASS"
                        & " cyc_total=" & integer'image(cyc_total)
                        & " ins_total=" & integer'image(ins_total)
                        & " cyc_kernel=" & integer'image(cyc_kernel)
                        & " ins_kernel=" & integer'image(ins_kernel));
                writeline(output, ln);
                running <= false;
                wait for CLK_PERIOD_NS;
                finish(0);
            elsif a0 = x"DEADBEEF" then
                write(ln, string'("CPIRESULT ") & TEST_NAME
                        & " status=FAIL"
                        & " cyc_total=" & integer'image(cyc_total)
                        & " ins_total=" & integer'image(ins_total)
                        & " cyc_kernel=" & integer'image(cyc_kernel)
                        & " ins_kernel=" & integer'image(ins_kernel));
                writeline(output, ln);
                running <= false;
                wait for CLK_PERIOD_NS;
                finish(1);
            elsif cyc_total >= WATCHDOG_CYCLES then
                write(ln, string'("CPIRESULT ") & TEST_NAME
                        & " status=TIMEOUT"
                        & " cyc_total=" & integer'image(cyc_total)
                        & " ins_total=" & integer'image(ins_total)
                        & " cyc_kernel=" & integer'image(cyc_kernel)
                        & " ins_kernel=" & integer'image(ins_kernel));
                writeline(output, ln);
                running <= false;
                wait for CLK_PERIOD_NS;
                finish(1);
            end if;
        end loop;
    end process;

end architecture sim;
