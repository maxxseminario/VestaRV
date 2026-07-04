entity tb_rv32uzbb_p_ctz is end tb_rv32uzbb_p_ctz;
architecture behavioral of tb_rv32uzbb_p_ctz is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32uzbb-p-ctz.rcf");
end architecture;
