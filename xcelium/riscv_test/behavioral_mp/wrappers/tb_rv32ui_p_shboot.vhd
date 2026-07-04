entity tb_rv32ui_p_shboot is end tb_rv32ui_p_shboot;
architecture behavioral of tb_rv32ui_p_shboot is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ui-p-shboot.rcf", HART_RAM0_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shboot.ram0.rcf", HART_RAM1_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shboot.ram1.rcf");
end architecture;
