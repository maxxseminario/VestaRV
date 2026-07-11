entity tb_rv32ui_p_lui is end tb_rv32ui_p_lui;
architecture behavioral of tb_rv32ui_p_lui is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxxrv32ui-p-lui.rcf");
end architecture;
