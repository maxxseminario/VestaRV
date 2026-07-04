entity tb_rv32ua_p_shamo is end tb_rv32ua_p_shamo;
architecture behavioral of tb_rv32ua_p_shamo is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxrv32ua-p-shamo.rcf", HART_RAM0_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ua-p-shamo.ram0.rcf", HART_RAM1_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ua-p-shamo.ram1.rcf");
end architecture;
