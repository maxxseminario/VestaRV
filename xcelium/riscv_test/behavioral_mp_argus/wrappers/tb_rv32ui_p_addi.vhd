entity tb_rv32ui_p_addi is end tb_rv32ui_p_addi;
architecture behavioral of tb_rv32ui_p_addi is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxrv32ui-p-addi.rcf");
end architecture;
