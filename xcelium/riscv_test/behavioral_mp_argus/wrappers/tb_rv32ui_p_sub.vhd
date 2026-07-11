entity tb_rv32ui_p_sub is end tb_rv32ui_p_sub;
architecture behavioral of tb_rv32ui_p_sub is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxxrv32ui-p-sub.rcf");
end architecture;
