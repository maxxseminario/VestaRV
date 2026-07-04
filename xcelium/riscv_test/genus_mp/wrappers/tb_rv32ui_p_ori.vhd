entity tb_rv32ui_p_ori is end tb_rv32ui_p_ori;
architecture behavioral of tb_rv32ui_p_ori is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxrv32ui-p-ori.rcf");
end architecture;
