entity tb_rv32ui_p_sll is end tb_rv32ui_p_sll;
architecture behavioral of tb_rv32ui_p_sll is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxxrv32ui-p-sll.rcf");
end architecture;
