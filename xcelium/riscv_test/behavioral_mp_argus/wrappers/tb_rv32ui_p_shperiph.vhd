entity tb_rv32ui_p_shperiph is end tb_rv32ui_p_shperiph;
architecture behavioral of tb_rv32ui_p_shperiph is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xrv32ui-p-shperiph.rcf");
end architecture;
