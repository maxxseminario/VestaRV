entity tb_rv32ui_p_add is end tb_rv32ui_p_add;
architecture behavioral of tb_rv32ui_p_add is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxxrv32ui-p-add.rcf");
end architecture;
