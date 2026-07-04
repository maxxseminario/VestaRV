entity tb_rv32ui_p_shperiph is end tb_rv32ui_p_shperiph;
architecture behavioral of tb_rv32ui_p_shperiph is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xrv32ui-p-shperiph.rcf", HART_RAM0_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shperiph.ram0.rcf", HART_RAM1_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shperiph.ram1.rcf");
end architecture;
