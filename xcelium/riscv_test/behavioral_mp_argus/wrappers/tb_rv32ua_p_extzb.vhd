entity tb_rv32ua_p_extzb is end tb_rv32ua_p_extzb;
architecture behavioral of tb_rv32ua_p_extzb is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxrv32ua-p-extzb.rcf");
end architecture;
