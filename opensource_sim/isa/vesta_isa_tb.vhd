-- Self-driving ISA-regression testbench for the `vesta` core (RV32IMAC+Zb*, multicycle, single unified bus): one test image per run, given by the TEST_FILE generic.
-- It terminates itself: a0 = 0xCAFEBABE reports TEST PASSED and exits 0, a0 = 0xDEADBEEF reports TEST FAILED, and the watchdog reports TEST TIMED OUT, both failures exiting nonzero.
-- Those sentinels are the riscv-tests values RVTEST_PASS and RVTEST_FAIL write to x10 (a0), the only pass/fail convention this core exports (no tohost).
-- Memory map: rcf word 0 is memory[0x8000], so RAM base is 0x8000 and PC_RST_VAL is 0x8200 (_start); this bare-core harness has no boot ROM.
-- Bus timing: mask = data_addr(1:0), mem_ready = '1', byte-lane writes on wen (ACTIVE-LOW per lane), and EXACTLY one cycle of read latency because the multicycle FSM has no fetch-wait state.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;
use std.env.all;

entity vesta_isa_tb is
    generic (
        -- Unconstrained string, so a path can be passed with no fixed-length padding.
        TEST_FILE     : string  := "";
        -- Behavioral clock period, no timing meaning (about 100 MHz).
        CLK_PERIOD_NS : time    := 10 ns;
        -- Watchdog in clock cycles: 300,000 is about 8x the longest passing test here, and short enough to fire inside the runner's per-test wall timeout.
        -- A hung test then ends as a reported sim timeout with a nonzero exit rather than as a wall kill.
        WATCHDOG_CYCLES : natural := 300_000
    );
end entity vesta_isa_tb;

architecture sim of vesta_isa_tb is

    -- rcf word 0 lives at RAM_BASE.
    -- RAM spans the full padded image (0x14000 bytes = 20480 words), so no in-range access can index past the array.
    constant RAM_BASE  : unsigned(31 downto 0) := x"00008000";
    constant RAM_WORDS : natural := 16#14000# / 4;  -- 20480

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';
    signal running : boolean  := true;

    -- core-to-RAM bus
    signal data_addr  : std_logic_vector(31 downto 0);
    signal wen        : std_logic_vector(3 downto 0);
    signal write_data : std_logic_vector(31 downto 0);
    signal read_data  : std_logic_vector(31 downto 0);
    signal mask       : std_logic_vector(1 downto 0);

    signal a0        : std_logic_vector(31 downto 0);
    signal trap_flag : std_logic;
    signal clk_cpu   : std_logic;

    type ram_t is array (0 to RAM_WORDS-1) of std_logic_vector(31 downto 0);

    -- Loads the rcf (one 32-bit ASCII-binary word per line) into the RAM image at ELABORATION, where a `severity failure` assert does NOT stop the simulator.
    -- On a missing or empty TEST_FILE it must RETURN EARLY with zero RAM instead of entering the read loop; the clean abort is the runtime file_guard process below.
    impure function load_rcf return ram_t is
        variable r     : ram_t := (others => (others => '0'));
        file     f     : text;
        variable status : file_open_status;
        variable ln    : line;
        variable bv    : bit_vector(31 downto 0);
        variable idx   : natural := 0;
    begin
        if TEST_FILE = "" then
            return r;                          -- file_guard will abort at t=0
        end if;
        file_open(status, f, TEST_FILE, read_mode);
        if status /= open_ok then
            return r;                          -- file_guard will abort at t=0
        end if;
        while not endfile(f) and idx < RAM_WORDS loop
            readline(f, ln);
            next when ln'length = 0;           -- tolerate a trailing blank line
            read(ln, bv);
            r(idx) := to_stdlogicvector(bv);
            idx := idx + 1;
        end loop;
        file_close(f);
        report "vesta_isa_tb: loaded " & integer'image(idx) & " words from " & TEST_FILE;
        return r;
    end function;

    signal ram   : ram_t := load_rcf;
    signal rdata : std_logic_vector(31 downto 0) := (others => '0');

    -- Word index into the RAM image for a byte address on the bus.
    function ram_idx(addr : std_logic_vector(31 downto 0)) return natural is
        variable a : unsigned(31 downto 0);
    begin
        a := unsigned(addr) - RAM_BASE;
        return to_integer(a(a'high downto 2)) mod RAM_WORDS;
    end function;

begin

    -- Authoritative TEST_FILE validation at t=0: unlike the elaboration-time loader, a runtime `severity failure` here stops the simulator at once with a nonzero exit.
    -- A missing or empty file therefore fails fast instead of running an empty RAM out to the watchdog.
    file_guard : process
        file     f  : text;
        variable st : file_open_status;
    begin
        assert TEST_FILE /= ""
            report "vesta_isa_tb: no TEST_FILE given (pass -gTEST_FILE=<path.rcf>)"
            severity failure;
        file_open(st, f, TEST_FILE, read_mode);
        assert st = open_ok
            report "vesta_isa_tb: cannot open TEST_FILE '" & TEST_FILE & "'"
            severity failure;
        assert not endfile(f)
            report "vesta_isa_tb: TEST_FILE '" & TEST_FILE & "' is empty (0 words)"
            severity failure;
        file_close(f);
        wait;
    end process;

    -- Free-running clock until the test process stops the sim.
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

    -- Reset: hold resetn low for a few cycles, then release (async, active-low).
    rst_gen : process
    begin
        resetn <= '0';
        wait for CLK_PERIOD_NS * 4;
        wait until falling_edge(clk);
        resetn <= '1';
        wait;
    end process;

    -- Byte position within the word: the same data_addr(1:0) slice the address decoder drives.
    mask <= data_addr(1 downto 0);

    -- Synchronous, 1-cycle-latency RAM. Byte-masked writes, wen active-LOW.
    ram_proc : process (clk)
        variable idx : natural;
    begin
        if rising_edge(clk) then
            idx := ram_idx(data_addr);
            if wen(0) = '0' then ram(idx)(7 downto 0)   <= write_data(7 downto 0);   end if;
            if wen(1) = '0' then ram(idx)(15 downto 8)  <= write_data(15 downto 8);  end if;
            if wen(2) = '0' then ram(idx)(23 downto 16) <= write_data(23 downto 16); end if;
            if wen(3) = '0' then ram(idx)(31 downto 24) <= write_data(31 downto 24); end if;
            rdata <= ram(idx);
        end if;
    end process;

    read_data <= rdata;

    -- Device under test: bare core at _start (PC_RST_VAL = 0x8200) with every extension that is functionally verifiable on a single bare core enabled; the entity defaults the optional ones FALSE, RV32IMAC and Zb* TRUE.
    -- The ISA ext-probe tests dispatch their result-checking arm on -DCORE_ENABLE_<EXT> at build time, so the image build must use exactly the -D set matching the TRUE generics below or probe polarity disagrees with the RTL.
    dut : entity work.vesta
        generic map (
            PC_RST_VAL    => x"00008200",
            ENABLE_ZICOND => true,   -- Zicond  : czero.eqz/nez
            ENABLE_ZCB    => true,   -- Zcb     : extra compressed (c.mul/c.zext/...)
            ENABLE_ZIMOP  => true,   -- Zimop   : may-be-operation placeholders
            ENABLE_ZIHINT => true,   -- Zihint  : hint NOPs (pause/ntl)
            ENABLE_ZIHPM  => false,  -- Zihpm   : hpm counters; OFF because the probe dispatches on an mhpmcounter advancing, which a bare core does not do
            ENABLE_ZAWRS  => false,  -- Zawrs   : OFF because wrs.nto/sto block until another master clears the reservation, so a single hart never retires them
            ENABLE_ZABHA  => true,   -- Zabha   : byte/halfword AMOs
            ENABLE_ZACAS  => true,   -- Zacas   : amocas.w/b/h compare-and-swap
            ENABLE_ZICBOZ => true,   -- Zicboz  : cbo.zero block-zero
            ENABLE_ZCMP   => true,   -- Zcmp    : cm.push/pop/mv
            ENABLE_ZCMT   => true,   -- Zcmt    : cm.jt table jump + jvt CSR
            ENABLE_ZBKB   => true,   -- Zbkb    : crypto bit-manip (pack/brev8/...)
            ENABLE_ZBKC   => true,   -- Zbkc    : carry-less multiply (clmul/clmulh)
            ENABLE_ZBKX   => true,   -- Zbkx    : crossbar permute (xperm8/xperm4)
            ENABLE_ZKN    => true,   -- Zkn     : scalar crypto AES + SHA
            ENABLE_ZFINX  => true    -- Zfinx   : single-precision FP in x-registers; needs fpu.vhd and fpu_simple.vhd in the source list, or the unbound component floats fpu_done and every FP op hangs
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

    -- a0 monitor and watchdog: sample a0 once reset is released; the core writes the sentinel then self-loops, so the value latches.
    monitor : process
        variable cycles : natural := 0;
    begin
        wait until resetn = '1';
        loop
            wait until rising_edge(clk);
            cycles := cycles + 1;

            if a0 = x"CAFEBABE" then
                report "TEST PASSED: " & TEST_FILE severity note;
                running <= false;
                finish(0);
            elsif a0 = x"DEADBEEF" then
                report "TEST FAILED: " & TEST_FILE severity failure;
            elsif cycles >= WATCHDOG_CYCLES then
                report "TEST TIMED OUT after " & integer'image(cycles)
                       & " cycles: " & TEST_FILE severity failure;
            end if;
        end loop;
    end process;

end architecture sim;
