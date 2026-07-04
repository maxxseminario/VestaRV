entity tb_rv32ui_p_andi is end tb_rv32ui_p_andi;
architecture behavioral of tb_rv32ui_p_andi is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxrv32ui-p-andi.rcf");
end architecture;
