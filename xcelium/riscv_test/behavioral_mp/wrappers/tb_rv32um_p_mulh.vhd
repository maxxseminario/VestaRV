entity tb_rv32um_p_mulh is end tb_rv32um_p_mulh;
architecture behavioral of tb_rv32um_p_mulh is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxxxrv32um-p-mulh.rcf");
end architecture;
