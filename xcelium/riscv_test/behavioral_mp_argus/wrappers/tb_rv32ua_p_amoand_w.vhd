entity tb_rv32ua_p_amoand_w is end tb_rv32ua_p_amoand_w;
architecture behavioral of tb_rv32ua_p_amoand_w is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xrv32ua-p-amoand_w.rcf");
end architecture;
