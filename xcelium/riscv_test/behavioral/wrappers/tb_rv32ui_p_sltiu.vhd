entity tb_rv32ui_p_sltiu is end tb_rv32ui_p_sltiu;
architecture behavioral of tb_rv32ui_p_sltiu is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32ui-p-sltiu.rcf");
end architecture;
