entity tb_rv32ua_p_amomin_w is end tb_rv32ua_p_amomin_w;
architecture behavioral of tb_rv32ua_p_amomin_w is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xrv32ua-p-amomin_w.rcf");
end architecture;
