entity tb_rv32ui_p_or is end tb_rv32ui_p_or;
architecture behavioral of tb_rv32ui_p_or is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxxxrv32ui-p-or.rcf");
end architecture;
