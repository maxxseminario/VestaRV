entity tb_rv32ui_p_jalr is end tb_rv32ui_p_jalr;
architecture behavioral of tb_rv32ui_p_jalr is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxrv32ui-p-jalr.rcf");
end architecture;
