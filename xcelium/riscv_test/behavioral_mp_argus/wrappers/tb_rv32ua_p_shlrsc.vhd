entity tb_rv32ua_p_shlrsc is end tb_rv32ua_p_shlrsc;
architecture behavioral of tb_rv32ua_p_shlrsc is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxrv32ua-p-shlrsc.rcf");
end architecture;
