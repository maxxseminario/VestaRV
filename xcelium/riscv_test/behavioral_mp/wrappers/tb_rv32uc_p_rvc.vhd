entity tb_rv32uc_p_rvc is end tb_rv32uc_p_rvc;
architecture behavioral of tb_rv32uc_p_rvc is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxrv32uc-p-rvc.rcf");
end architecture;
