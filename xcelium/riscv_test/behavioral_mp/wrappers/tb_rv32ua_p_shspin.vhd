entity tb_rv32ua_p_shspin is end tb_rv32ua_p_shspin;
architecture behavioral of tb_rv32ua_p_shspin is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ua-p-shspin.rcf", HART_RAM0_INIT => "/home/mseminario2/vestarv/xcelium/riscv_test/ram_images/rv32ua-p-shspin.ram0.rcf");
end architecture;
