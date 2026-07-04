entity tb_rv32ui_p_srl is end tb_rv32ui_p_srl;
architecture behavioral of tb_rv32ui_p_srl is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxrv32ui-p-srl.rcf");
end architecture;
