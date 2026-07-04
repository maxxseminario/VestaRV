entity tb_rv32ui_p_shwfi is end tb_rv32ui_p_shwfi;
architecture behavioral of tb_rv32ui_p_shwfi is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32ui-p-shwfi.rcf", HART_RAM0_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shwfi.ram0.rcf", HART_RAM1_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shwfi.ram1.rcf");
end architecture;
