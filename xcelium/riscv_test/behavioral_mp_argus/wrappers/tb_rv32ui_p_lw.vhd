entity tb_rv32ui_p_lw is end tb_rv32ui_p_lw;
architecture behavioral of tb_rv32ui_p_lw is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxxxrv32ui-p-lw.rcf");
end architecture;
