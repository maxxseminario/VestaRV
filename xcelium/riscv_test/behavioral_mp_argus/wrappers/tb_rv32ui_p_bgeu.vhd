entity tb_rv32ui_p_bgeu is end tb_rv32ui_p_bgeu;
architecture behavioral of tb_rv32ui_p_bgeu is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxrv32ui-p-bgeu.rcf");
end architecture;
