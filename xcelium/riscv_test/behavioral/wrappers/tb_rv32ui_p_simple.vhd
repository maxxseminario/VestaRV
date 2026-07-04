entity tb_rv32ui_p_simple is end tb_rv32ui_p_simple;
architecture behavioral of tb_rv32ui_p_simple is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ui-p-simple.rcf");
end architecture;
