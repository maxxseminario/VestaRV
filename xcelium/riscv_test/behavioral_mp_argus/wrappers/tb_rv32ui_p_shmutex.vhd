entity tb_rv32ui_p_shmutex is end tb_rv32ui_p_shmutex;
architecture behavioral of tb_rv32ui_p_shmutex is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxrv32ui-p-shmutex.rcf");
end architecture;
