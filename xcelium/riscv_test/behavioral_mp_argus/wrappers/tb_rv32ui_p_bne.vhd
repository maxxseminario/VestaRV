entity tb_rv32ui_p_bne is end tb_rv32ui_p_bne;
architecture behavioral of tb_rv32ui_p_bne is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxxrv32ui-p-bne.rcf");
end architecture;
