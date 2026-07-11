entity tb_rv32ui_p_shpwr is end tb_rv32ui_p_shpwr;
architecture behavioral of tb_rv32ui_p_shpwr is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32ui-p-shpwr.rcf");
end architecture;
