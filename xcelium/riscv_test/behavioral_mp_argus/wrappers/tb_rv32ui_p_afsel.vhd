entity tb_rv32ui_p_afsel is end tb_rv32ui_p_afsel;
architecture behavioral of tb_rv32ui_p_afsel is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxrv32ui-p-afsel.rcf");
end architecture;
