entity tb_rv32ui_p_bge is end tb_rv32ui_p_bge;
architecture behavioral of tb_rv32ui_p_bge is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxxrv32ui-p-bge.rcf");
end architecture;
