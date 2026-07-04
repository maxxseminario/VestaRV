entity tb_rv32ui_p_shmutex is end tb_rv32ui_p_shmutex;
architecture behavioral of tb_rv32ui_p_shmutex is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxrv32ui-p-shmutex.rcf", HART_RAM0_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shmutex.ram0.rcf", HART_RAM1_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shmutex.ram1.rcf");
end architecture;
