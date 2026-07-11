entity tb_rv32ui_p_lh is end tb_rv32ui_p_lh;
architecture behavioral of tb_rv32ui_p_lh is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxxxrv32ui-p-lh.rcf");
end architecture;
