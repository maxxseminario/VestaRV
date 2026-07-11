entity tb_rv32uzbb_p_min is end tb_rv32uzbb_p_min;
architecture behavioral of tb_rv32uzbb_p_min is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxrv32uzbb-p-min.rcf");
end architecture;
