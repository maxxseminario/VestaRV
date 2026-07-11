entity tb_rv32uzbb_p_clz is end tb_rv32uzbb_p_clz;
architecture behavioral of tb_rv32uzbb_p_clz is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxrv32uzbb-p-clz.rcf");
end architecture;
