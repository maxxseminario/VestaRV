entity tb_rv32ua_p_shspin is end tb_rv32ua_p_shspin;
architecture behavioral of tb_rv32ua_p_shspin is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ua-p-shspin.rcf");
end architecture;
