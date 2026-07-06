entity tb_rv32ua_p_shlock is end tb_rv32ua_p_shlock;
architecture behavioral of tb_rv32ua_p_shlock is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ua-p-shlock.rcf", HART_RAM0_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ua-p-shlock.ram0.rcf");
end architecture;
