entity tb_rv32ui_p_slt is end tb_rv32ui_p_slt;
architecture behavioral of tb_rv32ui_p_slt is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxrv32ui-p-slt.rcf");
end architecture;
