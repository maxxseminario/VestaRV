entity tb_rv32uzbb_p_ror is end tb_rv32uzbb_p_ror;
architecture behavioral of tb_rv32uzbb_p_ror is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxrv32uzbb-p-ror.rcf");
end architecture;
