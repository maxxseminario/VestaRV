entity tb_rv32ui_p_shclint is end tb_rv32ui_p_shclint;
architecture behavioral of tb_rv32ui_p_shclint is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxrv32ui-p-shclint.rcf");
end architecture;
