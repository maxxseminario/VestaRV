entity tb_rv32ua_p_amoxor_w is end tb_rv32ua_p_amoxor_w;
architecture behavioral of tb_rv32ua_p_amoxor_w is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xrv32ua-p-amoxor_w.rcf");
end architecture;
