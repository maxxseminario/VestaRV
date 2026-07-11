entity tb_rv32um_p_divu is end tb_rv32um_p_divu;
architecture behavioral of tb_rv32um_p_divu is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rca/xxxxxrv32um-p-divu.rcf");
end architecture;
