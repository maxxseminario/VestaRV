entity tb_rv32uzbb_p_cpop is end tb_rv32uzbb_p_cpop;
architecture behavioral of tb_rv32uzbb_p_cpop is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32uzbb-p-cpop.rcf");
end architecture;
