entity tb_rv32ua_p_shlock is end tb_rv32ua_p_shlock;
architecture behavioral of tb_rv32ua_p_shlock is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ua-p-shlock.rcf");
end architecture;
