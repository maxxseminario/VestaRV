entity tb_rv32ui_p_slli is end tb_rv32ui_p_slli;
architecture behavioral of tb_rv32ui_p_slli is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxrv32ui-p-slli.rcf");
end architecture;
