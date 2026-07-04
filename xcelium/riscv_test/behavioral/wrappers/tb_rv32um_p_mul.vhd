entity tb_rv32um_p_mul is end tb_rv32um_p_mul;
architecture behavioral of tb_rv32um_p_mul is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxxrv32um-p-mul.rcf");
end architecture;
