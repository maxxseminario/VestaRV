entity tb_rv32ua_p_lrsc is end tb_rv32ua_p_lrsc;
architecture behavioral of tb_rv32ua_p_lrsc is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxrv32ua-p-lrsc.rcf");
end architecture;
