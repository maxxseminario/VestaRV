entity tb_rv32ua_p_extzihpm is end tb_rv32ua_p_extzihpm;
architecture behavioral of tb_rv32ua_p_extzihpm is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xrv32ua-p-extzihpm.rcf");
end architecture;
