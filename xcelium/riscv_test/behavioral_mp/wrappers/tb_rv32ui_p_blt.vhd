entity tb_rv32ui_p_blt is end tb_rv32ui_p_blt;
architecture behavioral of tb_rv32ui_p_blt is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxrv32ui-p-blt.rcf");
end architecture;
