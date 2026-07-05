entity tb_rv32uzbc_p_clmulr is end tb_rv32uzbc_p_clmulr;
architecture behavioral of tb_rv32uzbc_p_clmulr is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xrv32uzbc-p-clmulr.rcf");
end architecture;
