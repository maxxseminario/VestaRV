entity tb_rv32uzbb_p_sext_b is end tb_rv32uzbb_p_sext_b;
architecture behavioral of tb_rv32uzbb_p_sext_b is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xrv32uzbb-p-sext_b.rcf");
end architecture;
