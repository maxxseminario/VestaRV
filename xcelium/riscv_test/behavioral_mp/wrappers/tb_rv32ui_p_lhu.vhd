entity tb_rv32ui_p_lhu is end tb_rv32ui_p_lhu;
architecture behavioral of tb_rv32ui_p_lhu is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxrv32ui-p-lhu.rcf");
end architecture;
