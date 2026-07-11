entity tb_rv32ui_p_beq is end tb_rv32ui_p_beq;
architecture behavioral of tb_rv32ui_p_beq is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxxrv32ui-p-beq.rcf");
end architecture;
