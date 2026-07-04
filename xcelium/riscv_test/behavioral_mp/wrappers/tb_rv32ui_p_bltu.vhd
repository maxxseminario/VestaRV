entity tb_rv32ui_p_bltu is end tb_rv32ui_p_bltu;
architecture behavioral of tb_rv32ui_p_bltu is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxrv32ui-p-bltu.rcf");
end architecture;
