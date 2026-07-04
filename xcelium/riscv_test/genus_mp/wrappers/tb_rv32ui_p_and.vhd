entity tb_rv32ui_p_and is end tb_rv32ui_p_and;
architecture behavioral of tb_rv32ui_p_and is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxrv32ui-p-and.rcf");
end architecture;
