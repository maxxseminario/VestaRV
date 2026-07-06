entity tb_rv32ui_p_shi2c is end tb_rv32ui_p_shi2c;
architecture behavioral of tb_rv32ui_p_shi2c is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32ui-p-shi2c.rcf");
end architecture;
