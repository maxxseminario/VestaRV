entity tb_rv32ui_p_srai is end tb_rv32ui_p_srai;
architecture behavioral of tb_rv32ui_p_srai is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxrv32ui-p-srai.rcf");
end architecture;
