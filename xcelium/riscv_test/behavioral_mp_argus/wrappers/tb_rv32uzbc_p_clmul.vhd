entity tb_rv32uzbc_p_clmul is end tb_rv32uzbc_p_clmul;
architecture behavioral of tb_rv32uzbc_p_clmul is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxrv32uzbc-p-clmul.rcf");
end architecture;
