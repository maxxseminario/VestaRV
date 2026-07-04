entity tb_rv32ui_p_shi2c is end tb_rv32ui_p_shi2c;
architecture behavioral of tb_rv32ui_p_shi2c is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32ui-p-shi2c.rcf", HART_RAM0_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shi2c.ram0.rcf", HART_RAM1_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shi2c.ram1.rcf");
end architecture;
