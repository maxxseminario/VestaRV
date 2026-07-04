entity tb_rv32ui_p_jal is end tb_rv32ui_p_jal;
architecture behavioral of tb_rv32ui_p_jal is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxrv32ui-p-jal.rcf");
end architecture;
