entity tb_rv32ui_p_sw is end tb_rv32ui_p_sw;
architecture behavioral of tb_rv32ui_p_sw is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxxrv32ui-p-sw.rcf");
end architecture;
