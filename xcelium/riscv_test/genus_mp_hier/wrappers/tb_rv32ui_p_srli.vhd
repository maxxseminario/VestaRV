entity tb_rv32ui_p_srli is end tb_rv32ui_p_srli;
architecture behavioral of tb_rv32ui_p_srli is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxrv32ui-p-srli.rcf");
end architecture;
