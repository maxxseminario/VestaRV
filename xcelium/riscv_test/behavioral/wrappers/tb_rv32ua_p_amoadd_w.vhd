entity tb_rv32ua_p_amoadd_w is end tb_rv32ua_p_amoadd_w;
architecture behavioral of tb_rv32ua_p_amoadd_w is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xrv32ua-p-amoadd_w.rcf");
end architecture;
