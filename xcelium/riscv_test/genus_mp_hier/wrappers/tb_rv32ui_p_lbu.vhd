entity tb_rv32ui_p_lbu is end tb_rv32ui_p_lbu;
architecture behavioral of tb_rv32ui_p_lbu is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxrv32ui-p-lbu.rcf");
end architecture;
