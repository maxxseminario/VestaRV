entity tb_rv32ui_p_shtimer is end tb_rv32ui_p_shtimer;
architecture behavioral of tb_rv32ui_p_shtimer is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxrv32ui-p-shtimer.rcf");
end architecture;
