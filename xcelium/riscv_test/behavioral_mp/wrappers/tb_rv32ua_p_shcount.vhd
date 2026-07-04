entity tb_rv32ua_p_shcount is end tb_rv32ua_p_shcount;
architecture behavioral of tb_rv32ua_p_shcount is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxrv32ua-p-shcount.rcf");
end architecture;
