entity tb_rv32ua_p_amoswap_w is end tb_rv32ua_p_amoswap_w;
architecture behavioral of tb_rv32ua_p_amoswap_w is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/rv32ua-p-amoswap_w.rcf");
end architecture;
