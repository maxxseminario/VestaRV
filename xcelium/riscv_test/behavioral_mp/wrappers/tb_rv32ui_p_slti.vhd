entity tb_rv32ui_p_slti is end tb_rv32ui_p_slti;
architecture behavioral of tb_rv32ui_p_slti is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxrv32ui-p-slti.rcf");
end architecture;
