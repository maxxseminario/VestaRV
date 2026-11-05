-- verification/perf_mp: top wrapper. Binds the (timeout-patched) riscv_tb to one fixed image path so ONE snapshot
-- serves every run: each run's cwd supplies its own ../rcf/. perf_mon sits beside the testbench and is purely an
-- observer unless its STALL_D generic is set.
entity perf_top is
    generic (STALL_D : natural := 0);
end perf_top;
architecture behavioral of perf_top is
begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxxxxxxxxxperf.rcf");
    mon: entity work.perf_mon generic map (STALL_D => STALL_D);
end architecture;
