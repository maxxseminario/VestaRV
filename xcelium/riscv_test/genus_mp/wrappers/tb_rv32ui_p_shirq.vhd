entity tb_rv32ui_p_shirq is end tb_rv32ui_p_shirq;
architecture behavioral of tb_rv32ui_p_shirq is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32ui-p-shirq.rcf");
end architecture;
