entity tb_rv32ui_p_shuart is end tb_rv32ui_p_shuart;
architecture behavioral of tb_rv32ui_p_shuart is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ui-p-shuart.rcf", HART_RAM0_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shuart.ram0.rcf", HART_RAM1_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shuart.ram1.rcf");
end architecture;
