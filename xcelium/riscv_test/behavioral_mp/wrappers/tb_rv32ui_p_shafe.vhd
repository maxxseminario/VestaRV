entity tb_rv32ui_p_shafe is end tb_rv32ui_p_shafe;
architecture behavioral of tb_rv32ui_p_shafe is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32ui-p-shafe.rcf");
end architecture;
