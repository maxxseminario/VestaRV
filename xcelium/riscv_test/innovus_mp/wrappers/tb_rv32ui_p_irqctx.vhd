entity tb_rv32ui_p_irqctx is end tb_rv32ui_p_irqctx;
architecture behavioral of tb_rv32ui_p_irqctx is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ui-p-irqctx.rcf");
end architecture;
