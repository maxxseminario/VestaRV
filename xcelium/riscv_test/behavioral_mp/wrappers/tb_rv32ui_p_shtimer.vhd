entity tb_rv32ui_p_shtimer is end tb_rv32ui_p_shtimer;
architecture behavioral of tb_rv32ui_p_shtimer is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxrv32ui-p-shtimer.rcf", HART_RAM0_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shtimer.ram0.rcf", HART_RAM1_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shtimer.ram1.rcf");
end architecture;
