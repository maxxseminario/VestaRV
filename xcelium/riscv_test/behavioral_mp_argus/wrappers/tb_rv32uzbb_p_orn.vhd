entity tb_rv32uzbb_p_orn is end tb_rv32uzbb_p_orn;
architecture behavioral of tb_rv32uzbb_p_orn is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxrv32uzbb-p-orn.rcf");
end architecture;
