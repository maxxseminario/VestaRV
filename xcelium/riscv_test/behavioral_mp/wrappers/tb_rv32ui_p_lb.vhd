entity tb_rv32ui_p_lb is end tb_rv32ui_p_lb;
architecture behavioral of tb_rv32ui_p_lb is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxxrv32ui-p-lb.rcf");
end architecture;
