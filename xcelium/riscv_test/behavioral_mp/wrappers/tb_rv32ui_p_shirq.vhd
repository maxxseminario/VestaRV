entity tb_rv32ui_p_shirq is end tb_rv32ui_p_shirq;
architecture behavioral of tb_rv32ui_p_shirq is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32ui-p-shirq.rcf", HART_RAM0_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shirq.ram0.rcf", HART_RAM1_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ui-p-shirq.ram1.rcf");
end architecture;
