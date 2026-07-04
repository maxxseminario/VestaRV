entity tb_rv32ua_p_amoor_w is end tb_rv32ua_p_amoor_w;
architecture behavioral of tb_rv32ua_p_amoor_w is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxrv32ua-p-amoor_w.rcf");
end architecture;
