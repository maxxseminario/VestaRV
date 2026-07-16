entity tb_rv32uzbb_p_max is end tb_rv32uzbb_p_max;
architecture behavioral of tb_rv32uzbb_p_max is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32uzbb-p-max.rcf");
end architecture;
