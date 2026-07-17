entity tb_rv32ua_p_extzimop is end tb_rv32ua_p_extzimop;
architecture behavioral of tb_rv32ua_p_extzimop is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xrv32ua-p-extzimop.rcf");
end architecture;
