entity tb_rv32uzbb_p_andn is end tb_rv32uzbb_p_andn;
architecture behavioral of tb_rv32uzbb_p_andn is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxrv32uzbb-p-andn.rcf");
end architecture;
