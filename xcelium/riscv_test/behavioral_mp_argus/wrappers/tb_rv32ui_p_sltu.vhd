entity tb_rv32ui_p_sltu is end tb_rv32ui_p_sltu;
architecture behavioral of tb_rv32ui_p_sltu is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxrv32ui-p-sltu.rcf");
end architecture;
