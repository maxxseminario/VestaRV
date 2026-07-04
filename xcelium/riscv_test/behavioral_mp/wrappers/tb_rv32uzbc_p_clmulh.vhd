entity tb_rv32uzbc_p_clmulh is end tb_rv32uzbc_p_clmulh;
architecture behavioral of tb_rv32uzbc_p_clmulh is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xrv32uzbc-p-clmulh.rcf");
end architecture;
